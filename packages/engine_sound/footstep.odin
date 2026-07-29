package engine_sound

import "core:math"

Footstep_Surface :: enum u8 {
    Grass,
    Dirt,
    Sand,
    Gravel,
    Cobblestone,
    Asphalt,
}

FOOTSTEP_VOICE_COUNT :: 4

Footstep_Mixer :: struct {
    voices:            [FOOTSTEP_VOICE_COUNT]Footstep_Synth,
    next_voice:        int,
    next_side:         f32,
    stolen_tail_left:  f32,
    stolen_tail_right: f32,
}

Footstep_Synth :: struct {
    noise_state:    u32,
    age:            f32,
    duration:       f32,
    intensity:      f32,
    landing_mix:    f32,
    wetness:        f32,
    hardness:       f32,
    grit:           f32,
    body_low:       f32,
    detail_low:     f32,
    tap_phase:      f32,
    tap_hz:         f32,
    toe_low:        f32,
    toe_phase:      f32,
    toe_hz:         f32,
    toe_delay:      f32,
    landing_slide:  f32,
    slide_low:      f32,
    slide_phase:    f32,
    water_low:      f32,
    water_detail:   f32,
    grain_phase:    f32,
    grain_interval: f32,
    grain_rate:     f32,
    grain_level:    f32,
    grain_tone:     f32,
    grain_low:      f32,
    grain_count:    u32,
    pan:            f32,
    last_output:    f32,
}

new_footstep :: proc(seed := u32(0x50415753)) -> Footstep_Synth {
    return {noise_state = seed == 0 ? 0x50415753 : seed}
}

new_footstep_mixer :: proc(seed := u32(0x50415753)) -> Footstep_Mixer {
    mixer: Footstep_Mixer
    base_seed := seed == 0 ? u32(0x50415753) : seed
    for index in 0 ..< FOOTSTEP_VOICE_COUNT {
        voice_seed := base_seed ~ (u32(index + 1) * u32(0x85ebca6b))
        mixer.voices[index] = new_footstep(voice_seed)
    }
    mixer.next_side = -.14
    return mixer
}

footstep_phase_crossed :: proc(previous, current: f32) -> bool {
    if current < previous do return true
    return previous < math.PI && current >= math.PI
}

trigger_footstep :: proc(
    synth: ^Footstep_Synth,
    intensity: f32,
    surface: Footstep_Surface,
    landing: bool = false,
    wetness: f32 = 0,
    landing_slide: f32 = 0,
) {
    if synth == nil do return
    synth.age = 0
    synth.intensity = clamp(intensity, .08, 1)
    synth.landing_mix = landing ? 1 : 0
    synth.wetness = clamp(wetness, 0, 1)
    synth.landing_slide = landing ? clamp(landing_slide, 0, 1) : 0
    synth.body_low = 0
    synth.detail_low = 0
    synth.tap_phase = 0
    synth.toe_low = 0
    synth.toe_phase = 0
    synth.slide_low = 0
    synth.slide_phase = 0
    synth.water_low = 0
    synth.water_detail = 0
    synth.grain_phase = 0
    synth.grain_interval = .58 + (noise(&synth.noise_state) + 1) * .42
    synth.grain_level = 0
    synth.grain_tone = 0
    synth.grain_low = 0
    synth.grain_count = 0
    synth.last_output = 0
    switch surface {
    case .Grass:
        synth.hardness, synth.grit, synth.tap_hz, synth.duration, synth.grain_rate = .12, .28, 58, .18, 34
    case .Dirt:
        synth.hardness, synth.grit, synth.tap_hz, synth.duration, synth.grain_rate = .24, .48, 66, .17, 58
    case .Sand:
        synth.hardness, synth.grit, synth.tap_hz, synth.duration, synth.grain_rate = .08, .68, 48, .20, 92
    case .Gravel:
        synth.hardness, synth.grit, synth.tap_hz, synth.duration, synth.grain_rate = .46, .92, 92, .15, 138
    case .Cobblestone:
        synth.hardness, synth.grit, synth.tap_hz, synth.duration, synth.grain_rate = .82, .54, 138, .13, 20
    case .Asphalt:
        synth.hardness, synth.grit, synth.tap_hz, synth.duration, synth.grain_rate = .72, .22, 116, .12, 10
    }
    if landing {
        synth.duration += .09 + synth.landing_slide * .10
        synth.tap_hz *= .75
    }
    synth.duration += synth.wetness * .025
    // Small seeded variations keep repeated contacts from becoming a fixed
    // two-hit pattern while retaining deterministic playback and tests.
    tone_variation := .92 + (noise(&synth.noise_state) + 1) * .08
    timing_variation := (noise(&synth.noise_state) + 1) * .006
    synth.tap_hz *= tone_variation
    synth.toe_hz = synth.tap_hz * (1.26 + synth.hardness * .18)
    synth.toe_delay = .043 + (1 - synth.intensity) * .018 + timing_variation
    if landing do synth.toe_delay += .018
}

