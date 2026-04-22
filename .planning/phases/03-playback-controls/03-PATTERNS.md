# Phase 3: Playback Controls - Pattern Map

**Mapped:** 2026-04-22
**Files analyzed:** 4
**Analogs found:** 4 / 4

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `manzo-core/src/lib.rs` | service (FFI surface) | streaming, request-response | `manzo-core/src/lib.rs` (Phase 2, current file) | exact — same file, fields + functions added |
| `ManzoApp/ManzoApp/AppDelegate.swift` | controller (app delegate) | event-driven, request-response | `ManzoApp/ManzoApp/AppDelegate.swift` (Phase 2) | exact — same file, polling timer added |
| `manzo-core/tests/integration_test.rs` | test | request-response | `manzo-core/tests/integration_test.rs` (Phase 2) | exact — same file, new test cases added |
| `manzo-core/tests/fixtures/test2.mp3` | fixture (binary) | file-I/O | `manzo-core/tests/fixtures/test.mp3` | role-match (same binary fixture pattern) |

---

## Pattern Assignments

### `manzo-core/src/lib.rs` — InnerState extension (service, streaming)

**Analog:** `manzo-core/src/lib.rs` lines 20–34 (Phase 2 InnerState struct)

**Existing InnerState to extend** (lines 20–34):
```rust
struct InnerState {
    mpg_handle: *mut mpg123_sys::mpg123_handle,
    file_data: Vec<u8>,
    file_offset: usize,
    stream: Option<cpal::Stream>,
    position_samples: u64,
    sample_rate: u32,
    channels: u16,
    is_playing: bool,
    // Phase 4 DSP fields — stored now, wired into DSP chain in Phase 4
    volume: f32,
    pan: f32,
    eq_gains: [f32; 10],
    eq_preamp: f32,
}
```

**Phase 3 additions to InnerState** — append after `eq_preamp`:
```rust
    // Phase 3: playback state for manzo_get_state() — values match D-02 constants
    //   1 = PLAYING, 2 = PAUSED, 3 = STOPPED, 4 = ENDED
    playback_state: i32,
    // Phase 3: 529-sample decoder startup delay trim — initialized in manzo_open (D-04)
    startup_skip_remaining: u64,
```

---

### `manzo-core/src/lib.rs` — manzo_open initialization (service, request-response)

**Analog:** `manzo-core/src/lib.rs` lines 120–136 (InnerState construction block in manzo_open)

**Existing InnerState construction** (lines 120–136):
```rust
    let inner = InnerState {
        mpg_handle: mh,
        file_offset: first_chunk_len,
        file_data,
        stream: None,
        position_samples: 0,
        sample_rate: 44100,
        channels: 2,
        is_playing: false,
        volume: 1.0,
        pan: 0.0,
        eq_gains: [0.0; 10],
        eq_preamp: 0.0,
    };

    let arc = Arc::new(Mutex::new(inner));
    Box::into_raw(Box::new(arc)) as *mut ManzoHandle
```

**Phase 3 additions** — add new fields in the struct literal (after `eq_preamp: 0.0`):
```rust
        playback_state: 3,          // STOPPED — no track playing on fresh open
        startup_skip_remaining: 529, // D-04: trim mpg123 decoder delay on first play
```

---

### `manzo-core/src/lib.rs` — manzo_play state transition (service, request-response)

**Analog:** `manzo-core/src/lib.rs` lines 155–278 (manzo_play full body)

**Existing state transition at end of manzo_play** (lines 276–278):
```rust
    state.stream = Some(stream);
    state.is_playing = true;
    0
```

**Phase 3 addition** — set `playback_state` alongside `is_playing`:
```rust
    state.stream = Some(stream);
    state.is_playing = true;
    state.playback_state = 1; // PLAYING
    0
```

---

### `manzo-core/src/lib.rs` — manzo_pause state transition (service, request-response)

**Analog:** `manzo-core/src/lib.rs` lines 281–293 (manzo_pause full body)

**Existing manzo_pause** (lines 281–293):
```rust
#[no_mangle]
pub extern "C" fn manzo_pause(handle: *mut ManzoHandle) {
    if handle.is_null() { return; }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());
    // Set flag — audio callback fills silence when is_playing is false.
    // Stream stays alive to allow resume without rebuilding the cpal pipeline.
    state.is_playing = false;
}
```

**Phase 3 addition** — set `playback_state` after `is_playing = false`:
```rust
    state.is_playing = false;
    state.playback_state = 2; // PAUSED
```

---

### `manzo-core/src/lib.rs` — manzo_stop state transition (service, request-response)

