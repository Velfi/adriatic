package atmosphere

import "core:math"
import "core:math/linalg"

DAY_MINUTES :: f32(1440)
WORLD_MINUTES_PER_SECOND :: f32(4)
FRONT_SECONDS :: f32(95)
SYNODIC_MONTH_DAYS :: f32(29.53059)

Weather_Preset :: enum {
    Automatic,
    Clear,
    Windy,
    Storm,
}

Weather_State :: struct {
    cloud_cover:   f32,
    precipitation: f32,
    haze:          f32,
    severity:      f32,
    wind:          [2]f32,
}

Sky_State :: struct {
    world_minutes:      f32,
    world_days:         f32,
    cloud_time_seconds: f32,
    cloud_seed:         u32,
    sun_direction:      [3]f32,
    moon_direction:     [3]f32,
    moon_phase:         f32,
    moon_illumination:  f32,
    daylight:           f32,
    twilight:           f32,
    weather:            Weather_State,
}

Atmosphere :: struct {
    seed:          u32,
    world_minutes: f32,
    world_days:    f32,
    lunar_days:    f32,
    front_seconds: f32,
    weather:       Weather_State,
    override:      Weather_Preset,
    paused:        bool,
}

new :: proc(seed: u32) -> Atmosphere {
    // The seed gives each world a stable starting age without changing the
    // physical cycle length.
    lunar_days := f32(hash(seed) % 10000) / 10000 * SYNODIC_MONTH_DAYS
    return {
        seed = seed,
        world_minutes = 9.5 * 60,
        lunar_days = lunar_days,
        weather = weather_for(.Clear),
        override = .Automatic,
    }
}

@(no_instrumentation)
weather_for :: #force_inline proc(preset: Weather_Preset) -> Weather_State {
    switch preset {
    case .Windy:
        return {.56, .07, .17, .30, {8, -4}}
    case .Storm:
        return {.92, .88, .70, .92, {14, -9}}
    case .Automatic, .Clear:
        return {.16, 0, .05, .04, {2, 1}}
    }
    return {}
}

@(no_instrumentation)
hash :: #force_inline proc(value: u32) -> u32 {
    x := value
    x = (x ~ (x >> 16)) * 0x7feb352d
    x = (x ~ (x >> 15)) * 0x846ca68b
    return x ~ (x >> 16)
}

automatic_preset :: proc(state: ^Atmosphere) -> Weather_Preset {
    front := u32(math.floor(f64(state.front_seconds / FRONT_SECONDS)))
    value := hash(state.seed ~ (front * 0x9e3779b9)) % 100
    if value < 54 do return .Clear
    if value < 82 do return .Windy
    return .Storm
}

lerp_weather :: proc(a, b: Weather_State, amount: f32) -> Weather_State {
    t := clamp(amount, 0, 1)
    return {
        cloud_cover = a.cloud_cover + (b.cloud_cover - a.cloud_cover) * t,
        precipitation = a.precipitation + (b.precipitation - a.precipitation) * t,
        haze = a.haze + (b.haze - a.haze) * t,
        severity = a.severity + (b.severity - a.severity) * t,
        wind = linalg.lerp(a.wind, b.wind, t),
    }
}

step :: proc(state: ^Atmosphere, delta_seconds: f32) {
    if state == nil || delta_seconds <= 0 do return
    delta := min(delta_seconds, f32(.1))
    if !state.paused {
        elapsed_minutes := delta * WORLD_MINUTES_PER_SECOND
        state.world_minutes += elapsed_minutes
        state.lunar_days = f32(
            math.mod(f64(state.lunar_days + elapsed_minutes / DAY_MINUTES), f64(SYNODIC_MONTH_DAYS)),
        )
        if state.world_minutes >= DAY_MINUTES {
            elapsed_days := f32(math.floor(f64(state.world_minutes / DAY_MINUTES)))
            state.world_minutes -= elapsed_days * DAY_MINUTES
            state.world_days += elapsed_days
        }
        state.front_seconds += delta
    }
    target_preset := state.override
    if target_preset == .Automatic do target_preset = automatic_preset(state)
    target := weather_for(target_preset)
    blend := 1 - f32(math.exp(f64(-delta / 7)))
    state.weather = lerp_weather(state.weather, target, blend)
}

set_weather_override :: proc(state: ^Atmosphere, preset: Weather_Preset) {
    if state != nil do state.override = preset
}

set_world_minutes :: proc(state: ^Atmosphere, minutes: f32) {
    if state == nil do return
    state.world_minutes = f32(math.mod(f64(minutes), f64(DAY_MINUTES)))
    if state.world_minutes < 0 do state.world_minutes += DAY_MINUTES
}

set_lunar_age :: proc(state: ^Atmosphere, days_since_new_moon: f32) {
    if state == nil do return
    state.lunar_days = f32(math.mod(f64(days_since_new_moon), f64(SYNODIC_MONTH_DAYS)))
    if state.lunar_days < 0 do state.lunar_days += SYNODIC_MONTH_DAYS
}

sample :: proc(state: ^Atmosphere) -> Sky_State {
    if state == nil do return {}
    angle := (state.world_minutes / DAY_MINUTES - .25) * 2 * f32(math.PI)
    sun := linalg.normalize0([3]f32{f32(math.cos(f64(angle))) * .72, f32(math.sin(f64(angle))), f32(math.cos(f64(angle))) * .38})
    moon_phase := state.lunar_days / SYNODIC_MONTH_DAYS
    moon_angle := angle + moon_phase * 2 * f32(math.PI)
    // A modest orbital inclination keeps the moon from tracing the sun's
    // exact path while retaining predictable rise and set times by phase.
    inclination := f32(math.sin(f64(moon_phase * 2 * f32(math.PI) + .73))) * .089
    moon := [3]f32 {
        f32(math.cos(f64(moon_angle))) * .72,
        f32(math.sin(f64(moon_angle))) + inclination,
        f32(math.cos(f64(moon_angle))) * .38,
    }
    moon = linalg.normalize0(moon)
    moon_illumination := (1 - f32(math.cos(f64(moon_phase * 2 * f32(math.PI))))) * .5
    daylight := clamp((sun.y + .10) / .30, 0, 1)
    twilight := clamp(1 - abs(sun.y) / .34, 0, 1) * (1 - daylight * .35)
    return {
        world_minutes = state.world_minutes,
        world_days = state.world_days,
        cloud_time_seconds = state.front_seconds,
        cloud_seed = state.seed,
        sun_direction = sun,
        moon_direction = moon,
        moon_phase = moon_phase,
        moon_illumination = moon_illumination,
        daylight = daylight,
        twilight = twilight,
        weather = state.weather,
    }
}

@(no_instrumentation)
preset_name :: #force_inline proc(preset: Weather_Preset) -> string {
    switch preset {
    case .Automatic:
        return "AUTO"
    case .Clear:
        return "CLEAR"
    case .Windy:
        return "WINDY"
    case .Storm:
        return "STORM"
    }
    return "AUTO"
}
