//
//  HDRToneMapping.metal
//  JellySeeTV
//
//  Compute kernel: HDR (HEVC Main10, BT.2020 PQ/HLG) → SDR (BT.709 8-bit)
//  using ITU-R BT.2390-3 tone mapping in PQ space.
//
//  Used by HDRToneMappingCompositor when an SDR display sees an HDR source.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Constants

// SMPTE ST 2084 (PQ) coefficients
constant float PQ_M1 = 2610.0 / 16384.0;
constant float PQ_M2 = 2523.0 / 4096.0 * 128.0;
constant float PQ_C1 = 3424.0 / 4096.0;
constant float PQ_C2 = 2413.0 / 4096.0 * 32.0;
constant float PQ_C3 = 2392.0 / 4096.0 * 32.0;

// BT.2020 → BT.709 color gamut conversion (linear RGB).
// Negative values represent the part of BT.2020's gamut that's outside
// BT.709 — we clamp afterward.
constant float3x3 BT2020_TO_BT709 = float3x3(
    float3( 1.6605, -0.1246, -0.0182),  // column 0
    float3(-0.5876,  1.1329, -0.1006),  // column 1
    float3(-0.0728, -0.0083,  1.1187)   // column 2
);

// MARK: - Transfer functions

// SMPTE ST 2084 inverse EOTF: PQ-encoded [0,1] → linear nits [0, 10000]
static float pq_to_linear_nits(float pq) {
    pq = max(pq, 0.0);
    float e_pow_inv_m2 = pow(pq, 1.0 / PQ_M2);
    float numerator = max(e_pow_inv_m2 - PQ_C1, 0.0);
    float denominator = PQ_C2 - PQ_C3 * e_pow_inv_m2;
    return pow(numerator / denominator, 1.0 / PQ_M1) * 10000.0;
}

// SMPTE ST 2084 OETF: linear nits [0, 10000] → PQ-encoded [0, 1]
static float linear_nits_to_pq(float nits) {
    float y = clamp(nits / 10000.0, 0.0, 1.0);
    float y_pow_m1 = pow(y, PQ_M1);
    float numerator = PQ_C1 + PQ_C2 * y_pow_m1;
    float denominator = 1.0 + PQ_C3 * y_pow_m1;
    return pow(numerator / denominator, PQ_M2);
}

// ARIB STD-B67 / Rec.2100 HLG inverse OETF: HLG-encoded [0,1] → linear scene
// Output is in [0, 12]; we'll scale by an assumed peak afterward.
static float hlg_to_linear(float hlg) {
    constexpr float a = 0.17883277;
    constexpr float b = 0.28466892;  // 1 - 4*a
    constexpr float c = 0.55991073;  // 0.5 - a * ln(4*a)
    if (hlg <= 0.5) {
        return (hlg * hlg) / 3.0;
    }
    return (exp((hlg - c) / a) + b) / 12.0;
}

// BT.709 OETF (gamma encode for SDR display)
static float bt709_oetf(float linear) {
    linear = clamp(linear, 0.0, 1.0);
    if (linear < 0.018) {
        return 4.5 * linear;
    }
    return 1.099 * pow(linear, 0.45) - 0.099;
}

static float3 bt709_oetf3(float3 linear) {
    return float3(bt709_oetf(linear.r), bt709_oetf(linear.g), bt709_oetf(linear.b));
}

// MARK: - YCbCr ↔ RGB conversion

// 10-bit BT.2020 YCbCr (limited range) → BT.2020 RGB (still in PQ encoding).
// `y`, `cbcr` are normalized [0, 1] reads from r16Unorm / rg16Unorm textures.
// AVFoundation packs the 10-bit value into the upper 10 bits of a 16-bit
// halfword, so reading as r16Unorm/rg16Unorm gives us a 0..1023 / 65535
// quantized value, which is approximately the 10-bit normalized value.
static float3 ycbcr10_lim_to_rgb_bt2020(float y, float2 cbcr) {
    // Dequantize from 10-bit limited range:
    //   Y:   [64/1023, 940/1023]  → [0, 1]
    //   CbCr: [64/1023, 960/1023] → [-0.5, 0.5]
    constexpr float Y_OFFSET = 64.0 / 1023.0;
    constexpr float Y_RANGE  = 1023.0 / (940.0 - 64.0);
    constexpr float C_OFFSET = 64.0 / 1023.0;
    constexpr float C_RANGE  = 1023.0 / (960.0 - 64.0);

    float y_n  = (y          - Y_OFFSET) * Y_RANGE;
    float cb_n = (cbcr.x     - C_OFFSET) * C_RANGE - 0.5;
    float cr_n = (cbcr.y     - C_OFFSET) * C_RANGE - 0.5;

    // BT.2020 non-constant luminance YCbCr → RGB
    float r = y_n + 1.4746 * cr_n;
    float g = y_n - 0.16455 * cb_n - 0.57135 * cr_n;
    float b = y_n + 1.8814 * cb_n;
    return float3(r, g, b);
}

// Linear BT.709 RGB → 8-bit YCbCr (BT.709 limited range, normalized [0,1])
static float3 rgb_bt709_to_ycbcr8_lim(float3 rgb) {
    rgb = clamp(rgb, 0.0, 1.0);
    float y  = 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b;
    float cb = (rgb.b - y) / 1.8556;
    float cr = (rgb.r - y) / 1.5748;

    // 8-bit limited range: Y [16, 235], CbCr [16, 240]
    float y_lim  = y  * (219.0 / 255.0) + (16.0 / 255.0);
    float cb_lim = cb * (224.0 / 255.0) + (128.0 / 255.0);
    float cr_lim = cr * (224.0 / 255.0) + (128.0 / 255.0);
    return float3(y_lim, cb_lim, cr_lim);
}

