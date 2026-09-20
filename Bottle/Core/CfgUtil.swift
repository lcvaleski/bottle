import Foundation

/// Result of one cfgutil invocation in `--format JSON` mode.
///
/// cfgutil prints `{"Command":..., "Type":"CommandOutput", "Output":{<ECID>: {...}}, "Devices":[...]}`
/// on success and `{"Type":"Error", "Message":...}` on failure. Per-device
/// failures show up under `"Errors"`.
struct CfgUtilResult {
    let command: String
    let output: [String: Any]
    let devices: [String]
    let errors: [String: String]

    static func empty(command: String) -> CfgUtilResult {
        CfgUtilResult(command: command, output: [:], devices: [], errors: [:])
    }

    func properties(for ecid: String) -> [String: Any] {
        output[ecid] as? [String: Any] ?? [:]
    }
}

enum CfgUtilError: LocalizedError {
    case notInstalled
    case commandFailed(command: String, message: String)
    case deviceError(command: String, ecid: String, message: String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "Apple Configurator is not installed, so cfgutil is unavailable."
        case let .commandFailed(command, message):
            "cfgutil \(command) failed: \(message)"
        case let .deviceError(command, _, message):
            "cfgutil \(command) failed on the device: \(message)"
        }
    }
}

/// Thin wrapper around the `cfgutil` binary that ships inside Apple Configurator.
/// Commands are serialized: cfgutil does not like two instances talking to the
/// same phone at once.
@MainActor
final class CfgUtil {
    static let executableURL = URL(fileURLWithPath: "/Applications/Apple Configurator.app/Contents/MacOS/cfgutil")

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    let log: ActivityLog
    /// Supervision identity passed as `-C/-K` on every call once it exists.
    var identity: SupervisionIdentity?
    private(set) var isBusy = false
    private let lock = AsyncLock()

    init(log: ActivityLog) {
        self.log = log
    }

    /// - Parameters:
    ///   - ecid: Target device. When set, a per-device error with no output throws.
    ///   - timeout: cfgutil's device-detection timeout in seconds.
    ///   - progress: Ask cfgutil to emit progress lines (long commands).
    ///   - quiet: Suppress command/stdout logging (for background polling).
    ///   - workingDirectory: Where cfgutil writes files (get-app-icon saves into cwd).
    @discardableResult
    func run(
        _ command: String,
        _ args: [String] = [],
        ecid: String? = nil,
        timeout: Int = 5,
        progress: Bool = false,
        quiet: Bool = false,
        workingDirectory: URL? = nil
    ) async throws -> CfgUtilResult {
        guard Self.isInstalled else { throw CfgUtilError.notInstalled }

        await lock.acquire()
        isBusy = true
        defer {
            isBusy = false
            lock.release()
        }

        var argv = ["--format", "JSON", "--timeout", String(timeout)]
        if progress { argv.append("--progress") }
        if let identity {
            argv += ["-C", identity.certificateURL.path, "-K", identity.privateKeyURL.path]
        }
        if let ecid { argv += ["-e", ecid] }
        argv.append(command)
        argv += args

        if !quiet { log.command("cfgutil " + Self.redacted(argv).joined(separator: " ")) }

        let log = self.log
        let output = try await ProcessRunner.run(Self.executableURL, arguments: argv, workingDirectory: workingDirectory) { stream, line in
            guard !quiet || stream == .stderr else { return }
            Task { @MainActor in
                log.append(stream == .stdout ? .stdout : .stderr, line)
            }
        }

        let result: CfgUtilResult
        do {
            result = try Self.parse(command: command, output: output)
        } catch {
            log.error(error.localizedDescription)
            throw error
        }

        if let ecid, let message = result.errors[ecid], result.properties(for: ecid).isEmpty {
            let error = CfgUtilError.deviceError(command: command, ecid: ecid, message: message)
            log.error(error.localizedDescription)
            throw error
        }
        return result
    }

    nonisolated private static func redacted(_ argv: [String]) -> [String] {
        var out = argv
        for (index, arg) in argv.enumerated() where arg == "--password" && index + 1 < argv.count {
            out[index + 1] = "••••••"
        }
        return out
    }

    nonisolated static func parse(command: String, output: ProcessRunner.Output) throws -> CfgUtilResult {
        let lines = output.stdout.split(whereSeparator: \.isNewline).map(String.init)

        // The final result is the last JSON object on stdout; --progress lines come before it.
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["Type"] as? String
            else { continue }

            switch type {
            case "Error":
                throw CfgUtilError.commandFailed(command: command, message: object["Message"] as? String ?? line)
            case "CommandOutput":
                var output = object["Output"] as? [String: Any] ?? [:]
                // cfgutil 2.20 nests "Errors" inside "Output" (keyed by ECID, empty dict = fine);
                // accept it at the top level too.
                var errors: [String: String] = [:]
                let rawErrors = (output.removeValue(forKey: "Errors") as? [String: Any])
                    ?? (object["Errors"] as? [String: Any]) ?? [:]
                for (ecid, value) in rawErrors {
                    if let dict = value as? [String: Any] {
                        guard !dict.isEmpty else { continue }
                        errors[ecid] = dict["Message"] as? String ?? dict["Description"] as? String ?? "\(dict)"
                    } else if let text = value as? String, !text.isEmpty {
                        errors[ecid] = text
                    }
                }
                return CfgUtilResult(
                    command: command,
                    output: output,
                    devices: object["Devices"] as? [String] ?? [],
                    errors: errors
                )
            default:
                continue
            }
        }

        if output.status != 0 {
            let stderr = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = !stderr.isEmpty ? stderr : (!stdout.isEmpty ? stdout : "exit code \(output.status)")
            throw CfgUtilError.commandFailed(command: command, message: message)
        }
        return .empty(command: command)
    }
}

/// FIFO mutex for async code on the main actor.
@MainActor
final class AsyncLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            isLocked = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
