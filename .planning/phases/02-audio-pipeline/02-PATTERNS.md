# Phase 2: Audio Pipeline - Pattern Map

**Mapped:** 2026-04-22
**Files analyzed:** 4
**Analogs found:** 3 / 4 (test fixture has no analog — it is a binary asset)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `manzo-core/src/lib.rs` | service (FFI surface) | streaming, request-response | `manzo-core/src/lib.rs` (Phase 1) | exact — same file, bodies replaced |
| `manzo-core/Cargo.toml` | config | n/a | `manzo-core/Cargo.toml` (Phase 1) | exact — same file, deps added |
| `manzo-core/tests/integration_test.rs` | test | request-response | `manzo-core/src/lib.rs` `#[cfg(test)]` block | role-match (unit → integration) |
| `manzo-core/tests/fixtures/test.mp3` | fixture (binary) | file-I/O | none | no analog |

---

## Pattern Assignments

### `manzo-core/src/lib.rs` (FFI service, streaming)

**Analog:** `manzo-core/src/lib.rs` (Phase 1, lines 1–127)

This is the primary file being modified. All 11 FFI signatures are preserved exactly; only the bodies change. The implementation adds a real `InnerState` struct behind `ManzoHandle` using `Box::into_raw` / `Box::from_raw` for the opaque-handle lifecycle.

**Crate-level doc and FFI conventions** (lines 1–10):
```rust
//! manzo-core — Rust audio/DSP core for MANZO
//! FFI surface: 11 C-callable functions, generated header via cbindgen
//! All functions are stubs; real implementations added in Phase 2+

/// Opaque handle returned by manzo_open and passed to all subsequent calls.
#[repr(C)]
pub struct ManzoHandle {
    _private: [u8; 0],
}
```

Phase 2 replaces `ManzoHandle` body with:
```rust
// ManzoHandle stays #[repr(C)] with _private: [u8; 0].
// The actual state lives behind a raw pointer cast:
//   *mut ManzoHandle  ←→  *mut InnerState (via Box::into_raw / Box::from_raw)
// InnerState is NOT repr(C) — it is internal Rust only.
```

**FFI handle open/close pattern** (lines 14–24 — the lifecycle template):
```rust
#[no_mangle]
pub extern "C" fn manzo_open(path: *const std::os::raw::c_char) -> *mut ManzoHandle {
    let _ = path; // used in Phase 2
    std::ptr::null_mut()
}

#[no_mangle]
pub extern "C" fn manzo_close(handle: *mut ManzoHandle) {
    let _ = handle; // real dealloc in Phase 2
}
```

Phase 2 pattern for these two (derived from D-02 threading model + CONTEXT.md code_context):
```rust
// manzo_open — allocate InnerState, return opaque raw pointer
#[no_mangle]
pub extern "C" fn manzo_open(path: *const std::os::raw::c_char) -> *mut ManzoHandle {
    if path.is_null() { return std::ptr::null_mut(); }
    // 1. CStr::from_ptr(path) → str → PathBuf
    // 2. Construct InnerState (mpg123 handle, cpal stream = None, position = 0)
    // 3. Wrap in Arc<Mutex<InnerState>>
    // 4. Box the Arc, return Box::into_raw(...) cast to *mut ManzoHandle
    // Return null on any error (D-04)
}

// manzo_close — drop the Arc; cpal stream auto-stops when dropped
#[no_mangle]
pub extern "C" fn manzo_close(handle: *mut ManzoHandle) {
    if handle.is_null() { return; }
    // unsafe { drop(Box::from_raw(handle as *mut Arc<Mutex<InnerState>>)); }
}
```

**FFI error-return pattern** (lines 26–31 — play/seek return i32):
```rust
#[no_mangle]
pub extern "C" fn manzo_play(handle: *mut ManzoHandle) -> i32 {
    let _ = handle;
    0
}
```

Phase 2 convention per D-04: return 0 = success, non-zero = failure. Null handle check is the first guard.

