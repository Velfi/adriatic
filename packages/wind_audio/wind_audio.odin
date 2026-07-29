package wind_audio

import "core:c"
import "core:math"
import sdl "vendor:sdl3"

SAMPLE_RATE :: 48_000
CHANNELS :: 2
CALLBACK_SAMPLES :: 4096
RAIN_DROP_VOICE_COUNT :: 4

Rain_Drop_Voice :: struct {
    left:      f32,
    right:     f32,
    phase_a:   f32,
    phase_b:   f32,
    frequency: f32,
}

Synth :: struct {
    random_state:          u32,
    strength:              f32,
    target_strength:       f32,
    direction:             f32,
    target_direction:      f32,
    precipitation:         f32,
    target_precipitation:  f32,
    storm_severity:        f32,
    target_storm_severity: f32,
    mute_gain:             f32,
    target_mute_gain:      f32,
    broad_low:             f32,
    body_low:              f32,
    left_air_low:          f32,
    right_air_low:         f32,
    gust_phase:            f32,
    gust_noise_low:        f32,
    gust_value:            f32,
    crosswind_low:         f32,
    whistle_wander_low:    f32,
    whistle_phase_a:       f32,
    whistle_phase_b:       f32,
    whistle_mix:           f32,
    rain_low_left:         f32,
    rain_low_right:        f32,
    splat_low_left:        f32,
    splat_low_right:       f32,
    drop_timer:            f32,
    drop_voices:           [RAIN_DROP_VOICE_COUNT]Rain_Drop_Voice,
    next_drop_voice:       int,
    heavy_drop_timer:      f32,
    heavy_drop_left:       f32,
    heavy_drop_right:      f32,
    drop_count:            u32,
    heavy_drop_count:      u32,
    thunder_timer:         f32,
    thunder_age:           f32,
    thunder_duration:      f32,
    thunder_intensity:     f32,
    thunder_pan:           f32,
    thunder_distance:      f32,
    thunder_low:           f32,
    thunder_mid:           f32,
    thunder_echo_delay_a:  f32,
    thunder_echo_delay_b:  f32,
    thunder_echo_pan_a:    f32,
    thunder_echo_pan_b:    f32,
    storm_thunder_armed:   bool,
}

Runtime :: struct {
    synth:             Synth,
    stream:            ^sdl.AudioStream,
    owns_audio_system: bool,
    manual_feed:       bool,
}

new_synth :: proc(seed: u32 = 0x6d2b79f5) -> Synth {
    return {random_state = seed == 0 ? 0x6d2b79f5 : seed, mute_gain = 1, target_mute_gain = 1}
}

set_strength :: proc(synth: ^Synth, strength: f32) {
    if synth == nil do return
    synth.target_strength = clamp(strength, 0, 1)
}

set_direction :: proc(synth: ^Synth, direction: f32) {
    if synth == nil do return
    synth.target_direction = clamp(direction, -1, 1)
}

set_precipitation :: proc(synth: ^Synth, precipitation: f32) {
    if synth == nil do return
    synth.target_precipitation = clamp(precipitation, 0, 1)
}

set_storm_severity :: proc(synth: ^Synth, severity: f32) {
    if synth == nil do return
    synth.target_storm_severity = clamp(severity, 0, 1)
}

set_muted :: proc(synth: ^Synth, muted: bool) {
    if synth != nil do synth.target_mute_gain = muted ? 0 : 1
}

trigger_thunder :: proc "contextless" (synth: ^Synth, intensity: f32 = 1, distance: f32 = -1) {
    if synth == nil do return
    synth.thunder_age = 0
    synth.thunder_intensity = clamp(intensity, .2, 1)
    if distance >= 0 {
        synth.thunder_distance = clamp(distance, 0, 1)
    } else {
        synth.thunder_distance = (next_noise(synth) + 1) * .5
    }
    synth.thunder_duration = 2.2 + (next_noise(synth) + 1) * .7 + synth.thunder_distance * 1.25
    synth.thunder_pan = next_noise(synth) * .7
    synth.thunder_timer = (5 + (next_noise(synth) + 1) * 4) / (.55 + synth.thunder_intensity * .45)
    synth.thunder_echo_delay_a = .17 + (next_noise(synth) + 1) * .13 + synth.thunder_distance * .34
    synth.thunder_echo_delay_b =
        synth.thunder_echo_delay_a + .36 + (next_noise(synth) + 1) * .22 + synth.thunder_distance * .48
    synth.thunder_echo_pan_a = next_noise(synth) * .85
    synth.thunder_echo_pan_b = next_noise(synth) * .85
    synth.thunder_low = 0
    synth.thunder_mid = 0
}

