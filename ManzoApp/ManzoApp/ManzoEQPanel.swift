//
//  ManzoEQPanel.swift
//  MANZO — 10-band Equalizer panel.
//
//  Drop-in, dependency-free. NSPanel (non-activating, utility-style) hosting
//  ManzoEQView. Width matches the main window (275pt). Height auto-fits.
//
//  Visual reference: manzo_ui_kit.html — `.eq` section.
//  Maps to CSS classes: .eq, .led-btn, .led, .is-on, .curve-graph,
//      #eqCurvePath, #eqCurveLine, .col-band, .slider-wrap, .thumb, .fill,
//      .fill--boost, .fill--cut, .fill--at-zero, .preamp-col,
//      .preamp-label-below, .band-label, .presets-btn, .db-scale.
//
//  Callbacks (AppDelegate wires these — no FFI is called from here):
//      panel.onBandChanged = { gains, preamp in /* … */ }
//      panel.onPreset      = { name             in /* … */ }
//
import AppKit

// MARK: - P3 color tokens (mirror ManzoMainWindow.swift) ----------------------

private enum EQColor {
    static func p3(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(displayP3Red: r, green: g, blue: b, alpha: a)
    }
    // Backdrop — navy textured (per HTML .eq .body)
    static let bgTop        = p3(0.04, 0.07, 0.14)
    static let bgBottom     = p3(0.06, 0.10, 0.18)
    // Foreground
    static let fg2          = p3(0.78, 0.80, 0.85)
    static let fg3          = p3(0.58, 0.60, 0.65)
    // LCD / curve / zero-line
    static let zeroGreen    = p3(0.18, 0.95, 0.35)
    static let curveYellow  = p3(0.96, 0.79, 0.15)
    static let curveFill    = p3(0.18, 0.83, 0.35, 0.40)
    // Slider fills
    static let boostTop     = p3(1.00, 0.90, 0.20)
    static let boostMid     = p3(0.95, 0.75, 0.10)
    static let boostBot     = p3(0.60, 0.45, 0.05)
    static let cutTop       = p3(0.18, 0.85, 0.32)
    static let cutMid       = p3(0.10, 0.55, 0.20)
    static let cutBot       = p3(0.06, 0.30, 0.10)
    // Slider chrome
    static let grooveDark   = p3(0, 0, 0, 0.55)
    static let grooveMid    = p3(0, 0, 0, 0.30)
    static let tickLight    = p3(0.60, 0.65, 0.70, 0.35)
    static let dashed       = p3(1, 1, 1, 0.12)
    // Ribbed thumb
    static let thumbTop     = p3(0.85, 0.85, 0.88)
    static let thumbMid     = p3(0.70, 0.71, 0.75)
    static let thumbBot     = p3(0.48, 0.49, 0.53)
    // Bevel chrome (LED button + Presets button)
    static let bevelTop     = p3(0.18, 0.20, 0.26)
    static let bevelBot     = p3(0.10, 0.12, 0.16)
    static let bevelHi      = p3(1, 1, 1, 0.15)
    static let bevelLo      = p3(0, 0, 0, 0.50)
    static let bevelOutline = p3(0, 0, 0, 0.60)
    // LED off / on
    static let ledOff       = p3(0.06, 0.10, 0.04)
    static let ledOn        = p3(0.18, 0.95, 0.35)
    // Curve graph backdrop
    static let curveBgTop   = p3(0, 0, 0, 0.65)
    static let curveBgBot   = p3(0, 0, 0, 0.85)
    // Amber preamp label
    static let amber        = p3(0.90, 0.60, 0.20)
}

// MARK: - Panel ---------------------------------------------------------------

public final class ManzoEQPanel: NSPanel {

    public let eqView: ManzoEQView

    /// Forwarded from `ManzoEQView`. AppDelegate hooks the FFI here.
    public var onBandChanged: (([Float], Float) -> Void)? {
        get { eqView.onBandChanged }
        set { eqView.onBandChanged = newValue }
    }

