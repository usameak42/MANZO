# Spike Wrap-Up Summary

**Date:** 2026-04-20
**Spikes processed:** 11 (all included)
**Feature areas:** Audio DSP Pipeline, Window & Glass Architecture, Neo-Aero Visual Stack, Metal Spectrum Renderer
**Skill output:** `./.claude/skills/spike-findings-MANZO/`

## Included Spikes

| # | Name | Verdict | Feature Area |
|---|------|---------|--------------|
| 001 | dsp-plugin-interface | VALIDATED | Audio DSP Pipeline |
| 002 | eq-math-vs-ui | VALIDATED | Audio DSP Pipeline |
| 003 | mp3-decoder-depth | VALIDATED | Audio DSP Pipeline |
| 004 | playback-pipeline-flow | VALIDATED | Audio DSP Pipeline |
| 005 | liquid-glass-appkit-access | PARTIAL | Window & Glass Architecture |
| 006 | frameless-plus-liquid-glass | VALIDATED | Window & Glass Architecture |
| 007 | glass-on-glass-compositing | VALIDATED | Window & Glass Architecture |
| 008 | aero-specular-stack-calayer | VALIDATED | Neo-Aero Visual Stack |
| 009 | dynamic-wet-reflection | VALIDATED | Neo-Aero Visual Stack |
| 010 | p3-color-in-appkit-metal | VALIDATED | Neo-Aero Visual Stack |
| 011 | spectrum-bloom-metal | VALIDATED | Metal Spectrum Renderer |

## Excluded Spikes

None.

## Key Findings

**Audio core**: Port `eq10dsp.cpp` dual-biquad IIR verbatim to Rust (~200 lines). Collapse the double int16↔float conversion waterfall — run float32 end-to-end. Trim 529-sample decoder delay for gapless. Replace `Out_Module` with `AVAudioPlayerNode`.

**Window**: One `.behindWindow` NSVisualEffectView at window root. All panels are CALayer-only — glass-on-glass appearance comes from semi-transparent layers over the glass body, not nested vibrancy. `isOpaque = false` mandatory. Liquid Glass AppKit API name unconfirmed — needs macOS 26 SDK prototype on day one.

**Neo-Aero rendering**: Full 5-layer specular stack (base gradient → specular band → lower glow → rim → reflection) achievable with pure CALayer, no bitmaps. `CAReplicatorLayer` for wet-floor reflections. All brand colors as `CGColor(colorSpace: displayP3)`. `shouldRasterize = true` for static panels.

**Spectrum**: `MTKView` with `.rgba16Float` + explicit P3 colorspace. SDF single-pass bloom for v1. FFT data via shared `MTLBuffer` from Rust core. `CADisplayLink` render loop on background thread.
