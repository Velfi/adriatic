package engine_sound

import "core:math"

MASTER_CEILING :: f32(.96)
MASTER_KNEE :: f32(.68)
DC_BLOCK_POLE :: f32(.9994765) // Approximately 4 Hz at 48 kHz.

Mix_State :: struct {
    previous_input:  f32,
    previous_output: f32,
    limiter_gain:    f32,
}

SOURCE_WIDTH_DELAY_SAMPLES :: 17

Source_Width_State :: struct {
    delay: [SOURCE_WIDTH_DELAY_SAMPLES]f32,
    index: int,
}

limit_sample :: proc(value: f32) -> f32 {
    magnitude := abs(value)
    if magnitude <= MASTER_KNEE do return value
    headroom := MASTER_CEILING - MASTER_KNEE
    limited := MASTER_KNEE + headroom * f32(math.tanh(f64((magnitude - MASTER_KNEE) / headroom)))
    limited = min(limited, MASTER_CEILING - f32(1e-6))
    return value < 0 ? -limited : limited
}

// Additive voices remain exactly linear through the normal operating range.
// Only peaks above the knee bend smoothly toward the ceiling after every
// source has contributed, avoiding order-dependent clipping and preserving
// engine fundamentals and surface detail.
limit_mix :: proc(samples: []f32) {
    for &sample in samples {
        sample = limit_sample(sample)
    }
}

// process_mix removes sub-audible bias from asymmetric firing and contact
// pulses before applying the final limiter. State must persist across callback
// buffers so the high-pass response remains continuous.
process_mix :: proc(state: ^Mix_State, samples: []f32) {
    if state == nil do return
    for &sample in samples {
        blocked := sample - state.previous_input + DC_BLOCK_POLE * state.previous_output
        state.previous_input = sample
        state.previous_output = blocked
        sample = limit_sample(blocked)
    }
}

process_mix_interleaved :: proc(states: []Mix_State, samples: []f32, channels: int) {
    if channels <= 0 || len(states) < channels do return
    frame_count := len(samples) / channels
    for frame in 0 ..< frame_count {
        peak := f32(0)
        for channel in 0 ..< channels {
            index := frame * channels + channel
            state := &states[channel]
            blocked := samples[index] - state.previous_input + DC_BLOCK_POLE * state.previous_output
            state.previous_input = samples[index]
            state.previous_output = blocked
            samples[index] = blocked
            peak = max(peak, abs(blocked))
        }
        desired_gain := f32(1)
        if peak > MASTER_KNEE {
            desired_gain = abs(limit_sample(peak)) / peak
        }
        linked_gain := states[0].limiter_gain
        if linked_gain <= 0 do linked_gain = 1
        if desired_gain < linked_gain {
            // Capture overload immediately so no sample can cross the ceiling.
            linked_gain = desired_gain
        } else {
            // Roughly 18 ms recovery avoids sample-by-sample gain chatter on
            // periodic engines, tire squeal, wind, and surf.
            linked_gain = approach(linked_gain, desired_gain, 55, f32(1.0 / SAMPLE_RATE))
        }
        states[0].limiter_gain = linked_gain
        for channel in 0 ..< channels {
            samples[frame * channels + channel] *= linked_gain
        }
    }
    for index in frame_count * channels ..< len(samples) {
        channel := index - frame_count * channels
        state := &states[channel]
        blocked := samples[index] - state.previous_input + DC_BLOCK_POLE * state.previous_output
        state.previous_input = samples[index]
        state.previous_output = blocked
        samples[index] = limit_sample(blocked)
    }
}

// widen_source_stereo derives a quiet decorrelated side signal from a short
// mechanical reflection. L+R remains exactly twice the mono input, so stereo
// width collapses cleanly without comb filtering or level loss.
widen_source_stereo :: proc(
    state: ^Source_Width_State,
    mono: []f32,
    stereo: []f32,
    width: f32 = .09,
    additive: bool = false,
) {
    if state == nil || len(stereo) < len(mono) * 2 do return
    side_gain := clamp(width, 0, .25)
    for sample, frame in mono {
        delayed := state.delay[state.index]
        state.delay[state.index] = sample
        state.index = (state.index + 1) % SOURCE_WIDTH_DELAY_SAMPLES
        side := (sample - delayed) * side_gain
        left, right := sample + side, sample - side
        if additive {
            stereo[frame * 2] += left
            stereo[frame * 2 + 1] += right
        } else {
            stereo[frame * 2] = left
            stereo[frame * 2 + 1] = right
        }
    }
}
