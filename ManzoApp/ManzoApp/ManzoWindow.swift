import AppKit

// ManzoWindow: frameless NSWindow for MANZO — 275×116 pt, no system chrome.
//
// Minimum deployment: macOS 26. No #available fallback to macOS 15.
// The window uses .borderless style mask; AppKit requires canBecomeKey and
// canBecomeMain overrides for .borderless windows to receive keyboard events
// (spike 006 landmine — without these, keyboard input is silently dropped).
//
// Window dimensions match classic Winamp exactly:
//   WINDOW_WIDTH  275 — Winamp/Src/winamp/Main.h:71
//   WINDOW_HEIGHT 116 — Winamp/Src/winamp/Main.h:72

private let kWindowWidth:  CGFloat = 275
private let kWindowHeight: CGFloat = 116

class ManzoWindow: NSWindow {

    // D-06 (spike 006): mandatory overrides — .borderless windows silently drop
    // keyboard events without these. No override = no keyboard input, no crash.
    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { true }

    // Designated initializer — called from AppDelegate.applicationDidFinishLaunching.
    // D-03: styleMask = [.borderless] — no title bar, no traffic-light buttons, fixed size.
    // D-04: isOpaque and backgroundColor are set immediately in body — they MUST be set
    //        before the window is shown via orderFront (compositor landmine, spike 006).
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: kWindowWidth, height: kWindowHeight),
            styleMask:   [.borderless],
            backing:     .buffered,
            defer:       false
        )

        // D-04: set before orderFront — changing after orderFront causes compositor hiccup.
        isOpaque        = false
        backgroundColor = .clear

        // D-05: shadow and Stage Manager opt-out.
        hasShadow         = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        NSLog("MANZO Phase 5: ManzoWindow initialized — 275×116 pt borderless")
    }
}
