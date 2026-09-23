import SwiftUI

/// The main screen for a phone Bottle can manage: choose what to block, apply it,
/// and — when the user wants it to stick — lock it.
struct BlockListView: View {
    @Bindable var model: AppRestrictionsModel
    let device: Device

    @Environment(AppModel.self) private var appModel
    @State private var tab = Tab.apps
    @State private var showLockSheet = false
    @State private var confirmRemove = false
    @State private var profileToRemove: InstalledProfile?

    private enum Tab: String, CaseIterable, Identifiable {
        case apps, websites
        var id: String { rawValue }
        var title: String { self == .apps ? "Apps" : "Websites" }
        var symbol: String { self == .apps ? "square.grid.2x2" : "globe" }
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            actionBar
        }
        .sheet(isPresented: $showLockSheet) {
            LockSheet(device: device, restrictions: model)
        }
        .task {
            await model.load()
            if Demo.screen == "lock" { showLockSheet = true }
        }
        .confirmationDialog("Unblock everything on this iPhone?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Unblock Everything", role: .destructive) { Task { await model.removeRestrictions() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every app and website Bottle is blocking comes back right away.")
        }
        .confirmationDialog(
            "Remove “\(profileToRemove?.displayName ?? "")”?",
            isPresented: Binding(get: { profileToRemove != nil }, set: { if !$0 { profileToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let profile = profileToRemove { Task { await model.removeProfile(profile) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This block wasn't made by Bottle. Anything it hides comes back.")
        }
    }

    // MARK: - Top controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in
                        Label(t.title, systemImage: t.symbol).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)

                Spacer()

                Picker("", selection: $model.mode) {
                    Text("Block what I pick").tag(RestrictionMode.block)
                    Text("Allow only what I pick").tag(RestrictionMode.allow)
                }
                .labelsHidden()
                .frame(width: 190)
                .help(model.mode.explanation)

                if tab == .apps {
                    SearchField(text: $model.search)
                        .frame(width: 200)
                }
            }

            topNotice
        }
        .padding(16)
    }

    @ViewBuilder
    private var topNotice: some View {
        if let error = model.errorMessage {
            NoticeBanner(tone: .danger, title: "That didn't work", detail: error,
                         actionTitle: "Show Log") { appModel.showLog = true }
        } else if model.isActive && !appModel.lock.isLocked && !model.hasPendingChanges {
            NoticeBanner(
                tone: .info,
                title: "Anyone with this Mac can undo this in one click",
                actionTitle: "Lock…"
            ) { showLockSheet = true }
        } else if model.mode == .allow {
            NoticeBanner(
                tone: .warning,
                title: "Allow-only mode hides everything you don't pick",
                detail: "Phone, Messages and Settings always stay. Pick every app you still want to see."
            )
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.apps.isEmpty && model.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading the apps on \(device.displayName)…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            switch tab {
            case .apps: appList
            case .websites: siteList
            }
        }
    }

    private var appList: some View {
        List {
            if !model.suggestions.isEmpty && model.mode == .block {
                Section {
                    ForEach(model.suggestions) { suggestionRow($0) }
                } header: {
                    HStack {
                        ListSectionHeader(title: "Suggested", count: model.suggestions.count)
                        Spacer()
                        Button("Add All") { model.acceptAllSuggestions() }
                            .controlSize(.small)
                        Button {
                            withAnimation { model.showSuggestions = false }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Hide suggestions")
                    }
                } footer: {
                    Text("The apps people most often block, narrowed to the ones on this iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if !model.chosenApps.isEmpty {
                Section {
                    ForEach(model.chosenApps) { appRow($0) }
                } header: {
                    ListSectionHeader(title: model.mode == .block ? "Blocked" : "Allowed", count: model.chosenApps.count)
                }
            }
            if !model.thirdPartyApps.isEmpty {
                Section {
                    ForEach(model.thirdPartyApps) { appRow($0) }
                } header: {
                    ListSectionHeader(title: model.chosenApps.isEmpty ? "Your apps" : "Everything else", count: model.thirdPartyApps.count)
                }
            }
            if !model.builtInApps.isEmpty {
                Section {
                    ForEach(model.builtInApps) { appRow($0) }
                } header: {
                    ListSectionHeader(title: "Apple apps", count: model.builtInApps.count)
                }
            }
            if !model.otherProfiles.isEmpty {
                Section {
                    ForEach(model.otherProfiles) { profileRow($0) }
                } header: {
                    ListSectionHeader(title: "Blocks not made by Bottle", count: model.otherProfiles.count)
                } footer: {
                    Text("Bottle didn't create these. Take one over to manage it here instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if model.filteredApps.isEmpty && !model.search.isEmpty {
                ContentUnavailableView.search(text: model.search)
            }
        }
        .listStyle(.inset)
        .animation(.snappy(duration: 0.22), value: model.selected)
        .animation(.default, value: model.search)
    }

    private func suggestionRow(_ app: InstalledApp) -> some View {
        Button {
            model.toggle(app.bundleID)
        } label: {
            HStack(spacing: 11) {
                AppIconView(image: model.iconCache.image(for: app.bundleID), side: 32)
                Text(app.name).foregroundStyle(.primary)
                Spacer(minLength: 8)
                Image(systemName: "plus.circle")
                    .font(.system(size: 17))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Add \(app.name) to the block list")
    }

    private func appRow(_ app: InstalledApp) -> some View {
        let state = model.state(of: app.bundleID)
        let blockedElsewhere = model.blockedByOthers[app.bundleID]
        return Button {
            model.toggle(app.bundleID)
        } label: {
            HStack(spacing: 11) {
                AppIconView(image: model.iconCache.image(for: app.bundleID), side: 32,
                            isBlocked: model.mode == .block && (state == .on))
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name)
                        .foregroundStyle(.primary)
                    if let blockedElsewhere {
                        Text("Already blocked by “\(blockedElsewhere)”")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 8)
                BlockToggle(state: state, blockingVerb: model.mode == .block)
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(app.bundleID)
    }

    private func profileRow(_ profile: InstalledProfile) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                Text(profileSummary(profile))
                    .font(.caption)
                    .foregroundStyle(profile.restrictions == nil ? .orange : .secondary)
            }
            Spacer(minLength: 8)
            if profile.restrictions != nil {
                Button("Take Over") { model.adopt(profile) }
                    .controlSize(.small)
                    .help("Add its apps to Bottle's list so one block covers everything")
            }
            Button("Remove") { profileToRemove = profile }
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    private func profileSummary(_ profile: InstalledProfile) -> String {
        guard let r = profile.restrictions else {
            return "Bottle can't read what this blocks"
        }
        let names = r.bundleIDs.map { id in model.apps.first { $0.bundleID == id }?.name ?? id }
        let shown = names.prefix(4).joined(separator: ", ")
        let more = names.count > 4 ? " +\(names.count - 4) more" : ""
        return "\(r.mode == .block ? "Blocks" : "Allows only") \(shown)\(more)"
    }

    // MARK: - Websites

    private var siteList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("instagram.com", text: $model.siteInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.addSite() }
                Button("Add Website") { model.addSite() }
                    .disabled(RestrictionsProfile.normalizeSite(model.siteInput) == nil)
            }
            .padding(16)

            if model.sites.isEmpty {
                ContentUnavailableView {
                    Label("No websites blocked", systemImage: "globe")
                } description: {
                    Text("Add a site and it stops loading in Safari and inside other apps. Blocking a website doesn't block its app — do that under Apps.")
                }
            } else {
                List {
                    Section { ForEach(model.sites, id: \.self) { siteRow($0) } }
                        header: { ListSectionHeader(title: "Blocked websites", count: model.sites.count) }
                }
                .listStyle(.inset)
            }
        }
    }

    private func siteRow(_ host: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "globe")
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            Text(host)
            Spacer(minLength: 8)
            BlockToggle(state: model.siteState(of: host), blockingVerb: model.mode == .block)
            Button {
                model.removeSite(host)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove from the list")
        }
        .padding(.vertical, 3)
    }

    // MARK: - Action bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            statusLine
            Spacer(minLength: 12)

            if model.hasPendingChanges {
                Button("Revert") { model.revert() }
                    .disabled(model.isApplying)
                Button(applyTitle) { Task { await model.apply() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.isApplying || (model.mode == .allow && model.selected.isEmpty && model.sites.isEmpty))
            } else if model.isActive {
                Button("Unblock Everything") { confirmRemove = true }
                    .disabled(model.isApplying)
                Button {
                    showLockSheet = true
                } label: {
                    Label("Lock…", systemImage: "lock.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isApplying)
            } else {
                Button {
                    Task { await model.load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
        .bottomBar()
    }

    private var applyTitle: String {
        let adds = model.pendingAdditions.count + model.pendingSiteAdditions.count
        let removes = model.pendingRemovals.count + model.pendingSiteRemovals.count
        if model.isActive && adds == 0 && removes > 0 { return "Apply · Unblock \(removes)" }
        if !model.isActive { return model.mode == .block ? "Block \(adds) Item\(adds == 1 ? "" : "s")" : "Apply" }
        return "Apply Changes"
    }

    private var pendingSummary: String {
        let adds = model.pendingAdditions.count + model.pendingSiteAdditions.count
        let removes = model.pendingRemovals.count + model.pendingSiteRemovals.count
        var parts: [String] = []
        if adds > 0 { parts.append("\(adds) to \(model.mode == .block ? "block" : "allow")") }
        if removes > 0 { parts.append("\(removes) to undo") }
        return parts.joined(separator: " · ") + " — not on the iPhone yet"
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.isApplying {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Sending to \(device.displayName)…").foregroundStyle(.secondary)
            }
        } else if let status = model.statusMessage, !model.hasPendingChanges {
            Label(status, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .lineLimit(1)
        } else if model.hasPendingChanges {
            Label(pendingSummary, systemImage: "circle.inset.filled")
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if model.isActive {
            let n = model.appliedApps.count + model.appliedSites.count
            Label("\(n) item\(n == 1 ? "" : "s") \(model.appliedMode == .block ? "blocked" : "allowed") on \(device.displayName)",
                  systemImage: "shield.fill")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("Pick what to block, then apply it.")
                .foregroundStyle(.secondary)
        }
    }
}

/// A search field that looks like the rest of the app on macOS 14.
struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.callout)
            TextField("Search apps", text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
