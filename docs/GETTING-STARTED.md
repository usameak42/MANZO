<!-- generated-by: gsd-doc-writer -->
# Getting Started with MANZO

MANZO is a Winamp-inspired macOS music player built with Rust (audio/DSP) and Swift/AppKit (UI). This guide walks through prerequisites, installation, and your first build.

---

## Prerequisites

MANZO targets Apple Silicon and macOS Sequoia exclusively. Ensure the following are installed before proceeding.

### System Requirements

- **macOS Sequoia 15.0 or later** — minimum deployment target, no older macOS versions supported
- **Apple Silicon Mac (arm64)** — no x86_64 / Intel support; the build chain targets `aarch64-apple-darwin` only

### Required Toolchain

| Tool | Minimum Version | Install |
|------|----------------|---------|
| Xcode | 16.0 | [Mac App Store](https://apps.apple.com/app/xcode/id497799835) |
| Rust toolchain | stable | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| `aarch64-apple-darwin` target | — | `rustup target add aarch64-apple-darwin` |
| `cbindgen` | — | `cargo install cbindgen` |
| XcodeGen | 2.x | `brew install xcodegen` |

> Xcode Command Line Tools alone are **not** sufficient — the full Xcode.app (16.0+) is required for Swift 5.10 and the Metal shader compiler.

---

## Installation Steps

### 1. Clone the repository

```bash
git clone <repository-url> MANZO
cd MANZO
```

### 2. Add the Rust Apple Silicon target

```bash
rustup target add aarch64-apple-darwin
```

### 3. Install cbindgen

cbindgen generates the C header (`manzo_core.h`) from the Rust FFI surface. The Xcode pre-build script calls it automatically, but it must be installed first.

```bash
cargo install cbindgen
```

### 4. Generate the Xcode project

The Xcode project file is not committed to the repository. It is generated from `ManzoApp/project.yml` using XcodeGen.

```bash
cd ManzoApp
xcodegen generate
```

This writes `ManzoApp/ManzoApp.xcodeproj`.

---

## First Run

### Open and build in Xcode

```bash
open ManzoApp/ManzoApp.xcodeproj
```

Press `Cmd+R` to build and run. Xcode's pre-build script automatically:

1. Runs `cargo build --release --target aarch64-apple-darwin` inside `manzo-core/`
2. Re-generates `manzo-core/manzo_core.h` via `cbindgen`
3. Links `libmanzo_core.a` into the Swift app via the bridging header

### Verify the build succeeded

On launch, the app writes the following line to the Xcode console:

```
MANZO Phase 1: FFI smoke test passed — manzo_play returned 0
```

This confirms the Rust staticlib linked correctly and the 11-function FFI surface is reachable from Swift.

### Run Rust unit tests independently

The Rust core has its own test suite that can be run without opening Xcode:

```bash
cd manzo-core
cargo test
```

These tests verify FFI stub contracts (return values, absence of crashes) and must pass before any Phase 2+ work modifies the FFI surface.

---

## Common Setup Issues

### `cbindgen: command not found` during Xcode build

The Xcode pre-build script exits with an error if `cbindgen` is absent from `$HOME/.cargo/bin`. Fix:

```bash
cargo install cbindgen
```

Restart Xcode after installing so the pre-build script picks up the updated `PATH`.

### `cargo build` fails — `aarch64-apple-darwin` target not installed

```
error[E0463]: can't find crate for `std`
note: the `aarch64-apple-darwin` target may not be installed
```

Fix:

```bash
rustup target add aarch64-apple-darwin
```

### `xcodegen: command not found`

XcodeGen is required to produce the `.xcodeproj` before opening Xcode. Fix:

```bash
brew install xcodegen
```

Then re-run `xcodegen generate` from the `ManzoApp/` directory.

### Build fails — wrong architecture (x86_64 output)

MANZO is arm64-only. If Xcode attempts to build for x86_64 (e.g., because Rosetta is active), the Rust staticlib will be rejected at link time. Ensure Xcode's scheme destination is set to a native Apple Silicon target and that the `ARCHS` build setting remains `arm64`.

---

## Next Steps

- **Architecture overview** — how `manzo-core` (Rust) and `ManzoApp` (Swift) are structured, the FFI surface, and key constraints: `docs/ARCHITECTURE.md`
- **Configuration reference** — Cargo build flags, cbindgen settings, and Xcode build settings: `docs/CONFIGURATION.md`
- **Development workflow** — adding features, running tests, code style: see `docs/DEVELOPMENT.md` (coming soon)
