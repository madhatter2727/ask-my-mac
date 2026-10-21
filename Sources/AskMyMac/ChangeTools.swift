import Foundation

/// Changing tools only build a PendingAction. They never move, copy, rename, or trash.
enum ChangeTools {
    static let names: Set<String> = [
        "move_items", "rename_item", "copy_items", "create_folder", "trash_items"
    ]

    static var definitions: [ToolDefinition] { all }

    static func perform(name: String, arguments: String) async -> ToolOutcome {
        let args = object(from: arguments)
        let action: PendingAction
        switch name {
        case "move_items":
            action = await ActionCenter.planMove(paths: pathList(args), destinationFolder: folder(args) ?? "")
        case "copy_items":
            action = await ActionCenter.planCopy(paths: pathList(args), destinationFolder: folder(args) ?? "")
        case "rename_item":
            action = await ActionCenter.planRename(path: string(args, "path") ?? "", newName: newName(args) ?? "")
        case "create_folder":
            action = await ActionCenter.planCreateFolder(path: string(args, "path") ?? "")
        case "trash_items":
            action = await ActionCenter.planTrash(paths: pathList(args))
        default:
            action = .failed(kind: .move, summary: "Unknown tool \(name).")
        }
        guard action.phase == .pending else { return .text(action.previewText) }
        let note = action.previewText + "\nWaiting for approval. Nothing has been changed."
        return ToolOutcome(text: note, pending: action)
    }

    private static let all: [ToolDefinition] = [
        tool(
            "move_items",
            "Prepare a move of files or folders into a destination folder. Does not move anything until the user approves. Colliding names get a \" 2\" suffix. Never overwrites.",
            [
                "paths": arrayProp("Paths to move."),
                "destination_folder": prop("string", "Folder to move them into. Created on approval if it is missing. A name like Desktop/Archive is inside the home folder.")
            ],
            ["paths", "destination_folder"]
        ),
        tool(
            "rename_item",
            "Prepare a rename of one file or folder in its current folder. Does not rename until the user approves. A colliding name gets a \" 2\" suffix.",
            [
                "path": prop("string", "File or folder to rename."),
                "new_name": prop("string", "New file name only, not a path.")
            ],
            ["path", "new_name"]
        ),
        tool(
            "copy_items",
            "Prepare a copy of files or folders into a destination folder. Does not copy until the user approves. Colliding names get a \" 2\" suffix. Never overwrites.",
            [
                "paths": arrayProp("Paths to copy."),
                "destination_folder": prop("string", "Folder to copy them into. Created on approval if it is missing.")
            ],
            ["paths", "destination_folder"]
        ),
        tool(
            "create_folder",
            "Prepare a new folder. Does not create it until the user approves. Refuses if that path already exists.",
            ["path": prop("string", "Folder to create, such as Desktop/Archive.")],
            ["path"]
        ),
        tool(
            "trash_items",
            "Prepare moving files or folders to the Trash. Does not trash anything until the user approves. Never permanently deletes.",
            ["paths": arrayProp("Paths to move to the Trash.")],
            ["paths"]
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

    private static func arrayProp(_ description: String) -> [String: Any] {
        ["type": "array", "description": description, "items": ["type": "string"]]
    }

    private static func folder(_ json: [String: Any]) -> String? {
        string(json, "destination_folder") ?? string(json, "destination") ?? string(json, "folder")
    }

    private static func newName(_ json: [String: Any]) -> String? {
        string(json, "new_name") ?? string(json, "newName") ?? string(json, "name")
    }

    private static func pathList(_ json: [String: Any]) -> [String] {
        let listed = strings(json, "paths")
        if !listed.isEmpty { return listed }
        let files = strings(json, "files")
        if !files.isEmpty { return files }
        if let one = string(json, "path") { return [one] }
        return []
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

    private static func strings(_ json: [String: Any], _ key: String) -> [String] {
        if let list = json[key] as? [String] {
            return list.compactMap { nonempty($0) }
        }
        if let list = json[key] as? [Any] {
            return list.compactMap { item in (item as? String).flatMap { nonempty($0) } }
        }
        guard let text = json[key] as? String else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return list.compactMap { ($0 as? String).flatMap { nonempty($0) } }
        }
        return nonempty(trimmed).map { [$0] } ?? []
    }

    private static func nonempty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
