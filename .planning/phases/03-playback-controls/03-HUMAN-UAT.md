---
status: partial
phase: 03-playback-controls
source: [03-VERIFICATION.md]
started: 2026-04-22T07:50:00.000Z
updated: 2026-04-22T07:50:00.000Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Gapless track boundary
expected: No audible pop or silence gap at the handoff between test.mp3 and test2.mp3 when AppDelegate auto-advances. A brief silence is acceptable per D-05; zero audible pop from the mpg123 decoder-delay trim is the goal.
result: [pending]

### 2. Seek without audible glitch
expected: After seeking, playback resumes from the correct position with no decoder artifact. Confirm the 529-sample startup trim does NOT re-fire on seek (manzo_seek must not touch startup_skip_remaining — D-04).
result: [pending]

### 3. Ignored integration tests with audio hardware
expected: `cd manzo-core && cargo test -- --ignored` passes all 3 hardware-dependent tests: `state_transitions_play_pause_stop` and `state_becomes_ended_after_short_track_completes` when audio output is available.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
