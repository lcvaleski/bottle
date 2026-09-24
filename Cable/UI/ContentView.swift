import SwiftUI
import AppKit

/// One window, one phone. There's no sidebar: people connect a single iPhone,
/// so the device lives in the toolbar and the whole window is the task at hand.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            DetailView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.showLog {
                Divider()
                LogView(log: model.log)
                    .frame(height: 200)
            }
        }
        .navigationTitle(model.monitor.selectedDevice?.displayName ?? "Cable")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if let device = model.monitor.selectedDevice {
                    StatusChip(kind: DeviceToolbarTitle.kind(for: device, locked: model.lock.isLocked))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                if model.monitor.devices.count > 1 {
                    DevicePicker()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showLog.toggle()
                } label: {
                    Label("Activity", systemImage: model.showLog ? "terminal.fill" : "terminal")
                }
                .help("Show exactly what Cable is running (⌘⇧L)")
            }
        }
        .background(WindowConfigurator())
        .task { model.monitor.start() }
    }

    private var subtitle: String {
        guard let device = model.monitor.selectedDevice else { return "" }
        var parts: [String] = []
        if let version = device.productVersion { parts.append("iOS \(version)") }
        if let battery = device.batteryLevel { parts.append("\(battery)%") }
        return parts.joined(separator: " · ")
    }
}

enum DeviceToolbarTitle {
    /// One place that decides which status word the whole app shows.
    static func kind(for device: Device, locked: Bool) -> StatusChip.Kind {
        if locked { return .locked }
        if device.isPaired == false { return .needsTrust }
        if device.isSupervised != true { return .notSetUp }
        return .ready
    }
}

/// Only appears when more than one device is plugged in, which is rare.
struct DevicePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var monitor = model.monitor
        Picker("Device", selection: $monitor.selectedECID) {
            ForEach(monitor.devices) { device in
                Text(device.displayName).tag(device.ecid as String?)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 200)
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !CfgUtil.isInstalled {
            ConfiguratorMissingView()
        } else if model.lock.isLocked {
            LockedView(device: model.monitor.selectedDevice)
        } else if let device = model.monitor.selectedDevice {
            DeviceView(device: device)
                .id(device.ecid)
        } else {
            WaitingForPhoneView(error: model.monitor.lastError)
        }
    }
}

struct WaitingForPhoneView: View {
    let error: String?

    var body: some View {
        ContentUnavailableView {
            Label("Plug in your iPhone", systemImage: "cable.connector")
        } description: {
            VStack(spacing: 10) {
                Text("Connect it with a cable, unlock it, and tap **Trust** if it asks.")
                Text("Wi-Fi isn't enough — Cable needs the cable to change what's on the phone.")
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .multilineTextAlignment(.center)
        }
    }
}

struct ConfiguratorMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("One free download first", systemImage: "app.badge.checkmark")
        } description: {
            Text("Cable drives Apple's own Apple Configurator to talk to your iPhone. Install it from the Mac App Store — it's free — then come back.")
        } actions: {
            Link("Get Apple Configurator", destination: URL(string: "macappstore://apps.apple.com/app/id1037126344")!)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}

/// SwiftUI's `.defaultSize` was being ignored for this scene, so size the window
/// through AppKit: restore the user's last frame if there is one, otherwise open
/// at a sensible size, and never let it shrink small enough to break the layout.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.minSize = NSSize(width: 720, height: 520)
            window.setFrameAutosaveName("CableMainWindow")
            if !window.setFrameUsingName("CableMainWindow") {
                window.setContentSize(NSSize(width: 940, height: 660))
                window.center()
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
