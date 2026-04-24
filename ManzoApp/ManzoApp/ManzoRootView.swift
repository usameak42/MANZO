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

    // Phase 7: retained spectrum MTKView — added as subview of bodyView after applyStyle().
    private(set) var spectrumView: ManzoSpectrumView? = nil

    // Designated initializer.
    // D-07: configure vibrancy material, blending mode, state, layer settings.
    override init(frame: NSRect) {
        super.init(frame: frame)

        // D-07: single root .behindWindow — the ONLY NSVisualEffectView in this window.
        material     = ManzoGlassMaterial
        blendingMode = .behindWindow
        state        = .active
        wantsLayer   = true
        layer?.cornerRadius = 10   // D-01: glass-bubble look, updated from 0 in Phase 6
        layer?.masksToBounds = true  // clip sublayers to rounded rect

        setupPanels()

        NSLog("MANZO Phase 5: ManzoRootView initialized — material=%@, blendingMode=behindWindow", "\(material.rawValue)")
        NSLog("MANZO Phase 6: ManzoRootView ready — applyStyle() awaits AppDelegate call, cornerRadius=10")
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

    // MARK: - Phase 6: Neo-Aero Style Application (D-10)

    // Called by AppDelegate after window setup, and again when ManzoVisualStyle changes.
    // Removes existing NeoAeroContainer sublayers from all insertion points,
    // inserts fresh layers from NeoAeroLayerFactory per the new style.
    func applyStyle(_ style: ManzoVisualStyle) {
        // Remove old NeoAero layers from all possible insertion points.
        // Factory tags container layers with name "NeoAeroContainer" (via setValue:forKey:).
        removeNeoAeroLayers(from: layer)
        removeNeoAeroLayers(from: titleView.layer)
        removeNeoAeroLayers(from: bodyView.layer)
        removeNeoAeroLayers(from: statusView.layer)

        // Remove existing CAReplicatorLayer wet-floor (D-07: remove, not hide).
        layer?.sublayers?.filter { $0 is CAReplicatorLayer }.forEach { $0.removeFromSuperlayer() }

        // Insert Neo-Aero layers based on PanelLayout (D-03).
        switch style.panelLayout {
        case .unifiedSlab:
            // Single glass slab spanning full 275×116 root view.
            // Inserted at index 0 so panel NSViews (titleView, bodyView, statusView) remain on top for hit-testing.
            let slab = NeoAeroLayerFactory.make(style: style, bounds: bounds)
            layer?.insertSublayer(slab, at: 0)

        case .threeBubbles:
            // One independent r=10 container per panel view.
            let titleLayer  = NeoAeroLayerFactory.make(style: style, bounds: titleView.bounds)
            let bodyLayer   = NeoAeroLayerFactory.make(style: style, bounds: bodyView.bounds)
            let statusLayer = NeoAeroLayerFactory.make(style: style, bounds: statusView.bounds)
            titleView.layer?.insertSublayer(titleLayer,  at: 0)
            bodyView.layer?.insertSublayer(bodyLayer,    at: 0)
            statusView.layer?.insertSublayer(statusLayer, at: 0)

        case .bodyFocus:
            // bodyView: full 5-layer stack (r=10).
            // titleView/statusView: simplified base+rim only (cornerRadius=0).
            let bodyLayer    = NeoAeroLayerFactory.make(style: style, bounds: bodyView.bounds)
            let titleSimple  = NeoAeroLayerFactory.makeSimplified(style: style, bounds: titleView.bounds)
            let statusSimple = NeoAeroLayerFactory.makeSimplified(style: style, bounds: statusView.bounds)
            bodyView.layer?.insertSublayer(bodyLayer,     at: 0)
            titleView.layer?.insertSublayer(titleSimple,  at: 0)
            statusView.layer?.insertSublayer(statusSimple, at: 0)
        }

        // Wire wet-floor CAReplicatorLayer if enabled (D-06, D-07).
        if style.wetFloor {
            let kWindowHeight: CGFloat = 116
            let kWindowWidth:  CGFloat = 275

            let replicator = CAReplicatorLayer()
            replicator.instanceCount = 2
            replicator.instanceTransform = CATransform3D(
                m11: 1, m12: 0, m13: 0, m14: 0,
                m21: 0, m22: -1, m23: 0, m24: 0,   // Y-flip
                m31: 0, m32: 0, m33:  1, m34: 0,
                m41: 0, m42: kWindowHeight * 2, m43: 0, m44: 1
            )
            replicator.instanceAlphaOffset = -0.5   // 50% opacity reflection (D-06)

            let reflectionHeight: CGFloat = kWindowHeight * 0.5
            let reflectionRect = CGRect(x: 0, y: -reflectionHeight, width: kWindowWidth, height: reflectionHeight)
            let fadeMask = CAGradientLayer()
            fadeMask.colors = [
                CGColor(gray: 0, alpha: 1.0),  // opaque at top of reflection
                CGColor(gray: 0, alpha: 0.0)   // transparent at bottom
            ]
            fadeMask.frame = reflectionRect
            replicator.mask = fadeMask

            // Insert at index 0 — below Neo-Aero chrome and panel views.
            layer?.insertSublayer(replicator, at: 0)
            NSLog("MANZO Phase 6: ManzoRootView.applyStyle — wet-floor CAReplicatorLayer inserted")
        }

        NSLog("MANZO Phase 6: ManzoRootView.applyStyle — layout=%@, theme=%@, wetFloor=%d",
              style.panelLayout.rawValue, style.colorTheme.rawValue, style.wetFloor ? 1 : 0)
    }

    // MARK: - Phase 7: Spectrum View Integration (D-01, D-02)

    func addSpectrumView(_ view: ManzoSpectrumView) {
        spectrumView?.removeFromSuperview()
        spectrumView = view

        view.translatesAutoresizingMaskIntoConstraints = false
        bodyView.addSubview(view)

        // D-01: 225×32 pt, centered horizontally, bottom-anchored in bodyView.
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 225),
            view.heightAnchor.constraint(equalToConstant: 32),
            view.centerXAnchor.constraint(equalTo: bodyView.centerXAnchor),
            view.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
        ])

        bodyView.layoutSubtreeIfNeeded()
        applySpectrumChromeMask(spectrumFrame: view.frame)

        NSLog("MANZO Phase 7: ManzoSpectrumView added — frame=%@, bodyView=%@",
              NSStringFromRect(view.frame), NSStringFromRect(bodyView.bounds))
    }

    // MARK: - Phase 8: PL Button Integration

    /// Add the PL toggle button to statusView (trailing side, 8 pt right inset).
    /// Called by AppDelegate after window setup. AppDelegate owns the NSButton instance.
    /// Button size: 20×12 pt — matching Winamp mini-button aesthetic (UI-SPEC PL Toggle Button).
    func addPLButton(_ button: NSButton) {
        button.translatesAutoresizingMaskIntoConstraints = false
        statusView.addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: statusView.trailingAnchor, constant: -8),
            button.centerYAnchor.constraint(equalTo: statusView.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: 20),
            button.heightAnchor.constraint(equalToConstant: 12),
        ])
        NSLog("MANZO Phase 8: ManzoRootView.addPLButton — PL button added to statusView, trailing-8pt")
    }

    // MARK: - Phase 8.1: LCD + Transport Controls Layout (D-02)

    /// ManzoLCDView: x=0, y=14, width=275 (full), height=43 (D-04).
    /// Added directly to ManzoRootView (not bodyView/statusView) — D-02.
    func addLCDView(_ view: ManzoLCDView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.heightAnchor.constraint(equalToConstant: 43),
        ])
        NSLog("MANZO Phase 8.1: ManzoRootView.addLCDView — 275×43pt at y=14")
    }

    /// ManzoSeekBar: x=16, y=72, width=248, height=10 (D-07).
    /// Added directly to ManzoRootView — D-02.
    func addSeekBar(_ view: ManzoSeekBar) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: 72),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            view.widthAnchor.constraint(equalToConstant: 248),
            view.heightAnchor.constraint(equalToConstant: 10),
        ])
        NSLog("MANZO Phase 8.1: ManzoRootView.addSeekBar — 248×10pt at x=16, y=72")
    }

    /// Volume slider: x=107, y=57, width=68, height=13, range 0–255 (D-08).
    /// Added directly to ManzoRootView — D-02.
    func addVolumeSlider(_ view: ManzoSlider) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: 57),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 107),
            view.widthAnchor.constraint(equalToConstant: 68),
            view.heightAnchor.constraint(equalToConstant: 13),
        ])
        NSLog("MANZO Phase 8.1: ManzoRootView.addVolumeSlider — 68×13pt at x=107, y=57")
    }

    /// Pan slider: x=177, y=57, width=38, height=13, range -127–+127 (D-08).
    /// Added directly to ManzoRootView — D-02.
    func addPanSlider(_ view: ManzoSlider) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: 57),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 177),
            view.widthAnchor.constraint(equalToConstant: 38),
            view.heightAnchor.constraint(equalToConstant: 13),
        ])
        NSLog("MANZO Phase 8.1: ManzoRootView.addPanSlider — 38×13pt at x=177, y=57")
    }

    /// Generic transport button adder (D-02, D-09).
    /// Caller passes exact x,y,width,height from D-01 for each button.
    /// Added directly to ManzoRootView — transport row (y=88–106) spans bodyView/statusView boundary.
    func addTransportButton(_ view: ManzoTransportButton, x: CGFloat, y: CGFloat,
                            width: CGFloat, height: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor, constant: y),
            view.leadingAnchor.constraint(equalTo: leadingAnchor, constant: x),
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height),
        ])
        NSLog("MANZO Phase 8.1: ManzoRootView.addTransportButton — label=%@, frame=(%g,%g,%g×%g)",
              (view.label as NSString), x, y, width, height)
    }

    // MARK: - Phase 8.1: Spectrum View Relocation (D-03)

    /// Relocates the ManzoSpectrumView from Phase 7's bottom-anchored layout to the Winamp viz band.
    /// Must be called AFTER addSpectrumView() has added the view to bodyView.
    /// New position: bodyView.topAnchor + 43, height=32, width=107, leading edge (D-03).
    /// Calls bodyView.layoutSubtreeIfNeeded() BEFORE applySpectrumChromeMask (UI-SPEC note 10).
    func relocateSpectrumView() {
        guard let sv = spectrumView else {
            NSLog("MANZO Phase 8.1: ManzoRootView.relocateSpectrumView — spectrumView is nil, skipping")
            return
        }
        // Remove ALL constraints on sv owned by sv itself.
        sv.removeConstraints(sv.constraints)
        // Remove superview-owned constraints referencing sv (Phase 7 created these in addSpectrumView).
        if let superConstraints = sv.superview?.constraints {
            let toRemove = superConstraints.filter { c in
                c.firstItem as? NSView == sv || c.secondItem as? NSView == sv
            }
            NSLayoutConstraint.deactivate(toRemove)
        }

        // Apply new Winamp viz band constraints (D-03):
        // topAnchor = bodyView.topAnchor + 43, height=32, width=107, leadingAnchor = bodyView.leadingAnchor
        NSLayoutConstraint.activate([
            sv.topAnchor.constraint(equalTo: bodyView.topAnchor, constant: 43),
            sv.heightAnchor.constraint(equalToConstant: 32),
            sv.widthAnchor.constraint(equalToConstant: 107),
            sv.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
        ])

        // UI-SPEC note 10: call layoutSubtreeIfNeeded BEFORE applySpectrumChromeMask;
        // otherwise spectrumFrame is CGRect.zero.
        bodyView.layoutSubtreeIfNeeded()
        applySpectrumChromeMask(spectrumFrame: sv.frame)

        NSLog("MANZO Phase 8.1: ManzoRootView.relocateSpectrumView — spectrum at bodyView.topAnchor+43, 107×32pt")
    }

    private func applySpectrumChromeMask(spectrumFrame: CGRect) {
        // threeBubbles / bodyFocus: container lives in bodyView.layer.
        if let neoAeroLayer = bodyView.layer?.sublayers?.first(where: {
            ($0.value(forKey: "name") as? String) == "NeoAeroContainer"
        }) {
            let maskPath = CGMutablePath()
            maskPath.addRect(bodyView.bounds)
            maskPath.addRect(spectrumFrame)
            let maskLayer = CAShapeLayer()
            maskLayer.path = maskPath
            maskLayer.fillRule = .evenOdd
            maskLayer.frame = bodyView.bounds
            neoAeroLayer.mask = maskLayer
            NSLog("MANZO Phase 7: NeoAeroContainer chrome mask applied — spectrumFrame=%@",
                  NSStringFromRect(spectrumFrame))
            return
        }

        // unifiedSlab: single container lives in the root layer — convert coords.
        guard let neoAeroLayer = layer?.sublayers?.first(where: {
            ($0.value(forKey: "name") as? String) == "NeoAeroContainer"
        }) else {
            NSLog("MANZO Phase 7: applySpectrumChromeMask — NeoAeroContainer not found; skipping mask")
            return
        }

        let rootSpectrumFrame = bodyView.convert(spectrumFrame, to: self)
        let maskPath = CGMutablePath()
        maskPath.addRect(bounds)
        maskPath.addRect(rootSpectrumFrame)
        let maskLayer = CAShapeLayer()
        maskLayer.path = maskPath
        maskLayer.fillRule = .evenOdd
        maskLayer.frame = bounds
        neoAeroLayer.mask = maskLayer
        NSLog("MANZO Phase 7: NeoAeroContainer chrome mask applied (unifiedSlab) — rootSpectrumFrame=%@",
              NSStringFromRect(rootSpectrumFrame))
    }

    // Removes all sublayers whose "name" key equals "NeoAeroContainer".
    // This is the factory-set tag used to identify layers owned by NeoAeroLayerFactory.
    private func removeNeoAeroLayers(from layer: CALayer?) {
        guard let layer = layer else { return }
        let toRemove = layer.sublayers?.filter {
            ($0.value(forKey: "name") as? String) == "NeoAeroContainer"
        } ?? []
        toRemove.forEach { $0.removeFromSuperlayer() }
    }

    // Invalidates rasterization cache on all NeoAeroContainer layers.
    // Call ONLY on actual visual state changes (theme switch, layout switch, drag-end).
    // NEVER call per-frame. (D-08)
    func invalidateNeoAeroRasterization() {
        func invalidate(_ layer: CALayer?) {
            layer?.sublayers?.forEach { sub in
                if (sub.value(forKey: "name") as? String) == "NeoAeroContainer" {
                    sub.shouldRasterize = false
                    sub.shouldRasterize = true
                    sub.rasterizationScale = 2.0
                }
            }
        }
        invalidate(layer)
        invalidate(titleView.layer)
        invalidate(bodyView.layer)
        invalidate(statusView.layer)
    }

    // MARK: - Drag

    // D-11: full-chrome drag — matches Winamp main_nonclient.cpp return HTCLIENT for all pixels.
    // Interactive controls added in Phase 6+ consume mouseDown in their own subviews first;
    // drag falls through to unoccupied chrome naturally. No hit-test exclusion zones needed.
    // Delegates to ManzoWindow.mouseDown/mouseDragged via responder chain (replaces performDrag
    // so ManzoWindow can fire onWindowMoved on every drag event — eliminates co-move lag).
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
}
