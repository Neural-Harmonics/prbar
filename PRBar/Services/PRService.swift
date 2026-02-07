import Foundation

final class PRService {
    private let client: GitHubClient

    init(client: GitHubClient) {
        self.client = client
    }

    func fetchIdentity(token: String, etag: String?) async throws -> (Identity?, String?) {
        struct UserDTO: Decodable {
            let login: String
            let avatar_url: URL?
        }
        let response: GitHubResponse<UserDTO?> = try await client.get("user", token: token, etag: etag)
        guard let value = response.value else { return (nil, response.etag) }
        return (Identity(login: value.login, avatarURL: value.avatar_url), response.etag)
    }

    func fetchOrganizations(token: String, etag: String?) async throws -> ([Identity]?, String?) {
        struct OrgDTO: Decodable {
            let login: String
            let avatar_url: URL?
        }
        let response: GitHubResponse<[OrgDTO]?> = try await client.get("user/orgs", token: token, etag: etag)
        guard let value = response.value else { return (nil, response.etag) }
        return (value.map { Identity(login: $0.login, avatarURL: $0.avatar_url) }, response.etag)
    }

    func fetchPRs(token: String,
                  userLogin: String,
                  settings: AppSettings,
                  quickScope: PopoverScopeSelection,
                  etags: [String: String]) async throws -> ([PullRequest], [String: String]) {
        let stateClause: String
        if settings.includeClosed {
            stateClause = ""
        } else if settings.openOnly {
            stateClause = "state:open"
        } else {
            stateClause = ""
        }

        let base = ["is:pr", "author:\(userLogin)", stateClause].filter { !$0.isEmpty }.joined(separator: " ")

        let units = searchUnits(settings: settings, quickScope: quickScope, userLogin: userLogin)
        let queries = units.isEmpty ? [base] : units.map { "\(base) \($0)" }

        return try await withThrowingTaskGroup(of: (String, [PullRequest], [String: String]).self) { group in
            for query in queries {
                group.addTask {
                    let fetched = try await self.fetchPRsForQuery(
                        token: token,
                        query: query,
                        limit: settings.limit,
                        etags: etags
                    )
                    return (query, fetched.0, fetched.1)
                }
            }

            var all: [PullRequest] = []
            var nextEtags = etags
            for try await (_, prs, localEtags) in group {
                all.append(contentsOf: prs)
                nextEtags.merge(localEtags, uniquingKeysWith: { _, new in new })
            }

            let merged = Dictionary(grouping: all, by: { $0.stableID }).compactMap { _, values in
                values.max(by: { $0.updatedAt < $1.updatedAt })
            }.sorted(by: { $0.updatedAt > $1.updatedAt })

            return (Array(merged.prefix(settings.limit)), nextEtags)
        }
    }

    func fetchPRDetail(token: String, pr: PullRequest) async throws -> PullRequest {
        struct DetailDTO: Decodable {
            struct Head: Decodable {
                struct Repo: Decodable {
                    struct Owner: Decodable { let login: String }
                    let name: String
                    let owner: Owner
                }
                let ref: String
                let sha: String
                let repo: Repo?
            }
            struct UserDTO: Decodable { let login: String }

            let number: Int
            let title: String
            let draft: Bool
            let state: String
            let head: Head
            let requested_reviewers: [UserDTO]
            let updated_at: Date
            let html_url: URL
        }
        async let detailResponse: GitHubResponse<DetailDTO?> = client.get(
            "repos/\(pr.repo.owner)/\(pr.repo.name)/pulls/\(pr.number)",
            token: token,
            decoder: .github
        )

        async let reviewsResponse: GitHubResponse<[PullReviewDTO]?> = client.get(
            "repos/\(pr.repo.owner)/\(pr.repo.name)/pulls/\(pr.number)/reviews",
            token: token,
            query: [URLQueryItem(name: "per_page", value: "100")],
            decoder: .github
        )

        let detail = try await detailResponse
        guard let dto = detail.value else { return pr }
        let reviews = try await reviewsResponse.value ?? []
        let reviewState = summarizeReviewState(reviews: reviews, requestedReviewers: dto.requested_reviewers.map(\.login))

        let repo = RepoRef(
            owner: dto.head.repo?.owner.login ?? pr.repo.owner,
            name: dto.head.repo?.name ?? pr.repo.name
        )
        return PullRequest(
            id: pr.id,
            number: dto.number,
            repo: repo,
            title: dto.title,
            isDraft: dto.draft,
            state: dto.state,
            headRef: dto.head.ref,
            headSHA: dto.head.sha,
            updatedAt: dto.updated_at,
            htmlURL: dto.html_url,
            reviewState: reviewState,
            checkSummary: pr.checkSummary,
            actionsSummary: pr.actionsSummary
        )
    }

