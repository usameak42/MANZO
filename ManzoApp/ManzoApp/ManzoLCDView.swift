import AppKit

// ManzoLCDView — Winamp-style LCD information display panel.
// Renders five CATextLayer fields on a P3 pure-black background.
// All colors are P3 wide-gamut (CLAUDE.md constraint — no sRGB).
// CALayer-only — no nested NSVisualEffectView (spike 007 rule).
// Frame: x=0, y=14, width=275, height=43 (placed by ManzoRootView in Wave 2).
final class ManzoLCDView: NSView {

    // MARK: - State

    /// True when the time display shows remaining time instead of elapsed.
    /// Toggled by mouseDown in the timeLayer area.
    var isShowingRemaining: Bool = false

    /// Current scroll offset in pts (shifted left each poll tick).
    private var titleScrollOffset: CGFloat = 0

    /// Full title string with " *** " spacer appended for seamless looping (D-05).
    private var titleText: String = ""

    /// Track duration in seconds — set by updateTrack(title:bitrate:kHz:stereo:duration:).
    private var trackDuration: Double = 0

    // MARK: - Layers

    private let titleLayer    = CATextLayer()
    private let timeLayer     = CATextLayer()
    private let bitrateLayer  = CATextLayer()
    private let kHzLayer      = CATextLayer()
    private let stereoLayer   = CATextLayer()

    // MARK: - P3 Color Space

    private let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setupBackground()
        setupTextLayers()
        setupTrackingArea()
        NSLog("MANZO Phase 8.1: ManzoLCDView.init — 275×43pt LCD view created")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used — code-only UI") }

    // MARK: - Setup

    private func setupBackground() {
        layer?.backgroundColor = CGColor(colorSpace: p3, components: [0.0, 0.0, 0.0, 1.0])!
    }

    private func setupTextLayers() {
        let lcdGreen = CGColor(colorSpace: p3, components: [0.18, 0.82, 0.18, 1.0])!

        // Configure all five CATextLayer fields.
        // Frames are set in layout() after bounds are known — NOT here.
        // shouldRasterize = false on all: these layers update on every poll tick (100ms).

        // titleLayer — scrolling song title
        titleLayer.contentsScale    = 2.0
        titleLayer.foregroundColor  = lcdGreen
        titleLayer.alignmentMode    = .left
        titleLayer.truncationMode   = .end
        titleLayer.shouldRasterize  = false
        titleLayer.font             = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular) as CTFont
        titleLayer.fontSize         = 8
        titleLayer.string           = ""
        layer?.addSublayer(titleLayer)

