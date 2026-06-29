import Foundation

enum UsageAPIError: Error, LocalizedError {
    case unauthorized
    case rateLimited
    case server(Int)
    case decoding
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Unauthorized (401) — re-login via Claude Code"
        case .rateLimited: return "Rate limited (429)"
        case .server(let code): return "Server error (\(code))"
        case .decoding: return "Could not read usage response"
        case .network(let e): return e.localizedDescription
        }
    }
}

/// Calls the undocumented Anthropic OAuth usage endpoint.
struct UsageAPIService {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetchUsage(accessToken: String) async throws -> UsageResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageAPIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageAPIError.decoding
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw UsageAPIError.unauthorized
        case 429:
            throw UsageAPIError.rateLimited
        default:
            throw UsageAPIError.server(http.statusCode)
        }

        guard let usage = UsageResponse.parse(data) else {
            throw UsageAPIError.decoding
        }
        return usage
    }
}
