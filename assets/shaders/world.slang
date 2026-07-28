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

static const uint MATERIAL_PLAIN = 0;
static const uint MATERIAL_WATER = 1;
static const uint MATERIAL_TERRAIN = 2;
static const uint MATERIAL_FOLIAGE = 3;
static const uint MATERIAL_ROAD = 4;
static const uint MATERIAL_LIT = 5;
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
    if (input.kind == MATERIAL_FOLIAGE) {
        float2 wind = push.water.zw;
        float wind_speed = length(wind);
        float2 wind_direction = wind_speed > .001 ? wind / wind_speed : float2(1, 0);
        float crown_weight = smoothstep(-.08, .76, input.normal.y);
        float phase = dot(input.position.xz, float2(.021, -.016)) +
                      push.water.x * (.34 + wind_speed * .012);
        float broad_sway = sin(phase) + sin(phase * .47 + 1.9) * .34;
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
    output.kind = MATERIAL_PLAIN;
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
        base_color = lerp(base_color, srgb_to_linear(paint.rgb), paint.a);
    }
    BrdfMaterial material;
    material.base_color = base_color;
    material.metallic = vehicle ? 0 : input.material.x;
    material.roughness = vehicle ? .04 : input.material.y;
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
    float3 interior = input.color.rgb;
    // Residential panes need a clearly readable opaque sky body even when
    // viewed head-on. Storefront and occupied panes retain more of their
    // authored interior color.
    float reflection_weight = lerp(.78, .90, fresnel);
    reflection_weight = lerp(
        reflection_weight,
        lerp(.62, .82, fresnel),
        interior_light
    );
    reflection_weight *= lerp(1.0, .55, interior_light * night);
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

    float cobble_row = floor(uv.y * .58);
    float cobble_cross = abs(frac(uv.x * 13.0 + frac(cobble_row * .5) * .5) - .5);
    float cobble_along = abs(frac(uv.y * .58) - .5);
    float cobble_joint = 1.0 - smoothstep(.035, .085, min(cobble_cross, cobble_along));
    color *= 1.0 - cobble_joint * cobble_weight * road_mask * .31;

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
    float3 sky_tint = lerp(float3(.055, .16, .24), float3(.20, .52, .62), push.sun.w);
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
    float foam_band = 1.0 - smoothstep(5.0, 31.0, coast_distance);
    float foam_breakup = value_noise(float2(dot(p, across) * .075, dot(p, axis) * .031) +
                                      float2(time * .028, 0));
    float foam = foam_band * lerp(.28, 1.0, smoothstep(.38, .76, foam_breakup));
    color = lerp(color, foam_color, foam * lerp(.38, .68, sea_state));

    return saturate(color);
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    // Indexed clipmap grids retain sea-level vertices so their topology stays
    // reusable. Do not let those terrain fragments cover the ocean pass.
    if (input.kind == MATERIAL_TERRAIN && input.world_position.y <= .001) {
        discard;
    }
    float fog = saturate((input.depth - push.projection.z) /
                         max(push.projection.w - push.projection.z, .001));
    float3 base = input.color.rgb;
    float output_alpha = input.color.a;
    switch (input.kind) {
        case MATERIAL_WATER:
            base = shade_water(input);
            break;
        case MATERIAL_FOLIAGE:
            base = shade_foliage(input);
            break;
        case MATERIAL_ROAD:
            base = shade_road(input);
            break;
        case MATERIAL_LIT:
        case MATERIAL_VEHICLE:
            base = shade_imported_material(input);
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
    }
    if (input.kind == MATERIAL_PLAIN ||
        input.kind == MATERIAL_TERRAIN ||
        input.kind == MATERIAL_FOLIAGE ||
        input.kind == MATERIAL_ROAD) {
        float visibility = dynamic_shadow_visibility(input.world_position, input.normal);
        // These palette-authored materials already contain their ambient/key
        // value grouping. Remove only the direct-looking portion so mapped
        // shadows do not crush that authored ambient illumination.
        base *= lerp(.72, 1.0, visibility);
    }
    if (input.kind == MATERIAL_WATER) {
        // Nearby boats and aircraft use the mapped caster pass. Let the water
        // receive their softened silhouettes without crushing its animated
        // pigment and glint response.
        float visibility = dynamic_shadow_visibility(input.world_position, input.normal);
        base *= lerp(.80, 1.0, visibility);
    }
    if (input.kind != MATERIAL_EMISSIVE &&
        input.kind != MATERIAL_EMISSIVE_POOL &&
        input.kind != MATERIAL_EMISSIVE_HALO) {
        float3 environment_lit =
            apply_environment_light(base, input.normal, input.world_position);
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
    return float4(lerp(base, srgb_to_linear(push.fog_color.rgb), fog), output_alpha);
}
