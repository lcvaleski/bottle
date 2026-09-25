import Foundation
import Observation

/// The paid-tier state machine on the Mac side.
///
/// Lock:   create on server → install password-profile → escrow identity → delete local identity.
/// Unlock: the phone (or the approver) drives the server; this Mac just polls, and once
///         released it pulls the key back and this Mac can change things again.
@MainActor
@Observable
final class LockModel {
    enum Step: String { case create, install, escrow, delete }

    private(set) var record: LockRecord?
    private(set) var status: LockService.LockStatus?
    private(set) var isWorking = false
    private(set) var progress: String?
    private(set) var errorMessage: String?
    fileprivate(set) var lastCreated: LockService.Created?

    private let service = LockService()
    private let cfgutil: CfgUtil
    private let identityStore: SupervisionIdentityStore
    private var pollTask: Task<Void, Never>?

    init(cfgutil: CfgUtil, identityStore: SupervisionIdentityStore) {
        self.cfgutil = cfgutil
        self.identityStore = identityStore
        record = LockRecord.load()
        if ["locked", "unlocking", "released", "lock-done"].contains(Demo.screen) {
            let now = Date().timeIntervalSince1970 * 1000
            record = LockRecord(
                id: "demolockid0000000000", token: "demo",
                statusURL: "https://cableblocker.com/l/demolockid0000000000#demo",
                approverURL: Demo.screen == "lock-done" ? "https://cableblocker.com/a/demolockid0000000000#demo" : nil,
                delayHours: 24, createdAt: Date(), deviceUDID: Demo.device.udid, deviceName: Demo.device.displayName
            )
            let state = Demo.screen == "locked" || Demo.screen == "lock-done" ? "locked" : Demo.screen
            status = LockService.LockStatus(
                id: "demolockid0000000000", state: state, delayHours: 24, createdAt: now,
                unlockRequestedAt: state == "locked" ? nil : now,
                unlockAt: state == "unlocking" ? Date().addingTimeInterval(6 * 3600 + 132).timeIntervalSince1970 * 1000 : nil,
                releasedAt: state == "released" ? now : nil,
                hasIdentity: true, hasApprover: Demo.screen == "lock-done", password: nil, identity: nil
            )
            if Demo.screen == "lock-done" {
                lastCreated = LockService.Created(
                    id: "demolockid0000000000", token: "demo", password: "yeeuyyh4xe",
                    statusUrl: record!.statusURL, approverUrl: record!.approverURL
                )
            }
        }
    }

    var isLocked: Bool { record != nil }

    // MARK: - Lock

    func lock(device: Device, restrictions: AppRestrictionsModel, delayHours: Double, partner: Bool) async {
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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("cable-lock-\(UUID().uuidString).mobileconfig")
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
        guard let record, !Demo.isOn else { return }
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
    /// (if the user hasn't already typed the password), and hand control back.
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
            cfgutil.log.info("Unlocked. This Mac can change the block again.")
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
