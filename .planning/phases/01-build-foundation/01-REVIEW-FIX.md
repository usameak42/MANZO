---
phase: 01-build-foundation
fixed_at: 2026-04-20T00:00:00Z
review_path: .planning/phases/01-build-foundation/01-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-04-20
**Source review:** .planning/phases/01-build-foundation/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4
- Fixed: 4
- Skipped: 0

## Fixed Issues

### WR-01: Silent ABI mismatch if cbindgen absent at build time

**Files modified:** `ManzoApp/project.yml`
**Commit:** 7cf29e5
**Applied fix:** Replaced the silent `if command -v cbindgen` guard with a hard-failure pattern — the cbindgen invocation is now run unconditionally and exits with a descriptive error message (`exit 1`) if cbindgen is not found, preventing a stale header from causing a silent ABI mismatch.

### WR-02: `assert()` in AppDelegate is stripped in Release builds

**Files modified:** `ManzoApp/ManzoApp/AppDelegate.swift`
**Commit:** e482052
**Applied fix:** Changed `assert(result == 0, ...)` to `precondition(result == 0, ...)` on line 8. `precondition()` is enforced in both Debug and Release builds, ensuring the FFI smoke test fires even in optimised binaries.

### WR-03: `manzo_get_spectrum` stub normalizes passing `null_mut()` as output buffer in tests

**Files modified:** `manzo-core/src/lib.rs`
**Commit:** dc29474
**Applied fix:** Two changes in lib.rs:
1. Updated the inline stub comment on line 91 from "stub: return count with zeros (buffer untouched)" to "stub: return count — buffer is NOT written (Phase 2 will write f32 zeros)", aligning it with the actual behaviour (no zeros are written).
2. Added a three-line `NOTE:` comment immediately above the `manzo_get_spectrum` call in `stub_get_spectrum_returns_count` test, explicitly warning that `null_mut()` is only safe because the stub does not dereference `out_buf`, and that Phase 2 must allocate a real buffer.

### WR-04: Target-level Xcode build configurations missing link settings

**Files modified:** `ManzoApp/project.yml`, `ManzoApp/ManzoApp.xcodeproj/project.pbxproj`
**Commit:** 0128280
**Applied fix:** Added a `settings.base` block under the `ManzoApp` target in `project.yml` containing `ARCHS`, `VALID_ARCHS`, `LIBRARY_SEARCH_PATHS`, `HEADER_SEARCH_PATHS`, `OTHER_LDFLAGS`, and `SWIFT_OBJC_BRIDGING_HEADER`. Then ran `xcodegen generate` to regenerate `project.pbxproj`, which now carries these settings explicitly in both the Debug and Release target-level build configuration blocks (verified at lines 139-176 and 161-176 of the regenerated file).

---

_Fixed: 2026-04-20_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
