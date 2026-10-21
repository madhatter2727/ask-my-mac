import SwiftUI

/// Distinct from a chat bubble: teal border, plain summary, Approve as the primary button.
struct ApprovalCardView: View {
    let action: PendingAction
    var onApprove: () -> Void
    var onCancel: () -> Void
    var onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(status)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AskPalette.teal)
            Text(action.title)
                .font(.headline)
            if action.phase == .pending {
                Text(action.summary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(action.transfers) { transfer in
                Text("\(transfer.source) → \(transfer.destination)")
                    .font(.callout)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
            }
            if action.phase == .pending {
                ForEach(Array(action.warnings.enumerated()), id: \.offset) { _, warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let result = action.resultText, !result.isEmpty, action.phase != .pending {
                Text(result)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            buttons
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.background.opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(AskPalette.teal, lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(action.title)
    }

    @ViewBuilder
    private var buttons: some View {
        switch action.phase {
        case .pending:
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                Button("Approve", action: onApprove)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        case .done:
            if action.undoID != nil {
                Button("Undo", action: onUndo)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        case .cancelled, .failed, .undone:
            EmptyView()
        }
    }

    private var status: String {
        switch action.phase {
        case .pending:
            return "Needs approval"
        case .done:
            return "Done"
        case .cancelled:
            return "Cancelled"
        case .failed:
            return "Not changed"
        case .undone:
            return "Undone"
        }
    }
}
