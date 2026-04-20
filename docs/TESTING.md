<!-- generated-by: gsd-doc-writer -->
# MANZO Testing

MANZO has two distinct test layers that must be run separately: Rust unit tests for the `manzo-core` audio/DSP library, and Xcode-based tests for the `ManzoApp` Swift front-end. Both layers must pass before any phase is considered complete.

---

## Test Framework and Setup

### Rust (manzo-core)

- **Framework:** Rust's built-in test harness (`cargo test`)
- **Test location:** Inline `#[cfg(test)]` modules in `manzo-core/src/lib.rs`
- **Required setup:** A working Rust toolchain with the `aarch64-apple-darwin` target installed.

```bash
rustup target add aarch64-apple-darwin
```

No additional test dependencies are declared in `manzo-core/Cargo.toml` — the `[dev-dependencies]` table is intentionally empty; all current tests use only the standard library.

### Swift (ManzoApp)

- **Framework:** XCTest (via Xcode)
- **Required setup:** Xcode 16+ on macOS Sequoia 15+, Apple Silicon Mac. The Rust static library must be built first (see Running Tests below) because the Xcode pre-build script compiles `manzo-core` before linking.
- **ENABLE_TESTABILITY** is set to `YES` in the Xcode project build settings, enabling in-process testing.

No CI configuration (`.github/workflows/`) is present in this repository yet.

---

## Running Tests

### Rust unit tests

Run all tests from the `manzo-core` package directory:

```bash
cd /path/to/MANZO/manzo-core
cargo test
```

To run a specific test by name:

```bash
cargo test stub_play_returns_zero
```

To run all tests and see output even for passing tests:

```bash
cargo test -- --nocapture
```

Cross-compile test run targeting the exact production architecture:

```bash
cargo test --target aarch64-apple-darwin
```

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

### Rust tests

Tests live as inline `#[cfg(test)]` modules directly in the source file under test. The current convention, established in `manzo-core/src/lib.rs`, is:

- Place the `mod tests { ... }` block at the bottom of the source file it tests.
- Use `use super::*;` to import the file's items.
- Name tests descriptively in snake_case: `{subject}_{condition}` (e.g., `stub_play_returns_zero`).
- Each test exercises one specific behavior with a single `assert_eq!` or `assert!`.

Example pattern:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn play_returns_zero_on_success() {
        let result = manzo_play(std::ptr::null_mut());
        assert_eq!(result, 0, "manzo_play must return 0 on success");
    }
}
```

**Safety note for FFI tests:** When testing stub functions that accept raw pointer arguments, passing `std::ptr::null_mut()` is only safe if the stub implementation does not dereference the pointer. Once Phase 2 replaces stubs with real implementations, tests must allocate valid state via `manzo_open` before calling other FFI functions.

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
2. Run Rust tests: `cargo test --target aarch64-apple-darwin` from `manzo-core/`
3. Build release library: `cargo build --release --target aarch64-apple-darwin`
4. Regenerate C header: `cbindgen --config cbindgen.toml --output manzo_core.h`
5. Run Xcode tests: `xcodebuild test -project ManzoApp.xcodeproj -scheme ManzoApp -destination 'platform=macOS,arch=arm64'`

Steps 3 and 4 are required before step 5 because the Xcode pre-build script links against `manzo-core/target/aarch64-apple-darwin/release/libmanzo_core.a`.
