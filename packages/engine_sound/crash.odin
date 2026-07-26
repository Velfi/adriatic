package engine_sound

import "core:math"

Crash_Surface :: enum u8 {
    Grass,
    Dirt,
    Sand,
    Gravel,
    Cobblestone,
    Asphalt,
}

Crash_Profile :: enum u8 {
    Car,
    Fixed_Wing,
    Rotorcraft,
}

Vehicle_Impact_Detector :: struct {
    cooldown: f32,
}

CRASH_VOICE_COUNT :: 4

Crash_Mixer :: struct {
    voices:      [CRASH_VOICE_COUNT]Crash_Synth,
    next_voice:  int,
    stolen_tail: f32,
}

detect_vehicle_impact :: proc(
    detector: ^Vehicle_Impact_Detector,
    before_x, before_y, before_z: f32,
    after_x, after_y, after_z: f32,
    delta_seconds: f32,
) -> (
    severity, slide_speed, obliqueness: f32,
) {
    if detector == nil || delta_seconds <= 0 do return
    detector.cooldown = max(detector.cooldown - delta_seconds, f32(0))
    delta_x := after_x - before_x
    delta_y := after_y - before_y
    delta_z := after_z - before_z
    impulse_speed := f32(math.sqrt(f64(delta_x * delta_x + delta_y * delta_y + delta_z * delta_z)))
    before_speed := f32(math.sqrt(f64(before_x * before_x + before_y * before_y + before_z * before_z)))
    // Normal powertrain and braking forces change velocity gradually. A
    // collision resolves several metres per second in one frame, so requiring
    // both meaningful approach speed and a sharp impulse avoids engine noise
    // triggering during ordinary driving.
    if detector.cooldown > 0 || before_speed < 4 || impulse_speed < 2.4 do return
    severity = clamp((impulse_speed - 2.4) / 10, .15, 1)
    horizontal_after := f32(math.sqrt(f64(after_x * after_x + after_z * after_z)))
    slide_speed = clamp(horizontal_after / 22, 0, 1)
    // A velocity impulse opposing travel is a blunt strike; one crossing the
    // travel vector is a glancing impact. This remains useful without knowing
    // the collider normal and distinguishes side-swipes from head-on stops.
    alignment_denominator := before_speed * impulse_speed
    if alignment_denominator > .0001 {
        opposing_alignment := -(before_x * delta_x + before_y * delta_y + before_z * delta_z) / alignment_denominator
        obliqueness = 1 - clamp(opposing_alignment, 0, 1)
    }
    detector.cooldown = .22 + severity * .28
    return
}

vehicle_audio_damage_step :: proc(current, impact_severity, delta_seconds: f32) -> f32 {
    damage := clamp(current, 0, 1)
    severity := clamp(impact_severity, 0, 1)
    if severity > 0 {
        audible_impact := clamp((severity - .12) / .88, 0, 1)
        // One large collision should be clearly audible afterward, while
        // repeated lesser contacts can accumulate into a rough-running motor.
        damage = max(damage, audible_impact * .65)
        damage += audible_impact * (1 - damage) * .25
    }
    if delta_seconds > 0 {
        damage *= f32(math.exp(f64(-delta_seconds / 30)))
    }
    return clamp(damage, 0, 1)
}

