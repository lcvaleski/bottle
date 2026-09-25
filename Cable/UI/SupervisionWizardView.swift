import SwiftUI

/// The erase-and-set-up flow. Two faces: a checklist before it starts, and a
/// progress list once it's running.
struct SupervisionWizardView: View {
    @Environment(AppModel.self) private var model
    @Bindable var wizard: SupervisionWizard
    let device: Device
    @State private var confirmErase = false
    @State private var showOptions = Demo.isOn && Demo.screen(is: "wizard-options")

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
                                 detail: failure, actionTitle: "Log") { model.showLog = true }
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
            Button("Erase and Set Up", role: .destructive) {
                wizard.start()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(wizard.skipBackup
                 ? "Everything on it is deleted. There's no undo."
                 : "Cable backs it up first and puts everything back.")
        }
    }

    private var heading: some View {
        Text(wizard.hasStarted ? "Setting up \(wizard.deviceName)" : "Three checks")
            .font(.largeTitle.weight(.semibold))
    }

    // MARK: Before

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 9) {
            VStack(spacing: 0) {
                CheckRow(isOn: $wizard.confirmedFindMyOff,
                         title: "Find My is off",
                         detail: "Settings → your name → Find My")
                Divider().padding(.leading, 40)
                CheckRow(isOn: $wizard.confirmedTrusted,
                         title: "iPhone is unlocked",
                         detail: "Leave it unlocked")
                Divider().padding(.leading, 40)
                CheckRow(isOn: $wizard.confirmedErase,
                         title: "OK to erase it",
                         detail: wizard.skipBackup ? "Nothing gets restored" : "Cable puts it all back")
            }
            .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
    }

    private var options: some View {
        DisclosureGroup("Options", isExpanded: $showOptions) {
            VStack(spacing: 0) {
                optionRow("Set up as new") {
                    Toggle("", isOn: $wizard.skipBackup)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                if !wizard.skipBackup, device.backupWillBeEncrypted == true {
                    Divider()
                    optionRow("Backup password") {
                        SecureField("", text: $wizard.backupPassword)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                }
                if model.identityStore.identity == nil {
                    Divider()
                    optionRow("Organization") {
                        TextField("", text: $wizard.organizationName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity)
        }
        .font(.callout)
    }

    private func optionRow<Control: View>(_ title: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack {
            Text(title)
            Spacer()
            control()
        }
        .padding(.vertical, 10)
    }

    // MARK: During

    private var progress: some View {
        VStack(alignment: .leading, spacing: 9) {
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
                Label("Done — finish setup on the iPhone", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Continue") { model.endWizard(for: wizard.ecid) }
                    .buttonStyle(.borderedProminent)
            } else if wizard.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Don't unplug it").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Stop", role: .cancel) { wizard.cancel() }
            } else if wizard.failedStep != nil {
                Spacer()
                Button("Close") { model.endWizard(for: wizard.ecid) }
                Button("Retry") { wizard.retry() }
                    .buttonStyle(.borderedProminent)
            } else {
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
