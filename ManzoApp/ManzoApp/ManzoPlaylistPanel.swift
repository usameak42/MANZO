//
//  ManzoPlaylistPanel.swift
//  MANZO — Playlist Editor panel (LOCAL + ONLINE tabs).
//
//  Drop-in, dependency-free. NSPanel (non-activating, utility-style) hosting
//  ManzoPlaylistView. Width 480pt; height auto-fits via setContentSize(_:).
//
//  Layout (top → bottom):
//      ┌─────────────────────────────────────────────────────┐  14  titlebar
//      │  ● ● ●        PLAYLIST EDITOR             480×320   │
//      ├─────────────────────────────────────────────────────┤  26  tab bar
//      │  [LOCAL 6] [ONLINE 7]              · QUEUE FEEDS …  │
//      ├─────────────────────────────────────────────────────┤
//      │  toolbar (LOCAL)  OR  source-pills + URL+ADD (ONLINE)
//      ├─────────────────────────────────────────────────────┤
//      │  scroll list (rows)                                 │
//      ├─────────────────────────────────────────────────────┤  14  statusbar
//      └─────────────────────────────────────────────────────┘
//
//  Visual reference: playlist-online-explorations.html (variation A).
//
//  Public API:
//      // LOCAL
//      var tracks: [PlaylistTrack]
//      var currentIndex: Int
//      func reloadData()
//      var onTrackSelected: ((Int) -> Void)?
//      var onAddTracks:     (() -> Void)?
//      var onRemoveTracks:  (() -> Void)?
//
//      // ONLINE
//      var onlineQueue: ManzoOnlineQueue   // assign once at boot
//      var onPlayOnline: ((OnlineTrack) -> Void)?
//
//      // Tabs
//      var activeTab: Tab           // .local / .online
//
//  No FFI. No manzo_core import.
//
import AppKit

// MARK: - Local-track model (unchanged) ---------------------------------------

public struct PlaylistTrack {
    public var title:    String
    public var duration: TimeInterval
    public var isMissing: Bool

