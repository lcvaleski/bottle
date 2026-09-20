import Foundation
import Testing
@testable import Bottle

struct RestrictionsProfileTests {
    private func payload(mode: RestrictionMode, ids: [String]) throws -> [String: Any] {
        let data = try RestrictionsProfile.data(mode: mode, bundleIDs: ids, organizationName: "Test Org")
        let root = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(root["PayloadIdentifier"] as? String == RestrictionsProfile.identifier)
        #expect(root["PayloadOrganization"] as? String == "Test Org")
        #expect(root["PayloadRemovalDisallowed"] as? Bool == false)
        let content = try #require(root["PayloadContent"] as? [[String: Any]])
        #expect(content.count == 1)
        return content[0]
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

    /// Round-trip: what Bottle writes, ProfileLibrary must read back.
    @Test func libraryReadsBottlesOwnProfile() throws {
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

    @Test func legacyIdentifierCountsAsBottle() {
        #expect(InstalledProfile(identifier: "com.bottle.app-restrictions", displayName: "old").isBottle)
        #expect(InstalledProfile(identifier: RestrictionsProfile.identifier, displayName: "new").isBottle)
        #expect(!InstalledProfile(identifier: "MacBook-Air-639.X", displayName: "Instagram").isBottle)
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
