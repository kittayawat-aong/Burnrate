import Foundation
import Combine
import UserNotifications

/// Result of a refresh, used by the AppDelegate to decide the next poll delay.
enum RefreshOutcome {
    case success
    case rateLimited
    case tokenExpired
    case error
}

@MainActor
final class UsageViewModel: ObservableObject {
    @Published private(set) var session: UsagePeriod?
    @Published private(set) var weekly: UsagePeriod?
    @Published private(set) var tokenSummary: TokenSummary?
    @Published private(set) var account: AccountInfo?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var nextUpdate: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false

    /// Called after any state change so AppKit (status item) can redraw.
    var onUpdate: (() -> Void)?

    /// Set by the AppDelegate when it schedules the next poll.
    func setNextUpdate(_ date: Date) {
        nextUpdate = date
    }

    /// Forces observing views to re-render (used to tick live countdowns).
    func tick() {
        objectWillChange.send()
    }

    /// Tracks whether we already alerted for the current >80% episode, per window.
    private var notifiedSession = false
    private var notifiedWeekly = false

    func refresh() async -> RefreshOutcome {
        isLoading = true
        notifyUpdate()
        defer {
            isLoading = false
            notifyUpdate()
        }

        // Account info rarely changes — load it once.
        if account == nil {
            account = AccountService.loadAccount()
        }

        do {
            let credentials = try KeychainService.loadCredentials()

            if credentials.isExpired {
                errorMessage = "Token expired — re-login via Claude Code"
                return .tokenExpired
            }

            let usage = try await UsageAPIService.fetchUsage(accessToken: credentials.accessToken)
            session = usage.session
            weekly = usage.weekly
            lastUpdated = Date()
            errorMessage = nil

            // Phase 2: local token breakdown (best effort).
            tokenSummary = JournalService.summarize()

            checkThresholds(usage)
            return .success
        } catch UsageAPIError.rateLimited {
            errorMessage = "Rate limited (429) — backing off"
            return .rateLimited
        } catch UsageAPIError.unauthorized {
            errorMessage = "Unauthorized — re-login via Claude Code"
            return .tokenExpired
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .error
        }
    }

    private func notifyUpdate() {
        onUpdate?()
    }

    // MARK: - Threshold notifications (Phase 2)

    private func checkThresholds(_ usage: UsageResponse) {
        notifiedSession = evaluate(
            window: "Session (5h)",
            utilization: usage.session.utilization,
            alreadyNotified: notifiedSession
        )
        notifiedWeekly = evaluate(
            window: "Weekly (7d)",
            utilization: usage.weekly.utilization,
            alreadyNotified: notifiedWeekly
        )
    }

    /// Returns the new "already notified" flag for the window.
    private func evaluate(window: String, utilization: Double, alreadyNotified: Bool) -> Bool {
        if utilization > 80 {
            if !alreadyNotified {
                sendNotification(
                    title: "Claude usage high",
                    body: "\(window) is at \(Int(utilization))%."
                )
            }
            return true
        }
        // Reset once we drop back under the threshold so the next spike re-alerts.
        return false
    }

    private func sendNotification(title: String, body: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
}
