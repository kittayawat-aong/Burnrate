import SwiftUI

/// Title bar and the optional "Account" section shown under it.
extension UsagePopover {
    var header: some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundColor(.orange)
            Text("Burnrate")
                .font(.headline)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            }
        }
    }

    func accountSection(_ account: AccountInfo) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .foregroundColor(.secondary)
                Text("Account")
                    .font(.subheadline.weight(.medium))
            }

            ForEach(account.displayRows, id: \.label) { row in
                HStack(alignment: .top, spacing: 8) {
                    Text(row.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .font(.caption)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }
}
