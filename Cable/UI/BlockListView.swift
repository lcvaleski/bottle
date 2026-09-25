import SwiftUI

/// The main screen for a phone Cable can manage: choose what to block, apply it,
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
            if Demo.isOn {
                if Demo.screen(is: "lock") || Demo.screen(is: "lock-done") { showLockSheet = true }
                if Demo.isSites { tab = .websites }
            }
        }
        .confirmationDialog("Unblock everything on this iPhone?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Unblock Everything", role: .destructive) { Task { await model.removeRestrictions() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything comes back.")
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
            Text("Anything it hides comes back.")
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
                .frame(width: 170)

                Spacer()

                if tab == .apps {
                    SearchField(text: $model.search)
                        .frame(minWidth: 130, maxWidth: 200)
                }
            }

            topNotice
        }
        .padding(16)
    }

    @ViewBuilder
    private var topNotice: some View {
        if let error = model.errorMessage {
            NoticeBanner(tone: .danger, title: error, actionTitle: "Log") { appModel.showLog = true }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.apps.isEmpty && model.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Reading apps…")
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

    /// Icons in rows rather than a vertical list of names: recognising an app
    /// by its icon is faster than reading it, and it uses the width.
    private var appList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !model.suggestions.isEmpty && model.mode == .block {
                    gridSection(
                        title: "Suggested",
                        count: model.suggestions.count,
                        apps: model.suggestions
                    ) {
                        HStack(spacing: 6) {
                            Button("Block All") { model.acceptAllSuggestions() }
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
                    }
                }
                if !model.chosenApps.isEmpty {
                    gridSection(
                        title: model.mode == .block ? "Blocked" : "Allowed",
                        count: model.chosenApps.count,
                        apps: model.chosenApps
                    )
                }
                if !model.thirdPartyApps.isEmpty {
                    gridSection(
                        title: "Your apps",
                        count: model.thirdPartyApps.count,
                        apps: model.thirdPartyApps
                    )
                }
                if !model.builtInApps.isEmpty {
                    gridSection(title: "Apple apps", count: model.builtInApps.count, apps: model.builtInApps)
                }
                if model.filteredApps.isEmpty && !model.search.isEmpty {
                    ContentUnavailableView.search(text: model.search)
                        .frame(maxWidth: .infinity)
                }
                if !model.otherProfiles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ListSectionHeader(title: "Not from Cable", count: model.otherProfiles.count)
                        ForEach(model.otherProfiles) { profileRow($0) }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .animation(.snappy(duration: 0.22), value: model.selected)
        .animation(.default, value: model.search)
    }

    private func gridSection<Accessory: View>(
        title: String,
        count: Int,
        apps: [InstalledApp],
        @ViewBuilder accessory: () -> Accessory = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ListSectionHeader(title: title, count: count)
                Spacer()
                accessory()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], alignment: .leading, spacing: 16) {
                ForEach(apps) { appTile($0) }
            }
        }
    }

    private func appTile(_ app: InstalledApp) -> some View {
        let state = model.state(of: app.bundleID)
        let blockedElsewhere = model.blockedByOthers[app.bundleID]
        return Button {
            model.toggle(app.bundleID)
        } label: {
            AppTile(image: model.iconCache.image(for: app.bundleID), name: app.name, state: state)
        }
        .buttonStyle(.plain)
        .help(blockedElsewhere.map { "\(app.name) — already blocked by “\($0)”" } ?? app.name)
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
                    .help("Add its apps to Cable's list so one block covers everything")
            }
            Button("Remove") { profileToRemove = profile }
                .controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    private func profileSummary(_ profile: InstalledProfile) -> String {
        guard let r = profile.restrictions else {
            return "Contents unknown"
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
                Button("Block") { model.addSite() }
                    .disabled(RestrictionsProfile.normalizeSite(model.siteInput) == nil)
            }
            .padding(16)
            Divider()

            if model.sites.isEmpty {
                ContentUnavailableView {
                    Label("No websites blocked", systemImage: "globe")
                } description: {
                    Text("Blocked in Safari and in apps.")
                }
            } else {
                List {
                    ForEach(model.sites, id: \.self) { siteRow($0) }
                }
                .listStyle(.inset)
            }
        }
    }

    private func siteRow(_ host: String) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "lock.fill")
                .font(.system(size: 13))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 32)
            Text(host)
            Spacer(minLength: 8)
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

            Menu {
                Button("Refresh") { Task { await model.load() } }
                Divider()
                Button("Unblock Everything…", role: .destructive) { confirmRemove = true }
                    .disabled(!model.isActive)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            if !appModel.lock.isLocked {
                Button {
                    showLockSheet = true
                } label: {
                    Label("Lock…", systemImage: "lock.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.selected.isEmpty && model.sites.isEmpty)
            }
        }
        .bottomBar()
    }

    @ViewBuilder
    private var statusLine: some View {
        if model.isApplying {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Saving…").foregroundStyle(.secondary)
            }
        } else if model.isActive {
            Label(blockedSummary, systemImage: "lock.fill")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text("Click an app to block it.")
                .foregroundStyle(.secondary)
        }
    }

    private var blockedSummary: String {
        var parts: [String] = []
        let apps = model.blockedAppCount, sites = model.blockedSiteCount
        if apps > 0 { parts.append("\(apps) app\(apps == 1 ? "" : "s")") }
        if sites > 0 { parts.append("\(sites) site\(sites == 1 ? "" : "s")") }
        return parts.isEmpty ? "Nothing blocked" : parts.joined(separator: " · ") + " blocked"
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
