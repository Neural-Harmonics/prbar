import Foundation

struct PRExpandedDetails: Hashable {
    let repoFullName: String
    let number: Int
    let title: String
    let isDraft: Bool
    let author: String
    let updatedAt: Date
    let labels: [String]
    let assignees: [String]
    let reviewers: [String]
    let mergeableState: String?
    let headSHA: String
    let branch: String
    let htmlURL: URL
    let checkSummary: CheckSummary?
    let actions: ActionsDetail
}

actor PRDetailsCache {
    private var store: [String: (Date, PRExpandedDetails)] = [:]
    private let ttl: TimeInterval = 45

    func get(_ id: String) -> PRExpandedDetails? {
        guard let value = store[id], Date().timeIntervalSince(value.0) <= ttl else {
            store.removeValue(forKey: id)
            return nil
        }
        return value.1
    }

    func set(_ id: String, _ details: PRExpandedDetails) {
        store[id] = (Date(), details)
    }
}

@MainActor
final class PRDetailsViewModel: ObservableObject {
    @Published var details: PRExpandedDetails?
    @Published var isLoading = false
    @Published var error: String?

    private let container: AppContainer
    private let cache = PRDetailsCache()
    private var task: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
    }

    func load(pr: PullRequest?) {
        task?.cancel()
        guard let pr else {
            details = nil
            return
        }

        task = Task {
            if let cached = await cache.get(pr.stableID) {
                await MainActor.run { self.details = cached }
                return
            }

            await MainActor.run {
                self.isLoading = true
                self.error = nil
            }

            do {
                guard let token = try container.keychain.loadToken(), !token.isEmpty else {
                    throw AppError.missingToken
                }

                async let enrichedTask = container.prService.fetchPRDetail(token: token, pr: pr)
                async let metadataTask = container.prService.fetchPRMetadata(token: token, pr: pr)
                let enriched = try await enrichedTask
                let metadata = try await metadataTask
                let (summaryPR, actionDetails, _) = try await container.actionsService.enrichPRSummary(enriched, token: token, etags: container.etags)
                let jobs = try await container.actionsService.loadJobs(for: enriched, runs: actionDetails.runs, token: token)
                var fullActions = actionDetails
                fullActions.jobsByRunID = jobs

                let expanded = PRExpandedDetails(
                    repoFullName: summaryPR.repo.fullName,
                    number: summaryPR.number,
                    title: summaryPR.title,
                    isDraft: summaryPR.isDraft,
                    author: metadata.author,
                    updatedAt: summaryPR.updatedAt,
                    labels: metadata.labels,
                    assignees: metadata.assignees,
                    reviewers: metadata.reviewers,
                    mergeableState: metadata.mergeableState,
                    headSHA: metadata.headSHA,
                    branch: metadata.branch,
                    htmlURL: summaryPR.htmlURL,
                    checkSummary: summaryPR.checkSummary,
                    actions: fullActions
                )

                await cache.set(pr.stableID, expanded)
                await MainActor.run {
                    self.details = expanded
                    self.isLoading = false
                }
            } catch is CancellationError {
                await MainActor.run { self.isLoading = false }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}
