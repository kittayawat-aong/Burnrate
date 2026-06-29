import SwiftUI

/// SwiftUI content shown inside the NSPopover.
struct UsagePopover: View {
    @ObservedObject var viewModel: UsageViewModel

    var onRefresh: () -> Void
    var onQuit: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            Divider()

            if let error = viewModel.errorMessage, viewModel.session == nil {
                errorState(error)
            } else {
                periodRow(title: "Session (5h)", period: viewModel.session)
                periodRow(title: "Weekly (7d)", period: viewModel.weekly)

                if let tokens = viewModel.tokenSummary, tokens.total > 0 {
                    Divider()
                    tokenBreakdown(tokens)
                }
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundColor(.orange)
            Text("Burnrate")
                .font(.headline)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
        }
    }

    private func periodRow(title: String, period: UsagePeriod?) -> some View {
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

    private func tokenBreakdown(_ tokens: TokenSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tokens today")
                .font(.subheadline.weight(.medium))
            tokenLine("Input", tokens.input)
            tokenLine("Output", tokens.output)
            tokenLine("Cache write", tokens.cacheCreation)
            tokenLine("Cache read", tokens.cacheRead)
            tokenLine("Total", tokens.total, bold: true)
        }
    }

    private func tokenLine(_ label: String, _ value: Int, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .caption.weight(.semibold) : .caption)
            Spacer()
            Text(formatTokens(value))
                .font(.caption.monospacedDigit())
                .fontWeight(bold ? .semibold : .regular)
        }
        .foregroundColor(bold ? .primary : .secondary)
    }

    private func errorState(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { newValue in
                    if !LaunchAtLogin.set(newValue) {
                        // Revert if the system rejected the change.
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }

            HStack {
                Text(updatedText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
                Button(action: onQuit) {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Quit Burnrate")
            }
        }
    }

    // MARK: - Helpers

    private func resetText(for period: UsagePeriod?) -> String {
        guard let resetsAt = period?.resetsAt else { return "Reset time unknown" }
        return "Resets in \(TimeFormatter.countdown(to: resetsAt)) · \(TimeFormatter.resetDate(resetsAt))"
    }

    private var updatedText: String {
        guard let updated = viewModel.lastUpdated else { return "Not yet updated" }
        return "Updated \(TimeFormatter.clock(updated))"
    }

    private func formatTokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
