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
        var step=sqlite3_step(stmt)
        while step == SQLITE_ROW {
            let source = text(2), originator = text(6)
            let label = originator.lowercased().contains("desktop") ? "Desktop" : (["cli","exec"].contains(source) ? "CLI" : "Desktop")
            agents.append(AgentRecord(id:text(0), title:text(1).isEmpty ? "Codex-Session" : text(1), source:label,
                rolloutPath:text(3), updatedAt:Date(timeIntervalSince1970:sqlite3_column_double(stmt,4)), cwd:text(5)))
            step=sqlite3_step(stmt)
        }
        guard step == SQLITE_DONE else { throw MonitorError.invalid("Codex-Sessiondaten sind vorübergehend nicht lesbar") }
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
    public static func completedToolIDs(path:String,matching:Set<String>) -> Set<String> {
        guard !matching.isEmpty,let handle=FileHandle(forReadingAtPath:path) else { return [] }
        defer { try? handle.close() }
        var buffer=Data(),found=Set<String>()
        while let chunk=try? handle.read(upToCount:65536),!chunk.isEmpty {
            buffer.append(chunk)
            while let newline=buffer.firstIndex(of:10) {
                let line=Data(buffer[..<newline]);buffer=Data(buffer.dropFirst(buffer.distance(from:buffer.startIndex,to:newline)+1))
                guard let json=try? JSONDecoder().decode(JSONValue.self,from:line),json["type"].string == "response_item",["function_call_output","custom_tool_call_output"].contains(json["payload"]["type"].string ?? ""),let id=json["payload"]["call_id"].string,matching.contains(id) else { continue }
                found.insert(id)
                if found == matching { return found }
            }
            // Bound a malformed or exceptionally large single line without interpreting it.
            if buffer.count > 16*1024*1024 { buffer.removeAll() }
        }
        return found
    }
    public static func completedToolIDs(from data: Data) -> Set<String> {
        var ids=Set<String>()
        for line in data.split(separator:10,omittingEmptySubsequences:false).dropLast() {
            guard let json=try? JSONDecoder().decode(JSONValue.self,from:Data(line)), json["type"].string == "response_item", ["function_call_output","custom_tool_call_output"].contains(json["payload"]["type"].string ?? ""), let id=json["payload"]["call_id"].string else { continue }
            ids.insert(id)
        }
        return ids
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