    /// Stub for V2 preset menu.
    public var onPreset: ((String) -> Void)? {
        get { eqView.onPreset }
        set { eqView.onPreset = newValue }
    }

    public convenience init() {
        let size = ManzoEQView.intrinsicSize
        let rect = NSRect(origin: .zero, size: size)
        let view = ManzoEQView(frame: rect)
        self.init(view: view, contentRect: rect)
    }

    private init(view: ManzoEQView, contentRect: NSRect) {
        self.eqView = view
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
                   backing: .buffered,
                   defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false
        self.level = .floating
        self.contentView = view
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

// MARK: - View ---------------------------------------------------------------

public final class ManzoEQView: NSView {

    // MARK: Geometry
    public static let intrinsicSize = NSSize(width: 275, height: 168)
    private let padding   : CGFloat = 8
    private let topRowH   : CGFloat = 30
    private let gridH     : CGFloat = 110
    private let labelH    : CGFloat = 12
    private let cornerR   : CGFloat = 6

    // MARK: State (gains in dB, range −12...+12)
    public private(set) var preamp: Float = 0.0
    public private(set) var gains:  [Float] = Array(repeating: 0.0, count: 10)

    /// Hz labels in band order.
    public static let bandLabels: [String] =
        ["60", "170", "310", "600", "1k", "3k", "6k", "12k", "14k", "16k"]

    public var onBandChanged: (([Float], Float) -> Void)?
    public var onPreset:      ((String) -> Void)?

    // MARK: Subviews
    private let onBtn      = LEDButton(title: "On",   on: true)
    private let autoBtn    = LEDButton(title: "Auto", on: false)
    private let curveView  = EQCurveGraph()
    private let presetsBtn = PresetsButton(currentPreset: "FLAT")

    private let dbScale    = DBScaleRail()
    private let preampSlider: VerticalDBSlider
    private var bandSliders: [VerticalDBSlider] = []
    private var bandLabelViews: [NSTextField] = []
    private let preampLabelView = NSTextField(labelWithString: "PRE")

    // MARK: Init
    public override init(frame: NSRect) {
        self.preampSlider = VerticalDBSlider(amber: true)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = cornerR
        layer?.masksToBounds = true

        addSubview(onBtn)
        addSubview(autoBtn)
        addSubview(curveView)
        addSubview(presetsBtn)
        addSubview(dbScale)
        addSubview(preampSlider)

        for i in 0..<10 {
            let s = VerticalDBSlider(amber: false)
            s.bandIndex = i
            s.onChange = { [weak self] db in self?.bandDidChange(index: i, db: db) }
            bandSliders.append(s)
            addSubview(s)

            let lbl = NSTextField(labelWithString: ManzoEQView.bandLabels[i])
            styleSmallLabel(lbl, color: EQColor.fg2)
            lbl.alignment = .center
            bandLabelViews.append(lbl)
            addSubview(lbl)
        }

        styleSmallLabel(preampLabelView, color: EQColor.amber)
        preampLabelView.alignment = .center
        preampLabelView.stringValue = "PRE"
        addSubview(preampLabelView)

        preampSlider.onChange = { [weak self] db in self?.preampDidChange(db: db) }

        onBtn.onToggle = { [weak self] on in self?.curveView.isEnabled = on }
        autoBtn.onToggle = { _ in /* reserved */ }

        presetsBtn.onClick = { [weak self] in
            guard let self = self else { return }
            self.onPreset?(self.presetsBtn.currentPreset)
        }

        // Initial curve render
        curveView.update(preamp: preamp, gains: gains)
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: Public — programmatic curve update
    public func updateCurve(gains: [Float]) {
        guard gains.count == 10 else { return }
        self.gains = gains
        for (i, db) in gains.enumerated() { bandSliders[i].setValue(db, notify: false) }
        curveView.update(preamp: preamp, gains: gains)
    }

    public func setPreamp(_ db: Float) {
        preamp = db
        preampSlider.setValue(db, notify: false)
        curveView.update(preamp: preamp, gains: gains)
    }

    // MARK: Layout
    public override var intrinsicContentSize: NSSize { ManzoEQView.intrinsicSize }

    public override func layout() {
        super.layout()
        let W = bounds.width
        let H = bounds.height

        // Top row: ON · AUTO · curve · Presets
        let topY = H - padding - topRowH
        var x = padding
        let ledW: CGFloat = 38
        onBtn.frame   = NSRect(x: x, y: topY, width: ledW, height: topRowH); x += ledW + 4
        autoBtn.frame = NSRect(x: x, y: topY, width: ledW, height: topRowH); x += ledW + 6
        let presetsW: CGFloat = 56
        let curveX = x
        let curveW = W - padding - presetsW - 6 - curveX
        curveView.frame = NSRect(x: curveX, y: topY, width: curveW, height: topRowH)
        presetsBtn.frame = NSRect(x: W - padding - presetsW, y: topY,
                                  width: presetsW, height: topRowH)

        // Slider grid row
        let gridY = padding + labelH + 2
        let scaleW: CGFloat = 26
        dbScale.frame = NSRect(x: padding, y: gridY, width: scaleW, height: gridH)

        // Preamp column (slightly wider) + 4pt gap
        let preampW: CGFloat = 18
        let preampGap: CGFloat = 6
        let preampX = padding + scaleW + 2
        preampSlider.frame = NSRect(x: preampX, y: gridY, width: preampW, height: gridH)
        preampLabelView.frame = NSRect(x: preampX - 4, y: padding,
                                       width: preampW + 8, height: labelH)

        // 10 band columns spread across remaining width
        let bandsX0    = preampX + preampW + preampGap
        let bandsRight = W - padding
        let totalW     = bandsRight - bandsX0
        let colW       = totalW / 10.0
        let bandW      = max(10, colW - 1)

        for i in 0..<10 {
            let cx = bandsX0 + CGFloat(i) * colW
            let bx = cx + (colW - bandW) / 2
            bandSliders[i].frame    = NSRect(x: bx, y: gridY, width: bandW, height: gridH)
            bandLabelViews[i].frame = NSRect(x: cx, y: padding, width: colW, height: labelH)
        }
    }

    // MARK: Painting (navy textured backdrop, inset shadow)
    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let path = CGPath(roundedRect: bounds,
                          cornerWidth: cornerR, cornerHeight: cornerR,
                          transform: nil)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        // Base gradient
        let space  = CGColorSpace(name: CGColorSpace.displayP3)!
        let colors = [EQColor.bgTop.cgColor, EQColor.bgBottom.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: bounds.maxY),
                                   end:   CGPoint(x: 0, y: 0),
                                   options: [])
        }
        // Subtle horizontal scanlines (1px every 3px ~2% white)
        EQColor.p3(1, 1, 1, 0.02).setFill()
        var y: CGFloat = 0
        while y < bounds.height {
            NSBezierPath(rect: NSRect(x: 0, y: y, width: bounds.width, height: 1)).fill()
            y += 3
        }
        ctx.restoreGState()

        // Inset rim
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        EQColor.p3(1, 1, 1, 0.06).setStroke()
        let rim = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                               xRadius: cornerR, yRadius: cornerR)
        rim.lineWidth = 1; rim.stroke()
        ctx.restoreGState()
    }

    // MARK: Events
    private func bandDidChange(index: Int, db: Float) {
        gains[index] = db
        curveView.update(preamp: preamp, gains: gains)
        onBandChanged?(gains, preamp)
    }
    private func preampDidChange(db: Float) {
        preamp = db
        curveView.update(preamp: preamp, gains: gains)
        onBandChanged?(gains, preamp)
    }

    // MARK: Helpers
    private func styleSmallLabel(_ tf: NSTextField, color: NSColor) {
        tf.isBezeled = false; tf.drawsBackground = false; tf.isEditable = false
        let mono = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .regular)
        tf.font = NSFont(name: "VT323", size: 11) ?? mono
        tf.textColor = color
    }
}

