package atmosphere

import "core:math"
import "core:math/linalg"

DAY_MINUTES :: f32(1440)
WORLD_MINUTES_PER_SECOND :: f32(4)
FRONT_SECONDS :: f32(95)
SYNODIC_MONTH_DAYS :: f32(29.53059)
WORLD_SIZE_METERS :: f32(8000)
FRONT_MIN_GAP_SECONDS :: f32(60 * 60)
FRONT_MAX_GAP_SECONDS :: f32(120 * 60)
FRONT_MIN_DURATION_SECONDS :: f32(10 * 60)
FRONT_MAX_DURATION_SECONDS :: f32(20 * 60)
CLIMATE_MIN_DURATION_SECONDS :: f32(35 * 60)
CLIMATE_MAX_DURATION_SECONDS :: f32(70 * 60)

Weather_Preset :: enum {
    Automatic,
    Clear,
    Windy,
    Storm,
}

Climate_Regime :: enum u8 {
    Maestral,
    Bura_Clear,
    Bura_Storm,
    Jugo,
    Calm_Humid,
    Post_Front,
}

Climate_State :: struct {
    initialized:              bool,
    rng_state:                u32,
    current:                  Climate_Regime,
    next:                     Climate_Regime,
    elapsed_seconds:          f32,
    transition_start_seconds: f32,
    transition_end_seconds:   f32,
}

Terrain_Context :: struct {
    valid:            bool,
    altitude_agl:     f32,
    terrain_height:   f32,
    terrain_gradient: [2]f32,
    sea_level:        f32,
    land:             bool,
    coast_to_sea:     [2]f32,
    coast_distance:   f32,
    terrain_channel:  f32,
}

Weather_State :: struct {
    cloud_cover:   f32,
    precipitation: f32,
    haze:          f32,
    severity:      f32,
    wind:          [2]f32,
}

Local_Weather :: struct {
    cloud_cover:           f32,
    precipitation:         f32,
    haze:                  f32,
    severity:              f32,
    wind:                  [3]f32,
    gust_strength:         f32,
    vertical_air_strength: f32,
    front_proximity:       f32,
    rain_shadow:           f32,
    thermal_breeze:        f32,
    temperature_tendency:  f32,
    regime:                Climate_Regime,
}

Front_State :: struct {
    active:          bool,
    event_id:        u32,
    seed:            u32,
    start_seconds:   f32,
    end_seconds:     f32,
    origin:          [2]f32,
    direction:       [2]f32,
    speed:           f32,
    width:           f32,
    intensity:       f32,
    gustiness:       f32,
    rainfall:        f32,
    visibility_loss: f32,
    cell_scale:      f32,
    cell_phase:      f32,
}

Front_Schedule :: struct {
    initialized:        bool,
    rng_state:          u32,
    elapsed_seconds:    f32,
    next_event_seconds: f32,
    event_serial:       u32,
    front:              Front_State,
}

Sky_Front_Field :: struct {
    active:                 bool,
    signed_distance_widths: f32,
    horizon_ray_widths:     f32,
    direction:              [2]f32,
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
    schedule:      Front_Schedule,
    climate:       Climate_State,
}

new :: proc(seed: u32) -> Atmosphere {
    // The seed gives each world a stable starting age without changing the
    // physical cycle length.
    lunar_days := f32(hash(seed) % 10000) / 10000 * SYNODIC_MONTH_DAYS
    result := Atmosphere {
        seed          = seed,
        world_minutes = 9.5 * 60,
        lunar_days    = lunar_days,
        weather       = weather_for(.Clear),
        override      = .Automatic,
    }
    initialize_schedule(&result)
    initialize_climate(&result)
    return result
}

@(no_instrumentation)
weather_for :: #force_inline proc(preset: Weather_Preset) -> Weather_State {
    switch preset {
    case .Windy:
        return {.56, .07, .17, .30, {6, -3}}
    case .Storm:
        return {.92, .88, .70, .92, {10, -6.5}}
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
    if state != nil && state.schedule.front.active do return .Storm
    return .Clear
}

