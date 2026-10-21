import Foundation

/// Small models sometimes emit a tool call as JSON text in `content` instead of `tool_calls`.
enum ToolJSON {
    static func extract(from content: String) -> (text: String, calls: [ToolCall]) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            let found = calls(from: json)
            if !found.isEmpty {
                let leftover = (json as? [String: Any]).flatMap { $0["content"] as? String } ?? ""
                return (leftover.trimmingCharacters(in: .whitespacesAndNewlines), found)
            }
            return (trimmed, [])
        }

        var found: [ToolCall] = []
        var removals: [Range<String.Index>] = []
        for range in objectRanges(in: content) {
            let piece = calls(fromFragment: String(content[range]))
            if piece.isEmpty { continue }
            found.append(contentsOf: piece)
            removals.append(range)
        }
        guard !found.isEmpty else { return (trimmed, []) }
        return (polish(removing(removals, from: content)), found)
    }

    static func call(from dict: [String: Any], fallbackIndex: Int) -> ToolCall? {
        let name: String
        let arguments: Any
        if let function = dict["function"] as? [String: Any], let functionName = string(function["name"]) {
            name = functionName
            arguments = value(function, keys: ["arguments"])
        } else if let plainName = string(dict["name"]) ?? string(dict["tool"]), hasArguments(dict) {
            name = plainName
            arguments = value(dict, keys: ["arguments", "parameters", "args"])
        } else {
            return nil
        }
        guard isToolName(name) else { return nil }
        let id = string(dict["id"]) ?? "call_\(fallbackIndex)_\(UUID().uuidString.prefix(8))"
        return ToolCall(id: id, name: name, arguments: jsonString(arguments))
    }

    private static func calls(from json: Any) -> [ToolCall] {
        if let rows = json as? [Any] {
            return rows.enumerated().compactMap { index, row in
                (row as? [String: Any]).flatMap { call(from: $0, fallbackIndex: index) }
            }
        }
        guard let dict = json as? [String: Any] else { return [] }
        if let nested = dict["tool_calls"] {
            let found = calls(from: nested)
            if !found.isEmpty { return found }
        }
        if let one = call(from: dict, fallbackIndex: 0) { return [one] }
        return []
    }

    private static func calls(fromFragment fragment: String) -> [ToolCall] {
        guard let data = fragment.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        return calls(from: json)
    }

    private static func hasArguments(_ dict: [String: Any]) -> Bool {
        for key in ["arguments", "parameters", "args"] {
            if let item = dict[key], !(item is NSNull) { return true }
        }
        return false
    }

    private static func value(_ dict: [String: Any], keys: [String]) -> Any {
        for key in keys {
            if let item = dict[key], !(item is NSNull) { return item }
        }
        return [String: Any]()
    }

    private static func isToolName(_ name: String) -> Bool {
        guard let first = name.first, first.isLetter || first == "_" else { return false }
        return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
    }

    private static func string(_ raw: Any?) -> String? {
        guard let text = raw as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func jsonString(_ raw: Any) -> String {
        if let text = raw as? String { return text }
        guard JSONSerialization.isValidJSONObject(raw),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private static func objectRanges(in text: String) -> [Range<String.Index>] {
        let chars = Array(text)
        var ranges: [Range<String.Index>] = []
        var index = 0
        while index < chars.count {
            guard chars[index] == "{", let end = endOfObject(chars, from: index) else {
                index += 1
                continue
            }
            let start = text.index(text.startIndex, offsetBy: index)
            let after = text.index(text.startIndex, offsetBy: end + 1)
            ranges.append(start ..< after)
            index = end + 1
        }
        return ranges
    }

    private static func endOfObject(_ chars: [Character], from start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < chars.count {
            let character = chars[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index += 1
        }
        return nil
    }

    private static func removing(_ ranges: [Range<String.Index>], from text: String) -> String {
        var result = text
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result.removeSubrange(range)
        }
        return result
    }

    private static func polish(_ text: String) -> String {
        let markers: Set<String> = ["```", "```json", "```JSON", "<tool_call>", "</tool_call>"]
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            !markers.contains(line.trimmingCharacters(in: .whitespaces))
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
