import AppKit

@objc class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - State

    // Keep handle alive for the app's lifetime — stored as instance var prevents premature dealloc.
    // Type matches cbindgen output: struct manzo_ManzoHandle * → UnsafeMutablePointer<manzo_ManzoHandle>?
    private var manzoHandle: UnsafeMutablePointer<manzo_ManzoHandle>? = nil

    // Phase 3 (D-02): playback state constants — must match the i32 returned by manzo_get_state.
    // Defined here as Int32 locals (rather than C macros in the bridging header) to keep this
    // task self-contained; cbindgen emits the function but not symbolic state names.
    private let MANZO_STATE_PLAYING: Int32 = 1
    private let MANZO_STATE_PAUSED:  Int32 = 2
    private let MANZO_STATE_STOPPED: Int32 = 3
    private let MANZO_STATE_ENDED:   Int32 = 4

    // Phase 3 (D-05 / AUDIO-05): polling timer — kept, wired to PlaylistManager.next() in Phase 8.
    private var pollTimer: Timer? = nil

    // Phase 5: retain the window for the app's lifetime.
    // ARC would deallocate a window stored only in a local var on the next runloop cycle.
    private var manzoWindow: ManzoWindow? = nil

    // Phase 6: retained ManzoVisualStyle — loaded from UserDefaults in applicationDidFinishLaunching.
    // AppDelegate owns the current style per D-10.
    private var visualStyle: ManzoVisualStyle = .default

    // Phase 7: retained spectrum view — initialized in applicationDidFinishLaunching.
    private var spectrumView: ManzoSpectrumView? = nil

    // Phase 8: PlaylistManager replaces trackQueue/currentTrackIndex (D-12).
    private var playlistManager:   PlaylistManager    = PlaylistManager()
    // Phase 8: ManzoPlaylistPanel — retained reference prevents ARC deallocation.
    private var playlistPanel:     ManzoPlaylistPanel? = nil
    // Phase 8: PL toggle button — retained so AppDelegate can update active/inactive appearance.
    private var plButton:          NSButton?          = nil
    // Phase 8: last known main window origin — used to compute delta for co-move (D-03).
    private var lastMainWindowOrigin: NSPoint         = .zero

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build the main menu programmatically so Cmd-Q (and other standard key
        // equivalents) are wired up. Without a MainMenu.xib this is never done
        // automatically — NSApplication creates a bare menu with no key equivalents.
        buildMainMenu()

        // Phase 8 (D-12): PlaylistManager loaded from JSON at init(); start first track if any.
        // On very first launch (empty JSON), playlist starts empty — no auto-load of test fixtures.
        NSLog("MANZO Phase 8: PlaylistManager loaded — %d tracks", playlistManager.tracks.count)

        if let firstTrack = playlistManager.trackAt(0), FileManager.default.fileExists(atPath: firstTrack.path) {
            playlistManager.currentIndex = 0
            manzoHandle = manzo_open(firstTrack.path)
            if manzoHandle == nil {
                NSLog("MANZO Phase 8: manzo_open returned null for first track \(firstTrack.path)")
            } else {
                let playResult = manzo_play(manzoHandle!)
                if playResult == 0 {
                    NSLog("MANZO Phase 8: playback started — \(firstTrack.path)")
                    if let sv = spectrumView {
                        sv.manzoHandle = manzoHandle
                        sv.startRenderLoop()
                        NSLog("MANZO Phase 7: spectrum render loop started")
                    }
                } else {
                    NSLog("MANZO Phase 8: manzo_play failed with code \(playResult)")
                }
                // Phase 3 poll timer pattern — kept identical (D-15).
                pollTimer = Timer.scheduledTimer(
                    timeInterval: 0.1,
                    target: self,
                    selector: #selector(pollPlaybackState),
                    userInfo: nil,
                    repeats: true
                )
                NSLog("MANZO Phase 8: 100ms state poll timer armed — playlist size \(playlistManager.tracks.count)")
            }
        } else if playlistManager.tracks.isEmpty {
            NSLog("MANZO Phase 8: empty playlist on first launch — no playback started")
        } else {
            NSLog("MANZO Phase 8: first track path not found on disk — skipping playback")
        }

        // MARK: Phase 5 / Phase 6 — window setup + Neo-Aero style application
        // D-04 (Phase 5): isOpaque=false and backgroundColor=.clear set inside ManzoWindow.init()
        //                 before this call — already correct for compositor.
        // D-10 (Phase 6): ManzoVisualStyle loaded and applied before contentView assignment.
        let window   = ManzoWindow()
        let rootView = ManzoRootView(frame: window.frame)

        // Phase 6 (D-10): load persisted style (or default on first launch) and apply Neo-Aero chrome.
        visualStyle = ManzoVisualStyle.load()
        rootView.applyStyle(visualStyle)
        NSLog("MANZO Phase 6: ManzoVisualStyle loaded and applied — layout=%@, theme=%@, wetFloor=%d",
              visualStyle.panelLayout.rawValue, visualStyle.colorTheme.rawValue,
              visualStyle.wetFloor ? 1 : 0)

        window.contentView = rootView
        window.center()
        window.orderFront(nil)
        // D-12: single call — AppKit saves frame on move and restores on next launch automatically.
        // Must be called AFTER orderFront so AppKit can match the autosave name to the visible window.
        window.setFrameAutosaveName("ManzoMainWindow")
        manzoWindow = window   // retain: prevent ARC deallocation
        NSLog("MANZO Phase 5: window ordered front — 275×116 pt frameless, autosave=ManzoMainWindow")

        // MARK: Phase 7 — Spectrum analyzer setup (CHK-02: after orderFront so bodyView has screen context)
        let spectrum = ManzoSpectrumView()
        rootView.addSpectrumView(spectrum)
        spectrumView = spectrum
        NSLog("MANZO Phase 7: ManzoSpectrumView created and added to bodyView")

        if let handle = manzoHandle {
            spectrum.manzoHandle = handle
            spectrum.startRenderLoop()
            NSLog("MANZO Phase 7: CADisplayLink render loop started — manzoHandle wired")
        }

        // MARK: Phase 8 — Playlist panel + PL button setup
        let panel = ManzoPlaylistPanel()
        panel.playlistDelegate = self
        // Set NSTableView data source and delegate.
        panel.tableView.dataSource = self
        panel.tableView.delegate   = self
        // Register for drag-reorder (required before dragging works).
        panel.tableView.registerForDraggedTypes([.string])
        panel.tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        // Position panel below main window (D-01).
        let mainOrigin = window.frame.origin
        let panelHeight = panel.frame.height
        panel.setFrameOrigin(NSPoint(x: mainOrigin.x, y: mainOrigin.y - panelHeight))
        lastMainWindowOrigin = mainOrigin
        // isOpaque=false + backgroundColor=.clear already set in ManzoPlaylistPanel.init().
        // setFrameAutosaveName AFTER orderFront (Phase 5 D-12 pattern).
        panel.orderFront(nil)
        panel.setFrameAutosaveName("ManzoPlaylistPanel")
        playlistPanel = panel   // retain reference

        // PL button: 20×12 pt in statusView, trailing-8pt (D-02, UI-SPEC).
        let plBtn = makePLButton()
        rootView.addPLButton(plBtn)
        plButton = plBtn
        updatePLButtonAppearance()

        // Update initial track count display.
        panel.updateTrackCount(playlistManager.tracks.count)
        panel.tableView.reloadData()
        panel.setEmptyStateVisible(playlistManager.tracks.isEmpty)

        // Co-move: fire on every mouseDragged event in ManzoWindow so panel follows in real time.
        // Replaces NSWindow.didMoveNotification which fires too infrequently (UAT fix, issue 3).
        window.onWindowMoved = { [weak self] in self?.handleMainWindowMoved() }
        NSLog("MANZO Phase 8: ManzoPlaylistPanel created — position below main window, co-move armed")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Phase 3: stop the poll timer FIRST so it cannot fire after the handle is freed.
        pollTimer?.invalidate()
        pollTimer = nil
        // Phase 7: stop render loop before releasing handle (loop reads handle).
        spectrumView?.stopRenderLoop()

        // Phase 8 (D-11): final save on terminate (in addition to per-mutation autosave).
        playlistManager.save()
        NSLog("MANZO Phase 8: PlaylistManager.save() called in applicationWillTerminate")

        // Release Rust handle on app exit — manzo_close drops the Arc and stops cpal stream (T-02-09).
        if let handle = manzoHandle {
            manzo_close(handle)
            manzoHandle = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    // MARK: - Phase 8: auto-advance polling (PlaylistManager replaces trackQueue — D-15)

    /// Polls the Rust core's playback state. When MANZO_STATE_ENDED is observed, calls
    /// PlaylistManager.next() to advance to the next track. Nil-spectrum + close-before-open
    /// ordering enforced verbatim from Phase 3 (prevents dangling handle access + dual cpal stream).
    @objc private func pollPlaybackState() {
        guard let handle = manzoHandle else { return }

        let state = manzo_get_state(handle)
        guard state == MANZO_STATE_ENDED else { return }

        NSLog("MANZO Phase 8: track ended (state=4) — advancing via PlaylistManager.next()")

        // Phase 8 (D-15): use PlaylistManager.next() instead of raw array indexing.
        // Nil spectrum + close-before-open pattern KEPT verbatim (Phase 3 constraint).
        spectrumView?.manzoHandle = nil
        manzo_close(handle)
        manzoHandle = nil

        guard let nextTrack = playlistManager.next() else {
            NSLog("MANZO Phase 8: PlaylistManager exhausted — stopping poll timer")
            pollTimer?.invalidate()
            pollTimer = nil
            spectrumView?.stopRenderLoop()
            // Reload table so active marker clears.
            playlistPanel?.tableView.reloadData()
            return
        }

        let nextPath = nextTrack.path
        guard FileManager.default.fileExists(atPath: nextPath) else {
            NSLog("MANZO Phase 8: next track not found at \(nextPath) — stopping poll timer")
            pollTimer?.invalidate()
            pollTimer = nil
            spectrumView?.stopRenderLoop()
            return
        }

        manzoHandle = manzo_open(nextPath)
        guard let nextHandle = manzoHandle else {
            NSLog("MANZO Phase 8: manzo_open returned null for next track \(nextPath) — stopping poll timer")
            pollTimer?.invalidate()
            pollTimer = nil
            spectrumView?.stopRenderLoop()
            return
        }
        let playResult = manzo_play(nextHandle)
        NSLog("MANZO Phase 8: auto-advance to \(nextPath) — play result: \(playResult)")
        spectrumView?.manzoHandle = nextHandle
        // Reload to update active row marker.
        playlistPanel?.tableView.reloadData()
        playlistPanel?.updateTrackCount(playlistManager.tracks.count)
    }

    // MARK: - Menu

    /// Builds NSApp.mainMenu programmatically.
    ///
    /// This app has no MainMenu.xib (pure code-only UI). Without this call
    /// NSApplication synthesises a bare menu that renders visible items (Quit,
    /// Hide, etc.) via AppKit's automatic menu population, but the Quit item
    /// lacks a keyEquivalent — so Cmd-Q is never dispatched to terminate:.
    ///
    /// Structure mirrors the standard Xcode-generated MainMenu.xib:
    ///   [AppName]  →  About, —, Hide, Hide Others, Show All, —, Quit
    ///   [Window]   →  Minimize, Zoom, —, Bring All to Front, —, Playlist Editor (Alt+E)
    ///
    /// Only the Application submenu is strictly required for Cmd-Q; the Window
    /// menu is included so AppKit window-management shortcuts (Cmd-M etc.) work.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        // ── Application menu ──────────────────────────────────────────────────
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appName = ProcessInfo.processInfo.processName
        let appMenu  = NSMenu()
        appMenuItem.submenu = appMenu

        appMenu.addItem(withTitle: "About \(appName)",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")

        appMenu.addItem(.separator())

        appMenu.addItem(withTitle: "Hide \(appName)",
                        action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")

        let hideOthers = appMenu.addItem(withTitle: "Hide Others",
                                         action: #selector(NSApplication.hideOtherApplications(_:)),
                                         keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]

        appMenu.addItem(withTitle: "Show All",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")

        appMenu.addItem(.separator())

        // Quit — this is the item that was missing its keyEquivalent.
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        // ── Window menu ───────────────────────────────────────────────────────
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        windowMenu.addItem(withTitle: "Minimize",
                           action: #selector(NSWindow.miniaturize(_:)),
                           keyEquivalent: "m")

        windowMenu.addItem(withTitle: "Zoom",
                           action: #selector(NSWindow.zoom(_:)),
                           keyEquivalent: "")

        windowMenu.addItem(.separator())

        windowMenu.addItem(withTitle: "Bring All to Front",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")

        windowMenu.addItem(.separator())

        // Phase 8 (D-02): Alt+E shortcut to toggle playlist panel (Winamp default config_pe_open toggle).
        let plItem = windowMenu.addItem(
            withTitle: "Playlist Editor",
            action:    #selector(togglePlaylistPanel),
            keyEquivalent: "e"
        )
        plItem.keyEquivalentModifierMask = [.option]
        NSLog("MANZO Phase 8: Playlist Editor menu item added — Alt+E")

        NSApp.mainMenu = mainMenu
        NSLog("MANZO: main menu built programmatically — Cmd-Q wired to terminate:")
    }

    // MARK: - Helpers

    /// Resolves a fixture path from the app bundle (Copy Bundle Resources).
    /// Falls back to MANZO_FIXTURE_DIR env var for CI overrides.
    /// Returns empty string if not found — caller checks fileExists.
    private func resolveFixturePath(name: String, ext: String) -> String {
        if let bundlePath = Bundle.main.path(forResource: name, ofType: ext) {
            return bundlePath
        }
        if let envDir = ProcessInfo.processInfo.environment["MANZO_FIXTURE_DIR"] {
            return (envDir as NSString).appendingPathComponent("\(name).\(ext)")
        }
        return ""
    }

    // MARK: - Phase 8: Playlist Panel Toggle (D-02)

    @objc func togglePlaylistPanel() {
        guard let panel = playlistPanel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
        updatePLButtonAppearance()
        NSLog("MANZO Phase 8: togglePlaylistPanel — visible=%d", playlistPanel?.isVisible == true ? 1 : 0)
    }

    // MARK: - Phase 8: NSOpenPanel File Picker (D-17)

    func openFilePicker() {
        let op = NSOpenPanel()
        op.allowsMultipleSelection = true
        op.canChooseFiles = true
        op.canChooseDirectories = false
        if #available(macOS 12.0, *) {
            op.allowedContentTypes = [.mp3]
        } else {
            op.allowedFileTypes = ["mp3"]
        }
        op.prompt = "Add Files\u{2026}"
        op.beginSheetModal(for: manzoWindow!) { [weak self] response in
            guard response == .OK, let self = self else { return }
            self.playlistManager.add(urls: op.urls) { [weak self] in
                guard let self = self else { return }
                self.playlistPanel?.tableView.reloadData()
                self.playlistPanel?.updateTrackCount(self.playlistManager.tracks.count)
                self.playlistPanel?.setEmptyStateVisible(self.playlistManager.tracks.isEmpty)
                // Scroll to last added row.
                if !self.playlistManager.tracks.isEmpty {
                    let lastRow = self.playlistManager.tracks.count - 1
                    self.playlistPanel?.tableView.scrollRowToVisible(lastRow)
                }
                NSLog("MANZO Phase 8: NSOpenPanel — added %d files", op.urls.count)
            }
        }
    }

    // MARK: - Phase 8: Co-Move (D-03)

    private func handleMainWindowMoved() {
        guard let window = manzoWindow, let panel = playlistPanel else { return }
        let newOrigin = window.frame.origin
        let delta     = NSPoint(x: newOrigin.x - lastMainWindowOrigin.x,
                                y: newOrigin.y - lastMainWindowOrigin.y)
        lastMainWindowOrigin = newOrigin
        let panelOrigin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: panelOrigin.x + delta.x, y: panelOrigin.y + delta.y))
    }

    // MARK: - Phase 8: PL Button Factory + Appearance

    private func makePLButton() -> NSButton {
        let button   = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.target     = self
        button.action     = #selector(togglePlaylistPanel)
        // Initial title/color set in updatePLButtonAppearance().
        return button
    }

    private func updatePLButtonAppearance() {
        guard let button = plButton else { return }
        let p3        = CGColorSpace(name: CGColorSpace.displayP3)!
        let isVisible = playlistPanel?.isVisible ?? false
        if isVisible {
            // Active: white label + P3(0.20,0.40,0.65,0.50) background (UI-SPEC PL Toggle Button)
            let activeColor = NSColor(cgColor: CGColor(colorSpace: p3, components: [1.0, 1.0, 1.0, 1.0])!)!
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: activeColor,
                .font: NSFont.boldSystemFont(ofSize: 9),
            ]
            button.attributedTitle = NSAttributedString(string: "PL", attributes: attrs)
            button.wantsLayer = true
            button.layer?.backgroundColor = CGColor(colorSpace: p3, components: [0.20, 0.40, 0.65, 0.50])
            button.layer?.cornerRadius = 2
        } else {
            // Inactive: dim label, no background (UI-SPEC PL Toggle Button)
            let inactiveColor = NSColor(cgColor: CGColor(colorSpace: p3, components: [0.78, 0.80, 0.85, 0.70])!)!
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: inactiveColor,
                .font: NSFont.boldSystemFont(ofSize: 9),
            ]
            button.attributedTitle = NSAttributedString(string: "PL", attributes: attrs)
            button.wantsLayer = true
            button.layer?.backgroundColor = .none
        }
    }
}

