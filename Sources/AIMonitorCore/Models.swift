import Foundation

public enum AgentStatus: String, Codable, Sendable {
    case idle, working, needsInput, unknown
    public var label: String {
        switch self { case .idle: return "Inaktiv"; case .working: return "Arbeitet"; case .needsInput: return "Eingabe nötig"; case .unknown: return "Status unbekannt" }
    }
    public static func aggregate(_ statuses: [Self]) -> Self {
        if statuses.contains(.needsInput) { return .needsInput }
        if statuses.contains(.working) { return .working }
        if statuses.contains(.unknown) { return .unknown }
        return .idle
    }
}

public struct UsageWindow: Identifiable, Sendable {
    public let id: String
    public let bucket: String
    public let usedPercent: Double?
    public let durationMinutes: Double?
    public let resetAt: Date?
    public var remainingPercent: Double? { usedPercent.map { 100 - $0 } }
    public var period: String {
        guard let minutes = durationMinutes, minutes.isFinite, minutes > 0, minutes < Double(Int.max) else { return "Zeitraum unbekannt" }
        if minutes == 10080 { return "Wöchentlich" }
        if minutes.truncatingRemainder(dividingBy: 1440) == 0 { return "\(Int(minutes / 1440)) Tage" }
        if minutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(Int(minutes / 60)) Stunden" }
        return "\(Int(minutes)) Minuten"
    }
}

public struct UsageSnapshot: Sendable {
    public let windows: [UsageWindow]
    public static func decode(_ json: JSONValue) -> Self {
        let buckets = json["rateLimitsByLimitId"].object ?? [json["rateLimits"]["limitId"].string ?? "codex": json["rateLimits"]]
        var result: [UsageWindow] = []
        for key in buckets.keys.sorted() {
            guard let bucket = buckets[key] else { continue }
            for kind in ["primary", "secondary"] {
                let window = bucket[kind]
                guard window.object != nil else { continue }
                result.append(UsageWindow(id: key + "." + kind, bucket: bucket["limitName"].string ?? key,
                    usedPercent: window["usedPercent"].number.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil },
                    durationMinutes: window["windowDurationMins"].number.flatMap { $0.isFinite && $0 > 0 && $0 < Double(Int.max) ? $0 : nil },
                    resetAt: window["resetsAt"].number.flatMap { $0.isFinite && $0 >= -62135596800 && $0 < 253402300800 ? Date(timeIntervalSince1970: $0) : nil }))
            }
        }
        return Self(windows: result)
    }
}

public struct AgentRecord: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let source: String
    public let rolloutPath: String
    public let updatedAt: Date
    public let cwd: String
    public init(id: String, title: String, source: String, rolloutPath: String, updatedAt: Date, cwd: String) {
        self.id=id; self.title=title; self.source=source; self.rolloutPath=rolloutPath; self.updatedAt=updatedAt; self.cwd=cwd
    }
}
