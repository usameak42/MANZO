import AppKit

// ManzoSeekBar — Winamp-style seek bar with live drag support.
// Layer structure: background (CALayer root) + fillLayer + thumbLayer.
// Frame: x=16, y=72, width=248, height=10 pt (placed by ManzoRootView in Wave 2).
// All colors are P3 wide-gamut (CLAUDE.md constraint — no sRGB).
// fillLayer and thumbLayer must NOT rasterize — they change on every poll tick (UI-SPEC note 5).
final class ManzoSeekBar: NSView {

    // MARK: - Properties

    /// Set by AppDelegate poll timer when isDragging == false.
    var duration: Double = 0

    /// Set by AppDelegate poll timer when isDragging == false.
    var currentPosition: Double = 0

    /// True during mouseDown/mouseDragged — poll timer skips fill update while true.
    private(set) var isDragging: Bool = false

    /// AppDelegate assigns this closure to call manzo_seek(handle, t) (D-07).
    var onSeek: ((Double) -> Void)?

    private let p3         = CGColorSpace(name: CGColorSpace.displayP3)!
    private let fillLayer  = CALayer()
    private let thumbLayer = CALayer()

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupLayers()
        NSLog("MANZO Phase 8.1: ManzoSeekBar.init — 248×10pt seek bar created")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }

    // MARK: - Layer Setup

    private func setupLayers() {
        let lcdBlack  = CGColor(colorSpace: p3, components: [0.0,  0.0,  0.0,  1.0])!
        let lcdGreen  = CGColor(colorSpace: p3, components: [0.18, 0.82, 0.18, 1.0])!
        let lcdBright = CGColor(colorSpace: p3, components: [0.30, 0.95, 0.30, 1.0])!

        layer?.backgroundColor = lcdBlack

        fillLayer.backgroundColor  = lcdGreen
        fillLayer.shouldRasterize  = false   // animated — changes width every poll tick (UI-SPEC note 5)
        layer?.addSublayer(fillLayer)

        thumbLayer.backgroundColor = lcdBright
        thumbLayer.shouldRasterize = false   // animated — changes x every poll tick (UI-SPEC note 5)
        layer?.addSublayer(thumbLayer)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // Reflect currentPosition on initial layout (poll timer drives updates when not dragging).
        updateFill(position: currentPosition, duration: duration)
    }

    // MARK: - Public API

    /// Called by AppDelegate poll timer when isDragging == false.
    /// Clamps position/duration and updates fill and thumb layers without implicit animation.
    func updateFill(position: Double, duration: Double) {
        guard duration > 0, !isDragging else { return }
        let fillWidth    = CGFloat(position / duration) * bounds.width
        let clampedWidth = max(0, min(fillWidth, bounds.width))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame  = CGRect(x: 0, y: 0, width: clampedWidth, height: bounds.height)
        thumbLayer.frame = CGRect(x: max(0, clampedWidth - 1.5), y: 0, width: 3, height: bounds.height)
        CATransaction.commit()
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        guard duration > 0 else { return }   // no-op when nothing is loaded
        isDragging = true
        let t = seekTime(from: event)
        onSeek?(t)
        // Provide immediate visual feedback during drag.
        applyDragFill(seekTime: t)
        NSLog("MANZO Phase 8.1: ManzoSeekBar.mouseDown — seek to %.2f", t)
    }

    override func mouseDragged(with event: NSEvent) {
        guard duration > 0 else { return }   // no-op when nothing is loaded
        let t = seekTime(from: event)
        onSeek?(t)
        applyDragFill(seekTime: t)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        NSLog("MANZO Phase 8.1: ManzoSeekBar.mouseUp — drag ended")
    }

    // MARK: - Private Helpers

    private func seekTime(from event: NSEvent) -> Double {
        let x       = convert(event.locationInWindow, from: nil).x
        let clamped = max(0, min(x, bounds.width))
        return Double(clamped / bounds.width) * duration
    }

    /// Update fill/thumb layers during drag for immediate visual feedback.
    private func applyDragFill(seekTime t: Double) {
        let fillWidth    = CGFloat(t / max(1, duration)) * bounds.width
        let clampedWidth = max(0, min(fillWidth, bounds.width))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame  = CGRect(x: 0, y: 0, width: clampedWidth, height: bounds.height)
        thumbLayer.frame = CGRect(x: max(0, clampedWidth - 1.5), y: 0, width: 3, height: bounds.height)
        CATransaction.commit()
    }
}
