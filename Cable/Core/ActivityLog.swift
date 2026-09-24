import Foundation
import Observation

/// Everything the app runs and everything cfgutil says, so a user can see
/// (and copy) what happened when something goes sideways.
@MainActor
@Observable
final class ActivityLog {
    enum Kind {
        case command, stdout, stderr, info, error

        var label: String {
            switch self {
            case .command: "$"
            case .stdout: "out"
            case .stderr: "err"
            case .info: "info"
            case .error: "error"
            }
        }
    }

    struct Entry: Identifiable {
        let id = UUID()
        let date = Date()
        let kind: Kind
        let text: String
    }

    private(set) var entries: [Entry] = []

    func append(_ kind: Kind, _ text: String) {
        entries.append(Entry(kind: kind, text: text))
        if entries.count > 4000 {
            entries.removeFirst(entries.count - 3000)
        }
    }

    func command(_ text: String) { append(.command, text) }
    func info(_ text: String) { append(.info, text) }
    func error(_ text: String) { append(.error, text) }
    func clear() { entries.removeAll() }

    var fullText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return entries
            .map { "\(formatter.string(from: $0.date)) [\($0.kind.label)] \($0.text)" }
            .joined(separator: "\n")
    }
}
