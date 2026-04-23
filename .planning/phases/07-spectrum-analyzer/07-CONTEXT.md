# Phase 7: Spectrum Analyzer - Context

**Gathered:** 2026-04-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the real-time FFT pipeline in Rust and the Metal spectrum renderer in Swift.
`manzo_get_spectrum` currently zero-fills — Phase 7 replaces that with a live FFT.
A `~150×32 pt` Winamp-faithful MTKView is added as a subview of `bodyView`, framed by
a masking hole in the NeoAero chrome. A `CADisplayLink`-driven render loop on a
background thread reads FFT magnitude data from a double-buffered shared array and
renders 75 spectrum bars with SDF bloom and Winamp-canonical colors (P3-upgraded).

**In scope:**
- `rustfft` FFT pipeline in the cpal audio callback (1024-sample window, no windowing)
- Double-buffer + atomic-index shared array for Rust→Swift zero-copy FFT data
- MTKView sub-region in `bodyView`: ~150×32 pt, center-bottom, NeoAero chrome inset mask
- 75 frequency bars, 2pt wide, 1pt gap, linear binning (4 FFT bins averaged per bar)
- `.rgba16Float` + explicit P3 colorspace on MTKView (SPEC-01)
- Winamp-canonical color gradient (ppal2) with P3 neon upgrades on three zones
- SDF single-pass bloom (SPEC-03) — bar quads extended by 3σ, analytical Gaussian glow
- Peak-hold dots: separate vertex buffer, ~10fps decay, gray RGB(150,150,150) color
- `CADisplayLink` render loop on dedicated background thread (SPEC-04)

**Out of scope:**
- v2 MPS two-pass Gaussian bloom — SPEC-05 explicitly deferred to v2
- EQ slider UI — Phase 8
- Playlist UI — Phase 8
- `.wsz` skin-driven palette — v2

</domain>

<decisions>
## Implementation Decisions

### Spectrum Panel Placement
- **D-01:** MTKView dimensions: **~150×32 pt** (2pt/bar × 75 bars + gaps ≈ 149 pt wide;
  32 pt tall — exact Winamp singlesize specData 76×16 px at 2× scale).
  Positioned: **center-horizontally, bottom-anchored** in `bodyView` (275×88 pt).
  Implemented as a subview of `bodyView` — NOT a sibling — so Auto Layout constraints
  are relative to `bodyView`.

- **D-02:** NeoAero chrome **insets around the MTKView** (chrome-frames-spectrum look).
  The `NeoAeroContainer` layer (or its mask) gets a rectangular cutout matching the
  MTKView's frame, using a `CAShapeLayer` mask with a path that subtracts the MTKView
  rect. Claude's discretion on exact mask API — `CALayer.mask` with a path-based shape
  layer is the standard approach.

### Bar Count & Frequency Layout
- **D-03:** **75 bars** exactly — canonical from `draw_sa.cpp`: `static int bx[75]`.
  Each bar = 2 pt wide, 1 pt gap = 3 pt per bar × 75 = 225 pt logical. MTKView width
  is sized to fit exactly (225 pt + any edge padding Claude decides).

- **D-04:** **Linear frequency binning** (Winamp original). In `draw_sa.cpp`:
  ```c
  int a=values[t], b=values[t+1], c=values[t+2], d=values[t+3];
  v = (a+b+c+d) / 4;  // 4 consecutive FFT bins averaged per bar
  ```
  With 1024-sample FFT at 44.1 kHz, each bin = 43 Hz.
  Bar `i` averages FFT bins `[i*4, i*4+3]` → covers 0–12,900 Hz over 75 bars.

- **D-05:** **16 height levels** (v = 0–15), matching Winamp: `if (v > 15) v = 15`.
  Normalized bar height in Metal: `h = v / 15.0`.

### FFT Pipeline (Rust)
- **D-06:** Add **`rustfft`** to `manzo-core/Cargo.toml` — most widely used Rust FFT,
  good docs, zero unsafe.

