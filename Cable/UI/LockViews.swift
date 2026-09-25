import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Lock

/// Locking is the one irreversible-feeling thing Cable does, so it gets a
/// deliberate sheet: what changes, how long, who can undo it.
struct LockSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let device: Device
    let restrictions: AppRestrictionsModel

    @State private var delayHours: Double = 24
    @State private var partner = false

    private let delays: [(String, Double)] = [
        ("5 minutes", 5.0 / 60), ("1 hour", 1), ("6 hours", 6),
        ("1 day", 24), ("3 days", 72), ("1 week", 168), ("30 days", 720),
    ]

    var body: some View {
        VStack(spacing: 0) {
            if model.lock.isLocked, let created = model.lock.lastCreated {
                handoff(created)
            } else {
                form
            }
        }
        .frame(width: 540)
    }

    // MARK: Before

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
                Text("Lock it")
                    .font(.title2.weight(.semibold))
                Text("After this, not even this Mac can unblock.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)

            Divider()

            VStack(spacing: 0) {
                row {
                    Text("Wait to unblock")
                    Spacer()
                    Picker("", selection: $delayHours) {
                        ForEach(delays, id: \.1) { Text($0.0).tag($0.1) }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
                Divider().padding(.leading, 24)
                row {
                    Text("Someone can approve sooner")
                    Spacer()
                    Toggle("", isOn: $partner)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                if let error = model.lock.errorMessage {
                    NoticeBanner(tone: .danger, title: error)
                }
                HStack(spacing: 9) {
                    if model.lock.isWorking {
                        ProgressView().controlSize(.small)
                        Text(model.lock.progress ?? "")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .disabled(model.lock.isWorking)
                    Button("Lock") {
                        Task {
                            await model.lock.lock(device: device, restrictions: restrictions,
                                                  delayHours: delayHours, partner: partner)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.lock.isWorking || (restrictions.selected.isEmpty && restrictions.sites.isEmpty))
                }
            }
            .padding(24)
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 12, content: content)
            .padding(.horizontal, 24)
            .padding(.vertical, 13)
    }

    private func handoff(_ created: LockService.Created) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.green)
                Text("\(device.displayName) is locked")
                    .font(.title2.weight(.semibold))
                Text("This page is the only way to unblock.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)

            Divider()

            HStack(alignment: .top, spacing: 18) {
                QRCodeView(text: created.statusUrl)
                    .frame(width: 128, height: 128)
                VStack(alignment: .leading, spacing: 9) {
                    Text("Scan it, then Share → Add to Home Screen.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    CopyableLink(url: created.statusUrl)
                }
            }
            .padding(24)

            if let approver = created.approverUrl {
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    Label("Send to your approver", systemImage: "person.badge.key.fill")
                        .font(.callout.weight(.medium))
                    Text("Shown once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    CopyableLink(url: approver)
                }
                .padding(24)
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
    }
}

// MARK: - Locked

/// What the app shows while the phone is locked. Mostly: how to get out.
struct LockedView: View {
    @Environment(AppModel.self) private var model
    let device: Device?

    var body: some View {
        let lock = model.lock
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let record = lock.record {
                    header(record)
                    stateCard(lock.status, record: record)

                    VStack(alignment: .leading, spacing: 11) {
                        ListSectionHeader(title: "Unblock from the iPhone")
                        HStack(alignment: .top, spacing: 18) {
                            QRCodeView(text: record.statusURL)
                                .frame(width: 118, height: 118)
                            VStack(alignment: .leading, spacing: 9) {
                                Text("The countdown, then the password.")
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                                CopyableLink(url: record.statusURL)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }

                    if let error = lock.errorMessage {
                        NoticeBanner(tone: .warning, title: "Can't reach Cable", actionTitle: "Retry") { Task { await lock.refresh() } }
                    }
                    if lock.isWorking, let progress = lock.progress {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(progress).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await lock.refresh() }
    }

    private func header(_ record: LockRecord) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(record.deviceName) is locked")
                    .font(.largeTitle.weight(.semibold))
                Text("Unblocking takes \(humanDelay(hours: record.delayHours)).")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                Task { await model.lock.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.lock.isWorking)
            .help("Check the lock's status")
        }
    }

    @ViewBuilder
    private func stateCard(_ status: LockService.LockStatus?, record: LockRecord) -> some View {
        let lock = model.lock
        switch status?.state {
        case "unlocking":
            card(tint: .orange) {
                VStack(alignment: .leading, spacing: 11) {
                    Label("Unblocking", systemImage: "hourglass")
                        .font(.headline)
                    if let date = status?.unlockDate {
                        CountdownText(target: date)
                    }
                    Text("You can close this.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("Stay Locked") { Task { await lock.cancelUnlock() } }
                        .disabled(lock.isWorking)
                }
            }
        case "released":
            card(tint: .green) {
                VStack(alignment: .leading, spacing: 11) {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                    Text("Get the password on the iPhone, or finish here.")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 9) {
                        Button("Finish Here") { Task { await lock.finishUnlock(device: device) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(lock.isWorking)
                        if device == nil {
                            Text("Plug in the iPhone to clear it from here too.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        case "locked":
            card(tint: .blue) {
                VStack(alignment: .leading, spacing: 11) {
                    Label("Locked", systemImage: "lock.fill")
                        .font(.headline)
                    Text("Nothing shortens the wait\(record.approverURL == nil ? "." : " except your approver.")")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Start the Wait") { Task { await lock.requestUnlock() } }
                        .disabled(lock.isWorking)
                }
            }
        default:
            card(tint: .secondary) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func card<Content: View>(tint: Color, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.2))
            )
    }
}

// MARK: - Pieces

/// Live countdown. TimelineView drives the tick, so there's no timer to manage.
struct CountdownText: View {
    let target: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(Self.remaining(until: target, from: context.date))
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    static func remaining(until target: Date, from now: Date) -> String {
        let seconds = max(0, Int(target.timeIntervalSince(now)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        if h > 0 { return String(format: "%dh %02dm %02ds", h, m, s) }
        return String(format: "%dm %02ds", m, s)
    }
}

struct CopyableLink: View {
    let url: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(url)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(2)); copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .controlSize(.small)
        }
        .padding(9)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct QRCodeView: View {
    let text: String

    var body: some View {
        Group {
            if let image = Self.image(for: text) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quaternary)
            }
        }
        .padding(7)
        .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.quaternary)
        )
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
