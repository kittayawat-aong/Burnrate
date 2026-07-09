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

    func refresh() async -> RefreshOutcome {
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
            LogService.shared.log(.error, .polling, "Refresh unauthorized — re-login required")
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

    /// Fetches usage, cascading through progressively more expensive recovery
    /// steps on a 401: a fresh (uncached) Keychain read first, in case our
    /// cache is merely stale (Claude Code rotated the token since we last
    /// read it live), then an OAuth token refresh using the stored refresh
    /// token, in case the token is genuinely expired and Claude Code CLI
    /// hasn't been run recently enough to renew it itself. The refreshed
    /// token is kept only in Burnrate's own cache — it is deliberately never
    /// written back into Claude Code's Keychain item. Refresh tokens rotate
    /// on use, so writing back risks racing (and clobbering) a refresh the
    /// CLI does on its own, which forces the CLI itself to need a re-login.
    /// Any failure along this chain surfaces as `UsageAPIError.unauthorized`
    /// so the caller's existing re-login messaging applies.
    private func fetchUsageResilient(credentials: OAuthCredentials, source: CredentialsSource) async throws -> (usage: UsageResponse, note: String) {
        do {
            let usage = try await UsageAPIService.fetchUsage(accessToken: credentials.accessToken)
            return (usage, source == .live ? "live" : "cached")
        } catch UsageAPIError.unauthorized {
            var latest = credentials

            if source == .cache {
                LogService.shared.log(.warning, .keychain, "Cached credentials were rejected (401) — retrying with a fresh Keychain read before reporting expiry")
                do {
                    latest = try KeychainService.retryLiveRead()
                    let usage = try await UsageAPIService.fetchUsage(accessToken: latest.accessToken)
                    return (usage, "cached, retried live")
                } catch UsageAPIError.unauthorized {
                    // Fall through to the refresh attempt below.
                } catch {
                    // Live Keychain read itself failed (e.g. "In dark wake, no
                    // UI possible" while the Mac is asleep) — that's not proof
                    // the token is expired, so don't give up here. Fall through
                    // and try the OAuth refresh token instead, which needs no
                    // Keychain access at all.
                    LogService.shared.log(.warning, .keychain, "Live Keychain retry failed (\(error.localizedDescription)) — falling through to OAuth refresh")
                }
            }

            guard let refreshToken = latest.refreshToken else {
                throw UsageAPIError.unauthorized
            }

            do {
                LogService.shared.log(.warning, .keychain, "Access token rejected (401) — attempting OAuth refresh")
                let refreshed = try await TokenRefreshService.refresh(refreshToken: refreshToken)
                CredentialsCache.save(OAuthCredentials(
                    accessToken: refreshed.accessToken,
                    refreshToken: refreshed.refreshToken,
                    expiresAt: refreshed.expiresAt
                ))
                LogService.shared.log(.info, .keychain, "OAuth refresh succeeded — cached in Burnrate only (not written back to Keychain)")

                let usage = try await UsageAPIService.fetchUsage(accessToken: refreshed.accessToken)
                return (usage, "refreshed")
            } catch UsageAPIError.unauthorized {
                LogService.shared.log(.error, .keychain, "OAuth refresh succeeded but the new access token was still rejected")
                throw UsageAPIError.unauthorized
            } catch {
                LogService.shared.log(.warning, .keychain, "OAuth refresh failed: \(error.localizedDescription)")
                throw UsageAPIError.unauthorized
            }
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