**FFI void-return pattern** (lines 33–43 — pause/stop return nothing):
```rust
#[no_mangle]
pub extern "C" fn manzo_pause(handle: *mut ManzoHandle) {
    let _ = handle;
}
#[no_mangle]
pub extern "C" fn manzo_stop(handle: *mut ManzoHandle) {
    let _ = handle;
}
```

**FFI getter pattern** (lines 76–80 — get_position returns u64):
```rust
#[no_mangle]
pub extern "C" fn manzo_get_position(handle: *mut ManzoHandle) -> u64 {
    let _ = handle;
    0
}
```

**Spectrum stub zero-fill pattern** (lines 82–92 — D-01 contract):

Phase 1 has a bug here (does NOT write the buffer). Phase 2 must fix this per D-01:
```rust
// Phase 1 (incorrect — does not write buffer):
pub extern "C" fn manzo_get_spectrum(
    handle: *mut ManzoHandle,
    out_buf: *mut f32,
    count: usize,
) -> usize {
    let _ = (handle, out_buf);
    count
}

// Phase 2 correct implementation per D-01:
pub extern "C" fn manzo_get_spectrum(
    handle: *mut ManzoHandle,
    out_buf: *mut f32,
    count: usize,
) -> usize {
    if out_buf.is_null() || count == 0 { return 0; }
    // Write count zeros — FFT pipeline is Phase 7; buffer must always be written
    unsafe {
        std::ptr::write_bytes(out_buf, 0, count);
    }
    count
}
```

**InnerState struct design** (Claude's discretion, per D-02):
```rust
use std::sync::{Arc, Mutex};

struct InnerState {
    // mpg123 handle (mpg123-sys type)
    mpg_handle: mpg123_sys::mpg123_handle_ptr,
    // Raw file bytes loaded into memory (or BufReader — to be decided by implementer)
    file_data: Vec<u8>,
    file_offset: usize,
    // cpal stream — None until manzo_play is called
    stream: Option<cpal::Stream>,
    // Playback position in samples (for get_position conversion to ms)
    position_samples: Arc<Mutex<u64>>,
    sample_rate: u32,
    channels: u16,
    // Playback state flag
    is_playing: bool,
}
```

**mpg123 feed/read pipeline** (from spike-findings-MANZO audio-dsp-pipeline.md):
```rust
// Feed chunk size: exactly 4096 bytes (validated in spike 003 — do not change)
const FEED_CHUNK_SIZE: usize = 4096;

// mpg123 init sequence (inside manzo_open):
//   mpg123_new(NULL, &err)       — create handle, auto-detect format
//   mpg123_param(mh, MPG123_FORCE_FLOAT, 1, 0.0)  — always float32 output
//   mpg123_open_feed(mh)         — streaming feed mode
//   mpg123_feed(mh, buf, 4096)  — feed first chunk
//   mpg123_read(mh, out, size, &done) → float32 PCM
//
// Decoder delay: 529 samples — DO NOT trim in Phase 2 (deferred to Phase 3)
```

**cpal output stream pattern** (from CONTEXT.md, D-02):
```rust
// Inside manzo_play — start cpal stream with Arc<Mutex<InnerState>> clone:
let inner_clone = Arc::clone(&inner);
let stream = device.build_output_stream(
    &config,
    move |data: &mut [f32], _| {
        // Lock inner, decode next chunk from mpg123, fill data buffer
        if let Ok(mut state) = inner_clone.lock() {
            // decode float32 PCM directly into `data` — no int16 conversion
        }
    },
    |err| eprintln!("cpal stream error: {err}"),
    None,  // no timeout — let cpal pick default BufferSize for CoreAudio
)?;
stream.play()?;
```

**Unit test pattern** (lines 97–127 — tests module structure):
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stub_play_returns_zero() {
        let result = manzo_play(std::ptr::null_mut());
        assert_eq!(result, 0, "manzo_play stub must return 0");
    }
    // ... additional tests follow same assert_eq! + descriptive message pattern
}
```

---

### `manzo-core/Cargo.toml` (config)

**Analog:** `manzo-core/Cargo.toml` (Phase 1, lines 1–19)

**Full existing file** (lines 1–19):
```toml
[package]
name = "manzo-core"
version = "0.1.0"
edition = "2021"

