import Foundation
import Combine

/// Result of a refresh, used by the AppDelegate to decide the next poll delay.
enum RefreshOutcome: Equatable {
    case success
    case rateLimited(retryAfter: TimeInterval?)
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

    // Set when a refresh ends in .tokenExpired: the Keychain item's
    // modification date at that moment. While the item stays unchanged a
    // re-login hasn't happened, so subsequent polls skip the network
    // entirely (the fetch would just 401 again) instead of burning requests
    // toward a 429. Cleared as soon as the item changes.
    private var isAwaitingRelogin = false
    private var expiredItemDate: Date?

    func refresh() async -> RefreshOutcome {
        if isAwaitingRelogin {
            guard !Self.sameItemDate(KeychainService.itemModificationDate(), expiredItemDate) else {
                LogService.shared.log(.debug, .polling, "Still awaiting re-login — Keychain item unchanged, skipping fetch")
                return .tokenExpired
            }
            LogService.shared.log(.info, .polling, "Keychain item changed since token expired — resuming fetches")
            isAwaitingRelogin = false
            expiredItemDate = nil
        }

        LogService.shared.log(.info, .polling, "Refresh started")
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
            // Whether re-login is actually required is decided by the /usage
            // call's 401 response below, not a locally-computed expiry —
            // reading "Claude Code-credentials" can fail transiently even
            // when the token is still valid.
            let (credentials, source) = try KeychainService.loadCredentials()

            // Capture old reset dates before overwriting.
            let prevSessionResetsAt = session?.resetsAt
            let prevWeeklyResetsAt  = weekly?.resetsAt

            let (usage, credentialNote) = try await fetchUsageResilient(credentials: credentials, source: source)
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
            LogService.shared.log(.info, .polling, "Refresh succeeded (\(credentialNote) credentials) — session \(Int(usage.session.utilization))%, weekly \(Int(usage.weekly.utilization))%")
            return .success
        } catch UsageAPIError.rateLimited(let retryAfter) {
            errorMessage = "Rate limited (429) — backing off"
            LogService.shared.log(.warning, .polling, "Refresh rate limited — backing off")
            return .rateLimited(retryAfter: retryAfter)
        } catch UsageAPIError.unauthorized {
            errorMessage = "Claude Code login expired\nRun “claude” in Terminal to log in again — Burnrate will pick up the new session automatically."
            LogService.shared.log(.error, .polling, "Refresh unauthorized — re-login required; pausing fetches until the Keychain item changes")
            isAwaitingRelogin = true
            expiredItemDate = KeychainService.itemModificationDate()
            return .tokenExpired
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            LogService.shared.log(.error, .polling, "Refresh failed: \(errorMessage ?? "unknown error")")
            return .error
        }
    }

    private func notifyUpdate() {
        onUpdate?()
    }

    /// Fetches usage, retrying once on a 401 when the rejection is plausibly
    /// our own staleness: cache-sourced credentials go stale whenever Claude
    /// Code rotates its token. The Keychain item's modification date —
    /// readable without triggering the macOS access prompt — decides whether
    /// a live re-read (which *can* prompt) is worth it: an unchanged item
    /// means a re-read would return the exact token that was just rejected.
    ///
    /// Burnrate deliberately never calls the OAuth token-refresh endpoint.
    /// Refresh tokens are single-use (the server rotates them), so consuming
    /// the CLI's refresh token invalidates the copy the CLI still holds and
    /// forces the CLI itself into a re-login. A genuinely expired token is
    /// fixed by running `claude`; see the `.tokenExpired` handling in
    /// `refresh()` for how polling pauses until that happens.
    private func fetchUsageResilient(credentials: OAuthCredentials, source: CredentialsSource) async throws -> (usage: UsageResponse, note: String) {
        do {
            let usage = try await UsageAPIService.fetchUsage(accessToken: credentials.accessToken)
            return (usage, source == .live ? "live" : "cached")
        } catch UsageAPIError.unauthorized {
            guard source == .cache else { throw UsageAPIError.unauthorized }

            let itemDate = KeychainService.itemModificationDate()
            if Self.sameItemDate(itemDate, credentials.sourceModificationDate) {
                LogService.shared.log(.warning, .keychain, "Cached credentials rejected (401) and the Keychain item is unchanged — token is genuinely expired")
                throw UsageAPIError.unauthorized
            }

            LogService.shared.log(.warning, .keychain, "Cached credentials rejected (401) but the Keychain item has changed — retrying with a live read")
            let latest = try KeychainService.retryLiveRead()
            let usage = try await UsageAPIService.fetchUsage(accessToken: latest.accessToken)
            return (usage, "cached, retried live")
        }
    }

    /// Keychain modification dates survive a JSON round-trip through the
    /// credentials cache, but compare with a small tolerance rather than
    /// exact equality to be safe against sub-second encoding drift.
    private static func sameItemDate(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a.timeIntervalSince(b)) < 1
        default: return false
        }
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
