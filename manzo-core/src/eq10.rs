//! 10-band parametric EQ — verbatim Rust port of `winamp/Src/Winamp/eq10dsp.cpp`
// Items in this module are used by Plan 02 (lib.rs wiring); suppress dead_code
// until then so `cargo build` exits with zero warnings.
#![allow(dead_code)]
//!
//! and `eq10dsp.h` (EQ10 Library version 1.0, Copyright (C)2002 4Front Technologies,
//! written by George Yohng).
//!
//! This module is `pub(crate)` — it is not exposed via cbindgen. No new crate
//! dependencies; all floating-point math uses `std::f64`.
//!
//! Key constants (from eq10dsp.h):
//!   EQ10_Q            = 1.41   (global Q factor)
//!   EQ10_NOFBANDS     = 10
//!   EQ10_TRIM_CODE    = 0.930  (dynamic limiter threshold)
//!   EQ10_TRIM_RELEASE = 0.700  (limiter release, seconds)
//!   DENORMAL_FIX      = 1e-30  (added to y0 and detect in sample loops)
//!
//! `EQ10_DETECTOR_CODE` is NOT defined in the shipped Winamp binary; per-band
//! detect/detectdecay fields are not ported.

// ── Struct definitions ────────────────────────────────────────────────────────

/// Per-band biquad IIR filter state.
///
/// Direct Rust translation of `eq10band_t` from eq10dsp.h lines 53-70.
/// All fields are `f64` to match the original's `double` precision.
/// `EQ10_DETECTOR_CODE` is NOT defined — detect/detectdecay per-band are omitted.
#[derive(Clone, Copy)]
pub(crate) struct Eq10Band {
    pub gain: f64,   // shifted-linear; 0.0 == 0 dB (use eq10_db2gain to convert)
    pub ua0: f64,    // boost coefficient a0 (Q*2)
    pub ub1: f64,    // boost coefficient b1
    pub ub2: f64,    // boost coefficient b2
    pub da0: f64,    // cut coefficient a0 (Q*0.5)
    pub db1: f64,    // cut coefficient b1
    pub db2: f64,    // cut coefficient b2
    pub x1: f64,     // input delay line z^-1
    pub x2: f64,     // input delay line z^-2
    pub y1: f64,     // output delay line z^-1
    pub y2: f64,     // output delay line z^-2
}

impl Default for Eq10Band {
    fn default() -> Self {
        Eq10Band {
            gain: 0.0,
            ua0: 0.0, ub1: 0.0, ub2: 0.0,
            da0: 0.0, db1: 0.0, db2: 0.0,
            x1: 0.0, x2: 0.0, y1: 0.0, y2: 0.0,
        }
    }
}

/// Complete EQ state for one audio channel.
///
/// Direct Rust translation of `eq10_t` from eq10dsp.h lines 73-84.
/// One instance per channel (two for stereo: eq_l and eq_r).
///
/// IMPORTANT: Always construct with `Eq10State::new(rate)` — never zero-initialize.
/// `detectdecay = 0.0` disables the limiter entirely (Pitfall 4).
pub(crate) struct Eq10State {
    pub rate: f64,
    pub band: [Eq10Band; 10],
    pub detect: f64,       // global limiter peak tracker
    pub detectdecay: f64,  // pow(0.001, 1/(rate * EQ10_TRIM_RELEASE)) — set in ::new()
}

// Winamp frequency table (eq10_freq[], eq10dsp.cpp line 28)
// Hardcoded for v1 (config_eq_frequencies == EQ_FREQUENCIES_WINAMP)
const FREQS: [f64; 10] = [70.0, 180.0, 320.0, 600.0, 1000.0, 3000.0, 6000.0, 12000.0, 14000.0, 16000.0];

/// Global Q factor (EQ10_Q from eq10dsp.h line 41)
const Q: f64 = 1.41;

impl Eq10State {
    /// Initialize EQ state for the given sample rate.
    ///
    /// Equivalent to `eq10_setup()` from eq10dsp.cpp lines 79-96.
    /// Computes biquad coefficients for all 10 bands at the Winamp frequency table.
    /// MUST be used instead of Default — detectdecay must be non-zero.
    pub(crate) fn new(rate: f64) -> Self {
        let mut state = Eq10State {
            rate,
            band: std::array::from_fn(|_| Eq10Band::default()),
            detect: 0.0,
            // Source: eq10dsp.cpp line 94: pow(0.001, 1.0/(rate*EQ10_TRIM_RELEASE))
            detectdecay: 0.001_f64.powf(1.0 / (rate * 0.700)),
        };
        for (i, band) in state.band.iter_mut().enumerate() {
            eq10_bsetup(rate, band, FREQS[i], Q);
        }
        state
    }
}

