---
spike: "010"
name: p3-color-in-appkit-metal
validates: "Given P3-wide-gamut aqua/teal colors on Apple Silicon with P3 displays, when rendered in CALayer and MTKView, then we know how to prevent sRGB clamping and confirm Metal's color space behavior"
verdict: VALIDATED
related: ["008-aero-specular-stack-calayer", "011-spectrum-bloom-metal"]
tags: [p3, wide-gamut, color-space, calayer, mtkview, metal, apple-silicon]
---

# Spike 010: P3 Color in AppKit + Metal

## What This Validates

How to specify P3 colors in CALayer gradients and Metal shaders without sRGB clamping,
and whether `MTKView` automatically uses P3 color space on Apple Silicon P3 displays.

---

## Why This Matters for Frutiger Aero

The defining aqua/teal of Frutiger Aero — vivid cyan-aqua around `rgb(0, 210, 230)` in
sRGB — is already pushing the sRGB boundary. In P3, there is approximately 25% more
saturation available in the cyan-teal-green region. On Apple Silicon Macs with P3 displays:
- Using sRGB: colors look slightly muted compared to the design intent
- Using P3 correctly: colors are visibly more vivid, especially teal/aqua/lime
- Using P3 incorrectly (values specified as P3 but rendered as sRGB): colors are oversaturated
  and distorted

---

## CALayer / AppKit — P3 Color Specification

### The Core Problem

`CALayer.backgroundColor`, `CALayer.borderColor`, and `CAGradientLayer.colors` all accept
`CGColor`. By default, `NSColor` and Swift color literals use the `sRGB` color space. If
you pass an sRGB `CGColor` with P3-saturated values (e.g. `r=0, g=0.85, b=0.90`), they
are silently clamped to sRGB gamut at render time — you get less vivid output.

### Correct P3 Color Creation

```swift
// Step 1: get the Display P3 color space
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!

// Step 2: create CGColor in P3 (component values 0–1, in P3 space)
// This aqua is outside sRGB gamut — only P3 can render it fully:
let aeroAqua = CGColor(colorSpace: p3, components: [0.0, 0.84, 0.90, 1.0])!

// For AppKit NSColor:
let aeroAquaNS = NSColor(colorSpace: NSColorSpace.displayP3,
                          components: [0.0, 0.84, 0.90, 1.0],
                          count: 4)

// Use in CAGradientLayer:
gradientLayer.colors = [aeroAqua, deeperTealP3]
// CALayer correctly forwards P3 CGColor to the render server
```

### Display P3 in CAGradientLayer

Core Animation's render server is color-space-aware. When you supply `CGColor` objects
tagged with the `displayP3` colorspace to `CAGradientLayer.colors`, the render server
renders the gradient in P3 space on P3-capable displays. **No extra configuration needed**
— the CGColor's embedded colorspace tag is sufficient.

Verify: on a non-P3 display (old iMac, external sRGB monitor), the render server
tone-maps the P3 colors to sRGB gamut. Colors appear slightly less vivid but never
distorted — the system handles the gamut mapping.

---

## MTKView — Color Space Configuration

### Does MTKView Automatically Use P3?

**No.** By default, `MTKView` renders to `MTLPixelFormat.bgra8Unorm`, which is an 8-bit
per channel unorm format. The underlying `CAMetalLayer` defaults to the `sRGB` color space.
P3 colors rendered without explicit configuration are clamped at the display level.

### Configuring MTKView for P3

```swift
// Option A: Configure via CAMetalLayer (the layer that backs MTKView)
let metalLayer = mtkView.layer as! CAMetalLayer
metalLayer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)
// pixel format stays .bgra8Unorm — P3 colorspace tag tells the display pipeline
// to treat the values as P3, not sRGB. This is enough for standard Aero colors.

// Option B: Extended range (for potential HDR/EDR use)
metalLayer.pixelFormat = .rgba16Float          // 16-bit float per channel
metalLayer.colorspace  = CGColorSpace(name: CGColorSpace.displayP3)
metalLayer.wantsExtendedDynamicRangeContent = true
// Allows values > 1.0 in the shader for bloom/HDR highlights (Aero glows)
```

**Recommended for this project**: Option A for normal UI panels (8-bit P3 is sufficient
for Aero teal/aqua). Option B for the spectrum analyzer MTKView where HDR bloom glow
may push luminance above 1.0 for the neon-edge effect.

### In Metal Shaders

```metal
// In fragment shader, work in linear P3 color space.
// If metalLayer.colorspace = displayP3, the GPU outputs to P3 framebuffer.
// Values are 0–1 in P3 gamut (not sRGB).

fragment float4 neoAeroFrag(VertexOut in [[stage_in]]) {
    // P3 aqua-teal: these values in P3 space are outside sRGB
    float4 aeroAqua = float4(0.0, 0.84, 0.90, 1.0);  // P3 components
    return aeroAqua;
}
```

**Important**: Metal shaders work in the color space of the framebuffer. If `colorspace`
is set to `displayP3`, shader values of `(0.0, 0.84, 0.90, 1.0)` ARE P3 values.
Don't convert from sRGB in the shader — just use P3 component values directly.

### Gamma / Linear Light Consideration

- `bgra8Unorm` is **gamma-encoded** (perceptual, like sRGB gamma ≈ 2.2)
- `rgba16Float` is typically **linear**
- For correct blending (especially the additive bloom in Spike 011), use `rgba16Float`
  so blending happens in linear light space, preventing bloom colors from looking muddy

---

## Checklist: P3 Color Correctness

| Context | What to do |
|---------|-----------|
| CAGradientLayer | Use `CGColor(colorSpace: displayP3, components:)` |
| NSView draw(_:) | Use `NSColor(colorSpace: .displayP3, components:)` |
| MTKView (normal UI) | Set `(layer as! CAMetalLayer).colorspace = displayP3` |
| MTKView (spectrum/bloom) | Set `.pixelFormat = .rgba16Float` + `.colorspace = displayP3` + `.wantsExtendedDynamicRangeContent = true` |
| Metal shaders | Use P3 component values directly; no sRGB conversion in shader |
| Image assets | Export from design tool as Display P3, embed in `.xcassets` with P3 tag |

---

## Verdict: VALIDATED

P3 color in CALayer requires one step: use `CGColor` with `displayP3` colorspace.
MTKView requires explicit `CAMetalLayer.colorspace` configuration — it does NOT default
to P3. Use `.rgba16Float` for the spectrum analyzer view to support HDR bloom values.

## Implication for Build

- Define a project-level color palette as `CGColor` constants in P3 colorspace
- All `CAGradientLayer` use P3 CGColors — no sRGB color literals for brand colors
- Spectrum analyzer MTKView: `.rgba16Float` + P3 colorspace from day one
- Other MTKViews (if any): `.bgra8Unorm` + P3 colorspace sufficient
- Add `@available(macOS 10.15, *)` check for `wantsExtendedDynamicRangeContent`
  (available macOS 10.15+, safe for Sequoia+ target)