    public init(title: String, duration: TimeInterval, isMissing: Bool = false) {
        self.title = title
        self.duration = duration
        self.isMissing = isMissing
    }
    public var durationString: String {
        if isMissing || duration.isNaN || duration < 0 { return "−:−−" }
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Color tokens (P3, mirror ManzoMainWindow.swift) ---------------------

private enum PLColor {
    static func p3(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
        NSColor(displayP3Red: r, green: g, blue: b, alpha: a)
    }
    static let baseTop      = p3(0.10, 0.10, 0.10)
    static let baseBottom   = p3(0.23, 0.23, 0.23)
    static let fg1          = p3(1, 1, 1)
    static let fg2          = p3(0.78, 0.80, 0.85)
    static let fg3          = p3(0.58, 0.60, 0.65)
    static let selectionBlue  = p3(0.15, 0.45, 0.85, 0.70)
    static let selectionBlueD = p3(0.10, 0.30, 0.60, 0.80)
    static let missing      = p3(0.50, 0.52, 0.55, 0.75)
    static let hover        = p3(1, 1, 1, 0.03)
    static let ghostBg      = p3(1, 1, 1, 0.04)
    static let ghostBgHover = p3(1, 1, 1, 0.10)
    static let toolbarBg    = p3(0, 0, 0, 0.20)
    static let urlbarBg     = p3(0, 0, 0, 0.28)
    static let inputBg      = p3(0, 0, 0, 0.55)
    static let sep          = p3(1, 1, 1, 0.10)
    static let rowBorder    = p3(1, 1, 1, 0.03)
    static let rim          = p3(1, 1, 1, 0.45)
    static let specTop      = p3(1, 1, 1, 0.50)
    static let specMid      = p3(1, 1, 1, 0.08)
    static let lowerGlow    = p3(1, 1, 1, 0.12)
    static let titlebarBg   = p3(1, 1, 1, 0.08)
    static let statusbarBg  = p3(0, 0, 0, 0.28)
    // Traffic lights
    static let tlRed    = p3(1.00, 0.38, 0.32)
    static let tlYellow = p3(1.00, 0.78, 0.15)
    static let tlGreen  = p3(0.32, 0.80, 0.30)
    // Source brand-ish (desaturated)
    static let ytRed    = p3(0.92, 0.20, 0.20)
    static let ytRedBg  = p3(0.92, 0.20, 0.20, 0.18)
    static let ytRedRim = p3(0.92, 0.20, 0.20, 0.55)
    static let scOrange   = p3(1.00, 0.45, 0.10)
    static let scOrangeBg = p3(1.00, 0.45, 0.10, 0.18)
    static let scOrangeRim = p3(1.00, 0.45, 0.10, 0.55)
    // ADD button
    static let addBlueTop = p3(0.15, 0.45, 0.85, 0.85)
    static let addBlueBot = p3(0.10, 0.30, 0.60, 0.95)
    // Live indicator
    static let live     = p3(1, 0.30, 0.25)
    // Danger / clear
    static let danger   = p3(0.95, 0.55, 0.50)
    static let dangerBg = p3(1, 0.30, 0.25, 0.30)
}

// MARK: - Tab enum ------------------------------------------------------------

public enum PlaylistTab: String { case local, online }

// MARK: - Panel ---------------------------------------------------------------

public final class ManzoPlaylistPanel: NSPanel {

    public let playlistView: ManzoPlaylistView

    // LOCAL forwards
    public var tracks: [PlaylistTrack] {
        get { playlistView.tracks } set { playlistView.tracks = newValue }
    }
    public var currentIndex: Int {
        get { playlistView.currentIndex } set { playlistView.currentIndex = newValue }
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

    // ONLINE forwards
    public var onlineQueue: ManzoOnlineQueue {
        get { playlistView.onlineQueue } set { playlistView.onlineQueue = newValue }
    }
    public var onPlayOnline: ((OnlineTrack) -> Void)? {
        get { playlistView.onPlayOnline } set { playlistView.onPlayOnline = newValue }
    }

    // Tab forwards
    public var activeTab: PlaylistTab {
        get { playlistView.activeTab } set { playlistView.activeTab = newValue }
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
                   backing: .buffered, defer: false)
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
    public override var canBecomeKey: Bool  { true }
    public override var canBecomeMain: Bool { false }
}

// MARK: - View ----------------------------------------------------------------

public final class ManzoPlaylistView: NSView {

    // Geometry
    public static let intrinsicSize = NSSize(width: 540, height: 320)
    private let titlebarH:  CGFloat = 14
    private let tabbarH:    CGFloat = 26
    private let toolbarH:   CGFloat = 22
    private let urlbarH:    CGFloat = 32
    private let statusbarH: CGFloat = 14
    private let rowH:       CGFloat = 24
    private let cornerR:    CGFloat = 10
    private let listPadV:   CGFloat = 4

    // LOCAL data
    public var tracks: [PlaylistTrack] = [] { didSet { reloadData() } }
    public var currentIndex: Int = -1 {
        didSet { localRows.currentIndex = currentIndex; localRows.needsDisplay = true }
    }
    public var onTrackSelected: ((Int) -> Void)?
    public var onAddTracks:     (() -> Void)?
    public var onRemoveTracks:  (() -> Void)?

    // ONLINE data
    public var onlineQueue: ManzoOnlineQueue = ManzoOnlineQueue() {
        didSet {
            onlineQueue.onChange = { [weak self] in self?.reloadData() }
            onlineQueue.onPlay   = { [weak self] t in self?.onPlayOnline?(t) }
            reloadData()
        }
    }
    public var onPlayOnline: ((OnlineTrack) -> Void)?

    // Tab state
    public var activeTab: PlaylistTab = .local { didSet { applyTabState() } }

    // Subviews
    private let titlebar  = TitlebarView(title: "PLAYLIST EDITOR")
    private let tabbar    = TabBarView()
    private let toolbar   = ToolbarView()         // LOCAL
    private let sourceRow = SourceFilterRow()     // ONLINE
    private let urlbar    = URLBarView()          // ONLINE
    private let scroller  = NSScrollView()
    fileprivate let localRows = LocalRowsView()
    fileprivate let onlineRows = OnlineRowsView()
    private let statusbar = StatusbarView()

    // Init
    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius  = cornerR
        layer?.borderColor   = PLColor.rim.cgColor
        layer?.borderWidth   = 1

        // Tabs
        tabbar.onSelectTab = { [weak self] t in self?.activeTab = t }

        // LOCAL toolbar
        toolbar.onAdd    = { [weak self] in self?.onAddTracks?() }
        toolbar.onRemove = { [weak self] in self?.onRemoveTracks?() }
        toolbar.onSort   = { [weak self] in
            guard let s = self else { return }
            s.tracks.sort {
                ($0.title.lowercased(), $0.duration) <
                ($1.title.lowercased(), $1.duration)
            }
        }
        toolbar.onSave = { /* V2 */ }

        // ONLINE source filter
        sourceRow.onSelectFilter = { [weak self] f in
            self?.onlineQueue.filter = f
            self?.reloadData()
        }

        // ONLINE url bar
        urlbar.onAdd = { [weak self] raw in
            guard let s = self else { return }
            s.urlbar.setState(.validating)
            s.onlineQueue.addURL(raw) { state in
                switch state {
                case .validating:        s.urlbar.setState(.validating)
                case .success:           s.urlbar.setState(.success); s.urlbar.clearText()
                case .failure(let err):  s.urlbar.setState(.error(err.localizedDescription))
                }
            }
        }
        urlbar.onClearAll = { [weak self] in self?.onlineQueue.clearAll() }

        // LOCAL rows
        localRows.onTrackSelected = { [weak self] i in
            self?.currentIndex = i
            self?.onTrackSelected?(i)
        }

        // ONLINE rows
        onlineRows.onPlay   = { [weak self] i in self?.onlineQueue.play(at: i) }
        onlineRows.onRemove = { [weak self] i in self?.onlineQueue.remove(at: i) }

        // Scroller hosts whichever rows view is active.
        scroller.drawsBackground = false
        scroller.hasVerticalScroller = true
        scroller.scrollerStyle = .overlay
        scroller.autohidesScrollers = true
        scroller.contentView.drawsBackground = false

        statusbar.onClearAll = { [weak self] in self?.onlineQueue.clearAll() }

        addSubview(titlebar)
        addSubview(tabbar)
        addSubview(toolbar)
        addSubview(sourceRow)
        addSubview(urlbar)
        addSubview(scroller)
        addSubview(statusbar)

        // Hook online queue change emissions immediately.
        onlineQueue.onChange = { [weak self] in self?.reloadData() }
        onlineQueue.onPlay   = { [weak self] t in self?.onPlayOnline?(t) }

        applyTabState()
    }
    public required init?(coder: NSCoder) { fatalError() }

    // Public reload
    public func reloadData() {
        // LOCAL
        localRows.tracks = tracks
        localRows.currentIndex = currentIndex
        localRows.needsDisplay = true
        // ONLINE
        onlineRows.snapshot = onlineQueue.filteredTracks
        onlineRows.currentIndex = onlineQueue.currentIndex
        onlineRows.needsDisplay = true

        // Counts
        let totalLocal = tracks.reduce(0) {
            $0 + (($1.isMissing || $1.duration.isNaN || $1.duration < 0) ? 0 : $1.duration)
        }
        toolbar.update(trackCount: tracks.count, totalSeconds: totalLocal)
        tabbar.update(localCount: tracks.count, onlineCount: onlineQueue.tracks.count,
                      activeTab: activeTab)
        sourceRow.update(filter: onlineQueue.filter,
                         filteredOf: onlineQueue.filteredTracks.count,
                         total: onlineQueue.tracks.count)

        // Statusbar
        switch activeTab {
        case .local:
            statusbar.updateLocal(trackCount: tracks.count,
                                  missingCount: tracks.filter(\.isMissing).count,
                                  totalSeconds: totalLocal)
        case .online:
            statusbar.updateOnline(trackCount: onlineQueue.tracks.count,
                                   ytCount: onlineQueue.youtubeCount,
                                   scCount: onlineQueue.soundcloudCount,
                                   liveCount: onlineQueue.liveCount,
                                   totalSeconds: onlineQueue.totalSeconds)
        }

        layoutListSize()
    }

    private func applyTabState() {
        let isLocal = (activeTab == .local)
        toolbar.isHidden  = !isLocal
        sourceRow.isHidden = isLocal
        urlbar.isHidden    = isLocal
        scroller.documentView = isLocal ? localRows : onlineRows
        needsLayout = true
        reloadData()
    }

    private func layoutListSize() {
        let listW = bounds.width
        let count = (activeTab == .local) ? tracks.count : onlineQueue.filteredTracks.count
        let needed = max(scroller.contentSize.height,
                         CGFloat(count) * rowH + listPadV * 2)
        let docView = scroller.documentView as? NSView
        docView?.frame = NSRect(x: 0, y: 0, width: listW, height: needed)
    }

    public override var intrinsicContentSize: NSSize { ManzoPlaylistView.intrinsicSize }

    public override func layout() {
        super.layout()
        let w = bounds.width
        let h = bounds.height
        var y = h
        y -= titlebarH;   titlebar.frame  = NSRect(x: 0, y: y, width: w, height: titlebarH)
        y -= tabbarH;     tabbar.frame    = NSRect(x: 0, y: y, width: w, height: tabbarH)

        if activeTab == .local {
            y -= toolbarH; toolbar.frame  = NSRect(x: 0, y: y, width: w, height: toolbarH)
        } else {
            y -= toolbarH; sourceRow.frame = NSRect(x: 0, y: y, width: w, height: toolbarH)
            y -= urlbarH;  urlbar.frame    = NSRect(x: 0, y: y, width: w, height: urlbarH)
        }

        statusbar.frame = NSRect(x: 0, y: 0, width: w, height: statusbarH)
        let listH = y - statusbarH
        scroller.frame = NSRect(x: 0, y: statusbarH, width: w, height: listH)
        layoutListSize()
    }

    // Background — same gradient as ManzoMainWindow.
    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let space = CGColorSpace(name: CGColorSpace.displayP3)!
        let path = CGPath(roundedRect: bounds, cornerWidth: cornerR, cornerHeight: cornerR, transform: nil)
        ctx.saveGState(); ctx.addPath(path); ctx.clip()

        let baseColors = [PLColor.baseTop.cgColor, PLColor.baseBottom.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: baseColors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: bounds.maxY),
                                   end: CGPoint(x: 0, y: 0), options: [])
        }
        let specColors = [PLColor.specTop.cgColor, PLColor.specMid.cgColor, NSColor.clear.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: specColors, locations: [0, 0.23, 0.52]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: bounds.maxY),
                                   end: CGPoint(x: 0, y: bounds.maxY - bounds.height * 0.52),
                                   options: [])
        }
        let glowColors = [NSColor.clear.cgColor, PLColor.lowerGlow.cgColor] as CFArray
        if let g = CGGradient(colorsSpace: space, colors: glowColors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: bounds.height * 0.25),
                                   end: CGPoint(x: 0, y: 0), options: [])
        }
        ctx.restoreGState()
    }
}

