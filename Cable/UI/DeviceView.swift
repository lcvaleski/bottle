import SwiftUI

/// Routes a connected phone to the right screen: set it up, fix the key, or block things.
struct DeviceView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @State private var showIdentitySetup = false

    var body: some View {
        if let wizard = model.wizard(for: device) {
            SupervisionWizardView(wizard: wizard, device: device)
        } else if device.isPaired == false {
            NotTrustedView(device: device)
        } else if device.isSupervised == true {
            if model.identityStore.identity == nil || showIdentitySetup {
                IdentitySetupView(device: device) { showIdentitySetup = false }
            } else {
                VStack(spacing: 0) {
                    if let identity = model.identityStore.identity,
                       let org = device.organizationName, org != identity.organizationName {
                        NoticeBanner(
                            tone: .warning,
                            title: "This iPhone belongs to “\(org)”, not “\(identity.organizationName)”",
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

/// Nothing works until the phone trusts this Mac, so this is its own screen
/// rather than a disabled button somewhere else.
struct NotTrustedView: View {
    let device: Device

    var body: some View {
        ContentUnavailableView {
            Label("Unlock \(device.displayName)", systemImage: "hand.raised.fill")
        } description: {
            Text("Then tap **Trust** on the iPhone.")
        }
    }
}

/// First run for an unsupervised phone. The erase has to be said out loud, but
/// once — everything else is three icons and a button.
struct SetUpIntroView: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 7) {
                Text("Set up \(device.displayName)")
                    .font(.largeTitle.weight(.semibold))
                Text("Apple makes you erase the iPhone once. Cable puts everything back.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                // One word, because this really hasn't run on many phones yet.
                Text("Experimental")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
            }

            HStack(spacing: 8) {
                StepChip(symbol: "externaldrive.fill", label: "Back up")
                StepArrow()
                StepChip(symbol: "arrow.trianglehead.2.clockwise", label: "Erase")
                StepArrow()
                StepChip(symbol: "checkmark.seal.fill", label: "Restore")
            }

            VStack(spacing: 9) {
                Button {
                    model.startWizard(for: device)
                } label: {
                    Text("Start")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(device.isPaired == false)

                Text(device.isPaired == false
                     ? "Unlock the iPhone and tap Trust."
                     : "About an hour. Keep it plugged in.")
                    .font(.callout)
                    .foregroundStyle(device.isPaired == false ? .red : .secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StepChip: View {
    let symbol: String
    let label: String

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(height: 26)
            Text(label)
                .font(.callout)
        }
        .frame(width: 84)
    }
}

struct StepArrow: View {
    var body: some View {
        Image(systemName: "arrow.right")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.bottom, 20)
    }
}
