//
//  ManzoMainWindow.swift
//  MANZO — Main window (275×116pt) — Winamp-classic layout in AppKit.
//
//  Drop-in, dependency-free. Creates a borderless NSWindow with a
//  MainWindowView that contains: titlebar (traffic lights + "MANZO"),
//  LCD timer, marquee + metadata + seek bar, spectrum analyzer,
//  transport row, VOL/BAL sliders, EQ/PL toggles, status bar.
//
//  Colors are authored in Display P3 (CLAUDE.md: P3 everywhere).
//  No external assets — bezels, digits, and glyphs are drawn in code.
//
//  Usage:
//      let win = ManzoMainWindow()
//      win.makeKeyAndOrderFront(nil)
//
import AppKit

// MARK: - Color tokens (P3) ---------------------------------------------------

enum ManzoColor {
    static func p3(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(displayP3Red: r, green: g, blue: b, alpha: a)
    }
    // Base (classic)
    static let baseTop      = p3(0.10, 0.10, 0.10)
    static let baseBottom   = p3(0.23, 0.23, 0.23)
    // Foreground
    static let fg1          = p3(1, 1, 1)
    static let fg2          = p3(0.78, 0.80, 0.85)
    static let fg3          = p3(0.58, 0.60, 0.65)
    // LCD / spectrum
    static let lcd          = p3(0.13, 0.85, 0.47)
    static let specGreen    = p3(0.13, 0.85, 0.47)
    static let specYellow   = p3(0.98, 0.92, 0.16)
    static let specRed      = p3(1.00, 0.35, 0.20)
    // Seek / knob teal→green
    static let tealStart    = p3(0.05, 0.78, 0.82)
    static let greenEnd     = p3(0.13, 0.85, 0.47)
    // Selection / toggle-on
    static let selectionBlue  = p3(0.15, 0.45, 0.85, 0.85)
    static let selectionBlueD = p3(0.10, 0.30, 0.60, 0.90)
    // Traffic lights
    static let tlRed    = p3(1.00, 0.38, 0.32)
    static let tlYellow = p3(1.00, 0.78, 0.15)
    static let tlGreen  = p3(0.32, 0.80, 0.30)
    // Rim / specular
    static let rim          = p3(1, 1, 1, 0.45)
    static let specTop      = p3(1, 1, 1, 0.50)
    static let specMid      = p3(1, 1, 1, 0.08)
    static let lowerGlow    = p3(1, 1, 1, 0.12)
}

// MARK: - Geometry ------------------------------------------------------------

enum ManzoMetrics {
    static let windowW:     CGFloat = 275
    static let windowH:     CGFloat = 116
    static let titlebarH:   CGFloat = 14
    static let statusbarH:  CGFloat = 14
    static let bodyH:       CGFloat = 88
    static let cornerRadius:CGFloat = 10
}

// MARK: - Borderless NSWindow -------------------------------------------------

public final class ManzoMainWindow: NSWindow {
    public convenience init() {
        let size = NSSize(width: ManzoMetrics.windowW, height: ManzoMetrics.windowH)
        let rect = NSRect(origin: .zero, size: size)
        self.init(contentRect: rect,
                  styleMask: [.borderless, .resizable],
                  backing: .buffered,
                  defer: false)
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        let root = ManzoMainWindowView(frame: rect)
        self.contentView = root
    }
}

// MARK: - Root view -----------------------------------------------------------

public final class ManzoMainWindowView: NSView {

    private let titlebar   = ManzoTitlebar()
    let body               = ManzoBodyView()
    let statusbar           = ManzoStatusbar()

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius  = ManzoMetrics.cornerRadius
        layer?.borderColor   = ManzoColor.rim.cgColor
        layer?.borderWidth   = 1

