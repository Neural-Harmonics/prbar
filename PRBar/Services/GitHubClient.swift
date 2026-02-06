import Foundation

struct GitHubResponse<T> {
    let value: T
    let etag: String?
}

struct APIMetrics: Codable, Hashable {
    var total: Int = 0
    var search: Int = 0
    var prDetails: Int = 0
    var reviews: Int = 0
    var actionsRuns: Int = 0
    var checks: Int = 0
    var jobs: Int = 0
    var identity: Int = 0
    var orgs: Int = 0
    var other: Int = 0
}

actor APIMetricsTracker {
    private var metrics = APIMetrics()

    func record(path: String) {
        metrics.total += 1
        switch path {
        case "user":
            metrics.identity += 1
        case "user/orgs":
            metrics.orgs += 1
        case "search/issues":
            metrics.search += 1
        case let p where p.contains("/pulls/") && p.hasSuffix("/reviews"):
            metrics.reviews += 1
        case let p where p.contains("/pulls/"):
            metrics.prDetails += 1
        case let p where p.contains("/actions/runs/") && p.hasSuffix("/jobs"):
            metrics.jobs += 1
        case let p where p.contains("/actions/runs"):
            metrics.actionsRuns += 1
        case let p where p.contains("/check-runs"):
            metrics.checks += 1
        default:
            metrics.other += 1
        }
    }

    func snapshot() -> APIMetrics {
        metrics
    }
}

final class GitHubClient {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.github.com")!
    private(set) var rateLimit = RateLimitInfo()
    private let metricsTracker = APIMetricsTracker()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func get<T: Decodable>(_ path: String,
                           token: String,
                           query: [URLQueryItem] = [],
                           etag: String? = nil,
                           decoder: JSONDecoder = .prbar) async throws -> GitHubResponse<T?> {
        await metricsTracker.record(path: path)
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query

        guard let url = components.url else { throw AppError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.addValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.addValue("PRBar", forHTTPHeaderField: "User-Agent")
        if let etag {
            request.addValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }

        updateRateLimit(from: http)

        if http.statusCode == 304 {
            return GitHubResponse(value: nil, etag: http.value(forHTTPHeaderField: "ETag"))
        }

        if http.statusCode == 403, rateLimit.remaining == 0 {
            throw AppError.rateLimited(reset: rateLimit.reset)
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw AppError.httpError(http.statusCode, body)
        }

        do {
            let decoded = try decoder.decode(T.self, from: data)
            return GitHubResponse(value: decoded, etag: http.value(forHTTPHeaderField: "ETag"))
        } catch {
            throw AppError.decodingError
        }
    }

    private func updateRateLimit(from response: HTTPURLResponse) {
        rateLimit.limit = Int(response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "0") ?? 0
        rateLimit.remaining = Int(response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "0") ?? 0
        if let resetRaw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"), let resetUnix = TimeInterval(resetRaw) {
            rateLimit.reset = Date(timeIntervalSince1970: resetUnix)
        }
    }

    func metricsSnapshot() async -> APIMetrics {
        await metricsTracker.snapshot()
    }
}
