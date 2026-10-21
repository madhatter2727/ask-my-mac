import Combine
import Foundation

enum BrainPresence: Equatable {
    case checking
    case ready
    case starting
    case offline

    var text: String {
        switch self {
        case .checking:
            return "Checking Osaurus…"
        case .ready:
            return "Brain ready"
        case .starting:
            return "Starting AI\u{2026}"
        case .offline:
            return "Osaurus offline \u{2013} open Osaurus app"
        }
    }
}

struct ToolOutcome {
    var text: String
    var pending: PendingAction?
    var filePaths: [String] = []

    static func text(_ text: String, paths: [String] = []) -> ToolOutcome {
        ToolOutcome(text: text, pending: nil, filePaths: paths)
    }
}

protocol ToolRegistry {
    var definitions: [ToolDefinition] { get }
    func call(name: String, arguments: String) async -> ToolOutcome
}

struct EmptyToolRegistry: ToolRegistry {
    var definitions: [ToolDefinition] { [] }

    func call(name: String, arguments: String) async -> ToolOutcome {
        .text("Unknown tool \(name). Arguments were not used: \(arguments)")
    }
}

@MainActor
final class ChatSession: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published private(set) var presence: BrainPresence = .checking
    @Published private(set) var isSending = false
    @Published var canUndo = false
    private(set) var turnOK = false
    var consumedLaunchPrompt = false

    let settings: Settings
    private let client: OsaurusClient
    private let registry: any ToolRegistry
    private var activeModel: String
    private let maxRounds = 6

    var statusText: String { presence.text }

    init(
        settings: Settings? = nil,
        client: OsaurusClient = OsaurusClient(),
        registry: any ToolRegistry = FileToolRegistry()
    ) {
        let settings = settings ?? Settings()
        self.settings = settings
        self.client = client
        self.registry = registry
        activeModel = settings.resolvedModel
        canUndo = UndoLog.hasEntries
        BuiltinEngine.stopOnQuit()
    }

    /// Checks Osaurus; if it is down, starts it in the background and waits.
    func refreshBrain(autoStart: Bool = true, announce: Bool = false) async {
        let engine = settings.engine
        if engine.isBuiltin {
            // Built-in engines never start Osaurus. Loading Bonsai can take a minute or two.
            BuiltinEngine.select(engine)
            await probeBrain()
            guard presence == .offline, autoStart else { return }
            presence = .starting
            if announce { messages.append(ChatMessage(role: .assistant, text: "Loading \(engine.label)\u{2026}")) }
            for _ in 0 ..< 240 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await probeBrain()
                if presence == .ready { return }
                presence = .starting
            }
            presence = .offline
            return
        }
        // Built-ins are unloaded when the picker leaves them or the app quits, not here,
        // so a background refresh never kills a model that is still loading.
        await probeBrain()
        guard presence == .offline, autoStart else { return }
        presence = .starting
        if announce { messages.append(ChatMessage(role: .assistant, text: "Starting AI\u{2026}")) }
        if settings.engine == .picker {
            // The Model Picker helper (LaunchAgent) owns port 7777; ask launchd to start it if it is down.
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            p.arguments = ["kickstart", "gui/\(getuid())/com.tara.modelpicker.proxy"]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
        } else if !OsaurusLauncher.launch() { presence = .offline; return }
        for _ in 0 ..< 60 {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await probeBrain()
            if presence == .ready { return }
            presence = .starting
        }
        presence = .offline
    }

    private func probeBrain() async {
        let preferred = settings.resolvedModel
        activeModel = preferred
        do {
            let models = try await client.listModels(baseURL: settings.resolvedBaseURL)
            if !models.isEmpty && !models.contains(preferred) {
                activeModel = models[0]
            }
            presence = .ready
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            activeModel = preferred
            presence = .offline
        }
    }

    func send(_ text: String) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        turnOK = false
        messages.append(ChatMessage(role: .user, text: content))

        if let route = PreRouter.match(content) {
            messages.append(await PreRouter.perform(route))
            turnOK = true
            return
        }

        await refreshBrain(announce: true)
        guard presence == .ready else {
            messages.append(ChatMessage(role: .assistant, text: BrainPresence.offline.text))
            return
        }

        var api = [APIMessage(role: "system", content: systemPrompt())]
        api.append(contentsOf: historyMessages())

        for _ in 0 ..< maxRounds {
            let reply: ModelReply
            do {
                reply = try await client.complete(
                    baseURL: settings.resolvedBaseURL,
                    model: activeModel,
                    messages: api,
                    tools: registry.definitions,
                    extra: settings.engine.extraBody
                )
            } catch is CancellationError {
                return
            } catch let urlError as URLError where urlError.code == .cancelled {
                return
            } catch OsaurusError.http(502, _) where settings.engine.isBuiltin {
                // vMLX answers 502 when the model calls a tool that doesn't exist. Retry once as plain chat.
                do {
                    reply = try await client.complete(
                        baseURL: settings.resolvedBaseURL,
                        model: activeModel,
                        messages: api,
                        tools: [],
                        extra: settings.engine.extraBody
                    )
                } catch {
                    messages.append(ChatMessage(role: .assistant, text: Self.explain(error)))
                    return
                }
            } catch {
                if Self.isOffline(error) { presence = .offline }
                messages.append(ChatMessage(role: .assistant, text: Self.explain(error)))
                return
            }

            let resolved = resolve(reply)
            if resolved.calls.isEmpty {
                let answer = resolved.text
                messages.append(ChatMessage(
                    role: .assistant,
                    text: answer.isEmpty ? "The AI returned an empty reply." : answer
                ))
                turnOK = !answer.isEmpty
                return
            }

            api.append(APIMessage(
                role: "assistant",
                content: resolved.text.isEmpty ? nil : resolved.text,
                toolCalls: resolved.calls
            ))
            for call in resolved.calls {
                let outcome = await registry.call(name: call.name, arguments: call.arguments)
                let paths = outcome.filePaths.isEmpty
                    ? Self.searchPaths(tool: call.name, output: outcome.text)
                    : outcome.filePaths
                messages.append(ChatMessage(
                    role: .assistant,
                    text: "",
                    toolNames: [call.name],
                    filePaths: paths,
                    pending: outcome.pending
                ))
                api.append(APIMessage(
                    role: "tool",
                    content: outcome.text,
                    toolCallID: call.id
                ))
            }
        }

        messages.append(ChatMessage(
            role: .assistant,
            text: "I stopped after several tool steps without a final answer."
        ))
        turnOK = true
    }

    func transcript() -> String {
        messages.compactMap { message in
            guard let body = Self.historyText(message) else { return nil }
            return "\(message.role.rawValue): \(body)"
        }.joined(separator: "\n")
    }

    private func historyMessages() -> [APIMessage] {
        messages.compactMap { message in
            guard let body = Self.historyText(message) else { return nil }
            return APIMessage(role: message.role.rawValue, content: body)
        }
    }

    /// Visible prose, plus search paths so a later turn can refer to them.
    private static func historyText(_ message: ChatMessage) -> String? {
        var text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pending = message.pending {
            let card: String
            if pending.phase == .pending {
                card = pending.previewText
            } else if let result = pending.resultText, !result.isEmpty {
                card = pending.title + "\n" + result
            } else {
                card = pending.previewText
            }
            text = text.isEmpty ? card : text + "\n" + card
        }
        if !message.filePaths.isEmpty {
            let list = "Search results:\n" + message.filePaths.joined(separator: "\n")
            text = text.isEmpty ? list : text + "\n" + list
        }
        return text.isEmpty ? nil : text
    }

    private static func searchPaths(tool: String, output: String) -> [String] {
        guard tool == "search_files" else { return [] }
        var seen = Set<String>()
        var paths: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let path = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard path.hasPrefix("/") else { continue }
            if seen.insert(path).inserted { paths.append(path) }
        }
        return paths
    }

    private func resolve(_ reply: ModelReply) -> (text: String, calls: [ToolCall]) {
        var text = reply.content.trimmingCharacters(in: .whitespacesAndNewlines)
        var calls = reply.toolCalls
        if calls.isEmpty, !text.isEmpty {
            let parsed = ToolJSON.extract(from: text)
            text = parsed.text
            calls = parsed.calls
        }
        return (text, unique(calls))
    }

    private func unique(_ calls: [ToolCall]) -> [ToolCall] {
        var seen = Set<String>()
        return calls.enumerated().map { index, call in
            var call = call
            if call.id.isEmpty || seen.contains(call.id) {
                call.id = "call_\(index)_\(UUID().uuidString.prefix(8))"
            }
            seen.insert(call.id)
            if call.arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                call.arguments = "{}"
            }
            return call
        }
    }

    private func systemPrompt() -> String {
        let now = Date().formatted(date: .complete, time: .shortened)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return """
        You are Ask My Mac, a private assistant on this Mac. Do not send anything to the cloud.

        Now: \(now). Home folder: \(home).

        Use tools for files, folders, the calendar, and reminders. Do not invent paths, file contents, or events. If a tool fails, say so in plain language. Keep replies short.
        Pass calendar_events start and end as ISO 8601 local times, like 2026-10-14T15:00:00.
        move_items, rename_item, copy_items, create_folder, trash_items, and create_calendar_event only prepare a preview. Nothing changes until the user approves the card. Never say a file was changed or an event was added before that.
        """
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let error = error as? OsaurusError else { return false }
        if case .offline = error { return true }
        if case .badURL = error { return true }
        return false
    }

    private static func explain(_ error: Error) -> String {
        guard let error = error as? OsaurusError else { return BrainPresence.offline.text }
        switch error {
        case .offline, .badURL:
            return BrainPresence.offline.text
        case .timedOut:
            return "Osaurus took too long to answer. Try again."
        case .http(let code, let message):
            if let message, !message.isEmpty {
                return "The AI couldn't answer (HTTP \(code)): \(message)"
            }
            return "The AI couldn't answer (HTTP \(code))."
        case .unreadable:
            return "Osaurus sent a reply I couldn't read."
        }
    }
}
