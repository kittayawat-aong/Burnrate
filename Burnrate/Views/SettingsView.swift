import SwiftUI
import AppKit

/// Preferences window content. Uses a custom top icon tab bar (rather than the
/// bordered SwiftUI `TabView`) so it renders cleanly inside an AppKit window.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var tab: Tab = .general

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 460, height: 360)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 18))
                        Text(item.title)
                            .font(.caption)
                    }
                    .frame(width: 52, height: 46)
                    .foregroundColor(tab == item ? .accentColor : .primary)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(tab == item ? Color.secondary.opacity(0.18) : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .general:
            GeneralTab()
        case .display:
            DisplayTab(settings: settings)
        case .notifications:
            NotificationsTab(settings: settings)
        case .webhook:
            WebhookTab(settings: settings)
        case .advanced:
            AdvancedTab(settings: settings)
        case .logs:
            LogsTab()
        case .about:
            AboutTab()
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case general, display, notifications, webhook, advanced, logs, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .display: return "Display"
            case .notifications: return "Notifications"
            case .webhook: return "Webhook"
            case .advanced: return "Advanced"
            case .logs: return "Logs"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .display: return "macwindow"
            case .notifications: return "bell"
            case .webhook: return "antenna.radiowaves.left.and.right"
            case .advanced: return "slider.horizontal.3"
            case .logs: return "doc.text.magnifyingglass"
            case .about: return "info.circle"
            }
        }
    }
}

// MARK: - Tab content

private struct GeneralTab: View {
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

private struct DisplayTab: View {
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
                Toggle("Token breakdown", isOn: $settings.popoverShowTokens)
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

private struct NotificationsTab: View {
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

private struct AdvancedTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Check usage every", selection: $settings.pollIntervalMinutes) {
                    Text("1 minute").tag(1)
                    Text("2 minutes").tag(2)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                }
            } header: {
                Text("Polling")
            } footer: {
                captionFooter("On rate limiting (429), Burnrate automatically backs off to 10 minutes. Changes apply from the next check.")
            }

            Section {
                Toggle("Simulate usage", isOn: $settings.debugSimulate)

                HStack {
                    Text("Session")
                    Slider(value: $settings.debugSessionPercent, in: 0...100, step: 1)
                    Text("\(Int(settings.debugSessionPercent))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                HStack {
                    Text("Weekly")
                    Slider(value: $settings.debugWeeklyPercent, in: 0...100, step: 1)
                    Text("\(Int(settings.debugWeeklyPercent))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }

                Button {
                    settings.debugSimulate = true
                    settings.debugSessionPercent = min(100, settings.debugSessionPercent + 5)
                } label: {
                    Label("Burn +5%", systemImage: "flame.fill")
                }
            } header: {
                Text("Simulated values (no real tokens used)")
            } footer: {
                captionFooter("Overrides what the menu bar and popover display so you can preview colors and thresholds. Real usage is unaffected.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct WebhookTab: View {
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

private struct LogsTab: View {
    @ObservedObject private var log = LogService.shared
    @State private var didCopy = false
    @State private var filter: LogCategory?

    private var filteredEntries: [LogEntry] {
        guard let filter else { return log.entries }
        return log.entries.filter { $0.category == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryBar

            Divider()

            if filteredEntries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(log.entries.isEmpty ? "No activity yet" : "No entries in this category")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(filteredEntries) { entry in
                        logRow(entry).id(entry.id)
                    }
                    .listStyle(.inset)
                    .onChange(of: log.entries.count) { _ in
                        if let last = filteredEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("\(filteredEntries.count) of \(log.entries.count) entries · saved daily to ~/Library/Logs/Burnrate/")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    copyToClipboard()
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(filteredEntries.isEmpty)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([log.logFileURL])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }

                Button(role: .destructive) {
                    log.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(log.entries.isEmpty)
            }
            .padding(10)
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(nil, title: "All")
                ForEach(LogCategory.allCases, id: \.self) { category in
                    categoryChip(category, title: category.label)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func categoryChip(_ category: LogCategory?, title: String) -> some View {
        Button {
            filter = category
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(filter == category ? Color.accentColor : Color.secondary.opacity(0.15))
                )
                .foregroundColor(filter == category ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(entry.category.label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 68, alignment: .leading)

            Text(entry.message)
                .font(.caption)
                .foregroundColor(color(for: entry.level))
                .textSelection(.enabled)
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }

    private func copyToClipboard() {
        let text = filteredEntries.map { entry in
            "\(Self.timeFormatter.string(from: entry.timestamp)) [\(entry.category.label)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 52))
                .foregroundColor(.orange)
            Text("Burnrate")
                .font(.title2.bold())
            Text("Claude Code usage in your menu bar")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Version \(AppInfo.version)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func captionFooter(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundColor(.secondary)
}