**Analog:** `manzo-core/src/lib.rs` lines 295–332 (manzo_stop full body)

**Existing state updates near top of manzo_stop** (lines 303–309):
```rust
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());

    state.is_playing = false;
    state.position_samples = 0;

    // Drop stream to stop CoreAudio
    state.stream = None;
```

**Phase 3 addition** — set `playback_state` alongside `is_playing = false`:
```rust
    state.is_playing = false;
    state.playback_state = 3; // STOPPED
    state.position_samples = 0;
    state.stream = None;
```

---

### `manzo-core/src/lib.rs` — audio callback EOF/ENDED detection (service, streaming)

**Analog:** `manzo-core/src/lib.rs` lines 246–259 (EOF branch inside the audio callback)

**Existing EOF handling** (lines 246–259) — currently sets `is_playing = false` only:
```rust
                    } else if frames_written == 0 {
                        // EOF — fill remainder with silence
                        data[written..].fill(0.0);
                        s.is_playing = false;
                        break;
                    }
                } else if ret != 0 && frames_written == 0 {
                    // Unrecoverable error or EOF
                    data[written..].fill(0.0);
                    break;
                }
```

**Phase 3 change** — set `playback_state = 4` (ENDED) at the natural EOF branch, and also trim 529-sample decoder delay before writing PCM to output. The startup skip pattern:

529-sample skip in the decode loop — insert at the top of the while loop, before the `mpg123_read` write to `data[written..]`:
```rust
            // D-04: discard startup_skip_remaining samples before writing to output
            // This trims the 529-sample mpg123 decoder delay (spike-validated).
            // Only fires once per manzo_open call; seek does NOT reset this counter.
            if s.startup_skip_remaining > 0 {
                // Decode into a scratch buffer to discard samples
                let skip_count = s.startup_skip_remaining.min((data.len() - written) as u64) as usize;
                let mut discard = vec![0f32; skip_count];
                let mut discarded_bytes: libc::size_t = 0;
                unsafe {
                    mpg123_sys::mpg123_read(
                        s.mpg_handle,
                        discard.as_mut_ptr() as *mut libc::c_uchar,
                        skip_count * 4,
                        &mut discarded_bytes,
                    );
                }
                let discarded_samples = discarded_bytes / 4;
                s.startup_skip_remaining = s.startup_skip_remaining
                    .saturating_sub(discarded_samples as u64);
                // Do not add to `written` — these samples are discarded silently
                continue;
            }
```

Natural EOF sets ENDED state:
```rust
                    } else if frames_written == 0 {
                        // EOF — fill remainder with silence; signal ENDED to Swift poller
                        data[written..].fill(0.0);
                        s.is_playing = false;
                        s.playback_state = 4; // ENDED — D-02: distinct from STOPPED
                        break;
                    }
```

---

### `manzo-core/src/lib.rs` — manzo_get_state (new FFI getter, request-response)

**Analog:** `manzo-core/src/lib.rs` lines 439–453 (`manzo_get_position` — same getter pattern: null guard → lock → read field → return)

**Existing getter to copy** (lines 439–453):
```rust
#[no_mangle]
pub extern "C" fn manzo_get_position(handle: *mut ManzoHandle) -> u64 {
    // T-02-05: null guard → return 0
    if handle.is_null() {
        return 0;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let state = arc.lock().unwrap_or_else(|e| e.into_inner());
    if state.sample_rate == 0 {
        return 0;
    }
    // Convert samples to milliseconds
    (state.position_samples * 1000) / state.sample_rate as u64
}
```

**New manzo_get_state — follow the same structure exactly:**
```rust
/// Returns current playback state as i32:
///   1 = PLAYING, 2 = PAUSED, 3 = STOPPED, 4 = ENDED.
/// Returns 3 (STOPPED) if handle is null.
#[no_mangle]
pub extern "C" fn manzo_get_state(handle: *mut ManzoHandle) -> i32 {
    if handle.is_null() {
        return 3; // STOPPED — safe sentinel for null
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let state = arc.lock().unwrap_or_else(|e| e.into_inner());
    state.playback_state
}
```

---

### `manzo-core/src/lib.rs` — manzo_get_duration (new FFI getter, request-response)

**Analog:** `manzo-core/src/lib.rs` lines 439–453 (`manzo_get_position` — same null-guard + lock + compute pattern)

