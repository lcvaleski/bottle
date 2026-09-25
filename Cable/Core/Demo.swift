import AppKit
import Foundation

/// Fake state for designing and screenshotting the UI without a phone attached.
/// Enabled with CABLE_DEMO=1; never reachable in a shipped launch.
enum Demo {
    static let isOn = ProcessInfo.processInfo.environment["CABLE_DEMO"] == "1"

    /// Jumps straight to one state so every screen can be reviewed and
    /// screenshotted without clicking around. See `scripts/screens.sh` for the
    /// full list.
    static var screen: String { ProcessInfo.processInfo.environment["CABLE_DEMO_SCREEN"] ?? "apps-blocked" }

    static func screen(is name: String) -> Bool { screen == name }
    static var isWizard: Bool { screen.hasPrefix("wizard") }
    static var isIdentity: Bool { screen.hasPrefix("identity") }
    static var isSites: Bool { screen.hasPrefix("sites") }

    static var device: Device {
        var device = Device(ecid: "0xDEM0")
        device.name = "Logan’s iPhone"
        device.deviceType = "iPhone16,1"
        device.udid = "00008130-000DEM0DEM0DEM0"
        device.activationState = "Activated"
        device.bootedState = "Booted"
        device.productVersion = "26.6.1"
        device.batteryLevel = 78
        device.backupWillBeEncrypted = false
        // Per-screen overrides last, or they get clobbered by the defaults.
        device.isSupervised = !(screen == "setup" || isWizard)
        device.isPaired = screen != "needstrust"
        device.organizationName = screen == "identity-mismatch" ? "Someone Else, Inc." : "Coventry Labs, LLC"
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

    /// Stand-in app icons so the grid can be laid out without a phone attached.
    private static var placeholders: [String: NSImage] = [:]

    static func placeholderIcon(for bundleID: String) -> NSImage? {
        if let cached = placeholders[bundleID] { return cached }
        let name = apps.first { $0.bundleID == bundleID }?.name ?? bundleID
        let side = 128.0
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(side), pixelsHigh: Int(side),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let hue = Double(abs(bundleID.hashValue) % 360) / 360
        NSColor(calibratedHue: hue, saturation: 0.62, brightness: 0.82, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: side, height: side), xRadius: side * 0.23, yRadius: side * 0.23).fill()
        let letter = String(name.prefix(1)).uppercased() as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: side * 0.5, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = letter.size(withAttributes: attrs)
        letter.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        placeholders[bundleID] = image
        return image
    }

    static let otherProfile = InstalledProfile(
        identifier: "MacBook-Air-639.3682B6C0",
        displayName: "Instagram",
        sourceURL: URL(fileURLWithPath: "/Users/demo/Downloads/IG.mobileconfig"),
        restrictions: AppRestrictions(mode: .block, bundleIDs: ["com.burbn.instagram"])
    )

    static let blockedApps: Set<String> = ["com.zhiliaoapp.musically", "com.reddit.Reddit", "com.google.ios.youtube"]
    static let blockedSites = ["news.ycombinator.com", "x.com"]
}
