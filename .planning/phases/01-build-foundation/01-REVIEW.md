---
phase: 01-build-foundation
reviewed: 2026-04-20T00:00:00Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - manzo-core/src/lib.rs
  - manzo-core/build.rs
  - manzo-core/Cargo.toml
  - manzo-core/cbindgen.toml
  - manzo-core/manzo_core.h
  - ManzoApp/ManzoApp/AppDelegate.swift
  - ManzoApp/ManzoApp/main.swift
  - ManzoApp/ManzoApp/ManzoApp-Bridging-Header.h
  - ManzoApp/project.yml
  - ManzoApp/ManzoApp.xcodeproj/project.pbxproj
findings:
  critical: 0
  warning: 4
  info: 2
  total: 6
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-04-20
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

All Phase 1 foundation files are structurally sound. The Rust FFI surface is correct, the
cbindgen pipeline works, and the Swift bridging header links cleanly to the generated C header.
No critical bugs or security issues were found.

Four warnings deserve attention before Phase 2 begins, as they establish patterns or gaps that
will become load-bearing when real audio code arrives. Two informational items are cosmetic but
worth a note for long-term maintainability.

---

## Warnings

### WR-01: Silent ABI mismatch if cbindgen absent at build time

**File:** `ManzoApp/project.yml:57-61` (same pattern duplicated in `ManzoApp/ManzoApp.xcodeproj/project.pbxproj:119`)

**Issue:** The cbindgen header re-generation is guarded by `if command -v cbindgen &> /dev/null`. If cbindgen is not on PATH the script silently skips header regeneration, the `cargo build` still produces a new `.a`, and the Swift compiler uses whatever stale `manzo_core.h` is on disk. If the Rust function signatures changed, the linker succeeds (symbol names match) but the call frame is wrong — silent ABI mismatch at runtime.

**Fix:** Make the guard a hard failure, or pin header regeneration into the Rust build script (already done via `build.rs`) and remove the redundant post-build cbindgen call entirely. If you want to keep it:

```zsh
# Replace the silent guard with a hard error:
cbindgen --config cbindgen.toml --output manzo_core.h \
  || { echo "error: cbindgen not found — install with: cargo install cbindgen"; exit 1; }
```

---

### WR-02: `assert()` in AppDelegate is stripped in Release builds

**File:** `ManzoApp/ManzoApp/AppDelegate.swift:8`

**Issue:** Swift `assert()` is a no-op when compiled with `-O` (Release). The comment on line 5 says "verify it links and calls without crashing" — but in a Release build the assertion silently disappears, so the smoke test provides no protection there. This matters because `applicationDidFinishLaunching` is launch-critical path.

**Fix:** Use `precondition()` which fires in both Debug and Release:

```swift
let result = manzo_play(nil)
precondition(result == 0, "manzo_play stub must return 0")
```

Alternatively, once Phase 2 replaces the stub, replace this entire call with real initialization and remove the assertion.

---

### WR-03: `manzo_get_spectrum` stub normalizes passing `null_mut()` as output buffer in tests

**File:** `manzo-core/src/lib.rs:89-91` and `manzo-core/src/lib.rs:121`

**Issue:** The stub returns `count` without writing into `out_buf`, and the unit test (line 121) passes `std::ptr::null_mut()` as the output buffer. This is safe for the stub, but it establishes a test pattern where the caller never needs to allocate a real buffer. Phase 2's real implementation will write into `out_buf` — if the test is copy-pasted or reused, dereferencing a null pointer causes undefined behavior.

Additionally, the doc comment on line 82 says the buffer "must be at least `count` elements" but the stub comment on line 91 says "stub: return count with zeros (buffer untouched)" — the actual return value is `count` but no zeros are written. The contract is self-contradictory for the stub.

**Fix:** Add a comment on the test making the Phase 2 requirement explicit, and align the stub comment with reality:

