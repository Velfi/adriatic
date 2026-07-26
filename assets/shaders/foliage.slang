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
    uint kind : TEXCOORD2;
};

struct VertexOutput {
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
    float depth : TEXCOORD1;
    nointerpolation uint kind : TEXCOORD2;
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

VertexOutput foliage_vertex_transform(VertexInput input) {
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
    bool native_atlas_card = input.kind == 0 && input.color.a > 1.5;
    // Native-card RGB carries layer value plus the authoritative texture-space
    // anchor from the CPU atlas table. Avoid duplicating 16 anchor constants
    // here, where an atlas edit could otherwise desynchronize wind roots.
    float2 native_anchor = input.color.gb;
    float anchor_distance = length((tile_uv - native_anchor) * float2(1.0, .88));
    float native_tip_weight = smoothstep(.10, .82, anchor_distance);
    float flutter = sin(push.water.x * (1.18 + wind_speed * .028) +
                        dot(input.position.xz, float2(.071, .043)) +
                        tile_uv.x * 2.7);
    // The lower three atlas rows contain flower-bearing sprays. Their papery
    // bracts carry a quicker, smaller rustle than the surrounding leaves.
    float native_flower_card = step(.25, input.uv.y);
    float bract_rustle = sin(push.water.x * (2.34 + wind_speed * .041) +
                             dot(input.position.xz, float2(.133, -.097)) +
                             tile_uv.x * 6.1 + tile_uv.y * 4.7);
    if (input.kind == 1) {
        // Advect several broad waves through world space. Their different
        // headings and wavelengths form irregular gust fronts that travel
        // across a field instead of making every tuft sway in unison.
        float grass_time = push.water.x * (.62 + wind_speed * .018);
        float downwind_coordinate = dot(input.position.xz, wind_direction);
        float crosswind_coordinate = dot(input.position.xz, wind_across);
        float primary_wave = sin(downwind_coordinate * .071 - grass_time);
        float crossing_wave =
            sin((downwind_coordinate * .039 + crosswind_coordinate * .052) -
                grass_time * .73 + 1.7);
        float detail_wave =
            sin((downwind_coordinate * .113 - crosswind_coordinate * .027) -
                grass_time * 1.07 + 4.1);
        float field_wave =
            primary_wave * .52 +
            crossing_wave * .31 +
            detail_wave * .17;

        // Keep the response continuous. Thresholding this signal into a gust
        // front made the cards appear to tick between poses even though the
        // underlying waves were smooth. A separate, low-amplitude tip ripple
        // adds local variation without changing the field's broad cadence.
        float wave_energy = field_wave * .5 + .5;
        float blade_flutter =
            sin(push.water.x * (.91 + wind_speed * .018) +
                dot(input.position.xz, float2(.29, -.23)) +
                crossing_wave * .35);
        float downwind_bend = (.045 + wave_energy * .105 + blade_flutter * .010) * amplitude;
        float crosswind_bend = (field_wave * .024 + blade_flutter * .010) * amplitude;
        world_position.xz += wind_direction * downwind_bend * tip_weight;
        world_position.xz += wind_across * crosswind_bend * tip_weight;
        world_position.y -= downwind_bend * (.060 + wave_energy * .025) * tip_weight;
    } else if (native_atlas_card) {
        // Wall-trained bougainvillea is tied to masonry. Keep the lower card
        // vertices pinned to the woody attachment and confine motion to the
        // painted leaf, bract, and branch-tip region. Reusing free-canopy sway
        // here made entire flower masses slide away from their stems in gusts.
        float trained_gust = (broad_sway * .075 + flutter * .045) * native_tip_weight;
        world_position.xz += wind_direction * trained_gust * amplitude;
        world_position.xz += wind_across * flutter * amplitude * .075 * native_tip_weight;
        world_position.y += flutter * amplitude * .035 * native_tip_weight;
        float bract_weight = native_flower_card * native_tip_weight;
        world_position.xz += wind_across * bract_rustle * amplitude * .035 * bract_weight;
        world_position.y += bract_rustle * amplitude * .018 * bract_weight;
    } else {
        world_position.xz += wind_direction * broad_sway * amplitude * .88;
        world_position.y += sin(phase * .73 - .8) * amplitude * .075 * .88;
        world_position.xz += wind_across * flutter * amplitude * .24 * tip_weight;
        world_position.y += flutter * amplitude * .11 * tip_weight;
    }

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
    output.color = float4(
        native_atlas_card ? input.color.rgb : srgb_to_linear(input.color.rgb),
        input.color.a
    );
    output.depth = depth;
    output.kind = input.kind;
    return output;
}

[shader("vertex")]
VertexOutput vertex_main(VertexInput input) {
    return foliage_vertex_transform(input);
}

struct GrassInstance {
    float3 center : POSITION;
    float2 size : TEXCOORD0;
    uint tile : TEXCOORD1;
    float4 color : COLOR0;
};

[shader("vertex")]
VertexOutput grass_vertex_main(GrassInstance instance, uint vertex_id : SV_VertexID) {
    static const float2 corners[6] = {
        float2(-.5, -.5), float2(.5, -.5), float2(.5, .5),
        float2(-.5, -.5), float2(.5, .5), float2(-.5, .5)
    };
    float2 corner = corners[vertex_id];
    float3 position = instance.center;
    // Camera-facing width with a world-vertical axis keeps roots planted even
    // when the chase camera pitches.
    position += push.camera_right.xyz * (corner.x * instance.size.x);
    position.y += corner.y * instance.size.y;

    uint column = instance.tile & 3;
    uint row = instance.tile >> 2;
    float inset = 2.0 / 1254.0;
    float u0 = float(column) * .25 + inset;
    float u1 = float(column + 1) * .25 - inset;
    if ((instance.tile & 1) == 0) {
        float swap_u = u0;
        u0 = u1;
        u1 = swap_u;
    }
    float v0 = float(row) * .25 + inset;
    float v1 = float(row + 1) * .25 - inset;
    float2 uv = float2(lerp(u0, u1, corner.x + .5),
                       lerp(v1, v0, corner.y + .5));

    VertexInput input;
    input.position = position;
    input.uv = uv;
    input.color = instance.color;
    input.kind = 1;
    return foliage_vertex_transform(input);
}

[shader("fragment")]
float4 fragment_main(VertexOutput input) : SV_Target {
    float4 texel = foliage_atlas.Sample(foliage_sampler, input.uv);
    bool native_atlas_color = input.kind == 0 && input.color.a > 1.5;
    bool young_native_growth = native_atlas_color && input.color.a > 2.5;
    // Cutout leaves remain crisp and depth-stable around overlapping blobs.
    // Generated bougainvillea contains much finer twigs and bract tips than
    // the painted foliage mask. Give those native-color cards a derivative-
    // aware coverage edge so distant mip levels do not shimmer or collapse
    // into dark, one-pixel outlines.
    float alpha_threshold = native_atlas_color ? .24 : .16;
    float alpha_width = native_atlas_color ? max(fwidth(texel.a) * .72, .025) : .001;
    float coverage = smoothstep(
        alpha_threshold - alpha_width,
        alpha_threshold + alpha_width,
        texel.a
    );
    if (coverage < .01) discard;
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
    if (native_atlas_color) {
        color = texel.rgb * input.color.rrr;
    }

    // Leaf-sprig tips catch the same warm sunlight as the crown crests. A
    // restrained, daylight-gated warm lift on the upper (tip) leaves keeps the
    // cards in the canopy's hand-painted temperature story instead of reading
    // as flat tinted cutouts, while the base leaves hold the cooler body value.
    // Atlas cells are four-by-four, so the tile-local v isolates the tips.
    float2 tile_uv = frac(input.uv * 4.0);
    float tip = smoothstep(.30, .95, 1.0 - tile_uv.y) * smoothstep(.34, .80, luminance);
    float daylight = saturate(push.sun.w);
    if (!native_atlas_color) {
        color *= 1.0 + tip * daylight * .14;
        color += float3(.055, .043, .010) * tip * daylight;
    } else if (native_atlas_color) {
        // Keep the generated botanical color, but seat it in the scene's
        // temperature story: cooler protected bases and gently warmer,
        // sun-facing tips. This is intentionally subtler than relighting the
        // image, which would flatten the atlas's painted leaf and bract detail.
        float3 native_shadow = float3(.90, .96, 1.02);
        float3 native_sun = float3(1.055, 1.015, .91);
        color *= lerp(native_shadow, native_sun, tip * daylight);

        // Flower tiles occupy the lower three rows of the native atlas. Preserve
        // their real cream-and-gold florets by selectively lifting only the
        // bright warm source pixels. Because this happens after the same card
        // vertices receive wind deformation, centers cannot drift away from
        // their surrounding papery bracts.
        float flower_tile = step(.25, input.uv.y);
        float source_bract_chroma = smoothstep(.04, .28, max(texel.r, texel.b) - texel.g);

        // Older, sheltered bracts lose a little chroma before they fall while
        // fresh terminal growth stays saturated. The CPU card-value gradient
        // already describes that age/exposure relationship, so reuse it here
        // and fade only colorful bract pixels toward a warm paper value.
        // Centers are restored immediately below, and green leaf pixels never
        // enter this mask.
        float old_bract = flower_tile * source_bract_chroma *
            saturate((.958 - input.color.r) / .063);
        float card_luminance = dot(color, float3(.2126, .7152, .0722));
        float3 faded_bract = card_luminance * float3(1.08, .96, .91);
        color = lerp(color, faded_bract, old_bract * .24);

        float warm_cream = smoothstep(.08, .30, texel.r - texel.b);
        float pale_center = smoothstep(.62, .88, luminance);
        float center_signal = flower_tile * warm_cream * pale_center;
        float3 center_color = float3(1.00, .80, .34) * input.color.rrr;
        color = lerp(color, center_color, center_signal * .52);

        // Camera-facing cards have no per-pixel normal, but their facing
        // direction is known. When the sun lies behind the card relative to
        // the viewer, lift only saturated bract pixels to suggest thin-paper
        // transmission. Green-dominant leaves and woody pixels contribute
        // nothing, and daylight gates the effect completely at night.
        float view_sun_alignment = dot(
            normalize(push.camera_forward.xyz),
            normalize(push.sun.xyz)
        );
        float backlight = smoothstep(.12, .82, view_sun_alignment) * daylight;
        float transmission = flower_tile * source_bract_chroma * backlight;
        color += texel.rgb * transmission * .13;
        color += float3(.025, .012, .004) * transmission;

        // Fresh bougainvillea leaves commonly emerge bronze-red before
        // hardening to green. CPU metadata marks only basal and renewal cards;
        // tint green-dominant source pixels while leaving wood and transparent
        // gaps untouched. Established crown cards retain their atlas color.
        float green_leaf = smoothstep(.006, .14, texel.g - max(texel.r, texel.b));
        float3 bronze_flush = color * float3(1.32, .68, .58) + float3(.055, .004, .001);
        color = lerp(color, bronze_flush, green_leaf * (young_native_growth ? .46 : 0.0));
    }
    if (input.kind == 1) {
        // Grass uses the atlas strictly as a grayscale value/alpha mask. The
        // CPU tint is derived from the live terrain beneath the card. Ease out
        // the atlas contrast with the same edge coverage used for the field
        // falloff, leaving the final visible blades at the terrain's value.
        // Grass atlas pixels skew dark, so use a narrower, higher value range
        // than canopy cards. This keeps texture definition without pulling the
        // field below the luminance-matched CPU tint.
        float grass_detail = lerp(.82, 1.30, smoothstep(.06, .94, luminance)) *
                             lerp(.94, 1.08, tip);
        color = input.color.rgb * lerp(1.0, grass_detail, input.color.a);
    }

    float alpha = native_atlas_color ? coverage : texel.a * input.color.a;
    return float4(lerp(color, srgb_to_linear(push.fog_color.rgb), fog), alpha);
}
