import Foundation

/// Formats reset times for the menu bar and popover.
enum TimeFormatter {
    /// "2h 30m", "45m", "3d 4h", or "now".
    static func countdown(to date: Date) -> String {
        let interval = date.timeIntervalSinceNow
        if interval <= 0 { return "now" }

        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60

        if hours >= 24 {
            let days = hours / 24
            return "\(days)d \(hours % 24)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// Compact, space-free variant for the menu bar: "2h30m", "45m", "3d4h", "now".
    static func compactCountdown(to date: Date) -> String {
        countdown(to: date).replacingOccurrences(of: " ", with: "")
    }

    /// "Jul 3, 5:00 AM".
    static func resetDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, h:mm a"
        return formatter.string(from: date)
    }

    /// "10:42 AM".
    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
