import SwiftUI

struct GeneralTab: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @ObservedObject private var claudeSettings = ClaudeSettingsService.shared

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { newValue in
                        if !LaunchAtLogin.set(newValue) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            } footer: {
                captionFooter("Start Burnrate automatically when you log in.")
            }

            Section {
                Toggle("Include Co-Authored-By in commits", isOn: $claudeSettings.includeCoAuthoredBy)
            } footer: {
                captionFooter("Adds a \"Co-Authored-By: Claude\" line to git commits made by Claude Code. Writes to ~/.claude/settings.json.")
            }
        }
        .formStyle(.grouped)
    }
}
