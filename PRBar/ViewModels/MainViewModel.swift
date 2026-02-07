import Foundation
import Combine

@MainActor
final class MainViewModel: ObservableObject {
    @Published var query = ""

    private let container: AppContainer
    private var containerSink: AnyCancellable?
    private var monitorStoreSink: AnyCancellable?

    init(container: AppContainer) {
        self.container = container
        containerSink = container.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        monitorStoreSink = container.monitorStore.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        container.refreshScheduler.register(key: "pr-list-refresh") { [weak self] in
            await self?.refreshAll(manual: false)
        }
        container.configureScheduler()
    }

    var filteredPRs: [PullRequest] {
        container.pullRequests.filter { pr in
            guard matchesQuickScope(pr) else { return false }
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty { return true }
            return pr.title.localizedCaseInsensitiveContains(q) || pr.repo.fullName.localizedCaseInsensitiveContains(q)
        }
    }

    private func matchesQuickScope(_ pr: PullRequest) -> Bool {
        switch container.settings.quickScope {
        case .all:
            return matchesAllScope(pr)
        case .personal:
            guard let login = container.user?.login.lowercased() else { return true }
            return pr.repo.owner.lowercased() == login
        case let .organization(org):
            return pr.repo.owner.caseInsensitiveCompare(org) == .orderedSame
        }
    }

    private func matchesAllScope(_ pr: PullRequest) -> Bool {
        let scope = container.settings.scope
        let owner = pr.repo.owner.lowercased()
        let selectedOrgs = Set(scope.selectedOrgs.map { $0.lowercased() })
        let login = container.user?.login.lowercased()

        if scope.personalEnabled, let login, owner == login {
            return true
        }
        if scope.organizationsEnabled, selectedOrgs.contains(owner) {
            return true
        }
        if !scope.personalEnabled && !scope.organizationsEnabled {
            return true
        }
        return false
    }

    func setQuickScope(_ scope: PopoverScopeSelection) {
        var next = container.settings
        next.quickScope = normalizedQuickScope(scope, availableOrgs: container.orgs)
        container.settings = next
        container.saveCache()
        Task { await requestRefresh() }
    }

    func toggleSelection(pr: PullRequest) {
        if container.selectedPRIDs.contains(pr.stableID) {
            container.selectedPRIDs.remove(pr.stableID)
        } else {
            container.selectedPRIDs.insert(pr.stableID)
            Task { await loadJobsForSelectedPRs() }
        }
        container.saveCache()
    }

    func isSelected(_ pr: PullRequest) -> Bool {
        container.selectedPRIDs.contains(pr.stableID)
    }

    func selectPR(_ pr: PullRequest?) {
        container.selectionState.select(pr)
    }

    func selectedPR() -> PullRequest? {
        guard let id = container.selectionState.selectedPRID else { return nil }
        return container.pullRequests.first(where: { $0.stableID == id })
    }

    func selectedPRs() -> [PullRequest] {
        container.pullRequests.filter { container.selectedPRIDs.contains($0.stableID) }
    }

    func pinSelectedPRToMonitor() {
        guard let selected = selectedPR() else { return }
        container.monitorStore.pin(selected.stableID)
    }

    func unpinFromMonitor(prID: String) {
        container.monitorStore.remove(prID)
    }

    func pinnedPRs() -> [PullRequest] {
        let set = Set(container.monitorStore.pinnedPRIDs)
        return container.pullRequests.filter { set.contains($0.stableID) }
    }

    func saveToken(_ token: String) async {
        do {
            try container.keychain.saveToken(token)
            container.tokenStatus = "Token saved"
            await validateTokenAndLoadIdentity()
        } catch {
            container.errorMessage = error.localizedDescription
        }
    }

    func requestRefresh() async {
        await container.refreshScheduler.requestRefresh()
    }

    func validateTokenAndLoadIdentity() async {
        do {
            guard let token = try container.keychain.loadToken(), !token.isEmpty else {
                container.tokenStatus = "Missing token"
                return
            }
            let (identity, userETag) = try await container.prService.fetchIdentity(token: token, etag: container.etags["user"])
            if let identity {
                container.user = identity
            }
            if let userETag { container.setETag(userETag, for: "user") }

            let (orgs, orgETag) = try await container.prService.fetchOrganizations(token: token, etag: container.etags["orgs"])
            if let orgs {
                container.orgs = orgs
                var next = container.settings
                if next.scope.selectedOrgs.isEmpty {
                    next.scope.selectedOrgs = Set(orgs.prefix(3).map { $0.login })
                }
                next.quickScope = normalizedQuickScope(next.quickScope, availableOrgs: orgs)
                container.settings = next
            }
            if let orgETag { container.setETag(orgETag, for: "orgs") }

            container.tokenStatus = "Token valid for @\(container.user?.login ?? "unknown")"
            container.rateLimitInfo = container.github.rateLimit
            container.apiMetrics = await container.github.metricsSnapshot()
            container.saveCache()
        } catch {
            container.errorMessage = error.localizedDescription
        }
    }

