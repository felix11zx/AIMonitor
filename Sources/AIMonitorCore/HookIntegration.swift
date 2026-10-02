import Foundation
import CryptoKit
import Darwin

public enum HookRecorder {
    public static var defaultDirectory: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AIMonitor/events", isDirectory:true) }
    public static func event(from json: JSONValue, timestamp: Double = Date().timeIntervalSince1970) throws -> HookEvent {
        guard let session = json["session_id"].string, !session.isEmpty, let kind = json["hook_event_name"].string else { throw MonitorError.invalid("Hook-Metadaten fehlen") }
        var input = json["tool_input"].object ?? [:]; input.removeValue(forKey:"description")
        let encoder=JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(JSONValue.object(input))).map { String(format:"%02x",$0) }.joined()
        let name=json["tool_name"].string
        let key=name.map { $0 + ":" + digest }
        return HookEvent(sessionID:session, turnID:json["turn_id"].string, kind:kind, toolID:key, toolName:name, timestamp:timestamp, processID:codexAncestor())
    }
    public static func codexAncestor() -> Int32? {
        var pid=getppid()
        for _ in 0..<12 {
            var info=proc_bsdinfo()
            let count=proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,Int32(MemoryLayout<proc_bsdinfo>.size))
            guard count > 0 else { break }
            let name=withUnsafeBytes(of:&info.pbi_comm) { raw in String(cString:raw.baseAddress!.assumingMemoryBound(to:CChar.self)) }
            if name == "codex" { return pid }
            guard info.pbi_ppid > 1 else { break }; pid=Int32(info.pbi_ppid)
        }
        return nil
    }
    public static func record(_ data: Data, directory: URL = defaultDirectory) throws {
        guard data.count < 2*1024*1024 else { return }
        let event=try event(from:JSONDecoder().decode(JSONValue.self,from:data))
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let path=directory.appendingPathComponent(String(format:"%.6f",event.timestamp)+"-"+UUID().uuidString+".json")
        try JSONEncoder().encode(event).write(to:path,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
    }
    public static func read(directory: URL = defaultDirectory) -> [HookEvent] {
        guard let files=try? FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }.suffix(2000).compactMap {
            guard let data=try? Data(contentsOf:$0) else { return nil }; return try? JSONDecoder().decode(HookEvent.self,from:data)
        }
    }
}

public enum HookInstaller {
    private static let marker="AIMonitor status observer"
    public static let events=["SessionStart","SessionEnd","UserPromptSubmit","Stop","Interrupt","PermissionRequest","PreToolUse","PostToolUse"]
    public static func isEnabled(home: URL) -> Bool {
        guard let data=try? Data(contentsOf:home.appendingPathComponent("hooks.json")),let json=try? JSONDecoder().decode(JSONValue.self,from:data) else { return false }
        return (json["hooks"]["UserPromptSubmit"].array ?? []).contains { $0["hooks"].array?.contains { $0["statusMessage"].string == marker } == true }
    }
    public static func setEnabled(_ enabled: Bool, home: URL, executable: String) throws {
        let fm=FileManager.default, file=home.appendingPathComponent("hooks.json")
        guard fm.fileExists(atPath:home.path) else { throw MonitorError.invalid("Codex-Verzeichnis existiert nicht") }
        let original=try? Data(contentsOf:file)
        var root: [String:JSONValue]
        if let original {
            guard let obj=try JSONDecoder().decode(JSONValue.self,from:original).object else { throw MonitorError.invalid("Vorhandene hooks.json ist ungültig") }; root=obj
        } else { root=[:] }
        if root["hooks"] != nil, root["hooks"]?.object == nil { throw MonitorError.invalid("Vorhandene Hook-Konfiguration ist ungültig") }
        var hooks=root["hooks"]?.object ?? [:]
        let backup=home.appendingPathComponent("hooks.json.aimonitor-backup")
        if let original, !fm.fileExists(atPath:backup.path) { try original.write(to:backup,options:.atomic) }
        let quote="'"+executable.replacingOccurrences(of:"'",with:"'\\''")+"'"
        for kind in events {
            var groups=hooks[kind]?.array ?? []
            groups=groups.compactMap { group in
                guard var obj=group.object, let entries=obj["hooks"]?.array else { return group }
                let remaining=entries.filter { $0["statusMessage"].string != marker }
                if remaining.isEmpty { return nil }; obj["hooks"] = .array(remaining); return .object(obj)
            }
            if enabled {
                let handler:JSONValue = .object(["type":.string("command"),"command":.string(quote+" --record-hook"),"timeout":.number(2),"statusMessage":.string(marker)])
                groups.append(.object(["hooks":.array([handler])]))
            }
            if groups.isEmpty { hooks.removeValue(forKey:kind) } else { hooks[kind] = .array(groups) }
        }
        root["hooks"] = .object(hooks)
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        try encoder.encode(JSONValue.object(root)).write(to:file,options:.atomic)
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
    }
}
