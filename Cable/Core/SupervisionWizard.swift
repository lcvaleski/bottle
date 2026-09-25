import Foundation
import Observation

/// Drives the erase → prepare → restore sequence for one phone.
///
/// Supervision can only be applied to a freshly erased device, so the flow is:
/// back up, erase, wait for the reboot, `prepare --supervised`, restore the
/// backup onto the still-at-Setup-Assistant phone (supervision survives a
/// restore), then confirm `isSupervised`.
@MainActor
@Observable
final class SupervisionWizard {
    enum StepID: String, CaseIterable, Identifiable {
        case identity, backup, erase, reconnect, prepare, restore, verify

        var id: String { rawValue }

        var title: String {
            switch self {
            case .identity: "Getting ready"
            case .backup: "Backing up"
            case .erase: "Erasing"
            case .reconnect: "Restarting"
            case .prepare: "Setting up"
            case .restore: "Restoring"
            case .verify: "Checking"
            }
        }
    }

    enum Status { case pending, running, done, skipped, failed }

    struct Step: Identifiable {
        let id: StepID
        var status: Status = .pending
        var detail = ""
        var title: String { id.title }
    }

    let ecid: String
    let udid: String?
    let deviceName: String

    // Preflight form
    var organizationName: String
    var backupPassword = ""
    var skipBackup = false
    var confirmedFindMyOff = false
    var confirmedTrusted = false
    var confirmedErase = false

    fileprivate(set) var steps: [Step] = StepID.allCases.map { Step(id: $0) }
    fileprivate(set) var hasStarted = false
    fileprivate(set) var isRunning = false
    fileprivate(set) var isComplete = false
    fileprivate(set) var failure: String?

    private let cfgutil: CfgUtil
    private let identityStore: SupervisionIdentityStore
    private var task: Task<Void, Never>?

    init(device: Device, cfgutil: CfgUtil, identityStore: SupervisionIdentityStore) {
        ecid = device.ecid
        udid = device.udid
        deviceName = device.displayName
        self.cfgutil = cfgutil
        self.identityStore = identityStore
        organizationName = identityStore.identity?.organizationName ?? "Cable"
    }

    /// Demo-only: pose the wizard mid-run, failed, or finished.
    func poseForDemo(_ screen: String) {
        confirmedFindMyOff = true
        confirmedTrusted = true
        confirmedErase = true
        func mark(_ upTo: Int, running: Int? = nil, failed: Int? = nil) {
            hasStarted = true
            for (i, step) in steps.enumerated() {
                if i < upTo { steps[i].status = .done }
                if i == running { steps[i].status = .running }
                if i == failed { steps[i].status = .failed }
                _ = step
            }
        }
        switch screen {
        case "wizard-running":
            mark(2, running: 2)
            steps[2].detail = "Keep the iPhone unlocked"
            isRunning = true
        case "wizard-failed":
            mark(3, failed: 3)
            steps[3].detail = "The iPhone didn't come back. Unlock it, plug it in again, and retry."
            failure = "The iPhone didn't come back. Unlock it, plug it in again, and retry."
        case "wizard-done":
            mark(steps.count)
            isComplete = true
        default:
            break
        }
    }

