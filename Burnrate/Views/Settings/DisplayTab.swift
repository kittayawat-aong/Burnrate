import SwiftUI

struct DisplayTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Claude Code", isOn: $settings.claudeEnabled)
                Toggle("Codex", isOn: $settings.codexEnabled)
            } header: {
                Text("Providers")
            } footer: {
                captionFooter("Burnrate reads each provider independently. At least one should be enabled.")
            }

            Section {
                Toggle("Session percentage", isOn: $settings.menuBarShowSession)
                    .disabled(!settings.claudeEnabled)
                Toggle("Reset countdown", isOn: $settings.menuBarShowCountdown)
                    .disabled(!settings.claudeEnabled)
                Toggle("Weekly percentage", isOn: $settings.menuBarShowWeekly)
                    .disabled(!settings.claudeEnabled)
                Toggle("Codex usage", isOn: $settings.menuBarShowCodex)
                    .disabled(!settings.codexEnabled)
            } header: {
                Text("Show in the menu bar")
            } footer: {
                captionFooter("The flame icon is always shown.")
            }

            Section("Show in the popover") {
                Toggle("Account details", isOn: $settings.popoverShowAccount)
                Toggle("Weekly usage", isOn: $settings.popoverShowWeekly)
                Toggle("Tokens today", isOn: $settings.popoverShowTokens)
            }

            Section {
                Toggle("Use 24-hour clock", isOn: $settings.use24HourClock)
            } footer: {
                captionFooter("Affects reset time and update timestamps shown in the popover.")
            }
        }
        .formStyle(.grouped)
    }
}
