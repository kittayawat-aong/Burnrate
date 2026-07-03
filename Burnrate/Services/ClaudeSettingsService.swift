import Foundation
import Combine

/// Reads and writes ~/.claude/settings.json so the user can tweak Claude Code
/// settings without leaving the app.
@MainActor
final class ClaudeSettingsService: ObservableObject {
    static let shared = ClaudeSettingsService()

    private let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    @Published var includeCoAuthoredBy: Bool = true {
        didSet { save() }
    }

    private init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = json["includeCoAuthoredBy"] as? Bool
        else {
            LogService.shared.log(.debug, .settings, "No includeCoAuthoredBy key in ~/.claude/settings.json — using default (true)")
            return
        }
        includeCoAuthoredBy = value
        LogService.shared.log(.debug, .settings, "Loaded includeCoAuthoredBy=\(value) from ~/.claude/settings.json")
    }

    private func save() {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }
        json["includeCoAuthoredBy"] = includeCoAuthoredBy
        guard let data = try? JSONSerialization.data(
            withJSONObject: json,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        do {
            try data.write(to: fileURL)
            LogService.shared.log(.info, .settings, "Wrote ~/.claude/settings.json (includeCoAuthoredBy=\(includeCoAuthoredBy))")
        } catch {
            LogService.shared.log(.error, .settings, "Failed to write ~/.claude/settings.json: \(error.localizedDescription)")
        }
    }
}
