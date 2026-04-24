import AppKit

// ManzoTransportButton — Reusable NeoAero glass transport button NSView subclass.
//
// Renders the full 5-layer NeoAero chrome stack via NeoAeroLayerFactory.make for
// all 7 transport buttons (prev/play/stop/next/eject/shuffle/repeat).
//
// Hover reduces rim alpha from 0.45 to 0.25 (D-09).
// Press flashes specular via shouldRasterize toggle (D-09 / ManzoRootView.invalidateNeoAeroRasterization pattern).
// label property is mutable — play/pause toggle driven by poll timer (D-10).
// action closure assigned by AppDelegate in Wave 2.
//
// Constraints:
// - CALayer-only — NO NSVisualEffectView (SHELL-02/SHELL-03)
// - P3 colors everywhere (CLAUDE.md, VIS-03)
// - shouldRasterize=true requires rasterizationScale=2.0 (CLAUDE.md)

final class ManzoTransportButton: NSView {

    // MARK: - Properties

    /// Set externally to change the displayed label (D-10: play/pause toggle driven by poll timer)
    var label: String = "" {
        didSet {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            labelLayer.string = label
            CATransaction.commit()
        }
    }

    /// Closure assigned by AppDelegate — called on mouseDown (press)
    var action: (() -> Void)?

    private let p3             = CGColorSpace(name: CGColorSpace.displayP3)!
    private var neoAeroLayer:  CALayer?      // NeoAeroContainer from factory
    private let labelLayer   = CATextLayer()
    private var rimLayer:    CALayer?        // sublayers[3] — for hover alpha change

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        isOpaque   = false
        // Note: setupChrome() uses bounds — must be called AFTER frame is set.
        // AppDelegate sets frame before adding to superview, so bounds is valid here.
        setupChrome()
        setupLabel()
        setupTracking()
        NSLog("MANZO Phase 8.1: ManzoTransportButton.init — frame=%@", NSStringFromRect(frame))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }

    // MARK: - Chrome (NeoAero)

    private func setupChrome() {
        let style  = ManzoVisualStyle.load()
        // UI-SPEC note 9: pass bounds (zero-origin), NOT frame (superview coords).
        let chrome = NeoAeroLayerFactory.make(style: style,
                                              bounds: CGRect(origin: .zero, size: bounds.size))
        layer?.addSublayer(chrome)
        neoAeroLayer = chrome
        // Rim is at sublayer index 3 (base=0, specular=1, lowerGlow=2, rim=3)
        // NeoAeroLayer.swift addSublayer order: base(0), specular(1), lowerGlow(2), rim(3)
        rimLayer = chrome.sublayers?[3]
        // NeoAeroLayerFactory already sets shouldRasterize=true + rasterizationScale=2.0
        // on the container — these are already set and CLAUDE.md pairs are satisfied.
        NSLog("MANZO Phase 8.1: ManzoTransportButton.setupChrome — NeoAeroContainer added, bounds=%@",
              NSStringFromRect(CGRect(origin: .zero, size: bounds.size)))
    }

    // MARK: - Label

    private func setupLabel() {
        let lcdGreen = CGColor(colorSpace: p3, components: [0.18, 0.82, 0.18, 1.0])!
        labelLayer.string          = label
        labelLayer.font            = NSFont.systemFont(ofSize: 9, weight: .regular) as CTFont
        labelLayer.fontSize        = 9
        labelLayer.foregroundColor = lcdGreen
        labelLayer.alignmentMode   = .center
        labelLayer.contentsScale   = 2.0
        // Label is not animated per-frame; shouldRasterize=false keeps text crisp
        labelLayer.shouldRasterize = false
        layer?.addSublayer(labelLayer)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Update NeoAero chrome frame to match current bounds
        neoAeroLayer?.frame = CGRect(origin: .zero, size: bounds.size)
        // Update NeoAero sublayer frames (base and specular reference bounds)
        if let sublayers = neoAeroLayer?.sublayers {
            sublayers.forEach { $0.frame = CGRect(origin: .zero, size: bounds.size) }
            // Specular band: top 52% of bounds
            if sublayers.count > 1 {
                sublayers[1].frame = CGRect(x: 0, y: 0,
                                            width: bounds.width,
                                            height: bounds.height * 0.52)
            }
            // Lower glow: bottom 25% of bounds
            if sublayers.count > 2 {
                sublayers[2].frame = CGRect(x: 0, y: bounds.height * 0.75,
                                            width: bounds.width,
                                            height: bounds.height * 0.25)
            }
            // Rim: inset 0.5pt
            if sublayers.count > 3 {
                sublayers[3].frame = bounds.insetBy(dx: 0.5, dy: 0.5)
            }
        }
        // Label: centered over full bounds
        labelLayer.frame = bounds
    }

    // MARK: - Tracking

    private func setupTracking() {
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    // MARK: - Mouse Events

    override func mouseEntered(with event: NSEvent) {
        // Hover: reduce rim highlight alpha from 0.45 to 0.25 (D-09: subtract 0.2)
        rimLayer?.borderColor = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.25])!
    }

    override func mouseExited(with event: NSEvent) {
        // Restore rim alpha on hover exit
        rimLayer?.borderColor = CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 0.45])!
    }

    override func mouseDown(with event: NSEvent) {
        // Press: flash specular by invalidating rasterization cache
        // (D-09 / ManzoRootView.invalidateNeoAeroRasterization pattern)
        neoAeroLayer?.shouldRasterize = false
        neoAeroLayer?.shouldRasterize = true
        neoAeroLayer?.rasterizationScale = 2.0
        action?()
        NSLog("MANZO Phase 8.1: ManzoTransportButton.mouseDown — label=%@", label)
    }
}