// MARK: - LED Button (.led-btn) ----------------------------------------------

private final class LEDButton: NSView {
    var on: Bool { didSet { needsDisplay = true } }
    let title: String
    var onToggle: ((Bool) -> Void)?

    init(title: String, on: Bool) {
        self.title = title
        self.on = on
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        on.toggle()
        onToggle?(on)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)

        // Bevel face
        ctx.saveGState(); path.addClip()
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let colors = [EQColor.bevelTop.cgColor, EQColor.bevelBot.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: r.maxY),
                                   end:   CGPoint(x: 0, y: r.minY),
                                   options: [])
        }
        ctx.restoreGState()

        // Outline + top hairline
        EQColor.bevelOutline.setStroke()
        path.lineWidth = 1; path.stroke()
        EQColor.bevelHi.setStroke()
        let hi = NSBezierPath()
        hi.move(to: NSPoint(x: r.minX + 1, y: r.maxY - 0.5))
        hi.line(to: NSPoint(x: r.maxX - 1, y: r.maxY - 0.5))
        hi.lineWidth = 1; hi.stroke()

        // 7×7 LED on the left
        let ledSize: CGFloat = 7
        let ledRect = NSRect(x: r.minX + 5,
                             y: r.midY - ledSize / 2,
                             width: ledSize, height: ledSize)
        let ledPath = NSBezierPath(roundedRect: ledRect, xRadius: 1, yRadius: 1)
        (on ? EQColor.ledOn : EQColor.ledOff).setFill()
        ledPath.fill()
        EQColor.p3(0, 0, 0, 0.8).setStroke()
        ledPath.lineWidth = 1; ledPath.stroke()
        if on {
            // Soft glow
            let glow = NSShadow()
            glow.shadowColor = EQColor.ledOn.withAlphaComponent(0.9)
            glow.shadowBlurRadius = 4
            ctx.saveGState()
            NSGraphicsContext.current?.saveGraphicsState()
            glow.set()
            EQColor.ledOn.setFill()
            ledPath.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            ctx.restoreGState()
        }

        // Title (mono uppercase, kerned)
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: EQColor.fg2,
            .kern: 0.6
        ]
        let s = (title.uppercased() as NSString)
        let size = s.size(withAttributes: attr)
        s.draw(at: NSPoint(x: ledRect.maxX + 4,
                           y: (r.height - size.height) / 2 + r.minY),
               withAttributes: attr)
    }
}