random_01 :: proc(state: ^u32) -> f32 {
    state^ = hash(state^ + 0x9e3779b9)
    return f32(state^ & 0x00ffffff) / f32(0x01000000)
}

random_range :: proc(state: ^u32, minimum, maximum: f32) -> f32 {
    return minimum + (maximum - minimum) * random_01(state)
}

regime_weather :: proc(regime: Climate_Regime) -> Weather_State {
    switch regime {
    case .Maestral:
        return {.24, .01, .08, .14, {4.5, -3.2}}
    case .Bura_Clear:
        return {.12, 0, .025, .48, {-8, -6.5}}
    case .Bura_Storm:
        return {.76, .52, .40, .82, {-10, -7.5}}
    case .Jugo:
        return {.82, .58, .58, .68, {-6, 5}}
    case .Calm_Humid:
        return {.46, .03, .42, .10, {.8, .4}}
    case .Post_Front:
        return {.38, .12, .16, .30, {5, -3.5}}
    }
    return weather_for(.Clear)
}

regime_name :: proc(regime: Climate_Regime) -> string {
    switch regime {
    case .Maestral:
        return "MAESTRAL"
    case .Bura_Clear:
        return "BURA CLEAR"
    case .Bura_Storm:
        return "BURA STORM"
    case .Jugo:
        return "JUGO"
    case .Calm_Humid:
        return "CALM HUMID"
    case .Post_Front:
        return "POST FRONT"
    }
    return "MAESTRAL"
}

season_phase :: proc(state: ^Atmosphere) -> f32 {
    if state == nil do return 0
    return f32(math.mod(f64(max(state.world_days, f32(0))), 360)) / 360
}

choose_initial_regime :: proc(state: ^Atmosphere) -> Climate_Regime {
    phase := season_phase(state)
    roll := random_01(&state.climate.rng_state)
    // Summer is dominated by fair maestral/calm cycles; the colder half of
    // the year admits substantially more bura and jugo sequences.
    summer := phase >= .20 && phase < .70
    if summer {
        if roll < .68 do return .Maestral
        if roll < .86 do return .Calm_Humid
        if roll < .95 do return .Jugo
        return .Post_Front
    }
    if roll < .30 do return .Jugo
    if roll < .52 do return .Bura_Clear
    if roll < .67 do return .Bura_Storm
    if roll < .84 do return .Post_Front
    return .Calm_Humid
}

choose_next_regime :: proc(state: ^Atmosphere, current: Climate_Regime) -> Climate_Regime {
    roll := random_01(&state.climate.rng_state)
    phase := season_phase(state)
    summer := phase >= .20 && phase < .70
    switch current {
    case .Maestral:
        if roll < (summer ? f32(.58) : f32(.25)) do return .Calm_Humid
        return .Jugo
    case .Calm_Humid:
        if roll < (summer ? f32(.62) : f32(.34)) do return .Maestral
        return .Jugo
    case .Jugo:
        if roll < (summer ? f32(.70) : f32(.48)) do return .Bura_Storm
        return .Post_Front
    case .Bura_Storm:
        if roll < .62 do return .Bura_Clear
        return .Post_Front
    case .Bura_Clear:
        if roll < (summer ? f32(.72) : f32(.45)) do return .Maestral
        return .Post_Front
    case .Post_Front:
        if roll < (summer ? f32(.66) : f32(.36)) do return .Maestral
        return .Calm_Humid
    }
    return .Maestral
}

