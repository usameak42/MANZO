---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-04-20T16:06:00Z"
progress:
  total_phases: 9
  completed_phases: 1
  total_plans: 3
  completed_plans: 3
  percent: 11
---

# MANZO — Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-20)

**Core value:** A tactile, skeuomorphic music player that sounds and looks like Winamp — running native on Apple Silicon, with glass chrome you can feel and DSP math bit-accurate to the original.
**Current focus:** Phase 01 — Build Foundation

---

## Milestone: v1.0

**Status:** Phase 01 Complete — Ready for Phase 02
**Phases:** 9 total

| # | Phase | Status | Plans |
|---|-------|--------|-------|
| 1 | Build Foundation | Complete (3/3) | 3 |
| 2 | Audio Pipeline | Not Started | 0 |
| 3 | Playback Controls | Not Started | 0 |
| 4 | DSP Engine | Not Started | 0 |
| 5 | UI Shell | Not Started | 0 |
| 6 | Neo-Aero Visual Stack | Not Started | 0 |
| 7 | Spectrum Analyzer | Not Started | 0 |
| 8 | Playlist & Library | Not Started | 0 |
| 9 | Online Streaming | Not Started | 0 |

**Progress:** [█░░░░░░░░░] 11% (1/9 phases complete)

```
[██████████████████████████████] 100% (Phase 01 plans: 3/3)
```

---

## Performance Metrics

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 01-build-foundation | 01 | 4m | 2 | 5 |
| 01-build-foundation | 02 | 1m | 1 | 6 |
| 01-build-foundation | 03 | 2m | 2 | 2 |

---

## Decisions

- cbindgen run via CLI (not just build.rs) to decouple header generation from Xcode build trigger (01-01)
- xcodegen project.yml as source of truth for ManzoApp.xcodeproj — reproducible, diff-friendly, avoids hand-editing pbxproj (01-02)
- Xcode project uses xcodegen (project.yml) for build config generation (01-03)
- cbindgen run-script must use subshell cd pattern: `(cd <crate-dir> && cbindgen ...)` — `--crate <path>` flag is not a directory argument (01-03)

## Accumulated Context

### Known Constraints

- Liquid Glass AppKit material name unconfirmed — needs macOS 26 SDK prototype on Phase 5 day one (30-min Xcode experiment)
- Fallback: `NSHostingView` wrapping SwiftUI `.glassEffect()` if AppKit API not available; gate with `#available(macOS 26, *)`
- Decoder delay is exactly 529 samples for MPEG Layer 3 — trim in Rust for gapless (Phase 3)
- MTKView does NOT auto-configure P3 — `CAMetalLayer.colorspace` must be set explicitly (Phase 7)
- Two `.behindWindow` NSVisualEffectView in one window = double-blur artifact — enforce one-per-window rule (Phase 5)
- `isOpaque = false` must be set on NSWindow before `orderFront`; changing after causes compositor hiccup
- `shouldRasterize = true` requires `rasterizationScale = 2.0` on Retina or layers appear blurry
- ARCHS = arm64 / ONLY_ACTIVE_ARCH = NO required in Release config to force aarch64-apple-darwin target

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
2026-04-20 — 01-02 complete: ManzoApp Xcode project (xcodegen, run-script cargo build, bridging header, AppDelegate FFI smoke test)
2026-04-20 — 01-03 complete: Build verification gate passed — all 8 criteria green; Phase 1 complete
