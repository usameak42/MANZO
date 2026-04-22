---
phase: 4
slug: dsp-engine
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-22
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Rust built-in test (`cargo test`) |
| **Config file** | None — uses Cargo defaults |
| **Quick run command** | `cargo test --manifest-path manzo-core/Cargo.toml --lib` |
| **Full suite command** | `cargo test --manifest-path manzo-core/Cargo.toml -- --include-ignored` |
| **Estimated runtime** | ~5 seconds (non-hardware tests only) |

---

## Sampling Rate

- **After every task commit:** Run `cargo test --manifest-path manzo-core/Cargo.toml --lib`
- **After every plan wave:** Run `cargo test --manifest-path manzo-core/Cargo.toml`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | DSP-01 | T-04-01, T-04-02, T-04-03 | gain clamped ±12 dB; detectdecay non-zero; denormal fix present | unit | `cargo test --manifest-path manzo-core/Cargo.toml --lib eq10` | ❌ W0 | ⬜ pending |
| 04-02-01 | 02 | 2 | DSP-03 | T-04-04 | preamp_gain_linear pre-converted (no powf in callback) | unit | `cargo test --manifest-path manzo-core/Cargo.toml --lib preamp` | ❌ W0 | ⬜ pending |
| 04-02-02 | 02 | 2 | DSP-02, DSP-04 | T-04-04 | vol/pan ramp reaches target in 441 samples | unit | `cargo test --manifest-path manzo-core/Cargo.toml --lib vol_pan` | ❌ W0 | ⬜ pending |
| 04-03-01 | 03 | 3 | DSP-01 | T-04-11 | EQ < 100 µs per 1024-frame stereo buffer | integration | `cargo test --manifest-path manzo-core/Cargo.toml --test integration_test eq_perf_under_100us` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `manzo-core/src/eq10.rs` — `Eq10Band`, `Eq10State`, all port functions (Plan 04-01 creates this)
- [ ] Unit tests in `eq10.rs` `#[cfg(test)]` block — `db2gain_zero`, `new_detectdecay_nonzero`, `flat_eq_is_noop`, `boost_modifies_buffer`, etc.
- [ ] `manzo-core/tests/integration_test.rs` addition — `eq_perf_under_100us` (Plan 04-03 adds this)

*All test infrastructure is created by the plans themselves. No separate Wave 0 setup needed.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| EQ band change takes effect within one buffer period with no audible click | DSP-02 | Requires audio hardware and subjective listening | Play a track, call `manzo_set_eq` with ±12 dB changes mid-playback, listen for clicks or dropouts |
| Volume/pan ramp is audibly smooth (no pops on large step) | DSP-04 | Requires audio hardware; ramp correctness is unit-tested | Play a track, call `manzo_set_volume(0.0)` then `manzo_set_volume(1.0)` rapidly, listen for pops |
| Preamp prevents input clipping at 0 dB full-scale | DSP-03 | Requires audio hardware and signal analysis | Play a 0 dBFS test tone with preamp at +12 dB; limiter should engage, output should not exceed ±1.0 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
