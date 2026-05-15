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

    // MARK: - Surfaces (dynamic light/dark)
    static let surfaceBase   = Color(light: "FAF6EF", dark: "1A1916")  // tan-50 / warm near-black
    static let surfaceRaised = Color(light: "FFFFFF", dark: "26241F")  // card bg
    static let surfaceSunken = Color(light: "F0E8D5", dark: "14130F")  // inputs, wells
    static let border        = Color(light: "DFD0B0", dark: "3A352C")  // 0.5px borders

    // MARK: - Text (dynamic light/dark)
    static let textPrimary   = Color(light: "2E2D2A", dark: "F0EBE3")  // slate-800 / warm white
    static let textSecondary = Color(light: "5A5854", dark: "B8B2A8")  // slate-600 / warm mid-gray
    static let textMuted     = Color(light: "8C8A84", dark: "6B665E")  // slate-400 / warm dim
    static let textBrand     = Color(light: "8A6E42", dark: "C7A56C")  // tan-600 / lifted for dark

    // MARK: - Interactive states (dynamic)
    static let surfaceSelected = Color(light: "EDE4D0", dark: "3A352C")  // active tab / selected item

    // MARK: - Provenance Accent (single-hex — works in both modes)
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
