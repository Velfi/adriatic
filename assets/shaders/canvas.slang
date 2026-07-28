// Minimal Adriatic canvas pipeline. The engine owns Vulkan setup; this shader
// defines the product-side presentation contract for canvas2d batches.
struct Push {
    float4 viewport;
    float4 texture_hatch;
    float4 hatch_shape;
    float4 hatch_tone;
    float4 hatch_offset;
    float4 hatch_angles;
    float4 hatch_levels;
};

[[vk::push_constant]] ConstantBuffer<Push> push;
[[vk::binding(0, 0)]] Texture2D<float4> ui_texture;
[[vk::binding(1, 0)]] SamplerState ui_sampler;

struct VertexInput {
    float2 position : POSITION;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

struct VertexOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

// Canvas colors originate as ordinary 8-bit sRGB palette values. Decode them
// before interpolation, texture modulation, and blending. Sampled UI textures
// already arrive in linear light from their sRGB image format.
float srgb_channel_to_linear(float color) {
    return color <= 0.04045
        ? color / 12.92
        : pow((color + 0.055) / 1.055, 2.4);
}

float3 srgb_to_linear(float3 color) {
    return float3(srgb_channel_to_linear(color.r),
                  srgb_channel_to_linear(color.g),
                  srgb_channel_to_linear(color.b));
}

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    float2 pixel = round(input.position / push.viewport.xy * push.viewport.zw);
    float2 ndc = pixel / push.viewport.zw * 2.0 - 1.0;
    output.position = float4(ndc, 0, 1);
    output.uv = input.uv;
    output.color = float4(srgb_to_linear(input.color.rgb), input.color.a);
    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    float4 texel = ui_texture.Sample(ui_sampler, input.uv);
    if (push.texture_hatch.x > 1.5) {
        return float4(input.color.rgb, input.color.a * texel.r);
    }
    return push.texture_hatch.x > .5 ? input.color * texel : input.color;
}

struct PostOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

// Miyazaki 16 by skeddles:
// https://lospec.com/palette-list/miyazaki-16
static const float3 ADRIATIC_PALETTE_LINEAR[16] = {
    float3(0.01680738, 0.01599629, 0.02121901),
    float3(0.02121901, 0.05448028, 0.11953843),
    float3(0.11443537, 0.09758735, 0.08865559),
    float3(0.24228112, 0.23455058, 0.17144110),
    float3(0.47932018, 0.43415364, 0.30054379),
    float3(0.54572446, 0.66538730, 0.57112483),
    float3(0.83076988, 0.83879901, 0.71569350),
    float3(0.01764195, 0.23455058, 0.38132601),
    float3(0.08865559, 0.49102085, 0.64447968),
    float3(0.17788842, 0.07421357, 0.05951124),
    float3(0.56471151, 0.08021982, 0.06124605),
    float3(0.79129794, 0.28744084, 0.25415209),
    float3(0.01298303, 0.17464740, 0.08650046),
    float3(0.09084171, 0.35153260, 0.09758735),
    float3(0.35640014, 0.52099557, 0.05286065),
    float3(0.76815115, 0.52711513, 0.08865559),
};

static const float3 ADRIATIC_PALETTE_OKLAB[16] = {
    float3(0.25556344, 0.00443450, -0.01032887),
    float3(0.37326412, -0.01759958, -0.05997703),
    float3(0.46575298, 0.00688358, 0.00878430),
    float3(0.61324253, -0.00546111, 0.02583939),
    float3(0.75662109, -0.00229202, 0.03828259),
    float3(0.85548163, -0.02412260, 0.01266057),
    float3(0.93798374, -0.00716268, 0.01999996),
    float3(0.57718602, -0.06901060, -0.07113464),
    float3(0.73792369, -0.08122130, -0.05823066),
    float3(0.46260112, 0.04787277, 0.02964259),
    float3(0.58435026, 0.13562879, 0.07089048),
    float3(0.74368690, 0.09297641, 0.04481514),
    float3(0.49986186, -0.09210481, 0.02831789),
    float3(0.63919908, -0.10520609, 0.07452333),
    float3(0.75801591, -0.08096465, 0.13117717),
    float3(0.81794441, -0.00279554, 0.13173212),
};

