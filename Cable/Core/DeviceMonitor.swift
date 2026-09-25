import Foundation
import Observation

/// Polls `cfgutil list` so the sidebar reflects what is plugged in.
/// Skips a poll while another cfgutil command is running.
@MainActor
@Observable
final class DeviceMonitor {
    private(set) var devices: [Device] = []
    private(set) var lastError: String?
    var selectedECID: String?

    private let cfgutil: CfgUtil
    private var task: Task<Void, Never>?

    init(cfgutil: CfgUtil) {
        self.cfgutil = cfgutil
    }

    var selectedDevice: Device? {
        devices.first { $0.ecid == selectedECID }
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func refresh(force: Bool = false) async {
        if Demo.isOn {
            if Demo.screen(is: "nophone") { devices = []; selectedECID = nil; return }
            if devices.isEmpty { devices = [Demo.device] }
            if selectedECID == nil { selectedECID = devices.first?.ecid }
            return
        }
        guard CfgUtil.isInstalled else {
            lastError = CfgUtilError.notInstalled.localizedDescription
            return
        }
        if cfgutil.isBusy && !force { return }

        do {
            let list = try await cfgutil.run("list", timeout: 2, quiet: true)
            var updated: [Device] = []
            for ecid in list.devices {
                var device = devices.first { $0.ecid == ecid } ?? Device(ecid: ecid)
                device.apply(list.properties(for: ecid))
                if let details = try? await cfgutil.run("get", Device.summaryProperties, ecid: ecid, timeout: 2, quiet: true) {
                    device.apply(details.properties(for: ecid))
                }
                updated.append(device)
            }
            devices = updated
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        if selectedECID == nil || !devices.contains(where: { $0.ecid == selectedECID }) {
            selectedECID = devices.first?.ecid
        }
    }
}
