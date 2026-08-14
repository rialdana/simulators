import Foundation

struct ShellError: LocalizedError {
    let command: String
    let status: Int32
    let stderr: String

    var errorDescription: String? {
        let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "\(command) failed (exit \(status))" : message
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ args: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Drain stderr on its own queue so a chatty process can't
                // fill the pipe buffer and deadlock against our stdout read.
                var errData = Data()
                let errQueue = DispatchQueue(label: "shell.stderr")
                errQueue.async { errData = err.fileHandleForReading.readDataToEndOfFile() }

                let outData = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                errQueue.sync {}

                if process.terminationStatus != 0 {
                    continuation.resume(throwing: ShellError(
                        command: ([path.components(separatedBy: "/").last ?? path] + args).joined(separator: " "),
                        status: process.terminationStatus,
                        stderr: String(data: errData, encoding: .utf8) ?? ""
                    ))
                } else {
                    continuation.resume(returning: String(data: outData, encoding: .utf8) ?? "")
                }
            }
        }
    }

    /// Launch a long-lived process (an emulator) fully detached, so it
    /// survives if this app quits.
    static func runDetached(_ command: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", "nohup \(command) >/dev/null 2>&1 &"]
        try? process.run()
    }
}
