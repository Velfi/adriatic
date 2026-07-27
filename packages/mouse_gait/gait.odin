package mouse_gait

import "core:math"

Weights :: struct {
    walk:  f32,
    trot:  f32,
    bound: f32,
}

Cycle :: struct {
    reach: f32,
    lift:  f32,
}

// During stance, cycle.reach travels linearly from +1 to -1. This amplitude
// makes that rearward paw travel exactly cancel the body's forward travel:
// 2A = duty_factor * stride_distance, stride_distance = 2pi / radians_per_meter.
stance_reach_amplitude :: proc(duty_factor, radians_per_meter: f32) -> f32 {
    duty := clamp(duty_factor, .05, .95)
    cadence := max(radians_per_meter, f32(.1))
    return duty * math.PI / cadence
}

// Transitional gallop keeps a lead side; a true full bound synchronizes each
// homologous pair. Weighting the lag down to zero avoids a residual limp at
// the high-speed attractor.
bound_bilateral_lag :: proc(bound_weight: f32) -> f32 {
    return .11 * (1 - clamp(bound_weight, 0, 1))
}

axial_flex_scale :: proc(gait: Weights) -> f32 {
    return gait.walk * .07 + gait.trot * .12 + gait.bound
}

vertical_bob_scale :: proc(gait: Weights) -> f32 {
    return gait.walk * .006 + gait.trot * .010 + gait.bound * .014
}

tail_counter_sway :: proc(phase_radians, chain_weight: f32, gait: Weights) -> f32 {
    weight := clamp(chain_weight, 0, 1)
    amplitude := gait.walk * .035 + gait.trot * .050 + gait.bound * .075
    return math.sin(phase_radians + weight * .9) * weight * amplitude
}

smooth_unit :: proc(value: f32) -> f32 {
    amount := clamp(value, 0, 1)
    return amount * amount * (3 - 2 * amount)
}

weights :: proc(
    horizontal_speed: f32,
    walk_full_speed, trot_full_speed, bound_start_speed, bound_full_speed: f32,
    airborne_weight: f32 = 0,
) -> Weights {
    walk_end := max(walk_full_speed, f32(.1))
    trot_end := max(trot_full_speed, walk_end + .1)
    bound_start := max(bound_start_speed, trot_end)
    bound_end := max(bound_full_speed, bound_start + .1)
    walk_to_trot := smooth_unit((horizontal_speed - walk_end) / (trot_end - walk_end))
    bound := max(smooth_unit((horizontal_speed - bound_start) / (bound_end - bound_start)), clamp(airborne_weight, 0, 1))
    return {
        walk  = (1 - walk_to_trot) * (1 - bound),
        trot  = walk_to_trot * (1 - bound),
        bound = bound,
    }
}

cycle :: proc(phase_radians, phase_offset, duty_factor: f32) -> Cycle {
    phase := phase_radians / (math.PI * 2) + phase_offset
    phase -= f32(math.floor(f64(phase)))
    duty := clamp(duty_factor, .05, .95)
    if phase < duty {
        stance := phase / duty
        return {reach = 1 - stance * 2}
    }
    swing := (phase - duty) / (1 - duty)
    smooth_swing := smooth_unit(swing)
    return {reach = -1 + smooth_swing * 2, lift = math.sin(swing * math.PI)}
}

blend :: proc(
    phase_radians: f32,
    walk_offset, trot_offset, bound_offset: f32,
    gait: Weights,
    walk_duty, trot_duty, bound_duty: f32,
) -> Cycle {
    walk := cycle(phase_radians, walk_offset, walk_duty)
    trot := cycle(phase_radians, trot_offset, trot_duty)
    bound := cycle(phase_radians, bound_offset, bound_duty)
    return {
        reach = walk.reach * gait.walk + trot.reach * gait.trot + bound.reach * gait.bound,
        lift  = walk.lift * gait.walk + trot.lift * gait.trot + bound.lift * gait.bound,
    }
}

blend_scaled :: proc(
    phase_radians: f32,
    walk_offset, trot_offset, bound_offset: f32,
    gait: Weights,
    walk_duty, trot_duty, bound_duty: f32,
    walk_radians_per_meter, trot_radians_per_meter, bound_radians_per_meter: f32,
) -> Cycle {
    walk := cycle(phase_radians, walk_offset, walk_duty)
    trot := cycle(phase_radians, trot_offset, trot_duty)
    bound := cycle(phase_radians, bound_offset, bound_duty)
    return {
        reach =
            walk.reach * stance_reach_amplitude(walk_duty, walk_radians_per_meter) * gait.walk +
            trot.reach * stance_reach_amplitude(trot_duty, trot_radians_per_meter) * gait.trot +
            bound.reach * stance_reach_amplitude(bound_duty, bound_radians_per_meter) * gait.bound,
        lift = walk.lift * gait.walk + trot.lift * gait.trot + bound.lift * gait.bound,
    }
}
