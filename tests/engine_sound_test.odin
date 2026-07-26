package tests

import engine_sound "../packages/engine_sound"
import "core:math"
import "core:testing"

@(test)
engine_sound_rate_changes_zero_crossing_density :: proc(t: ^testing.T) {
    slow, fast := engine_sound.new(1), engine_sound.new(1)
    slow_samples, fast_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(&slow, {rate = .1, power = .5, active = true}, slow_samples[:])
    engine_sound.render(&fast, {rate = .9, power = .5, active = true}, fast_samples[:])

    slow_crossings, fast_crossings := 0, 0
    for index in 1 ..< len(slow_samples) {
        if slow_samples[index - 1] <= 0 && slow_samples[index] > 0 do slow_crossings += 1
        if fast_samples[index - 1] <= 0 && fast_samples[index] > 0 do fast_crossings += 1
    }
    testing.expect(t, fast.rate > slow.rate)
    testing.expect(t, fast_crossings > slow_crossings)
}

@(test)
engine_sound_power_changes_energy_without_changing_rate :: proc(t: ^testing.T) {
    light, loaded := engine_sound.new(9), engine_sound.new(9)
    light_samples, loaded_samples: [engine_sound.SAMPLE_RATE / 2]f32
    engine_sound.render(&light, {rate = .55, power = .05, active = true}, light_samples[:])
    engine_sound.render(&loaded, {rate = .55, power = 1, active = true}, loaded_samples[:])

    light_energy, loaded_energy := f64(0), f64(0)
    for index in 0 ..< len(light_samples) {
        light_energy += f64(light_samples[index] * light_samples[index])
        loaded_energy += f64(loaded_samples[index] * loaded_samples[index])
        testing.expect(t, math.abs(light_samples[index]) <= .92)
        testing.expect(t, math.abs(loaded_samples[index]) <= .92)
    }
    testing.expect(t, loaded_energy > light_energy * 2)
}

@(test)
wheel_slip_sound_requires_slip_and_speed :: proc(t: ^testing.T) {
    quiet, slipping := engine_sound.new_slip(17), engine_sound.new_slip(17)
    quiet_samples, slipping_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.render_slip_add(
        &quiet,
        {amount = 0, speed = .8, active = true},
        quiet_samples[:],
    )
    engine_sound.render_slip_add(
        &slipping,
        {amount = .9, speed = .8, active = true},
        slipping_samples[:],
    )

    quiet_energy, slipping_energy := f64(0), f64(0)
    for index in 0 ..< len(quiet_samples) {
        quiet_energy += f64(quiet_samples[index] * quiet_samples[index])
        slipping_energy += f64(slipping_samples[index] * slipping_samples[index])
        testing.expect(t, math.abs(slipping_samples[index]) <= .92)
    }
    testing.expect(t, slipping_energy > quiet_energy + .01)
}

@(test)
tire_roll_speed_and_surface_shape_output :: proc(t: ^testing.T) {
    stopped, smooth, rough := engine_sound.new_roll(23), engine_sound.new_roll(23), engine_sound.new_roll(23)
    stopped_samples, smooth_samples, rough_samples: [engine_sound.SAMPLE_RATE / 4]f32
    engine_sound.render_roll_add(&stopped, {speed = 0, roughness = 1, active = true}, stopped_samples[:])
    engine_sound.render_roll_add(&smooth, {speed = .7, roughness = .1, active = true}, smooth_samples[:])
    engine_sound.render_roll_add(&rough, {speed = .7, roughness = 1, active = true}, rough_samples[:])

    stopped_energy, smooth_energy, rough_energy := f64(0), f64(0), f64(0)
    for index in 0 ..< len(stopped_samples) {
        stopped_energy += f64(stopped_samples[index] * stopped_samples[index])
        smooth_energy += f64(smooth_samples[index] * smooth_samples[index])
        rough_energy += f64(rough_samples[index] * rough_samples[index])
        testing.expect(t, math.abs(rough_samples[index]) <= .92)
    }
    testing.expect(t, stopped_energy < .0001)
    testing.expect(t, smooth_energy > stopped_energy + .001)
    testing.expect(t, rough_energy > smooth_energy)
}
