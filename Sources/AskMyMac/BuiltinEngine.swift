import AppKit
import Foundation

/// Which brain answers. Raptor runs in Osaurus; Spark and Bonsai run on Ask My Mac's own local servers.
enum Engine: String, CaseIterable, Identifiable {
    case osaurus, spark, bonsai, picker
    var id: String { rawValue }

    var label: String {
        switch self {
        case .osaurus: return "Raptor (Osaurus)"
        case .spark: return "Spark (built-in)"
        case .bonsai: return "Bonsai (built-in)"
        case .picker: return "Model Picker (follows the app)"
        }
    }

    var isBuiltin: Bool { self == .spark || self == .bonsai }

    /// launchd label, start script, port, model id for built-in engines.
    var jobLabel: String { "com.tara.askmymac.\(rawValue)" }
    var script: String { NSHomeDirectory() + "/.askmymac/run-\(rawValue).sh" }
    var port: Int { self == .spark ? 8095 : 8096 }
    var baseURL: String { self == .picker ? "http://127.0.0.1:7777/v1" : "http://127.0.0.1:\(port)/v1" }
    var modelID: String {
        switch self {
        case .osaurus: return ""
        case .picker: return "auto"
        case .spark: return NSHomeDirectory() + "/MLXModels/Spark-X2.5-4B-MLX-4bit"
        case .bonsai: return "bonsai-2-27b"
        }
    }

    /// Extra request fields. Bonsai is a thinking model; skip thinking for snappy replies.
    var extraBody: [String: Any] {
        self == .bonsai ? ["chat_template_kwargs": ["enable_thinking": false]] : [:]
    }
}

/// Starts and stops the built-in model servers with launchd. Never touches Osaurus.
/// Only one built-in server runs at a time so a single big model sits in memory.
enum BuiltinEngine {
    private static var observing = false

    /// Starts `engine`'s server and stops the other built-in one. For Osaurus, stops all built-ins.
    static func select(_ engine: Engine) {
        for other in Engine.allCases where other.isBuiltin && other != engine {
            stop(other)
        }
        if engine.isBuiltin { start(engine) }
    }

    static func start(_ engine: Engine) {
        guard engine.isBuiltin, !isLoaded(engine) else { return }
        guard FileManager.default.isExecutableFile(atPath: engine.script) else {
            NSLog("AskMyMac: missing \(engine.script)")
            return
        }
        launchctl(["submit", "-l", engine.jobLabel, "--", engine.script])
        NSLog("AskMyMac: started \(engine.label)")
    }

    static func stop(_ engine: Engine) {
        guard engine.isBuiltin, isLoaded(engine) else { return }
        launchctl(["remove", engine.jobLabel])
        NSLog("AskMyMac: stopped \(engine.label)")
    }

    static func stopAll() {
        for engine in Engine.allCases where engine.isBuiltin { stop(engine) }
    }

    static func isLoaded(_ engine: Engine) -> Bool {
        launchctl(["list", engine.jobLabel]) == 0
    }

    /// Frees model memory when the app quits (the menu bar app keeps running when the window closes).
    static func stopOnQuit() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { _ in stopAll() }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}
