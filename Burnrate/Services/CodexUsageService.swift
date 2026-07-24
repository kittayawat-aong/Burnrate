import Foundation

enum CodexUsageError: Error, LocalizedError {
    case notInstalled
    case launchFailed(String)
    case unavailable(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "Codex CLI not found\nInstall Codex or turn off Codex in Settings."
        case .launchFailed(let message):
            return "Could not start Codex\n\(message)"
        case .unavailable(let message):
            return "Codex usage unavailable\n\(message)"
        case .invalidResponse:
            return "Could not read Codex usage response"
        }
    }
}

/// Reads account usage through Codex's local app-server protocol. Burnrate
/// never opens ~/.codex/auth.json and never handles OpenAI credentials.
struct CodexUsageService {
    static func fetch() async throws -> CodexUsageSnapshot {
        try await Task.detached(priority: .utility) {
            try fetchBlocking()
        }.value
    }

    private static func fetchBlocking() throws -> CodexUsageSnapshot {
        guard let executable = findExecutable() else {
            throw CodexUsageError.notInstalled
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        do {
            try process.run()
        } catch {
            throw CodexUsageError.launchFailed(error.localizedDescription)
        }

        let requests: [[String: Any]] = [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "burnrate", "version": AppInfo.version],
                    "capabilities": ["experimentalApi": true]
                ]
            ],
            ["method": "initialized"],
            ["id": 2, "method": "account/rateLimits/read", "params": [:]],
            ["id": 3, "method": "account/read", "params": ["refreshToken": false]]
        ]

        do {
            for request in requests {
                let data = try JSONSerialization.data(withJSONObject: request)
                input.fileHandleForWriting.write(data)
                input.fileHandleForWriting.write(Data([0x0A]))
            }
        } catch {
            process.terminate()
            throw CodexUsageError.launchFailed(error.localizedDescription)
        }

        // account reads are asynchronous. Keep stdin open until both replies
        // arrive; app-server treats EOF as a shutdown signal and can otherwise
        // exit after initialize before the usage replies have been emitted.
        let collector = ResponseCollector()
        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if !chunk.isEmpty {
                collector.append(chunk)
            }
        }
        let completed = collector.wait(timeout: 20)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if !completed {
            process.terminate()
        }
        process.waitUntilExit()
        collector.append(output.fileHandleForReading.readDataToEndOfFile())
        let stdout = collector.data
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()

        guard completed else {
            throw CodexUsageError.unavailable("Timed out waiting for the local app-server")
        }
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CodexUsageError.unavailable(detail?.isEmpty == false ? detail! : "app-server exited unexpectedly")
        }

        return try parse(stdout)
    }

    private final class ResponseCollector: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var storage = Data()
        private var didComplete = false

        var data: Data {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            storage.append(chunk)
            let complete = Self.containsReplies(in: storage)
            if complete && !didComplete {
                didComplete = true
                lock.unlock()
                semaphore.signal()
                return
            }
            lock.unlock()
        }

        func wait(timeout: TimeInterval) -> Bool {
            semaphore.wait(timeout: .now() + timeout) == .success
        }

        private static func containsReplies(in data: Data) -> Bool {
            guard let text = String(data: data, encoding: .utf8) else { return false }
            var ids = Set<Int>()
            for line in text.split(whereSeparator: \.isNewline) {
                guard let lineData = String(line).data(using: .utf8),
                      let message = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                      let id = message["id"] as? Int else { continue }
                if id == 2 || id == 3 { ids.insert(id) }
            }
            return ids.count == 2
        }
    }

    private static func findExecutable() -> String? {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(NSHomeDirectory())/.local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func parse(_ data: Data) throws -> CodexUsageSnapshot {
        guard let text = String(data: data, encoding: .utf8) else {
            throw CodexUsageError.invalidResponse
        }

        var rateResult: [String: Any]?
        var accountResult: [String: Any]?
        var serverError: String?

        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = message["id"] as? Int else { continue }

            if let error = message["error"] as? [String: Any] {
                serverError = error["message"] as? String
                continue
            }
            guard let result = message["result"] as? [String: Any] else { continue }
            if id == 2 { rateResult = result }
            if id == 3 { accountResult = result }
        }

        if let serverError, rateResult == nil {
            throw CodexUsageError.unavailable(serverError)
        }
        guard let rateResult else { throw CodexUsageError.invalidResponse }

        let snapshots: [(String, [String: Any])]
        if let buckets = rateResult["rateLimitsByLimitId"] as? [String: [String: Any]], !buckets.isEmpty {
            snapshots = buckets.sorted { $0.key < $1.key }
        } else if let fallback = rateResult["rateLimits"] as? [String: Any] {
            snapshots = [((fallback["limitId"] as? String) ?? "codex", fallback)]
        } else {
            snapshots = []
        }

        var limits: [CodexUsageLimit] = []
        for (bucketID, snapshot) in snapshots {
            let bucketName = (snapshot["limitName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            for (position, key) in ["primary", "secondary"].enumerated() {
                guard let window = snapshot[key] as? [String: Any],
                      let used = number(window["usedPercent"]) else { continue }
                let minutes = number(window["windowDurationMins"]).map(Int.init)
                let label = windowLabel(minutes: minutes, bucketName: bucketName, bucketID: bucketID)
                let reset = number(window["resetsAt"]).map { Date(timeIntervalSince1970: $0) }
                limits.append(
                    CodexUsageLimit(
                        id: "\(bucketID)-\(position)-\(minutes ?? 0)",
                        label: label,
                        period: UsagePeriod(utilization: min(max(used, 0), 100), resetsAt: reset)
                    )
                )
            }
        }

        let accountDict = accountResult?["account"] as? [String: Any]
        let account = accountDict.map {
            CodexAccountInfo(email: $0["email"] as? String, plan: $0["planType"] as? String)
        }
        return CodexUsageSnapshot(limits: limits, account: account)
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func windowLabel(minutes: Int?, bucketName: String?, bucketID: String) -> String {
        let window: String
        switch minutes {
        case 300: window = "Session (5h)"
        case 10_080: window = "Weekly (7d)"
        case let minutes? where minutes % 1_440 == 0: window = "\(minutes / 1_440)-day"
        case let minutes? where minutes % 60 == 0: window = "\(minutes / 60)-hour"
        case let minutes?: window = "\(minutes)-minute"
        case nil: window = "Usage"
        }

        let name = bucketName?.isEmpty == false
            ? bucketName!
            : (bucketID == "codex" ? nil : bucketID)
        return name.map { "\($0) · \(window)" } ?? window
    }
}