        addSubview(titlebar)
        addSubview(body)
        addSubview(statusbar)
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        titlebar.frame  = NSRect(x: 0, y: h - ManzoMetrics.titlebarH,
                                 width: w, height: ManzoMetrics.titlebarH)
        statusbar.frame = NSRect(x: 0, y: 0, width: w, height: ManzoMetrics.statusbarH)
        body.frame      = NSRect(x: 0, y: ManzoMetrics.statusbarH,
                                 width: w,
                                 height: h - ManzoMetrics.titlebarH - ManzoMetrics.statusbarH)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Base gradient
        let colors = [ManzoColor.baseTop.cgColor, ManzoColor.baseBottom.cgColor] as CFArray
        let space  = CGColorSpace(name: CGColorSpace.displayP3)!
        if let gradient = CGGradient(colorsSpace: space, colors: colors,
                                     locations: [0, 1]) {
            ctx.saveGState()
            let path = CGPath(roundedRect: bounds,
                              cornerWidth: ManzoMetrics.cornerRadius,
                              cornerHeight: ManzoMetrics.cornerRadius,
                              transform: nil)
            ctx.addPath(path); ctx.clip()
            // base fill
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: 0, y: bounds.maxY),
                                   end:   CGPoint(x: 0, y: 0),
                                   options: [])
            // specular (top 52%)
            let specColors = [ManzoColor.specTop.cgColor,
                              ManzoColor.specMid.cgColor,
                              NSColor.clear.cgColor] as CFArray
            if let spec = CGGradient(colorsSpace: space, colors: specColors,
                                     locations: [0, 0.23, 0.52]) {
                ctx.drawLinearGradient(spec,
                                       start: CGPoint(x: 0, y: bounds.maxY),
                                       end:   CGPoint(x: 0, y: bounds.maxY - bounds.height * 0.52),
                                       options: [])
            }
            // lower glow
            let glowColors = [NSColor.clear.cgColor, ManzoColor.lowerGlow.cgColor] as CFArray
            if let glow = CGGradient(colorsSpace: space, colors: glowColors,
                                     locations: [0, 1]) {
                ctx.drawLinearGradient(glow,
                                       start: CGPoint(x: 0, y: bounds.height * 0.25),
                                       end:   CGPoint(x: 0, y: 0),
                                       options: [])
            }
            ctx.restoreGState()
        }
    }
}

// MARK: - Titlebar (14pt) -----------------------------------------------------

final class ManzoTitlebar: NSView {
    private let close = TrafficLight(color: ManzoColor.tlRed)
    private let mini  = TrafficLight(color: ManzoColor.tlYellow)
    private let maxi  = TrafficLight(color: ManzoColor.tlGreen)
    private let label = NSTextField(labelWithString: "MANZO")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = ManzoColor.p3(1, 1, 1, 0.08).cgColor
        [close, mini, maxi].forEach { addSubview($0) }
        label.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        label.textColor = ManzoColor.fg3
        label.alignment = .center
        label.isBezeled = false
        label.drawsBackground = false
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let dotSize: CGFloat = 8
        let y = (bounds.height - dotSize) / 2
        close.frame = NSRect(x: 10,            y: y, width: dotSize, height: dotSize)
        mini.frame  = NSRect(x: 10 + 14,       y: y, width: dotSize, height: dotSize)
        maxi.frame  = NSRect(x: 10 + 14 + 14,  y: y, width: dotSize, height: dotSize)
        label.sizeToFit()
        label.frame = NSRect(x: (bounds.width - label.bounds.width) / 2,
                             y: (bounds.height - label.bounds.height) / 2,
                             width: label.bounds.width, height: label.bounds.height)
    }
}

// MARK: - Traffic light -------------------------------------------------------

final class TrafficLight: NSView {
    let color: NSColor
    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(ovalIn: bounds)
        color.setFill()
        path.fill()
        // inner rim
        ManzoColor.p3(1, 1, 1, 0.18).setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

// MARK: - Body (LCD + meta + analyzer + transport) ----------------------------

final class ManzoBodyView: NSView {
    let lcd       = LCDLabel()
    let marquee   = MarqueeView()
    let specs     = NSTextField(labelWithString: "320 kbps · 44 khz · stereo · −5:13")
    let seek        = SeekBar()
    let analyzer    = SpectrumView()

