//
//  ManzoPlaylistPanel.swift
//  MANZO — Playlist Editor panel.
//
//  Drop-in, dependency-free. NSPanel (non-activating, utility-style) hosting
//  ManzoPlaylistView. Width matches the main window (480pt). Height auto-fits
//  with a sensible default; resize via the panel's `setContentSize(_:)`.
//
//  Visual reference: manzo_ui_kit.html — `.win.playlist` section.
//  Maps to CSS classes: .win, .titlebar, .ptoolbar, .ghost, .sep,
//      .prow, .prow--active, .prow--missing, .idx, .time, .statusbar.
//
//  Public API (AppDelegate-facing):
//      var tracks: [PlaylistTrack]
//      var currentIndex: Int
//      func reloadData()
//      var onTrackSelected: ((Int) -> Void)?
//      var onAddTracks:     (() -> Void)?
//      var onRemoveTracks:  (() -> Void)?
//
//  No FFI. No manzo_core import.
//
import AppKit

// MARK: - Track model ---------------------------------------------------------

public struct PlaylistTrack {
    public var title:    String      // e.g. "Bonobo — Black Sands"
    public var duration: TimeInterval // seconds; <0 or .nan means unknown
    public var isMissing: Bool        // file not found → strikethrough row

    public init(title: String, duration: TimeInterval, isMissing: Bool = false) {
        self.title = title
        self.duration = duration
        self.isMissing = isMissing
    }

