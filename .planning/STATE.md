---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: in_progress
last_updated: "2026-04-24T08:00:00.000Z"
progress:
  total_phases: 9
  completed_phases: 6
  total_plans: 25
  completed_plans: 19
  percent: 88
---

# MANZO — Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-04-22)

**Core value:** A tactile, skeuomorphic music player that sounds and looks like Winamp — running native on Apple Silicon, with glass chrome you can feel and DSP math bit-accurate to the original.
**Current focus:** Phase 8 — Playlist & Library

---

## Milestone: v1.0

**Status:** Ready to plan
**Phases:** 9 total

| # | Phase | Status | Plans |
|---|-------|--------|-------|
| 1 | Build Foundation | Complete (3/3) | 3 |
| 2 | Audio Pipeline | Complete (3/3) | 3 |
| 3 | Playback Controls | Complete (3/3) | 3 |
| 4 | DSP Engine | Complete (3/3) | 3 |
| 5 | UI Shell | Complete (2/2) | 2 |
| 6 | Neo-Aero Visual Stack | Complete (3/3) | 3 |
| 7 | Spectrum Analyzer | Complete (3/3) | 3 |
| 8 | Playlist & Library | Ready to execute (5/5) | 5 |
| 9 | Online Streaming | Not Started | 0 |

**Progress:** [██████░░░░] 67% (6/9 phases complete)

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

- Liquid Glass AppKit material name unconfirmed — Phase 5 uses `ManzoGlassMaterial` named constant; update in one place when macOS 26 SDK confirms the case name. No Sequoia fallback — macOS 26 minimum.
- MTKView does NOT auto-configure P3 — `CAMetalLayer.colorspace` must be set explicitly (Phase 7)
- Two `.behindWindow` NSVisualEffectView in one window = double-blur artifact — enforce one-per-window rule (Phase 5)
- `isOpaque = false` must be set on NSWindow before `orderFront`; changing after causes compositor hiccup
- `shouldRasterize = true` requires `rasterizationScale = 2.0` on Retina or layers appear blurry
- ARCHS = arm64 / ONLY_ACTIVE_ARCH = NO required in Release config to force aarch64-apple-darwin target

### Open Questions

- macOS 26 SDK Liquid Glass AppKit API name — resolve in Phase 5
- EQ band boost via manzo_set_eq (DSP-02) NOT fully verified with real audio — UAT key 1 fired during playback but no MP3 with rich frequency content was available to hear the effect clearly. Re-test in Phase 8/9 when playlist has real user-selected files.

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
2026-04-22 — Phase 3 complete: playback state machine, gapless 529-sample trim (divisor fixed), Swift auto-advance; UAT 5/5 passed; code review fixes applied (WR-01–04)
2026-04-23 — Phase 5 context gathered: frameless 275×116 NSWindow, ManzoGlassMaterial constant, named panel NSViews (titleView/bodyView/statusView), mouseDown drag pattern
2026-04-23 — Phase 4 complete: eq10dsp.cpp Rust port, 5-stage DSP chain wired into cpal callback, perf gate passes; EQ band boost deferred re-test to Phase 8/9
2026-04-24 — Phase 6 complete: NeoAeroLayerFactory + ManzoVisualStyle + applyStyle wired; 5-layer P3 chrome, CAReplicatorLayer wet-floor, rasterization; 2 visual UAT items pending human run
2026-04-24 — Phase 7 Wave 1 complete: Rust FFT pipeline (rustfft 1024-pt, 75 bars, try_lock double-buffer) + Metal renderer (ManzoSpectrumView .rgba16Float+displayP3, Spectrum.metal SDF bloom, Winamp peak-hold)
2026-04-24 — Phase 7 UAT approved: spectrum bars visible during playback; 3 UAT fixes applied (bundle path, unifiedSlab NeoAeroContainer lookup, dangling-handle crash); Metal MTLRenderPassDescriptor warning fixed; full spectrum test deferred to Phase 8 with real audio files
2026-04-24 — Phase 8 Wave 2 complete: 08-03 (AppDelegate full integration — PlaylistManager wiring, PL button, co-move, Alt+E, NSTableViewDataSource validateDrop+acceptDrop) + 08-04 (ManzoPlaylistPanel drag registration, Delete key, right-click context menu) — xcodebuild BUILD SUCCEEDED; PlaylistManager.swift added to pbxproj
2026-04-24 — Phase 8 planned: 5 plans across 3 waves (Wave 1: model layer + visual shell in parallel; Wave 2: AppDelegate wiring + drag-reorder in parallel; Wave 3: UAT checkpoint); all LIB-01–04 covered; verification passed
