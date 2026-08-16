import SwiftUI

/// SwiftUI content shown inside the NSPopover. Each section's view code lives
/// in an extension under Views/Popover/ — this file just owns the state and
/// composes them.
struct UsagePopover: View {
    @ObservedObject var viewModel: UsageViewModel
    @ObservedObject var settings: AppSettings

    var onRefresh: () -> Void
    var onOpenSettings: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if settings.claudeEnabled {
                Divider()
                providerHeader("Claude Code", symbol: "sparkles", color: .orange)

                if settings.popoverShowAccount, let account = viewModel.account {
                    accountSection(account)
                }

                if let error = viewModel.errorMessage, viewModel.session == nil {
                    errorState(error)
                } else {
                    if let error = viewModel.errorMessage {
                        staleNote(error)
                    }
                    periodRow(title: "Session (5h)", period: viewModel.effectiveSession)
                    if settings.popoverShowWeekly {
                        periodRow(title: "Weekly (7d)", period: viewModel.effectiveWeekly)
                        ForEach(viewModel.scopedLimits) { scoped in
                            periodRow(title: scopedTitle(scoped), period: scoped.period)
                        }
                    }

                    if settings.popoverShowTokens, let tokens = viewModel.tokenSummary, tokens.total > 0 {
                        tokenBreakdown(tokens)
                    }
                }
            }

            if settings.codexEnabled {
                Divider()
                providerHeader("Codex", symbol: "terminal.fill", color: .blue)

                if settings.popoverShowAccount, let account = viewModel.codexAccount {
                    codexAccountSection(account)
                }

                if let error = viewModel.codexErrorMessage, viewModel.codexLimits.isEmpty {
                    errorState(error)
                } else {
                    if let error = viewModel.codexErrorMessage {
                        staleNote(error)
                    }
                    ForEach(viewModel.codexLimits) { limit in
                        periodRow(title: limit.label, period: limit.period)
                    }
                }
            }

            if settings.glmEnabled {
                Divider()
                providerHeader("GLM (z.ai)", symbol: "brain", color: .purple)

                if settings.popoverShowAccount, let plan = viewModel.glmPlan {
                    glmPlanSection(plan)
                }

                if let error = viewModel.glmErrorMessage, viewModel.glmLimits.isEmpty {
                    errorState(error)
                } else {
                    if let error = viewModel.glmErrorMessage {
                        staleNote(error)
                    }
                    ForEach(viewModel.glmLimits) { limit in
                        periodRow(title: limit.label, period: limit.period, caption: limit.creditsText)
                    }

                    if settings.popoverShowTokens, viewModel.glmTotalTokens > 0 {
                        glmTokenBreakdown(viewModel.glmModels, total: viewModel.glmTotalTokens)
                    }
                }
            }

            Divider()

            footer
        }
        .padding(16)
        .frame(width: 310)
    }
}