// MARK: - Titlebar (unchanged) ------------------------------------------------

private final class TitlebarView: NSView {
    private let close = TrafficDot(color: PLColor.tlRed)
    private let mini  = TrafficDot(color: PLColor.tlYellow)
    private let maxi  = TrafficDot(color: PLColor.tlGreen)
    private let label = NSTextField(labelWithString: "PLAYLIST EDITOR")
    private let dim   = NSTextField(labelWithString: "480×320")

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = PLColor.titlebarBg.cgColor
        [close, mini, maxi].forEach { addSubview($0) }
        label.stringValue = title
        styleCaps(label, color: PLColor.fg3); addSubview(label)
        styleCaps(dim, color: PLColor.fg3); dim.alphaValue = 0.5; addSubview(dim)
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
        PLColor.p3(1, 1, 1, 0.18).setStroke(); p.lineWidth = 0.5; p.stroke()
    }
}

// MARK: - Tab bar (LOCAL | ONLINE) -------------------------------------------

private final class TabBarView: NSView {
    var onSelectTab: ((PlaylistTab) -> Void)?

    private let localTab  = TabPill(label: "Local")
    private let onlineTab = TabPill(label: "Online")
    private let segmentBg = NSView()
    private let hint      = NSTextField(labelWithString: "")

    private var activeTab: PlaylistTab = .local

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = PLColor.toolbarBg.cgColor

        segmentBg.wantsLayer = true
        segmentBg.layer?.backgroundColor = PLColor.p3(0, 0, 0, 0.45).cgColor
        segmentBg.layer?.cornerRadius = 10
        segmentBg.layer?.borderColor  = PLColor.p3(1, 1, 1, 0.05).cgColor
        segmentBg.layer?.borderWidth  = 1
        addSubview(segmentBg)
        addSubview(localTab)
        addSubview(onlineTab)

        localTab.onClick  = { [weak self] in self?.onSelectTab?(.local) }
        onlineTab.onClick = { [weak self] in self?.onSelectTab?(.online) }

        hint.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
        hint.textColor = PLColor.fg3
        hint.isBezeled = false; hint.drawsBackground = false; hint.isEditable = false
        hint.stringValue = "· FILES ON DISK ·"
        addSubview(hint)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(localCount: Int, onlineCount: Int, activeTab tab: PlaylistTab) {
        self.activeTab = tab
        localTab.set(active:  tab == .local,  count: localCount)
        onlineTab.set(active: tab == .online, count: onlineCount)
        hint.stringValue = (tab == .online) ? "· QUEUE FEEDS PLAYER ·" : "· FILES ON DISK ·"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let segH: CGFloat = 22
        let y = (bounds.height - segH) / 2
        localTab.sizeToFit()
        onlineTab.sizeToFit()
        let totalW = localTab.bounds.width + onlineTab.bounds.width + 4
        segmentBg.frame = NSRect(x: 10, y: y, width: totalW, height: segH)
        localTab.frame  = NSRect(x: 12, y: y + 1,
                                 width: localTab.bounds.width, height: segH - 2)
        onlineTab.frame = NSRect(x: 12 + localTab.bounds.width,
                                 y: y + 1, width: onlineTab.bounds.width, height: segH - 2)

        hint.sizeToFit()
        hint.frame = NSRect(x: bounds.width - hint.bounds.width - 10,
                            y: (bounds.height - hint.bounds.height) / 2,
                            width: hint.bounds.width, height: hint.bounds.height)
    }
}

private final class TabPill: NSView {
    private let labelText: String
    private(set) var count: Int = 0
    private var isActive = false
    var onClick: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    init(label: String) {
        self.labelText = label
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(active: Bool, count: Int) {
        self.isActive = active; self.count = count
        layer?.cornerRadius = 8
        needsDisplay = true
    }

    func sizeToFit() {
        let s = (textAttr().0)
        let w = (labelText as NSString).size(withAttributes: s).width
        let cs = ("\(count)" as NSString).size(withAttributes: countAttr())
        frame.size = NSSize(width: ceil(w + cs.width) + 26, height: 18)
    }

    private func textAttr() -> ([NSAttributedString.Key: Any], CGSize) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: isActive ? NSColor.white : PLColor.fg3,
            .kern: 1.2,
        ]
        let size = (labelText as NSString).size(withAttributes: attr)
        return (attr, size)
    }
    private func countAttr() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .medium),
         .foregroundColor: isActive ? NSColor.white : PLColor.p3(1, 1, 1, 0.55)]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInKeyWindow],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        if isActive {
            let bg = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            let cs = [PLColor.p3(1, 1, 1, 0.18).cgColor, PLColor.p3(1, 1, 1, 0.04).cgColor] as CFArray
            if let ctx = NSGraphicsContext.current?.cgContext,
               let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                                  colors: cs, locations: [0, 1]) {
                ctx.saveGState(); bg.addClip()
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.maxY),
                                       end: CGPoint(x: 0, y: 0), options: [])
                ctx.restoreGState()
            }
            PLColor.p3(1, 1, 1, 0.25).setStroke(); bg.lineWidth = 1; bg.stroke()
        }

        let (attr, _) = textAttr()
        let label = labelText as NSString
        let labelSize = label.size(withAttributes: attr)
        label.draw(at: NSPoint(x: 10, y: (r.height - labelSize.height) / 2),
                   withAttributes: attr)

        // Count chip
        let cAttr = countAttr()
        let cStr = "\(count)" as NSString
        let cSize = cStr.size(withAttributes: cAttr)
        let chipW = cSize.width + 8, chipH: CGFloat = 12
        let chipX = 10 + labelSize.width + 6
        let chipY = (r.height - chipH) / 2
        let chip = NSBezierPath(roundedRect: NSRect(x: chipX, y: chipY,
                                                    width: chipW, height: chipH),
                                xRadius: 5, yRadius: 5)
        (isActive ? PLColor.p3(1, 1, 1, 0.18) : PLColor.p3(0, 0, 0, 0.35)).setFill()
        chip.fill()
        cStr.draw(at: NSPoint(x: chipX + 4, y: chipY + (chipH - cSize.height) / 2),
                  withAttributes: cAttr)
    }
}

// MARK: - LOCAL toolbar (unchanged behaviour) ---------------------------------

private final class ToolbarView: NSView {
    var onAdd:    (() -> Void)?
    var onRemove: (() -> Void)?
    var onSort:   (() -> Void)?
    var onSave:   (() -> Void)?

    private let addBtn  = GhostButton(title: "+ ADD")
    private let remBtn  = GhostButton(title: "− REM")
    private let sep1    = SeparatorTick()
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
    }
    override func draw(_ dirtyRect: NSRect) {
        PLColor.p3(1, 1, 1, 0.04).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 1)).fill()
    }
}

