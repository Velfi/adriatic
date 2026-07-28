package tests

import mouse_gait "../packages/mouse_gait"
import "core:math"
import "core:testing"

@(test)
stance_reach_cancels_body_travel :: proc(t: ^testing.T) {
    duty := f32(.68)
    radians_per_meter := f32(6)
    speed := f32(2.6)
    delta_seconds := f32(.01)
    phase := f32(math.PI * .20)
    phase_delta := speed * delta_seconds * radians_per_meter
    amplitude := mouse_gait.stance_reach_amplitude(duty, radians_per_meter)
    before := mouse_gait.cycle(phase, 0, duty)
    after := mouse_gait.cycle(phase + phase_delta, 0, duty)
    world_paw_delta := speed * delta_seconds + (after.reach - before.reach) * amplitude
    testing.expectf(t, math.abs(world_paw_delta) < .00001, "stance paw slipped by %.6f", world_paw_delta)
}

@(test)
gait_cycle_is_position_continuous_at_contact_boundaries :: proc(t: ^testing.T) {
    duty := f32(.68)
    epsilon := f32(.00001)
    before_liftoff := mouse_gait.cycle((duty - epsilon) * math.PI * 2, 0, duty)
    after_liftoff := mouse_gait.cycle((duty + epsilon) * math.PI * 2, 0, duty)
    before_touchdown := mouse_gait.cycle((1 - epsilon) * math.PI * 2, 0, duty)
    after_touchdown := mouse_gait.cycle(epsilon * math.PI * 2, 0, duty)
    testing.expect(t, math.abs(before_liftoff.reach - after_liftoff.reach) < .001)
    testing.expect(t, math.abs(before_liftoff.lift - after_liftoff.lift) < .001)
    testing.expect(t, math.abs(before_touchdown.reach - after_touchdown.reach) < .001)
    testing.expect(t, math.abs(before_touchdown.lift - after_touchdown.lift) < .001)
}

@(test)
full_bound_synchronizes_homologous_limbs :: proc(t: ^testing.T) {
    testing.expect_value(t, mouse_gait.bound_bilateral_lag(1), f32(0))
    testing.expect(t, mouse_gait.bound_bilateral_lag(.5) > 0)
    testing.expect(t, mouse_gait.bound_bilateral_lag(0) > mouse_gait.bound_bilateral_lag(.5))
}

@(test)
alternating_gaits_restrain_axial_flexion :: proc(t: ^testing.T) {
    walk := mouse_gait.axial_flex_scale({walk = 1})
    trot := mouse_gait.axial_flex_scale({trot = 1})
    bound := mouse_gait.axial_flex_scale({bound = 1})
    testing.expect(t, walk < trot)
    testing.expect(t, trot < bound)
    testing.expect(t, walk <= .07)
}

@(test)
bound_vertical_excursion_exceeds_walk :: proc(t: ^testing.T) {
    walk := mouse_gait.vertical_bob_scale({walk = 1})
    trot := mouse_gait.vertical_bob_scale({trot = 1})
    bound := mouse_gait.vertical_bob_scale({bound = 1})
    testing.expect(t, walk < trot)
    testing.expect(t, trot < bound)
    testing.expect(t, bound >= walk * 2)
}

@(test)
gait_tail_sway_stays_attached_at_the_root :: proc(t: ^testing.T) {
    gait := mouse_gait.Weights {
        walk = 1,
    }
    testing.expect_value(t, mouse_gait.tail_counter_sway(1.2, 0, gait), f32(0))
    testing.expect(t, math.abs(mouse_gait.tail_counter_sway(1.2, 1, gait)) <= .035)
}

@(test)
bound_tail_counter_sway_exceeds_walk :: proc(t: ^testing.T) {
    phase := f32(math.PI * .5 - .9)
    walk := mouse_gait.tail_counter_sway(phase, 1, {walk = 1})
    bound := mouse_gait.tail_counter_sway(phase, 1, {bound = 1})
    testing.expect(t, math.abs(bound) > math.abs(walk))
}

@(test)
procedural_tail_follows_the_pelvis_most_at_its_root :: proc(t: ^testing.T) {
    testing.expect_value(t, mouse_gait.tail_root_follow(0), f32(1))
    testing.expect(t, mouse_gait.tail_root_follow(.5) < 1)
    testing.expect(t, mouse_gait.tail_root_follow(1) > 0)
    testing.expect(t, mouse_gait.tail_root_follow(1) < mouse_gait.tail_root_follow(.5))
}

