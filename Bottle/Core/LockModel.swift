import Foundation
import Observation

/// The paid-tier state machine on the Mac side.
///
/// Lock:   create on server → install password-profile → escrow identity → delete local identity.
/// Unlock: the phone (or the approver) drives the server; this Mac just polls, and once
///         released it pulls the identity back and returns to switch mode.
@MainActor
@Observable
final class LockModel {
    enum Step: String { case create, install, escrow, delete }

    private(set) var record: LockRecord?
    private(set) var status: LockService.LockStatus?
    private(set) var isWorking = false
    private(set) var progress: String?
    private(set) var errorMessage: String?
    private(set) var lastCreated: LockService.Created?

    private let service = LockService()
    private let cfgutil: CfgUtil
    private let identityStore: SupervisionIdentityStore
    private var pollTask: Task<Void, Never>?

    init(cfgutil: CfgUtil, identityStore: SupervisionIdentityStore) {
        self.cfgutil = cfgutil
        self.identityStore = identityStore
        record = LockRecord.load()
    }

    var isLocked: Bool { record != nil }

    // MARK: - Lock

    func lock(device: Device, restrictions: AppRestrictionsModel, delayHours: Int, partner: Bool) async {
        guard !isWorking, record == nil else { return }
        guard let identity = identityStore.identity else {
            errorMessage = "No supervision identity on this Mac — nothing to hand over."
            return
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false; progress = nil }

        do {
            progress = "Creating lock…"
            let created = try await service.create(
                delayHours: delayHours, mode: restrictions.mode, apps: Array(restrictions.selected),
                sites: restrictions.sites, partner: partner, organizationName: identity.organizationName
            )

            // Order matters: the phone must have a password-protected (removable) profile
            // BEFORE this Mac loses the ability to manage it.
            progress = "Installing the locked profile on the iPhone…"
            let data = try RestrictionsProfile.data(
                mode: restrictions.mode, bundleIDs: Array(restrictions.selected), sites: restrictions.sites,
                organizationName: identity.organizationName, removalPassword: created.password
            )
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("bottle-lock-\(UUID().uuidString).mobileconfig")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            try await cfgutil.run("install-profile", [url.path], ecid: device.ecid, timeout: 15)

            progress = "Handing the supervision identity to the server…"
            try await service.escrow(id: created.id, token: created.token, identity: try identityStore.export())
            let confirmed = try await service.status(id: created.id, token: created.token, includeIdentity: false)
            guard confirmed.hasIdentity else { throw LockError.message("Server did not confirm it holds the identity; keeping the local copy.") }

            progress = "Removing the identity from this Mac…"
            let newRecord = LockRecord(
                id: created.id, token: created.token, statusURL: created.statusUrl, approverURL: created.approverUrl,
                delayHours: delayHours, createdAt: Date(), deviceUDID: device.udid, deviceName: device.displayName
            )
            try newRecord.save()
            try identityStore.deleteLocal(log: cfgutil.log)
            cfgutil.identity = nil

            record = newRecord
            status = confirmed
            lastCreated = created
            cfgutil.log.info("Locked. Unlock from the iPhone at \(created.statusUrl)")
            startPolling()
        } catch {
            errorMessage = error.localizedDescription
            cfgutil.log.error("Lock failed: \(error.localizedDescription)")
        }
    }

    // MARK: - While locked

    func refresh() async {
        guard let record else { return }
        do {
            status = try await service.status(id: record.id, token: record.token)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestUnlock() async {
        guard let record, !isWorking else { return }
        isWorking = true; defer { isWorking = false }
        do { status = try await service.requestUnlock(id: record.id, token: record.token) }
        catch { errorMessage = error.localizedDescription }
    }

    func cancelUnlock() async {
        guard let record, !isWorking else { return }
        isWorking = true; defer { isWorking = false }
        do { status = try await service.cancelUnlock(id: record.id, token: record.token) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Once released: bring the identity home, take the locked profile off the phone
    /// (if the user hasn't already typed the password), and go back to switch mode.
    func finishUnlock(device: Device?) async {
        guard let record, !isWorking else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false; progress = nil }
        do {
            progress = "Fetching the identity from the server…"
            let released = try await service.status(id: record.id, token: record.token, includeIdentity: true)
            guard released.isReleased, let exported = released.identity else {
                throw LockError.message("The server hasn't released this lock yet.")
            }
            let identity = try identityStore.importExported(exported, log: cfgutil.log)
            cfgutil.identity = identity

            if let device {
                progress = "Removing the locked profile from the iPhone…"
                try? await cfgutil.run("remove-profile", [RestrictionsProfile.identifier], ecid: device.ecid, timeout: 15)
            }

            LockRecord.clear()
            self.record = nil
            status = nil
            stopPolling()
            cfgutil.log.info("Unlocked. Back in switch mode.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startPolling() {
        guard pollTask == nil, record != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    enum LockError: LocalizedError {
        case message(String)
        var errorDescription: String? { switch self { case let .message(m): m } }
    }
}
