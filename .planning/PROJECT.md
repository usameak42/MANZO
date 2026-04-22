# MANZO

## What This Is

MANZO is a native macOS music player built in the spirit of classic Winamp — delivering its
skeuomorphic Neo-Aero aesthetic and precise DSP fidelity on modern Apple Silicon hardware.
The core is written in Rust (audio decode, 10-band EQ, spectrum FFT) and the UI in Swift/AppKit
with Metal rendering; it targets macOS Sequoia 15+ exclusively and bundles yt-dlp for
URL-based streaming.

## Core Value

A tactile, skeuomorphic music player that sounds and looks like Winamp — running native on
Apple Silicon, with glass chrome you can feel and DSP math that is bit-accurate to the original.

## Requirements

### Validated

- [x] Rust + Swift/AppKit FFI bridge via cbindgen — arm64 staticlib, C header, all 11 functions linked (Phase 1)
- [x] Xcode + Cargo dual build system — run-script triggers cargo automatically, xcodebuild exits 0 (Phase 1)
- [x] MP3 decode pipeline: mpg123-sys feed/read → cpal float32 CoreAudio output, no int16 conversion (Phase 2)
- [x] Gapless MP3 playback — 529-sample decoder delay trim, auto-advance via 100ms state poll (Phase 3)

### Active

- [ ] 10-band EQ (eq10dsp.cpp port to Rust, dual-biquad IIR — gains pre-validated ±12 dB in FFI)
- [ ] Frameless NSWindow with single-root `.behindWindow` vibrancy
- [ ] 5-layer Neo-Aero specular panel stack (pure CALayer, no bitmaps)
- [ ] Metal spectrum analyzer (MTKView, rgba16Float, P3, SDF bloom)
- [ ] Local playlist management with persistence
- [ ] yt-dlp sidecar for URL streaming

### Out of Scope

- Windows / Linux — Apple Silicon macOS only; no cross-platform abstraction
- iOS / iPadOS — desktop-first, no UIKit port
- Win32 DSP plugin DLLs — macOS-native pipeline, AUv3 for v2+
- Online store / subscriptions — playback tool, not a service
- AirPlay / DLNA — network output deferred to future milestone

## Context

- **11 spikes completed (all validated)** covering: DSP pipeline, MP3 decoder delay, EQ math,
  Liquid Glass AppKit access, frameless window compositing, glass-on-glass CALayer, Neo-Aero
  specular stack, CAReplicatorLayer reflections, P3 color in AppKit + Metal, spectrum bloom
- Winamp source reference is in `winamp/` (Src/ and BuildTools/)
- Tech stack decision: Option B (Rust + Swift) — see `.planning/spikes/TECH-STACK-PROPOSAL.md`
- Liquid Glass AppKit API name unconfirmed; macOS 26 SDK prototype needed on day one
- `CAReplicatorLayer` confirmed for wet-floor reflections
- Decoder delay: 529 samples — must be trimmed in Rust for true gapless

## Constraints

- **Platform**: macOS Sequoia 15+, Apple Silicon (arm64) only — Metal, NEON SIMD, Liquid Glass
- **Language split**: Rust (audio/DSP/FFT), Swift/AppKit (UI/Metal) — FFI via cbindgen C header
- **Build system**: Cargo + Xcode dual build; no pure-Swift audio allowed
- **Color**: P3 wide-gamut throughout — `CGColor(colorSpace: displayP3)` mandatory for all brand colors
- **No bitmaps in chrome**: All panel specular/glow/reflection achieved via CALayer API
- **Performance**: EQ < 0.1 ms per 1024-sample buffer on M1; spectrum at display refresh rate

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Rust + Swift/AppKit (Option B) | Direct eq10dsp.cpp port, safe concurrency, explicit NEON SIMD | — Pending |
| mpg123-sys for MP3 decode | Feed/read streaming API, explicit 529-sample delay tracking | Validated in Phase 2 |
| cpal for audio output | CoreAudio wrapper, matches Out_Module::Write non-blocking model | Validated in Phase 2 |
| One `.behindWindow` NSVisualEffectView at window root | CALayer-only panels avoid nested vibrancy artifacts (spike 007) | — Pending |
| Float32 pipeline end-to-end | Eliminates double int16↔float conversion waterfall (spike 004) | — Pending |
| MTKView with .rgba16Float + P3 | Wide-gamut spectrum from day one (spike 010, 011) | — Pending |
| SDF single-pass bloom for spectrum v1 | MPS two-pass deferred to v2 (spike 011) | — Pending |
| cbindgen for Swift-Rust FFI | Clean C header, ~10 function surface | Validated — Phase 1 |
| startup-skip divisor uses `/(4*channels)` not `/4` | Per-channel f32 values ≠ mono frames; wrong divisor doubled gapless trim to 1058 samples | Fixed in code review (Phase 3) |
| Test fixtures as Xcode Copy Bundle Resources | DerivedData path traversal from bundleURL is unreliable; bundle resources resolve correctly on all machines | Validated — Phase 3 |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-22 — Phase 3 complete (Playback Controls: state machine, 529-sample gapless trim, Swift auto-advance)*
