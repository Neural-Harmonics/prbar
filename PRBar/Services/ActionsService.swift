import Foundation

final class ActionsService {
    private let client: GitHubClient

    init(client: GitHubClient) {
        self.client = client
    }

    func enrichPRSummary(_ pr: PullRequest, token: String, etags: [String: String]) async throws -> (PullRequest, ActionsDetail, [String: String]) {
        var nextPR = pr
        var nextEtags = etags

        async let runsResponse: GitHubResponse<RunsResponse?> = client.get(
            "repos/\(pr.repo.owner)/\(pr.repo.name)/actions/runs",
            token: token,
            query: [
                URLQueryItem(name: "per_page", value: "30")
            ],
            etag: etags[runsKey(for: pr)],
            decoder: .github
        )

        async let checksResponse: GitHubResponse<ChecksResponse?> = client.get(
            "repos/\(pr.repo.owner)/\(pr.repo.name)/commits/\(pr.headSHA.isEmpty ? "HEAD" : pr.headSHA)/check-runs",
            token: token,
            query: [URLQueryItem(name: "per_page", value: "20")],
            etag: etags[checksKey(for: pr)],
            decoder: .github
        )

        let runs = try await runsResponse
        let checks = try await checksResponse

        let mappedRuns = runs.value?.workflow_runs.map {
            WorkflowRun(id: $0.id, name: $0.name, status: $0.status, conclusion: $0.conclusion, htmlURL: $0.html_url, createdAt: $0.created_at, updatedAt: $0.updated_at, headSHA: $0.head_sha)
        } ?? []
        let runsForPR: [WorkflowRun]
        if pr.headSHA.isEmpty {
            runsForPR = mappedRuns
        } else {
            runsForPR = mappedRuns.filter { $0.headSHA == pr.headSHA }
        }

        if let etag = runs.etag { nextEtags[runsKey(for: pr)] = etag }
        if let etag = checks.etag { nextEtags[checksKey(for: pr)] = etag }

        nextPR.actionsSummary = WorkflowSummary(state: workflowState(from: runsForPR.first), latestRun: runsForPR.first)

        let mappedChecks = checks.value?.check_runs.map {
            CheckRun(id: $0.id, name: $0.name, status: $0.status, conclusion: $0.conclusion, detailsURL: $0.details_url, summary: $0.output?.summary)
        } ?? []
        nextPR.checkSummary = CheckSummary(state: overallCheckState(checks: mappedChecks), runs: mappedChecks)

        return (nextPR, ActionsDetail(runs: runsForPR, jobsByRunID: [:]), nextEtags)
    }

    func loadJobs(for pr: PullRequest, runs: [WorkflowRun], token: String) async throws -> [Int: [Job]] {
        var jobsByRunID: [Int: [Job]] = [:]
        for run in runs.prefix(2) {
            let response: GitHubResponse<JobsResponse?> = try await client.get(
                "repos/\(pr.repo.owner)/\(pr.repo.name)/actions/runs/\(run.id)/jobs",
                token: token,
                query: [URLQueryItem(name: "per_page", value: "50")],
                decoder: .github
            )
            let jobs = response.value?.jobs.map {
                Job(
                    id: $0.id,
                    name: $0.name,
                    status: $0.status,
                    conclusion: $0.conclusion,
                    startedAt: $0.started_at,
                    completedAt: $0.completed_at,
                    steps: $0.steps?.map { Step(name: $0.name, status: $0.status, conclusion: $0.conclusion, number: $0.number) } ?? []
                )
            } ?? []
            jobsByRunID[run.id] = jobs
        }
        return jobsByRunID
    }

    private func workflowState(from run: WorkflowRun?) -> String {
        guard let run else { return "unknown" }
        if run.status != "completed" { return "in_progress" }
        return run.conclusion ?? "neutral"
    }

    private func overallCheckState(checks: [CheckRun]) -> String {
        if checks.contains(where: { $0.status != "completed" }) { return "in_progress" }
        if checks.contains(where: { $0.conclusion == "failure" || $0.conclusion == "timed_out" || $0.conclusion == "cancelled" }) { return "failure" }
        if checks.contains(where: { $0.conclusion == "success" }) { return "success" }
        return "neutral"
    }

    private func runsKey(for pr: PullRequest) -> String { "runs:\(pr.stableID)" }
    private func checksKey(for pr: PullRequest) -> String { "checks:\(pr.stableID)" }
}

private struct RunsResponse: Decodable {
    struct Run: Decodable {
        let id: Int
        let name: String
        let status: String
        let conclusion: String?
        let html_url: URL
        let created_at: Date
        let updated_at: Date
        let head_sha: String
    }

    let workflow_runs: [Run]
}

private struct ChecksResponse: Decodable {
    struct Item: Decodable {
        struct Output: Decodable { let summary: String? }
        let id: Int
        let name: String
        let status: String
        let conclusion: String?
        let details_url: URL?
        let output: Output?
    }

    let check_runs: [Item]
}

private struct JobsResponse: Decodable {
    struct JobDTO: Decodable {
        struct StepDTO: Decodable {
            let name: String
            let status: String
            let conclusion: String?
            let number: Int
        }

        let id: Int
        let name: String
        let status: String
        let conclusion: String?
        let started_at: Date?
        let completed_at: Date?
        let steps: [StepDTO]?
    }

    let jobs: [JobDTO]
}
