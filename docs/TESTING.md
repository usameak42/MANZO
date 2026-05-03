<!-- generated-by: gsd-doc-writer -->
# MANZO Testing

MANZO has two distinct test layers that must be run separately: Rust unit and integration tests for the `manzo-core` audio/DSP library, and Xcode-based tests for the `ManzoApp` Swift front-end. Both layers must pass before any phase is considered complete.

---

## Test Framework and Setup

### Rust (manzo-core)

- **Framework:** Rust's built-in test harness (`cargo test`)
- **Test locations:**
  - Inline `#[cfg(test)]` modules in `manzo-core/src/lib.rs` (unit tests — null-handle guards and sentinel returns)
  - `manzo-core/tests/integration_test.rs` (integration tests — full open/play/close pipeline against real MP3 fixtures)
- **Test fixtures:** `manzo-core/tests/fixtures/test.mp3` (~5s CC0 sine-tone) and `manzo-core/tests/fixtures/test2.mp3` (~1s clip for ENDED-state polling)
- **Required setup:** A working Rust toolchain with the `aarch64-apple-darwin` target installed.

```bash
rustup target add aarch64-apple-darwin
```

No additional test dependencies are declared in `manzo-core/Cargo.toml` — the `[dev-dependencies]` table is intentionally empty; all current tests use only the standard library and the crate's own public API.

### Swift (ManzoApp)

- **Framework:** XCTest (via Xcode)
- **Required setup:** Xcode 16+ on macOS Sequoia 15+, Apple Silicon Mac. The Rust static library must be built first (see Running Tests below) because the Xcode pre-build script compiles `manzo-core` before linking.
- **ENABLE_TESTABILITY** is set to `YES` in the Xcode project build settings, enabling in-process testing.
- No dedicated test target is currently defined in `ManzoApp.xcodeproj`. XCTest files can be added to the main app target using `ENABLE_TESTABILITY = YES`.

No CI configuration (`.github/workflows/`) is present in this repository yet.

---

## Running Tests

### Rust unit tests

Run all unit tests from the `manzo-core` package directory:

```bash
cd /path/to/MANZO/manzo-core
cargo test
```

To run a specific test by name:

```bash
cargo test play_null_returns_minus_one
```

To run all tests and see output even for passing tests:

```bash
cargo test -- --nocapture
```

Cross-compile test run targeting the exact production architecture:

```bash
cargo test --target aarch64-apple-darwin
```

### Rust integration tests

Integration tests live in `manzo-core/tests/integration_test.rs` and use real MP3 fixtures. Run them explicitly:

```bash
cd /path/to/MANZO/manzo-core
cargo test --test integration_test
```

Several integration tests require audio output hardware and are marked `#[ignore]`. To run all tests including those:

```bash
cargo test --test integration_test -- --include-ignored
```

To run only the hardware-requiring tests in isolation:

```bash
cargo test --test integration_test -- --ignored
```

The integration tests that run without audio hardware (safe for headless CI):

| Test | What it verifies |
|---|---|
| `open_returns_non_null_for_valid_mp3` | `manzo_open` returns non-null for a valid MP3 |
| `open_returns_null_for_invalid_path` | `manzo_open` returns null for a nonexistent path |
| `spectrum_buffer_is_zero_filled` | `manzo_get_spectrum` zero-fills before first playback (D-01) |
| `spectrum_null_buf_returns_zero` | `manzo_get_spectrum` with null buffer returns 0 (T-02-06) |
| `get_state_returns_stopped_after_open` | Fresh handle reports state 3 (STOPPED) (D-02) |
| `get_duration_returns_nonzero_for_valid_mp3` | `manzo_get_duration` returns >0 ms for a valid MP3 |
| `eq_perf_under_100us` | 10-band EQ processing ≤100 µs p99 over 1000 iterations (D-07) |

Tests requiring audio hardware (marked `#[ignore]`):

| Test | What it verifies |
|---|---|
| `play_advances_position` | Playback position advances after 200ms of play |
| `state_transitions_play_pause_stop` | Full state machine: PLAYING→PAUSED→STOPPED (D-02) |
| `state_becomes_ended_after_short_track_completes` | ENDED state (4) reached within 3s for a ~1s clip (AUDIO-05) |

### Swift / Xcode tests

Build the Rust library first (required before any Xcode build):

