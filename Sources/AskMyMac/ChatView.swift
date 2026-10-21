import AppKit
import SwiftUI

enum AskPalette {
    static let teal = Color(red: 0.0, green: 0.38, blue: 0.40)
}

struct ChatView: View {
    @ObservedObject var session: ChatSession
    @State private var draft = ""
    @State private var showSettings = false
    @StateObject private var speech = SpeechInput()
    @FocusState private var fieldFocused: Bool

    private let suggestions: [Suggestion] = [
        Suggestion("Find my resume", "doc.text.magnifyingglass"),
        Suggestion("What's on my calendar tomorrow?", "calendar"),
        Suggestion("Move last week's screenshots to an Archive folder", "photo.on.rectangle"),
        Suggestion("Open the PDF about…", "doc.richtext")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.35)
            transcript
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .background(WindowChrome())
        .tint(AskPalette.teal)
        .onAppear { focusComposer() }
        .task { await launch() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focusComposer()
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            Task { await session.refreshBrain() }
        }) {
            SettingsView(settings: session.settings)
        }
    }

    /// Check the local brain, then send ASKMYMAC_AUTOPROMPT once if the GUI was launched with it.
    private func launch() async {
        await session.refreshBrain()
        guard !Task.isCancelled else { return }
        guard let prompt = session.takeAutoPrompt() else { return }
        draft = prompt
        send()
    }

    private var statusColor: Color {
        switch session.presence {
        case .ready:
            return AskPalette.teal
        case .offline:
            return Color.orange
        case .checking, .starting:
            return Color.secondary
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Label("Ask My Mac", systemImage: "text.bubble")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Settings")
                }
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(session.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quaternary.opacity(0.7)))
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var transcript: some View {
        if session.messages.isEmpty {
            emptyState
        } else {
            messageList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(AskPalette.teal.opacity(0.14))
                    .frame(width: 72, height: 72)
                Image(systemName: "text.bubble")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(AskPalette.teal)
            }
            Text("Ask about files, your calendar, and folders on this Mac.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 240), spacing: 8, alignment: .leading)],
                spacing: 8
            ) {
                ForEach(suggestions) { suggestion in
                    Button {
                        send(suggestion.title)
                    } label: {
                        Label {
                            Text(suggestion.title)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        } icon: {
                            Image(systemName: suggestion.symbol)
                        }
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(session.isSending)
                }
            }
            .frame(maxWidth: 560)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(session.messages) { message in
                        MessageRow(
                            message: message,
                            onApprove: { session.approve(messageID: message.id) },
                            onCancel: { session.cancel(messageID: message.id) },
                            onUndo: { session.undo(messageID: message.id) }
                        )
                        .id(message.id)
                    }
                    if session.isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .id("pending")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: session.isSending) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if session.isSending {
                proxy.scrollTo("pending", anchor: .bottom)
            } else if let last = session.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                TextField("Ask about your Mac", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($fieldFocused)
                    .onSubmit { send() }
                SpeechMicButton(speech: speech, draft: $draft, busy: session.isSending)
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.borderless)
                .disabled(trimmedDraft.isEmpty || session.isSending)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.background.opacity(0.55))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AskPalette.teal.opacity(0.35), lineWidth: 1)
            }
            if let warning = speech.warning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .padding(16)
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send(_ text: String? = nil) {
        let content = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !session.isSending else { return }
        if text == nil { draft = "" }
        focusComposer()
        Task { await session.send(content) }
    }

    private func focusComposer() {
        DispatchQueue.main.async {
            fieldFocused = true
        }
    }
}

private struct Suggestion: Identifiable {
    let title: String
    let symbol: String
    var id: String { title }

    init(_ title: String, _ symbol: String) {
        self.title = title
        self.symbol = symbol
    }
}

private final class ClickThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct WindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ClickThroughView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.isMovableByWindowBackground = true
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
    }
}
