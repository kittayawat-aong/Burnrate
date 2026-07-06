import SwiftUI

struct WebhookTab: View {
    @ObservedObject var settings: AppSettings
    @State private var testStatus: TestStatus = .idle

    enum TestStatus: Equatable {
        case idle, sending, success
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Send webhook on each fetch", isOn: $settings.webhookEnabled)

                TextField("URL", text: $settings.webhookURL,
                          prompt: Text("https://your-server.com/webhook"))
                    .disabled(!settings.webhookEnabled)

                HStack(spacing: 8) {
                    Button {
                        sendTest()
                    } label: {
                        Label("Send test", systemImage: "paperplane")
                    }
                    .disabled(settings.webhookURL.isEmpty || testStatus == .sending)

                    switch testStatus {
                    case .idle:
                        EmptyView()
                    case .sending:
                        ProgressView().scaleEffect(0.7)
                    case .success:
                        Label("200 OK", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            } footer: {
                captionFooter("Sends a POST request with JSON after every successful fetch. Timestamp is UTC+0.")
            }
        }
        .formStyle(.grouped)
    }

    private func sendTest() {
        guard let url = URL(string: settings.webhookURL) else {
            testStatus = .failure("Invalid URL")
            return
        }
        testStatus = .sending
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["timestamp": ISO8601DateFormatter().string(from: Date()), "test": true]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    testStatus = .failure(error.localizedDescription)
                    return
                }
                if let http = response as? HTTPURLResponse {
                    testStatus = http.statusCode == 200 ? .success : .failure("HTTP \(http.statusCode)")
                } else {
                    testStatus = .failure("No response")
                }
            }
        }.resume()
    }
}
