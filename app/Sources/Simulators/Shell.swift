import Foundation

struct ShellError: LocalizedError {
    let command: String
    let status: Int32
    let detail: String

    var errorDescription: String? {
        let message = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "\(command) failed (exit \(status))" : message
    }
}

enum Shell {
    /// Run a command and capture its output.
    ///
    /// Output is read incrementally instead of waiting for pipe EOF: children
    /// that spawn daemons (adb's server, ssh connection sharing) leave the
    /// pipe's write end open after the command itself exits, so EOF may never
    /// arrive. A hard timeout terminates anything that stalls (e.g. a hung
    /// network fetch) so callers always get an answer.
    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 120) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = args
                process.standardInput = FileHandle.nullDevice

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                let lock = NSLock()
                var outData = Data()
                var errData = Data()
                out.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty { handle.readabilityHandler = nil; return }
                    lock.lock(); outData.append(chunk); lock.unlock()
                }
                err.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty { handle.readabilityHandler = nil; return }
                    lock.lock(); errData.append(chunk); lock.unlock()
                }

                do {
                    try process.run()
                } catch {
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                    return
                }

                var timedOut = false
                let killer = DispatchWorkItem {
                    timedOut = true
                    process.terminate()
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                process.waitUntilExit()
                killer.cancel()
                // Give the final buffered chunks a beat to arrive, then stop.
                usleep(100_000)
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil

                lock.lock()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
                lock.unlock()

                let command = ([path.components(separatedBy: "/").last ?? path] + args)
                    .joined(separator: " ")
                if timedOut {
                    continuation.resume(throwing: ShellError(
                        command: command, status: process.terminationStatus,
                        detail: "\(command) timed out after \(Int(timeout))s"
                    ))
                } else if process.terminationStatus != 0 {
                    continuation.resume(throwing: ShellError(
                        command: command, status: process.terminationStatus,
                        detail: stderr.isEmpty ? stdout : stderr
                    ))
                } else {
                    continuation.resume(returning: stdout)
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