airflow_strength :: proc(weather_speed, motion_speed: f32) -> f32 {
    weather := clamp((weather_speed - .5) / 12, 0, 1)
    motion := clamp((motion_speed - 2) / 40, 0, 1)
    // Independent contributions combine without exceeding unity.
    return 1 - (1 - weather) * (1 - motion)
}

wind_lateral_direction :: proc(wind_x, wind_z, listener_yaw: f32) -> f32 {
    speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
    if speed < .001 do return 0
    right_x := f32(math.cos(f64(listener_yaw)))
    right_z := -f32(math.sin(f64(listener_yaw)))
    return clamp((wind_x * right_x + wind_z * right_z) / speed, -1, 1)
}

apparent_lateral_direction :: proc(
    wind_x, wind_z, listener_velocity_x, listener_velocity_z, listener_yaw: f32,
) -> f32 {
    // Airflow relative to a moving listener is the world wind minus listener
    // velocity. This keeps calm high-speed travel spatial rather than centered.
    return wind_lateral_direction(wind_x - listener_velocity_x, wind_z - listener_velocity_z, listener_yaw)
}

apparent_airflow_speed :: proc(wind_x, wind_z, listener_velocity_x, listener_velocity_z: f32) -> f32 {
    relative_x := wind_x - listener_velocity_x
    relative_z := wind_z - listener_velocity_z
    return f32(math.sqrt(f64(relative_x * relative_x + relative_z * relative_z)))
}

next_noise :: proc "contextless" (synth: ^Synth) -> f32 {
    x := synth.random_state
    x = x ~ (x << 13)
    x = x ~ (x >> 17)
    x = x ~ (x << 5)
    synth.random_state = x
    return f32(x & 0x00ffffff) / f32(0x007fffff) - 1
}

coefficient_for_sample_rate :: proc "contextless" (reference_coefficient, sample_rate: f32) -> f32 {
    if sample_rate <= 0 do return 0
    coefficient := clamp(reference_coefficient, 0, 1)
    return f32(1 - math.pow(f64(1 - coefficient), f64(SAMPLE_RATE) / f64(sample_rate)))
}

