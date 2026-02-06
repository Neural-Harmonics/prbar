import SwiftUI

struct PRDetailsPanelView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var detailsViewModel: PRDetailsViewModel
    let pinMonitor: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if detailsViewModel.isLoading {
                ProgressView("Loading details...")
            } else if let details = detailsViewModel.details {
                header(details)
                meta(details)
                checks(details)
                actions(details)
                buttons(details)
            } else {
                Text("Select a PR to view details").foregroundStyle(.secondary)
            }
            if let err = detailsViewModel.error {
                Text(err).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(10)
    }

    @ViewBuilder private func header(_ d: PRExpandedDetails) -> some View {
        Text("\(d.repoFullName) #\(d.number)").font(.headline)
        Text(d.title).font(.subheadline)
        Text("\(d.isDraft ? "Draft" : "Ready") · @\(d.author) · Updated \(d.updatedAt.formatted(date: .abbreviated, time: .shortened))")
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func meta(_ d: PRExpandedDetails) -> some View {
        Text("Branch: \(d.branch) · SHA: \(d.headSHA.prefix(8))")
            .font(.caption)
        Text("Merge state: \(d.mergeableState ?? "Not available")")
            .font(.caption)
        Text("Labels: \(d.labels.isEmpty ? "None" : d.labels.joined(separator: ", "))")
            .font(.caption2).foregroundStyle(.secondary)
        Text("Assignees: \(d.assignees.isEmpty ? "None" : d.assignees.joined(separator: ", "))")
            .font(.caption2).foregroundStyle(.secondary)
        Text("Reviewers: \(d.reviewers.isEmpty ? "None" : d.reviewers.joined(separator: ", "))")
            .font(.caption2).foregroundStyle(.secondary)
    }

    @ViewBuilder private func checks(_ d: PRExpandedDetails) -> some View {
        if let checkSummary = d.checkSummary {
            Text("Checks: \(checkSummary.state)").font(.subheadline)
            ForEach(checkSummary.runs.prefix(6), id: \.id) { check in
                HStack {
                    Image(systemName: icon(status: check.status, conclusion: check.conclusion))
                    Text(check.name).font(.caption)
                    Spacer()
                    Text(check.conclusion ?? check.status).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func actions(_ d: PRExpandedDetails) -> some View {
        Text("Workflow Runs").font(.subheadline)
        ForEach(d.actions.runs.prefix(2), id: \.id) { run in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: icon(status: run.status, conclusion: run.conclusion))
                    Text(run.name).font(.caption)
                    Spacer()
                    Link("Open Run", destination: run.htmlURL).font(.caption2)
                }
                if let jobs = d.actions.jobsByRunID[run.id] {
                    ForEach(jobs.prefix(4), id: \.id) { job in
                        Text("• \(job.name): \(job.conclusion ?? job.status)")
                            .font(.caption2)
                            .foregroundStyle(job.conclusion == "failure" ? .red : .secondary)
                    }
                }
            }
            .padding(6)
            .background(.background.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    @ViewBuilder private func buttons(_ d: PRExpandedDetails) -> some View {
        HStack {
            Link("Open PR", destination: d.htmlURL)
            Button("Copy PR URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(d.htmlURL.absoluteString, forType: .string)
            }
            Button("Copy Branch") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(d.branch, forType: .string)
            }
            Spacer()
            Button("Pin Floating Monitor", action: pinMonitor)
        }
        .font(.caption)
    }

    private func icon(status: String, conclusion: String?) -> String {
        if status != "completed" { return ActionState.inProgress.sfSymbol }
        if conclusion == "success" { return ActionState.success.sfSymbol }
        if conclusion == "failure" || conclusion == "cancelled" || conclusion == "timed_out" { return ActionState.failure.sfSymbol }
        return ActionState.neutral.sfSymbol
    }
}