// ── Coefficient setup ─────────────────────────────────────────────────────────

/// Compute biquad coefficients for one coefficient set (boost or cut).
///
/// Direct Rust translation of `eq10_bsetup2()` from eq10dsp.cpp lines 36-66.
/// Called twice per band: once for cut (boost=false, q=Q*0.5) and once for boost
/// (boost=true, q=Q*2.0).
///
/// NOTE: The Nyquist guard (line 44) sets BOTH ua0 and da0 to 0.0, regardless
/// of the `boost` parameter — matching the original `band->ua0=band->da0=0`.
fn eq10_bsetup2(boost: bool, rate: f64, band: &mut Eq10Band, freq: f64, q: f64) {
    // Source: eq10dsp.cpp lines 41-43 — rate/freq clamping
    let rate = if rate < 4000.0 { 4000.0 } else if rate > 384000.0 { 384000.0 } else { rate };
    let freq = if freq < 20.0 { 20.0 } else { freq };

    // Source: eq10dsp.cpp line 44 — Nyquist guard: zero BOTH coeff sets and return
    if freq >= rate * 0.499 {
        band.ua0 = 0.0;
        band.da0 = 0.0;
        return;
    }

    // Source: eq10dsp.cpp lines 46-52 — biquad peaking EQ coefficient formulas
    // Note: original uses 3.1415926535897932384626433832795 literally; std::f64::consts::PI matches
    let angle = 2.0 * std::f64::consts::PI * freq / rate;
    let alpha = angle.sin() / (2.0 * q);
    let b0 = 1.0 / (1.0 + alpha);
    let a0 = b0 * alpha;
    let b1 = b0 * 2.0 * angle.cos();
    let b2 = b0 * (alpha - 1.0);

    // Source: eq10dsp.cpp lines 54-65 — u>0 → boost coeffs; u<=0 → cut coeffs
    if boost {
        band.ua0 = a0; band.ub1 = b1; band.ub2 = b2;
    } else {
        band.da0 = a0; band.db1 = b1; band.db2 = b2;
    }
}

/// Compute both coefficient sets for a single band at the given frequency and Q.
///
/// Direct Rust translation of `eq10_bsetup()` from eq10dsp.cpp lines 68-77.
/// Resets all band fields to zero (C: memset), then computes cut and boost coefficients.
pub(crate) fn eq10_bsetup(rate: f64, band: &mut Eq10Band, freq: f64, q: f64) {
    // Source: eq10dsp.cpp line 70 — memset(band, 0, sizeof(*band)) equivalent
    *band = Eq10Band::default();
    // Source: eq10dsp.cpp line 71 — cut coefficients: Q*0.5
    eq10_bsetup2(false, rate, band, freq, q * 0.5);
    // Source: eq10dsp.cpp line 72 — boost coefficients: Q*2.0
    eq10_bsetup2(true, rate, band, freq, q * 2.0);
}

// ── Sample processing ─────────────────────────────────────────────────────────