Crash_Synth :: struct {
    noise_state:         u32,
    age:                 f32,
    duration:            f32,
    severity:            f32,
    water_mix:           f32,
    surface_wetness:     f32,
    slide_speed:         f32,
    obliqueness:         f32,
    surface:             Crash_Surface,
    profile:             Crash_Profile,
    body_scale:          f32,
    contact_frequency:   f32,
    metal_scale:         f32,
    ring_pitch_scale:    f32,
    debris_scale:        f32,
    ground_hardness:     f32,
    ground_grit:         f32,
    boom_low:            f32,
    tear_low:            f32,
    scrape_low:          f32,
    ground_low:          f32,
    ground_detail:       f32,
    ground_phase:        f32,
    ground_hz:           f32,
    surface_drag_phase:  f32,
    surface_drag_hz:     f32,
    splash_low:          f32,
    spray_low:           f32,
    bubble_phase:        f32,
    bubble_frequency:    f32,
    bubble_mix:          f32,
    ring_phase_a:        f32,
    ring_phase_b:        f32,
    ring_frequency_a:    f32,
    ring_frequency_b:    f32,
    crumple_phase:       f32,
    crumple_rate:        f32,
    crumple_hz:          f32,
    crumple_age_a:       f32,
    crumple_age_b:       f32,
    crumple_frequency_a: f32,
    crumple_frequency_b: f32,
    crumple_level_a:     f32,
    crumple_level_b:     f32,
    crumple_mix:         f32,
    crumple_next:        u8,
    crumple_count:       u32,
    debris_phase:        f32,
    debris_rate:         f32,
    debris_level:        f32,
    glass_phase:         f32,
    glass_rate:          f32,
    glass_level:         f32,
    glass_low:           f32,
    glass_mix:           f32,
    glass_phase_a:       f32,
    glass_phase_b:       f32,
    glass_frequency_a:   f32,
    glass_frequency_b:   f32,
    machinery_phase:     f32,
    machinery_rate:      f32,
    machinery_ring:      f32,
    machinery_ring_b:    f32,
    machinery_hz:        f32,
    machinery_level:     f32,
    machinery_level_b:   f32,
    machinery_mix:       f32,
    machinery_next:      u8,
    machinery_count:     u32,
    scrape_phase:        f32,
    rebound_time_a:      f32,
    rebound_time_b:      f32,
    rebound_level_a:     f32,
    rebound_level_b:     f32,
    settle_time:         f32,
    settle_phase:        f32,
    settle_hz:           f32,
    settle_mix:          f32,
    tire_burst_time:     f32,
    tire_burst_phase:    f32,
    tire_burst_hz:       f32,
    tire_burst_mix:      f32,
    tire_air_low:        f32,
    last_output:         f32,
}

new_crash :: proc(seed := u32(0x43524153)) -> Crash_Synth {
    return {noise_state = seed == 0 ? 0x43524153 : seed}
}

new_crash_mixer :: proc(seed := u32(0x43524153)) -> Crash_Mixer {
    mixer: Crash_Mixer
    base_seed := seed == 0 ? u32(0x43524153) : seed
    for index in 0 ..< CRASH_VOICE_COUNT {
        voice_seed := base_seed ~ (u32(index + 1) * u32(0x9e3779b9))
        mixer.voices[index] = new_crash(voice_seed)
    }
    return mixer
}

