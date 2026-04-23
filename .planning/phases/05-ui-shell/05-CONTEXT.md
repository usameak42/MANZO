# Phase 5: UI Shell - Context

**Gathered:** 2026-04-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the frameless NSWindow shell: a 275×116 pt rectangular window with a single-root
`.behindWindow` vibrancy view, three named structural subviews, a custom drag region, and
persistent window position/size via UserDefaults.

Pure Swift/AppKit phase — no Rust changes, no DSP, no visual decoration. All three structural
NSViews (`titleView`, `bodyView`, `statusView`) are empty and unstyled; Phase 6 adds the
Neo-Aero CAGradientLayer stack on top of this hierarchy.

**In scope:**
- NSWindow subclass (frameless, fixed 275×116 pt, macOS 26+)
- Single root `NSVisualEffectView` with `ManzoGlassMaterial` blending `.behindWindow`
- Three named structural NSViews: `titleView` (275×14), `bodyView` (275×88), `statusView` (275×14)
- `mouseDown` drag via `window.performDrag(with:)`
- Window frame persistence via UserDefaults (position + size saved on move/resize, restored on launch)

**Out of scope:**
- Any visual decoration, gradients, or color — Phase 6
- Spectrum analyzer MTKView — Phase 7
- Playlist / library UI — Phase 8
- EQ slider controls — Phase 8
- Transport buttons — Phase 6+

</domain>

<decisions>
## Implementation Decisions

### Liquid Glass Material
- **D-01:** Define a named constant `ManzoGlassMaterial` for the macOS 26 Liquid Glass
  `NSVisualEffectView.Material` case. The material name is unconfirmed until the macOS 26 SDK
  is in hand — a named constant means it is updated in exactly one place when confirmed.
- **D-02:** macOS 26 is the minimum deployment target for this phase. No `#available` fallback
  to macOS 15 Sequoia — the project is developed and shipped on macOS 26. Document this
  requirement clearly in code comments.

### Window Configuration
- **D-03:** Window dimensions: **275×116 pt**, matching classic Winamp exactly.
  Fixed size — no `.resizable` in `styleMask`. `styleMask = [.borderless]`.
- **D-04:** `isOpaque = false` and `backgroundColor = .clear` set **before** `orderFront` —
  changing after `orderFront` causes a compositor hiccup (spike 006 landmine).
- **D-05:** `hasShadow = true`. `collectionBehavior = [.canJoinAllSpaces, .stationary]`
  to opt out of Stage Manager grouping.
- **D-06:** NSWindow subclass must override `canBecomeKey` → `true` and `canBecomeMain` → `true`;
  `.borderless` windows do not receive keyboard events without these overrides (spike 006 landmine).

### Root Vibrancy View
- **D-07:** The window's `contentView` is an `NSVisualEffectView` subclass (e.g. `ManzoRootView`)
  with `material = ManzoGlassMaterial`, `blendingMode = .behindWindow`, `state = .active`.
  `wantsLayer = true`, `layer?.cornerRadius = 0` (rectangular). This is the **only**
  `NSVisualEffectView` in the window — no nested `.behindWindow` views ever (spike 007 constraint).

### Panel Structure
- **D-08:** Phase 5 creates three named structural `NSView` subviews directly inside the root view:
  - `titleView`  — 275×14 pt, anchored to top
  - `bodyView`   — 275×88 pt, fills middle
  - `statusView` — 275×14 pt, anchored to bottom
- **D-09:** All three views: `wantsLayer = true`, `isOpaque = false`. Their backing `CALayer` is
  a plain `CALayer()` — no `CAGradientLayer` or special type. This makes Phase 6 layer insertion
  clean: Phase 6 adds `CAGradientLayer` sublayers into each view's existing `layer` without any
  view hierarchy restructuring.
- **D-10:** Views are laid out with Auto Layout constraints pinned to the root view edges.
  No frame-based layout — `translatesAutoresizingMaskIntoConstraints = false` on all three.

### Drag Region
- **D-11:** Override `mouseDown(with:)` in `ManzoRootView`. Call `window?.performDrag(with: event)`.
  This makes the entire window chrome draggable from any unoccupied pixel — matching Winamp's
  full-`HTCLIENT` pattern (confirmed from `main_nonclient.cpp`: `return HTCLIENT` for all pixels).
  Interactive controls added in later phases consume `mouseDown` in their own subviews first,
  so drag naturally falls through to chrome-only areas.