// Matriax8c by Davit Masia:
// https://lospec.com/palette-list/matriax8c
static const float3 MATRIAX8C_PALETTE_LINEAR[8] = {
    float3(0.87136712, 0.87136712, 0.71569350),
    float3(0.95597335, 0.57758044, 0.00000000),
    float3(0.00518152, 0.57758044, 0.05126946),
    float3(0.00000000, 0.35153260, 0.57758044),
    float3(0.64447968, 0.05126946, 0.05126946),
    float3(0.35153260, 0.14126329, 0.07036010),
    float3(0.17144110, 0.12743768, 0.12743768),
    float3(0.00518152, 0.00913406, 0.01444384),
};

static const float3 MATRIAX8C_PALETTE_OKLAB[8] = {
    float3(0.94979472, -0.00766732, 0.02524943),
    float3(0.85242214, -0.00123564, 0.17421185),
    float3(0.72539039, -0.18233827, 0.12493428),
    float3(0.65561106, -0.08868566, -0.08518422),
    float3(0.58387974, 0.16609135, 0.07686988),
    float3(0.57248673, 0.05435908, 0.06279459),
    float3(0.51752455, 0.01832100, 0.00587880),
    float3(0.20502250, -0.00722610, -0.01865918),
};

static const uint BAYER_8[64] = {
     0, 32,  8, 40,  2, 34, 10, 42,
    48, 16, 56, 24, 50, 18, 58, 26,
    12, 44,  4, 36, 14, 46,  6, 38,
    60, 28, 52, 20, 62, 30, 54, 22,
     3, 35, 11, 43,  1, 33,  9, 41,
    51, 19, 59, 27, 49, 17, 57, 25,
    15, 47,  7, 39, 13, 45,  5, 37,
    63, 31, 55, 23, 61, 29, 53, 21,
};

// A deterministic best-candidate blue-noise rank tile. Four-by-four rotated,
// mirrored, and rank-shifted copies reconstruct a non-repeating 64x64 field
// without an additional texture binding.
static const uint BLUE_NOISE_16_PACKED[64] = {
    0x53CAB34E, 0x83EB35F7, 0x90046A8D, 0x1D8719F3, 0xA58B3169, 0xB66B5C17, 0x9CB99A20, 0xD94FE72F,
    0xA213E6FC, 0xDC0AFA6E, 0x49CEB144, 0x07C62C7E, 0xC8F934F2, 0xF8988233, 0x6F0B5723, 0x7D408E32,
    0x62485E68, 0xEEA71FBD, 0x29AA2E7C, 0x47B812BB, 0x02AB7218, 0x107BDEFE, 0xE3E4D0C7, 0xAE3EB593,
    0xC1DD3A7F, 0xF64B7143, 0x9900BCA1, 0x55DFEF2A, 0xCD1CDA27, 0xB09B2BD5, 0x2DF0771B, 0xAF0889B7,
    0x50D192D4, 0x4DBA8474, 0xA32456DB, 0xF4FFAC16, 0xE8BE05EA, 0x6706FB42, 0x46C03CE0, 0x2281F573,
    0x1152F139, 0x9FD259D6, 0x9109CB25, 0x5F750D88, 0xA63DFDC4, 0x86ED1E95, 0x38E1454C, 0x1A9779A4,
    0x6CE90CC3, 0x37C2D830, 0x664A8CA8, 0xA0A99636, 0x218A65C9, 0x635D9DE5, 0x1458640F, 0xAD03E2CC,
    0x946DEC15, 0x8FB201D7, 0x7A803B61, 0x76CF41BF, 0x5B0E51C5, 0x26B45A3F, 0x7885D370, 0x60549E28,
};

float3 linear_to_oklab(float3 color) {
    float l = 0.4122214708 * color.r + 0.5363325363 * color.g + 0.0514459929 * color.b;
    float m = 0.2119034982 * color.r + 0.6806995451 * color.g + 0.1073969566 * color.b;
    float s = 0.0883024619 * color.r + 0.2817188376 * color.g + 0.6299787005 * color.b;
    float3 root = pow(max(float3(l, m, s), 0.0), 1.0 / 3.0);
    return float3(
        0.2104542553 * root.x + 0.7936177850 * root.y - 0.0040720468 * root.z,
        1.9779984951 * root.x - 2.4285922050 * root.y + 0.4505937099 * root.z,
        0.0259040371 * root.x + 0.7827717662 * root.y - 0.8086757660 * root.z
    );
}

float3 palette_linear(int mode, int index) {
    return mode == 3 ? MATRIAX8C_PALETTE_LINEAR[index] : ADRIATIC_PALETTE_LINEAR[index];
}

