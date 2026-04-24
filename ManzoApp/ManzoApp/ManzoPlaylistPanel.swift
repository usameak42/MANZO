import AppKit

// ManzoPlaylistPanel — the Playlist Editor floating panel (D-01).
// Separate NSPanel from the main ManzoWindow: 275pt fixed width, vertically resizable.
// Root contentView is a single .behindWindow vibrancy view — all inner panels are plain NSView.
// All inner panels (titleView, bodyView, toolbarView) are plain NSView with wantsLayer=true.
// NeoAero chrome applied via NeoAeroLayerFactory in bodyFocus mode (D-05).

private let kPanelWidth:       CGFloat = 275   // Winamp config_pe_width (CONTEXT.md D-01)
private let kPanelInitHeight:  CGFloat = 116   // Winamp config_pe_height (CONTEXT.md D-01)
private let kPanelMinHeight:   CGFloat = 60    // UI-SPEC: minimum usable height
private let kPLTitleBarHeight: CGFloat = 16    // UI-SPEC: titleView height (16pt strip)
private let kPLToolbarHeight:  CGFloat = 16    // UI-SPEC: toolbarView height (16pt strip)

final class ManzoPlaylistPanel: NSPanel {

    // MARK: - Structural Views
    let titleView   = NSView()
    let bodyView    = NSView()
    let toolbarView = NSView()

    // MARK: - NSTableView
    let tableView  = NSTableView()
    let scrollView = NSScrollView()

    // MARK: - Toolbar Controls
    let addButton:      NSButton
    let removeButton:   NSButton
    let trackCountLabel: NSTextField

    // MARK: - Empty State
    private let emptyStateContainer = NSView()

    // MARK: - Delegate (set by AppDelegate in Plan 08-03)
    weak var delegate: ManzoPlaylistPanelDelegate? = nil

    // MARK: - canBecomeKey / canBecomeMain

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Init