    func refreshAll(manual: Bool) async {
        guard !container.isLoading else { return }

        do {
            guard let token = try container.keychain.loadToken(), !token.isEmpty else {
                container.tokenStatus = "Missing token"
                return
            }
            guard let user = container.user else {
                await validateTokenAndLoadIdentity()
                guard container.user != nil else { return }
                await refreshAll(manual: manual)
                return
            }

            container.isLoading = true
            let (prsBase, etags) = try await container.prService.fetchPRs(
                token: token,
                userLogin: user.login,
                settings: container.settings,
                quickScope: container.settings.quickScope,
                etags: container.etags
            )
            container.replaceETags(etags)

            let detailed = try await withThrowingTaskGroup(of: PullRequest.self) { group in
                for pr in prsBase {
                    group.addTask { try await self.container.prService.fetchPRDetail(token: token, pr: pr) }
                }
                var prs: [PullRequest] = []
                for try await pr in group { prs.append(pr) }
                return prs.sorted(by: { $0.updatedAt > $1.updatedAt })
            }

            var result: [PullRequest] = []
            var actionsMap: [String: ActionsDetail] = container.actionsByPRID
            var etagMap = container.etags

            for pr in detailed {
                do {
                    let (enriched, actions, nextEtags) = try await container.actionsService.enrichPRSummary(pr, token: token, etags: etagMap)
                    result.append(enriched)
                    actionsMap[enriched.stableID] = actions
                    etagMap.merge(nextEtags, uniquingKeysWith: { _, new in new })
                } catch {
                    result.append(pr)
                }
            }

            container.pullRequests = result
            container.actionsByPRID = actionsMap
            container.replaceETags(etagMap)
            container.rateLimitInfo = container.github.rateLimit
            container.apiMetrics = await container.github.metricsSnapshot()
            container.configureScheduler()
            container.errorMessage = nil
            container.saveCache()
            await loadJobsForSelectedPRs()
        } catch {
            container.errorMessage = error.localizedDescription
        }

        container.isLoading = false
    }

    func updateSettings(_ settings: AppSettings) {
        var next = settings
        next.quickScope = normalizedQuickScope(next.quickScope, availableOrgs: container.orgs)
        container.settings = next
        container.saveCache()
        container.configureScheduler()
    }

    func reconfigureScheduler() {
        container.configureScheduler()
    }

    func currentSettings() -> AppSettings { container.settings }
    func currentUser() -> Identity? { container.user }
    func currentOrgs() -> [Identity] { container.orgs.sorted { $0.login.localizedCaseInsensitiveCompare($1.login) == .orderedAscending } }
    func rateLimit() -> RateLimitInfo { container.rateLimitInfo }
    func apiMetrics() -> APIMetrics { container.apiMetrics }
    func actions(for prID: String) -> ActionsDetail? { container.actionsByPRID[prID] }
    func isLoadingJobs(for prID: String) -> Bool { container.loadingJobsPRIDs.contains(prID) }
    func loadJobsForSelectedPRs() async {
        guard let token = try? container.keychain.loadToken(), !token.isEmpty else { return }
        let selected = selectedPRs()
        for pr in selected {
            guard var detail = container.actionsByPRID[pr.stableID], detail.jobsByRunID.isEmpty else { continue }
            container.setLoadingJobs(true, prID: pr.stableID)
            do {
                let jobs = try await container.actionsService.loadJobs(for: pr, runs: detail.runs, token: token)
                detail.jobsByRunID = jobs
                container.actionsByPRID[pr.stableID] = detail
            } catch {
                container.setLoadingJobs(false, prID: pr.stableID)
                continue
            }
            container.setLoadingJobs(false, prID: pr.stableID)
        }
        container.apiMetrics = await container.github.metricsSnapshot()
    }
    func error() -> String? { container.errorMessage }
    func tokenStatus() -> String { container.tokenStatus }
    var isLoading: Bool { container.isLoading }
    var isAutoRefreshPaused: Bool { container.monitorStore.autoRefreshPaused }

    func toggleAutoRefresh() {
        container.monitorStore.setPaused(!container.monitorStore.autoRefreshPaused)
        container.configureScheduler()
    }

    private func normalizedQuickScope(_ scope: PopoverScopeSelection, availableOrgs: [Identity]) -> PopoverScopeSelection {
        switch scope {
        case let .organization(org):
            if availableOrgs.contains(where: { $0.login.caseInsensitiveCompare(org) == .orderedSame }) {
                return .organization(org)
            }
            return .all
        case .all, .personal:
            return scope
        }
    }
}
