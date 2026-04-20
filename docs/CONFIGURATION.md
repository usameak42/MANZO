<!-- generated-by: gsd-doc-writer -->
# Configuration

MANZO has no runtime configuration files or environment variables — it is a macOS desktop application that ships as a self-contained `.app` bundle. All configurable values are compiled constants, Xcode build settings, Cargo build flags, and (at runtime) UserDefaults keys persisted by the app itself.

---

## Build-Time Configuration

### Rust Crate — `manzo-core/Cargo.toml`

| Setting | Value | Description |
|---------|-------|-------------|
| `[lib] crate-type` | `["staticlib"]` | Compiles to `libmanzo_core.a` for static linkage |
| `[profile.release] opt-level` | `3` | Maximum compiler optimization |
| `[profile.release] lto` | `true` | Link-time optimization — reduces binary size and enables cross-crate inlining |

Debug builds (the default for `cargo build` without `--release`) omit the `lto` and `opt-level` overrides. The Xcode pre-build script always passes `--release`:

```zsh
cargo build --release \
  --manifest-path "$SRCROOT/../manzo-core/Cargo.toml" \
  --target aarch64-apple-darwin
```

### cbindgen — `manzo-core/cbindgen.toml`

Controls C header generation from the Rust FFI surface.

| Setting | Value | Description |
|---------|-------|-------------|
| `language` | `C` | Output header is plain C, not C++ |
| `include_guard` | `MANZO_CORE_H` | Header guard symbol |
| `[export] prefix` | `manzo_` | All exported symbols are prefixed `manzo_` |
| `documentation` | `true` | Rustdoc comments are reproduced in the generated header |
| `tab_width` | `4` | Indentation in the generated header |

The header is regenerated automatically by the Xcode pre-build script after each `cargo build`. Do not hand-edit `manzo-core/manzo_core.h` — it will be overwritten.

### Xcode Project — `ManzoApp/project.yml` (XcodeGen source)

| Setting | Value | Description |
|---------|-------|-------------|
| `SWIFT_VERSION` | `5.10` | Minimum Swift language version |
| `MACOSX_DEPLOYMENT_TARGET` | `15.0` | macOS Sequoia minimum |
| `ARCHS` | `arm64` | Apple Silicon only — x86_64 is excluded |
| `VALID_ARCHS` | `arm64` | Enforces single-arch throughout |
| `LIBRARY_SEARCH_PATHS` | `$(SRCROOT)/../manzo-core/target/aarch64-apple-darwin/release` | Where Xcode finds `libmanzo_core.a` |
| `HEADER_SEARCH_PATHS` | `$(SRCROOT)/../manzo-core` | Where the bridging header finds `manzo_core.h` |
| `OTHER_LDFLAGS` | `-lmanzo_core` | Links the Rust static library |
| `SWIFT_OBJC_BRIDGING_HEADER` | `ManzoApp/ManzoApp/ManzoApp-Bridging-Header.h` | Exposes the C FFI to Swift |

The `.xcodeproj` is generated from `ManzoApp/project.yml` via XcodeGen. Edit `project.yml` to change build settings — do not modify `project.pbxproj` directly.

---

## App Bundle Identity

Declared in `ManzoApp/ManzoApp/Info.plist` and mirrored in `project.yml`:

| Key | Value |
|-----|-------|
| `CFBundleIdentifier` | `com.manzo.ManzoApp` |
| `CFBundleShortVersionString` | `0.1.0` |
| `LSMinimumSystemVersion` | `15.0` |
| `NSAllowsArbitraryLoads` | `false` (App Transport Security enforced) |

---

## FFI Surface Configuration

The Rust core exposes exactly 11 C-callable functions via the generated header. These are fixed-contract values — changing them requires updating both `manzo-core/src/lib.rs` (Rust side) and the Swift call sites:

| Function | Signature | Notes |
|----------|-----------|-------|
| `manzo_open` | `(const char*) → ManzoHandle*` | Returns null on failure |
| `manzo_close` | `(ManzoHandle*)` | Frees the handle |
| `manzo_play` | `(ManzoHandle*) → i32` | Returns 0 on success |
| `manzo_pause` | `(ManzoHandle*)` | — |
| `manzo_stop` | `(ManzoHandle*)` | Resets position to start |
| `manzo_seek` | `(ManzoHandle*, u64) → i32` | Position in milliseconds |
| `manzo_set_eq` | `(ManzoHandle*, const float[10], float)` | Gains ±12.0 dB; preamp in dB |
| `manzo_set_volume` | `(ManzoHandle*, float)` | Range [0.0, 1.0] |
| `manzo_set_pan` | `(ManzoHandle*, float)` | Range [−1.0, 1.0]; 0.0 = center |
| `manzo_get_position` | `(ManzoHandle*) → u64` | Returns milliseconds |
| `manzo_get_spectrum` | `(ManzoHandle*, float*, usize) → usize` | `count` float32 FFT magnitudes [0.0, 1.0] |

---

## Audio Pipeline Constants

These values are encoded in the Rust implementation and must not be changed without understanding the downstream effects:

