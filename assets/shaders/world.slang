struct Push {
    float4 camera_position;
    float4 camera_right;
    float4 camera_up;
    float4 camera_forward;
    float4 projection;
    float4 fog_color; // rgb horizon fog, a moonlight strength
    float4 water; // time, sea state, wind x, wind z
    float4 sun;   // direction xyz, daylight
};
[[vk::push_constant]] ConstantBuffer<Push> push;

[[vk::binding(0, 0)]] Texture2DArray<float4> vehicle_paint_atlas;
[[vk::binding(1, 0)]] SamplerState vehicle_paint_sampler;
[[vk::binding(2, 0)]] Texture2D<float4> soda_cap_logo;
[[vk::binding(3, 0)]] SamplerState soda_cap_logo_sampler;
[[vk::binding(4, 0)]] Texture2D<float4> architecture_material_atlas;
[[vk::binding(5, 0)]] SamplerState architecture_material_sampler;
[[vk::binding(6, 0)]] Texture2D<float4> business_sign_atlas;
[[vk::binding(7, 0)]] SamplerState business_sign_sampler;
[[vk::binding(8, 0)]] Texture2D<float4> material_lab_albedo;
[[vk::binding(9, 0)]] SamplerState material_lab_albedo_sampler;
[[vk::binding(10, 0)]] Texture2D<float4> material_lab_specular;
[[vk::binding(11, 0)]] SamplerState material_lab_specular_sampler;
[[vk::binding(12, 0)]] Texture2D<float4> material_lab_roughness;
[[vk::binding(13, 0)]] SamplerState material_lab_roughness_sampler;
[[vk::binding(14, 0)]] Texture2D<float4> material_lab_normal;
[[vk::binding(15, 0)]] SamplerState material_lab_normal_sampler;
[[vk::binding(16, 0)]] Texture2D<float4> marine_ecology_atlas;
[[vk::binding(17, 0)]] SamplerState marine_ecology_sampler;

struct DynamicShadowCascade {
    // Light-space basis vectors. The fourth components contain the snapped
    // anchor coordinates (right/up) and minimum light depth (forward).
    float4 right;
    float4 up;
    float4 forward;
    // coverage, inverse depth range, enabled strength, inverse resolution
    float4 params;
};
struct DynamicShadow {
    DynamicShadowCascade cascades[3];
    // Origin-distance limits for cascades 0..2, final shadow strength.
    float4 settings;
    float4 origin;
    float4 fog_bank_a[4];
    float4 fog_bank_b[4];
    float4 fog_bank_c[4];
    float4 fog_previous_a[4];
    float4 fog_previous_b[4];
    float4 fog_previous_c[4];
    float4 fog_settings;
};
struct DynamicShadowPush {
    uint cascade;
};
[[vk::push_constant]] ConstantBuffer<DynamicShadowPush> dynamic_shadow_push;
[[vk::binding(0, 1)]] ConstantBuffer<DynamicShadow> dynamic_shadow;
[[vk::binding(1, 1)]] Texture2D<float> dynamic_shadow_map_0;
[[vk::binding(2, 1)]] Texture2D<float> dynamic_shadow_map_1;
[[vk::binding(3, 1)]] Texture2D<float> dynamic_shadow_map_2;
[[vk::binding(4, 1)]] SamplerComparisonState dynamic_shadow_sampler;

struct VertexInput {
    float3 position : POSITION;
    float4 color : COLOR0;
    uint kind : TEXCOORD0;
    float3 normal : NORMAL0;
    float2 material : TEXCOORD1;
    float2 uv : TEXCOORD5;
};

struct InstanceVertexInput {
    float3 position : POSITION;
    float4 color : COLOR0;
    uint kind : TEXCOORD0;
    float3 normal : NORMAL0;
    float2 material : TEXCOORD1;
    float2 uv : TEXCOORD5;
    float4 basis_x_translation_x : TEXCOORD6;
    float4 basis_y_translation_y : TEXCOORD7;
    float4 basis_z_translation_z : TEXCOORD8;
    float4 instance_color : TEXCOORD9;
    float4 normal_override : TEXCOORD10;
};

struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR0;
    float depth : TEXCOORD0;
    float3 world_position : TEXCOORD1;
    nointerpolation uint kind : TEXCOORD2;
    float3 normal : TEXCOORD3;
    float2 material : TEXCOORD4;
    float2 uv : TEXCOORD5;
};

static const uint MATERIAL_UNSHADED = 0;
static const uint MATERIAL_WATER = 1;
static const uint MATERIAL_TERRAIN = 2;
static const uint MATERIAL_FOLIAGE = 3;
static const uint MATERIAL_ROAD = 4;
static const uint MATERIAL_BRDF = 5;
static const uint MATERIAL_EYE = 6;
static const uint MATERIAL_VEHICLE = 7;
static const uint MATERIAL_ACORN = 8;
static const uint MATERIAL_BOTTLE_CAP = 9;
static const uint MATERIAL_EMISSIVE = 10;
static const uint MATERIAL_EMISSIVE_POOL = 11;
static const uint MATERIAL_ARCHITECTURE = 12;
static const uint MATERIAL_GLASS = 13;
static const uint MATERIAL_EMISSIVE_HALO = 14;
static const uint MATERIAL_SAILOR_HAT = 15;
static const uint MATERIAL_SIGN = 16;
static const uint MATERIAL_LIGHTHOUSE_GLITTER = 17;
static const uint MATERIAL_LEAF = 18;
static const uint MATERIAL_PETAL = 19;
static const uint MATERIAL_FOUNTAIN_WATER = 20;
static const uint MATERIAL_CAR_PAINT = 21;
static const uint MATERIAL_MATERIAL_LAB = 22;
static const uint MATERIAL_SETTLEMENT = 23;
static const uint MATERIAL_FOG_SHELL = 24;
static const uint MATERIAL_ROCK = 25;
static const uint MATERIAL_BARK = 26;
static const uint MATERIAL_MARINE_WATER = 27;

float fog_bank_density(float3 p, float4 a, float4 b, float4 c) {
    float2 offset = p.xz - a.xy;
    float2 axis = normalize(b.xy + float2(.00001, 0));
    float2 local = float2(dot(offset, axis), dot(offset, float2(-axis.y, axis.x)));
    float radial = length(local / max(a.zw, float2(1, 1)));
    float horizontal = 1.0 - smoothstep(1.0 - clamp(c.x, .01, .95), 1.0, radial);
    float vertical = smoothstep(b.z, b.z + 28.0, p.y) *
        (1.0 - smoothstep(lerp(b.z, b.w, .62), b.w, p.y));
    return horizontal * vertical * c.y;
}

float local_fog_density(float3 p) {
    float density = 0.0;
    [unroll] for (uint i = 0; i < 4; ++i) {
        float old_density = fog_bank_density(p, dynamic_shadow.fog_previous_a[i], dynamic_shadow.fog_previous_b[i], dynamic_shadow.fog_previous_c[i]);
        float new_density = fog_bank_density(p, dynamic_shadow.fog_bank_a[i], dynamic_shadow.fog_bank_b[i], dynamic_shadow.fog_bank_c[i]);
        density = max(density, lerp(old_density, new_density, dynamic_shadow.fog_settings.y));
    }
    float2 wind = push.water.zw;
    float wind_length = max(length(wind), .001);
    float2 direction = wind / wind_length;
    float grain = sin(dot(p.xz, direction) * .011 - dynamic_shadow.fog_settings.z * .12) * .5 + .5;
    return density * dynamic_shadow.fog_settings.x * lerp(.82, 1.0, grain);
}

float combined_fog(VertexOutput input) {
    float fog_start = abs(push.projection.z);
    // Keep distinct depth planes without laying a grey veil across the whole
    // scene. LOVE used haze as separation behind luminous detail fragments.
    float fog_end = push.projection.w;
    float distance_fog = saturate((input.depth - fog_start) /
                                  max(fog_end - fog_start, .001));
    // Legacy horizon haze is a near-surface layer. Without altitude thinning
    // it saturates every sea ray from above and hides the local bank shape.
    float altitude_clear = smoothstep(180.0, 500.0, push.camera_position.y);
    distance_fog *= lerp(1.0, .20, altitude_clear);
    float3 midpoint = (push.camera_position.xyz + input.world_position) * .5;
    float density = (local_fog_density(push.camera_position.xyz) +
                     4.0 * local_fog_density(midpoint) +
                     local_fog_density(input.world_position)) / 6.0;
    float optical_depth = density * min(max(input.depth, 0.0), 4500.0) * .0032;
    float bank_fog = 1.0 - exp(-optical_depth);
    return 1.0 - (1.0 - distance_fog) * (1.0 - bank_fog);
}

float3 shade_grass_wind_sheen(VertexOutput input, float3 color) {
    float grass = smoothstep(.18, .82, input.material.x);
    float2 wind = push.water.zw;
    float wind_speed = length(wind);
    float2 wind_direction = wind_speed > .001 ? wind / wind_speed : float2(1, 0);
    float2 wind_across = float2(-wind_direction.y, wind_direction.x);
    float grass_time = push.water.x * (.62 + wind_speed * .018);
    float downwind_coordinate = dot(input.world_position.xz, wind_direction);
    float crosswind_coordinate = dot(input.world_position.xz, wind_across);
    float field_wave =
        sin(downwind_coordinate * .071 - grass_time) * .52 +
        sin((downwind_coordinate * .039 + crosswind_coordinate * .052) -
            grass_time * .73 + 1.7) * .31 +
        sin((downwind_coordinate * .113 - crosswind_coordinate * .027) -
            grass_time * 1.07 + 4.1) * .17;

    float wind_presence = smoothstep(1.4, 8.5, wind_speed);
    float field_distance =
        smoothstep(2.0, 11.0, input.depth) *
        (1.0 - smoothstep(150.0, 235.0, input.depth));
    float crest = smoothstep(-.14, .68, field_wave);
    float trough = smoothstep(-.04, .66, -field_wave);
    float daylight = saturate(push.sun.w);
    float sun_height = smoothstep(-.08, .48, push.sun.y);
    float shadow_visibility =
        dynamic_shadow_visibility(input.world_position, input.normal);
    float postcard_sheen =
        grass * wind_presence * field_distance * daylight *
        shadow_visibility * sun_height;

    float3 warm_grass =
        color * float3(1.18, 1.14, .80) +
        float3(.026, .022, .004);
    float3 cool_grass = color * float3(.88, .94, 1.04);
    color = lerp(color, cool_grass, trough * postcard_sheen * .34);
    return lerp(color, warm_grass, crest * postcard_sheen * .46);
}

// CPU-authored vertex and fog colors are ordinary 8-bit sRGB palette values.
// Decode them before interpolation, lighting, and fog blending; the sRGB
// attachment performs the single linear-to-sRGB conversion on write.
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
    float3 world_position = input.position;
    if (input.kind == MATERIAL_FOLIAGE ||
        input.kind == MATERIAL_LEAF ||
        input.kind == MATERIAL_PETAL) {
        float2 wind = push.water.zw;
        float wind_speed = length(wind);
        float2 wind_direction = wind_speed > .001 ? wind / wind_speed : float2(1, 0);
        float2 wind_across = float2(-wind_direction.y, wind_direction.x);
        // Leaf and petal sheets are emitted twice with opposite normals for
        // two-sided rendering. Their wind position must not depend on which
        // copy faces the camera, or adjacent facets separate where visibility
        // switches sides and expose bright hairline mesh edges.
        float wind_normal_y =
            input.kind == MATERIAL_LEAF || input.kind == MATERIAL_PETAL
                ? abs(input.normal.y)
                : input.normal.y;
        float crown_weight = smoothstep(-.08, .76, wind_normal_y);
        float downwind_coordinate = dot(input.position.xz, wind_direction);
        float crosswind_coordinate = dot(input.position.xz, wind_across);
        float wind_time = push.water.x * (.34 + wind_speed * .012);
        float phase =
            downwind_coordinate * .018 +
            crosswind_coordinate * .006 -
            wind_time;
        float crossing_phase =
            downwind_coordinate * .008 -
            crosswind_coordinate * .011 -
            wind_time * .47 +
            1.9;
        float broad_sway = sin(phase) + sin(crossing_phase) * .34;
        float amplitude = lerp(.20, 1.18, saturate(wind_speed / 14.0 + push.water.y * .24));
        world_position.xz += wind_direction * broad_sway * amplitude * crown_weight;
        world_position.y += sin(phase * .73 - .8) * amplitude * .075 * crown_weight;
    }

    float3 view = world_position - push.camera_position.xyz;
    float depth = dot(view, push.camera_forward.xyz);
    float x = dot(view, push.camera_right.xyz) * push.projection.x / push.projection.y;
    float y = dot(view, push.camera_up.xyz) * push.projection.x;
    float near_plane = push.camera_position.w;
    float far_plane = push.camera_right.w;
    float clip_z = far_plane / (far_plane - near_plane) * depth -
                   far_plane * near_plane / (far_plane - near_plane);
    output.position = float4(x, -y, clip_z, depth);
    output.color = float4(srgb_to_linear(input.color.rgb), input.color.a);
    output.depth = depth;
    output.world_position = world_position;
    output.kind = input.kind;
    output.normal = input.normal;
    output.material = input.material;
    output.uv = input.uv;
    return output;
}

[shader("vertex")]
VertexOutput instance_vertex_main(InstanceVertexInput input) {
    VertexOutput output;
    float3 world_position =
        input.basis_x_translation_x.xyz * input.position.x +
        input.basis_y_translation_y.xyz * input.position.y +
        input.basis_z_translation_z.xyz * input.position.z +
        float3(
            input.basis_x_translation_x.w,
            input.basis_y_translation_y.w,
            input.basis_z_translation_z.w
        );
    float3 world_normal = input.normal_override.w > .5
        ? normalize(input.normal_override.xyz)
        : normalize(
            input.basis_x_translation_x.xyz * input.normal.x +
            input.basis_y_translation_y.xyz * input.normal.y +
            input.basis_z_translation_z.xyz * input.normal.z
        );
    if (input.kind == MATERIAL_FOLIAGE ||
        input.kind == MATERIAL_LEAF ||
        input.kind == MATERIAL_PETAL) {
        float2 wind = push.water.zw;
        float wind_speed = length(wind);
        float2 wind_direction = wind_speed > .001 ? wind / wind_speed : float2(1, 0);
        float2 wind_across = float2(-wind_direction.y, wind_direction.x);
        float wind_normal_y =
            input.kind == MATERIAL_LEAF || input.kind == MATERIAL_PETAL
                ? abs(world_normal.y)
                : world_normal.y;
        float crown_weight = smoothstep(-.08, .76, wind_normal_y);
        float downwind_coordinate = dot(world_position.xz, wind_direction);
        float crosswind_coordinate = dot(world_position.xz, wind_across);
        float wind_time = push.water.x * (.34 + wind_speed * .012);
        float phase =
            downwind_coordinate * .018 +
            crosswind_coordinate * .006 -
            wind_time;
        float crossing_phase =
            downwind_coordinate * .008 -
            crosswind_coordinate * .011 -
            wind_time * .47 +
            1.9;
        float broad_sway = sin(phase) + sin(crossing_phase) * .34;
        float amplitude = lerp(.20, 1.18, saturate(wind_speed / 14.0 + push.water.y * .24));
        world_position.xz += wind_direction * broad_sway * amplitude * crown_weight;
        world_position.y += sin(phase * .73 - .8) * amplitude * .075 * crown_weight;
    }
    float3 view = world_position - push.camera_position.xyz;
    float depth = dot(view, push.camera_forward.xyz);
    float x = dot(view, push.camera_right.xyz) * push.projection.x / push.projection.y;
    float y = dot(view, push.camera_up.xyz) * push.projection.x;
    float near_plane = push.camera_position.w;
    float far_plane = push.camera_right.w;
    float clip_z = far_plane / (far_plane - near_plane) * depth -
                   far_plane * near_plane / (far_plane - near_plane);
    output.position = float4(x, -y, clip_z, depth);
    output.color = float4(srgb_to_linear(input.instance_color.rgb), input.instance_color.a);
    output.depth = depth;
    output.world_position = world_position;
    output.kind = input.kind;
    output.normal = world_normal;
    output.material = input.material;
    output.uv = input.uv;
    return output;
}

[shader("vertex")]
VertexOutput shadow_vertex(VertexInput input) {
    VertexOutput output;
    float receiver_y = push.water.y;
    float sun_y = max(push.sun.y, .12);
    float ray_distance = max(input.position.y - receiver_y, 0.0) / sun_y;
    float3 world_position = float3(
        input.position.x - push.sun.x * ray_distance,
        receiver_y + .040,
        input.position.z - push.sun.z * ray_distance
    );

    float3 view = world_position - push.camera_position.xyz;
    float depth = dot(view, push.camera_forward.xyz);
    float x = dot(view, push.camera_right.xyz) * push.projection.x / push.projection.y;
    float y = dot(view, push.camera_up.xyz) * push.projection.x;
    float near_plane = push.camera_position.w;
    float far_plane = push.camera_right.w;
    float clip_z = far_plane / (far_plane - near_plane) * depth -
                   far_plane * near_plane / (far_plane - near_plane);
    output.position = float4(x, -y, clip_z, depth);
    output.color = 0;
    output.depth = depth;
    output.world_position = world_position;
    output.kind = MATERIAL_UNSHADED;
    output.normal = float3(0, 1, 0);
    output.material = 0;
    output.uv = 0;
    return output;
}

[shader("vertex")]
float4 dynamic_shadow_vertex(VertexInput input) : SV_Position {
    DynamicShadowCascade shadow = dynamic_shadow.cascades[min(dynamic_shadow_push.cascade, 2)];
    float x = (dot(input.position, shadow.right.xyz) - shadow.right.w) /
              shadow.params.x;
    float y = (dot(input.position, shadow.up.xyz) - shadow.up.w) /
              shadow.params.x;
    float z = (dot(input.position, shadow.forward.xyz) - shadow.forward.w) *
              shadow.params.y;
    return float4(x * 2.0, -y * 2.0, saturate(z), 1.0);
}

[shader("fragment")]
float4 shadow_fragment(VertexOutput input) : SV_Target {
    return float4(.030, .036, .039, 1.0);
}

struct BrdfMaterial {
    float3 base_color;
    float metallic;
    float roughness;
};

float dynamic_shadow_compare(uint cascade, float2 uv, float depth) {
    if (cascade == 0) {
        return dynamic_shadow_map_0.SampleCmpLevelZero(dynamic_shadow_sampler, uv, depth);
    }
    if (cascade == 1) {
        return dynamic_shadow_map_1.SampleCmpLevelZero(dynamic_shadow_sampler, uv, depth);
    }
    return dynamic_shadow_map_2.SampleCmpLevelZero(dynamic_shadow_sampler, uv, depth);
}

bool dynamic_shadow_cascade_contains(uint cascade, float3 world_position) {
    DynamicShadowCascade shadow = dynamic_shadow.cascades[cascade];
    float2 uv = float2(
        (dot(world_position, shadow.right.xyz) - shadow.right.w) /
            shadow.params.x + .5,
        .5 - (dot(world_position, shadow.up.xyz) - shadow.up.w) /
            shadow.params.x
    );
    return max(abs(uv.x - .5), abs(uv.y - .5)) < .5;
}

float dynamic_shadow_cascade_visibility(
    uint cascade,
    float3 world_position,
    float3 normal
) {
    DynamicShadowCascade shadow = dynamic_shadow.cascades[cascade];
    float2 uv = float2(
        (dot(world_position, shadow.right.xyz) - shadow.right.w) /
            shadow.params.x + .5,
        .5 - (dot(world_position, shadow.up.xyz) - shadow.up.w) /
            shadow.params.x
    );
    float edge = max(abs(uv.x - .5), abs(uv.y - .5));
    if (edge >= .5) {
        return 1.0;
    }
    float receiver_depth =
        (dot(world_position, shadow.forward.xyz) - shadow.forward.w) *
        shadow.params.y;
    float cascade_scale = 1.0 + float(cascade) * .65;
    float normal_bias =
        (1.0 - saturate(dot(normalize(normal), normalize(push.sun.xyz)))) *
        .00040 * cascade_scale;
    receiver_depth -= .00012 * cascade_scale + normal_bias;
    float texel = shadow.params.w;
    float visibility = 0.0;
    [unroll]
    for (int y = -1; y <= 1; ++y) {
        [unroll]
        for (int x = -1; x <= 1; ++x) {
            visibility += dynamic_shadow_compare(
                cascade,
                uv + float2(x, y) * texel,
                receiver_depth
            );
        }
    }
    visibility /= 9.0;
    return visibility;
}