footstep_voice_audibility :: proc(synth: ^Footstep_Synth) -> f32 {
    if synth == nil || synth.duration <= 0 || synth.age >= synth.duration do return 0
    remaining := clamp(1 - synth.age / synth.duration, 0, 1)
    source_weight := .3 + synth.intensity * .7 + synth.landing_mix * .25 + synth.wetness * .08
    return remaining * remaining * source_weight
}

trigger_footstep_mixer :: proc(
    mixer: ^Footstep_Mixer,
    intensity: f32,
    surface: Footstep_Surface,
    landing: bool = false,
    wetness: f32 = 0,
    landing_slide: f32 = 0,
) -> int {
    if mixer == nil do return -1
    voice_index := mixer.next_voice
    found_idle := false
    for offset in 0 ..< FOOTSTEP_VOICE_COUNT {
        candidate := (mixer.next_voice + offset) % FOOTSTEP_VOICE_COUNT
        if mixer.voices[candidate].duration <= 0 {
            voice_index = candidate
            found_idle = true
            break
        }
    }
    if !found_idle {
        quietest := footstep_voice_audibility(&mixer.voices[voice_index])
        for offset in 1 ..< FOOTSTEP_VOICE_COUNT {
            candidate := (mixer.next_voice + offset) % FOOTSTEP_VOICE_COUNT
            audibility := footstep_voice_audibility(&mixer.voices[candidate])
            if audibility < quietest {
                voice_index = candidate
                quietest = audibility
            }
        }
        stolen_voice := &mixer.voices[voice_index]
        mixer.stolen_tail_left = clamp(
            mixer.stolen_tail_left + stolen_voice.last_output * (1 - stolen_voice.pan),
            f32(-.45),
            f32(.45),
        )
        mixer.stolen_tail_right = clamp(
            mixer.stolen_tail_right + stolen_voice.last_output * (1 + stolen_voice.pan),
            f32(-.45),
            f32(.45),
        )
    }
    trigger_footstep(&mixer.voices[voice_index], intensity, surface, landing, wetness, landing_slide)
    if landing {
        mixer.voices[voice_index].pan = 0
    } else {
        if mixer.next_side == 0 do mixer.next_side = -.14
        mixer.voices[voice_index].pan = mixer.next_side
        mixer.next_side = -mixer.next_side
    }
    mixer.next_voice = (voice_index + 1) % FOOTSTEP_VOICE_COUNT
    return voice_index
}