**New manzo_get_duration — same null-guard / lock structure, mpg123_length computation:**
```rust
/// Returns total track duration in milliseconds, or 0 if unavailable (D-03).
/// Duration is computed via mpg123_length() / sample_rate.
/// Returns 0 for CBR files without LAME header (mpg123_length returns MPG123_ERR).
#[no_mangle]
pub extern "C" fn manzo_get_duration(handle: *mut ManzoHandle) -> u64 {
    if handle.is_null() {
        return 0;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let state = arc.lock().unwrap_or_else(|e| e.into_inner());
    if state.sample_rate == 0 {
        return 0;
    }
    // mpg123_length returns total samples or MPG123_ERR (-1) if unknown
    let total_samples = unsafe { mpg123_sys::mpg123_length(state.mpg_handle) };
    if total_samples < 0 {
        return 0; // CBR without LAME header — D-03: defer scanning to Phase 8
    }
    (total_samples as u64 * 1000) / state.sample_rate as u64
}
```

---

### `manzo-core/src/lib.rs` — unit test additions (test, request-response)

**Analog:** `manzo-core/src/lib.rs` lines 479–517 (existing `#[cfg(test)] mod tests` block)

**Existing test structure to extend** (lines 479–517):
```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn play_null_returns_minus_one() {
        let result = manzo_play(std::ptr::null_mut());
        assert_eq!(result, -1, "manzo_play with null handle must return -1");
    }
    // ... additional tests follow same pattern
}
```

**New unit tests to append** — follow `assert_eq!` + descriptive message convention exactly:
```rust
    #[test]
    fn get_state_null_returns_stopped() {
        let result = manzo_get_state(std::ptr::null_mut());
        assert_eq!(result, 3, "manzo_get_state with null handle must return 3 (STOPPED)");
    }

    #[test]
    fn get_duration_null_returns_zero() {
        let result = manzo_get_duration(std::ptr::null_mut());
        assert_eq!(result, 0, "manzo_get_duration with null handle must return 0");
    }
```

---

### `ManzoApp/ManzoApp/AppDelegate.swift` — polling timer for auto-advance (controller, event-driven)

**Analog:** `ManzoApp/ManzoApp/AppDelegate.swift` lines 1–53 (Phase 2 full file)

**Existing Phase 2 AppDelegate to extend** (lines 1–53):
```swift
import AppKit

@objc class AppDelegate: NSObject, NSApplicationDelegate {
    private var manzoHandle: UnsafeMutablePointer<manzo_ManzoHandle>? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mp3Path: String
        if let bundlePath = Bundle.main.path(forResource: "test", ofType: "mp3") {
            mp3Path = bundlePath
        } else {
            mp3Path = "/Users/usameak42/Coding/MANZO/manzo-core/tests/fixtures/test.mp3"
        }
        guard FileManager.default.fileExists(atPath: mp3Path) else {
            NSLog("MANZO Phase 2: MP3 not found at \(mp3Path) — skipping playback")
            return
        }
        manzoHandle = manzo_open(mp3Path)
        guard let handle = manzoHandle else {
            NSLog("MANZO Phase 2: manzo_open returned null for \(mp3Path)")
            return
        }
        let playResult = manzo_play(handle)
        if playResult == 0 {
            NSLog("MANZO Phase 2: playback started — \(mp3Path)")
        } else {
            NSLog("MANZO Phase 2: manzo_play failed with code \(playResult)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let handle = manzoHandle {
            manzo_close(handle)
            manzoHandle = nil
        }
    }
    ...
}
```

**Phase 3 additions** — new instance vars and timer-based polling:

```swift
    // Phase 3 state constants (D-02) — defined as local constants matching bridging header
    private let MANZO_STATE_PLAYING: Int32 = 1
    private let MANZO_STATE_PAUSED:  Int32 = 2
    private let MANZO_STATE_STOPPED: Int32 = 3
    private let MANZO_STATE_ENDED:   Int32 = 4

    // Phase 3: second test track path for back-to-back auto-advance demo
    private var trackQueue: [String] = []
    private var currentTrackIndex: Int = 0
    private var pollTimer: Timer? = nil
```

**Timer start pattern** — append to `applicationDidFinishLaunching` after `manzo_play`:
```swift
        // Phase 3: start 100ms polling timer to detect ENDED and auto-advance
        pollTimer = Timer.scheduledTimer(
            timeInterval: 0.1,
            target: self,
            selector: #selector(pollPlaybackState),
            userInfo: nil,
            repeats: true
        )
```