private final class GhostButton: NSView {
    private(set) var title: String
    var onClick: (() -> Void)?
    var isDanger: Bool = false { didSet { needsDisplay = true } }
    private var hovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(title: String) { self.title = title; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    func sizeToFit() {
        let attr = attrs(hovered: false)
        let s = (title as NSString).size(withAttributes: attr)
        frame.size = NSSize(width: ceil(s.width) + 12, height: 14)
    }

    private func attrs(hovered: Bool) -> [NSAttributedString.Key: Any] {
        let color: NSColor = isDanger
            ? (hovered ? .white : PLColor.danger)
            : (hovered ? .white : PLColor.fg3)
        return [.font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: color,
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
        let fill: NSColor = isDanger
            ? (hovered ? PLColor.dangerBg : PLColor.ghostBg)
            : (hovered ? PLColor.ghostBgHover : PLColor.ghostBg)
        fill.setFill(); bg.fill()
        let attr = attrs(hovered: hovered)
        let s = (title as NSString)
        let size = s.size(withAttributes: attr)
        s.draw(at: NSPoint(x: (r.width - size.width) / 2,
                           y: (r.height - size.height) / 2),
               withAttributes: attr)
    }
}

private final class SeparatorTick: NSView {
    override func draw(_ dirtyRect: NSRect) {
        PLColor.sep.setFill(); NSBezierPath(rect: bounds).fill()
    }
}

// MARK: - Source filter row (ONLINE) ------------------------------------------

private final class SourceFilterRow: NSView {
    var onSelectFilter: ((OnlineSourceFilter) -> Void)?

    private let allPill = SourcePill(kind: .all)
    private let ytPill  = SourcePill(kind: .yt)
    private let scPill  = SourcePill(kind: .sc)
    private let countLabel = NSTextField(labelWithString: "0 of 0")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = PLColor.toolbarBg.cgColor
        allPill.onClick = { [weak self] in self?.onSelectFilter?(.all) }
        ytPill.onClick  = { [weak self] in self?.onSelectFilter?(.only(.youtube)) }
        scPill.onClick  = { [weak self] in self?.onSelectFilter?(.only(.soundcloud)) }
        countLabel.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        countLabel.textColor = PLColor.fg3
        countLabel.isBezeled = false; countLabel.drawsBackground = false
        countLabel.isEditable = false; countLabel.alignment = .right
        [allPill, ytPill, scPill, countLabel].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(filter: OnlineSourceFilter, filteredOf: Int, total: Int) {
        allPill.set(active: filter == .all)
        ytPill.set(active: filter == .only(.youtube))
        scPill.set(active: filter == .only(.soundcloud))
        countLabel.stringValue = "\(filteredOf) OF \(total)"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 10
        let h = bounds.height
        for pill in [allPill, ytPill, scPill] {
            pill.sizeToFit()
            pill.frame = NSRect(x: x, y: (h - pill.bounds.height) / 2,
                                width: pill.bounds.width, height: pill.bounds.height)
            x += pill.bounds.width + 4
        }
        countLabel.sizeToFit()
        countLabel.frame = NSRect(x: bounds.width - countLabel.bounds.width - 10,
                                  y: (h - countLabel.bounds.height) / 2,
                                  width: countLabel.bounds.width,
                                  height: countLabel.bounds.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        PLColor.p3(1, 1, 1, 0.04).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: bounds.width, height: 1)).fill()
    }
}

private final class SourcePill: NSView {
    enum Kind { case all, yt, sc }
    let kind: Kind
    var onClick: (() -> Void)?
    private var active = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?
    private var hovered = false { didSet { needsDisplay = true } }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(active: Bool) { self.active = active }

    private var labelText: String {
        switch kind { case .all: return "All"; case .yt: return "YouTube"; case .sc: return "SoundCloud" }
    }
    private var glyphText: String? {
        switch kind { case .all: return nil; case .yt: return "YT"; case .sc: return "SC" }
    }

    func sizeToFit() {
        let lblAttr = textAttr()
        let labelSize = (labelText as NSString).size(withAttributes: lblAttr)
        var w = labelSize.width + 16
        if glyphText != nil { w += 14 + 5 }
        frame.size = NSSize(width: ceil(w), height: 16)
    }

    private func textAttr() -> [NSAttributedString.Key: Any] {
        let color: NSColor
        if active {
            switch kind {
            case .all: color = .white
            case .yt:  color = PLColor.p3(1, 0.85, 0.85)
            case .sc:  color = PLColor.p3(1, 0.92, 0.85)
            }
        } else {
            color = hovered ? PLColor.fg2 : PLColor.fg3
        }
        return [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: color,
                .kern: 1.0]
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInKeyWindow],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited (with e: NSEvent) { hovered = false }
    override func mouseDown   (with e: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let bg = NSBezierPath(roundedRect: r, xRadius: 9, yRadius: 9)
        let (fill, rim): (NSColor, NSColor) = {
            if !active {
                return (hovered ? PLColor.p3(1, 1, 1, 0.07) : PLColor.p3(1, 1, 1, 0.04),
                        PLColor.p3(1, 1, 1, 0.06))
            }
            switch kind {
            case .all: return (PLColor.p3(1, 1, 1, 0.10), PLColor.p3(1, 1, 1, 0.30))
            case .yt:  return (PLColor.ytRedBg,           PLColor.ytRedRim)
            case .sc:  return (PLColor.scOrangeBg,        PLColor.scOrangeRim)
            }
        }()
        fill.setFill(); bg.fill()
        rim.setStroke(); bg.lineWidth = 1; bg.stroke()

        var x: CGFloat = 6
        if let glyph = glyphText {
            let glyphRect = NSRect(x: x, y: (r.height - 12) / 2, width: 14, height: 12)
            let glyphBg = NSBezierPath(roundedRect: glyphRect, xRadius: 2, yRadius: 2)
            let (gFill, gColor): (NSColor, NSColor) = {
                if !active { return (PLColor.p3(1, 1, 1, 0.06), PLColor.fg3) }
                switch kind {
                case .yt: return (PLColor.ytRed, .white)
                case .sc: return (PLColor.scOrange, .white)
                default:  return (PLColor.fg3, .white)
                }
            }()
            gFill.setFill(); glyphBg.fill()
            let gAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 8, weight: .bold),
                .foregroundColor: gColor]
            let gStr = glyph as NSString
            let gSize = gStr.size(withAttributes: gAttr)
            gStr.draw(at: NSPoint(x: glyphRect.midX - gSize.width / 2,
                                  y: glyphRect.midY - gSize.height / 2),
                      withAttributes: gAttr)
            x += 14 + 5
        }

        let lblAttr = textAttr()
        let lblStr = labelText as NSString
        let lblSize = lblStr.size(withAttributes: lblAttr)
        lblStr.draw(at: NSPoint(x: x, y: (r.height - lblSize.height) / 2),
                    withAttributes: lblAttr)
    }
}

// MARK: - URL bar (ONLINE) ----------------------------------------------------

private final class URLBarView: NSView, NSTextFieldDelegate {
    enum State {
        case idle, validating, success, error(String)
    }

    var onAdd:      ((String) -> Void)?
    var onClearAll: (() -> Void)?

    private let field   = URLTextField()
    private let detector = NSTextField(labelWithString: "")
    private let addBtn  = AddButton()
    private let clearBtn = TrashButton()
    private let spinner = NSProgressIndicator()

    private var state: State = .idle
    private var clipboardHint: String? { detectClipboardURL() }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = PLColor.urlbarBg.cgColor