// MARK: - Phase 8: NSTableViewDataSource

extension AppDelegate: NSTableViewDataSource {

    func numberOfRows(in tableView: NSTableView) -> Int {
        return playlistManager.tracks.count
    }

    // Drag-reorder pasteboard write — source row index encoded as String.
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .string)
        return item
    }

    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // Force drop indicator to appear BETWEEN rows (.above), not ON a row.
        // This triggers the 2pt horizontal line UI (NSTableView default for .above drops).
        if dropOperation == .on {
            tableView.setDropRow(row, dropOperation: .above)
        }
        return .move
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        // Extract source row index from pasteboard (set in pasteboardWriterForRow).
        // T-08-13: validate string is a valid integer and bounds-check before use.
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let sourceStr = item.string(forType: .string),
              let sourceRow = Int(sourceStr) else { return false }

        guard sourceRow != row, sourceRow >= 0, sourceRow < playlistManager.tracks.count else { return false }

        // PlaylistManager.move saves automatically (D-11).
        playlistManager.move(from: sourceRow, to: row)

        // Use NSTableView.moveRow for smooth visual reorder (no full reload flash).
        let destinationRow = row > sourceRow ? row - 1 : row
        tableView.moveRow(at: sourceRow, to: destinationRow)

        // Update active row marker if currentIndex track moved.
        tableView.reloadData()
        playlistPanel?.updateTrackCount(playlistManager.tracks.count)

        NSLog("MANZO Phase 8: drag-reorder accepted — from=%d to=%d, currentIndex=%d", sourceRow, row, playlistManager.currentIndex)
        return true
    }
}