**Polling callback** — new method following the Phase 2 FFI call style (`manzo_*` + NSLog):
```swift
    @objc private func pollPlaybackState() {
        guard let handle = manzoHandle else { return }

        let state = manzo_get_state(handle)
        if state == MANZO_STATE_ENDED {
            NSLog("MANZO Phase 3: track ended — advancing to next track")
            // Advance to next track in queue
            currentTrackIndex += 1
            guard currentTrackIndex < trackQueue.count else {
                NSLog("MANZO Phase 3: queue exhausted — stopping timer")
                pollTimer?.invalidate()
                pollTimer = nil
                return
            }
            let nextPath = trackQueue[currentTrackIndex]
            // Close current handle before opening next track
            manzo_close(handle)
            manzoHandle = manzo_open(nextPath)
            guard let newHandle = manzoHandle else {
                NSLog("MANZO Phase 3: manzo_open returned null for \(nextPath)")
                return
            }
            let result = manzo_play(newHandle)
            NSLog("MANZO Phase 3: auto-advance to \(nextPath) — play result: \(result)")
        }
    }
```

**Timer cleanup** — extend `applicationWillTerminate`:
```swift
    func applicationWillTerminate(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        if let handle = manzoHandle {
            manzo_close(handle)
            manzoHandle = nil
        }
    }
```

---

### `manzo-core/tests/integration_test.rs` — new Phase 3 test cases (test, request-response)

**Analog:** `manzo-core/tests/integration_test.rs` lines 1–105 (Phase 2 full file)

**Existing import block to extend** (lines 10–13):
```rust
use manzo_core::{
    ManzoHandle,
    manzo_close, manzo_get_position, manzo_get_spectrum, manzo_open, manzo_play,
};
```

**Phase 3 addition** — add new FFI functions to the import:
```rust
use manzo_core::{
    ManzoHandle,
    manzo_close, manzo_get_duration, manzo_get_position, manzo_get_spectrum,
    manzo_get_state, manzo_open, manzo_play, manzo_pause, manzo_stop,
};
```

**Second fixture constant** — append after line 18:
```rust
const FIXTURE_PATH_2: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/test2.mp3");
```

**New test cases** — follow open → operate → assert → close pattern from lines 20–105:
```rust
#[test]
fn get_state_returns_stopped_after_open() {
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    let state = unsafe { manzo_get_state(handle) };
    assert_eq!(state, 3, "state must be STOPPED (3) immediately after open");

    unsafe { manzo_close(handle) };
}

#[test]
fn get_duration_returns_nonzero_for_valid_mp3() {
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    let duration = unsafe { manzo_get_duration(handle) };
    assert!(
        duration > 0,
        "manzo_get_duration must return > 0 ms for a valid MP3 with VBR header (got {})",
        duration
    );

    unsafe { manzo_close(handle) };
}

#[test]
#[ignore = "requires audio output hardware; not available in headless CI environments"]
fn state_transitions_play_pause_stop() {
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    // STOPPED after open
    assert_eq!(unsafe { manzo_get_state(handle) }, 3, "must be STOPPED after open");

    // PLAYING after play
    let play_ret = unsafe { manzo_play(handle) };
    assert_eq!(play_ret, 0, "manzo_play must return 0");
    assert_eq!(unsafe { manzo_get_state(handle) }, 1, "must be PLAYING after play");

    // PAUSED after pause
    unsafe { manzo_pause(handle) };
    assert_eq!(unsafe { manzo_get_state(handle) }, 2, "must be PAUSED after pause");

    // STOPPED after stop
    unsafe { manzo_stop(handle) };
    assert_eq!(unsafe { manzo_get_state(handle) }, 3, "must be STOPPED after stop");

    unsafe { manzo_close(handle) };
}

#[test]
#[ignore = "requires audio output hardware; not available in headless CI environments"]
fn state_becomes_ended_after_short_track_completes() {
    // Uses test2.mp3 — a very short (~1s) clip so ENDED is reached quickly
    let path = CString::new(FIXTURE_PATH_2).expect("FIXTURE_PATH_2 contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed with test2.mp3");

    let play_ret = unsafe { manzo_play(handle) };
    assert_eq!(play_ret, 0, "manzo_play must return 0 on test2.mp3");

    // Poll until ENDED or timeout (3s max)
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
    let mut final_state = 0i32;
    while std::time::Instant::now() < deadline {
        final_state = unsafe { manzo_get_state(handle) };
        if final_state == 4 { break; }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    assert_eq!(
        final_state, 4,
        "state must reach ENDED (4) after short track completes"
    );

    unsafe { manzo_close(handle) };
}
```

---

### `manzo-core/tests/fixtures/test2.mp3` (binary fixture)

**Analog:** `manzo-core/tests/fixtures/test.mp3` (Phase 2 fixture — same CC0 binary asset pattern)

