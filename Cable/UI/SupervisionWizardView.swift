import SwiftUI

/// The erase-and-set-up flow. Two faces: a checklist before it starts, and a
/// progress list once it's running.
struct SupervisionWizardView: View {
    @Environment(AppModel.self) private var model
    @Bindable var wizard: SupervisionWizard
    let device: Device
    @State private var confirmErase = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heading
                if wizard.hasStarted {
                    progress
                } else {
                    checklist
                    options
                }
                if let failure = wizard.failure, wizard.failedStep != nil {
                    NoticeBanner(tone: .danger, title: "Stopped at “\(wizard.failedStep?.title ?? "")”",
                                 detail: failure, actionTitle: "Show Log") { model.showLog = true }
                }
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom) { controls }
        .confirmationDialog(
            wizard.skipBackup ? "Erase \(wizard.deviceName) without a backup?" : "Back up and erase \(wizard.deviceName)?",
            isPresented: $confirmErase,
            titleVisibility: .visible
        ) {
            Button(wizard.skipBackup ? "Erase and Set Up" : "Back Up, Erase, and Set Up", role: .destructive) {
                wizard.start()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(wizard.skipBackup
                 ? "Everything on the iPhone is deleted and it starts fresh. There's no undo."
                 : "Cable copies the iPhone to this Mac, erases it, sets it up, and puts everything back. Keep it plugged in the whole time.")
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(wizard.hasStarted ? "Setting up \(wizard.deviceName)" : "Ready when you are")
                .font(.largeTitle.weight(.semibold))
            Text(wizard.hasStarted
                 ? "Leave the iPhone plugged in. It will restart on its own — that's expected."
                 : "Three quick checks, then Cable takes over for about an hour.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Before

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 9) {
            ListSectionHeader(title: "Check these first")
            VStack(spacing: 0) {
                CheckRow(isOn: $wizard.confirmedFindMyOff,
                         title: "Find My iPhone is off",
                         detail: "Settings → your name → Find My → Find My iPhone. The erase fails if it's on.")
                Divider().padding(.leading, 40)
                CheckRow(isOn: $wizard.confirmedTrusted,
                         title: "The iPhone is unlocked and trusts this Mac",
                         detail: "Keep it unlocked while the backup runs.")
                Divider().padding(.leading, 40)
                CheckRow(isOn: $wizard.confirmedErase,
                         title: "I know the iPhone will be erased",
                         detail: wizard.skipBackup ? "Nothing will be restored afterwards." : "Cable restores it from the backup it makes first.")
            }
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 9) {
            ListSectionHeader(title: "Options")
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Organization name")
                        Text("The iPhone shows this in Settings as the organization managing it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("", text: $wizard.organizationName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 170)
                        .disabled(model.identityStore.identity != nil)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider().padding(.leading, 14)

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start fresh instead of restoring")
                        Text("Skips the backup. Use this for a spare or a kid's phone.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $wizard.skipBackup)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                if !wizard.skipBackup {
                    Divider().padding(.leading, 14)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Backup password")
                            Text(device.backupWillBeEncrypted == true
                                 ? "This iPhone uses encrypted backups — the password is required."
                                 : "Only needed if you turned on encrypted backups in Finder.")
                                .font(.caption)
                                .foregroundStyle(device.backupWillBeEncrypted == true ? .orange : .secondary)
                        }
                        Spacer()
                        SecureField("", text: $wizard.backupPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 170)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    // MARK: During

    private var progress: some View {
        VStack(alignment: .leading, spacing: 9) {
            ListSectionHeader(title: "Progress")
            VStack(spacing: 0) {
                ForEach(Array(wizard.steps.enumerated()), id: \.element.id) { index, step in
                    StepRow(step: step)
                    if index < wizard.steps.count - 1 {
                        Divider().padding(.leading, 42)
                    }
                }
            }
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 12) {
            if wizard.isComplete {
                Label("Done — finish the setup screens on the iPhone", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Start Blocking") { model.endWizard(for: wizard.ecid) }
                    .buttonStyle(.borderedProminent)
            } else if wizard.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Don't unplug the iPhone").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop", role: .cancel) { wizard.cancel() }
            } else if wizard.failedStep != nil {
                Spacer()
                Button("Close") { model.endWizard(for: wizard.ecid) }
                Button("Try That Step Again") { wizard.retry() }
                    .buttonStyle(.borderedProminent)
            } else {
                Text(wizard.canStart ? "About an hour, mostly waiting." : "Tick all three checks to continue.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.endWizard(for: wizard.ecid) }
                Button("Begin") { confirmErase = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!wizard.canStart)
            }
        }
        .bottomBar()
    }
}

struct CheckRow: View {
    @Binding var isOn: Bool
    let title: String
    let detail: String

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isOn ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.18), value: isOn)
    }
}

struct StepRow: View {
    let step: SupervisionWizard.Step

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            icon
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title)
                    .foregroundStyle(step.status == .pending ? .secondary : .primary)
                    .fontWeight(step.status == .running ? .medium : .regular)
                if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.callout)
                        .foregroundStyle(step.status == .failed ? .red : .secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var icon: some View {
        switch step.status {
        case .pending:
            Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical).foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .symbolRenderingMode(.hierarchical).foregroundStyle(.red)
        }
    }
}
