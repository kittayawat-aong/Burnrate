import SwiftUI

/// Lets the user configure Claude Code's `autoMode` classifier — trusted
/// infrastructure plus allow/deny rule overrides — without hand-editing
/// ~/.claude/settings.json. See https://code.claude.com/docs/en/auto-mode-config
struct AutoModeTab: View {
    @ObservedObject private var claudeSettings = ClaudeSettingsService.shared

    var body: some View {
        Form {
            Section {
                Toggle("Classify all shell commands", isOn: $claudeSettings.autoMode.classifyAllShell)
            } footer: {
                captionFooter("When on, every Bash/PowerShell command is checked by the auto mode classifier while it's active, instead of letting narrow allow rules (like Bash(npm test)) skip the check.")
            }

            AutoModeListEditor(
                title: "Trusted environment",
                entries: $claudeSettings.autoMode.environment,
                footer: "One entry per line, e.g. \"Source control: github.example.com/acme-corp\". Include a \"$defaults\" line to keep Claude Code's built-in trust slots and add these alongside them."
            )

            AutoModeListEditor(
                title: "Allow",
                entries: $claudeSettings.autoMode.allow,
                footer: "Exceptions to soft-deny rules, one per line. Include \"$defaults\" to keep the built-in exceptions."
            )

            AutoModeListEditor(
                title: "Soft deny",
                entries: $claudeSettings.autoMode.softDeny,
                footer: "Destructive actions explicit user intent can still override. Omitting \"$defaults\" replaces ALL built-in soft-deny rules, including force-push and curl | bash — add it unless you mean to take over the whole list."
            )

            AutoModeListEditor(
                title: "Hard deny",
                entries: $claudeSettings.autoMode.hardDeny,
                footer: "Unconditional security boundaries, never overridden by user intent or allow rules. Omitting \"$defaults\" replaces ALL built-in hard-deny rules, including data-exfiltration protections."
            )
        }
        .formStyle(.grouped)
    }
}

/// One `autoMode` string array edited as newline-separated free text.
private struct AutoModeListEditor: View {
    let title: String
    @Binding var entries: [String]
    let footer: String

    @State private var text: String = ""

    var body: some View {
        Section {
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 120)
                .onAppear { text = entries.joined(separator: "\n") }
                .onChange(of: text) { newValue in
                    entries = newValue
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                }
        } header: {
            Text(title)
        } footer: {
            captionFooter(footer)
        }
    }
}
