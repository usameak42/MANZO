---
phase: 03-playback-controls
reviewed: 2026-04-22T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - manzo-core/src/lib.rs
  - manzo-core/manzo_core.h
  - manzo-core/tests/integration_test.rs
  - ManzoApp/ManzoApp/AppDelegate.swift
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-04-22T00:00:00Z
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Reviewed the Phase 3 playback-controls implementation: the Rust audio core (`lib.rs`), its cbindgen C header, the integration test suite, and the Swift `AppDelegate`. The critical path — state machine (D-02), duration probe (D-03), seek (D-04), and auto-advance polling (D-05) — is structurally sound. No security vulnerabilities or data-loss risks were found.

Two related bugs exist in the startup-skip (D-04, gapless trim) block: a wrong byte-to-frame divisor and a potential infinite-spin path when the decoder stalls silently. Both affect audio correctness. Two additional warnings cover input validation gaps that will matter in Phase 4 when the EQ and volume values are wired into the DSP chain.

---

## Warnings

### WR-01: Wrong byte-to-frame divisor in startup-skip branch causes 2x over-trim on stereo

**File:** `manzo-core/src/lib.rs:279`

**Issue:** `discarded_samples = discarded_bytes / 4` treats 4 bytes as one "sample". For a stereo f32 stream each *frame* (one time-unit across both channels) is 8 bytes (4 bytes × 2 channels). `startup_skip_remaining` is initialized to 529 to represent 529 *frames*, matching the mpg123 decoder startup delay measured in the spike. Dividing by 4 gives per-channel f32 values, so for a stereo track the counter decrements at half the correct rate — 1058 per-channel values (529 frames × 2 channels) are discarded instead of 529 frames. This doubles the gapless trim, cutting ~12 ms of audio that should be audible.

By contrast the main decode loop at line 323 correctly divides by `channels` to produce mono-equivalent frames, so the two counting schemes are inconsistent.

**Fix:**
```rust
// Replace line 279:
let discarded_samples = discarded_bytes / (4 * s.channels as usize);
// Rename for clarity — these are frames (mono-equivalent), not per-channel values
s.startup_skip_remaining = s
    .startup_skip_remaining
    .saturating_sub(discarded_samples as u64);
```

Also update line 267–268 to cap against frame count, not raw buffer length:
```rust
// The output buffer data[] contains per-channel f32; convert to frame count first
let remaining_frames = (data.len() - written) / s.channels as usize;
let skip_frames = (s.startup_skip_remaining as usize).min(remaining_frames);
let mut scratch = vec![0f32; skip_frames * s.channels as usize];
// then pass skip_frames * s.channels as usize * 4 as the byte count to mpg123_read
```

---

### WR-02: Potential infinite spin in startup-skip loop when decoder returns OK with zero bytes

**File:** `manzo-core/src/lib.rs:283`

**Issue:** The guard on line 283 only feeds a new chunk when `ret == MPG123_NEED_MORE && discarded_samples == 0`. If `mpg123_read` returns `MPG123_OK` (0) but produces `discarded_bytes == 0` — which can happen when the internal ring buffer is primed but the decoder is still warming up — the condition is false, no data is fed, `startup_skip_remaining` is not decremented (because `discarded_samples == 0`), and the loop immediately `continue`s and calls `mpg123_read` again with no new data. This spins indefinitely inside the audio callback, stalling the CoreAudio thread until the OS kills the stream.

**Fix:** Feed a new chunk whenever `discarded_samples == 0`, regardless of the return code:

```rust
if discarded_samples == 0 {
    // No progress — feed more data regardless of ret code to avoid spin
    let start = s.file_offset;
    let end = (start + FEED_CHUNK_SIZE).min(s.file_data.len());
    if start < s.file_data.len() {
        unsafe {
            mpg123_sys::mpg123_feed(
                s.mpg_handle,
                s.file_data[start..end].as_ptr(),
                end - start,
            );
        }
        s.file_offset = end;
    } else {
        // EOF during startup-skip — give up trimming, exit
        break;
    }
}
```

---

### WR-03: `manzo_set_eq` stores EQ gains without range validation

**File:** `manzo-core/src/lib.rs:500–503`

**Issue:** The API contract documents gains in the range ±12.0 dB, but values are copied from the caller-supplied slice verbatim with no clamping or NaN check. Phase 4 will feed these directly into the biquad DSP chain (the `eq10dsp.cpp` port). Passing gains outside ±12.0 dB or NaN/Inf will produce saturated or undefined DSP output. The bug is latent now but will be a correctness defect the moment the Phase 4 DSP chain is wired.

