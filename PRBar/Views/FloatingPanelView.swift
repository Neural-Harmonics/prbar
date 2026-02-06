import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(viewModel.selectedPRs(), id: \.stableID) { pr in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(pr.repo.fullName) #\(pr.number)").font(.headline)
                            if pr.isDraft { Text("Draft").font(.caption).padding(.horizontal, 6).background(.orange.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 5)) }
                            Spacer()
                            Link("Open PR", destination: pr.htmlURL)
                        }

                        Text(pr.title).font(.subheadline)
                        Text("Branch: \(pr.headRef.isEmpty ? "unknown" : pr.headRef)  Updated: \(pr.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let actions = viewModel.actions(for: pr.stableID) {
                            workflowsSection(pr: pr, actions: actions)
                        } else {
                            Text("No workflow data yet.").font(.caption)
                        }

                        Divider()
                    }
                    .padding(12)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 440)
        .task {
            await viewModel.loadJobsForSelectedPRs()
        }
    }

    @ViewBuilder
    private func workflowsSection(pr: PullRequest, actions: ActionsDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Workflow Runs").font(.subheadline.bold())
            ForEach(actions.runs.prefix(3), id: \.id) { run in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: icon(for: run.status, conclusion: run.conclusion))
                        Text(run.name)
                        Text(run.status).foregroundStyle(.secondary)
                        Spacer()
                        Link("Open in Browser", destination: run.htmlURL)
                    }
                    .font(.caption)

                    if let jobs = actions.jobsByRunID[run.id] {
                        ForEach(jobs, id: \.id) { job in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Job: \(job.name) [\(job.status)]")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(job.steps, id: \.id) { step in
                                    Text("• \(step.number). \(step.name) - \(step.status)\(step.conclusion.map { " (\($0))" } ?? "")")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else if viewModel.isLoadingJobs(for: pr.stableID) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading jobs...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(.background.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let checks = pr.checkSummary {
                Text("Check Runs: \(checks.state)").font(.caption)
                ForEach(checks.runs.prefix(5), id: \.id) { check in
                    HStack {
                        Image(systemName: icon(for: check.status, conclusion: check.conclusion))
                        Text(check.name).font(.caption)
                        Spacer()
                        if let details = check.detailsURL {
                            Link("Details", destination: details).font(.caption)
                        }
                    }
                    if let summary = check.summary, !summary.isEmpty {
                        Text(summary).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
                    }
                }
            }
        }
    }

    private func icon(for status: String, conclusion: String?) -> String {
        if status != "completed" { return ActionState.inProgress.sfSymbol }
        if conclusion == "success" { return ActionState.success.sfSymbol }
        if conclusion == "failure" || conclusion == "cancelled" || conclusion == "timed_out" { return ActionState.failure.sfSymbol }
        return ActionState.neutral.sfSymbol
    }
}
