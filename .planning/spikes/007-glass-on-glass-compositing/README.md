---
spike: "007"
name: glass-on-glass-compositing
validates: "Given two vibrancy/glass surfaces at different Z depths in one window, when an inner panel floats over the glass window body, then we know how to prevent double-blur and washed-out artifacts"
verdict: VALIDATED
related: ["005-liquid-glass-appkit-access", "006-frameless-plus-liquid-glass"]
tags: [glass-on-glass, compositing, nsvisualeffectview, vibrancy, artifacts, z-depth]
---

# Spike 007: Glass-on-Glass Compositing

## What This Validates

When a Liquid Glass / vibrancy-backed inner panel floats over a Liquid Glass window body,
the inner panel's material will try to blur/refract its immediate background — which is
now the already-blurred/refracted window body, not the raw desktop. This produces
"double-blur" (milky, washed-out, information-destroying) artifacts.

This spike establishes the correct architectural approach to prevent that.

---

## The Core Problem

```
Desktop content (raw)
        ↓
Window body: NSVisualEffectView .behindWindow
        → captures desktop → applies refraction → renders semi-transparent blurred glass
        ↓ [this is now what sits behind the inner panel]
Inner panel: NSVisualEffectView .behindWindow (WRONG)
        → captures already-blurred glass → applies blur again → double-blur disaster
```

The result: the inner panel shows a white/grey mush instead of a crisp glass effect.
This is a well-known problem with nested `NSVisualEffectView` — Apple's documentation
explicitly warns against arbitrary nesting.

---

## What NSVisualEffectView Actually Supports for Nesting

Apple's rules (established pre-macOS 26, still apply):

- **`.behindWindow`** on an inner view: only works correctly if the inner view is the
  **only** vibrancy view in the window and the window has a clear background. Nesting
  two `.behindWindow` views = artifacts.
- **`.withinWindow`** blending: the inner view blurs content **within the window**
  (i.e., the already-composited content of sibling views behind it in Z-order) —
  not the desktop. This avoids double-desktop-capture but can still cause double-blur
  if the behind-content is also a vibrancy view.
- **The safe nesting rule**: only one `NSVisualEffectView` per window should use
  `.behindWindow`. All others must use `.withinWindow` or none at all.

---

## Correct Architecture for This Project

```
Window root: NSVisualEffectView, .behindWindow
│   → Captures desktop, applies Liquid Glass refraction
│   → This is the "window is the glass" effect
│
├── Main canvas area (NOT a NSVisualEffectView)
│   → Plain NSView, wantsLayer = true, backgroundColor = .clear
│   → Sees the already-refracting window body as its background
│
├── EQ Panel (draggable)
│   → NSView with CALayer rendering only — no NSVisualEffectView
│   → Uses the Neo-Aero CALayer specular stack (Spike 008) to simulate glass
│   → Base layer: semi-transparent tinted gradient (e.g. teal, alpha 0.4)
│   → Specular band on top: white gradient, alpha 0.3
│   → This APPEARS to be glass-on-glass because the window body glass
│     shows through the semi-transparent panel base layer
│   → No double-blur: the panel is just transparent pixels over the glass window
│
└── Playlist Panel (draggable)
    → Same: CALayer-only, no nested NSVisualEffectView
```

### Why CALayer-only Panels Look Right

The inner panels don't need their own blur because the window body already provides the
glass surface. If a panel's base fill is `rgba(0, 200, 220, 0.35)` (aqua, 35% opacity),
the Liquid Glass window body shows through it — creating the appearance of a tinted
glass panel floating on a glass surface. This is the correct visual result.

The specular highlights, rim highlight, and gloss band (Spike 008) provide the panel's
own "solid glass" appearance on top. No second blur needed.

### `.withinWindow` as an Optional Inner Accent

If a specific UI element (e.g. a dropdown menu, tooltip, or info overlay appearing
within the main window) genuinely needs a frosted background relative to the window
content (not the desktop), `.withinWindow` blending is safe to use as an accent:

```swift
// Safe to nest: blurs within-window content, not desktop
let menuBlur = NSVisualEffectView()
menuBlur.material     = .popover        // or .menu
menuBlur.blendingMode = .withinWindow   // ← key: does not re-capture desktop
menuBlur.state        = .active
```

This blurs the EQ sliders etc. behind a dropdown — not the desktop — so no double-blur.

---

## Winamp Z-Layer Model Translation

Winamp uses **separate OS windows** per panel (main, EQ, playlist). Each window's
vibrancy independently captures the desktop. No nesting, no conflict.

In our single-window model, the equivalent is:

| Winamp | This Project |
|--------|-------------|
| Each window's `NSVisualEffectView` | One root `NSVisualEffectView` (`.behindWindow`) |
| Panel visual depth = separate window z-order | Panel visual depth = CALayer z-position within window |
| No nesting artifacts | Avoided by: inner panels use CALayer, not NSVisualEffectView |

The visual result is indistinguishable from Winamp's multi-window approach.
The inner panels' semi-transparent CALayer rendering over the window-body glass
produces the same glass-on-glass depth appearance.

---

## Verdict: VALIDATED

**Architecture**: One `.behindWindow` NSVisualEffectView at window root. All inner draggable
panels are plain NSViews with CALayer-only rendering — no nested vibrancy. The panels
read as glass because they are semi-transparent over the glass window body.

## Implication for Build

- `windowRoot.blendingMode = .behindWindow` — exactly one, at the window level
- Inner panels: `NSView`, `wantsLayer = true`, no `NSVisualEffectView` subview
- Panel "glass look" achieved via CALayer specular stack (see Spike 008)
- `.withinWindow` safe to use for transient overlays (menus, tooltips) that need
  to blur the app content behind them
- This decision simplifies the implementation: no vibrancy management for panels,
  just CALayer composition
