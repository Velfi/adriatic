package fog_field

import atmosphere "../atmosphere"
import "core:math"

MAX_BANKS :: 4
FRONT_SECONDS :: f32(95)

Vec2 :: [2]f32
Vec3 :: [3]f32

World_Bounds :: struct {
    minimum: Vec2,
    maximum: Vec2,
}

Fog_Bank :: struct {
    center:       Vec2,
    radii:        Vec2,
    axis:         Vec2,
    base_altitude: f32,
    top_altitude:  f32,
    edge_softness: f32,
    peak_density:  f32,
}

Fog_Field :: struct {
    banks:          [MAX_BANKS]Fog_Bank,
    previous_banks: [MAX_BANKS]Fog_Bank,
    blend:          f32,
    global_density: f32,
    wind:           Vec2,
    time_seconds:   f32,
}

hash :: #force_inline proc(value: u32) -> u32 {
    x := value
    x = (x ~ (x >> 16)) * 0x7feb352d
    x = (x ~ (x >> 15)) * 0x846ca68b
    return x ~ (x >> 16)
}

random01 :: #force_inline proc(seed: u32) -> f32 {
    return f32(hash(seed) & 0x00ffffff) / f32(0x01000000)
}

finite_or :: #force_inline proc(value, fallback: f32) -> f32 {
    return value == value && abs(value) <= f32(3.4028234e38) ? value : fallback
}

smoothstep :: #force_inline proc(edge0, edge1, value: f32) -> f32 {
    t := clamp((value - edge0) / max(edge1 - edge0, f32(0.00001)), 0, 1)
    return t * t * (3 - 2 * t)
}

generation :: proc(seed: u32, front: i64, weather: atmosphere.Weather_State, bounds: World_Bounds) -> [MAX_BANKS]Fog_Bank {
    result: [MAX_BANKS]Fog_Bank
    min_x := finite_or(min(bounds.minimum.x, bounds.maximum.x), -4000)
    max_x := finite_or(max(bounds.minimum.x, bounds.maximum.x), 4000)
    min_z := finite_or(min(bounds.minimum.y, bounds.maximum.y), -4000)
    max_z := finite_or(max(bounds.minimum.y, bounds.maximum.y), 4000)
    width, depth := max(max_x - min_x, f32(100)), max(max_z - min_z, f32(100))
    weather_density := clamp((finite_or(weather.haze, 0) - .06) * 1.45 + finite_or(weather.precipitation, 0) * .42, 0, 1)
    for index in 0 ..< MAX_BANKS {
        salt := seed ~ u32(front) * 0x9e3779b9 ~ u32(index + 1) * 0x85ebca6b
        angle := random01(salt ~ 1) * 2 * f32(math.PI)
        random_x := min_x + (.12 + random01(salt ~ 2) * .76) * width
        // The two-island world leaves its broadest open-water corridor near
        // the world midpoint. Bias, rather than clamp, so outer coastal banks
        // still occur while most generations read as weather over the sea.
        water_bias := index < 2 ? f32(.62) : f32(.34)
        center_x := random_x + ((min_x + max_x) * .5 - random_x) * water_bias
        result[index] = {
            center = {
                center_x,
                min_z + (.12 + random01(salt ~ 3) * .76) * depth,
            },
            radii = {
                width * (.075 + random01(salt ~ 4) * .105),
                depth * (.050 + random01(salt ~ 5) * .080),
            },
            axis = {f32(math.cos(f64(angle))), f32(math.sin(f64(angle)))},
            base_altitude = -18 + random01(salt ~ 6) * 14,
            top_altitude = 120 + random01(salt ~ 7) * 230,
            edge_softness = .34 + random01(salt ~ 8) * .22,
            peak_density = weather_density * (.62 + random01(salt ~ 9) * .38),
        }
    }
    return result
}

generate :: proc(
    seed: u32,
    front_seconds: f32,
    weather: atmosphere.Weather_State,
    world_bounds: World_Bounds,
    regime: atmosphere.Climate_Regime = .Calm_Humid,
) -> Fog_Field {
    time := max(finite_or(front_seconds, 0), f32(0))
    front := i64(math.floor(f64(time / FRONT_SECONDS)))
    phase := time / FRONT_SECONDS - f32(front)
    // Spend the first quarter of each front dissolving from the previous
    // deterministic generation; the remainder is stable apart from drift.
    blend := phase < .25 ? phase / .25 : f32(1)
    wind := Vec2{finite_or(weather.wind.x, 0), finite_or(weather.wind.y, 0)}
    current := generation(seed, front, weather, world_bounds)
    previous := generation(seed, front - 1, weather, world_bounds)
    drift := time - f32(front) * FRONT_SECONDS
    previous_drift := drift + FRONT_SECONDS
    for index in 0 ..< MAX_BANKS {
        current[index].center += wind * drift * .32
        previous[index].center += wind * previous_drift * .32
    }
    regime_density := f32(1)
    if regime == .Jugo do regime_density = 1.22
    if regime == .Calm_Humid do regime_density = 1.12
    if regime == .Post_Front do regime_density = .72
    if regime == .Bura_Storm do regime_density = .28
    if regime == .Bura_Clear do regime_density = .04
    global_density := clamp(
        ((finite_or(weather.haze, 0) - .04) * 1.5 + finite_or(weather.precipitation, 0) * .30) * regime_density,
        0,
        1,
    )
    return {current, previous, blend, global_density, wind, time}
}

sample_bank :: proc(bank: Fog_Bank, position: Vec3) -> f32 {
    if bank.peak_density <= 0 || bank.radii.x <= 0 || bank.radii.y <= 0 || bank.top_altitude <= bank.base_altitude do return 0
    offset := Vec2{position.x - bank.center.x, position.z - bank.center.y}
    along := offset.x * bank.axis.x + offset.y * bank.axis.y
    across := -offset.x * bank.axis.y + offset.y * bank.axis.x
    radial := f32(math.sqrt(f64((along / bank.radii.x) * (along / bank.radii.x) + (across / bank.radii.y) * (across / bank.radii.y))))
    horizontal := 1 - smoothstep(1 - clamp(bank.edge_softness, .01, .95), 1, radial)
    vertical := smoothstep(bank.base_altitude, bank.base_altitude + 28, position.y) *
        (1 - smoothstep(bank.top_altitude * .62, bank.top_altitude, position.y))
    return clamp(horizontal * vertical * bank.peak_density, 0, 1)
}

sample :: proc(field: Fog_Field, world_position: Vec3) -> f32 {
    density := f32(0)
    for index in 0 ..< MAX_BANKS {
        old_density := sample_bank(field.previous_banks[index], world_position)
        new_density := sample_bank(field.banks[index], world_position)
        density = max(density, old_density + (new_density - old_density) * field.blend)
    }
    return clamp(density * field.global_density, 0, 1)
}
