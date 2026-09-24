import SwiftUI

struct LogView: View {
    let log: ActivityLog

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Activity Log")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log.fullText, forType: .string)
                }
                Button("Clear") { log.clear() }
            }
            .controlSize(.small)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(log.entries) { entry in
                            Text(entry.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: entry.kind))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: log.entries.count) {
                    if let last = log.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func color(for kind: ActivityLog.Kind) -> Color {
        switch kind {
        case .command: .accentColor
        case .stdout: .primary
        case .stderr: .orange
        case .info: .secondary
        case .error: .red
        }
    }
}
