# Metal Spectrum Renderer

Validated patterns for the MTKView spectrum analyzer with Aero neon-bloom aesthetic.

## Validated Patterns

### MTKView Setup (Spike 011 + 010)
```swift
// Always configure from day one — no retrofitting later
let metalLayer = mtkView.layer as! CAMetalLayer
metalLayer.pixelFormat   = .rgba16Float       // supports HDR values > 1.0 for bloom
metalLayer.colorspace    = CGColorSpace(name: CGColorSpace.displayP3)
metalLayer.wantsExtendedDynamicRangeContent = true

// Render loop: CADisplayLink (macOS 14+) on background thread
let displayLink = CADisplayLink(target: self, selector: #selector(render))
displayLink.add(to: .main, forMode: .common)
```

### Rust → Metal FFT Data Bridge
```swift
// Rust audio core writes FFT magnitude data to a shared float buffer.
// Swift side creates an MTLBuffer from it — zero copy if using shared memory.
let fftBuffer = device.makeBuffer(
    bytesNoCopy: rustFFTPointer,        // UnsafeMutablePointer<Float> from Rust
    length: barCount * MemoryLayout<Float>.stride,
    options: .storageModeShared,
    deallocator: nil
)
// Vertex shader reads fftBuffer directly — no CPU copy per frame
```

### v1: SDF Single-Pass Bloom (Spike 011) — Recommended for v1
Each bar quad is extended by `3σ` pixels on all sides. Glow computed analytically:
```metal
fragment float4 sdfBarFrag(SDFIn in [[stage_in]]) {
    float d    = abs(in.edgeDist);                          // px from bar edge
    float glow = exp(-d * d / (2.0 * sigma * sigma));       // Gaussian falloff
    float4 barColor = /* height-based P3 gradient */;
    return barColor * glow + barColor * float(d < 1.0);     // core + halo
}
```
- No extra textures, no second pass, no MPS dependency
- Con: glow doesn't cross between adjacent bars

### v2: Two-Pass MPS Bloom (Spike 011) — When Cross-Bar Glow Needed
```
Pass 1: render bars → MTLTexture (full-res, rgba16Float)
Pass 2a: threshold bright pixels → half-res MTLTexture
Pass 2b: MPSImageGaussianBlur(sigma: 6.0) on half-res texture
Pass 3: additive composite (bar + bloom * 1.2) → drawable
```
```swift
import MetalPerformanceShaders
let blur = MPSImageGaussianBlur(device: device, sigma: 6.0)
blur.encode(commandBuffer: cmdBuf, sourceTexture: thresholdTex, destinationTexture: blurTex)
```
GPU time on M1: < 0.6ms total. < 4% of 60fps frame budget.

### Bar Color Gradient — P3 Aero Palette (Spike 011)
```metal
// Height h: 0.0 (silent) → 1.0 (peak)
float4 deepTeal   = float4(0.02, 0.55, 0.65, 1.0);  // P3
float4 brightAqua = float4(0.0,  0.88, 0.95, 1.0);  // P3 — outside sRGB gamut
float4 whiteHot   = float4(0.85, 1.0,  1.0,  1.0);  // > 1.0 allowed in rgba16Float

float4 color = h < 0.6
    ? mix(deepTeal, brightAqua, h / 0.6)
    : mix(brightAqua, whiteHot, (h - 0.6) / 0.4);
```

### Peak-Hold Dots (Spike 011)
Update peak vertex buffer at ~10fps (decay rate), not every render frame:
```swift
// In render loop: only update peak buffer when peaks change
if peaksDirty {
    memcpy(peakBuffer.contents(), rustPeakPointer, peakCount * MemoryLayout<Float>.stride)
    peaksDirty = false
}
// Draw peak dots as separate vertex buffer with stronger glow (sigma * 2.0)
```

### Threshold Fragment for Bloom (Spike 011)
```metal
fragment float4 thresholdFrag(ThresholdIn in [[stage_in]],
                               texture2d<float> src [[texture(0)]]) {
    float4 color = src.sample(linearSampler, in.uv);
    float lum = dot(color.rgb, float3(0.2126, 0.7152, 0.0722));
    return lum > 0.65 ? color : float4(0.0);
}
```

### Additive Composite for Neon Effect (Spike 011)
```metal
fragment float4 compositeFrag(CompositeIn in [[stage_in]],
                               texture2d<float> bars  [[texture(0)]],
                               texture2d<float> bloom [[texture(1)]]) {
    return bars.sample(s, in.uv) + bloom.sample(s, in.uv) * 1.2;
    // Values > 1.0 render as HDR highlights on EDR displays
}
```

## Landmines

- **MTKView does NOT auto-configure P3** — `(mtkView.layer as! CAMetalLayer).colorspace` must be set explicitly. Silent failure: colors render but are sRGB-clamped with no error.
- **`bgra8Unorm` for bloom is wrong** — 8-bit cannot represent values > 1.0. Use `.rgba16Float` for the spectrum view from the start. Retrofitting pixel format later requires recreating render pipelines.
- **Bloom at full resolution is wasteful** — always threshold into a half-res texture before blur. The human eye cannot distinguish full-res vs half-res bloom glow.
- **`MPSImageGaussianBlur` is a single call** (not two) — it internally runs separable H+V passes. Don't implement a manual two-pass Gaussian; MPS uses tiled architecture optimizations that hand-written shaders rarely match.
- **Peak-hold updates at 60fps burn CPU** for negligible visual gain — update the peak vertex buffer only when peak values change (typically 10–30fps decay rate).

## Constraints

- `.rgba16Float` + EDR: values slightly > 1.0 render as true HDR highlights on ProMotion displays; values far > 1.0 clip at display white
- `CADisplayLink` available macOS 14+; use `CVDisplayLink` for macOS 13 if needed (not relevant for Sequoia+ target)
- `MPSImageGaussianBlur` available macOS 10.13+ — safe for Sequoia+ target
- Render loop must run on a **background thread** — never block the main thread with GPU work

## Origin
Synthesized from spike: 011 (with P3 setup from spike 010)
Source files: `sources/011-spectrum-bloom-metal/`, `sources/010-p3-color-in-appkit-metal/`
