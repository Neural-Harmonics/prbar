import SwiftUI

struct PRRowView: View {
    let pr: PullRequest
    let selected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(pr.repo.fullName).font(.caption).foregroundStyle(.secondary)
                    if pr.isDraft { Text("DRAFT").font(.caption2).padding(.horizontal, 4).background(.orange.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 4)) }
                }
                Text(pr.title).font(.subheadline).lineLimit(2)
                HStack(spacing: 8) {
                    label(icon: "message", text: pr.reviewState ?? "review: n/a")
                    label(icon: stateIcon(pr.checkSummary?.state), text: "checks")
                    label(icon: stateIcon(pr.actionsSummary?.state), text: "actions")
                }.font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func label(icon: String, text: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(text)
        }
    }

    private func stateIcon(_ raw: String?) -> String {
        switch raw {
        case "success": return ActionState.success.sfSymbol
        case "failure", "cancelled", "timed_out": return ActionState.failure.sfSymbol
        case "in_progress", "queued", "waiting", "requested": return ActionState.inProgress.sfSymbol
        default: return ActionState.neutral.sfSymbol
        }
    }
}
