import Foundation
import Testing
@testable import Cable

struct RestrictionsProfileTests {
    private func payload(mode: RestrictionMode, ids: [String]) throws -> [String: Any] {
        let data = try RestrictionsProfile.data(mode: mode, bundleIDs: ids, organizationName: "Test Org")
        let root = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(root["PayloadIdentifier"] as? String == RestrictionsProfile.identifier)
        #expect(root["PayloadOrganization"] as? String == "Test Org")
        #expect(root["PayloadRemovalDisallowed"] as? Bool == true, "locked on the phone by default")
        let content = try #require(root["PayloadContent"] as? [[String: Any]])
        #expect(content.count == 1)
        return content[0]
    }

    @Test func unlockedProfileIsRemovable() throws {
        let data = try RestrictionsProfile.data(mode: .block, bundleIDs: [], organizationName: "x", lockedOnPhone: false)
        let root = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(root["PayloadRemovalDisallowed"] as? Bool == false)
    }

    @Test func blockModeUsesBlockedKey() throws {
        let p = try payload(mode: .block, ids: ["com.b", "com.a"])
        #expect(p["PayloadType"] as? String == "com.apple.applicationaccess")
        #expect(p["blockedAppBundleIDs"] as? [String] == ["com.a", "com.b"])
        #expect(p["allowListedAppBundleIDs"] == nil)
    }

    @Test func allowModeUsesAllowListKey() throws {
        let p = try payload(mode: .allow, ids: ["com.apple.MobileSMS"])
        #expect(p["allowListedAppBundleIDs"] as? [String] == ["com.apple.MobileSMS"])
        #expect(p["blockedAppBundleIDs"] == nil)
    }

    /// Round-trip: what Cable writes, ProfileLibrary must read back.
    @Test func libraryReadsCablesOwnProfile() throws {
        let data = try RestrictionsProfile.data(mode: .block, bundleIDs: ["com.burbn.instagram"], organizationName: "x")
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let r = try #require(ProfileLibrary.restrictions(in: plist))
        #expect(r.mode == .block)
        #expect(r.bundleIDs == ["com.burbn.instagram"])
    }

    @Test func builtInListHasNoDuplicatesAndNoSystemEssentials() {
        let ids = RestrictionsProfile.builtInApps.map(\.bundleID)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains("com.apple.mobilephone"))
        #expect(!ids.contains("com.apple.Preferences"))
    }
}

struct ProfileLibraryTests {
    /// Apple Configurator's own profiles use the legacy "blacklisted" key.
    @Test func readsLegacyBlacklistKey() {
        let plist: [String: Any] = [
            "PayloadIdentifier": "MacBook-Air-639.3682B6C0",
            "PayloadContent": [[
                "PayloadType": "com.apple.applicationaccess",
                "blacklistedAppBundleIDs": ["com.burbn.instagram"],
            ]],
        ]
        let r = ProfileLibrary.restrictions(in: plist)
        #expect(r?.mode == .block)
        #expect(r?.bundleIDs == ["com.burbn.instagram"])
    }

    @Test func readsLegacyWhitelistKey() {
        let plist: [String: Any] = [
            "PayloadContent": [[
                "PayloadType": "com.apple.applicationaccess",
                "whitelistedAppBundleIDs": ["com.apple.mobilephone", "com.apple.MobileSMS"],
            ]],
        ]
        #expect(ProfileLibrary.restrictions(in: plist)?.mode == .allow)
    }

    @Test func ignoresUnrelatedPayloads() {
        let plist: [String: Any] = [
            "PayloadContent": [[
                "PayloadType": "com.apple.webcontent-filter",
                "FilterType": "BuiltIn",
            ]],
        ]
        #expect(ProfileLibrary.restrictions(in: plist) == nil)
    }

