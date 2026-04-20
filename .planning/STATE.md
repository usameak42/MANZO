# MANZO — Project State

## Project Reference
See: .planning/PROJECT.md (updated 2026-04-20)

**Core value:** A tactile, skeuomorphic music player that sounds and looks like Winamp — running native on Apple Silicon, with glass chrome you can feel and DSP math bit-accurate to the original.
**Current focus:** Phase 1

---

## Milestone: v1.0

**Status:** Planning
**Phases:** 9 total

| # | Phase | Status | Plans |
|---|-------|--------|-------|
| 1 | Build Foundation | Not Started | 0 |
| 2 | Audio Pipeline | Not Started | 0 |
| 3 | Playback Controls | Not Started | 0 |
| 4 | DSP Engine | Not Started | 0 |
| 5 | UI Shell | Not Started | 0 |
| 6 | Neo-Aero Visual Stack | Not Started | 0 |
| 7 | Spectrum Analyzer | Not Started | 0 |
| 8 | Playlist & Library | Not Started | 0 |
| 9 | Online Streaming | Not Started | 0 |

**Progress:** 0/9 phases complete

```
[░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░] 0%
```

---

## Performance Metrics

*(Populated as phases complete)*

---

## Decisions

*(Populated as phases complete)*

---

## Accumulated Context

### Known Constraints

- Liquid Glass AppKit material name unconfirmed — needs macOS 26 SDK prototype on Phase 5 day one (30-min Xcode experiment)
- Fallback: `NSHostingView` wrapping SwiftUI `.glassEffect()` if AppKit API not available; gate with `#available(macOS 26, *)`
- Decoder delay is exactly 529 samples for MPEG Layer 3 — trim in Rust for gapless (Phase 3)
- MTKView does NOT auto-configure P3 — `CAMetalLayer.colorspace` must be set explicitly (Phase 7)
- Two `.behindWindow` NSVisualEffectView in one window = double-blur artifact — enforce one-per-window rule (Phase 5)
- `isOpaque = false` must be set on NSWindow before `orderFront`; changing after causes compositor hiccup
- `shouldRasterize = true` requires `rasterizationScale = 2.0` on Retina or layers appear blurry

### Open Questions

- macOS 26 SDK Liquid Glass AppKit API name — resolve in Phase 5

---

## Todos

*(Populated during execution)*

---

## Blockers

*(None currently)*

---

## Last Activity

2026-04-20 — Project initialized, roadmap created (9 phases, 32 requirements mapped)
