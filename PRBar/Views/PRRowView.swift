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
                    stateLabel(state: pr.checkSummary?.state, text: "checks")
                    stateLabel(state: pr.actionsSummary?.state, text: "actions")
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

    private func stateLabel(state: String?, text: String) -> some View {
        let mapped = mappedState(state)
        return HStack(spacing: 4) {
            Circle()
                .fill(stateColor(mapped))
                .frame(width: 7, height: 7)
            Image(systemName: stateIcon(mapped))
            Text(text)
        }
    }

    private func mappedState(_ raw: String?) -> ActionState {
        switch raw {
        case "success":
            return .success
        case "failure", "cancelled", "timed_out":
            return .failure
        case "in_progress", "queued", "waiting", "requested":
            return .inProgress
        default:
            return .neutral
        }
    }

    private func stateColor(_ state: ActionState) -> Color {
        switch state {
        case .success:
            return .green
        case .failure:
            return .red
        case .inProgress:
            return .yellow
        case .neutral:
            return .gray
        }
    }

    private func stateIcon(_ state: ActionState) -> String {
        state.sfSymbol
    }
}
