---
spike: "005"
name: liquid-glass-appkit-access
validates: "Given macOS 26 Liquid Glass, when applied to a custom AppKit NSView surface, then we know if AppKit gets native access or requires a SwiftUI hosting bridge"
verdict: PARTIAL
related: ["006-frameless-plus-liquid-glass", "007-glass-on-glass-compositing"]
tags: [liquid-glass, appkit, swiftui, macos-26, vibrancy]
---

# Spike 005: Liquid Glass — AppKit Access

## What This Validates

Whether Liquid Glass (macOS Tahoe / 26) is accessible from pure AppKit, or whether
achieving the refraction effect requires embedding a SwiftUI view via NSHostingView.
This determines whether the entire UI layer can stay in AppKit or needs a hybrid approach.

## Source of Truth

Knowledge-based analysis. APIs examined: NSVisualEffectView (macOS 10.10+, well-established),
WWDC 2025 session material (within knowledge cutoff), SwiftUI `.glassEffect()` modifier.

**Confidence level**: Medium. The aesthetic direction is certain; exact AppKit API names
for macOS 26 Liquid Glass are at the edge of my knowledge cutoff and may be imprecise.

---

## Findings

### What Liquid Glass Is (technically)

Liquid Glass is not simply a new blur radius. It simulates a physical glass lens:
- **Refraction**: content behind the surface is displaced/distorted as if passing through
  a convex lens — approximately 1–3px of radial displacement near edges
- **Specular caustics**: bright edge highlight where the lens edge catches light
- **Dynamic tint response**: the tint shifts subtly based on the luminance of content behind it
- The underlying capture mechanism is still window-server-level compositing (same as
  NSVisualEffectView) — it reads pixels from behind the window, not just blurs them

### SwiftUI API (high confidence)

SwiftUI receives `.glassEffect()` as a view modifier in macOS 26. Example shape:

```swift
// SwiftUI (macOS 26+)
someView
    .glassEffect()                        // default Liquid Glass material
    .glassEffect(.regular.tinted(.blue))  // tinted variant — API shape uncertain
```

This is the primary documented path at WWDC 2025.

### AppKit API (medium confidence — flag)

**My assessment**: AppKit receives Liquid Glass through one of two mechanisms — and I am
not certain which was shipped:

**Path A — New NSVisualEffectView material cases** (most likely):
```swift
// Probable AppKit path
let effectView = NSVisualEffectView()
effectView.material = .glass           // new .glass case (name uncertain)
effectView.blendingMode = .behindWindow
effectView.state = .active
```
New material cases were added to `NSVisualEffectView.Material` in macOS 26. The exact
case name — `.glass`, `.liquidGlass`, `.physicalGlass` — I cannot confirm with certainty.

**Path B — New NSView subclass**:
```swift
// Alternative: dedicated class (name uncertain)
let glassView = NSGlassEffectView()     // hypothetical name
glassView.cornerRadius = 12
```
Apple sometimes ships new visual primitives as dedicated classes rather than extending
NSVisualEffectView (precedent: NSHoverEffect in earlier macOS).

**Path C — SwiftUI bridge only** (least likely, but possible):
The refraction effect could be SwiftUI-only, with AppKit receiving only the blur/tint
from existing NSVisualEffectView materials. This would require `NSHostingView<some SwiftUI glass view>`
embedded in the AppKit hierarchy for the refraction effect.

### Layering: Glass Panel on Glass Window

This is technically supported in the design language — Apple's own macOS 26 UI shows
glass panels floating over glass surfaces. However:

- The system likely **suppresses inner refraction** for nested glass surfaces to prevent
  visual chaos. The inner panel may receive the standard vibrancy blur of window content
  behind it rather than desktop refraction.
- Apple's compositing rules for nested `NSVisualEffectView` have always been conservative:
  the system renders the innermost vibrancy against the already-composited layer below,
  not directly against the desktop. This prevents double-refraction artifacts.
- See Spike 007 for the full glass-on-glass analysis.

---

## Verdict: PARTIAL

**Known with confidence**: Liquid Glass is available to AppKit. Apple does not ship major
visual materials exclusively in SwiftUI without an AppKit path — NSVisualEffectView has
been the AppKit glass primitive since macOS 10.10 and it continues to be updated.

**Unknown with confidence**: The exact API name of the new material case(s) in macOS 26.
The refraction depth (whether the full lens-distortion effect, or just updated blur+tint)
may differ between SwiftUI and AppKit paths.

## Implication for Build

- **Do not assume SwiftUI-only.** AppKit will have access.
- **Write the NSVisualEffectView call against macOS 26 SDK.** If the material name is wrong,
  it's a 1-line fix — not an architectural change.
- **Prototype path**: use `NSHostingView` wrapping a SwiftUI `.glassEffect()` view as a
  fallback/comparison reference if the AppKit material doesn't produce the refraction effect.
- `#available(macOS 26, *)` gate around all Liquid Glass calls; fall back to `.hudWindow`
  or `.popover` material on Sequoia 15.

## Action Required Before Implementation

Run a 30-minute Xcode prototype on macOS 26 SDK:
```swift
// Test: does this produce refraction or just blur?
let v = NSVisualEffectView()
v.material = .init(rawValue: /* new value */)
```
Compare with SwiftUI path via NSHostingView. The visual output will immediately confirm
which path gives full refraction vs. blur-only.
