import SwiftUI

struct PRDetailsPanelView: View {
    @ObservedObject var viewModel: MainViewModel
    @ObservedObject var detailsViewModel: PRDetailsViewModel
    let pinMonitor: () -> Void
    @State private var showOnlyFailedJobs = false
    @State private var expandedJobKeys: Set<String> = []

    var body: some View {
        ScrollView {
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
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
        HStack {
            Text("Workflow Runs").font(.subheadline)
            Spacer()
            Toggle("Failed jobs only", isOn: $showOnlyFailedJobs)
                .toggleStyle(.checkbox)
                .font(.caption2)
        }
        ForEach(d.actions.runs.prefix(2), id: \.id) { run in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon(status: run.status, conclusion: run.conclusion))
                    Text(run.name).font(.caption)
                    Spacer()
                    stateChip(mappedState(run.status, run.conclusion), text: run.conclusion ?? run.status)
                    Link("Open Run", destination: run.htmlURL).font(.caption2)
                }
                if let jobs = d.actions.jobsByRunID[run.id] {
                    let visibleJobs = showOnlyFailedJobs
                        ? jobs.filter { mappedState($0.status, $0.conclusion) == .failure }
                        : jobs
                    let totalSteps = jobs.reduce(0) { $0 + $1.totalStepCount }
                    let doneSteps = jobs.reduce(0) { $0 + $1.completedStepCount }
                    if totalSteps > 0 {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Step progress: \(doneSteps)/\(totalSteps)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ProgressView(value: Double(doneSteps), total: Double(totalSteps))
                                .controlSize(.small)
                        }
                    }

                    ForEach(visibleJobs.prefix(4), id: \.id) { job in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                stateChip(mappedState(job.status, job.conclusion), text: job.conclusion ?? job.status)
                                Text(job.name)
                                    .font(.caption2)
                                Spacer()
                                Text(jobStepSummary(job))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                if !job.sortedSteps.isEmpty {
                                    Button {
                                        toggleJobExpanded(run: run, job: job)
                                    } label: {
                                        Image(systemName: isJobExpanded(run: run, job: job) ? "chevron.up" : "chevron.down")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            if let step = job.activeStep {
                                Text("Current step: #\(step.number) \(step.name)")
                                    .font(.caption2)
                                    .foregroundStyle(stateColor(mappedState(step.status, step.conclusion)))
                            }
                            if isJobExpanded(run: run, job: job) {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(job.sortedSteps, id: \.id) { step in
                                        HStack(spacing: 6) {
                                            stateChip(mappedState(step.status, step.conclusion), text: step.conclusion ?? step.status)
                                            Text("#\(step.number) \(step.name)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.leading, 8)
                            }
                        }
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

    private func mappedState(_ status: String, _ conclusion: String?) -> ActionState {
        if status != "completed" { return .inProgress }
        if conclusion == "success" { return .success }
        if conclusion == "failure" || conclusion == "cancelled" || conclusion == "timed_out" { return .failure }
        return .neutral
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

    private func jobStepSummary(_ job: Job) -> String {
        guard job.totalStepCount > 0 else {
            return job.conclusion ?? job.status
        }
        return "\(job.completedStepCount)/\(job.totalStepCount) steps"
    }

    private func jobKey(run: WorkflowRun, job: Job) -> String {
        "\(run.id):\(job.id)"
    }

    private func isJobExpanded(run: WorkflowRun, job: Job) -> Bool {
        expandedJobKeys.contains(jobKey(run: run, job: job))
    }

    private func toggleJobExpanded(run: WorkflowRun, job: Job) {
        let key = jobKey(run: run, job: job)
        if expandedJobKeys.contains(key) {
            expandedJobKeys.remove(key)
        } else {
            expandedJobKeys.insert(key)
        }
    }

    private func stateChip(_ state: ActionState, text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(stateColor(state).opacity(0.18))
            .foregroundStyle(stateColor(state))
            .clipShape(Capsule())
    }
}
