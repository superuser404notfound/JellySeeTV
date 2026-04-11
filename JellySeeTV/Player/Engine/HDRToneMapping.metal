//
//  HDRToneMapping.metal
//  JellySeeTV
//
//  Trivial vertex + fragment pair that draws a single texture (already
//  in 8-bit BT.709 SDR BGRA, courtesy of AVPlayerItemVideoOutput's pixel
//  transfer session) to a full-screen quad on the CAMetalLayer drawable.
//
//  Apple's pixel transfer session does the heavy lifting:
//   - HDR sources (HEVC Main10 / HDR10 / HLG / Dolby Vision) → tone-mapped
//     to BT.709 SDR before they reach us
//   - SDR sources → pass through unchanged
//   - YCbCr / packed / lossless / whatever → converted to BGRA
//
//  We just need to put the pixels on the screen with the correct aspect
//  ratio. The actual aspect-fit happens via the MTLViewport set on the
//  CPU side; the shader just samples and outputs.
//

#include <metal_stdlib>
using namespace metal;

struct QuadVertex {
    float4 position [[position]];
    float2 uv;
};

// Single full-screen triangle (more efficient than a quad — 3 verts
// instead of 6) covering NDC [-1, +1]² with UV [0, 1]² over the visible
// portion. The off-screen verts get clipped automatically.
vertex QuadVertex hdr_fullscreen_vertex(uint vid [[vertex_id]]) {
    QuadVertex out;
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0),
    };
    float2 uvs[3] = {
        float2(0.0, 1.0),  // bottom-left → flipped V (Metal y-down sample)
        float2(2.0, 1.0),
        float2(0.0, -1.0),
    };
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

// Sample the source texture and output as-is. Apple's pixel transfer
// session has already done all the color conversion / tone mapping.
fragment float4 hdr_tone_map_fragment(
    QuadVertex in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]]
) {
    constexpr sampler texSampler(filter::linear, address::clamp_to_edge);
    return sourceTexture.sample(texSampler, in.uv);
}
