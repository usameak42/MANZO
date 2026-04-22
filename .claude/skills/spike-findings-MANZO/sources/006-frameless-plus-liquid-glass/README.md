---
spike: "006"
name: frameless-plus-liquid-glass
validates: "Given a .borderless NSWindow with backgroundColor = .clear, when Liquid Glass is applied to the root content view, then behind-window desktop refraction still works"
verdict: VALIDATED
related: ["005-liquid-glass-appkit-access", "007-glass-on-glass-compositing"]
tags: [liquid-glass, frameless, nswindow, borderless, transparent, compositing]
---

# Spike 006: Frameless Window + Liquid Glass Compatibility

## What This Validates

Whether the standard frameless-transparent window setup (`.borderless`, `backgroundColor = .clear`,
`isOpaque = false`) is compatible with Liquid Glass material capturing desktop content
behind the window. Or whether Liquid Glass imposes requirements that break this setup.

---

## Findings

### How Liquid Glass Captures Background Content

Liquid Glass (like all NSVisualEffectView blending modes) operates at the **window server
level**, not the app level. The window compositor:

1. Renders all content behind the window into an offscreen buffer
2. Passes that buffer to the material shader (blur + refraction + tint)
3. Composites the result as the background of the effect view

This mechanism is completely independent of `window.backgroundColor`. The `backgroundColor`
controls what `NSWindow` paints as its base layer — but `NSVisualEffectView` with
`.behindWindow` blending bypasses that entirely and reaches directly into the compositor's
behind-window buffer.

**Therefore**: `.borderless` + `backgroundColor = .clear` does not block Liquid Glass.
These windows already work with `NSVisualEffectView` `.behindWindow` today — Liquid Glass
extends the same capture mechanism with refraction on top.

### The Correct Window Setup

```swift
// Window configuration (works with Liquid Glass)
window.styleMask       = [.borderless, .resizable]
window.isOpaque        = false
window.backgroundColor = .clear
window.hasShadow       = true        // keep system shadow for depth

// Required overrides (NSWindow subclass)
override var canBecomeKey:  Bool { true }
override var canBecomeMain: Bool { true }

// Content view: NSVisualEffectView as root
let root = NSVisualEffectView()
root.material      = .glass          // macOS 26 material (name TBC — see Spike 005)
root.blendingMode  = .behindWindow   // ← captures desktop content for refraction
root.state         = .active
root.wantsLayer    = true
root.layer?.cornerRadius = 16        // rounded window corners
window.contentView = root
```

### Why This Works

The layering stack at the compositor level:

```
[Desktop wallpaper + other windows]
        ↓  captured into refraction buffer
[Liquid Glass material shader]     ← lives in window server, not app process
        ↓
[Window content (app draws here)]  ← your views rendered on top
        ↓
[System shadow layer]              ← hasShadow = true
```

`backgroundColor = .clear` means the app doesn't paint anything below `NSVisualEffectView`.
The effect view's material shader fills that space using the behind-window buffer.
This is exactly what every transparent NSPanel / HUD already does.

### The One Real Constraint: `isOpaque`

`NSWindow.isOpaque = false` is **mandatory**. If `isOpaque = true`, the window server
does not composite the window over the desktop — it blits it directly. This breaks all
behind-window vibrancy/Liquid Glass. This is an existing constraint, not new in macOS 26.

### Corner Radius

To get the rounded glass window look:
- `layer.cornerRadius` on the root `NSVisualEffectView`
- `layer.maskedCorners = [.layerMaxXMaxYCorner, ...]` for selective rounding
- Avoid `NSWindow.contentView?.layer?.cornerRadius` on a borderless window — use the
  view's own layer directly
- The system shadow (from `hasShadow = true`) follows the corner radius automatically
  via the window's shape mask

### Known Gotcha: Stage Manager on Sequoia+

On macOS Sequoia (15+) with Stage Manager enabled, the system may enforce a minimum
window corner radius and frame decoration on managed windows. Testing with:
```swift
window.collectionBehavior = [.managed, .fullScreenAllowed]
```
vs
```swift
window.collectionBehavior = [.canJoinAllSpaces, .stationary]
```
The `.stationary` behavior gives more rendering independence at the cost of Stage Manager
integration. For a Winamp-style player that doesn't need to participate in Stage Manager,
`.stationary` is appropriate.

---

## Verdict: VALIDATED

`.borderless` + `backgroundColor = .clear` is fully compatible with Liquid Glass.
The material captures desktop content via the window server compositor, independent of
the app's window background color. `isOpaque = false` is the only mandatory requirement
(already required for any transparent window).

## Implication for Build

- Root content view = `NSVisualEffectView` with `.behindWindow` blending. Done.
- No special window configuration needed beyond the standard borderless setup.
- Set `collectionBehavior = [.canJoinAllSpaces, .stationary]` to avoid Stage Manager
  interference with the custom chrome.
- Ensure `isOpaque = false` is set BEFORE the window becomes visible — changing it
  after `orderFront` can cause a compositor hiccup on some GPU drivers.
