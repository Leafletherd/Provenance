import SwiftUI

struct FloatingPill<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Brand.surfaceFloating))
        .shadow(color: Brand.pillShadow, radius: 8, x: 0, y: 2)
    }
}

struct PillIconButton: View {
    let systemImage: String?
    let assetName: String?
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false

    init(systemImage: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.assetName = nil
        self.isActive = isActive
        self.action = action
    }
    init(asset: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.systemImage = nil
        self.assetName = asset
        self.isActive = isActive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if let sys = systemImage { Image(systemName: sys) }
                else if let asset = assetName { Image(asset).renderingMode(.template) }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(isActive ? Brand.accent : Brand.textSecondary)
            .frame(width: 28, height: 28)
            .background(Circle().fill(hovering ? Brand.surfaceHover : Color.clear))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct PillDivider: View {
    var body: some View {
        Rectangle()
            .fill(Brand.border)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 2)
    }
}

struct PillPrimaryAction: View {
    let systemImage: String?
    let assetName: String?
    let label: String
    let action: () -> Void
    @State private var hovering = false

    init(systemImage: String, label: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.assetName = nil
        self.label = label
        self.action = action
    }
    init(asset: String, label: String, action: @escaping () -> Void) {
        self.systemImage = nil
        self.assetName = asset
        self.label = label
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Group {
                    if let sys = systemImage { Image(systemName: sys) }
                    else if let asset = assetName { Image(asset).renderingMode(.template) }
                }
                .font(.system(size: 14, weight: .medium))
                Text(label)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundColor(Brand.textBrand)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(hovering ? Brand.surfaceHover : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