    // Transport — non-private so AppDelegate can set onTap closures
    let prev    = TransportButton(glyph: .prev)
    let play    = TransportButton(glyph: .play)
    let pause   = TransportButton(glyph: .pause)
    let stop    = TransportButton(glyph: .stop)
    let next    = TransportButton(glyph: .next)
    let eject   = TransportButton(glyph: .eject)

    private let volLabel = CapsLabel("vol")
    let volSlider = KnobSlider(value: 0.70)
    private let balLabel = CapsLabel("bal")
    let balSlider = KnobSlider(value: 0.50, centered: true, width: 40)
    let eqBtn = PillToggle(title: "EQ", isOn: true)
    let plBtn = PillToggle(title: "PL", isOn: true)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        lcd.stringValue = "0:00"
        specs.font = NSFont.systemFont(ofSize: 9)
        specs.textColor = ManzoColor.fg3
        specs.isBezeled = false; specs.drawsBackground = false

        [lcd, marquee, specs, seek, analyzer,
         prev, play, pause, stop, next, eject,
         volLabel, volSlider, balLabel, balSlider,
         eqBtn, plBtn].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let topBandH: CGFloat = 58
        let padX: CGFloat = 14
        let gap:  CGFloat = 14

        lcd.frame = NSRect(x: padX, y: bounds.height - topBandH,
                           width: 86, height: topBandH)

        let anaW: CGFloat = 120, anaH: CGFloat = 32
        analyzer.frame = NSRect(x: bounds.width - padX - anaW,
                                y: bounds.height - topBandH + (topBandH - anaH) / 2,
                                width: anaW, height: anaH)

        let metaX = lcd.frame.maxX + gap
        let metaW = analyzer.frame.minX - gap - metaX
        let metaTop = bounds.height - 4
        marquee.frame = NSRect(x: metaX, y: metaTop - 18, width: metaW, height: 18)
        specs.frame   = NSRect(x: metaX, y: marquee.frame.minY - 14, width: metaW, height: 12)
        seek.frame    = NSRect(x: metaX, y: specs.frame.minY - 8,    width: metaW, height: 10)

        // Transport row — 24pt tall, 10pt from bottom of body
        let tY: CGFloat = 6
        var x: CGFloat = padX
        let btnW: CGFloat = 30, btnH: CGFloat = 24, btnGap: CGFloat = 6
        for btn in [prev, play, pause, stop, next, eject] {
            btn.frame = NSRect(x: x, y: tY, width: btnW, height: btnH)
            x += btnW + btnGap
        }
        // Spacer
        x += 6
        volLabel.sizeToFit()
        volLabel.frame.origin  = NSPoint(x: x, y: tY + (btnH - volLabel.frame.height)/2)
        x += volLabel.frame.width + 6
        volSlider.frame = NSRect(x: x, y: tY + (btnH - 8)/2, width: 64, height: 8)
        x += 64 + 8
        balLabel.sizeToFit()
        balLabel.frame.origin  = NSPoint(x: x, y: tY + (btnH - balLabel.frame.height)/2)
        x += balLabel.frame.width + 6
        balSlider.frame = NSRect(x: x, y: tY + (btnH - 8)/2, width: 40, height: 8)
        x += 40 + 12
        // EQ / PL pills
        eqBtn.frame = NSRect(x: x, y: tY, width: 24, height: btnH);  x += 24 + 4
        plBtn.frame = NSRect(x: x, y: tY, width: 24, height: btnH)
    }
}

// MARK: - LCD label -----------------------------------------------------------

final class LCDLabel: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    required init?(coder: NSCoder) { super.init(coder: coder); setup() }
    private func setup() {
        isEditable = false; isBezeled = false; drawsBackground = false
        font = NSFont.monospacedDigitSystemFont(ofSize: 34, weight: .regular)
        // VT323 lookalike via custom font; fallback system mono if not installed
        if let vt = NSFont(name: "VT323", size: 34) { font = vt }
        textColor = ManzoColor.lcd
        alignment = .left
        // Glow
        let glow = NSShadow()
        glow.shadowColor = ManzoColor.lcd.withAlphaComponent(0.5)
        glow.shadowBlurRadius = 6
        shadow = glow
    }
}

