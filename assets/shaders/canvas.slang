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
    return push.texture_hatch.x > .5 ? input.color * texel : input.color;
}

struct PostOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

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
    // Both the HDR intermediate and an sRGB fixed-resolution scene sample as
    // linear values. Return that value unchanged and let the swapchain encode.
    return ui_texture.Sample(ui_sampler, input.uv);
}
