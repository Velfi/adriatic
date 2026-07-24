struct SkyPush {
    float4 camera_right;   // xyz basis, w aspect ratio
    float4 camera_up;      // xyz basis, w focal length
    float4 camera_forward;
    float4 sun_direction;  // xyz direction, w deterministic cloud seed
    float4 time_light;     // world minutes, cloud seconds, daylight, twilight
    float4 wind_cloud;     // wind xy, cloud cover, precipitation
    float4 haze_severity;  // haze, severity, reserved, reserved
};
[[vk::push_constant]] ConstantBuffer<SkyPush> sky;

struct SkyOutput {
    float4 position : SV_Position;
    float2 lens : TEXCOORD0;
};

float hash31(float3 p) {
    p = frac(p * .1031);
    p += dot(p, p.yzx + 33.33);
    return frac((p.x + p.y) * p.z);
}

float noise3(float3 p) {
    float3 i = floor(p), f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    return lerp(lerp(lerp(hash31(i), hash31(i + float3(1,0,0)), f.x),
                     lerp(hash31(i + float3(0,1,0)), hash31(i + float3(1,1,0)), f.x), f.y),
                lerp(lerp(hash31(i + float3(0,0,1)), hash31(i + float3(1,0,1)), f.x),
                     lerp(hash31(i + float3(0,1,1)), hash31(i + float3(1,1,1)), f.x), f.y), f.z);
}

float fbm3(float3 p) {
    float value = noise3(p) * .58;
    value += noise3(p * 2.03 + 7.1) * .28;
    value += noise3(p * 4.11 - 3.7) * .14;
    return value;
}

[shader("vertex")]
SkyOutput sky_vertex(uint vertex_id : SV_VertexID) {
    SkyOutput output;
    float2 position = vertex_id == 0 ? float2(-1, -1) :
                      vertex_id == 1 ? float2(3, -1) : float2(-1, 3);
    output.position = float4(position, 0, 1);
    output.lens = position;
    return output;
}

[shader("fragment")]
float4 sky_fragment(SkyOutput input) : SV_Target {
    float focal = max(sky.camera_up.w, .001);
    float3 ray = normalize(
        sky.camera_forward.xyz +
        sky.camera_right.xyz * input.lens.x * sky.camera_right.w / focal -
        sky.camera_up.xyz * input.lens.y / focal
    );
    float3 sun_dir = normalize(sky.sun_direction.xyz);
    float world_minutes = sky.time_light.x;
    float cloud_seconds = sky.time_light.y;
    float daylight = sky.time_light.z;
    float twilight = sky.time_light.w;
    float2 wind = sky.wind_cloud.xy;
    float cloud_cover = sky.wind_cloud.z;
    float precipitation = sky.wind_cloud.w;
    float haze = sky.haze_severity.x;
    float severity = sky.haze_severity.y;
    float elevation = max(ray.y, 0.0);

    const float3 zenith_color = float3(.115, .35, .56);
    const float3 upper_color = float3(.27, .54, .70);
    const float3 horizon_color = float3(.72, .82, .82);
    const float3 night_zenith = float3(.027, .075, .157);
    const float3 night_horizon = float3(.094, .157, .231);
    float3 color = lerp(horizon_color, upper_color, smoothstep(0.0, .30, elevation));
    color = lerp(color, zenith_color, smoothstep(.22, 1.0, elevation));
    float storm = saturate(severity * .68 + precipitation * .52);
    float overcast = saturate(cloud_cover * .72 + precipitation * .38);
    float3 storm_sky = lerp(
        float3(.36, .43, .46),
        float3(.14, .23, .30),
        smoothstep(0.0, .72, elevation)
    );
    storm_sky = lerp(
        storm_sky,
        float3(.44, .49, .50),
        haze * (1.0 - smoothstep(.08, .62, elevation)) * .55
    );
    color = lerp(color, storm_sky, storm * .82);
    float3 night_sky = lerp(
        night_horizon,
        night_zenith,
        smoothstep(0.0, .72, elevation)
    );
    color = lerp(night_sky, color, daylight);
    color += float3(.34, .16, .08) *
             twilight * (1.0 - smoothstep(0.0, .42, elevation));

    float sun = max(dot(ray, sun_dir), 0.0);
    float sun_visibility = 1.0 - overcast * .92;
    color += float3(1.0, .72, .38) * pow(sun, 96.0) *
             1.25 * daylight * sun_visibility;
    color += float3(1.0, .78, .52) * pow(sun, 12.0) * .14 *
             (daylight + twilight * .5) * lerp(1.0, .22, overcast);

    // Fronts change density and palette without replacing the cloud field.
    float2 drift = wind * cloud_seconds * .000125;
    float seed = frac(sky.sun_direction.w * .000013);
    float3 seed_offset = float3(seed * 31.7, seed * 17.3, seed * 43.1);
    float tower_field = fbm3(ray * 3.1 + float3(drift.x, 0, drift.y) + seed_offset);
    float cloud_top = .11 + smoothstep(.34, .72, tower_field) * .37;
    float3 cloud_uv = ray * 7.2 +
        float3(elevation * 5.3, -elevation * 10.5, elevation * 3.1);
    cloud_uv.xz += drift;
    cloud_uv += seed_offset;
    float body_field = fbm3(cloud_uv) +
        fbm3(ray * 13.4 + float3(-4,8,2.7) * elevation +
             float3(drift.x,0,drift.y)) * .18;
    float base = smoothstep(.002, .048, elevation);
    float top = 1.0 - smoothstep(cloud_top - .045, cloud_top + .025, elevation);
    float threshold = lerp(.55, .41, cloud_cover);
    float bank = .5 + .5 * sin(ray.x * 10.7 + ray.z * 6.2 + cloud_seconds * .0015 + seed * 8.0);
    float cloud_field = body_field * .82 + bank * .18;
    float density = smoothstep(
        threshold,
        threshold + .12,
        cloud_field + (cloud_top - elevation) * .28
    ) * base * top;
    density *= smoothstep(.02, .11, elevation);
    float crown = smoothstep(.16, max(cloud_top, .17), elevation);
    float broad = fbm3(cloud_uv * .43 + 9.7);
    float underside = (1.0 - crown) * smoothstep(.34, .70, 1.0 - broad);
    float sunward = smoothstep(
        -.2,
        .72,
        dot(normalize(float3(ray.x, max(ray.y,.08), ray.z)), sun_dir)
    );
    float3 cloud_shadow = lerp(float3(.52,.63,.68), float3(.25,.32,.35), storm);
    float3 cloud_body = lerp(float3(.84,.88,.86), float3(.49,.55,.56), storm);
    float3 cloud_light = lerp(float3(1.0,.93,.78), float3(.69,.72,.70), storm);
    float light_region = smoothstep(.47, .69, broad + crown * .22 + sunward * .24);
    float3 cloud = lerp(cloud_body, cloud_light, light_region * .72);
    cloud = lerp(cloud, cloud_shadow, underside * lerp(.24, .62, storm));
    cloud = lerp(cloud * float3(.09, .14, .24), cloud, daylight);
    density = saturate(density * lerp(.76, 1.24, overcast));
    color = lerp(color, cloud, density * lerp(.32, .68, overcast));
    return float4(color, 1);
}
