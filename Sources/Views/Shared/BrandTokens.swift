import SwiftUI

// MARK: - Process Suite Design Tokens
// Provenance — Archival Teal
// Source: process_suite_brand_guidelines.html v1.0 · 2026
//
// Rules:
//   • No drop shadows, no gradients in UI chrome
//   • Borders always 0.5px
//   • Elevation via background color difference only
//   • System UI for all app chrome; Playfair Display for splash/marketing only

enum Brand {

    // MARK: - Surfaces
    static let surfaceBase   = Color(hex: "FAF6EF")  // tan-50  — window/page bg
    static let surfaceRaised = Color.white             // card bg
    static let surfaceSunken = Color(hex: "F0E8D5")  // tan-100 — inputs, wells
    static let border        = Color(hex: "DFD0B0")  // tan-200 — 0.5px borders

    // MARK: - Text
    static let textPrimary   = Color(hex: "2E2D2A")  // slate-800
    static let textSecondary = Color(hex: "5A5854")  // slate-600
    static let textMuted     = Color(hex: "8C8A84")  // slate-400
    static let textBrand     = Color(hex: "8A6E42")  // tan-600

    // MARK: - Provenance Accent (Archival Teal)
    static let accent        = Color(hex: "1D9E75")  // teal-400
    static let accentDark    = Color(hex: "186B56")  // teal-600
    static let accentLight   = Color(hex: "2DC490")  // icon gradient top
    static let accentDim     = Color(hex: "E4F2EE")  // teal-50 — tinted well

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

    // MARK: - Status colors (kept close to system; tinted toward brand palette)
    static let statusWorking     = Color(hex: "1D9E75") // teal — on-brand
    static let statusStuck       = Color(hex: "C0783A") // warm amber-orange
    static let statusBreakthrough = Color(hex: "2B8A3E") // deep green
    static let statusPaused      = Color(hex: "8C8A84") // slate-400
    static let statusDone        = Color(hex: "5A6480") // dusty slate
}

// MARK: - Color(hex:) initializer

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
