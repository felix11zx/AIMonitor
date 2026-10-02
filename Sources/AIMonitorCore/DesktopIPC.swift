import Foundation
import Darwin

public enum DesktopEvent {
    case connected
    case status(String, AgentStatus)
    case disconnected(String)
}

public final class DesktopIPC {
    private let lock=NSLock()
    private let queue=DispatchQueue(label:"com.aimonitor.desktop-ipc",qos:.utility)
    private var desired=Set<String>()
    private var stopping=false
    private var started=false
    public init() {}
    public func observe(home: URL, ids: [String], onEvent: @escaping (DesktopEvent)->Void) {
        lock.lock();desired=Set(ids)
        if started { lock.unlock();return }
        stopping=false;started=true;lock.unlock()
        queue.async { [weak self] in self?.run(home:home,onEvent:onEvent) }
    }
    public func update(ids: [String]) { lock.lock();desired=Set(ids);lock.unlock() }
    public func stop() { lock.lock();stopping=true;lock.unlock() }
    private func settings() -> (Bool,Set<String>) { lock.lock();defer{lock.unlock()};return(stopping,desired) }
    private func run(home: URL,onEvent: @escaping (DesktopEvent)->Void) {
        defer { lock.lock();started=false;lock.unlock() }
        while !settings().0 {
            var fd:Int32 = -1
            do {
                fd=try Self.connect(path:home.appendingPathComponent("ipc/ipc.sock").path)
                var client="initializing-client",states:[String:DesktopState]=[:],subscribed=Set<String>(),frames=FrameBuffer()
                var initialized=false;let deadline=Date().addingTimeInterval(5)
                try Self.write(.object(["type":.string("request"),"requestId":.string(UUID().uuidString),"sourceClientId":.string(client),"version":.number(0),"method":.string("initialize"),"params":.object(["clientType":.string("aimonitor")])]),fd:fd)
                func follow(_ id: String,_ following:Bool) throws {
                    try Self.write(.object(["type":.string("broadcast"),"sourceClientId":.string(client),"version":.number(1),"method":.string("thread-stream-following-changed"),"params":.object(["conversationId":.string(id),"hostId":.string("local"),"following":.bool(following)])]),fd:fd)
                }
                while !settings().0 {
                    if !initialized,Date() > deadline { throw MonitorError.invalid("Desktop-Verbindung antwortet nicht") }
                    if initialized {
                        let ids=settings().1
                        for id in ids.subtracting(subscribed) { try follow(id,true);subscribed.insert(id) }
                        for id in subscribed.subtracting(ids) { try follow(id,false);subscribed.remove(id);states.removeValue(forKey:id) }
                    }
                    var poller=pollfd(fd:fd,events:Int16(POLLIN),revents:0)
                    guard poll(&poller,1,250) > 0 else { continue }
                    var chunk=[UInt8](repeating:0,count:65536)
                    let count=Darwin.read(fd,&chunk,chunk.count)
                    guard count > 0 else { throw MonitorError.invalid("Desktop ist nicht verbunden") }
                    for message in try frames.append(Data(chunk.prefix(count))) {
                        let method=message["method"].string
                        if message["type"].string == "response",method == "initialize",let id=message["result"]["clientId"].string {
                            client=id;initialized=true;onEvent(.connected)
                        } else if message["type"].string == "client-discovery-request" {
                            try Self.write(.object(["type":.string("client-discovery-response"),"requestId":message["requestId"],"response":.object(["canHandle":.bool(false)])]),fd:fd)
                        } else if method == "thread-stream-state-changed",message["params"]["hostId"].string == "local",let id=message["params"]["conversationId"].string,subscribed.contains(id) {
                            guard message["version"].number == 11 else { throw MonitorError.invalid("Diese Codex-Desktop-Version benötigt eine aktualisierte AIMonitor-Anbindung") }
                            var state=states[id] ?? DesktopState()
                            do { try state.apply(message["params"]["change"]);states[id]=state;onEvent(.status(id,state.status)) }
                            catch { states.removeValue(forKey:id);onEvent(.status(id,.unknown));try follow(id,false);try follow(id,true) }
                        } else if method == "client-status-changed",message["params"]["status"].string == "disconnected" {
                            // Any owner's exit invalidates cached runtime state until fresh snapshots arrive.
                            for id in subscribed { onEvent(.status(id,.unknown));states.removeValue(forKey:id);try follow(id,false);try follow(id,true) }
                        }
                    }
                }
                for id in subscribed { try? follow(id,false) }
            } catch { if !settings().0 { onEvent(.disconnected(error.localizedDescription)) } }
            if fd >= 0 { Darwin.close(fd) }
            for _ in 0..<12 { if settings().0 { break };Thread.sleep(forTimeInterval:0.25) }
        }
    }
    private static func connect(path: String) throws -> Int32 {
        var info=stat()
        guard lstat(path,&info) == 0,(info.st_mode & S_IFMT) == S_IFSOCK,info.st_uid == getuid(),info.st_mode & 0o077 == 0 else { throw MonitorError.invalid("Codex Desktop ist nicht geöffnet oder sein Socket ist nicht verfügbar") }
        var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX)
        let bytes=Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue:address.sun_path) else { throw MonitorError.invalid("Codex-Socketpfad ist zu lang") }
        withUnsafeMutableBytes(of:&address.sun_path) { raw in raw.copyBytes(from:bytes.map { UInt8(bitPattern:$0) }) }
        let fd=socket(AF_UNIX,SOCK_STREAM,0)
        guard fd >= 0 else { throw MonitorError.invalid("Desktop-Socket konnte nicht geöffnet werden") }
        var yes:Int32=1;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,socklen_t(MemoryLayout.size(ofValue:yes)))
        let result=withUnsafePointer(to:&address) { pointer in pointer.withMemoryRebound(to:sockaddr.self,capacity:1) { Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { Darwin.close(fd);throw MonitorError.invalid("Codex Desktop ist nicht verbunden") }
        return fd
    }
    private static func write(_ message: JSONValue,fd:Int32) throws {
        let frame=try FrameBuffer.encode(message)
        try frame.withUnsafeBytes { raw in
            var offset=0
            while offset < raw.count {
                let count=Darwin.write(fd,raw.baseAddress!.advanced(by:offset),raw.count-offset)
                if count < 0,errno == EINTR { continue }
                guard count > 0 else { throw MonitorError.invalid("Desktop-Verbindung wurde beendet") };offset+=count
            }
        }
    }
}
