import SwiftUI

struct MonitorWindowView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var monitorStore: MonitorStore

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

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(viewModel.pinnedPRs(), id: \.stableID) { pr in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("\(pr.repo.fullName) #\(pr.number)").font(.headline)
                                Spacer()
                                Button("Remove") { viewModel.unpinFromMonitor(prID: pr.stableID) }
                            }
                            Text(pr.title).font(.subheadline)
                            Text("Checks: \(pr.checkSummary?.state ?? "n/a") · Actions: \(pr.actionsSummary?.state ?? "n/a")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let actions = viewModel.actions(for: pr.stableID) {
                                ForEach(actions.runs.prefix(1), id: \.id) { run in
                                    Text("Run: \(run.name) - \(run.conclusion ?? run.status)").font(.caption)
                                    if let jobs = actions.jobsByRunID[run.id] {
                                        ForEach(jobs.prefix(5), id: \.id) { job in
                                            Text("• \(job.name): \(job.conclusion ?? job.status)")
                                                .font(.caption2)
                                                .foregroundStyle(job.conclusion == "failure" ? .red : .secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 700, minHeight: 450)
    }
}
