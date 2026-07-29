package engine_sound

import "core:math"

Roll_Controls :: struct {
    speed:     f32,
    roughness: f32,
    wetness:   f32,
    damage:    f32,
    surface:   Footstep_Surface,
    active:    bool,
}

Roll_Synth :: struct {
    speed, roughness, wetness, damage, hardness, looseness, level: f32,
    hydroplane_mix:                                                f32,
    noise_state:                                                   u32,
    road_low, road_body:                                           f32,
    water_low:                                                     f32,
    tread_phase:                                                   f32,
    rear_tread_phase:                                              f32,
    knock_phase:                                                   f32,
    knock_interval:                                                f32,
    knock_level:                                                   f32,
    knock_count:                                                   u32,
    spray_phase:                                                   f32,
    spray_interval:                                                f32,
    spray_level:                                                   f32,
    spray_count:                                                   u32,
    hydroplane_phase:                                              f32,
    wobble_phase:                                                  f32,
    wobble_ring_phase:                                             f32,
    wobble_level:                                                  f32,
    wobble_count:                                                  u32,
}

new_roll :: proc(seed := u32(0x85ebca6b)) -> Roll_Synth {
    return {noise_state = seed, rear_tread_phase = .37, knock_interval = 1, spray_interval = 1}
}

// render_roll_add models the tire contact patch rather than the engine. Speed
// raises tread cadence and spectral brightness; roughness moves energy from a
// smooth low road hum into coarse, broadband surface texture.
render_roll_add :: proc(synth: ^Roll_Synth, controls: Roll_Controls, samples: []f32) {
    if synth == nil || len(samples) == 0 do return
    target_speed := controls.active ? clamp(controls.speed, 0, 1) : f32(0)
    target_roughness := controls.active ? clamp(controls.roughness, 0, 1) : f32(0)
    target_wetness := controls.active ? clamp(controls.wetness, 0, 1) : f32(0)
    target_hydroplane := clamp((target_wetness - .52) / .48, 0, 1) * clamp((target_speed - .42) / .58, 0, 1)
    target_damage := controls.active ? clamp(controls.damage, 0, 1) : f32(0)
    target_hardness, target_looseness := f32(0), f32(0)
    if controls.active {
        switch controls.surface {
        case .Grass:
            target_hardness, target_looseness = .08, .30
        case .Dirt:
            target_hardness, target_looseness = .20, .62
        case .Sand:
            target_hardness, target_looseness = .04, .78
        case .Gravel:
            target_hardness, target_looseness = .35, .96
        case .Cobblestone:
            target_hardness, target_looseness = .88, .19
        case .Asphalt:
            target_hardness, target_looseness = .94, .03
        }
    }
    target_level := controls.active && controls.speed > .015 ? f32(1) : f32(0)
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)

    for &sample in samples {
        synth.speed = approach(synth.speed, target_speed, 10, seconds_per_sample)
        synth.roughness = approach(synth.roughness, target_roughness, 8, seconds_per_sample)
        synth.hardness = approach(synth.hardness, target_hardness, 9, seconds_per_sample)
        synth.looseness = approach(synth.looseness, target_looseness, 9, seconds_per_sample)
        wetness_rate := target_wetness > synth.wetness ? f32(2.2) : f32(.11)
        synth.wetness = approach(synth.wetness, target_wetness, wetness_rate, seconds_per_sample)
        synth.hydroplane_mix = approach(synth.hydroplane_mix, target_hydroplane, 3.5, seconds_per_sample)
        synth.damage = approach(synth.damage, target_damage, 4, seconds_per_sample)
        synth.level = approach(synth.level, target_level, target_level > 0 ? f32(8) : f32(18), seconds_per_sample)

        road := noise(&synth.noise_state)
        body_cutoff := .004 + synth.speed * .025
        detail_cutoff := .035 + synth.speed * .16
        synth.road_body += (road - synth.road_body) * body_cutoff
        synth.road_low += (road - synth.road_low) * detail_cutoff
        synth.water_low += (road - synth.water_low) * (.08 + synth.speed * .14)
        coarse_detail := road - synth.road_low

        tread_hz := 7 + synth.speed * 58
        synth.tread_phase += tread_hz * seconds_per_sample
        synth.rear_tread_phase += tread_hz * 1.071 * seconds_per_sample
        synth.tread_phase -= math.floor(synth.tread_phase)
        synth.rear_tread_phase -= math.floor(synth.rear_tread_phase)
        front_tread := math.sin(synth.tread_phase * TAU) * .65 + math.sin(synth.tread_phase * TAU * 2) * .35
        rear_tread := math.sin(synth.rear_tread_phase * TAU)
        tread := .78 + front_tread * .12 + rear_tread * .08

        // Irregular stones, seams, and cobbles excite brief contact-patch
        // knocks. Event density follows wheel speed while roughness controls
        // their strength, keeping asphalt subdued and gravel lively.
        knock_hz := (3 + synth.speed * 27) * (.18 + synth.roughness * .82)
        synth.knock_phase += knock_hz * seconds_per_sample
        if synth.knock_phase >= synth.knock_interval {
            synth.knock_phase -= synth.knock_interval
            strength := .12 + (noise(&synth.noise_state) + 1) * .10
            material_knock := .42 + synth.looseness * .48 + synth.hardness * .22
            synth.knock_level += strength * synth.roughness * synth.roughness * material_knock
            synth.knock_interval = .55 + (noise(&synth.noise_state) + 1) * .45
            synth.knock_count += 1
        }
        synth.knock_level *= f32(math.exp(f64(-115 * seconds_per_sample)))
        knock := synth.knock_level * (synth.road_low * .5 + .5)

        // A wet contact patch adds high-passed water hiss plus irregular
        // displacement bursts. The film builds quickly in rain but dries
        // slowly after precipitation stops.
        spray_hz := (2 + synth.speed * 34) * synth.wetness
        synth.spray_phase += spray_hz * seconds_per_sample
        if synth.spray_phase >= synth.spray_interval {
            synth.spray_phase -= synth.spray_interval
            synth.spray_level += (.18 + (noise(&synth.noise_state) + 1) * .11) * synth.wetness
            synth.spray_interval = .55 + (noise(&synth.noise_state) + 1) * .45
            synth.spray_count += 1
        }
        synth.spray_level *= f32(math.exp(f64(-82 * seconds_per_sample)))
        water_hiss := (road - synth.water_low) * synth.wetness * (.08 + synth.speed * .13)
        water_burst := synth.spray_level * (synth.water_low * .35 + .65) * .17
        synth.hydroplane_phase += (11 + synth.speed * 24) * seconds_per_sample
        synth.hydroplane_phase -= math.floor(synth.hydroplane_phase)
        hydroplane_flutter :=
            (.72 + max(math.sin(synth.hydroplane_phase * TAU), f32(-.42)) * .28) * synth.hydroplane_mix

        // Collision damage leaves a wheel or tire out of round. Each wheel
        // revolution excites a short suspension mode plus a softer rubber
        // flap, so cadence follows road speed instead of becoming a fixed
        // warning sound.
        wobble_hz := 2.5 + synth.speed * 16
        previous_wobble_phase := synth.wobble_phase
        synth.wobble_phase += wobble_hz * seconds_per_sample
        synth.wobble_phase -= math.floor(synth.wobble_phase)
        if synth.wobble_phase < previous_wobble_phase && synth.damage > .001 {
            variation := (noise(&synth.noise_state) + 1) * .5
            synth.wobble_ring_phase = 0
            synth.wobble_level += (.09 + variation * .08) * synth.damage
            synth.wobble_count += 1
        }
        synth.wobble_ring_phase += (48 + synth.hardness * 29) * seconds_per_sample
        synth.wobble_ring_phase -= math.floor(synth.wobble_ring_phase)
        synth.wobble_level *= f32(math.exp(f64(-54 * seconds_per_sample)))
        suspension_thump := math.sin(synth.wobble_ring_phase * TAU) * synth.wobble_level
        tire_flap :=
            max(math.sin(synth.wobble_phase * TAU), f32(-.30)) *
            synth.damage *
            synth.speed *
            (.018 + synth.speed * .018)

        speed_gain := synth.speed * (.35 + synth.speed * .65)
        smooth_hum := synth.road_body * .32
        rough_texture := (synth.road_low * .22 + coarse_detail * .12) * synth.roughness
        loose_aggregate := coarse_detail * synth.looseness * (.05 + synth.roughness * .10)
        hard_tread := (front_tread * .72 + rear_tread * .28) * synth.hardness * (.018 + synth.speed * .032)
        contact_scale := 1 - synth.hydroplane_mix * .38
        water_film := ((road - synth.water_low) * .075 + synth.water_low * .018) * hydroplane_flutter
        rolling :=
            ((smooth_hum + rough_texture * contact_scale) * tread +
                loose_aggregate * contact_scale +
                hard_tread * contact_scale +
                knock * .28 * contact_scale +
                suspension_thump * .34 +
                tire_flap +
                water_hiss * (1 + synth.hydroplane_mix * .42) +
                water_burst * (1 + synth.hydroplane_mix * .28) +
                water_film) *
            speed_gain *
            synth.level
        sample += rolling
    }
}