/// Process one channel of interleaved audio through the 10-band biquad EQ and
/// optional dynamic limiter.
///
/// Direct Rust translation of `eq10_processf()` from eq10dsp.cpp lines 98-206.
/// In-place port: buf == outbuf (same interleaved slice). The copy-only else-if
/// branch (source lines 200-204, only relevant when buf != outbuf) is omitted.
///
/// # Parameters
/// - `eq`:               mutable EQ state for this channel
/// - `buf`:              interleaved audio buffer (modified in place)
/// - `sz`:               number of FRAMES (not samples); for stereo: sz = buf.len() / 2
/// - `idx`:              channel index (0 = left, 1 = right)
/// - `step`:             channel count (2 for stereo)
/// - `config_eq_limiter`: enable dynamic limiter (source: global config_eq_limiter)
pub(crate) fn eq10_processf(
    eq: &mut Eq10State,
    buf: &mut [f32],
    sz: usize,
    idx: usize,
    step: usize,
    config_eq_limiter: bool,
) {
    // Source: eq10dsp.cpp lines 109-175 — 10-band cascade
    // In-place: buf == outbuf; cascade is automatic (next band reads previous band's output).
    // After each band loop, C sets `in = outbuf` (line 165); in Rust we just reuse buf.
    for k in 0..10 {
        let band = &mut eq.band[k];
        let gain = band.gain;

        // Source: eq10dsp.cpp lines 126-137 — select boost or cut coefficients by gain sign
        let (a0, b1, b2) = if gain > 0.0 {
            (band.ua0 * gain, band.ub1, band.ub2)   // boost branch (gain > 0)
        } else {
            (band.da0 * gain, band.db1, band.db2)   // cut branch (gain <= 0)
        };

        // Source: eq10dsp.cpp line 139 — skip flat bands (a0==0.0): correctness + perf
        if a0 == 0.0 { continue; }

        // Load delay lines into locals for LICM / register allocation
        let mut x1 = band.x1;
        let mut x2 = band.x2;
        let mut y1 = band.y1;
        let mut y2 = band.y2;

        // Source: eq10dsp.cpp lines 141-163 — per-sample biquad IIR loop
        // t iterates frames; index into interleaved buffer: idx + t*step
        for t in 0..sz {
            let i = idx + t * step;
            let x = buf[i] as f64;
            // Peaking EQ biquad: y0 = (x - x2)*a0 + y1*b1 + y2*b2 + DENORMAL_FIX
            // Source: eq10dsp.cpp lines 143-148
            let y0 = (x - x2) * a0 + y1 * b1 + y2 * b2 + 1e-30_f64;  // DENORMAL_FIX
            // Source: eq10dsp.cpp line 160 — state update AFTER computing y0
            x2 = x1; x1 = x; y2 = y1; y1 = y0;
            // Source: eq10dsp.cpp line 162 — peaking EQ: add filtered delta to input
            buf[i] = (y0 + x) as f32;
        }

        // Write delay lines back to band struct
        band.x1 = x1; band.x2 = x2; band.y1 = y1; band.y2 = y2;
        // In-place: next band reads the same buf — cascade is automatic (Pitfall 1 avoided)
    }

    // Source: eq10dsp.cpp lines 177-199 — dynamic limiter (EQ10_TRIM_CODE=0.930)
    // config_eq_limiter matches the global `config_eq_limiter` in the original.
    // The copy-only else-if (lines 200-204) is omitted — in-place port only.
    if config_eq_limiter {
        let mut detect = eq.detect;
        let detectdecay = eq.detectdecay;
        for t in 0..sz {
            let i = idx + t * step;
            let s = buf[i] as f64;
            // Source: eq10dsp.cpp line 185 — track absolute peak
            let abs_s = s.abs();
            if abs_s > detect { detect = abs_s; }
            // Source: eq10dsp.cpp lines 188-191 — scale if over threshold
            buf[i] = if detect > 0.930 {
                (s * (0.930 / detect)) as f32
            } else {
                s as f32
            };
            // Source: eq10dsp.cpp lines 193-196 — decay + DENORMAL_FIX
            detect *= detectdecay;
            detect += 1e-30_f64;  // DENORMAL_FIX
        }
        eq.detect = detect;
    }
}

// ── Gain conversion ───────────────────────────────────────────────────────────

/// Convert decibels to the internal shifted-linear gain representation.
///
/// Direct Rust translation of `eq10_db2gain()` from eq10dsp.cpp lines 208-211.
/// 0 dB → 0.0; +12 dB → ≈2.981; -12 dB → ≈-0.749.
/// The shifted-linear form means `gain > 0.0` selects boost coefficients and
/// `gain <= 0.0` selects cut coefficients in `eq10_processf`.
pub(crate) fn eq10_db2gain(gain_db: f64) -> f64 {
    10.0_f64.powf(gain_db / 20.0) - 1.0
}

/// Set a band's gain in dB.
///
/// Direct Rust translation of the `eq10_setgain()` body from eq10dsp.cpp lines 219-231.
pub(crate) fn eq10_setgain(band: &mut Eq10Band, db: f64) {
    band.gain = eq10_db2gain(db);
}

