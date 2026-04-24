import AppKit

// ManzoSlider — Reusable horizontal CALayer slider for volume and pan.
// Layer structure: background (CALayer root) + fillLayer + thumbLayer.
// Volume: x=107, y=57, width=68, height=13. Range 0–255.
// Pan:    x=177, y=57, width=38, height=13. Range -127–+127.
// All colors are P3 wide-gamut (CLAUDE.md constraint — no sRGB).
// fillLayer and thumbLayer must NOT rasterize — they change on every value update (UI-SPEC note 5).
final class ManzoSlider: NSView {

    // MARK: - Properties

    var minValue: Float = 0
    var maxValue: Float = 255

    /// Setting value triggers updateFill() immediately via didSet.
    var value: Float = 0 {
        didSet { updateFill() }
    }

    /// AppDelegate assigns this closure to call manzo_set_volume or manzo_set_pan (D-08).
    var onValueChanged: ((Float) -> Void)?

    private let p3         = CGColorSpace(name: CGColorSpace.displayP3)!
    private let fillLayer  = CALayer()
    private let thumbLayer = CALayer()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
        NSLog("MANZO Phase 8.1: ManzoSlider.init — slider created, range=%.0f–%.0f", minValue, maxValue)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }

    // MARK: - Layer Setup

    private func setupLayers() {
        let lcdBlack  = CGColor(colorSpace: p3, components: [0.0,  0.0,  0.0,  1.0])!
        let lcdGreen  = CGColor(colorSpace: p3, components: [0.18, 0.82, 0.18, 1.0])!
        let lcdBright = CGColor(colorSpace: p3, components: [0.30, 0.95, 0.30, 1.0])!

        layer?.backgroundColor = lcdBlack

        fillLayer.backgroundColor  = lcdGreen
        fillLayer.shouldRasterize  = false   // animated — changes on every value update (UI-SPEC note 5)
        layer?.addSublayer(fillLayer)

        thumbLayer.backgroundColor = lcdBright
        thumbLayer.shouldRasterize = false   // animated (UI-SPEC note 5)
        layer?.addSublayer(thumbLayer)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateFill()
    }

    // MARK: - Private

    private func updateFill() {
        guard maxValue > minValue, bounds.width > 0 else { return }
        let normalized   = CGFloat((value - minValue) / (maxValue - minValue))
        let fillWidth    = normalized * bounds.width
        let clampedWidth = max(0, min(fillWidth, bounds.width))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame  = CGRect(x: 0, y: 0, width: clampedWidth, height: bounds.height)
        thumbLayer.frame = CGRect(x: max(0, clampedWidth - 1.5), y: 0, width: 3, height: bounds.height)
        CATransaction.commit()
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        updateValue(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateValue(from: event)
    }

    private func updateValue(from event: NSEvent) {
        let x          = convert(event.locationInWindow, from: nil).x
        let clamped    = max(0, min(x, bounds.width))
        let normalized = Float(clamped / bounds.width)
        value          = minValue + normalized * (maxValue - minValue)
        onValueChanged?(value)
        NSLog("MANZO Phase 8.1: ManzoSlider.updateValue — value=%.1f (range %.0f–%.0f)",
              value, minValue, maxValue)
    }
}
