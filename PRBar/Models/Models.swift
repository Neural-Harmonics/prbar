import Foundation

struct RepoRef: Codable, Hashable {
    let owner: String
    let name: String

    var fullName: String { "\(owner)/\(name)" }
}

struct PullRequest: Codable, Identifiable, Hashable {
    let id: Int
    let number: Int
    let repo: RepoRef
    let title: String
    let isDraft: Bool
    let state: String
    let headRef: String
    let headSHA: String
    let updatedAt: Date
    let htmlURL: URL
    var reviewState: String?
    var checkSummary: CheckSummary?
    var actionsSummary: WorkflowSummary?

    var stableID: String { "\(repo.fullName)#\(number)" }
}

struct WorkflowRun: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let htmlURL: URL
    let createdAt: Date
    let updatedAt: Date
    let headSHA: String
}

struct Job: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?
    let steps: [Step]
}

struct Step: Codable, Hashable, Identifiable {
    var id: Int { number }
    let name: String
    let status: String
    let conclusion: String?
    let number: Int
}

struct CheckRun: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let status: String
    let conclusion: String?
    let detailsURL: URL?
    let summary: String?
}

struct CheckSummary: Codable, Hashable {
    let state: String
    let runs: [CheckRun]
}

struct WorkflowSummary: Codable, Hashable {
    let state: String
    let latestRun: WorkflowRun?
}

struct Identity: Codable, Hashable {
    let login: String
    let avatarURL: URL?
}

struct ScopeSettings: Codable, Hashable {
    var personalEnabled: Bool = true
    var organizationsEnabled: Bool = true
    var selectedOrgs: Set<String> = []
    var repoAllowlist: [String] = []
}

enum PopoverScopeSelection: Codable, Hashable {
    case all
    case personal
    case organization(String)
}

struct AppSettings: Codable, Hashable {
    var refreshInterval: Double = 60
    var autoRefreshEnabled: Bool = true
    var includeDrafts: Bool = true
    var includeClosed: Bool = false
    var openOnly: Bool = true
    var limit: Int = 50
    var scope: ScopeSettings = .init()
    var quickScope: PopoverScopeSelection = .all
}

struct ActionsDetail: Codable, Hashable {
    var runs: [WorkflowRun] = []
    var jobsByRunID: [Int: [Job]] = [:]
}

struct CachedState: Codable {
    var user: Identity?
    var orgs: [Identity] = []
    var pullRequests: [PullRequest] = []
    var selectedPRIDs: [String] = []
    var etags: [String: String] = [:]
    var settings: AppSettings = .init()
}

enum ActionState: String {
    case success
    case failure
    case inProgress = "in_progress"
    case neutral

    var sfSymbol: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .inProgress: return "arrow.triangle.2.circlepath.circle.fill"
        case .neutral: return "minus.circle.fill"
        }
    }
}

extension DateFormatter {
    static let githubISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