float dynamic_shadow_visibility(float3 world_position, float3 normal) {
    if (dynamic_shadow.settings.w <= 0.0) {
        return 1.0;
    }
    float origin_distance = length(world_position.xz - dynamic_shadow.origin.xz);
    uint cascade =
        origin_distance < dynamic_shadow.settings.x ? 0 :
        origin_distance < dynamic_shadow.settings.y ? 1 : 2;
    // Horizontal distance is only an estimate of light-space coverage. Tall
    // receivers and low sun angles can move an otherwise-near point outside
    // the inner projection, so fall outward until a cascade actually contains
    // the receiver.
    if (cascade == 0 && !dynamic_shadow_cascade_contains(0, world_position)) {
        cascade = 1;
    }
    if (cascade == 1 && !dynamic_shadow_cascade_contains(1, world_position)) {
        cascade = 2;
    }
    float visibility = dynamic_shadow_cascade_visibility(cascade, world_position, normal);
    // Blend the final 10% of each inner cascade into the next one. Both
    // projections are texel-stabilized, so this hides resolution transitions
    // without introducing camera-motion shimmer.
    if (cascade < 2) {
        float limit = cascade == 0 ? dynamic_shadow.settings.x : dynamic_shadow.settings.y;
        float blend = smoothstep(limit * .90, limit, origin_distance);
        if (blend > 0.0 && dynamic_shadow_cascade_contains(cascade + 1, world_position)) {
            float outer = dynamic_shadow_cascade_visibility(cascade + 1, world_position, normal);
            visibility = lerp(visibility, outer, blend);
        }
    }
    float far_fade = 1.0 - smoothstep(
        dynamic_shadow.settings.z * .90,
        dynamic_shadow.settings.z,
        origin_distance
    );
    return lerp(1.0, visibility, far_fade * dynamic_shadow.settings.w);
}

// Shared opaque-surface response. Product materials supply only base color,
// metallic, and roughness; scene lighting and presentation exposure stay here.
float3 shade_brdf(BrdfMaterial material, float3 normal, float3 world_position) {
    normal = normalize(normal);
    float3 sun_direction = normalize(push.sun.xyz);
    float3 view_direction = normalize(push.camera_position.xyz - world_position);
    float3 half_direction = normalize(sun_direction + view_direction);
    float metallic = saturate(material.metallic);
    float roughness = clamp(material.roughness, .04, 1.0);

    float direct = saturate(dot(normal, sun_direction));
    float shadow_visibility = dynamic_shadow_visibility(world_position, normal);
    float sky = saturate(normal.y * .5 + .5);
    float daylight = saturate(push.sun.w);
    // Values above ordinary daylight are reserved for presentation scenes and
    // act as overall daylight exposure, brightening ambient and direct light.
    float daylight_intensity = max(push.sun.w, 1.0);
    float diffuse_light =
        (.22 + sky * .16 + direct * shadow_visibility * lerp(.26, .78, daylight)) *
        daylight_intensity;
    float3 diffuse = material.base_color * diffuse_light * (1.0 - metallic * .72);

    // This intentionally remains a compact, art-directed BRDF rather than a
    // full image-based PBR stack. It is stable for palette-authored surfaces
    // and requires no material textures beyond optional vehicle paint.
    float3 f0 = lerp(float3(.04, .04, .04), material.base_color, metallic);
    float specular_power = lerp(128.0, 6.0, roughness);
    float specular_strength = pow(saturate(dot(normal, half_direction)), specular_power);
    specular_strength *=
        lerp(.72, .09, roughness) *
        direct * shadow_visibility *
        lerp(.18, 1.0, daylight) *
        daylight_intensity;
    return saturate(diffuse + f0 * specular_strength);
}

float3 shade_cinematic_spotlight(VertexOutput input) {
    float spotlight_intensity = max(push.camera_up.w, 0.0);
    if (spotlight_intensity <= 0.0) return 0.0;
    const float3 spotlight_position = float3(0.0, 11.52, -2.0);
    float3 to_light = spotlight_position - input.world_position;
    float light_distance_squared = max(dot(to_light, to_light), .001);
    float3 light_direction = to_light * rsqrt(light_distance_squared);
    float footprint_radius = max(push.camera_forward.w, .001);
    float footprint_distance =
        length(input.world_position.xz - spotlight_position.xz);
    float cone =
        1.0 - smoothstep(
            footprint_radius * .50,
            footprint_radius,
            footprint_distance
        );
    float range_attenuation =
        1.0 / (1.0 + light_distance_squared * .018);
    float local_direct =
        saturate(dot(normalize(input.normal), light_direction));
    float local_energy =
        spotlight_intensity * cone * range_attenuation;
    float3 spotlight_color = float3(1.0, .73, .40);
    float3 diffuse =
        input.color.rgb * spotlight_color * local_direct * local_energy;

    float3 view_direction =
        normalize(push.camera_position.xyz - input.world_position);
    float3 half_direction =
        normalize(light_direction + view_direction);
    float specular =
        pow(saturate(dot(normalize(input.normal), half_direction)), 24.0) *
        local_direct * local_energy * .16;
    return diffuse + spotlight_color * specular;
}

float3 shade_cinematic_limelights(VertexOutput input) {
    if (push.camera_up.w <= 0.0) return 0.0;
    float3 normal = normalize(input.normal);
    float3 result = 0.0;
    const float3 lime_color = float3(.48, 1.0, .31);
    [unroll]
    for (int lamp = 0; lamp < 9; ++lamp) {
        float3 position =
            float3(-5.2 + float(lamp) * 1.30, .91, -.18);
        float3 to_light = position - input.world_position;
        float distance_squared = max(dot(to_light, to_light), .001);
        float3 light_direction = to_light * rsqrt(distance_squared);
        float direct = saturate(dot(normal, light_direction));
        float attenuation = 1.0 / (1.0 + distance_squared * .085);
        result +=
            input.color.rgb * lime_color *
            direct * attenuation * .34;
    }
    return result;
}

// Palette-authored surfaces intentionally carry their own value grouping, but
// they still need to inhabit the current environment. At night, reduce their
// luminance and chroma, suppress long wavelengths, and add a restrained lunar
// key. This models the perceptual read of mesopic vision without applying a
// flat blue screen filter.
float3 apply_environment_light(
    float3 color,
    float3 normal,
    float3 world_position
) {
    float daylight = saturate(push.sun.w);
    float night = 1.0 - smoothstep(.0, .34, daylight);
    if (night <= 0.0) {
        return color;
    }

    float luma = dot(color, float3(.2126, .7152, .0722));
    float3 low_chroma = lerp(color, luma.xxx, .34);
    float moon_strength = saturate(push.fog_color.a);
    // Preserve a small starlight/readability floor at new moon, then let the
    // whole environment brighten with perceived lunar intensity. The square
    // root keeps quarter and gibbous phases visually distinct.
    float ambient_level = lerp(.15, .35, sqrt(moon_strength));
    float3 cool_fill =
        low_chroma * float3(.68, .84, 1.14) * ambient_level;

    float moon_facing = saturate(dot(normalize(normal), normalize(push.sun.xyz)));
    float moon_key = moon_facing * moon_strength * .13;
    float3 moon_color = float3(.54, .68, .92);
    float3 night_color = cool_fill + low_chroma * moon_color * moon_key;
    return lerp(color, night_color, night);
}

float3 shade_emissive(VertexOutput input) {
    float3 color = input.color.rgb;
    float daylight = saturate(push.sun.w);
    float night = 1.0 - smoothstep(.0, .34, daylight);
    // Fixtures remain recognizable as amber glass by day, then become a
    // stable warm source at night regardless of moonlight availability.
    float3 dormant = color * float3(.24, .20, .14);
    float3 glowing = saturate(color * 1.16 + float3(.12, .045, .006));
    float3 source = lerp(dormant, glowing, night);
    if (input.material.x > .5) {
        if (input.material.x < 1.5) {
            // Municipal post-top lanterns reuse their six glass faces: UV-space
            // perimeter iron and one vertical mullion describe a caged fixture
            // without extra geometry, draw calls, or textures.
            float2 edge_distance = min(input.uv, 1.0 - input.uv);
            float perimeter =
                1.0 - smoothstep(.055, .105, min(edge_distance.x, edge_distance.y));
            float mullion =
                1.0 - smoothstep(.035, .070, abs(input.uv.x - .5));
            float cage = saturate(max(perimeter, mullion));
            float3 iron = source * lerp(.15, .08, night);
            source = lerp(source, iron, cage * .94);
        } else {
            // Cantilever heads use the same box faces as a shallow prismatic
            // lens. A dim gasket, frosted shoulder, and two broad optic ribs
            // keep the source from reading as an unshaped emissive slab.
            float2 lens_position = input.uv * 2.0 - 1.0;
            float lens_radius =
                length(lens_position * float2(.90, 1.08));
            float gasket =
                smoothstep(.74, .94, max(abs(lens_position.x), abs(lens_position.y)));
            float shoulder =
                1.0 - smoothstep(.24, .92, lens_radius);
            float optic_ribs =
                .88 + .12 * pow(abs(cos(lens_position.x * 6.2831853)), 5.0);
            source *= lerp(.90, 1.08, shoulder) * optic_ribs;
            source = lerp(source, source * lerp(.24, .12, night), gasket);
        }
    }
    return source;
}

float3 shade_imported_material(VertexOutput input) {
    float3 base_color = input.color.rgb;
    bool vehicle = input.kind == MATERIAL_VEHICLE;
    if (vehicle && input.material.x > .5) {
        float4 paint = vehicle_paint_atlas.Sample(
            vehicle_paint_sampler,
            float3(input.uv, input.material.y)
        );
        // The atlas uses VK_FORMAT_R8G8B8A8_SRGB, so texture sampling has
        // already decoded the stored palette color into linear space.
        base_color = lerp(base_color, paint.rgb, paint.a);
    }
    BrdfMaterial material;
    material.base_color = base_color;
    material.metallic = vehicle ? 0 : input.material.x;
    material.roughness = vehicle ? .04 : input.material.y;
    return shade_brdf(material, input.normal, input.world_position);
}

float3 shade_material_lab(VertexOutput input) {
    float4 albedo = material_lab_albedo.Sample(material_lab_albedo_sampler, input.uv);
    float specular = material_lab_specular.Sample(material_lab_specular_sampler, input.uv).r;
    float roughness = material_lab_roughness.Sample(material_lab_roughness_sampler, input.uv).r;
    float3 map_normal = material_lab_normal.Sample(material_lab_normal_sampler, input.uv).xyz * 2.0 - 1.0;
    float3 geometric_normal = normalize(input.normal);
    float3 tangent = float3(-geometric_normal.z, 0.0, geometric_normal.x);
    tangent = dot(tangent, tangent) < .01 ? float3(1.0, 0.0, 0.0) : normalize(tangent);
    float3 bitangent = normalize(cross(geometric_normal, tangent));
    float3 normal = normalize(
        tangent * map_normal.x +
        bitangent * map_normal.y +
        geometric_normal * map_normal.z
    );
    BrdfMaterial material;
    material.base_color = albedo.rgb * input.color.rgb;
    material.metallic = saturate(specular);
    material.roughness = clamp(roughness, .02, 1.0);
    return shade_brdf(material, normal, input.world_position);
}

float bark_value_noise(float2 p) {
    float2 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(
        lerp(hash12(i), hash12(i + float2(1, 0)), f.x),
        lerp(hash12(i + float2(0, 1)), hash12(i + float2(1, 1)), f.x),
        f.y
    );
}

float bark_voronoi_plate(float2 p) {
    float2 cell = floor(p);
    float2 local = frac(p);
    float nearest = 100.0;
    float second = 100.0;
    [unroll] for (int y = -1; y <= 1; ++y) {
        [unroll] for (int x = -1; x <= 1; ++x) {
            float2 neighbor = float2(x, y);
            float2 id = cell + neighbor;
            float2 jitter = float2(
                bark_value_noise(id + 13.7),
                bark_value_noise(id + 47.3)
            );
            float distance_to_site = length(neighbor + jitter - local);
            if (distance_to_site < nearest) {
                second = nearest;
                nearest = distance_to_site;
            } else if (distance_to_site < second) {
                second = distance_to_site;
            }
        }
    }
    return smoothstep(.035, .13, second - nearest);
}

float3 shade_bark(VertexOutput input) {
    uint pattern = (uint)floor(input.material.x + .0001);
    float detail_strength = saturate(frac(input.material.x) * 100.0);
    // Integer-only payloads from older or auxiliary callers mean full detail.
    detail_strength = detail_strength < .001 ? 1.0 : detail_strength;
    float2 uv = input.uv;
    float uv_footprint = max(length(ddx(uv)), length(ddy(uv)));
    float footprint_detail = 1.0 - smoothstep(.008, .045, uv_footprint);
    detail_strength *= footprint_detail;
    float warp = bark_value_noise(float2(uv.y * .42, uv.x * 1.7 + 9.3)) - .5;
    float2 grain_uv = float2(uv.x + warp * .075, uv.y);
    float broad = bark_value_noise(grain_uv * float2(4.0, 1.35));
    float fine = bark_value_noise(grain_uv * float2(17.0, 8.0) + 7.1);
    // Broad color identity can survive at a larger footprint than relief.
    // This preserves plane camouflage and peeling color at game distance
    // while the fine bump signal still filters away on narrow branches.
    float identity_strength = 1.0 - smoothstep(.045, .20, uv_footprint);
    float identity_broad = lerp(.5, broad, identity_strength);
    float mask = .5;

    if (pattern == 1) {
        // Long, wandering valleys. Two frequencies prevent the evenly
        // spaced corduroy that makes a trunk read as machined or banded.
        float primary = abs(sin((grain_uv.x * 5.2 + warp * .42) * 6.2831853));
        float secondary = abs(sin((grain_uv.x * 10.7 - warp * .24 + broad * .10) * 6.2831853));
        float ridges = smoothstep(.16, .62, primary) * .76 + smoothstep(.28, .70, secondary) * .16;
        mask = saturate(ridges + broad * .16);
    } else if (pattern == 2) {
        // Fine peeling flakes need broken organic outlines. A warped,
        // vertically elongated Voronoi field avoids the brick-grid rhythm
        // that becomes especially obvious on long trained grape canes.
        float2 flake_uv = grain_uv * float2(6.4, 3.1);
        flake_uv.x += (bark_value_noise(float2(grain_uv.y * 1.1, 31.7)) - .5) * .62;
        flake_uv.y += (bark_value_noise(float2(grain_uv.x * 2.3, 17.2)) - .5) * .28;
        float flake = bark_voronoi_plate(flake_uv);
        mask = smoothstep(.08, .88, flake) * lerp(.72, 1.0, broad);
    } else if (pattern == 3) {
        float2 warped = uv * float2(9.2, 4.4);
        warped.x += (bark_value_noise(float2(uv.y * 1.7, 8.4)) - .5) * .94;
        warped.y += (bark_value_noise(float2(uv.x * 1.3, 2.1)) - .5) * .64;
        float plate = bark_voronoi_plate(warped);
        float vertical_split = smoothstep(.18, .72, abs(sin((grain_uv.x * 13.0 + warp * .7) * 6.2831853)));
        mask = plate * lerp(.74, 1.0, broad) * lerp(.88, 1.0, vertical_split);
    } else if (pattern == 4) {
        mask = smoothstep(.30, .68, broad);
    } else if (pattern == 5) {
        float fiber = bark_value_noise(float2(uv.x * 18.0, uv.y * 3.2));
        mask = lerp(.58, 1.0, fiber) * lerp(.82, 1.0, broad);
    } else if (pattern == 6) {
        float lenticel_noise = bark_value_noise(uv * float2(8.0, 18.0));
        float lenticel = smoothstep(.82, .93, lenticel_noise);
        mask = lerp(.92, .48, lenticel) * lerp(.90, 1.06, broad);
    } else if (pattern == 7) {
        mask = lerp(.94, 1.04, fine);
    } else {
        mask = lerp(.88, 1.08, broad * .65 + fine * .35);
    }

    // Low-detail trunks carry fewer radial faces and cover fewer pixels.
    // Fade procedural contrast before it aliases into rigid bars or crawling
    // highlights, retaining the catalog base color as the distant identity.
    mask = lerp(.5, mask, detail_strength);
    broad = lerp(.5, broad, detail_strength);
    fine = lerp(.5, fine, detail_strength);

    float contrast = pattern == 3 ? .28 : pattern == 1 ? .26 : pattern == 2 ? .25 : .18;
    float tone = lerp(1.0 - contrast, 1.0 + contrast * .34, saturate(mask));
    float height = saturate(mask * .78 + fine * .22);
    float2 gradient = float2(ddx(height), ddy(height));
    float3 geometric_normal = normalize(input.normal);
    float normal_strength = (pattern == 3 ? .14 : pattern == 1 ? .12 : .08) * detail_strength;
    // `gradient` is in screen-derivative space, not UV tangent space. Build
    // the surface gradient directly from position derivatives so relief
    // follows bent and horizontal limbs without turning into dotted facets.
    float3 position_dx = ddx(input.world_position);
    float3 position_dy = ddy(input.world_position);
    float3 gradient_basis_x = cross(position_dy, geometric_normal);
    float3 gradient_basis_y = cross(geometric_normal, position_dx);
    float determinant = dot(position_dx, gradient_basis_x);
    float3 surface_gradient = sign(determinant) *
                              (gradient.x * gradient_basis_x + gradient.y * gradient_basis_y);
    float3 mapped_normal = normalize(
        max(abs(determinant), 1e-6) * geometric_normal -
        surface_gradient * normal_strength
    );

    BrdfMaterial material;
    float3 bark_color = input.color.rgb * tone;
    if (pattern == 2) {
        // Thin flakes expose a warm, cleaner face above cooler old bark.
        // Keeping this relative to the catalog color lets strawberry tree,
        // pomegranate, and hydrangea retain separate identities.
        float peel_wave = .5 + .5 * sin(
            grain_uv.y * 8.2 + grain_uv.x * 10.4 + warp * 3.6
        );
        peel_wave = lerp(.5, peel_wave, identity_strength);
        float peel = smoothstep(
            .32,
            .70,
            identity_broad * .34 + mask * .28 + peel_wave * .38
        );
        float3 old_bark = input.color.rgb * float3(.66, .60, .56);
        float3 fresh_face = saturate(input.color.rgb * float3(1.22, 1.09, 1.01) + float3(.026, .007, 0));
        bark_color = lerp(old_bark, fresh_face, peel);
        bark_color *= lerp(.92, 1.06, fine);
    } else if (pattern == 3) {
        // Plate faces sun-bleach while their separating fissures stay cool.
        float plate_face = smoothstep(.24, .76, mask);
        float3 fissure = input.color.rgb * float3(.72, .67, .63);
        float3 face = saturate(input.color.rgb * 1.08 + float3(.010, .005, 0));
        bark_color = lerp(fissure, face, plate_face);
    } else if (pattern == 4) {
        // Plane bark is recognized first by broad cream, olive, and taupe
        // camouflage patches, not by high-frequency relief.
        float mottle_wave = .5 + .5 * sin(
            grain_uv.y * 6.4 + grain_uv.x * 9.2 +
            bark_value_noise(grain_uv * float2(1.35, .82) + 6.8) * 3.8
        );
        mottle_wave = lerp(.5, mottle_wave, identity_strength);
        float patch = smoothstep(.26, .72, identity_broad * .42 + mottle_wave * .58);
        float island_noise = bark_value_noise(grain_uv * float2(1.65, .62) + 19.4);
        float island = lerp(.5, smoothstep(.34, .69, island_noise), identity_strength);
        float3 olive_patch = input.color.rgb * float3(.57, .65, .51);
        float3 taupe_patch = input.color.rgb * float3(.88, .84, .73);
        float3 cream_patch = saturate(input.color.rgb * float3(1.30, 1.25, 1.13) + float3(.052, .043, .025));
        bark_color = lerp(olive_patch, taupe_patch, smoothstep(.12, .55, patch));
        bark_color = lerp(bark_color, cream_patch, smoothstep(.52, .88, patch * .72 + island * .28));
    }
    material.base_color = bark_color;
    material.metallic = 0.0;
    material.roughness = clamp(input.material.y + (fine - .5) * .08, .62, 1.0);
    return shade_brdf(material, mapped_normal, input.world_position);
}

float3 shade_rock(VertexOutput input) {
    float4 albedo = material_lab_albedo.Sample(material_lab_albedo_sampler, input.uv);
    float roughness_map = material_lab_roughness.Sample(material_lab_roughness_sampler, input.uv).r;
    float3 map_normal = material_lab_normal.Sample(material_lab_normal_sampler, input.uv).xyz * 2.0 - 1.0;
    float3 geometric_normal = normalize(input.normal);
    float3 tangent = float3(-geometric_normal.z, 0.0, geometric_normal.x);
    tangent = dot(tangent, tangent) < .01 ? float3(1.0, 0.0, 0.0) : normalize(tangent);
    float3 bitangent = normalize(cross(geometric_normal, tangent));
    float3 mapped_normal = normalize(
        tangent * map_normal.x * .55 +
        bitangent * map_normal.y * .55 +
        geometric_normal * max(map_normal.z, .25)
    );

    float texture_mix = saturate(input.color.a);
    float3 base_color = lerp(input.color.rgb, albedo.rgb * input.color.rgb, texture_mix);
    float3 view_direction = normalize(push.camera_position.xyz - input.world_position);

    // Normal derivatives spike where a pixel quad crosses a faceted mesh edge.
    // The view term keeps silhouettes readable as the camera moves. Strength
    // zero bypasses both effects, making dynamic edge shading truly optional.
    float crease_metric = length(ddx(geometric_normal)) + length(ddy(geometric_normal));
    float crease = smoothstep(.035, .28, crease_metric);
    float rim = pow(1.0 - saturate(dot(mapped_normal, view_direction)), 2.0);
    float edge = saturate((crease * 1.1 + rim * .65) * max(input.material.x, 0.0));
    float3 warm_edge = base_color * 1.25 + float3(.045, .036, .018);
    base_color = lerp(base_color, warm_edge, edge * .88);

    BrdfMaterial material;
    material.base_color = base_color;
    material.metallic = 0.0;
    material.roughness = clamp(lerp(input.material.y, roughness_map, texture_mix), .18, 1.0);
    return shade_brdf(material, mapped_normal, input.world_position);
}

