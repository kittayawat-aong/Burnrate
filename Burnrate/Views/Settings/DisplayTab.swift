import SwiftUI

struct DisplayTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Session percentage", isOn: $settings.menuBarShowSession)
                Toggle("Reset countdown", isOn: $settings.menuBarShowCountdown)
                Toggle("Weekly percentage", isOn: $settings.menuBarShowWeekly)
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
