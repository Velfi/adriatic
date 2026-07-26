package engine_sound

import "core:math"

Roll_Controls :: struct {
    speed:     f32,
    roughness: f32,
    active:    bool,
}

Roll_Synth :: struct {
    speed, roughness, level: f32,
    noise_state:             u32,
    road_low, road_body:     f32,
    tread_phase:             f32,
}

new_roll :: proc(seed := u32(0x85ebca6b)) -> Roll_Synth {
    return {noise_state = seed}
}

// render_roll_add models the tire contact patch rather than the engine. Speed
// raises tread cadence and spectral brightness; roughness moves energy from a
// smooth low road hum into coarse, broadband surface texture.
render_roll_add :: proc(synth: ^Roll_Synth, controls: Roll_Controls, samples: []f32) {
    if synth == nil || len(samples) == 0 do return
    target_speed := controls.active ? clamp(controls.speed, 0, 1) : f32(0)
    target_roughness := controls.active ? clamp(controls.roughness, 0, 1) : f32(0)
    target_level := controls.active && controls.speed > .015 ? f32(1) : f32(0)
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)

    for &sample in samples {
        synth.speed = approach(synth.speed, target_speed, 10, seconds_per_sample)
        synth.roughness = approach(synth.roughness, target_roughness, 8, seconds_per_sample)
        synth.level = approach(synth.level, target_level, target_level > 0 ? f32(8) : f32(18), seconds_per_sample)

        road := noise(&synth.noise_state)
        body_cutoff := .004 + synth.speed * .025
        detail_cutoff := .035 + synth.speed * .16
        synth.road_body += (road - synth.road_body) * body_cutoff
        synth.road_low += (road - synth.road_low) * detail_cutoff
        coarse_detail := road - synth.road_low

        tread_hz := 7 + synth.speed * 58
        synth.tread_phase += tread_hz * seconds_per_sample
        synth.tread_phase -= math.floor(synth.tread_phase)
        tread := .76 + math.sin(synth.tread_phase * TAU) * .16 +
            math.sin(synth.tread_phase * TAU * 2) * .08

        speed_gain := synth.speed * (.35 + synth.speed * .65)
        smooth_hum := synth.road_body * .32
        rough_texture := (synth.road_low * .22 + coarse_detail * .12) * synth.roughness
        rolling := (smooth_hum + rough_texture) * tread * speed_gain * synth.level
        sample = clamp(sample + rolling, -.92, .92)
    }
}
