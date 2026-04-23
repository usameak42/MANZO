import AppKit

// ManzoRootView: the single root NSVisualEffectView for the MANZO window.
//
// Minimum deployment: macOS 26. No #available fallback.
//
// Architecture constraint (spike 007 — ABSOLUTE MAXIMUM):
//   Exactly ONE NSVisualEffectView with .behindWindow blending per window.
//   ALL inner panels (titleView, bodyView, statusView) are plain NSView with
//   wantsLayer = true. They are NOT NSVisualEffectView. Nesting a second
//   .behindWindow view causes a double-blur artifact (milky, washed-out) with
//   no crash or warning — silent visual corruption.
//
// Panel layout matches classic Winamp (Winamp/Src/winamp/draw_main.cpp:draw_tbar()):
//   titleView  — 14 pt (update_area(0,0,275,14))
//   bodyView   — 88 pt (116 − 14 − 14)
//   statusView — 14 pt (symmetric with title bar)
//
// Phase 6 insertion points: titleView.layer, bodyView.layer, statusView.layer
// receive CAGradientLayer sublayers for the Neo-Aero visual stack.
// Phase 5 leaves all three layer trees EMPTY — no sublayers, no backgroundColor.

// D-01: Liquid Glass material — macOS 26 SDK name unconfirmed at planning time.
// Day-one action: 30-min Xcode prototype on macOS 26 SDK to find correct case.
// Expected: .glass or similar. Update ONLY this constant when confirmed.
// No #available fallback — macOS 26 minimum deployment (D-02).
private let ManzoGlassMaterial: NSVisualEffectView.Material = .hudWindow  // TBD: replace .hudWindow with confirmed .glass case name

private let kTitleBarHeight:  CGFloat = 14   // Winamp draw_tbar() update_area(0,0,275,14)
private let kStatusBarHeight: CGFloat = 14   // symmetric with title bar
private let kBodyHeight:      CGFloat = 88   // kWindowHeight − kTitleBarHeight − kStatusBarHeight

class ManzoRootView: NSVisualEffectView {

    // D-08: three named structural NSViews — NOT NSVisualEffectView (spike 007 rule).
    // Phase 6 adds CAGradientLayer sublayers into these views' existing layer property.
    let titleView  = NSView()
    let bodyView   = NSView()
    let statusView = NSView()

    // Designated initializer.
    // D-07: configure vibrancy material, blending mode, state, layer settings.
    override init(frame: NSRect) {
        super.init(frame: frame)

        // D-07: single root .behindWindow — the ONLY NSVisualEffectView in this window.
        material     = ManzoGlassMaterial
        blendingMode = .behindWindow
        state        = .active
        wantsLayer   = true
        layer?.cornerRadius = 0   // D-07: rectangular in Phase 5; Phase 6 may add corner radius

        setupPanels()

        NSLog("MANZO Phase 5: ManzoRootView initialized — material=%@, blendingMode=behindWindow", "\(material.rawValue)")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }

    // MARK: - Panel Setup

    // D-08/D-09/D-10: configure and constrain the three structural NSViews.
    // Each panel: wantsLayer=true, isOpaque=false, plain CALayer backing.
    // Auto Layout via NSLayoutAnchor — no frame-based layout (D-10).
    private func setupPanels() {
        for panel in [titleView, bodyView, statusView] {
            panel.translatesAutoresizingMaskIntoConstraints = false
            panel.wantsLayer = true        // D-09: CALayer backing
            // D-09: transparent — NSView.isOpaque is a get-only computed property; NSView
            // returns false by default when wantsLayer=true and no background color is set.
            // No assignment needed (and the compiler rejects it as get-only).
            // D-09: plain CALayer() — Phase 6 inserts CAGradientLayer sublayers here.
            // Do NOT add sublayers, set backgroundColor, or specialize layer type in Phase 5.
            addSubview(panel)
        }

        NSLayoutConstraint.activate([
            // titleView — top 14 pt strip
            titleView.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleView.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleView.topAnchor.constraint(equalTo: topAnchor),
            titleView.heightAnchor.constraint(equalToConstant: kTitleBarHeight),

            // statusView — bottom 14 pt strip
            statusView.leadingAnchor.constraint(equalTo: leadingAnchor),
            statusView.trailingAnchor.constraint(equalTo: trailingAnchor),
            statusView.bottomAnchor.constraint(equalTo: bottomAnchor),
            statusView.heightAnchor.constraint(equalToConstant: kStatusBarHeight),

            // bodyView — fills the middle between title and status
            bodyView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bodyView.topAnchor.constraint(equalTo: titleView.bottomAnchor),
            bodyView.bottomAnchor.constraint(equalTo: statusView.topAnchor),
        ])

        NSLog("MANZO Phase 5: panels constrained — titleView 14pt / bodyView 88pt / statusView 14pt")
    }

    // MARK: - Drag

    // D-11: full-chrome drag — matches Winamp main_nonclient.cpp return HTCLIENT for all pixels.
    // Interactive controls added in Phase 6+ consume mouseDown in their own subviews first;
    // drag falls through to unoccupied chrome naturally. No hit-test exclusion zones needed.
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
