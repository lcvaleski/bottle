import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Lock sheet (free → locked)

struct LockSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let device: Device
    let restrictions: AppRestrictionsModel

    @State private var delayHours = 24
    @State private var partner = false

    private let delays: [(String, Int)] = [("1 hour", 1), ("6 hours", 6), ("24 hours", 24), ("3 days", 72), ("1 week", 168), ("30 days", 720)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let created = model.lock.lastCreated, model.lock.isLocked {
                done(created)
            } else {
                form
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Lock this iPhone")
                .font(.title2.weight(.semibold))
            Text("Right now this Mac can undo the block any time. Lock hands that ability to the Bottle server: the profile is reinstalled with a password you never see, and this Mac's supervision identity is moved to the server. Unblocking then happens from the iPhone, after a wait.")
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Wait before unblocking") {
                Picker("", selection: $delayHours) {
                    ForEach(delays, id: \.1) { Text($0.0).tag($0.1) }
                }
                .labelsHidden()
                .frame(width: 160)
            }
            Toggle(isOn: $partner) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Someone I choose can approve an early unblock")
                    Text("You'll get a link to send them. Bottle shows it once.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What will be locked").font(.caption.weight(.semibold))
                    Text("\(restrictions.selected.count) app\(restrictions.selected.count == 1 ? "" : "s") \(restrictions.mode == .block ? "blocked" : "allowed")\(restrictions.sites.isEmpty ? "" : ", \(restrictions.sites.count) site\(restrictions.sites.count == 1 ? "" : "s") blocked")")
                    Text("Change the list first if it isn't right — tightening later means unlocking first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !SupervisionIdentityStore.keychainIdentities().isEmpty {
                Label {
                    Text("Apple Configurator on this Mac also holds a supervision identity in your keychain. Bottle only removes its own copy, so Configurator could still manage the phone. Delete the organization in Configurator → Settings → Organizations if you want the lock to bind this Mac too.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "key.fill").foregroundStyle(.orange)
                }
            }

            if let error = model.lock.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled)
            }

            HStack {
                if model.lock.isWorking {
                    ProgressView().controlSize(.small)
                    Text(model.lock.progress ?? "Working…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.disabled(model.lock.isWorking)
                Button("Lock") {
                    Task { await model.lock.lock(device: device, restrictions: restrictions, delayHours: delayHours, partner: partner) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.lock.isWorking || (restrictions.selected.isEmpty && restrictions.sites.isEmpty))
            }
        }
    }

    private func done(_ created: LockService.Created) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Locked", systemImage: "lock.fill").font(.title2.weight(.semibold))
            Text("This Mac can no longer change the iPhone. Put this link on the iPhone — it's where you'll unblock from.")
            LinkRow(title: "Unblock page", url: created.statusUrl)
            if let approver = created.approverUrl {
                LinkRow(title: "Approver link — send it to your person, then close this", url: approver)
                    .foregroundStyle(.orange)
            }
            HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent) }
        }
    }
}

// MARK: - Locked state (replaces the restrictions screen)

struct LockedView: View {
    @Environment(AppModel.self) private var model
    let device: Device?

    var body: some View {
        let lock = model.lock
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let record = lock.record {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                        Text("\(record.deviceName) is locked").font(.title3.weight(.semibold))
                        Spacer()
                        Button { Task { await lock.refresh() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                            .disabled(lock.isWorking)
                    }

                    stateBlock(lock.status, record: record)

                    GroupBox("Unblock from the iPhone") {
                        HStack(alignment: .top, spacing: 16) {
                            QRCodeView(text: record.statusURL).frame(width: 140, height: 140)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Scan with the iPhone camera, then add the page to the Home Screen. It shows the timer and, when it's up, the password.")
                                    .font(.callout)
                                LinkRow(title: "", url: record.statusURL)
                                if let approver = record.approverURL {
                                    Text("An approver link was created when you locked. Bottle doesn't show it again.")
                                        .font(.caption).foregroundStyle(.secondary)
                                    let _ = approver
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if let error = lock.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).textSelection(.enabled)
                    }
                    if lock.isWorking, let progress = lock.progress {
                        HStack { ProgressView().controlSize(.small); Text(progress).foregroundStyle(.secondary) }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await lock.refresh() }
    }

    @ViewBuilder
    private func stateBlock(_ status: LockService.LockStatus?, record: LockRecord) -> some View {
        let lock = model.lock
        switch status?.state {
        case "unlocking":
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Unblock requested").font(.headline)
                    if let date = status?.unlockDate {
                        Text("Password releases \(date, style: .relative) from now (\(date, style: .date) \(date, style: .time)).")
                    }
                    Button("Never mind, keep it locked") { Task { await lock.cancelUnlock() } }
                        .disabled(lock.isWorking)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case "released":
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Released").font(.headline)
                    Text("The iPhone can show the password now. Or finish here: this Mac takes its identity back and removes the locked profile.")
                    Button("Finish unlock on this Mac") { Task { await lock.finishUnlock(device: device) } }
                        .buttonStyle(.borderedProminent)
                        .disabled(lock.isWorking)
                    if device == nil {
                        Text("Plug the iPhone in first if you want the profile removed from here too.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        default:
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Locked").font(.headline)
                    Text("Asking to unblock starts a \(record.delayHours)-hour wait. Nothing — including this Mac — can shorten it\(record.approverURL == nil ? "." : ", except the person you chose.")")
                    Button("Request unblock") { Task { await lock.requestUnlock() } }
                        .disabled(lock.isWorking || status == nil)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Bits

struct LinkRow: View {
    let title: String
    let url: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !title.isEmpty { Text(title).font(.caption.weight(.semibold)) }
            HStack {
                Text(url).font(.system(.caption, design: .monospaced)).textSelection(.enabled).lineLimit(2)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }
                .controlSize(.small)
            }
        }
    }
}

struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.image(for: text) {
            Image(nsImage: image).resizable().interpolation(.none).aspectRatio(1, contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
        }
    }

    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
