struct Push {
    float4 camera_position;
    float4 camera_right;
    float4 camera_up;
    float4 camera_forward;
    float4 projection;
    float4 fog_color;
    float4 water;
    float4 sun;
};
[[vk::push_constant]] ConstantBuffer<Push> push;

[[vk::binding(0, 0)]] Texture2D<float4> foliage_atlas;
[[vk::binding(1, 0)]] SamplerState foliage_sampler;

struct VertexInput {
    float3 position : POSITION;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

struct VertexOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
    float depth : TEXCOORD1;
};

// The atlas uses an sRGB image and is decoded by the sampler. Vertex tints and
// fog colors are CPU-authored sRGB palette values, so decode only those.
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
    float3 world_position = input.position;
    float2 wind = push.water.zw;
    float wind_speed = length(wind);
    float2 wind_direction = wind_speed > .001 ? wind / wind_speed : float2(1, 0);
    float2 wind_across = float2(-wind_direction.y, wind_direction.x);
    // Match the solid foliage shader's broad phase exactly so a card's branch
    // base travels with its parent crown instead of sliding across the mesh.
    // Cards sit on upper shoulders, represented by a stable .88 crown weight;
    // only the fine crosswind flutter below remains independently animated.
    float phase = dot(input.position.xz, float2(.021, -.016)) +
                  push.water.x * (.34 + wind_speed * .012);
    float broad_sway = sin(phase) + sin(phase * .47 + 1.9) * .34;
    float amplitude = lerp(.20, 1.18, saturate(wind_speed / 14.0 + push.water.y * .24));

    // Atlas cells are four-by-four. Their top vertices have a local v near
    // zero, allowing the painted branch tips to flutter while their bases stay
    // visually attached to the solid canopy.
    float2 tile_uv = frac(input.uv * 4.0);
    float tip_weight = smoothstep(.34, .96, 1.0 - tile_uv.y);
    float flutter = sin(push.water.x * (1.18 + wind_speed * .028) +
                        dot(input.position.xz, float2(.071, .043)) +
                        tile_uv.x * 2.7);
    world_position.xz += wind_direction * broad_sway * amplitude * .88;
    world_position.y += sin(phase * .73 - .8) * amplitude * .075 * .88;
    world_position.xz += wind_across * flutter * amplitude * .24 * tip_weight;
    world_position.y += flutter * amplitude * .11 * tip_weight;

    float3 view = world_position - push.camera_position.xyz;
    float depth = dot(view, push.camera_forward.xyz);
    float x = dot(view, push.camera_right.xyz) * push.projection.x / push.projection.y;
    float y = dot(view, push.camera_up.xyz) * push.projection.x;
    float near_plane = push.camera_position.w;
    float far_plane = push.camera_right.w;
    float clip_z = far_plane / (far_plane - near_plane) * depth -
                   far_plane * near_plane / (far_plane - near_plane);

    VertexOutput output;
    output.position = float4(x, -y, clip_z, depth);
    output.uv = input.uv;
    output.color = float4(srgb_to_linear(input.color.rgb), input.color.a);
    output.depth = depth;
    return output;
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    float4 texel = foliage_atlas.Sample(foliage_sampler, input.uv);
    // Cutout leaves remain crisp and depth-stable around overlapping blobs.
    // The soft outermost antialiasing survives through regular alpha blending.
    if (texel.a < .16) discard;
    float fog = saturate((input.depth - push.projection.z) /
                         max(push.projection.w - push.projection.z, .001));
    // Use the painted atlas as a value-and-alpha mask. Its original yellow
    // highlights and teal shadows become luminance, then inherit the exact
    // upper-canopy tint supplied by the parent foliage blob.
    float luminance = dot(texel.rgb, float3(.2126, .7152, .0722));
    // These side-view branch fragments should merge into the canopy value
    // mass. Keeping the top value below the former rosette sprites prevents
    // them from reading as pale flowers pasted onto the surface.
    float painted_value = lerp(.54, 1.38, smoothstep(.06, .94, luminance));
    float3 color = input.color.rgb * painted_value;

    // Leaf-sprig tips catch the same warm sunlight as the crown crests. A
    // restrained, daylight-gated warm lift on the upper (tip) leaves keeps the
    // cards in the canopy's hand-painted temperature story instead of reading
    // as flat tinted cutouts, while the base leaves hold the cooler body value.
    // Atlas cells are four-by-four, so the tile-local v isolates the tips.
    float2 tile_uv = frac(input.uv * 4.0);
    float tip = smoothstep(.30, .95, 1.0 - tile_uv.y) * smoothstep(.34, .80, luminance);
    float daylight = saturate(push.sun.w);
    color *= 1.0 + tip * daylight * .14;
    color += float3(.055, .043, .010) * tip * daylight;

    return float4(lerp(color, srgb_to_linear(push.fog_color.rgb), fog), texel.a * input.color.a);
}
