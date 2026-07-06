import SwiftUI

/// The session/weekly usage bars, plus the stale-data and hard-error states
/// shown in their place when a fetch has failed.
extension UsagePopover {
    func periodRow(title: String, period: UsagePeriod?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(period.map { "\(Int($0.utilization))%" } ?? "—")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(period.map { UsageColor.swiftUIColor(for: $0.utilization) } ?? .secondary)
            }

            ProgressView(value: (period?.utilization ?? 0) / 100)
                .tint(UsageColor.swiftUIColor(for: period?.utilization ?? 0))

            Text(resetText(for: period))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    /// Thin inline warning shown above cached values when a fetch failed.
    func staleNote(_ message: String) -> some View {
        let (title, detail) = splitMessage(message)
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail == nil ? "\(title) · showing last update" : title)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundColor(.secondary)
    }

    func errorState(_ message: String) -> some View {
        let (title, detail) = splitMessage(message)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Error messages may carry a "title\ndetail" second line with
    /// user-facing instructions (e.g. the re-login hint) — split it out so
    /// it can be styled as secondary text instead of one flat sentence.
    private func splitMessage(_ message: String) -> (title: String, detail: String?) {
        guard let newlineIndex = message.firstIndex(of: "\n") else { return (message, nil) }
        return (String(message[..<newlineIndex]), String(message[message.index(after: newlineIndex)...]))
    }

    func resetText(for period: UsagePeriod?) -> String {
        guard let resetsAt = period?.resetsAt else { return "Reset time unknown" }
        return "Resets in \(TimeFormatter.countdown(to: resetsAt)) · \(TimeFormatter.resetDate(resetsAt, use24Hour: settings.use24HourClock))"
    }
}