[lib]
name = "manzo_core"
crate-type = ["staticlib"]

[build-dependencies]
cbindgen = "0.27"

[dev-dependencies]
# nothing yet — unit tests live in src/lib.rs

[profile.release]
opt-level = 3
lto = true
```

**Phase 2 additions** — add runtime deps between `[build-dependencies]` and `[dev-dependencies]`:
```toml
[dependencies]
mpg123-sys = "0.1"          # libmpg123 Rust bindings — feed/read streaming API
cpal = "0.15"               # cross-platform audio output; CoreAudio backend on macOS

[dev-dependencies]
# integration tests in tests/ are auto-discovered by cargo test
```

Key constraints:
- `crate-type = ["staticlib"]` must remain unchanged — Swift/Xcode links this `.a`
- `lto = true` must remain — production audio library
- `mpg123-sys` requires libmpg123 to be available; check if Homebrew install is needed on CI

---

### `manzo-core/tests/integration_test.rs` (test, request-response)

**Analog:** `manzo-core/src/lib.rs` `#[cfg(test)]` block (lines 97–127)

The unit tests in `lib.rs` establish the assertion style and naming conventions. The integration test file follows the same pattern but lives in `tests/` and uses real file paths.

**Unit test style to copy** (lines 97–127):
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stub_play_returns_zero() {
        let result = manzo_play(std::ptr::null_mut());
        assert_eq!(result, 0, "manzo_play stub must return 0");
    }
}
```

**Integration test structure** (new file, no existing analog — derive from unit test conventions + D-03):
```rust
// manzo-core/tests/integration_test.rs
// Integration test: verifies decode pipeline end-to-end (open → play → position advances)
// Requires tests/fixtures/test.mp3 (CC0 ~5s audio clip)

use std::ffi::CString;

const FIXTURE_PATH: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/test.mp3");

#[test]
fn open_returns_non_null_for_valid_mp3() {
    let path = CString::new(FIXTURE_PATH).unwrap();
    let handle = unsafe { manzo_core::manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "manzo_open must return non-null for valid MP3");
    unsafe { manzo_core::manzo_close(handle) };
}

#[test]
fn play_advances_position() {
    let path = CString::new(FIXTURE_PATH).unwrap();
    let handle = unsafe { manzo_core::manzo_open(path.as_ptr()) };
    assert!(!handle.is_null());
    let result = unsafe { manzo_core::manzo_play(handle) };
    assert_eq!(result, 0, "manzo_play must return 0 on success");
    // Allow audio thread to decode a few frames
    std::thread::sleep(std::time::Duration::from_millis(200));
    let pos = unsafe { manzo_core::manzo_get_position(handle) };
    assert!(pos > 0, "position must advance after playback starts");
    unsafe { manzo_core::manzo_close(handle) };
}

