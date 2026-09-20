import Foundation
import Sparkle

/// Sparkle wiring. Update checks only happen if CI baked a feed URL and public
/// key into Info.plist; a dev build's placeholder feed just fails quietly.
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: Self.isConfigured, updaterDelegate: nil, userDriverDelegate: nil)
    }

    /// True when the build carries a real feed URL and signing key.
    static var isConfigured: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let feed = info["SUFeedURL"] as? String, let key = info["SUPublicEDKey"] as? String else { return false }
        return !key.isEmpty && !feed.contains("example.invalid")
    }

    var canCheck: Bool { Self.isConfigured && controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
