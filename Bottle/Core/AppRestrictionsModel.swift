import Foundation
import Observation

/// Loads the apps on a supervised phone and installs/removes the restrictions profile.
@MainActor
@Observable
final class AppRestrictionsModel {
    let ecid: String
    let iconCache: IconCache
    private let deviceKey: String
    private let storageKey: String
    private let cfgutil: CfgUtil
    private let identityStore: SupervisionIdentityStore

    var mode: RestrictionMode = .block {
        didSet { persistSelection() }
    }
    var selected: Set<String> = [] {
        didSet { persistSelection() }
    }
    /// Whether the profile can be removed from the iPhone's own Settings. Off = only this Mac can.
    var lockedOnPhone = true {
        didSet { persistSelection() }
    }
    var search = ""

    private(set) var apps: [InstalledApp] = []
    private(set) var profiles: [InstalledProfile] = []
    private(set) var profileInstalled = false
    private(set) var isLoading = false
    private(set) var isApplying = false
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?

    init(device: Device, cfgutil: CfgUtil, identityStore: SupervisionIdentityStore, iconCache: IconCache) {
        ecid = device.ecid
        deviceKey = device.udid ?? device.ecid
        storageKey = "restrictions.\(deviceKey)"
        self.cfgutil = cfgutil
        self.identityStore = identityStore
        self.iconCache = iconCache
        restoreSelection()
    }

