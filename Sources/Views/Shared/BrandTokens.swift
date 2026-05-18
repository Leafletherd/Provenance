import SwiftUI
import AppKit

// MARK: - Process Suite Design Tokens
// Provenance — Archival Teal
// Source: PROCESS_SUITE_DESIGN_STANDARDS.md §1 · REV-3 update
//
// Rules:
//   • No drop shadows, no gradients in UI chrome
//   • Borders always 0.5px
//   • Elevation via background color difference only
//   • System UI for all app chrome; Playfair Display for splash/marketing only
//   • Surface + text tokens are dynamic (light/dark); accent + status stay single-hex

enum Brand {

    // MARK: - Surfaces — loaded from xcassets Color Sets (per ui_color_assignment.html).
    // The asset catalog is compiled to Assets.car by actool in make-app.sh.
    // SwiftUI's Color("name", bundle: .main) reads from that catalog at runtime
    // and properly adapts to light/dark mode via NSColor.systemBackground semantics.
    static let surfaceBase     = Color("surfaceBase", bundle: .main)
    static let surfaceSidebar  = Color("surfaceSidebar", bundle: .main)
    static let surfaceRaised   = Color("surfaceRaised", bundle: .main)
    static let surfaceSunken   = Color("surfaceSunken", bundle: .main)
    static let surfaceSelected = Color("surfaceSelected", bundle: .main)
    static let border          = Color("borderUI", bundle: .main)
    static let borderSubtle    = Color("borderSubtle", bundle: .main)

    // MARK: - Text
    static let textPrimary   = Color("textPrimary", bundle: .main)
    static let textSecondary = Color("textSecondary", bundle: .main)
    static let textMuted     = Color("textMuted", bundle: .main)
    static let textBrand     = Color("textBrand", bundle: .main)

    // MARK: - Floating chrome tokens (§5b, §5c — REV-6/7)
    /// Floating toolbar pill background — matches surface-raised per spec.
    static let surfaceFloating  = Color("surfaceFloating", bundle: .main)
    /// Titlebar background — surfaceSidebar + 5% per-app tint wash (per spec § 00).
    static let titlebarBg       = Color("titlebarBg", bundle: .main)
    /// Pill drop shadow: #000 @10% in light, .clear in dark (value contrast handles elevation in dark).
    static let pillShadow       = Color(NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
        case .darkAqua: return NSColor(white: 0, alpha: 0)
        default:        return NSColor(white: 0, alpha: 0.05)
        }
    })
    /// Icon hover fill: ~6% black in light, ~8% white in dark (Apple Mail pattern).
    static let surfaceHover     = Color(NSColor(name: nil) { appearance in
        switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
        case .darkAqua: return NSColor(white: 1, alpha: 0.08)
        default:        return NSColor(white: 0, alpha: 0.06)
        }
    })

    // MARK: - Provenance Accent + tint — loaded from xcassets
    static let accent      = Color("accent", bundle: .main)
    static let accentDark  = Color("accentDark", bundle: .main)
    static let accentLight = Color(hex: "2DC490")  // icon gradient top — single hex, not adaptive
    static let tintSurface = Color("tintSurface", bundle: .main)
    static let tintBorder  = Color("tintBorder", bundle: .main)
    /// Legacy alias used in existing code — points to new tintSurface.
    static let accentDim   = tintSurface

    // MARK: - Radii (as CGFloat for use with .cornerRadius / clipShape)
    static let radiusSm: CGFloat =   3
    static let radiusMd: CGFloat =   6
    static let radiusLg: CGFloat =  10
    static let radiusPill: CGFloat = 999

    // MARK: - Spacing
    static let spaceXS: CGFloat =  4
    static let spaceSM: CGFloat =  8
    static let spaceMD: CGFloat = 12
    static let spaceLG: CGFloat = 20
    static let spaceXL: CGFloat = 32

    // MARK: - Status colors (single-hex — designed to read on both light and dark warm surfaces)
    static let statusWorking      = Color(hex: "1D9E75") // teal — on-brand
    static let statusStuck        = Color(hex: "C0783A") // warm amber-orange
    static let statusBreakthrough = Color(hex: "2B8A3E") // deep green
    static let statusPaused       = Color(hex: "8C8A84") // slate-400
    static let statusDone         = Color(hex: "5A6480") // dusty slate
    static let statusPaste        = Color(hex: "7C6F9F") // muted violet — paste/origin events
}

// MARK: - Color(hex:) initializer (static hex)

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: Double
        switch h.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >>  8) & 0xFF) / 255
            b = Double( int        & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(red: r, green: g, blue: b)
    }

    // Dynamic color that adapts to macOS light/dark mode
    init(light lightHex: String, dark darkHex: String) {
        self.init(NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return NSColor(brandHex: darkHex)
            default:        return NSColor(brandHex: lightHex)
            }
        })
    }
}

// MARK: - NSColor hex initializer (used by dynamic Color init above)

private extension NSColor {
    convenience init(brandHex hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r, g, b: CGFloat
        switch h.count {
        case 6:
            r = CGFloat((int >> 16) & 0xFF) / 255
            g = CGFloat((int >>  8) & 0xFF) / 255
            b = CGFloat( int        & 0xFF) / 255
        default:
            r = 1; g = 1; b = 1
        }
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Shared panel header modifier

struct PanelHeaderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Brand.spaceLG)
            .padding(.vertical, Brand.spaceMD)
            .background(Brand.surfaceBase)
            .overlay(Divider().opacity(0.6), alignment: .bottom)
    }
}

extension View {
    func panelHeader() -> some View {
        modifier(PanelHeaderStyle())
    }
}

// MARK: - TypeBadge (shared tag pill)

struct TypeBadge: View {
    let label: String
    var color: Color = Brand.accent

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, Brand.spaceSM)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .overlay(
                RoundedRectangle(cornerRadius: Brand.radiusSm)
                    .stroke(color.opacity(0.25), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Brand.radiusSm))
    }
}