// MARK: - Marquee -------------------------------------------------------------

final class MarqueeView: NSView {
    var text = "★ 03. Bump — Rustie · Glass Swords     "
    private var offset: CGFloat = 0
    private var displayLink: CVDisplayLink?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        startAnimation()
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { stopAnimation() }

    private func startAnimation() {
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let dl = dl else { return }
        displayLink = dl
        CVDisplayLinkSetOutputHandler(dl) { [weak self] _, _, _, _, _ -> CVReturn in
            DispatchQueue.main.async { self?.advance() }
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(dl)
    }
    private func stopAnimation() {
        if let dl = displayLink { CVDisplayLinkStop(dl) }
    }
    private func advance() {
        offset += 0.4
        let font = NSFont(name: "VT323", size: 16) ?? NSFont.systemFont(ofSize: 14)
        let w = (text as NSString).size(withAttributes: [.font: font]).width
        if offset >= w { offset = 0 }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let font = NSFont(name: "VT323", size: 16) ?? NSFont.systemFont(ofSize: 14)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: ManzoColor.p3(0.85, 0.88, 0.93)
        ]
        let str = text + text
        let size = (str as NSString).size(withAttributes: attr)
        let y = (bounds.height - size.height) / 2
        (str as NSString).draw(at: NSPoint(x: -offset, y: y), withAttributes: attr)
    }
}

// MARK: - Seek bar ------------------------------------------------------------

final class SeekBar: NSView {
    var progress: CGFloat = 0.48
    var isDragging: Bool = false
    var onSeek: ((Double) -> Void)?

    override func mouseDown(with event: NSEvent) {
        isDragging = true
        updateProgress(from: event)
    }
    override func mouseDragged(with event: NSEvent) {
        updateProgress(from: event)
    }
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        onSeek?(Double(progress))
    }
    private func updateProgress(from event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        progress = max(0, min(1, x / bounds.width))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let track = NSRect(x: 0, y: (bounds.height - 4)/2, width: bounds.width, height: 4)
        let tp = NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2)
        ManzoColor.p3(0, 0, 0, 0.45).setFill(); tp.fill()

        // Fill gradient
        let fillRect = NSRect(x: track.minX, y: track.minY,
                              width: track.width * progress, height: track.height)
        ctx.saveGState()
        NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2).setClip()
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let colors = [ManzoColor.tealStart.cgColor, ManzoColor.greenEnd.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: fillRect.minX, y: 0),
                                   end:   CGPoint(x: fillRect.maxX, y: 0),
                                   options: [])
        }
        ctx.restoreGState()

        // Thumb 8×10
        let thumb = NSRect(x: fillRect.maxX - 4, y: track.midY - 5, width: 8, height: 10)
        let tPath = NSBezierPath(roundedRect: thumb, xRadius: 2, yRadius: 2)
        NSColor.white.setFill(); tPath.fill()
        ManzoColor.p3(0, 0, 0, 0.4).setStroke()
        tPath.lineWidth = 1; tPath.stroke()
    }
}

// MARK: - Knob slider (VOL / BAL) ---------------------------------------------

final class KnobSlider: NSView {
    var value: CGFloat     // 0..1
    let centered: Bool     // if true, fill shows offset from center (BAL)
    var onValueChanged: ((CGFloat) -> Void)?