float3 shade_settlement_material(VertexOutput input) {
    uint id = (uint)round(input.material.x);
    float3 color = float3(.72, .70, .64);
    float metallic = 0.0;
    float roughness = .72;

    // These IDs mirror Settlement_Material. Generated geometry stores only the
    // compact semantic ID; thousands of surfaces share this one shader path.
    if (id == 0) { color = float3(.78, .75, .66); roughness = .78; }
    else if (id == 1) { color = float3(.91, .84, .68); roughness = .88; }
    else if (id == 2) { color = float3(.71, .66, .55); roughness = .48; }
    else if (id == 3) { color = float3(.17, .21, .21); metallic = .38; roughness = .46; }
    else if (id == 4) { color = float3(.22, .31, .34); metallic = .72; roughness = .31; }
    else if (id == 5) { color = float3(.07, .08, .08); metallic = .55; roughness = .36; }
    else if (id == 6) { color = float3(.31, .16, .075); roughness = .55; }
    else if (id == 7) { color = float3(.62, .23, .12); roughness = .82; }
    else if (id == 8) { color = float3(.105, .065, .035); roughness = .97; }
    else if (id == 9) { color = float3(.075, .082, .080); roughness = .93; }
    else if (id == 10) { color = float3(.67, .65, .59); roughness = .86; }
    else if (id == 11) { color = float3(.11, .13, .13); metallic = .76; roughness = .57; }
    else if (id == 12) { color = float3(.88, .88, .80); roughness = .68; }
    else if (id == 13) { color = float3(.76, .55, .12); roughness = .71; }
    else if (id == 14) { color = float3(.53, .34, .12); metallic = .86; roughness = .28; }
    else if (id == 15) { color = float3(.82, .76, .57); metallic = .28; roughness = .34; }
    else if (id == 16) { color = float3(.57, .075, .045); metallic = .22; roughness = .29; }
    else if (id == 17) { color = float3(.64, .61, .53); roughness = .94; }
    else if (id == 18) { color = float3(.60, .56, .47); roughness = .30; }
    else if (id == 19) { color = float3(.62, .57, .45); roughness = .78; }
    else if (id == 20) { color = float3(.16, .24, .25); metallic = .63; roughness = .39; }
    else if (id == 21) { color = float3(.075, .20, .23); metallic = .08; roughness = .16; }
    else if (id == 22) { color = float3(.20, .24, .24); metallic = .82; roughness = .25; }
    else if (id == 23) { color = float3(.055, .36, .35); roughness = .25; }
    else if (id == 24) { color = float3(.71, .70, .64); roughness = .91; }
    else if (id == 25) { color = float3(.28, .32, .30); roughness = .34; }
    else if (id == 26) { color = float3(.38, .030, .022); metallic = .18; roughness = .34; }
    else if (id == 27) { color = float3(.59, .32, .11); roughness = .42; }

    float2 uv = input.uv;
    float grain = value_noise(floor(uv * 24.0) + id * 11.7) - .5;
    color *= 1.0 + grain * ((id == 1 || id == 8 || id == 9 || id == 17) ? .15 : .055);
    if (id == 0 || id == 17) {
        float joints = min(frac(uv.x * .42), frac(uv.y * .42));
        color *= lerp(.70, 1.0, smoothstep(.025, .065, joints));
    } else if (id == 2 || id == 18) {
        // Broad, continuous aggregate survives distance filtering. The old
        // 13-samples-per-metre binary chips collapsed into salt-and-pepper
        // noise across the large airport floor.
        float frequency = id == 18 ? 2.4 : 3.2;
        float aggregate = value_noise(uv * frequency);
        float contrast = smoothstep(.24, .82, aggregate);
        color *= lerp(.90, 1.07, contrast);
    } else if (id == 19) {
        // Forecourt paving reads from slab joints and restrained stone value,
        // rather than sharing the terrazzo chip field.
        float2 slab_uv = uv / float2(2.4, 1.6);
        float row = floor(slab_uv.y);
        slab_uv.x += fmod(abs(row), 2.0) * .5;
        float2 edge = min(frac(slab_uv), 1.0 - frac(slab_uv));
        float joint = smoothstep(.018, .050, min(edge.x, edge.y));
        float stone = value_noise(uv * .72);
        color *= lerp(.72, lerp(.96, 1.04, stone), joint);
    } else if (id == 6) {
        color *= .82 + .18 * smoothstep(.08, .20, abs(frac(uv.y * 5.0) - .5));
    } else if (id == 11) {
        color *= .64 + .36 * smoothstep(.12, .25, abs(frac(uv.x * 5.0) - .5));
    } else if (id == 20) {
        color *= .76 + .24 * smoothstep(.05, .16, abs(frac(uv.x * .72) - .5));
    } else if (id == 23) {
        float2 grout = min(frac(uv * 3.2), 1.0 - frac(uv * 3.2));
        color = lerp(float3(.55, .55, .50), color, smoothstep(.025, .055, min(grout.x, grout.y)));
    } else if (id == 26) {
        float orange_peel = value_noise(uv * 38.0);
        float chips = smoothstep(.955, .99, value_noise(uv * 11.0 + 7.3));
        color *= lerp(.96, 1.035, orange_peel);
        color = lerp(color, float3(.035, .040, .038), chips * .72);
        roughness = lerp(roughness, .70, chips);
    } else if (id == 27) {
        float fine_grain = value_noise(float2(uv.x * 5.0, uv.y * 34.0));
        float broad_grain = value_noise(float2(uv.x * 1.4, uv.y * 8.0) + 4.7);
        color *= lerp(.88, 1.10, fine_grain) * lerp(.94, 1.05, broad_grain);
        roughness *= lerp(.90, 1.08, fine_grain);
    }

    BrdfMaterial material;
    material.base_color = srgb_to_linear(saturate(color)) * input.color.rgb;
    material.metallic = metallic;
    material.roughness = roughness;
    return shade_brdf(material, input.normal, input.world_position);
}

float3 shade_car_paint_coat(
    VertexOutput input,
    float3 base_color,
    float finish,
    float roughness
) {
    float metal_flake = step(.5, finish);
    BrdfMaterial color_coat;
    color_coat.base_color = base_color;
    // Opaque paint remains a dielectric pigment layer. Metallic paint mixes
    // in a restrained conductor response instead of reading as bare metal.
    color_coat.metallic = metal_flake * .18;
    color_coat.roughness = roughness;
    float3 base = shade_brdf(color_coat, input.normal, input.world_position);

    // Automotive paint has a color-bearing coat below a smooth, colorless
    // dielectric layer. Keep this as an independent lobe so the broad body
    // shading remains readable beneath a tighter, view-dependent highlight.
    float3 normal = normalize(input.normal);
    float3 view_direction =
        normalize(push.camera_position.xyz - input.world_position);
    float3 sun_direction = normalize(push.sun.xyz);
    float3 half_direction = normalize(sun_direction + view_direction);
    float direct = saturate(dot(normal, sun_direction));
    float facing = saturate(dot(normal, view_direction));
    float fresnel = .04 + .96 * pow(1.0 - facing, 5.0);
    float shadow_visibility =
        dynamic_shadow_visibility(input.world_position, normal);
    float daylight = saturate(push.sun.w);
    float daylight_intensity = max(push.sun.w, 1.0);
    float clearcoat_specular =
        pow(saturate(dot(normal, half_direction)), 112.0) *
        direct * shadow_visibility *
        lerp(.16, 1.0, daylight) * daylight_intensity;
    float sky_glance = pow(1.0 - facing, 3.0) * (.035 + daylight * .075);
    float3 clearcoat =
        float3(1.0, .97, .90) * (clearcoat_specular * .42 + sky_glance);

    // Stable object-scale noise represents flakes distributed through the
    // color coat. Broad frequencies avoid sub-pixel glitter shimmer, while
    // the half-vector term reveals flecks as the body turns through the light.
    float flake_field =
        value_noise(input.world_position.xz * 21.0 +
                    input.world_position.y * float2(9.0, -13.0)) * .64 +
        value_noise(input.world_position.zy * 37.0 +
                    input.world_position.x * float2(-7.0, 11.0)) * .36;
    float flake_mask = smoothstep(.67, .90, flake_field) * metal_flake;
    float flake_alignment =
        pow(saturate(dot(normal, half_direction)), 34.0);
    float3 flake_specular =
        lerp(float3(.78, .86, .88), base_color, .28) *
        flake_mask * flake_alignment * direct * shadow_visibility *
        daylight_intensity * .38;

    // The top interface reflects a little energy before it reaches the color
    // coat; applying that attenuation keeps the added pass from washing out
    // the petrol-teal body at grazing angles.
    return saturate(
        base * (1.0 - fresnel * .34) + flake_specular + clearcoat
    );
}

float3 shade_car_paint(VertexOutput input) {
    return shade_car_paint_coat(
        input,
        input.color.rgb,
        input.material.x,
        input.material.y
    );
}

float3 shade_vehicle(VertexOutput input) {
    bool paintable = input.material.x > .5;
    float3 base_color = input.color.rgb;
    if (paintable) {
        float4 paint = vehicle_paint_atlas.Sample(
            vehicle_paint_sampler,
            float3(input.uv, input.material.y)
        );
        // The sRGB atlas is decoded by the sampler. Decoding it again here
        // darkens and shifts the selected palette color.
        base_color = lerp(base_color, paint.rgb, paint.a);
        // Keep the editable atlas as the pigment beneath the shared clear coat.
        return shade_car_paint_coat(input, base_color, 0.0, .54);
    }

    BrdfMaterial material;
    material.base_color = base_color;
    material.metallic = 0;
    material.roughness = .58;
    return shade_brdf(material, input.normal, input.world_position);
}

float architecture_texture_sample(VertexOutput input) {
    float3 normal = abs(normalize(input.normal));
    // World-space triplanar projection keeps the procedural building meshes
    // textured consistently without adding a second UV-generation path.
    float2 uv_x = input.world_position.zy / 2.0;
    float2 uv_y = input.world_position.xz / 4.0;
    float2 uv_z = input.world_position.xy / 2.0;
    float3 weights = pow(normal, 8.0);
    weights /= max(weights.x + weights.y + weights.z, .001);
    float selector = input.material.x;
    float tile = clamp(floor(selector + .5), 0.0, 2.0);
    float2 atlas_x = float2((frac(uv_x.x) + tile) / 3.0, frac(uv_x.y));
    float2 atlas_y = float2((frac(uv_y.x) + tile) / 3.0, frac(uv_y.y));
    float2 atlas_z = float2((frac(uv_z.x) + tile) / 3.0, frac(uv_z.y));
    float sample_x = architecture_material_atlas.Sample(architecture_material_sampler, atlas_x).r;
    float sample_y = architecture_material_atlas.Sample(architecture_material_sampler, atlas_y).r;
    float sample_z = architecture_material_atlas.Sample(architecture_material_sampler, atlas_z).r;
    return dot(float3(sample_x, sample_y, sample_z), weights);
}

float3 shade_architecture(VertexOutput input) {
    float selector = input.material.x;
    float reference = selector < .5 ? .7466 : selector < 1.5 ? .6619 : .4842;
    float strength = selector < .5 ? .42 : selector < 1.5 ? .58 : .52;
    float modulation = lerp(1.0, architecture_texture_sample(input) / reference, strength);
    float3 base = saturate(input.color.rgb * clamp(modulation, .68, 1.30));
    float visibility = dynamic_shadow_visibility(input.world_position, input.normal);
    return base * lerp(.72, 1.0, visibility);
}

float ray_box_distance(float3 ray_origin, float3 ray_direction, float3 box_center, float3 box_half_extent) {
    float3 safe_direction = float3(
        abs(ray_direction.x) < .0001 ? (ray_direction.x < 0.0 ? -.0001 : .0001) : ray_direction.x,
        abs(ray_direction.y) < .0001 ? (ray_direction.y < 0.0 ? -.0001 : .0001) : ray_direction.y,
        abs(ray_direction.z) < .0001 ? (ray_direction.z < 0.0 ? -.0001 : .0001) : ray_direction.z
    );
    float3 inverse_direction = 1.0 / safe_direction;
    float3 near_plane = (box_center - box_half_extent - ray_origin) * inverse_direction;
    float3 far_plane = (box_center + box_half_extent - ray_origin) * inverse_direction;
    float3 near_axis = min(near_plane, far_plane);
    float3 far_axis = max(near_plane, far_plane);
    float near_distance = max(near_axis.x, max(near_axis.y, near_axis.z));
    float far_distance = min(far_axis.x, min(far_axis.y, far_axis.z));
    return far_distance >= max(near_distance, 0.0) ? max(near_distance, 0.0) : 1e6;
}

