package tests

import atmosphere "../packages/atmosphere"
import "core:testing"

@(test)
atmosphere_is_deterministic_and_bounded :: proc(t: ^testing.T) {
    a := atmosphere.new(77)
    b := atmosphere.new(77)
    for _ in 0 ..< 240 {
        atmosphere.step(&a, 1.0 / 60)
        atmosphere.step(&b, 1.0 / 60)
    }
    sa := atmosphere.sample(&a)
    sb := atmosphere.sample(&b)
    testing.expect(t, sa == sb)
    testing.expect(t, sa.daylight >= 0 && sa.daylight <= 1)
    testing.expect(t, sa.twilight >= 0 && sa.twilight <= 1)
    testing.expect(t, sa.weather.cloud_cover >= 0 && sa.weather.cloud_cover <= 1)
}

@(test)
atmosphere_wraps_time_and_honors_controls :: proc(t: ^testing.T) {
    state := atmosphere.new(1)
    atmosphere.set_world_minutes(&state, 1500)
    testing.expect(t, state.world_minutes == 60)
    atmosphere.set_world_minutes(&state, -30)
    testing.expect(t, state.world_minutes == 1410)
    state.paused = true
    before := state.world_minutes
    atmosphere.step(&state, 1)
    testing.expect(t, state.world_minutes == before)
    atmosphere.set_weather_override(&state, .Storm)
    for _ in 0 ..< 200 do atmosphere.step(&state, .05)
    testing.expect(t, state.weather.severity > .6)
    atmosphere.set_weather_override(&state, .Automatic)
    testing.expect(t, state.override == .Automatic)
}

@(test)
atmosphere_cloud_time_remains_continuous_across_midnight :: proc(t: ^testing.T) {
    state := atmosphere.new(41)
    atmosphere.set_world_minutes(&state, atmosphere.DAY_MINUTES - .1)
    before := atmosphere.sample(&state)
    atmosphere.step(&state, .05)
    after := atmosphere.sample(&state)
    testing.expect(t, after.world_minutes < before.world_minutes)
    testing.expect(t, after.cloud_time_seconds > before.cloud_time_seconds)
    testing.expect(t, after.cloud_seed == before.cloud_seed)
    testing.expect(t, after.world_days > before.world_days)
}

@(test)
atmosphere_weather_transitions_are_bounded_and_gradual :: proc(t: ^testing.T) {
    state := atmosphere.new(9)
    atmosphere.set_weather_override(&state, .Storm)
    before := atmosphere.sample(&state).weather
    atmosphere.step(&state, .1)
    after := atmosphere.sample(&state).weather
    testing.expect(t, after.cloud_cover > before.cloud_cover)
    testing.expect(t, after.cloud_cover - before.cloud_cover < .1)
    testing.expect(t, after.precipitation >= 0 && after.precipitation <= 1)
    testing.expect(t, after.haze >= 0 && after.haze <= 1)
    testing.expect(t, after.severity >= 0 && after.severity <= 1)
}

@(test)
atmosphere_moon_tracks_synodic_phase_and_midnight :: proc(t: ^testing.T) {
    state := atmosphere.new(12)
    atmosphere.set_lunar_age(&state, 0)
    new_moon := atmosphere.sample(&state)
    testing.expect(t, new_moon.moon_illumination < .001)

    atmosphere.set_lunar_age(&state, atmosphere.SYNODIC_MONTH_DAYS * .5)
    full_moon := atmosphere.sample(&state)
    testing.expect(t, full_moon.moon_illumination > .999)
    alignment :=
        full_moon.sun_direction[0] * full_moon.moon_direction[0] +
        full_moon.sun_direction[1] * full_moon.moon_direction[1] +
        full_moon.sun_direction[2] * full_moon.moon_direction[2]
    testing.expect(t, alignment < -.98)

    atmosphere.set_world_minutes(&state, atmosphere.DAY_MINUTES - .1)
    age_before := state.lunar_days
    atmosphere.step(&state, .05)
    testing.expect(t, state.lunar_days > age_before)
}
