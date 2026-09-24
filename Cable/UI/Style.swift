import SwiftUI

// Shared building blocks so every screen speaks the same visual language.

/// A pill that names the device's current situation in plain words.
struct StatusChip: View {
    enum Kind {
        case ready, locked, notSetUp, needsTrust, active

        var label: String {
            switch self {
            case .ready: "Ready"
            case .locked: "Locked"
            case .notSetUp: "Not set up"
            case .needsTrust: "Tap Trust on iPhone"
            case .active: "Blocking"
            }
        }

        var symbol: String {
            switch self {
            case .ready: "checkmark.circle.fill"
            case .locked: "lock.fill"
            case .notSetUp: "exclamationmark.circle.fill"
            case .needsTrust: "hand.raised.fill"
            case .active: "shield.fill"
            }
        }

        var tint: Color {
            switch self {
            case .ready: .green
            case .locked: .blue
            case .notSetUp: .orange
            case .needsTrust: .red
            case .active: .blue
            }
        }
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbol)
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
            Text(kind.label)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(kind.tint.opacity(0.14), in: Capsule())
        .foregroundStyle(kind.tint)
    }
}

/// An app icon from the phone, with a muted treatment when the app is blocked.
struct AppIconView: View {
    let image: NSImage?
    var side: CGFloat = 32
    var isBlocked = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .saturation(isBlocked ? 0 : 1)
                    .opacity(isBlocked ? 0.55 : 1)
            } else {
                RoundedRectangle(cornerRadius: side * 0.23, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "app.dashed")
                            .font(.system(size: side * 0.42))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: side * 0.23, style: .continuous))
    }
}

/// One app in the grid. Icon-led: the icon is the whole control, and blocking
/// draws a border around it. A name only appears when there's no icon to show,
/// so a tile is never unidentifiable.
struct AppTile: View {
    let image: NSImage?
    let name: String
    let state: AppRestrictionsModel.RowState
    let blocking: Bool
    var side: CGFloat = 72

    private var ring: (color: Color, dashed: Bool)? {
        switch state {
        case .off: nil
        case .on: (blocking ? .red : .green, false)
        case .willTurnOn: (.orange, false)
        case .willTurnOff: (.orange, true)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                AppIconView(image: image, side: side, isBlocked: blocking && state == .on)
                if let ring {
                    RoundedRectangle(cornerRadius: (side + 10) * 0.235, style: .continuous)
                        .strokeBorder(
                            ring.color,
                            style: StrokeStyle(lineWidth: 2.5, dash: ring.dashed ? [4, 3] : [])
                        )
                        .frame(width: side + 10, height: side + 10)
                }
            }
            .frame(width: side + 14, height: side + 14)

            if image == nil {
                Text(name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: side + 14)
            }
        }
        .animation(.snappy(duration: 0.18), value: state)
    }
}

/// State for rows that stay textual (websites), where a tile makes no sense.
struct StateBadge: View {
    let state: AppRestrictionsModel.RowState
    let blocking: Bool

    var body: some View {
        if let (text, color) = label {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .animation(.snappy(duration: 0.18), value: state)
        }
    }

    private var label: (String, Color)? {
        switch state {
        case .off: nil
        case .on: (blocking ? "Blocked" : "Allowed", blocking ? .red : .green)
        case .willTurnOn: (blocking ? "Will block" : "Will allow", .orange)
        case .willTurnOff: ("Will undo", .orange)
        }
    }
}

/// A short, non-alarming notice with an optional action. Used instead of raw
/// error strings wherever the user can actually do something about it.
struct NoticeBanner: View {
    enum Tone { case info, warning, danger, success

        var tint: Color {
            switch self {
            case .info: .accentColor
            case .warning: .orange
            case .danger: .red
            case .success: .green
            }
        }

        var symbol: String {
            switch self {
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .danger: "xmark.octagon.fill"
            case .success: "checkmark.circle.fill"
            }
        }
    }

    let tone: Tone
    let title: String
    var detail: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: tone.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tone.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(tone.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(tone.tint.opacity(0.18))
        )
    }
}

/// Section label in the list. Quieter than the default so app names lead.
struct ListSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .tracking(0.6)
            if let count {
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }
}

extension View {
    /// The window's bottom action bar.
    func bottomBar() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
    }
}
