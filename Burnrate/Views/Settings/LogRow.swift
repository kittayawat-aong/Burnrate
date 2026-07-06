import SwiftUI

/// One row in the Logs tab list. Long messages (e.g. a pretty-printed API
/// response body) collapse to a single-line preview by default and expand
/// in place when tapped, so the list stays scannable.
struct LogRow: View {
    let entry: LogEntry
    @State private var isExpanded = false

    private var firstLine: String {
        entry.message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? entry.message
    }

    private var isCollapsible: Bool {
        entry.message.contains("\n") || entry.message.count > 140
    }

    private var previewText: String {
        firstLine.count > 140 ? String(firstLine.prefix(140)) + "…" : firstLine
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 64, alignment: .leading)

            Text(entry.category.label)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .frame(width: 68, alignment: .leading)

            Text(isExpanded || !isCollapsible ? entry.message : previewText)
                .font(.caption)
                .foregroundColor(color(for: entry.level))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            if isCollapsible {
                Spacer(minLength: 4)
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isCollapsible else { return }
            isExpanded.toggle()
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
