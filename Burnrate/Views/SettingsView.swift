import SwiftUI

/// Preferences window content. Uses a custom top icon tab bar (rather than the
/// bordered SwiftUI `TabView`) so it renders cleanly inside an AppKit window.
/// Each tab's content lives in its own file under Views/Settings/.
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
        .frame(minWidth: 460, idealWidth: 460, minHeight: 360, idealHeight: 360)
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
