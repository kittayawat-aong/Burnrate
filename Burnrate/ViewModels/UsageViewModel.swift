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

    // The resetsAt date of the period we last sent a threshold alert for.
    // Nil = no alert sent yet. Changes to a new date when the period resets,
    // which automatically allows a fresh alert for the new period.
    private var notifiedSessionPeriod: Date?
    private var notifiedWeeklyPeriod: Date?

    func refresh() async -> RefreshOutcome {
        isLoading = true
        notifyUpdate()
        defer {
            isLoading = false
            notifyUpdate()
        }

        if account == nil {
            account = AccountService.loadAccount()
        }

        do {
            let credentials = try KeychainService.loadCredentials()

            if credentials.isExpired {
                errorMessage = "Token expired — re-login via Claude Code"
                return .tokenExpired
            }

            // Capture old reset dates before overwriting.
            let prevSessionResetsAt = session?.resetsAt
            let prevWeeklyResetsAt  = weekly?.resetsAt

            let usage = try await UsageAPIService.fetchUsage(accessToken: credentials.accessToken)
            session = usage.session
            weekly  = usage.weekly
            lastUpdated = Date()
            errorMessage = nil

            UsageCache.save(session: usage.session, weekly: usage.weekly, lastUpdated: lastUpdated!)
            tokenSummary = JournalService.summarize()

            // Detect period resets (new resetsAt is meaningfully later than the old one).
            if periodDidReset(prev: prevSessionResetsAt, next: usage.session.resetsAt) {
                notifiedSessionPeriod = nil
                NotificationService.send(
                    title: "Session reset",
                    body: "Your 5-hour Claude session has reset — you're back to 0%."
                )
            }
            if periodDidReset(prev: prevWeeklyResetsAt, next: usage.weekly.resetsAt) {
                notifiedWeeklyPeriod = nil
                NotificationService.send(
                    title: "Weekly reset",
                    body: "Your 7-day Claude usage has reset — you're back to 0%."
                )
            }

            runThresholdCheck()
            WebhookService.send(session: usage.session, weekly: usage.weekly, tokens: tokenSummary)
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

    // MARK: - Threshold notifications

    /// Fires a threshold alert at most once per usage period (identified by resetsAt).
    /// Call only after a successful fetch — not on every settings change.
    func runThresholdCheck() {
        let settings = AppSettings.shared
        guard settings.notifyEnabled else { return }

        checkThreshold(
            window: "Session (5h)",
            period: effectiveSession,
            notifiedPeriod: &notifiedSessionPeriod
        )
        checkThreshold(
            window: "Weekly (7d)",
            period: effectiveWeekly,
            notifiedPeriod: &notifiedWeeklyPeriod
        )
    }

    private func checkThreshold(window: String, period: UsagePeriod?, notifiedPeriod: inout Date?) {
        let settings = AppSettings.shared
        guard let utilization = period?.utilization,
              utilization >= settings.notifyThreshold else { return }

        // Truncate to the minute so sub-second API timestamp drift doesn't
        // make the same period look like a new one on every poll.
        let raw = period?.resetsAt ?? .distantFuture
        let periodKey = Date(timeIntervalSinceReferenceDate:
            (raw.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        guard notifiedPeriod != periodKey else { return }

        NotificationService.send(
            title: "Claude usage high",
            body: "\(window) is at \(Int(utilization))%."
        )
        notifiedPeriod = periodKey
    }

    /// Returns true when the period has rolled over to a new window.
    private func periodDidReset(prev: Date?, next: Date?) -> Bool {
        guard let prev, let next else { return false }
        return next.timeIntervalSince(prev) > 60
    }
}
