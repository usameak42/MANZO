---
phase: 01-build-foundation
plan: "01"
subsystem: rust-ffi-core
tags: [rust, staticlib, cbindgen, ffi, aarch64]
dependency_graph:
  requires: []
  provides: [manzo-core staticlib, manzo_core.h C header, 11 FFI stubs]
  affects: [01-02-PLAN.md (Xcode links against libmanzo_core.a + imports manzo_core.h)]
tech_stack:
  added: [Rust 1.95.0, cbindgen 0.27.0, cargo staticlib target]
  patterns: [no_mangle pub extern C, opaque handle (ManzoHandle), let _ = ptr null-check pattern]
key_files:
  created:
    - manzo-core/Cargo.toml
    - manzo-core/Cargo.lock
    - manzo-core/cbindgen.toml
    - manzo-core/build.rs
    - manzo-core/src/lib.rs
    - manzo-core/manzo_core.h
  modified: []
decisions:
  - "cbindgen run via CLI (not build.rs) for manual header generation; build.rs still present for Xcode-triggered rebuilds"
  - "Placeholder src/lib.rs created first so cargo fetch can parse manifest before full implementation"
metrics:
  duration: "4m"
  completed: "2026-04-20"
  tasks_completed: 2
  tasks_total: 2
---

# Phase 1 Plan 01: manzo-core Rust Staticlib + CBIndgen FFI Bridge Summary

**One-liner:** Rust staticlib crate `manzo-core` with 11 no_mangle C-ABI stubs and cbindgen-generated `manzo_core.h` targeting aarch64-apple-darwin.

## What Was Built

- `manzo-core/Cargo.toml` — staticlib crate, cbindgen 0.27 build-dep, release opt-level 3 + LTO
- `manzo-core/cbindgen.toml` — C language output, `MANZO_CORE_H` include guard, `manzo_` prefix
- `manzo-core/build.rs` — `cbindgen::Builder` generates `manzo_core.h` into crate directory on every `cargo build`
- `manzo-core/src/lib.rs` — 11 `#[no_mangle] pub extern "C"` stubs with `ManzoHandle` opaque type, 4 unit tests
- `manzo-core/manzo_core.h` — generated C header with all 11 function declarations and `MANZO_CORE_H` guard

## Verification Results

| Check | Result |
|-------|--------|
| `cargo test --target aarch64-apple-darwin` | 4 passed, 0 failed |
| `lipo -info libmanzo_core.a` | arm64 |
| `grep -c "manzo_" manzo_core.h` | 16 (11 declarations + struct + comments) |
| `#ifndef MANZO_CORE_H` guard present | Yes |
| All 11 function names in header | Yes |
| No `unsafe` blocks in lib.rs | Yes |
| `#[no_mangle]` count | 11 |

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 612642a | feat | create manzo-core staticlib crate with cbindgen config |
| b14a846 | test | add failing tests for 11 FFI stub functions (RED) |
| f7f2e55 | feat | implement 11 no_mangle FFI stubs + generate manzo_core.h (GREEN) |

## TDD Gate Compliance

- RED gate (test commit): b14a846 — tests failed to compile as expected (4 undefined symbols)
- GREEN gate (feat commit): f7f2e55 — all 4 tests pass

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Rust toolchain not installed**
- **Found during:** Task 1 pre-execution
- **Issue:** `cargo` not on PATH; rustup settings present but toolchain partially installed
- **Fix:** Ran `rustup toolchain install stable` + `rustup target remove/add aarch64-apple-darwin` to reinstall the stdlib (lib directory was empty from a prior partial install)
- **Files modified:** None (toolchain install only)
- **Commit:** n/a (environment fix)

**2. [Rule 3 - Blocking] cargo fetch fails without src/lib.rs**
- **Found during:** Task 1 validation
- **Issue:** `cargo fetch` errors with "can't find library `manzo_core`" before `src/lib.rs` exists
- **Fix:** Created minimal placeholder `src/lib.rs` before running `cargo fetch`; replaced with full implementation in Task 2
- **Files modified:** manzo-core/src/lib.rs
- **Commit:** 612642a (placeholder), f7f2e55 (full implementation)

**3. [Rule 3 - Blocking] cbindgen CLI requires `cargo` on PATH**
- **Found during:** Task 2 header generation
- **Issue:** `cbindgen --crate .` panicked — needed cargo accessible in PATH
- **Fix:** Used `PATH="$HOME/.cargo/bin:$PATH" cbindgen --config cbindgen.toml --output manzo_core.h` (without `--crate .` flag)
- **Files modified:** None (invocation change only)
- **Commit:** n/a

## Known Stubs

All 11 FFI functions are intentional stubs — this is the design for Phase 1. Each returns a safe zero/null value and uses `let _ = ptr` to avoid dereferencing null handles (T-01-03 mitigation). Real implementations are added in Phase 2+.

## Threat Flags

No new threat surface beyond what is documented in the plan's `<threat_model>`. All three threat entries (T-01-01, T-01-02, T-01-03) have been addressed:
- T-01-03 (null pointer DoS): mitigated via `let _ = handle` pattern in all stubs.

## Self-Check: PASSED