    /// "M:SS" — or "−:−−" for missing/unknown.
    public var durationString: String {
        if isMissing || duration.isNaN || duration < 0 { return "−:−−" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - P3 color tokens (mirror ManzoMainWindow.swift) ----------------------

private enum PLColor {
    static func p3(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(displayP3Red: r, green: g, blue: b, alpha: a)
    }
    // Base (classic) — matches main window
    static let baseTop      = p3(0.10, 0.10, 0.10)
    static let baseBottom   = p3(0.23, 0.23, 0.23)
    // Foreground
    static let fg1          = p3(1, 1, 1)
    static let fg2          = p3(0.78, 0.80, 0.85)
    static let fg3          = p3(0.58, 0.60, 0.65)
    // Selection / active row
    static let selectionBlue  = p3(0.15, 0.45, 0.85, 0.70)
    static let selectionBlueD = p3(0.10, 0.30, 0.60, 0.80)
    // Missing-row text
    static let missing      = p3(0.50, 0.52, 0.55, 0.75)
    // Hover wash
    static let hover        = p3(1, 1, 1, 0.03)
    // Toolbar / ghost button
    static let ghostBg      = p3(1, 1, 1, 0.04)
    static let ghostBgHover = p3(1, 1, 1, 0.10)
    static let toolbarBg    = p3(0, 0, 0, 0.20)
    static let sep          = p3(1, 1, 1, 0.10)
    static let rowBorder    = p3(1, 1, 1, 0.03)
    // Chrome
    static let rim          = p3(1, 1, 1, 0.45)
    static let specTop      = p3(1, 1, 1, 0.50)
    static let specMid      = p3(1, 1, 1, 0.08)
    static let lowerGlow    = p3(1, 1, 1, 0.12)
    // Title-/status-bar
    static let titlebarBg   = p3(1, 1, 1, 0.08)
    static let statusbarBg  = p3(0, 0, 0, 0.28)
    // Traffic lights
    static let tlRed    = p3(1.00, 0.38, 0.32)
    static let tlYellow = p3(1.00, 0.78, 0.15)
    static let tlGreen  = p3(0.32, 0.80, 0.30)
}

// MARK: - Panel ---------------------------------------------------------------

public final class ManzoPlaylistPanel: NSPanel {

    public let playlistView: ManzoPlaylistView

    // Forwarded data + callbacks ------------------------------------------------
    public var tracks: [PlaylistTrack] {
        get { playlistView.tracks }
        set { playlistView.tracks = newValue }
    }
    public var currentIndex: Int {
        get { playlistView.currentIndex }
        set { playlistView.currentIndex = newValue }
    }
    public func reloadData() { playlistView.reloadData() }

    public var onTrackSelected: ((Int) -> Void)? {
        get { playlistView.onTrackSelected } set { playlistView.onTrackSelected = newValue }
    }
    public var onAddTracks: (() -> Void)? {
        get { playlistView.onAddTracks } set { playlistView.onAddTracks = newValue }
    }
    public var onRemoveTracks: (() -> Void)? {
        get { playlistView.onRemoveTracks } set { playlistView.onRemoveTracks = newValue }
    }

    public convenience init() {
        let size = ManzoPlaylistView.intrinsicSize
        let rect = NSRect(origin: .zero, size: size)
        let view = ManzoPlaylistView(frame: rect)
        self.init(view: view, contentRect: rect)
    }

    private init(view: ManzoPlaylistView, contentRect: NSRect) {
        self.playlistView = view
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel, .utilityWindow, .resizable],
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

// MARK: - View ----------------------------------------------------------------

public final class ManzoPlaylistView: NSView {

    // MARK: Geometry — mirrors HTML kit
    public static let intrinsicSize = NSSize(width: 480, height: 220)
    private let titlebarH:  CGFloat = 14
    private let toolbarH:   CGFloat = 22
    private let statusbarH: CGFloat = 14
    private let rowH:       CGFloat = 24
    private let cornerR:    CGFloat = 10
    private let listPadV:   CGFloat = 4   // .padding 4px 0

    // MARK: Data
    public var tracks: [PlaylistTrack] = [] {
        didSet { reloadData() }
    }
    public var currentIndex: Int = -1 {
        didSet { rowsView.currentIndex = currentIndex; rowsView.needsDisplay = true }
    }

    // MARK: Callbacks
    public var onTrackSelected: ((Int) -> Void)?
    public var onAddTracks:     (() -> Void)?
    public var onRemoveTracks:  (() -> Void)?

    // MARK: Subviews
    private let titlebar  = TitlebarView(title: "PLAYLIST EDITOR")
    private let toolbar   = ToolbarView()
    private let scroller  = NSScrollView()
    fileprivate let rowsView = RowsView()
    private let statusbar = StatusbarView()

    // MARK: Init
    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius  = cornerR
        layer?.borderColor   = PLColor.rim.cgColor
        layer?.borderWidth   = 1

        // Toolbar wiring
        toolbar.onAdd    = { [weak self] in self?.onAddTracks?() }
        toolbar.onRemove = { [weak self] in self?.onRemoveTracks?() }
        toolbar.onSort   = { [weak self] in
            guard let s = self else { return }
            s.tracks.sort {
                ($0.title.lowercased(), $0.duration) <
                ($1.title.lowercased(), $1.duration)
            }
        }
        toolbar.onSave   = { /* reserved for V2 */ }

        // Rows wiring
        rowsView.onTrackSelected = { [weak self] i in
            self?.currentIndex = i
            self?.onTrackSelected?(i)
        }

        // Scroller hosting rowsView
        scroller.drawsBackground = false
        scroller.hasVerticalScroller = true
        scroller.scrollerStyle = .overlay
        scroller.autohidesScrollers = true
        scroller.documentView = rowsView
        scroller.contentView.drawsBackground = false

        addSubview(titlebar)
        addSubview(toolbar)
        addSubview(scroller)
        addSubview(statusbar)
    }
    public required init?(coder: NSCoder) { fatalError() }

    // MARK: Public — refresh after mutating `tracks` directly
    public func reloadData() {
        rowsView.tracks = tracks
        rowsView.currentIndex = currentIndex
        statusbar.update(trackCount: tracks.count,
                         missingCount: tracks.filter(\.isMissing).count,
                         totalSeconds: tracks.reduce(0) {
                             $0 + (($1.isMissing || $1.duration.isNaN || $1.duration < 0)
                                   ? 0 : $1.duration)
                         })
        rowsView.frame.size.height = max(scroller.contentSize.height,
                                         CGFloat(tracks.count) * rowH + listPadV * 2)
        rowsView.needsDisplay = true
        toolbar.update(trackCount: tracks.count,
                       totalSeconds: tracks.reduce(0) {
                           $0 + (($1.isMissing || $1.duration.isNaN || $1.duration < 0)
                                 ? 0 : $1.duration)
                       })
    }

    // MARK: Layout
    public override var intrinsicContentSize: NSSize { ManzoPlaylistView.intrinsicSize }

    public override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        titlebar.frame = NSRect(x: 0, y: h - titlebarH, width: w, height: titlebarH)
        toolbar.frame  = NSRect(x: 0, y: h - titlebarH - toolbarH,
                                width: w, height: toolbarH)
        statusbar.frame = NSRect(x: 0, y: 0, width: w, height: statusbarH)
        let listH = h - titlebarH - toolbarH - statusbarH
        scroller.frame = NSRect(x: 0, y: statusbarH, width: w, height: listH)

        // Doc view stays at full width; height grows with row count.
        let needed = max(listH, CGFloat(tracks.count) * rowH + listPadV * 2)
        rowsView.frame = NSRect(x: 0, y: 0, width: w, height: needed)
    }

    // MARK: Background — same gradient as ManzoMainWindow
    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let path = CGPath(roundedRect: bounds,
                          cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()

        let baseColors = [PLColor.baseTop.cgColor, PLColor.baseBottom.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: baseColors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: bounds.maxY),
                                   end:   CGPoint(x: 0, y: 0),
                                   options: [])
        }
        // Top specular
        let specColors = [PLColor.specTop.cgColor,
                          PLColor.specMid.cgColor,
                          NSColor.clear.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: specColors,
                              locations: [0, 0.23, 0.52]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: bounds.maxY),
                                   end:   CGPoint(x: 0, y: bounds.maxY - bounds.height * 0.52),
                                   options: [])
        }
        // Lower glow
        let glowColors = [NSColor.clear.cgColor, PLColor.lowerGlow.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: glowColors, locations: [0, 1]) {
            ctx.drawLinearGradient(g,
                                   start: CGPoint(x: 0, y: bounds.height * 0.25),
                                   end:   CGPoint(x: 0, y: 0),
                                   options: [])
        }
        ctx.restoreGState()
    }
}