    var canStart: Bool {
        confirmedFindMyOff && confirmedTrusted && confirmedErase
            && !organizationName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var failedStep: Step? { steps.first { $0.status == .failed } }

    /// Once the erase has started there is nothing to stop — the phone is going
    /// to come back empty either way, so stopping only strands it.
    var isPastPointOfNoReturn: Bool {
        guard let running = steps.first(where: { $0.status == .running }) else { return false }
        return [.erase, .reconnect, .prepare, .restore].contains(running.id)
    }

    func start() { start(from: .identity) }

    func retry() {
        guard let failed = failedStep else { return }
        start(from: failed.id)
    }

    func cancel() {
        task?.cancel()
    }

    private func start(from first: StepID) {
        guard !isRunning else { return }
        hasStarted = true
        isRunning = true
        isComplete = false
        failure = nil

        let order = StepID.allCases
        if let index = order.firstIndex(of: first) {
            for id in order[index...] { set(id, .pending, "") }
        }
        task = Task { await runSteps(from: first) }
    }

    private func runSteps(from first: StepID) async {
        let order = StepID.allCases
        guard let start = order.firstIndex(of: first) else { return }

        for id in order[start...] {
            if Task.isCancelled {
                set(id, .failed, "Cancelled")
                failure = "Cancelled"
                isRunning = false
                return
            }
            set(id, .running, "")
            do {
                try await perform(id)
            } catch is CancellationError {
                set(id, .failed, "Cancelled")
                failure = "Cancelled"
                isRunning = false
                return
            } catch {
                set(id, .failed, error.localizedDescription)
                failure = error.localizedDescription
                isRunning = false
                return
            }
        }
        isRunning = false
        isComplete = true
    }

    private func perform(_ id: StepID) async throws {
        switch id {
        case .identity:
            let identity: SupervisionIdentity
            if let existing = identityStore.identity {
                identity = existing
            } else {
                identity = try await identityStore.generate(organizationName: organizationName, log: cfgutil.log)
            }
            cfgutil.identity = identity
            set(id, .done, "")

        case .backup:
            if skipBackup {
                set(id, .skipped, "Skipped")
                return
            }
            set(id, .running, "Keep the iPhone unlocked")
            try await cfgutil.run("backup", ecid: ecid, timeout: 10, progress: true)
            set(id, .done, "")

        case .erase:
            // No --esim: the eSIM survives the erase, so the user doesn't have to
            // re-activate with their carrier. Don't "fix" this by adding the flag.
            try await cfgutil.run("erase", ecid: ecid, timeout: 10, progress: true)
            set(id, .done, "")

        case .reconnect:
            try await waitForDevice(id, timeout: 15 * 60, initialDelay: 15)
            set(id, .done, "")

        case .prepare:
            guard let identity = cfgutil.identity else {
                throw WizardError.message("No supervision identity is loaded")
            }
            set(id, .running, "")
            try await cfgutil.run("prepare", [
                "--supervised",
                "--name", organizationName.trimmingCharacters(in: .whitespaces),
                "--host-cert", identity.certificateURL.path,
            ], ecid: ecid, timeout: 30, progress: true)
            set(id, .done, "")

        case .restore:
            if skipBackup {
                set(id, .skipped, "Skipped")
                return
            }
            try await waitForDevice(id, timeout: 5 * 60, initialDelay: 3)
            var args: [String] = []
            if !backupPassword.isEmpty { args += ["--password", backupPassword] }
            if let udid { args += ["--source", udid] }
            set(id, .running, "The iPhone will restart when this finishes")
            try await cfgutil.run("restore-backup", args, ecid: ecid, timeout: 30, progress: true)
            set(id, .done, "")

        case .verify:
            try await waitForDevice(id, timeout: 10 * 60, initialDelay: 5)
            let result = try await cfgutil.run("get", ["isSupervised", "organizationName"], ecid: ecid, timeout: 10)
            let props = result.properties(for: ecid)
            guard JSONCoerce.bool(props["isSupervised"]) == true else {
                throw WizardError.message("The iPhone didn't take the setup.")
            }
            let org = JSONCoerce.string(props["organizationName"]) ?? organizationName
            set(id, .done, "")
        }
    }

    /// Polls until the device is listed and reports a booted state.
    private func waitForDevice(_ id: StepID, timeout: TimeInterval, initialDelay: TimeInterval) async throws {
        set(id, .running, "")
        try await Task.sleep(for: .seconds(initialDelay))
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            try Task.checkCancellation()
            if let list = try? await cfgutil.run("list", timeout: 3, quiet: true), list.devices.contains(ecid) {
                let props = (try? await cfgutil.run("get", ["bootedState", "activationState"], ecid: ecid, timeout: 3, quiet: true))?
                    .properties(for: ecid) ?? [:]
                let booted = JSONCoerce.string(props["bootedState"]) ?? ""
                if booted.isEmpty || booted.caseInsensitiveCompare("Booted") == .orderedSame {
                    // Give MobileDevice a moment to finish pairing after boot.
                    try await Task.sleep(for: .seconds(3))
                    return
                }
                set(id, .running, "")
            }
            try await Task.sleep(for: .seconds(5))
        }
        throw WizardError.message("The iPhone didn't come back. Unlock it, plug it in again, and retry.")
    }

    private func set(_ id: StepID, _ status: Status, _ detail: String) {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].status = status
        steps[index].detail = detail
    }

    enum WizardError: LocalizedError {
        case message(String)
        var errorDescription: String? {
            switch self { case let .message(text): text }
        }
    }
}
