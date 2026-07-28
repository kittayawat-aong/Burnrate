import SwiftUI

struct MQTTTab: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var mqtt = MQTTService.shared

    var body: some View {
        Form {
            Section {
                Toggle("Keep connected", isOn: $settings.mqttEnabled)
                Label(mqtt.status.label, systemImage: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.caption)
            } footer: {
                captionFooter("Keeps a persistent connection open and subscribes to the topic below. It reconnects automatically if the broker disconnects. Client name: \(mqtt.clientIdentifier)")
            }

            Section {
                TextField("Host", text: $settings.mqttHost,
                          prompt: Text("broker.example.com or broker.example.com:1883"))
                TextField("Username (optional)", text: $settings.mqttUsername)
                SecureField("Password (optional)", text: $settings.mqttPassword)
            } header: {
                Text("Broker")
            } footer: {
                captionFooter("Use host:port to connect on a non-default port. Password is saved locally in plain text.")
            }

            Section {
                TextField("Topic", text: $settings.mqttTopic,
                          prompt: Text("burnrate/usage"))
            } header: {
                Text("Delivery")
            } footer: {
                captionFooter("This topic will be used for MQTT usage delivery when it is enabled in a later update.")
            }

            Section {
                Button {
                    mqtt.reconnect(settings: settings)
                } label: {
                    Label("Reconnect", systemImage: "arrow.clockwise")
                }
                .disabled(!settings.mqttEnabled)
            }
        }
        .formStyle(.grouped)
    }

    private var statusIcon: String {
        switch mqtt.status {
        case .connected: return "checkmark.circle.fill"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .failed: return "xmark.circle.fill"
        case .disconnected: return "circle"
        }
    }

    private var statusColor: Color {
        switch mqtt.status {
        case .connected: return .green
        case .connecting: return .secondary
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }
}
