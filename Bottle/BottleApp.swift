import SwiftUI

@main
struct BottleApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Updater.shared.checkForUpdates() }
                    .disabled(!Updater.shared.canCheck)
            }
            CommandGroup(after: .toolbar) {
                Button("Toggle Activity Log") { model.showLog.toggle() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
        }
    }
}
