<!-- generated-by: gsd-doc-writer -->
# MANZO

A Winamp-inspired macOS music player built on Rust (audio/DSP) and Swift/AppKit (UI), targeting Apple Silicon and macOS Sequoia 15+. Neo-Aero aesthetic: Frutiger Aero glass chrome with Liquid Glass vibrancy, a real-time Metal spectrum analyzer, and a 10-band EQ ported bit-accurately from Winamp's DSP source.

## Requirements

- macOS Sequoia 15.0 or later
- Apple Silicon (arm64 only — no x86_64 support)
- Xcode 16.0+
- Rust toolchain with the `aarch64-apple-darwin` target
- `cbindgen` (`cargo install cbindgen`)

## Installation

```bash
# Add the Apple Silicon Rust target (once)
rustup target add aarch64-apple-darwin

# Install cbindgen (once)
cargo install cbindgen

# Clone and generate the Xcode project
git clone <repository-url> MANZO
cd MANZO/ManzoApp
xcodegen generate
```

## Quick Start

1. Generate the Xcode project (if not already done):

```bash
cd ManzoApp && xcodegen generate
```

2. Open the project in Xcode:

```bash
open ManzoApp/ManzoApp.xcodeproj
```

3. Build and run with `Cmd+R`. Xcode's pre-build script automatically runs `cargo build --release --target aarch64-apple-darwin` and regenerates `manzo_core.h` via `cbindgen` before linking.

4. Verify the build: the app logs `MANZO Phase 1: FFI smoke test passed` on launch, confirming the Rust staticlib linked correctly.

## Architecture

MANZO is split into two top-level components:

| Component | Language | Role |
|-----------|----------|------|
| `manzo-core/` | Rust | Audio decode (mpg123), DSP (EQ, volume, pan), FFT for spectrum |
| `ManzoApp/` | Swift/AppKit | UI shell, Metal renderer, playlist, FFI calls into manzo-core |

The Rust crate compiles to a static library (`libmanzo_core.a`) linked into the Swift app via a cbindgen-generated C header (`manzo_core.h`). The FFI surface is exactly 11 functions:

```c
manzo_ManzoHandle *manzo_open(const char *path);
void               manzo_close(manzo_ManzoHandle *handle);
int32_t            manzo_play(manzo_ManzoHandle *handle);
void               manzo_pause(manzo_ManzoHandle *handle);
void               manzo_stop(manzo_ManzoHandle *handle);
int32_t            manzo_seek(manzo_ManzoHandle *handle, uint64_t position_ms);
void               manzo_set_eq(manzo_ManzoHandle *handle, const float *gains, float preamp);
void               manzo_set_volume(manzo_ManzoHandle *handle, float volume);
void               manzo_set_pan(manzo_ManzoHandle *handle, float pan);
uint64_t           manzo_get_position(manzo_ManzoHandle *handle);
uintptr_t          manzo_get_spectrum(manzo_ManzoHandle *handle, float *out_buf, uintptr_t count);
```

Key architectural constraints (validated by spike experiments):

- One `.behindWindow` `NSVisualEffectView` at the window root only — nested vibrancy causes double-blur artifacts
- All inner panels: `CALayer`-only, `isOpaque = false`, no nested `NSVisualEffectView`
- P3 colors everywhere: `CGColor(colorSpace: .displayP3)` — no sRGB
- `MTKView` uses `.rgba16Float` pixel format with explicit `CAMetalLayer.colorspace` set to P3
- Float32 audio pipeline end-to-end — no int16 conversion between mpg123 and cpal
- MP3 gapless playback: trim exactly 529 samples of mpg123 decoder delay

## Development Status

Phase 1 (Build Foundation) is complete. The full v1.0 roadmap spans 9 phases and 32 requirements:

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Build Foundation — Cargo+Xcode dual build chain with cbindgen FFI | Complete |
| 2 | Audio Pipeline — MP3 decode via mpg123-sys + cpal/CoreAudio float32 | Not started |
| 3 | Playback Controls — Gapless playback, transport, auto-advance | Not started |
| 4 | DSP Engine — 10-band EQ (eq10dsp.cpp port), volume, pan | Not started |
| 5 | UI Shell — Frameless NSWindow, single-root vibrancy, drag region | Not started |
| 6 | Neo-Aero Visual Stack — 5-layer CALayer specular stack, P3 color | Not started |
| 7 | Spectrum Analyzer — MTKView FFT, SDF bloom, CADisplayLink | Not started |
| 8 | Playlist & Library — File picker, drag-reorder, persistence | Not started |
| 9 | Online Streaming — yt-dlp sidecar, URL streaming | Not started |

## Testing

The Rust core has its own test suite runnable independently of Xcode:

```bash
cd manzo-core
cargo test
```

The tests verify FFI stub contracts (return values, absence of crashes) and must pass before any Phase 2+ work modifies the FFI surface.

## License

License not yet specified.