```bash
cd /path/to/MANZO/manzo-core
cargo build --release --target aarch64-apple-darwin
cbindgen --config cbindgen.toml --output manzo_core.h
```

Then run the Xcode test scheme from the command line:

```bash
cd /path/to/MANZO/ManzoApp
xcodebuild test \
  -project ManzoApp.xcodeproj \
  -scheme ManzoApp \
  -destination 'platform=macOS,arch=arm64'
```

Or run directly in Xcode with Cmd+U.

---

## Writing New Tests

### Rust unit tests

Unit tests live as inline `#[cfg(test)]` modules directly in the source file under test. The current convention, established in `manzo-core/src/lib.rs`, is:

- Place the `mod tests { ... }` block at the bottom of the source file it tests.
- Use `use super::*;` to import the file's items.
- Name tests descriptively in snake_case: `{subject}_{condition}` (e.g., `play_null_returns_minus_one`).
- Each test exercises one specific behavior with a single `assert_eq!` or `assert!`.

Example pattern:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn get_state_null_returns_stopped() {
        let result = manzo_get_state(std::ptr::null_mut());
        assert_eq!(result, 3, "manzo_get_state with null handle must return 3 (STOPPED)");
    }
}
```

### Rust integration tests

Integration tests live in `manzo-core/tests/integration_test.rs` and import from the crate via `use manzo_core::...`. The crate exposes both `staticlib` and `rlib` output (see `Cargo.toml` `[lib].crate-type`) so integration tests can link against the `rlib`.

**Safety note for FFI tests:** Phases 2–4 are complete — all 13 FFI functions have real implementations. Tests must allocate a valid handle via `manzo_open` before calling any other function, and must call `manzo_close` to release it when done. Passing `std::ptr::null_mut()` is only valid for tests that specifically exercise null-guard behavior (the `*_null_*` unit tests in `src/lib.rs`).

```rust
use manzo_core::{manzo_open, manzo_close, manzo_get_state};
use std::ffi::CString;

const FIXTURE_PATH: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/test.mp3");

#[test]
fn my_new_integration_test() {
    let path = CString::new(FIXTURE_PATH).expect("no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    // ... exercise the function under test ...

    unsafe { manzo_close(handle) };
}
```

Tests that require audio output hardware must be marked `#[ignore]` so they are skipped in headless CI environments:

```rust
#[test]
#[ignore = "requires audio output hardware; not available in headless CI environments"]
fn my_audio_hardware_test() { ... }
```

### Swift tests

Add test files to the `ManzoApp` Xcode target with `ENABLE_TESTABILITY = YES`. Follow XCTest conventions:

- File name: `{Subject}Tests.swift`
- Class: `class {Subject}Tests: XCTestCase`
- Method name: `func test{Behavior}()`

---

## Coverage Requirements

No coverage thresholds are currently configured. The `manzo-core/Cargo.toml` does not specify a coverage tool (e.g., `cargo-llvm-cov`, `tarpaulin`), and there is no `.nycrc` or similar configuration.

To generate a coverage report manually using `cargo-llvm-cov` (must be installed separately):

```bash
cargo install cargo-llvm-cov
cd /path/to/MANZO/manzo-core
cargo llvm-cov --target aarch64-apple-darwin
```

---

## CI Integration

No CI pipeline is configured in this repository. There is no `.github/workflows/` directory. Tests must be run manually.

When CI is added, the recommended test step sequence is:

1. Install Rust toolchain: `rustup target add aarch64-apple-darwin`
2. Run Rust unit tests: `cargo test --target aarch64-apple-darwin` from `manzo-core/`
3. Run Rust integration tests (headless-safe subset): `cargo test --test integration_test --target aarch64-apple-darwin` from `manzo-core/`
4. Build release library: `cargo build --release --target aarch64-apple-darwin`
5. Regenerate C header: `cbindgen --config cbindgen.toml --output manzo_core.h`
6. Run Xcode tests: `xcodebuild test -project ManzoApp.xcodeproj -scheme ManzoApp -destination 'platform=macOS,arch=arm64'`

Steps 4 and 5 are required before step 6 because the Xcode pre-build script links against `manzo-core/target/aarch64-apple-darwin/release/libmanzo_core.a`.

The hardware-requiring integration tests (`play_advances_position`, `state_transitions_play_pause_stop`, `state_becomes_ended_after_short_track_completes`) are marked `#[ignore]` and will be skipped in step 3 unless a macOS runner with audio output is available.
