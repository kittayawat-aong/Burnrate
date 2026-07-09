import Foundation
import Combine

/// Claude Code's `autoMode` classifier settings — trusted infrastructure plus
/// allow/soft-deny/hard-deny rule overrides. See
/// https://code.claude.com/docs/en/auto-mode-config
struct AutoModeConfig: Equatable {
    var environment: [String] = []
    var allow: [String] = []
    var softDeny: [String] = []
    var hardDeny: [String] = []
    var classifyAllShell: Bool = false

    init() {}

    init(json: [String: Any]) {
        environment = (json["environment"] as? [String]) ?? []
        allow = (json["allow"] as? [String]) ?? []
        softDeny = (json["soft_deny"] as? [String]) ?? []
        hardDeny = (json["hard_deny"] as? [String]) ?? []
        classifyAllShell = (json["classifyAllShell"] as? Bool) ?? false
    }

    /// nil when every field is at its default, so `save()` can omit the
    /// `autoMode` key entirely rather than writing an empty object.
    var jsonObject: [String: Any]? {
        var obj: [String: Any] = [:]
        if !environment.isEmpty { obj["environment"] = environment }
        if !allow.isEmpty { obj["allow"] = allow }
        if !softDeny.isEmpty { obj["soft_deny"] = softDeny }
        if !hardDeny.isEmpty { obj["hard_deny"] = hardDeny }
        if classifyAllShell { obj["classifyAllShell"] = true }
        return obj.isEmpty ? nil : obj
    }
}

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

    @Published var autoMode: AutoModeConfig = AutoModeConfig() {
        didSet { save() }
    }

    private init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            LogService.shared.log(.debug, .settings, "No ~/.claude/settings.json found — using defaults")
            return
        }
        if let value = json["includeCoAuthoredBy"] as? Bool {
            includeCoAuthoredBy = value
            LogService.shared.log(.debug, .settings, "Loaded includeCoAuthoredBy=\(value) from ~/.claude/settings.json")
        }
        if let autoModeJSON = json["autoMode"] as? [String: Any] {
            autoMode = AutoModeConfig(json: autoModeJSON)
            LogService.shared.log(.debug, .settings, "Loaded autoMode config from ~/.claude/settings.json")
        }
    }

    private func save() {
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }
        json["includeCoAuthoredBy"] = includeCoAuthoredBy
        if let autoModeObject = autoMode.jsonObject {
            json["autoMode"] = autoModeObject
        } else {
            json.removeValue(forKey: "autoMode")
        }
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
