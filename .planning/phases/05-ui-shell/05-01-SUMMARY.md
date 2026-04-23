---
phase: 05-ui-shell
plan: 01
subsystem: ui
tags: [swift, appkit, nswindow, nsvisualeffectview, calayer, autolayout, vibrancy, liquid-glass]

# Dependency graph
requires:
  - phase: 04-dsp-engine
    provides: Audio pipeline and FFI bridge remain untouched; Phase 5 is pure Swift/AppKit

provides:
  - ManzoWindow NSWindow subclass — borderless 275x116pt, canBecomeKey/canBecomeMain, isOpaque=false pre-orderFront
  - ManzoRootView NSVisualEffectView subclass — single behindWindow vibrancy root, three plain-NSView panels with Auto Layout, mouseDown drag
  - ManzoGlassMaterial named constant — single update site for macOS 26 SDK Liquid Glass material case name

affects:
  - 05-02 (AppDelegate wiring — consumes ManzoWindow and ManzoRootView)
  - 06-neo-aero-visual-stack (Phase 6 inserts CAGradientLayer sublayers into titleView.layer, bodyView.layer, statusView.layer)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - NSWindow subclass with borderless styleMask and mandatory canBecomeKey/canBecomeMain overrides
    - Single-root NSVisualEffectView with behindWindow blending; all inner panels are plain NSView
    - Auto Layout via NSLayoutAnchor (not frame-based); 12 constraints for 3 panels summing to 116pt
    - ManzoGlassMaterial named constant pattern for unconfirmed macOS 26 API name
    - mouseDown override delegating to window?.performDrag(with:) for full-chrome drag

key-files:
  created:
    - ManzoApp/ManzoApp/ManzoWindow.swift
    - ManzoApp/ManzoApp/ManzoRootView.swift
  modified: []

key-decisions:
  - "ManzoGlassMaterial uses .hudWindow placeholder — update to confirmed .glass case name on macOS 26 SDK receipt (D-01)"
  - "isOpaque=false and backgroundColor=.clear set inside ManzoWindow.init() body, before any orderFront call — compositor landmine avoidance (D-04/spike 006)"
  - "Three inner panels are NSView (not NSVisualEffectView) — one-per-window behindWindow rule enforced per spike 007"
  - "bodyView has no explicit heightAnchor — fills remaining space between titleView.bottom and statusView.top (Auto Layout fills 88pt)"

patterns-established:
  - "NSWindow subclass: styleMask=[.borderless], override canBecomeKey/canBecomeMain returning true"
  - "NSVisualEffectView root: blendingMode=.behindWindow, state=.active, single instance only"
  - "Panel NSViews: wantsLayer=true, isOpaque=false, translatesAutoresizingMaskIntoConstraints=false"
  - "mouseDown drag: override calls window?.performDrag(with:) — no super.mouseDown, no exclusion zones"
  - "Named material constant: private let ManzoGlassMaterial: NSVisualEffectView.Material — one update site"

requirements-completed: [SHELL-01, SHELL-02, SHELL-03, SHELL-04]

# Metrics
duration: 1min
completed: 2026-04-23
---

# Phase 5 Plan 01: UI Shell Summary

**Frameless 275x116pt NSWindow subclass and single-root NSVisualEffectView with three Auto Layout panel NSViews and full-chrome mouseDown drag — implementing all spike 006/007 landmine avoidances**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-23T20:32:12Z
- **Completed:** 2026-04-23T20:33:53Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- ManzoWindow: borderless 275x116pt NSWindow with canBecomeKey/canBecomeMain overrides (keyboard event fix), isOpaque=false/backgroundColor=.clear set before orderFront (compositor landmine avoided), hasShadow=true, collectionBehavior=[.canJoinAllSpaces,.stationary]
- ManzoRootView: single-root NSVisualEffectView with behindWindow blending and ManzoGlassMaterial named constant; three plain-NSView panels (titleView 14pt top, bodyView 88pt middle, statusView 14pt bottom) constrained via 12 NSLayoutAnchor constraints summing to exactly 116pt
- mouseDown override delegates to window?.performDrag(with:) — full-chrome drag matching Winamp's HTCLIENT pattern; no super.mouseDown, no hit-test exclusion zones

## Task Commits

Each task was committed atomically:

1. **Task 1: Create ManzoWindow.swift — NSWindow subclass** - `53db27c` (feat)
2. **Task 2: Create ManzoRootView.swift — NSVisualEffectView subclass** - `41bd845` (feat)

**Plan metadata:** (committed after summary creation)

## Files Created/Modified

- `ManzoApp/ManzoApp/ManzoWindow.swift` — NSWindow subclass; borderless styleMask, canBecomeKey/canBecomeMain overrides, kWindowWidth/kWindowHeight constants, isOpaque=false pre-orderFront
- `ManzoApp/ManzoApp/ManzoRootView.swift` — NSVisualEffectView subclass; ManzoGlassMaterial constant, behindWindow blending, three panel NSViews with Auto Layout, mouseDown drag handler

## Decisions Made

- ManzoGlassMaterial uses `.hudWindow` as the placeholder material. The macOS 26 SDK Liquid Glass API name is unconfirmed at planning time. A named constant at file scope means only one edit needed when confirmed.
- `isOpaque = false` and `backgroundColor = .clear` are set inside `ManzoWindow.init()` body immediately after `super.init()` — this avoids the spike 006 compositor hiccup that occurs if these are changed after `orderFront`.
- `bodyView` has no explicit `heightAnchor.constraint` — its height is derived from top=titleView.bottom and bottom=statusView.top. This is the correct approach: the middle panel fills remaining space, and Auto Layout enforces the 88pt geometry implicitly.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## Known Stubs

- `ManzoGlassMaterial` uses `.hudWindow` as a placeholder for the unconfirmed macOS 26 Liquid Glass `NSVisualEffectView.Material` case. The window renders with an existing AppKit material (hudWindow) until the macOS 26 SDK arrives and the correct case name (expected `.glass` or similar) is confirmed. Update the single constant at line 27 of ManzoRootView.swift. This is intentional — not a bug.

## Threat Flags

No new security-relevant surface introduced beyond what the plan's threat model documented. ManzoRootView.mouseDown uses standard AppKit performDrag API (T-05-01: accepted). ManzoGlassMaterial placeholder causes no crash (T-05-02: accepted). NSLog output contains no PII (T-05-03: accepted).

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- ManzoWindow and ManzoRootView are ready for Plan 02 (AppDelegate wiring): instantiate ManzoWindow, set contentView to ManzoRootView(frame:), call setFrameAutosaveName("ManzoMainWindow"), center(), orderFront(nil)
- Phase 6 (Neo-Aero Visual Stack) can insert CAGradientLayer sublayers directly into titleView.layer, bodyView.layer, statusView.layer — layer trees are empty and layer type is plain CALayer
- xcodegen sources glob (`path: ManzoApp`, excludes: `*.yml`) auto-includes both new Swift files — no project.yml edit required

## Self-Check

Files exist:
- `ManzoApp/ManzoApp/ManzoWindow.swift`: FOUND
- `ManzoApp/ManzoApp/ManzoRootView.swift`: FOUND

Commits exist:
- `53db27c` (ManzoWindow): FOUND
- `41bd845` (ManzoRootView): FOUND

## Self-Check: PASSED

---
*Phase: 05-ui-shell*
*Completed: 2026-04-23*
