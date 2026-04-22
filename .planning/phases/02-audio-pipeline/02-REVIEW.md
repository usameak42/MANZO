---
phase: 02-audio-pipeline
reviewed: 2026-04-22T00:18:28Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - manzo-core/src/lib.rs
  - manzo-core/Cargo.toml
  - manzo-core/tests/integration_test.rs
  - ManzoApp/ManzoApp/AppDelegate.swift
  - ManzoApp/project.yml
findings:
  critical: 0
  warning: 4
  info: 4
  total: 8
status: issues_found
---

# Phase 2: Code Review Report

**Reviewed:** 2026-04-22T00:18:28Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Phase 2 delivers a real MP3 decode and CoreAudio output pipeline via the
mpg123 feed API, cpal, and an 11-function FFI surface. The Float32 end-to-end
constraint is correctly enforced with `MPG123_FORCE_FLOAT`. All FFI entry
points null-check their handle argument with one documented exception
(`manzo_get_spectrum`, a Phase 7 stub that intentionally ignores the handle).

Four warnings were found — no critical (security or crash) issues. The most
actionable are: the silent discard of `mpg123_open_feed`'s return value in
`manzo_stop` (leaving the decoder in an unknown state on failure), a
potential integer-overflow / wrap-around on the `off_t → usize` cast in
`manzo_seek`, and the mutex being held across the entire decode loop which
can stall the UI thread during `manzo_pause` or `manzo_seek`.

---

## Warnings

### WR-01: `manzo_stop` discards `mpg123_open_feed` return value — decoder may be in unknown state

**File:** `manzo-core/src/lib.rs:303`
**Issue:** `mpg123_open_feed` returns an `mpg123_errors` code (0 = `MPG123_OK`). The
return value is silently discarded on line 303. If it fails, the subsequent
`mpg123_feed` call on line 304 sends data into a handle that is not in feed
mode, which can produce garbled output or panic the callback on the next
`mpg123_read` call. The same pattern was applied correctly for the initial
`manzo_open` path (lines 102–106 check and early-return on failure) but was
omitted in `manzo_stop`.

**Fix:**
```rust
// manzo_stop reset block — check return value and log/ignore gracefully
let feed_ret = unsafe { mpg123_sys::mpg123_open_feed(state.mpg_handle) };
if feed_ret == 0 {
    unsafe {
        mpg123_sys::mpg123_feed(
            state.mpg_handle,
            state.file_data.as_ptr(),
            first_chunk_len,
        );
    }
    state.file_offset = first_chunk_len;
} else {
    // Open-feed reset failed; leave offset at 0 — next play will rebuild stream
    state.file_offset = 0;
    eprintln!("manzo_stop: mpg123_open_feed reset failed ({feed_ret})");
}
```

---

### WR-02: `off_t → usize` cast in `manzo_seek` wraps on negative value

**File:** `manzo-core/src/lib.rs:344`
**Issue:** `input_byte_offset` is declared as `libc::off_t` (an alias for `i64` on
macOS). After the `result < 0` guard passes, the code casts `input_byte_offset`
directly to `usize` without checking its sign:

```rust
state.file_offset = (input_byte_offset as usize).min(state.file_data.len());
```

If `mpg123_feedseek` returns a non-negative `result` while leaving
`input_byte_offset` at a large or negative value (which is within its contract
for certain error states), the cast of a negative `i64` to `usize` wraps to
a very large number. The `.min(state.file_data.len())` clamps the final
assignment, preventing an out-of-bounds access, but the file_offset silently
becomes the file length instead of the correct byte position, causing the
decoder to see EOF immediately on next play.

**Fix:**
```rust
// Replace line 344
let byte_offset = if input_byte_offset >= 0 {
    (input_byte_offset as usize).min(state.file_data.len())
} else {
    // feedseek returned a bad offset — treat as seek to 0
    eprintln!("manzo_seek: unexpected negative input_byte_offset {input_byte_offset}");
    0
};
state.file_offset = byte_offset;
```

---

### WR-03: Mutex held across entire decode loop — can stall UI thread in `manzo_pause` / `manzo_seek`

**File:** `manzo-core/src/lib.rs:191-247`
**Issue:** The audio callback acquires the `Arc<Mutex<InnerState>>` lock at line
191 and holds it for the full duration of the decode loop — including all
`mpg123_read` and `mpg123_feed` calls. Meanwhile, `manzo_pause` (line 277)
and `manzo_seek` (line 324) call `arc.lock()` on the main/UI thread. If the
audio callback is mid-decode, the UI thread stalls until the callback
completes. On a slow device or with a large `FEED_CHUNK_SIZE`, this can
exceed the 8 ms frame budget and produce a visible UI freeze or audio
dropout.

This is not a crash, but it is a design issue that will become increasingly
painful once the UI shell (Phase 5) adds click handlers for pause and seek.