// MARK: - Titlebar (14pt) -----------------------------------------------------

private final class TitlebarView: NSView {
    private let close = TrafficDot(color: PLColor.tlRed)
    private let mini  = TrafficDot(color: PLColor.tlYellow)
    private let maxi  = TrafficDot(color: PLColor.tlGreen)
    private let label = NSTextField(labelWithString: "PLAYLIST EDITOR")
    private let dim   = NSTextField(labelWithString: "350×420")

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PLColor.titlebarBg.cgColor
        [close, mini, maxi].forEach { addSubview($0) }

        label.stringValue = title
        styleCaps(label, color: PLColor.fg3)
        addSubview(label)

        styleCaps(dim, color: PLColor.fg3)
        dim.alphaValue = 0.5
        addSubview(dim)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func styleCaps(_ tf: NSTextField, color: NSColor) {
        tf.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        tf.textColor = color
        tf.isBezeled = false; tf.drawsBackground = false; tf.isEditable = false
        tf.alignment = .center
    }

    override func layout() {
        super.layout()
        let dotSize: CGFloat = 8
        let y = (bounds.height - dotSize) / 2
        close.frame = NSRect(x: 10,           y: y, width: dotSize, height: dotSize)
        mini.frame  = NSRect(x: 10 + 14,      y: y, width: dotSize, height: dotSize)
        maxi.frame  = NSRect(x: 10 + 14 + 14, y: y, width: dotSize, height: dotSize)

        label.sizeToFit()
        label.frame = NSRect(x: (bounds.width - label.bounds.width) / 2,
                             y: (bounds.height - label.bounds.height) / 2,
                             width: label.bounds.width, height: label.bounds.height)

        dim.sizeToFit()
        dim.frame = NSRect(x: bounds.width - dim.bounds.width - 10,
                           y: (bounds.height - dim.bounds.height) / 2,
                           width: dim.bounds.width, height: dim.bounds.height)
    }
}

