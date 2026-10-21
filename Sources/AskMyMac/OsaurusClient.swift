import Foundation

struct ToolDefinition {
    var name: String
    var description: String
    var parameters: [String: Any]

    func jsonObject() -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parameters
            ] as [String: Any]
        ]
    }
}

struct ToolCall {
    var id: String
    var name: String
    var arguments: String

    func jsonObject() -> [String: Any] {
        [
            "id": id,
            "type": "function",
            "function": [
                "name": name,
                "arguments": arguments
            ] as [String: Any]
        ]
    }
}

struct APIMessage {
    var role: String
    var content: String?
    var toolCalls: [ToolCall] = []
    var toolCallID: String?
    var name: String?

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = ["role": role]
        if let content {
            object["content"] = content
        } else if role == "assistant" || role == "tool" {
            // Local servers reject JSON null here. OpenAI accepts an empty string.
            object["content"] = ""
        }
        if !toolCalls.isEmpty {
            object["tool_calls"] = toolCalls.map { $0.jsonObject() }
        }
        if let toolCallID, !toolCallID.isEmpty {
            object["tool_call_id"] = toolCallID
        }
        if let name, !name.isEmpty {
            object["name"] = name
        }
        return object
    }
}

struct ModelReply {
    var content: String
    var toolCalls: [ToolCall]
}

enum OsaurusError: Error {
    case offline
    case timedOut
    case badURL
    case http(Int, String?)
    case unreadable
}

/// OpenAI-compatible client for a local Osaurus server. Non-streaming, 120s timeout.
final class OsaurusClient {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 300
            config.timeoutIntervalForResource = 300
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    func listModels(baseURL: String) async throws -> [String] {
        let data = try await send(url: try endpoint(baseURL, "/models"), method: "GET", body: nil)
        return try Self.modelIDs(from: data)
    }

    func complete(
        baseURL: String,
        model: String,
        messages: [APIMessage],
        tools: [ToolDefinition],
        extra: [String: Any] = [:]
    ) async throws -> ModelReply {
        var payload: [String: Any] = extra
        payload.merge([
            "model": model,
            "messages": messages.map { $0.jsonObject() },
            "stream": false
        ]) { _, new in new }
        if !tools.isEmpty {
            payload["tools"] = tools.map { $0.jsonObject() }
        }
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            throw OsaurusError.unreadable
        }
        let data = try await send(
            url: try endpoint(baseURL, "/chat/completions"),
            method: "POST",
            body: body
        )
        return try Self.reply(from: data)
    }

    private func send(url: URL, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error is CancellationError { throw error }
            if let urlError = error as? URLError, urlError.code == .cancelled { throw error }
            throw Self.mapTransport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw OsaurusError.unreadable }
        guard (200 ... 299).contains(http.statusCode) else {
            throw OsaurusError.http(http.statusCode, Self.serverMessage(data))
        }
        return data
    }

    private func endpoint(_ base: String, _ path: String) throws -> URL {
        var root = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") { root.removeLast() }
        guard let url = URL(string: root + path),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { throw OsaurusError.badURL }
        return url
    }

    private static func mapTransport(_ error: Error) -> OsaurusError {
        guard let urlError = error as? URLError else { return .unreadable }
        if urlError.code == .timedOut { return .timedOut }
        return .offline
    }

    private static func modelIDs(from data: Data) throws -> [String] {
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data) } catch { throw OsaurusError.unreadable }
        let rows: [Any]
        if let root = json as? [String: Any] {
            if let message = serverMessage(in: root), root["data"] == nil {
                throw OsaurusError.http(200, message)
            }
            rows = root["data"] as? [Any] ?? []
        } else if let array = json as? [Any] {
            rows = array
        } else {
            throw OsaurusError.unreadable
        }
        return rows.compactMap { row in
            if let id = row as? String { return id }
            return (row as? [String: Any])?["id"] as? String
        }
    }

    private static func reply(from data: Data) throws -> ModelReply {
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data) } catch { throw OsaurusError.unreadable }
        guard let root = json as? [String: Any] else { throw OsaurusError.unreadable }
        guard let choices = root["choices"] as? [Any],
              let first = choices.first as? [String: Any],
              let message = first["message"] as? [String: Any]
        else {
            if let message = serverMessage(in: root) {
                throw OsaurusError.http(200, message)
            }
            throw OsaurusError.unreadable
        }
        let content = textContent(message["content"])
        let calls = toolCalls(message["tool_calls"])
        return ModelReply(content: content, toolCalls: calls)
    }

    private static func textContent(_ value: Any?) -> String {
        if value is NSNull || value == nil { return "" }
        if let text = value as? String { return text }
        if let parts = value as? [Any] {
            return parts.compactMap { part -> String? in
                if let text = part as? String { return text }
                return (part as? [String: Any])?["text"] as? String
            }.joined()
        }
        return ""
    }

    private static func toolCalls(_ value: Any?) -> [ToolCall] {
        guard let rows = value as? [Any] else { return [] }
        return rows.enumerated().compactMap { index, row in
            (row as? [String: Any]).flatMap { ToolJSON.call(from: $0, fallbackIndex: index) }
        }
    }

    private static func serverMessage(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return serverMessage(in: root)
    }

    private static func serverMessage(in root: [String: Any]) -> String? {
        let raw: String?
        if let error = root["error"] as? [String: Any] {
            raw = error["message"] as? String
        } else if let error = root["error"] as? String {
            raw = error
        } else {
            raw = root["message"] as? String
        }
        guard let raw else { return nil }
        let oneLine = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if oneLine.isEmpty { return nil }
        if oneLine.count <= 180 { return oneLine }
        return String(oneLine.prefix(180))
    }
}
