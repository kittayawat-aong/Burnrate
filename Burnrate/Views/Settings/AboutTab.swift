import SwiftUI

struct AboutTab: View {
    private let githubURL = URL(string: "https://github.com/kittayawat-aong/Burnrate")!
    private let contactEmail = "kittayawat.aong@gmail.com"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 52))
                .foregroundColor(.orange)
            Text("Burnrate")
                .font(.title2.bold())
            Text("Claude Code usage in your menu bar")
                .font(.callout)
                .foregroundColor(.secondary)
            Text("Version \(AppInfo.version)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            Divider()
                .padding(.vertical, 6)
                .frame(width: 180)

            VStack(spacing: 4) {
                Text("Made by Nonthawat K.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Link(destination: githubURL) {
                    Text("github.com/kittayawat-aong/Burnrate")
                }
                .font(.caption)
                Link(destination: URL(string: "mailto:\(contactEmail)")!) {
                    Text(contactEmail)
                }
                .font(.caption)
                Text("MIT License")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
