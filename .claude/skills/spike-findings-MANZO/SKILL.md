---
name: spike-findings-MANZO
description: Validated patterns, constraints, and implementation knowledge from spike experiments for the MANZO macOS music player (Winamp-inspired, Rust+Swift, Frutiger Aero/Liquid Glass UI). Auto-loaded during implementation work on MANZO.
---

<context>
## Project: MANZO

macOS music player inspired by Winamp. Tech stack: Rust (audio/DSP core) + Swift/AppKit (UI).
Target: macOS Sequoia+ (15+), Apple Silicon only. Aesthetic: Frutiger Aero / Neo-Aero composed
with macOS Liquid Glass + Vibrancy — physical glass simulation, aqua/teal P3 color language,
wet-floor reflections, neon spectrum analyzer. Single frameless NSWindow with draggable panels.

Spike sessions wrapped: 2026-04-20
</context>

<findings_index>
## Feature Areas

| Area | Reference | Key Finding |
|------|-----------|-------------|
| Audio DSP Pipeline | references/audio-dsp-pipeline.md | Collapse double int16↔float conversion; port eq10dsp.cpp dual-biquad verbatim; decoder delay = 529 samples |
| Window & Glass Architecture | references/window-glass-architecture.md | One `.behindWindow` NSVisualEffectView at root only; all inner panels are CALayer-only; Liquid Glass API name needs macOS 26 SDK prototype |
| Neo-Aero Visual Stack | references/neo-aero-visual-stack.md | Full 5-layer specular stack via CAGradientLayer, no bitmaps; CAReplicatorLayer for reflections; P3 CGColor for all brand colors |
| Metal Spectrum Renderer | references/metal-spectrum-renderer.md | SDF single-pass bloom for v1; MPS two-pass for v2; rgba16Float + P3 colorspace on MTKView from day one |

## Source Files

Original spike READMEs preserved in `sources/` for complete reference.
</findings_index>

<metadata>
## Processed Spikes

- 001-dsp-plugin-interface
- 002-eq-math-vs-ui
- 003-mp3-decoder-depth
- 004-playback-pipeline-flow
- 005-liquid-glass-appkit-access
- 006-frameless-plus-liquid-glass
- 007-glass-on-glass-compositing
- 008-aero-specular-stack-calayer
- 009-dynamic-wet-reflection
- 010-p3-color-in-appkit-metal
- 011-spectrum-bloom-metal
</metadata>
