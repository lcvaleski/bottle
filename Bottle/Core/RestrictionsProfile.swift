import Foundation

enum RestrictionMode: String, CaseIterable, Identifiable {
    case block
    case allow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .block: "Block selected apps"
        case .allow: "Allow only selected apps"
        }
    }

    var explanation: String {
        switch self {
        case .block: "Checked apps are hidden from the Home Screen and cannot be opened."
        case .allow: "Only checked apps stay visible. Phone, Settings, and other system essentials are always allowed."
        }
    }
}

/// Builds the `com.apple.applicationaccess` configuration profile that hides or
/// allow-lists apps. Both keys require a supervised device.
enum RestrictionsProfile {
    static let identifier = "com.coventrylabs.bottle.app-restrictions"
    /// Identifiers earlier builds used. Treated as Bottle's own and replaced on the next Apply.
    static let legacyIdentifiers: Set<String> = ["com.bottle.app-restrictions"]

    /// - Parameters:
    ///   - sites: Hostnames to block in Safari and in-app browsers (web content filter payload).
    ///   - lockedOnPhone: When true, iOS refuses to remove the profile from Settings → VPN & Device
    ///     Management; only the supervising Mac can remove it. Supervised devices honour this.
    ///   - removalPassword: When set, the profile is removable from Settings *only* with this
    ///     password (`lockedOnPhone` is ignored). This is the paid tier's door.
    static func data(
        mode: RestrictionMode,
        bundleIDs: [String],
        sites: [String] = [],
        organizationName: String,
        lockedOnPhone: Bool = true,
        removalPassword: String? = nil
    ) throws -> Data {
        let key = mode == .block ? "blockedAppBundleIDs" : "allowListedAppBundleIDs"
        var payloads: [[String: Any]] = [[
            "PayloadType": "com.apple.applicationaccess",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier + ".applicationaccess",
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "App Restrictions",
            key: bundleIDs.sorted(),
        ]]

        let urls = denyListURLs(for: sites)
        if !urls.isEmpty {
            payloads.append([
                "PayloadType": "com.apple.webcontent-filter",
                "PayloadVersion": 1,
                "PayloadIdentifier": identifier + ".webfilter",
                "PayloadUUID": UUID().uuidString,
                "PayloadDisplayName": "Website Restrictions",
                "FilterType": "BuiltIn",
                "AutoFilterEnabled": false,
                "DenyListURLs": urls,
            ])
        }

        if let removalPassword, !removalPassword.isEmpty {
            payloads.append([
                "PayloadType": "com.apple.profileRemovalPassword",
                "PayloadVersion": 1,
                "PayloadIdentifier": identifier + ".removalpassword",
                "PayloadUUID": UUID().uuidString,
                "PayloadDisplayName": "Removal Password",
                "RemovalPassword": removalPassword,
            ])
        }

        let root: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier,
            "PayloadUUID": UUID().uuidString,
            "PayloadDisplayName": "Bottle App Restrictions",
            "PayloadDescription": "Installed by Bottle to \(mode == .block ? "block" : "allow") selected apps\(urls.isEmpty ? "" : " and block selected websites").",
            "PayloadOrganization": organizationName,
            "PayloadRemovalDisallowed": removalPassword == nil ? lockedOnPhone : false,
            "PayloadContent": payloads,
        ]
        return try PropertyListSerialization.data(fromPropertyList: root, format: .xml, options: 0)
    }

    /// "instagram.com" → https/http × bare/www. Accepts pasted URLs too.
    static func normalizeSite(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        if let range = text.range(of: "://") { text = String(text[range.upperBound...]) }
        text = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? text
        text = text.split(separator: "?", maxSplits: 1).first.map(String.init) ?? text
        if text.hasPrefix("www.") { text = String(text.dropFirst(4)) }
        guard text.contains("."), !text.contains(" ") else { return nil }
        return text
    }

    static func denyListURLs(for sites: [String]) -> [String] {
        var urls: [String] = []
        for host in sites.compactMap(normalizeSite) {
            urls += ["https://\(host)", "http://\(host)", "https://www.\(host)", "http://www.\(host)"]
        }
        return Array(NSOrderedSet(array: urls)) as? [String] ?? urls
    }

    /// Apple apps that don't always show up in `installedApps` but can be blocked.
    static let builtInApps: [InstalledApp] = [
        ("com.apple.mobilesafari", "Safari"),
        ("com.apple.AppStore", "App Store"),
        ("com.apple.MobileSMS", "Messages"),
        ("com.apple.facetime", "FaceTime"),
        ("com.apple.camera", "Camera"),
        ("com.apple.mobileslideshow", "Photos"),
        ("com.apple.mobilemail", "Mail"),
        ("com.apple.Music", "Music"),
        ("com.apple.tv", "TV"),
        ("com.apple.news", "News"),
        ("com.apple.podcasts", "Podcasts"),
        ("com.apple.iBooks", "Books"),
        ("com.apple.Maps", "Maps"),
        ("com.apple.Passbook", "Wallet"),
        ("com.apple.Health", "Health"),
        ("com.apple.Fitness", "Fitness"),
        ("com.apple.weather", "Weather"),
        ("com.apple.stocks", "Stocks"),
        ("com.apple.calculator", "Calculator"),
        ("com.apple.mobilenotes", "Notes"),
        ("com.apple.reminders", "Reminders"),
        ("com.apple.mobilecal", "Calendar"),
        ("com.apple.mobiletimer", "Clock"),
        ("com.apple.MobileAddressBook", "Contacts"),
        ("com.apple.DocumentsApp", "Files"),
        ("com.apple.shortcuts", "Shortcuts"),
        ("com.apple.Translate", "Translate"),
        ("com.apple.VoiceMemos", "Voice Memos"),
        ("com.apple.Home", "Home"),
        ("com.apple.findmy", "Find My"),
        ("com.apple.tips", "Tips"),
        ("com.apple.freeform", "Freeform"),
        ("com.apple.journal", "Journal"),
        ("com.apple.compass", "Compass"),
        ("com.apple.measure", "Measure"),
        ("com.apple.Magnifier", "Magnifier"),
        ("com.apple.Bridge", "Watch"),
        ("com.apple.MobileStore", "iTunes Store"),
    ].map { InstalledApp(bundleID: $0.0, name: $0.1, isBuiltIn: true) }
}