render :: proc "contextless" (synth: ^Synth, output: []f32, sample_rate: f32 = SAMPLE_RATE) {
    frame_count := len(output) / CHANNELS
    if synth == nil || frame_count <= 0 || sample_rate <= 0 do return

    smoothing := f32(1 - math.exp(f64(-12 / sample_rate)))
    mute_smoothing := f32(1 - math.exp(f64(-18 / sample_rate)))
    direction_smoothing := f32(1 - math.exp(f64(-2.4 / sample_rate)))
    body_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 92 / sample_rate)))
    gust_cutoff := f32(1 - math.exp(f64(-2 * math.PI * .31 / sample_rate)))
    crosswind_cutoff := f32(1 - math.exp(f64(-2 * math.PI * .17 / sample_rate)))
    whistle_wander_cutoff := f32(1 - math.exp(f64(-2 * math.PI * .63 / sample_rate)))
    whistle_smoothing := f32(1 - math.exp(f64(-3.2 / sample_rate)))
    rain_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 1900 / sample_rate)))
    splat_cutoff := f32(1 - math.exp(f64(-2 * math.PI * 520 / sample_rate)))
    drop_decay := f32(math.exp(f64(-145 / sample_rate)))
    heavy_drop_decay := f32(math.exp(f64(-58 / sample_rate)))
    thunder_low_cutoff := coefficient_for_sample_rate(.0025, sample_rate)
    thunder_mid_cutoff := coefficient_for_sample_rate(.028, sample_rate)
    phase_step := f32(2 * math.PI * .11 / sample_rate)
    broad_calm := coefficient_for_sample_rate(.047, sample_rate)
    broad_strong := coefficient_for_sample_rate(.105, sample_rate)
    air_calm := coefficient_for_sample_rate(.34, sample_rate)
    air_strong := coefficient_for_sample_rate(.20, sample_rate)

    for frame in 0 ..< frame_count {
        synth.strength += (synth.target_strength - synth.strength) * smoothing
        synth.direction += (synth.target_direction - synth.direction) * direction_smoothing
        synth.precipitation += (synth.target_precipitation - synth.precipitation) * smoothing
        synth.storm_severity += (synth.target_storm_severity - synth.storm_severity) * smoothing
        synth.mute_gain += (synth.target_mute_gain - synth.mute_gain) * mute_smoothing
        noise := next_noise(synth)
        stereo_noise := next_noise(synth)
        modulation_noise := next_noise(synth)
        synth.gust_noise_low += (modulation_noise - synth.gust_noise_low) * gust_cutoff
        synth.crosswind_low += (stereo_noise - synth.crosswind_low) * crosswind_cutoff
        synth.whistle_wander_low += (noise - synth.whistle_wander_low) * whistle_wander_cutoff
        synth.rain_low_left += (noise - synth.rain_low_left) * rain_cutoff
        synth.rain_low_right += (stereo_noise - synth.rain_low_right) * rain_cutoff
        synth.splat_low_left += (noise - synth.splat_low_left) * splat_cutoff
        synth.splat_low_right += (stereo_noise - synth.splat_low_right) * splat_cutoff

        // Faster wind shifts the broadband body upward and exposes more air.
        // Interpolating stable one-pole coefficients avoids recalculating
        // exponentials for every sample.
        broad_cutoff := broad_calm + (broad_strong - broad_calm) * synth.strength
        air_cutoff := air_calm + (air_strong - air_calm) * synth.strength
        synth.broad_low += (noise - synth.broad_low) * broad_cutoff
        synth.body_low += (synth.broad_low - synth.body_low) * body_cutoff
        synth.left_air_low += (noise - synth.left_air_low) * air_cutoff
        synth.right_air_low += (stereo_noise - synth.right_air_low) * air_cutoff

        periodic_gust :=
            .72 + .16 * f32(math.sin(f64(synth.gust_phase))) + .07 * f32(math.sin(f64(synth.gust_phase * 2.37 + 1.4)))
        gust := clamp(periodic_gust + synth.gust_noise_low * 42, .38, 1.14)
        synth.gust_value = gust
        synth.gust_phase += phase_step
        if synth.gust_phase >= 2 * math.PI do synth.gust_phase -= 2 * math.PI

        body := synth.broad_low - synth.body_low
        left_air := noise - synth.left_air_low
        right_air := stereo_noise - synth.right_air_low
        turbulent_crosswind := clamp(synth.crosswind_low * 46, -.13, .13)
        directional_crosswind := synth.direction * synth.strength * .18
        crosswind := clamp(turbulent_crosswind + directional_crosswind, -.29, .29)
        gain := synth.strength * synth.strength * gust
        gust_brightness := clamp((gust - .52) / .62, 0, 1)
        body_gain := .67 - gust_brightness * .10
        air_gain := .115 + gust_brightness * .105

        // At high airflow, gaps and rigging shed narrow aeolian modes above
        // the broadband rush. Gusts breathe the resonances in and out while
        // slow seeded wander prevents a fixed electronic whistle.
        whistle_target := clamp((synth.strength - .62) / .38, 0, 1) * clamp((gust - .52) / .48, 0, 1)
        synth.whistle_mix += (whistle_target - synth.whistle_mix) * whistle_smoothing
        whistle_hz := 470 + synth.strength * 560 + synth.whistle_wander_low * 115
        synth.whistle_phase_a += whistle_hz / sample_rate
        synth.whistle_phase_b += whistle_hz * 1.417 / sample_rate
        synth.whistle_phase_a -= math.floor(synth.whistle_phase_a)
        synth.whistle_phase_b -= math.floor(synth.whistle_phase_b)
        whistle :=
            (f32(math.sin(f64(synth.whistle_phase_a * 2 * math.PI))) * .72 +
                f32(math.sin(f64(synth.whistle_phase_b * 2 * math.PI))) * .28) *
            synth.whistle_mix *
            (.010 + synth.strength * .012)
        whistle_pan := clamp(synth.direction * .24 + turbulent_crosswind * .72, -.38, .38)
        if synth.precipitation > .001 {
            synth.drop_timer -= 1 / sample_rate
            if synth.drop_timer <= 0 {
                wind_drive := .86 + synth.strength * .34
                drop_strength := (.55 + (next_noise(synth) + 1) * .35) * wind_drive
                pan := clamp(next_noise(synth) * .78 + synth.direction * .34, -1, 1)
                // A raindrop excites a tiny surface mode rather than
                // producing a one-sided DC pulse. The seeded pitch range
                // suggests varied nearby materials without turning rainfall
                // into a fixed pitched texture. Independent voices allow
                // adjacent arrivals to decay naturally through dense rain.
                pitch_variation := (next_noise(synth) + 1) * .5
                voice := &synth.drop_voices[synth.next_drop_voice]
                voice^ = {
                    left      = drop_strength * (1 - pan) * .5,
                    right     = drop_strength * (1 + pan) * .5,
                    frequency = 780 + pitch_variation * 1_720,
                }
                synth.next_drop_voice = (synth.next_drop_voice + 1) % RAIN_DROP_VOICE_COUNT
                drop_rate := (4 + synth.precipitation * 52) * (.82 + synth.strength * .56)
                interval_variation := .48 + (next_noise(synth) + 1) * .44
                synth.drop_timer = interval_variation / drop_rate
                synth.drop_count += 1
            }
            if synth.precipitation > .55 {
                synth.heavy_drop_timer -= 1 / sample_rate
                if synth.heavy_drop_timer <= 0 {
                    drop_strength := (.45 + (next_noise(synth) + 1) * .34) * (.88 + synth.strength * .32)
                    pan := clamp(next_noise(synth) * .72 + synth.direction * .42, -1, 1)
                    heavy_mix := clamp((synth.precipitation - .55) / .45, 0, 1)
                    synth.heavy_drop_left += drop_strength * (1 - pan) * .5 * heavy_mix
                    synth.heavy_drop_right += drop_strength * (1 + pan) * .5 * heavy_mix
                    heavy_rate := (2.5 + heavy_mix * 8.5) * (.84 + synth.strength * .50)
                    interval_variation := .42 + (next_noise(synth) + 1) * .58
                    synth.heavy_drop_timer = interval_variation / heavy_rate
                    synth.heavy_drop_count += 1
                }
            }
        }
        synth.heavy_drop_left *= heavy_drop_decay
        synth.heavy_drop_right *= heavy_drop_decay
        drop_resonance_left, drop_resonance_right := f32(0), f32(0)
        for &voice in synth.drop_voices {
            voice.left *= drop_decay
            voice.right *= drop_decay
            if abs(voice.left) + abs(voice.right) < .000001 do continue
            voice.phase_a += voice.frequency / sample_rate
            voice.phase_b += voice.frequency * 1.613 / sample_rate
            voice.phase_a -= math.floor(voice.phase_a)
            voice.phase_b -= math.floor(voice.phase_b)
            resonance :=
                f32(math.sin(f64(voice.phase_a * 2 * math.PI))) * .76 +
                f32(math.sin(f64(voice.phase_b * 2 * math.PI))) * .24
            drop_resonance_left += resonance * voice.left
            drop_resonance_right += resonance * voice.right
        }
        rain_gain := synth.precipitation * synth.precipitation
        heavy_splat_left := (noise - synth.splat_low_left) * synth.heavy_drop_left
        heavy_splat_right := (stereo_noise - synth.splat_low_right) * synth.heavy_drop_right
        driven_streak_left := (noise - synth.rain_low_left) * synth.strength * (.025 + abs(synth.direction) * .018)
        driven_streak_right :=
            (stereo_noise - synth.rain_low_right) * synth.strength * (.025 + abs(synth.direction) * .018)
        rain_left :=
            ((noise - synth.rain_low_left) * .13 +
                driven_streak_left +
                drop_resonance_left * .16 +
                heavy_splat_left * .20) *
            rain_gain
        rain_right :=
            ((stereo_noise - synth.rain_low_right) * .13 +
                driven_streak_right +
                drop_resonance_right * .16 +
                heavy_splat_right * .20) *
            rain_gain
        rain_crosswind := synth.direction * synth.precipitation * .17
        rain_left *= 1 - rain_crosswind
        rain_right *= 1 + rain_crosswind

        storm_active := synth.storm_severity > .55
        if storm_active && !synth.storm_thunder_armed {
            // A storm front should not produce thunder on the exact frame it
            // crosses the threshold. Seeded arming delay makes the first cell
            // feel spatially remote rather than like an immediate UI cue.
            synth.thunder_timer = 2.5 + (next_noise(synth) + 1) * 1.75
            synth.storm_thunder_armed = true
        } else if !storm_active && synth.storm_thunder_armed {
            synth.storm_thunder_armed = false
            if synth.thunder_duration <= 0 do synth.thunder_timer = 0
        }
        if synth.storm_thunder_armed && synth.thunder_duration <= 0 {
            synth.thunder_timer -= synth.storm_severity / sample_rate
            if synth.thunder_timer <= 0 {
                trigger_thunder(synth, synth.storm_severity)
            }
        }
        thunder := f32(0)
        thunder_pan := synth.thunder_pan
        if synth.thunder_duration > 0 {
            thunder_progress := synth.thunder_age / synth.thunder_duration
            synth.thunder_low += (modulation_noise - synth.thunder_low) * thunder_low_cutoff
            synth.thunder_mid += (modulation_noise - synth.thunder_mid) * thunder_mid_cutoff
            attack_rate := 18 - synth.thunder_distance * 12
            attack := 1 - f32(math.exp(f64(-synth.thunder_age * attack_rate)))
            primary_rumble := attack * f32(math.exp(f64(-thunder_progress * 3.1)))
            crack_envelope := f32(math.exp(f64(-synth.thunder_age * 24)))

            // Two delayed reflections build a rolling thunder tail. Each has
            // its own seeded arrival time and pan, so the apparent source
            // spreads across the sky after the direct crack.
            echo_a_envelope, echo_b_envelope := f32(0), f32(0)
            echo_a_crack, echo_b_crack := f32(0), f32(0)
            if synth.thunder_age >= synth.thunder_echo_delay_a {
                echo_age := synth.thunder_age - synth.thunder_echo_delay_a
                echo_a_envelope = (1 - f32(math.exp(f64(-echo_age * 14)))) * f32(math.exp(f64(-echo_age * 1.65)))
                echo_a_crack = f32(math.exp(f64(-echo_age * 29)))
            }
            if synth.thunder_age >= synth.thunder_echo_delay_b {
                echo_age := synth.thunder_age - synth.thunder_echo_delay_b
                echo_b_envelope = (1 - f32(math.exp(f64(-echo_age * 10)))) * f32(math.exp(f64(-echo_age * 1.18)))
                echo_b_crack = f32(math.exp(f64(-echo_age * 24)))
            }
            rumble_envelope := primary_rumble + echo_a_envelope * .48 + echo_b_envelope * .34
            branched_crack := crack_envelope + echo_a_crack * .15 + echo_b_crack * .09
            low_body :=
                synth.thunder_low * (1.7 + synth.thunder_distance * .48) +
                (synth.thunder_mid - synth.thunder_low) * (.62 - synth.thunder_distance * .27)
            crack_gain := .42 * (1 - synth.thunder_distance * .78)
            distance_gain := 1 - synth.thunder_distance * .34
            thunder =
                (low_body * rumble_envelope + (modulation_noise - synth.thunder_mid) * branched_crack * crack_gain) *
                synth.thunder_intensity *
                distance_gain *
                clamp(synth.storm_severity / .55, 0, 1)
            reflection_weight := echo_a_envelope + echo_b_envelope
            if reflection_weight > .0001 {
                reflected_pan :=
                    (synth.thunder_echo_pan_a * echo_a_envelope + synth.thunder_echo_pan_b * echo_b_envelope) /
                    reflection_weight
                thunder_pan = clamp(
                    (synth.thunder_pan * primary_rumble + reflected_pan * reflection_weight) /
                    max(primary_rumble + reflection_weight, f32(.0001)),
                    -.9,
                    .9,
                )
            }
            synth.thunder_age += 1 / sample_rate
            if synth.thunder_age >= synth.thunder_duration {
                synth.thunder_duration = 0
            }
        }
        thunder_spread := .28 * (1 - synth.thunder_distance * .24)
        thunder_left := thunder * (1 - thunder_pan * thunder_spread)
        thunder_right := thunder * (1 + thunder_pan * thunder_spread)
        output[frame * 2] =
            clamp(
                (body * body_gain * (1 - crosswind) + left_air * air_gain) * gain +
                whistle * (1 - whistle_pan) +
                rain_left +
                thunder_left,
                -.9,
                .9,
            ) *
            synth.mute_gain
        output[frame * 2 + 1] =
            clamp(
                (body * body_gain * (1 + crosswind) + right_air * air_gain) * gain +
                whistle * (1 + whistle_pan) +
                rain_right +
                thunder_right,
                -.9,
                .9,
            ) *
            synth.mute_gain
    }
}

