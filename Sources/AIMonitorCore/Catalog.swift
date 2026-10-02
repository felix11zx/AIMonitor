import Foundation
import SQLite3

public enum Catalog {
    public static func read(home: URL, limit: Int = 60) throws -> [AgentRecord] {
        let candidates = (try FileManager.default.contentsOfDirectory(at: home, includingPropertiesForKeys: nil))
            .filter { $0.lastPathComponent.hasPrefix("state_") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
        guard let path = candidates.first else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { if let db { sqlite3_close(db) }; throw MonitorError.invalid("Codex-Sessiondaten können nicht gelesen werden") }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 300)
        var stmt: OpaquePointer?
        let modern = "SELECT id, COALESCE(NULLIF(name,''),title), source, rollout_path, updated_at, cwd, originator FROM threads WHERE archived=0 AND source NOT LIKE '{%' ORDER BY updated_at DESC LIMIT ?"
        let legacy = "SELECT id, title, source, rollout_path, updated_at, cwd, '' FROM threads WHERE archived=0 AND source NOT LIKE '{%' ORDER BY updated_at DESC LIMIT ?"
        if sqlite3_prepare_v2(db, modern, -1, &stmt, nil) != SQLITE_OK {
            if let stmt { sqlite3_finalize(stmt) }; stmt=nil
            guard sqlite3_prepare_v2(db, legacy, -1, &stmt, nil) == SQLITE_OK else { throw MonitorError.invalid("Codex-Sessionformat wird nicht unterstützt") }
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        func text(_ index: Int32) -> String { sqlite3_column_text(stmt,index).map { String(cString: $0) } ?? "" }
        var agents: [AgentRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let source = text(2), originator = text(6)
            let label = originator.lowercased().contains("desktop") ? "Desktop" : (["cli","exec"].contains(source) ? "CLI" : "Desktop")
            agents.append(AgentRecord(id:text(0), title:text(1).isEmpty ? "Codex-Session" : text(1), source:label,
                rolloutPath:text(3), updatedAt:Date(timeIntervalSince1970:sqlite3_column_double(stmt,4)), cwd:text(5)))
        }
        return agents
    }
}

public enum SessionTail {
    public static func read(path: String) -> Data? {
        guard let handle = FileHandle(forReadingAtPath:path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > 256*1024 ? size - 256*1024 : 0)
        return try? handle.readToEnd()
    }
    public static func status(from data: Data) -> AgentStatus {
        var status: AgentStatus = .unknown
        // Only complete lines: a concurrent writer can leave its last record partial.
        let lines = data.split(separator:10,omittingEmptySubsequences:false).dropLast()
        for line in lines {
            guard let json = try? JSONDecoder().decode(JSONValue.self,from:Data(line)) else { continue }
            if json["type"].string == "event_msg" {
                switch json["payload"]["type"].string {
                case "task_started": status = .working
                case "task_complete", "turn_aborted": status = .idle
                default: break
                }
            }
        }
        return status
    }
}