trigger_crash :: proc(
    synth: ^Crash_Synth,
    severity: f32,
    water_mix: f32 = 0,
    slide_speed: f32 = 0,
    surface: Crash_Surface = .Dirt,
    profile: Crash_Profile = .Car,
    surface_wetness: f32 = 0,
    obliqueness: f32 = 0,
) {
    if synth == nil do return
    synth.age = 0
    synth.severity = clamp(severity, .15, 1)
    synth.water_mix = clamp(water_mix, 0, 1)
    synth.surface_wetness = clamp(surface_wetness, 0, 1)
    synth.slide_speed = clamp(slide_speed, 0, 1)
    synth.obliqueness = clamp(obliqueness, 0, 1)
    synth.surface = surface
    synth.profile = profile
    glass_profile := f32(1)
    glass_base_a, glass_base_b := f32(2_250), f32(3_850)
    contact_base := f32(52)
    machinery_rate_base, machinery_hz_base, machinery_profile := f32(0), f32(0), f32(0)
    settle_hz_base, settle_profile := f32(82), f32(1)
    crumple_hz_base, crumple_profile := f32(175), f32(1)
    tire_profile := f32(1)
    switch profile {
    case .Car:
        synth.body_scale, synth.metal_scale, synth.ring_pitch_scale, synth.debris_scale = 1, 1, 1, 1
    case .Fixed_Wing:
        synth.body_scale, synth.metal_scale, synth.ring_pitch_scale, synth.debris_scale = .82, 1.18, 1.42, .92
        glass_profile = .72
        glass_base_a, glass_base_b = 3_150, 5_200
        contact_base = 68
        machinery_rate_base, machinery_hz_base, machinery_profile = 67, 710, .72
        settle_hz_base, settle_profile = 126, .72
        crumple_hz_base, crumple_profile = 270, .78
        tire_profile = 0
    case .Rotorcraft:
        synth.body_scale, synth.metal_scale, synth.ring_pitch_scale, synth.debris_scale = 1.08, .74, .78, 1.24
        glass_profile = .38
        glass_base_a, glass_base_b = 1_700, 3_050
        contact_base = 42
        machinery_rate_base, machinery_hz_base, machinery_profile = 17, 390, 1
        settle_hz_base, settle_profile = 57, 1.12
        crumple_hz_base, crumple_profile = 112, .88
        tire_profile = 0
    }
    synth.duration =
        .48 +
        synth.severity * .82 +
        synth.water_mix * .34 +
        synth.surface_wetness * (1 - synth.water_mix) * .10 +
        synth.slide_speed * .62 +
        synth.obliqueness * .10
    if profile == .Fixed_Wing {
        synth.duration += .12
    } else if profile == .Rotorcraft {
        synth.duration += .18
    }
    synth.boom_low = 0
    synth.tear_low = 0
    synth.scrape_low = 0
    synth.ground_low = 0
    synth.ground_detail = 0
    synth.ground_phase = 0
    synth.surface_drag_phase = 0
    synth.splash_low = 0
    synth.spray_low = 0
    synth.bubble_phase = 0
    synth.bubble_mix = synth.water_mix
    bubble_variation := (noise(&synth.noise_state) + 1) * .5
    synth.bubble_frequency = 19 + bubble_variation * 21 + synth.severity * 8
    synth.ring_phase_a = 0
    synth.ring_phase_b = .17
    synth.crumple_phase = .72
    synth.crumple_rate = 34 + synth.severity * 47
    synth.crumple_hz = crumple_hz_base
    synth.crumple_age_a = -1
    synth.crumple_age_b = -1
    synth.crumple_frequency_a = crumple_hz_base
    synth.crumple_frequency_b = crumple_hz_base * 1.17
    synth.crumple_level_a = 0
    synth.crumple_level_b = 0
    synth.crumple_mix =
        clamp((synth.severity - .28) / .72, 0, 1) *
        crumple_profile *
        (1 - synth.water_mix * .76) *
        (1 + synth.obliqueness * .22)
    synth.crumple_next = 0
    synth.crumple_count = 0
    synth.debris_phase = 0
    synth.debris_rate = 31 + synth.severity * 37
    synth.debris_level = 0
    synth.glass_phase = 0
    synth.glass_rate = 125 + synth.severity * 95
    synth.glass_level = 0
    synth.glass_low = 0
    synth.glass_mix =
        clamp((synth.severity - .48) / .52, 0, 1) *
        glass_profile *
        (1 - synth.water_mix * .82) *
        (1 - synth.surface_wetness * .12)
    synth.glass_phase_a = 0
    synth.glass_phase_b = .27
    glass_variation_a := (noise(&synth.noise_state) + 1) * .5
    glass_variation_b := (noise(&synth.noise_state) + 1) * .5
    synth.glass_frequency_a = glass_base_a * (.90 + glass_variation_a * .20)
    synth.glass_frequency_b = glass_base_b * (.90 + glass_variation_b * .20)
    machinery_variation := (noise(&synth.noise_state) + 1) * .5
    synth.machinery_phase = .78 + machinery_variation * .18
    synth.machinery_rate = machinery_rate_base * (.88 + machinery_variation * .24)
    synth.machinery_ring = 0
    synth.machinery_ring_b = 0
    synth.machinery_hz = machinery_hz_base * (.90 + machinery_variation * .20)
    synth.machinery_level = 0
    synth.machinery_level_b = 0
    synth.machinery_next = 0
    synth.machinery_count = 0
    synth.machinery_mix = clamp((synth.severity - .32) / .68, 0, 1) * machinery_profile * (1 - synth.water_mix * .76)
    contact_variation := (noise(&synth.noise_state) + 1) * .5
    synth.contact_frequency = contact_base * (.92 + contact_variation * .16)
    synth.scrape_phase = 0
    synth.last_output = 0
    switch surface {
    case .Grass:
        synth.ground_hardness, synth.ground_grit, synth.ground_hz = .08, .24, 47
        synth.surface_drag_hz = 45
    case .Dirt:
        synth.ground_hardness, synth.ground_grit, synth.ground_hz = .18, .46, 55
        synth.surface_drag_hz = 75
    case .Sand:
        synth.ground_hardness, synth.ground_grit, synth.ground_hz = .04, .67, 39
        synth.surface_drag_hz = 38
    case .Gravel:
        synth.ground_hardness, synth.ground_grit, synth.ground_hz = .42, .94, 81
        synth.surface_drag_hz = 160
    case .Cobblestone:
        synth.ground_hardness, synth.ground_grit, synth.ground_hz = .88, .53, 126
        synth.surface_drag_hz = 260
    case .Asphalt:
        synth.ground_hardness, synth.ground_grit, synth.ground_hz = .76, .20, 108
        synth.surface_drag_hz = 520
    }
    // Each impact advances the seed, producing a different arrangement of
    // tearing metal and secondary debris without relying on sampled assets.
    variation_a := (noise(&synth.noise_state) + 1) * .5
    variation_b := (noise(&synth.noise_state) + 1) * .5
    synth.ring_frequency_a = (118 + variation_a * 94 + synth.severity * 42) * synth.ring_pitch_scale
    synth.ring_frequency_b = (263 + variation_b * 157 + synth.severity * 71) * synth.ring_pitch_scale
    // A damaged chassis rarely stops on the first contact. Two irregular,
    // rapidly decaying rebounds add weight without becoming a rhythmic echo.
    rebound_variation_a := (noise(&synth.noise_state) + 1) * .5
    rebound_variation_b := (noise(&synth.noise_state) + 1) * .5
    synth.rebound_time_a = .095 + rebound_variation_a * .075
    synth.rebound_time_b = synth.rebound_time_a + .105 + rebound_variation_b * .14
    water_damping := 1 - synth.water_mix * .68
    synth.rebound_level_a = (.22 + synth.severity * .42) * water_damping
    synth.rebound_level_b = (.10 + synth.severity * .25) * water_damping
    settle_variation := (noise(&synth.noise_state) + 1) * .5
    synth.settle_time = synth.rebound_time_b + .045 + settle_variation * .085
    synth.settle_phase = .12 + settle_variation * .21
    synth.settle_hz = settle_hz_base * (.88 + settle_variation * .24)
    synth.settle_mix = clamp((synth.severity - .38) / .62, 0, 1) * settle_profile * (1 - synth.water_mix * .72)
    tire_variation := (noise(&synth.noise_state) + 1) * .5
    synth.tire_burst_time = .032 + tire_variation * .058
    synth.tire_burst_phase = 0
    synth.tire_burst_hz = 118 + tire_variation * 74
    synth.tire_burst_mix = clamp((synth.severity - .58) / .42, 0, 1) * tire_profile * (1 - synth.water_mix * .90)
    synth.tire_air_low = 0
}