audio_callback :: proc "c" (userdata: rawptr, stream: ^sdl.AudioStream, additional_amount, total_amount: c.int) {
    runtime := cast(^Runtime)userdata
    remaining := int(additional_amount) / size_of(f32)
    samples: [CALLBACK_SAMPLES]f32
    for remaining > 0 {
        count := min(remaining, CALLBACK_SAMPLES)
        count -= count % CHANNELS
        if count == 0 do break
        render(&runtime.synth, samples[:count])
        if !sdl.PutAudioStreamData(stream, raw_data(samples[:count]), c.int(count * size_of(f32))) do break
        remaining -= count
    }
}

init :: proc(runtime: ^Runtime, playback_device: sdl.AudioDeviceID = 0) -> bool {
    runtime.synth = new_synth()
    already_initialized := sdl.WasInit(sdl.INIT_AUDIO) != {}
    if !already_initialized {
        if !sdl.InitSubSystem(sdl.INIT_AUDIO) do return false
        runtime.owns_audio_system = true
    }
    spec := sdl.AudioSpec {
        format   = .F32,
        channels = CHANNELS,
        freq     = SAMPLE_RATE,
    }
    if playback_device != 0 {
        runtime.stream = sdl.CreateAudioStream(&spec, nil)
        if runtime.stream != nil && !sdl.BindAudioStream(playback_device, runtime.stream) {
            sdl.DestroyAudioStream(runtime.stream)
            runtime.stream = nil
        }
        runtime.manual_feed = runtime.stream != nil
    } else {
        runtime.stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_callback, runtime)
    }
    if runtime.stream == nil {
        if runtime.owns_audio_system {
            sdl.QuitSubSystem(sdl.INIT_AUDIO)
            runtime.owns_audio_system = false
        }
        return false
    }
    if playback_device == 0 && !sdl.ResumeAudioStreamDevice(runtime.stream) {
        sdl.DestroyAudioStream(runtime.stream)
        runtime.stream = nil
        if runtime.owns_audio_system {
            sdl.QuitSubSystem(sdl.INIT_AUDIO)
            runtime.owns_audio_system = false
        }
        return false
    }
    return true
}

