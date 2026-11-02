import SwiftUI

/// Bottom row: last-updated/next-update timestamps plus the keep-awake,
/// refresh, settings, and quit buttons.
extension UsagePopover {
    var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(updatedText)
                Text(nextUpdateText)
                if caffeinate.isActive {
                    Text(keepAwakeText)
                        .foregroundColor(.brown)
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            Spacer()
            keepAwakeMenu
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

    var keepAwakeMenu: some View {
        Menu {
            if caffeinate.isActive {
                Button("Turn Off") { caffeinate.stop() }
                Divider()
            }
            ForEach(CaffeinateService.durations, id: \.self) { duration in
                Button(CaffeinateService.label(for: duration)) {
                    caffeinate.start(duration: duration, mode: settings.caffeinateMode)
                }
            }
        } label: {
            Image(systemName: caffeinate.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(caffeinate.isActive ? "Keep awake is on" : "Keep Mac awake")
    }

    var keepAwakeText: String {
        guard let end = caffeinate.endsAt else { return "☕ Awake until turned off" }
        return "☕ Awake until \(TimeFormatter.clock(end, use24Hour: settings.use24HourClock))"
    }

    var nextUpdateText: String {
        guard let next = viewModel.nextUpdate else { return "Next update: —" }
        return "Next update: \(TimeFormatter.clock(next, use24Hour: settings.use24HourClock)) (in \(TimeFormatter.countdownWithSeconds(to: next)))"
    }

    var updatedText: String {
        guard let updated = viewModel.mostRecentUpdate else { return "Not yet updated" }
        return "Updated \(TimeFormatter.clock(updated, use24Hour: settings.use24HourClock))"
    }
}
