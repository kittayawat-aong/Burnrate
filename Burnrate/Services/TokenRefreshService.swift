import Foundation
import Alamofire

enum TokenRefreshError: Error, LocalizedError {
    case network(Error)
    case rejected(Int)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .network(let e): return e.localizedDescription
        case .rejected(let code): return "Token refresh rejected (\(code))"
        case .invalidResponse: return "Could not parse token refresh response"
        }
    }
}

struct RefreshedTokens {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

/// Refreshes an expired Claude Code access token using the refresh token
/// Claude Code itself stores in Keychain, mirroring what the `claude` CLI
/// does internally. The endpoint and client_id are undocumented — reverse
/// engineered the same way as `UsageAPIService`'s endpoint — so any failure
/// here (network, rejected, unparsable) is treated as non-fatal by the
/// caller: it just means the existing re-login prompt applies.
struct TokenRefreshService {
    static let endpoint = "https://console.anthropic.com/v1/oauth/token"
    static let clientId = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    static func refresh(refreshToken: String) async throws -> RefreshedTokens {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId
        ]

        let start = Date()
        let dataTask = AF.request(
            endpoint,
            method: .post,
            parameters: body,
            encoder: JSONParameterEncoder.default
        ).serializingData()

        let response = await dataTask.response
        let ms = Int(Date().timeIntervalSince(start) * 1000)

        switch response.result {
        case .failure(let error):
            LogService.shared.log(.warning, .api, "POST /oauth/token -> network error (\(ms)ms) — \(error.localizedDescription)")
            throw TokenRefreshError.network(error)
        case .success(let data):
            let status = response.response?.statusCode ?? 0
            guard (200...299).contains(status) else {
                LogService.shared.log(.warning, .api, "POST /oauth/token -> \(status) (\(ms)ms)")
                throw TokenRefreshError.rejected(status)
            }
            guard
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                let access = json["access_token"] as? String,
                let refresh = json["refresh_token"] as? String
            else {
                LogService.shared.log(.warning, .api, "POST /oauth/token -> 2xx (\(ms)ms) but response was unparsable")
                throw TokenRefreshError.invalidResponse
            }

            var expiresIn: Double = 3600
            if let secs = json["expires_in"] as? Double {
                expiresIn = secs
            } else if let secs = json["expires_in"] as? Int {
                expiresIn = Double(secs)
            }

            LogService.shared.log(.info, .api, "POST /oauth/token -> success (\(ms)ms)")
            return RefreshedTokens(accessToken: access, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expiresIn))
        }
    }
}
