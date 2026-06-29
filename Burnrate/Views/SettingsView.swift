import SwiftUI

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
                    .frame(width: 68, height: 46)
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
        case .menuBar:
            MenuBarTab(settings: settings)
        case .popover:
            PopoverTab(settings: settings)
        case .notifications:
            NotificationsTab(settings: settings)
        case .polling:
            PollingTab(settings: settings)
        case .about:
            AboutTab()
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case general, menuBar, popover, notifications, polling, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .menuBar: return "Menu Bar"
            case .popover: return "Popover"
            case .notifications: return "Notifications"
            case .polling: return "Polling"
            case .about: return "About"
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .menuBar: return "menubar.rectangle"
            case .popover: return "macwindow"
            case .notifications: return "bell"
            case .polling: return "clock.arrow.circlepath"
            case .about: return "info.circle"
            }
        }
    }
}

// MARK: - Tab content

private struct GeneralTab: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

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
        }
        .formStyle(.grouped)
    }
}

private struct MenuBarTab: View {
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
        }
        .formStyle(.grouped)
    }
}

private struct PopoverTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Show in the popover") {
                Toggle("Account details", isOn: $settings.popoverShowAccount)
                Toggle("Weekly usage", isOn: $settings.popoverShowWeekly)
                Toggle("Token breakdown", isOn: $settings.popoverShowTokens)
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
            } footer: {
                captionFooter("Sends a notification once a usage window crosses the threshold.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct PollingTab: View {
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
            } footer: {
                captionFooter("On rate limiting (429), Burnrate automatically backs off to 10 minutes. Changes apply from the next check.")
            }
        }
        .formStyle(.grouped)
    }
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
