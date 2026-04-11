//
//  HDRToneMapping.metal
//  JellySeeTV
//
//  Vertex + Fragment shader pair that takes a single HDR-aware
//  RGBA16Float texture (linear extended Rec.2020 RGB) coming straight
//  out of AVPlayerItemVideoOutput's pixel transfer session, and renders
//  it into a CAMetalLayer drawable as 8-bit BT.709 SDR using
//  ITU-R BT.2390-3 tone mapping in PQ space.
//
//  Pipeline (per fragment):
//    1. Sample input texture (already linear, BT.2020 primaries, in nits)
//    2. BT.2390-3 tone curve (max-component, hue-preserving)
//    3. BT.2020 → BT.709 color matrix
//    4. Clamp to [0, 1]
//    5. BT.709 OETF (gamma encode for SDR display)
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Constants

// SMPTE ST 2084 (PQ) coefficients — for max-headroom-aware tone mapping in PQ space
constant float PQ_M1 = 2610.0 / 16384.0;
constant float PQ_M2 = 2523.0 / 4096.0 * 128.0;
constant float PQ_C1 = 3424.0 / 4096.0;
constant float PQ_C2 = 2413.0 / 4096.0 * 32.0;
constant float PQ_C3 = 2392.0 / 4096.0 * 32.0;

// BT.2020 → BT.709 color gamut conversion (linear RGB)
constant float3x3 BT2020_TO_BT709 = float3x3(
    float3( 1.6605, -0.1246, -0.0182),  // column 0
    float3(-0.5876,  1.1329, -0.1006),  // column 1
    float3(-0.0728, -0.0083,  1.1187)   // column 2
);

// MARK: - PQ helpers

static float linear_nits_to_pq(float nits) {
    float y = clamp(nits / 10000.0, 0.0, 1.0);
    float y_pow_m1 = pow(y, PQ_M1);
    float numerator = PQ_C1 + PQ_C2 * y_pow_m1;
    float denominator = 1.0 + PQ_C3 * y_pow_m1;
    return pow(numerator / denominator, PQ_M2);
}

static float pq_to_linear_nits(float pq) {
    pq = max(pq, 0.0);
    float e_pow_inv_m2 = pow(pq, 1.0 / PQ_M2);
    float numerator = max(e_pow_inv_m2 - PQ_C1, 0.0);
    float denominator = PQ_C2 - PQ_C3 * e_pow_inv_m2;
    return pow(numerator / denominator, 1.0 / PQ_M1) * 10000.0;
}

// MARK: - BT.709 OETF (gamma encode)

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

// MARK: - BT.2390-3 tone mapping (in PQ space)

// Hermite spline knee curve. Inputs and outputs are in normalized PQ
// space where 1.0 represents the source HDR peak.
static float bt2390_curve(float e1, float maxLum) {
    float ks = 1.5 * maxLum - 0.5;  // knee start
    if (e1 < ks) {
        return e1;  // pass through below the knee
    }
    float t = (e1 - ks) / (1.0 - ks);
    float t2 = t * t;
    float t3 = t2 * t;
    return (2.0 * t3 - 3.0 * t2 + 1.0) * ks
         + (t3 - 2.0 * t2 + t) * (1.0 - ks)
         + (-2.0 * t3 + 3.0 * t2) * maxLum;
}

// Hue-preserving tone mapping: encode max RGB component in PQ space,
// apply BT.2390 curve, decode, scale all channels by the ratio.
static float3 tonemap_bt2390(float3 rgb_nits, float hdr_peak_nits, float sdr_peak_nits) {
    float max_comp = max(rgb_nits.r, max(rgb_nits.g, rgb_nits.b));
    if (max_comp <= 0.0) {
        return float3(0.0);
    }

    float pq_in   = linear_nits_to_pq(max_comp);
    float pq_peak = linear_nits_to_pq(hdr_peak_nits);
    float pq_sdr  = linear_nits_to_pq(sdr_peak_nits);

    float e1 = pq_in / pq_peak;
    float maxLum = pq_sdr / pq_peak;

    float e2 = bt2390_curve(e1, maxLum);

    float pq_out = e2 * pq_peak;
    float max_out = pq_to_linear_nits(pq_out);

    float scale = max_out / max_comp;
    return rgb_nits * scale;
}

// MARK: - Vertex shader (full-screen quad)

struct QuadVertex {
    float4 position [[position]];
    float2 uv;
};

// Full-screen triangle (more efficient than quad — 3 verts instead of 6)
vertex QuadVertex hdr_fullscreen_vertex(uint vid [[vertex_id]]) {
    QuadVertex out;
    // Three vertices that form a triangle covering [-1, +1]^2 with UV [0, 0]..[2, 2]
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0),
    };
    float2 uvs[3] = {
        float2(0.0, 1.0),  // bottom-left
        float2(2.0, 1.0),  // bottom-right (extends past)
        float2(0.0, -1.0), // top-left (extends past)
    };
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

// MARK: - Fragment shader

struct ToneMapUniforms {
    float hdrPeakNits;  // typical HDR10 mastering peak (1000)
    float sdrPeakNits;  // SDR reference white (100)
};

fragment float4 hdr_tone_map_fragment(
    QuadVertex in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    constant ToneMapUniforms& uniforms [[buffer(0)]]
) {
    constexpr sampler texSampler(filter::linear, address::clamp_to_edge);

    // 1. Sample the source texture. AVPlayerItemVideoOutput delivers this
    //    as linear extended Rec.2020 RGB in the [0, big] range (where 1.0
    //    represents 100 nits SDR white). Multiply by 10000 to get nits if
    //    you want, but BT.2390 works in absolute nits, so:
    float4 sample = sourceTexture.sample(texSampler, in.uv);

    // The sample is already linear-light. Apple normalizes it so that
    // 1.0 = 100 nits (SDR reference). Convert to absolute nits.
    float3 rgb_nits = sample.rgb * 100.0;

    // 2. Apply BT.2390-3 tone mapping → linear nits, BT.2020 primaries
    float3 sdr_nits = tonemap_bt2390(rgb_nits, uniforms.hdrPeakNits, uniforms.sdrPeakNits);

    // 3. Normalize to SDR [0, 1] (100 nits → 1.0)
    float3 sdr_linear = sdr_nits / uniforms.sdrPeakNits;

    // 4. BT.2020 → BT.709 color gamut
    float3 sdr_709 = BT2020_TO_BT709 * sdr_linear;
    sdr_709 = clamp(sdr_709, 0.0, 1.0);

    // 5. BT.709 OETF (gamma encode)
    float3 sdr_gamma = bt709_oetf3(sdr_709);

    return float4(sdr_gamma, 1.0);
}