@(test)
full_bound_has_two_aerial_intervals :: proc(t: ^testing.T) {
    first_flight := mouse_gait.bound_aerial_weight(f32(.42 * math.PI * 2))
    second_flight := mouse_gait.bound_aerial_weight(f32(.93 * math.PI * 2))
    testing.expect(t, first_flight > .9)
    testing.expect(t, second_flight > .9)
    testing.expect_value(t, mouse_gait.bound_aerial_weight(0), f32(0))
    testing.expect_value(t, mouse_gait.bound_aerial_weight(math.PI), f32(0))
}

@(test)
bound_aerial_weight_loops_continuously :: proc(t: ^testing.T) {
    epsilon := f32(.00001)
    before := mouse_gait.bound_aerial_weight(math.PI * 2 - epsilon)
    after := mouse_gait.bound_aerial_weight(epsilon)
    testing.expect(t, math.abs(before - after) < .001)
}

@(test)
eight_frame_bound_samples_land_on_key_phases :: proc(t: ^testing.T) {
    fore_support := mouse_gait.bound_aerial_weight(mouse_gait.bound_animation_phase(0))
    first_flight := mouse_gait.bound_aerial_weight(mouse_gait.bound_animation_phase(f32(3) / 8 * math.PI * 2))
    hind_support := mouse_gait.bound_aerial_weight(mouse_gait.bound_animation_phase(math.PI))
    second_flight := mouse_gait.bound_aerial_weight(mouse_gait.bound_animation_phase(f32(7) / 8 * math.PI * 2))
    testing.expect_value(t, fore_support, f32(0))
    testing.expect(t, first_flight > .9)
    testing.expect_value(t, hind_support, f32(0))
    testing.expect(t, second_flight > .9)
}

@(test)
mouse_gait_weights_have_distinct_speed_regimes :: proc(t: ^testing.T) {
    walk := mouse_gait.weights(3, 4.2, 6.4, 8.4, 10.5)
    trot := mouse_gait.weights(7, 4.2, 6.4, 8.4, 10.5)
    bound := mouse_gait.weights(11, 4.2, 6.4, 8.4, 10.5)
    testing.expect(t, walk.walk == 1 && walk.trot == 0 && walk.bound == 0)
    testing.expect(t, trot.walk == 0 && trot.trot == 1 && trot.bound == 0)
    testing.expect(t, bound.walk == 0 && bound.trot == 0 && bound.bound == 1)
}

@(test)
mouse_gait_weights_remain_normalized_through_transitions :: proc(t: ^testing.T) {
    for index in 0 ..= 120 {
        speed := f32(index) * .1
        gait := mouse_gait.weights(speed, 4.2, 6.4, 8.4, 10.5)
        sum := gait.walk + gait.trot + gait.bound
        testing.expect(t, math.abs(sum - 1) < .0001)
        testing.expect(t, gait.walk >= 0 && gait.trot >= 0 && gait.bound >= 0)
    }
}

@(test)
mouse_forelimb_enters_swing_before_hindlimb_during_walk :: proc(t: ^testing.T) {
    // At 70% of a cycle the shorter-duty forelimb has lifted while the
    // hindlimb remains in stance, preserving three-foot support.
    phase := f32(math.PI * 2 * .70)
    fore := mouse_gait.cycle(phase, 0, .68)
    hind := mouse_gait.cycle(phase, 0, .76)
    testing.expect(t, fore.lift > 0)
    testing.expect(t, hind.lift == 0)
}

@(test)
mouse_walk_uses_a_single_limb_swing_sequence :: proc(t: ^testing.T) {
    gait := mouse_gait.Weights {
        walk = 1,
    }
    // Midway through the right-hind recovery interval, the other three feet
    // remain in stance for the common LF-RH-RF-LH mouse walk sequence.
    phase := f32(math.PI * 2 * .10)
    left_fore := mouse_gait.blend(phase, 0, 0, 0, gait, .68, .56, .34)
    right_fore := mouse_gait.blend(phase, .50, .50, 0, gait, .68, .56, .34)
    left_hind := mouse_gait.blend(phase, .25, .50, 0, gait, .76, .60, .36)
    right_hind := mouse_gait.blend(phase, .75, 0, 0, gait, .76, .60, .36)
    testing.expect(t, right_hind.lift > 0)
    testing.expect(t, left_fore.lift == 0 && right_fore.lift == 0 && left_hind.lift == 0)
}