// MARK: - BT.2390-3 tone mapping (operates in PQ space)

// Hermite spline knee curve. Inputs and outputs are in normalized PQ space
// where 1.0 represents the source HDR peak. The SDR target is at maxLum.
//
// Reference: ITU-R BT.2390-3 Annex 1
static float bt2390_curve(float e1, float maxLum) {
    // Knee point: where the linear pass-through ends and the curve begins
    float ks = 1.5 * maxLum - 0.5;

    if (e1 < ks) {
        // Below the knee — linear pass-through
        return e1;
    }

    // Above the knee — Hermite spline that smoothly compresses [ks, 1] → [ks, maxLum]
    float t = (e1 - ks) / (1.0 - ks);
    float t2 = t * t;
    float t3 = t2 * t;

    return (2.0 * t3 - 3.0 * t2 + 1.0) * ks
         + (t3 - 2.0 * t2 + t) * (1.0 - ks)
         + (-2.0 * t3 + 3.0 * t2) * maxLum;
}

// Apply BT.2390 tone mapping to a linear-light RGB triplet (in nits).
// Preserves hue by scaling RGB uniformly based on the tone-mapped maximum
// component.
static float3 tonemap_bt2390(float3 rgb_nits, float hdr_peak_nits, float sdr_peak_nits) {
    float max_comp = max(rgb_nits.r, max(rgb_nits.g, rgb_nits.b));
    if (max_comp <= 0.0) {
        return float3(0.0);
    }

    // Encode max-component, HDR peak, and SDR target to PQ
    float pq_in   = linear_nits_to_pq(max_comp);
    float pq_peak = linear_nits_to_pq(hdr_peak_nits);
    float pq_sdr  = linear_nits_to_pq(sdr_peak_nits);

    // Normalize source value to source HDR peak
    float e1 = pq_in / pq_peak;
    // SDR target normalized to source HDR peak (this is the BT.2390 maxLum)
    float maxLum = pq_sdr / pq_peak;

    // Apply curve
    float e2 = bt2390_curve(e1, maxLum);

    // Decode back: SDR target normalized result × HDR-peak PQ → linear nits
    float pq_out = e2 * pq_peak;
    float max_out = pq_to_linear_nits(pq_out);

    // Scale all channels uniformly to preserve hue
    float scale = max_out / max_comp;
    return rgb_nits * scale;
}

// MARK: - Uniforms

struct ToneMapUniforms {
    uint  transferFunction;  // 0 = PQ (HDR10/DV base layer), 1 = HLG
    float hdrPeakNits;        // assumed source HDR peak (typ. 1000 for HDR10)
    float sdrPeakNits;        // SDR display reference white (always 100)
};

// MARK: - Compute kernel

kernel void hdr_to_sdr_tone_map(
    texture2d<float, access::read>  yIn      [[texture(0)]],
    texture2d<float, access::read>  cbcrIn   [[texture(1)]],
    texture2d<float, access::write> yOut     [[texture(2)]],
    texture2d<float, access::write> cbcrOut  [[texture(3)]],
    constant ToneMapUniforms& uniforms       [[buffer(0)]],
    uint2 gid                                [[thread_position_in_grid]]
) {
    // Bounds check (Y plane = full output resolution)
    if (gid.x >= yOut.get_width() || gid.y >= yOut.get_height()) {
        return;
    }

    // 1. Read Y at full resolution and CbCr at half resolution (4:2:0 subsample)
    float y_pq = yIn.read(gid).r;
    uint2 cbcr_coord = gid / 2;
    float2 cbcr_pq = cbcrIn.read(cbcr_coord).rg;

    // 2. YCbCr → RGB (still in PQ/HLG encoding, BT.2020 primaries)
    float3 rgb_pq = ycbcr10_lim_to_rgb_bt2020(y_pq, cbcr_pq);

    // 3. Inverse transfer function: PQ/HLG → linear-light nits
    float3 rgb_linear;
    if (uniforms.transferFunction == 0u) {
        rgb_linear = float3(
            pq_to_linear_nits(rgb_pq.r),
            pq_to_linear_nits(rgb_pq.g),
            pq_to_linear_nits(rgb_pq.b)
        );
    } else {
        // HLG nominal peak ≈ 1000 nits
        rgb_linear = float3(
            hlg_to_linear(rgb_pq.r),
            hlg_to_linear(rgb_pq.g),
            hlg_to_linear(rgb_pq.b)
        ) * 1000.0;
    }

    // 4. BT.2390-3 tone mapping in PQ space
    float3 sdr_nits = tonemap_bt2390(rgb_linear, uniforms.hdrPeakNits, uniforms.sdrPeakNits);

    // 5. Normalize to SDR [0, 1] (100 nits → 1.0)
    float3 sdr_linear = sdr_nits / uniforms.sdrPeakNits;

    // 6. Color gamut: BT.2020 → BT.709 (still linear)
    float3 sdr_709 = BT2020_TO_BT709 * sdr_linear;
    sdr_709 = clamp(sdr_709, 0.0, 1.0);

    // 7. BT.709 OETF (gamma encode)
    float3 sdr_gamma = bt709_oetf3(sdr_709);

    // 8. RGB BT.709 → YCbCr 8-bit limited range
    float3 ycbcr_out = rgb_bt709_to_ycbcr8_lim(sdr_gamma);

    // 9. Write Y at full resolution
    yOut.write(float4(ycbcr_out.x, 0.0, 0.0, 1.0), gid);

    // 10. Write CbCr at half resolution — only on the top-left of each 2×2 block
    if ((gid.x & 1u) == 0u && (gid.y & 1u) == 0u) {
        cbcrOut.write(float4(ycbcr_out.y, ycbcr_out.z, 0.0, 1.0), cbcr_coord);
    }
}
