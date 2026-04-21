# Phase 2: Audio Pipeline - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-22
**Phase:** 02-audio-pipeline
**Areas discussed:** Spectrum stub scope, Decode threading model, Test MP3 in repo, Error reporting to Swift

---

## Scope Note

**User question:** Should Phase 2 handle MP3 only via mpg123, or also FLAC and WAV? If FLAC/WAV are deferred, which phase do they land in?

**Resolution:** FLAC/WAV/AAC/OGG are v2 requirements under ADVAUDIO-01 — no v1 phase covers them. Phase 2 is MP3-only via mpg123-sys, locked by AUDIO-01 and AUDIO-04.

---

## Spectrum stub scope

| Option | Description | Selected |
|--------|-------------|----------|
| Zero-fill only | Write f32 zeros into out_buf. Phase 7 replaces with real RustFFT. | ✓ |
| Real FFT now | Implement RustFFT magnitude pipeline in Phase 2. | |

**User's choice:** Zero-fill only
**Notes:** Phase 2 stays focused on decode+output. Spectrum FFT is Phase 7's domain.

---

## Decode threading model

| Option | Description | Selected |
|--------|-------------|----------|
| Arc<Mutex<>> | Standard Rust approach — decoder + state behind a Mutex shared between cpal callback and Swift FFI calls. | ✓ |
| Lock-free ring buffer | Command channel from FFI → audio thread; audio thread owns all mutable state. Zero contention, more complexity. | |
| You decide | Let the planner choose. | |

**User's choice:** Arc<Mutex<>>
**Notes:** Mutex contention is negligible for a music player. Lock-free channel deferred.

---

## Test MP3 in repo

| Option | Description | Selected |
|--------|-------------|----------|
| Commit a CC0 test clip | ~5s CC0/royalty-free MP3 in tests/fixtures/ for automated Rust integration testing. | ✓ |
| Manual verification only | No test file committed; manual file selection during verification. | |

**User's choice:** Commit a CC0 test clip
**Notes:** Enables automated acceptance testing — planner should include step to generate or download a CC0 sine tone MP3 via sox.

---

## Error reporting to Swift

| Option | Description | Selected |
|--------|-------------|----------|
| Null + return codes only | manzo_open returns null; manzo_play/seek return non-zero i32. Sufficient for Phase 2. | ✓ |
| Add manzo_last_error() now | Expose C-string error message from Rust. More FFI surface. | |

**User's choice:** Null + return codes only
**Notes:** Richer error API deferred to Phase 3 when UI error display is needed.

---

## Claude's Discretion

- Internal InnerState struct fields
- mpg123 feed chunk size (4096 bytes from spike 003)
- cpal BufferSize (default CoreAudio)
- Ring buffer sizing between decoder and cpal callback
- File reading strategy (mmap vs buffered File)

## Deferred Ideas

- FLAC/WAV/AAC/OGG support — v2, ADVAUDIO-01
- manzo_last_error() — Phase 3
- Lock-free threading — deferred
- Spectrum FFT pipeline — Phase 7
