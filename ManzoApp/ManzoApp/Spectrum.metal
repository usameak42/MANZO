#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────────────────
// Spectrum.metal — Bar + peak-dot shaders for MANZO spectrum analyzer.
//
// Two draw passes (driven by ManzoSpectrumView):
//   Pass 1: barVertex + barFragment  — 75 spectrum bars with SDF Gaussian bloom
//   Pass 2: peakVertex + peakFragment — 75 peak-hold dots with stronger bloom
//
// Pixel format: rgba16Float (supports values > 1.0 for HDR glow — SPEC-01)
// Blending: additive (src*srcAlpha + dst*1) — neon glow accumulation
// SDF distance computed in pt-space for isotropic behavior on both axes (CHK-03)
// ─────────────────────────────────────────────────────────────────────────────

// Shared vertex input layout (per vertex, 4 floats = 16 bytes):
//   float4 v = verts[vid]
//   v.x = NDC x position
//   v.y = NDC y position
//   v.z = barIndex (0..74)
//   v.w = barHeight normalized [0.0, 1.0]
//
// ManzoSpectrumView builds these quad buffers on the CPU every CADisplayLink tick.

struct BarVaryings {
    float4 position [[position]];
    float2 uv_pt;       // fragment position in pt-space (225×32 view)
    float  barIndex;
    float  barHeight;
    float  sigma;       // glow sigma — bars=2.0, peaks=4.0
};

// ─────────────────────────────────────────────────────────────────────────────
// specColor: 5-stop ppal2 gradient with P3 neon upgrades (D-12).
//
// h = normalized bar height [0.0 = bottom, 1.0 = top]
// Source: Winamp/Src/Winamp/draw.cpp lines 370–395 (ppal2 default palette).
// P3 neon pushes applied to ppal2[12], ppal2[8-9], ppal2[2] per CONTEXT.md D-12.
//
// DO NOT round or approximate these float4 values — they are canonical from D-12.
// ─────────────────────────────────────────────────────────────────────────────
float4 specColor(float h) {
    float4 c0 = float4(0.094, 0.518, 0.031, 1.0); // ppal2[17] RGB(24,132,8)   — dark green (bottom)
    float4 c1 = float4(0.000, 0.950, 0.060, 1.0); // ppal2[12] → P3 neon green  — outside sRGB
    float4 c2 = float4(0.741, 0.871, 0.161, 1.0); // ppal2[10] RGB(189,222,41)  — yellow-green
    float4 c3 = float4(0.920, 0.750, 0.000, 1.0); // ppal2[8-9] → P3 vivid gold — outside sRGB
    float4 c4 = float4(1.000, 0.120, 0.040, 1.0); // ppal2[2] → P3 saturated red — outside sRGB (top)

    if      (h < 0.35) return mix(c0, c1, h / 0.35);
    else if (h < 0.55) return mix(c1, c2, (h - 0.35) / 0.20);
    else if (h < 0.70) return mix(c2, c3, (h - 0.55) / 0.15);
    else               return mix(c3, c4, (h - 0.70) / 0.30);
}

