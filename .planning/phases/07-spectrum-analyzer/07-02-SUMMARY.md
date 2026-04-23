---
phase: 07-spectrum-analyzer
plan: "02"
subsystem: Metal Spectrum Renderer
tags: [metal, mtkview, spectrum, p3, hdr, sdf-bloom, peak-hold, cpal-displaylink]
dependency_graph:
  requires:
    - 07-01: Rust FFT pipeline (provides manzo_get_spectrum real data)
  provides:
    - ManzoSpectrumView: MTKView subclass ready for bodyView insertion (Plan 07-03)
    - Spectrum.metal: compiled shaders in default Metal library
  affects:
    - ManzoApp/project.yml: Metal + MetalKit frameworks added to target
tech_stack:
  added:
    - Metal.framework (GPU command encoding, MTLBuffer, MTLRenderPipelineState)
    - MetalKit.framework (MTKView)
    - CADisplayLink (macOS 14+, background thread render loop)
  patterns:
    - SDF single-pass Gaussian bloom (spike 011 validated)
    - storageModeShared MTLBuffer for CPU+GPU zero-copy on Apple Silicon
    - Additive blending (src*srcAlpha + dst*1) for neon glow accumulation
key_files:
  created:
    - ManzoApp/ManzoApp/ManzoSpectrumView.swift
    - ManzoApp/ManzoApp/Spectrum.metal
  modified:
    - ManzoApp/project.yml
decisions:
  - "SPEC-01: Set CAMetalLayer.pixelFormat + .colorspace + wantsExtendedDynamicRangeContent directly — MTKView.colorPixelFormat does not configure CAMetalLayer on manual render loops"
  - "SPEC-02: storageModeShared MTLBuffer satisfies zero-copy on Apple Silicon — ARM STORE to unified physical RAM, no DMA transfer"
  - "CHK-03: SDF distance computed in pt-space (not NDC) for isotropic bloom — view is 225×32 pt (not square), NDC-space distance is anisotropic"
  - "Peak-hold velocity decay: initial velocity 3.0/256.0, multiplied by spfo=1.1 each frame — matches Winamp draw_sa.cpp t_vx canonical pattern"
  - "commandQueue created lazily in viewDidMoveToWindow (also in startRenderLoop) to handle both wire-up orderings from AppDelegate"
metrics:
  duration: "3m 19s"
  completed: "2026-04-24"
  tasks_completed: 2
  files_changed: 3
---

# Phase 7 Plan 02: Metal Spectrum Renderer Summary

**One-liner:** MTKView subclass with .rgba16Float + displayP3 CAMetalLayer, storageModeShared FFT buffer, CADisplayLink background-thread render loop, Winamp spfo=1.1 peak-hold decay, and ppal2 5-stop P3-upgraded gradient Metal shaders.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | ManzoSpectrumView.swift — MTKView subclass with CADisplayLink render loop | 7b92795 | ManzoApp/ManzoApp/ManzoSpectrumView.swift |
| 2 | Spectrum.metal shader + project.yml Metal frameworks | aa77013 | ManzoApp/ManzoApp/Spectrum.metal, ManzoApp/project.yml |

## What Was Built

### Task 1: ManzoSpectrumView.swift

`ManzoSpectrumView` is a `MTKView` subclass that provides the complete Metal rendering stack for the MANZO spectrum analyzer.

**P3/HDR Metal configuration (SPEC-01):**
- `CAMetalLayer.pixelFormat = .rgba16Float` — set directly on the layer, not via `MTKView.colorPixelFormat`
- `CAMetalLayer.colorspace = CGColorSpace(name: CGColorSpace.displayP3)` — explicit, no silent sRGB fallback
- `CAMetalLayer.wantsExtendedDynamicRangeContent = true` — values > 1.0 render as true HDR highlights

**Buffers (SPEC-02):**
- `fftBuffer`: 75×Float32, `storageModeShared` — CPU-written by `manzo_get_spectrum`, GPU-read by vertex shaders without any copy. On Apple Silicon unified memory this is a plain ARM STORE to shared physical RAM.
- `barVertexBuffer` / `peakVertexBuffer`: CPU-built each frame, `storageModeShared`, 75×6 vertices each.

**Render loop (SPEC-04):**
- `CADisplayLink` added to a dedicated background `RunLoop` on a `Thread` named `ManzoSpectrumRender`
- `qualityOfService = .userInteractive` for display-rate priority
- Main thread is never blocked by GPU work