// MARK: - Presets Button (.presets-btn) --------------------------------------

private final class PresetsButton: NSView {
    var currentPreset: String { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    init(currentPreset: String) {
        self.currentPreset = currentPreset
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)

        ctx.saveGState(); path.addClip()
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let colors = [EQColor.bevelTop.cgColor, EQColor.bevelBot.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: r.maxY),
                                   end:   CGPoint(x: 0, y: r.minY),
                                   options: [])
        }
        ctx.restoreGState()
        EQColor.bevelOutline.setStroke()
        path.lineWidth = 1; path.stroke()
        EQColor.bevelHi.setStroke()
        let hi = NSBezierPath()
        hi.move(to: NSPoint(x: r.minX + 1, y: r.maxY - 0.5))
        hi.line(to: NSPoint(x: r.maxX - 1, y: r.maxY - 0.5))
        hi.lineWidth = 1; hi.stroke()

        let topAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: EQColor.fg2,
            .kern: 0.8
        ]
        let bottomAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .regular),
            .foregroundColor: EQColor.fg3,
            .kern: 1.0
        ]
        let top = ("PRESETS" as NSString)
        let topSize = top.size(withAttributes: topAttr)
        top.draw(at: NSPoint(x: (r.width - topSize.width) / 2 + r.minX,
                             y: r.midY + 1),
                 withAttributes: topAttr)
        let bot = ("\(currentPreset.uppercased()) ▾" as NSString)
        let botSize = bot.size(withAttributes: bottomAttr)
        bot.draw(at: NSPoint(x: (r.width - botSize.width) / 2 + r.minX,
                             y: r.midY - botSize.height - 1),
                 withAttributes: bottomAttr)
    }
}

