import AppKit
import SwiftUI

/// Maps a 0–100 utilization value to the traffic-light color scheme:
/// 🟢 < 50%, 🟡 50–80%, 🔴 > 80%.
enum UsageColor {
    static func nsColor(for utilization: Double) -> NSColor {
        switch utilization {
        case ..<50: return .systemGreen
        case ..<80: return .systemYellow
        default: return .systemRed
        }
    }

    static func swiftUIColor(for utilization: Double) -> Color {
        switch utilization {
        case ..<50: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }
}
