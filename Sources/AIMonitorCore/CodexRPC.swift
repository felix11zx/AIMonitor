import Foundation
import Darwin

public actor CodexRPC {
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer=Data()
    private var configuration=""
    private var nextID=1
    public init() {}

    public func readLimits(executable: String, home: URL) throws -> UsageSnapshot {
        do {
            let config=executable+home.path
            if process?.isRunning != true || config != configuration {
                shutdown(); configuration=config
                let child=Process(), stdin=Pipe(), stdout=Pipe(), stderr=Pipe()
                child.executableURL=URL(fileURLWithPath:executable)
                child.arguments=["app-server","--listen","stdio://"]
                var environment=ProcessInfo.processInfo.environment
                environment["CODEX_HOME"]=home.path
                environment["PATH"]="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:"+(environment["PATH"] ?? "")
                child.environment=environment
                child.standardInput=stdin;child.standardOutput=stdout;child.standardError=stderr
                stderr.fileHandleForReading.readabilityHandler={ handle in _ = handle.availableData }
                try child.run();process=child;input=stdin.fileHandleForWriting;output=stdout.fileHandleForReading
                let id=nextID;nextID+=1
                try send(.object(["id":.number(Double(id)),"method":.string("initialize"),"params":.object(["clientInfo":.object(["name":.string("aimonitor"),"title":.string("AIMonitor"),"version":.string("0.1.0")])])]))
                _ = try response(id:id)
                try send(.object(["method":.string("initialized")]))
            }
            let id=nextID;nextID+=1
            try send(.object(["id":.number(Double(id)),"method":.string("account/rateLimits/read")]))
            return UsageSnapshot.decode(try response(id:id))
        } catch {
            shutdown()
            if let error=error as? MonitorError { throw error }
            throw MonitorError.invalid("Codex konnte nicht gestartet werden. Bitte Pfad und Anmeldung prüfen.")
        }
    }
    private func send(_ json: JSONValue) throws {
        guard let input else { throw MonitorError.invalid("Codex ist nicht verbunden") }
        var data=try json.data();data.append(10);try input.write(contentsOf:data)
    }
    private func response(id: Int) throws -> JSONValue {
        let deadline=Date().addingTimeInterval(20)
        while Date() < deadline {
            if let newline=buffer.firstIndex(of:10) {
                let line=Data(buffer[..<newline]);buffer=Data(buffer.dropFirst(buffer.distance(from:buffer.startIndex,to:newline)+1))
                guard let message=try? JSONDecoder().decode(JSONValue.self,from:line),message["id"].number == Double(id) else { continue }
                if message["error"].object != nil {
                    let message=message["error"]["message"].string?.lowercased() ?? ""
                    throw MonitorError.invalid(message.contains("auth") || message.contains("login") || message.contains("sign") ? "Codex-Anmeldung fehlt oder ist abgelaufen. Bitte in Codex anmelden." : "Codex-Limits sind derzeit nicht verfügbar.")
                }
                return message["result"]
            }
            guard let output,process?.isRunning == true else { throw MonitorError.invalid("Die Codex-Verbindung wurde beendet") }
            var poller=pollfd(fd:output.fileDescriptor,events:Int16(POLLIN),revents:0)
            if poll(&poller,1,250) > 0 {
                var chunk=[UInt8](repeating:0,count:65536)
                let count=Darwin.read(output.fileDescriptor,&chunk,chunk.count)
                guard count > 0 else { throw MonitorError.invalid("Die Codex-Verbindung wurde beendet") }
                buffer.append(contentsOf:chunk.prefix(count))
                guard buffer.count < 16*1024*1024 else { throw MonitorError.invalid("Codex-Antwort ist zu groß") }
            }
        }
        throw MonitorError.invalid("Codex antwortet nicht. Die Verbindung wird erneut versucht.")
    }
    public func shutdown() {
        try? input?.close();input=nil;try? output?.close();output=nil;buffer.removeAll()
        if process?.isRunning == true { process?.terminate() };process=nil
    }
}