    @Test func legacyIdentifiersCountAsCable() {
        // Both historical identifiers must keep matching, or a phone set up by an
        // older build would end up with two stacked profiles.
        #expect(InstalledProfile(identifier: "com.bottle.app-restrictions", displayName: "first builds").isCable)
        #expect(InstalledProfile(identifier: "com.coventrylabs.bottle.app-restrictions", displayName: "pre-rename").isCable)
        #expect(InstalledProfile(identifier: RestrictionsProfile.identifier, displayName: "new").isCable)
        #expect(!InstalledProfile(identifier: "MacBook-Air-639.X", displayName: "Instagram").isCable)
    }
}

struct SupervisionIdentityTests {
    @Test func organizationFromConfiguratorLabel() {
        let label = "Apple Configurator: Coventry Labs, LLC (6A98678B-5B5C-4EFA-B06D-6E517E07330F)"
        #expect(SupervisionIdentityStore.organization(fromLabel: label) == "Coventry Labs, LLC")
    }

    @Test func organizationFromPlainLabel() {
        #expect(SupervisionIdentityStore.organization(fromLabel: "Acme") == "Acme")
    }
}

struct LockProfileTests {
    private func root(_ data: Data) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
    private func payloads(_ root: [String: Any]) throws -> [[String: Any]] {
        try #require(root["PayloadContent"] as? [[String: Any]])
    }

    @Test func removalPasswordMakesProfileRemovableWithPassword() throws {
        let data = try RestrictionsProfile.data(mode: .block, bundleIDs: ["com.a"], organizationName: "x", lockedOnPhone: true, removalPassword: "abc123")
        let r = try root(data)
        #expect(r["PayloadRemovalDisallowed"] as? Bool == false, "password door only works when removal is allowed")
        let pw = try #require(try payloads(r).first { $0["PayloadType"] as? String == "com.apple.profileRemovalPassword" })
        #expect(pw["RemovalPassword"] as? String == "abc123")
    }

    @Test func noPasswordPayloadByDefault() throws {
        let data = try RestrictionsProfile.data(mode: .block, bundleIDs: ["com.a"], organizationName: "x")
        #expect(try payloads(root(data)).count == 1)
    }

    @Test func sitesAddWebFilterPayload() throws {
        let data = try RestrictionsProfile.data(mode: .block, bundleIDs: [], sites: ["instagram.com", "https://www.reddit.com/r/all"], organizationName: "x")
        let filter = try #require(try payloads(root(data)).first { $0["PayloadType"] as? String == "com.apple.webcontent-filter" })
        #expect(filter["FilterType"] as? String == "BuiltIn")
        #expect(filter["AutoFilterEnabled"] as? Bool == false)
        let urls = try #require(filter["DenyListURLs"] as? [String])
        #expect(urls.contains("https://instagram.com"))
        #expect(urls.contains("https://www.instagram.com"))
        #expect(urls.contains("http://reddit.com"))
        #expect(urls.count == 8)
    }

    @Test func normalizeSite() {
        #expect(RestrictionsProfile.normalizeSite("  Instagram.com ") == "instagram.com")
        #expect(RestrictionsProfile.normalizeSite("https://www.reddit.com/r/all?x=1") == "reddit.com")
        #expect(RestrictionsProfile.normalizeSite("www.tiktok.com") == "tiktok.com")
        #expect(RestrictionsProfile.normalizeSite("notadomain") == nil)
        #expect(RestrictionsProfile.normalizeSite("") == nil)
    }

    @Test func libraryStillReadsAppsFromMultiPayloadProfile() throws {
        let data = try RestrictionsProfile.data(mode: .allow, bundleIDs: ["com.apple.MobileSMS"], sites: ["x.com"], organizationName: "x", removalPassword: "p")
        let r = try #require(ProfileLibrary.restrictions(in: try root(data)))
        #expect(r.mode == .allow)
        #expect(r.bundleIDs == ["com.apple.MobileSMS"])
    }
}