| Constant | Value | Source |
|----------|-------|--------|
| MP3 gapless trim | 529 samples | mpg123 decoder priming delay (MPEG Layer 3 spec) |
| EQ bands (Winamp mode) | 70, 180, 320, 600, 1000, 3000, 6000, 12000, 14000, 16000 Hz | From `eq10dsp.cpp` |
| EQ Q factor | 1.41 | From `eq10dsp.cpp` |
| EQ gain range | ±12.0 dB per band | Winamp preset format constraint |
| EQ output limiter | −0.6 dB (`TRIM_CODE = 0.930`) | Prevents clipping on full boost |
| EQ preset byte mapping | `v=31 → 0 dB`; `v>31` boost; `v<31` cut | `.eqf` file format (unsigned char 0–63) |
| Audio sample format | Float32 end-to-end | No int16 conversion in pipeline |

---

## Rendering Constants

Fixed values that define the Neo-Aero / Frutiger Aero visual aesthetic. Changing these alters the look of the app.

### Color Space

All colors are P3 wide-gamut. sRGB values must not be used:

```swift
// Correct — P3 tagged CGColor
let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
let aeroAqua = CGColor(colorSpace: p3, components: [0.0, 0.84, 0.90, 1.0])!

// Wrong — sRGB
// UIColor(red:0, green:0.84, blue:0.90, alpha:1)  // do not use
```

### Aero Color Palette (P3 components)

| Name | P3 Components (R, G, B, A) | Usage |
|------|---------------------------|-------|
| Aqua-teal top | `(0.05, 0.78, 0.82, 1.0)` | Panel base gradient top |
| Deeper teal bottom | `(0.02, 0.52, 0.60, 1.0)` | Panel base gradient bottom |
| Aero aqua | `(0.0, 0.84, 0.90, 1.0)` | Accent / spectrum mid |
| Deep teal (spectrum) | `(0.02, 0.55, 0.65, 1.0)` | Spectrum bar bottom |
| Bright aqua (spectrum) | `(0.0, 0.88, 0.95, 1.0)` | Spectrum bar mid — outside sRGB gamut |
| White-hot (spectrum) | `(0.85, 1.0, 1.0, 1.0)` | Spectrum bar peak — HDR highlight |

### Panel Layer Stack (5 layers per panel)

| Layer | Type | Key Values |
|-------|------|-----------|
| Base gradient | `CAGradientLayer` | Aqua-teal top → deeper teal bottom |
| Specular band | `CAGradientLayer` | Top 52% of height; white alpha 0.50 → 0.08 → 0.0 |
| Lower glow | `CAGradientLayer` | Bottom 25% of height; white alpha 0.0 → 0.12 |
| Rim highlight | `CALayer` | 1 px border, white alpha 0.45, inset 0.5 px |
| Container (clips) | `CALayer` | `cornerRadius = 10`, `masksToBounds = true` |

Performance: `shouldRasterize = true`, `rasterizationScale = 2.0` on all static panels.

### MTKView (Spectrum Analyzer)

| Setting | Value | Reason |
|---------|-------|--------|
| `pixelFormat` | `.rgba16Float` | HDR values > 1.0 for neon bloom |
| `colorspace` | `CGColorSpace.displayP3` | P3 is not configured automatically |
| `wantsExtendedDynamicRangeContent` | `true` | EDR highlights on ProMotion displays |
| Bloom algorithm (v1) | SDF single-pass | No extra textures; glow per-bar |
| Bloom algorithm (v2) | MPS two-pass Gaussian (`sigma = 6.0`, half-res) | Cross-bar glow; < 0.6 ms on M1 |

### NSWindow

| Setting | Value | Reason |
|---------|-------|--------|
| `styleMask` | `[.borderless, .resizable]` | Frameless Winamp-style window |
| `isOpaque` | `false` | Required for Liquid Glass / vibrancy |
| `backgroundColor` | `.clear` | Required for Liquid Glass / vibrancy |
| `collectionBehavior` | `[.canJoinAllSpaces, .stationary]` | Opts out of Stage Manager grouping |
| Root vibrancy | `.behindWindow` (`NSVisualEffectView`) | Exactly one per window; no nesting |
| `layer.cornerRadius` | `16` | Rounded window chrome |

---

## Runtime Persistence (UserDefaults)

Window position and size are persisted between launches via `UserDefaults` (requirement SHELL-05). No key names are documented yet — they will be defined when the UI shell is implemented in Phase 5.

<!-- VERIFY: Final UserDefaults key names for window position and size persistence -->

---

## Online Streaming (Phase 9)

When online streaming is implemented, `yt-dlp` will be bundled at `Contents/MacOS/yt-dlp` inside the app bundle. The quarantine extended attribute (`com.apple.quarantine`) is stripped on first launch. No configuration file is needed — the binary path is resolved relative to `Bundle.main.bundleURL`.

<!-- VERIFY: yt-dlp version to be bundled -->

---

## Per-Environment Notes

MANZO is a macOS desktop app with no server-side components and no staging/production split. There is no `.env` file, no environment variable matrix, and no CI deployment pipeline. The two meaningful "environments" are:

| Environment | Trigger | Key Difference |
|-------------|---------|----------------|
| Debug | `cargo build` (no `--release`) | No LTO, lower opt-level, larger binary |
| Release | `cargo build --release --target aarch64-apple-darwin` | `opt-level = 3`, `lto = true` |

The Xcode pre-build script always uses `--release`. To iterate on Rust code without a full release build, run `cargo build` directly in `manzo-core/` and update `LIBRARY_SEARCH_PATHS` to point at the debug output path (`target/aarch64-apple-darwin/debug`).
