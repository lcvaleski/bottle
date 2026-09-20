import SwiftUI

struct SupervisionWizardView: View {
    @Environment(AppModel.self) private var model
    @Bindable var wizard: SupervisionWizard
    let device: Device
    @State private var confirmErase = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !wizard.hasStarted {
                    preflight
                }
                steps
                controls
            }
            .padding(20)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            "Erase “\(wizard.deviceName)”?",
            isPresented: $confirmErase,
            titleVisibility: .visible
        ) {
            Button("Back Up, Erase, and Supervise", role: .destructive) { wizard.start() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(wizard.skipBackup
                 ? "Everything on the iPhone will be deleted and it will be set up as new."
                 : "The iPhone will be backed up to this Mac, erased, supervised, and restored from that backup.")
        }
    }

    // MARK: - Preflight

    private var preflight: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Before you start") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $wizard.confirmedFindMyOff) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Find My iPhone is turned off")
                            Text("Settings → your name → Find My → Find My iPhone. The erase fails if Activation Lock is on.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $wizard.confirmedTrusted) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("The iPhone is unlocked and trusts this Mac")
                            Text("Keep it unlocked while the backup runs.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $wizard.confirmedErase) {
                        Text("I understand the iPhone will be erased")
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Options") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Organization name") {
                        TextField("Shown on the iPhone as the supervising organization", text: $wizard.organizationName)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.identityStore.identity != nil)
                    }
                    if model.identityStore.identity != nil {
                        Text("A supervision identity already exists on this Mac, so the name is fixed.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    Toggle("Skip backup — set the iPhone up as new", isOn: $wizard.skipBackup)

                    if !wizard.skipBackup {
                        LabeledContent("Backup password") {
                            SecureField("Only if encrypted backups are on", text: $wizard.backupPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        if device.backupWillBeEncrypted == true {
                            Text("This iPhone uses encrypted backups. Enter the password you set in Finder or the restore step will fail.")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Steps

    private var steps: some View {
        GroupBox("Steps") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(wizard.steps) { step in
                    HStack(alignment: .top, spacing: 10) {
                        statusIcon(step.status)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title)
                                .foregroundStyle(step.status == .pending ? .secondary : .primary)
                            if !step.detail.isEmpty {
                                Text(step.detail)
                                    .font(.caption)
                                    .foregroundStyle(step.status == .failed ? .red : .secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    if step.id != SupervisionWizard.StepID.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: SupervisionWizard.Status) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle").foregroundStyle(.tertiary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        HStack {
            if wizard.isComplete {
                Label("Done. Finish Setup Assistant on the iPhone, then manage its apps here.", systemImage: "checkmark.seal")
                    .foregroundStyle(.green)
                Spacer()
                Button("Continue") { model.endWizard(for: wizard.ecid) }
                    .buttonStyle(.borderedProminent)
            } else if wizard.isRunning {
                Text("Don't unplug the iPhone.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { wizard.cancel() }
            } else if wizard.failedStep != nil {
                Text(wizard.failure ?? "Failed")
                    .foregroundStyle(.red)
                    .lineLimit(3)
                Spacer()
                Button("Close") { model.endWizard(for: wizard.ecid) }
                Button("Retry Step") { wizard.retry() }
                    .buttonStyle(.borderedProminent)
            } else {
                Spacer()
                Button("Cancel") { model.endWizard(for: wizard.ecid) }
                Button("Start") { confirmErase = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!wizard.canStart)
            }
        }
    }
}
