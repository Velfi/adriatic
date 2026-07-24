struct Push {
    float4 camera_position;
    float4 camera_right;
    float4 camera_up;
    float4 camera_forward;
    float4 projection;
    float4 fog_color;
    float4 water; // time, sea state, wind x, wind z
    float4 sun;   // direction xyz, daylight
};
[[vk::push_constant]] ConstantBuffer<Push> push;

struct VertexInput {
    float3 position : POSITION;
    float4 color : COLOR0;
    float kind : TEXCOORD0;
};

struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR0;
    float depth : TEXCOORD0;
    float3 world_position : TEXCOORD1;
    float kind : TEXCOORD2;
};

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    VertexOutput output;
    float3 view = input.position - push.camera_position.xyz;
    float depth = dot(view, push.camera_forward.xyz);
    float x = dot(view, push.camera_right.xyz) * push.projection.x / push.projection.y;
    float y = dot(view, push.camera_up.xyz) * push.projection.x;
    float near_plane = push.camera_position.w;
    float far_plane = push.camera_right.w;
    float clip_z = far_plane / (far_plane - near_plane) * depth -
                   far_plane * near_plane / (far_plane - near_plane);
    output.position = float4(x, -y, clip_z, depth);
    output.color = input.color;
    output.depth = depth;
    output.world_position = input.position;
    output.kind = input.kind;
    return output;
}

float hash12(float2 p) {
    float3 p3 = frac(float3(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float value_noise(float2 p) {
    float2 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(
        lerp(hash12(i), hash12(i + float2(1,0)), f.x),
        lerp(hash12(i + float2(0,1)), hash12(i + float2(1,1)), f.x),
        f.y
    );
}

float2 rotate2(float2 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

float3 shade_water(VertexOutput input) {
    float2 p = input.world_position.xz;
    float time = push.water.x;
    float sea_state = saturate(.28 + push.water.y * .64);
    float2 wind = push.water.zw;
    float wind_length = max(length(wind), .001);
    float2 axis = wind / wind_length;
    float2 across = float2(-axis.y, axis.x);

    // Adriatic's authored islands replace ArchipelagoGame's packed depth map.
    float island_radius = 280.0;
    float coast_a = length(p - float2(1300, 1300)) - island_radius;
    float coast_b = length(p + float2(1300, 1300)) - island_radius;
    float coast_distance = max(min(coast_a, coast_b), 0.0);
    float shallow = 1.0 - smoothstep(12.0, 92.0, coast_distance);
    float deep = smoothstep(30.0, 280.0, coast_distance);

    float3 shallow_color = float3(.10, .60, .60);
    float3 middle_color = float3(.025, .43, .52);
    float3 deep_color = float3(.016, .20, .31);
    float3 foam_color = float3(.78, .84, .80);
    float3 glint_color = float3(1.0, .88, .63);
    float3 color = lerp(shallow_color, middle_color, smoothstep(.08, .72, deep));
    color = lerp(color, deep_color, deep * .68);

    // Broad, warped wind-aligned pigment fields give the surface painted value
    // masses without exposing a rectangular procedural lattice.
    float2 broad_p = rotate2(p, .47) / 520.0;
    broad_p += float2(sin(broad_p.y * 1.43), sin(broad_p.x * 1.17 + .8)) * .24;
    float broad = value_noise(broad_p) - .5;
    float warp = sin(dot(p, rotate2(axis, .72)) * .0027 - time * .022) +
                 sin(dot(p, rotate2(axis, -.65)) * .0013 + time * .014) * .62;
    float lane = .5 + .5 * sin(dot(p, axis) * .013 +
                               sin(dot(p, across) * .0021 + warp) * 1.55 -
                               time * .095);
    color *= lerp(.92, 1.08, saturate(broad + lane * .36 + .38));
    color = lerp(color, middle_color * 1.10, smoothstep(.76, .91, lane) * .10);

    // Analytic wave slopes support a restrained Fresnel tint and sun glitter.
    float phase_a = dot(p, axis) * .043 - time * (.42 + sea_state * .24);
    float2 diagonal = normalize(axis + across * .55);
    float phase_b = dot(p, diagonal) * .091 - time * (.73 + sea_state * .31);
    float2 slope = axis * cos(phase_a) * (.035 + sea_state * .055) +
                   diagonal * cos(phase_b) * (.018 + sea_state * .032);
    float3 normal = normalize(float3(-slope.x, 1, -slope.y));
    float3 view = normalize(push.camera_position.xyz - input.world_position);
    float facing = saturate(dot(normal, view));
    float fresnel = .03 + .38 * pow(1.0 - facing, 4.0);
    float3 sky_tint = lerp(float3(.055, .16, .24), float3(.20, .52, .62), push.sun.w);
    color = lerp(color, sky_tint, fresnel * .31);

    float3 sun_dir = normalize(push.sun.xyz);
    float glint_core = max(dot(reflect(-sun_dir, normal), view), 0.0);
    float dry_glint = smoothstep(.67, .88, value_noise(p / 13.0 + time * float2(.03, -.01)));
    float glint = pow(glint_core, lerp(22.0, 10.0, sea_state)) * dry_glint * push.sun.w;
    color = lerp(color, glint_color, glint * .42);

    // A narrow, broken aerated edge keeps foam attached to the coastline.
    float foam_band = 1.0 - smoothstep(5.0, 31.0, coast_distance);
    float foam_breakup = value_noise(float2(dot(p, across) * .075, dot(p, axis) * .031) +
                                      float2(time * .028, 0));
    float foam = foam_band * lerp(.28, 1.0, smoothstep(.38, .76, foam_breakup));
    color = lerp(color, foam_color, foam * lerp(.38, .68, sea_state));

    return saturate(color);
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    float fog = saturate((input.depth - push.projection.z) /
                         max(push.projection.w - push.projection.z, .001));
    float3 base = input.kind > .5 ? shade_water(input) : input.color.rgb;
    return float4(lerp(base, push.fog_color.rgb, fog), input.color.a);
}