        field.placeholderAttributedString = NSAttributedString(string: "paste youtube or soundcloud url…",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                         .foregroundColor: PLColor.p3(0.50, 0.52, 0.58)])
        field.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        field.textColor = PLColor.fg2
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(submit)
        addSubview(field)

        addSubview(detector)
        styleDetector()

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)

        addBtn.onClick = { [weak self] in self?.submit() }
        addSubview(addBtn)
        clearBtn.onClick = { [weak self] in self?.onClearAll?() }
        addSubview(clearBtn)

        field.onFocusChange = { [weak self] in self?.updateButtonLabel() }
    }
    required init?(coder: NSCoder) { fatalError() }

    func setState(_ s: State) {
        self.state = s
        switch s {
        case .validating: spinner.startAnimation(nil)
        default:          spinner.stopAnimation(nil)
        }
        needsDisplay = true
        needsLayout = true
        updateDetector()
    }

    func clearText() { field.stringValue = ""; updateDetector(); updateButtonLabel() }

    @objc private func submit() {
        let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        // If empty + clipboard hint, paste-on-enter
        if raw.isEmpty, let hint = clipboardHint {
            field.stringValue = hint
            updateDetector()
            return
        }
        guard !raw.isEmpty else { return }
        onAdd?(raw)
    }

    public func controlTextDidChange(_ obj: Notification) {
        updateDetector()
        updateButtonLabel()
        if case .error = state { setState(.idle) }
        if case .success = state { setState(.idle) }
    }

    private func styleDetector() {
        detector.font = NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold)
        detector.textColor = .white
        detector.isBezeled = false
        detector.drawsBackground = true
        detector.alignment = .center
        detector.isEditable = false
        detector.alphaValue = 0
        detector.wantsLayer = true
        detector.layer?.cornerRadius = 2
    }

    private func updateDetector() {
        let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw.contains("://") ? raw : "https://\(raw)"),
              let src = MockOnlineSourceAdapter().detect(url: url) else {
            detector.alphaValue = 0
            return
        }
        detector.stringValue = " " + src.badge + " "
        detector.layer?.backgroundColor = (src == .youtube ? PLColor.ytRed : PLColor.scOrange).cgColor
        detector.alphaValue = (state.isValidating ? 0 : 1)
        needsLayout = true
    }

    private func updateButtonLabel() {
        let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            addBtn.title = "ADD ↵"
            setPlaceholderVisible(true)
        } else if field.currentEditor() != nil, clipboardHint != nil {
            addBtn.title = "SUBMIT ↵"
            setPlaceholderVisible(false)
        } else {
            addBtn.title = "ADD"
            setPlaceholderVisible(true)
        }
    }

    private func setPlaceholderVisible(_ visible: Bool) {
        if visible {
            field.placeholderAttributedString = NSAttributedString(
                string: "paste youtube or soundcloud url…",
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                             .foregroundColor: PLColor.p3(0.50, 0.52, 0.58)])
        } else {
            field.placeholderAttributedString = nil
        }
    }

    private func detectClipboardURL() -> String? {
        let pb = NSPasteboard.general
        guard let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty,
              let url = URL(string: s.contains("://") ? s : "https://\(s)"),
              MockOnlineSourceAdapter().detect(url: url) != nil
        else { return nil }
        return s
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        let fieldH: CGFloat = 22

        clearBtn.frame = NSRect(x: bounds.width - 10 - 22, y: (h - 22) / 2, width: 22, height: 22)
        addBtn.sizeToFit()
        addBtn.frame = NSRect(x: clearBtn.frame.minX - 6 - addBtn.bounds.width,
                              y: (h - 22) / 2, width: addBtn.bounds.width, height: 22)

        let fieldRect = NSRect(x: 10, y: (h - fieldH) / 2,
                               width: addBtn.frame.minX - 6 - 10,
                               height: fieldH)
        // The drawn input box is fieldRect; the editable text inset by 8.
        // We position the NSTextField inset.
        var textInsetX: CGFloat = 10
        if state.isValidating {
            spinner.frame = NSRect(x: fieldRect.minX + 8, y: (h - 12) / 2, width: 12, height: 12)
            textInsetX = 24
        } else {
            spinner.frame = .zero
        }

        // Detector pill inside the field, right side
        if detector.alphaValue > 0 {
            detector.sizeToFit()
            let dW = detector.bounds.width + 4
            let dRect = NSRect(x: fieldRect.maxX - dW - 6, y: (h - 14) / 2, width: dW, height: 14)
            detector.frame = dRect
            field.frame = NSRect(x: fieldRect.minX + textInsetX, y: fieldRect.minY,
                                 width: dRect.minX - fieldRect.minX - textInsetX - 4,
                                 height: fieldH)
        } else {
            detector.frame = .zero
            field.frame = NSRect(x: fieldRect.minX + textInsetX, y: fieldRect.minY,
                                 width: fieldRect.maxX - fieldRect.minX - textInsetX - 6,
                                 height: fieldH)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Draw the recessed input box ourselves (NSTextField is borderless, transparent).
        let h = bounds.height
        let fieldH: CGFloat = 22
        let fieldRect = NSRect(x: 10, y: (h - fieldH) / 2,
                               width: bounds.width - 10 - 6 - 22 - 6 - addBtn.bounds.width - 10,
                               height: fieldH)
        let path = NSBezierPath(roundedRect: fieldRect, xRadius: 4, yRadius: 4)
        PLColor.inputBg.setFill(); path.fill()

        // Rim — green when success, red when error, dark otherwise.
        let rim: NSColor = {
            switch state {
            case .success:    return PLColor.p3(0.13, 0.85, 0.47, 0.55)
            case .error:      return PLColor.p3(1, 0.30, 0.25, 0.65)
            default:          return PLColor.p3(0, 0, 0, 0.7)
            }
        }()
        rim.setStroke(); path.lineWidth = 1; path.stroke()

        // Top hairline of the bar
        PLColor.p3(1, 1, 1, 0.04).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.maxY - 1,
                                  width: bounds.width, height: 1)).fill()

        // Empty + focused + clipboard URL → ghost hint.
        if field.stringValue.isEmpty,
           field.currentEditor() != nil,
           let hint = clipboardHint {
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
                       .withTraits(italic: true),
                .foregroundColor: PLColor.p3(0.45, 0.50, 0.58, 0.85),
            ]
            let display = hint as NSString
            let textH = display.size(withAttributes: attr).height
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState()
                ctx.clip(to: fieldRect.insetBy(dx: 6, dy: 0))
                display.draw(at: NSPoint(x: fieldRect.minX + 10,
                                         y: fieldRect.minY + (fieldH - textH) / 2),
                             withAttributes: attr)
                ctx.restoreGState()
            }
        }
    }
}

private extension URLBarView.State {
    var isValidating: Bool { if case .validating = self { return true } else { return false } }
}

// Helper: italic monospaced font
private extension NSFont {
    func withTraits(italic: Bool) -> NSFont {
        guard italic else { return self }
        let desc = fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: pointSize) ?? self
    }
}