update :: proc(
    runtime: ^Runtime,
    weather_speed: f32,
    motion_speed: f32 = 0,
    precipitation: f32 = 0,
    storm_severity: f32 = 0,
    direction: f32 = 0,
    muted: bool = false,
) {
    if runtime == nil do return
    strength := airflow_strength(weather_speed, motion_speed)
    rain := clamp(precipitation, 0, 1)
    storm := clamp(storm_severity, 0, 1)
    if runtime.stream == nil {
        set_strength(&runtime.synth, strength)
        set_direction(&runtime.synth, direction)
        set_precipitation(&runtime.synth, rain)
        set_storm_severity(&runtime.synth, storm)
        set_muted(&runtime.synth, muted)
    } else if sdl.LockAudioStream(runtime.stream) {
        set_strength(&runtime.synth, strength)
        set_direction(&runtime.synth, direction)
        set_precipitation(&runtime.synth, rain)
        set_storm_severity(&runtime.synth, storm)
        set_muted(&runtime.synth, muted)
        sdl.UnlockAudioStream(runtime.stream)
    }
    if runtime.manual_feed {
        queued_samples := int(sdl.GetAudioStreamQueued(runtime.stream)) / size_of(f32)
        target_samples := SAMPLE_RATE / 10 * CHANNELS
        samples: [CALLBACK_SAMPLES]f32
        for queued_samples < target_samples {
            count := min(target_samples - queued_samples, CALLBACK_SAMPLES)
            count -= count % CHANNELS
            if count == 0 do break
            render(&runtime.synth, samples[:count])
            if !sdl.PutAudioStreamData(runtime.stream, raw_data(samples[:count]), c.int(count * size_of(f32))) {
                break
            }
            queued_samples += count
        }
    }
}

destroy :: proc(runtime: ^Runtime) {
    if runtime.stream != nil {
        sdl.DestroyAudioStream(runtime.stream)
        runtime.stream = nil
    }
    if runtime.owns_audio_system {
        sdl.QuitSubSystem(sdl.INIT_AUDIO)
        runtime.owns_audio_system = false
    }
}
