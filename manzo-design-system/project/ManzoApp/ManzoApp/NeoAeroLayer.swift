import AppKit

// MARK: - NeoAeroLayerFactory (D-09)
// Static factory that builds the Neo-Aero 5-layer CALayer specular chrome stack.
//
// Architecture (spike 008, D-09):
//   container (CALayer, masksToBounds=true, cornerRadius=10, shouldRasterize=true, rasterizationScale=2.0)
//   ├── [1] base       CAGradientLayer  full bounds, cornerRadius=10, 2-stop linear gradient
//   ├── [2] specular   CAGradientLayer  top 52% of bounds, 3-stop white-alpha (50%→8%→0%)
//   ├── [3] lowerGlow  CAGradientLayer  bottom 25% of bounds, 2-stop white-alpha (0%→12%)
//   └── [4] rim        CALayer          bounds.insetBy(dx:0.5, dy:0.5), borderWidth=1.0
//
// All brand colors use CGColor(colorSpace: displayP3) — never sRGB (D-05, VIS-03).
// masksToBounds off-screen rendering mitigated by shouldRasterize=true (D-08, spike 008 landmine).
// rasterizationScale=2.0 always paired with shouldRasterize=true (Retina requirement, CLAUDE.md).

struct NeoAeroLayerFactory {

    // MARK: - Palette

    private struct Palette {
        let baseTop:    CGColor
        let baseBottom: CGColor
        let specTop:    CGColor
        let specMid:    CGColor
        let specBtm:    CGColor
        let glowTop:    CGColor
        let glowBtm:    CGColor
        let rimColor:   CGColor
    }