**Peak-hold (D-14, D-15, D-16):**
- `peakValues[75]` + `peakVelocity[75]` track per-bar state in normalized [0,1] space
- Snap-up on `fft > peak`; accelerating decay: `velocity *= 1.1` then `peak -= velocity` each frame
- Winamp canonical: `config_sa_peak_falloff=1 → spfo=1.1` from `draw_sa.cpp`

**Render encoding:**
- Pass 1: bar quads via `barPipelineState` (bars × 6 triangles per quad)
- Pass 2: peak dot quads via `peakPipelineState` (separate vertex buffer, stronger glow)
- `guard let` on drawable/commandQueue/descriptor — no crash on nil (T-07-05 mitigated)

**Architecture constraints honored:**
- No nested `NSVisualEffectView` — `ManzoSpectrumView` is a plain `MTKView`, not a vibrancy view
- `shouldRasterize` NOT set on the MTKView — it renders live, not rasterized
- P3 colors everywhere: all layer configuration uses `CGColorSpace.displayP3`

### Task 2: Spectrum.metal

Four shader functions implementing the visual design:

**`specColor(float h)` — 5-stop ppal2 gradient:**
| Stop | h | Source | Metal float4 |
|------|---|--------|--------------|
| Bottom | 0.00 | ppal2[17] RGB(24,132,8) | `float4(0.094, 0.518, 0.031, 1.0)` |
| Green peak | 0.35 | ppal2[12] + P3 push | `float4(0.000, 0.950, 0.060, 1.0)` |
| Yellow-green | 0.55 | ppal2[10] RGB(189,222,41) | `float4(0.741, 0.871, 0.161, 1.0)` |
| Gold | 0.70 | ppal2[8-9] + P3 push | `float4(0.920, 0.750, 0.000, 1.0)` |
| Top red | 1.00 | ppal2[2] + P3 push | `float4(1.000, 0.120, 0.040, 1.0)` |

**`barVertex` / `barFragment` — SDF bloom bars:**
- Buffer(0) reads `float4` vertices: [ndcX, ndcY, barIndex, barHeight]
- `uv_pt` converts NDC → pt-space: x=(ndcX+1)×112.5, y=(ndcY+1)×16.0
- SDF: `d_pt = length(max(d2_pt, 0)) + min(max(d2_pt.x, d2_pt.y), 0)` in pt-space
- Gaussian: `glow = exp(-d_pt² / (2×sigma²))`, sigma=2.0
- Output: `barColor * glow + barColor * step(d_pt, 0.5)` — halo + solid core

**`peakVertex` / `peakFragment` — peak-hold dots:**
- Same buffer layout and pt-space transform
- sigma=4.0 (D-16: σ×2.0 for stronger, softer glow)
- Color: `float4(0.588, 0.588, 0.588, 1.0)` = ppal2[23] RGB(150,150,150) (D-13)

**project.yml changes:**
- `Metal.framework` and `MetalKit.framework` added to `targets.ManzoApp.dependencies`
- Sources path `ManzoApp/` already covers new `.swift` and `.metal` files — no explicit listing needed

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

`ManzoSpectrumView.manzoHandle` is `nil` by default — `manzo_get_spectrum(nil, ...)` is called every frame until Plan 07-03 wires the handle from AppDelegate. The FFI stub currently zero-fills (flat spectrum), which is correct for Phase 7 Wave 1. Plan 07-03 (Wave 2) wires the real handle after Plan 07-01 delivers the live FFT.

## Threat Surface

No new trust boundaries beyond those declared in the plan's threat model:
- T-07-04 mitigated: `fftBuffer` is fixed 75×Float, count arg hardcoded as `75` — no overflow
- T-07-05 mitigated: `guard let` pattern in `render()` — returns early on nil drawable/commandQueue
- T-07-06 accepted: NSLayoutConstraint clipping deferred to Plan 07-03

## Self-Check: PASSED

- `/Users/usameak42/Coding/MANZO/ManzoApp/ManzoApp/ManzoSpectrumView.swift` — FOUND (392 lines)
- `/Users/usameak42/Coding/MANZO/ManzoApp/ManzoApp/Spectrum.metal` — FOUND
- `/Users/usameak42/Coding/MANZO/ManzoApp/project.yml` — Metal.framework + MetalKit.framework at lines 43-44
- Commit 7b92795 — Task 1 (ManzoSpectrumView.swift)
- Commit aa77013 — Task 2 (Spectrum.metal + project.yml)
