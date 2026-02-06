import Foundation
import Combine

@MainActor
final class AppContainer: ObservableObject {
    let keychain = KeychainService()
    let cache = CacheService()
    let github = GitHubClient()
    lazy var prService = PRService(client: github)
    lazy var actionsService = ActionsService(client: github)
    let selectionState = PRSelectionState()
    let monitorStore = MonitorStore()
    let refreshScheduler = RefreshScheduler()

    @Published var settings: AppSettings
    @Published var user: Identity?
    @Published var orgs: [Identity]
    @Published var pullRequests: [PullRequest]
    @Published var selectedPRIDs: Set<String>
    @Published var actionsByPRID: [String: ActionsDetail]
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var tokenStatus: String = "Token not validated"
    @Published var rateLimitInfo: RateLimitInfo = .init()
    @Published var apiMetrics: APIMetrics = .init()
    @Published var loadingJobsPRIDs: Set<String> = []

    private(set) var etags: [String: String]
    init() {
        let cached = cache.load()
        settings = cached.settings
        user = cached.user
        orgs = cached.orgs
        pullRequests = cached.pullRequests
        selectedPRIDs = Set(cached.selectedPRIDs)
        etags = cached.etags
        actionsByPRID = [:]
    }

    func saveCache() {
        cache.save(CachedState(
            user: user,
            orgs: orgs,
            pullRequests: pullRequests,
            selectedPRIDs: Array(selectedPRIDs),
            etags: etags,
            settings: settings
        ))
    }

    func configureScheduler() {
        let remaining = rateLimitInfo.remaining
        let base = settings.refreshInterval
        let slowed = remaining > 0 && remaining < 100 ? max(base, 180) : base
        let enabled = settings.autoRefreshEnabled && !monitorStore.autoRefreshPaused
        refreshScheduler.configure(interval: slowed, enabled: enabled)
    }

    func setETag(_ value: String, for key: String) {
        etags[key] = value
    }

    func replaceETags(_ value: [String: String]) {
        etags = value
    }

    func setLoadingJobs(_ loading: Bool, prID: String) {
        if loading {
            loadingJobsPRIDs.insert(prID)
        } else {
            loadingJobsPRIDs.remove(prID)
        }
    }
}
