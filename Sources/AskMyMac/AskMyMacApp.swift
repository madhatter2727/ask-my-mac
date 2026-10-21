import ServiceManagement
import AppKit
import Darwin
import SwiftUI

// Headless self-tests must finish before SwiftUI builds a window.
@main
enum AskMyMacEntry {
    static func main() {
        if let query = SelfTestArgs.findQuery(CommandLine.arguments) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                fputs("usage: AskMyMac --selftest-find \"<q>\"\n", stderr)
                exit(2)
            }
            HeadlessFind.run(trimmed)
        }
        if let prompt = SelfTestArgs.askPrompt(CommandLine.arguments) {
            let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                fputs("usage: AskMyMac --selftest-ask \"<prompt>\"\n", stderr)
                exit(2)
            }
            HeadlessAsk.run(trimmed)
        }
        switch SelfTestArgs.moveRequest(CommandLine.arguments) {
        case .absent:
            break
        case .incomplete:
            fputs("usage: AskMyMac --selftest-move <srcFile> <destFolder>\n", stderr)
            exit(2)
        case .ready(let source, let destination):
            HeadlessMove.run(source: source, destination: destination)
        }
        if SelfTestArgs.wantsCalendar(CommandLine.arguments) {
            HeadlessCalendar.run()
        }
        AskMyMacApp.main()
    }
}

enum SelfTestArgs {
    /// Query following `--selftest-find`, or nil when that flag is absent.
    /// An empty string means the flag was present without a query.
    static func findQuery(_ arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--selftest-find") else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return "" }
        return arguments[next]
    }

    /// Prompt following `--selftest-ask`, or nil when that flag is absent.
    /// An empty string means the flag was present without a prompt.
    static func askPrompt(_ arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: "--selftest-ask") else { return nil }
        let next = arguments.index(after: index)
        guard next < arguments.endIndex else { return "" }
        return arguments[next]
    }

    enum MoveRequest {
        case absent
        case incomplete
        case ready(String, String)
    }

    static func moveRequest(_ arguments: [String]) -> MoveRequest {
        guard let index = arguments.firstIndex(of: "--selftest-move") else { return .absent }
        let sourceIndex = arguments.index(after: index)
        guard sourceIndex < arguments.endIndex else { return .incomplete }
        let destinationIndex = arguments.index(after: sourceIndex)
        guard destinationIndex < arguments.endIndex else { return .incomplete }
        let source = arguments[sourceIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = arguments[destinationIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        if source.isEmpty || destination.isEmpty { return .incomplete }
        return .ready(source, destination)
    }

    static func wantsCalendar(_ arguments: [String]) -> Bool {
        arguments.contains("--selftest-calendar")
    }
}

enum HeadlessFind {
    static func run(_ query: String) -> Never {
        for path in FileTools.searchFiles(query: query) {
            print(path)
        }
        fflush(stdout)
        exit(0)
    }
}

enum HeadlessCalendar {
    static func run() -> Never {
        Task { @MainActor in
            print(await CalendarTools.selftestText())
            fflush(stdout)
            exit(0)
        }
        RunLoop.main.run()
        exit(1)
    }
}

enum HeadlessAsk {
    static func run(_ prompt: String) -> Never {
        Task { @MainActor in
            let session = ChatSession()
            await session.send(prompt)
            print(session.transcript())
            fflush(stdout)
            exit(session.turnOK ? 0 : 1)
        }
        // Keeps the main actor and URLSession alive without opening a window.
        RunLoop.main.run()
        exit(1)
    }
}

struct AskMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = ChatSession()

    var body: some Scene {
        WindowGroup("Ask My Mac", id: "main") {
            ChatView(session: session)
                .frame(minWidth: 560, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 720, height: 820)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Last Action") {
                    session.undoLast()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!session.canUndo)
            }
        }

        MenuBarExtra("Ask My Mac", systemImage: "bubble.left.and.text.bubble.right") {
            MenuBarChat(session: session)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarChat: View {
    @ObservedObject var session: ChatSession
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            ChatView(session: session)
                .frame(width: 400, height: 500)
            Divider()
            HStack {
                Button("Open full window") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(8)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        NSApp.activate(ignoringOtherApps: true)
        makeMainWindowKey()
        NSLog("AskMyMac: menu bar item installed (bubble.left.and.text.bubble.right)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // SwiftUI inserts the window just after launch. Retry until it can become key.
    private func makeMainWindowKey(attempt: Int = 0) {
        let window = NSApp.mainWindow
            ?? NSApp.windows.first { $0.canBecomeKey && $0.level == .normal }
        if let window {
            window.title = "Ask My Mac"
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard attempt < 8 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.makeMainWindowKey(attempt: attempt + 1)
        }
    }
}
