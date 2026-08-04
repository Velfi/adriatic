package air_effects

import "core:math"

// Camera response begins first and stays subtle through ordinary flight.
// Vapor follows as airflow becomes readable around the wing, while explicit
// radial streaks are reserved for genuinely fast travel.
lens_strength :: proc(airspeed: f32) -> f32 {
    return eased_range(airspeed, 10, 68)
}

vapor_strength :: proc(airspeed: f32) -> f32 {
    return eased_range(airspeed, 16, 50)
}

streak_strength :: proc(airspeed: f32) -> f32 {
    return eased_range(airspeed, 30, 68)
}

screen_streak_count :: proc(airspeed: f32) -> int {
    strength := streak_strength(airspeed)
    if strength <= 0 do return 0
    return 12 + int(strength * 46 + .5)
}

world_rain_streak_count :: proc(weather_speed: f32) -> int {
    strength := eased_range(weather_speed, 1, 9)
    if strength <= 0 do return 0
    return 10 + int(strength * 34 + .5)
}

rain_streak_visibility :: proc(precipitation: f32) -> f32 {
    return smooth_step(clamp((precipitation - .08) / .42, 0, 1))
}

// Camera buffet is deliberately much weaker than flyby shake. A layered gust
// envelope creates periods of relative calm, while lateral flow and storm
// severity make exposed crosswind feel less mechanically uniform.
buffet_strength :: proc(weather_speed, apparent_lateral, severity, gust_phase: f32) -> f32 {
    wind := eased_range(weather_speed, 4, 16)
    storm := clamp(severity, 0, 1)
    if wind <= 0 && storm <= 0 do return 0
    wave :=
        .5 +
        f32(math.sin(f64(gust_phase * .83))) * .27 +
        f32(math.sin(f64(gust_phase * 1.91 + 1.4))) * .15 +
        f32(math.sin(f64(gust_phase * .37 + 2.2))) * .08
    gust := smooth_step(clamp((wave - .32) / .68, 0, 1))
    exposure := .65 + math.abs(clamp(apparent_lateral, -1, 1)) * .35
    return clamp((wind * .24 + storm * .12) * exposure * (.35 + gust * .65), 0, .38)
}

eased_range :: proc(value, onset, full: f32) -> f32 {
    if full <= onset do return value >= full ? 1 : 0
    normalized := clamp((value - onset) / (full - onset), 0, 1)
    return normalized * normalized * (3 - 2 * normalized)
}

clamp :: proc(value, lower, upper: f32) -> f32 {
    return min(max(value, lower), upper)
}

smooth_step :: proc(value: f32) -> f32 {
    return value * value * (3 - 2 * value)
}
