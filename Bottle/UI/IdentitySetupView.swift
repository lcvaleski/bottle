import SwiftUI
import AppKit

/// Shown for a phone that is already supervised when Bottle doesn't yet hold a
/// supervision identity (or holds one for a different organization).
struct IdentitySetupView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    var onDone: () -> Void = {}

    @State private var keychainIdentities: [KeychainIdentity] = []
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var p12URL: URL?
    @State private var p12Password = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("This iPhone is already supervised")
                    .font(.title3.weight(.semibold))
                Text("It's managed by **\(device.organizationName ?? "an unknown organization")**. To change its apps, Bottle needs that organization's supervision identity — the certificate and private key Apple Configurator created when the phone was supervised.")

                GroupBox("From Apple Configurator on this Mac") {
                    VStack(alignment: .leading, spacing: 10) {
                        if keychainIdentities.isEmpty {
                            Text("No Apple Configurator organizations found in the keychain.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(keychainIdentities) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.organizationName)
                                        Text(item.label).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if item.organizationName == device.organizationName {
                                        Badge(text: "Matches this iPhone", color: .green)
                                    }
                                    Button("Use") { importKeychain(item) }
                                        .disabled(isWorking)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("From another Mac") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("In Apple Configurator: Settings → Organizations → select the organization → Export Supervision Identity. Then pick the .p12 here.")
                            .font(.callout).foregroundStyle(.secondary)
                        HStack {
                            Button("Choose .p12…") { choosePicker() }
                            Text(p12URL?.lastPathComponent ?? "No file selected")
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Password") {
                            SecureField("Set when exporting", text: $p12Password)
                                .textFieldStyle(.roundedBorder)
                        }
                        Button("Import") { importP12() }
                            .disabled(p12URL == nil || isWorking)
                    }
                    .padding(.vertical, 4)
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if isWorking {
                    ProgressView("Importing…")
                }
                if model.identityStore.identity != nil {
                    Button("Cancel") { onDone() }
                }
            }
            .padding(20)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { keychainIdentities = SupervisionIdentityStore.keychainIdentities() }
    }

    private func importKeychain(_ item: KeychainIdentity) {
        run { try await model.identityStore.importFromKeychain(item, log: model.log) }
    }

    private func importP12() {
        guard let url = p12URL else { return }
        run { try await model.identityStore.importP12(at: url, password: p12Password, log: model.log) }
    }

    private func run(_ work: @escaping () async throws -> SupervisionIdentity) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                let identity = try await work()
                model.adoptIdentity(identity)
                onDone()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func choosePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pkcs12]
        panel.allowsMultipleSelection = false
        panel.message = "Choose the supervision identity exported from Apple Configurator"
        if panel.runModal() == .OK {
            p12URL = panel.url
        }
    }
}
