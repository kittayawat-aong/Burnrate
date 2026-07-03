import Foundation

enum LogLevel: String, Codable {
    case debug, info, warning, error

    var symbol: String {
        switch self {
        case .debug: return "·"
        case .info: return "ℹ︎"
        case .warning: return "⚠︎"
        case .error: return "✕"
        }
    }
}

enum LogCategory: String, Codable, CaseIterable {
    case api, keychain, webhook, notification, settings, journal, account, polling, ui

    var label: String {
        switch self {
        case .api: return "API"
        case .keychain: return "Keychain"
        case .webhook: return "Webhook"
        case .notification: return "Notification"
        case .settings: return "Settings"
        case .journal: return "Journal"
        case .account: return "Account"
        case .polling: return "Polling"
        case .ui: return "UI"
        }
    }
}

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String

    init(timestamp: Date = Date(), level: LogLevel, category: LogCategory, message: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }
}
