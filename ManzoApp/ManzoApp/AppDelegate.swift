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

    // Phase 9: retain the window for the app's lifetime.
    private var manzoWindow: NSWindow? = nil

    // Phase 8: PlaylistManager replaces trackQueue/currentTrackIndex (D-12).
    private var playlistManager:   PlaylistManager    = PlaylistManager()
    // Phase 8: ManzoPlaylistPanel — retained reference prevents ARC deallocation.
    private var playlistPanel:     ManzoPlaylistPanel? = nil
    // EQ panel — retained reference prevents ARC deallocation.
    private var eqPanel:           ManzoEQPanel?       = nil
    // Phase 8: PL toggle button — retained so AppDelegate can update active/inactive appearance.
    private var plButton:          NSButton?          = nil
    // Phase 8: last known main window origin — used to compute delta for co-move (D-03).
    private var lastMainWindowOrigin: NSPoint         = .zero

    // Phase 9: direct refs to ManzoMainWindow's LCD components
    private var lcdLabel:    LCDLabel?       = nil
    private var marqueeView: MarqueeView?    = nil
    private var specsLabel:  NSTextField?    = nil
    private var statusbarView: ManzoStatusbar? = nil
    private var seekBarView: SeekBar?        = nil
    private var analyzerView: SpectrumView?  = nil
    private var currentDuration: Double      = 0

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

        // MARK: Phase 9 — ManzoMainWindow
        let win = ManzoMainWindow()
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.setFrameAutosaveName("ManzoMainWindow")
        manzoWindow = win
        eqPanel = ManzoEQPanel()
        eqPanel?.onBandChanged = { [weak self] gains, preamp in
            guard let handle = self?.manzoHandle else { return }
            var g = gains
            g.withUnsafeBufferPointer { ptr in
                manzo_set_eq(handle, ptr.baseAddress, preamp)
            }
        }
        NSLog("MANZO Phase 9: ManzoMainWindow ordered front — 275×116pt")

        // MARK: Phase 9 wiring — connect ManzoMainWindow components to existing FFI handlers
        if let winView = win.contentView as? ManzoMainWindowView {
            let body = winView.body

            // LCD: wire native components for time/title/specs updates
            lcdLabel      = body.lcd
            marqueeView   = body.marquee
            specsLabel    = body.specs
            statusbarView = winView.statusbar
            seekBarView   = body.seek
            analyzerView  = body.analyzer
            analyzerView?.manzoHandle = manzoHandle  // non-nil if track auto-started before window

            body.seek.onSeek = { [weak self] ratio in
                guard let self, let h = self.manzoHandle else { return }
                let ms = UInt64(ratio * self.currentDuration * 1000)
                manzo_seek(h, ms)
            }

            // VOL/BAL: fire existing FFI calls on drag
            body.volSlider.onValueChanged = { [weak self] v in
                guard let handle = self?.manzoHandle else { return }
                manzo_set_volume(handle, Float(v))
            }
            body.balSlider.onValueChanged = { [weak self] v in
                guard let handle = self?.manzoHandle else { return }
                manzo_set_pan(handle, Float(v * 2 - 1))   // 0..1 → -1..+1
            }

            // Transport: point onTap to existing AppDelegate handlers
            body.play.onTap  = { [weak self] in self?.handlePlayPauseButton() }
            body.pause.onTap = { [weak self] in self?.handlePlayPauseButton() }
            body.prev.onTap  = { [weak self] in self?.handlePrevButton() }
            body.stop.onTap  = { [weak self] in
                guard let handle = self?.manzoHandle else { return }
                manzo_stop(handle)
            }
            body.next.onTap  = { [weak self] in
                guard let self = self else { return }
                guard let _ = self.playlistManager.next() else { return }
                self.jumpToTrack(at: self.playlistManager.currentIndex)
            }
            body.eject.onTap = { [weak self] in self?.openFilePicker() }

            // PL toggle: show/hide playlist panel
            body.plBtn.onToggle = { [weak self] isOn in
                guard let self else { return }
                if isOn { self.playlistPanel?.makeKeyAndOrderFront(nil) }
                else     { self.playlistPanel?.orderOut(nil) }
            }
            body.eqBtn.onToggle = { [weak self] isOn in
                if isOn { self?.eqPanel?.makeKeyAndOrderFront(nil) }
                else     { self?.eqPanel?.orderOut(nil) }
            }
        }

        // MARK: Phase 8 — Playlist panel
        let panel = ManzoPlaylistPanel()
        panel.playlistDelegate = self
        panel.tableView.dataSource = self
        panel.tableView.delegate   = self
        panel.tableView.registerForDraggedTypes([.string])
        panel.tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        let mainOrigin = win.frame.origin
        let panelHeight = panel.frame.height
        panel.setFrameOrigin(NSPoint(x: mainOrigin.x, y: mainOrigin.y - panelHeight))
        lastMainWindowOrigin = mainOrigin
        panel.orderFront(nil)
        panel.setFrameAutosaveName("ManzoPlaylistPanel")
        playlistPanel = panel

        updatePLButtonAppearance()
        panel.updateTrackCount(playlistManager.tracks.count)
        panel.tableView.reloadData()
        panel.setEmptyStateVisible(playlistManager.tracks.isEmpty)

        if let track = playlistManager.trackAt(playlistManager.currentIndex) {
            let title = track.title ?? (track.path as NSString).lastPathComponent
            marqueeView?.text = "★ \(playlistManager.currentIndex + 1). \(title)     "
            specsLabel?.stringValue = "128 kbps · 44 khz · stereo"
        }
        NSLog("MANZO Phase 8: PlaylistPanel configured — %d tracks", playlistManager.tracks.count)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Phase 3: stop the poll timer FIRST so it cannot fire after the handle is freed.
        pollTimer?.invalidate()
        pollTimer = nil
        // Phase 8 (D-11): final save on terminate (in addition to per-mutation autosave).
        playlistManager.save()
        NSLog("MANZO Phase 8: PlaylistManager.save() called in applicationWillTerminate")

        // Release Rust handle on app exit — manzo_close drops the Arc and stops cpal stream (T-02-09).
        if let handle = manzoHandle {
            analyzerView?.manzoHandle = nil
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

        // Phase 8.1 (D-12): four poll steps run on every non-ENDED tick.
        guard state == MANZO_STATE_ENDED else {
            let position = Double(manzo_get_position(handle)) / 1000.0
            let duration = playlistManager.trackAt(playlistManager.currentIndex)?.duration ?? 0
            currentDuration = duration

            // Update LCDLabel time display
            let m = Int(position) / 60, s = Int(position) % 60
            lcdLabel?.stringValue = String(format: "%d:%02d", m, s)
            // Update seek bar position (skip if user is dragging)
            if let bar = seekBarView, !bar.isDragging {
                bar.progress = CGFloat(duration > 0 ? position / duration : 0)
                bar.needsDisplay = true
            }
            // Update status bar
            if state == MANZO_STATE_PLAYING {
                statusbarView?.setStatus("▶ Playing")
            } else if state == MANZO_STATE_PAUSED {
                statusbarView?.setStatus("⏸ Paused")
            } else {
                statusbarView?.setStatus("■ Stopped")
            }
            return
        }

        // --- ENDED branch: existing auto-advance logic (unchanged) ---
        NSLog("MANZO Phase 8: track ended (state=4) — advancing via PlaylistManager.next()")

        // Phase 8 (D-15): use PlaylistManager.next() instead of raw array indexing.
        analyzerView?.manzoHandle = nil
        manzo_close(handle)
        manzoHandle = nil

        guard let nextTrack = playlistManager.next() else {
            NSLog("MANZO Phase 8: PlaylistManager exhausted — stopping poll timer")
            pollTimer?.invalidate()
            pollTimer = nil
            // Reload table so active marker clears.
            playlistPanel?.tableView.reloadData()
            return
        }

        let nextPath = nextTrack.path
        guard FileManager.default.fileExists(atPath: nextPath) else {
            NSLog("MANZO Phase 8: next track not found at \(nextPath) — stopping poll timer")
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }

        manzoHandle = manzo_open(nextPath)
        guard let nextHandle = manzoHandle else {
            NSLog("MANZO Phase 8: manzo_open returned null for next track \(nextPath) — stopping poll timer")
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        let playResult = manzo_play(nextHandle)
        analyzerView?.manzoHandle = nextHandle
        NSLog("MANZO Phase 8: auto-advance to \(nextPath) — play result: \(playResult)")
        if let track = playlistManager.trackAt(playlistManager.currentIndex) {
            let title = track.title ?? (track.path as NSString).lastPathComponent
            marqueeView?.text = "★ \(playlistManager.currentIndex + 1). \(title)     "
            specsLabel?.stringValue = "128 kbps · 44 khz · stereo"
        }
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

    private func addControl(_ view: NSView, to parent: NSView, top: CGFloat, leading: CGFloat, width: CGFloat, height: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: parent.topAnchor, constant: top),
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: leading),
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height),
        ])
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
                    // Auto-start first track if nothing is playing yet (poll timer unarmed).
                    if self.manzoHandle == nil {
                        self.jumpToTrack(at: 0)
                    }
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
        return 24  // matches ManzoPlaylistPanel.tableView.rowHeight
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