    var filteredApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return apps }
        return apps.filter { $0.name.lowercased().contains(query) || $0.bundleID.lowercased().contains(query) }
    }

    var builtInApps: [InstalledApp] { filteredApps.filter(\.isBuiltIn) }
    var thirdPartyApps: [InstalledApp] { filteredApps.filter { !$0.isBuiltIn } }

    /// Profiles on the phone that Bottle didn't install.
    var otherProfiles: [InstalledProfile] { profiles.filter { !$0.isBottle } }

    /// bundle ID → name of a non-Bottle profile that blocks it.
    var blockedByOthers: [String: String] {
        var map: [String: String] = [:]
        for profile in otherProfiles {
            guard let r = profile.restrictions, r.mode == .block else { continue }
            for id in r.bundleIDs where map[id] == nil { map[id] = profile.displayName }
        }
        return map
    }

    /// Non-Bottle profiles with an allow-list (they override everything else).
    var allowListProfiles: [InstalledProfile] {
        otherProfiles.filter { $0.restrictions?.mode == .allow }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let result = try await cfgutil.run("get", ["installedApps", "configurationProfiles"], ecid: ecid, timeout: 10)
            let props = result.properties(for: ecid)

            var merged = RestrictionsProfile.builtInApps
            var seen = Set(merged.map(\.bundleID))
            for app in Self.parseApps(props["installedApps"]) where !seen.contains(app.bundleID) {
                seen.insert(app.bundleID)
                merged.append(app)
            }
            apps = merged.sorted { ($0.isBuiltIn ? 0 : 1, $0.name.lowercased()) < ($1.isBuiltIn ? 0 : 1, $1.name.lowercased()) }

            let library = await ProfileLibrary.localProfiles()
            profiles = Self.parseProfiles(props["configurationProfiles"]).map { profile in
                var resolved = profile
                if let local = library[profile.identifier] {
                    resolved.sourceURL = local.url
                    resolved.restrictions = local.restrictions
                }
                return resolved
            }
            profileInstalled = profiles.contains { $0.isBottle }
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Icons load after the list is on screen; rows fill in as batches land.
        let ids = apps.map(\.bundleID)
        Task { await iconCache.ensureIcons(for: ids, ecid: ecid, deviceKey: deviceKey) }
    }

    func apply() async {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = nil
        statusMessage = nil
        defer { isApplying = false }

        do {
            let org = identityStore.identity?.organizationName ?? "Bottle"
            let data = try RestrictionsProfile.data(mode: mode, bundleIDs: Array(selected), organizationName: org, lockedOnPhone: lockedOnPhone)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("bottle-app-restrictions-\(UUID().uuidString).mobileconfig")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            try await cfgutil.run("install-profile", [url.path], ecid: ecid, timeout: 10)
            for legacy in profiles where RestrictionsProfile.legacyIdentifiers.contains(legacy.identifier) {
                try await cfgutil.run("remove-profile", [legacy.identifier], ecid: ecid, timeout: 10)
            }
            profileInstalled = true
            profiles.removeAll { $0.isBottle }
            profiles.append(InstalledProfile(
                identifier: RestrictionsProfile.identifier,
                displayName: "Bottle App Restrictions",
                restrictions: AppRestrictions(mode: mode, bundleIDs: Array(selected))
            ))
            statusMessage = "Applied — \(selected.count) app\(selected.count == 1 ? "" : "s") \(mode == .block ? "blocked" : "allowed")"
                + (lockedOnPhone ? ". Removable only from this Mac." : ". Removable from the iPhone's Settings.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes a profile someone else installed (Apple Configurator, an MDM test, …).
    func removeProfile(_ profile: InstalledProfile) async {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = nil
        statusMessage = nil
        defer { isApplying = false }

        do {
            try await cfgutil.run("remove-profile", [profile.identifier], ecid: ecid, timeout: 10)
            profiles.removeAll { $0.identifier == profile.identifier }
            statusMessage = "Removed “\(profile.displayName)”."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Copies another profile's app list into Bottle's selection so it can be
    /// re-applied as Bottle's own profile and the original removed.
    func adopt(_ profile: InstalledProfile) {
        guard let r = profile.restrictions else { return }
        mode = r.mode
        selected.formUnion(r.bundleIDs)
        let unknown = r.bundleIDs.filter { id in !apps.contains { $0.bundleID == id } }
        // Apps the profile names but the phone doesn't have installed still deserve a row.
        apps.append(contentsOf: unknown.map { InstalledApp(bundleID: $0, name: $0, isBuiltIn: false) })
        statusMessage = "Added \(r.bundleIDs.count) app\(r.bundleIDs.count == 1 ? "" : "s") from “\(profile.displayName)”. Apply, then remove the old profile."
    }

    func removeRestrictions() async {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = nil
        statusMessage = nil
        defer { isApplying = false }

        do {
            for profile in profiles where profile.isBottle {
                try await cfgutil.run("remove-profile", [profile.identifier], ecid: ecid, timeout: 10)
            }
            profileInstalled = false
            profiles.removeAll { $0.isBottle }
            statusMessage = "Restrictions removed. All apps are visible again."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Parsing

    private static func parseApps(_ value: Any?) -> [InstalledApp] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            let bundleID = JSONCoerce.string(item["bundleIdentifier"])
                ?? JSONCoerce.string(item["CFBundleIdentifier"])
                ?? JSONCoerce.string(item["bundleID"])
            guard let bundleID, !bundleID.isEmpty else { return nil }
            let name = JSONCoerce.string(item["name"])
                ?? JSONCoerce.string(item["displayName"])
                ?? JSONCoerce.string(item["CFBundleDisplayName"])
                ?? JSONCoerce.string(item["CFBundleName"])
                ?? bundleID
            return InstalledApp(bundleID: bundleID, name: name, isBuiltIn: bundleID.hasPrefix("com.apple."))
        }
    }

    private static func parseProfiles(_ value: Any?) -> [InstalledProfile] {
        guard let items = value as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let id = JSONCoerce.string(item["identifier"])
                ?? JSONCoerce.string(item["PayloadIdentifier"])
                ?? JSONCoerce.string(item["payloadIdentifier"]) else { return nil }
            let name = JSONCoerce.string(item["displayName"]) ?? JSONCoerce.string(item["PayloadDisplayName"]) ?? id
            return InstalledProfile(identifier: id, displayName: name)
        }
    }

    // MARK: - Persistence (the phone doesn't hand the payload back, so remember what we sent)

    private func persistSelection() {
        UserDefaults.standard.set(
            ["mode": mode.rawValue, "selected": Array(selected), "locked": lockedOnPhone] as [String: Any],
            forKey: storageKey
        )
    }

    private func restoreSelection() {
        guard let saved = UserDefaults.standard.dictionary(forKey: storageKey) else { return }
        if let raw = saved["mode"] as? String, let savedMode = RestrictionMode(rawValue: raw) {
            mode = savedMode
        }
        if let ids = saved["selected"] as? [String] {
            selected = Set(ids)
        }
        if let locked = saved["locked"] as? Bool {
            lockedOnPhone = locked
        }
    }
}