- **D-07:** **FFT size = 1024 samples**. Buffer the last 1024 decoded float32 samples
  in `InnerState` (circular buffer). Run FFT every time the audio callback has produced
  1024 new samples (stride can be shorter — e.g. every 512 for smoother visuals — but
  1024-stride is the Winamp-equivalent starting point; Claude's discretion on stride).

- **D-08:** **No windowing** (Winamp-original). No Hann or other window function applied
  to the 1024-sample block before FFT.

- **D-09:** **FFT runs inside the cpal audio callback**, after decoding and DSP, before
  writing to the cpal output buffer. Computation cost for 1024-sample FFT is ≤0.05 ms
  on M-series — safe in the audio hot path.

- **D-10:** **Double buffer + atomic index** for Rust→Swift zero-copy:

  ```rust
  // In InnerState:
  fft_bufs: [[f32; 75]; 2],   // two magnitude arrays
  fft_write_idx: AtomicUsize,  // which buf the audio callback is writing
  fft_read_idx: AtomicUsize,   // which buf Swift should read
  ```

  After computing 75 bar magnitudes, the audio callback:
  1. Writes into `fft_bufs[fft_write_idx]`
  2. Atomically swaps `fft_read_idx = fft_write_idx`
  3. Flips `fft_write_idx` to the other slot (0↔1)

  `manzo_get_spectrum` reads `fft_bufs[fft_read_idx.load(Relaxed)]` — no lock,
  no allocation, no copy. Swift calls it once per frame from the `CADisplayLink`
  callback and copies the 75 floats into the `MTLBuffer`.contents().

### Spectrum Colors (Winamp ppal2 + P3 Upgrade)
- **D-11:** Canonical color source: `Winamp/Src/Winamp/draw.cpp` lines 370–395 (`ppal2`
  array). All 24 palette entries are hardcoded there as the Winamp default viscolor.txt.

- **D-12:** The Metal fragment shader uses a **5-stop gradient** derived from ppal2
  with P3 saturation pushes on three zones. `h` = normalized bar height [0.0=bottom,
  1.0=top]:

  | Stop | h | Source | Metal float4 (P3 normalized) | Note |
  |------|---|--------|------------------------------|------|
  | Bottom | 0.00 | ppal2[17] RGB(24,132,8) | `float4(0.094, 0.518, 0.031, 1.0)` | sRGB faithful |
  | Green peak | 0.35 | ppal2[12] pushed | `float4(0.0, 0.95, 0.06, 1.0)` | **P3 neon** — outside sRGB |
  | Yellow-green | 0.55 | ppal2[10] RGB(189,222,41) | `float4(0.741, 0.871, 0.161, 1.0)` | sRGB faithful |
  | Gold | 0.70 | ppal2[8–9] pushed | `float4(0.920, 0.750, 0.0, 1.0)` | **P3 vivid gold** |
  | Top red | 1.00 | ppal2[2] pushed | `float4(1.0, 0.12, 0.04, 1.0)` | **P3 saturated red** |

  Interpolation: linear `mix()` between adjacent stops in the Metal fragment shader.
  Claude's discretion: adjust intermediate stop h-values if the gradient looks uneven
  on real music.

- **D-13:** **Peak dot color** = ppal2[23] RGB(150,150,150) → `float4(0.588, 0.588, 0.588, 1.0)`.
  No P3 extension — neutral gray reads clearly against all bar heights.

### Peak-Hold Dots
- **D-14:** Peak-hold dots **included in Phase 7**. Pattern from spike 011 (validated).

- **D-15:** Peak vertex buffer updated at **~10fps decay rate** (not every render frame).
  Track `peak_values: [f32; 75]` in Swift. After each `CADisplayLink` tick:
  - If `fft_magnitude[i] > peak_values[i]`: snap up immediately
  - Otherwise: decay by `spfo` multiplier (match Winamp `t_vx[i] *= spfo` with
    `config_sa_peak_falloff = 1` → `spfo = 1.1`). Only copy to MTLBuffer when any
    peak changed.

- **D-16:** Peak dots rendered as separate draw call — 75 single-pixel quads with
  stronger glow (σ × 2.0 in the SDF fragment), using the peak dot color from D-13.

### Claude's Discretion
- Exact `CAShapeLayer` mask API for the NeoAero chrome cutout (D-02)
- FFT update stride (every 1024 or every 512 new samples) for visual smoothness
- MTKView exact width (225 pt bare or with ~4 pt edge padding) and constraint anchors
- Whether to pre-compute the 1024-sample Hann table anyway for a config toggle later
- Rust struct layout for `fft_bufs` / atomic fields in `InnerState`
- `AtomicUsize` relaxed vs. acquire/release ordering on fft_read_idx swap
- Whether magnitude is log-scaled (`20 * log10(mag)`) before normalization to 0–15
  range — standard for audio visualizers; Claude decides based on what looks best

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Winamp Source (spectrum behavior reference)
- `Winamp/Src/Winamp/draw_sa.cpp` — Canonical bar drawing: 75 bars, 16 height levels,
  4-bin linear averaging, peak-hold logic (`t_bx`, `t_vx`, `spfo`), `config_sa_peaks`.
  Read `draw_sa` function end-to-end before writing any FFT→bar mapping code.
- `Winamp/Src/Winamp/SA.cpp` — Spectrum analyzer state machine, ring buffer, `sa_get()`.
  Read for the data-flow model (input: 75 `unsigned char` values, range 0–15).
- `Winamp/Src/Winamp/draw.cpp` lines 368–443 — **`ppal2[]` hardcoded default palette**
  (24 entries, indices 0–23). The spectrum color gradient and peak dot color live here.
  This is the authoritative source — not viscolor.txt (which overrides at runtime; our
  Metal shader bakes ppal2 as the fixed palette).

### Spike Findings (Metal renderer reference)
- `.claude/skills/spike-findings-MANZO/references/metal-spectrum-renderer.md` — MTKView
  setup (`.rgba16Float`, explicit P3 colorspace), Rust→Metal shared buffer pattern
  (`bytesNoCopy` + `storageModeShared`), SDF single-pass bloom GLSL sketch, peak-hold
  update pattern, two-pass MPS bloom for v2. Use the MTKView + SDF patterns directly.
  **Note:** the spike's deepTeal→brightAqua color palette is superseded by D-12 (ppal2
  base + P3 upgrades). All other spike patterns are valid.

