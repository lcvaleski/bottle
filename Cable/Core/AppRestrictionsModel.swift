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
    /// Hostnames blocked via the web content filter payload.
    var sites: [String] = [] {
        didSet { persistSelection() }
    }
    var siteInput = ""

    private(set) var apps: [InstalledApp] = []
    private(set) var profiles: [InstalledProfile] = []
    private(set) var profileInstalled = false

    /// What is actually live on the phone right now, as opposed to what the user
    /// is editing. The phone never hands the payload back, so this is what Cable
    /// last successfully installed.
    private(set) var appliedMode: RestrictionMode?
    private(set) var appliedApps: Set<String> = []
    private(set) var appliedSites: [String] = []

    var showSuggestions = true
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

    var suggestions: [InstalledApp] {
        guard showSuggestions else { return [] }
        return Suggestions.build(apps: apps, excluding: selected)
    }

    func acceptAllSuggestions() {
        for app in suggestions { selected.insert(app.bundleID) }
    }

    /// Everything the user has picked or that is already live — the phone's
    /// current state, pulled to the top of the list so it's never hunted for.
    var chosenApps: [InstalledApp] {
        filteredApps.filter { state(of: $0.bundleID) != .off }
    }

    var builtInApps: [InstalledApp] {
        filteredApps.filter { $0.isBuiltIn && state(of: $0.bundleID) == .off }
    }

    var thirdPartyApps: [InstalledApp] {
        filteredApps.filter { !$0.isBuiltIn && state(of: $0.bundleID) == .off }
    }

    // MARK: - Live vs. edited

    var isActive: Bool { profileInstalled && appliedMode != nil }

    /// Apps the user has ticked that aren't live yet.
    var pendingAdditions: Set<String> { selected.subtracting(appliedApps) }
    /// Apps that are live but the user has unticked.
    var pendingRemovals: Set<String> { appliedApps.subtracting(selected) }
    var pendingSiteAdditions: [String] { sites.filter { !appliedSites.contains($0) } }
    var pendingSiteRemovals: [String] { appliedSites.filter { !sites.contains($0) } }

    var hasPendingChanges: Bool {
        guard isActive else { return !selected.isEmpty || !sites.isEmpty }
        return !pendingAdditions.isEmpty || !pendingRemovals.isEmpty
            || !pendingSiteAdditions.isEmpty || !pendingSiteRemovals.isEmpty
            || appliedMode != mode
    }

    /// Where an app stands: live, about to change, or untouched.
    enum RowState { case off, on, willTurnOn, willTurnOff }

    func state(of bundleID: String) -> RowState {
        let live = isActive && appliedApps.contains(bundleID)
        let picked = selected.contains(bundleID)
        switch (live, picked) {
        case (true, true): return .on
        case (false, false): return .off
        case (false, true): return .willTurnOn
        case (true, false): return .willTurnOff
        }
    }

    func siteState(of host: String) -> RowState {
        let live = isActive && appliedSites.contains(host)
        let picked = sites.contains(host)
        switch (live, picked) {
        case (true, true): return .on
        case (false, false): return .off
        case (false, true): return .willTurnOn
        case (true, false): return .willTurnOff
        }
    }

    /// Throw away edits and go back to what the phone actually has.
    func revert() {
        selected = appliedApps
        sites = appliedSites
        if let appliedMode { mode = appliedMode }
        statusMessage = nil
        errorMessage = nil
    }

    func toggle(_ bundleID: String) {
        if selected.contains(bundleID) { selected.remove(bundleID) } else { selected.insert(bundleID) }
    }

    /// Profiles on the phone that Cable didn't install.
    var otherProfiles: [InstalledProfile] { profiles.filter { !$0.isCable } }

    /// bundle ID → name of a non-Cable profile that blocks it.
    var blockedByOthers: [String: String] {
        var map: [String: String] = [:]
        for profile in otherProfiles {
            guard let r = profile.restrictions, r.mode == .block else { continue }
            for id in r.bundleIDs where map[id] == nil { map[id] = profile.displayName }
        }
        return map
    }

    /// Non-Cable profiles with an allow-list (they override everything else).
    var allowListProfiles: [InstalledProfile] {
        otherProfiles.filter { $0.restrictions?.mode == .allow }
    }

    func load() async {
        if Demo.isOn {
            apps = Demo.apps.sorted { ($0.isBuiltIn ? 0 : 1, $0.name.lowercased()) < ($1.isBuiltIn ? 0 : 1, $1.name.lowercased()) }
            profiles = [Demo.otherProfile, InstalledProfile(identifier: RestrictionsProfile.identifier, displayName: "Cable App Restrictions")]
            profileInstalled = true
            appliedMode = .block
            appliedApps = Demo.blockedApps
            appliedSites = Demo.blockedSites
            selected = Demo.blockedApps
            sites = Demo.blockedSites
            mode = .block
            return
        }
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
            profileInstalled = profiles.contains { $0.isCable }
            if !profileInstalled {
                appliedMode = nil
                appliedApps = []
                appliedSites = []
            }
            persistApplied()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Icons load after the list is on screen; rows fill in as batches land.
        let ids = apps.map(\.bundleID)
        Task { await iconCache.ensureIcons(for: ids, ecid: ecid, deviceKey: deviceKey) }
    }

    func addSite() {
        guard let host = RestrictionsProfile.normalizeSite(siteInput) else { return }
        if !sites.contains(host) { sites.append(host) }
        siteInput = ""
    }

    func removeSite(_ host: String) {
        sites.removeAll { $0 == host }
    }

    func apply() async {
        guard !isApplying else { return }
        isApplying = true
        errorMessage = nil
        statusMessage = nil
        defer { isApplying = false }

        do {
            let org = identityStore.identity?.organizationName ?? "Cable"
            let data = try RestrictionsProfile.data(mode: mode, bundleIDs: Array(selected), sites: sites, organizationName: org, lockedOnPhone: lockedOnPhone)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("cable-app-restrictions-\(UUID().uuidString).mobileconfig")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }

            try await cfgutil.run("install-profile", [url.path], ecid: ecid, timeout: 10)
            for legacy in profiles where RestrictionsProfile.legacyIdentifiers.contains(legacy.identifier) {
                try await cfgutil.run("remove-profile", [legacy.identifier], ecid: ecid, timeout: 10)
            }
            profileInstalled = true
            appliedMode = mode
            appliedApps = selected
            appliedSites = sites
            profiles.removeAll { $0.isCable }
            profiles.append(InstalledProfile(
                identifier: RestrictionsProfile.identifier,
                displayName: "Cable App Restrictions",
                restrictions: AppRestrictions(mode: mode, bundleIDs: Array(selected))
            ))
            statusMessage = "Applied — \(selected.count) app\(selected.count == 1 ? "" : "s") \(mode == .block ? "blocked" : "allowed")"
                + (sites.isEmpty ? "" : ", \(sites.count) site\(sites.count == 1 ? "" : "s") blocked")
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

    /// Copies another profile's app list into Cable's selection so it can be
    /// re-applied as Cable's own profile and the original removed.
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
            for profile in profiles where profile.isCable {
                try await cfgutil.run("remove-profile", [profile.identifier], ecid: ecid, timeout: 10)
            }
            profileInstalled = false
            appliedMode = nil
            appliedApps = []
            appliedSites = []
            selected = []
            sites = []
            profiles.removeAll { $0.isCable }
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

    private static func savedUnderOldAppName(key: String) -> [String: Any]? {
        UserDefaults(suiteName: "com.coventrylabs.bottle")?.dictionary(forKey: key)
    }

    private func persistApplied() { persistSelection() }

    private func persistSelection() {
        UserDefaults.standard.set(
            [
                "mode": mode.rawValue, "selected": Array(selected), "locked": lockedOnPhone, "sites": sites,
                "appliedMode": appliedMode?.rawValue ?? "", "appliedApps": Array(appliedApps), "appliedSites": appliedSites,
            ] as [String: Any],
            forKey: storageKey
        )
    }

    private func restoreSelection() {
        var saved = UserDefaults.standard.dictionary(forKey: storageKey)
        if saved == nil, let carried = Self.savedUnderOldAppName(key: storageKey) {
            // Carried over from when the app was called Bottle.
            UserDefaults.standard.set(carried, forKey: storageKey)
            saved = carried
        }
        guard let saved else { return }
        // Allow-only mode has no interface for now, so never restore into it —
        // there would be no way back out. The profile builder still supports it.
        mode = .block
        if let ids = saved["selected"] as? [String] {
            selected = Set(ids)
        }
        if let locked = saved["locked"] as? Bool {
            lockedOnPhone = locked
        }
        if let savedSites = saved["sites"] as? [String] {
            sites = savedSites
        }
        if let raw = saved["appliedMode"] as? String, let m = RestrictionMode(rawValue: raw) {
            appliedMode = m
        }
        if let ids = saved["appliedApps"] as? [String] { appliedApps = Set(ids) }
        if let hosts = saved["appliedSites"] as? [String] { appliedSites = hosts }
    }
}