    init(value: CGFloat, centered: Bool = false, width: CGFloat = 64) {
        self.value = value
        self.centered = centered
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 8))
    }
    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent)    { updateValue(from: event) }
    override func mouseDragged(with event: NSEvent) { updateValue(from: event) }
    private func updateValue(from event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        value = max(0, min(1, loc.x / bounds.width))
        needsDisplay = true
        onValueChanged?(value)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let track = bounds
        let tp = NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4)
        ManzoColor.p3(0, 0, 0, 0.35).setFill(); tp.fill()

        // Fill
        let fillRect: NSRect
        if centered {
            let midX = track.midX
            let off  = (value - 0.5) * track.width
            fillRect = NSRect(x: min(midX, midX + off), y: 0,
                              width: abs(off), height: track.height)
        } else {
            fillRect = NSRect(x: 0, y: 0, width: track.width * value, height: track.height)
        }
        ctx.saveGState()
        NSBezierPath(roundedRect: fillRect, xRadius: 4, yRadius: 4).setClip()
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let colors = [ManzoColor.tealStart.cgColor, ManzoColor.greenEnd.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: track.minX, y: 0),
                                   end:   CGPoint(x: track.maxX, y: 0),
                                   options: [])
        }
        ctx.restoreGState()

        // Thumb
        let thumbX = track.minX + track.width * value
        let thumb = NSRect(x: thumbX - 5, y: -3, width: 10, height: 14)
        let tPath = NSBezierPath(roundedRect: thumb, xRadius: 2, yRadius: 2)
        ManzoColor.p3(0.90, 0.91, 0.93).setFill(); tPath.fill()
        ManzoColor.p3(0, 0, 0, 0.5).setStroke()
        tPath.lineWidth = 1; tPath.stroke()
    }
}

// MARK: - Transport button ----------------------------------------------------

final class TransportButton: NSControl {
    enum Glyph { case prev, play, pause, stop, next, eject }
    let glyph: Glyph
    private(set) var isPressed = false

    init(glyph: Glyph) {
        self.glyph = glyph
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    var onTap: (() -> Void)?
    override func mouseDown(with event: NSEvent) { isPressed = true;  needsDisplay = true }
    override func mouseUp(with event: NSEvent)   { isPressed = false; needsDisplay = true
        onTap?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)

        // Beveled gray face
        ctx.saveGState()
        path.addClip()
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let topA: NSColor, botA: NSColor
        if isPressed {
            topA = ManzoColor.p3(0.28, 0.30, 0.36)
            botA = ManzoColor.p3(0.58, 0.60, 0.66)
        } else {
            topA = ManzoColor.p3(0.58, 0.60, 0.66)
            botA = ManzoColor.p3(0.28, 0.30, 0.36)
        }
        let colors = [topA.cgColor, botA.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: rect.maxY),
                                   end:   CGPoint(x: 0, y: rect.minY),
                                   options: [])
        }
        ctx.restoreGState()

        // Outer dark rim
        ManzoColor.p3(0, 0, 0, 0.6).setStroke()
        path.lineWidth = 1; path.stroke()
        // Top hairline highlight
        let hi = NSBezierPath()
        hi.move(to: NSPoint(x: rect.minX + 1, y: rect.maxY - 0.5))
        hi.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 0.5))
        ManzoColor.p3(1, 1, 1, 0.45).setStroke()
        hi.lineWidth = 1; hi.stroke()

        // Glyph — dark ink for beveled look
        let ink = ManzoColor.p3(0.08, 0.09, 0.12)
        drawGlyph(in: ctx, rect: rect, ink: ink)
    }

    private func drawGlyph(in ctx: CGContext, rect: NSRect, ink: NSColor) {
        ink.setFill()
        ink.setStroke()
        let cx = rect.midX, cy = rect.midY
        switch glyph {
        case .prev:
            // bar + triangle reversed
            let bar = NSRect(x: cx - 6, y: cy - 4, width: 1.5, height: 8)
            NSBezierPath(rect: bar).fill()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: cx + 4, y: cy - 4))
            p.line(to: NSPoint(x: cx + 4, y: cy + 4))
            p.line(to: NSPoint(x: cx - 3, y: cy))
            p.close(); p.fill()
        case .play:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: cx - 4, y: cy - 5))
            p.line(to: NSPoint(x: cx + 5, y: cy))
            p.line(to: NSPoint(x: cx - 4, y: cy + 5))
            p.close(); p.fill()
        case .pause:
            NSBezierPath(rect: NSRect(x: cx - 4, y: cy - 4, width: 2.5, height: 8)).fill()
            NSBezierPath(rect: NSRect(x: cx + 1.5, y: cy - 4, width: 2.5, height: 8)).fill()
        case .stop:
            NSBezierPath(rect: NSRect(x: cx - 4, y: cy - 4, width: 8, height: 8)).fill()
        case .next:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: cx - 5, y: cy - 4))
            p.line(to: NSPoint(x: cx - 5, y: cy + 4))
            p.line(to: NSPoint(x: cx + 2, y: cy))
            p.close(); p.fill()
            NSBezierPath(rect: NSRect(x: cx + 3, y: cy - 4, width: 1.5, height: 8)).fill()
        case .eject:
            let p = NSBezierPath()
            p.move(to: NSPoint(x: cx, y: cy + 4))
            p.line(to: NSPoint(x: cx + 5, y: cy - 1))
            p.line(to: NSPoint(x: cx - 5, y: cy - 1))
            p.close(); p.fill()
            NSBezierPath(rect: NSRect(x: cx - 5, y: cy - 4, width: 10, height: 2)).fill()
        }
    }
}

