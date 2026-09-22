import SwiftUI

struct DeviceView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @State private var showIdentitySetup = false

    var body: some View {
        VStack(spacing: 0) {
            DeviceHeaderView(device: device)
            Divider()
            if model.lock.isLocked {
                LockedView(device: device)
            } else if let wizard = model.wizard(for: device) {
                SupervisionWizardView(wizard: wizard, device: device)
            } else if device.isSupervised == true {
                if model.identityStore.identity == nil || showIdentitySetup {
                    IdentitySetupView(device: device) { showIdentitySetup = false }
                } else {
                    if let identity = model.identityStore.identity,
                       let org = device.organizationName, org != identity.organizationName {
                        identityMismatchBanner(identity: identity, phoneOrg: org)
                        Divider()
                    }
                    AppRestrictionsView(model: model.restrictions(for: device), device: device)
                }
            } else {
                SupervisionIntroView(device: device)
            }
        }
    }

    private func identityMismatchBanner(identity: SupervisionIdentity, phoneOrg: String) -> some View {
        HStack {
            Label("Bottle's identity is for “\(identity.organizationName)” but this iPhone is supervised by “\(phoneOrg)”. Changes will probably be refused.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Spacer()
            Button("Change Identity…") { showIdentitySetup = true }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.08))
    }
}

struct DeviceHeaderView: View {
    let device: Device

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: device.family == "iPad" ? "ipad" : "iphone")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.title2.weight(.semibold))
                HStack(spacing: 8) {
                    if let productVersion = device.productVersion { Text("iOS \(productVersion)") }
                    if !device.deviceType.isEmpty { Text(device.deviceType) }
                    if let battery = device.batteryLevel { Text("\(battery)%") }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let supervised = device.isSupervised {
                    Badge(
                        text: supervised ? "Supervised" + (device.organizationName.map { " · \($0)" } ?? "") : "Not supervised",
                        color: supervised ? .green : .orange
                    )
                }
                if device.isPaired == false {
                    Badge(text: "Not trusted — unlock and tap Trust", color: .red)
                }
            }
        }
        .padding(16)
    }
}

struct Badge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct SupervisionIntroView: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Text("This iPhone isn't supervised yet")
                    .font(.title3.weight(.semibold))
                Badge(text: "Experimental", color: .orange)
            }

            Label {
                Text("The supervision wizard hasn't been tested on enough phones yet. If it fails partway, Apple Configurator can finish the job — the phone is never left in a state Configurator can't recover. Keep the activity log (⌘⇧L) open and report what happened.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
            .padding(12)
            .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            Text("Supervision lets Bottle hide or allow-list apps on the phone. Apple only permits it on a freshly erased device, so Bottle will:")

            VStack(alignment: .leading, spacing: 8) {
                bullet("1", "Back up the iPhone to this Mac")
                bullet("2", "Erase it and mark it as supervised")
                bullet("3", "Put the backup back — apps, photos, and settings included")
            }

            Text("Plan for 20–60 minutes depending on how much is on the phone. Keep it plugged in the whole time.")
                .foregroundStyle(.secondary)

            Button("Set Up Supervision…") {
                model.startWizard(for: device)
            }
            .buttonStyle(.borderedProminent)
            .disabled(device.isPaired == false)

            if device.isPaired == false {
                Text("Unlock the iPhone and tap Trust before continuing.")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .frame(width: 20, height: 20)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            Text(text)
        }
    }
}