### Phase 6 Context (integration points)
- `.planning/phases/06-neo-aero-visual-stack/06-CONTEXT.md` — D-09 (`NeoAeroContainer`
  layer name tag), D-08 (`shouldRasterize` invalidation on state change). The Phase 7
  MTKView is inserted into `bodyView` — NeoAero chrome layers are already there.
  Read D-02/D-10 for how `applyStyle` inserts/removes layers.

### Existing Swift Code (integration points)
- `ManzoApp/ManzoApp/ManzoRootView.swift` — `bodyView` is the MTKView parent. Read
  `setupPanels()` for layout constraints pattern and `applyStyle()` for the layer
  insertion model that Phase 7's chrome-mask approach follows.
- `ManzoApp/ManzoApp/AppDelegate.swift` — Wiring point for MTKView setup and
  `CADisplayLink` initialization.

### Existing Rust Code (stub to replace)
- `manzo-core/src/lib.rs` lines 678–697 — `manzo_get_spectrum` stub. Phase 7 replaces
  the zero-fill body with the double-buffer atomic read from `InnerState`.
- `manzo-core/Cargo.toml` — Add `rustfft = "6"` (or latest) to `[dependencies]`.

### Project Planning
- `.planning/REQUIREMENTS.md` — SPEC-01, SPEC-02, SPEC-03, SPEC-04
- `.planning/ROADMAP.md` — Phase 7 success criteria (4 items)
- `.planning/PROJECT.md` — Float32 pipeline, P3 colors mandatory, MTKView constraints
  (`CAMetalLayer.colorspace` must be set explicitly, `.rgba16Float` from day one)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `manzo_get_spectrum(handle, out_buf, count)` — FFI stub already in the header and
  linked. Phase 7 replaces the body only; the signature and Swift call site are stable.
- `Arc<Mutex<InnerState>>` — already used by the audio callback for EQ/vol/pan.
  Phase 7 adds `fft_bufs` and atomic index fields to `InnerState`. The mutex is NOT
  used for FFT reads (atomic index avoids it) — but `fft_bufs` initialization happens
  under the existing mutex at open time.
- `ManzoRootView.bodyView` — existing `NSView` with `wantsLayer = true`, NeoAero layers
  already inserted by Phase 6. The MTKView is added as a subview here.
- `AppDelegate.applicationDidFinishLaunching` — existing wiring point for window and
  style setup. Phase 7 adds MTKView + `CADisplayLink` initialization here (or in a new
  `ManzoSpectrumController`).

### Established Patterns
- `NSLog(...)` for all diagnostic output (Phases 1–6 convention)
- No NIBs/storyboards — all UI in code
- `shouldRasterize = true` + `rasterizationScale = 2.0` for static layers (NeoAero)
  but the MTKView renders live — do NOT set `shouldRasterize` on it
- Auto Layout with `NSLayoutAnchor` — all three structural panels use this; MTKView
  constraints should follow the same pattern

