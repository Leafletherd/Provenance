import SwiftUI

struct EmptyStateView: View {
    let message: String
    var systemImage: String = "doc.text.magnifyingglass"
    var body: some View {
        VStack(spacing: Brand.spaceMD) {
            Image(systemName: systemImage)
                .font(.system(size: 42))
                .foregroundColor(Brand.textMuted)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(Brand.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
