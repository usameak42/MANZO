---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-04-20T15:59:18.115Z"
progress:
  total_phases: 9
  completed_phases: 0
  total_plans: 3
  completed_plans: 1
  percent: 33
---

# MANZO — Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-20)

**Core value:** A tactile, skeuomorphic music player that sounds and looks like Winamp — running native on Apple Silicon, with glass chrome you can feel and DSP math bit-accurate to the original.
**Current focus:** Phase 01 — Build Foundation

---

## Milestone: v1.0

**Status:** Executing Phase 01
**Phases:** 9 total

| # | Phase | Status | Plans |
|---|-------|--------|-------|
| 1 | Build Foundation | In Progress (1/3) | 3 |
| 2 | Audio Pipeline | Not Started | 0 |
| 3 | Playback Controls | Not Started | 0 |
| 4 | DSP Engine | Not Started | 0 |
| 5 | UI Shell | Not Started | 0 |
| 6 | Neo-Aero Visual Stack | Not Started | 0 |
| 7 | Spectrum Analyzer | Not Started | 0 |
| 8 | Playlist & Library | Not Started | 0 |
| 9 | Online Streaming | Not Started | 0 |

**Progress:** 0/9 phases complete (1/3 plans in Phase 01)

```
[███░░░░░░░░░░░░░░░░░░░░░░░░░░░] 33% (Phase 01 plans)
```

---

## Performance Metrics

*(Populated as phases complete)*

---

## Decisions

- cbindgen run via CLI (not just build.rs) to decouple header generation from Xcode build trigger (01-01)

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
2026-04-20 — Phase 1 planned (3 plans, 3 waves): Rust staticlib + cbindgen FFI bridge + Xcode wiring
2026-04-20 — 01-01 complete: manzo-core staticlib (11 FFI stubs, manzo_core.h, arm64 libmanzo_core.a, 4 tests pass)