float3 palette_oklab(int mode, int index) {
    return mode == 3 ? MATRIAX8C_PALETTE_OKLAB[index] : ADRIATIC_PALETTE_OKLAB[index];
}

uint blue_noise_rank(int2 pixel) {
    uint x = uint(pixel.x) & 63;
    uint y = uint(pixel.y) & 63;
    uint tile_x = x >> 4;
    uint tile_y = y >> 4;
    uint tile = tile_y * 4 + tile_x;
    uint local_x = x & 15;
    uint local_y = y & 15;
    if ((tile & 1) != 0) local_x = 15 - local_x;
    if ((tile & 2) != 0) local_y = 15 - local_y;
    if ((tile & 4) != 0) {
        uint swap = local_x;
        local_x = local_y;
        local_y = swap;
    }
    uint index = local_y * 16 + local_x;
    uint packed = BLUE_NOISE_16_PACKED[index >> 2];
    uint rank = (packed >> ((index & 3) * 8)) & 255;
    return (rank + tile * 53) & 255;
}

float dither_threshold(int mode, int2 pixel) {
    if (mode == 1) {
        uint index = (uint(pixel.y) & 7) * 8 + (uint(pixel.x) & 7);
        return (float(BAYER_8[index]) + 0.5) / 64.0;
    }
    if (mode == 2 || mode == 3) return (float(blue_noise_rank(pixel)) + 0.5) / 256.0;
    uint index = (uint(pixel.y) & 7) * 8 + (uint(pixel.x) & 7);
    return (float(BAYER_8[index]) + 0.5) / 64.0;
}

[shader("vertex")]
PostOutput post_vertex(uint vertex_id : SV_VertexID) {
    PostOutput output;
    float2 position = vertex_id == 0 ? float2(-1, -1) : vertex_id == 1 ? float2(3, -1) : float2(-1, 3);
    output.position = float4(position, 0, 1);
    output.uv = position * .5 + .5;
    return output;
}

[shader("fragment")]
float4 post_fragment(PostOutput input) : SV_Target {
    // Both the HDR intermediate and the world scene sample as linear values.
    float4 source = ui_texture.Sample(ui_sampler, input.uv);
    float exposure = max(push.hatch_tone.x, .001);
    float sun_glare = saturate(push.hatch_tone.y);
    source.rgb *= exposure;
    // Looking into the Sun lowers retinal/camera exposure while forward
    // scattering lifts the black floor slightly. Keep this restrained and
    // world-only; UI is composited after this pass and remains fully legible.
    float3 warm_veil = float3(.62, .39, .19);
    source.rgb = lerp(source.rgb, warm_veil, sun_glare * .075);
    int mode = int(round(push.texture_hatch.x));
    // The world pass preserves alpha as a cheap classification channel: sky is
    // alpha-zero, while world geometry is opaque. Keep the smooth sky gradient
    // out of palette quantization; dithering remains active for the world.
    if (mode <= 0 || source.a < .5) return source;

    float3 target = linear_to_oklab(max(source.rgb, 0.0));
    int palette_count = mode == 3 ? 8 : 16;
    int closest = 0;
    float closest_error = 1e9;
    [unroll]
    for (int index = 0; index < 16; ++index) {
        if (index >= palette_count) continue;
        float3 delta = target - palette_oklab(mode, index);
        float error = dot(delta, delta);
        if (error < closest_error) {
            closest_error = error;
            closest = index;
        }
    }

    int partner = closest;
    float partner_weight = 0.0;
    float segment_error = closest_error;
    [unroll]
    for (int index = 0; index < 16; ++index) {
        if (index == closest || index >= palette_count) continue;
        float3 start = palette_oklab(mode, closest);
        float3 segment = palette_oklab(mode, index) - start;
        float weight = saturate(dot(target - start, segment) / max(dot(segment, segment), 1e-6));
        float3 reconstruction = start + segment * weight;
        float3 residual = target - reconstruction;
        float error = dot(residual, residual);
        if (error < segment_error) {
            segment_error = error;
            partner = index;
            partner_weight = weight;
        }
    }

    float2 viewport_origin = (push.viewport.xy - push.viewport.zw) * 0.5;
    int2 pixel = int2(floor(input.position.xy - viewport_origin));
    pixel += int2(round(push.texture_hatch.yz));
    float threshold = dither_threshold(mode, pixel);
    int palette_index = threshold < partner_weight ? partner : closest;
    return float4(palette_linear(mode, palette_index), source.a);
}
