import Foundation

/// OpenAI function schemas for the read-only file tools, plus dispatch.
struct FileToolRegistry: ToolRegistry {
    var definitions: [ToolDefinition] {
        Self.all + ChangeTools.definitions + CalendarTools.definitions
    }

    func call(name: String, arguments: String) async -> ToolOutcome {
        if ChangeTools.names.contains(name) {
            return await ChangeTools.perform(name: name, arguments: arguments)
        }
        if CalendarTools.names.contains(name) {
            return await CalendarTools.perform(name: name, arguments: arguments)
        }
        return .text(await readOnly(name: name, arguments: arguments))
    }

    private func readOnly(name: String, arguments: String) async -> String {
        let args = Self.object(from: arguments)
        switch name {
        case "search_files":
            guard let query = Self.string(args, "query") else { return "Missing query." }
            let paths = FileTools.searchFiles(query: query)
            return paths.isEmpty ? "No matching files." : paths.joined(separator: "\n")
        case "list_folder":
            guard let path = Self.string(args, "path") else { return "Missing path." }
            return await FileTools2.listFolder(path: path)
        case "file_info":
            guard let path = Self.string(args, "path") else { return "Missing path." }
            return await FileTools2.fileInfo(path: path)
        case "read_file_text":
            guard let path = Self.string(args, "path") else { return "Missing path." }
            return await FileTools2.readFileText(path: path)
        case "list_files_by_date":
            let days = Self.int(args, "days_back") ?? 7
            return await FileTools2.listFilesByDate(
                folder: Self.string(args, "folder"),
                daysBack: days,
                nameContains: Self.string(args, "name_contains")
            )
        case "open_item":
            let target = Self.string(args, "target")
                ?? Self.string(args, "path")
                ?? Self.string(args, "url")
                ?? Self.string(args, "app")
            guard let target else { return "Missing target." }
            return await FileTools2.openItem(target)
        case "ask_photo_reader":
            guard let path = Self.string(args, "path") else { return "Missing path." }
            guard let question = Self.string(args, "question") else { return "Missing question." }
            return await FileTools2.askPhotoReader(path: path, question: question)
        default:
            return "Unknown tool \(name)."
        }
    }

    private static let all: [ToolDefinition] = [
        tool(
            "search_files",
            "Find files and folders in the home folder by name or file contents. Returns up to 15 paths, documents and folders first.",
            ["query": prop("string", "Words to look for in the file name or contents.")],
            ["query"]
        ),
        tool(
            "list_folder",
            "List the files and folders directly inside one folder.",
            ["path": prop("string", "Folder path. A name like Desktop is looked up inside the home folder.")],
            ["path"]
        ),
        tool(
            "file_info",
            "Show the kind, size, and dates for one file or folder.",
            ["path": prop("string", "Path to a file or folder inside the home folder.")],
            ["path"]
        ),
        tool(
            "read_file_text",
            "Read the text of a file. PDFs return the first 4000 characters. RTF and Word (.docx) are read as documents. Other files are read as plain text.",
            ["path": prop("string", "Path to a file inside the home folder.")],
            ["path"]
        ),
        tool(
            "list_files_by_date",
            "List files in a folder that were created or modified within the last N days. Omit folder to use the screenshot folder (System Settings capture location, otherwise Desktop). For screenshots, pass name_contains Screenshot.",
            [
                "folder": prop("string", "Folder to scan. Omit for the screenshot folder, or Desktop if no custom capture location is set."),
                "days_back": prop("integer", "How many days back to include. 7 is the last week. 0 means today."),
                "name_contains": prop("string", "Optional case-insensitive substring of the file name. Screenshot also matches names that begin with Screen Shot.")
            ],
            ["days_back"]
        ),
        tool(
            "open_item",
            "Open a file path, an application by name (Notes, Safari), or a web URL. Opening does not change any files.",
            ["target": prop("string", "A file path, an app name, or a URL such as https://example.com.")],
            ["target"]
        ),
        tool(
            "ask_photo_reader",
            "Ask the local Photo Reader about one image. Posts the image to http://127.0.0.1:8093/v1/chat/completions. If Photo Reader is not running, say so.",
            [
                "path": prop("string", "Path to an image in the home folder (jpg, png, heic, gif, webp, or tiff)."),
                "question": prop("string", "What to ask about the image.")
            ],
            ["path", "question"]
        )
    ]

    private static func tool(
        _ name: String,
        _ description: String,
        _ properties: [String: Any],
        _ required: [String]
    ) -> ToolDefinition {
        ToolDefinition(
            name: name,
            description: description,
            parameters: [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        )
    }

    private static func prop(_ type: String, _ description: String) -> [String: Any] {
        ["type": type, "description": description]
    }

    private static func object(from arguments: String) -> [String: Any] {
        guard let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }

    private static func string(_ json: [String: Any], _ key: String) -> String? {
        guard let text = json[key] as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func int(_ json: [String: Any], _ key: String) -> Int? {
        if let number = json[key] as? NSNumber {
            return number.intValue
        }
        if let text = json[key] as? String {
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}