crash_voice_audibility :: proc(synth: ^Crash_Synth) -> f32 {
    if synth == nil || synth.duration <= 0 || synth.age >= synth.duration do return 0
    remaining := clamp(1 - synth.age / synth.duration, 0, 1)
    source_weight := .35 + synth.severity * .65 + synth.slide_speed * .18 + synth.water_mix * .10
    return remaining * remaining * source_weight
}

trigger_crash_mixer :: proc(
    mixer: ^Crash_Mixer,
    severity: f32,
    water_mix: f32 = 0,
    slide_speed: f32 = 0,
    surface: Crash_Surface = .Dirt,
    profile: Crash_Profile = .Car,
    surface_wetness: f32 = 0,
    obliqueness: f32 = 0,
) -> int {
    if mixer == nil do return -1
    voice_index := mixer.next_voice
    found_idle := false
    for offset in 0 ..< CRASH_VOICE_COUNT {
        candidate := (mixer.next_voice + offset) % CRASH_VOICE_COUNT
        if mixer.voices[candidate].duration <= 0 {
            voice_index = candidate
            found_idle = true
            break
        }
    }
    if !found_idle {
        quietest := crash_voice_audibility(&mixer.voices[voice_index])
        for offset in 1 ..< CRASH_VOICE_COUNT {
            candidate := (mixer.next_voice + offset) % CRASH_VOICE_COUNT
            audibility := crash_voice_audibility(&mixer.voices[candidate])
            if audibility < quietest {
                voice_index = candidate
                quietest = audibility
            }
        }
        // Preserve the old voice's final sample, then decay it quickly in the
        // mixer. This bridges the replacement boundary without retaining a
        // full fifth synthesis voice.
        mixer.stolen_tail = clamp(mixer.stolen_tail + mixer.voices[voice_index].last_output, f32(-.65), f32(.65))
    }
    trigger_crash(
        &mixer.voices[voice_index],
        severity,
        water_mix,
        slide_speed,
        surface,
        profile,
        surface_wetness,
        obliqueness,
    )
    mixer.next_voice = (voice_index + 1) % CRASH_VOICE_COUNT
    return voice_index
}

