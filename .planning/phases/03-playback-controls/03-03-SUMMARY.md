---
phase: 03-playback-controls
plan: "03"
subsystem: ManzoApp
tags: [swift, appdelegate, auto-advance, polling-timer, ffi, audio-05]
dependency_graph:
  requires: [03-01]
  provides: [auto-advance-demo, AUDIO-05-proof]
  affects: [ManzoApp/ManzoApp/AppDelegate.swift]
tech_stack:
  added: []
  patterns: [timer-polling, close-before-open-stream-ordering, guard-null-ffi, invalidate-before-close]
key_files:
  created: []
  modified:
    - ManzoApp/ManzoApp/AppDelegate.swift
decisions:
  - MANZO_STATE_* constants defined as Int32 instance lets in AppDelegate (not C macros in bridging header) — self-contained, no header modification needed
  - pollTimer invalidated BEFORE manzo_close in applicationWillTerminate (T-03-13 use-after-free prevention)
  - manzo_close called BEFORE manzo_open in pollPlaybackState (T-03-14 single cpal stream invariant)
  - resolveFixturePath helper extracts path resolution logic — bundle first, dev fixture fallback
metrics:
  duration: ~2m
  completed: "2026-04-22T04:34:39Z"
  tasks_completed: 1
  files_modified: 1
---

# Phase 03 Plan 03: Swift Auto-Advance AppDelegate Summary

**One-liner:** AppDelegate replaced with Phase 3 auto-advance implementation: 2-track queue polled via 100ms Timer.scheduledTimer, with MANZO_STATE_ENDED (4) triggering close-before-open track handoff via manzo_get_state FFI.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Replace AppDelegate.swift with Phase 3 auto-advance implementation | b97a139 | ManzoApp/ManzoApp/AppDelegate.swift |

## What Was Built

### Task 1: Phase 3 AppDelegate Auto-Advance

Full rewrite of `ManzoApp/ManzoApp/AppDelegate.swift` from Phase 2 (single-track playback, 53 lines) to Phase 3 (2-track auto-advance with polling, 131 lines).

**New instance vars:**
- `MANZO_STATE_PLAYING: Int32 = 1`, `MANZO_STATE_PAUSED: Int32 = 2`, `MANZO_STATE_STOPPED: Int32 = 3`, `MANZO_STATE_ENDED: Int32 = 4` — D-02 constants as instance lets
- `trackQueue: [String] = []` — 2-entry queue built at launch
- `currentTrackIndex: Int = 0` — cursor into queue
- `pollTimer: Timer? = nil` — 100ms repeating main-runloop timer

**applicationDidFinishLaunching:**
- Builds `trackQueue` via `resolveFixturePath(name:ext:)` helper (bundle resource first, dev fixture fallback)
- Opens `trackQueue[0]` via `manzo_open`, calls `manzo_play`, guards on each step
- Arms `pollTimer = Timer.scheduledTimer(timeInterval: 0.1, ...)` targeting `#selector(pollPlaybackState)`
- NSLog: `"MANZO Phase 3: 100 ms state poll timer armed — queue size 2"`

**pollPlaybackState (new @objc method):**
- Guards `manzoHandle` not nil before every FFI call
- Reads `manzo_get_state(handle)` — returns immediately on any value != 4 (MANZO_STATE_ENDED)
- On ENDED: logs state=4, calls `manzo_close(handle)`, sets `manzoHandle = nil`, increments cursor
- Queue exhausted path: logs + `pollTimer?.invalidate()` + `pollTimer = nil`
- Missing next-track path: logs + invalidate + nil
- null-open path: logs + invalidate + nil
- Happy path: opens `nextPath`, plays, logs result

**applicationWillTerminate:**
- `pollTimer?.invalidate(); pollTimer = nil` FIRST (before handle operations)
- Then closes `manzoHandle` if non-nil (unchanged Phase 2 logic preserved)

**resolveFixturePath helper:**
- Bundle resource lookup via `Bundle.main.path(forResource:ofType:)`
- Fallback to `/Users/usameak42/Coding/MANZO/manzo-core/tests/fixtures/<name>.<ext>`

## Verification Results

| Check | Result |
|-------|--------|
| cargo build --target aarch64-apple-darwin | PASS (0.07s, no recompilation needed) |
| manzo_get_state in manzo_core.h | PASS (1 occurrence) |
| xcodebuild Debug build | ** BUILD SUCCEEDED ** |
| MANZO_STATE_PLAYING Int32 = 1 | PASS (count=1) |
| MANZO_STATE_PAUSED  Int32 = 2 | PASS (count=1) |
| MANZO_STATE_STOPPED Int32 = 3 | PASS (count=1) |
| MANZO_STATE_ENDED   Int32 = 4 | PASS (count=1) |
| trackQueue: [String] | PASS (count=1) |
| currentTrackIndex: Int | PASS (count=1) |
| pollTimer: Timer? | PASS (count=1) |
| Timer.scheduledTimer | PASS (count=1) |
| timeInterval: 0.1 | PASS (count=1) |
| @objc private func pollPlaybackState | PASS (count=1) |
| manzo_get_state(handle) | PASS (count=1) |
| MANZO_STATE_ENDED occurrences | PASS (count=4, >= 2 required) |
| pollTimer?.invalidate() occurrences | PASS (count=4, >= 2 required) |
| test2 in queue | PASS (count=2) |
| 3 lifecycle delegate methods | PASS (count=3) |
| manzo_close occurrences | PASS (count=3, >= 2 required) |
| pollPlaybackState occurrences | PASS (count=3, >= 2 required) |

## Deviations from Plan

None — plan executed exactly as written. AppDelegate.swift matches the specification verbatim.

## Known Stubs

None. `test2.mp3` path is included in `trackQueue` via the dev fixture fallback. If the file is absent (created by Plan 03-02), `FileManager.default.fileExists` returns false and `pollPlaybackState` logs "next track not found" and stops the timer cleanly — this is documented intended behavior per the plan, not a stub.

## Threat Flags

No new security surface beyond the plan's threat model. All four trust boundaries from the plan's threat register are mitigated in the implementation:

| Threat | Mitigation | Status |
|--------|-----------|--------|
| T-03-13 Timer fires after handle freed | `pollTimer?.invalidate(); pollTimer = nil` BEFORE `manzo_close` in applicationWillTerminate | Applied |
| T-03-14 Two cpal streams simultaneously | `manzo_close(handle)` + `manzoHandle = nil` BEFORE `manzo_open(nextPath)` | Applied |
| T-03-15 pollPlaybackState reads stale handle | `guard let handle = manzoHandle else { return }` at entry; local `handle` not re-used after close | Applied |
| T-03-18 trackQueue out-of-bounds | `guard currentTrackIndex < trackQueue.count` before every `trackQueue[currentTrackIndex]` access | Applied |

## Self-Check: PASSED

- ManzoApp/ManzoApp/AppDelegate.swift: EXISTS
- Commit b97a139: EXISTS (feat(03-03): replace AppDelegate with Phase 3 auto-advance implementation)
