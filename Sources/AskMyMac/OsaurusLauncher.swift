import Foundation

/// Starts the Osaurus server in the background (no window) when it is down.
enum OsaurusLauncher {
    static let cliCandidates = [
        "/Applications/osaurus.app/Contents/Helpers/osaurus",
        NSHomeDirectory() + "/Applications/osaurus.app/Contents/Helpers/osaurus",
        "/opt/homebrew/bin/osaurus",
        "/usr/local/bin/osaurus",
    ]

    static var cliPath: String? {
        cliCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Launches `osaurus serve` detached. Returns false if no CLI was found.
    static func launch() -> Bool {
        guard let cli = cliPath else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            NSLog("AskMyMac: started Osaurus via \(cli) serve")
            return true
        } catch {
            NSLog("AskMyMac: failed to start Osaurus: \(error)")
            return false
        }
    }
}