        // timeLayer — elapsed or remaining time digits
        timeLayer.contentsScale    = 2.0
        timeLayer.foregroundColor  = lcdGreen
        timeLayer.alignmentMode    = .left
        timeLayer.shouldRasterize  = false
        timeLayer.font             = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium) as CTFont
        timeLayer.fontSize         = 8
        timeLayer.string           = "0:00"
        layer?.addSublayer(timeLayer)

        // bitrateLayer — bitrate in kbps (e.g. "128")
        bitrateLayer.contentsScale    = 2.0
        bitrateLayer.foregroundColor  = lcdGreen
        bitrateLayer.alignmentMode    = .left
        bitrateLayer.shouldRasterize  = false
        bitrateLayer.font             = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium) as CTFont
        bitrateLayer.fontSize         = 8
        bitrateLayer.string           = "---"
        layer?.addSublayer(bitrateLayer)

        // kHzLayer — sample rate in kHz (e.g. "44")
        kHzLayer.contentsScale    = 2.0
        kHzLayer.foregroundColor  = lcdGreen
        kHzLayer.alignmentMode    = .left
        kHzLayer.shouldRasterize  = false
        kHzLayer.font             = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium) as CTFont
        kHzLayer.fontSize         = 8
        kHzLayer.string           = "--"
        layer?.addSublayer(kHzLayer)

        // stereoLayer — "STEREO" / "MONO" / ""
        stereoLayer.contentsScale    = 2.0
        stereoLayer.foregroundColor  = lcdGreen
        stereoLayer.alignmentMode    = .left
        stereoLayer.shouldRasterize  = false
        stereoLayer.font             = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium) as CTFont
        stereoLayer.fontSize         = 8
        stereoLayer.string           = ""
        layer?.addSublayer(stereoLayer)
    }

    /// NSTrackingArea over the timeLayer area for the elapsed/remaining toggle (D-06).
    private func setupTrackingArea() {
        // timeLayer view-local rect: x=36, y=12, width=64, height=13
        let timeRect = CGRect(x: 36, y: 12, width: 64, height: 13)
        let area = NSTrackingArea(
            rect: timeRect,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        // All layer frames use view-local coordinates.
        // Winamp window-absolute y values converted: subtract 14 (titleView height).
        // titleLayer: window y=25 → view y=11
        titleLayer.frame   = CGRect(x: 111, y: 11, width: 154, height: 10)
        // timeLayer: window y=26 → view y=12
        timeLayer.frame    = CGRect(x: 36,  y: 12, width: 64,  height: 13)
        // bitrateLayer: window y=43 → view y=29
        bitrateLayer.frame = CGRect(x: 111, y: 29, width: 45,  height:  6)
        // kHzLayer: window y=43 → view y=29
        kHzLayer.frame     = CGRect(x: 156, y: 29, width: 20,  height:  6)
        // stereoLayer: window y=41 → view y=27
        stereoLayer.frame  = CGRect(x: 212, y: 27, width: 56,  height: 12)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let timeRect = CGRect(x: 36, y: 12, width: 64, height: 13)
        if timeRect.contains(loc) {
            isShowingRemaining.toggle()
            NSLog("MANZO Phase 8.1: ManzoLCDView.mouseDown — isShowingRemaining=%d",
                  isShowingRemaining ? 1 : 0)
        }
    }

    // MARK: - Public API (called by AppDelegate.pollPlaybackState — D-12)

    /// Called by AppDelegate.pollPlaybackState() each 100ms tick.
    /// Updates timeLayer.string based on isShowingRemaining flag.
    func updateTime(position: Double, duration: Double) {
        let displayTime: Double
        let prefix: String
        if isShowingRemaining && duration > 0 {
            displayTime = duration - position
            prefix = "-"
        } else {
            displayTime = position
            prefix = ""
        }
        let minutes = Int(displayTime) / 60
        let seconds = Int(displayTime) % 60
        timeLayer.string = String(format: "%@%d:%02d", prefix, minutes, seconds)
    }

    /// Called by AppDelegate.pollPlaybackState() each 100ms tick.
    /// Scrolls titleLayer left by 0.5pt when title is wider than the 154pt display area (D-05).
    func tickTitleScroll() {
        guard !titleText.isEmpty else { return }
        // Approximate text width: 8pt mono ≈ 5pt per char at this size.
        // Only scroll when text would overflow the 154pt display area.
        let textWidth = CGFloat(titleText.count) * 5.0
        guard textWidth > 154 else { return }

        titleScrollOffset -= 0.5
        // When text has scrolled completely past the left edge, loop back to the right.
        if titleScrollOffset < -(textWidth + 20) {   // 20pt buffer past left edge
            titleScrollOffset = 154
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleLayer.frame = CGRect(x: 111 + titleScrollOffset, y: 11,
                                  width: titleLayer.frame.width, height: 10)
        CATransaction.commit()
    }

    /// Called by AppDelegate when a new track starts (jumpToTrack / pollPlaybackState).
    /// Resets scroll offset and updates all LCD fields.
    func updateTrack(title: String?, bitrate: Int, kHz: Int, stereo: Bool, duration: Double) {
        titleScrollOffset = 0
        trackDuration     = duration
        let displayTitle  = title ?? ""
        // Append " *** " spacer for seamless loop (D-05 / Winamp canonical separator).
        titleText         = displayTitle.isEmpty ? "" : displayTitle + " *** "
        titleLayer.string = titleText

        bitrateLayer.string = bitrate > 0 ? "\(bitrate)" : "---"
        kHzLayer.string     = kHz > 0    ? "\(kHz)"     : "--"
        stereoLayer.string  = stereo ? "STEREO" : (kHz > 0 ? "MONO" : "")

        // Reset titleLayer frame to base position (no scroll).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleLayer.frame = CGRect(x: 111, y: 11, width: 154, height: 10)
        CATransaction.commit()

        NSLog("MANZO Phase 8.1: ManzoLCDView.updateTrack — title=%@, bitrate=%dkbps, kHz=%d, stereo=%d",
              displayTitle, bitrate, kHz, stereo ? 1 : 0)
    }

    /// Clears all fields to empty/default state (no track loaded).
    func clearTrack() {
        titleText         = ""
        titleScrollOffset = 0
        trackDuration     = 0
        titleLayer.string   = ""
        timeLayer.string    = "0:00"
        bitrateLayer.string = "---"
        kHzLayer.string     = "--"
        stereoLayer.string  = ""
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        titleLayer.frame = CGRect(x: 111, y: 11, width: 154, height: 10)
        CATransaction.commit()
    }
}
