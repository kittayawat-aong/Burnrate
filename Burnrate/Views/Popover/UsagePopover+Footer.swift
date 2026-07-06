import SwiftUI

/// Bottom row: last-updated/next-update timestamps plus the refresh,
/// settings, and quit buttons.
extension UsagePopover {
    var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(updatedText)
                Text(nextUpdateText)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Burnrate")
        }
    }

    var nextUpdateText: String {
        guard let next = viewModel.nextUpdate else { return "Next update: —" }
        return "Next update: \(TimeFormatter.clock(next, use24Hour: settings.use24HourClock)) (in \(TimeFormatter.countdownWithSeconds(to: next)))"
    }

    var updatedText: String {
        guard let updated = viewModel.lastUpdated else { return "Not yet updated" }
        return "Updated \(TimeFormatter.clock(updated, use24Hour: settings.use24HourClock))"
    }
}
