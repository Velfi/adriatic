struct SkyPush {
    float4 camera_right;   // xyz basis, w aspect ratio
    float4 camera_up;      // xyz basis, w focal length
    float4 camera_forward;
    float4 sun_direction;  // xyz direction, w deterministic cloud seed
    float4 moon_direction; // xyz direction, w illuminated fraction
    float4 time_light;     // world minutes, cloud seconds, daylight, twilight
    float4 wind_cloud;     // wind xy, cloud cover, precipitation
    float4 haze_severity;  // haze, severity, elapsed world days, reserved
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

float3 rotate_about_axis(float3 value, float3 axis, float angle) {
    float sine, cosine;
    sincos(angle, sine, cosine);
    return value * cosine + cross(axis, value) * sine +
           axis * dot(axis, value) * (1.0 - cosine);
}

float2 hash22(float2 p) {
    float3 p3 = frac(float3(p.xyx) * float3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.xx + p3.yz) * p3.zy);
}

float3 stellar_color(float temperature_sample) {
    // Most naked-eye stars appear close to white. Preserve restrained warm
    // giant and blue-white branches without the saturated "Christmas light"
    // colors common to procedural skies.
    float3 warm = float3(1.0, .72, .48);
    float3 solar = float3(1.0, .94, .82);
    float3 blue = float3(.72, .84, 1.0);
    return temperature_sample < .56
        ? lerp(warm, solar, smoothstep(.02, .56, temperature_sample))
        : lerp(solar, blue, smoothstep(.56, .98, temperature_sample));
}

