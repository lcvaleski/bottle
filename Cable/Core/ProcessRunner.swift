import Foundation

/// Runs a subprocess, streaming complete output lines as they arrive and
/// returning the full output once it exits. Cancelling the surrounding Task
/// terminates the process.
enum ProcessRunner {
    struct Output {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    enum Stream { case stdout, stderr }

    static func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        onLine: ((Stream, String) -> Void)? = nil
    ) async throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        var env = ProcessInfo.processInfo.environment
        if let environment {
            env.merge(environment) { _, new in new }
        }
        // cfgutil resolves relative output paths against $PWD rather than the real cwd.
        if let workingDirectory {
            env["PWD"] = workingDirectory.path
        }
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let collector = LineCollector(onLine: onLine)
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.append(handle.availableData, to: .stdout)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            collector.append(handle.availableData, to: .stderr)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    collector.append(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), to: .stdout)
                    collector.append(stderrPipe.fileHandleForReading.readDataToEndOfFile(), to: .stderr)
                    collector.finish()
                    continuation.resume(returning: Output(
                        status: finished.terminationStatus,
                        stdout: collector.text(.stdout),
                        stderr: collector.text(.stderr)
                    ))
                }
                do {
                    try process.run()
                } catch {
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

/// Accumulates pipe data and splits it into lines. Called from the pipes'
/// background reader threads, so everything is behind a lock.
private final class LineCollector {
    private let lock = NSLock()
    private var full: [ProcessRunner.Stream: String] = [.stdout: "", .stderr: ""]
    private var partial: [ProcessRunner.Stream: String] = [.stdout: "", .stderr: ""]
    private let onLine: ((ProcessRunner.Stream, String) -> Void)?

    init(onLine: ((ProcessRunner.Stream, String) -> Void)?) {
        self.onLine = onLine
    }

    func append(_ data: Data, to stream: ProcessRunner.Stream) {
        guard !data.isEmpty else { return }
        let chunk = String(decoding: data, as: UTF8.self)
        var lines: [String] = []

        lock.lock()
        full[stream, default: ""] += chunk
        var buffer = partial[stream, default: ""] + chunk
        while let newline = buffer.firstIndex(of: "\n") {
            lines.append(String(buffer[..<newline]))
            buffer = String(buffer[buffer.index(after: newline)...])
        }
        partial[stream] = buffer
        lock.unlock()

        lines.forEach { onLine?(stream, $0) }
    }

    func finish() {
        lock.lock()
        let remaining = partial
        partial = [.stdout: "", .stderr: ""]
        lock.unlock()
        for (stream, text) in remaining where !text.isEmpty {
            onLine?(stream, text)
        }
    }

    func text(_ stream: ProcessRunner.Stream) -> String {
        lock.lock(); defer { lock.unlock() }
        return full[stream, default: ""]
    }
}