private final class TrafficDot: NSView {
    let color: NSColor
    init(color: NSColor) { self.color = color; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        let p = NSBezierPath(ovalIn: bounds)
        color.setFill(); p.fill()
        PLColor.p3(1, 1, 1, 0.18).setStroke()
        p.lineWidth = 0.5; p.stroke()
    }
}

// MARK: - Toolbar (22pt) ------------------------------------------------------

private final class ToolbarView: NSView {

    var onAdd:    (() -> Void)?
    var onRemove: (() -> Void)?
    var onSort:   (() -> Void)?
    var onSave:   (() -> Void)?

    private let addBtn = GhostButton(title: "+ ADD")
    private let remBtn = GhostButton(title: "− REM")
    private let sep1   = SeparatorTick()
    private let sortBtn = GhostButton(title: "SORT")
    private let saveBtn = GhostButton(title: "SAVE")
    private let countLabel = NSTextField(labelWithString: "0 TRACKS · 0:00")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = PLColor.toolbarBg.cgColor

        addBtn.onClick  = { [weak self] in self?.onAdd?()    }
        remBtn.onClick  = { [weak self] in self?.onRemove?() }
        sortBtn.onClick = { [weak self] in self?.onSort?()   }
        saveBtn.onClick = { [weak self] in self?.onSave?()   }

        countLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = PLColor.fg3
        countLabel.isBezeled = false; countLabel.drawsBackground = false
        countLabel.isEditable = false; countLabel.alignment = .right

        [addBtn, remBtn, sep1, sortBtn, saveBtn, countLabel].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(trackCount: Int, totalSeconds: TimeInterval) {
        let total = Int(totalSeconds.rounded())
        countLabel.stringValue =
            "\(trackCount) TRACK\(trackCount == 1 ? "" : "S") · " +
            String(format: "%d:%02d", total / 60, total % 60)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 10
        let y: CGFloat = 0
        let h = bounds.height
        for ghost in [addBtn, remBtn] {
            ghost.sizeToFit()
            ghost.frame = NSRect(x: x, y: (h - ghost.bounds.height) / 2,
                                 width: ghost.bounds.width, height: ghost.bounds.height)
            x += ghost.bounds.width + 6
        }
        sep1.frame = NSRect(x: x, y: (h - 10) / 2, width: 1, height: 10)
        x += 1 + 6
        for ghost in [sortBtn, saveBtn] {
            ghost.sizeToFit()
            ghost.frame = NSRect(x: x, y: (h - ghost.bounds.height) / 2,
                                 width: ghost.bounds.width, height: ghost.bounds.height)
            x += ghost.bounds.width + 6
        }
        countLabel.sizeToFit()
        countLabel.frame = NSRect(x: bounds.width - countLabel.bounds.width - 10,
                                  y: (h - countLabel.bounds.height) / 2,
                                  width: countLabel.bounds.width,
                                  height: countLabel.bounds.height)
        _ = y
    }

    override func draw(_ dirtyRect: NSRect) {
        // Bottom 1px hairline
        PLColor.p3(1, 1, 1, 0.04).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 1)).fill()
    }
}

private final class GhostButton: NSView {
    private(set) var title: String
    var onClick: (() -> Void)?
    private var hovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override func sizeToFit() {
        let attr = Self.attrs(hovered: false)
        let s = (title as NSString).size(withAttributes: attr)
        frame.size = NSSize(width: ceil(s.width) + 12, height: 14)
    }

    private static func attrs(hovered: Bool) -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 10, weight: .medium),
         .foregroundColor: hovered ? NSColor.white : PLColor.fg3,
         .kern: 0.8]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInKeyWindow],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }

    override func mouseEntered(with event: NSEvent) { hovered = true  }
    override func mouseExited (with event: NSEvent) { hovered = false }
    override func mouseDown   (with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let bg = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
        (hovered ? PLColor.ghostBgHover : PLColor.ghostBg).setFill()
        bg.fill()
        let attr = Self.attrs(hovered: hovered)
        let s = (title as NSString)
        let size = s.size(withAttributes: attr)
        s.draw(at: NSPoint(x: (r.width  - size.width)  / 2,
                           y: (r.height - size.height) / 2),
               withAttributes: attr)
    }
}