    // palette(for:) — extract per-theme P3 colors.
    // All brand colors constructed via CGColorSpace.displayP3 (D-05).
    // .wszSkin falls through to .winampClassic (v2 placeholder — no palette defined, D-04).
    private static func palette(for theme: ColorTheme) -> Palette {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

        // Shared white-alpha overlay colors (specular and rim — same for winampClassic and neoAero)
        let specTopWhite = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.50])!
        let specMidWhite = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.08])!
        let specBtmClear = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.00])!
        let glowTopClear = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.00])!
        let glowBtmWhite = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.12])!
        let rimWhite     = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.45])!

        switch theme {
        case .winampClassic, .wszSkin:
            // Pixel-sampled from Winamp/Src/Winamp/resource/MAIN.BMP (275×116, 8-bit palette).
            // #181829 top, #39395A bottom — within sRGB gamut; P3 components numerically equal.
            return Palette(
                baseTop:    CGColor(colorSpace: p3, components: [0.09, 0.09, 0.16, 1.0])!,
                baseBottom: CGColor(colorSpace: p3, components: [0.22, 0.22, 0.35, 1.0])!,
                specTop:    specTopWhite,
                specMid:    specMidWhite,
                specBtm:    specBtmClear,
                glowTop:    glowTopClear,
                glowBtm:    glowBtmWhite,
                rimColor:   rimWhite
            )

        case .neoAero:
            // Frutiger Aero / Vista Aero aqua palette — P3-native, outside sRGB gamut.
            return Palette(
                baseTop:    CGColor(colorSpace: p3, components: [0.05, 0.78, 0.82, 1.0])!,
                baseBottom: CGColor(colorSpace: p3, components: [0.02, 0.52, 0.60, 1.0])!,
                specTop:    specTopWhite,
                specMid:    specMidWhite,
                specBtm:    specBtmClear,
                glowTop:    glowTopClear,
                glowBtm:    glowBtmWhite,
                rimColor:   rimWhite
            )

        case .indigoTeal:
            // Deep navy-teal — cold, OLED-optimized variant.
            // Ice blue specular tint: P3(0.74, 0.87, 0.90) instead of pure white.
            let specTopIce = CGColor(colorSpace: p3, components: [0.74, 0.87, 0.90, 0.50])!
            let specMidIce = CGColor(colorSpace: p3, components: [0.74, 0.87, 0.90, 0.08])!
            let specBtmIce = CGColor(colorSpace: p3, components: [0.74, 0.87, 0.90, 0.00])!
            return Palette(
                baseTop:    CGColor(colorSpace: p3, components: [0.04, 0.09, 0.20, 1.0])!,
                baseBottom: CGColor(colorSpace: p3, components: [0.10, 0.22, 0.28, 1.0])!,
                specTop:    specTopIce,
                specMid:    specMidIce,
                specBtm:    specBtmIce,
                glowTop:    glowTopClear,
                glowBtm:    glowBtmWhite,
                rimColor:   rimWhite
            )
        }
    }

    // MARK: - Public API

    /// Build the full 5-layer Neo-Aero chrome stack for a panel.
    ///
    /// Returns a container `CALayer` (cornerRadius=10, masksToBounds=true) with 4 sublayers:
    /// base, specular, lowerGlow, rim. The container is tagged "NeoAeroContainer" so that
    /// `applyStyle()` in ManzoRootView can locate and remove it by name on style change (D-09, D-10).
    ///
    /// - Parameters:
    ///   - style: Current `ManzoVisualStyle` — drives colorTheme and panelLayout.
    ///   - bounds: Frame for the container layer (full panel or full root view bounds).
    /// - Returns: Configured container `CALayer` ready for `addSublayer`.
    static func make(style: ManzoVisualStyle, bounds: CGRect) -> CALayer {
        NSLog("MANZO Phase 6: NeoAeroLayerFactory.make — layout=%@, theme=%@, bounds=%@",
              style.panelLayout.rawValue, style.colorTheme.rawValue, NSStringFromRect(bounds))

        let pal = palette(for: style.colorTheme)

        // [1] Base gradient — full bounds, cornerRadius=10 for clipping at base layer level
        let base = CAGradientLayer()
        base.colors       = [pal.baseTop, pal.baseBottom]
        base.cornerRadius = 10
        base.frame        = bounds

        // [2] Specular band — top 52% of bounds; 3-stop white-alpha gradient
        let specular = CAGradientLayer()
        specular.colors    = [pal.specTop, pal.specMid, pal.specBtm]
        specular.locations = [0.0, 0.45, 1.0]
        specular.frame     = CGRect(x: 0, y: 0,
                                    width: bounds.width,
                                    height: bounds.height * 0.52)

        // [3] Lower glow — bottom 25% of bounds; 2-stop glow edge
        let lowerGlow = CAGradientLayer()
        lowerGlow.colors = [pal.glowTop, pal.glowBtm]
        lowerGlow.frame  = CGRect(x: 0, y: bounds.height * 0.75,
                                  width: bounds.width,
                                  height: bounds.height * 0.25)

        // [4] Rim highlight — 0.5pt inset, cornerRadius=9.5 (= 10 - borderWidth/2), 1pt border
        let rim = CALayer()
        rim.frame        = bounds.insetBy(dx: 0.5, dy: 0.5)
        rim.cornerRadius = 9.5
        rim.borderWidth  = 1.0
        rim.borderColor  = pal.rimColor

        // [5] Container — clips sublayers to rounded rect; rasterization caches the stack (D-08)
        let container = CALayer()
        container.cornerRadius  = 10
        container.masksToBounds = true
        container.frame         = bounds
        container.addSublayer(base)
        container.addSublayer(specular)
        container.addSublayer(lowerGlow)
        container.addSublayer(rim)
        // D-08: shouldRasterize=true makes masksToBounds off-screen render a one-time cost.
        // rasterizationScale=2.0 MUST be paired — omitting causes blurry layers on Retina (CLAUDE.md).
        container.shouldRasterize    = true
        container.rasterizationScale = 2.0

        // Tag container for layer-removal in applyStyle() — identify by name (D-09, D-10)
        container.setValue("NeoAeroContainer", forKey: "name")

        return container
    }

    /// Build a simplified 2-layer chrome stack (base + rim only, cornerRadius=0).
    ///
    /// Used by `.bodyFocus` layout for `titleView` and `statusView` (14pt panels) where the
    /// full specular stack would be visually cramped. No specular band, no lower glow. (D-03)
    ///
    /// - Parameters:
    ///   - style: Current `ManzoVisualStyle` — drives colorTheme.
    ///   - bounds: Frame for the container layer (typically 275×14 pt panel bounds).
    /// - Returns: Configured container `CALayer` ready for `addSublayer`.
    static func makeSimplified(style: ManzoVisualStyle, bounds: CGRect) -> CALayer {
        NSLog("MANZO Phase 6: NeoAeroLayerFactory.makeSimplified — theme=%@, bounds=%@",
              style.colorTheme.rawValue, NSStringFromRect(bounds))

        let pal = palette(for: style.colorTheme)

        // [1] Base gradient — full bounds, cornerRadius=0 (flat edge, no bubble rounding)
        let base = CAGradientLayer()
        base.colors       = [pal.baseTop, pal.baseBottom]
        base.cornerRadius = 0
        base.frame        = bounds

        // [2] Rim highlight — 0.5pt inset, cornerRadius=0, 1pt border
        let rim = CALayer()
        rim.frame        = bounds.insetBy(dx: 0.5, dy: 0.5)
        rim.cornerRadius = 0
        rim.borderWidth  = 1.0
        rim.borderColor  = pal.rimColor

        // Container — cornerRadius=0, clips sublayers, rasterized
        let container = CALayer()
        container.cornerRadius  = 0
        container.masksToBounds = true
        container.frame         = bounds
        container.addSublayer(base)
        container.addSublayer(rim)
        // D-08: pair shouldRasterize + rasterizationScale (CLAUDE.md constraint)
        container.shouldRasterize    = true
        container.rasterizationScale = 2.0

        // Tag container for layer-removal in applyStyle() (D-09, D-10)
        container.setValue("NeoAeroContainer", forKey: "name")

        return container
    }
}