// MARK: - Phase 8: NSTableViewDelegate

extension AppDelegate: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("PlaylistRowView")
        var cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PlaylistRowView
        if cell == nil {
            cell = PlaylistRowView()
            cell?.identifier = identifier
        }
        guard let cell = cell, let track = playlistManager.trackAt(row) else { return nil }
        cell.configure(track: track, rowNum: row + 1, isActive: row == playlistManager.currentIndex)
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("ManzoPlaylistRowBackground")
        var rowView = tableView.makeView(withIdentifier: identifier, owner: self) as? ManzoPlaylistRowBackground
        if rowView == nil {
            rowView = ManzoPlaylistRowBackground()
            rowView?.identifier = identifier
        }
        return rowView
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 18  // Winamp canonical row height (UI-SPEC)
    }

    // Delete key removal (D-13).
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { true }
}

// MARK: - Phase 8: ManzoPlaylistPanelDelegate

extension AppDelegate: ManzoPlaylistPanelDelegate {

    func playlistPanelDidRequestAdd(_ panel: ManzoPlaylistPanel) {
        openFilePicker()
    }

    func playlistPanel(_ panel: ManzoPlaylistPanel, didRequestRemoveAt index: Int) {
        removeTrackAt(index)
    }

    func playlistPanel(_ panel: ManzoPlaylistPanel, didDoubleClickRow row: Int) {
        jumpToTrack(at: row)
    }
}

