import SwiftUI

struct DisplayTab: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                sourceRow(
                    title: "Claude Code",
                    detail: "Session, weekly usage, and local token totals",
                    symbol: "sparkles",
                    color: .orange,
                    isOn: $settings.claudeEnabled
                )
                sourceRow(
                    title: "ChatGPT / Codex",
                    detail: "Codex usage from your ChatGPT plan",
                    symbol: "terminal.fill",
                    color: .blue,
                    isOn: $settings.codexEnabled
                )
                sourceRow(
                    title: "GLM (z.ai)",
                    detail: "GLM Coding Plan usage via opencode’s saved key",
                    symbol: "brain",
                    color: .purple,
                    isOn: $settings.glmEnabled
                )
            } header: {
                Text("Data sources")
            } footer: {
                captionFooter("Enabled sources appear together in the popover. They refresh independently.")
            }

            Section {
                Picker("Show usage from", selection: $settings.menuBarProvider) {
                    ForEach(MenuBarProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Usage percentage", isOn: $settings.menuBarShowSession)
                Toggle("Reset countdown", isOn: $settings.menuBarShowCountdown)
                if settings.menuBarProvider == .claude {
                    Toggle("Weekly percentage", isOn: $settings.menuBarShowWeekly)
                }

                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                    Text(menuBarHint)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            } header: {
                Text("Menu bar")
            } footer: {
                captionFooter("Only one provider is shown so the menu bar stays compact. Its icon changes with your selection; the popover still shows every enabled source.")
            }

            Section("Show in the popover") {
                Toggle("Account details", isOn: $settings.popoverShowAccount)
                Toggle("Weekly usage", isOn: $settings.popoverShowWeekly)
                Toggle("Tokens today", isOn: $settings.popoverShowTokens)
            }

            Section {
                Toggle("Use 24-hour clock", isOn: $settings.use24HourClock)
            } footer: {
                captionFooter("Affects reset time and update timestamps shown in the popover.")
            }
        }
        .formStyle(.grouped)
    }

    private var menuBarHint: String {
        switch settings.menuBarProvider {
        case .claude:
            return settings.claudeEnabled
                ? "Showing Claude usage beside the flame."
                : "Claude is disabled above. Enable it to show live usage."
        case .codex:
            return settings.codexEnabled
                ? "Showing ChatGPT Codex usage beside the flame."
                : "ChatGPT / Codex is disabled above. Enable it to show live usage."
        case .glm:
            return settings.glmEnabled
                ? "Showing GLM (z.ai) usage beside the flame."
                : "GLM is disabled above. Enable it to show live usage."
        }
    }

    private func sourceRow(
        title: String,
        detail: String,
        symbol: String,
        color: Color,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.vertical, 3)
    }
}