float3 shade_window_room(VertexOutput input, float3 view, float facing) {
    float encoded = input.material.y;
    float variant = max(floor(encoded) - 1.0, 0.0);
    int purpose = int(variant + .5);
    float payload = floor(frac(encoded) * 4096.0);
    float encoded_depth = lerp(.35, .95, floor(payload / 64.0) / 63.0);
    float pane_aspect = lerp(.25, 4.0, fmod(payload, 64.0) / 63.0);
    float decor = frac(encoded_depth * 19.19 + pane_aspect * 7.31);
    float form_variation_a = frac(decor * 7.17 + .31);
    float form_variation_b = frac(decor * 13.73 + .57);
    float form_variation_c = frac(decor * 23.41 + .19);
    // Treat the pane as an aperture into a normally proportioned room rather
    // than making the pane itself the room cross-section. The room expands to
    // contain wide panes and crops horizontally behind narrow panes.
    float canonical_room_aspect = 1.35;
    float height_scale = 1.10;
    float depth_scale = 1.0;
    float window_center_height = .02;
    if (purpose == 1) {
        canonical_room_aspect = 1.80;
        height_scale = 1.18;
        depth_scale = 1.18;
        window_center_height = .075;
    } else if (purpose == 2) {
        canonical_room_aspect = 1.65;
        height_scale = 1.16;
        depth_scale = 1.12;
        window_center_height = .055;
    } else if (purpose == 3) {
        canonical_room_aspect = 1.55;
        height_scale = 1.12;
        depth_scale = 1.28;
        window_center_height = .025;
    } else if (purpose == 4) {
        canonical_room_aspect = 1.75;
        height_scale = 1.34;
        depth_scale = 1.22;
        window_center_height = .075;
    } else if (purpose == 5) {
        canonical_room_aspect = 1.45;
        height_scale = 1.12;
        depth_scale = .92;
        window_center_height = .025;
    }
    canonical_room_aspect *= lerp(.95, 1.05, form_variation_a);
    height_scale *= lerp(.96, 1.04, form_variation_b);
    depth_scale *= lerp(.94, 1.07, form_variation_c);
    window_center_height += lerp(-.012, .012, form_variation_a);
    float room_height = max(1.0, pane_aspect / canonical_room_aspect) * height_scale;
    float room_width = canonical_room_aspect * room_height;
    float room_depth = encoded_depth * room_height * depth_scale;
    float2 room_half_extent = float2(room_width, room_height) * .5;
    float3 normal = normalize(input.normal);
    float3 up = float3(0.0, 1.0, 0.0);
    float3 right = normalize(cross(up, normal));
    float3 inward = -normal;
    float3 ray_world = -view;
    float3 ray = float3(
        dot(ray_world, right),
        dot(ray_world, up),
        dot(ray_world, inward)
    );
    ray.z = max(ray.z, .035);
    float3 origin = float3(
        (input.uv.x - .5) * pane_aspect,
        .5 - input.uv.y + window_center_height * room_height,
        0.0
    );

    // Purpose and seed can reshape the primary shell itself. Taper is measured
    // from the window plane to the back wall; ceiling drop produces a shed
    // profile while leaving the floor flat.
    float wall_taper = 0.0;
    if (purpose == 0) wall_taper = lerp(-.14, -.06, form_variation_a);
    if (purpose == 1) wall_taper = lerp(.04, .12, form_variation_b);
    if (purpose == 2) wall_taper = lerp(-.08, .02, form_variation_c);
    if (purpose == 4) wall_taper = lerp(.04, .10, form_variation_a);
    float ceiling_drop = 0.0;
    if (purpose == 0 && form_variation_c > .55) ceiling_drop = room_height * lerp(.04, .09, form_variation_b);
    if (purpose == 2) ceiling_drop = room_height * lerp(.12, .20, form_variation_a);
    if (purpose == 3) ceiling_drop = room_height * lerp(.08, .16, form_variation_b);

    float side_sign = ray.x >= 0.0 ? 1.0 : -1.0;
    float side_x = side_sign * room_half_extent.x;
    float side_y = ray.y >= 0.0 ? room_half_extent.y : -room_half_extent.y;
    float taper_rate = wall_taper / max(room_depth, .001);
    float wall_denominator = ray.x - side_sign * room_half_extent.x * taper_rate * ray.z;
    wall_denominator = abs(wall_denominator) < .0001 ?
                       (wall_denominator < 0.0 ? -.0001 : .0001) : wall_denominator;
    float wall_numerator = side_sign * room_half_extent.x * (1.0 + taper_rate * origin.z) - origin.x;
    float tx = wall_numerator / wall_denominator;
    float ty = 0.0;
    if (ray.y >= 0.0 && ceiling_drop > 0.0) {
        float ceiling_slope = ceiling_drop / max(room_depth, .001);
        float ceiling_denominator = ray.y + ceiling_slope * ray.z;
        ceiling_denominator = abs(ceiling_denominator) < .0001 ? .0001 : ceiling_denominator;
        ty = (room_half_extent.y - origin.y - ceiling_slope * origin.z) / ceiling_denominator;
    } else {
        float safe_ray_y = abs(ray.y) < .0001 ? (ray.y < 0.0 ? -.0001 : .0001) : ray.y;
        ty = (side_y - origin.y) / safe_ray_y;
    }
    if (purpose == 4) {
        // Elliptical barrel vault, extruded through the room depth. Solve the
        // upper ellipse intersection directly so the curved ceiling has true
        // parallax instead of behaving like back-wall decoration.
        float vault_origin_x = origin.x / room_width;
        float vault_origin_y = origin.y / room_height - .32;
        float vault_ray_x = ray.x / room_width;
        float vault_ray_y = ray.y / room_height;
        float vault_a = vault_ray_x * vault_ray_x / (.5 * .5) +
                        vault_ray_y * vault_ray_y / (.18 * .18);
        float vault_b = 2.0 * (vault_origin_x * vault_ray_x / (.5 * .5) +
                               vault_origin_y * vault_ray_y / (.18 * .18));
        float vault_c = vault_origin_x * vault_origin_x / (.5 * .5) +
                        vault_origin_y * vault_origin_y / (.18 * .18) - 1.0;
        float vault_discriminant = vault_b * vault_b - 4.0 * vault_a * vault_c;
        if (vault_a > .000001 && vault_discriminant >= 0.0) {
            float vault_t = (-vault_b + sqrt(vault_discriminant)) / (2.0 * vault_a);
            if (vault_t > 0.0) ty = min(ty, vault_t);
        }
    }
    float tz = room_depth / ray.z;
    float distance = min(tx, min(ty, tz));
    float3 hit = origin + ray * distance;
    float3 room_hit = float3(
        hit.x / room_width,
        hit.y / room_height,
        hit.z / room_height
    );
    float normalized_room_depth = room_depth / room_height;

    bool back = tz <= tx && tz <= ty;
    bool horizontal = !back && ty <= tx;
    // Some purposes continue through a rear opening instead of terminating at
    // one flat wall. Moving the analytic hit plane creates a real secondary
    // volume with view-dependent parallax, not just a painted dark rectangle.
    float rear_x = room_hit.x;
    float rear_y = room_hit.y;
    float dwelling_door_x = (decor < .5 ? -1.0 : 1.0) * lerp(.22, .29, form_variation_b);
    float dwelling_door_half = lerp(.12, .15, form_variation_c);
    float shop_bay_half = lerp(.29, .34, form_variation_a);
    float workshop_bay_center = lerp(.23, .29, form_variation_b);
    float workshop_bay_half = lerp(.145, .18, form_variation_c);
    float civic_arch_half = lerp(.245, .29, form_variation_a);
    float clinic_corridor_edge = lerp(-.20, -.14, form_variation_b);
    bool dwelling_door = purpose == 0 && abs(rear_x - dwelling_door_x) < dwelling_door_half &&
                         rear_y > -.36 && rear_y < .29;
    bool shop_bay = purpose == 1 && abs(rear_x) < shop_bay_half && rear_y > -.31 && rear_y < .36;
    bool workshop_bay = purpose == 2 && abs(rear_x - workshop_bay_center) < workshop_bay_half &&
                        rear_y > -.30 && rear_y < .32;
    bool civic_arch = purpose == 4 && abs(rear_x) < civic_arch_half &&
                      (rear_y < .16 || length(float2(rear_x / civic_arch_half, (rear_y - .16) / .19)) < 1.0);
    bool clinic_corridor = purpose == 5 && rear_x < clinic_corridor_edge && rear_y > -.34 && rear_y < .38;
    bool rear_bay = back && (dwelling_door || shop_bay || workshop_bay || civic_arch || clinic_corridor);
    float rear_jamb = 0.0;
    if (back && purpose == 0 && abs(rear_x - dwelling_door_x) < dwelling_door_half + .04 && rear_y > -.39 && rear_y < .33) {
        float edge = min(abs(abs(rear_x - dwelling_door_x) - dwelling_door_half),
                         min(abs(rear_y + .36), abs(rear_y - .29)));
        rear_jamb = 1.0 - smoothstep(.012, .034, edge);
    } else if (back && purpose == 1 && abs(rear_x) < shop_bay_half + .04 && rear_y > -.35 && rear_y < .40) {
        float edge = min(abs(abs(rear_x) - shop_bay_half), min(abs(rear_y + .31), abs(rear_y - .36)));
        rear_jamb = 1.0 - smoothstep(.012, .035, edge);
    } else if (back && purpose == 2 && abs(rear_x - workshop_bay_center) < workshop_bay_half + .04 && rear_y > -.34 && rear_y < .36) {
        float edge = min(abs(abs(rear_x - workshop_bay_center) - workshop_bay_half),
                         min(abs(rear_y + .30), abs(rear_y - .32)));
        rear_jamb = 1.0 - smoothstep(.012, .034, edge);
    } else if (back && purpose == 4 && abs(rear_x) < civic_arch_half + .04 && rear_y < .39) {
        float vertical_edge = abs(abs(rear_x) - civic_arch_half);
        float arch_edge = abs(length(float2(rear_x / civic_arch_half, (rear_y - .16) / .19)) - 1.0) * .19;
        float edge = rear_y < .16 ? vertical_edge : arch_edge;
        rear_jamb = 1.0 - smoothstep(.012, .032, edge);
    } else if (back && purpose == 5 && rear_x < clinic_corridor_edge + .04 && rear_y > -.38 && rear_y < .42) {
        float edge = min(abs(rear_x - clinic_corridor_edge), min(abs(rear_y + .34), abs(rear_y - .38)));
        rear_jamb = 1.0 - smoothstep(.012, .034, edge);
    }
    if (rear_bay) {
        float recess_depth = room_height * (purpose == 5 ? .24 : (purpose == 0 ? .14 : .18)) *
                             lerp(.90, 1.10, form_variation_c);
        distance = (room_depth + recess_depth) / ray.z;
        hit = origin + ray * distance;
        room_hit = float3(hit.x / room_width, hit.y / room_height, hit.z / room_height);
        normalized_room_depth += recess_depth / room_height;
    }
    float3 purpose_color = srgb_to_linear(float3(.52, .38, .22));
    if (purpose == 1) purpose_color = srgb_to_linear(float3(.58, .40, .17));
    if (purpose == 2) purpose_color = srgb_to_linear(float3(.43, .37, .26));
    if (purpose == 3) purpose_color = srgb_to_linear(float3(.36, .37, .25));
    if (purpose == 4) purpose_color = srgb_to_linear(float3(.31, .42, .45));
    if (purpose == 5) purpose_color = srgb_to_linear(float3(.48, .54, .46));
    float3 unlit_back = lerp(input.color.rgb * float3(.23, .26, .25), purpose_color * .42, .35);
    float3 lit_back = purpose_color;
    float occupied = saturate(input.material.x);
    // Daylight entering through the pane keeps unlit rooms from collapsing
    // into identical blue rectangles. It remains deliberately weaker than an
    // occupied room's authored light.
    float daylight_ambient = saturate(push.sun.w) * .48; // indirect window fill
    float room_illumination = max(occupied, daylight_ambient);
    float3 back_color = lerp(unlit_back, lit_back, room_illumination);
    float3 room = back_color;
    if (horizontal) {
        bool floor_surface = side_y < 0.0;
        room *= floor_surface ? float3(.72, .66, .55) : float3(.34, .36, .37);
        if (floor_surface) {
            if (purpose <= 1) {
                // Long boards run into the room; staggered end joints keep the
                // perspective legible without producing diagonal striping.
                float board_frequency = purpose == 0 ? 7.0 : 5.0;
                float board_index = floor((room_hit.x + .5) * board_frequency + decor);
                float board_x = frac((room_hit.x + .5) * board_frequency + decor);
                float board_edge = 1.0 - smoothstep(.025, .065, min(board_x, 1.0 - board_x));
                float board_z = frac(room_hit.z * 3.2 + board_index * .43);
                float end_joint = 1.0 - smoothstep(.018, .05, min(board_z, 1.0 - board_z));
                room = lerp(room, room * .56, max(board_edge, end_joint * .52));
            } else if (purpose == 2) {
                // Large poured-concrete bays with restrained saw cuts.
                float2 joint_uv = frac(float2((room_hit.x + .5) * 2.4, room_hit.z * 2.0));
                float joint = 1.0 - smoothstep(.018, .055, min(min(joint_uv.x, 1.0 - joint_uv.x),
                                                               min(joint_uv.y, 1.0 - joint_uv.y)));
                room = lerp(room * float3(.76, .77, .73), room * .48, joint * .52);
            } else if (purpose == 3) {
                // Broad offset stone slabs suit a heavy storage floor.
                float slab_row = floor(room_hit.z * 3.0);
                float2 slab_uv = frac(float2((room_hit.x + .5) * 3.0 + slab_row * .5, room_hit.z * 3.0));
                float slab_edge = 1.0 - smoothstep(.025, .07, min(min(slab_uv.x, 1.0 - slab_uv.x),
                                                                  min(slab_uv.y, 1.0 - slab_uv.y)));
                room = lerp(room * float3(.73, .70, .61), room * .44, slab_edge * .62);
            } else {
                // Formal and clinical rooms use regular tile modules; the
                // civic floor is darker and subtly alternating.
                float tile_frequency = purpose == 4 ? 4.0 : 5.0;
                float2 tile_coord = float2((room_hit.x + .5) * tile_frequency, room_hit.z * tile_frequency);
                float2 tile_uv = frac(tile_coord);
                float tile_edge = 1.0 - smoothstep(.018, .055, min(min(tile_uv.x, 1.0 - tile_uv.x),
                                                                  min(tile_uv.y, 1.0 - tile_uv.y)));
                float checker = fmod(floor(tile_coord.x) + floor(tile_coord.y), 2.0);
                float tile_tone = purpose == 4 ? lerp(.78, .92, checker) : lerp(.91, 1.0, checker);
                room *= tile_tone;
                room = lerp(room, room * .50, tile_edge * .62);
            }
        } else if (purpose == 4) {
            float vault_band = frac(room_hit.z * 5.0 + decor * .35);
            float vault_rib = 1.0 - smoothstep(.025, .075, min(vault_band, 1.0 - vault_band));
            float vault_center_fill = 1.0 - saturate(abs(room_hit.x) * 1.7);
            room *= lerp(.86, 1.08, vault_center_fill);
            room = lerp(room, room * .46, vault_rib * .62);
        }
    } else if (!back) {
        // A gentle falloff along the side walls makes their depth legible even
        // when the view is nearly head-on.
        float wall_depth = saturate(room_hit.z / max(normalized_room_depth, .001));
        room *= lerp(float3(.68, .70, .67), float3(.48, .52, .52), wall_depth);
    } else {
        float2 wall_uv = room_hit.xy + .5;
        if (rear_bay) room *= .84;
        if (purpose == 0) {
            // Domestic plaster, low paneling, and one framed picture.
            float panel = smoothstep(.025, .055, abs(frac(wall_uv.x * 3.0) - .5));
            room *= lerp(.86, 1.04, panel);
            float picture_x = lerp(-.18, .20, decor);
            bool picture = abs(room_hit.x - picture_x) < .13 && abs(room_hit.y - .12) < .11;
            bool picture_inner = abs(room_hit.x - picture_x) < .105 && abs(room_hit.y - .12) < .085;
            room = picture ? lerp(room, srgb_to_linear(float3(.16, .11, .07)), .75) : room;
            room = picture_inner ? lerp(room, srgb_to_linear(float3(.30, .22, .14)), .72) : room;
        } else if (purpose == 1) {
            // Repeated shelves and small stock shapes read as a shop display.
            float shelf = 1.0 - smoothstep(.012, .025, min(abs(room_hit.y + .24), abs(room_hit.y + .02)));
            float stock = step(.52, frac(wall_uv.x * 9.0 + floor(wall_uv.y * 5.0) * .37 + decor));
            stock *= step(room_hit.y, .18) * step(-.28, room_hit.y);
            room = lerp(room, room * .48, shelf);
            room = lerp(room, srgb_to_linear(float3(.40, .22, .08)), stock * .34);
        } else if (purpose == 2) {
            // Pegboard points and a darker tool rail distinguish workshops.
            float2 peg = abs(frac(wall_uv * float2(13.0, 9.0)) - .5);
            float pegs = 1.0 - smoothstep(.08, .18, max(peg.x, peg.y));
            float rail = 1.0 - smoothstep(.012, .026, abs(room_hit.y - .04));
            float bench_back = 1.0 - smoothstep(-.18, -.14, room_hit.y);
            float tool_shift = lerp(-.055, .055, decor);
            bool long_tool = abs(room_hit.x + .22 - tool_shift) < .025 && room_hit.y > -.02 && room_hit.y < .30;
            bool short_tool = abs(room_hit.x - .02 - tool_shift) < .035 && room_hit.y > .02 && room_hit.y < .23;
            bool square_tool = abs(room_hit.x - .24 + tool_shift) < .065 && room_hit.y > .04 && room_hit.y < .16;
            room = lerp(room, room * .38, pegs * .58 + rail * .78);
            room = lerp(room, srgb_to_linear(float3(.12, .10, .075)), bench_back * .82);
            room = (long_tool || short_tool || square_tool) ?
                   lerp(room, srgb_to_linear(float3(.10, .085, .065)), .88) : room;
        } else if (purpose == 3) {
            // Offset crate fronts fill the lower storehouse wall.
            float2 crate_uv = frac(float2(wall_uv.x * 4.0 + floor(wall_uv.y * 4.0) * .5 + decor, wall_uv.y * 4.0));
            float crate_edge = smoothstep(.03, .08, min(min(crate_uv.x, 1.0 - crate_uv.x), min(crate_uv.y, 1.0 - crate_uv.y)));
            float crates = step(room_hit.y, .16);
            room *= lerp(.58, lerp(.72, 1.0, crate_edge), crates);
        } else if (purpose == 4) {
            // Restrained vertical paneling gives civic rooms a formal rhythm.
            float seam = 1.0 - smoothstep(.012, .028, abs(frac(wall_uv.x * 5.0) - .5));
            float dado = 1.0 - smoothstep(.012, .026, abs(room_hit.y + .16));
            room = lerp(room, room * .58, max(seam * .34, dado * .68));
            bool side_cabinet = abs(room_hit.x) > .31 && room_hit.y < .24 && room_hit.y > -.30;
            float crest_x = lerp(-.055, .055, decor);
            bool crest_frame = abs(room_hit.x - crest_x) < .12 && room_hit.y > .08 && room_hit.y < .27;
            bool crest_inner = abs(room_hit.x - crest_x) < .09 && room_hit.y > .105 && room_hit.y < .245;
            room = side_cabinet ? lerp(room, srgb_to_linear(float3(.10, .15, .16)), .76) : room;
            room = crest_frame ? lerp(room, srgb_to_linear(float3(.12, .10, .075)), .82) : room;
            room = crest_inner ? lerp(room, srgb_to_linear(float3(.30, .38, .38)), .72) : room;
        } else {
            // Pale washable wall bands and a compact cabinet suit a clinic.
            float tile_line = 1.0 - smoothstep(.01, .022, abs(frac((wall_uv.y + .08) * 6.0) - .5));
            room = lerp(room, room * .72, tile_line * step(room_hit.y, .12) * .45);
            bool cabinet_back = abs(room_hit.x + .27) < .12 && room_hit.y < .18 && room_hit.y > -.30;
            room = cabinet_back ? lerp(room, srgb_to_linear(float3(.20, .27, .24)), .62) : room;
        }

        // Shared trim gives every room a clear floor/wall and wall/ceiling
        // junction. These thin anchors survive when bespoke decor is occluded
        // by mullions or viewed through a small pane.
        float baseboard = 1.0 - smoothstep(.014, .032, abs(room_hit.y + .37));
        float cornice = 1.0 - smoothstep(.010, .026, abs(room_hit.y - .38));
        room = lerp(room, room * .48, max(baseboard, cornice * .55));
        room = lerp(room, srgb_to_linear(float3(.10, .085, .065)), rear_jamb * .74);
    }

    // A broad authored light pool gives occupied rooms a focal point and
    // keeps the back wall from reading as one uniformly emissive rectangle.
    if (back && occupied > 0.0) {
        float lamp_x = lerp(-.20, .20, decor);
        float2 lamp_delta = (room_hit.xy - float2(lamp_x, .24)) / float2(.34, .42);
        float lamp_pool = 1.0 - smoothstep(.18, 1.0, length(lamp_delta));
        float3 lamp_color = purpose == 5 ?
                            srgb_to_linear(float3(.58, .68, .61)) :
                            srgb_to_linear(float3(.72, .48, .24));
        room += lamp_color * lamp_pool * occupied * .24;
    }

    // Analytic corner occlusion anchors the virtual walls without another
    // texture lookup or ray. It also keeps unoccupied rooms convincingly dark.
    float depth_fraction = saturate(room_hit.z / max(normalized_room_depth, .001));
    float local_half_width = .5 * (1.0 + wall_taper * depth_fraction);
    float local_ceiling = .5 - ceiling_drop / max(room_height, .001) * depth_fraction;
    if (purpose == 4) {
        float vault_x = saturate(abs(room_hit.x) / max(local_half_width, .001));
        local_ceiling = .32 + .18 * sqrt(max(1.0 - vault_x * vault_x, 0.0));
    }
    float edge_x = max(local_half_width - abs(room_hit.x), 0.0);
    float edge_y = max(min(local_ceiling - room_hit.y, room_hit.y + .5), 0.0);
    float edge_z = max(min(room_hit.z, normalized_room_depth - room_hit.z), 0.0);
    float corner_distance = back ? min(edge_x, edge_y) :
                            (horizontal ? min(edge_x, edge_z) : min(edge_y, edge_z));
    float corner = smoothstep(.0, .14, corner_distance);
    room *= lerp(.42, 1.0, corner);

    // Furniture and internal structure use analytic box intersections. The
    // nearest solid face replaces the room boundary hit, so these objects have
    // real side/top faces and parallax instead of reading as dark cards.
    float solid_distance = distance;
    float3 solid_center = 0.0;
    float3 solid_half_extent = 1.0;
    float3 solid_color = purpose_color;
    float floor_y = -room_half_extent.y;
    if (purpose == 0) {
        float table_x = (dwelling_door_x < 0.0 ? .17 : -.17) * room_width;
        float3 center = float3(table_x, floor_y + room_height * .22, room_depth * .48);
        float3 half_extent = float3(room_width * .16, room_height * .022, room_depth * .12);
        float candidate = ray_box_distance(origin, ray, center, half_extent);
        if (candidate < solid_distance) {
            solid_distance = candidate;
            solid_center = center;
            solid_half_extent = half_extent;
            solid_color = srgb_to_linear(float3(.30, .17, .075));
        }
        for (int leg_index = 0; leg_index < 2; ++leg_index) {
            float leg_x = table_x + (leg_index == 0 ? -.115 : .115) * room_width;
            center = float3(leg_x, floor_y + room_height * .10, room_depth * .48);
            half_extent = float3(room_width * .018, room_height * .10, room_depth * .075);
            candidate = ray_box_distance(origin, ray, center, half_extent);
            if (candidate < solid_distance) {
                solid_distance = candidate;
                solid_center = center;
                solid_half_extent = half_extent;
                solid_color = srgb_to_linear(float3(.22, .12, .055));
            }
        }
    } else if (purpose == 1) {
        float counter_x = lerp(-.045, .045, form_variation_b) * room_width;
        float3 center = float3(counter_x, floor_y + room_height * .245, room_depth * .43);
        float3 half_extent = float3(room_width * .34, room_height * .025, room_depth * .11);
        float candidate = ray_box_distance(origin, ray, center, half_extent);
        if (candidate < solid_distance) {
            solid_distance = candidate;
            solid_center = center;
            solid_half_extent = half_extent;
            solid_color = srgb_to_linear(float3(.40, .25, .10));
        }
        for (int pedestal_index = 0; pedestal_index < 2; ++pedestal_index) {
            float pedestal_x = counter_x + (pedestal_index == 0 ? -.205 : .205) * room_width;
            center = float3(pedestal_x, floor_y + room_height * .105, room_depth * .45);
            half_extent = float3(room_width * .105, room_height * .105, room_depth * .075);
            candidate = ray_box_distance(origin, ray, center, half_extent);
            if (candidate < solid_distance) {
                solid_distance = candidate;
                solid_center = center;
                solid_half_extent = half_extent;
                solid_color = srgb_to_linear(float3(.31, .18, .07));
            }
        }
    } else if (purpose == 2) {
        float bench_x = lerp(-.08, .04, form_variation_a) * room_width;
        float3 center = float3(bench_x, floor_y + room_height * .225, room_depth * .46);
        float3 half_extent = float3(room_width * .33, room_height * .025, room_depth * .13);
        float candidate = ray_box_distance(origin, ray, center, half_extent);
        if (candidate < solid_distance) {
            solid_distance = candidate;
            solid_center = center;
            solid_half_extent = half_extent;
            solid_color = srgb_to_linear(float3(.15, .12, .075));
        }
        for (int leg_index = 0; leg_index < 2; ++leg_index) {
            float leg_x = bench_x + (leg_index == 0 ? -.27 : .27) * room_width;
            center = float3(leg_x, floor_y + room_height * .10, room_depth * .46);
            half_extent = float3(room_width * .025, room_height * .10, room_depth * .085);
            candidate = ray_box_distance(origin, ray, center, half_extent);
            if (candidate < solid_distance) {
                solid_distance = candidate;
                solid_center = center;
                solid_half_extent = half_extent;
                solid_color = srgb_to_linear(float3(.10, .085, .055));
            }
        }
    } else if (purpose == 3) {
        float3 deck_center = float3(0.0, floor_y + room_height * .72, room_depth * .58);
        float3 deck_half = float3(room_width * .43, room_height * .025, room_depth * .34);
        float candidate = ray_box_distance(origin, ray, deck_center, deck_half);
        if (candidate < solid_distance) {
            solid_distance = candidate;
            solid_center = deck_center;
            solid_half_extent = deck_half;
            solid_color = srgb_to_linear(float3(.25, .19, .09));
        }
        for (int support_index = 0; support_index < 2; ++support_index) {
            float support_x = (support_index == 0 ? -.37 : .37) * room_width;
            float3 support_center = float3(support_x, floor_y + room_height * .35, room_depth * .52);
            float3 support_half = float3(room_width * .022, room_height * .35, room_depth * .025);
            candidate = ray_box_distance(origin, ray, support_center, support_half);
            if (candidate < solid_distance) {
                solid_distance = candidate;
                solid_center = support_center;
                solid_half_extent = support_half;
                solid_color = srgb_to_linear(float3(.22, .16, .075));
            }
        }
        for (int crate_index = 0; crate_index < 4; ++crate_index) {
            float crate_column = float(crate_index % 2) - .5;
            float crate_row = float(crate_index / 2);
            float crate_jitter = frac(decor * (float(crate_index) + 3.7));
            float3 crate_half = float3(
                room_width * lerp(.105, .135, crate_jitter),
                room_height * lerp(.105, .14, frac(crate_jitter * 3.1)),
                room_depth * .09
            );
            float3 crate_center = float3(
                crate_column * room_width * .34 + lerp(-.025, .025, crate_jitter) * room_width,
                floor_y + crate_half.y,
                room_depth * (.30 + crate_row * .25)
            );
            candidate = ray_box_distance(origin, ray, crate_center, crate_half);
            if (candidate < solid_distance) {
                solid_distance = candidate;
                solid_center = crate_center;
                solid_half_extent = crate_half;
                solid_color = srgb_to_linear(float3(.34, .25, .11));
            }
        }
    } else if (purpose == 4) {
        float desk_x = lerp(-.035, .035, form_variation_c) * room_width;
        float3 center = float3(desk_x, floor_y + room_height * .245, room_depth * .43);
        float3 half_extent = float3(room_width * .29, room_height * .025, room_depth * .115);
        float candidate = ray_box_distance(origin, ray, center, half_extent);
        if (candidate < solid_distance) {
            solid_distance = candidate;
            solid_center = center;
            solid_half_extent = half_extent;
            solid_color = srgb_to_linear(float3(.10, .19, .19));
        }
        for (int pedestal_index = 0; pedestal_index < 2; ++pedestal_index) {
            float pedestal_x = desk_x + (pedestal_index == 0 ? -.19 : .19) * room_width;
            center = float3(pedestal_x, floor_y + room_height * .105, room_depth * .445);
            half_extent = float3(room_width * .075, room_height * .105, room_depth * .075);
            candidate = ray_box_distance(origin, ray, center, half_extent);
            if (candidate < solid_distance) {
                solid_distance = candidate;
                solid_center = center;
                solid_half_extent = half_extent;
                solid_color = srgb_to_linear(float3(.07, .14, .15));
            }
        }
    } else if (purpose == 5) {
        float3 center = float3(-room_width * .25, floor_y + room_height * .34, room_depth * .46);
        float3 half_extent = float3(room_width * .018, room_height * .34, room_depth * .13);
        float candidate = ray_box_distance(origin, ray, center, half_extent);
        if (candidate < solid_distance) {
            solid_distance = candidate;
            solid_center = center;
            solid_half_extent = half_extent;
            solid_color = srgb_to_linear(float3(.25, .38, .34));
        }
        float table_x = room_width * lerp(.10, .18, form_variation_a);
        center = float3(table_x, floor_y + room_height * .245, room_depth * .48);
        half_extent = float3(room_width * .23, room_height * .025, room_depth * .15);
        candidate = ray_box_distance(origin, ray, center, half_extent);
        if (candidate < solid_distance) {
            solid_distance = candidate;
            solid_center = center;
            solid_half_extent = half_extent;
            solid_color = srgb_to_linear(float3(.36, .48, .42));
        }
        for (int leg_index = 0; leg_index < 2; ++leg_index) {
            float leg_x = table_x + (leg_index == 0 ? -.17 : .17) * room_width;
            center = float3(leg_x, floor_y + room_height * .11, room_depth * .48);
            half_extent = float3(room_width * .022, room_height * .11, room_depth * .09);
            candidate = ray_box_distance(origin, ray, center, half_extent);
            if (candidate < solid_distance) {
                solid_distance = candidate;
                solid_center = center;
                solid_half_extent = half_extent;
                solid_color = srgb_to_linear(float3(.20, .29, .25));
            }
        }
    }
    if (solid_distance < distance) {
        float3 solid_hit = origin + ray * solid_distance;
        float3 box_position = (solid_hit - solid_center) / max(solid_half_extent, float3(.0001));
        float3 box_axis = abs(box_position);
        float3 box_normal = 0.0;
        if (box_axis.x > box_axis.y && box_axis.x > box_axis.z) {
            box_normal.x = box_position.x < 0.0 ? -1.0 : 1.0;
        } else if (box_axis.y > box_axis.z) {
            box_normal.y = box_position.y < 0.0 ? -1.0 : 1.0;
        } else {
            box_normal.z = box_position.z < 0.0 ? -1.0 : 1.0;
        }
        float largest_axis = max(box_axis.x, max(box_axis.y, box_axis.z));
        float smallest_axis = min(box_axis.x, min(box_axis.y, box_axis.z));
        float second_axis = box_axis.x + box_axis.y + box_axis.z - largest_axis - smallest_axis;
        float box_edge = smoothstep(.82, .98, second_axis);
        float face_light = .58 + max(box_normal.y, 0.0) * .28 + max(-box_normal.z, 0.0) * .12;
        float solid_depth = saturate(solid_hit.z / max(room_depth, .001));
        room = solid_color * face_light * lerp(1.0, .72, solid_depth);
        room *= lerp(1.0, .62, box_edge);
    }

    // Thin textiles and task-light profiles remain on an intermediate plane;
    // all substantial furniture above is volumetric.
    float slice_z = room_depth * lerp(.28, .56, decor);
    float slice_t = slice_z / ray.z;
    float2 slice_hit = origin.xy + ray.xy * slice_t;
    float2 room_slice_hit = slice_hit / float2(room_width, room_height);
    float visible_distance = min(distance, solid_distance);
    bool slice_inside = slice_t < visible_distance && all(abs(room_slice_hit) < float2(.49, .49));
    float curtain_position = abs(room_slice_hit.x + lerp(-.025, .025, decor));
    bool dwelling_curtain = purpose == 0 && curtain_position > .385 && curtain_position < .485 &&
                             room_slice_hit.y > -.38;
    bool workshop_lamp_stem = purpose == 2 && abs(room_slice_hit.x - .18) < .014 &&
                              room_slice_hit.y > -.06 && room_slice_hit.y < .13;
    bool workshop_lamp_head = purpose == 2 &&
                              length((room_slice_hit - float2(.15, .15)) / float2(.075, .04)) < 1.0;
    bool workshop_lamp = workshop_lamp_stem || workshop_lamp_head;
    bool silhouette_shape = dwelling_curtain || workshop_lamp;
    float silhouette = slice_inside && silhouette_shape ? 1.0 : 0.0;
    float3 furniture_color = srgb_to_linear(float3(.25, .10, .075));
    if (workshop_lamp) furniture_color = srgb_to_linear(float3(.13, .11, .075));
    room = lerp(room, furniture_color * lerp(.46, 1.05, room_illumination), silhouette * .88);

    // Purpose-specific fixtures sit on the intermediate plane, so they shift
    // against the back wall as the camera moves. Shops use paired lamps,
    // workshops a broad metal shade, storehouses a bare bulb, civic rooms a
    // globe, and clinics a compact fluorescent bar.
    float fixture_x = lerp(-.16, .16, decor);
    if (purpose == 1) fixture_x = room_slice_hit.x < 0.0 ? -.20 : .20;
    float shade_width = purpose == 2 ? .11 : .105;
    float shade_height = purpose == 2 ? .045 : .065;
    bool fixture_cord = purpose < 5 && abs(room_slice_hit.x - fixture_x) < .012 &&
                        room_slice_hit.y > .24 && room_slice_hit.y < .49;
    float2 shade_delta = (room_slice_hit - float2(fixture_x, .22)) / float2(shade_width, shade_height);
    bool fixture_shade = purpose < 3 && length(shade_delta) < 1.0 && room_slice_hit.y > .20;
    float2 bulb_delta = (room_slice_hit - float2(fixture_x, .175)) / float2(.035, .045);
    bool fixture_bulb = purpose <= 3 && length(bulb_delta) < 1.0;
    float2 globe_delta = (room_slice_hit - float2(fixture_x, .20)) / float2(.036, .048);
    bool civic_globe = purpose == 4 && length(globe_delta) < 1.0;
    bool clinic_bar = purpose == 5 && abs(room_slice_hit.x) < .19 &&
                      abs(room_slice_hit.y - .25) < .028;
    if (slice_inside && (fixture_cord || fixture_shade)) {
        room = lerp(room, srgb_to_linear(float3(.09, .075, .055)), .86);
    }
    if (slice_inside && (fixture_bulb || civic_globe || clinic_bar) && occupied > 0.0) {
        float3 bulb_color = purpose == 5 ?
                            srgb_to_linear(float3(.66, .82, .76)) :
                            srgb_to_linear(float3(1.0, .70, .34));
        room = lerp(room, bulb_color, occupied * (civic_globe ? .58 : .82));
    }

    // Interior mapping degrades at grazing angles; blend smoothly back to the
    // established flat pane instead of allowing the virtual box to stretch.
    float grazing_fade = smoothstep(.06, .24, facing);
    return lerp(input.color.rgb * .32, room, grazing_fade);
}

