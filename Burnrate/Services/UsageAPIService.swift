import Foundation
import Alamofire

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
    static let endpoint = "https://api.anthropic.com/api/oauth/usage"

    static func fetchUsage(accessToken: String) async throws -> UsageResponse {
        let headers: HTTPHeaders = [
            .authorization(bearerToken: accessToken),
            HTTPHeader(name: "anthropic-beta", value: "oauth-2025-04-20"),
            .accept("application/json")
        ]

        LogService.shared.log(.debug, .api, "GET /api/oauth/usage — Authorization: Bearer \(redacted(accessToken)), anthropic-beta: oauth-2025-04-20")

        let start = Date()
        // No .validate() — non-2xx status codes are handled explicitly below,
        // same as the previous raw-URLSession version (Alamofire only treats
        // a request as failed here for actual transport-level errors).
        let response = await AF.request(endpoint, method: .get, headers: headers) {
            $0.timeoutInterval = 20
        }
        .serializingData()
        .response
        let ms = elapsedMs(since: start)

        guard let http = response.response else {
            let message = response.error?.localizedDescription ?? "unknown network error"
            LogService.shared.log(.error, .api, "GET /api/oauth/usage network error after \(ms)ms: \(message)")
            throw UsageAPIError.network(response.error ?? URLError(.unknown))
        }

        let data = response.data ?? Data()

        switch http.statusCode {
        case 200:
            LogService.shared.log(.debug, .api, "GET /api/oauth/usage -> 200 (\(data.count) bytes, \(ms)ms) — \(bodySnippet(data))")
        case 401:
            LogService.shared.log(.warning, .api, "GET /api/oauth/usage -> 401 Unauthorized (\(ms)ms) — \(bodySnippet(data))")
            throw UsageAPIError.unauthorized
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").map { " (Retry-After: \($0)s)" } ?? ""
            LogService.shared.log(.warning, .api, "GET /api/oauth/usage -> 429 Rate limited\(retryAfter) (\(ms)ms) — \(bodySnippet(data))")
            throw UsageAPIError.rateLimited
        default:
            LogService.shared.log(.error, .api, "GET /api/oauth/usage -> \(http.statusCode) (\(ms)ms) — \(bodySnippet(data))")
            throw UsageAPIError.server(http.statusCode)
        }

        guard let usage = UsageResponse.parse(data) else {
            LogService.shared.log(.error, .api, "GET /api/oauth/usage: could not parse response body — \(bodySnippet(data))")
            throw UsageAPIError.decoding
        }

        LogService.shared.log(.info, .api, "Usage parsed — session \(describe(usage.session)), weekly \(describe(usage.weekly))")
        return usage
    }

    private static func describe(_ period: UsagePeriod) -> String {
        let resets = period.resetsAt.map(isoFormatter.string) ?? "unknown"
        return "\(Int(period.utilization))% (resets \(resets))"
    }

    private static func elapsedMs(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    /// Shows just enough of the token to correlate log lines without leaking
    /// a usable credential into the log file.
    private static func redacted(_ token: String) -> String {
        guard token.count > 12 else { return "***" }
        return "\(token.prefix(8))…\(token.suffix(4))"
    }

    private static let isoFormatter = ISO8601DateFormatter()

    /// A log-safe preview of a response body (usage/error payloads only —
    /// never request headers/tokens). Pretty-prints JSON with indentation so
    /// it's actually readable in the Logs tab / log file, falling back to
    /// the raw text for non-JSON bodies. Truncated so one bad response can't
    /// blow up the log file.
    private static func bodySnippet(_ data: Data) -> String {
        guard !data.isEmpty else { return "(empty body)" }

        if let object = try? JSONSerialization.jsonObject(with: data),
           let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: pretty, encoding: .utf8) {
            return text.count > 4000 ? String(text.prefix(4000)) + "\n…" : text
        }

        let text = String(data: data, encoding: .utf8) ?? "(non-UTF8 body, \(data.count) bytes)"
        return text.count > 2000 ? String(text.prefix(2000)) + "…" : text
    }
}