initialize_climate :: proc(state: ^Atmosphere) {
    if state == nil || state.climate.initialized do return
    state.climate.initialized = true
    state.climate.rng_state = hash(state.seed ~ 0xc11a7e51)
    state.climate.current = choose_initial_regime(state)
    state.climate.next = choose_next_regime(state, state.climate.current)
    state.climate.transition_start_seconds = random_range(
        &state.climate.rng_state,
        CLIMATE_MIN_DURATION_SECONDS,
        CLIMATE_MAX_DURATION_SECONDS,
    )
    state.climate.transition_end_seconds = state.climate.transition_start_seconds + 90
}

set_climate_regime :: proc(state: ^Atmosphere, regime: Climate_Regime) {
    if state == nil do return
    initialize_climate(state)
    state.climate.current = regime
    state.climate.next = regime
    state.climate.transition_start_seconds = state.climate.elapsed_seconds + CLIMATE_MAX_DURATION_SECONDS
    state.climate.transition_end_seconds = state.climate.transition_start_seconds + 90
}

climate_transition_progress :: proc(state: ^Atmosphere) -> f32 {
    if state == nil || !state.climate.initialized do return 0
    return smoothstep(
        state.climate.transition_start_seconds,
        state.climate.transition_end_seconds,
        state.climate.elapsed_seconds,
    )
}

climate_weather :: proc(state: ^Atmosphere) -> Weather_State {
    if state == nil do return weather_for(.Clear)
    initialize_climate(state)
    return lerp_weather(
        regime_weather(state.climate.current),
        regime_weather(state.climate.next),
        climate_transition_progress(state),
    )
}

initialize_schedule :: proc(state: ^Atmosphere) {
    if state == nil || state.schedule.initialized do return
    state.schedule.initialized = true
    state.schedule.rng_state = hash(state.seed ~ 0xa7105f21)
    state.schedule.next_event_seconds = random_range(
        &state.schedule.rng_state,
        FRONT_MIN_GAP_SECONDS,
        FRONT_MAX_GAP_SECONDS,
    )
}

trigger_front :: proc(state: ^Atmosphere) {
    if state == nil do return
    initialize_schedule(state)
    rng := &state.schedule.rng_state
    direction := climate_weather(state).wind
    direction_length := f32(math.sqrt(f64(direction[0] * direction[0] + direction[1] * direction[1])))
    if direction_length < .01 {
        angle := random_range(rng, 0, 2 * f32(math.PI))
        direction = {f32(math.cos(f64(angle))), f32(math.sin(f64(angle)))}
    } else {
        direction /= direction_length
    }
    duration := random_range(rng, FRONT_MIN_DURATION_SECONDS, FRONT_MAX_DURATION_SECONDS)
    travel := WORLD_SIZE_METERS * 2.4
    state.schedule.event_serial += 1
    state.schedule.front = {
        active          = true,
        event_id        = state.schedule.event_serial,
        seed            = hash(rng^ ~ state.schedule.event_serial),
        start_seconds   = state.schedule.elapsed_seconds,
        end_seconds     = state.schedule.elapsed_seconds + duration,
        origin          = {-direction[0] * travel * .5, -direction[1] * travel * .5},
        direction       = direction,
        speed           = travel / duration,
        width           = random_range(rng, 1800, 3200),
        intensity       = random_range(rng, .72, 1),
        gustiness       = random_range(rng, .55, 1),
        rainfall        = random_range(rng, .68, 1),
        visibility_loss = random_range(rng, .55, .9),
        cell_scale      = random_range(rng, 700, 1500),
        cell_phase      = random_range(rng, 0, 2 * f32(math.PI)),
    }
}

front_progress :: proc(state: ^Atmosphere) -> f32 {
    if state == nil || !state.schedule.front.active do return 0
    front := &state.schedule.front
    duration := max(front.end_seconds - front.start_seconds, f32(.001))
    return clamp((state.schedule.elapsed_seconds - front.start_seconds) / duration, 0, 1)
}