float3 shade_glass(VertexOutput input) {
    float3 normal = normalize(input.normal);
    float3 view = normalize(push.camera_position.xyz - input.world_position);
    float facing = saturate(dot(normal, view));
    float fresnel = pow(1.0 - facing, 3.0);
    float daylight = saturate(push.sun.w);
    float horizon = saturate(normalize(view).y * .5 + .5);
    float3 sky_blue = srgb_to_linear(float3(.43, .68, .78));
    float3 sky_pale = srgb_to_linear(float3(.78, .89, .87));
    float3 reflected_sky = lerp(sky_blue, sky_pale, horizon);

    // Broad painted shapes read more clearly than a physically perfect
    // reflection at the small on-screen size of most façade panes.
    float diagonal = input.uv.x * .72 + input.uv.y;
    float sheen = smoothstep(.46, .58, diagonal) *
                  (1.0 - smoothstep(.64, .78, diagonal));
    float upper_glow = 1.0 - smoothstep(.08, .62, input.uv.y);
    float pane_variation = value_noise(
        floor(input.world_position.xy * .37) + input.world_position.z * .11
    );
    reflected_sky *= lerp(.88, 1.08, pane_variation);
    reflected_sky += srgb_to_linear(float3(.86, .95, .91)) *
                     (sheen * .38 + upper_glow * .14);

    float interior_light = saturate(input.material.x);
    float night = 1.0 - smoothstep(.0, .34, daylight);
    float3 interior = input.material.y > .5 ? shade_window_room(input, view, facing) : input.color.rgb;
    // Residential panes need a clearly readable opaque sky body even when
    // viewed head-on. Storefront and occupied panes retain more of their
    // authored interior color.
    float reflection_weight = lerp(.78, .90, fresnel);
    if (input.material.y > .5) {
        // Interior-mapped panes need enough transmission for the virtual
        // walls to read head-on, while grazing views remain sky-dominant.
        reflection_weight = lerp(.16, .84, fresnel);
    }
    float occupied_reflection = input.material.y > .5 ?
                                lerp(.28, .86, fresnel) :
                                lerp(.62, .82, fresnel);
    reflection_weight = lerp(reflection_weight, occupied_reflection, interior_light);
    reflection_weight *= lerp(1.0, .32, interior_light * night);
    float3 color = lerp(interior, reflected_sky, reflection_weight);
    if (interior_light > 0.0) {
        // Interior light should remain a warm source without clipping into a
        // flat yellow card. Reflections and authored pane detail retain enough
        // headroom to describe actual glass.
        color += interior * interior_light * lerp(.06, .22, night);
    }
    float visibility = dynamic_shadow_visibility(input.world_position, normal);
    color *= lerp(.86, 1.0, visibility);
    return saturate(color);
}

float3 shade_eye(VertexOutput input) {
    float3 normal = normalize(input.normal);
    float3 view_direction = normalize(push.camera_position.xyz - input.world_position);
    // A camera-relative studio light keeps the small corneal glint on the
    // upper-left shoulder from every gameplay angle without separate geometry.
    float3 highlight_direction = normalize(
        view_direction + push.camera_up.xyz * .30 - push.camera_right.xyz * .22
    );
    float highlight_alignment = saturate(dot(normal, highlight_direction));
    float broad_gloss = pow(highlight_alignment, 18.0) * .12;
    float sharp_glint = pow(highlight_alignment, 92.0) * .94;
    float rim = pow(1.0 - saturate(dot(normal, view_direction)), 3.0) * .08;
    float3 highlight_color = srgb_to_linear(float3(1.0, .94, .78));
    BrdfMaterial material;
    material.base_color = input.color.rgb;
    material.metallic = 0;
    material.roughness = .16;
    float3 body = shade_brdf(material, normal, input.world_position);
    return saturate(body * (1.0 + rim) +
                    highlight_color * (broad_gloss + sharp_glint));
}

float3 shade_acorn(VertexOutput input) {
    float3 normal = normalize(input.normal);
    float rows = 10.0;
    float columns = 18.0;
    float row = floor(input.uv.y * rows);
    float2 cell = float2(
        frac(input.uv.x * columns + fmod(row, 2.0) * .5) - .5,
        frac(input.uv.y * rows) - .5
    );
    // Acorn cups are covered in overlapping scutes rather than circular
    // dimples. Widen each cell toward its upper edge and taper it toward the
    // lower edge to produce a small shield/teardrop shape.
    float vertical = cell.y + .5;
    float half_width = lerp(.12, .43, smoothstep(0.0, .72, vertical));
    float2 shield = float2(
        cell.x / max(half_width, .001),
        cell.y / .48
    );
    float shield_radius_squared = dot(shield, shield);
    float inside = saturate(1.0 - shield_radius_squared);
    inside = inside * inside * (3.0 - 2.0 * inside);
    // A rounded raised center suggests one woody scute overlapping the next
    // row without changing any vertex positions.
    float2 slope = float2(
        -shield.x * inside * columns * .070,
        -shield.y * inside * rows * .090
    );
    float3 tangent = normalize(float3(-normal.z, 0.0, normal.x));
    float3 bitangent = normalize(cross(normal, tangent));
    normal = normalize(normal + tangent * slope.x + bitangent * slope.y);

    BrdfMaterial material;
    material.base_color = input.color.rgb;
    material.metallic = 0;
    material.roughness = .64;
    float3 body = shade_brdf(material, normal, input.world_position);
    float3 view_direction =
        normalize(push.camera_position.xyz - input.world_position);
    float3 soft_key_direction = normalize(
        view_direction + push.camera_up.xyz * .78 -
        push.camera_right.xyz * .58
    );
    float soft_key = saturate(dot(normal, soft_key_direction));
    return body * (.82 + soft_key * .48);
}

float3 shade_bottle_cap(VertexOutput input) {
    float3 normal = normalize(input.normal);
    float circumference = atan2(normal.z, normal.x) * (21.0 / 6.2831853);
    float flute = pow(abs(cos(circumference * 3.14159265)), 5.0);
    float skirt = 1.0 - smoothstep(.38, .58, input.material.x);
    float shoulder = smoothstep(.32, .50, input.material.x) *
                     (1.0 - smoothstep(.62, .78, input.material.x));
    float pressed = sin(circumference * 6.2831853) * skirt * .13;
    float3 tangent = normalize(float3(-normal.z, 0.0, normal.x));
    normal = normalize(normal + tangent * pressed);

    // Closely spaced rolled-metal striations and a calmer stamped crown give
    // the connected mesh surface detail without adding decal geometry.
    float fine_ridges = .86 + .14 * pow(abs(sin(circumference * 12.56637)), 7.0);
    float crown_brush = .97;
    float texture_value = lerp(crown_brush, fine_ridges, skirt);
    texture_value *= lerp(.90, 1.12, flute * skirt);
    texture_value *= lerp(1.0, 1.08, shoulder);

    float3 metal_color = input.color.rgb * texture_value;
    float3 logo_color = soda_cap_logo.Sample(soda_cap_logo_sampler, input.uv).rgb;
    float top_print = smoothstep(.52, .66, input.material.x);
    float3 base_color = lerp(metal_color, logo_color, top_print);

    BrdfMaterial material;
    material.base_color = base_color;
    material.metallic = .34;
    material.roughness = .42;
    return shade_brdf(material, normal, input.world_position);
}

