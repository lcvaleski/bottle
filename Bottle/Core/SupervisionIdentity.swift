import Foundation
import Observation
import Security

/// The certificate + private key that identifies this Mac as the phone's
/// supervising organization. cfgutil wants both as DER files
/// (`--host-cert` at prepare time, `-C/-K` on every call afterwards).
///
/// Losing these files means losing the ability to manage the phone without
/// erasing it again, so they live in Application Support, not a temp dir.
struct SupervisionIdentity {
    let certificateURL: URL
    let privateKeyURL: URL
    let organizationName: String
}

/// A supervision identity Apple Configurator created and stored in the login keychain.
struct KeychainIdentity: Identifiable {
    let identity: SecIdentity
    let label: String
    let organizationName: String

    var id: String { label }
}

@MainActor
@Observable
final class SupervisionIdentityStore {
    static let directory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Bottle/SupervisionIdentity", isDirectory: true)
    }()

    private static let certificateURL = directory.appendingPathComponent("supervision-cert.der")
    private static let privateKeyURL = directory.appendingPathComponent("supervision-key.der")
    private static let organizationURL = directory.appendingPathComponent("organization.txt")
    private static let openssl = URL(fileURLWithPath: "/usr/bin/openssl")

    private(set) var identity: SupervisionIdentity?

    init() {
        identity = Self.load()
    }

    private static func load() -> SupervisionIdentity? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: certificateURL.path), fm.fileExists(atPath: privateKeyURL.path) else {
            return nil
        }
        let org = (try? String(contentsOf: organizationURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SupervisionIdentity(
            certificateURL: certificateURL,
            privateKeyURL: privateKeyURL,
            organizationName: org?.isEmpty == false ? org! : "Bottle"
        )
    }

    // MARK: - Generate

    /// Generates a self-signed identity with the system openssl. Ten-year validity;
    /// the phone only checks that the host presents the matching private key.
    func generate(organizationName: String, log: ActivityLog) async throws -> SupervisionIdentity {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)

        let keyPEM = Self.directory.appendingPathComponent("key.pem")
        let certPEM = Self.directory.appendingPathComponent("cert.pem")
        defer {
            try? fm.removeItem(at: keyPEM)
            try? fm.removeItem(at: certPEM)
        }

        // Slashes would break the -subj syntax.
        let safeOrg = organizationName.replacingOccurrences(of: "/", with: "-")
        let subject = "/CN=\(safeOrg) Supervision/O=\(safeOrg)"

        try await openssl([
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "3650",
            "-subj", subject, "-keyout", keyPEM.path, "-out", certPEM.path,
        ], log: log)
        try await openssl(["x509", "-in", certPEM.path, "-outform", "DER", "-out", Self.certificateURL.path], log: log)
        try await openssl(["rsa", "-in", keyPEM.path, "-outform", "DER", "-out", Self.privateKeyURL.path], log: log)

        return try finish(organizationName: organizationName, log: log, source: "Generated new supervision identity")
    }

    // MARK: - Import from Apple Configurator's keychain entry

    /// Identities Apple Configurator made (Settings → Organizations). Their labels look like
    /// "Apple Configurator: Acme Inc (UUID)".
    static func keychainIdentities() -> [KeychainIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchSubjectContains as String: "Apple Configurator:",
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [SecIdentity]
        else { return [] }

        return items.compactMap { identity in
            var cert: SecCertificate?
            SecIdentityCopyCertificate(identity, &cert)
            guard let cert, let label = SecCertificateCopySubjectSummary(cert) as String? else { return nil }
            return KeychainIdentity(identity: identity, label: label, organizationName: Self.organization(fromLabel: label))
        }
    }

    nonisolated static func organization(fromLabel label: String) -> String {
        var name = label
        if name.hasPrefix("Apple Configurator:") {
            name = String(name.dropFirst("Apple Configurator:".count))
        }
        // Drop the trailing " (UUID)".
        if let open = name.range(of: " (", options: .backwards), name.hasSuffix(")") {
            name = String(name[..<open.lowerBound])
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    func importFromKeychain(_ item: KeychainIdentity, log: ActivityLog) async throws -> SupervisionIdentity {
        // SecKeyCopyExternalRepresentation fails for legacy keychain keys, so go through PKCS#12.
        let passphrase = UUID().uuidString
        var params = SecItemImportExportKeyParameters()
        params.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        params.passphrase = Unmanaged.passRetained(passphrase as CFString)
        defer { params.passphrase?.release() }

        var exported: CFData?
        let status = SecItemExport(item.identity, .formatPKCS12, [], &params, &exported)
        guard status == errSecSuccess, let p12 = exported as Data? else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw IdentityError.importFailed("Keychain refused to export “\(item.label)”: \(reason)")
        }

        let fm = FileManager.default
        try fm.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let p12URL = Self.directory.appendingPathComponent("import.p12")
        try p12.write(to: p12URL, options: .completeFileProtection)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: p12URL.path)
        defer { try? fm.removeItem(at: p12URL) }

        try await extract(p12: p12URL, password: passphrase, log: log)
        return try finish(organizationName: item.organizationName, log: log, source: "Imported “\(item.label)” from the keychain")
    }

    // MARK: - Import a .p12 exported from Apple Configurator on another Mac

    func importP12(at url: URL, password: String, log: ActivityLog) async throws -> SupervisionIdentity {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try await extract(p12: url, password: password, log: log)

        var org = "Bottle"
        let subject = try await openssl(["x509", "-in", Self.certificateURL.path, "-inform", "DER", "-noout", "-subject", "-nameopt", "sep_multiline"], log: log)
        if let line = subject.split(whereSeparator: \.isNewline).map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { $0.hasPrefix("O=") }) {
            org = String(line.dropFirst(2))
        }
        return try finish(organizationName: org, log: log, source: "Imported \(url.lastPathComponent)")
    }

    // MARK: - Escrow support (paid tier)

    struct Exported: Codable {
        let certificate: String   // base64 DER
        let privateKey: String    // base64 DER
        let organizationName: String
    }

    func export() throws -> Exported {
        guard let identity else { throw IdentityError.importFailed("no identity to export") }
        return Exported(
            certificate: try Data(contentsOf: identity.certificateURL).base64EncodedString(),
            privateKey: try Data(contentsOf: identity.privateKeyURL).base64EncodedString(),
            organizationName: identity.organizationName
        )
    }

    func importExported(_ exported: Exported, log: ActivityLog) throws -> SupervisionIdentity {
        guard let cert = Data(base64Encoded: exported.certificate), let key = Data(base64Encoded: exported.privateKey),
              !cert.isEmpty, !key.isEmpty else {
            throw IdentityError.importFailed("escrowed identity is not valid base64")
        }
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try cert.write(to: Self.certificateURL)
        try key.write(to: Self.privateKeyURL)
        return try finish(organizationName: exported.organizationName, log: log, source: "Restored identity from escrow")
    }

    /// Removes the identity from this Mac. Only ever called after the server confirmed it holds a copy.
    func deleteLocal(log: ActivityLog) throws {
        let fm = FileManager.default
        for url in [Self.certificateURL, Self.privateKeyURL, Self.organizationURL] where fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        identity = nil
        log.info("Deleted local supervision identity (escrowed)")
    }

    // MARK: - Helpers

    private func extract(p12: URL, password: String, log: ActivityLog) async throws {
        let fm = FileManager.default
        let keyPEM = Self.directory.appendingPathComponent("key.pem")
        let certPEM = Self.directory.appendingPathComponent("cert.pem")
        defer {
            try? fm.removeItem(at: keyPEM)
            try? fm.removeItem(at: certPEM)
        }
        // Password goes through the environment so it never shows up in `ps`.
        let env = ["BOTTLE_P12_PASSWORD": password]
        try await openssl(["pkcs12", "-in", p12.path, "-passin", "env:BOTTLE_P12_PASSWORD", "-clcerts", "-nokeys", "-out", certPEM.path], environment: env, log: log)
        try await openssl(["pkcs12", "-in", p12.path, "-passin", "env:BOTTLE_P12_PASSWORD", "-nocerts", "-nodes", "-out", keyPEM.path], environment: env, log: log)
        try await openssl(["x509", "-in", certPEM.path, "-outform", "DER", "-out", Self.certificateURL.path], log: log)
        try await openssl(["rsa", "-in", keyPEM.path, "-outform", "DER", "-out", Self.privateKeyURL.path], log: log)
    }

    private func finish(organizationName: String, log: ActivityLog, source: String) throws -> SupervisionIdentity {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.privateKeyURL.path)
        try organizationName.write(to: Self.organizationURL, atomically: true, encoding: .utf8)
        guard let loaded = Self.load() else {
            throw IdentityError.importFailed("openssl finished but the DER files are missing")
        }
        identity = loaded
        log.info("\(source) → \(Self.directory.path)")
        return loaded
    }

    @discardableResult
    private func openssl(_ args: [String], environment: [String: String]? = nil, log: ActivityLog) async throws -> String {
        log.command("openssl " + args.joined(separator: " "))
        let output = try await ProcessRunner.run(Self.openssl, arguments: args, environment: environment) { stream, line in
            Task { @MainActor in log.append(stream == .stdout ? .stdout : .stderr, line) }
        }
        guard output.status == 0 else {
            throw IdentityError.importFailed(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return output.stdout
    }

    enum IdentityError: LocalizedError {
        case importFailed(String)

        var errorDescription: String? {
            switch self {
            case let .importFailed(detail): "Supervision identity problem: \(detail)"
            }
        }
    }
}
