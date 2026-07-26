package engine_sound

import "core:math"

MASTER_CEILING :: f32(.96)
MASTER_KNEE :: f32(.68)
DC_BLOCK_POLE :: f32(.9994765) // Approximately 4 Hz at 48 kHz.

Mix_State :: struct {
    previous_input:  f32,
    previous_output: f32,
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