private final class CenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let s = super.drawingRect(forBounds: rect)
        let textH = cellSize(forBounds: rect).height
        let y = s.minY + max(0, (s.height - textH) / 2)
        return NSRect(x: s.minX, y: y, width: s.width, height: textH)
    }
    override func edit(withFrame rect: NSRect, in controlView: NSView,
                       editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView,
                   editor: textObj, delegate: delegate, event: event)
    }
    override func select(withFrame rect: NSRect, in controlView: NSView,
                         editor textObj: NSText, delegate: Any?,
                         start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView,
                     editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

private final class URLTextField: NSTextField {
    var onFocusChange: (() -> Void)?
    override class var cellClass: AnyClass? {
        get { CenteredTextFieldCell.self }
        set { _ = newValue }
    }
    override func becomeFirstResponder() -> Bool {
        let r = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = PLColor.fg2
        }
        superview?.needsDisplay = true
        onFocusChange?()
        return r
    }
    override func resignFirstResponder() -> Bool {
        let r = super.resignFirstResponder()
        superview?.needsDisplay = true
        onFocusChange?()
        return r
    }
}

private final class AddButton: NSView {
    var onClick: (() -> Void)?
    var title: String = "ADD" { didSet { sizeToFit(); needsDisplay = true; superview?.needsLayout = true } }
    private var hovered = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func sizeToFit() {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .kern: 1.6]
        let w = (title as NSString).size(withAttributes: attr).width
        frame.size = NSSize(width: ceil(w) + 20, height: 22)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInKeyWindow],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited (with e: NSEvent) { hovered = false; pressed = false }
    override func mouseDown   (with e: NSEvent) { pressed = true }
    override func mouseUp     (with e: NSEvent) {
        let was = pressed; pressed = false
        if was, bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() }
    }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
        let cs: CFArray
        if pressed {
            cs = [PLColor.p3(0.08, 0.25, 0.55).cgColor,
                  PLColor.p3(0.06, 0.18, 0.45).cgColor] as CFArray
        } else if hovered {
            cs = [PLColor.p3(0.20, 0.55, 0.95, 0.95).cgColor,
                  PLColor.p3(0.12, 0.35, 0.70).cgColor] as CFArray
        } else {
            cs = [PLColor.addBlueTop.cgColor,
                  PLColor.addBlueBot.cgColor] as CFArray
        }
        if let ctx = NSGraphicsContext.current?.cgContext,
           let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                              colors: cs, locations: [0, 1]) {
            ctx.saveGState(); path.addClip()
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: r.maxY),
                                   end: CGPoint(x: 0, y: 0), options: [])
            ctx.restoreGState()
        }
        PLColor.p3(1, 1, 1, 0.30).setStroke(); path.lineWidth = 1; path.stroke()

        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white,
            .kern: 1.6,
        ]
        let s = title as NSString
        let size = s.size(withAttributes: attr)
        s.draw(at: NSPoint(x: (r.width - size.width) / 2,
                           y: (r.height - size.height) / 2),
               withAttributes: attr)
    }
}

private final class TrashButton: NSView {
    var onClick: (() -> Void)?
    private var hovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInKeyWindow],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited (with e: NSEvent) { hovered = false }
    override func mouseDown   (with e: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let bg = NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3)
        (hovered ? PLColor.dangerBg : PLColor.ghostBg).setFill(); bg.fill()
        PLColor.p3(1, 1, 1, 0.06).setStroke(); bg.lineWidth = 1; bg.stroke()

        // Trash glyph
        let color: NSColor = hovered ? PLColor.danger : PLColor.fg3
        color.setStroke(); color.setFill()
        let lid = NSBezierPath()
        lid.move(to: NSPoint(x: r.midX - 5, y: r.midY + 4))
        lid.line(to: NSPoint(x: r.midX + 5, y: r.midY + 4))
        lid.lineWidth = 1.1; lid.stroke()
        let body = NSBezierPath(rect: NSRect(x: r.midX - 4, y: r.midY - 5, width: 8, height: 9))
        body.lineWidth = 1.1; body.stroke()
        let handle = NSBezierPath()
        handle.move(to: NSPoint(x: r.midX - 1.5, y: r.midY + 5.5))
        handle.line(to: NSPoint(x: r.midX + 1.5, y: r.midY + 5.5))
        handle.lineWidth = 1.5; handle.stroke()
    }
}

// MARK: - LOCAL rows (unchanged behaviour, renamed) ---------------------------

fileprivate final class LocalRowsView: NSView {
    var tracks: [PlaylistTrack] = []
    var currentIndex: Int = -1
    var onTrackSelected: ((Int) -> Void)?

    private let rowH: CGFloat = 24
    private let listPadV: CGFloat = 4
    private var hoverIndex: Int = -1
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

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
        if isActive {
            let inset = NSRect(x: rect.minX + 4, y: rect.minY + 1,
                               width: rect.width - 8, height: rect.height - 2)
            let p = NSBezierPath(roundedRect: inset, xRadius: 3, yRadius: 3)
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState(); p.addClip()
                let cs = [PLColor.selectionBlue.cgColor, PLColor.selectionBlueD.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                                      colors: cs, locations: [0, 1]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: inset.maxY),
                                           end: CGPoint(x: 0, y: inset.minY), options: [])
                }
                ctx.restoreGState()
            }
        } else if isHover {
            PLColor.hover.setFill(); NSBezierPath(rect: rect).fill()
        }
        if !isActive {
            PLColor.rowBorder.setFill()
            NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - 1,
                                      width: rect.width, height: 1)).fill()
        }
        let mainColor: NSColor
        let dimColor:  NSColor
        if isActive { mainColor = .white; dimColor = NSColor.white.withAlphaComponent(0.9) }
        else if isMissing { mainColor = PLColor.missing; dimColor = PLColor.missing }
        else { mainColor = PLColor.fg2; dimColor = PLColor.fg3 }

        let monoFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let textFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        var idxAttr: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: dimColor]
        var titleAttr: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: mainColor]
        var timeAttr: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: dimColor]
        if isMissing {
            idxAttr[.strikethroughStyle]   = NSUnderlineStyle.single.rawValue
            titleAttr[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            timeAttr[.strikethroughStyle]  = NSUnderlineStyle.single.rawValue
            idxAttr[.strikethroughColor]   = PLColor.missing
            titleAttr[.strikethroughColor] = PLColor.missing
            timeAttr[.strikethroughColor]  = PLColor.missing
        }
        let padL: CGFloat = 12, padR: CGFloat = 12, idxColW: CGFloat = 28
        let idxStr = String(format: "%02d.", i + 1) as NSString
        let idxSize = idxStr.size(withAttributes: idxAttr)
        idxStr.draw(at: NSPoint(x: rect.minX + padL,
                                y: rect.minY + (rect.height - idxSize.height) / 2),
                    withAttributes: idxAttr)
        let displayTime = isMissing ? "−:−−" : track.durationString
        let timeStr = displayTime as NSString
        let timeSize = timeStr.size(withAttributes: timeAttr)
        let timeX = rect.maxX - padR - timeSize.width
        timeStr.draw(at: NSPoint(x: timeX,
                                 y: rect.minY + (rect.height - timeSize.height) / 2),
                     withAttributes: timeAttr)
        let titleX = rect.minX + padL + idxColW
        let titleAvailW = max(0, timeX - 8 - titleX)
        var titleText = track.title
        if isMissing && !titleText.lowercased().contains("missing") { titleText += " (missing)" }
        let drawnTitle = truncate(titleText, attrs: titleAttr, maxWidth: titleAvailW)
        let titleStr = drawnTitle as NSString
        let titleSize = titleStr.size(withAttributes: titleAttr)
        titleStr.draw(in: NSRect(x: titleX,
                                 y: rect.minY + (rect.height - titleSize.height) / 2,
                                 width: titleAvailW, height: titleSize.height),
                      withAttributes: titleAttr)
    }
    private func truncate(_ s: String, attrs: [NSAttributedString.Key: Any],
                          maxWidth: CGFloat) -> String {
        let ns = s as NSString
        if ns.size(withAttributes: attrs).width <= maxWidth { return s }
        var lo = 0, hi = ns.length
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = ns.substring(to: mid) + "…"
            let w = (candidate as NSString).size(withAttributes: attrs).width
            if w <= maxWidth { lo = mid } else { hi = mid - 1 }
        }
        return ns.substring(to: lo) + "…"
    }
}