render_crash_add :: proc(synth: ^Crash_Synth, samples: []f32) {
    if synth == nil || synth.duration <= 0 do return
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)

    for &sample in samples {
        if synth.age >= synth.duration {
            synth.duration = 0
            synth.last_output = 0
            break
        }
        progress := synth.age / synth.duration
        impact_envelope := f32(math.exp(f64(-progress * (7 + synth.severity * 3))))
        debris_envelope := f32(math.exp(f64(-progress * 3.4))) * min(progress * 18, f32(1))

        rough := noise(&synth.noise_state)
        synth.boom_low += (rough - synth.boom_low) * (.025 + synth.severity * .018)
        synth.tear_low += (rough - synth.tear_low) * .24
        synth.scrape_low += (rough - synth.scrape_low) * (.045 + synth.slide_speed * .11)
        synth.ground_low += (rough - synth.ground_low) * (.014 + synth.ground_hardness * .026)
        synth.ground_detail += (rough - synth.ground_detail) * (.09 + synth.ground_grit * .16)
        synth.splash_low += (rough - synth.splash_low) * (.012 + synth.severity * .008)
        synth.spray_low += (rough - synth.spray_low) * (.11 + synth.severity * .08)
        tearing := rough - synth.tear_low

        // Two inharmonic modes give the impact a bent sheet-metal body. Their
        // pitch droops slightly as the structure loses energy.
        pitch_droop := 1 - progress * (.08 + synth.severity * .07)
        synth.ring_phase_a += synth.ring_frequency_a * pitch_droop * seconds_per_sample
        synth.ring_phase_b += synth.ring_frequency_b * pitch_droop * seconds_per_sample
        synth.ring_phase_a -= f32(math.floor(f64(synth.ring_phase_a)))
        synth.ring_phase_b -= f32(math.floor(f64(synth.ring_phase_b)))
        ring_envelope := f32(math.exp(f64(-progress * (4.3 + synth.severity))))
        ringing :=
            (f32(math.sin(f64(synth.ring_phase_a * TAU))) * .62 + f32(math.sin(f64(synth.ring_phase_b * TAU))) * .38) *
            ring_envelope

        // Structural collapse arrives as a short cascade of irregular panel
        // buckles rather than one monolithic noise burst. Alternating
        // zero-crossing resonators let adjacent failures overlap without
        // introducing digital discontinuities.
        crumple_cascade := f32(0)
        crumple_window := .13 + synth.severity * .10
        if synth.crumple_mix > 0 && synth.age < crumple_window {
            collapse_slowdown := max(1 - synth.age / crumple_window * .62, f32(.28))
            synth.crumple_phase += synth.crumple_rate * collapse_slowdown * seconds_per_sample
            if synth.crumple_phase >= 1 {
                synth.crumple_phase -= 1
                buckle_variation := (noise(&synth.noise_state) + 1) * .5
                synth.crumple_rate = 30 + (noise(&synth.noise_state) + 1) * 24 + synth.severity * 24
                buckle_level := (.18 + buckle_variation * .20) * synth.crumple_mix
                buckle_frequency := synth.crumple_hz * (.78 + buckle_variation * .48)
                if synth.crumple_next == 0 {
                    synth.crumple_age_a = 0
                    synth.crumple_level_a = buckle_level
                    synth.crumple_frequency_a = buckle_frequency
                    synth.crumple_next = 1
                } else {
                    synth.crumple_age_b = 0
                    synth.crumple_level_b = buckle_level
                    synth.crumple_frequency_b = buckle_frequency * 1.09
                    synth.crumple_next = 0
                }
                synth.crumple_count += 1
            }
        }
        if synth.crumple_age_a >= 0 {
            buckle_envelope_a := f32(math.exp(f64(-synth.crumple_age_a * (48 + synth.severity * 17))))
            crumple_cascade +=
                math.sin(synth.crumple_age_a * synth.crumple_frequency_a * TAU) *
                buckle_envelope_a *
                synth.crumple_level_a
            synth.crumple_age_a += seconds_per_sample
        }
        if synth.crumple_age_b >= 0 {
            buckle_envelope_b := f32(math.exp(f64(-synth.crumple_age_b * (52 + synth.severity * 15))))
            crumple_cascade +=
                math.sin(synth.crumple_age_b * synth.crumple_frequency_b * TAU) *
                buckle_envelope_b *
                synth.crumple_level_b
            synth.crumple_age_b += seconds_per_sample
        }

        synth.debris_phase += synth.debris_rate * seconds_per_sample
        if synth.debris_phase >= 1 {
            synth.debris_phase -= 1
            synth.debris_rate = 24 + (noise(&synth.noise_state) + 1) * 29
            synth.debris_level += noise(&synth.noise_state) * (.42 + synth.severity * .28) * synth.debris_scale
        }
        // A few milliseconds of decay turns each debris impulse into a small
        // physical knock instead of a one-sample digital click.
        synth.debris_level *= f32(math.exp(f64(-190 * seconds_per_sample)))
        clatter := synth.debris_level * debris_envelope

        // Severe impacts shed short, aperiodic brittle fragments. Cars carry
        // the strongest window layer, fixed-wing canopies are lighter, and
        // rotorcraft glazing is quieter; water suppresses the bright fracture.
        synth.glass_low += (rough - synth.glass_low) * .47
        synth.glass_phase += synth.glass_rate * seconds_per_sample
        if synth.glass_phase >= 1 {
            synth.glass_phase -= 1
            synth.glass_rate = 105 + (noise(&synth.noise_state) + 1) * 115
            synth.glass_level += (.10 + (noise(&synth.noise_state) + 1) * .09) * synth.glass_mix
        }
        synth.glass_level *= f32(math.exp(f64(-430 * seconds_per_sample)))
        glass_envelope := f32(math.exp(f64(-synth.age * 4.8)))
        glass_pitch_droop := 1 - progress * .07
        synth.glass_phase_a += synth.glass_frequency_a * glass_pitch_droop * seconds_per_sample
        synth.glass_phase_b += synth.glass_frequency_b * glass_pitch_droop * seconds_per_sample
        synth.glass_phase_a -= math.floor(synth.glass_phase_a)
        synth.glass_phase_b -= math.floor(synth.glass_phase_b)
        glass_tinkle := math.sin(synth.glass_phase_a * TAU) * .62 + math.sin(synth.glass_phase_b * TAU) * .38
        brittle_fracture := ((rough - synth.glass_low) * .68 + glass_tinkle * .32) * synth.glass_level * glass_envelope

        // A severe car impact can rupture a tire shortly after the body
        // contact. A short membrane mode supplies the pressure pop, followed
        // by high-passed escaping air; aircraft profiles and submerged
        // impacts suppress this car-specific layer.
        synth.tire_air_low += (rough - synth.tire_air_low) * .21
        tire_burst := f32(0)
        tire_age := synth.age - synth.tire_burst_time
        if tire_age >= 0 && synth.tire_burst_mix > 0 {
            synth.tire_burst_phase += synth.tire_burst_hz * (1 - min(tire_age * 1.7, f32(.18))) * seconds_per_sample
            synth.tire_burst_phase -= math.floor(synth.tire_burst_phase)
            membrane_pop := math.sin(synth.tire_burst_phase * TAU) * f32(math.exp(f64(-tire_age * 49)))
            air_attack := 1 - f32(math.exp(f64(-tire_age * 85)))
            air_hiss := (rough - synth.tire_air_low) * air_attack * f32(math.exp(f64(-tire_age * 7.2)))
            tire_burst = (membrane_pop * .72 + air_hiss * .28) * synth.tire_burst_mix
        }

        // Aircraft retain rotating energy after the fuselage makes contact.
        // Each decelerating blade strike excites a short metal mode rather
        // than emitting a one-sample click. Propeller strikes are quicker and
        // brighter; rotorcraft strikes are slower and heavier.
        machinery_strike := f32(0)
        if synth.machinery_mix > 0 {
            machinery_rate := synth.machinery_rate * max(1 - progress * .84, f32(.08))
            synth.machinery_phase += machinery_rate * seconds_per_sample
            if synth.machinery_phase >= 1 {
                synth.machinery_phase -= 1
                strike_variation := (noise(&synth.noise_state) + 1) * .5
                strike_level := (.28 + strike_variation * .24) * synth.machinery_mix
                if synth.machinery_next == 0 {
                    synth.machinery_ring = 0
                    synth.machinery_level = strike_level
                    synth.machinery_next = 1
                } else {
                    synth.machinery_ring_b = 0
                    synth.machinery_level_b = strike_level
                    synth.machinery_next = 0
                }
                synth.machinery_count += 1
            }
            machinery_ring_step := synth.machinery_hz * (1 - progress * .18) * seconds_per_sample
            synth.machinery_ring += machinery_ring_step
            synth.machinery_ring_b += machinery_ring_step * 1.013
            synth.machinery_ring -= math.floor(synth.machinery_ring)
            synth.machinery_ring_b -= math.floor(synth.machinery_ring_b)
            synth.machinery_level *= f32(math.exp(f64(-82 * seconds_per_sample)))
            synth.machinery_level_b *= f32(math.exp(f64(-82 * seconds_per_sample)))
            machinery_strike =
                (math.sin(synth.machinery_ring * TAU) * synth.machinery_level +
                    math.sin(synth.machinery_ring_b * TAU) * synth.machinery_level_b) *
                f32(math.exp(f64(-progress * 2.2)))
        }

        contact_attack := 1 - f32(math.exp(f64(-synth.age * 320)))
        contact_decay := f32(math.exp(f64(-synth.age * (21 + synth.severity * 7))))
        compression_pulse :=
            math.sin(synth.age * synth.contact_frequency * TAU) *
            contact_attack *
            contact_decay *
            (.48 + synth.severity * .52) *
            synth.body_scale *
            (1 - synth.obliqueness * .38)
        initial_slam :=
            synth.boom_low *
                impact_envelope *
                (1.5 + synth.severity) *
                synth.body_scale *
                (1 - synth.obliqueness * .32) +
            compression_pulse * .46
        metal :=
            tearing *
            (impact_envelope * .58 + debris_envelope * .24) *
            synth.metal_scale *
            (1 + synth.obliqueness * .34)
        resonant_body := ringing * (.18 + synth.severity * .16) * synth.metal_scale * (1 + synth.obliqueness * .18)
        rebound_a, rebound_b := f32(0), f32(0)
        rebound_age_a := synth.age - synth.rebound_time_a
        if rebound_age_a >= 0 {
            rebound_envelope_a :=
                min(rebound_age_a * 190, f32(1)) * f32(math.exp(f64(-rebound_age_a * (24 + synth.severity * 7))))
            rebound_a =
                (synth.boom_low * 1.35 + tearing * .16 + ringing * .11) * rebound_envelope_a * synth.rebound_level_a
        }
        rebound_age_b := synth.age - synth.rebound_time_b
        if rebound_age_b >= 0 {
            rebound_envelope_b :=
                min(rebound_age_b * 165, f32(1)) * f32(math.exp(f64(-rebound_age_b * (27 + synth.severity * 8))))
            rebound_b =
                (synth.boom_low * 1.18 + tearing * .12 + ringing * .08) * rebound_envelope_b * synth.rebound_level_b
        }
        // Once the sharp rebounds subside, stressed bodywork relaxes with a
        // slower downward torsional sweep. Its delayed attack keeps it
        // perceptually separate from the collision and secondary knocks.
        settling_groan := f32(0)
        settle_age := synth.age - synth.settle_time
        if settle_age >= 0 && synth.settle_mix > 0 {
            settle_pitch := max(1 - settle_age * 1.18, f32(.42))
            synth.settle_phase += synth.settle_hz * settle_pitch * seconds_per_sample
            synth.settle_phase -= math.floor(synth.settle_phase)
            settle_attack := 1 - f32(math.exp(f64(-settle_age * 34)))
            settle_decay := f32(math.exp(f64(-settle_age * (5.2 + synth.severity * .8))))
            settle_modes := math.sin(synth.settle_phase * TAU) * .78 + math.sin(synth.settle_phase * TAU * 1.47) * .22
            settling_groan =
                settle_modes * settle_attack * settle_decay * synth.settle_mix * (.88 + synth.tear_low * .12)
        }

        // Tangential impact speed sustains a high-passed scrape after the
        // initial strike. A slowing, asymmetric judder models seams and
        // structural contact without introducing a fixed pitched tone.
        scrape_hz := (18 + synth.slide_speed * 43) * (1 - progress * .72)
        synth.scrape_phase += scrape_hz * seconds_per_sample
        synth.scrape_phase -= math.floor(synth.scrape_phase)
        scrape_judder := .62 + max(math.sin(synth.scrape_phase * TAU), f32(-.35)) * .38
        scrape_envelope := f32(math.exp(f64(-progress * (1.8 + (1 - synth.slide_speed) * 2.2))))
        scrape_detail := rough - synth.scrape_low
        scrape :=
            (scrape_detail * .58 + tearing * .22 + synth.boom_low * .20) *
            scrape_judder *
            scrape_envelope *
            max(synth.slide_speed, synth.obliqueness * .42)
        metal_crash :=
            initial_slam +
            metal +
            resonant_body +
            crumple_cascade * .46 +
            clatter +
            brittle_fracture +
            tire_burst * .34 +
            machinery_strike * .42 +
            settling_groan * .24 +
            scrape * .62 +
            rebound_a +
            rebound_b

        // Ground contact is independent of the bending vehicle shell. Soft
        // terrain supplies displaced-earth body, loose aggregate adds crunch,
        // and pavement excites a short hard mode.
        synth.ground_phase += synth.ground_hz * (1 - progress * .18) * seconds_per_sample
        synth.ground_phase -= math.floor(synth.ground_phase)
        ground_envelope := f32(math.exp(f64(-progress * (5.2 + synth.ground_hardness * 4.5))))
        ground_tail := f32(math.exp(f64(-progress * 3.1)))
        ground_tone := math.sin(synth.ground_phase * TAU) * synth.ground_hardness * ground_envelope
        ground_crunch := (rough - synth.ground_detail) * synth.ground_grit * ground_tail
        displaced_ground := synth.ground_low * ground_envelope * (1.05 - synth.ground_hardness * .34)
        synth.surface_drag_phase += synth.surface_drag_hz * (1 - progress * .36) * seconds_per_sample
        synth.surface_drag_phase -= math.floor(synth.surface_drag_phase)
        drag_tone :=
            math.sin(synth.surface_drag_phase * TAU) * synth.ground_hardness * (1 - synth.surface_wetness * .25)
        drag_chatter :=
            max(math.sin(synth.surface_drag_phase * TAU * (1.7 + synth.ground_grit)), f32(-.34)) * synth.ground_grit
        drag_aggregate := (rough - synth.ground_detail) * synth.ground_grit
        surface_drag :=
            (drag_tone * .18 + drag_chatter * .12 + drag_aggregate * .22) *
            synth.slide_speed *
            scrape_envelope *
            (1 - synth.water_mix) *
            (.45 + synth.severity * .35)
        ground_contact :=
            (displaced_ground * .52 + ground_crunch * .25 + ground_tone * .31) * (.35 + synth.severity * .45) +
            surface_drag

        // Water contact replaces most of the ringing and debris with a deep
        // displaced-water body and a longer high-passed spray tail.
        water_envelope := f32(math.exp(f64(-progress * 2.65)))
        water_body := synth.splash_low * impact_envelope * (2.1 + synth.severity)
        water_spray :=
            (rough - synth.spray_low) * (impact_envelope * .22 + water_envelope * (.43 + synth.slide_speed * .18))
        bubble_gurgle := f32(0)
        if synth.age >= .07 {
            bubble_age := synth.age - .07
            bubble_wobble := 1 + clamp(synth.splash_low * .18, -.08, .08)
            synth.bubble_phase += synth.bubble_frequency * bubble_wobble * seconds_per_sample
            synth.bubble_phase -= math.floor(synth.bubble_phase)
            bubble_envelope :=
                (1 - f32(math.exp(f64(-bubble_age * 16)))) *
                f32(math.exp(f64(-bubble_age * (2.7 + synth.severity * .45))))
            bubble_modes := math.sin(synth.bubble_phase * TAU) * .72 + math.sin(synth.bubble_phase * TAU * 1.71) * .28
            bubble_gurgle = bubble_modes * bubble_envelope * synth.bubble_mix * (.16 + synth.severity * .12)
        }
        water_impact := water_body + water_spray + bubble_gurgle
        wet_surface_mix := synth.surface_wetness * (1 - synth.water_mix)
        puddle_slap := synth.splash_low * impact_envelope * (.34 + synth.severity * .26)
        wet_surface_spray :=
            (rough - synth.spray_low) * (impact_envelope * .10 + water_envelope * (.13 + synth.slide_speed * .09))
        wet_surface_impact := (puddle_slap + wet_surface_spray) * wet_surface_mix
        material_mix :=
            metal_crash * (1 - synth.water_mix * .72) +
            ground_contact * (1 - synth.water_mix) +
            water_impact * synth.water_mix +
            wet_surface_impact
        mixed := material_mix * (.28 + synth.severity * .34)
        sample += mixed
        synth.last_output = mixed
        synth.age += seconds_per_sample
    }
}

render_crash_mixer_add :: proc(mixer: ^Crash_Mixer, samples: []f32) {
    if mixer == nil do return
    for &voice in mixer.voices {
        render_crash_add(&voice, samples)
    }
    tail_decay := f32(math.exp(f64(-185.0 / SAMPLE_RATE)))
    for &sample in samples {
        sample += mixer.stolen_tail
        mixer.stolen_tail *= tail_decay
        if abs(mixer.stolen_tail) < .000001 do mixer.stolen_tail = 0
    }
}