render_footstep_add :: proc(synth: ^Footstep_Synth, samples: []f32) {
    if synth == nil || synth.duration <= 0 do return
    seconds_per_sample := f32(1.0 / SAMPLE_RATE)
    for &sample in samples {
        if synth.age >= synth.duration {
            synth.duration = 0
            synth.last_output = 0
            break
        }
        progress := synth.age / synth.duration
        contact_envelope := f32(math.exp(f64(-progress * (6.5 + synth.hardness * 5))))
        grit_envelope := f32(math.exp(f64(-progress * 4.2)))
        rough := noise(&synth.noise_state)
        synth.body_low += (rough - synth.body_low) * (.018 + synth.hardness * .025)
        synth.detail_low += (rough - synth.detail_low) * (.10 + synth.grit * .15)
        synth.toe_low += (rough - synth.toe_low) * (.07 + synth.grit * .12)
        synth.slide_low += (rough - synth.slide_low) * (.055 + synth.hardness * .075)
        synth.water_low += (rough - synth.water_low) * (.012 + synth.hardness * .018)
        synth.water_detail += (rough - synth.water_detail) * (.08 + synth.hardness * .10)

        // Loose ground is a cloud of short, irregular particle contacts, not
        // merely continuous noise. Seeded micro-grains give gravel individual
        // stone ticks and sand a denser, softer cascade without sacrificing
        // deterministic playback.
        grain_density := synth.grain_rate * (1 - progress * .72) * (.65 + synth.intensity * .35)
        synth.grain_phase += grain_density * seconds_per_sample
        if synth.grain_phase >= synth.grain_interval {
            synth.grain_phase -= synth.grain_interval
            variation := (noise(&synth.noise_state) + 1) * .5
            synth.grain_level = (.35 + variation * .65) * synth.grit
            synth.grain_tone = 420 + variation * 2_300 + synth.hardness * 1_100
            // A renewal interval avoids the machine-like cadence produced by
            // a fixed grain clock while preserving the requested mean
            // aggregate density.
            synth.grain_interval = .58 + (noise(&synth.noise_state) + 1) * .42
            synth.grain_count += 1
        }
        grain_excitation := noise(&synth.noise_state)
        synth.grain_low +=
            (grain_excitation - synth.grain_low) * clamp(synth.grain_tone / SAMPLE_RATE, f32(.01), f32(.12))
        grain_tick := (grain_excitation - synth.grain_low) * synth.grain_level
        synth.grain_level *= f32(math.exp(f64(-(150 + synth.hardness * 210) * seconds_per_sample)))

        synth.tap_phase += synth.tap_hz * (1 - progress * .12) * seconds_per_sample
        synth.tap_phase -= math.floor(synth.tap_phase)
        tap := math.sin(synth.tap_phase * TAU) * contact_envelope * synth.hardness

        // A delayed toe contact gives each ordinary step a readable weight
        // transfer. Hard ground emphasizes the pitched tap; loose ground
        // replaces it with a short granular scuff.
        toe_tap, toe_scuff, toe_splash := f32(0), f32(0), f32(0)
        if synth.age >= synth.toe_delay {
            toe_age := synth.age - synth.toe_delay
            synth.toe_phase += synth.toe_hz * (1 - min(toe_age * 1.8, f32(.14))) * seconds_per_sample
            synth.toe_phase -= math.floor(synth.toe_phase)
            toe_envelope := f32(math.exp(f64(-toe_age * (38 + synth.hardness * 34))))
            toe_tap = math.sin(synth.toe_phase * TAU) * toe_envelope * synth.hardness
            toe_scuff = (rough - synth.toe_low) * toe_envelope * synth.grit
            toe_splash = (rough - synth.water_detail) * toe_envelope * synth.wetness * (.08 + synth.hardness * .08)
        }
        landing_envelope := f32(math.exp(f64(-progress * 3.2))) * synth.landing_mix
        landing_scuff := f32(0)
        if synth.landing_slide > 0 && synth.age >= .025 {
            slide_age := synth.age - .025
            slide_hz := (24 + synth.landing_slide * 46) * (1 - progress * .55)
            synth.slide_phase += slide_hz * seconds_per_sample
            synth.slide_phase -= math.floor(synth.slide_phase)
            slide_judder := .68 + max(math.sin(synth.slide_phase * TAU), f32(-.4)) * .32
            slide_envelope :=
                (1 - f32(math.exp(f64(-slide_age * 70)))) * f32(math.exp(f64(-progress * (3.1 + synth.hardness))))
            landing_scuff =
                (rough - synth.slide_low) *
                slide_judder *
                slide_envelope *
                synth.landing_slide *
                (.45 + synth.hardness * .35 + synth.grit * .20)
        }
        body := synth.body_low * (contact_envelope + landing_envelope * .75)
        grit := (rough - synth.detail_low) * grit_envelope * synth.grit
        wet_envelope := f32(math.exp(f64(-progress * 3.5)))
        water_squelch := synth.water_low * wet_envelope * synth.wetness * (1 - synth.hardness * .52)
        water_slap := (rough - synth.water_detail) * contact_envelope * synth.wetness * (.09 + synth.hardness * .13)
        toe_mix := 1 - synth.landing_mix * .58
        contact :=
            (body * (.62 + synth.landing_mix * .58) +
                grit * .22 +
                grain_tick * .14 * grit_envelope +
                tap * (.42 + synth.landing_mix * .18) +
                toe_tap * .34 * toe_mix +
                toe_scuff * .20 * toe_mix +
                landing_scuff * .26 +
                water_squelch * (.30 + synth.landing_mix * .22) +
                water_slap * (.34 + synth.landing_mix * .18) +
                toe_splash * toe_mix) *
            synth.intensity
        sample += contact
        synth.last_output = contact
        synth.age += seconds_per_sample
    }
}

render_footstep_mixer_add :: proc(mixer: ^Footstep_Mixer, samples: []f32) {
    if mixer == nil do return
    for &voice in mixer.voices {
        render_footstep_add(&voice, samples)
    }
    tail_decay := f32(math.exp(f64(-220.0 / SAMPLE_RATE)))
    for &sample in samples {
        sample += (mixer.stolen_tail_left + mixer.stolen_tail_right) * .5
        mixer.stolen_tail_left *= tail_decay
        mixer.stolen_tail_right *= tail_decay
        if abs(mixer.stolen_tail_left) < .000001 do mixer.stolen_tail_left = 0
        if abs(mixer.stolen_tail_right) < .000001 do mixer.stolen_tail_right = 0
    }
}

render_footstep_mixer_stereo_add :: proc(mixer: ^Footstep_Mixer, stereo: []f32) {
    if mixer == nil do return
    frame_count := len(stereo) / 2
    scratch: [BUFFER_SAMPLES]f32
    for &voice in mixer.voices {
        offset := 0
        for offset < frame_count {
            count := min(BUFFER_SAMPLES, frame_count - offset)
            for index in 0 ..< count do scratch[index] = 0
            render_footstep_add(&voice, scratch[:count])
            for index in 0 ..< count {
                sample := scratch[index]
                stereo[(offset + index) * 2] += sample * (1 - voice.pan)
                stereo[(offset + index) * 2 + 1] += sample * (1 + voice.pan)
            }
            offset += count
        }
    }
    tail_decay := f32(math.exp(f64(-220.0 / SAMPLE_RATE)))
    for frame in 0 ..< frame_count {
        stereo[frame * 2] += mixer.stolen_tail_left
        stereo[frame * 2 + 1] += mixer.stolen_tail_right
        mixer.stolen_tail_left *= tail_decay
        mixer.stolen_tail_right *= tail_decay
        if abs(mixer.stolen_tail_left) < .000001 do mixer.stolen_tail_left = 0
        if abs(mixer.stolen_tail_right) < .000001 do mixer.stolen_tail_right = 0
    }
}