front_seconds_until_next :: proc(state: ^Atmosphere) -> f32 {
    if state == nil do return 0
    if state.schedule.front.active do return max(state.schedule.front.end_seconds - state.schedule.elapsed_seconds, f32(0))
    if state.climate.initialized {
        return max(state.climate.transition_start_seconds - state.climate.elapsed_seconds, f32(0))
    }
    return max(state.schedule.next_event_seconds - state.schedule.elapsed_seconds, f32(0))
}

sky_front_field :: proc(state: ^Atmosphere, position: [3]f32) -> Sky_Front_Field {
    if state == nil || state.override != .Automatic || !state.schedule.front.active do return {}
    front := &state.schedule.front
    age := state.schedule.elapsed_seconds - front.start_seconds
    center_x := front.origin[0] + front.direction[0] * front.speed * age
    center_z := front.origin[1] + front.direction[1] * front.speed * age
    relative_x, relative_z := position[0] - center_x, position[2] - center_z
    lateral := -relative_x * front.direction[1] + relative_z * front.direction[0]
    width := max(front.width, f32(1))
    distortion := f32(math.sin(f64(lateral / max(front.cell_scale, f32(1)) * 2.1 + front.cell_phase))) * width * .12
    along := relative_x * front.direction[0] + relative_z * front.direction[1] + distortion
    // The sky is not a literal plane, but a 6.5 km horizon probe gives the
    // dome a stable geographic read at Adriatic's eight-kilometre world scale.
    return {
        active = true,
        signed_distance_widths = clamp(along / width, f32(-8), f32(8)),
        horizon_ray_widths = 6500 / width,
        direction = front.direction,
    }
}

smoothstep :: proc(edge_0, edge_1, value: f32) -> f32 {
    t := clamp((value - edge_0) / max(edge_1 - edge_0, f32(.0001)), 0, 1)
    return t * t * (3 - 2 * t)
}