#[test]
fn spectrum_buffer_is_written() {
    let path = CString::new(FIXTURE_PATH).unwrap();
    let handle = unsafe { manzo_core::manzo_open(path.as_ptr()) };
    assert!(!handle.is_null());
    let mut buf = vec![f32::NAN; 512];  // pre-fill with NaN to detect unwritten bytes
    let written = unsafe { manzo_core::manzo_get_spectrum(handle, buf.as_mut_ptr(), 512) };
    assert_eq!(written, 512);
    assert!(buf.iter().all(|&v| v == 0.0), "spectrum must be zero-filled (D-01)");
    unsafe { manzo_core::manzo_close(handle) };
}
```

Key conventions derived from unit test analog:
- `assert_eq!` with descriptive string message (third argument)
- Functions named `verb_noun_condition` (snake_case)
- Each test is self-contained: open → operate → close

---

### `manzo-core/tests/fixtures/test.mp3` (binary fixture)

**Analog:** none

No binary test fixtures exist in this codebase yet. This is a CC0 ~5-second MP3 clip (synthesized tone or royalty-free music). It must be committed to the repository as a binary file.

Requirements:
- Format: MPEG Layer 3, 44100 Hz or 48000 Hz, stereo or mono
- Duration: ~5 seconds (enough for position-advance test with 200ms sleep)
- License: CC0 (public domain) — no rights clearance needed
- Source options: generate with `ffmpeg -f lavfi -i "sine=frequency=440:duration=5" -c:a libmp3lame test.mp3` or download from freesound.org (CC0 filter)

---

## Shared Patterns

### Null-pointer Guard
**Source:** `manzo-core/src/lib.rs` Phase 1 threat model (T-01-03), applied in Phase 2
**Apply to:** Every FFI function that dereferences `handle`

```rust
// Pattern: null-check before any deref — return safe sentinel on null
if handle.is_null() { return std::ptr::null_mut(); }  // for *mut returns
if handle.is_null() { return; }                        // for void returns
if handle.is_null() { return -1; }                     // for i32 error returns
if handle.is_null() { return 0; }                      // for u64/usize getters
```

### FFI Handle Lifecycle (Box into_raw / from_raw)
**Source:** CONTEXT.md `## Established Patterns` section
**Apply to:** `manzo_open` (allocate) and `manzo_close` (deallocate)

```rust
// Allocate in manzo_open:
let state = Box::new(Arc::new(Mutex::new(InnerState { ... })));
Box::into_raw(state) as *mut ManzoHandle

// Deallocate in manzo_close:
unsafe {
    drop(Box::from_raw(handle as *mut Arc<Mutex<InnerState>>));
}
```

### Float32 End-to-End Pipeline
**Source:** spike-findings-MANZO audio-dsp-pipeline.md, "Full Playback Pipeline" section
**Apply to:** cpal output callback, any intermediate buffer allocation

```
mpg123 (MPG123_FORCE_FLOAT) → float32 → cpal callback data: &mut [f32] → CoreAudio
```
No int16 conversion at any stage. Both int16↔float round-trips present in original Winamp code are eliminated.

### mpg123 Feed Chunk Size
**Source:** spike-findings-MANZO audio-dsp-pipeline.md, spike 003
**Apply to:** Any loop that calls `mpg123_feed`

```rust
const FEED_CHUNK_SIZE: usize = 4096; // validated — do not change
```

### cbindgen Header Preservation
**Source:** `manzo-core/build.rs` (lines 1–16), `manzo-core/cbindgen.toml` (lines 1–9)
**Apply to:** Any change to FFI function signatures (Phase 2 must NOT change signatures)

Phase 2 constraint: FFI signatures are frozen. Only bodies change. If a signature ever changes, `build.rs` regenerates `manzo_core.h` automatically on `cargo build`, and `ManzoApp/` bridging header may need re-linking.

---

## No Analog Found

| File | Role | Data Flow | Reason |
|---|---|---|---|
| `manzo-core/tests/fixtures/test.mp3` | fixture | file-I/O | First binary test asset in the project; no prior fixture pattern |

---

## Metadata

**Analog search scope:** `manzo-core/src/`, `manzo-core/tests/`, `.claude/skills/spike-findings-MANZO/`
**Files scanned:** `manzo-core/src/lib.rs`, `manzo-core/Cargo.toml`, `manzo-core/build.rs`, `manzo-core/cbindgen.toml`, `.planning/phases/01-build-foundation/01-01-PLAN.md`, `.claude/skills/spike-findings-MANZO/references/audio-dsp-pipeline.md`
**Pattern extraction date:** 2026-04-22
