import Foundation

/// A configuration profile installed on the phone. cfgutil only reports
/// identifier/name/version; the payload is recovered by finding the original
/// `.mobileconfig` on this Mac and reading it.
struct InstalledProfile: Identifiable, Hashable {
    let identifier: String
    let displayName: String
    var sourceURL: URL?
    var restrictions: AppRestrictions?

    var id: String { identifier }
    var isCable: Bool {
        identifier == RestrictionsProfile.identifier || RestrictionsProfile.legacyIdentifiers.contains(identifier)
    }
}

struct AppRestrictions: Hashable {
    let mode: RestrictionMode
    let bundleIDs: [String]
}

enum ProfileLibrary {
    /// Every readable `.mobileconfig` on the Mac, keyed by PayloadIdentifier.
    /// Uses Spotlight, then falls back to scanning the usual folders.
    static func localProfiles() async -> [String: (url: URL, restrictions: AppRestrictions?)] {
        var urls = await spotlightProfiles()
        if urls.isEmpty {
            urls = scanCommonFolders()
        }

        var result: [String: (url: URL, restrictions: AppRestrictions?)] = [:]
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let identifier = plist["PayloadIdentifier"] as? String
            else { continue }   // signed (CMS-wrapped) profiles don't parse as plists; skipped for now
            // Prefer the most recently modified copy when identifiers collide.
            if let existing = result[identifier], modificationDate(existing.url) >= modificationDate(url) { continue }
            result[identifier] = (url, restrictions(in: plist))
        }
        return result
    }

    static func restrictions(in profile: [String: Any]) -> AppRestrictions? {
        guard let payloads = profile["PayloadContent"] as? [[String: Any]] else { return nil }
        for payload in payloads where payload["PayloadType"] as? String == "com.apple.applicationaccess" {
            for key in ["blockedAppBundleIDs", "blacklistedAppBundleIDs"] {
                if let ids = payload[key] as? [String] { return AppRestrictions(mode: .block, bundleIDs: ids) }
            }
            for key in ["allowListedAppBundleIDs", "whitelistedAppBundleIDs"] {
                if let ids = payload[key] as? [String] { return AppRestrictions(mode: .allow, bundleIDs: ids) }
            }
        }
        return nil
    }

    private static func spotlightProfiles() async -> [URL] {
        guard let output = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/mdfind"),
            arguments: ["kMDItemFSName == '*.mobileconfig'c"]
        ), output.status == 0 else { return [] }
        return output.stdout
            .split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)) }
            .filter { !$0.path.hasPrefix("/System/") && !$0.path.hasPrefix("/Library/Developer/") }
    }

    private static func scanCommonFolders() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var found: [URL] = []
        for folder in ["Downloads", "Desktop", "Documents"] {
            let root = home.appendingPathComponent(folder)
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in enumerator {
                if enumerator.level > 3 { enumerator.skipDescendants(); continue }
                if url.pathExtension == "mobileconfig" { found.append(url) }
            }
        }
        return found
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}
