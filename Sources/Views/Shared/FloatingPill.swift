import SwiftUI

struct FloatingPill<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        // Feathered shadow — larger radius for soft falloff, lower opacity for
        // subtlety. Identical across all four apps for visual unity.
        .background(Capsule().fill(Brand.surfaceFloating))
        .shadow(color: Brand.pillShadow, radius: 8, x: 0, y: 1)
    }
}

struct PillIconButton: View {
    let systemImage: String?
    let assetName: String?
    let isActive: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

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
            // Per-app accent ALWAYS — explicit opacity on disabled defeats SwiftUI's greyout.
            .foregroundColor(Brand.accent)
            .opacity(isEnabled ? (isActive ? 1.0 : 0.85) : 0.35)
            .frame(width: 28, height: 28)
            .background(Circle().fill(hovering && isEnabled ? Brand.surfaceHover : Color.clear))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { if isEnabled { hovering = $0 } }
    }
}

struct PillDivider: View {
    var body: some View {
        Rectangle()
            // Brand.textMuted instead of Brand.border because in dark mode
            // Brand.border (#3A352C) is identical to surfaceFloating (#3A352C),
            // making the divider invisible. textMuted gives visible contrast
            // against the pill bg in both light and dark modes.
            .fill(Brand.textMuted.opacity(0.5))
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
    @Environment(\.isEnabled) private var isEnabled

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
                .font(.system(size: 13, weight: .medium))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            // Per-app accent — explicit opacity on disabled defeats SwiftUI's greyout.
            .foregroundColor(Brand.accent)
            .opacity(isEnabled ? 1.0 : 0.4)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(hovering && isEnabled ? Brand.surfaceHover : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { if isEnabled { hovering = $0 } }
    }
}
