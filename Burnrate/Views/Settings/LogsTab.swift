import SwiftUI
import AppKit

struct LogsTab: View {
    @ObservedObject private var log = LogService.shared
    @State private var didCopy = false
    @State private var filter: LogCategory?

    private var filteredEntries: [LogEntry] {
        guard let filter else { return log.entries }
        return log.entries.filter { $0.category == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryBar

            Divider()

            if filteredEntries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text(log.entries.isEmpty ? "No activity yet" : "No entries in this category")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(filteredEntries) { entry in
                        LogRow(entry: entry).id(entry.id)
                    }
                    .listStyle(.inset)
                    .onChange(of: log.entries.count) { _ in
                        if let last = filteredEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("\(filteredEntries.count) of \(log.entries.count) entries · saved daily to ~/Library/Logs/Burnrate/")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    copyToClipboard()
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(filteredEntries.isEmpty)

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([log.logFileURL])
                } label: {
                    Label("Reveal", systemImage: "folder")
                }

                Button(role: .destructive) {
                    log.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(log.entries.isEmpty)
            }
            .padding(10)
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(nil, title: "All")
                ForEach(LogCategory.allCases, id: \.self) { category in
                    categoryChip(category, title: category.label)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func categoryChip(_ category: LogCategory?, title: String) -> some View {
        Button {
            filter = category
        } label: {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(filter == category ? Color.accentColor : Color.secondary.opacity(0.15))
                )
                .foregroundColor(filter == category ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private func copyToClipboard() {
        let text = filteredEntries.map { entry in
            "\(LogRow.timeFormatter.string(from: entry.timestamp)) [\(entry.category.label)] \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }
}