### Integration Points
- `bodyView.layer` — NeoAero `CAShapeLayer` mask for the chrome cutout (D-02) is added
  here. The Phase 6 `NeoAeroContainer` layer (already a sublayer of `bodyView.layer`)
  gets a mask applied that subtracts the MTKView rect.
- `project.yml` (xcodegen) — any new Swift files (`ManzoSpectrumView.swift`,
  `ManzoSpectrumRenderer.swift`) and the Metal shader file (`Spectrum.metal`) must be
  listed here to be included in the build. Metal shaders are added under a
  `sources:` path entry in project.yml.

</code_context>

<specifics>
## Specific Ideas

- **Exact ppal2 palette (draw.cpp:370–395):**
  ```
  [0]  (  0,   0,   0)  background
  [1]  ( 24,  24,  41)  dot background
  [2]  (239,  49,  16)  bar top (red)
  [3]  (206,  41,  16)
  [4]  (214,  90,   0)
  [5]  (214, 102,   0)
  [6]  (214, 115,   0)
  [7]  (198, 123,   8)
  [8]  (222, 165,  24)
  [9]  (214, 181,  33)
  [10] (189, 222,  41)
  [11] (148, 222,  33)
  [12] ( 41, 206,  16)  bar bright-green zone
  [13] ( 50, 190,  16)
  [14] ( 57, 181,  16)
  [15] ( 49, 156,   8)
  [16] ( 41, 148,   0)
  [17] ( 24, 132,   8)  bar bottom (default t=17)
  [18] (255, 255, 255)  oscilloscope colors (not used in spectrum bars)
  ...
  [23] (150, 150, 150)  PEAK DOT
  ```

- **Metal gradient stops (D-12) — copy directly into Spectrum.metal:**
  ```metal
  float4 specColor(float h) {
      // h = normalized height [0.0=bottom, 1.0=top]
      float4 c0 = float4(0.094, 0.518, 0.031, 1.0); // ppal2[17] dark green
      float4 c1 = float4(0.000, 0.950, 0.060, 1.0); // ppal2[12] → P3 neon green
      float4 c2 = float4(0.741, 0.871, 0.161, 1.0); // ppal2[10] yellow-green
      float4 c3 = float4(0.920, 0.750, 0.000, 1.0); // ppal2[8–9] → P3 gold
      float4 c4 = float4(1.000, 0.120, 0.040, 1.0); // ppal2[2] → P3 red
      if      (h < 0.35) return mix(c0, c1, h / 0.35);
      else if (h < 0.55) return mix(c1, c2, (h - 0.35) / 0.20);
      else if (h < 0.70) return mix(c2, c3, (h - 0.55) / 0.15);
      else               return mix(c3, c4, (h - 0.70) / 0.30);
  }
  ```

- **Peak falloff from Winamp draw_sa.cpp** (for Swift peak decay):
  ```
  config_sa_peak_falloff = 1  →  spfo = 1.1f
  t_bx[x] -= (int)t_vx[x];   // each tick: subtract current falloff value
  t_vx[x] *= spfo;            // accelerating falloff (exponential feel)
  ```
  Swift equivalent: `peakVelocity[i] *= 1.1; peakValue[i] -= peakVelocity[i] / 256.0`

- **Winamp singlesize visualization area**: 76×16 px (stride 76×2=152 for DIBSection).
  At 2× Retina scale, our 150×32 pt MTKView = 300×64 Metal framebuffer pixels.
  Each bar = 4 px wide, 2 px gap at 2×. 16 height levels × (64px / 16) = 4 px per level.

</specifics>

<deferred>
## Deferred Ideas

- v2 MPS two-pass Gaussian bloom (SPEC-05) — explicitly out of scope for Phase 7.
  When ready: `MPSImageGaussianBlur(device: device, sigma: 6.0)` on a half-res texture,
  then additive composite. Spike 011 has the full pattern.
- Hann windowing toggle — deferred. Phase 7 is Winamp-faithful (no window). A future
  config `config_fft_window` could enable it without touching the bar rendering code.
- Logarithmic frequency scale toggle — deferred. Phase 7 is Winamp-linear. Log scale
  is a Phase 8+ config option.
- `.wsz` skin-driven palette (ppal2 override) — v2 when .wsz parser ships.
- Oscilloscope mode (`config_sa == 2`) — deferred. Phase 7 is spectrum bars only.
- Windowshade mode mini spectrum — deferred. Phase 7 targets the normal window only.

</deferred>

---

*Phase: 07-spectrum-analyzer*
*Context gathered: 2026-04-24*
