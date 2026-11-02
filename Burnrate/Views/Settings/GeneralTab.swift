import SwiftUI

struct GeneralTab: View {
    @ObservedObject private var settings = AppSettings.shared
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
                Picker("Mode", selection: $settings.caffeinateMode) {
                    ForEach(CaffeinateMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } header: {
                Text("Keep Awake")
            } footer: {
                captionFooter("Start keep-awake from the ☕ button in the popover. Closing the lid still sleeps the Mac unless an external display and power are connected.")
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
