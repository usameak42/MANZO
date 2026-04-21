---
phase: 02-audio-pipeline
plan: 01
subsystem: audio
tags: [rust, cargo, mpg123-sys, cpal, mp3, coreaudio, testing]

# Dependency graph
requires:
  - phase: 01-build-foundation
    provides: manzo-core Cargo.toml with staticlib configuration and cbindgen build dep
provides:
  - mpg123-sys = "0.1" and cpal = "0.15" in manzo-core [dependencies]
  - manzo-core/tests/fixtures/test.mp3 — CC0 5-second 440 Hz stereo MP3 at 44100 Hz
  - Cargo.lock with 93 resolved packages including audio decode and output crates
affects: [02-audio-pipeline/02-02, 02-audio-pipeline/02-03, 04-dsp-engine]

# Tech tracking
tech-stack:
  added:
    - mpg123-sys v0.1.0 (MPEG Layer 3 decode via libmpg123)
    - cpal v0.15.3 (cross-platform audio output, CoreAudio backend on macOS)
    - coreaudio-rs v0.11.3 (pulled transitively by cpal)
    - coreaudio-sys v0.2.17 (pulled transitively by cpal)
  patterns:
    - Test fixtures in manzo-core/tests/fixtures/ for integration testing
    - CC0-only test assets generated locally (no downloaded content)

key-files:
  created:
    - manzo-core/tests/fixtures/test.mp3
    - manzo-core/Cargo.lock
  modified:
    - manzo-core/Cargo.toml

key-decisions:
  - "Used lameenc Python library to synthesize test MP3 locally when ffmpeg/sox unavailable — guarantees CC0 provenance"
  - "Pinned mpg123-sys = 0.1 per plan (v0.6.0 available but plan specifies 0.1 for API compatibility with Phase 2 implementation)"
  - "Pinned cpal = 0.15 per plan (v0.17.3 available but plan specifies 0.15 for stable CoreAudio backend)"

patterns-established:
  - "Test fixtures live in manzo-core/tests/fixtures/ — use this path for all integration test assets"
  - "MP3 test asset: MPEG ADTS layer III, 44100 Hz, stereo, 128 kbps — reference spec for decoder tests"

requirements-completed: [AUDIO-04]

# Metrics
duration: 10min
completed: 2026-04-22
---

# Phase 2 Plan 01: Audio Pipeline Dep Setup Summary

**mpg123-sys v0.1.0 and cpal v0.15.3 added to Cargo.toml with 93-package lock; CC0 5-second 440 Hz stereo MP3 fixture synthesized locally at manzo-core/tests/fixtures/test.mp3**

## Performance

- **Duration:** ~10 min
- **Started:** 2026-04-22T02:45:00Z
- **Completed:** 2026-04-22T02:56:00Z
- **Tasks:** 2 completed
- **Files modified:** 3 (Cargo.toml, Cargo.lock, tests/fixtures/test.mp3)

## Accomplishments

- Added [dependencies] section to manzo-core/Cargo.toml with mpg123-sys = "0.1" and cpal = "0.15"
- cargo fetch resolved all 93 transitive packages without error, including coreaudio-rs and coreaudio-sys
- Generated CC0 5-second sine tone MP3 (440 Hz, stereo, 44100 Hz, 128 kbps, 80666 bytes) via local synthesis using lameenc — no third-party content

## Task Commits

Each task was committed atomically:

1. **Task 1: Add mpg123-sys and cpal to Cargo.toml** - `730af8f` (chore)
2. **Task 2: Generate CC0 test MP3 fixture** - `fab0195` (chore)

**Plan metadata:** (committed with SUMMARY.md)

## Files Created/Modified

- `manzo-core/Cargo.toml` - Added [dependencies] section with mpg123-sys = "0.1" and cpal = "0.15"
- `manzo-core/Cargo.lock` - Generated with 93 resolved packages
- `manzo-core/tests/fixtures/test.mp3` - CC0 MPEG Layer 3 file, 5s, 44100 Hz stereo, 128 kbps, 80666 bytes

## Decisions Made

- Used lameenc Python package for MP3 synthesis since ffmpeg and sox were not installed. lameenc produces valid MPEG Layer 3 output (verified by `file(1)`), guarantees CC0 provenance from local generation, and requires no system audio tool installation.
- Kept version pins exactly as specified in the plan (mpg123-sys = "0.1", cpal = "0.15") even though newer versions exist, to ensure API compatibility with the Phase 2 implementation plan (02-02).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Used lameenc instead of ffmpeg/sox for MP3 generation**
- **Found during:** Task 2 (Generate CC0 test MP3 fixture)
- **Issue:** Plan specified ffmpeg or sox for MP3 generation; neither was installed on the system
- **Fix:** Installed lameenc Python package and generated MP3 programmatically from a 440 Hz sine wave — identical audio content, same file format, identical CC0 provenance guarantee
- **Files modified:** manzo-core/tests/fixtures/test.mp3
- **Verification:** `file(1)` confirms "MPEG ADTS, layer III, v1, 128 kbps, 44.1 kHz, JntStereo"; size 80666 bytes (within 20-200 KB window)
- **Committed in:** fab0195

---

**Total deviations:** 1 auto-fixed (1 blocking — tool substitution)
**Impact on plan:** Zero impact. Same file format, same audio spec, stronger CC0 provenance (locally synthesized). No scope creep.

## Issues Encountered

- ffmpeg and sox not found at `/opt/homebrew/bin/` or `/usr/local/bin/`. Resolved by installing lameenc via pip3 and generating the MP3 from a Python sine wave synthesis loop.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Plan 02-02 (lib.rs FFI implementation) is now unblocked: mpg123-sys and cpal are in Cargo.toml and resolved
- Plan 02-03 (integration tests + AppDelegate) is unblocked: test.mp3 fixture exists at the expected path
- Both crates compile for aarch64-apple-darwin (CoreAudio backend selected automatically by cpal on macOS)

---
*Phase: 02-audio-pipeline*
*Completed: 2026-04-22*

## Self-Check: PASSED

- FOUND: manzo-core/Cargo.toml
- FOUND: manzo-core/tests/fixtures/test.mp3
- FOUND: .planning/phases/02-audio-pipeline/02-01-SUMMARY.md
- FOUND commit: 730af8f (chore(02-01): add mpg123-sys and cpal runtime deps to Cargo.toml)
- FOUND commit: fab0195 (chore(02-01): add CC0 test MP3 fixture for integration tests)
