import SwiftUI

struct AppRestrictionsView: View {
    @Bindable var model: AppRestrictionsModel
    @State private var confirmRemove = false
    @State private var profileToRemove: InstalledProfile?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.apps.isEmpty && model.isLoading {
                ProgressView("Reading apps from iPhone…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                appList
            }
            Divider()
            footer
        }
        .task { await model.load() }
        .confirmationDialog("Remove all app restrictions?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Restrictions", role: .destructive) {
                Task { await model.removeRestrictions() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove “\(profileToRemove?.displayName ?? "")” from the iPhone?",
            isPresented: Binding(get: { profileToRemove != nil }, set: { if !$0 { profileToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove Profile", role: .destructive) {
                if let profile = profileToRemove { Task { await model.removeProfile(profile) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Anything this profile blocks becomes visible again.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Mode", selection: $model.mode) {
                    ForEach(RestrictionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                Spacer()
                TextField("Search apps", text: $model.search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
            }
            HStack {
                Text(model.mode.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if model.profileInstalled {
                    Badge(text: "Restrictions active", color: .blue)
                }
            }
        }
        .padding(16)
    }

    private var appList: some View {
        List {
            if !model.otherProfiles.isEmpty {
                Section("Other profiles on this iPhone") {
                    ForEach(model.otherProfiles) { profile in profileRow(profile) }
                }
            }
            if !model.builtInApps.isEmpty {
                Section("Apple apps") {
                    ForEach(model.builtInApps) { app in row(app) }
                }
            }
            if !model.thirdPartyApps.isEmpty {
                Section("Installed apps") {
                    ForEach(model.thirdPartyApps) { app in row(app) }
                }
            }
        }
        .listStyle(.inset)
    }

    private func profileRow(_ profile: InstalledProfile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.badge.gearshape")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                Text(profileSummary(profile))
                    .font(.caption)
                    .foregroundStyle(profile.restrictions == nil ? .orange : .secondary)
                Text(profile.identifier)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            if profile.restrictions != nil {
                Button("Add to Bottle") { model.adopt(profile) }
                    .help("Copy this profile's app list into Bottle's selection")
            }
            Button("Remove…") { profileToRemove = profile }
                .disabled(model.isApplying)
        }
        .padding(.vertical, 2)
    }

    private func profileSummary(_ profile: InstalledProfile) -> String {
        guard let r = profile.restrictions else {
            return "Contents unknown — no matching .mobileconfig found on this Mac"
        }
        let names = r.bundleIDs.map { id in model.apps.first { $0.bundleID == id }?.name ?? id }
        let verb = r.mode == .block ? "Blocks" : "Allows only"
        let list = names.prefix(6).joined(separator: ", ") + (names.count > 6 ? ", +\(names.count - 6) more" : "")
        return "\(verb) \(names.count) app\(names.count == 1 ? "" : "s"): \(list)"
    }

    private func row(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            Toggle(isOn: binding(for: app)) {
                HStack(spacing: 10) {
                    AppIconView(image: model.iconCache.image(for: app.bundleID))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(app.name)
                        Text(app.bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            Spacer()
            if let by = model.blockedByOthers[app.bundleID] {
                Badge(text: "Blocked by “\(by)”", color: .red)
            } else if model.profileInstalled && model.selected.contains(app.bundleID) {
                Badge(text: model.mode == .block ? "Blocked" : "Allowed", color: .blue)
            }
        }
    }

    private func binding(for app: InstalledApp) -> Binding<Bool> {
        Binding(
            get: { model.selected.contains(app.bundleID) },
            set: { isOn in
                if isOn { model.selected.insert(app.bundleID) } else { model.selected.remove(app.bundleID) }
            }
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else if let status = model.statusMessage {
                Label(status, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("\(model.selected.count) selected")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await model.load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(model.isLoading || model.isApplying)

            Button("Remove Restrictions") { confirmRemove = true }
                .disabled(!model.profileInstalled || model.isApplying)

            Button("Apply to iPhone") {
                Task { await model.apply() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isApplying || (model.mode == .allow && model.selected.isEmpty))
        }
        .padding(12)
        .background(.bar)
    }
}

struct AppIconView: View {
    let image: NSImage?
    private let side: CGFloat = 30

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "app")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
