import Foundation
import Combine

/// User preferences for what Burnrate displays. Persisted to UserDefaults and
/// shared across the menu bar, popover, and settings window.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // Menu bar
    @Published var menuBarShowSession: Bool { didSet { defaults.set(menuBarShowSession, forKey: Keys.menuBarShowSession) } }
    @Published var menuBarShowCountdown: Bool { didSet { defaults.set(menuBarShowCountdown, forKey: Keys.menuBarShowCountdown) } }
    @Published var menuBarShowWeekly: Bool { didSet { defaults.set(menuBarShowWeekly, forKey: Keys.menuBarShowWeekly) } }

    // Popover
    @Published var popoverShowAccount: Bool { didSet { defaults.set(popoverShowAccount, forKey: Keys.popoverShowAccount) } }
    @Published var popoverShowWeekly: Bool { didSet { defaults.set(popoverShowWeekly, forKey: Keys.popoverShowWeekly) } }
    @Published var popoverShowTokens: Bool { didSet { defaults.set(popoverShowTokens, forKey: Keys.popoverShowTokens) } }

    // Notifications
    @Published var notifyEnabled: Bool { didSet { defaults.set(notifyEnabled, forKey: Keys.notifyEnabled) } }
    @Published var notifyThreshold: Double { didSet { defaults.set(notifyThreshold, forKey: Keys.notifyThreshold) } }

    // Polling
    @Published var pollIntervalMinutes: Int { didSet { defaults.set(pollIntervalMinutes, forKey: Keys.pollIntervalMinutes) } }

    // Debug / simulation (throwaway play feature — does not touch real quota)
    @Published var debugSimulate: Bool { didSet { defaults.set(debugSimulate, forKey: Keys.debugSimulate) } }
    @Published var debugSessionPercent: Double { didSet { defaults.set(debugSessionPercent, forKey: Keys.debugSessionPercent) } }
    @Published var debugWeeklyPercent: Double { didSet { defaults.set(debugWeeklyPercent, forKey: Keys.debugWeeklyPercent) } }

    private init() {
        let store = UserDefaults.standard
        func bool(_ key: String, default fallback: Bool) -> Bool {
            store.object(forKey: key) == nil ? fallback : store.bool(forKey: key)
        }
        func double(_ key: String, default fallback: Double) -> Double {
            store.object(forKey: key) == nil ? fallback : store.double(forKey: key)
        }
        func int(_ key: String, default fallback: Int) -> Int {
            store.object(forKey: key) == nil ? fallback : store.integer(forKey: key)
        }
        // didSet does not fire during init, so these are pure loads.
        menuBarShowSession = bool(Keys.menuBarShowSession, default: true)
        menuBarShowCountdown = bool(Keys.menuBarShowCountdown, default: true)
        menuBarShowWeekly = bool(Keys.menuBarShowWeekly, default: false)
        popoverShowAccount = bool(Keys.popoverShowAccount, default: true)
        popoverShowWeekly = bool(Keys.popoverShowWeekly, default: true)
        popoverShowTokens = bool(Keys.popoverShowTokens, default: true)
        notifyEnabled = bool(Keys.notifyEnabled, default: true)
        notifyThreshold = double(Keys.notifyThreshold, default: 80)
        pollIntervalMinutes = int(Keys.pollIntervalMinutes, default: 5)
        debugSimulate = bool(Keys.debugSimulate, default: false)
        debugSessionPercent = double(Keys.debugSessionPercent, default: 40)
        debugWeeklyPercent = double(Keys.debugWeeklyPercent, default: 15)
    }

    private enum Keys {
        static let menuBarShowSession = "menuBarShowSession"
        static let menuBarShowCountdown = "menuBarShowCountdown"
        static let menuBarShowWeekly = "menuBarShowWeekly"
        static let popoverShowAccount = "popoverShowAccount"
        static let popoverShowWeekly = "popoverShowWeekly"
        static let popoverShowTokens = "popoverShowTokens"
        static let notifyEnabled = "notifyEnabled"
        static let notifyThreshold = "notifyThreshold"
        static let pollIntervalMinutes = "pollIntervalMinutes"
        static let debugSimulate = "debugSimulate"
        static let debugSessionPercent = "debugSessionPercent"
        static let debugWeeklyPercent = "debugWeeklyPercent"
    }
}

/// App version info from the bundle, e.g. "1.0 (1)".
enum AppInfo {
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
