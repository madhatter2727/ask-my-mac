import Foundation

extension ChatSession {
    /// The GUI sends ASKMYMAC_AUTOPROMPT once on launch. Headless tests never call this.
    func takeAutoPrompt() -> String? {
        guard !consumedLaunchPrompt else { return nil }
        consumedLaunchPrompt = true
        guard let raw = ProcessInfo.processInfo.environment["ASKMYMAC_AUTOPROMPT"] else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    func approve(messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        guard var action = messages[index].pending, action.phase == .pending else { return }
        action = ActionCenter.execute(action)
        var message = messages[index]
        message.pending = action
        messages[index] = message
        canUndo = UndoLog.hasEntries
    }

    func cancel(messageID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        guard var action = messages[index].pending, action.phase == .pending else { return }
        action.phase = .cancelled
        action.resultText = "Cancelled. Nothing was changed."
        var message = messages[index]
        message.pending = action
        messages[index] = message
    }

    func undo(messageID: UUID) {
        guard let undoID = messages.first(where: { $0.id == messageID })?.pending?.undoID else { return }
        guard messages.first(where: { $0.id == messageID })?.pending?.phase == .done else { return }
        applyUndo(undoID)
    }

    func undoLast() {
        guard let undoID = UndoLog.lastID() else { return }
        applyUndo(undoID)
    }

    private func applyUndo(_ undoID: UUID) {
        let result = UndoLog.undo(id: undoID)
        canUndo = UndoLog.hasEntries
        var matched = false
        for index in messages.indices {
            guard var action = messages[index].pending, action.undoID == undoID else { continue }
            matched = true
            if result.ok {
                action.phase = .undone
            }
            let prior = action.resultText ?? ""
            action.resultText = prior.isEmpty ? result.message : prior + "\n" + result.message
            var message = messages[index]
            message.pending = action
            messages[index] = message
        }
        if !matched {
            messages.append(ChatMessage(role: .assistant, text: result.message))
        }
    }
}