// ── Unit tests ────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    /// eq10_db2gain(0.0) must return exactly 0.0 (pow(10,0)-1 = 1-1 = 0).
    #[test]
    fn db2gain_zero() {
        let result = eq10_db2gain(0.0);
        assert!(
            (result - 0.0_f64).abs() < 1e-10,
            "eq10_db2gain(0.0) = {}, expected 0.0",
            result
        );
    }

    /// eq10_db2gain(12.0) ≈ 2.981 (pow(10, 12/20) - 1).
    #[test]
    fn db2gain_plus12() {
        let result = eq10_db2gain(12.0);
        assert!(
            (result - 2.981_f64).abs() < 0.01,
            "eq10_db2gain(12.0) = {}, expected ≈2.981",
            result
        );
    }

    /// eq10_db2gain(-12.0) ≈ -0.749 (pow(10, -12/20) - 1).
    #[test]
    fn db2gain_minus12() {
        let result = eq10_db2gain(-12.0);
        assert!(
            (result - (-0.749_f64)).abs() < 0.01,
            "eq10_db2gain(-12.0) = {}, expected ≈-0.749",
            result
        );
    }

    /// detectdecay must be non-zero (Pitfall 4: detectdecay=0 disables the limiter).
    #[test]
    fn new_detectdecay_nonzero() {
        let state = Eq10State::new(44100.0);
        assert!(
            state.detectdecay > 0.0,
            "detectdecay = {}, must be > 0.0",
            state.detectdecay
        );
    }

    /// detectdecay must decay slowly at 44.1 kHz with 0.700s release.
    /// Actual: pow(0.001, 1/(44100*0.700)) = 0.99977625... (verified against Python)
    /// Bound: 0.9997 < d < 1.0 — non-zero, less than 1.0, and approximately correct.
    #[test]
    fn new_detectdecay_is_slow_decay() {
        let state = Eq10State::new(44100.0);
        let d = state.detectdecay;
        assert!(
            d > 0.9997 && d < 1.0,
            "detectdecay = {}, expected 0.9997 < d < 1.0",
            d
        );
    }

    /// Band 0 (70 Hz) must have non-zero boost coefficient ua0 after Eq10State::new().
    #[test]
    fn new_band0_has_nonzero_boost() {
        let state = Eq10State::new(44100.0);
        assert!(
            state.band[0].ua0 > 0.0,
            "band[0].ua0 = {}, expected > 0.0 for 70 Hz boost",
            state.band[0].ua0
        );
    }

    /// Band 0 (70 Hz) must have non-zero cut coefficient da0 after Eq10State::new().
    #[test]
    fn new_band0_has_nonzero_cut() {
        let state = Eq10State::new(44100.0);
        assert!(
            state.band[0].da0 > 0.0,
            "band[0].da0 = {}, expected > 0.0 for 70 Hz cut",
            state.band[0].da0
        );
    }

    /// At flat EQ (all gains = 0.0), processf must be a no-op (a0 == 0.0 skip fires).
    /// This is both a correctness test and a verification of Pitfall 2.
    #[test]
    fn flat_eq_is_noop() {
        let mut eq = Eq10State::new(44100.0);
        // All gains default to 0.0 — eq10_db2gain(0.0) = 0.0 → a0 = ua0*0 = 0
        // The a0==0.0 check skips all bands. Also disable limiter for clean test.
        let input: Vec<f32> = (0..2048).map(|i| (i as f32) * 0.001 - 1.0).collect();
        let mut buf = input.clone();
        eq10_processf(&mut eq, &mut buf, 1024, 0, 2, false);
        for (orig, got) in input.iter().zip(buf.iter()) {
            assert!(
                (orig - got).abs() < f32::EPSILON,
                "flat EQ modified sample: orig={}, got={}",
                orig,
                got
            );
        }
    }

    /// With band[0].gain set to +12 dB, processf must modify the buffer.
    /// Tests that the boost path is active and the a0==0.0 skip is bypassed.
    #[test]
    fn boost_modifies_buffer() {
        let mut eq = Eq10State::new(44100.0);
        // Apply +12 dB to band[0] (70 Hz)
        eq.band[0].gain = eq10_db2gain(12.0);
        // Use a non-trivial input so the biquad produces non-zero output
        let input: Vec<f32> = (0..2048).map(|i| ((i as f32) * 0.01).sin() * 0.5).collect();
        let mut buf = input.clone();
        eq10_processf(&mut eq, &mut buf, 1024, 0, 2, false);
        // At least one sample must differ after boosting
        let any_changed = input.iter().zip(buf.iter()).any(|(a, b)| (a - b).abs() > 1e-10);
        assert!(any_changed, "boost did not modify any sample in the buffer");
    }

    /// processf must not panic on a standard 1024-frame stereo buffer (2048 f32 values).
    /// Verifies no out-of-bounds access for idx=0, step=2, sz=1024 (T-04-05).
    #[test]
    fn processf_no_panic_1024_frames() {
        let mut eq = Eq10State::new(44100.0);
        eq.band[0].gain = eq10_db2gain(6.0);  // non-zero gain so hot path runs
        let mut buf = vec![0.5_f32; 2048];
        // Left channel: idx=0, step=2 → max index = 0 + 1023*2 = 2046 (within 2048)
        eq10_processf(&mut eq, &mut buf, 1024, 0, 2, true);
        // Right channel: idx=1, step=2 → max index = 1 + 1023*2 = 2047 (within 2048)
        eq10_processf(&mut eq, &mut buf, 1024, 1, 2, true);
        // If we reach here without panic, the test passes
    }
}
