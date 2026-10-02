import Foundation

public enum MonitorError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { object?[key] ?? .null }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var array: [JSONValue]? { if case .array(let v) = self { return v }; return nil }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public static func parse(_ text: String) throws -> JSONValue { try JSONDecoder().decode(Self.self, from: Data(text.utf8)) }
    public func data() throws -> Data { try JSONEncoder().encode(self) }

    public mutating func patch(path: [JSONValue], operation: String, value: JSONValue) throws {
        guard let first = path.first else {
            guard operation != "remove" else { throw MonitorError.invalid("Ungültiger Snapshot-Patch") }
            self = value; return
        }
        let tail = Array(path.dropFirst())
        switch self {
        case .object(var obj):
            guard let key = first.string else { throw MonitorError.invalid("Ungültiger Objekt-Patch") }
            if tail.isEmpty {
                if operation == "remove" { guard obj.removeValue(forKey: key) != nil else { throw MonitorError.invalid("Patch-Ziel fehlt") } }
                else { if operation == "replace", obj[key] == nil { throw MonitorError.invalid("Patch-Ziel fehlt") }; obj[key] = value }
            } else {
                guard var child = obj[key] else { throw MonitorError.invalid("Patch-Ziel fehlt") }
                try child.patch(path: tail, operation: operation, value: value); obj[key] = child
            }
            self = .object(obj)
        case .array(var arr):
            let index = first.number.map(Int.init) ?? first.string.flatMap(Int.init)
            guard let i = index, i >= 0 else { throw MonitorError.invalid("Ungültiger Array-Patch") }
            if tail.isEmpty, operation == "add" { guard i <= arr.count else { throw MonitorError.invalid("Patch-Index fehlt") }; arr.insert(value, at: i) }
            else {
                guard i < arr.count else { throw MonitorError.invalid("Patch-Index fehlt") }
                if tail.isEmpty { if operation == "remove" { arr.remove(at: i) } else { arr[i] = value } }
                else { try arr[i].patch(path: tail, operation: operation, value: value) }
            }
            self = .array(arr)
        default: throw MonitorError.invalid("Ungültiger Snapshot-Patch")
        }
    }
}

public struct FrameBuffer {
    private var buffer = Data()
    public init() {}
    public static let maximumSize = 16 * 1024 * 1024
    public static func encode(_ json: JSONValue) throws -> Data {
        let body = try json.data()
        guard !body.isEmpty, body.count <= maximumSize else { throw MonitorError.invalid("IPC-Nachricht zu groß") }
        var length = UInt32(body.count).littleEndian
        var data = withUnsafeBytes(of: &length) { Data($0) }; data.append(body); return data
    }
    public mutating func append(_ data: Data) throws -> [JSONValue] {
        buffer.append(data); var frames: [JSONValue] = []
        while buffer.count >= 4 {
            let bytes = Array(buffer.prefix(4))
            let size = Int(UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
            guard size > 0, size <= Self.maximumSize else { buffer.removeAll(); throw MonitorError.invalid("Ungültige IPC-Framegröße") }
            guard buffer.count >= 4 + size else { break }
            frames.append(try JSONDecoder().decode(JSONValue.self, from: buffer.subdata(in: 4..<(4+size))))
            buffer = Data(buffer.dropFirst(4 + size))
        }
        return frames
    }
}