// MARK: - Caps label ----------------------------------------------------------

final class CapsLabel: NSTextField {
    convenience init(_ text: String) {
        self.init(labelWithString: text.uppercased())
        font = NSFont.systemFont(ofSize: 9, weight: .medium)
        textColor = ManzoColor.fg3
        isBezeled = false; drawsBackground = false
    }
}

// MARK: - Pill toggle (EQ / PL) -----------------------------------------------

final class PillToggle: NSButton {
    var isOnState: Bool { didSet { needsDisplay = true } }
    var onToggle: ((Bool) -> Void)?
    init(title: String, isOn: Bool) {
        self.isOnState = isOn
        super.init(frame: .zero)
        self.title = title
        isBordered = false
        wantsLayer = true
        setButtonType(.toggle)
        state = isOn ? .on : .off
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
        ctx.saveGState(); path.addClip()
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let colors: CFArray
        if isOnState {
            colors = [ManzoColor.selectionBlue.cgColor,
                      ManzoColor.selectionBlueD.cgColor] as CFArray
        } else {
            colors = [ManzoColor.p3(1, 1, 1, 0.14).cgColor,
                      ManzoColor.p3(1, 1, 1, 0.03).cgColor] as CFArray
        }
        if let g = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: rect.maxY),
                                   end:   CGPoint(x: 0, y: rect.minY),
                                   options: [])
        }
        ctx.restoreGState()
        ManzoColor.p3(1, 1, 1, isOnState ? 0.35 : 0.22).setStroke()
        path.lineWidth = 1; path.stroke()

        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8.5, weight: .semibold),
            .foregroundColor: isOnState ? NSColor.white : ManzoColor.fg2,
            .kern: 1.0
        ]
        let str = (title as NSString)
        let size = str.size(withAttributes: attr)
        str.draw(at: NSPoint(x: (rect.width - size.width)/2 + rect.minX,
                             y: (rect.height - size.height)/2 + rect.minY),
                 withAttributes: attr)
    }

    override func mouseDown(with event: NSEvent) {
        isOnState.toggle()
        state = isOnState ? .on : .off
        onToggle?(isOnState)
        sendAction(action, to: target)
    }
}

// MARK: - Spectrum analyzer ---------------------------------------------------

final class SpectrumView: NSView {
    var manzoHandle: UnsafeMutablePointer<manzo_ManzoHandle>? = nil

    private let cols = 20
    private var heights: [CGFloat]
    private var peaks:   [CGFloat]
    private var displayLink: CVDisplayLink?
    private var t: CGFloat = 0

    override init(frame frameRect: NSRect) {
        heights = Array(repeating: 0.3, count: 20)
        peaks   = Array(repeating: 0.3, count: 20)
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = ManzoColor.p3(0, 0, 0, 0.35).cgColor
        layer?.cornerRadius = 2
        start()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let d = displayLink { CVDisplayLinkStop(d) } }

    private func start() {
        var dl: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&dl)
        guard let dl = dl else { return }
        displayLink = dl
        CVDisplayLinkSetOutputHandler(dl) { [weak self] _, _, _, _, _ -> CVReturn in
            DispatchQueue.main.async { self?.advance() }
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(dl)
    }