// MARK: - dB scale rail (.db-scale) ------------------------------------------

private final class DBScaleRail: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let labels = ["+12 db", "+0 db", "−12 db"]
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "VT323", size: 11)
                ?? NSFont.monospacedSystemFont(ofSize: 8.5, weight: .regular),
            .foregroundColor: EQColor.p3(0.70, 0.75, 0.82)
        ]
        let positions: [CGFloat] = [
            bounds.height - 10,
            bounds.midY - 5,
            2
        ]
        for (i, s) in labels.enumerated() {
            let str = s as NSString
            let size = str.size(withAttributes: attr)
            str.draw(at: NSPoint(x: bounds.maxX - size.width - 2, y: positions[i]),
                     withAttributes: attr)
        }
    }
}

// MARK: - Vertical dB slider (.col-band > .slider-wrap) ----------------------

private final class VerticalDBSlider: NSView {

    /// Range and inset constants
    private let dbMin: Float = -12.0
    private let dbMax: Float =  12.0
    private let thumbH: CGFloat = 11
    private let amber: Bool

    var bandIndex: Int = 0
    var value: Float = 0.0 { didSet { needsDisplay = true } }
    var onChange: ((Float) -> Void)?

    init(amber: Bool) {
        self.amber = amber
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func setValue(_ db: Float, notify: Bool) {
        let clamped = max(dbMin, min(dbMax, db))
        value = clamped
        if notify { onChange?(clamped) }
    }

    // MARK: Hit / drag
    override func mouseDown(with event: NSEvent) { handle(event) }
    override func mouseDragged(with event: NSEvent) { handle(event) }

    private func handle(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let usable = bounds.height - thumbH
        let clamped = max(0, min(usable, p.y - thumbH / 2))
        let pct = clamped / usable
        let db = Float(pct) * (dbMax - dbMin) + dbMin
        setValue(db, notify: true)
    }

    // MARK: Painting
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Recessed groove (.slider-wrap)
        let groove = bounds
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        ctx.saveGState()
        let grooveColors = [EQColor.grooveDark.cgColor,
                            EQColor.grooveMid.cgColor,
                            EQColor.grooveDark.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: grooveColors,
                              locations: [0, 0.5, 1]) {
            NSBezierPath(rect: groove).addClip()
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: groove.minX, y: 0),
                                   end:   CGPoint(x: groove.maxX, y: 0),
                                   options: [])
        }
        ctx.restoreGState()

        // Outline + 1px inset top shadow
        EQColor.p3(0, 0, 0, 0.5).setStroke()
        let outline = NSBezierPath(rect: groove.insetBy(dx: 0.5, dy: 0.5))
        outline.lineWidth = 1; outline.stroke()

        // Ruler tick marks (16 divisions on left/right edges)
        EQColor.tickLight.setStroke()
        let ticks = 16
        for i in 0...ticks {
            let y = bounds.minY + CGFloat(i) * bounds.height / CGFloat(ticks)
            let p1 = NSBezierPath()
            p1.move(to: NSPoint(x: groove.minX, y: y))
            p1.line(to: NSPoint(x: groove.minX + 2, y: y))
            p1.move(to: NSPoint(x: groove.maxX - 2, y: y))
            p1.line(to: NSPoint(x: groove.maxX, y: y))
            p1.lineWidth = 0.5; p1.stroke()
        }

        // Reference lines: green zero (mid), dashed ±12 (top + bottom)
        EQColor.zeroGreen.withAlphaComponent(0.28).setStroke()
        let zero = NSBezierPath()
        zero.move(to: NSPoint(x: groove.minX, y: groove.midY))
        zero.line(to: NSPoint(x: groove.maxX, y: groove.midY))
        zero.lineWidth = 1; zero.stroke()

        EQColor.dashed.setStroke()
        for y in [groove.minY + 0.5, groove.maxY - 0.5] {
            let dash = NSBezierPath()
            dash.move(to: NSPoint(x: groove.minX, y: y))
            dash.line(to: NSPoint(x: groove.maxX, y: y))
            dash.lineWidth = 1
            dash.setLineDash([3, 3], count: 2, phase: 0)
            dash.stroke()
        }

        // Fill (.fill / --boost / --cut / --at-zero)
        let pct = (value - dbMin) / (dbMax - dbMin) // 0..1 bottom→top
        let usable = bounds.height - thumbH
        let thumbY = CGFloat(pct) * usable
        let fillX = groove.minX + 3, fillW = groove.width - 6

        if abs(value) < 0.05 {
            // .fill--at-zero — thin solid green bar
            let fillRect = NSRect(x: fillX,
                                  y: groove.midY - 1,
                                  width: fillW, height: 2)
            EQColor.zeroGreen.setFill()
            NSBezierPath(rect: fillRect).fill()
        } else if value > 0 {
            // .fill--boost — yellow gradient, top at thumb, bottom at zero
            let top = thumbY + thumbH / 2
            let fillRect = NSRect(x: fillX,
                                  y: groove.midY,
                                  width: fillW,
                                  height: max(0, top - groove.midY - 5))
            ctx.saveGState()
            NSBezierPath(rect: fillRect).addClip()
            let cs = [EQColor.boostTop.cgColor,
                      EQColor.boostMid.cgColor,
                      EQColor.boostBot.cgColor] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: cs,
                                  locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(g,
                                       start: CGPoint(x: 0, y: fillRect.maxY),
                                       end:   CGPoint(x: 0, y: fillRect.minY),
                                       options: [])
            }
            ctx.restoreGState()
        } else {
            // .fill--cut — green gradient, top at zero, bottom at thumb
            let bot = thumbY + thumbH / 2
            let fillRect = NSRect(x: fillX,
                                  y: bot + 5,
                                  width: fillW,
                                  height: max(0, groove.midY - bot - 5))
            ctx.saveGState()
            NSBezierPath(rect: fillRect).addClip()
            let cs = [EQColor.cutTop.cgColor,
                      EQColor.cutMid.cgColor,
                      EQColor.cutBot.cgColor] as CFArray
            if let g = CGGradient(colorsSpace: space, colors: cs,
                                  locations: [0, 0.5, 1]) {
                ctx.drawLinearGradient(g,
                                       start: CGPoint(x: 0, y: fillRect.maxY),
                                       end:   CGPoint(x: 0, y: fillRect.minY),
                                       options: [])
            }
            ctx.restoreGState()
        }

        // Thumb (.thumb) — square, beveled, ribbed
        let thumbRect = NSRect(x: groove.minX + 1,
                               y: thumbY,
                               width: groove.width - 2,
                               height: thumbH)
        ctx.saveGState()
        NSBezierPath(rect: thumbRect).addClip()
        let tc = [EQColor.thumbTop.cgColor,
                  EQColor.thumbMid.cgColor,
                  EQColor.thumbBot.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: tc,
                              locations: [0, 0.5, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: thumbRect.maxY),
                                   end:   CGPoint(x: 0, y: thumbRect.minY),
                                   options: [])
        }
        ctx.restoreGState()
        EQColor.p3(0, 0, 0, 0.75).setStroke()
        NSBezierPath(rect: thumbRect.insetBy(dx: 0.5, dy: 0.5)).stroke()

        // Ribbed etches (≡)
        let inner = thumbRect.insetBy(dx: 2, dy: 2)
        var ry = inner.minY
        while ry < inner.maxY {
            EQColor.p3(0, 0, 0, 0.35).setFill()
            NSBezierPath(rect: NSRect(x: inner.minX, y: ry,
                                      width: inner.width, height: 1)).fill()
            EQColor.p3(1, 1, 1, 0.30).setFill()
            NSBezierPath(rect: NSRect(x: inner.minX, y: ry + 1,
                                      width: inner.width, height: 1)).fill()
            ry += 2
        }

        // Amber tint overlay if preamp
        if amber {
            EQColor.amber.withAlphaComponent(0.06).setFill()
            NSBezierPath(rect: bounds).fill()
        }
    }
}

