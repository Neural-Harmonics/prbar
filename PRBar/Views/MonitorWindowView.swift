import SwiftUI
import AppKit

struct MonitorWindowView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var monitorStore: MonitorStore
    @State private var controlsHeight: CGFloat = 0
    @State private var cardHeights: [String: CGFloat] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Refresh now") { Task { await viewModel.requestRefresh() } }
                Button(monitorStore.autoRefreshPaused ? "Resume auto-refresh" : "Pause auto-refresh") {
                    monitorStore.setPaused(!monitorStore.autoRefreshPaused)
                    viewModel.reconfigureScheduler()
                }
                Spacer()
            }
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: MonitorControlsHeightPreferenceKey.self, value: geo.size.height)
                }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.pinnedPRs(), id: \.stableID) { pr in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(pr.repo.fullName) #\(pr.number)").font(.headline)
                                Spacer()
                                Button("Open PR") { openURL(pr.htmlURL) }
                                Button("Remove") { viewModel.unpinFromMonitor(prID: pr.stableID) }
                            }
                            Text(pr.title).font(.subheadline)
                            HStack(spacing: 12) {
                                statusBadge(label: "Checks", rawState: pr.checkSummary?.state)
                                statusBadge(label: "Actions", rawState: pr.actionsSummary?.state)
                            }
                            .font(.caption)
                            if let actions = viewModel.actions(for: pr.stableID) {
                                ForEach(actions.runs.prefix(1), id: \.id) { run in
                                    Text("Run: \(run.name) - \(run.conclusion ?? run.status)")
                                        .font(.caption)
                                        .foregroundStyle(stateColor(mappedState(run.status, run.conclusion)))
                                    if let jobs = actions.jobsByRunID[run.id] {
                                        ForEach(jobs.prefix(5), id: \.id) { job in
                                            Text("• \(job.name): \(job.conclusion ?? job.status)")
                                                .font(.caption2)
                                                .foregroundStyle(stateColor(mappedState(job.status, job.conclusion)))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            openURL(pr.htmlURL)
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: MonitorCardHeightPreferenceKey.self,
                                    value: [pr.stableID: geo.size.height]
                                )
                            }
                        )
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 700)
        .onAppear {
            applyDynamicMinHeight()
        }
        .onChange(of: monitorStore.pinnedPRIDs) { _ in
            applyDynamicMinHeight()
        }
        .onPreferenceChange(MonitorControlsHeightPreferenceKey.self) { value in
            controlsHeight = value
            applyDynamicMinHeight()
        }
        .onPreferenceChange(MonitorCardHeightPreferenceKey.self) { value in
            cardHeights = value
            applyDynamicMinHeight()
        }
    }

    private func applyDynamicMinHeight() {
        guard let window = NSApp.windows.first(where: { $0.title == "PRBar Monitor" }) else { return }
        let pinned = viewModel.pinnedPRs()
        let cardsHeight = pinned.reduce(CGFloat(0)) { partial, pr in
            partial + (cardHeights[pr.stableID] ?? 0)
        }
        let cardsSpacing = CGFloat(max(0, pinned.count - 1)) * 10
        let stackSpacing: CGFloat = pinned.isEmpty ? 0 : 10
        let verticalPadding: CGFloat = 20
        let measuredContentHeight = controlsHeight + stackSpacing + cardsHeight + cardsSpacing + verticalPadding
        let contentHeight = max(120, measuredContentHeight.rounded(.up))
        window.minSize = NSSize(width: 700, height: contentHeight)

        guard let contentView = window.contentView else { return }
        let currentContentHeight = contentView.frame.height
        guard abs(currentContentHeight - contentHeight) > 1 else { return }

        var frame = window.frame
        let delta = contentHeight - currentContentHeight
        frame.size.height += delta
        frame.origin.y -= delta
        window.setFrame(frame, display: true, animate: true)
    }

    private func statusBadge(label: String, rawState: String?) -> some View {
        let state = mappedState(rawState)
        return HStack(spacing: 5) {
            Circle()
                .fill(stateColor(state))
                .frame(width: 8, height: 8)
            Text("\(label): \(rawState ?? "n/a")")
                .foregroundStyle(.secondary)
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

    private func mappedState(_ status: String, _ conclusion: String?) -> ActionState {
        if status != "completed" { return .inProgress }
        switch conclusion {
        case "success":
            return .success
        case "failure", "cancelled", "timed_out":
            return .failure
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
}

private struct MonitorCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct MonitorControlsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