No code pattern — binary file. Generation command:
```bash
ffmpeg -f lavfi -i "sine=frequency=440:duration=1" -c:a libmp3lame \
    manzo-core/tests/fixtures/test2.mp3
```
Requirements:
- Duration: ~1 second (so ENDED state is reached quickly in the polling integration test)
- Format: MPEG Layer 3, 44100 Hz or 48000 Hz, stereo or mono
- License: CC0 (synthesized tone — no rights clearance needed)

---

## Shared Patterns

### Null-pointer Guard
**Source:** `manzo-core/src/lib.rs` Phase 2 (applied in every FFI function)
**Apply to:** Both new FFI getters (`manzo_get_state`, `manzo_get_duration`)

```rust
// i32 getter (manzo_get_state) — return safe sentinel:
if handle.is_null() { return 3; }  // STOPPED

// u64 getter (manzo_get_duration) — return 0:
if handle.is_null() { return 0; }
```

### Arc<Mutex<InnerState>> Lock Pattern
**Source:** `manzo-core/src/lib.rs` lines 161–164 and 288–289 (manzo_play, manzo_pause)
**Apply to:** Both new FFI getters and all modified state transition points

```rust
let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
let state = arc.lock().unwrap_or_else(|e| e.into_inner());
// (use `let mut state` when writing fields)
```

The `unwrap_or_else(|e| e.into_inner())` poison-recovery idiom (T-02-08) must appear on every lock call — do not use plain `.unwrap()`.

### WR-03 Known Limitation Comment
**Source:** `manzo-core/src/lib.rs` lines 192–208 (inside audio callback)
**Apply to:** The audio callback in `manzo_play` — keep the existing comment verbatim when modifying the callback body

The comment documents that the mutex is held across the full decode loop and that the Phase 5 fix is planned. Do not remove or shorten it.

### FFI State Constant Definitions
**Source:** CONTEXT.md D-02 (Swift-side constants to add in bridging header or AppDelegate)
**Apply to:** `ManzoApp/ManzoApp/AppDelegate.swift`

```swift
// D-02 state constants — match manzo_get_state() return values exactly
private let MANZO_STATE_PLAYING: Int32 = 1
private let MANZO_STATE_PAUSED:  Int32 = 2
private let MANZO_STATE_STOPPED: Int32 = 3
private let MANZO_STATE_ENDED:   Int32 = 4
```

Alternatively, if the bridging header is updated, define as C macros:
```c
#define MANZO_STATE_PLAYING 1
#define MANZO_STATE_PAUSED  2
#define MANZO_STATE_STOPPED 3
#define MANZO_STATE_ENDED   4
```

### cbindgen Auto-regeneration
**Source:** `manzo-core/build.rs` (Phase 2 — no change required)
**Apply to:** Both new FFI functions (`manzo_get_state`, `manzo_get_duration`)

cbindgen regenerates `manzo_core.h` automatically on `cargo build`. The new function signatures appear in the header without any manual edit. No changes to `build.rs` or `cbindgen.toml` are needed.

### NSLog Tracing Style
**Source:** `ManzoApp/ManzoApp/AppDelegate.swift` lines 22–38 (Phase 2)
**Apply to:** All new Swift code in AppDelegate

```swift
NSLog("MANZO Phase 3: <description> — <key value>")
```
Prefix with `MANZO Phase 3:`, include a dash-separated key value pair for context. Matches Phase 2 convention exactly.

### Integration Test: open → operate → assert → close
**Source:** `manzo-core/tests/integration_test.rs` lines 20–30 (open_returns_non_null_for_valid_mp3)
**Apply to:** All new integration test functions

```rust
let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
let handle = unsafe { manzo_open(path.as_ptr()) };
assert!(!handle.is_null(), "precondition: manzo_open must succeed");
// ... operate and assert ...
unsafe { manzo_close(handle) };
```
Every test opens fresh, operates, asserts with a descriptive message (third argument), then closes. No shared state between tests.

---

## No Analog Found

No files in Phase 3 are entirely without analog — all are extensions of Phase 2 files or binary fixtures matching the Phase 2 fixture pattern.

---

## Metadata

**Analog search scope:** `manzo-core/src/`, `manzo-core/tests/`, `ManzoApp/ManzoApp/`, `.claude/skills/spike-findings-MANZO/references/`
**Files scanned:** `manzo-core/src/lib.rs`, `ManzoApp/ManzoApp/AppDelegate.swift`, `ManzoApp/ManzoApp/main.swift`, `manzo-core/tests/integration_test.rs`, `.claude/skills/spike-findings-MANZO/references/audio-dsp-pipeline.md`, `.planning/phases/02-audio-pipeline/02-PATTERNS.md`
**Pattern extraction date:** 2026-04-22
