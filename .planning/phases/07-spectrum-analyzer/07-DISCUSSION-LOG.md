# Phase 7: Spectrum Analyzer - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-24
**Phase:** 07-spectrum-analyzer
**Areas discussed:** Spectrum panel placement, Bar count & frequency layout, FFT pipeline in Rust, Peak-hold dots, Spectrum colors (color research session)

---

## Spectrum Panel Placement

| Option | Description | Selected |
|--------|-------------|----------|
| Full 275×88 bodyView | MTKView fills entire center panel | |
| Winamp viz sub-region (~150×32) | Faithful to original, center-bottom of bodyView | ✓ |

**Follow-up: Position within bodyView**

| Option | Description | Selected |
|--------|-------------|----------|
| Center-bottom of bodyView | Matches classic Winamp layout | ✓ |
| Full width, bottom half | Wider spectrum, denser bars | |

**Follow-up: Chrome compositing**

| Option | Description | Selected |
|--------|-------------|----------|
| MTKView on top of chrome | Simple layering, bars over chrome | |
| Chrome surrounds MTKView (inset look) | NeoAero layers masked, chrome frames spectrum | ✓ |

**User's choices:** Winamp-faithful 150×32 pt sub-region, center-bottom of bodyView, chrome inset look (NeoAero mask with cutout).

---

## Bar Count & Frequency Layout

| Option | Description | Selected |
|--------|-------------|----------|
| 75 bars, 2pt wide, 1pt gap | Winamp-faithful (draw_sa.cpp `bx[75]`) | ✓ |
| 48 bars, wider | Fewer, more legible | |
| Claude's discretion | — | |

| Option | Description | Selected |
|--------|-------------|----------|
| Logarithmic frequency axis | Musically natural | |
| Linear (Winamp original) | 4 FFT bins averaged per bar | ✓ |
| Claude's discretion | — | |

**User's choices:** 75 bars Winamp-faithful. Linear frequency scale.

---

## FFT Pipeline in Rust

| Option | Description | Selected |
|--------|-------------|----------|
| rustfft | Widely used, zero unsafe | ✓ |
| realfft | Optimized for real input, faster | |
| Claude's discretion | — | |

| Option | Description | Selected |
|--------|-------------|----------|
| 1024 samples | 23 ms latency, Winamp default | ✓ |
| 2048 samples | Better resolution, 46 ms latency | |
| 512 samples | Fast, coarser | |

| Option | Description | Selected |
|--------|-------------|----------|
| Inside cpal audio callback | Simplest, FFT is trivially fast | ✓ |
| Dedicated FFT thread + ring buffer | More decoupled, unnecessary overhead | |

| Option | Description | Selected |
|--------|-------------|----------|
| Double buffer + atomic index | No mutex contention, zero-copy | ✓ |
| Mutex-guarded single array | Simpler but blocks audio hot path | |
| Claude's discretion | — | |

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, Hann window | Cleaner peaks, less spectral leakage | |
| No windowing (Winamp original) | Pixel-faithful Winamp behavior | ✓ |
| Claude's discretion | — | |

**User's choices:** rustfft, 1024 samples, in-callback, double buffer + atomic, no windowing.

---

## Peak-Hold Dots

| Option | Description | Selected |
|--------|-------------|----------|
| Yes — implement in Phase 7 | In original Winamp, spike-validated | ✓ |
| No — defer to v2 | Skip for now | |

| Option | Description | Selected |
|--------|-------------|----------|
| Bright white | ppal2[23] = RGB(150,150,150), classic look | ✓ |
| Bright orange/yellow | Warmer, less classic | |
| Claude's discretion | — | |

**User's choices:** Peak-hold in Phase 7. Peak dot color = gray RGB(150,150,150).

---

## Spectrum Colors (color research session)

User requested checking the actual Winamp source for canonical spectrum colors before locking the Metal shader palette.

**Research finding:** `draw.cpp` lines 370–395 contain `ppal2[]` — the hardcoded default spectrum palette for when no `viscolor.txt` is present. 24 entries (sRGB). Key finding: the gradient runs index 17 (bottom = dark green RGB(24,132,8)) → index 2 (top = bright red RGB(239,49,16)). Peak dot = index 23 = RGB(150,150,150).

| Option | Description | Selected |
|--------|-------------|----------|
| Use ppal2 exactly | Faithful sRGB values, no P3 push | |
| Winamp base + P3 upgrade | Keep gradient shape, push 3 zones into P3 gamut | ✓ |
| Claude's discretion | Adjust on P3 surface | |

**P3 upgrade zones selected (multi-select):**
- Bright green zone (indices 11–12) → P3 neon green ✓
- Top red (indices 2–3) → P3 saturated red ✓
- Golden yellow (indices 8–9) → P3 vivid gold ✓
- Claude's discretion for transitions ✓

**User's choices:** ppal2 as base, all three zones pushed to P3, Claude discretion on interpolation.

---

## Claude's Discretion

- Exact `CAShapeLayer` mask API for NeoAero chrome cutout
- FFT update stride (every 1024 or 512 new samples)
- MTKView exact width and constraint anchors
- Whether to pre-compute Hann table for future toggle
- Rust `AtomicUsize` memory ordering for double-buffer index swap
- Whether magnitude is log-scaled before 0–15 normalization
- Gradient stop h-values may be adjusted if visual result is uneven

## Deferred Ideas

- v2 MPS two-pass bloom (SPEC-05)
- Hann windowing toggle
- Logarithmic frequency scale toggle
- `.wsz` skin-driven palette
- Oscilloscope mode
- Windowshade mini spectrum
