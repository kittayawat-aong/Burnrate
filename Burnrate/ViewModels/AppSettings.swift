import Foundation
import Combine

enum MenuBarProvider: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }
    var title: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "ChatGPT"
        }
    }
}

/// User preferences for what Burnrate displays. Persisted to UserDefaults and
/// shared across the menu bar, popover, and settings window.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // Providers
    @Published var claudeEnabled: Bool { didSet { defaults.set(claudeEnabled, forKey: Keys.claudeEnabled) } }
    @Published var codexEnabled: Bool { didSet { defaults.set(codexEnabled, forKey: Keys.codexEnabled) } }

    // Menu bar
    @Published var menuBarShowSession: Bool { didSet { defaults.set(menuBarShowSession, forKey: Keys.menuBarShowSession) } }
    @Published var menuBarShowCountdown: Bool { didSet { defaults.set(menuBarShowCountdown, forKey: Keys.menuBarShowCountdown) } }
    @Published var menuBarShowWeekly: Bool { didSet { defaults.set(menuBarShowWeekly, forKey: Keys.menuBarShowWeekly) } }
    @Published var menuBarProvider: MenuBarProvider {
        didSet { defaults.set(menuBarProvider.rawValue, forKey: Keys.menuBarProvider) }
    }

    // Popover
    @Published var popoverShowAccount: Bool { didSet { defaults.set(popoverShowAccount, forKey: Keys.popoverShowAccount) } }
    @Published var popoverShowWeekly: Bool { didSet { defaults.set(popoverShowWeekly, forKey: Keys.popoverShowWeekly) } }
    @Published var popoverShowTokens: Bool { didSet { defaults.set(popoverShowTokens, forKey: Keys.popoverShowTokens) } }

    // Notifications
    @Published var notifyEnabled: Bool { didSet { defaults.set(notifyEnabled, forKey: Keys.notifyEnabled) } }
    @Published var notifyThreshold: Double { didSet { defaults.set(notifyThreshold, forKey: Keys.notifyThreshold) } }

    // Polling
    @Published var pollIntervalMinutes: Int { didSet { defaults.set(pollIntervalMinutes, forKey: Keys.pollIntervalMinutes) } }

    // Time format
    @Published var use24HourClock: Bool { didSet { defaults.set(use24HourClock, forKey: Keys.use24HourClock) } }

    // Webhook
    @Published var webhookEnabled: Bool { didSet { defaults.set(webhookEnabled, forKey: Keys.webhookEnabled) } }
    @Published var webhookURL: String { didSet { defaults.set(webhookURL, forKey: Keys.webhookURL) } }

    // MQTT
    @Published var mqttEnabled: Bool { didSet { defaults.set(mqttEnabled, forKey: Keys.mqttEnabled) } }
    @Published var mqttHost: String { didSet { defaults.set(mqttHost, forKey: Keys.mqttHost) } }
    @Published var mqttUsername: String { didSet { defaults.set(mqttUsername, forKey: Keys.mqttUsername) } }
    @Published var mqttTopic: String { didSet { defaults.set(mqttTopic, forKey: Keys.mqttTopic) } }
    /// Stored as plain text by user choice, to avoid Keychain authorization
    /// prompts while using a local MQTT broker.
    @Published var mqttPassword: String { didSet { defaults.set(mqttPassword, forKey: Keys.mqttPassword) } }

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
        claudeEnabled = bool(Keys.claudeEnabled, default: true)
        codexEnabled = bool(Keys.codexEnabled, default: true)
        menuBarShowSession = bool(Keys.menuBarShowSession, default: true)
        menuBarShowCountdown = bool(Keys.menuBarShowCountdown, default: true)
        menuBarShowWeekly = bool(Keys.menuBarShowWeekly, default: false)
        menuBarProvider = MenuBarProvider(
            rawValue: store.string(forKey: Keys.menuBarProvider) ?? ""
        ) ?? .claude
        popoverShowAccount = bool(Keys.popoverShowAccount, default: true)
        popoverShowWeekly = bool(Keys.popoverShowWeekly, default: true)
        popoverShowTokens = bool(Keys.popoverShowTokens, default: true)
        notifyEnabled = bool(Keys.notifyEnabled, default: true)
        notifyThreshold = double(Keys.notifyThreshold, default: 80)
        pollIntervalMinutes = int(Keys.pollIntervalMinutes, default: 5)
        use24HourClock = bool(Keys.use24HourClock, default: false)
        webhookEnabled = bool(Keys.webhookEnabled, default: false)
        webhookURL = store.string(forKey: Keys.webhookURL) ?? ""
        let mqttHostValue = store.string(forKey: Keys.mqttHost) ?? ""
        let mqttUsernameValue = store.string(forKey: Keys.mqttUsername) ?? ""
        let mqttTopicValue = store.string(forKey: Keys.mqttTopic) ?? ""
        mqttHost = mqttHostValue
        mqttUsername = mqttUsernameValue
        mqttTopic = mqttTopicValue
        mqttPassword = store.string(forKey: Keys.mqttPassword) ?? ""
        // Versions before persistent MQTT saved mqttEnabled as false while
        // only offering a one-shot connection test. Enable existing broker
        // configurations once; afterward the user's toggle always wins.
        if !bool(Keys.mqttPersistentMigrationComplete, default: false) {
            mqttEnabled = !mqttHostValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !mqttTopicValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            store.set(true, forKey: Keys.mqttPersistentMigrationComplete)
        } else {
            mqttEnabled = bool(Keys.mqttEnabled, default: true)
        }
        debugSimulate = bool(Keys.debugSimulate, default: false)
        debugSessionPercent = double(Keys.debugSessionPercent, default: 40)
        debugWeeklyPercent = double(Keys.debugWeeklyPercent, default: 15)
    }

    private enum Keys {
        static let claudeEnabled = "claudeEnabled"
        static let codexEnabled = "codexEnabled"
        static let menuBarShowSession = "menuBarShowSession"
        static let menuBarShowCountdown = "menuBarShowCountdown"
        static let menuBarShowWeekly = "menuBarShowWeekly"
        static let menuBarProvider = "menuBarProvider"
        static let popoverShowAccount = "popoverShowAccount"
        static let popoverShowWeekly = "popoverShowWeekly"
        static let popoverShowTokens = "popoverShowTokens"
        static let notifyEnabled = "notifyEnabled"
        static let notifyThreshold = "notifyThreshold"
        static let pollIntervalMinutes = "pollIntervalMinutes"
        static let use24HourClock = "use24HourClock"
        static let webhookEnabled = "webhookEnabled"
        static let webhookURL = "webhookURL"
        static let mqttHost = "mqttHost"
        static let mqttEnabled = "mqttEnabled"
        static let mqttUsername = "mqttUsername"
        static let mqttTopic = "mqttTopic"
        static let mqttPassword = "mqttPassword"
        static let mqttPersistentMigrationComplete = "mqttPersistentMigrationComplete"
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
