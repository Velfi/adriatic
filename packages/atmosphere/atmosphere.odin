package atmosphere

import "core:math"

DAY_MINUTES :: f32(1440)
WORLD_MINUTES_PER_SECOND :: f32(4)
FRONT_SECONDS :: f32(95)

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
    cloud_time_seconds: f32,
    cloud_seed:         u32,
    sun_direction:      [3]f32,
    daylight:           f32,
    twilight:           f32,
    weather:            Weather_State,
}

Atmosphere :: struct {
    seed:          u32,
    world_minutes: f32,
    front_seconds: f32,
    weather:       Weather_State,
    override:      Weather_Preset,
    paused:        bool,
}

new :: proc(seed: u32) -> Atmosphere {
    return {seed = seed, world_minutes = 9.5 * 60, weather = weather_for(.Clear), override = .Automatic}
}

weather_for :: proc(preset: Weather_Preset) -> Weather_State {
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

hash :: proc(value: u32) -> u32 {
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
        wind = {a.wind[0] + (b.wind[0] - a.wind[0]) * t, a.wind[1] + (b.wind[1] - a.wind[1]) * t},
    }
}

step :: proc(state: ^Atmosphere, delta_seconds: f32) {
    if state == nil || delta_seconds <= 0 do return
    delta := min(delta_seconds, f32(.1))
    if !state.paused {
        state.world_minutes = f32(
            math.mod(f64(state.world_minutes + delta * WORLD_MINUTES_PER_SECOND), f64(DAY_MINUTES)),
        )
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

sample :: proc(state: ^Atmosphere) -> Sky_State {
    if state == nil do return {}
    angle := (state.world_minutes / DAY_MINUTES - .25) * 2 * f32(math.PI)
    sun := [3]f32{f32(math.cos(f64(angle))) * .72, f32(math.sin(f64(angle))), f32(math.cos(f64(angle))) * .38}
    length := f32(math.sqrt(f64(sun[0] * sun[0] + sun[1] * sun[1] + sun[2] * sun[2])))
    for &component in sun do component /= max(length, f32(.0001))
    daylight := clamp((sun[1] + .10) / .30, 0, 1)
    twilight := clamp(1 - abs(sun[1]) / .34, 0, 1) * (1 - daylight * .35)
    return {
        world_minutes = state.world_minutes,
        cloud_time_seconds = state.front_seconds,
        cloud_seed = state.seed,
        sun_direction = sun,
        daylight = daylight,
        twilight = twilight,
        weather = state.weather,
    }
}

preset_name :: proc(preset: Weather_Preset) -> string {
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
