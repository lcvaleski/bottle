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

/// The trailing control on an app or site row. Reads as a state, not a checkbox:
/// filled when live, outlined-with-tint when the change is still pending.
struct BlockToggle: View {
    let state: AppRestrictionsModel.RowState
    let blockingVerb: Bool   // true = "Blocked", false = "Allowed" (allow-list mode)

    var body: some View {
        HStack(spacing: 7) {
            if let caption {
                Text(caption)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
            }
            Image(systemName: symbol)
                .font(.system(size: 17))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(state == .off ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.snappy(duration: 0.18), value: state)
    }

    private var caption: String? {
        switch state {
        case .off: nil
        case .on: blockingVerb ? "Blocked" : "Allowed"
        case .willTurnOn: blockingVerb ? "Will block" : "Will allow"
        case .willTurnOff: "Will undo"
        }
    }

    private var symbol: String {
        switch state {
        case .off: "circle"
        case .on: blockingVerb ? "slash.circle.fill" : "checkmark.circle.fill"
        case .willTurnOn: "circle.inset.filled"
        case .willTurnOff: "circle.dashed"
        }
    }

    private var tint: Color {
        switch state {
        case .off: .secondary
        case .on: blockingVerb ? .red : .green
        case .willTurnOn, .willTurnOff: .orange
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
