---
phase: 02-audio-pipeline
plan: 02
subsystem: audio-core
tags: [rust, ffi, mpg123, cpal, coreaudio, float32, arc-mutex]
dependency_graph:
  requires: [02-01]
  provides: [real-mp3-decode, cpal-output-stream, ffi-handle-lifecycle]
  affects: [manzo-core/src/lib.rs, ManzoApp (FFI consumer)]
tech_stack:
  added: [libc = "0.2"]
  patterns: [Arc<Mutex<>> threading, Box::into_raw/from_raw opaque handle, mpg123 feed/read streaming, cpal float32 output callback]
key_files:
  created: []
  modified:
    - manzo-core/src/lib.rs
    - manzo-core/Cargo.toml
    - manzo-core/Cargo.lock
    - manzo-core/manzo_core.h
decisions:
  - manzo_stop resets mpg123 by calling mpg123_open_feed again rather than mpg123_feedseek(0) — simpler and avoids edge cases with seek-before-index-built
  - libc added as explicit dep for off_t/size_t/SEEK_SET — mpg123-sys uses libc but does not re-export it
  - MPG123_FORCE_FLOAT flag applied via mpg123_param(MPG123_FLAGS, MPG123_FORCE_FLOAT as c_long, 0.0) — only the flags parm, value is the bitmask
metrics:
  duration: 5m
  completed: "2026-04-22T00:04:49Z"
  tasks_completed: 1
  files_modified: 4
---

# Phase 02 Plan 02: FFI Implementation — MP3 Decode + CoreAudio Output Summary

**One-liner:** Full mpg123 feed/read + cpal CoreAudio float32 pipeline replacing all 11 FFI stubs via Arc<Mutex<InnerState>> handle lifecycle.

## What Was Built

All 11 `manzo_*` FFI function bodies in `manzo-core/src/lib.rs` were replaced with a real implementation:

- `manzo_open`: reads file, inits mpg123 with `MPG123_FORCE_FLOAT`, opens feed mode, feeds first 4096-byte chunk, returns `Box::into_raw(Box::new(Arc::new(Mutex::new(InnerState))))` cast to `*mut ManzoHandle`
- `manzo_close`: `Box::from_raw` → drops Arc → `InnerState::Drop` calls `mpg123_delete`
- `manzo_play`: builds cpal float32 `CoreAudio` output stream; audio callback decodes float32 PCM directly from mpg123 into cpal's `&mut [f32]` buffer with feed-on-demand; stores stream in `InnerState`, sets `is_playing = true`
- `manzo_pause`: sets `is_playing = false`; callback silences; stream stays alive for resume
- `manzo_stop`: sets `is_playing = false`, resets position, drops stream, re-opens feed mode from byte 0
- `manzo_seek`: `mpg123_feedseek` to sample position, updates `file_offset` from returned byte offset
- `manzo_set_eq/set_volume/set_pan`: store values in `InnerState`; Phase 4 wires into DSP chain
- `manzo_get_position`: `(position_samples * 1000) / sample_rate`
- `manzo_get_spectrum`: `write_bytes(out_buf, 0, count)` zero-fill per D-01

## Decisions Made

1. `manzo_stop` resets mpg123 by calling `mpg123_open_feed` again rather than `mpg123_feedseek(0, SEEK_SET)` — simpler and avoids edge cases when the seek index hasn't been built yet on short files.

2. `libc = "0.2"` added as explicit dependency for `off_t`, `size_t`, `c_uchar`, `SEEK_SET` — `mpg123-sys` uses libc internally but does not re-export it.

3. `MPG123_FORCE_FLOAT` applied via `mpg123_param(MPG123_FLAGS, MPG123_FORCE_FLOAT as c_long, 0.0)` — the first non-handle param is the `mpg123_parms` enum (`MPG123_FLAGS`), the value argument is the bitmask cast to `c_long`.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written. One minor note: `libc` was not listed in the plan's Cargo.toml additions but is required because `mpg123-sys` does not re-export its libc types. Added under Rule 3 (blocking dependency).

## Threat Mitigations Applied

All T-02-XX threats from the plan's threat register were mitigated:

| Threat | Mitigation Applied |
|--------|-------------------|
| T-02-03 path injection | `CStr::from_ptr` → `to_str()` before filesystem access |
| T-02-04 null path UB | Null check is first statement before `CStr::from_ptr` |
| T-02-05 null handle deref | Every FFI function checks `handle.is_null()` as first guard |
| T-02-06 out_buf overrun | `if out_buf.is_null() \|\| count == 0` guard; writes exactly `count` bytes |
| T-02-07 resource leak | `Box::from_raw` in `manzo_close`; `InnerState::Drop` calls `mpg123_delete` |
| T-02-08 mutex poisoning | `lock().unwrap_or_else(\|e\| e.into_inner())` in all lock sites |

## Known Stubs

- `manzo_set_eq`, `manzo_set_volume`, `manzo_set_pan`: values stored in `InnerState` but not yet wired into the audio callback (Phase 4 responsibility). These are intentional stubs per the plan design.
- `manzo_get_spectrum`: returns 0.0-filled buffer (Phase 7 implements FFT). This is the correct D-01 contract — buffer is always written.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes introduced. All trust boundaries were pre-enumerated in the plan's threat model.

## Verification Results

1. `cargo test` — 5 tests pass (0 failures)
2. `grep "struct InnerState"` — match found
3. `grep "mpg123_open_feed"` — 2 matches (open + stop reset)
4. `grep "build_output_stream"` — match found
5. `grep "write_bytes(out_buf"` — match found (D-01)
6. `grep -c "i16\|int16"` in code — 0 (only in comment text)
7. `cargo build --target aarch64-apple-darwin` — exits 0

## Self-Check

### Files Exist
- `/Users/usameak42/Coding/MANZO/.claude/worktrees/agent-ae656207/manzo-core/src/lib.rs` — FOUND
- `/Users/usameak42/Coding/MANZO/.claude/worktrees/agent-ae656207/manzo-core/Cargo.toml` — FOUND

### Commits Exist
- `fa3d2a5` — feat(02-02): implement InnerState, threading model, and all 11 FFI function bodies

## Self-Check: PASSED
