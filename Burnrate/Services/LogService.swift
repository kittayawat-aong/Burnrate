import Foundation
import Combine
import OSLog

/// In-app activity log: records every API call and other notable action
/// (keychain reads, webhook sends, notifications, settings writes, polling
/// lifecycle) so the user can see what Burnrate has been doing. Mirrors to
/// Console.app via os.Logger and persists to one file per calendar day at
/// ~/Library/Logs/Burnrate/burnrate-YYYY-MM-DD.log so history survives
/// relaunches, stays easy to skim per day, and can be shared for support.
/// Files older than `retentionDays` are deleted automatically.
///
/// `log()` is called from background contexts (URLSession completion
/// handlers, non-actor services) as well as MainActor code, so it and its
/// helpers are explicitly `nonisolated` rather than relying on the project's
/// default MainActor isolation — only the `@Published entries` array (read by
/// SwiftUI) is actor-isolated.
final class LogService: ObservableObject {
    nonisolated(unsafe) static let shared = LogService()

    @Published private(set) var entries: [LogEntry] = []
    nonisolated private let maxInMemory = 500
    nonisolated private let maxFileBytes = 2 * 1024 * 1024 // trim a day's file to its newest half once exceeded
    nonisolated private let retentionDays = 14

    nonisolated private let osLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "dev.raywel.Burnrate", category: "activity")
    nonisolated private let logsDir: URL
    nonisolated private let fileQueue = DispatchQueue(label: "dev.raywel.Burnrate.logfile", qos: .utility)

    // Pinned to Gregorian/POSIX so filenames stay yyyy-MM-dd regardless of
    // the user's calendar/locale (e.g. Thai Buddhist Era would otherwise
    // turn 2026 into 2569).
    nonisolated private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    nonisolated private init() {
        let dir = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Burnrate")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logsDir = dir
        fileQueue.async { [retentionDays, dir] in
            Self.deleteFiles(olderThan: retentionDays, in: dir)
        }
    }

    /// Records an entry. Safe to call from any thread.
    nonisolated func log(_ level: LogLevel, _ category: LogCategory, _ message: String) {
        let entry = LogEntry(level: level, category: category, message: message)

        osLog.log(level: level.osLogType, "[\(category.label, privacy: .public)] \(message, privacy: .public)")

        Task { @MainActor in
            self.append(entry)
        }
        writeToFile(entry)
    }

    @MainActor
    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxInMemory {
            entries.removeFirst(entries.count - maxInMemory)
        }
    }

    nonisolated private func fileURL(for date: Date) -> URL {
        logsDir.appendingPathComponent("burnrate-\(Self.dayFormatter.string(from: date)).log")
    }

    nonisolated private func writeToFile(_ entry: LogEntry) {
        fileQueue.async { [weak self] in
            guard let self else { return }
            let fileURL = self.fileURL(for: entry.timestamp)
            let iso = ISO8601DateFormatter()
            let line = "\(iso.string(from: entry.timestamp)) [\(entry.level.rawValue.uppercased())] [\(entry.category.label)] \(entry.message)\n"
            guard let data = line.data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }

            if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
               size > self.maxFileBytes,
               let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                let lines = content.split(separator: "\n", omittingEmptySubsequences: true)
                let tail = lines.suffix(lines.count / 2).joined(separator: "\n") + "\n"
                try? tail.write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
    }

    nonisolated private static func deleteFiles(olderThan days: Int, in dir: URL) {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
              )
        else { return }

        for file in files where file.pathExtension == "log" {
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  modified < cutoff
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Clears the in-memory log shown in Settings and truncates today's file on disk.
    nonisolated func clear() {
        Task { @MainActor in
            self.entries.removeAll()
        }
        fileQueue.async { [weak self] in
            guard let self else { return }
            try? "".write(to: self.fileURL(for: Date()), atomically: true, encoding: .utf8)
        }
    }

    /// Today's log file — used by the "Reveal" button in Settings. Other
    /// days' files live alongside it in the same folder.
    nonisolated var logFileURL: URL { fileURL(for: Date()) }
}

private extension LogLevel {
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        }
    }
}