    init() {
        // Build toolbar controls before super.init (stored properties).
        addButton    = ManzoPlaylistPanel.makeToolbarButton(label: "+", tooltip: "Add Files\u{2026}")
        removeButton = ManzoPlaylistPanel.makeToolbarButton(label: "\u{2212}", tooltip: "Remove Selected Track")
        trackCountLabel = ManzoPlaylistPanel.makeTrackCountLabel()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: kPanelWidth, height: kPanelInitHeight),
            styleMask:   [.nonactivatingPanel, .resizable],
            backing:     .buffered,
            defer:       false
        )

        // D-04 (Phase 5 pattern): set before orderFront — compositor requirement.
        isOpaque        = false
        backgroundColor = .clear
        hasShadow         = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Lock width to 275 pt; height freely resizable (D-04).
        minSize = NSSize(width: kPanelWidth, height: kPanelMinHeight)
        maxSize = NSSize(width: kPanelWidth, height: CGFloat.greatestFiniteMagnitude)

        // Corner radius 10 pt (UI-SPEC: matches main window).
        contentView?.wantsLayer = true
        contentView?.layer?.cornerRadius = 10
        contentView?.layer?.masksToBounds = true

        setupContentView()
        setupTableView()
        setupEmptyState()
        setupToolbar()
        applyNeoAeroChrome()

        // Initial state: show empty state (no tracks yet — AppDelegate wires data in 08-03).
        setEmptyStateVisible(true)

        NSLog("MANZO Phase 8: ManzoPlaylistPanel.init — 275×116pt panel, vertically resizable")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }

    // MARK: - Content View (single .behindWindow vibrancy root)

    private func setupContentView() {
        // Single root vibrancy view — inner panels are plain NSView only (CLAUDE.md: no nested vibrancy).
        let root = NSVisualEffectView()
        root.material     = .hudWindow   // TBD: replace with confirmed .glass when macOS 26 SDK name confirmed
        root.blendingMode = .behindWindow
        root.state        = .active
        root.wantsLayer   = true
        root.layer?.cornerRadius = 10
        root.layer?.masksToBounds = true
        contentView = root

        for panel in [titleView, bodyView, toolbarView] {
            panel.translatesAutoresizingMaskIntoConstraints = false
            panel.wantsLayer = true
            root.addSubview(panel)
        }

        NSLayoutConstraint.activate([
            // titleView — top 16 pt strip (UI-SPEC Panel Layout)
            titleView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            titleView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            titleView.topAnchor.constraint(equalTo: root.topAnchor),
            titleView.heightAnchor.constraint(equalToConstant: kPLTitleBarHeight),

            // toolbarView — bottom 16 pt strip (UI-SPEC Panel Layout)
            toolbarView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbarView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: kPLToolbarHeight),

            // bodyView — fills between title and toolbar (UI-SPEC Panel Layout)
            bodyView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            bodyView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            bodyView.topAnchor.constraint(equalTo: titleView.bottomAnchor),
            bodyView.bottomAnchor.constraint(equalTo: toolbarView.topAnchor),
        ])

        addTitleLabel(to: titleView)

        NSLog("MANZO Phase 8: ManzoPlaylistPanel.setupContentView — titleView/bodyView/toolbarView constrained")
    }

    private func addTitleLabel(to view: NSView) {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let label = NSTextField(labelWithString: "PLAYLIST EDITOR")
        label.font          = NSFont.systemFont(ofSize: 11)
        label.textColor     = NSColor(cgColor: CGColor(colorSpace: p3, components: [0.58, 0.60, 0.65, 1.0])!)!
        label.alignment     = .center
        label.isBezeled     = false
        label.isEditable    = false
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    // titleView drag — mouseDown on titleView delegates to panel performDrag.
    override func mouseDown(with event: NSEvent) {
        let locInContent = contentView!.convert(event.locationInWindow, from: nil)
        let titleFrame   = titleView.frame
        if titleFrame.contains(locInContent) {
            performDrag(with: event)
        } else {
            super.mouseDown(with: event)
        }
    }

    // MARK: - NSTableView Setup

    private func setupTableView() {
        // NSScrollView pinned to all 4 bodyView edges (PATTERNS.md NSScrollView pattern).
        scrollView.documentView          = tableView
        scrollView.hasVerticalScroller   = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground       = false
        scrollView.backgroundColor       = .clear
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: bodyView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: bodyView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: bodyView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bodyView.bottomAnchor),
        ])

        // NSTableView configuration (UI-SPEC NSTableView section).
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TrackColumn"))
        column.width = kPanelWidth - 16  // 8 pt inset each side
        tableView.addTableColumn(column)

        tableView.headerView              = nil             // no column header (Winamp aesthetic)
        tableView.rowHeight               = 18              // Winamp canonical row height (UI-SPEC)
        tableView.backgroundColor         = .clear
        tableView.selectionHighlightStyle = .none           // custom selection via ManzoPlaylistRowBackground
        tableView.gridStyleMask           = []              // disable system grid; PlaylistRowView draws separator
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection    = true
        tableView.intercellSpacing        = NSSize(width: 0, height: 0)
        tableView.usesAlternatingRowBackgroundColors = false

        // Double-click to jump to track (D-14) — target set; AppDelegate becomes delegate in 08-03.
        tableView.doubleAction = #selector(handleDoubleClick(_:))
        tableView.target = self

        NSLog("MANZO Phase 8: ManzoPlaylistPanel.setupTableView — NSTableView 18pt rows, no header")
    }

    // MARK: - Empty State (UI-SPEC Empty State section)

    private func setupEmptyState() {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

        emptyStateContainer.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.wantsLayer = true
        bodyView.addSubview(emptyStateContainer)

        NSLayoutConstraint.activate([
            emptyStateContainer.centerXAnchor.constraint(equalTo: bodyView.centerXAnchor),
            emptyStateContainer.centerYAnchor.constraint(equalTo: bodyView.centerYAnchor),
            emptyStateContainer.widthAnchor.constraint(equalTo: bodyView.widthAnchor, constant: -32),
        ])

        // Line 1: "No tracks" — 13 pt regular, P3(0.78, 0.80, 0.85, 0.70)
        let headingLabel = NSTextField(labelWithString: "No tracks")
        headingLabel.font       = NSFont.systemFont(ofSize: 13)
        headingLabel.textColor  = NSColor(cgColor: CGColor(colorSpace: p3, components: [0.78, 0.80, 0.85, 0.70])!)!
        headingLabel.alignment  = .center
        headingLabel.isBezeled  = false
        headingLabel.isEditable = false
        headingLabel.backgroundColor = .clear
        headingLabel.drawsBackground = false
        headingLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.addSubview(headingLabel)

        // Line 2: "Add tracks with + or drag files here." — 11 pt regular, P3(0.78, 0.80, 0.85, 0.45)
        let bodyLabel = NSTextField(labelWithString: "Add tracks with + or drag files here.")
        bodyLabel.font       = NSFont.systemFont(ofSize: 11)
        bodyLabel.textColor  = NSColor(cgColor: CGColor(colorSpace: p3, components: [0.78, 0.80, 0.85, 0.45])!)!
        bodyLabel.alignment  = .center
        bodyLabel.isBezeled  = false
        bodyLabel.isEditable = false
        bodyLabel.backgroundColor = .clear
        bodyLabel.drawsBackground = false
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateContainer.addSubview(bodyLabel)

        NSLayoutConstraint.activate([
            headingLabel.leadingAnchor.constraint(equalTo: emptyStateContainer.leadingAnchor),
            headingLabel.trailingAnchor.constraint(equalTo: emptyStateContainer.trailingAnchor),
            headingLabel.topAnchor.constraint(equalTo: emptyStateContainer.topAnchor),

            bodyLabel.leadingAnchor.constraint(equalTo: emptyStateContainer.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: emptyStateContainer.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: headingLabel.bottomAnchor, constant: 4),
            bodyLabel.bottomAnchor.constraint(equalTo: emptyStateContainer.bottomAnchor),
        ])
    }

    // MARK: - Toolbar Setup (D-16)

    private func setupToolbar() {
        addButton.target    = self
        addButton.action    = #selector(addButtonClicked(_:))
        removeButton.target = self
        removeButton.action = #selector(removeButtonClicked(_:))

        addButton.translatesAutoresizingMaskIntoConstraints     = false
        removeButton.translatesAutoresizingMaskIntoConstraints  = false
        trackCountLabel.translatesAutoresizingMaskIntoConstraints = false

        toolbarView.addSubview(addButton)
        toolbarView.addSubview(removeButton)
        toolbarView.addSubview(trackCountLabel)

        NSLayoutConstraint.activate([
            // [+] button: 8 pt left inset, 24×16 pt (UI-SPEC toolbarView)
            addButton.leadingAnchor.constraint(equalTo: toolbarView.leadingAnchor, constant: 8),
            addButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            addButton.widthAnchor.constraint(equalToConstant: 24),
            addButton.heightAnchor.constraint(equalToConstant: 16),

            // [−] button: 4 pt gap after [+] (UI-SPEC toolbarView)
            removeButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 4),
            removeButton.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 24),
            removeButton.heightAnchor.constraint(equalToConstant: 16),

            // Track count label: 8 pt right inset, right-aligned (UI-SPEC toolbarView)
            trackCountLabel.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -8),
            trackCountLabel.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor),
        ])

        NSLog("MANZO Phase 8: ManzoPlaylistPanel.setupToolbar — [+]/[\u{2212}] buttons wired")
    }

    // MARK: - NeoAero Chrome (D-05, bodyFocus style)

    func applyNeoAeroChrome() {
        let style = ManzoVisualStyle.load()

        // Remove old layers first (applyStyle pattern from ManzoRootView).
        removeNeoAeroLayers(from: bodyView.layer)
        removeNeoAeroLayers(from: titleView.layer)
        removeNeoAeroLayers(from: toolbarView.layer)

        // bodyFocus: full 5-layer chrome on bodyView; simplified base+rim on title/toolbar (D-05).
        // Bounds may be zero at init time — layers resize correctly on first layout via
        // NeoAeroLayerFactory setting frame = bounds. Correct frames applied on layout pass.
        let bodyLayer   = NeoAeroLayerFactory.make(style: style, bounds: bodyView.bounds)
        let titleSimple = NeoAeroLayerFactory.makeSimplified(style: style, bounds: titleView.bounds)
        let toolSimple  = NeoAeroLayerFactory.makeSimplified(style: style, bounds: toolbarView.bounds)

        bodyView.layer?.insertSublayer(bodyLayer,    at: 0)
        titleView.layer?.insertSublayer(titleSimple, at: 0)
        toolbarView.layer?.insertSublayer(toolSimple, at: 0)

        NSLog("MANZO Phase 8: ManzoPlaylistPanel.applyNeoAeroChrome — bodyFocus layers applied, theme=%@",
              style.colorTheme.rawValue)
    }

    private func removeNeoAeroLayers(from layer: CALayer?) {
        guard let layer = layer else { return }
        let toRemove = layer.sublayers?.filter {
            ($0.value(forKey: "name") as? String) == "NeoAeroContainer"
        } ?? []
        toRemove.forEach { $0.removeFromSuperlayer() }
    }

    // MARK: - UI Updates

    /// Update track count label and show/hide empty state.
    /// Called by AppDelegate after mutations to PlaylistManager.
    func updateTrackCount(_ count: Int) {
        let p3      = CGColorSpace(name: CGColorSpace.displayP3)!
        let dimColor = NSColor(cgColor: CGColor(colorSpace: p3, components: [0.58, 0.60, 0.65, 1.0])!)!
        let text = count == 1 ? "1 track" : "\(count) tracks"
        trackCountLabel.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [.foregroundColor: dimColor, .font: NSFont.systemFont(ofSize: 11)]
        )
        setEmptyStateVisible(count == 0)
    }

    /// Show or hide the empty state overlay (and correspondingly hide the table).
    /// success_criteria: scrollView.isHidden = visible AND tableView.isHidden = visible (belt-and-suspenders).
    func setEmptyStateVisible(_ visible: Bool) {
        scrollView.isHidden          = visible     // hide the table when empty state is shown
        tableView.isHidden           = visible     // belt-and-suspenders: hide tableView too
        emptyStateContainer.isHidden = !visible    // show the overlay when empty
    }

    // MARK: - Actions (delegate wired by AppDelegate in Plan 08-03)

    @objc private func addButtonClicked(_ sender: Any) {
        delegate?.playlistPanelDidRequestAdd(self)
    }

    @objc private func removeButtonClicked(_ sender: Any) {
        let row = tableView.selectedRow
        guard row >= 0 else { return }
        delegate?.playlistPanel(self, didRequestRemoveAt: row)
    }

    /// T-08-06: guard row >= 0 prevents out-of-range delegate calls.
    @objc func handleDoubleClick(_ sender: Any) {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        delegate?.playlistPanel(self, didDoubleClickRow: row)
    }

    // MARK: - Factory Helpers

    private static func makeToolbarButton(label: String, tooltip: String) -> NSButton {
        let p3       = CGColorSpace(name: CGColorSpace.displayP3)!
        let dimColor = NSColor(cgColor: CGColor(colorSpace: p3, components: [0.58, 0.60, 0.65, 1.0])!)!
        let button   = NSButton()
        button.bezelStyle  = .inline
        button.isBordered  = false
        button.toolTip     = tooltip
        button.title       = ""
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: dimColor,
            .font: NSFont.systemFont(ofSize: 11),
        ]
        button.attributedTitle = NSAttributedString(string: label, attributes: attrs)
        return button
    }

    private static func makeTrackCountLabel() -> NSTextField {
        let p3       = CGColorSpace(name: CGColorSpace.displayP3)!
        let dimColor = NSColor(cgColor: CGColor(colorSpace: p3, components: [0.58, 0.60, 0.65, 1.0])!)!
        let label    = NSTextField(labelWithString: "0 tracks")
        label.font          = NSFont.systemFont(ofSize: 11)
        label.textColor     = dimColor
        label.alignment     = .right
        label.isBezeled     = false
        label.isEditable    = false
        label.backgroundColor = .clear
        label.drawsBackground = false
        return label
    }
}

// MARK: - Delegate Protocol (wired by AppDelegate in Plan 08-03)

protocol ManzoPlaylistPanelDelegate: AnyObject {
    func playlistPanelDidRequestAdd(_ panel: ManzoPlaylistPanel)
    func playlistPanel(_ panel: ManzoPlaylistPanel, didRequestRemoveAt index: Int)
    func playlistPanel(_ panel: ManzoPlaylistPanel, didDoubleClickRow row: Int)
}
