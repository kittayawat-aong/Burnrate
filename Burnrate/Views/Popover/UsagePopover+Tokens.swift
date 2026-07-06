import SwiftUI

/// The "Tokens today" breakdown — toggled via Settings ▸ Display ▸
/// "Tokens today" (`AppSettings.popoverShowTokens`).
extension UsagePopover {
    func tokenBreakdown(_ tokens: TokenSummary) -> some View {
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

    func tokenLine(_ label: String, _ value: Int, bold: Bool = false) -> some View {
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

    func formatTokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
