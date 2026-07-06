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

            Divider()

            if settings.popoverShowAccount, let account = viewModel.account {
                accountSection(account)
                Divider()
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
                }

                if settings.popoverShowTokens, let tokens = viewModel.tokenSummary, tokens.total > 0 {
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
}
