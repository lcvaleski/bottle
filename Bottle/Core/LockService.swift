import Foundation

/// Client for the Bottle lock service (site/api). The server holds the profile's
/// removal password and, while locked, this Mac's supervision identity.
struct LockService {
    static let baseURL = URL(string: "https://corephone.org")!

    struct LockStatus: Codable {
        let id: String
        var state: String            // locked | unlocking | released
        let delayHours: Double
        let createdAt: Double
        var unlockRequestedAt: Double?
        var unlockAt: Double?
        var releasedAt: Double?
        let hasIdentity: Bool
        let hasApprover: Bool
        var password: String?
        var identity: SupervisionIdentityStore.Exported?

        var unlockDate: Date? { unlockAt.map { Date(timeIntervalSince1970: $0 / 1000) } }
        var isReleased: Bool { state == "released" }
    }

    struct Created: Codable {
        let id: String
        let token: String
        let password: String
        let statusUrl: String
        let approverUrl: String?
    }

    enum ServiceError: LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self { case let .http(code, message): "Bottle service: \(message) (HTTP \(code))" }
        }
    }

    func create(delayHours: Double, mode: RestrictionMode, apps: [String], sites: [String], partner: Bool, organizationName: String) async throws -> Created {
        try await request("POST", "/api/locks", body: [
            "delayHours": delayHours, "mode": mode.rawValue, "apps": apps, "sites": sites,
            "partner": partner, "organizationName": organizationName,
        ])
    }

    func escrow(id: String, token: String, identity: SupervisionIdentityStore.Exported) async throws {
        struct OK: Codable { let ok: Bool }
        let _: OK = try await request("PUT", "/api/locks/\(id)/identity", token: token, body: [
            "certificate": identity.certificate, "privateKey": identity.privateKey, "organizationName": identity.organizationName,
        ])
    }

    func status(id: String, token: String, includeIdentity: Bool = false) async throws -> LockStatus {
        try await request("GET", "/api/locks/\(id)\(includeIdentity ? "?identity=1" : "")", token: token)
    }

    func requestUnlock(id: String, token: String) async throws -> LockStatus {
        try await request("POST", "/api/locks/\(id)/unlock", token: token)
    }

    func cancelUnlock(id: String, token: String) async throws -> LockStatus {
        try await request("POST", "/api/locks/\(id)/cancel", token: token)
    }

    private func request<T: Decodable>(_ method: String, _ path: String, token: String? = nil, body: [String: Any]? = nil) async throws -> T {
        var req = URLRequest(url: Self.baseURL.appendingPathComponent(path).absoluteURL)
        // appendingPathComponent escapes "?", so rebuild when there's a query.
        if path.contains("?") { req.url = URL(string: Self.baseURL.absoluteString + path) }
        req.httpMethod = method
        req.timeoutInterval = 30
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String ?? "request failed"
            throw ServiceError.http(code, message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// "5 minutes", "24 hours", "3 days".
func humanDelay(hours: Double) -> String {
    if hours < 1 { let m = Int((hours * 60).rounded()); return "\(m) minute\(m == 1 ? "" : "s")" }
    if hours.truncatingRemainder(dividingBy: 24) == 0 { let d = Int(hours / 24); return "\(d) day\(d == 1 ? "" : "s")" }
    let h = Int(hours); return "\(h) hour\(h == 1 ? "" : "s")"
}

/// What this Mac remembers about its active lock. Lives next to the (now absent) identity.
struct LockRecord: Codable {
    let id: String
    let token: String
    let statusURL: String
    let approverURL: String?
    let delayHours: Double
    let createdAt: Date
    let deviceUDID: String?
    let deviceName: String

    static let url = SupervisionIdentityStore.directory.deletingLastPathComponent().appendingPathComponent("lock.json")

    static func load() -> LockRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LockRecord.self, from: data)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: Self.url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.url.path)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
