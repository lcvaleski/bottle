import SwiftUI
import AppKit

/// Shown when the phone is already managed but this Mac doesn't hold the key.
/// Deliberately avoids the words "certificate" and "supervision identity" —
/// what matters is which computer is allowed to change the phone.
struct IdentitySetupView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    var onDone: () -> Void = {}

    @State private var candidates: [KeychainIdentity] = []
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var fileURL: URL?
    @State private var password = ""
    @State private var showFileImport = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 7) {
                Text("Allow Cable to manage \(device.displayName)")
                    .font(.largeTitle.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let org = device.organizationName {
                    Text("It was set up by \(org).")
                        .foregroundStyle(.secondary)
                }
            }

            if candidates.isEmpty {
                NoticeBanner(
                    tone: .warning,
                    title: "Nothing on this Mac can manage it",
                    detail: "Open the Mac that set it up, then bring the file over."
                )
                .frame(maxWidth: 420)
            } else {
                VStack(spacing: 8) {
                    ForEach(candidates) { candidateRow($0) }
                }
                .frame(maxWidth: 420)
            }

            if isWorking {
                ProgressView().controlSize(.small)
            }
            if let errorMessage {
                NoticeBanner(tone: .danger, title: errorMessage, actionTitle: "Log") { model.showLog = true }
                    .frame(maxWidth: 420)
            }

            DisclosureGroup("Set up on another Mac?") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("There: Apple Configurator → Settings → Organizations → Export Supervision Identity.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 9) {
                        Button("Choose File…") { showFileImport = true }
                        Text(fileURL?.lastPathComponent ?? "")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 9) {
                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 200)
                        Button("Open") { importFile() }
                            .disabled(fileURL == nil || isWorking)
                    }
                }
                .padding(.top, 8)
            }
            .font(.callout)
            .frame(maxWidth: 420)

            if model.identityStore.identity != nil {
                Button("Cancel") { onDone() }
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { candidates = SupervisionIdentityStore.keychainIdentities() }
        .fileImporter(isPresented: $showFileImport, allowedContentTypes: [.pkcs12]) { result in
            if case let .success(url) = result { fileURL = url }
        }
    }

    private func candidateRow(_ item: KeychainIdentity) -> some View {
        let matches = item.organizationName == device.organizationName
        return HStack(spacing: 11) {
            Image(systemName: "key.fill")
                .font(.system(size: 19))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(matches ? .green : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.organizationName).fontWeight(.medium)
                if !matches {
                    Text("A different iPhone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Button("Use") { useKeychain(item) }
                .buttonStyle(matches ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
                .disabled(isWorking)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (matches ? Color.green.opacity(0.07) : Color.secondary.opacity(0.06)),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(matches ? Color.green.opacity(0.25) : Color.secondary.opacity(0.14))
        )
    }

    private func useKeychain(_ item: KeychainIdentity) {
        run { try await model.identityStore.importFromKeychain(item, log: model.log) }
    }

    private func importFile() {
        guard let url = fileURL else { return }
        run { try await model.identityStore.importP12(at: url, password: password, log: model.log) }
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
}

/// Lets a conditional pick between two button styles.
struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        make = { config in AnyView(Button(config).buttonStyle(style)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}
