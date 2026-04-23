# Phase 5: UI Shell - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-23
**Phase:** 05-ui-shell
**Areas discussed:** Liquid Glass strategy, Window dimensions/shape, Panel structure, Drag region

---

## Pre-discussion: Winamp Source Archaeology

User requested a read of `/Users/usameak42/Coding/MANZO/Winamp/Src/` before answering
dimension and shape questions. Key findings surfaced:
- `Main.h`: `WINDOW_WIDTH 275`, `WINDOW_HEIGHT 116`
- `draw_main.cpp:draw_tbar()`: title bar = 14 px
- `main_nonclient.cpp`: returns `HTCLIENT` for entire window (full-chrome drag pattern)
- `Set.cpp`: non-rectangular shapes come from skin `region.txt` polygon — not hardcoded in core
- **Conclusion:** organic shape is a skin community convention, not in core source.
  User then decided: **rectangle, classic Winamp 275×116**.

---

## Liquid Glass Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Prototype on day one | 30-min Xcode experiment to confirm AppKit material name | |
| Use a named constant | `ManzoGlassMaterial` constant — update in one place when SDK confirms name | ✓ |
| SwiftUI glassEffect() primary | NSHostingView + SwiftUI .glassEffect() — avoids AppKit name problem | |

**User's choice:** Named constant (`ManzoGlassMaterial`)
**Notes:** Easy to update once macOS 26 SDK is in hand; no SwiftUI dependency.

---

## Sequoia Fallback

| Option | Description | Selected |
|--------|-------------|----------|
| .hudWindow | Dark frosted glass — closest visual match on macOS 15 | |
| .popover | Lighter translucent panel | |
| macOS 26 only — no fallback | No #available gate; target macOS 26 from day one | ✓ |

**User's choice:** macOS 26 only
**Notes:** Developing on macOS 26; no need for graceful degradation.

---

## Window Dimensions & Shape

| Option | Description | Selected |
|--------|-------------|----------|
| Organic/rounded (oval/teardrop) | CAShapeLayer bezier path mask — Frutiger Aero style | |
| Winamp-exact 275×116 rectangle | Classic dimensions, no shape mask | ✓ |
| 2× scaled 550×232 | Modern density | |
| Modern 360×180 | Compromise | |

**User's choice:** Rectangle, 275×116 pt — classic Winamp
**Notes:** User initially asked about organic/teardrop shape; after reviewing Winamp source
(which showed organic shape is a skin artifact, not core code), decided to go with canonical
rectangle. No `CAShapeLayer` mask needed.

---

## Panel Structure

| Option | Description | Selected |
|--------|-------------|----------|
| Blank canvas only | Root NSVisualEffectView only; no subviews in Phase 5 | |
| Named region NSViews, no styling | titleView (275×14), bodyView (275×88), statusView (275×14) | ✓ |

**User's choice:** Named region NSViews
**Notes:** User added clarification: all three views must be structured so Phase 6 can insert
CAGradientLayer Neo-Aero stack without restructuring the NSView hierarchy. Implementation
implication: `wantsLayer = true`, `isOpaque = false`, plain `CALayer()` backing on all three
views from Phase 5 day one.

---

## Drag Region

| Option | Description | Selected |
|--------|-------------|----------|
| mouseDown on root view | Override in ManzoRootView → window.performDrag(with: event) | ✓ |
| Dedicated drag strip NSView | Transparent DragView over 275×14 title strip only | |
| isMovableByWindowBackground = true | Single AppKit property; less control | |

**User's choice:** mouseDown on root view
**Notes:** Mirrors Winamp's full-HTCLIENT pattern exactly. Controls added in later phases
consume mouseDown in their own subviews first; chrome drag is the natural fallback.

---

## Claude's Discretion

- Whether `ManzoRootView` is standalone or nested in `ManzoWindow.swift`
- Whether window is wired in `AppDelegate` or via `ManzoWindowController`
- Auto Layout constraint syntax choice

## Deferred Ideas

- Organic/teardrop shape — considered and ruled out (not in Winamp core source; would require new design work)
- Corner radius (8–12 pt rounded) — deferred to Phase 6 alongside Neo-Aero visual pass
- Double-size (2×) mode — deferred (Winamp had `config_dsize`; not needed for v1)
- `.withinWindow` vibrancy for dropdowns — deferred to Phase 6+ when controls exist
