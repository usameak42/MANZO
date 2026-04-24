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

    // Phase 8.1: retained view references — prevent ARC deallocation between poll ticks.
    private var lcdView:         ManzoLCDView?         = nil
    private var seekBar:         ManzoSeekBar?          = nil
    private var volumeSlider:    ManzoSlider?           = nil
    private var panSlider:       ManzoSlider?           = nil
    private var playPauseButton: ManzoTransportButton?  = nil

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

        // MARK: Phase 8.1 — Transport Controls + LCD Display

        // ManzoLCDView: full width, y=14, height=43 (D-04)
        let lcd = ManzoLCDView(frame: .zero)
        rootView.addLCDView(lcd)
        lcdView = lcd

        // ManzoSeekBar: x=16, y=72, 248×10 (D-07)
        let bar = ManzoSeekBar(frame: NSRect(x: 16, y: 72, width: 248, height: 10))
        bar.onSeek = { [weak self] t in
            guard let self = self, let handle = self.manzoHandle else { return }
            manzo_seek(handle, UInt64(t * 1000))
            NSLog("MANZO Phase 8.1: ManzoSeekBar.onSeek — seeking to %.2f", t)
        }
        rootView.addSeekBar(bar)
        seekBar = bar

        // Volume slider: x=107, y=57, 68×13, range 0–255 (D-08)
        let volSlider = ManzoSlider(frame: NSRect(x: 107, y: 57, width: 68, height: 13))
        volSlider.minValue = 0
        volSlider.maxValue = 255
        volSlider.value    = 200   // sensible default ~78%
        volSlider.onValueChanged = { [weak self] v in
            guard let self = self, let handle = self.manzoHandle else { return }
            manzo_set_volume(handle, v / 255.0)
        }
        rootView.addVolumeSlider(volSlider)
        volumeSlider = volSlider
        // Apply initial volume so audio matches slider position
        if let handle = manzoHandle { manzo_set_volume(handle, volSlider.value / 255.0) }

        // Pan slider: x=177, y=57, 38×13, range -127 to +127, default 0 (center) (D-08)
        let panSl = ManzoSlider(frame: NSRect(x: 177, y: 57, width: 38, height: 13))
        panSl.minValue = -127
        panSl.maxValue =  127
        panSl.value    =    0   // center
        panSl.onValueChanged = { [weak self] v in
            guard let self = self, let handle = self.manzoHandle else { return }
            manzo_set_pan(handle, v / 127.0)
        }
        rootView.addPanSlider(panSl)
        panSlider = panSl

        // Transport buttons — 7 total (D-09)
        // 4 wired + 3 placeholders. All created via ManzoTransportButton.

        // Prev: x=16, y=88, 23×18 — smart prev logic (D-11)
        let prevBtn = ManzoTransportButton(frame: NSRect(x: 16, y: 88, width: 23, height: 18))
        prevBtn.label  = "⏮"
        prevBtn.action = { [weak self] in self?.handlePrevButton() }
        rootView.addTransportButton(prevBtn, x: 16, y: 88, width: 23, height: 18)

        // Play/Pause: x=39, y=88, 23×18 — toggles based on manzo_get_state (D-10)
        let ppBtn = ManzoTransportButton(frame: NSRect(x: 39, y: 88, width: 23, height: 18))
        ppBtn.label  = "▶"
        ppBtn.action = { [weak self] in self?.handlePlayPauseButton() }
        rootView.addTransportButton(ppBtn, x: 39, y: 88, width: 23, height: 18)
        playPauseButton = ppBtn   // retained: poll timer updates label

        // Stop: x=62, y=88, 23×18
        let stopBtn = ManzoTransportButton(frame: NSRect(x: 62, y: 88, width: 23, height: 18))
        stopBtn.label  = "■"
        stopBtn.action = { [weak self] in
            guard let self = self, let handle = self.manzoHandle else { return }
            manzo_stop(handle)
            self.playPauseButton?.label = "▶"
            NSLog("MANZO Phase 8.1: stop button pressed — manzo_stop called")
        }
        rootView.addTransportButton(stopBtn, x: 62, y: 88, width: 23, height: 18)

        // Next: x=85, y=88, 23×18 — calls PlaylistManager.next() + jumpToTrack
        let nextBtn = ManzoTransportButton(frame: NSRect(x: 85, y: 88, width: 23, height: 18))
        nextBtn.label  = "⏭"
        nextBtn.action = { [weak self] in
            guard let self = self else { return }
            guard let _ = self.playlistManager.next() else { return }
            self.jumpToTrack(at: self.playlistManager.currentIndex)
            NSLog("MANZO Phase 8.1: next button pressed — jumpToTrack at %d", self.playlistManager.currentIndex)
        }
        rootView.addTransportButton(nextBtn, x: 85, y: 88, width: 23, height: 18)

        // Eject: x=136, y=89, 22×16 — opens file picker (wired)
        let ejectBtn = ManzoTransportButton(frame: NSRect(x: 136, y: 89, width: 22, height: 16))
        ejectBtn.label  = "⏏"
        ejectBtn.action = { [weak self] in self?.openFilePicker() }
        rootView.addTransportButton(ejectBtn, x: 136, y: 89, width: 22, height: 16)

        // Shuffle placeholder: x=164, y=89, 47×15 — no-op
        let shuffleBtn = ManzoTransportButton(frame: NSRect(x: 164, y: 89, width: 47, height: 15))
        shuffleBtn.label  = "SHF"
        shuffleBtn.action = { NSLog("MANZO Phase 8.1: shuffle pressed — no-op placeholder") }
        rootView.addTransportButton(shuffleBtn, x: 164, y: 89, width: 47, height: 15)

        // Repeat placeholder: x=210, y=89, 28×15 — no-op
        let repeatBtn = ManzoTransportButton(frame: NSRect(x: 210, y: 89, width: 28, height: 15))
        repeatBtn.label  = "REP"
        repeatBtn.action = { NSLog("MANZO Phase 8.1: repeat pressed — no-op placeholder") }
        rootView.addTransportButton(repeatBtn, x: 210, y: 89, width: 28, height: 15)

        // Relocate spectrum to Winamp viz band (D-03): bodyView.topAnchor+43, 107×32 (left-aligned)
        // Must be called AFTER addSpectrumView (which Phase 7 already called above)
        rootView.relocateSpectrumView()

        // Initialize LCD with current track if playlist has one
        if let track = playlistManager.trackAt(playlistManager.currentIndex) {
            lcdView?.updateTrack(title: track.title ?? (track.path as NSString).lastPathComponent,
                                 bitrate: 128, kHz: 44, stereo: true, duration: track.duration)
        } else {
            lcdView?.clearTrack()
        }

        NSLog("MANZO Phase 8.1: all transport controls created and wired — LCD, SeekBar, Sliders×2, Buttons×7")
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

        // Phase 8.1 (D-12): four poll steps run on every non-ENDED tick.
        guard state == MANZO_STATE_ENDED else {
            let position = Double(manzo_get_position(handle))
            let duration = playlistManager.trackAt(playlistManager.currentIndex)?.duration ?? 0

            // Step 1: Update seek bar position (only when not dragging)
            if let bar = seekBar, !bar.isDragging {
                bar.duration = duration
                bar.updateFill(position: position, duration: duration)
            }
            // Step 2: Tick title scroll in LCD
            lcdView?.tickTitleScroll()
            // Step 3: Update LCD time display (elapsed or remaining based on toggle)
            lcdView?.updateTime(position: position, duration: duration)
            // Step 4: Update play/pause button label based on current state
            if state == MANZO_STATE_PLAYING {
                playPauseButton?.label = "⏸"
            } else {
                // PAUSED (2), STOPPED (3) — both show ▶
                playPauseButton?.label = "▶"
            }
            return
        }

        // --- ENDED branch: existing auto-advance logic (unchanged) ---
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
        // Phase 8.1: update seek bar duration and LCD on auto-advance
        if let track = playlistManager.trackAt(playlistManager.currentIndex) {
            seekBar?.duration = track.duration
            lcdView?.updateTrack(
                title: track.title ?? (track.path as NSString).lastPathComponent,
                bitrate: 128, kHz: 44, stereo: true, duration: track.duration
            )
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
        let elapsed = manzoHandle.map { Double(manzo_get_position($0)) } ?? 0
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
            playPauseButton?.label = "▶"   // now paused → show play icon
            NSLog("MANZO Phase 8.1: handlePlayPauseButton — was PLAYING, now paused")
        } else {
            // PAUSED (2) or STOPPED (3)
            manzo_play(handle)
            playPauseButton?.label = "⏸"  // now playing → show pause icon
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

        // Phase 8.1: update LCD display and seek bar duration when track changes
        if let track = playlistManager.trackAt(index) {
            lcdView?.updateTrack(
                title: track.title ?? (track.path as NSString).lastPathComponent,
                bitrate: 128, kHz: 44, stereo: true, duration: track.duration
            )
            seekBar?.duration = track.duration
        }

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
