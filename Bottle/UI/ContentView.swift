import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                DetailView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.showLog {
                    Divider()
                    LogView(log: model.log)
                        .frame(height: 220)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.showLog.toggle()
                } label: {
                    Label("Activity Log", systemImage: "terminal")
                }
                .help("Show cfgutil output")
            }
        }
        .task { model.monitor.start() }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var monitor = model.monitor
        List(selection: $monitor.selectedECID) {
            Section("Devices") {
                if monitor.devices.isEmpty {
                    Text("Nothing connected")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monitor.devices) { device in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.displayName)
                                Text(device.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: device.family == "iPad" ? "ipad" : "iphone")
                        }
                        .tag(device.ecid)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(CfgUtil.isInstalled ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(CfgUtil.isInstalled ? "Apple Configurator found" : "Apple Configurator missing")
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.identityStore.identity == nil ? .gray : .green)
                        .frame(width: 8, height: 8)
                    Text(model.identityStore.identity.map { "Identity: \($0.organizationName)" } ?? "No supervision identity")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.bar)
        }
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if !CfgUtil.isInstalled {
            ConfiguratorMissingView()
        } else if let device = model.monitor.selectedDevice {
            DeviceView(device: device)
                .id(device.ecid)
        } else if model.lock.isLocked {
            LockedView(device: nil)
        } else {
            NoDeviceView(error: model.monitor.lastError)
        }
    }
}

struct NoDeviceView: View {
    let error: String?

    var body: some View {
        ContentUnavailableView {
            Label("Connect an iPhone", systemImage: "iphone.gen3.slash")
        } description: {
            VStack(spacing: 6) {
                Text("Plug your iPhone into this Mac with a cable, unlock it, and tap **Trust** if asked.")
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }
}

struct ConfiguratorMissingView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Apple Configurator is required", systemImage: "app.dashed")
        } description: {
            Text("Bottle uses the `cfgutil` tool that ships inside Apple Configurator. Install it from the Mac App Store (free), then relaunch Bottle.")
        } actions: {
            Link("Open in App Store", destination: URL(string: "macappstore://apps.apple.com/app/id1037126344")!)
                .buttonStyle(.borderedProminent)
        }
    }
}
