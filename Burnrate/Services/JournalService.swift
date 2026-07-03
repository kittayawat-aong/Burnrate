import Foundation

/// Parses local Claude Code JSONL logs to produce a token breakdown.
///
/// Logs live at `~/.claude/projects/**/*.jsonl`. Each line is a JSON object;
/// assistant messages carry a `message.usage` object with the token counts.
struct JournalService {
    /// Summarize token usage for the current calendar day across all projects.
    static func summarize(since cutoff: Date? = JournalService.startOfToday()) -> TokenSummary {
        var summary = TokenSummary()
        let fm = FileManager.default
        let projectsDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard let enumerator = fm.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            LogService.shared.log(.warning, .journal, "Could not enumerate ~/.claude/projects — no token breakdown available")
            return summary
        }

        var scanned = 0
        var matched = 0
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            scanned += 1

            // Skip files not touched since the cutoff to avoid reading old logs.
            if let cutoff,
               let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let modified = values.contentModificationDate,
               modified < cutoff {
                continue
            }

            matched += 1
            summary = summary + parseFile(at: url, since: cutoff)
        }
        LogService.shared.log(.debug, .journal, "Scanned \(scanned) .jsonl file(s), \(matched) touched since cutoff — today's tokens: in \(summary.input), out \(summary.output), cache-write \(summary.cacheCreation), cache-read \(summary.cacheRead)")
        return summary
    }

    private static func parseFile(at url: URL, since cutoff: Date?) -> TokenSummary {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return TokenSummary()
        }

        var summary = TokenSummary()
        content.enumerateLines { line, _ in
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else { return }

            if let cutoff, let ts = obj["timestamp"] as? String,
               let date = isoDate(ts), date < cutoff {
                return
            }

            guard let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { return }

            summary = summary + TokenSummary(
                input: intValue(usage["input_tokens"]),
                output: intValue(usage["output_tokens"]),
                cacheCreation: intValue(usage["cache_creation_input_tokens"]),
                cacheRead: intValue(usage["cache_read_input_tokens"])
            )
        }
        return summary
    }

    private static func intValue(_ any: Any?) -> Int {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        return 0
    }

    private static func startOfToday() -> Date {
        Calendar.current.startOfDay(for: Date())
    }

    private static func isoDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}