```rust
// NOTE: Phase 2 must allocate a real buffer here; null_mut() is only safe
// because the stub does NOT dereference out_buf.
let result = manzo_get_spectrum(std::ptr::null_mut(), std::ptr::null_mut(), 512);

// In lib.rs stub comment: clarify "buffer untouched — Phase 2 will write f32 zeros"
```

---

### WR-04: Target-level Xcode build configurations missing link settings

**File:** `ManzoApp/ManzoApp.xcodeproj/project.pbxproj:136-167`

**Issue:** The two target-level build configurations (`0E27BDB1D4A3BBFA7CDB8FDB` Debug and `422F451AC9235ECFB746E249` Release, lines 136-167) are missing `LIBRARY_SEARCH_PATHS`, `HEADER_SEARCH_PATHS`, `OTHER_LDFLAGS`, `SWIFT_OBJC_BRIDGING_HEADER`, `ARCHS`, and `VALID_ARCHS`. These are only set at the project level (lines 168-299). In Xcode, target-level settings override project-level settings — but if they are empty, the project-level values are inherited, which works today. However, any future scheme customization or target duplication will silently drop these settings and produce a link failure.

**Fix:** Either add the required keys to the target-level Debug and Release blocks:

```
LIBRARY_SEARCH_PATHS = "$(SRCROOT)/../manzo-core/target/aarch64-apple-darwin/release";
HEADER_SEARCH_PATHS = "$(SRCROOT)/../manzo-core";
OTHER_LDFLAGS = "-lmanzo_core";
SWIFT_OBJC_BRIDGING_HEADER = "ManzoApp/ManzoApp-Bridging-Header.h";
ARCHS = arm64;
VALID_ARCHS = arm64;
```

Or, since `project.yml` is the authoritative source and `project.pbxproj` is generated by XcodeGen, ensure the `settings.base` block in `project.yml` regenerates correctly. The current `project.yml` settings are correct; the generated `.pbxproj` may have placed them only at the project level instead of the target level.

---

## Info

### IN-01: `out_dir` variable in build.rs holds crate root, not OUT_DIR

**File:** `manzo-core/build.rs:6`

**Issue:** The variable is named `out_dir` but is assigned `PathBuf::from(&crate_dir)` — the crate manifest directory, not Cargo's `$OUT_DIR`. The naming is misleading for future contributors who would expect `out_dir` to refer to the Cargo output directory.

**Fix:** Rename to match what it actually holds:

```rust
let crate_dir = env::var("CARGO_MANIFEST_DIR").unwrap();
let crate_path = PathBuf::from(&crate_dir);   // was: out_dir

cbindgen::Builder::new()
    .with_crate(&crate_dir)
    .with_config(cbindgen::Config::from_file(
        crate_path.join("cbindgen.toml"),
    ).expect("cbindgen.toml not found"))
    .generate()
    .expect("cbindgen generation failed")
    .write_to_file(crate_path.join("manzo_core.h"));
```

---

### IN-02: cbindgen export prefix produces `manzo_ManzoHandle` type name

**File:** `manzo-core/cbindgen.toml:8` / `manzo-core/manzo_core.h:15-17`

**Issue:** Setting `prefix = "manzo_"` in `[export]` applies to all exported names including struct type names. The struct `ManzoHandle` becomes `manzo_ManzoHandle` in the generated header — a redundant double-prefix. Function names like `manzo_open` are correct, but the type name will appear in all Phase 2+ Swift code as `manzo_ManzoHandle` which reads awkwardly.

**Fix:** Use cbindgen's `[export.rename]` to override just the struct, or rename the Rust struct to `Handle` so the prefixed output becomes `manzo_Handle`:

```toml
[export.rename]
"ManzoHandle" = "ManzoHandle"   # keep the struct name unprefixed
```

Or in cbindgen.toml, use `item_types` to limit prefix application to functions only. This is cosmetic but worth fixing before the type name proliferates in Phase 2 Swift code.

---

_Reviewed: 2026-04-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
