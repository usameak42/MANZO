# Neo-Aero Visual Stack

Validated CALayer rendering patterns for the Frutiger Aero / Neo-Aero aesthetic.
All inner panels use this stack — no NSVisualEffectView (see window-glass-architecture.md).

## Validated Patterns

### NeoAeroLayer Stack (Spike 008) — No Bitmaps Required
Five layers assembled per element. Wrap in a factory or `CALayer` subclass:

```swift
// [1] Base gradient
let base = CAGradientLayer()
base.colors = [
    CGColor(colorSpace: p3, components: [0.05, 0.78, 0.82, 1.0]),  // aqua-teal top
    CGColor(colorSpace: p3, components: [0.02, 0.52, 0.60, 1.0]),  // deeper teal bottom
]
base.cornerRadius = 10;  base.frame = bounds

// [2] Specular band — top 50% only
let specular = CAGradientLayer()
specular.colors   = [CGColor(gray:1, alpha:0.50), CGColor(gray:1, alpha:0.08), CGColor(gray:1, alpha:0.0)]
specular.locations = [0.0, 0.45, 1.0]
specular.frame    = CGRect(x:0, y:0, width:bounds.width, height:bounds.height * 0.52)

// [3] Lower glow — bottom 25%
let lowerGlow = CAGradientLayer()
lowerGlow.colors = [CGColor(gray:1, alpha:0.0), CGColor(gray:1, alpha:0.12)]
lowerGlow.frame  = CGRect(x:0, y:bounds.height*0.75, width:bounds.width, height:bounds.height*0.25)

// [4] Rim highlight
let rim = CALayer()
rim.frame = bounds.insetBy(dx:0.5, dy:0.5);  rim.cornerRadius = 9.5
rim.borderWidth = 1.0;  rim.borderColor = CGColor(gray:1, alpha:0.45)

// Container (clips to rounded rect)
let container = CALayer()
container.cornerRadius = 10;  container.masksToBounds = true
container.addSublayer(base); container.addSublayer(specular)
container.addSublayer(lowerGlow); container.addSublayer(rim)

// Performance: cache static panels
container.shouldRasterize = true
container.rasterizationScale = 2.0  // Retina
```

30 elements on M-series < 0.8ms GPU. `shouldRasterize = true` reduces to ~0 per-frame cost for static panels. Invalidate only on state changes (hover, drag).

### P3 Color — CALayer (Spike 010)
```swift
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
// CGColor tagged with P3 colorspace — Core Animation render server handles P3 output automatically
let aeroAqua = CGColor(colorSpace: p3, components: [0.0, 0.84, 0.90, 1.0])!
gradientLayer.colors = [aeroAqua, deeperTealP3]  // no extra config needed
```
On non-P3 displays the render server tone-maps gracefully — never distorts.

For `NSView.draw(_:)`:
```swift
let aeroAquaNS = NSColor(colorSpace: .displayP3, components: [0.0, 0.84, 0.90, 1.0], count: 4)
```

### P3 Color — MTKView (Spike 010) ⚠ Not Automatic
```swift
// MTKView does NOT auto-use P3. Must configure explicitly:
let metalLayer = mtkView.layer as! CAMetalLayer
metalLayer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)

// For spectrum/bloom views (HDR values > 1.0 needed for neon edge):
metalLayer.pixelFormat = .rgba16Float
metalLayer.colorspace  = CGColorSpace(name: CGColorSpace.displayP3)
metalLayer.wantsExtendedDynamicRangeContent = true
```
In Metal shaders: use P3 component values directly — no sRGB conversion. `(0.0, 0.84, 0.90, 1.0)` ARE P3 values when colorspace is set to displayP3.

### Wet-Floor Reflection — `CAReplicatorLayer` (Spike 009)
```swift
let replicator = CAReplicatorLayer()
replicator.instanceCount = 2
replicator.instanceTransform = CATransform3D(
    m11:1, m12:0, m13:0, m14:0,
    m21:0, m22:-1, m23:0, m24:0,   // Y-flip
    m31:0, m32:0, m33:1, m34:0,
    m41:0, m42:panelHeight * 2, m43:0, m44:1  // offset below panel
)
replicator.instanceAlphaOffset = -0.5   // reflection at 50% opacity

let fadeMask = CAGradientLayer()
fadeMask.colors = [CGColor(gray:0, alpha:1.0), CGColor(gray:0, alpha:0.0)]
fadeMask.frame  = reflectionRect
replicator.mask = fadeMask
```
- Zero CPU per-frame — GPU-only, auto-tracks panel position during drag
- For panels with live content (spectrum): `shouldRasterize = false` on panel layer
- For static panels: `shouldRasterize = true` — reflection caches for free

## Landmines

- **`masksToBounds = true` triggers off-screen rendering** on the container layer. Mitigate with `shouldRasterize = true` so it's a one-time cost, not per-frame.
- **`CAGradientLayer` radial type is always centered** — cannot do an off-axis specular orb natively. Use a `32×32` PNG for any asymmetric radial highlight, or approximate with `type = .radial` and adjusted start/end points.
- **`layer.snapshot()` is a debugging tool** — never call it per-frame for reflections. It's not designed for real-time use and its behavior under load is undefined.
- **`CALayer.render(in:)` is synchronous CPU-side** — 5–15ms per call. Not suitable for live drag reflection updates. Use `CAReplicatorLayer` instead.
- **Forgetting `rasterizationScale = 2.0`** on Retina displays produces blurry rasterized layers. Always set alongside `shouldRasterize = true`.
- **MTKView sRGB silent failure** — if `CAMetalLayer.colorspace` is not set, P3 colors are silently clamped to sRGB. The result looks correct but muted. No error is thrown.

## Constraints

- `CAReplicatorLayer.instanceAlphaOffset`: negative value reduces alpha per instance (−0.5 = 50% opacity reflection)
- `shouldRasterize` must be invalidated (`false` → `true`) on any visual state change, or stale cached image persists
- `wantsExtendedDynamicRangeContent` available macOS 10.15+ — safe for Sequoia+ target
- P3 color components are in P3 space (not sRGB) — `(0.0, 0.84, 0.90)` in P3 is outside sRGB gamut

## Origin
Synthesized from spikes: 008, 009, 010
Source files: `sources/008-aero-specular-stack-calayer/`, `sources/009-dynamic-wet-reflection/`, `sources/010-p3-color-in-appkit-metal/`