float3 shade_sailor_hat(VertexOutput input) {
    float3 normal = normalize(input.normal);

    // Two navy bands are printed into the UV-mapped cloth. Feathered edges
    // keep them from aliasing as the tiny hat recedes from the camera.
    float stripe_one =
        smoothstep(.285, .300, input.uv.y) *
        (1.0 - smoothstep(.340, .355, input.uv.y));
    float stripe_two =
        smoothstep(.475, .490, input.uv.y) *
        (1.0 - smoothstep(.540, .555, input.uv.y));
    float stripe = saturate(stripe_one + stripe_two);
    float3 canvas = input.color.rgb;
    float3 navy = srgb_to_linear(float3(38.0, 88.0, 145.0) / 255.0);

    // Fine crossing warp and weft provide a restrained woven texture without
    // introducing geometry or swimming world-space noise.
    float warp = .5 + .5 * sin(input.uv.x * 24.0 * 6.2831853);
    float weft = .5 + .5 * sin(input.uv.y * 72.0 * 6.2831853);
    float weave = lerp(.975, 1.025, warp * weft);
    float3 fabric = lerp(canvas, navy, stripe) * weave;

    BrdfMaterial material;
    material.base_color = fabric;
    material.metallic = 0;
    material.roughness = .86;
    return shade_brdf(material, normal, input.world_position);
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

float3 shade_terrain_dunes(VertexOutput input, float3 color) {
    if (input.material.x >= -.001) return color;

    float2 p = input.world_position.xz;
    float broad =
        sin(p.x * .018 + p.y * .029 + .7) *
        sin(p.x * -.027 + p.y * .014 + 2.1);
    float local =
        sin(p.x * .071 + p.y * -.043 + 1.3) *
        sin(p.x * .039 + p.y * .083 + 2.8);
    float ripple =
        sin(p.x * .19 + p.y * .081 + broad * .8) *
        sin(p.x * -.047 + p.y * .16 + .4);
    float field = broad * .58 + local * .29 + ripple * .13;

    // World-position evaluation keeps this drawing independent of clipmap
    // topology. Fade the highest-frequency contrast as the pixel footprint
    // grows so distant rings converge without shimmer.
    float footprint = max(
        length(ddx(input.world_position)),
        length(ddy(input.world_position))
    );
    float visibility = 1.0 - smoothstep(1.2, 6.0, footprint);
    float variation = field * lerp(.42, 1.0, visibility);
    float warm = max(variation, 0.0);
    float cool = max(-variation, 0.0);
    color *= 1.0 + variation * float3(.035, .025, .018);
    color += float3(warm * .010, warm * .0045, cool * .007);

    // The generated material extends below -1 only through the swash zone.
    // Saturated sand is cooler and darker than the dry beach, creating a
    // readable intermediate band before the water shader's aerated edge.
    // This uses ecology/bathymetry data rather than a world-height threshold,
    // so raised sea levels and edited shore profiles retain the same response.
    float wetness = saturate(-input.material.x - 1.0);
    float wet_patch = value_noise(rotate2(p, -.27) / 4.8 + float2(-2.4, 6.1));
    float3 wet_sand = color * float3(.72, .76, .70);
    wet_sand += float3(.012, .018, .015) * wet_patch;
    color = lerp(color, wet_sand, wetness * .78);

    // Dry exposed sand carries shallow transverse wind ripples. Keep them
    // sub-material rather than geometry, and fade them before their wavelength
    // approaches the pixel footprint so map views never shimmer.
    float2 wind = normalize(float2(.18, .98));
    float2 across = float2(-wind.y, wind.x);
    float ripple_phase =
        dot(p, across) * 7.4 +
        sin(dot(p, wind) * .31 + field * .7) * .58;
    float ripple_wave = sin(ripple_phase);
    float ripple_crest = smoothstep(.72, .96, ripple_wave);
    float ripple_trough = 1.0 - smoothstep(-.96, -.70, ripple_wave);
    float ripple_visibility = 1.0 - smoothstep(.18, 1.05, footprint);
    float active_sand = smoothstep(.22, .88, -input.material.x);
    float ripple_patch = smoothstep(
        .30,
        .76,
        value_noise(rotate2(p, .41) / 5.5 + float2(3.7, -1.2))
    );
    float ripple_weight =
        active_sand *
        (1.0 - wetness) *
        ripple_visibility *
        lerp(.18, 1.0, ripple_patch);
    color *= lerp(.990, 1.012, ripple_crest * ripple_weight);
    color *= lerp(1.0, .986, ripple_trough * ripple_weight);

    float3 normal = normalize(input.normal);
    float3 light = normalize(float3(-.45, .85, -.3));
    float shade = clamp(.48 + max(dot(normal, light), 0.0) * .52, .42, 1.05);
    color *= shade;
    return saturate(color);
}

float3 shade_terrain_limestone(VertexOutput input, float3 color) {
    float cliff = smoothstep(.08, .72, input.material.y);
    if (cliff <= .001) return color;

    float2 world = input.world_position.xz;
    float3 normal = normalize(input.normal);
    float face_u = abs(normal.x) > abs(normal.z) ? world.y : world.x;
    float2 face = float2(face_u, input.world_position.y);
    float patch = value_noise(rotate2(world, .31) / 38.0 + float2(4.1, -2.7));
    float detail = value_noise(rotate2(world, -.58) / 11.0 + float2(8.3, 2.7));

    // Estimate the world-space pixel footprint. Large panels remain visible
    // from the overview while the sparse drawing disappears before it aliases.
    float footprint = max(length(ddx(input.world_position)), length(ddy(input.world_position)));
    float fine_visibility = 1.0 - smoothstep(.75, 4.5, footprint);

    // Broad, face-oriented mineral panels replace continuous fine bedding.
    // Elevation is the vertical axis, so near-vertical walls do not compress
    // world-XZ paint into dense contour stripes.
    float2 panel_warp = face + float2((patch - .5) * 5.2, (detail - .5) * 3.4);
    float2 panel_cell = floor(panel_warp / float2(12.0, 8.0));
    float panel_id = hash12(panel_cell);
    float slab_mass = value_noise(face / float2(19.0, 14.0) + float2(2.7, -5.1));
    float slab_plane =
        smoothstep(.36, .53, slab_mass) -
        smoothstep(.68, .82, slab_mass);
    float slab_lee = smoothstep(
        .55,
        .75,
        value_noise(face / float2(27.0, 18.0) + float2(-4.3, 6.7))
    );

    float3 limestone = color;
    limestone *= lerp(.92, 1.08, panel_id);
    limestone *= lerp(.91, 1.08, slab_plane);
    limestone = lerp(limestone, color * .82, slab_lee * .24);
    limestone *= lerp(.95, 1.04, detail);

    // Two broken diagonal fracture families and their occasional pale chipped
    // shoulders provide drawing without turning the entire face into stripes.
    float fracture_a =
        frac(dot(face, normalize(float2(.82, .57))) / 14.0 + (patch - .5) * .16);
    float fracture_b =
        frac(dot(face, normalize(float2(-.91, .42))) / 19.0 + (detail - .5) * .12);
    float fracture_gate_a = smoothstep(
        .48,
        .68,
        value_noise(face / 13.0 + float2(.7, 3.1))
    );
    float fracture_gate_b = smoothstep(
        .60,
        .77,
        value_noise(face / 16.0 + float2(-5.3, 1.1))
    );
    float seam_a =
        (1.0 - smoothstep(.012, .040, abs(fracture_a - .5))) *
        fracture_gate_a * fine_visibility;
    float seam_b =
        (1.0 - smoothstep(.010, .035, abs(fracture_b - .5))) *
        fracture_gate_b * fine_visibility;
    float chipped_shoulder =
        (1.0 - smoothstep(.018, .060, abs(fracture_a - .445))) *
        fracture_gate_a * fine_visibility;

    // Widely spaced ledges are slightly warped and broken into runs. Sparse
    // vertical joints settle into the same cool mineral shadow.
    float stratigraphic_height =
        input.world_position.y + world.x * .012 + (patch - .5) * 1.6;
    float ledge_phase = frac(stratigraphic_height / 5.5);
    float ledge_distance = min(ledge_phase, 1.0 - ledge_phase);
    float ledge_segment = smoothstep(
        .54,
        .72,
        value_noise(world / 15.0 + float2(7.3, -4.1))
    );
    float recessed_ledge =
        (1.0 - smoothstep(.016, .065, ledge_distance)) *
        ledge_segment * fine_visibility;
    float joint_phase = abs(frac((face_u + (patch - .5) * 3.0) / 9.0) - .5);
    float joint_segment = smoothstep(
        .60,
        .76,
        value_noise(world / 12.0 + float2(-1.9, 8.3))
    );
    float joint_stain =
        (1.0 - smoothstep(.445, .490, joint_phase)) *
        joint_segment * fine_visibility;

    float mineral_shadow =
        saturate(seam_a * .72 + seam_b * .52 +
                 recessed_ledge * .76 + joint_stain * .46);
    limestone = lerp(
        limestone,
        limestone * float3(.62, .69, .65),
        mineral_shadow
    );
    limestone = lerp(
        limestone,
        limestone * float3(1.16, 1.12, 1.02),
        chipped_shoulder * .28
    );

    float3 result = lerp(color, limestone, cliff);
    // A selective dark-green break makes the turf cap readable without
    // outlining clipmap triangles or ordinary rolling ground.
    float rim_profile =
        1.0 - smoothstep(.035, .10, abs(input.material.y - .52));
    float rim_break = lerp(
        .70,
        1.0,
        smoothstep(.36, .68, value_noise(world / 7.0 + float2(2.9, 1.7)))
    );
    float3 turf_rim = srgb_to_linear(float3(.10, .18, .105));
    return lerp(result, turf_rim, rim_profile * rim_break * .38);
}

float3 shade_foliage(VertexOutput input) {
    float3 normal = normalize(input.normal);
    float3 geometric_normal = normal;
    float3 to_camera = push.camera_position.xyz - input.world_position;
    float view_distance = length(to_camera);
    // Close foliage needs calm body shading and fine marks; broad graphic
    // groups become progressively stronger as crowns recede and merge into a
    // forest composition.
    float broad_group_weight = smoothstep(180.0, 420.0, view_distance);
    // Broad, continuous noise bends the interpolated dome normal into leafy
    // bunches without revealing the underlying six-sided lobe topology.
    // Skewed three-axis projections wrap the painted groups around crown
    // shoulders. A plain XZ projection stretches patches into vertical
    // curtains when trees are viewed near eye level.
    float2 bunch_uv = float2(
        dot(input.world_position, float3(.066, .031, .018)),
        dot(input.world_position, float3(-.021, .044, .061))
    );
    float2 detail_uv = float2(
        dot(input.world_position, float3(.119, -.038, .091)),
        dot(input.world_position, float3(.047, .137, -.073))
    );
    float bunch = value_noise(bunch_uv + float2(0, -.37));
    float bunch_detail = value_noise(detail_uv + float2(2.7, .41));
    float angle = bunch * 6.2831853 + bunch_detail * 1.7;
    float3 normal_wobble = float3(cos(angle), (bunch_detail - .5) * .72, sin(angle));
    // Let the synthetic leafy bunches lead the body lighting. A weaker blend
    // allowed the interpolated ring normal to form long triangular highlight
    // ribbons at eye level, revealing tessellation instead of leaf volume.
    // The untouched geometric normal still drives the restrained silhouette
    // rim below, so this does not flatten the crown's overall form.
    normal = normalize(normal + normal_wobble * lerp(.34, .42, broad_group_weight));

    float3 sun_direction = normalize(push.sun.xyz);
    float wrapped_light = saturate(dot(normal, sun_direction) * .5 + .5);
    float top_light = saturate(normal.y * .5 + .5);
    float cluster_value = bunch * .76 + bunch_detail * .24;
    // A steeper light curve gives the canopy painterly value grouping: deep
    // pockets between bunches, a clear body midtone, and restrained hot crowns.
    float directional = pow(wrapped_light, 1.65);
    // Two soft thresholds turn continuous noise into a few broad painted
    // families instead of evenly distributed foam. Dark pockets stay sparse,
    // most of the crown holds one calm midtone, and only selected planes lift.
    float pocket_group = smoothstep(.27, .45, cluster_value);
    float mid_group = smoothstep(.42, .56, cluster_value);
    float crown_group = smoothstep(.65, .82, cluster_value);
    float distant_grouped_value = .79 + pocket_group * .19 + crown_group * .14;
    // Block the close canopy into a few painted value bands instead of a smooth
    // gradient, the way a background painter stacks flat shapes: a deep pocket,
    // a broad body, a lifted mid, and a restrained hot crown. The stepped sum
    // keeps the same mean exposure as the former lerp while reading as grouped
    // planes rather than a continuous chalky surface.
    float close_grouped_value =
        .74 + pocket_group * .18 + mid_group * .12 + crown_group * .16;
    float grouped_value = lerp(close_grouped_value, distant_grouped_value, broad_group_weight);
    float value = (.40 + directional * .66 + top_light * .07) * grouped_value;


    // Separate light by color as well as value. Cool blue-green pockets make
    // overlapping bunches recede while a restrained yellow warmth joins the
    // sun-facing leaves into broad, readable crowns.
    // A crisper transition and a wider temperature spread push the canopy
    // toward a hand-painted read: teal-leaning shade against distinctly warm,
    // yellow sun-facing leaves.
    float light_group = smoothstep(.28, .76, directional);
    float3 shadow_temperature = float3(.62, .82, .92);
    float3 sun_temperature = float3(1.20, 1.06, .70);
    float3 temperature = lerp(shadow_temperature, sun_temperature, light_group);

    // Sparse leaf-shaped dry-brush marks add a readable middle scale between
    // the broad value masses and the atlas fringe. The skewed world projection
    // wraps across both crown and shoulder without UVs, while two related
    // ellipses read as a tiny leaf pair rather than a regular polka-dot grid.
    float2 brush_uv = float2(
        dot(input.world_position, float3(.410, .148, .116)),
        dot(input.world_position, float3(-.104, .184, .436))
    );
    float2 brush_cell = floor(brush_uv);
    float2 brush_local = frac(brush_uv) - .5;
    float brush_seed = hash12(brush_cell + float2(13.7, 4.1));
    float brush_angle = brush_seed * 6.2831853;
    brush_local = rotate2(brush_local, brush_angle);
    float leaf_a = 1.0 - smoothstep(.13, .255, length(brush_local * float2(.72, 1.85)));
    float2 paired_local = brush_local - float2(.17, -.09);
    float leaf_b = 1.0 - smoothstep(.11, .225, length(paired_local * float2(.76, 1.72)));
    float brush_pair = max(leaf_a, leaf_b * .78);
    float brush_presence = smoothstep(.62, .78, brush_seed);
    float brush_cluster = smoothstep(.43, .70, cluster_value);
    // Painted leaf accents belong mostly on planes that catch sky or sun.
    // Suppressing them in deep side planes prevents the paired ellipses from
    // turning into dark vertical scratches across an otherwise calm crown.
    float brush_light = lerp(.22, 1.0, smoothstep(.25, .78, wrapped_light));
    float brush_sky = lerp(.48, 1.0, smoothstep(.34, .76, top_light));
    float brush_mask =
        brush_pair * brush_presence * brush_cluster * brush_light * brush_sky;
    float close_detail_weight = 1.0 - broad_group_weight;
    // A painted leaf bunch needs a dark socket as well as a bright dab. Offset
    // a wider, softer echo beneath each selected pair so the mark reads as
    // overlapping foliage instead of a pale spot printed onto the surface.
    // The same wrapped projection and random rotation keep these shadows
    // attached to the crown around its shoulders, while the distance fade
    // prevents dense forests from turning into high-frequency noise.
    float2 socket_local = brush_local + float2(-.018, .15);
    float socket_a =
        1.0 - smoothstep(.15, .30, length(socket_local * float2(.68, 1.58)));
    float2 socket_pair_local = socket_local - float2(.18, -.075);
    float socket_b =
        1.0 - smoothstep(.13, .27, length(socket_pair_local * float2(.72, 1.48)));
    float socket_pair = max(socket_a, socket_b * .82);
    float socket_mask =
        socket_pair *
        brush_presence *
        smoothstep(.31, .64, cluster_value) *
        lerp(.44, .93, smoothstep(.18, .70, wrapped_light)) *
        close_detail_weight;
    value *= lerp(1.0, .84, socket_mask * .58);

    // These are dry-brushed glints, not holes in the mass. Keep every mark at
    // or above the local body value and let lighting decide how bright it gets.
    float brush_value = lerp(1.025, 1.27, hash12(brush_cell + float2(2.3, 19.1)));
    float brush_influence = lerp(.36, .72, close_detail_weight);
    value *= lerp(1.0, brush_value, brush_mask * brush_influence);
    float3 brush_temperature = lerp(float3(.76, .91, 1.06), float3(1.15, 1.08, .80), light_group);
    temperature *= lerp(
        float3(1.0),
        brush_temperature,
        brush_mask * lerp(.20, .46, close_detail_weight)
    );

    // Wind should change the painted light as well as displace the mesh.
    // Two broad, wind-aligned phases travel across only sky-facing, lit
    // bunches, producing a restrained leaf shimmer rather than full-canopy
    // flashing or high-frequency glitter.
    float wind_speed = length(push.water.zw);
    float2 wind_direction =
        wind_speed > .001 ? push.water.zw / wind_speed : float2(1, 0);
    float shimmer_phase =
        dot(input.world_position.xz, wind_direction) * .052 -
        push.water.x * (.54 + wind_speed * .024) +
        bunch * 1.73;
    float shimmer_wave =
        sin(shimmer_phase) * .67 +
        sin(shimmer_phase * .47 + 2.1) * .33;
    float shimmer_exposure =
        smoothstep(.40, .82, wrapped_light) *
        smoothstep(.38, .78, top_light) *
        saturate(wind_speed / 10.0) *
        saturate(push.sun.w);
    value *= 1.0 + shimmer_wave * shimmer_exposure * .042;

    float3 color = input.color.rgb * temperature * value;

    // A light-story woodland should retain colored air beneath the crown
    // instead of collapsing into a black ceiling. Downward-facing leaves pick
    // up a restrained blue-green ground-and-sky bounce, broken by the same
    // bunch field as the body shading so overlapping boughs remain readable.
    // Daylight gating preserves the night hierarchy and the small additive
    // term leaves sunlit crown contrast intact.
    float underside = smoothstep(.08, .82, -geometric_normal.y);
    float daylight = saturate(push.sun.w);
    float bounce_group = lerp(.46, 1.0, smoothstep(.24, .76, cluster_value));
    float bounce_amount = underside * daylight * bounce_group;
    color += float3(.012, .027, .025) * bounce_amount;

    // Thin canopy edges catch warm light even when the body remains a grouped
    // painted mass. A view rim exposes the silhouette, sun-facing edges receive
    // a restrained lift, and back-facing edges get a small transmitted glow.
    // Daylight gating keeps twilight and night foliage from self-illuminating.
    float3 view_direction = normalize(to_camera);
    float view_facing = saturate(abs(dot(geometric_normal, view_direction)));
    float rim = pow(1.0 - view_facing, 1.45);
    float sun_rim = rim * smoothstep(.48, .84, wrapped_light);
    float transmission = rim * pow(saturate(-dot(normal, sun_direction)), 1.45);
    float edge_cluster = lerp(.72, 1.0, cluster_value);
    // A soft darker perimeter blocks the crown in as a shape, the way a painter
    // draws a canopy mass. It peaks exactly edge-on and is applied before the
    // warm rim and backlit transmission below, so sun-facing and back-facing
    // edges still glow rather than reading as a flat dark line.
    float outline = smoothstep(.34, .06, view_facing);
    color *= lerp(1.0, .60, outline * edge_cluster * daylight);
    color *= 1.0 + sun_rim * daylight * edge_cluster * .27;
    color += float3(.125, .096, .018) *
             transmission * daylight * edge_cluster * .54;

    return saturate(color);
}

// Thin botanical surfaces have no meaningful volume at world scale. Treat
// them as two-sided diffuse sheets and add colored forward scattering when
// the sun is behind them. Petals transmit more light and spread it more
// broadly than chlorophyll-dense leaves.
float3 shade_thin_transmission(VertexOutput input, bool petal) {
    float3 view_direction =
        normalize(push.camera_position.xyz - input.world_position);
    float3 geometric_normal = normalize(input.normal);
    float3 normal = geometric_normal;
    if (dot(normal, view_direction) < 0.0) normal = -normal;

    float3 sun_direction = normalize(push.sun.xyz);
    float front_light = saturate(dot(normal, sun_direction));
    float back_light = saturate(dot(-normal, sun_direction));
    float daylight = saturate(push.sun.w);
    // Shadow bias must use the sun-facing side of a two-sided sheet. Using the
    // view-facing normal makes the bias change sign as the camera crosses it.
    float3 shadow_normal = geometric_normal;
    if (dot(shadow_normal, sun_direction) < 0.0) shadow_normal = -shadow_normal;
    float visibility =
        dynamic_shadow_visibility(input.world_position, shadow_normal);

    float wrap = saturate((dot(normal, sun_direction) + .42) / 1.42);
    float body_light =
        .24 + wrap * .50 * visibility * lerp(.32, 1.0, daylight);
    float transmission_strength = petal ? .72 : .48;
    // Favor light travelling through the sheet toward the viewer, but retain
    // enough broad scatter for thin silhouettes to read away from exact solar
    // alignment.
    float forward_scatter =
        lerp(.38, 1.0, pow(saturate(dot(view_direction, -sun_direction)), petal ? 1.5 : 2.2));
    float transmission =
        pow(back_light, petal ? 1.35 : 1.8) *
        transmission_strength * forward_scatter * visibility * daylight;

    // Absorption enriches the material's own hue instead of washing thin
    // silhouettes toward white. Leaves retain a warm yellow-green vein glow;
    // petals keep their authored pigment.
    float luma = dot(input.color.rgb, float3(.2126, .7152, .0722));
    float3 transmitted_color = petal
        ? saturate(input.color.rgb * 1.18 + luma * .06)
        : saturate(input.color.rgb * float3(1.18, 1.34, .72));
    float rim = pow(1.0 - saturate(dot(normal, view_direction)), 2.0);
    float3 result =
        input.color.rgb * body_light +
        transmitted_color * transmission +
        input.color.rgb * rim * .06;
    if (!petal && input.material.y > .5) {
        // Procedural leaf texture. The CPU supplies canonical blade UVs and a
        // shape index; density varies slightly by botanical profile while the
        // mask remains resolution-independent and follows every curved mesh.
        float shape = input.material.x;
        float pairs = (shape == 1.0 || shape == 9.0) ? 9.0 :
                      (shape >= 6.0 && shape <= 8.0) ? 5.0 : 7.0;
        float center_distance = abs(input.uv.x - .5);
        // A restrained lamina gradient gives the blade a living, waxy depth
        // before any vein marks are applied: slightly shaded at the petiole
        // and margin, with a broad soft lift through the central tissue.
        float center_bloom = 1.0 - smoothstep(.08, .48, center_distance);
        float tip_fade = smoothstep(.06, .22, input.uv.y) *
                         (1.0 - smoothstep(.84, 1.0, input.uv.y));
        result *= lerp(.91, 1.045, center_bloom * tip_fade);

        float midrib = 1.0 - smoothstep(.008, .024, center_distance);
        float sweep = lerp(.18, .32, saturate(input.uv.y));
        float branch_coordinate = input.uv.y - center_distance * sweep;
        float branch_phase = abs(frac(branch_coordinate * pairs + .5) - .5);
        float secondary = 1.0 - smoothstep(.024, .070, branch_phase);
        secondary *= smoothstep(.045, .13, center_distance);
        secondary *= 1.0 - smoothstep(.37, .49, center_distance);
        secondary *= smoothstep(.045, .14, input.uv.y) *
                     (1.0 - smoothstep(.90, .99, input.uv.y));
        float vein = saturate(max(midrib, secondary * .66));
        // Veins should organize the surface, not read as luminous paint.
        // Lift the already-lit lamina so the mark remains visible in shadow
        // without turning into the fluorescent overlay used previously.
        float3 vein_color = saturate(result * float3(1.16, 1.22, 1.04) + float3(.006, .014, .002));
        result = lerp(result, vein_color, vein * .56);
    }
    return saturate(result);
}

float3 shade_road(VertexOutput input) {
    float2 uv = input.normal.xy;
    float pavement = input.normal.z;
    float2 world = input.world_position.xz;

    // Broad pigment clouds and a restrained dry-brush grain break up the
    // computer-flat surface without introducing a repeating texture asset.
    float broad = value_noise(rotate2(world, .43) * .052 + float2(.7, 2.1));
    float grain = hash12(world * 1.37 + floor(uv.y * .35));
    float value = lerp(.78, 1.20, broad) * lerp(.91, 1.09, grain);
    float3 color = input.color.rgb * value;

    // The swept profile places the carriageway between one- and two-thirds
    // across its UV span. Soft dust at those seams integrates it with the
    // earthen shoulder, while paired low-contrast wheel paths imply use.
    float road_mask = smoothstep(.305, .365, uv.x) *
                      (1.0 - smoothstep(.635, .695, uv.x));
    float seam_distance = abs(abs(uv.x - .5) - .1667);
    float dusty_seam = (1.0 - smoothstep(.018, .070, seam_distance)) * road_mask;
    float3 dust = float3(.47, .36, .20);
    color = lerp(color, color + dust * .16, dusty_seam * (.58 + broad * .34));

    float wheel_distance = min(abs(uv.x - .415), abs(uv.x - .585));
    float wheel_wear = (1.0 - smoothstep(.018, .052, wheel_distance)) * road_mask;
    color *= 1.0 - wheel_wear * lerp(.095, .205, broad);

    // Material-specific marks remain tonal rather than literal: broken pale
    // aggregate for gravel, offset cool joints for cobble, and warm ruts for
    // dirt. Pavement is constant per swept edge and interpolates naturally at
    // the mixed-material junction.
    float gravel_weight = saturate(1.0 - abs(pavement - 1.0));
    float cobble_weight = saturate(1.0 - abs(pavement - 2.0));
    float dirt_weight = saturate(1.0 - abs(pavement - 3.0));
    float gravel = smoothstep(.77, .94, hash12(world * 2.45 + float2(8.1, .6)));
    color += gravel * gravel_weight * road_mask * float3(.145, .120, .075);

    // Derivative reads must remain outside material-weight branches: pavement
    // interpolates through junction triangles, and derivatives are undefined
    // when neighboring pixels diverge before evaluating them.
    float2 road_uv_dx = ddx(uv);
    float2 road_uv_dy = ddy(uv);
    float3 road_position_dx = ddx(input.world_position);
    float3 road_position_dy = ddy(input.world_position);
    // Cobble is the most detailed road material. Keep its hashes, noise fields,
    // and reconstruction arithmetic out of the other pavement paths except
    // for the narrow interpolated band at mixed-material junctions.
    if (cobble_weight > .001) {
    float cobble_detail = 1.0 - smoothstep(85.0, 230.0, input.depth);
    float cobble_junction = step(.02, input.material.y);
    float cobble_neglect = 1.0 - saturate(input.uv.x);
    // Staggered, softly rounded setts avoid the graph-paper look of a single
    // rectangular grid. Hashing per cell varies both silhouette and pigment,
    // while keeping the pattern stable as the camera and road geometry move.
    float road_half_width = max(input.material.x, .01);
    float cobble_across_metres = (uv.x - .5) * road_half_width / .165;
    float2 cobble_road_grid = float2(cobble_across_metres * 2.35, uv.y * 1.85);
    // A junction fan interpolates unrelated edge-distance UVs toward one
    // synthetic center value. Use a world-stable coursing field through that
    // interior, leaving only a narrow transition at each approach boundary.
    float2 cobble_junction_grid =
        rotate2(world, .43) * float2(2.35, 1.85);
    float2 cobble_grid = lerp(
        cobble_road_grid,
        cobble_junction_grid,
        cobble_junction
    );
    float cobble_row = floor(cobble_grid.y);
    float cobble_row_seed = hash12(float2(cobble_row, 11.7));
    cobble_grid.x += frac(cobble_row * .5) * .5 + (cobble_row_seed - .5) * .18;
    float2 cobble_cell = floor(cobble_grid);
    float2 cobble_local = frac(cobble_grid) - .5;
    float cobble_shape_seed = hash12(cobble_cell + float2(17.3, 4.9));
    float cobble_tone_seed = hash12(cobble_cell + float2(3.7, 29.1));
    cobble_local.x += (cobble_shape_seed - .5) * .075;
    cobble_local.y += (cobble_tone_seed - .5) * .055;
    float cobble_angle = (cobble_shape_seed - .5) * .15;
    cobble_local = rotate2(cobble_local, cobble_angle);
    float2 cobble_half_size = float2(
        lerp(.405, .455, cobble_shape_seed),
        lerp(.395, .452, cobble_tone_seed)
    );
    float cobble_radius = lerp(.075, .13, hash12(cobble_cell + float2(41.2, 8.6)));
    float2 cobble_edge = abs(cobble_local) - cobble_half_size + cobble_radius;
    float cobble_distance =
        length(max(cobble_edge, 0.0)) +
        min(max(cobble_edge.x, cobble_edge.y), 0.0) -
        cobble_radius;
    // Cell-local erosion gently chips otherwise analytic edges. The field is
    // deterministic in material space, so the irregularity remains attached
    // to each stone rather than crawling as the camera moves.
    float cobble_erosion = value_noise(
        rotate2(cobble_local, cobble_tone_seed * 1.7) * 3.4 +
        cobble_cell * .613
    );
    cobble_distance += (cobble_erosion - .5) * .030 * cobble_detail;
    float cobble_across_scale = road_half_width / .165 * 2.35;
    float2 cobble_grid_dx = float2(
        road_uv_dx.x * cobble_across_scale,
        road_uv_dx.y * 1.85
    );
    float2 cobble_grid_dy = float2(
        road_uv_dy.x * cobble_across_scale,
        road_uv_dy.y * 1.85
    );
    float2 cobble_junction_grid_dx =
        rotate2(road_position_dx.xz, .43) * float2(2.35, 1.85);
    float2 cobble_junction_grid_dy =
        rotate2(road_position_dy.xz, .43) * float2(2.35, 1.85);
    cobble_grid_dx = lerp(
        cobble_grid_dx,
        cobble_junction_grid_dx,
        cobble_junction
    );
    cobble_grid_dy = lerp(
        cobble_grid_dy,
        cobble_junction_grid_dy,
        cobble_junction
    );
    float cobble_aa = max(
        max(length(cobble_grid_dx), length(cobble_grid_dy)) * .55,
        .009
    );
    float cobble_stone = 1.0 - smoothstep(-cobble_aa, cobble_aa, cobble_distance);
    float cobble_joint = 1.0 - cobble_stone;
    float cobble_pattern = cobble_weight * road_mask;
    // Mortar is not a uniformly inked outline: broad deposits alternately
    // expose cool packed joints and catch the road's warm shoulder dust.
    float cobble_joint_field = value_noise(
        rotate2(world, .31) * .28 + float2(6.4, 19.7)
    );
    float cobble_joint_depth = lerp(.115, .205, cobble_joint_field);
    color *= 1.0 - cobble_joint * cobble_pattern * cobble_joint_depth;
    float cobble_joint_dust = smoothstep(.57, .83, cobble_joint_field);
    color +=
        cobble_joint * cobble_pattern * cobble_joint_dust *
        float3(.018, .013, .006);
    // Neglected stone is reclaimed from the living verge inward. Growth stays
    // down in the mortar, avoids the two wheel paths, and forms discontinuous
    // colonies instead of a uniform green outline around every sett.
    float cobble_from_verge = smoothstep(.035, .155, abs(uv.x - .5));
    float cobble_center_strip =
        1.0 - smoothstep(.035, .105, abs(uv.x - .5));
    float cobble_wheel_clear = smoothstep(.030, .072, wheel_distance);
    float cobble_growth_field = value_noise(
        rotate2(world, -.27) * .19 + float2(31.4, 7.2)
    );
    float cobble_colonies = smoothstep(
        lerp(.78, .46, cobble_neglect),
        .92,
        cobble_growth_field
    );
    float cobble_grass =
        cobble_joint * cobble_pattern * cobble_neglect *
        cobble_wheel_clear * cobble_colonies *
        saturate(cobble_from_verge + cobble_center_strip * .48);
    float3 cobble_grass_dark = float3(.075, .105, .030);
    float3 cobble_grass_lit = float3(.18, .245, .060);
    float3 cobble_grass_color = lerp(
        cobble_grass_dark,
        cobble_grass_lit,
        broad * .55 + cobble_growth_field * .45
    );
    color = lerp(color, cobble_grass_color, cobble_grass * .88);
    float3 cobble_tint = lerp(
        float3(.91, .955, .95),
        float3(1.09, 1.045, .95),
        cobble_tone_seed
    );
    color = lerp(color, color * cobble_tint, cobble_stone * cobble_pattern * .52);
    float cobble_face_mottle = .5;
    if (cobble_detail > .001) {
        cobble_face_mottle = value_noise(
            rotate2(world, cobble_shape_seed * .8) * 3.7 +
            cobble_cell * .193
        );
    }
    color *= lerp(
        lerp(1.0, .973, cobble_detail),
        lerp(1.0, 1.027, cobble_detail),
        cobble_face_mottle * cobble_stone * cobble_pattern +
        .5 * (1.0 - cobble_stone * cobble_pattern)
    );
    // Reconstruct the road's transverse and longitudinal world axes from
    // screen-space derivatives. This lets the painted bevel follow the actual
    // Sun around bends instead of baking a false highlight direction into UVs.
    if (cobble_detail > .001) {
    float road_uv_determinant =
        road_uv_dx.x * road_uv_dy.y - road_uv_dy.x * road_uv_dx.y;
    float road_uv_safe_determinant =
        road_uv_determinant >= 0.0
            ? max(road_uv_determinant, .000001)
            : min(road_uv_determinant, -.000001);
    float3 road_across = (
        road_position_dx * road_uv_dy.y -
        road_position_dy * road_uv_dx.y
    ) / road_uv_safe_determinant;
    float3 road_along = (
        road_position_dy * road_uv_dx.x -
        road_position_dx * road_uv_dy.x
    ) / road_uv_safe_determinant;
    road_across /= max(length(road_across), .001);
    road_along /= max(length(road_along), .001);
    if (cobble_junction > .5) {
        float junction_c = cos(.43), junction_s = sin(.43);
        road_across = float3(junction_c, 0, -junction_s);
        road_along = float3(junction_s, 0, junction_c);
    }
    float3 cobble_sun = normalize(push.sun.xyz);
    float2 cobble_sun_local = float2(
        dot(cobble_sun, road_across),
        dot(cobble_sun, road_along)
    );
    cobble_sun_local /= max(length(cobble_sun_local), .08);
    float2 cobble_outward = cobble_local / max(cobble_half_size, float2(.001, .001));
    cobble_outward /= max(length(cobble_outward), .001);
    cobble_outward = rotate2(cobble_outward, -cobble_angle);
    float cobble_bevel =
        (1.0 - smoothstep(.018, .115, -cobble_distance)) *
        cobble_stone * cobble_pattern;
    float cobble_bevel_facing = dot(cobble_outward, cobble_sun_local);
    color *= 1.0 +
        cobble_bevel * cobble_bevel_facing *
        saturate(push.sun.w) * cobble_detail * .065;
    }
    float cobble_crown = smoothstep(.015, .13, -cobble_distance);
    color *= 1.0 +
        cobble_crown * cobble_stone * cobble_pattern *
        lerp(.012, .026, cobble_detail);
    // Weather severity doubles as the renderer's established rain/moisture
    // signal. Damp limestone darkens in broad patches, cools slightly, and
    // retains only a restrained broken sheen on the raised crowns.
    float cobble_wetness = smoothstep(.16, .78, saturate(push.water.y));
    if (cobble_wetness > .001) {
        float cobble_wet_patch = lerp(
            .62,
            1.0,
            value_noise(rotate2(world, .19) * .16 + float2(2.7, 13.4))
        );
        float cobble_wet = cobble_wetness * cobble_pattern * cobble_wet_patch;
        color = lerp(
            color,
            color * float3(.73, .79, .82),
            cobble_wet * .46
        );
        float cobble_wet_sheen =
            smoothstep(.63, .88, cobble_face_mottle) *
            cobble_crown * cobble_stone * cobble_wet *
            saturate(push.sun.w);
        color += float3(.018, .024, .026) * cobble_wet_sheen;
    }
    }

    float rut = 1.0 - smoothstep(.028, .075, wheel_distance);
    color = lerp(color, color * float3(.87, .76, .64), rut * dirt_weight * road_mask * .68);

    // A gentle sun wash keeps the material in the same painted value hierarchy
    // as foliage and terrain without adding a second lighting model.
    float daylight = saturate(push.sun.w);
    color *= lerp(.91, 1.035, daylight);
    return saturate(color);
}

float3 shade_water(VertexOutput input) {
    float2 p = input.world_position.xz;
    float time = push.water.x;
    float sea_state = saturate(.28 + push.water.y * .64);
    float2 wind = push.water.zw;
    float wind_length = max(length(wind), .001);
    float2 axis = wind / wind_length;
    float2 across = float2(-axis.y, axis.x);

    // The local ocean grid carries the interpolated terrain elevation above
    // sea level. Positive terrain approaches the water from beneath the
    // visible surface, so the shallow tint and foam follow authored terrain
    // edits instead of a pair of hard-coded island circles. Far-ocean vertices
    // have no terrain signal and remain deep water.
    float terrain_shore = abs(input.material.y) *
        smoothstep(.025, 1.35, input.material.x);
    float shallow = terrain_shore;
    float deep = 1.0 - smoothstep(.015, .72, terrain_shore);

    // The horizon color is the sky radiance available for broad water
    // reflection. Shape it through depth-dependent absorption rather than
    // starting from a fixed turquoise palette, so overcast, storms, twilight,
    // and night all carry coherently into the ocean.
    float3 sky_color = srgb_to_linear(push.fog_color.rgb);
    float3 shallow_color =
        sky_color * float3(.42, .78, .72) + float3(.012, .070, .055);
    float3 middle_color =
        sky_color * float3(.30, .62, .72) + float3(.006, .032, .065);
    float3 deep_color =
        sky_color * float3(.20, .42, .58) + float3(.002, .018, .052);
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

    // At eye level, add long wind ripples that break up the otherwise planar
    // near field. They fade before map/editor overview heights and toward the
    // horizon, preserving the existing large-scale painted ocean treatment.
    float camera_height = abs(push.camera_position.y - input.world_position.y);
    float eye_level = 1.0 - smoothstep(18.0, 72.0, camera_height);
    float camera_distance = length(push.camera_position.xz - p);
    float near_detail = eye_level * (1.0 - smoothstep(180.0, 900.0, camera_distance));
    float ripple_phase =
        dot(p, axis) * .31 +
        sin(dot(p, across) * .045 + time * .09) * .72 -
        time * (1.05 + sea_state * .42);
    float ripple_wave = sin(ripple_phase);
    float ripple_crest = smoothstep(.80, .97, ripple_wave) * near_detail;
    color = lerp(color, color * 1.16 + foam_color * .025, ripple_crest * .34);
    slope += axis * cos(ripple_phase) * (.026 + sea_state * .030) * near_detail;

    float3 normal = normalize(float3(-slope.x, 1, -slope.y));
    float3 view = normalize(push.camera_position.xyz - input.world_position);
    float facing = saturate(dot(normal, view));
    float fresnel = .03 + .38 * pow(1.0 - facing, 4.0);
    // Fresnel is the least-filtered sky contribution. Its source remains the
    // same active sky color while daylight controls only reflection strength.
    float3 sky_tint = sky_color * lerp(.68, 1.12, saturate(push.sun.w));
    color = lerp(color, sky_tint, fresnel * .31);

    float3 sun_dir = normalize(push.sun.xyz);
    float n_dot_l = saturate(dot(normal, sun_dir));
    float n_dot_v = max(dot(normal, view), .0001);
    float3 half_vector = normalize(sun_dir + view);
    float n_dot_h = max(dot(normal, half_vector), .0001);

    // Cox-Munk ocean glitter is the probability that an unresolved water
    // facet has the half-vector normal required to reflect the Sun into the
    // camera. Approximate that measured slope distribution with an
    // anisotropic Beckmann NDF aligned to the wind.
    float3 wind_seed = float3(axis.x, 0, axis.y);
    float3 wind_tangent = normalize(
        wind_seed - normal * dot(wind_seed, normal)
    );
    float3 wind_bitangent = normalize(cross(normal, wind_tangent));
    float h_wind = dot(half_vector, wind_tangent);
    float h_crosswind = dot(half_vector, wind_bitangent);
    float wind_roughness = saturate(wind_length / 14.0);
    float alpha_wind = .195 + wind_roughness * .120 + sea_state * .065;
    float alpha_crosswind = .125 + wind_roughness * .082 + sea_state * .047;
    float inverse_h_y_squared = 1.0 / max(n_dot_h * n_dot_h, .000001);
    float slope_exponent = -(
        h_wind * h_wind / (alpha_wind * alpha_wind) +
        h_crosswind * h_crosswind /
            (alpha_crosswind * alpha_crosswind)
    ) * inverse_h_y_squared;
    float beckmann = exp(max(slope_exponent, -80.0)) /
        max(
            3.14159265 *
            alpha_wind *
            alpha_crosswind *
            n_dot_h * n_dot_h * n_dot_h * n_dot_h,
            .00001
        );

    // Water is a dielectric with F0 ~= 2%. At grazing angles Fresnel makes the
    // low-Sun path much brighter without an authored horizon multiplier.
    float v_dot_h = saturate(dot(view, half_vector));
    float water_f0 = .02037;
    float sun_fresnel =
        water_f0 + (1.0 - water_f0) * pow(1.0 - v_dot_h, 5.0);
    float smith_alpha = sqrt(alpha_wind * alpha_crosswind);
    float smith_alpha_squared = smith_alpha * smith_alpha;
    float smith_v = 2.0 * n_dot_v /
        max(
            n_dot_v +
            sqrt(
                smith_alpha_squared +
                (1.0 - smith_alpha_squared) * n_dot_v * n_dot_v
            ),
            .0001
        );
    // At grazing incidence the unresolved facets still see the Sun even when
    // the resolved macro normal is almost perpendicular to it. Retain a small
    // effective cosine here; the Smith term then models partial horizon
    // shadowing without incorrectly extinguishing the whole glitter path.
    float effective_n_dot_l = max(
        n_dot_l,
        alpha_crosswind * .18
    );
    float smith_l = 2.0 * effective_n_dot_l /
        max(
            effective_n_dot_l +
            sqrt(
                smith_alpha_squared +
                (1.0 - smith_alpha_squared) *
                effective_n_dot_l * effective_n_dot_l
            ),
            .0001
        );
    float masking_shadowing = smith_v * smith_l;

    // Nearby capillary facets resolve into individual flashes. In the
    // distance their sub-pixel contributions converge to the smooth NDF.
    float capillary_a = value_noise(
        p * .71 + time * float2(.29, -.12)
    );
    float capillary_b = value_noise(
        rotate2(p, .83) * 1.27 + time * float2(-.18, .34)
    );
    float2 capillary_cell = floor(
        p * 18.5 +
        floor(time * 12.0) * float2(.37, -.23)
    );
    float capillary_flash = smoothstep(
        .74,
        .965,
        hash12(capillary_cell)
    );
    float capillary_cluster = smoothstep(
        .46,
        .84,
        capillary_a * .62 + capillary_b * .38
    );
    float resolved_capillaries =
        1.0 - smoothstep(480.0, 2400.0, camera_distance);
    float facet_sampling = lerp(
        1.0,
        lerp(.16, 3.4, capillary_flash) *
        lerp(.58, 1.32, capillary_cluster),
        resolved_capillaries
    );
    float sun_above_horizon = smoothstep(-.012, .025, sun_dir.y);
    float sun_specular =
        sun_fresnel *
        beckmann *
        masking_shadowing /
        max(4.0 * n_dot_v, .0001) *
        facet_sampling *
        sun_above_horizon *
        .18;
    float3 sunset_gold = float3(1.0, .47, .12);
    float3 noon_sun = float3(1.0, .93, .72);
    float3 sun_reflection_color = lerp(
        sunset_gold,
        noon_sun,
        smoothstep(.025, .42, sun_dir.y)
    );
    color += sun_reflection_color * min(sun_specular, 2.4);

    // A narrow, broken aerated edge keeps foam attached to the coastline.
    float foam_band = smoothstep(.035, .30, terrain_shore) *
                      (1.0 - smoothstep(.48, .92, terrain_shore));
    float foam_breakup = value_noise(float2(dot(p, across) * .075, dot(p, axis) * .031) +
                                      float2(time * .028, 0));
    float breaking_shore = step(0.0, input.material.y);
    float foam = foam_band * breaking_shore *
                 lerp(.28, 1.0, smoothstep(.38, .76, foam_breakup));
    color = lerp(color, foam_color, foam * lerp(.38, .68, sea_state));

    // Generated coasts deliberately keep the shelf marker negative so mixed
    // ocean-grid triangles cannot cross through a false zero/deep-water
    // diagonal. Recover a much narrower swash edge from the top of the
    // continuous shallowness signal instead. Derivative widening keeps this
    // sub-pixel band stable at overview distances, while broken coverage and a
    // restrained blend soften the hard terrain/water staircase without
    // painting the whole nearshore shelf white.
    float swash_footprint = max(fwidth(input.material.x) * 1.35, .012);
    float swash_proximity = smoothstep(
        1.235 - swash_footprint,
        1.315 + swash_footprint,
        input.material.x
    );
    float swash_breakup = value_noise(
        float2(dot(p, across) * .115, dot(p, axis) * .041) +
        float2(time * .034, 7.3)
    );
    float swash_threads =
        .5 + .5 * sin(dot(p, across) * .34 +
                      sin(dot(p, axis) * .052 - time * .16) * .82);
    float swash_continuity = lerp(
        .30,
        .88,
        smoothstep(.30, .76, swash_breakup * .72 + swash_threads * .28)
    );
    float swash = swash_proximity * swash_continuity;
    color = lerp(color, foam_color, swash * lerp(.34, .52, sea_state));

    return saturate(color);
}

float3 shade_marine_water(VertexOutput input, float4 habitat) {
    float3 water = shade_water(input);
    float2 p = input.world_position.xz;
    float broad = value_noise(rotate2(p, .31) / 58.0);
    float channel = value_noise(rotate2(p + float2(37, -19), -.22) / 23.0);
    float grain = value_noise(rotate2(p, .67) / 7.5);
    float seagrass = habitat.r * lerp(.68, 1.18, broad) * lerp(.72, 1.12, channel);
    float algae = habitat.g * lerp(.78, 1.10, grain) * lerp(1.10, .82, broad);
    float reef = habitat.b * lerp(.76, 1.12, broad);
    float disturbance = habitat.a;
    float coverage = max(seagrass, max(algae, reef)) * (1.0 - disturbance);
    // Break the interpolated suitability field into broad natural masses. The
    // field remains continuous across chunk edges; this only moves its visual
    // boundary at several world-space scales.
    float meadow = smoothstep(.12, .46, coverage + (broad - .5) * .16 + (channel - .5) * .09);

    float3 seagrass_color = srgb_to_linear(float3(48, 91, 58) / 255.0);
    float3 algae_color = srgb_to_linear(float3(47, 72, 55) / 255.0);
    float3 reef_color = srgb_to_linear(float3(132, 91, 78) / 255.0);
    float weight_sum = max(seagrass + algae + reef, .0001);
    float3 ecology_color =
        (seagrass_color * seagrass + algae_color * algae + reef_color * reef) /
        weight_sum;

    // At foot level, a wind-aligned fine signal suggests a moving canopy.
    // From the air it collapses into stable meadow masses instead of resolving
    // into repeated instances or a chunk lattice.
    float2 wind = push.water.zw;
    float wind_length = max(length(wind), .001);
    float2 wind_axis = wind / wind_length;
    float canopy_wave = sin(dot(p, wind_axis) * .19 - push.water.x * (.34 + wind_length * .012));
    float camera_height = abs(push.camera_position.y - input.world_position.y);
    float near_canopy = 1.0 - smoothstep(32.0, 150.0, camera_height);
    ecology_color *= lerp(.96, 1.04, (canopy_wave * .5 + .5) * near_canopy);
    // Ecology belongs beneath the water response, not in place of it. Keeping
    // most of the shaded ocean preserves reflections, depth, and atmosphere.
    float ecology_strength = meadow * lerp(.18, .30, saturate(seagrass + algae));
    return lerp(water, ecology_color, ecology_strength);
}

float3 shade_fountain_water(VertexOutput input) {
    float2 p = input.world_position.xz;
    float time = push.water.x;
    float3 color = input.color.rgb;
    float daylight = saturate(push.sun.w);
    float3 shallow_tint = lerp(
        float3(.035, .12, .16),
        float3(.10, .43, .53),
        daylight
    );
    color = lerp(color, shallow_tint, .68);

    // Fountain basins are shallow, bounded water. Keep their authored color
    // and add compact crossing ripples instead of the ocean's kilometre-scale
    // depth, coast, wind-lane, and swell response.
    float phase_a = dot(p, normalize(float2(.91, .42))) * 7.4 - time * 1.65;
    float phase_b = dot(p, normalize(float2(-.36, .93))) * 11.2 + time * 1.13;
    float2 ripple_c = normalize(float2(.68, -.73));
    float phase_c = dot(p, ripple_c) * 15.5 - time * 2.1;
    float2 slope =
        normalize(float2(.91, .42)) * cos(phase_a) * .065 +
        normalize(float2(-.36, .93)) * cos(phase_b) * .035;
    slope += ripple_c * cos(phase_c) * .025;

    float3 normal = normalize(float3(-slope.x, 1.0, -slope.y));
    float3 view = normalize(push.camera_position.xyz - input.world_position);
    float facing = saturate(dot(normal, view));
    float fresnel = .035 + .42 * pow(1.0 - facing, 4.0);
    float3 sky_tint = lerp(float3(.045, .12, .18), float3(.22, .58, .67), daylight);
    color = lerp(color, sky_tint, fresnel * .38);

    float wave_field =
        sin(phase_a) * .50 +
        sin(phase_b) * .31 +
        sin(phase_c) * .19;
    // Broad moving value bands remain visible from garden and plaza cameras;
    // the narrower crest highlight then gives close views a wet sparkle.
    color *= 1.0 + wave_field * .075;
    float crossing = smoothstep(.18, .72, wave_field);
    color = lerp(color, float3(.28, .68, .74), crossing * .075);
    float crest = smoothstep(.72, .96, wave_field);
    color = lerp(color, float3(.56, .84, .87), crest * .16);

    float3 sun_dir = normalize(push.sun.xyz);
    float3 half_vector = normalize(sun_dir + view);
    float highlight = pow(saturate(dot(normal, half_vector)), 96.0) * daylight;
    color += float3(1.0, .91, .72) * highlight * .32;

    // Shallow fountain water should remain legible under overcast and night
    // lighting rather than collapsing to the ocean's deep-water value.
    color *= lerp(.82, 1.08, daylight);
    return saturate(color);
}

float4 shade_lighthouse_glitter(VertexOutput input) {
    float night = 1.0 - smoothstep(.0, .34, saturate(push.sun.w));
    float strength = saturate(input.material.x) * night;
    if (strength <= .001) discard;

    float2 ellipse = input.uv * 2.0 - 1.0;
    float footprint = saturate(1.0 - dot(ellipse, ellipse));
    footprint *= footprint;
    if (footprint <= .001) discard;

    float2 p = input.world_position.xz;
    float time = push.water.x;
    float sea_state = saturate(.28 + push.water.y * .64);
    float2 wind = push.water.zw;
    float wind_length = length(wind);
    float2 axis = wind_length > .001 ? wind / wind_length : float2(.86, .51);
    float2 across = float2(-axis.y, axis.x);
    float phase_a = dot(p, axis) * .043 - time * (.42 + sea_state * .24);
    float2 diagonal = normalize(axis + across * .55);
    float phase_b = dot(p, diagonal) * .091 - time * (.73 + sea_state * .31);
    float2 slope = axis * cos(phase_a) * (.035 + sea_state * .055) +
                   diagonal * cos(phase_b) * (.018 + sea_state * .032);

    float camera_height = abs(push.camera_position.y - input.world_position.y);
    float eye_level = 1.0 - smoothstep(18.0, 72.0, camera_height);
    float camera_distance = length(push.camera_position.xz - p);
    float near_detail = eye_level * (1.0 - smoothstep(180.0, 900.0, camera_distance));
    float ripple_phase =
        dot(p, axis) * .31 +
        sin(dot(p, across) * .045 + time * .09) * .72 -
        time * (1.05 + sea_state * .42);
    slope += axis * cos(ripple_phase) *
             (.026 + sea_state * .030) * near_detail;

    float3 normal = normalize(float3(-slope.x, 1, -slope.y));
    float3 view = normalize(push.camera_position.xyz - input.world_position);
    float3 light_direction = normalize(input.normal);
    float3 half_vector = normalize(light_direction + view);
    float n_dot_v = max(dot(normal, view), .0001);
    float n_dot_h = max(dot(normal, half_vector), .0001);

    // Match the Sun path's anisotropic Cox-Munk approximation so this local
    // source breaks into the same wind-shaped, capillary-scale glitter.
    float3 wind_seed = float3(axis.x, 0, axis.y);
    float3 wind_tangent = normalize(wind_seed - normal * dot(wind_seed, normal));
    float3 wind_bitangent = normalize(cross(normal, wind_tangent));
    float h_wind = dot(half_vector, wind_tangent);
    float h_crosswind = dot(half_vector, wind_bitangent);
    float wind_roughness = saturate(wind_length / 14.0);
    // The Fresnel lens has finite aperture and vertical divergence, unlike the
    // effectively angular-point Sun. Broaden the same measured ocean slope
    // distribution just enough for grazing lighthouse light to occupy more
    // than a vanishing sub-pixel tail.
    float alpha_wind = .34 + wind_roughness * .16 + sea_state * .09;
    float alpha_crosswind = .25 + wind_roughness * .12 + sea_state * .07;
    float inverse_h_y_squared = 1.0 / max(n_dot_h * n_dot_h, .000001);
    float slope_exponent = -(
        h_wind * h_wind / (alpha_wind * alpha_wind) +
        h_crosswind * h_crosswind / (alpha_crosswind * alpha_crosswind)
    ) * inverse_h_y_squared * .070;
    float beckmann = exp(max(slope_exponent, -80.0)) /
        max(
            3.14159265 * alpha_wind * alpha_crosswind *
            n_dot_h * n_dot_h * n_dot_h * n_dot_h,
            .00001
        );

    float v_dot_h = saturate(dot(view, half_vector));
    float fresnel = .02037 + (1.0 - .02037) * pow(1.0 - v_dot_h, 5.0);
    float capillary_a = value_noise(p * .71 + time * float2(.29, -.12));
    float capillary_b = value_noise(
        rotate2(p, .83) * 1.27 + time * float2(-.18, .34)
    );
    float2 capillary_cell = floor(
        p * 18.5 + floor(time * 12.0) * float2(.37, -.23)
    );
    float capillary_flash = smoothstep(.74, .965, hash12(capillary_cell));
    float capillary_cluster = smoothstep(
        .46,
        .84,
        capillary_a * .62 + capillary_b * .38
    );
    float resolved_capillaries =
        1.0 - smoothstep(480.0, 2400.0, camera_distance);
    float facet_sampling = lerp(
        1.0,
        capillary_flash * capillary_cluster * 5.0,
        resolved_capillaries
    );
    float glitter = min(
        fresnel * beckmann * facet_sampling * .82,
        2.8
    );
    float visibility = footprint * strength * glitter;
    if (visibility <= .002) discard;
    return float4(input.color.rgb * (1.05 + glitter * .32), input.color.a * visibility);
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    // Indexed clipmap grids retain sea-level vertices so their topology stays
    // reusable. Do not let those terrain fragments cover the ocean pass.
    if (input.kind == MATERIAL_TERRAIN && input.world_position.y <= .001) {
        discard;
    }
    float fog = combined_fog(input);
    float3 base = input.color.rgb;
    float output_alpha = input.color.a;
    switch (input.kind) {
        case MATERIAL_FOG_SHELL: {
            float2 wind = push.water.zw;
            float wind_length = max(length(wind), .001);
            float2 direction = wind / wind_length;
            float phase = dot(input.world_position.xz, direction) * .018 - push.water.x * .19;
            float broad = sin(phase + input.world_position.y * .027) * .50 + .50;
            float crossing = sin(dot(input.world_position.xz, float2(-direction.y, direction.x)) * .013 +
                                 input.world_position.y * .041 + push.water.x * .07) * .50 + .50;
            float billow = smoothstep(.22, .78, broad * .68 + crossing * .32);
            float vertical = smoothstep(.02, .19, input.uv.y) *
                             (1.0 - smoothstep(.62, 1.0, input.uv.y));
            output_alpha *= billow * vertical;
            base = input.color.rgb * lerp(.82, 1.06, billow);
            break;
        }
        case MATERIAL_TERRAIN:
            base = shade_terrain_dunes(input, base);
            base = shade_grass_wind_sheen(input, base);
            base = shade_terrain_limestone(input, base);
            break;
        case MATERIAL_WATER:
            base = shade_water(input);
            break;
        case MATERIAL_MARINE_WATER: {
            float4 habitat = marine_ecology_atlas.Sample(marine_ecology_sampler, input.uv);
            float coverage = max(habitat.r, max(habitat.g, habitat.b)) * (1.0 - habitat.a);
            if (coverage < .018) discard;
            base = shade_marine_water(input, habitat);
            break;
        }
        case MATERIAL_FOUNTAIN_WATER:
            base = shade_fountain_water(input);
            break;
        case MATERIAL_FOLIAGE:
            base = shade_foliage(input);
            break;
        case MATERIAL_LEAF:
            base = shade_thin_transmission(input, false);
            break;
        case MATERIAL_PETAL:
            base = shade_thin_transmission(input, true);
            break;
        case MATERIAL_ROAD:
            base = shade_road(input);
            break;
        case MATERIAL_BRDF:
            base = shade_imported_material(input);
            break;
        case MATERIAL_VEHICLE:
            base = shade_vehicle(input);
            break;
        case MATERIAL_CAR_PAINT:
            base = shade_car_paint(input);
            break;
        case MATERIAL_MATERIAL_LAB:
            base = shade_material_lab(input);
            break;
        case MATERIAL_ROCK:
            base = shade_rock(input);
            output_alpha = 1.0;
            break;
        case MATERIAL_BARK:
            base = shade_bark(input);
            output_alpha = 1.0;
            break;
        case MATERIAL_SETTLEMENT:
            base = shade_settlement_material(input);
            break;
        case MATERIAL_EYE:
            base = shade_eye(input);
            break;
        case MATERIAL_ACORN:
            base = shade_acorn(input);
            break;
        case MATERIAL_BOTTLE_CAP:
            base = shade_bottle_cap(input);
            break;
        case MATERIAL_SAILOR_HAT:
            base = shade_sailor_hat(input);
            break;
        case MATERIAL_EMISSIVE:
            base = shade_emissive(input);
            break;
        case MATERIAL_EMISSIVE_POOL:
            float night = 1.0 - smoothstep(.0, .34, saturate(push.sun.w));
            if (night <= .001) discard;
            float2 pool_position = input.uv * 2.0 - 1.0;
            float radial = saturate(1.0 - dot(pool_position, pool_position));
            // The authored fixture faces local +Z, which maps to +Y in these
            // pool UVs. Model cutoff optics by suppressing backlight behind the
            // post while retaining a soft shoulder at the source. This makes
            // the aimed throw readable and reduces light trespass without
            // changing the pool mesh, extent, or submission count.
            float pool_directionality =
                saturate(input.material.x);
            float forward_cutoff =
                smoothstep(-.72, .18, pool_position.y);
            float aimed_cutoff = lerp(.32, 1.0, forward_cutoff);
            radial *= lerp(
                1.0,
                aimed_cutoff,
                pool_directionality
            );
            radial *= radial;
            // Break the mathematically perfect decal edge against paving,
            // soil, and grass while keeping the optically bright center
            // stable. One low-frequency world-space sample gives overlapping
            // pools the same surface response without another primitive,
            // texture fetch, light object, or draw call.
            float surface_noise = value_noise(input.world_position.xz * .31);
            float surface_response = lerp(.86, 1.08, surface_noise);
            radial *= lerp(surface_response, 1.0, smoothstep(.18, .68, radial));
            if (radial <= .001) discard;
            // A real pool reads pale nearest the luminaire and warmer toward
            // its edge. Shape both zones inside the existing primitive rather
            // than layering another transparent disc.
            float core = smoothstep(.20, .78, radial);
            float pool_luma =
                dot(input.color.rgb, float3(.2126, .7152, .0722));
            float3 core_color =
                lerp(input.color.rgb, pool_luma.xxx, .38) * 1.12;
            base = lerp(input.color.rgb * .76, core_color, core);
            // Rain and sea-weather lift specular scatter from wet paving.
            // Keep the fixed pool footprint, but make its source reflection a
            // little paler and more persistent as weather severity rises.
            float weather_scatter = saturate(push.water.y);
            // Weather is uniform for the frame, so clear nights can skip the
            // complete wet-sheen path without fragment divergence.
            if (weather_scatter > .001) {
                // Wet paving does not merely brighten uniformly: the reflected
                // source compresses into a broken sheen along the optical axis.
                // Reuse the pool UV and noise sample above so rain gains a distinct
                // material response without another fetch, primitive, or light.
                float aimed_wet_lane =
                    saturate(1.0 - abs(pool_position.x) * 1.34);
                aimed_wet_lane *= aimed_wet_lane;
                // Symmetric post-tops have no authored optical axis. Keep their
                // wet response even around the source instead of accidentally
                // aligning every reflection to world north; aimed heads retain the
                // narrow longitudinal sheen established by their UV orientation.
                float wet_lane =
                    lerp(.58, aimed_wet_lane, pool_directionality);
                float wet_sheen =
                    wet_lane * smoothstep(.10, .72, radial) *
                    lerp(.72, 1.08, surface_noise);
                float3 wet_reflection =
                    lerp(base, pool_luma.xxx, .40) * 1.08;
                base = lerp(
                    base,
                    wet_reflection,
                    weather_scatter * (.16 + wet_sheen * .38)
                );
            }

            // Human exposure adapts to the lunar ambient: a fixed municipal
            // lamp has more apparent contrast at new moon than at full moon.
            // Reuse the environment's moon scalar so this costs no additional
            // CPU state, light objects, draw calls, or geometry.
            float moon_adaptation =
                lerp(1.0, .72, sqrt(saturate(push.fog_color.a)));
            output_alpha *=
                radial * night * moon_adaptation *
                lerp(1.0, 1.14, weather_scatter);
            break;
        case MATERIAL_EMISSIVE_HALO:
            float halo_night =
                1.0 - smoothstep(.0, .34, saturate(push.sun.w));
            if (halo_night <= .001) discard;
            float halo_distance_visibility =
                smoothstep(5.0, 15.0, input.depth) *
                (1.0 - smoothstep(150.0, 220.0, input.depth));
            if (halo_distance_visibility <= .001) discard;
            float2 halo_position = input.uv * 2.0 - 1.0;
            float halo_source =
                saturate(1.0 - dot(halo_position, halo_position));
            // A fixture bloom must disappear well inside its supporting quad;
            // the broader pool curve left a readable rectangular card when
            // viewed close to a lamp. Moist air broadens that compact core
            // slightly, but never expands the existing billboard footprint.
            float halo_broad = halo_source * halo_source;
            float halo_compact = halo_broad * halo_source;
            float halo_radial = lerp(
                halo_compact,
                halo_broad,
                saturate(push.water.y) * .34
            );
            if (halo_radial <= .004) discard;
            float halo_luma =
                dot(input.color.rgb, float3(.2126, .7152, .0722));
            base = lerp(input.color.rgb, halo_luma.xxx, .28);
            float halo_moon_adaptation =
                lerp(1.0, .72, sqrt(saturate(push.fog_color.a)));
            output_alpha *=
                halo_radial * halo_night * halo_moon_adaptation *
                halo_distance_visibility *
                lerp(1.0, 1.28, saturate(push.water.y));
            break;
        case MATERIAL_ARCHITECTURE:
            base = shade_architecture(input);
            break;
        case MATERIAL_GLASS:
            base = shade_glass(input);
            break;
        case MATERIAL_SIGN:
            float2 sign_tile_uv = float2(frac(input.uv.x * 5.0), input.uv.y);
            float2 sign_ellipse = (sign_tile_uv - float2(.5, .5)) / float2(.48, .43);
            if (dot(sign_ellipse, sign_ellipse) > 1.0) discard;
            float4 sign_sample = business_sign_atlas.Sample(business_sign_sampler, input.uv);
            if (sign_sample.a < .08) discard;
            base = srgb_to_linear(sign_sample.rgb);
            output_alpha *= sign_sample.a;
            break;
        case MATERIAL_LIGHTHOUSE_GLITTER:
            float4 lighthouse_glitter = shade_lighthouse_glitter(input);
            base = lighthouse_glitter.rgb;
            output_alpha = lighthouse_glitter.a;
            break;
    }
    // Road vertices repurpose their compact normal channel for material-space
    // UV and pavement. Reconstruct the geometric surface normal here before
    // the shared shadow and environment-lighting tail consumes it.
    float3 surface_normal = input.normal;
    if (input.kind == MATERIAL_ROAD) {
        surface_normal = normalize(cross(
            ddx(input.world_position),
            ddy(input.world_position)
        ));
        if (surface_normal.y < 0.0) surface_normal = -surface_normal;
    }
    if (input.kind == MATERIAL_UNSHADED ||
        input.kind == MATERIAL_TERRAIN ||
        input.kind == MATERIAL_FOLIAGE ||
        input.kind == MATERIAL_LEAF ||
        input.kind == MATERIAL_PETAL ||
        input.kind == MATERIAL_ROAD) {
        float visibility = dynamic_shadow_visibility(input.world_position, surface_normal);
        // These palette-authored materials already contain their ambient/key
        // value grouping. Remove only the direct-looking portion so mapped
        // shadows do not crush that authored ambient illumination.
        base *= lerp(.72, 1.0, visibility);
    }
    if (input.kind == MATERIAL_WATER ||
        input.kind == MATERIAL_MARINE_WATER ||
        input.kind == MATERIAL_FOUNTAIN_WATER) {
        // Nearby boats and aircraft use the mapped caster pass. Let the water
        // receive their softened silhouettes without crushing its animated
        // pigment and glint response.
        float visibility = dynamic_shadow_visibility(input.world_position, input.normal);
        base *= lerp(.80, 1.0, visibility);
    }
    if (input.kind != MATERIAL_EMISSIVE &&
        input.kind != MATERIAL_EMISSIVE_POOL &&
        input.kind != MATERIAL_EMISSIVE_HALO &&
        input.kind != MATERIAL_LIGHTHOUSE_GLITTER) {
        float3 environment_lit =
            apply_environment_light(base, surface_normal, input.world_position);
        if (input.kind == MATERIAL_GLASS) {
            float night =
                1.0 - smoothstep(.0, .34, saturate(push.sun.w));
            float interior_visibility =
                saturate(input.material.x) * night;
            base = lerp(environment_lit, base, interior_visibility);
        } else {
            base = environment_lit;
        }
    }
    if (input.kind == MATERIAL_BRDF ||
        input.kind == MATERIAL_EYE ||
        input.kind == MATERIAL_ACORN ||
        input.kind == MATERIAL_BOTTLE_CAP ||
        input.kind == MATERIAL_SAILOR_HAT ||
        input.kind == MATERIAL_VEHICLE ||
        input.kind == MATERIAL_CAR_PAINT ||
        input.kind == MATERIAL_MATERIAL_LAB ||
        input.kind == MATERIAL_SETTLEMENT ||
        input.kind == MATERIAL_BARK) {
        // Local light is added after night adaptation: the environment should
        // darken unlit surfaces, not erase illumination arriving from a nearby
        // theatrical source.
        base = saturate(
            base +
            shade_cinematic_spotlight(input) +
            shade_cinematic_limelights(input)
        );
    }
    if (input.kind == MATERIAL_FOG_SHELL && output_alpha <= .005) discard;
    float3 resolved = lerp(base, srgb_to_linear(push.fog_color.rgb), fog);
    if (push.projection.z < 0.0) {
        float luminance = dot(resolved, float3(.2126, .7152, .0722));
        resolved = lerp(luminance.xxx, resolved, .82);
        resolved = lerp(resolved, floor(resolved * 15.0 + .5) / 15.0, .42);
    }
    return float4(resolved, output_alpha);
}
