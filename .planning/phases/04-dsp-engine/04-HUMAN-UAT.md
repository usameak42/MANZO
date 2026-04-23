---
status: partial
phase: 04-dsp-engine
source: [04-VERIFICATION.md]
started: 2026-04-23T19:30:00Z
updated: 2026-04-23T19:30:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Real-Time EQ Adjustment Without Dropout
expected: Play a track and call manzo_set_eq to boost bands 1 and 10 to +12 dB during playback. EQ change is audibly present within one buffer period (~23 ms); no dropout, click, or glitch heard at moment of adjustment.
result: [pending]

### 2. Preamp Gain Without Clipping
expected: Play a 0 dBFS tone, call manzo_set_eq with preamp=+12.0. Output level increases audibly; dynamic limiter (0.930 threshold) prevents hard clipping. No distortion beyond what the limiter intentionally applies.
result: [pending]

### 3. Volume Ramp Click-Free Transitions
expected: During playback call manzo_set_volume(0.0) then manzo_set_volume(1.0). Volume ramps linearly over 441 frames (~10 ms) with no pop or click on either transition.
result: [pending]

### 4. Stereo Pan Control
expected: During playback call manzo_set_pan(-1.0), manzo_set_pan(1.0), manzo_set_pan(0.0). Audio pans to correct channel for each call with ~10 ms ramp transition and no click; center returns equal volume on both channels.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