sample_at :: proc(
    state: ^Atmosphere,
    position: [3]f32,
    altitude: f32,
    terrain_context: Terrain_Context = {},
) -> Local_Weather {
    if state == nil do return {}
    if state.override != .Automatic {
        uniform := weather_for(state.override)
        return {
            cloud_cover = uniform.cloud_cover,
            precipitation = uniform.precipitation,
            haze = uniform.haze,
            severity = uniform.severity,
            wind = {uniform.wind[0], 0, uniform.wind[1]},
            gust_strength = uniform.severity * .25,
            vertical_air_strength = 0,
            front_proximity = uniform.severity,
            regime = state.climate.current,
        }
    }
    base := climate_weather(state)
    result := Local_Weather {
        cloud_cover   = base.cloud_cover,
        precipitation = base.precipitation,
        haze          = base.haze,
        severity      = base.severity,
        wind          = {base.wind[0], 0, base.wind[1]},
        regime        = state.climate.current,
    }
    front := &state.schedule.front
    if front.active {

        age := state.schedule.elapsed_seconds - front.start_seconds
        center_x := front.origin[0] + front.direction[0] * front.speed * age
        center_z := front.origin[1] + front.direction[1] * front.speed * age
        relative_x, relative_z := position[0] - center_x, position[2] - center_z
        lateral := -relative_x * front.direction[1] + relative_z * front.direction[0]
        distortion :=
            f32(math.sin(f64(lateral / max(front.cell_scale, f32(1)) * 2.1 + front.cell_phase))) * front.width * .12
        along := relative_x * front.direction[0] + relative_z * front.direction[1] + distortion
        half_width := front.width * .5
        edge := max(front.width * .16, f32(120))
        band :=
            smoothstep(-half_width - edge, -half_width + edge, along) *
            (1 - smoothstep(half_width - edge, half_width + edge, along))
        cell_wave :=
            .5 + .5 * f32(math.sin(f64(lateral / max(front.cell_scale, f32(1)) * 5.3 + front.cell_phase * 1.7)))
        cell := clamp(.68 + cell_wave * .42, 0, 1)
        exposure := clamp(band * front.intensity * cell, 0, 1)
        if exposure > .0001 {

            gust_period := 1.35 + f32(front.seed % 1400) / 1000
            gust_phase :=
                state.schedule.elapsed_seconds * (2 * f32(math.PI) / gust_period) + lateral * .0037 + front.cell_phase
            gust_wave := .5 + .5 * f32(math.sin(f64(gust_phase)))
            gust := exposure * front.gustiness * smoothstep(.18, .88, gust_wave)
            cross_x, cross_z := -front.direction[1], front.direction[0]
            wind_speed := 4 + exposure * 8 + gust * 3
            vertical := exposure * (f32(math.sin(f64(gust_phase * .47 + cell_wave * 4))) * 2.6 - cell_wave * 1.35)
            altitude_fade := 1 - smoothstep(900, 2600, altitude)
            vertical *= .35 + altitude_fade * .65
            result.cloud_cover = clamp(base.cloud_cover + exposure * .84, 0, 1)
            result.precipitation = clamp(exposure * front.rainfall, 0, 1)
            result.haze = clamp(base.haze + exposure * front.visibility_loss, 0, 1)
            result.severity = clamp(base.severity + exposure * .96, 0, 1)
            result.wind = {
                front.direction[0] * wind_speed + cross_x * gust * 2.5,
                vertical,
                front.direction[1] * wind_speed + cross_z * gust * 2.5,
            }
            result.gust_strength = gust
            result.vertical_air_strength = vertical
            result.front_proximity = band
        }
    }

    if terrain_context.valid {
        horizontal := [2]f32{result.wind[0], result.wind[2]}
        speed := f32(math.sqrt(f64(horizontal[0] * horizontal[0] + horizontal[1] * horizontal[1])))
        wind_direction := speed > .001 ? horizontal / speed : [2]f32{}
        gradient := terrain_context.terrain_gradient
        upslope := horizontal[0] * gradient[0] + horizontal[1] * gradient[1]
        low_altitude := 1 - smoothstep(120, 650, terrain_context.altitude_agl)
        channel := clamp(terrain_context.terrain_channel, 0, 1)

        // coast_to_sea points away from land. Daytime heating drives the
        // opposite onshore vector; cool land reverses it after sunset.
        solar := f32(math.sin(f64((state.world_minutes / DAY_MINUTES - .25) * 2 * f32(math.PI))))
        afternoon :=
            smoothstep(.05, .75, solar) *
            smoothstep(7 * 60, 13 * 60, state.world_minutes) *
            (1 - smoothstep(18 * 60, 21 * 60, state.world_minutes))
        night := 1 - smoothstep(-.18, .08, solar)
        coast_fade := 1 - smoothstep(150, 1800, terrain_context.coast_distance)
        thermal := (afternoon * 3.8 - night * 1.6) * coast_fade
        if terrain_context.land {
            horizontal -= terrain_context.coast_to_sea * thermal
        } else {
            horizontal -= terrain_context.coast_to_sea * thermal * .55
        }
        result.thermal_breeze = thermal

        ridge_lift := clamp(upslope * .42, f32(-3.2), f32(4.2)) * low_altitude
        lee := clamp(-upslope * .055, 0, 1) * low_altitude
        result.rain_shadow = lee
        result.wind[1] += ridge_lift
        if upslope < 0 {
            phase := state.climate.elapsed_seconds * 2.7 + position[0] * .017 - position[2] * .013
            result.wind[1] += f32(math.sin(f64(phase))) * min(-upslope * .28, f32(2.4)) * low_altitude
        }
        shelter := clamp(1 - lee * .38, .62, 1)
        if result.regime == .Bura_Clear || result.regime == .Bura_Storm {
            // Strong northeasterly flow accelerates through deterministic
            // terrain gaps while exposed downslope sites remain gusty.
            shelter = clamp(shelter + channel * .42, .62, 1.35)
            result.gust_strength = clamp(result.gust_strength + channel * .55 * low_altitude, 0, 1)
        }
        horizontal *= shelter
        result.wind[0], result.wind[2] = horizontal[0], horizontal[1]
        result.wind[1] = clamp(result.wind[1], f32(-5.5), f32(5.5))
        result.vertical_air_strength = result.wind[1]
        windward := clamp(upslope * .08, 0, 1) * low_altitude
        result.cloud_cover = clamp(result.cloud_cover + windward * .22 - lee * .16, 0, 1)
        result.precipitation = clamp(result.precipitation * (1 + windward * .55) * (1 - lee * .68), 0, 1)
        result.haze = clamp(result.haze * (1 - (result.regime == .Bura_Clear ? f32(.72) : f32(0))), 0, 1)
        result.temperature_tendency = afternoon * (terrain_context.land ? f32(1) : f32(.2)) - night * .45
        _ = wind_direction
    }
    return result
}