    func fetchPRMetadata(token: String, pr: PullRequest) async throws -> PRMetadata {
        struct DetailDTO: Decodable {
            struct UserDTO: Decodable { let login: String }
            struct LabelDTO: Decodable { let name: String }
            struct Head: Decodable { let ref: String; let sha: String }
            let mergeable_state: String?
            let user: UserDTO
            let labels: [LabelDTO]
            let assignees: [UserDTO]
            let requested_reviewers: [UserDTO]
            let head: Head
        }

        let response: GitHubResponse<DetailDTO?> = try await client.get(
            "repos/\(pr.repo.owner)/\(pr.repo.name)/pulls/\(pr.number)",
            token: token,
            decoder: .github
        )
        guard let dto = response.value else {
            return PRMetadata(author: "unknown", labels: [], assignees: [], reviewers: [], mergeableState: nil, branch: pr.headRef, headSHA: pr.headSHA)
        }
        return PRMetadata(
            author: dto.user.login,
            labels: dto.labels.map(\.name),
            assignees: dto.assignees.map(\.login),
            reviewers: dto.requested_reviewers.map(\.login),
            mergeableState: dto.mergeable_state,
            branch: dto.head.ref,
            headSHA: dto.head.sha
        )
    }

    private func summarizeReviewState(reviews: [PullReviewDTO], requestedReviewers: [String]) -> String {
        let ordered = reviews.sorted {
            ($0.submitted_at ?? .distantPast) < ($1.submitted_at ?? .distantPast)
        }
        for review in ordered.reversed() {
            switch review.state.uppercased() {
            case "CHANGES_REQUESTED":
                return "changes requested"
            case "APPROVED":
                return "approved"
            case "COMMENTED":
                continue
            default:
                continue
            }
        }
        if !requestedReviewers.isEmpty { return "review requested" }
        return "pending"
    }

    private func fetchPRsForQuery(token: String,
                                  query: String,
                                  limit: Int,
                                  etags: [String: String]) async throws -> ([PullRequest], [String: String]) {
        var page = 1
        var all: [PullRequest] = []
        var nextEtags: [String: String] = [:]

        while all.count < limit {
            let perPage = min(100, limit - all.count)
            let key = "search:\(query):page:\(page)"
            let response: GitHubResponse<SearchResponse?> = try await client.get(
                "search/issues",
                token: token,
                query: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "sort", value: "updated"),
                    URLQueryItem(name: "order", value: "desc"),
                    URLQueryItem(name: "per_page", value: "\(perPage)"),
                    URLQueryItem(name: "page", value: "\(page)")
                ],
                etag: page == 1 ? etags[key] : nil,
                decoder: .github
            )

            if let etag = response.etag, page == 1 { nextEtags[key] = etag }
            guard let payload = response.value else { break }
            let mapped = payload.items.compactMap { $0.toPR() }
            all.append(contentsOf: mapped)

            if mapped.count < perPage { break }
            page += 1
        }

        return (all, nextEtags)
    }

    private func searchUnits(settings: AppSettings, quickScope: PopoverScopeSelection, userLogin: String) -> [String] {
        let allowlist = settings.scope.repoAllowlist.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !allowlist.isEmpty {
            return allowlist.map { "repo:\($0)" }
        }

        switch quickScope {
        case .all:
            var units: [String] = []
            if settings.scope.personalEnabled { units.append("") }
            if settings.scope.organizationsEnabled {
                units.append(contentsOf: settings.scope.selectedOrgs.map { "org:\($0)" })
            }
            return units
        case .personal:
            return []
        case let .organization(org):
            return ["org:\(org)"]
        }
    }
}

struct PRMetadata: Hashable {
    let author: String
    let labels: [String]
    let assignees: [String]
    let reviewers: [String]
    let mergeableState: String?
    let branch: String
    let headSHA: String
}

private struct PullReviewDTO: Decodable {
    let state: String
    let submitted_at: Date?
}

private struct SearchResponse: Decodable {
    struct Item: Decodable {
        let id: Int
        let number: Int
        let title: String
        let state: String
        let updated_at: Date
        let html_url: URL
        let pull_request: PullRef
        let repository_url: String

        struct PullRef: Decodable {
            let url: String
        }

        func toPR() -> PullRequest? {
            guard let repo = parseRepo(from: repository_url) else { return nil }
            return PullRequest(
                id: id,
                number: number,
                repo: repo,
                title: title,
                isDraft: false,
                state: state,
                headRef: "",
                headSHA: "",
                updatedAt: updated_at,
                htmlURL: html_url,
                reviewState: nil,
                checkSummary: nil,
                actionsSummary: nil
            )
        }

        private func parseRepo(from repositoryURL: String) -> RepoRef? {
            let chunks = repositoryURL.split(separator: "/")
            guard chunks.count >= 2 else { return nil }
            return RepoRef(owner: String(chunks[chunks.count - 2]), name: String(chunks.last!))
        }
    }

    let items: [Item]
}

extension JSONDecoder {
    static var github: JSONDecoder {
        let decoder = JSONDecoder.prbar
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = DateFormatter.githubISO8601.date(from: str) {
                return date
            }
            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: str) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(str)")
        }
        return decoder
    }
}
