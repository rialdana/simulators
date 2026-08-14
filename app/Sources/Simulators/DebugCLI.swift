import Foundation

/// `Simulators --list` prints the detected devices and exits, so the device
/// discovery logic can be verified from a terminal without launching the UI.
enum DebugCLI {
    static func runIfNeeded() {
        debugAndroidIfNeeded()
        checkUpdateIfNeeded()
        guard CommandLine.arguments.contains("--list") else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            let favorites = Favorites.load()
            let devices = await DeviceLoader.loadAll()
            for d in devices {
                let fav = favorites.contains(d.id) ? "★" : "-"
                print("\(d.platform.rawValue)\t\(d.os)\t\(d.name)\t\(d.booted ? "Booted" : "Off")\t\(fav)")
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }

    /// `Simulators --check-update` prints the update status and exits.
    private static func checkUpdateIfNeeded() {
        guard CommandLine.arguments.contains("--check-update") else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let s = try await Updater.check()
                print("repo=\(Updater.repoPath ?? "?") current=\(s.current) latest=\(s.latest) behind=\(s.commitsBehind)")
            } catch {
                print("check failed: \(error.localizedDescription)")
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }

    /// `Simulators --debug-android` traces every step of emulator detection.
    private static func debugAndroidIfNeeded() {
        guard CommandLine.arguments.contains("--debug-android") else { return }
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            print("adb path: \(SDKPaths.adb ?? "NOT FOUND")")
            print("emulator path: \(SDKPaths.emulator ?? "NOT FOUND")")
            if let adb = SDKPaths.adb {
                do {
                    let out = try await Shell.run(adb, ["devices"])
                    print("adb devices raw: \(out.debugDescription)")
                    let serials = out.split(separator: "\n").compactMap { line -> String? in
                        let l = String(line)
                        return l.hasPrefix("emulator-") ? l.components(separatedBy: .whitespaces).first : nil
                    }
                    print("parsed serials: \(serials)")
                    for serial in serials {
                        let raw = try await Shell.run(adb, ["-s", serial, "emu", "avd", "name"])
                        print("avd name raw for \(serial): \(raw.debugDescription)")
                    }
                } catch {
                    print("adb FAILED: \(error)")
                }
            }
            if let emulator = SDKPaths.emulator {
                do {
                    let raw = try await Shell.run(emulator, ["-list-avds"])
                    print("list-avds raw: \(raw.debugDescription)")
                } catch {
                    print("list-avds FAILED: \(error)")
                }
            }
            let android = await DeviceLoader.loadAndroid()
            print("loadAndroid(): \(android.map { "\($0.name)=\($0.booted ? "Booted" : "Off")" })")
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}
