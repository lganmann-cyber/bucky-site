// Procedural film grain as a stitchable Core Image kernel.
//
// Grain is value noise evaluated per grain cell (cell size scales with output
// resolution), luminance-weighted toward shadows/mids, with a controllable
// chroma component. Nothing is textured or tiled — every pixel is computed
// from (coordinate, seed), so re-renders with the same seed are identical and
// grain never repeats across the frame.

#include <metal_stdlib>
#include <CoreImage/CoreImage.h>

using namespace metal;

namespace {

// Deterministic hash → [0, 1). Standard fract-sin free integer hash so the
// pattern is stable across GPU families.
inline float hash13(float3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

// Smooth value noise over grain cells: nearest-cell randomness with
// interpolation so clumps read as silver halide, not pixel salt.
inline float grainNoise(float2 coord, float cellSize, float seed) {
    float2 c = coord / max(cellSize, 1.0f);
    float2 base = floor(c);
    float2 f = fract(c);
    f = f * f * (3.0f - 2.0f * f);
    float a = hash13(float3(base, seed));
    float b = hash13(float3(base + float2(1, 0), seed));
    float d = hash13(float3(base + float2(0, 1), seed));
    float e = hash13(float3(base + float2(1, 1), seed));
    return mix(mix(a, b, f.x), mix(d, e, f.x), f.y);
}

} // namespace

extern "C" {

[[stitchable]] float4
osGrain(coreimage::sample_t s,
        float seed,
        float intensity,
        float cellSize,
        float chromaMix,
        float shadowWeight,
        coreimage::destination dest)
{
    float2 coord = dest.coord();

    // Independent noise fields for luma and the two chroma axes.
    float nLuma = grainNoise(coord, cellSize, seed) - 0.5f;
    float nR = grainNoise(coord, cellSize, seed + 17.0f) - 0.5f;
    float nB = grainNoise(coord, cellSize, seed + 41.0f) - 0.5f;

    float luma = dot(s.rgb, float3(0.299f, 0.587f, 0.114f));

    // Real neg film grain reads strongest in shadows and mids; highlights
    // stay comparatively clean. shadowWeight = 0 → uniform grain.
    float zone = mix(1.0f, 1.0f - luma * luma, shadowWeight);
    float amount = intensity * zone;

    float3 grain = float3(nLuma) + chromaMix * float3(nR, 0.0f, nB);
    float3 rgb = s.rgb + grain * amount;

    return float4(clamp(rgb, 0.0f, 1.0f), s.a);
}

} // extern "C"