**Fix:** Split mutable state into two structs — a small control struct
protected by the mutex (just `is_playing`, `file_offset`, position), and a
decoder state accessed only from the audio thread without the lock. The
callback copies out the control flags at the start of each buffer, releases
the lock, then decodes without holding it. This pattern is outlined in the
spike 004 findings.

Alternatively, for a lower-effort fix, switch from `Arc<Mutex<>>` to
`Arc<(Mutex<ControlState>, UnsafeCell<DecoderState>)>` where only the
control state is guarded.

---

### WR-04: `MPG123_NEED_MORE` cast to `i32` — type assumption not checked

**File:** `manzo-core/src/lib.rs:223`
**Issue:** `mpg123_sys::MPG123_NEED_MORE` is compared via `as i32` cast:

```rust
if ret == mpg123_sys::MPG123_NEED_MORE as i32 {
```

The `mpg123_sys` crate exposes these as `u32` constants. Casting `u32` to
`i32` is well-defined in Rust (wraps on overflow), but if `MPG123_NEED_MORE`
has a numeric value ≥ 2^31 the cast produces a negative i32 and the
comparison always fails silently. In practice `MPG123_NEED_MORE = 10` so
this is safe today, but the same pattern should not be extended to other
constants without checking their values. The `ret` variable from
`mpg123_read` is already typed `i32` (the C function returns `int`), so the
correct fix is to cast the constant to the same type explicitly.

**Fix:**
```rust
// Replace line 223
if ret == mpg123_sys::MPG123_NEED_MORE as libc::c_int {
```
`libc::c_int` = `i32` on all Apple platforms, making the intent unambiguous.

---

## Info

### IN-01: Hardcoded developer absolute path in `AppDelegate` fallback

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:18`
**Issue:** The development fallback path is hardcoded to an absolute path on
the developer's machine:

```swift
mp3Path = "/Users/usameak42/Coding/MANZO/manzo-core/tests/fixtures/test.mp3"
```

If another developer clones the repository, or the directory is renamed, the
fallback silently produces an `NSLog` and skips playback with no build-time
warning. This is fine for Phase 2 (single-developer project), but the path
should be removed or made relative before Phase 5 ships the UI shell.

**Fix:** Remove the `else` branch entirely and let the `guard` on line 21
handle the missing file cleanly, or derive the path via `#file` / relative
to the bundle at runtime.

---

### IN-02: `manzo_get_spectrum` missing handle null guard — will need to be added before Phase 7

**File:** `manzo-core/src/lib.rs:432-448`
**Issue:** Every other FFI function in this file null-checks its `handle`
argument (T-02-05 requirement). `manzo_get_spectrum` intentionally skips
this check because the handle is unused in the Phase 7 stub. When Phase 7
wires the FFT pipeline, the handle will be dereferenced — and if the null
guard is not added at that point, it will be a crash.

**Fix:** Add the guard now as a forward-proof measure, or leave a `// T-02-05: add null-check before handle is dereferenced in Phase 7` comment at line 432 to ensure it is not missed.

---

### IN-03: `libmpg123.dylib` copy step in pre-build script silently no-ops if only versioned dylib exists

**File:** `ManzoApp/project.yml:74-78`
**Issue:** The `find` command uses `-not -name "libmpg123.0.dylib"` to exclude
the versioned symlink and find the canonical dylib. If mpg123's build system
changes to ship only the versioned name (or names it `libmpg123.dylib.0`),
`find` returns empty, `MPG123_LIB` is empty, and the `cp` is skipped — the
`-lmpg123` linker flag then fails at link time with a non-obvious error.

**Fix:** Add an `else` block that fails loudly:
```zsh
if [ -n "$MPG123_LIB" ]; then
  cp "$MPG123_LIB" "$SRCROOT/../manzo-core/target/aarch64-apple-darwin/release/libmpg123.dylib"
else
  echo "error: libmpg123.dylib not found under build/ — re-run cargo build --release"; exit 1
fi
```

---

### IN-04: Gapless 529-sample trim has no tracking comment in lib.rs

**File:** `manzo-core/src/lib.rs:86-98`
**Issue:** The spike findings (audio-dsp-pipeline.md) establish that gapless
MP3 playback requires trimming exactly 529 samples of decoder priming delay
from the mpg123 output. This is listed as a Phase 3 concern in CLAUDE.md,
but there is no comment in the codebase near the `MPG123_FORCE_FLOAT` /
`mpg123_open_feed` setup to flag where the trim must be applied. Phase 3
implementers may miss it.

**Fix:** Add a tracking comment near line 88:
```rust
// FUTURE (Phase 3 gapless): trim exactly 529 samples from the start of
// the first mpg123_read output per MPEG Layer 3 decoder priming delay.
// See spike 003 / audio-dsp-pipeline.md.
```

---

_Reviewed: 2026-04-22T00:18:28Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