    private func advance() {
        if let handle = manzoHandle {
            var buf = [Float](repeating: 0, count: cols)
            buf.withUnsafeMutableBufferPointer { ptr in
                manzo_get_spectrum(handle, ptr.baseAddress, UInt(cols))
            }
            for i in 0..<cols {
                let raw = CGFloat(buf[i])
                heights[i] += (raw - heights[i]) * 0.25
                if heights[i] > peaks[i] { peaks[i] = heights[i] }
                else { peaks[i] = max(0, peaks[i] - 0.008) }
            }
        } else {
            t += 0.016
            for i in 0..<cols {
                let target = max(0.05,
                    0.35 + 0.35 * sin(t*3 + CGFloat(i)*0.4) +
                    0.25 * sin(t*8 + CGFloat(i)*0.9) +
                    0.15 * CGFloat.random(in: 0...1))
                heights[i] += (target - heights[i]) * 0.25
                if heights[i] > peaks[i] { peaks[i] = heights[i] }
                else { peaks[i] = max(0, peaks[i] - 0.008) }
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let pad: CGFloat = 2
        let colW = (bounds.width - pad*2) / CGFloat(cols)
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let grad = [ManzoColor.specGreen.cgColor,
                    ManzoColor.specYellow.cgColor,
                    ManzoColor.specRed.cgColor] as CFArray
        guard let g = CGGradient(colorsSpace: space, colors: grad,
                                 locations: [0, 0.65, 1]) else { return }

        for i in 0..<cols {
            let x = pad + CGFloat(i) * colW
            let h = (bounds.height - pad*2) * heights[i]
            let r = NSRect(x: x, y: pad, width: colW - 0.5, height: h)
            ctx.saveGState()
            ctx.clip(to: r)
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: bounds.height - pad),
                                   end:   CGPoint(x: 0, y: pad),
                                   options: [])
            ctx.restoreGState()

            // Peak hold dot
            let py = pad + (bounds.height - pad*2) * peaks[i]
            NSColor.white.setFill()
            NSBezierPath(rect: NSRect(x: x, y: py, width: colW - 0.5, height: 1)).fill()
        }
    }
}

// MARK: - Status bar ----------------------------------------------------------

final class ManzoStatusbar: NSView {
    let left  = NSTextField(labelWithString: "▶ Playing")
    private let shuf  = BadgeLabel(text: "SHUF", on: true)
    private let rep   = BadgeLabel(text: "REP",  on: false)
    private let eq    = BadgeLabel(text: "EQ",   on: false)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = ManzoColor.p3(0, 0, 0, 0.28).cgColor
        left.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        left.textColor = ManzoColor.fg3
        left.isBezeled = false; left.drawsBackground = false
        [left, shuf, rep, eq].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func setStatus(_ text: String) { left.stringValue = text }

    override func layout() {
        super.layout()
        left.sizeToFit()
        left.frame.origin = NSPoint(x: 10, y: (bounds.height - left.bounds.height)/2)
        var x = bounds.width - 10
        for b in [eq, rep, shuf] {
            b.sizeToFit()
            x -= b.bounds.width
            b.frame.origin = NSPoint(x: x, y: (bounds.height - b.bounds.height)/2)
            x -= 4
        }
    }
}

final class BadgeLabel: NSView {
    let text: String; let on: Bool
    init(text: String, on: Bool) {
        self.text = text; self.on = on
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func sizeToFit() {
        let attr: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9, weight: .semibold)]
        let s = (text as NSString).size(withAttributes: attr)
        frame.size = NSSize(width: ceil(s.width) + 8, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
        (on ? ManzoColor.selectionBlue : ManzoColor.p3(1, 1, 1, 0.06)).setFill()
        r.fill()
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: on ? NSColor.white : ManzoColor.fg3
        ]
        let s = (text as NSString).size(withAttributes: attr)
        (text as NSString).draw(
            at: NSPoint(x: (bounds.width - s.width)/2,
                        y: (bounds.height - s.height)/2),
            withAttributes: attr)
    }
}
