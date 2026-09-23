import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let log = ActivityLog()
    let identityStore = SupervisionIdentityStore()
    let cfgutil: CfgUtil
    let monitor: DeviceMonitor
    let iconCache: IconCache
    let lock: LockModel

    var showLog = false
    private(set) var wizards: [String: SupervisionWizard] = [:]
    private var restrictionsModels: [String: AppRestrictionsModel] = [:]

    init() {
        cfgutil = CfgUtil(log: log)
        cfgutil.identity = identityStore.identity
        monitor = DeviceMonitor(cfgutil: cfgutil)
        iconCache = IconCache(cfgutil: cfgutil)
        lock = LockModel(cfgutil: cfgutil, identityStore: identityStore)
        if lock.isLocked && !Demo.isOn { lock.startPolling() }
    }

    func adoptIdentity(_ identity: SupervisionIdentity) {
        cfgutil.identity = identity
        Task { await monitor.refresh(force: true) }
    }

    func wizard(for device: Device) -> SupervisionWizard? {
        wizards[device.ecid]
    }

    @discardableResult
    func startWizard(for device: Device) -> SupervisionWizard {
        if let existing = wizards[device.ecid] { return existing }
        let wizard = SupervisionWizard(device: device, cfgutil: cfgutil, identityStore: identityStore)
        wizards[device.ecid] = wizard
        return wizard
    }

    func endWizard(for ecid: String) {
        wizards[ecid]?.cancel()
        wizards[ecid] = nil
        Task { await monitor.refresh(force: true) }
    }

    func restrictions(for device: Device) -> AppRestrictionsModel {
        if let existing = restrictionsModels[device.ecid] { return existing }
        let model = AppRestrictionsModel(device: device, cfgutil: cfgutil, identityStore: identityStore, iconCache: iconCache)
        restrictionsModels[device.ecid] = model
        return model
    }
}
