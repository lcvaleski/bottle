import Foundation

/// Bottle can't read Screen Time — Apple doesn't expose it over the cable. What
/// it can read is the Home Screen layout, and where an app sits is a decent
/// stand-in for how often it gets opened: the dock holds four apps you reach for
/// without thinking, and page one is the rest of the habit.
///
/// That, plus the apps people actually come here to block, is what "Suggested" is.
enum Suggestions {
    /// The apps people install Bottle to get away from. Being on this list only
    /// ever offers a suggestion; nothing is blocked without the user saying so.
    static let usualSuspects: Set<String> = [
        "com.burbn.instagram",            // Instagram
        "com.zhiliaoapp.musically",       // TikTok
        "com.toyopagroup.picaboo",        // Snapchat
        "com.reddit.Reddit",
        "com.google.ios.youtube",
        "com.atebits.Tweetie2",           // X
        "com.facebook.Facebook",
        "com.hammerandchisel.discord",
        "com.linkedin.LinkedIn",
        "pinterest",
        "com.netflix.Netflix",
        "com.hulu.plus",
        "tv.twitch",
        "com.tinder",
        "com.cardify.tinder",
        "com.bumble.app",
        "com.hinge.app",
        "com.tmediatech.truthsocial",
        "com.wbd.stream",
        "com.amazon.Amazon",
        "com.ebay.iphone",
        "com.robinhood.release.Robinhood",
        "com.polymarket.ios-app",
        "com.draftkings.sportsbook",
        "com.fanduel.sportsbook",
    ]

    /// Where an app sits on the Home Screen. 0 = dock, 1 = first page, and so on.
    /// Apps that aren't placed anywhere don't appear.
    static func homeScreenRanks(fromIconLayout json: String) -> [String: Int] {
        guard let data = json.data(using: .utf8),
              let pages = try? JSONSerialization.jsonObject(with: data) as? [Any]
        else { return [:] }

        var ranks: [String: Int] = [:]
        for (index, page) in pages.enumerated() {
            collect(page, page: index, into: &ranks)
        }
        return ranks
    }

    /// Pages nest folders as ["Folder", [ids…]], so walk instead of assuming depth.
    private static func collect(_ node: Any, page: Int, into ranks: inout [String: Int]) {
        if let id = node as? String {
            guard id != "Folder", id.contains(".") || id.contains("-") else { return }
            if ranks[id] == nil { ranks[id] = page }
        } else if let list = node as? [Any] {
            for child in list { collect(child, page: page, into: &ranks) }
        }
    }

    struct Suggestion: Identifiable {
        let app: InstalledApp
        let reason: String
        var id: String { app.bundleID }
    }

    /// At most `limit` apps worth offering, best first.
    static func build(apps: [InstalledApp], ranks: [String: Int], excluding chosen: Set<String>, limit: Int = 8) -> [Suggestion] {
        let candidates = apps.filter { app in
            guard !chosen.contains(app.bundleID), !app.isBuiltIn else { return false }
            return usualSuspects.contains(app.bundleID) || (ranks[app.bundleID].map { $0 <= 1 } ?? false)
        }

        return candidates
            .map { app -> (Suggestion, Int) in
                let rank = ranks[app.bundleID]
                let known = usualSuspects.contains(app.bundleID)
                let reason: String
                switch (known, rank) {
                case (true, 0): reason = "In your dock"
                case (true, 1): reason = "On your first Home Screen page"
                case (true, _): reason = "Commonly blocked"
                case (false, 0): reason = "In your dock"
                default: reason = "On your first Home Screen page"
                }
                // Known distractions first, then by how close to hand they are.
                let score = (known ? 0 : 100) + (rank ?? 9)
                return (Suggestion(app: app, reason: reason), score)
            }
            .sorted { ($0.1, $0.0.app.name.lowercased()) < ($1.1, $1.0.app.name.lowercased()) }
            .prefix(limit)
            .map(\.0)
    }
}
