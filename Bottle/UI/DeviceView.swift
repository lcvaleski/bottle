import SwiftUI

/// Routes a connected phone to the right screen: set it up, fix the key, or block things.
struct DeviceView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @State private var showIdentitySetup = false

    var body: some View {
        if let wizard = model.wizard(for: device) {
            SupervisionWizardView(wizard: wizard, device: device)
        } else if device.isSupervised == true {
            if model.identityStore.identity == nil || showIdentitySetup {
                IdentitySetupView(device: device) { showIdentitySetup = false }
            } else {
                VStack(spacing: 0) {
                    if let identity = model.identityStore.identity,
                       let org = device.organizationName, org != identity.organizationName {
                        NoticeBanner(
                            tone: .warning,
                            title: "This iPhone answers to a different computer",
                            detail: "It's managed by “\(org)”, but this Mac holds the key for “\(identity.organizationName)”. Changes will probably be refused.",
                            actionTitle: "Fix…"
                        ) { showIdentitySetup = true }
                        .padding([.horizontal, .top], 16)
                    }
                    BlockListView(model: model.restrictions(for: device), device: device)
                }
            }
        } else {
            SetUpIntroView(device: device)
        }
    }
}

/// First run for an unsupervised phone. Explains the erase honestly and up front.
struct SetUpIntroView: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set up \(device.displayName)")
                        .font(.largeTitle.weight(.semibold))
                    Text("Apple only lets a Mac block apps on an iPhone the Mac set up itself. That setup happens during the phone's first-run screens, so the phone has to be erased once. After that, blocking and unblocking take seconds.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 10) {
                    StepCard(number: 1, title: "Bottle backs up your iPhone",
                             detail: "To this Mac, the same way Finder does.",
                             symbol: "externaldrive.fill.badge.timemachine")
                    StepCard(number: 2, title: "Your iPhone erases and restarts",
                             detail: "This is the part Apple requires. It takes a few minutes.",
                             symbol: "arrow.trianglehead.2.clockwise")
                    StepCard(number: 3, title: "Bottle puts everything back",
                             detail: "Apps, photos, messages and settings, from the backup it just made.",
                             symbol: "checkmark.seal.fill")
                }

                NoticeBanner(
                    tone: .warning,
                    title: "Still being tested",
                    detail: "This setup has worked in testing but on few phones so far. If it stops partway, Apple Configurator can finish it — the phone is never left somewhere it can't be recovered from. Make an iCloud backup first anyway."
                )

                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        model.startWizard(for: device)
                    } label: {
                        Text("Get Started")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(device.isPaired == false)

                    if device.isPaired == false {
                        Label("Unlock the iPhone and tap Trust first.", systemImage: "hand.raised.fill")
                            .font(.callout)
                            .foregroundStyle(.red)
                    } else {
                        Text("Set aside about an hour, mostly waiting. Keep the phone plugged in.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StepCard: View {
    let number: Int
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 21))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, height: 20)
                .background(.quaternary, in: Circle())
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