// ─────────────────────────────────────────────────────────────────────────────
// barVertex — spectrum bar vertex shader.
//
// Input buffer layout: buffer(0) = const device float4* (one float4 per vertex).
// NDC x ∈ [-1,1], NDC y ∈ [-1,1] (Metal convention: bottom-left origin).
// uv_pt converts NDC → pt-space so SDF distance is computed in isotropic pt
// coordinates (view = 225 × 32 pt). CHK-03: doing distance in NDC then scaling
// by a single factor gives anisotropic results because the view is not square.
// ─────────────────────────────────────────────────────────────────────────────
vertex BarVaryings barVertex(
    uint vid [[vertex_id]],
    const device float4* verts [[buffer(0)]])
{
    float4 v = verts[vid];

    BarVaryings out;
    out.position = float4(v.x, v.y, 0.0, 1.0);
    // pt-space: x ∈ [0, 225], y ∈ [0, 32]
    // NDC x ∈ [-1,1] → pt_x = (x + 1.0) * 112.5
    // NDC y ∈ [-1,1] → pt_y = (y + 1.0) * 16.0
    out.uv_pt    = float2((v.x + 1.0) * 112.5, (v.y + 1.0) * 16.0);
    out.barIndex  = v.z;
    out.barHeight = v.w;
    out.sigma     = 2.0;  // bar glow sigma (spike 011)
    return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// barFragment — SDF single-pass bloom for spectrum bars (SPEC-03, spike 011).
//
// The bar quad was extended by 3σ=6 pt on all sides in ManzoSpectrumView.
// Each fragment computes the signed distance to the bar rectangle in pt-space,
// then applies an analytical Gaussian falloff.
//
// Spike 011 validated formula:
//   glow = exp(-d² / (2σ²))
//   output = barColor * glow            (halo region outside bar)
//          + barColor * step(d, 0.5)    (solid core inside ±0.5 pt of edge)
//
// Additive blending on the pipeline means overlapping glows accumulate — giving
// the correct neon-on-black appearance without alpha pre-multiply.
// ─────────────────────────────────────────────────────────────────────────────
fragment float4 barFragment(BarVaryings in [[stage_in]]) {
    float sigma = in.sigma;   // 2.0 for bars
    float barH  = in.barHeight;

    // Silent bars: skip entirely (no visible bar, no glow).
    if (barH < 0.01) return float4(0.0);

    // Bar rectangle in pt-space (view origin = bottom-left).
    float barWidthPt  = 2.0;
    float gapPt       = 1.0;
    float xLeft_pt    = in.barIndex * (barWidthPt + gapPt);
    float xRight_pt   = xLeft_pt + barWidthPt;
    float yBottom_pt  = 0.0;
    float yTop_pt     = barH * 32.0;  // bar top in pt (32 pt = view height)

    float px_pt = in.uv_pt.x;
    float py_pt = in.uv_pt.y;

    // Signed distance from rectangle in pt-space — isotropic on both axes (CHK-03).
    // d2_pt.x > 0: fragment is outside the bar horizontally.
    // d2_pt.y > 0: fragment is outside the bar vertically.
    float2 d2_pt = float2(
        max(xLeft_pt - px_pt, px_pt - xRight_pt),
        max(yBottom_pt - py_pt, py_pt - yTop_pt)
    );
    // length of positive components + negative slack (inside distance is negative).
    float d_pt = length(max(d2_pt, 0.0)) + min(max(d2_pt.x, d2_pt.y), 0.0);

    // Discard fragments far beyond bloom radius (3σ already guaranteed by quad extension).
    if (d_pt > 4.0 * sigma) discard_fragment();

    // Analytical Gaussian glow — spike 011 validated pattern.
    float glow = exp(-d_pt * d_pt / (2.0 * sigma * sigma));

    // Color: sample the ppal2 gradient at fragment's height within the bar.
    // fragH = 0 at bar bottom, 1 at bar top — independent of view height.
    float fragH = saturate((py_pt - yBottom_pt) / max(yTop_pt - yBottom_pt, 0.001));
    float4 barColor = specColor(fragH);

    // Solid core inside 0.5 pt of the bar edge + outer halo.
    float core = step(d_pt, 0.5);
    return barColor * glow + barColor * core;
}

// ─────────────────────────────────────────────────────────────────────────────
// peakVertex — peak-hold dot vertex shader.
//
// Same buffer layout as barVertex. sigma=4.0 (D-16: σ×2.0 for stronger glow).
// ─────────────────────────────────────────────────────────────────────────────
vertex BarVaryings peakVertex(
    uint vid [[vertex_id]],
    const device float4* verts [[buffer(0)]])
{
    float4 v = verts[vid];
    BarVaryings out;
    out.position  = float4(v.x, v.y, 0.0, 1.0);
    out.uv_pt     = float2((v.x + 1.0) * 112.5, (v.y + 1.0) * 16.0);  // pt-space (CHK-03)
    out.barIndex  = v.z;
    out.barHeight = v.w;
    out.sigma     = 4.0;  // peak glow: sigma × 2.0 = 4.0 (D-16, stronger than bars)
    return out;
}

// ─────────────────────────────────────────────────────────────────────────────
// peakFragment — peak-hold dot fragment shader.
//
// Color: ppal2[23] RGB(150,150,150) → float4(0.588, 0.588, 0.588, 1.0) (D-13).
// Neutral gray — reads clearly against all bar height colors.
// Same SDF Gaussian formula as barFragment; sigma=4.0 gives wider, softer glow.
// Peak dot is 1-pt tall × 2-pt wide in pt-space.
// ─────────────────────────────────────────────────────────────────────────────
fragment float4 peakFragment(BarVaryings in [[stage_in]]) {
    float sigma  = in.sigma;   // 4.0 — peak sigma (D-16)
    float peakH  = in.barHeight;

    if (peakH < 0.01) return float4(0.0);

    // Peak dot geometry in pt-space: 2-pt wide, 1-pt tall, centered at peak level.
    float barWidthPt  = 2.0;
    float gapPt       = 1.0;
    float xLeft_pt    = in.barIndex * (barWidthPt + gapPt);
    float xRight_pt   = xLeft_pt + barWidthPt;
    float dotY_pt     = peakH * 32.0;    // dot center in pt
    float yBottom_pt  = dotY_pt - 0.5;  // ±0.5 pt for 1-pt dot height
    float yTop_pt     = dotY_pt + 0.5;

    float px_pt = in.uv_pt.x;
    float py_pt = in.uv_pt.y;

    // SDF rectangle distance in pt-space (isotropic — CHK-03).
    float2 d2_pt = float2(
        max(xLeft_pt - px_pt, px_pt - xRight_pt),
        max(yBottom_pt - py_pt, py_pt - yTop_pt)
    );
    float d_pt = length(max(d2_pt, 0.0)) + min(max(d2_pt.x, d2_pt.y), 0.0);

    if (d_pt > 4.0 * sigma) discard_fragment();

    float glow = exp(-d_pt * d_pt / (2.0 * sigma * sigma));
    float core = step(d_pt, 0.5);

    // D-13: ppal2[23] RGB(150,150,150) — neutral gray, no P3 extension needed.
    float4 dotColor = float4(0.588, 0.588, 0.588, 1.0);
    return dotColor * glow + dotColor * core;
}