// MARK: - ONLINE rows ---------------------------------------------------------

fileprivate final class OnlineRowsView: NSView {
    /// Filtered snapshot from the queue: original index + track. We render
    /// using these indices so play/remove callbacks reference real positions.
    var snapshot: [(index: Int, track: OnlineTrack)] = []
    var currentIndex: Int = -1
    var onPlay:   ((Int) -> Void)?
    var onRemove: ((Int) -> Void)?

    private let rowH: CGFloat = 24
    private let listPadV: CGFloat = 4
    private var hoverRow: Int = -1
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .mouseMoved,
                                         .activeInKeyWindow, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }

    private func snapshotRowAt(_ p: NSPoint) -> Int {
        guard p.y >= listPadV else { return -1 }
        let i = Int((p.y - listPadV) / rowH)
        return (i >= 0 && i < snapshot.count) ? i : -1
    }
    private func removeHitAt(_ p: NSPoint, forSnapshotRow row: Int) -> Bool {
        let y = listPadV + CGFloat(row) * rowH
        let removeRect = NSRect(x: bounds.width - 26, y: y + 4, width: 16, height: 16)
        return removeRect.contains(p)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let r = snapshotRowAt(p)
        if r != hoverRow { hoverRow = r; needsDisplay = true }
    }
    override func mouseExited(with event: NSEvent) {
        if hoverRow != -1 { hoverRow = -1; needsDisplay = true }
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let row = snapshotRowAt(p)
        guard row >= 0 else { return }
        let real = snapshot[row].index
        if removeHitAt(p, forSnapshotRow: row) { onRemove?(real) }
        else                                   { onPlay?(real) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        if snapshot.isEmpty {
            drawEmptyState(width: w)
            return
        }
        for (row, item) in snapshot.enumerated() {
            let y = listPadV + CGFloat(row) * rowH
            drawRow(item: item, snapshotRow: row,
                    rect: NSRect(x: 0, y: y, width: w, height: rowH))
        }
    }

    private func drawEmptyState(width: CGFloat) {
        let cx = width / 2
        let cy = bounds.height / 2 - 10
        // Disc glyph
        let circle = NSBezierPath(ovalIn: NSRect(x: cx - 21, y: cy - 21, width: 42, height: 42))
        PLColor.p3(1, 1, 1, 0.20).setStroke()
        circle.lineWidth = 1; circle.stroke()
        let tri = NSBezierPath()
        tri.move(to: NSPoint(x: cx - 5, y: cy - 5))
        tri.line(to: NSPoint(x: cx + 7, y: cy))
        tri.line(to: NSPoint(x: cx - 5, y: cy + 5))
        tri.close()
        PLColor.p3(1, 1, 1, 0.30).setFill(); tri.fill()

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: PLColor.fg2,
            .kern: 1.5,
        ]
        let title = "ONLINE QUEUE IS EMPTY" as NSString
        let titleSize = title.size(withAttributes: titleAttr)
        title.draw(at: NSPoint(x: cx - titleSize.width / 2, y: cy + 30),
                   withAttributes: titleAttr)

        let hintAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: PLColor.fg3,
        ]
        let hint = "Paste a YouTube or SoundCloud URL above and press ↵." as NSString
        let hintSize = hint.size(withAttributes: hintAttr)
        hint.draw(at: NSPoint(x: cx - hintSize.width / 2, y: cy + 50),
                  withAttributes: hintAttr)
    }

    private func drawRow(item: (index: Int, track: OnlineTrack),
                         snapshotRow: Int, rect: NSRect) {
        let track = item.track
        let isActive = (item.index == currentIndex)
        let isHover  = (snapshotRow == hoverRow && !isActive)

        // Background
        if isActive {
            let inset = NSRect(x: rect.minX + 4, y: rect.minY + 1,
                               width: rect.width - 8, height: rect.height - 2)
            let p = NSBezierPath(roundedRect: inset, xRadius: 3, yRadius: 3)
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.saveGState(); p.addClip()
                let cs = [PLColor.selectionBlue.cgColor, PLColor.selectionBlueD.cgColor] as CFArray
                if let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.displayP3)!,
                                      colors: cs, locations: [0, 1]) {
                    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: inset.maxY),
                                           end: CGPoint(x: 0, y: inset.minY), options: [])
                }
                ctx.restoreGState()
            }
        } else if isHover {
            PLColor.hover.setFill(); NSBezierPath(rect: rect).fill()
        }
        if !isActive {
            PLColor.rowBorder.setFill()
            NSBezierPath(rect: NSRect(x: rect.minX, y: rect.maxY - 1,
                                      width: rect.width, height: 1)).fill()
        }

        let mainColor:  NSColor = isActive ? .white : PLColor.fg2
        let dimColor:   NSColor = isActive ? NSColor.white.withAlphaComponent(0.9) : PLColor.fg3

        var x = rect.minX + 8
        // idx
        let idxAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: dimColor]
        let idxStr = String(format: "%02d", item.index + 1) as NSString
        let idxSize = idxStr.size(withAttributes: idxAttr)
        idxStr.draw(at: NSPoint(x: x, y: rect.minY + (rect.height - idxSize.height) / 2),
                    withAttributes: idxAttr)
        x += 22 + 6

        // Source badge
        let badgeRect = NSRect(x: x, y: rect.minY + (rect.height - 14) / 2,
                               width: 22, height: 14)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 2, yRadius: 2)
        (track.source == .youtube ? PLColor.ytRed : PLColor.scOrange).setFill()
        badgePath.fill()
        PLColor.p3(0, 0, 0, 0.4).setStroke(); badgePath.lineWidth = 1; badgePath.stroke()
        let badgeAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold),
            .foregroundColor: NSColor.white, .kern: 0.5]
        let badgeStr = track.source.badge as NSString
        let badgeSize = badgeStr.size(withAttributes: badgeAttr)
        badgeStr.draw(at: NSPoint(x: badgeRect.midX - badgeSize.width / 2,
                                  y: badgeRect.midY - badgeSize.height / 2),
                      withAttributes: badgeAttr)
        x += 22 + 8

        // Time / LIVE — drawn first so we can clip the title
        let timeRightX = rect.maxX - 26 - 6
        if track.isLive {
            let liveAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: isActive ? NSColor.white : PLColor.live,
                .kern: 0.8]
            let liveStr = "LIVE" as NSString
            let lSize = liveStr.size(withAttributes: liveAttr)
            // dot
            let dotRect = NSRect(x: timeRightX - lSize.width - 8,
                                 y: rect.midY - 2.5, width: 5, height: 5)
            PLColor.live.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            liveStr.draw(at: NSPoint(x: timeRightX - lSize.width,
                                     y: rect.minY + (rect.height - lSize.height) / 2),
                         withAttributes: liveAttr)
        } else {
            let timeAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: dimColor]
            let timeStr = track.durationString as NSString
            let tSize = timeStr.size(withAttributes: timeAttr)
            timeStr.draw(at: NSPoint(x: timeRightX - tSize.width,
                                     y: rect.minY + (rect.height - tSize.height) / 2),
                         withAttributes: timeAttr)
        }

        // Title (between badge and time area, with right padding so × can sit there)
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: mainColor]
        let timeWidthGuess: CGFloat = track.isLive ? 50 : 36
        let titleAvailW = max(0, timeRightX - timeWidthGuess - 8 - x)
        let titleStr = truncate(track.title, attrs: titleAttr, maxWidth: titleAvailW) as NSString
        let titleSize = titleStr.size(withAttributes: titleAttr)
        titleStr.draw(at: NSPoint(x: x, y: rect.minY + (rect.height - titleSize.height) / 2),
                      withAttributes: titleAttr)

        // Remove × — hover or active reveals
        if isHover || isActive {
            let removeRect = NSRect(x: rect.maxX - 26, y: rect.minY + 4, width: 16, height: 16)
            let bg = NSBezierPath(roundedRect: removeRect, xRadius: 3, yRadius: 3)
            (isActive ? PLColor.p3(1, 1, 1, 0.15) : PLColor.p3(1, 1, 1, 0.08)).setFill()
            bg.fill()
            let xAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: isActive ? NSColor.white : PLColor.fg2]
            let xStr = "×" as NSString
            let xSize = xStr.size(withAttributes: xAttr)
            xStr.draw(at: NSPoint(x: removeRect.midX - xSize.width / 2,
                                  y: removeRect.midY - xSize.height / 2),
                      withAttributes: xAttr)
        }
    }

    private func truncate(_ s: String, attrs: [NSAttributedString.Key: Any],
                          maxWidth: CGFloat) -> String {
        let ns = s as NSString
        if ns.size(withAttributes: attrs).width <= maxWidth { return s }
        var lo = 0, hi = ns.length
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = ns.substring(to: mid) + "…"
            let w = (candidate as NSString).size(withAttributes: attrs).width
            if w <= maxWidth { lo = mid } else { hi = mid - 1 }
        }
        return ns.substring(to: lo) + "…"
    }
}

