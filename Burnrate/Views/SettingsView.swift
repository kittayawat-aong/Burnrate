import SwiftUI

/// Preferences window content. A sidebar keeps the growing set of settings
/// scannable and gives each pane enough horizontal room.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var tab: Tab = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                paneHeader
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(minWidth: 680, idealWidth: 720, minHeight: 460, idealHeight: 500)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.orange)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Burnrate")
                        .font(.headline)
                    Text("Settings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            sidebarGroup("APP", tabs: [.general, .display, .notifications])
            sidebarGroup("INTEGRATIONS", tabs: [.webhook])
            sidebarGroup("CLAUDE CODE", tabs: [.autoMode])
            sidebarGroup("SYSTEM", tabs: [.advanced, .logs, .about])

            Spacer()
        }
        .padding(.bottom, 12)
        .frame(width: 176)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private func sidebarGroup(_ title: String, tabs: [Tab]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)

            ForEach(tabs) { item in
                Button {
                    tab = item
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 18)
                        Text(item.title)
                            .font(.callout)
                        Spacer()
                    }
                    .foregroundColor(tab == item ? .white : .primary)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(tab == item ? Color.accentColor : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
            }
        }
    }

    private var paneHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title)
                    .font(.title2.weight(.semibold))
                Text(tab.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
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
        case .autoMode:
            AutoModeTab()
        case .logs:
            LogsTab()
        case .about:
            AboutTab()
        }
    }

    enum Tab: String, CaseIterable, Identifiable {
        case general, display, notifications, webhook, advanced, autoMode, logs, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return "General"
            case .display: return "Display"
            case .notifications: return "Notifications"
            case .webhook: return "Webhook"
            case .advanced: return "Advanced"
            case .autoMode: return "Auto Mode"
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
            case .autoMode: return "checkmark.shield"
            case .logs: return "doc.text.magnifyingglass"
            case .about: return "info.circle"
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "Startup and Claude Code preferences"
            case .display: return "Choose what appears in the menu bar and popover"
            case .notifications: return "Usage alerts and thresholds"
            case .webhook: return "Send usage updates to another service"
            case .advanced: return "Polling and display simulation"
            case .autoMode: return "Claude Code command classification rules"
            case .logs: return "Inspect Burnrate activity and errors"
            case .about: return "Version, project, and contact information"
            }
        }
    }
}