**Fix:**
```rust
let gain_slice = unsafe { std::slice::from_raw_parts(gains, 10) };
for (dst, &src) in state.eq_gains.iter_mut().zip(gain_slice.iter()) {
    // Clamp to documented range; reject NaN by letting clamp produce the boundary
    state.eq_gains[/* idx */] = src.clamp(-12.0, 12.0);
}
// Similarly clamp preamp:
state.eq_preamp = preamp.clamp(-12.0, 12.0);
```

Or more idiomatically:
```rust
let gain_slice = unsafe { std::slice::from_raw_parts(gains, 10) };
for (dst, &src) in state.eq_gains.iter_mut().zip(gain_slice.iter()) {
    *dst = src.clamp(-12.0_f32, 12.0_f32);
}
state.eq_preamp = preamp.clamp(-12.0_f32, 12.0_f32);
```

---

### WR-04: Hardcoded absolute developer path baked into the Swift binary

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:141`

**Issue:** The fallback path in `resolveFixturePath` is the literal string `/Users/usameak42/Coding/MANZO/manzo-core/tests/fixtures/\(name).\(ext)`. This path is compiled into the binary. On any machine other than the developer's Mac (including CI runners, test machines, or a future device) `FileManager.default.fileExists` returns false and the first track is silently skipped. The `NSLog` message at line 41 surfaces the failure, but it is easy to miss.

**Fix:** For Phase 3 demo scope, derive the fixture path relative to `Bundle.main.bundleURL` or use `ProcessInfo.processInfo.environment["MANZO_FIXTURE_DIR"]` for test overrides. At minimum, fail loudly with an assertion or `fatalError` in debug builds so the misconfiguration is caught at launch:

```swift
private func resolveFixturePath(name: String, ext: String) -> String {
    if let bundlePath = Bundle.main.path(forResource: name, ofType: ext) {
        return bundlePath
    }
    // Dev fallback — derive from bundle location rather than hardcoding developer home
    let devFixtures = Bundle.main.bundleURL
        .deletingLastPathComponent()          // .app
        .deletingLastPathComponent()          // build dir
        .appendingPathComponent("manzo-core/tests/fixtures/\(name).\(ext)")
        .path
    return devFixtures
}
```

---

## Info

### IN-01: `frames_written` variable name is misleading for a multi-channel stream

**File:** `manzo-core/src/lib.rs:320`

**Issue:** The comment says `// bytes → f32 samples` and the variable is named `frames_written`, but `done / 4` actually produces the count of per-channel f32 *values*, not stereo frames. For a 2-channel stream a "frame" is 2 samples = 8 bytes. The variable is then divided by `channels` on line 323 to get mono-equivalent frames for `position_samples`, which is correct — but the naming and comment create a false impression that the division has already happened. This is a latent source of confusion for Phase 4 when DSP processing is added to the callback.

**Fix:** Rename to `samples_written` (per-channel values) and update the comment:
```rust
let samples_written = done / 4; // bytes → per-channel f32 values
written += samples_written;
s.position_samples += samples_written as u64 / s.channels as u64;
```

---

### IN-02: `manzo_set_volume` and `manzo_set_pan` accept out-of-range values

**File:** `manzo-core/src/lib.rs:515–517`, `528–530`

**Issue:** `manzo_set_volume` stores `volume` without clamping to [0.0, 1.0] and `manzo_set_pan` stores `pan` without clamping to [-1.0, 1.0]. Unlike `manzo_set_eq` (WR-03), the downstream consequences are lower severity — clipping at the output stage rather than DSP chain corruption — but the same pattern applies. Invalid state will be silently stored and activated in Phase 4.

**Fix:**
```rust
// manzo_set_volume
state.volume = volume.clamp(0.0_f32, 1.0_f32);

// manzo_set_pan
state.pan = pan.clamp(-1.0_f32, 1.0_f32);
```

---

### IN-03: `state_becomes_ended_after_short_track_completes` uses a fixed 3-second deadline

**File:** `manzo-core/tests/integration_test.rs:204`

**Issue:** The test polls for `ENDED` (state=4) with a hardcoded 3-second deadline for a track described as "~1 second". If the audio hardware is slow to initialise (common on first-run CI agents) or if `test2.mp3` is longer than expected, the test could either produce a false timeout failure or pass without exercising the full decode. The deadline is not tied to the known duration of the fixture.

**Fix:** Derive the deadline from `manzo_get_duration` at runtime:
```rust
let duration_ms = unsafe { manzo_get_duration(handle) };
let deadline_ms = duration_ms.max(3000) + 500; // actual duration + 500 ms margin
let deadline = std::time::Instant::now()
    + std::time::Duration::from_millis(deadline_ms);
```

---

_Reviewed: 2026-04-22T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
