import AppKit
import AVFoundation

@objc class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - State

    private var manzoHandle: UnsafeMutablePointer<manzo_ManzoHandle>? = nil

    private let MANZO_STATE_PLAYING: Int32 = 1
    private let MANZO_STATE_PAUSED:  Int32 = 2
    private let MANZO_STATE_STOPPED: Int32 = 3
    private let MANZO_STATE_ENDED:   Int32 = 4

    private var pollTimer: Timer? = nil
    private var manzoWindow: NSWindow? = nil
    private var playlistManager:   PlaylistManager    = PlaylistManager()
    private var playlistPanel:     ManzoPlaylistPanel? = nil
    private var eqPanel:           ManzoEQPanel?       = nil
    private var plButton:          NSButton?          = nil
    private var lastMainWindowOrigin: NSPoint         = .zero

    private var lcdLabel:    LCDLabel?       = nil
    private var marqueeView: MarqueeView?    = nil
    private var specsLabel:  NSTextField?    = nil
    private var statusbarView: ManzoStatusbar? = nil
    private var seekBarView: SeekBar?        = nil
    private var analyzerView: SpectrumView?  = nil
    private var currentDuration: Double      = 0
    var avPlayer: AVPlayer?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        stripBinaryQuarantines()
        buildMainMenu()

        NSLog("MANZO Phase 8: PlaylistManager loaded — %d tracks", playlistManager.tracks.count)

        if let firstTrack = playlistManager.trackAt(0), FileManager.default.fileExists(atPath: firstTrack.path) {
            playlistManager.currentIndex = 0
            manzoHandle = manzo_open(firstTrack.path)
            if manzoHandle == nil {
                NSLog("MANZO Phase 8: manzo_open returned null for first track \(firstTrack.path)")
            } else {
                let playResult = manzo_play(manzoHandle!)
                if playResult == 0 {
                    analyzerView?.isPlaying = true
                    NSLog("MANZO Phase 8: playback started — \(firstTrack.path)")
                } else {
                    NSLog("MANZO Phase 8: manzo_play failed with code \(playResult)")
                }
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
        NSApp.activate(ignoringOtherApps: true)
        win.setFrameAutosaveName("ManzoMainWindow")
        win.setContentSize(NSSize(width: 540, height: 116))
        manzoWindow = win
        eqPanel = ManzoEQPanel()
        eqPanel?.onBandChanged = { [weak self] gains, preamp in
            guard let handle = self?.manzoHandle else { return }
            var g = gains
            g.withUnsafeBufferPointer { ptr in
                manzo_set_eq(handle, ptr.baseAddress, preamp)
            }
        }
        eqPanel?.onClose = { [weak self] in
            guard let self else { return }
            (self.manzoWindow?.contentView as? ManzoMainWindowView)?.body.eqBtn.isOnState = false
        }
        NSLog("MANZO Phase 9: ManzoMainWindow ordered front — 275×116pt")

        // MARK: Phase 9 wiring — connect ManzoMainWindow components to existing FFI handlers
        if let winView = win.contentView as? ManzoMainWindowView {
            let body = winView.body

            lcdLabel      = body.lcd
            marqueeView   = body.marquee
            specsLabel    = body.specs
            statusbarView = winView.statusbar
            seekBarView   = body.seek
            analyzerView  = body.analyzer
            analyzerView?.manzoHandle = manzoHandle
            analyzerView?.isPlaying   = (manzoHandle != nil)

            body.seek.onSeek = { [weak self] ratio in
                guard let self, let h = self.manzoHandle else { return }
                let ms = UInt64(ratio * self.currentDuration * 1000)
                manzo_seek(h, ms)
            }

            body.volSlider.onValueChanged = { [weak self] v in
                guard let handle = self?.manzoHandle else { return }
                manzo_set_volume(handle, Float(v))
            }
            body.balSlider.onValueChanged = { [weak self] v in
                guard let handle = self?.manzoHandle else { return }
                manzo_set_pan(handle, Float(v * 2 - 1))
            }

            body.play.onTap  = { [weak self] in self?.handlePlayPauseButton() }
            body.pause.onTap = { [weak self] in self?.handlePlayPauseButton() }
            body.prev.onTap  = { [weak self] in self?.handlePrevButton() }
            body.stop.onTap  = { [weak self] in
                guard let handle = self?.manzoHandle else { return }
                manzo_stop(handle)
                self?.analyzerView?.isPlaying = false
            }
            body.next.onTap  = { [weak self] in
                guard let self = self else { return }
                guard let _ = self.playlistManager.next() else { return }
                self.jumpToTrack(at: self.playlistManager.currentIndex)
            }
            body.eject.onTap = { [weak self] in self?.openFilePicker() }

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

        // MARK: Phase 8 — Playlist panel (Claude Design API)
        let panel = ManzoPlaylistPanel()
        panel.onAddTracks    = { [weak self] in self?.openFilePicker() }
        panel.onRemoveTracks = { [weak self] in
            guard let self else { return }
            self.removeTrackAt(self.playlistPanel?.currentIndex ?? self.playlistManager.currentIndex)
        }
        panel.onTrackSelected = { [weak self] index in
            self?.jumpToTrack(at: index)
        }
        let mainOrigin = win.frame.origin
        let panelHeight = panel.frame.height
        panel.setFrameOrigin(NSPoint(x: mainOrigin.x, y: mainOrigin.y - panelHeight))
        lastMainWindowOrigin = mainOrigin
        panel.setFrameAutosaveName("ManzoPlaylistPanel")
        playlistPanel = panel
        playlistPanel?.onlineQueue = ManzoOnlineQueue()
        playlistPanel?.onPlayOnline = { [weak self] track in
            self?.playYouTubeURL(track.url.absoluteString)
        }
        (win.contentView as? ManzoMainWindowView)?.body.plBtn.isOnState = false

        updatePLButtonAppearance()
        syncPlaylistPanel()

        if let track = playlistManager.trackAt(playlistManager.currentIndex) {
            let title = track.title ?? (track.path as NSString).lastPathComponent
            marqueeView?.text = "★ \(playlistManager.currentIndex + 1). \(title)     "
            specsLabel?.stringValue = "128 kbps · 44 khz · stereo"
        }
        NSLog("MANZO Phase 8: PlaylistPanel configured — %d tracks", playlistManager.tracks.count)
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        playlistManager.save()
        NSLog("MANZO Phase 8: PlaylistManager.save() called in applicationWillTerminate")

        if let handle = manzoHandle {
            analyzerView?.manzoHandle = nil
            manzo_close(handle)
            manzoHandle = nil
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        manzoWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    // MARK: - Phase 8: auto-advance polling

    @objc private func pollPlaybackState() {
        guard let handle = manzoHandle else { return }

        let state = manzo_get_state(handle)

        guard state == MANZO_STATE_ENDED else {
            let position = Double(manzo_get_position(handle)) / 1000.0
            let duration = playlistManager.trackAt(playlistManager.currentIndex)?.duration ?? 0
            currentDuration = duration

            let m = Int(position) / 60, s = Int(position) % 60
            lcdLabel?.stringValue = String(format: "%d:%02d", m, s)
            if let bar = seekBarView, !bar.isDragging {
                bar.progress = CGFloat(duration > 0 ? position / duration : 0)
                bar.needsDisplay = true
            }
            if state == MANZO_STATE_PLAYING {
                statusbarView?.setStatus("▶ Playing")
            } else if state == MANZO_STATE_PAUSED {
                statusbarView?.setStatus("⏸ Paused")
            } else {
                statusbarView?.setStatus("■ Stopped")
            }
            return
        }

        NSLog("MANZO Phase 8: track ended (state=4) — advancing via PlaylistManager.next()")

        analyzerView?.manzoHandle = nil
        manzo_close(handle)
        manzoHandle = nil

        guard let nextTrack = playlistManager.next() else {
            NSLog("MANZO Phase 8: PlaylistManager exhausted — stopping poll timer")
            pollTimer?.invalidate()
            pollTimer = nil
            syncPlaylistPanel()
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
        analyzerView?.isPlaying = playResult == 0
        NSLog("MANZO Phase 8: auto-advance to \(nextPath) — play result: \(playResult)")
        if let track = playlistManager.trackAt(playlistManager.currentIndex) {
            let title = track.title ?? (track.path as NSString).lastPathComponent
            marqueeView?.text = "★ \(playlistManager.currentIndex + 1). \(title)     "
            specsLabel?.stringValue = "128 kbps · 44 khz · stereo"
        }
        syncPlaylistPanel()
    }

    // MARK: - Menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

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
        appMenu.addItem(withTitle: "Quit \(appName)",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

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
                self.syncPlaylistPanel()
                if !self.playlistManager.tracks.isEmpty && self.manzoHandle == nil {
                    self.jumpToTrack(at: 0)
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

    // MARK: - Phase 8: PL Button Appearance

    private func makePLButton() -> NSButton {
        let button   = NSButton()
        button.bezelStyle = .inline
        button.isBordered = false
        button.target     = self
        button.action     = #selector(togglePlaylistPanel)
        return button
    }

    private func updatePLButtonAppearance() {
        guard let button = plButton else { return }
        let p3        = CGColorSpace(name: CGColorSpace.displayP3)!
        let isVisible = playlistPanel?.isVisible ?? false
        if isVisible {
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

    // MARK: - Playlist sync helper

    private func syncPlaylistPanel() {
        guard let panel = playlistPanel else { return }
        panel.tracks = playlistManager.tracks.map { t in
            PlaylistTrack(
                title: t.displayTitle,
                duration: t.duration > 0 && t.duration.isFinite ? t.duration : Double.nan,
                isMissing: t.isMissingFile
            )
        }
        panel.currentIndex = playlistManager.currentIndex
        panel.reloadData()
    }
}

// MARK: - Phase 8.1: Transport Button Handlers

extension AppDelegate {

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

    func handlePlayPauseButton() {
        guard let handle = manzoHandle else {
            openFilePicker()
            return
        }
        let state = manzo_get_state(handle)
        if state == MANZO_STATE_PLAYING {
            manzo_pause(handle)
            analyzerView?.isPlaying = false
            NSLog("MANZO Phase 8.1: handlePlayPauseButton — was PLAYING, now paused")
        } else {
            manzo_play(handle)
            analyzerView?.isPlaying = true
            NSLog("MANZO Phase 8.1: handlePlayPauseButton — was PAUSED/STOPPED, now playing")
        }
    }
}

// MARK: - Phase 10.1: YouTube Streaming

extension AppDelegate {

    func stripBinaryQuarantines() {
        let key = "binary_quarantine_stripped_v2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let base = Bundle.main.bundlePath + "/Contents/MacOS/"
        for bin in ["yt-dlp", "ffmpeg"] {
            Process.launchedProcess(launchPath: "/usr/bin/xattr",
                arguments: ["-d", "com.apple.quarantine", base + bin])
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    func playYouTubeURL(_ youtubeURL: String) {
        let ytdlpPath = Bundle.main.bundlePath + "/Contents/MacOS/yt-dlp"
        NSLog("MANZO: resolving stream via manzo_open_url — %@", youtubeURL)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let newHandle = youtubeURL.withCString { urlPtr in
                ytdlpPath.withCString { ytPtr in
                    manzo_open_url(urlPtr, ytPtr)
                }
            }
            guard let newHandle else {
                NSLog("MANZO: manzo_open_url returned null for %@", youtubeURL)
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let old = self.manzoHandle {
                    self.analyzerView?.manzoHandle = nil
                    manzo_stop(old)
                    manzo_close(old)
                    self.manzoHandle = nil
                }
                self.manzoHandle = newHandle
                manzo_play(newHandle)
                self.analyzerView?.manzoHandle = newHandle
                self.analyzerView?.isPlaying = true
                self.marqueeView?.text = "★ YouTube Stream     "
                self.specsLabel?.stringValue = "Stream · 44 kHz"
                self.statusbarView?.setStatus("▶ Playing")
                if self.pollTimer == nil {
                    self.pollTimer = Timer.scheduledTimer(
                        timeInterval: 0.1, target: self,
                        selector: #selector(self.pollPlaybackState),
                        userInfo: nil, repeats: true)
                }
                NSLog("MANZO: YouTube stream live via manzo_open_url")
            }
        }
    }
}

// MARK: - Phase 8: Track Operations

extension AppDelegate {

    func removeTrackAt(_ index: Int) {
        let wasCurrentTrack = (index == playlistManager.currentIndex)
        playlistManager.remove(at: index)
        syncPlaylistPanel()

        if wasCurrentTrack {
            if let nextTrack = playlistManager.trackAt(playlistManager.currentIndex),
               FileManager.default.fileExists(atPath: nextTrack.path) {
                jumpToTrack(at: playlistManager.currentIndex)
            } else {
                if let handle = manzoHandle {
                    analyzerView?.manzoHandle = nil
                    manzo_close(handle)
                    manzoHandle = nil
                }
                pollTimer?.invalidate()
                pollTimer = nil
            }
        }
        NSLog("MANZO Phase 8: removeTrackAt — index=%d, wasCurrentTrack=%d, total=%d",
              index, wasCurrentTrack ? 1 : 0, playlistManager.tracks.count)
    }

    func jumpToTrack(at index: Int) {
        guard let track = playlistManager.trackAt(index) else { return }

        if let handle = manzoHandle {
            analyzerView?.manzoHandle = nil
            manzo_stop(handle)
            manzo_close(handle)
            manzoHandle = nil
        }

        playlistManager.currentIndex = index
        guard FileManager.default.fileExists(atPath: track.path) else {
            NSLog("MANZO Phase 8: jumpToTrack — file missing at %@", track.path)
            syncPlaylistPanel()
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

        syncPlaylistPanel()
        NSLog("MANZO Phase 8: jumpToTrack — index=%d, path=%@", index, track.path)
    }
}
