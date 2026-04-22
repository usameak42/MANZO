# Window & Glass Architecture

Validated patterns for the frameless NSWindow + Liquid Glass foundation on macOS Sequoia+/26.

## Validated Patterns

### Frameless Window Setup (Spike 006)
```swift
// NSWindow subclass — required overrides
override var canBecomeKey:  Bool { true }   // mandatory for .borderless
override var canBecomeMain: Bool { true }

// Window configuration
window.styleMask       = [.borderless, .resizable]
window.isOpaque        = false              // MUST be set before orderFront
window.backgroundColor = .clear
window.hasShadow       = true
window.collectionBehavior = [.canJoinAllSpaces, .stationary]  // avoid Stage Manager

// Root content view = NSVisualEffectView
let root = NSVisualEffectView()
root.material      = /* macOS 26 glass material — see Liquid Glass section */
root.blendingMode  = .behindWindow          // ONE per window, at root only
root.state         = .active
root.wantsLayer    = true
root.layer?.cornerRadius = 16
window.contentView = root
```
`isOpaque = false` **must** be set before the window becomes visible — changing it after `orderFront` causes a compositor hiccup on some GPU drivers.

### Liquid Glass — AppKit Access (Spike 005)
⚠ **PARTIAL — requires SDK prototype before implementation.**
- AppKit will have access (not SwiftUI-only) — confirmed direction
- Exact `NSVisualEffectView.Material` case name for macOS 26 unconfirmed; likely `.glass` or similar
- SwiftUI path (high confidence): `.glassEffect()` modifier on macOS 26+
- **Day-one action**: 30-min Xcode prototype on macOS 26 SDK to confirm AppKit material name
- Fallback: `NSHostingView` wrapping SwiftUI `.glassEffect()` embedded in AppKit hierarchy
- Availability gate: `#available(macOS 26, *)` with fallback to `.hudWindow` / `.popover` on macOS 15

### Glass-on-Glass Rule (Spike 007) ⭐ Critical Architecture Decision
**One `.behindWindow` NSVisualEffectView per window. All inner panels use CALayer only.**

```
Window root: NSVisualEffectView, .behindWindow  ← only one
│   → desktop refraction lives here
│
├── Inner panel (EQ, Playlist, etc.)
│   → NSView, wantsLayer = true
│   → CALayer-only, NO nested NSVisualEffectView
│   → semi-transparent base layer (teal, alpha ≈ 0.35-0.4)
│   → shows through to glass window body = glass-on-glass appearance
│
└── Transient overlays (menus, tooltips)
    → NSVisualEffectView, .withinWindow  ← safe to nest; blurs window content, not desktop
```

Reason: nesting two `.behindWindow` views → double-blur artifacts (milky/washed-out). The inner panels *appear* as glass because they are semi-transparent over the glass window body — no second blur needed.

### `.withinWindow` for Transient Overlays (Spike 007)
```swift
let menuBlur = NSVisualEffectView()
menuBlur.material     = .popover
menuBlur.blendingMode = .withinWindow  // blurs window content, not desktop — safe to nest
menuBlur.state        = .active
```
Safe for dropdowns, tooltips, info panels that need frosted background over app content.

## Landmines

- **Two `.behindWindow` views in one window = instant artifact.** The second one captures the already-blurred first layer, producing a white/grey mush. Always check the full view hierarchy before adding any NSVisualEffectView.
- **`isOpaque = true` breaks all Liquid Glass.** The window server skips compositing and blits directly — no behind-window buffer is captured. This is a silent failure (no crash, just no glass effect).
- **Stage Manager on Sequoia+** may impose corner radius / frame decoration on `.managed` windows. Use `.stationary` collection behavior to opt out.
- **`canBecomeKey` must be overridden** on `.borderless` windows — without it, the window won't receive keyboard events. This is a common gotcha that causes puzzling input failures.
- **`layer.cornerRadius` on the content view**, not `window.contentView?.layer?.cornerRadius` via the window — use the view's own layer directly on borderless windows.

## Constraints

- macOS 26+ required for Liquid Glass material; must degrade gracefully on macOS 15 (Sequoia)
- `isOpaque = false` is mandatory, not optional, for any behind-window vibrancy
- Maximum one `.behindWindow` NSVisualEffectView per NSWindow
- `.stationary` collection behavior: window won't participate in Stage Manager grouping — acceptable for a music player

## Origin
Synthesized from spikes: 005, 006, 007
Source files: `sources/005-liquid-glass-appkit-access/`, `sources/006-frameless-plus-liquid-glass/`, `sources/007-glass-on-glass-compositing/`
