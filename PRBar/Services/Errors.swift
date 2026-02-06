import Foundation

enum AppError: LocalizedError {
    case missingToken
    case invalidResponse
    case httpError(Int, String)
    case decodingError
    case rateLimited(reset: Date?)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "Missing GitHub token. Add one in Settings."
        case .invalidResponse:
            return "Received invalid response from GitHub."
        case let .httpError(code, message):
            return "GitHub error \(code): \(message)"
        case .decodingError:
            return "Failed to decode GitHub response."
        case let .rateLimited(reset):
            if let reset {
                return "Rate limited until \(reset.formatted(date: .omitted, time: .shortened))."
            }
            return "GitHub API rate limit exceeded."
        case let .keychain(status):
            return "Keychain error: \(status)"
        }
    }
}

struct RateLimitInfo: Codable, Hashable {
    var limit: Int = 0
    var remaining: Int = 0
    var reset: Date?
}
