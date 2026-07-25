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
    float3 normal : NORMAL0;
    float2 material : TEXCOORD1;
};

struct VertexOutput {
    float4 position : SV_Position;
    float4 color : COLOR0;
    float depth : TEXCOORD0;
    float3 world_position : TEXCOORD1;
    float kind : TEXCOORD2;
    float3 normal : TEXCOORD3;
    float2 material : TEXCOORD4;
};

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
    if (input.kind > 2.5 && input.kind < 3.5) {
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
        receiver_y + .020,
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
    output.kind = 0;
    output.normal = float3(0, 1, 0);
    output.material = 0;
    return output;
}

[shader("fragment")]
float4 shadow_fragment(VertexOutput input) : SV_Target {
    return float4(.030, .036, .039, 1.0);
}

float3 shade_imported_material(VertexOutput input) {
    float3 base_color = input.color.rgb;
    float3 normal = normalize(input.normal);
    float3 sun_direction = normalize(push.sun.xyz);
    float3 view_direction = normalize(push.camera_position.xyz - input.world_position);
    float3 half_direction = normalize(sun_direction + view_direction);
    float metallic = saturate(input.material.x);
    float roughness = clamp(input.material.y, .04, 1.0);

    float direct = saturate(dot(normal, sun_direction));
    float sky = saturate(normal.y * .5 + .5);
    float daylight = saturate(push.sun.w);
    float diffuse_light = .22 + sky * .16 + direct * lerp(.26, .78, daylight);
    float3 diffuse = base_color * diffuse_light * (1.0 - metallic * .72);

    // A compact metallic-roughness response gives imported assets readable
    // form without adding a separate texture pipeline to the world pass.
    float3 f0 = lerp(float3(.04, .04, .04), base_color, metallic);
    float specular_power = lerp(128.0, 6.0, roughness);
    float specular_strength = pow(saturate(dot(normal, half_direction)), specular_power);
    specular_strength *= lerp(.72, .09, roughness) * direct * lerp(.18, 1.0, daylight);
    return saturate(diffuse + f0 * specular_strength);
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
    return saturate(input.color.rgb * (.82 + rim) +
                    highlight_color * (broad_gloss + sharp_glint));
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
    float value = lerp(.82, 1.16, broad) * lerp(.94, 1.06, grain);
    float3 color = input.color.rgb * value;

    // The swept profile places the carriageway between one- and two-thirds
    // across its UV span. Soft dust at those seams integrates it with the
    // earthen shoulder, while paired low-contrast wheel paths imply use.
    float road_mask = smoothstep(.305, .365, uv.x) *
                      (1.0 - smoothstep(.635, .695, uv.x));
    float seam_distance = abs(abs(uv.x - .5) - .1667);
    float dusty_seam = (1.0 - smoothstep(.018, .070, seam_distance)) * road_mask;
    float3 dust = float3(.47, .36, .20);
    color = lerp(color, color + dust * .11, dusty_seam * (.45 + broad * .35));

    float wheel_distance = min(abs(uv.x - .415), abs(uv.x - .585));
    float wheel_wear = (1.0 - smoothstep(.018, .052, wheel_distance)) * road_mask;
    color *= 1.0 - wheel_wear * lerp(.045, .115, broad);

    // Material-specific marks remain tonal rather than literal: broken pale
    // aggregate for gravel, offset cool joints for cobble, and warm ruts for
    // dirt. Pavement is constant per swept edge and interpolates naturally at
    // the mixed-material junction.
    float gravel_weight = saturate(1.0 - abs(pavement - 1.0));
    float cobble_weight = saturate(1.0 - abs(pavement - 2.0));
    float dirt_weight = saturate(1.0 - abs(pavement - 3.0));
    float gravel = smoothstep(.77, .94, hash12(world * 2.45 + float2(8.1, .6)));
    color += gravel * gravel_weight * road_mask * float3(.10, .085, .055);

    float cobble_row = floor(uv.y * .58);
    float cobble_cross = abs(frac(uv.x * 13.0 + frac(cobble_row * .5) * .5) - .5);
    float cobble_along = abs(frac(uv.y * .58) - .5);
    float cobble_joint = 1.0 - smoothstep(.035, .085, min(cobble_cross, cobble_along));
    color *= 1.0 - cobble_joint * cobble_weight * road_mask * .20;

    float rut = 1.0 - smoothstep(.028, .075, wheel_distance);
    color = lerp(color, color * float3(.91, .84, .75), rut * dirt_weight * road_mask * .55);

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
    // Indexed clipmap grids retain sea-level vertices so their topology stays
    // reusable. Do not let those terrain fragments cover the ocean pass.
    if (input.kind > 1.5 && input.world_position.y <= .001) {
        discard;
    }
    float fog = saturate((input.depth - push.projection.z) /
                         max(push.projection.w - push.projection.z, .001));
    float3 base = input.kind > 5.5 && input.kind < 6.5 ?
                  shade_eye(input) :
                  (input.kind > .5 && input.kind < 1.5 ?
                  shade_water(input) :
                  (input.kind > 2.5 && input.kind < 3.5 ?
                   shade_foliage(input) :
                   (input.kind > 3.5 && input.kind < 4.5 ?
                    shade_road(input) :
                    (input.kind > 4.5 && input.kind < 5.5 ?
                     shade_imported_material(input) : input.color.rgb))));
    return float4(lerp(base, srgb_to_linear(push.fog_color.rgb), fog), input.color.a);
}
