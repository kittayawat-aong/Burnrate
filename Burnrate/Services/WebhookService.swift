import Foundation

enum WebhookService {
    static func send(session: UsagePeriod?, weekly: UsagePeriod?, tokens: TokenSummary?) {
        let settings = AppSettings.shared
        guard settings.webhookEnabled,
              !settings.webhookURL.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: settings.webhookURL.trimmingCharacters(in: .whitespaces))
        else { return }

        let iso = ISO8601DateFormatter()
        iso.timeZone = TimeZone(abbreviation: "UTC")

        var payload: [String: Any] = ["timestamp": iso.string(from: Date())]

        if let session {
            var s: [String: Any] = ["utilization": session.utilization]
            if let r = session.resetsAt { s["resets_at"] = iso.string(from: r) }
            payload["session"] = s
        }
        if let weekly {
            var w: [String: Any] = ["utilization": weekly.utilization]
            if let r = weekly.resetsAt { w["resets_at"] = iso.string(from: r) }
            payload["weekly"] = w
        }
        if let tokens {
            payload["tokens"] = [
                "input": tokens.input,
                "output": tokens.output,
                "cache_write": tokens.cacheCreation,
                "cache_read": tokens.cacheRead,
                "total": tokens.total
            ]
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Burnrate/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        request.timeoutInterval = 10

        LogService.shared.log(.info, .webhook, "POST \(url.absoluteString)")

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error {
                LogService.shared.log(.error, .webhook, "POST \(url.absoluteString) failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse {
                LogService.shared.log(.info, .webhook, "POST \(url.absoluteString) -> \(http.statusCode)")
            }
        }.resume()
    }
}
