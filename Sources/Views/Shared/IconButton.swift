import SwiftUI

/// Reusable icon-only button with Apple-Mail-style circular hover background (§5c).
/// Use for all toolbar pill icons, sidebar actions, and in-row icon-only buttons.
///
///     IconButton(systemImage: "plus", helpText: "Add item") { addItem() }
///
struct IconButton: View {
    let systemImage: String
    let helpText: String
    var iconSize: CGFloat = 14
    var iconColor: Color = Brand.textSecondary
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundColor(iconColor)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(hovering ? Brand.surfaceHover : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
    }
}
