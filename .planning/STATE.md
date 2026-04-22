---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: ready_to_plan
last_updated: "2026-04-22T08:00:00.000Z"
progress:
  total_phases: 9
  completed_phases: 3
  total_plans: 9
  completed_plans: 9
  percent: 33
---

# MANZO — Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-20)

**Core value:** A tactile, skeuomorphic music player that sounds and looks like Winamp — running native on Apple Silicon, with glass chrome you can feel and DSP math bit-accurate to the original.
**Current focus:** Phase 4 — DSP Engine

---

## Milestone: v1.0

**Status:** Ready to plan
**Phases:** 9 total

| # | Phase | Status | Plans |
|---|-------|--------|-------|
| 1 | Build Foundation | Complete (3/3) | 3 |
| 2 | Audio Pipeline | Complete (3/3) | 3 |
| 3 | Playback Controls | Complete (3/3) | 3 |
| 4 | DSP Engine | Not Started | 0 |
| 5 | UI Shell | Not Started | 0 |
| 6 | Neo-Aero Visual Stack | Not Started | 0 |
| 7 | Spectrum Analyzer | Not Started | 0 |
| 8 | Playlist & Library | Not Started | 0 |
| 9 | Online Streaming | Not Started | 0 |

**Progress:** [███░░░░░░░] 33% (3/9 phases complete)

```
[██████████████████████████████] 100% (Phase 01 plans: 3/3)
[██████████████████████████████] 100% (Phase 02 plans: 3/3)
[██████████████████████████████] 100% (Phase 03 plans: 3/3)
```

---

## Performance Metrics

| Phase | Plan | Duration | Tasks | Files |
|-------|------|----------|-------|-------|
| 01-build-foundation | 01 | 4m | 2 | 5 |
| 01-build-foundation | 02 | 1m | 1 | 6 |
| 01-build-foundation | 03 | 2m | 2 | 2 |
| 03-playback-controls | 01 | 8m | 2 | 2 |
| 03-playback-controls | 02 | 9m | 2 | 3 |
| 03-playback-controls | 03 | 2m | 1 | 1 |

---

## Decisions

- cbindgen run via CLI (not just build.rs) to decouple header generation from Xcode build trigger (01-01)
- xcodegen project.yml as source of truth for ManzoApp.xcodeproj — reproducible, diff-friendly, avoids hand-editing pbxproj (01-02)
- Xcode project uses xcodegen (project.yml) for build config generation (01-03)
- cbindgen run-script must use subshell cd pattern: `(cd <crate-dir> && cbindgen ...)` — `--crate <path>` flag is not a directory argument (01-03)
- manzo_get_duration uses cached total_samples: i64 in InnerState — mpg123_scan() does not work on feed/push-API handles; probe via secondary file-API handle at open time (03-02)
- Swift polls manzo_get_state every 100ms on the main runloop; on ENDED (4), close-before-open ordering enforced to prevent two cpal streams simultaneously (03-03)

## Accumulated Context

### Known Constraints

- Liquid Glass AppKit material name unconfirmed — needs macOS 26 SDK prototype on Phase 5 day one (30-min Xcode experiment)
- Fallback: `NSHostingView` wrapping SwiftUI `.glassEffect()` if AppKit API not available; gate with `#available(macOS 26, *)`
- MTKView does NOT auto-configure P3 — `CAMetalLayer.colorspace` must be set explicitly (Phase 7)
- Two `.behindWindow` NSVisualEffectView in one window = double-blur artifact — enforce one-per-window rule (Phase 5)
- `isOpaque = false` must be set on NSWindow before `orderFront`; changing after causes compositor hiccup
- `shouldRasterize = true` requires `rasterizationScale = 2.0` on Retina or layers appear blurry
- ARCHS = arm64 / ONLY_ACTIVE_ARCH = NO required in Release config to force aarch64-apple-darwin target
- WR-01 (Phase 3 code review): startup-skip divisor should be `/(4*channels)` not `/4` — fix before Phase 4 DSP wiring
- WR-02 (Phase 3 code review): audio callback may spin on MPG123_OK + zero bytes in startup-skip block — fix before Phase 4

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
2026-04-20 — Phase 1 complete: Rust staticlib + cbindgen FFI bridge + Xcode wiring verified
2026-04-22 — Phase 2 complete: mpg123-sys + cpal float32 pipeline; audible playback confirmed
2026-04-22 — Phase 3 complete: playback state machine (PLAYING/PAUSED/STOPPED/ENDED), 529-sample trim, manzo_get_state/duration FFI, Swift auto-advance via 100ms polling; 3 hardware UAT items pending
