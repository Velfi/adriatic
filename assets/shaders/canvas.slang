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
[[vk::binding(2, 0)]] Texture2D<float> world_depth;
[[vk::binding(3, 0)]] SamplerState world_depth_sampler;
[[vk::binding(4, 0)]] Texture2D<float4> post_aux_pattern;
[[vk::binding(5, 0)]] SamplerState post_aux_pattern_sampler;
[[vk::binding(6, 0)]] Texture2D<float4> post_aux_lut;
[[vk::binding(7, 0)]] SamplerState post_aux_lut_sampler;
[[vk::binding(8, 0)]] Texture2D<float4> post_original_scene;
[[vk::binding(9, 0)]] SamplerState post_original_scene_sampler;

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

float3 oklab_to_linear(float3 color) {
    float l_root = color.x + 0.3963377774 * color.y + 0.2158037573 * color.z;
    float m_root = color.x - 0.1055613458 * color.y - 0.0638541728 * color.z;
    float s_root = color.x - 0.0894841775 * color.y - 1.2914855480 * color.z;
    float l = l_root * l_root * l_root;
    float m = m_root * m_root * m_root;
    float s = s_root * s_root * s_root;
    return float3(
         4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
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

// Photo-mode painting filters are clean-room implementations inspired by the
// effect families in jhaakma/joy-of-painting. They intentionally share one
// bounded, texture-free pass so every control remains cheap and deterministic.
float photo_luma(float3 color) {
    return dot(color, float3(.2126, .7152, .0722));
}

float photo_hash(float2 pixel) {
    return frac(sin(dot(pixel, float2(12.9898, 78.233))) * 43758.5453);
}

float3 photo_sample(float2 uv, float2 offset, float2 texel, float exposure) {
    return ui_texture.Sample(ui_sampler, saturate(uv + offset * texel)).rgb * exposure;
}

float3 photo_rgb_to_hsl(float3 color) {
    float maximum = max(color.r, max(color.g, color.b));
    float minimum = min(color.r, min(color.g, color.b));
    float chroma = maximum - minimum;
    float hue = 0.0;
    if (chroma > 1e-5) {
        if (maximum == color.r) hue = frac((color.g - color.b) / chroma / 6.0);
        else if (maximum == color.g) hue = ((color.b - color.r) / chroma + 2.0) / 6.0;
        else hue = ((color.r - color.g) / chroma + 4.0) / 6.0;
    }
    float lightness = (maximum + minimum) * .5;
    float saturation = chroma / max(1.0 - abs(2.0 * lightness - 1.0), 1e-5);
    return float3(hue, saturation, lightness);
}

float3 photo_hsl_to_rgb(float3 hsl) {
    float chroma = (1.0 - abs(2.0 * hsl.z - 1.0)) * hsl.y;
    float sector = hsl.x * 6.0;
    float x = chroma * (1.0 - abs(fmod(sector, 2.0) - 1.0));
    float3 rgb = sector < 1.0 ? float3(chroma, x, 0) : sector < 2.0 ? float3(x, chroma, 0) : sector < 3.0 ? float3(0, chroma, x) : sector < 4.0 ? float3(0, x, chroma) : sector < 5.0 ? float3(x, 0, chroma) : float3(chroma, 0, x);
    return rgb + (hsl.z - chroma * .5);
}

float3 photo_kuwahara(float2 uv, float2 texel, float exposure, int radius) {
    float3 best_mean = ui_texture.Sample(ui_sampler, uv).rgb * exposure;
    float best_variance = 1e9;
    [unroll]
    for (int quadrant = 0; quadrant < 4; ++quadrant) {
        float3 sum = 0;
        float sum_luma = 0;
        float sum_luma_squared = 0;
        float count = 0;
        [unroll]
        for (int y = 0; y <= 5; ++y) {
            [unroll]
            for (int x = 0; x <= 5; ++x) {
                if (x > radius || y > radius) continue;
                float2 sign_offset = float2((quadrant & 1) == 0 ? -x : x, (quadrant & 2) == 0 ? -y : y);
                float3 sample_color = ui_texture.Sample(ui_sampler, saturate(uv + sign_offset * texel)).rgb * exposure;
                float sample_luma = photo_luma(sample_color);
                sum += sample_color;
                sum_luma += sample_luma;
                sum_luma_squared += sample_luma * sample_luma;
                count += 1;
            }
        }
        float3 mean = sum / max(count, 1.0);
        float mean_luma = sum_luma / max(count, 1.0);
        float variance = sum_luma_squared / max(count, 1.0) - mean_luma * mean_luma;
        if (variance < best_variance) {
            best_variance = variance;
            best_mean = mean;
        }
    }
    return best_mean;
}

float photo_media(int tile, float2 uv, float scale) {
    int column = tile % 3;
    int row = tile / 3;
    float2 local = frac(uv * scale);
    float2 atlas_uv = float2((float(column) + local.x) / 3.0,
                             (float(row) + local.y) / 3.0 * .8333333);
    return post_aux_pattern.Sample(post_aux_pattern_sampler, atlas_uv).r;
}

float3 photo_lut_slice(int grade, float3 color, int blue_slice) {
    int grade_x = grade % 3;
    int grade_y = grade / 3;
    int slice_x = blue_slice % 8;
    int slice_y = blue_slice / 8;
    float2 cube_uv = (float2(slice_x, slice_y) * 8.0 + saturate(color.rg) * 7.0 + .5) / 64.0;
    float2 atlas_uv = (float2(grade_x, grade_y) + cube_uv) / 3.0;
    return post_aux_lut.Sample(post_aux_lut_sampler, atlas_uv).rgb;
}

float3 photo_lut_grade(int grade, float3 color) {
    float blue = saturate(color.b) * 63.0;
    int lower = int(floor(blue));
    int upper = min(lower + 1, 63);
    return lerp(photo_lut_slice(grade, color, lower), photo_lut_slice(grade, color, upper), frac(blue));
}

float3 photo_adjust_oklab(float3 linear_color, float saturation, float contrast, float brightness) {
    float3 color = linear_to_oklab(max(linear_color, 0.0));
    color.x = (color.x - .5) * contrast + .5 + brightness;
    color.yz *= saturation;
    return color;
}

float3 photo_quantize_oklab(float3 color, float levels) {
    float steps = max(levels - 1.0, 1.0);
    // Oklab lightness is [0, 1]. Its opponent axes cover the visible sRGB
    // gamut comfortably within [-.4, .4]. Quantize all three perceptual axes.
    float3 normalized = float3(
        saturate(color.x),
        saturate(color.y / .8 + .5),
        saturate(color.z / .8 + .5)
    );
    normalized = floor(normalized * steps + .5) / steps;
    return float3(normalized.x, (normalized.y - .5) * .8, (normalized.z - .5) * .8);
}

float3 photo_quantization_error_oklab(
    float3 linear_color,
    float levels,
    float saturation,
    float contrast,
    float brightness
) {
    float3 adjusted = photo_adjust_oklab(linear_color, saturation, contrast, brightness);
    return adjusted - photo_quantize_oklab(adjusted, levels);
}

float3 photo_filter(float3 source, float2 uv, float2 texel, float exposure, int mode) {
    float intensity = saturate(push.hatch_offset.y);
    float radius = saturate(push.hatch_offset.z);
    float detail = saturate(push.hatch_offset.w);
    float saturation = max(push.hatch_angles.x, 0.0);
    float contrast = max(push.hatch_angles.y, 0.0);
    float brightness = push.hatch_angles.z;
    float grain = saturate(push.hatch_angles.w);
    float vignette = saturate(push.hatch_levels.x);
    float distortion = saturate(push.hatch_levels.y);
    float2 pixel = uv / max(texel, 1e-6);
    float noise = photo_hash(floor(pixel * (1.0 - radius * .75))) - .5;
    float perlin = photo_media(0, uv, lerp(1.5, 6.0, radius)) - .5;
    float animation_time = push.hatch_shape.w;
    float animated_x = perlin + sin(uv.y * 17.0 + animation_time * 1.7) * .18;
    float animated_y = (photo_media(0, uv.yx + animation_time * .007, lerp(1.5, 6.0, radius)) - .5) + cos(uv.x * 19.0 - animation_time * 1.3) * .18;
    float2 warped_uv = saturate(uv + float2(animated_x, animated_y) * distortion * texel * 12.0);
    float spread = 1.0 + radius * 7.0;
    float3 center = photo_sample(warped_uv, float2(0, 0), texel, exposure);
    float3 north = photo_sample(warped_uv, float2(0, -spread), texel, exposure);
    float3 south = photo_sample(warped_uv, float2(0, spread), texel, exposure);
    float3 west = photo_sample(warped_uv, float2(-spread, 0), texel, exposure);
    float3 east = photo_sample(warped_uv, float2(spread, 0), texel, exposure);
    float3 blur = (center * 4.0 + north + south + west + east) / 8.0;
    float3 result = center;
    float3 original_scene = post_original_scene.Sample(post_original_scene_sampler, uv).rgb * exposure;
    float luma = photo_luma(center);
    float depth = world_depth.Sample(world_depth_sampler, uv);
    float near_clip = max(push.hatch_tone.z, .001);
    float far_clip = max(push.hatch_tone.w, near_clip + .01);
    float view_depth = near_clip * far_clip / max(far_clip - depth * (far_clip - near_clip), .001);
    float depth_unit = saturate(log(max(view_depth / near_clip, 1.0)) / log(far_clip / near_clip));

    if (mode == 1) { // Oil: edge-preserving blocks with warm pigment response.
        float3 painterly = blur;
        float pigment = smoothstep(.05, .95, photo_luma(painterly));
        painterly *= lerp(float3(.94, .97, 1.04), float3(1.07, 1.01, .91), pigment * detail);
        result = lerp(painterly, center, detail * .35);
    } else if (mode == 2) { // Watercolor: translucent wash and pooled edges.
        float edge = length(center - blur);
        float3 wash = lerp(blur, center, .22 + detail * .35);
        wash = lerp(photo_luma(wash).xxx, wash, .75 + saturation * .25);
        result = wash * (1.04 - saturate(edge * 3.0) * .16) + perlin * grain * .06;
    } else if (mode == 3) { // Pastel: lifted pigment over fine paper grain.
        result = lerp(blur, center, .55 + detail * .35);
        result = pow(max(result, 0.0), .82);
        result += (photo_media(5, uv, 2.0 + radius * 5.0) - .5) * (.05 + grain * .12);
        result = lerp(photo_luma(result).xxx, result, 1.12);
    } else if (mode == 4) { // Charcoal paper division.
        float edge = saturate(length(center - blur) * (5.0 + detail * 12.0));
        float paper = (photo_media(2, uv, 1.0 + radius * 4.0) - .5) * grain * .5;
        result = saturate((center + .1) / max(.35 - paper + edge * .2, .08));
    } else if (mode == 5) { // Ink brightness/contrast treatment.
        result = center * contrast + brightness;
    } else if (mode == 6) { // Cross-hatch.
        float scale = lerp(3.0, 11.0, radius);
        float hatch_level = photo_media(3, uv, max(1.0, 13.0 / scale));
        float ink = smoothstep(luma - .18, luma + .18, hatch_level);
        result = lerp(center, center * ink, .45 + detail * .55);
    } else if (mode == 7) { // Kuwahara.
        result = photo_kuwahara(warped_uv, texel, exposure, 1 + int(round(radius * 4.0)));
    } else if (mode == 8) { // Hue/luminance quantization.
        float3 hsl = photo_rgb_to_hsl(saturate(center));
        float hue_levels = floor(4.0 + detail * 20.0);
        float saturation_levels = floor(2.0 + saturation * 6.0);
        float lightness_levels = floor(3.0 + detail * 13.0);
        hsl = floor(hsl * float3(hue_levels, saturation_levels, lightness_levels) + .5) / float3(hue_levels, saturation_levels, lightness_levels);
        result = photo_hsl_to_rgb(hsl);
    } else if (mode == 9) { // Black and white threshold.
        result = step(lerp(.25, .75, radius), luma).xxx;
    } else if (mode == 10) { // Greyscale.
        result = luma.xxx;
    } else if (mode == 11) { // Sharpen.
        result = center + (center - blur) * (1.0 + detail * 3.0);
    } else if (mode == 12) { // Mottled canvas.
        float mottle = photo_media(6, uv, 1.0 + radius * 4.0);
        result = center * lerp(.76, 1.18, mottle * (.35 + grain * .65));
    } else if (mode == 13) { // Distortion.
        result = center;
    } else if (mode == 14) { // Vignette (also available as a shared control).
        result = center;
        vignette = max(vignette, intensity);
    } else if (mode == 15) { // Adjuster: color correction with hue rotation.
        float angle = radius * 6.2831853;
        float3 axis = normalize(float3(1, 1, 1));
        result = center * cos(angle) + cross(axis, center) * sin(angle) + axis * dot(axis, center) * (1 - cos(angle));
    } else if (mode == 16) { // Mixed media composite.
        float edge = saturate(length(center - blur) * (7.0 + detail * 12.0));
        float hatch = step(.52, frac((pixel.x + pixel.y) / lerp(4.0, 12.0, radius)));
        float3 wash = lerp(blur, center, .3);
        result = wash * lerp(1.0, hatch, edge * .7) + noise * grain * .06;
    } else if (mode == 17) { // Depth of field.
        float focus = radius;
        float coc = saturate(abs(depth_unit - focus) / max(detail * .25, .005));
        result = lerp(original_scene, center, coc);
    } else if (mode == 18) { // Color fog.
        float fog = smoothstep(radius, min(radius + detail, 1.0), depth_unit);
        float3 fog_color = lerp(float3(.30, .42, .55), float3(.88, .72, .52), saturation * .5);
        result = lerp(center, fog_color, fog * intensity);
    } else if (mode == 19) { // Monochrome fog.
        float fog = smoothstep(radius, min(radius + detail, 1.0), depth_unit);
        float fog_value = brightness * .5 + .5;
        result = lerp(center, fog_value.xxx, fog * intensity);
    } else if (mode == 20) { // Trilinearly sampled 8x8x8 LUT atlas.
        int grade = int(floor(radius * 8.999));
        result = photo_lut_grade(grade, saturate(center));
    } else if (mode == 21) { // Depth and color outline.
        float depth_n = world_depth.Sample(world_depth_sampler, saturate(uv + float2(0, -spread) * texel));
        float depth_s = world_depth.Sample(world_depth_sampler, saturate(uv + float2(0, spread) * texel));
        float depth_w = world_depth.Sample(world_depth_sampler, saturate(uv + float2(-spread, 0) * texel));
        float depth_e = world_depth.Sample(world_depth_sampler, saturate(uv + float2(spread, 0) * texel));
        float depth_edge = abs(depth_e - depth_w) + abs(depth_s - depth_n);
        float color_edge = length(center - blur);
        float line = saturate((depth_edge * 120.0 + color_edge * 5.0 - detail * .25) * 4.0);
        result = center * (1.0 - line * contrast);
    } else if (mode == 22) { // Watercolor splash breakup.
        float cell = photo_media(7, uv, 1.0 + radius * 3.0);
        float splash = smoothstep(.28, .72, cell + (luma - .5) * detail);
        result = lerp(blur, center, splash) + (cell - .5) * grain * .12;
    } else if (mode == 23) { // Canvas window.
        float2 centered = abs(uv * 2.0 - 1.0);
        float aspect = lerp(.55, 1.45, detail);
        float frame = max(centered.x * aspect, centered.y / aspect);
        float mask = 1.0 - smoothstep(radius, min(radius + .02 + grain * .08, 1.0), frame);
        result = center * mask;
    } else if (mode == 24) { // Floyd-Steinberg error diffusion.
        float levels = floor(2.0 + radius * 14.0);
        float3 dither_center = photo_sample(uv, float2(0, 0), texel, exposure);
        float3 adjusted = photo_adjust_oklab(dither_center, saturation, contrast, brightness);

        // Fragment invocations cannot carry mutable error between pixels, so
        // reconstruct the incoming error from the four already-visited source
        // neighbours. This preserves the Floyd-Steinberg 7/3/5/1 kernel while
        // remaining deterministic and parallel on the GPU.
        bool reverse = distortion > .5 && (int(floor(pixel.y)) & 1) != 0;
        float direction = reverse ? 1.0 : -1.0;
        float3 side = photo_sample(uv, float2(direction, 0), texel, exposure);
        float3 upper_far = photo_sample(uv, float2(-direction, -1), texel, exposure);
        float3 upper = photo_sample(uv, float2(0, -1), texel, exposure);
        float3 upper_near = photo_sample(uv, float2(direction, -1), texel, exposure);
        float3 incoming =
            photo_quantization_error_oklab(side, levels, saturation, contrast, brightness) * (7.0 / 16.0) +
            photo_quantization_error_oklab(upper_far, levels, saturation, contrast, brightness) * (3.0 / 16.0) +
            photo_quantization_error_oklab(upper, levels, saturation, contrast, brightness) * (5.0 / 16.0) +
            photo_quantization_error_oklab(upper_near, levels, saturation, contrast, brightness) * (1.0 / 16.0);
        adjusted += incoming * detail;
        adjusted.x += noise * grain / max(levels - 1.0, 1.0);
        result = max(oklab_to_linear(photo_quantize_oklab(adjusted, levels)), 0.0);

        float2 centered_uv = uv * 2.0 - 1.0;
        float vignette_mask = smoothstep(1.15, .25, dot(centered_uv, centered_uv));
        result *= lerp(1.0, vignette_mask, vignette);
        return lerp(source, max(result, 0.0), intensity);
    }

    float adjusted_luma = photo_luma(result);
    result = lerp(adjusted_luma.xxx, result, saturation);
    result = (result - .5) * contrast + .5 + brightness;
    if (mode != 3 && mode != 4 && mode != 12) result += noise * grain * .025;
    float2 centered_uv = uv * 2.0 - 1.0;
    float vignette_mask = smoothstep(1.15, .25, dot(centered_uv, centered_uv));
    result *= lerp(1.0, vignette_mask, vignette);
    if (mode == 17) return lerp(original_scene, max(result, 0.0), intensity);
    return lerp(source, max(result, 0.0), intensity);
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
    int photo_mode = int(round(push.hatch_offset.x));
    if (photo_mode > 0) {
        float2 texel_size = 1.0 / max(push.viewport.zw, float2(1.0, 1.0));
        int pass_index = int(round(push.hatch_levels.z));
        int pass_count = max(int(round(push.hatch_levels.w)), 1);
        if (pass_count > 1 && pass_index < pass_count - 1) {
            float spread = .75 + saturate(push.hatch_offset.z) * (photo_mode == 17 ? 6.0 : 2.0);
            float2 axis = pass_index == 0 ? float2(spread, 0) : float2(0, spread);
            float3 a = ui_texture.Sample(ui_sampler, saturate(input.uv - axis * texel_size)).rgb;
            float3 b = source.rgb;
            float3 c = ui_texture.Sample(ui_sampler, saturate(input.uv + axis * texel_size)).rgb;
            return float4((a + b * 2.0 + c) * .25, source.a);
        }
        source.rgb *= exposure;
        float3 warm_veil = float3(.62, .39, .19);
        source.rgb = lerp(source.rgb, warm_veil, sun_glare * .075);
        source.rgb = photo_filter(source.rgb, input.uv, texel_size, exposure, photo_mode);
        return source;
    }
    source.rgb *= exposure;
    // Looking into the Sun lowers retinal/camera exposure while forward
    // scattering lifts the black floor slightly. Keep this restrained and
    // world-only; UI is composited after this pass and remains fully legible.
    float3 warm_veil = float3(.62, .39, .19);
    source.rgb = lerp(source.rgb, warm_veil, sun_glare * .075);
    int mode = int(round(push.texture_hatch.x));
    int visual_style = int(round(push.texture_hatch.w));
    // The world pass preserves alpha as a cheap classification channel: sky is
    // alpha-zero, while world geometry is opaque. Keep the smooth sky gradient
    // out of palette quantization; dithering remains active for the world.
    if (visual_style != 1 || mode <= 0 || source.a < .5) return source;

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
