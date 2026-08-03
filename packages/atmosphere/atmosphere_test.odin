package atmosphere

import "core:math"
import "core:testing"

when ODIN_TEST {
    @(test)
    authored_weather_winds_are_distinct_but_flyable :: proc(t: ^testing.T) {
        clear := weather_for(.Clear).wind
        windy := weather_for(.Windy).wind
        storm := weather_for(.Storm).wind
        clear_speed := f32(math.sqrt(f64(clear[0] * clear[0] + clear[1] * clear[1])))
        windy_speed := f32(math.sqrt(f64(windy[0] * windy[0] + windy[1] * windy[1])))
        storm_speed := f32(math.sqrt(f64(storm[0] * storm[0] + storm[1] * storm[1])))
        bura := regime_weather(.Bura_Storm).wind
        bura_speed := f32(math.sqrt(f64(bura[0] * bura[0] + bura[1] * bura[1])))

        testing.expect(t, clear_speed < windy_speed && windy_speed < storm_speed)
        testing.expect(t, storm_speed < 13)
        testing.expect(t, bura_speed < 13)
    }

    @(test)
    front_schedule_is_seeded_rare_and_bounded :: proc(t: ^testing.T) {
        a := new(0x41544d4f)
        b := new(0x41544d4f)
        testing.expect(t, a.schedule == b.schedule)
        testing.expect(t, a.schedule.next_event_seconds >= FRONT_MIN_GAP_SECONDS)
        testing.expect(t, a.schedule.next_event_seconds <= FRONT_MAX_GAP_SECONDS)
        a.schedule.elapsed_seconds = a.schedule.next_event_seconds
        trigger_front(&a)
        duration := a.schedule.front.end_seconds - a.schedule.front.start_seconds
        testing.expect(t, a.schedule.front.active)
        testing.expect(t, duration >= FRONT_MIN_DURATION_SECONDS)
        testing.expect(t, duration <= FRONT_MAX_DURATION_SECONDS)
        testing.expect(t, a.schedule.front.width >= 1800 && a.schedule.front.width <= 3200)
        testing.expect(t, a.schedule.front.intensity >= .72 && a.schedule.front.intensity <= 1)
    }

    @(test)
    front_sampling_is_spatial_coherent_and_bounded :: proc(t: ^testing.T) {
        a := new(91)
        trigger_front(&a)
        front := &a.schedule.front
        a.schedule.elapsed_seconds = front.start_seconds + (front.end_seconds - front.start_seconds) * .5
        age := a.schedule.elapsed_seconds - front.start_seconds
        center := [3]f32 {
            front.origin[0] + front.direction[0] * front.speed * age,
            120,
            front.origin[1] + front.direction[1] * front.speed * age,
        }
        inside := sample_at(&a, center, center[1])
        nearby := sample_at(&a, {center[0] + 1, center[1], center[2] + 1}, center[1])
        outside := sample_at(
            &a,
            {
                center[0] + front.direction[0] * front.width * 2,
                center[1],
                center[2] + front.direction[1] * front.width * 2,
            },
            center[1],
        )
        testing.expect(t, inside.severity > .45)
        testing.expect(t, math.abs(inside.severity - nearby.severity) < .02)
        testing.expect(t, outside.severity < inside.severity)
        testing.expect(t, inside.wind[1] >= -5.5 && inside.wind[1] <= 5.5)
    }

    @(test)
    override_freezes_and_resumes_schedule :: proc(t: ^testing.T) {
        a := new(123)
        before := a.schedule.elapsed_seconds
        set_weather_override(&a, .Storm)
        step(&a, 1)
        testing.expect(t, a.schedule.elapsed_seconds == before)
        forced := sample_at(&a, {}, 0)
        testing.expect(t, forced.severity == weather_for(.Storm).severity)
        set_weather_override(&a, .Automatic)
        step(&a, 1)
        testing.expect(t, a.schedule.elapsed_seconds > before)
    }

    @(test)
    time_scale_changes_clock_rate :: proc(t: ^testing.T) {
        normal := new(17)
        fast := new(17)
        paused := new(17)
        before := normal.world_minutes
        step(&normal, .1)
        step(&fast, .1, 4)
        step(&paused, .1, 0)
        testing.expect(t, math.abs((fast.world_minutes - before) - (normal.world_minutes - before) * 4) < .001)
        testing.expect(t, paused.world_minutes == before)
    }

    @(test)
    climate_sequence_is_seeded_and_transition_bounded :: proc(t: ^testing.T) {
        a := new(0x434c494d)
        b := new(0x434c494d)
        testing.expect(t, a.climate == b.climate)
        testing.expect(t, a.climate.transition_start_seconds >= CLIMATE_MIN_DURATION_SECONDS)
        testing.expect(t, a.climate.transition_start_seconds <= CLIMATE_MAX_DURATION_SECONDS)
        a.climate.elapsed_seconds = a.climate.transition_end_seconds - .05
        before := a.climate.current
        step(&a, .1)
        testing.expect(t, a.climate.current != before || a.climate.next != before)
        testing.expect(t, a.climate.transition_start_seconds > a.climate.elapsed_seconds)
    }

    @(test)
    coastal_breeze_reverses_and_terrain_shapes_rain :: proc(t: ^testing.T) {
        a := new(77)
        set_climate_regime(&a, .Jugo)
        terrain_ctx := Terrain_Context {
            valid            = true,
            altitude_agl     = 40,
            terrain_gradient = {0, .12},
            land             = true,
            coast_to_sea     = {1, 0},
            coast_distance   = 240,
        }
        set_world_minutes(&a, 15 * 60)
        afternoon := sample_at(&a, {}, 40, terrain_ctx)
        set_world_minutes(&a, 2 * 60)
        night := sample_at(&a, {}, 40, terrain_ctx)
        testing.expect(t, afternoon.thermal_breeze > 0)
        testing.expect(t, night.thermal_breeze < 0)

        set_world_minutes(&a, 15 * 60)
        windward := sample_at(&a, {}, 40, terrain_ctx)
        terrain_ctx.terrain_gradient = -terrain_ctx.terrain_gradient
        leeward := sample_at(&a, {}, 40, terrain_ctx)
        testing.expect(t, windward.precipitation >= leeward.precipitation)
        testing.expect(t, leeward.rain_shadow >= windward.rain_shadow)
    }

    @(test)
    bura_accelerates_channels_and_clears_haze :: proc(t: ^testing.T) {
        a := new(88)
        set_climate_regime(&a, .Bura_Clear)
        open := Terrain_Context {
            valid          = true,
            land           = true,
            altitude_agl   = 30,
            coast_distance = 1000,
        }
        channel := open
        channel.terrain_channel = 1
        calm := sample_at(&a, {}, 30, open)
        jet := sample_at(&a, {}, 30, channel)
        calm_speed := math.sqrt(f64(calm.wind[0] * calm.wind[0] + calm.wind[2] * calm.wind[2]))
        jet_speed := math.sqrt(f64(jet.wind[0] * jet.wind[0] + jet.wind[2] * jet.wind[2]))
        testing.expect(t, jet_speed > calm_speed)
        testing.expect(t, jet.haze < regime_weather(.Jugo).haze)
    }

    @(test)
    sky_front_field_tracks_the_same_geographic_band_as_weather_sampling :: proc(t: ^testing.T) {
        a := new(0x534b5946)
        trigger_front(&a)
        front := &a.schedule.front
        duration := front.end_seconds - front.start_seconds
        a.schedule.elapsed_seconds = front.start_seconds + duration * .5
        age := a.schedule.elapsed_seconds - front.start_seconds
        center := [3]f32 {
            front.origin[0] + front.direction[0] * front.speed * age,
            200,
            front.origin[1] + front.direction[1] * front.speed * age,
        }
        field := sky_front_field(&a, center)
        local := sample_at(&a, center, center[1])
        testing.expect(t, field.active)
        testing.expect(t, math.abs(field.signed_distance_widths) <= .13)
        testing.expect(t, field.horizon_ray_widths > 2)
        testing.expect(t, local.front_proximity > .8)
        set_weather_override(&a, .Clear)
        testing.expect(t, !sky_front_field(&a, center).active)
    }
}
