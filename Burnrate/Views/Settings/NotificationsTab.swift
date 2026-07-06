import SwiftUI

struct NotificationsTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle("Notify when usage is high", isOn: $settings.notifyEnabled)

                HStack {
                    Text("Threshold")
                    Slider(value: $settings.notifyThreshold, in: 50...95, step: 5)
                    Text("\(Int(settings.notifyThreshold))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .disabled(!settings.notifyEnabled)

                Button {
                    NotificationService.send(
                        title: "Burnrate",
                        body: "Test notification — notifications are working ✅"
                    )
                } label: {
                    Label("Send test notification", systemImage: "bell.badge")
                }
            } footer: {
                captionFooter("Sends a notification once a usage window crosses the threshold. If the test does nothing, allow Burnrate in System Settings ▸ Notifications.")
            }
        }
        .formStyle(.grouped)
    }
}
