import Foundation

struct Device: Identifiable, Hashable {
    let ecid: String
    var name = ""
    var deviceType = ""
    var udid: String?
    var serialNumber: String?
    var isSupervised: Bool?
    var isPaired: Bool?
    var isRestorable: Bool?
    var activationState: String?
    var bootedState: String?
    var productVersion: String?
    var organizationName: String?
    var passcodeProtected: Bool?
    var backupWillBeEncrypted: Bool?
    var batteryLevel: Int?

    var id: String { ecid }

    /// Properties fetched on every poll — keep this cheap.
    static let summaryProperties = [
        "name", "deviceType", "UDID", "serialNumber",
        "isSupervised", "isPaired", "isRestorable",
        "activationState", "bootedState",
        "humanReadableProductVersion", "organizationName",
        "passcodeProtected", "backupWillBeEncrypted", "batteryCurrentCapacity",
    ]

    mutating func apply(_ props: [String: Any]) {
        if let v = JSONCoerce.string(props["name"]) { name = v }
        if let v = JSONCoerce.string(props["deviceType"]) { deviceType = v }
        if let v = JSONCoerce.string(props["UDID"]) { udid = v }
        if let v = JSONCoerce.string(props["serialNumber"]) { serialNumber = v }
        if let v = JSONCoerce.bool(props["isSupervised"]) { isSupervised = v }
        if let v = JSONCoerce.bool(props["isPaired"]) { isPaired = v }
        if let v = JSONCoerce.bool(props["isRestorable"]) { isRestorable = v }
        if let v = JSONCoerce.string(props["activationState"]) { activationState = v }
        if let v = JSONCoerce.string(props["bootedState"]) { bootedState = v }
        if let v = JSONCoerce.string(props["humanReadableProductVersion"]) { productVersion = v }
        if let v = JSONCoerce.string(props["organizationName"]) { organizationName = v }
        if let v = JSONCoerce.bool(props["passcodeProtected"]) { passcodeProtected = v }
        if let v = JSONCoerce.bool(props["backupWillBeEncrypted"]) { backupWillBeEncrypted = v }
        if let v = JSONCoerce.int(props["batteryCurrentCapacity"]) { batteryLevel = v }
    }

    var family: String {
        for prefix in ["iPhone", "iPad", "iPod", "AppleTV"] where deviceType.hasPrefix(prefix) {
            return prefix == "AppleTV" ? "Apple TV" : prefix
        }
        return deviceType.isEmpty ? "Device" : deviceType
    }

    var displayName: String { name.isEmpty ? family : name }

    var subtitle: String {
        var parts: [String] = []
        if let productVersion { parts.append("iOS \(productVersion)") }
        if let isSupervised { parts.append(isSupervised ? "Supervised" : "Not supervised") }
        return parts.joined(separator: " · ")
    }
}

struct InstalledApp: Identifiable, Hashable {
    let bundleID: String
    let name: String
    let isBuiltIn: Bool

    var id: String { bundleID }
}

/// cfgutil's JSON is loosely typed (bools show up as true/1/"true"), so coerce.
enum JSONCoerce {
    static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool: return b
        case let n as NSNumber: return n.boolValue
        case let s as String:
            switch s.lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        default: return nil
        }
    }

    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }
}