private final class SeparatorTick: NSView {
    override func draw(_ dirtyRect: NSRect) {
        PLColor.sep.setFill()
        NSBezierPath(rect: bounds).fill()
    }
}

// MARK: - Rows view (the scrollable list) -------------------------------------

fileprivate final class RowsView: NSView {

    var tracks: [PlaylistTrack] = []
    var currentIndex: Int = -1
    var onTrackSelected: ((Int) -> Void)?

    private let rowH: CGFloat = 24
    private let listPadV: CGFloat = 4
    private var hoverIndex: Int = -1
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Hit-testing
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .mouseMoved,
                                         .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }

    private func indexAt(_ p: NSPoint) -> Int {
        guard p.y >= listPadV else { return -1 }
        let i = Int((p.y - listPadV) / rowH)
        return (i >= 0 && i < tracks.count) ? i : -1
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let new = indexAt(p)
        if new != hoverIndex { hoverIndex = new; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) {
        if hoverIndex != -1 { hoverIndex = -1; needsDisplay = true }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = indexAt(p)
        if i >= 0 { onTrackSelected?(i) }
    }

    // MARK: Painting
    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        for (i, track) in tracks.enumerated() {
            let y = listPadV + CGFloat(i) * rowH
            let rowRect = NSRect(x: 0, y: y, width: w, height: rowH)
            drawRow(track: track, index: i, rect: rowRect)
        }
    }

    private func drawRow(track: PlaylistTrack, index i: Int, rect: NSRect) {
        let isActive  = (i == currentIndex)
        let isHover   = (i == hoverIndex && !isActive)
        let isMissing = track.isMissing

        // Background
        if isActive {
            let inset = NSRect(x: rect.minX + 4, y: rect.minY + 1,
                               width: rect.width - 8, height: rect.height - 2)
            let p = NSBezierPath(roundedRect: inset, xRadius: 3, yRadius: 3)
            // Vertical gradient blue → darker blue
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                p.addClip()
                let cs = [PLColor.selectionBlue.cgColor,
                          PLColor.selectionBlueD.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                                      colors: cs, locations: [0, 1]) {
                    ctx.drawLinearGradient(g,
                                           start: CGPoint(x: 0, y: inset.maxY),
                                           end:   CGPoint(x: 0, y: inset.minY),
                                           options: [])
                }
                ctx.restoreGState()
            }
        } else if isHover {
            PLColor.hover.setFill()
            NSBezierPath(rect: rect).fill()
        }

        // Bottom 1px row separator (skip last; skip behind active)
        if !isActive {
            PLColor.rowBorder.setFill()
            NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - 1,
                                      width: rect.width, height: 1)).fill()
        }

        // Text colors
        let mainColor: NSColor
        let dimColor:  NSColor
        if isActive {
            mainColor = NSColor.white
            dimColor  = NSColor.white.withAlphaComponent(0.9)
        } else if isMissing {
            mainColor = PLColor.missing
            dimColor  = PLColor.missing
        } else {
            mainColor = PLColor.fg2
            dimColor  = PLColor.fg3
        }

        // Common attrs
        let monoFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let textFont = NSFont.systemFont(ofSize: 11, weight: .regular)

        var idxAttr: [NSAttributedString.Key: Any] = [
            .font: monoFont, .foregroundColor: dimColor]
        var titleAttr: [NSAttributedString.Key: Any] = [
            .font: textFont, .foregroundColor: mainColor]
        var timeAttr: [NSAttributedString.Key: Any] = [
            .font: monoFont, .foregroundColor: dimColor]

        if isMissing {
            idxAttr[.strikethroughStyle]   = NSUnderlineStyle.single.rawValue
            titleAttr[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            timeAttr[.strikethroughStyle]  = NSUnderlineStyle.single.rawValue
            idxAttr[.strikethroughColor]   = PLColor.missing
            titleAttr[.strikethroughColor] = PLColor.missing
            timeAttr[.strikethroughColor]  = PLColor.missing
        }

        // Layout: 12px left padding, 28px idx column, then title; time right-aligned, 12px right pad
        let padL: CGFloat = 12, padR: CGFloat = 12
        let idxColW: CGFloat = 28

        let idxStr = String(format: "%02d.", i + 1) as NSString
        let idxSize = idxStr.size(withAttributes: idxAttr)
        let idxY = rect.minY + (rect.height - idxSize.height) / 2
        idxStr.draw(at: NSPoint(x: rect.minX + padL, y: idxY), withAttributes: idxAttr)

        // Time on the right
        let displayTime = isMissing ? "−:−−" : track.durationString
        let timeStr = displayTime as NSString
        let timeSize = timeStr.size(withAttributes: timeAttr)
        let timeX = rect.maxX - padR - timeSize.width
        let timeY = rect.minY + (rect.height - timeSize.height) / 2
        timeStr.draw(at: NSPoint(x: timeX, y: timeY), withAttributes: timeAttr)

        // Title (truncated to fit between idx column and time)
        let titleX = rect.minX + padL + idxColW
        let titleAvailW = max(0, timeX - 8 - titleX)
        var titleText = track.title
        if isMissing && !titleText.lowercased().contains("missing") {
            titleText += " (missing)"
        }
        let drawnTitle = truncate(titleText, attrs: titleAttr, maxWidth: titleAvailW)
        let titleStr = drawnTitle as NSString
        let titleSize = titleStr.size(withAttributes: titleAttr)
        let titleY = rect.minY + (rect.height - titleSize.height) / 2
        titleStr.draw(in: NSRect(x: titleX, y: titleY,
                                 width: titleAvailW, height: titleSize.height),
                      withAttributes: titleAttr)
    }

    private func truncate(_ s: String,
                          attrs: [NSAttributedString.Key: Any],
                          maxWidth: CGFloat) -> String {
        let ns = s as NSString
        if ns.size(withAttributes: attrs).width <= maxWidth { return s }
        let ellipsis = "…"
        var lo = 0, hi = ns.length
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = ns.substring(to: mid) + ellipsis
            let w = (candidate as NSString).size(withAttributes: attrs).width
            if w <= maxWidth { lo = mid } else { hi = mid - 1 }
        }
        return ns.substring(to: lo) + ellipsis
    }
}

