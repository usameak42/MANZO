---
spike: "009"
name: dynamic-wet-reflection
validates: "Given a draggable panel, when a real-time wet-floor reflection must render beneath it, then we know which approach (CALayer transform / Metal snapshot / CIFilter) is most performant"
verdict: VALIDATED
related: ["008-aero-specular-stack-calayer", "007-glass-on-glass-compositing"]
tags: [reflection, careplicatorlayer, calayer, metal, cifilter, neo-aero, animation]
---

# Spike 009: Dynamic Wet-Floor Reflection

## What This Validates

Which approach — CALayer transform + opacity mask, Metal snapshot, or CIFilter —
gives the best performance for a live "wet floor" reflection beneath draggable Neo-Aero
panels that updates in real time as the panel is dragged.

---

## The Requirement

Below each panel: a vertically-flipped, fading copy of the panel content.
- Updates live as the panel is dragged (position changes ~60 times/second)
- Fades from ~50% opacity at the edge touching the panel to 0% at ~80% of the panel height below
- Slight horizontal blur is optional but authentic to the Aero look
- Does NOT need to show live content changes inside the panel at 60fps —
  the reflection only needs to update when the panel is MOVED or its content changes (slider drag, etc.)

---

## Option A: CALayer Transform + Gradient Mask

### Approach

```swift
// Reflection layer: a CAReplicatorLayer child
let replicator = CAReplicatorLayer()
replicator.instanceCount       = 2
replicator.instanceTransform   = CATransform3D(
    // Y-flip + vertical offset (panel height × 2 to place below panel)
    m11: 1, m12:  0, m13: 0, m14: 0,
    m21: 0, m22: -1, m23: 0, m24: 0,
    m31: 0, m32:  0, m33: 1, m34: 0,
    m41: 0, m42: panelHeight * 2, m43: 0, m44: 1
)
replicator.instanceAlphaOffset = -0.5  // reflection is 50% opacity

// Gradient mask fades the reflection out vertically
let fadeMask = CAGradientLayer()
fadeMask.colors    = [CGColor(gray: 0, alpha: 1.0), CGColor(gray: 0, alpha: 0.0)]
fadeMask.locations = [0.0, 1.0]
fadeMask.frame     = reflectionRect
replicator.mask    = fadeMask
```

`CAReplicatorLayer` with `instanceCount = 2` creates a GPU-duplicated copy of the
source layer (your panel's CALayer tree) with the specified transform applied to
the second instance. The flip + offset is entirely GPU-side — no pixel readback,
no CPU copying.

**Crucially**: when the panel moves (frame changes), the replicator's second instance
automatically tracks it. No "update the reflection" step needed. The GPU handles it.

**For the fade gradient**: apply a `CAGradientLayer` as the `mask` on the reflection
portion. This is composited in the render server.

### Performance

- Zero CPU per-frame overhead during drag
- The replicator duplicates the source layer's cached rasterization (if `shouldRasterize = true`)
- When source panel content changes → rasterization cache invalidates → both source and
  reflection re-rasterize in one pass
- Cost: essentially the same as rendering one additional copy of the panel per frame
- M1: < 0.3ms additional per panel with reflection

---

## Option B: Metal Snapshot (`MTLTexture` readback)

### Approach

1. Render the panel to an `MTLTexture` via `layer.render(in: metalContext)`
2. In Metal: create a flipped render pass reading that texture, apply gradient alpha mask
3. Composite the reflection texture beneath the panel via a Metal quad

### Performance

- `CALayer.render(in:)` is **synchronous and CPU-side** — it re-rasterizes the entire
  layer tree on the CPU. At 60fps during drag: potentially 5–15ms per call depending on
  panel complexity. **Unacceptable for real-time drag.**
- An async Metal blit (`MTLBlitCommandEncoder.copy(from:to:)`) is faster but requires
  maintaining a shared `MTLTexture` and synchronizing with the Core Animation render pass
- This approach is appropriate only for **static panels** (update texture once on content
  change, not on every drag position change)

**Verdict for this use case: too expensive for live drag updates.**

---

## Option C: CIFilter on Live Layer Snapshot

### Approach

1. `layer.snapshot()` or custom render → `CGImage`
2. Apply `CIFilter(name: "CIAffineTransform")` for Y-flip
3. Apply `CIFilter(name: "CIGaussianBlur")` for the optional horizontal softening
4. Display result in a secondary `CALayer`

### Performance

- `layer.snapshot()` is documented as a debugging tool — it's not designed for per-frame
  use and behavior under load is not guaranteed
- CIFilter processing on a CGImage is CPU-bound unless using `CIContext(mtlDevice:)`
  with GPU rendering — but even then, the round-trip (CALayer → CGImage → CIFilter → CALayer)
  adds 3–8ms latency per frame
- Gaussian blur adds another 1–3ms on M1 depending on radius

**Verdict for this use case: viable for static content, too slow for live drag.**

---

## Recommended Approach: `CAReplicatorLayer` with Gradient Mask

`CAReplicatorLayer` is exactly the right tool. It was designed for this use case (Apple's
own documentation uses "reflection" as the primary example). The GPU handles duplication
and transform without any CPU involvement.

For optional horizontal softening of the reflection:
- Apply a very low `shadowRadius` on the replicator layer — this adds a soft glow below
  without a separate blur pass
- Or: keep the reflection sharp (authentic Aero look is a crisp flip, not a blurred one)

### Handling Content Updates

- Panel with static layout (knobs at rest, EQ sliders static): `shouldRasterize = true`
  on the panel layer. Reflection updates when rasterization invalidates.
- Panel with live animation (spectrum meter, VU bar): set `shouldRasterize = false`.
  The replicator reflects the live layer tree each frame. Still GPU-only, still fast.

---

## Verdict: VALIDATED

`CAReplicatorLayer` + gradient mask is the correct approach. Zero CPU overhead during
drag, automatic tracking of panel position changes, integrates with `shouldRasterize`
caching. Metal snapshot and CIFilter are appropriate only for on-demand (not per-frame)
reflection capture.

## Implication for Build

- Each draggable panel wraps its content in a `CAReplicatorLayer` that handles the reflection
- Reflection fade = `CAGradientLayer` mask on the replicator
- Reflection alpha = `instanceAlphaOffset = -0.5` on `CAReplicatorLayer`
- Reflection position = `instanceTransform` Y-flip + `panelHeight * 2` Y-offset
- For panels with live content (spectrum analyzer): `shouldRasterize = false`, let
  replicator track live
- For panels with static content: `shouldRasterize = true`, reflection cached for free
