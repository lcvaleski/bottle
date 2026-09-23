import Foundation

/// The apps people install Bottle to get away from, in the order they're most
/// often the reason. Suggestions are just this list narrowed to what's actually
/// on the phone — nothing is ever blocked without the user choosing it.
///
/// (Screen Time would be the better signal, but Apple doesn't expose it over the
/// cable: `cfgutil` reports no usage data of any kind.)
enum Suggestions {
    static let usualSuspects: [String] = [
        "com.burbn.instagram",            // Instagram
        "com.zhiliaoapp.musically",       // TikTok
        "com.toyopagroup.picaboo",        // Snapchat
        "com.atebits.Tweetie2",           // X
        "com.reddit.Reddit",
        "com.google.ios.youtube",
        "com.facebook.Facebook",
        "com.hammerandchisel.discord",
        "tv.twitch",
        "com.netflix.Netflix",
        "com.hulu.plus",
        "com.wbd.stream",                 // HBO Max
        "com.linkedin.LinkedIn",
        "pinterest",
        "com.cardify.tinder",
        "com.bumble.app",
        "co.hinge.app",
        "com.amazon.Amazon",
        "com.ebay.iphone",
        "com.robinhood.release.Robinhood",
        "com.polymarket.ios-app",
        "com.draftkings.sportsbook",
        "com.fanduel.sportsbook",
        "com.tmediatech.truthsocial",
    ]

    private static let priority: [String: Int] = Dictionary(
        uniqueKeysWithValues: usualSuspects.enumerated().map { ($0.element, $0.offset) }
    )

    /// The usual suspects that are installed and not already picked, best first.
    static func build(apps: [InstalledApp], excluding chosen: Set<String>, limit: Int = 8) -> [InstalledApp] {
        apps
            .filter { priority[$0.bundleID] != nil && !chosen.contains($0.bundleID) }
            .sorted { (priority[$0.bundleID] ?? .max) < (priority[$1.bundleID] ?? .max) }
            .prefix(limit)
            .map { $0 }
    }
}