// MARK: - EQ Curve Graph (.curve-graph) --------------------------------------

private final class EQCurveGraph: NSView {

    var isEnabled: Bool = true { didSet { needsDisplay = true } }
    private var preamp: Float = 0.0
    private var gains:  [Float] = Array(repeating: 0.0, count: 10)

    func update(preamp: Float, gains: [Float]) {
        self.preamp = preamp
        self.gains  = gains
        needsDisplay = true
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 2
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let space = CGColorSpace(name: CGColorSpace.displayP3)!

        // Recessed black background
        ctx.saveGState()
        let bgPath = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        bgPath.addClip()
        let bg = [EQColor.curveBgTop.cgColor, EQColor.curveBgBot.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: bg, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: bounds.maxY),
                                   end:   CGPoint(x: 0, y: 0),
                                   options: [])
        }
        ctx.restoreGState()

        // Zero line (mid)
        EQColor.zeroGreen.withAlphaComponent(0.22).setStroke()
        let zero = NSBezierPath()
        zero.move(to: NSPoint(x: bounds.minX, y: bounds.midY))
        zero.line(to: NSPoint(x: bounds.maxX, y: bounds.midY))
        zero.lineWidth = 1; zero.stroke()

        // Compute curve points (Catmull–Rom)
        guard gains.count == 10 else { return }
        let W = bounds.width, H = bounds.height
        let pts: [CGPoint] = gains.enumerated().map { i, v in
            let total = max(-12.0, min(12.0, v + preamp))
            let x = bounds.minX + CGFloat(i) / 9.0 * W
            let y = bounds.midY - CGFloat(total / 12.0) * (H / 2 - 3)
            return CGPoint(x: x, y: y)
        }

        let curveLine = CGMutablePath()
        let curveFill = CGMutablePath()
        curveLine.move(to: pts[0])
        curveFill.move(to: CGPoint(x: pts[0].x, y: bounds.minY))
        curveFill.addLine(to: pts[0])

        for i in 0..<(pts.count - 1) {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = (i + 2) < pts.count ? pts[i + 2] : p2
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                             y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                             y: p2.y - (p3.y - p1.y) / 6)
            curveLine.addCurve(to: p2, control1: c1, control2: c2)
            curveFill.addCurve(to: p2, control1: c1, control2: c2)
        }
        curveFill.addLine(to: CGPoint(x: pts.last!.x, y: bounds.minY))
        curveFill.closeSubpath()

        // Translucent green area fill
        ctx.saveGState()
        ctx.addPath(curveFill)
        ctx.clip()
        let fillCs = [EQColor.curveFill.cgColor,
                      EQColor.curveFill.withAlphaComponent(0.02).cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: fillCs, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: bounds.maxY),
                                   end:   CGPoint(x: 0, y: bounds.minY),
                                   options: [])
        }
        ctx.restoreGState()

        // Yellow curve line
        ctx.saveGState()
        ctx.setLineWidth(1.2)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor((isEnabled ? EQColor.curveYellow
                                      : EQColor.curveYellow.withAlphaComponent(0.35)).cgColor)
        ctx.addPath(curveLine)
        ctx.strokePath()
        ctx.restoreGState()

        // Outline
        EQColor.p3(0, 0, 0, 0.7).setStroke()
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                   xRadius: 2, yRadius: 2)
        outline.lineWidth = 1; outline.stroke()
    }
}