float3 procedural_stars(
    float3 celestial_ray,
    float visibility,
    float cloud_seconds,
    float elevation
) {
    const float PI = 3.14159265359;
    const float TAU = 6.28318530718;
    float longitude = atan2(celestial_ray.z, celestial_ray.x) / TAU + .5;
    float latitude = asin(clamp(celestial_ray.y, -1.0, 1.0)) / PI + .5;
    float2 grid_size = float2(720, 360);
    float2 grid_position = float2(longitude, latitude) * grid_size;
    float2 cell = floor(grid_position);
    float2 random = hash22(cell);

    float3 galactic_normal = normalize(float3(.31, .79, -.53));
    float galactic_latitude = abs(dot(celestial_ray, galactic_normal));
    float milky_density = exp(-galactic_latitude * 13.5);
    float dust = fbm3(celestial_ray * 5.2 + 11.7);
    float density = lerp(.045, .16, milky_density * lerp(.55, 1.0, dust));
    float exists = random.x < density ? 1.0 : 0.0;

    float2 candidate = hash22(cell + 19.17);
    float2 delta = frac(grid_position) - candidate;
    delta.x *= max(cos((latitude - .5) * PI), .08) * 2.0;
    float angular_distance = length(delta) * PI / grid_size.y;

    // The logarithmic apparent-magnitude scale naturally produces many faint
    // points and very few bright stars. Brighter stars receive a slightly
    // larger reconstruction footprint so they survive subpixel sampling.
    float magnitude_random = max(hash22(cell + 47.91).x, .00001);
    float apparent_magnitude = 6.2 + log10(magnitude_random) / .60;
    apparent_magnitude = max(apparent_magnitude, -1.45);
    float flux = pow(2.512, -apparent_magnitude);
    float radius = lerp(.00072, .00215, saturate((2.2 - apparent_magnitude) / 3.7));
    float point = 1.0 - smoothstep(radius * .35, radius, angular_distance);

    float scintillation_seed = hash22(cell + 83.4).y * TAU;
    float horizon_airmass = 1.0 - saturate(elevation * 2.4);
    float scintillation =
        1.0 + sin(cloud_seconds * (4.1 + random.y * 5.7) + scintillation_seed) *
        (.025 + horizon_airmass * .16);
    float temperature = hash22(cell + 123.7).y;
    float3 color = stellar_color(temperature);
    float intensity = min(.42 + flux * .36, 3.2) * scintillation;
    return color * point * exists * intensity * visibility;
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
    float3 moon_dir = normalize(sky.moon_direction.xyz);
    float world_minutes = sky.time_light.x;
    float cloud_seconds = sky.time_light.y;
    float daylight = sky.time_light.z;
    float twilight = sky.time_light.w;
    float2 wind = sky.wind_cloud.xy;
    float cloud_cover = sky.wind_cloud.z;
    float precipitation = sky.wind_cloud.w;
    float haze = sky.haze_severity.x;
    float severity = sky.haze_severity.y;
    // Preserve observer-local inputs before reconstructing weather along the
    // current view ray. Solar visibility must be evaluated behind the viewer,
    // independently from rain toward the antisolar bow.
    float observer_cloud_cover = cloud_cover;
    float observer_severity = severity;
    float world_days = sky.haze_severity.z;
    float elevation = max(ray.y, 0.0);
    // Red dawn and dusk are directional low-sun scattering, not a uniform
    // orange ring. Clock gates distinguish the eastern morning glow from the
    // western evening afterglow while solar elevation shapes both transitions.
    float morning = smoothstep(4.0 * 60.0, 5.5 * 60.0, world_minutes) *
                    (1.0 - smoothstep(7.0 * 60.0, 8.5 * 60.0, world_minutes));
    float evening = smoothstep(15.5 * 60.0, 17.0 * 60.0, world_minutes) *
                    (1.0 - smoothstep(20.5 * 60.0, 22.0 * 60.0, world_minutes));
    float sunset_altitude = smoothstep(-.20, .055, sun_dir.y) *
                            (1.0 - smoothstep(.055, .24, sun_dir.y));
    float sunward_horizon = pow(saturate(
        dot(normalize(ray.xz + float2(.0001, 0)), normalize(sun_dir.xz + float2(.0001, 0))) * .5 + .5
    ), 3.2) * (1.0 - smoothstep(.015, .48, elevation));
    float storm_seed = frac(sky.sun_direction.w * .000013);
    float wind_length = length(wind);
    float2 wind_direction = wind_length > .05 ? wind / wind_length : float2(1, 0);
    float storm_bearing = dot(normalize(ray.xz + float2(.0001, 0)), wind_direction);

    // Reconstruct the active analytic front across the dome. The CPU passes
    // the camera's signed distance from the front in front-width units and
    // the number of widths covered by a horizon ray. This keeps sky weather
    // geographically aligned with the same moving band sampled by gameplay.
    if (sky.haze_severity.w > 0.0) {
        float front_coordinate = sky.camera_forward.w +
            dot(ray.xz, wind_direction) * sky.haze_severity.w;
        float boundary_warp = sin(
            dot(ray.xz, float2(-wind_direction.y, wind_direction.x)) * 9.0 +
            cloud_seconds * .0017 + storm_seed * 21.0
        ) * .12;
        front_coordinate += boundary_warp;
        // Give the front a long atmospheric shoulder. Cloud and haze arrive
        // first, while the denser rain core remains farther inside the band;
        // this avoids a visible clear/storm seam across the dome.
        float directional_front = smoothstep(-1.05, -.15, front_coordinate) *
                                  (1.0 - smoothstep(.15, 1.05, front_coordinate));
        float embedded_cell = .82 + .18 * smoothstep(
            .22,
            .78,
            fbm3(float3(ray.xz * 4.8, storm_seed * 17.0 + cloud_seconds * .0004))
        );
        directional_front *= embedded_cell;
        float rain_core = directional_front * smoothstep(.12, .88, directional_front);
        float haze_shoulder = smoothstep(.02, .82, directional_front);
        float background_cloud = min(cloud_cover, .42);
        float background_haze = min(haze, .24);
        float background_severity = min(severity, .18);
        cloud_cover = lerp(background_cloud, max(cloud_cover, .94), directional_front);
        precipitation = lerp(0.0, max(precipitation, .88), rain_core);
        haze = lerp(background_haze, max(haze, .68), haze_shoulder);
        severity = lerp(background_severity, max(severity, .92),
                        directional_front * directional_front);
    }
    float dry_air = (1.0 - smoothstep(.10, .62, precipitation)) *
                    (1.0 - smoothstep(.42, .88, severity));
    float aerosol = lerp(.48, 1.0, smoothstep(.025, .38, haze));
    float broken_clouds = 1.0 +
        smoothstep(.08, .34, cloud_cover) * (1.0 - smoothstep(.62, .90, cloud_cover)) * .55;
    float red_sky = max(morning, evening) * sunset_altitude * dry_air * aerosol;

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
    // A front does not darken the dome uniformly. Broad, wind-aligned shelf
    // structure makes one horizon visibly more threatening while leaving a
    // weaker shoulder behind the aircraft.
    float shelf_noise = fbm3(float3(
        ray.x * 2.7 + wind_direction.x * cloud_seconds * .00022,
        ray.z * 2.7 + wind_direction.y * cloud_seconds * .00022,
        storm_seed * 29.0
    ));
    float shelf_horizon = (1.0 - smoothstep(.04, .34, elevation)) *
                          smoothstep(.31, .68, shelf_noise + storm_bearing * .16);
    float3 shelf_color = lerp(float3(.29, .35, .37), float3(.105, .16, .20), severity);
    color = lerp(color, shelf_color, shelf_horizon * storm * .72);
    float3 night_sky = lerp(
        night_horizon,
        night_zenith,
        smoothstep(0.0, .72, elevation)
    );
    color = lerp(night_sky, color, daylight);
    color += float3(.34, .16, .08) *
             twilight * (1.0 - smoothstep(0.0, .42, elevation));
    color += float3(.52, .105, .025) * red_sky * sunward_horizon * broken_clouds;
    color += float3(.18, .025, .012) * red_sky *
             pow(sunward_horizon, 2.0) * (1.0 - daylight) * .55;

    // Rainbows are view-dependent, not objects suspended at a fixed point in
    // the world.  The primary bow lies on a ~42 degree cone around the
    // antisolar direction.  Use the live sun vector and precipitation so the
    // bow moves with the light and vanishes when either sunlight or rain is
    // absent.  A broad rain-cell mask keeps clear portions of the sky from
    // receiving a perfectly uniform, diagram-like ring.
    const float DEG = 0.01745329252;
    float sun_cloud_cover = observer_cloud_cover;
    float sun_severity = observer_severity;
    if (sky.haze_severity.w > 0.0) {
        float sun_front_coordinate = sky.camera_forward.w +
            dot(sun_dir.xz, wind_direction) * sky.haze_severity.w;
        sun_front_coordinate += sin(
            dot(sun_dir.xz, float2(-wind_direction.y, wind_direction.x)) * 9.0 +
            cloud_seconds * .0017 + storm_seed * 21.0
        ) * .12;
        float sun_front = smoothstep(-1.05, -.15, sun_front_coordinate) *
                          (1.0 - smoothstep(.15, 1.05, sun_front_coordinate));
        sun_cloud_cover = lerp(min(observer_cloud_cover, .42), max(observer_cloud_cover, .94), sun_front);
        sun_severity = lerp(min(observer_severity, .18), max(observer_severity, .92), sun_front * sun_front);
    }
    float direct_sun = smoothstep(.015, .16, sun_dir.y) * daylight *
                       (1.0 - saturate(sun_cloud_cover * .68 + sun_severity * .18));
    float bow_dot = dot(ray, -sun_dir);
    bool primary_candidate = bow_dot > cos(43.8 * DEG) && bow_dot < cos(39.5 * DEG);
    bool secondary_candidate = precipitation > .52 &&
        bow_dot > cos(54.2 * DEG) && bow_dot < cos(49.7 * DEG);

    // Avoid the costly inverse trig and spectral exponentials for clear
    // weather, darkness, and almost every pixel outside the two narrow cones.
    if (precipitation > .08 && direct_sun > .001 && ray.y > -.015 &&
        (primary_candidate || secondary_candidate)) {
        float rain_cell = fbm3(float3(
            ray.x * 2.15 + wind_direction.x * cloud_seconds * .00016,
            ray.z * 2.15 + wind_direction.y * cloud_seconds * .00016,
            storm_seed * 41.0 + 9.0
        ));
        float rain_available = smoothstep(.08, .62, precipitation) *
                               smoothstep(.24, .72, rain_cell + precipitation * .34);
        float bow_visibility = rain_available * direct_sun *
                               smoothstep(-.015, .035, ray.y);
        float bow_angle = acos(clamp(bow_dot, -1.0, 1.0));

        // The angular ordering follows water-droplet dispersion: violet is on
        // the inner edge and red on the outer edge.
        if (primary_candidate) {
            float3 rainbow = float3(0, 0, 0);
            rainbow += float3(.50, .16, .72) * exp(-pow((bow_angle - 40.55 * DEG) / (.34 * DEG), 2.0));
            rainbow += float3(.16, .31, .92) * exp(-pow((bow_angle - 40.92 * DEG) / (.35 * DEG), 2.0));
            rainbow += float3(.10, .70, .78) * exp(-pow((bow_angle - 41.28 * DEG) / (.36 * DEG), 2.0));
            rainbow += float3(.18, .82, .32) * exp(-pow((bow_angle - 41.64 * DEG) / (.38 * DEG), 2.0));
            rainbow += float3(.96, .75, .12) * exp(-pow((bow_angle - 42.00 * DEG) / (.39 * DEG), 2.0));
            rainbow += float3(1.00, .37, .08) * exp(-pow((bow_angle - 42.36 * DEG) / (.40 * DEG), 2.0));
            rainbow += float3(.92, .08, .055) * exp(-pow((bow_angle - 42.74 * DEG) / (.41 * DEG), 2.0));
            color += rainbow * bow_visibility * .34;
        }

        // A second internal reflection reverses the secondary bow's colors.
        if (secondary_candidate) {
            float3 secondary = float3(0, 0, 0);
            secondary += float3(.90, .09, .06) * exp(-pow((bow_angle - 50.7 * DEG) / (.48 * DEG), 2.0));
            secondary += float3(.94, .72, .13) * exp(-pow((bow_angle - 51.3 * DEG) / (.48 * DEG), 2.0));
            secondary += float3(.16, .75, .34) * exp(-pow((bow_angle - 51.9 * DEG) / (.48 * DEG), 2.0));
            secondary += float3(.14, .32, .88) * exp(-pow((bow_angle - 52.5 * DEG) / (.48 * DEG), 2.0));
            secondary += float3(.48, .15, .68) * exp(-pow((bow_angle - 53.1 * DEG) / (.48 * DEG), 2.0));
            color += secondary * bow_visibility * smoothstep(.52, .92, precipitation) * .16;
        }
    }

    // At Adriatic latitude, the celestial pole sits about 43 degrees above
    // the northern horizon. Stars advance by one extra rotation per tropical
    // year relative to solar time, reproducing the roughly four-minute daily
    // sidereal drift and seasonal constellations.
    const float TAU = 6.28318530718;
    float latitude_radians = .75049;
    float3 celestial_axis = normalize(float3(0, sin(latitude_radians), cos(latitude_radians)));
    float sidereal_angle =
        (world_minutes / 1440.0 + world_days / 365.2422) * TAU;
    float3 celestial_ray = rotate_about_axis(ray, celestial_axis, -sidereal_angle);
    float moon_above_horizon = smoothstep(-.03, .10, moon_dir.y);
    float lunar_skyglow = sky.moon_direction.w * moon_above_horizon;
    float moon_proximity = pow(saturate(dot(ray, moon_dir) * .5 + .5), 12.0);
    float star_visibility =
        (1.0 - daylight) *
        (1.0 - twilight * .92) *
        (1.0 - saturate(cloud_cover * .88 + precipitation * .72)) *
        (1.0 - haze * .68) *
        (1.0 - lunar_skyglow * (.38 + moon_proximity * .52)) *
        smoothstep(-.01, .055, ray.y);

    float3 galactic_normal = normalize(float3(.31, .79, -.53));
    float galactic_latitude = abs(dot(celestial_ray, galactic_normal));
    float milky_band = exp(-galactic_latitude * 8.5);
    float milky_structure = fbm3(celestial_ray * 4.7 + 21.3);
    float milky_dust = smoothstep(.34, .72, milky_structure);
    color += float3(.17, .20, .27) * milky_band * milky_dust *
             star_visibility * .16;
    color += procedural_stars(
        celestial_ray,
        star_visibility,
        cloud_seconds,
        elevation
    );

    float sun = max(dot(ray, sun_dir), 0.0);
    float sun_visibility = 1.0 - overcast * .92;
    // Keep a readable solar disc inside the broad atmospheric bloom. The
    // previous power lobes produced only a glow, so the sun had no silhouette
    // even when the camera looked directly at it.
    float sun_disc = smoothstep(.9987, .99955, sun);
    float3 sun_disc_color = lerp(
        float3(1.0, .61, .25),
        float3(1.0, .91, .62),
        daylight
    );
    color = lerp(
        color,
        sun_disc_color,
        sun_disc * sun_visibility * saturate(.72 + daylight + twilight * .35)
    );
    color += float3(1.0, .72, .38) * pow(sun, 96.0) *
             1.25 * daylight * sun_visibility;
    color += float3(1.0, .78, .52) * pow(sun, 12.0) * .14 *
             (daylight + twilight * .5) * lerp(1.0, .22, overcast);

    // Resolve the lunar phase on a sphere instead of drawing a flat crescent.
    // The surface normal faces the viewer at disc center, and its dot product
    // with the solar direction produces the correct waxing/waning terminator.
    const float moon_angular_radius = .0092;
    float moon_cos = dot(ray, moon_dir);
    float moon_radius = acos(clamp(moon_cos, -1.0, 1.0));
    float moon_disc = 1.0 - smoothstep(moon_angular_radius * .88, moon_angular_radius, moon_radius);
    if (moon_disc > 0.0 && moon_dir.y > -.015) {
        float3 tangent_x = normalize(cross(
            abs(moon_dir.y) < .96 ? float3(0, 1, 0) : float3(1, 0, 0),
            moon_dir
        ));
        float3 tangent_y = cross(moon_dir, tangent_x);
        float2 moon_uv = float2(dot(ray, tangent_x), dot(ray, tangent_y)) /
                         moon_angular_radius;
        float sphere_z = sqrt(saturate(1.0 - dot(moon_uv, moon_uv)));
        float3 surface_normal = normalize(
            tangent_x * moon_uv.x + tangent_y * moon_uv.y - moon_dir * sphere_z
        );
        float lunar_light = smoothstep(-.025, .035, dot(surface_normal, sun_dir));
        float earthshine = lerp(.075, .018, sky.moon_direction.w);
        float maria = .90 + .10 * noise3(surface_normal * 17.0 + 4.2);
        float3 moon_color = float3(.82, .86, .88) * maria *
                            max(lunar_light, earthshine);
        float moon_visibility = (1.0 - overcast * .94) *
                                saturate((moon_dir.y + .015) * 10.0) *
                                lerp(1.0, .23, daylight);
        color = lerp(color, moon_color, moon_disc * moon_visibility);
    }

    // Fronts change density and palette without replacing the cloud field.
    float2 drift = wind * cloud_seconds * .000125;
    float seed = storm_seed;
    float3 seed_offset = float3(seed * 31.7, seed * 17.3, seed * 43.1);
    float tower_field = fbm3(ray * lerp(3.1, 2.35, storm) + float3(drift.x, 0, drift.y) + seed_offset);
    float cloud_top = .11 + smoothstep(.34, .72, tower_field) * lerp(.37, .55, storm);
    float3 cloud_uv = ray * 7.2 +
        float3(elevation * 5.3, -elevation * 10.5, elevation * 3.1);
    cloud_uv.xz += drift;
    cloud_uv += seed_offset;
    float body_field = fbm3(cloud_uv) +
        fbm3(ray * 13.4 + float3(-4,8,2.7) * elevation +
             float3(drift.x,0,drift.y)) * .18;
    float storm_base = lerp(.048, .018, storm);
    float base = smoothstep(.002, storm_base, elevation);
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
    float sunset_cloud_light = red_sky * sunward_horizon *
        smoothstep(.08, .42, cloud_cover) * (1.0 - smoothstep(.76, .96, cloud_cover));
    cloud_light = lerp(cloud_light, float3(1.0, .31, .105), sunset_cloud_light * .82);
    cloud_body = lerp(cloud_body, float3(.72, .20, .12), sunset_cloud_light * .36);
    float light_region = smoothstep(.47, .69, broad + crown * .22 + sunward * .24);
    float3 cloud = lerp(cloud_body, cloud_light, light_region * .72);
    cloud = lerp(cloud, cloud_shadow, underside * lerp(.24, .62, storm));
    // Stacked scud beneath the main deck gives severe weather depth instead
    // of reading as the clear cloud field with a darker palette.
    float scud_field = fbm3(
        ray * 11.7 + float3(drift.x * 1.8, -cloud_seconds * .00028, drift.y * 1.8) +
        seed_offset * 1.9
    );
    float scud_height = smoothstep(.015, .17, elevation) * (1.0 - smoothstep(.17, .31, elevation));
    float scud = smoothstep(.54, .72, scud_field + shelf_horizon * .15) *
                 scud_height * storm;
    cloud = lerp(cloud, cloud_shadow * .72, scud * .78);
    density = saturate(density + scud * .58);
    cloud = lerp(cloud * float3(.09, .14, .24), cloud, daylight);
    density = saturate(density * lerp(.76, 1.24, overcast));
    color = lerp(color, cloud, density * lerp(.32, .68, overcast));

    // Rain shafts hang below the shelf as broad translucent curtains. Their
    // streaking is directional and low-frequency so it remains stable during
    // flight rather than sparkling like screen noise.
    float rain_column = fbm3(float3(
        ray.x * 18.0 + drift.x * 2.4,
        ray.z * 18.0 + drift.y * 2.4,
        floor(cloud_seconds * .18) * .07 + seed * 41.0
    ));
    float rain_horizon = (1.0 - smoothstep(.015, .27, elevation)) *
                         smoothstep(.42, .72, rain_column + shelf_horizon * .24);
    float rain_curtain = rain_horizon * precipitation * smoothstep(.34, .72, severity);
    float3 rain_color = lerp(float3(.31, .39, .42), float3(.12, .19, .23), severity);
    color = lerp(color, rain_color, rain_curtain * .58);

    // Rare deterministic double flashes illuminate cloud volume, never a
    // full-screen white frame. The narrow timing keeps lightning surprising
    // while the spatial lobe makes it feel embedded in one cell.
    float flash_cycle = frac(cloud_seconds / 13.7 + seed * 7.3);
    float flash = (1.0 - smoothstep(.010, .026, abs(flash_cycle - .035))) +
                  (1.0 - smoothstep(.008, .020, abs(flash_cycle - .082))) * .46;
    float lightning_gate = smoothstep(.76, .96, severity) * smoothstep(.58, .9, precipitation);
    float lightning_azimuth = frac(seed * 19.7 + floor(cloud_seconds / 13.7) * .618) * 6.28318530718;
    float3 lightning_direction = normalize(float3(cos(lightning_azimuth), .16, sin(lightning_azimuth)));
    float lightning_lobe = pow(saturate(dot(ray, lightning_direction) * .5 + .5), 18.0) *
                           smoothstep(.015, .42, elevation);
    color += float3(.55, .63, .66) * flash * lightning_gate * lightning_lobe *
             (density * .8 + shelf_horizon * .55);
    // Alpha is a world-pass classification channel. The sky is rendered first
    // and remains alpha-zero so the palette post-process can leave this smooth
    // gradient alone while opaque world geometry overwrites it with alpha one.
    return float4(color, 0);
}