sample_airflow :: proc(state: ^Atmosphere, position: [3]f32, altitude, time: f32) -> [3]f32 {
    _ = time // Schedule time is the deterministic gust clock.
    return sample_at(state, position, altitude).wind
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

step :: proc(state: ^Atmosphere, delta_seconds: f32, time_scale: f32 = 1) {
    if state == nil || delta_seconds <= 0 || time_scale <= 0 do return
    delta := min(delta_seconds, f32(.1)) * time_scale
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
        if state.override == .Automatic {
            initialize_schedule(state)
            initialize_climate(state)
            state.schedule.elapsed_seconds += delta
            state.climate.elapsed_seconds += delta
            if state.schedule.front.active && state.schedule.elapsed_seconds >= state.schedule.front.end_seconds {
                state.schedule.front.active = false
            }
            if state.climate.elapsed_seconds >= state.climate.transition_end_seconds {
                state.climate.current = state.climate.next
                state.climate.next = choose_next_regime(state, state.climate.current)
                state.climate.transition_start_seconds =
                    state.climate.elapsed_seconds +
                    random_range(&state.climate.rng_state, CLIMATE_MIN_DURATION_SECONDS, CLIMATE_MAX_DURATION_SECONDS)
                state.climate.transition_end_seconds = state.climate.transition_start_seconds + 90
                if !state.schedule.front.active &&
                   (state.climate.current == .Jugo || state.climate.current == .Bura_Storm) {
                    trigger_front(state)
                }
            }
        }
    }
    target := weather_for(state.override)
    if state.override == .Automatic {
        target_local := sample_at(state, [3]f32{}, 0)
        target = {
            target_local.cloud_cover,
            target_local.precipitation,
            target_local.haze,
            target_local.severity,
            {target_local.wind[0], target_local.wind[2]},
        }
    }
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

world_minutes :: proc(state: ^Atmosphere) -> f32 {
    return state != nil ? state.world_minutes : 0
}

set_lunar_age :: proc(state: ^Atmosphere, days_since_new_moon: f32) {
    if state == nil do return
    state.lunar_days = f32(math.mod(f64(days_since_new_moon), f64(SYNODIC_MONTH_DAYS)))
    if state.lunar_days < 0 do state.lunar_days += SYNODIC_MONTH_DAYS
}

sample :: proc(
    state: ^Atmosphere,
    observer_position: [3]f32 = {},
    terrain_context: Terrain_Context = {},
) -> Sky_State {
    if state == nil do return {}
    angle := (state.world_minutes / DAY_MINUTES - .25) * 2 * f32(math.PI)
    sun := linalg.normalize0(
        [3]f32{f32(math.cos(f64(angle))) * .72, f32(math.sin(f64(angle))), f32(math.cos(f64(angle))) * .38},
    )
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
    local := sample_at(state, observer_position, observer_position[1], terrain_context)
    local_weather := Weather_State {
        local.cloud_cover,
        local.precipitation,
        local.haze,
        local.severity,
        {local.wind[0], local.wind[2]},
    }
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
        weather = local_weather,
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
