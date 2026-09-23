import Foundation

/// Fake state for designing and screenshotting the UI without a phone attached.
/// Enabled with BOTTLE_DEMO=1; never reachable in a shipped launch.
enum Demo {
    static let isOn = ProcessInfo.processInfo.environment["BOTTLE_DEMO"] == "1"

    /// Opens a screen straight away so it can be reviewed without clicking
    /// around: BOTTLE_DEMO_SCREEN=lock | locked | setup | wizard
    static var screen: String? { ProcessInfo.processInfo.environment["BOTTLE_DEMO_SCREEN"] }

    static var device: Device {
        var device = Device(ecid: "0xDEM0")
        device.name = "Logan’s iPhone"
        device.deviceType = "iPhone16,1"
        device.udid = "00008130-000DEM0DEM0DEM0"
        device.isSupervised = (screen != "setup" && screen != "wizard")
        device.isPaired = true
        device.activationState = "Activated"
        device.bootedState = "Booted"
        device.productVersion = "26.6.1"
        device.organizationName = "Coventry Labs, LLC"
        device.batteryLevel = 78
        device.backupWillBeEncrypted = false
        return device
    }

    static let apps: [InstalledApp] = ([
        ("com.burbn.instagram", "Instagram"),
        ("com.zhiliaoapp.musically", "TikTok"),
        ("com.reddit.Reddit", "Reddit"),
        ("com.google.ios.youtube", "YouTube"),
        ("com.toyopagroup.picaboo", "Snapchat"),
        ("com.atebits.Tweetie2", "X"),
        ("com.hammerandchisel.discord", "Discord"),
        ("com.netflix.Netflix", "Netflix"),
        ("com.spotify.client", "Spotify"),
        ("com.openai.chat", "ChatGPT"),
        ("com.anthropic.claude", "Claude"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("com.linkedin.LinkedIn", "LinkedIn"),
        ("com.ubercab.UberClient", "Uber"),
        ("com.squareup.cash", "Cash App"),
        ("com.amazon.Amazon", "Amazon"),
    ].map { InstalledApp(bundleID: $0.0, name: $0.1, isBuiltIn: false) })
        + RestrictionsProfile.builtInApps.prefix(14)

    static let otherProfile = InstalledProfile(
        identifier: "MacBook-Air-639.3682B6C0",
        displayName: "Instagram",
        sourceURL: URL(fileURLWithPath: "/Users/demo/Downloads/IG.mobileconfig"),
        restrictions: AppRestrictions(mode: .block, bundleIDs: ["com.burbn.instagram"])
    )

    static let blockedApps: Set<String> = ["com.zhiliaoapp.musically", "com.reddit.Reddit", "com.google.ios.youtube"]
    static let blockedSites = ["news.ycombinator.com", "x.com"]
}