### Window Persistence
- **D-12:** Save window frame to `UserDefaults` using `window.setFrameAutosaveName("ManzoMainWindow")`.
  AppKit's built-in frame autosave handles both save (on move/resize) and restore (on launch)
  automatically with a single call — no manual `NotificationCenter` observation needed.

### Claude's Discretion
- Whether `ManzoRootView` is a standalone Swift file or nested in `ManzoWindow.swift`
- Whether `ManzoWindow` (NSWindow subclass) is wired in `AppDelegate.applicationDidFinishLaunching`
  or via a separate `ManzoWindowController`
- Exact AutoLayout constraint syntax (NSLayoutConstraint API vs `NSLayoutAnchor`)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Spike Findings (primary implementation reference)
- `.claude/skills/spike-findings-MANZO/references/window-glass-architecture.md` — Frameless
  window setup, Liquid Glass access, glass-on-glass one-`behindWindow` rule, landmines
  (isOpaque timing, canBecomeKey override, Stage Manager). Read all sections.

### Winamp Source (layout reference)
- `Winamp/Src/winamp/Main.h:71-72` — `WINDOW_WIDTH 275`, `WINDOW_HEIGHT 116` — canonical dims
- `Winamp/Src/winamp/draw_main.cpp:draw_tbar()` — title bar = 14 px (`update_area(0,0,275,14)`)
- `Winamp/Src/winamp/main_nonclient.cpp:Main_OnNCHitTest()` — full `HTCLIENT` drag pattern

### Project Planning
- `.planning/REQUIREMENTS.md` — SHELL-01 through SHELL-05
- `.planning/ROADMAP.md` — Phase 5 success criteria (5 items)
- `.planning/PROJECT.md` — one `.behindWindow` constraint, `isOpaque = false` constraint,
  P3 colors for Phase 6+ (not yet needed in Phase 5)

### Prior Phase Context
- `.planning/phases/04-dsp-engine/04-CONTEXT.md` — no UI decisions carry into Phase 5;
  audio pipeline is untouched in this phase

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ManzoApp/ManzoApp/main.swift` — Bare `NSApplication.shared` + `AppDelegate()` + `app.run()`.
  Phase 5 wires the window here or via AppDelegate; no scaffolding to remove.
- `ManzoApp/ManzoApp/AppDelegate.swift` — `applicationDidFinishLaunching` currently opens
  audio and starts playback. Phase 5 adds window setup here (or delegates to `ManzoWindowController`).
  `applicationShouldTerminateAfterLastWindowClosed` already returns `true` — correct behavior retained.

### Established Patterns
- `NSLog(...)` for all diagnostic output — consistent with Phases 1–4
- `Int32` return codes from FFI; Swift side checks `== 0` for success — not relevant to Phase 5
  but established convention for any new FFI calls
- No existing window, no NSViewController, no NIB/storyboard — build entirely in code

### Integration Points
- `AppDelegate.applicationDidFinishLaunching`: window setup runs here (or via a controller it owns)
- `AppDelegate.applicationWillTerminate`: poll timer and handle cleanup already present;
  window teardown is implicit (OS closes window when app terminates)
- Xcode project is `project.yml` (xcodegen) — new Swift files must be listed there

</code_context>

<specifics>
## Specific Ideas

- Winamp title bar height is exactly 14 px — use this as `titleView` height constant:
  `private let kTitleBarHeight: CGFloat = 14`
- Winamp status bar height is also 14 px (symmetric with title bar); body = 116 − 14 − 14 = 88 pt
- `window.setFrameAutosaveName("ManzoMainWindow")` — single call handles full UserDefaults
  persistence; no manual save/restore needed
- Phase 6 note: `titleView.layer`, `bodyView.layer`, and `statusView.layer` are the insertion
  points for CAGradientLayer sublayers. Do NOT add `sublayers` in Phase 5 — leave them empty.

</specifics>

<deferred>
## Deferred Ideas

- `.withinWindow` NSVisualEffectView for dropdown menus / tooltips — Phase 6+ when UI controls exist
- Corner radius on root view (e.g. 8–12 pt rounded corners) — deferred to Phase 6 alongside
  the Neo-Aero visual pass; Phase 5 is `cornerRadius = 0`
- Double-size (2×) mode — deferred; Winamp supported `config_dsize` to double all dimensions;
  Phase 5 hardcodes 275×116

</deferred>

---

*Phase: 05-ui-shell*
*Context gathered: 2026-04-23*
