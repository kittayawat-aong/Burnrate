import Foundation
import Combine

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

    init() {
        // Restore the last successful fetch so something shows immediately,
        // even before the first (or a failing) network call.
        if let cached = UsageCache.load() {
            session = UsagePeriod(utilization: cached.sessionUtilization, resetsAt: cached.sessionResetsAt)
            weekly = UsagePeriod(utilization: cached.weeklyUtilization, resetsAt: cached.weeklyResetsAt)
            lastUpdated = cached.lastUpdated
        }
    }

    // MARK: - Display values (apply the debug simulation override if enabled)

    var effectiveSession: UsagePeriod? {
        debugApplied(session, percent: AppSettings.shared.debugSessionPercent)
    }

    var effectiveWeekly: UsagePeriod? {
        debugApplied(weekly, percent: AppSettings.shared.debugWeeklyPercent)
    }

    private func debugApplied(_ period: UsagePeriod?, percent: Double) -> UsagePeriod? {
        guard AppSettings.shared.debugSimulate else { return period }
        let resets = period?.resetsAt ?? Date().addingTimeInterval(2 * 3600)
        return UsagePeriod(utilization: percent, resetsAt: resets)
    }

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

            // Persist so values survive relaunch and remain visible on later failures.
            UsageCache.save(session: usage.session, weekly: usage.weekly, lastUpdated: lastUpdated!)

            // Phase 2: local token breakdown (best effort).
            tokenSummary = JournalService.summarize()

            runThresholdCheck()
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

    /// Evaluate thresholds against the *displayed* values (so the debug
    /// simulator triggers alerts too). Safe to call often — it only fires on
    /// a fresh crossing of the threshold.
    func runThresholdCheck() {
        notifiedSession = evaluate(
            window: "Session (5h)",
            utilization: effectiveSession?.utilization,
            alreadyNotified: notifiedSession
        )
        notifiedWeekly = evaluate(
            window: "Weekly (7d)",
            utilization: effectiveWeekly?.utilization,
            alreadyNotified: notifiedWeekly
        )
    }

    /// Returns the new "already notified" flag for the window.
    private func evaluate(window: String, utilization: Double?, alreadyNotified: Bool) -> Bool {
        let settings = AppSettings.shared
        guard settings.notifyEnabled, let utilization else { return false }

        if utilization >= settings.notifyThreshold {
            if !alreadyNotified {
                NotificationService.send(
                    title: "Claude usage high",
                    body: "\(window) is at \(Int(utilization))%."
                )
            }
            return true
        }
        // Reset once we drop back under the threshold so the next spike re-alerts.
        return false
    }
}