// MARK: - Phase 8: Track Operations

extension AppDelegate {

    /// Remove track at index from PlaylistManager. Handle currently-playing case (D-13).
    func removeTrackAt(_ index: Int) {
        let wasCurrentTrack = (index == playlistManager.currentIndex)
        playlistManager.remove(at: index)
        playlistPanel?.tableView.reloadData()
        playlistPanel?.updateTrackCount(playlistManager.tracks.count)
        playlistPanel?.setEmptyStateVisible(playlistManager.tracks.isEmpty)

        if wasCurrentTrack {
            // Removed track was playing: advance to next or stop (D-13).
            if let nextTrack = playlistManager.trackAt(playlistManager.currentIndex),
               FileManager.default.fileExists(atPath: nextTrack.path) {
                jumpToTrack(at: playlistManager.currentIndex)
            } else {
                // Stop playback.
                if let handle = manzoHandle {
                    spectrumView?.manzoHandle = nil
                    manzo_close(handle)
                    manzoHandle = nil
                    spectrumView?.stopRenderLoop()
                }
                pollTimer?.invalidate()
                pollTimer = nil
            }
        }
        NSLog("MANZO Phase 8: removeTrackAt — index=%d, wasCurrentTrack=%d, total=%d", index, wasCurrentTrack ? 1 : 0, playlistManager.tracks.count)
    }