struct SuggestionsTests {
    private let installed = [
        InstalledApp(bundleID: "com.spotify.client", name: "Spotify", isBuiltIn: false),
        InstalledApp(bundleID: "com.reddit.Reddit", name: "Reddit", isBuiltIn: false),
        InstalledApp(bundleID: "com.burbn.instagram", name: "Instagram", isBuiltIn: false),
        InstalledApp(bundleID: "com.example.obscure", name: "Obscure", isBuiltIn: false),
    ]

    @Test func suggestsOnlyInstalledSuspectsInPriorityOrder() {
        let result = Suggestions.build(apps: installed, excluding: [])
        #expect(result.map(\.bundleID) == ["com.burbn.instagram", "com.reddit.Reddit"])
    }

    @Test func alreadyPickedAppsDropOut() {
        let result = Suggestions.build(apps: installed, excluding: ["com.burbn.instagram"])
        #expect(result.map(\.bundleID) == ["com.reddit.Reddit"])
    }

    @Test func honoursTheLimit() {
        #expect(Suggestions.build(apps: installed, excluding: [], limit: 1).count == 1)
    }

    @Test func noSuspectsInstalledMeansNoSuggestions() {
        let others = [InstalledApp(bundleID: "com.example.obscure", name: "Obscure", isBuiltIn: false)]
        #expect(Suggestions.build(apps: others, excluding: []).isEmpty)
    }

    @Test func listHasNoDuplicates() {
        #expect(Set(Suggestions.usualSuspects).count == Suggestions.usualSuspects.count)
    }
}

struct SuggestionOverlapTests {
    /// An app being unblocked is still live on the phone, so it must not also be
    /// offered as a suggestion — it would appear twice in the same list.
    @Test func liveAppsAreNeverSuggested() {
        let apps = [
            InstalledApp(bundleID: "com.reddit.Reddit", name: "Reddit", isBuiltIn: false),
            InstalledApp(bundleID: "com.burbn.instagram", name: "Instagram", isBuiltIn: false),
        ]
        let live: Set<String> = ["com.reddit.Reddit"]
        let ticked: Set<String> = []
        let result = Suggestions.build(apps: apps, excluding: ticked.union(live))
        #expect(result.map(\.bundleID) == ["com.burbn.instagram"])
    }
}

@MainActor
struct SelectionTests {
    private func makeModel() -> AppRestrictionsModel {
        let log = ActivityLog()
        let cfgutil = CfgUtil(log: log)
        return AppRestrictionsModel(
            device: Device(ecid: "0xTEST"), cfgutil: cfgutil,
            identityStore: SupervisionIdentityStore(), iconCache: IconCache(cfgutil: cfgutil)
        )
    }

    /// Clicking a tile is the whole commitment now — the selection has to move
    /// the instant it's clicked, with no staging step in between.
    @Test func togglingFlipsStateImmediately() {
        let model = makeModel()
        model.selected = []
        #expect(model.state(of: "com.burbn.instagram") == .off)
        model.toggle("com.burbn.instagram")
        #expect(model.state(of: "com.burbn.instagram") == .on)
        model.toggle("com.burbn.instagram")
        #expect(model.state(of: "com.burbn.instagram") == .off)
    }

    /// Sites are the same two-state affair, keyed by hostname.
    @Test func sitesTrackTheirOwnState() {
        let model = makeModel()
        model.sites = []
        model.siteInput = "https://www.Instagram.com/explore"
        model.addSite()
        #expect(model.sites == ["instagram.com"])
        #expect(model.siteState(of: "instagram.com") == .on)
        model.removeSite("instagram.com")
        #expect(model.siteState(of: "instagram.com") == .off)
    }

    /// Junk in the field must not become a blocked host.
    @Test func rubbishIsNotAddedAsASite() {
        let model = makeModel()
        model.sites = []
        model.siteInput = "not a domain"
        model.addSite()
        #expect(model.sites.isEmpty)
        #expect(model.siteInput == "not a domain", "and the text is left alone to be fixed")
    }
}