// MARK: - Phase 8.1: Transport Button Handlers

extension AppDelegate {

    /// Smart prev (D-11): if elapsed > 2s, restart current track; else go to previous track.
    func handlePrevButton() {
        let elapsed = manzoHandle.map { Double(manzo_get_position($0)) / 1000.0 } ?? 0
        if elapsed > 2.0 {
            if let handle = manzoHandle {
                manzo_seek(handle, 0)
                NSLog("MANZO Phase 8.1: handlePrevButton — elapsed=%.1f > 2s, restarting track", elapsed)
            }
        } else {
            _ = playlistManager.prev()
            jumpToTrack(at: playlistManager.currentIndex)
            NSLog("MANZO Phase 8.1: handlePrevButton — elapsed=%.1f <= 2s, previous track index=%d",
                  elapsed, playlistManager.currentIndex)
        }
    }

    /// Play/pause toggle (D-10): driven by current manzo_get_state.
    /// PLAYING → pause (label shows ▶ after); PAUSED/STOPPED → play (label shows ⏸ after).
    /// Label is immediately updated optimistically; poll timer corrects within 100ms.
    func handlePlayPauseButton() {
        guard let handle = manzoHandle else {
            // No handle: open file picker so user can load a track
            openFilePicker()
            return
        }
        let state = manzo_get_state(handle)
        if state == MANZO_STATE_PLAYING {
            manzo_pause(handle)
            NSLog("MANZO Phase 8.1: handlePlayPauseButton — was PLAYING, now paused")
        } else {
            // PAUSED (2) or STOPPED (3)
            manzo_play(handle)
            NSLog("MANZO Phase 8.1: handlePlayPauseButton — was PAUSED/STOPPED, now playing")
        }
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
                    analyzerView?.manzoHandle = nil
                    manzo_close(handle)
                    manzoHandle = nil
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

        // Stop before close — prevents second cpal stream overlapping during track switch (UAT fix).
        if let handle = manzoHandle {
            analyzerView?.manzoHandle = nil
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
        analyzerView?.manzoHandle = newHandle

        if let track = playlistManager.trackAt(index) {
            let title = track.title ?? (track.path as NSString).lastPathComponent
            marqueeView?.text = "★ \(index + 1). \(title)     "
            specsLabel?.stringValue = "128 kbps · 44 khz · stereo"
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
