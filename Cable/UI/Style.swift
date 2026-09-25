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

/// One app in the grid. Icon-led, with its name underneath so a wall of icons
/// is still scannable. Blocked reads as settled — dimmed with a small lock —
/// not as an error; red is kept for things that actually went wrong.
struct AppTile: View {
    let image: NSImage?
    let name: String
    let state: AppRestrictionsModel.RowState
    var side: CGFloat = 60

    private var isBlocked: Bool { state == .on }

    var body: some View {
        VStack(spacing: 5) {
            ZStack(alignment: .bottomTrailing) {
                AppIconView(image: image, side: side, isBlocked: isBlocked)
                    .opacity(isBlocked ? 0.45 : 1)
                if isBlocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(.secondary))
                        .overlay(Circle().strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
                        .offset(x: 3, y: 3)
                }
            }
            .frame(width: side, height: side)

            Text(name)
                .font(.caption2)
                .foregroundStyle(isBlocked ? .tertiary : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: side + 18)
        }
        .animation(.snappy(duration: 0.18), value: state)
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
