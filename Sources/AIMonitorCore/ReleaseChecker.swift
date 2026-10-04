import Foundation

/// Stable release versions use major.minor.patch, optionally prefixed with v.
public struct ReleaseVersion: Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]) else { return nil }
        self.major = major; self.minor = minor; self.patch = patch
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct GitHubRelease: Decodable, Sendable {
    public let tag: String
    public let draft: Bool
    public let prerelease: Bool

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name", draft, prerelease
    }
}

public enum ReleaseCheckResult: Equatable, Sendable {
    case upToDate
    case available(version: String, url: URL)
    case noRelease
}

public enum ReleaseCheckError: LocalizedError {
    case invalidResponse, invalidVersion, rateLimited, http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: return "GitHub hat keine gültige Release-Antwort geliefert."
        case .invalidVersion: return "Die Versionsnummer konnte nicht verglichen werden."
        case .rateLimited: return "GitHub begrenzt gerade die Anfragen. Bitte später erneut versuchen."
        case .http(let code): return "GitHub ist gerade nicht erreichbar (HTTP \(code))."
        }
    }
}

public struct ReleaseChecker: Sendable {
    public static let repositoryURL = URL(string: "https://github.com/felix11zx/AIMonitor")!
    public static let latestReleaseURL = repositoryURL.appendingPathComponent("releases/latest")
    public static let endpoint = URL(string: "https://api.github.com/repos/felix11zx/AIMonitor/releases/latest")!

    public init() {}

    public func check(currentVersion: String, session: URLSession = .shared) async throws -> ReleaseCheckResult {
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AIMonitor/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ReleaseCheckError.invalidResponse }
        switch response.statusCode {
        case 404: return .noRelease
        case 403, 429: throw ReleaseCheckError.rateLimited
        case 200: break
        default: throw ReleaseCheckError.http(response.statusCode)
        }
        let release: GitHubRelease
        do { release = try JSONDecoder().decode(GitHubRelease.self, from: data) }
        catch { throw ReleaseCheckError.invalidResponse }
        return try Self.evaluate(release, currentVersion: currentVersion)
    }

    public static func evaluate(_ release: GitHubRelease, currentVersion: String) throws -> ReleaseCheckResult {
        guard !release.draft, !release.prerelease else { return .noRelease }
        guard let current = ReleaseVersion(currentVersion), let latest = ReleaseVersion(release.tag) else {
            throw ReleaseCheckError.invalidVersion
        }
        guard latest > current else { return .upToDate }
        // Construct the link from our repository rather than trusting a URL in the response.
        return .available(version: release.tag, url: repositoryURL.appendingPathComponent("releases/tag").appendingPathComponent(release.tag))
    }
}