    /// Jump to track at index via double-click (D-14).
    /// close-before-open ordering enforced (Phase 3 D-05 constraint).
    func jumpToTrack(at index: Int) {
        guard let track = playlistManager.trackAt(index) else { return }

        // Nil spectrum before close to prevent dangling handle access (Phase 7 fix pattern).
        spectrumView?.manzoHandle = nil

        // Stop before close — prevents second cpal stream overlapping during track switch (UAT fix).
        if let handle = manzoHandle {
            manzo_stop(handle)
            manzo_close(handle)
            manzoHandle = nil
        }

        playlistManager.currentIndex = index
        guard FileManager.default.fileExists(atPath: track.path) else {
            NSLog("MANZO Phase 8: jumpToTrack — file missing at %@", track.path)
            playlistPanel?.tableView.reloadData()
            return
        }

        manzoHandle = manzo_open(track.path)
        guard let newHandle = manzoHandle else {
            NSLog("MANZO Phase 8: jumpToTrack — manzo_open returned null for %@", track.path)
            return
        }
        manzo_play(newHandle)
        spectrumView?.manzoHandle = newHandle

        // Restart render loop + poll timer if not running.
        // startRenderLoop() is idempotent (guards renderSource == nil internally).
        if let sv = spectrumView {
            sv.startRenderLoop()
        }
        if pollTimer == nil {
            pollTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self,
                selector: #selector(pollPlaybackState), userInfo: nil, repeats: true)
        }

        playlistPanel?.tableView.reloadData()
        playlistPanel?.tableView.scrollRowToVisible(index)
        NSLog("MANZO Phase 8: jumpToTrack — index=%d, path=%@", index, track.path)
    }
}