// MARK: - Statusbar -----------------------------------------------------------

private final class StatusbarView: NSView {
    private let left  = NSTextField(labelWithString: "")
    private let right = NSTextField(labelWithString: "")
    private let clearBtn = TextButton(label: "CLEAR")

    var onClearAll: (() -> Void)?
    private var showClear = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = PLColor.statusbarBg.cgColor
        for tf in [left, right] {
            tf.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
            tf.textColor = PLColor.fg3
            tf.isBezeled = false; tf.drawsBackground = false; tf.isEditable = false
        }
        addSubview(left); addSubview(right)
        clearBtn.onClick = { [weak self] in self?.onClearAll?() }
        clearBtn.color = PLColor.danger
        clearBtn.hoverBg = PLColor.dangerBg
        addSubview(clearBtn)
    }
    required init?(coder: NSCoder) { fatalError() }

    func updateLocal(trackCount: Int, missingCount: Int, totalSeconds: TimeInterval) {
        showClear = false
        clearBtn.isHidden = true
        left.attributedStringValue = NSAttributedString(
            string: "\(trackCount) TRACK\(trackCount == 1 ? "" : "S") · \(missingCount) MISSING",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
                         .foregroundColor: PLColor.fg3, .kern: 0.8])
        let total = Int(totalSeconds.rounded())
        right.stringValue = String(format: "%d:%02d", total / 60, total % 60)
        needsLayout = true; needsDisplay = true
    }

    func updateOnline(trackCount: Int, ytCount: Int, scCount: Int,
                      liveCount: Int, totalSeconds: TimeInterval) {
        showClear = trackCount > 0
        clearBtn.isHidden = !showClear

        let baseAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: PLColor.fg3, .kern: 0.8]
        let result = NSMutableAttributedString(
            string: "\(trackCount) TRACK\(trackCount == 1 ? "" : "S")  ",
            attributes: baseAttr)
        result.append(NSAttributedString(string: "YT \(ytCount) ",
            attributes: [.font: baseAttr[.font]!,
                         .foregroundColor: PLColor.p3(1, 0.55, 0.50), .kern: 0.4]))
        result.append(NSAttributedString(string: "SC \(scCount)",
            attributes: [.font: baseAttr[.font]!,
                         .foregroundColor: PLColor.p3(1, 0.70, 0.45), .kern: 0.4]))
        if liveCount > 0 {
            result.append(NSAttributedString(string: "  ● \(liveCount) LIVE",
                attributes: [.font: baseAttr[.font]!,
                             .foregroundColor: PLColor.live, .kern: 0.8]))
        }
        left.attributedStringValue = result
        let total = Int(totalSeconds.rounded())
        right.stringValue = String(format: "%d:%02d", total / 60, total % 60)
        needsLayout = true; needsDisplay = true
    }

    override func layout() {
        super.layout()
        left.sizeToFit()
        left.frame.origin = NSPoint(x: 10, y: (bounds.height - left.bounds.height) / 2)

        // Right side: [time]   [CLEAR]?
        var rightX = bounds.width - 10
        if showClear {
            clearBtn.sizeToFit()
            clearBtn.frame = NSRect(x: rightX - clearBtn.bounds.width,
                                    y: (bounds.height - clearBtn.bounds.height) / 2,
                                    width: clearBtn.bounds.width, height: clearBtn.bounds.height)
            rightX -= clearBtn.bounds.width + 8
        }
        right.sizeToFit()
        right.frame = NSRect(x: rightX - right.bounds.width,
                             y: (bounds.height - right.bounds.height) / 2,
                             width: right.bounds.width, height: right.bounds.height)
    }
    override func draw(_ dirtyRect: NSRect) {
        PLColor.p3(1, 1, 1, 0.04).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: bounds.maxY - 1,
                                  width: bounds.width, height: 1)).fill()
    }
}

private final class TextButton: NSView {
    let label: String
    var color: NSColor = PLColor.fg3 { didSet { needsDisplay = true } }
    var hoverBg: NSColor = PLColor.ghostBgHover
    var onClick: (() -> Void)?
    private var hovered = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(label: String) { self.label = label; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }

    func sizeToFit() {
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .kern: 1.0]
        let s = (label as NSString).size(withAttributes: attr)
        frame.size = NSSize(width: ceil(s.width) + 10, height: 12)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds,
                               options: [.mouseEnteredAndExited, .activeInKeyWindow],
                               owner: self, userInfo: nil)
        addTrackingArea(t); trackingArea = t
    }
    override func mouseEntered(with e: NSEvent) { hovered = true }
    override func mouseExited (with e: NSEvent) { hovered = false }
    override func mouseDown   (with e: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        if hovered {
            let p = NSBezierPath(roundedRect: bounds, xRadius: 2, yRadius: 2)
            hoverBg.setFill(); p.fill()
        }
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: color, .kern: 1.0]
        let s = label as NSString
        let size = s.size(withAttributes: attr)
        s.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                           y: (bounds.height - size.height) / 2),
               withAttributes: attr)
    }
}
