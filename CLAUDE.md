# MANZO

macOS music player — Winamp-inspired, Rust (audio/DSP) + Swift/AppKit (UI), Apple Silicon only.
Target: macOS Sequoia 15+, Apple Silicon. Aesthetic: Neo-Aero / Frutiger Aero with Liquid Glass + Vibrancy.

## Auto-load

- **Spike findings for MANZO** (audio pipeline, window architecture, Neo-Aero rendering, Metal spectrum) → `Skill("spike-findings-MANZO")`

## GSD Workflow

This project uses GSD (Get Shit Done) for planning and execution.

**Planning artifacts:** `.planning/` — ROADMAP.md, REQUIREMENTS.md, STATE.md, phases/
**Current milestone:** v1.0 — 9 phases, 32 requirements
**Mode:** YOLO (auto-approve), Fine granularity, Parallel execution

**Phase progression:**
1. Build Foundation → 2. Audio Pipeline → 3. Playback Controls → 4. DSP Engine
5. UI Shell → 6. Neo-Aero Visual Stack → 7. Spectrum Analyzer
8. Playlist & Library → 9. Online Streaming

**Key commands:**
- `/gsd-plan-phase N` — plan next phase
- `/gsd-execute-phase N` — execute a planned phase
- `/gsd-progress` — check current status

## Execution Rules

- When tasks within a phase are independent of each other, spawn multiple agents and run them in parallel. Do not work sequentially if parallelism is possible.

## Critical Constraints (from spikes)

- One `.behindWindow` NSVisualEffectView at window root ONLY — nested vibrancy = double-blur artifact
- All inner panels: CALayer-only, `isOpaque = false`, no nested NSVisualEffectView
- P3 colors everywhere: `CGColor(colorSpace: .displayP3)` — no sRGB
- MTKView: `.rgba16Float` + explicit `CAMetalLayer.colorspace` (P3 not auto-configured)
- `shouldRasterize = true` requires `rasterizationScale = 2.0` on Retina
- MP3 gapless: trim exactly 529 samples from mpg123 decoder output
- Float32 pipeline end-to-end — no int16 conversion in audio path
- FFI surface: exactly 11 `manzo_*` functions via cbindgen C header