// MARK: - Statusbar (14pt) ----------------------------------------------------

private final class StatusbarView: NSView {
    private let left  = NSTextField(labelWithString: "0 TRACKS · 0 MISSING")
    private let right = NSTextField(labelWithString: "0:00")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = PLColor.statusbarBg.cgColor

        for tf in [left, right] {
            tf.font = NSFont.systemFont(ofSize: 9, weight: .medium)
            tf.textColor = PLColor.fg3
            tf.isBezeled = false; tf.drawsBackground = false; tf.isEditable = false
        }
        addSubview(left); addSubview(right)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(trackCount: Int, missingCount: Int, totalSeconds: TimeInterval) {
        left.stringValue = "\(trackCount) TRACK\(trackCount == 1 ? "" : "S") · " +
                           "\(missingCount) MISSING"
        let total = Int(totalSeconds.rounded())
        right.stringValue = String(format: "%d:%02d", total / 60, total % 60)
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        left.sizeToFit()
        left.frame.origin = NSPoint(x: 10,
                                    y: (bounds.height - left.bounds.height) / 2)
        right.sizeToFit()
        right.frame.origin = NSPoint(x: bounds.width - right.bounds.width - 10,
                                     y: (bounds.height - right.bounds.height) / 2)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Top 1px hairline (matches HTML border-top)
        PLColor.p3(1, 1, 1, 0.04).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.maxY - 1,
                                  width: bounds.width, height: 1)).fill()
    }
}
