import SwiftUI

/// Small caption-style footer text shared across the Settings tabs.
func captionFooter(_ text: String) -> some View {
    Text(text)
        .font(.caption)
        .foregroundColor(.secondary)
}
