import AppKit
import SwiftUI

struct ToolChips: View {
    let names: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(AskPalette.teal)
                    .background(Capsule().fill(AskPalette.teal.opacity(0.14)))
                    .accessibilityLabel("Used \(name)")
            }
        }
    }
}

struct FileResultRow: View {
    let path: String

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(AskPalette.teal)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(parent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 40, alignment: .leading)
            Spacer(minLength: 8)
            Button("Open") { open() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Open \(name)")
            Button("Reveal in Finder") { reveal() }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityLabel("Reveal \(name) in Finder")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.opacity(0.45))
        }
    }

    private var name: String {
        (path as NSString).lastPathComponent
    }

    private var parent: String {
        shortened((path as NSString).deletingLastPathComponent)
    }

    private var symbol: String {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        let ext = (path as NSString).pathExtension.lowercased()
        if exists && isDirectory.boolValue && !Self.packages.contains(ext) {
            return "folder"
        }
        switch ext {
        case "pdf", "pages", "doc", "docx", "rtf", "rtfd":
            return "doc.richtext"
        case "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp":
            return "photo"
        case "txt", "md":
            return "doc.text"
        case "xlsx", "xls", "numbers", "csv":
            return "tablecells"
        case "key", "ppt", "pptx":
            return "rectangle.on.rectangle"
        default:
            return "doc"
        }
    }

    private func open() {
        guard case .success(let ok) = PathGuard.accept(path) else { return }
        _ = NSWorkspace.shared.open(URL(fileURLWithPath: ok))
    }

    private func reveal() {
        guard case .success(let ok) = PathGuard.accept(path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: ok)])
    }

    private func shortened(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        let prefix = home.hasSuffix("/") ? home : home + "/"
        guard path.hasPrefix(prefix) else { return path }
        return "~/" + path.dropFirst(prefix.count)
    }

    private static let packages: Set<String> = ["pages", "key", "numbers", "rtfd"]
}

struct MessageRow: View {
    let message: ChatMessage
    var onApprove: () -> Void = {}
    var onCancel: () -> Void = {}
    var onUndo: () -> Void = {}

    private var isUser: Bool { message.role == .user }

    var body: some View {
        if isUser {
            bubble
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if !message.toolNames.isEmpty {
                    ToolChips(names: message.toolNames)
                }
                if !message.filePaths.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(message.filePaths, id: \.self) { path in
                            FileResultRow(path: path)
                        }
                    }
                }
                if let pending = message.pending {
                    ApprovalCardView(
                        action: pending,
                        onApprove: onApprove,
                        onCancel: onCancel,
                        onUndo: onUndo
                    )
                }
                if !message.text.isEmpty && message.pending == nil {
                    bubble
                }
            }
        }
    }

    private var bubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 64) }
            if !isUser {
                Image(systemName: "text.bubble.fill")
                    .font(.caption)
                    .foregroundStyle(AskPalette.teal)
            }
            Text(message.text)
                .textSelection(.enabled)
                .foregroundStyle(isUser ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isUser ? AnyShapeStyle(AskPalette.teal) : AnyShapeStyle(.thinMaterial))
                }
            if !isUser { Spacer(minLength: 64) }
        }
    }
}
