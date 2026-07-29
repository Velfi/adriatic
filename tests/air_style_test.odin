package tests

import air_style "../packages/air_style"
import flight "../packages/flight"
import "core:math"
import "core:math/linalg"
import "core:testing"

AIR_STYLE_TEST_DT :: f32(1.0 / 120.0)

Air_Style_Synthetic_State :: struct {
    body: flight.Body_State,
    pace: f32,
}

air_style_synthetic_state :: proc(altitude: f32 = 200, pace: f32 = 40) -> Air_Style_Synthetic_State {
    return {
        body = {position = {0, altitude, 0}, velocity = {0, 0, -pace}, orientation = flight.identity_orientation()},
        pace = pace,
    }
}

air_style_sign :: proc(value: f32) -> f32 {
    if value < 0 do return -1
    if value > 0 do return 1
    return 0
}

air_style_append_motion :: proc(
    samples: ^[dynamic]air_style.Motion_Sample,
    state: ^Air_Style_Synthetic_State,
    local_rate: flight.Vec3,
    steps: int,
) {
    for _ in 0 ..< steps {
        previous := state.body
        previous_basis := flight.basis_from_orientation(previous.orientation)
        world_rate := flight.local_to_world(previous_basis, local_rate)
        state.body.orientation = flight.integrate_orientation(state.body.orientation, world_rate, AIR_STYLE_TEST_DT)
        basis := flight.basis_from_orientation(state.body.orientation)
        state.body.angular_velocity_world = flight.local_to_world(basis, local_rate)
        state.body.velocity = basis.forward * state.pace
        state.body.position += state.body.velocity * AIR_STYLE_TEST_DT
        append(
            samples,
            air_style.Motion_Sample {
                previous_body = previous,
                body = state.body,
                pace = state.pace,
                intent = {
                    pitch = air_style_sign(local_rate.x),
                    yaw = air_style_sign(local_rate.y),
                    roll = air_style_sign(local_rate.z),
                    throttle = 1,
                },
                ground_clearance = max(state.body.position.y, f32(0)),
                recovery_margin = 1,
                delta_seconds = AIR_STYLE_TEST_DT,
            },
        )
    }
}

air_style_append_falling_hold :: proc(
    samples: ^[dynamic]air_style.Motion_Sample,
    state: ^Air_Style_Synthetic_State,
    steps: int,
) {
    for _ in 0 ..< steps {
        previous := state.body
        basis := flight.basis_from_orientation(state.body.orientation)
        state.body.angular_velocity_world = {}
        state.body.velocity = basis.forward * state.pace + flight.Vec3{0, -12, 0}
        state.body.position += state.body.velocity * AIR_STYLE_TEST_DT
        append(
            samples,
            air_style.Motion_Sample {
                previous_body = previous,
                body = state.body,
                pace = linalg.length(state.body.velocity),
                intent = {yaw = 1, throttle = 1},
                ground_clearance = max(state.body.position.y, f32(0)),
                recovery_margin = 1,
                delta_seconds = AIR_STYLE_TEST_DT,
            },
        )
    }
}

air_style_set_pose :: proc(state: ^Air_Style_Synthetic_State, orientation: quaternion128) {
    state.body.orientation = orientation
    state.body.angular_velocity_world = {}
    state.body.velocity = flight.basis_from_orientation(orientation).forward * state.pace
}

air_style_target_rate :: proc(radians: f32, steps: int) -> f32 {
    return radians / (f32(steps) * AIR_STYLE_TEST_DT)
}

air_style_run_stream :: proc(
    samples: []air_style.Motion_Sample,
    definitions: air_style.Definitions,
) -> (
    recognizer: air_style.Recognizer,
    events: [dynamic]air_style.Maneuver_Event,
) {
    for sample in samples {
        buffer := air_style.recognize_step(&recognizer, definitions, sample)
        for index in 0 ..< buffer.count {
            append(&events, buffer.events[index])
        }
    }
    return
}

air_style_event_count :: proc(
    events: []air_style.Maneuver_Event,
    kind: air_style.Maneuver_Kind,
    lifecycle: air_style.Lifecycle,
) -> int {
    result := 0
    for event in events {
        if event.kind == kind && event.lifecycle == lifecycle do result += 1
    }
    return result
}

air_style_find_event :: proc(
    events: []air_style.Maneuver_Event,
    kind: air_style.Maneuver_Kind,
    lifecycle: air_style.Lifecycle,
) -> (
    air_style.Maneuver_Event,
    bool,
) {
    for event in events {
        if event.kind == kind && event.lifecycle == lifecycle do return event, true
    }
    return {}, false
}

air_style_has_failure :: proc(events: []air_style.Maneuver_Event, failure: air_style.Failure_Reason) -> bool {
    for event in events {
        if event.lifecycle == .Failed && event.failure_reason == failure do return true
    }
    return false
}

air_style_reason_count :: proc(events: []air_style.Maneuver_Event, reason: air_style.Transition_Reason) -> int {
    result := 0
    for event in events {
        if event.transition_reason == reason do result += 1
    }
    return result
}

air_style_expect_near :: proc(t: ^testing.T, actual, expected: f32, tolerance: f32 = 1e-4) {
    testing.expect(t, math.abs(actual - expected) <= tolerance)
}

air_style_expect_composite_lifecycle :: proc(
    t: ^testing.T,
    events: []air_style.Maneuver_Event,
    base_kind, composite_kind: air_style.Maneuver_Kind,
    promotion_reason: air_style.Transition_Reason,
) {
    expected_kinds := [?]air_style.Maneuver_Kind{base_kind, base_kind, composite_kind, composite_kind, composite_kind}
    expected_lifecycles := [?]air_style.Lifecycle{.Primed, .Committed, .Committed, .Recovering, .Completed}
    expected_reasons := [?]air_style.Transition_Reason {
        .Motion_Primed,
        .Motion_Committed,
        promotion_reason,
        .Rotation_Reached,
        .Controlled_Exit,
    }
    testing.expect(t, len(events) == len(expected_lifecycles))
    if len(events) != len(expected_lifecycles) do return

    gesture_id := events[0].gesture_id
    testing.expect(t, gesture_id != 0)
    for event, index in events {
        testing.expect(t, event.gesture_id == gesture_id)
        testing.expect(t, event.kind == expected_kinds[index])
        testing.expect(t, event.lifecycle == expected_lifecycles[index])
        testing.expect(t, event.transition_reason == expected_reasons[index])
    }
    testing.expect(t, air_style_reason_count(events, promotion_reason) == 1)
}

air_style_append_controlled_exit :: proc(
    samples: ^[dynamic]air_style.Motion_Sample,
    state: ^Air_Style_Synthetic_State,
    orientation: quaternion128,
    definitions: air_style.Definitions,
) {
    air_style_set_pose(state, orientation)
    exit_steps := int(definitions.exit_hold_seconds / AIR_STYLE_TEST_DT) + 4
    air_style_append_motion(samples, state, {}, exit_steps)
}

@(test)
air_style_full_positive_and_negative_roll_complete_once :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    directions := [?]f32{-1, 1}
    for direction in directions {
        state := air_style_synthetic_state()
        samples: [dynamic]air_style.Motion_Sample
        defer delete(samples)
        roll_steps := 126
        roll_radians := direction * f32(math.PI * 2.1)
        air_style_append_motion(&samples, &state, {0, 0, air_style_target_rate(roll_radians, roll_steps)}, roll_steps)
        air_style_append_controlled_exit(&samples, &state, flight.identity_orientation(), definitions)

        recognizer, events := air_style_run_stream(samples[:], definitions)
        defer delete(events)
        testing.expect(t, !recognizer.candidate.active)
        testing.expect(t, air_style_event_count(events[:], .Aileron_Roll, .Completed) == 1)
        testing.expect(t, air_style_event_count(events[:], .Loop, .Completed) == 0)
        completion, found := air_style_find_event(events[:], .Aileron_Roll, .Completed)
        testing.expect(t, found)
        testing.expect(t, air_style_sign(completion.signed_local_rotation.z) == direction)
        testing.expect(t, math.abs(completion.signed_local_rotation.z) > definitions.full_rotation)
    }
}

@(test)
air_style_partial_and_corrected_rolls_do_not_complete :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()

    partial_state := air_style_synthetic_state()
    partial_samples: [dynamic]air_style.Motion_Sample
    defer delete(partial_samples)
    partial_steps := 45
    air_style_append_motion(
        &partial_samples,
        &partial_state,
        {0, 0, air_style_target_rate(f32(math.PI * .75), partial_steps)},
        partial_steps,
    )
    timeout_steps := int(definitions.candidate_timeout_seconds / AIR_STYLE_TEST_DT) + 4
    air_style_append_motion(&partial_samples, &partial_state, {}, timeout_steps)
    _, partial_events := air_style_run_stream(partial_samples[:], definitions)
    defer delete(partial_events)
    testing.expect(t, air_style_event_count(partial_events[:], .Aileron_Roll, .Completed) == 0)
    testing.expect(t, air_style_has_failure(partial_events[:], .Timeout))

    corrected_state := air_style_synthetic_state()
    corrected_samples: [dynamic]air_style.Motion_Sample
    defer delete(corrected_samples)
    correction_steps := 60
    correction_rate := air_style_target_rate(f32(math.PI), correction_steps)
    air_style_append_motion(&corrected_samples, &corrected_state, {0, 0, correction_rate}, correction_steps)
    air_style_append_motion(&corrected_samples, &corrected_state, {0, 0, -correction_rate}, correction_steps)
    air_style_append_motion(&corrected_samples, &corrected_state, {}, timeout_steps)
    _, corrected_events := air_style_run_stream(corrected_samples[:], definitions)
    defer delete(corrected_events)
    testing.expect(t, air_style_event_count(corrected_events[:], .Aileron_Roll, .Completed) == 0)
    testing.expect(t, air_style_has_failure(corrected_events[:], .Timeout))
}

@(test)
air_style_loop_completes_once_and_never_as_roll :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    state := air_style_synthetic_state(altitude = 250)
    samples: [dynamic]air_style.Motion_Sample
    defer delete(samples)
    pitch_steps := 126
    pitch_radians := f32(math.PI * 2.1)
    air_style_append_motion(&samples, &state, {air_style_target_rate(pitch_radians, pitch_steps), 0, 0}, pitch_steps)
    air_style_append_controlled_exit(&samples, &state, flight.identity_orientation(), definitions)

    _, events := air_style_run_stream(samples[:], definitions)
    defer delete(events)
    testing.expect(t, air_style_event_count(events[:], .Loop, .Completed) == 1)
    testing.expect(t, air_style_event_count(events[:], .Aileron_Roll, .Completed) == 0)
}

@(test)
air_style_knife_edge_requires_controlled_track_and_height :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    knife_orientation := flight.orientation_from_forward_and_up({0, 0, -1}, {1, 0, 0})
    hold_steps := int(definitions.knife_minimum_hold_seconds / AIR_STYLE_TEST_DT) + 4

    controlled_state := air_style_synthetic_state()
    air_style_set_pose(&controlled_state, knife_orientation)
    controlled_samples: [dynamic]air_style.Motion_Sample
    defer delete(controlled_samples)
    air_style_append_motion(&controlled_samples, &controlled_state, {}, hold_steps)
    air_style_append_controlled_exit(
        &controlled_samples,
        &controlled_state,
        flight.identity_orientation(),
        definitions,
    )
    _, controlled_events := air_style_run_stream(controlled_samples[:], definitions)
    defer delete(controlled_events)
    testing.expect(t, air_style_event_count(controlled_events[:], .Knife_Edge, .Completed) == 1)

    falling_state := air_style_synthetic_state()
    air_style_set_pose(&falling_state, knife_orientation)
    falling_samples: [dynamic]air_style.Motion_Sample
    defer delete(falling_samples)
    air_style_append_falling_hold(&falling_samples, &falling_state, 180)
    _, falling_events := air_style_run_stream(falling_samples[:], definitions)
    defer delete(falling_events)
    testing.expect(t, air_style_event_count(falling_events[:], .Knife_Edge, .Completed) == 0)
    testing.expect(t, air_style_has_failure(falling_events[:], .Uncontrolled_Exit))
}

air_style_build_immelmann :: proc(
    ordered, include_roll: bool,
    definitions: air_style.Definitions,
) -> [dynamic]air_style.Motion_Sample {
    state := air_style_synthetic_state(altitude = 250)
    samples: [dynamic]air_style.Motion_Sample
    half_steps := 63
    half_rate := air_style_target_rate(f32(math.PI * 1.05), half_steps)
    if !ordered {
        air_style_append_motion(&samples, &state, {0, 0, half_rate}, half_steps)
        air_style_append_motion(&samples, &state, {-half_rate, 0, 0}, half_steps)
    } else {
        air_style_append_motion(&samples, &state, {half_rate, 0, 0}, half_steps)
        if include_roll {
            air_style_append_motion(&samples, &state, {0, 0, half_rate}, half_steps)
        }
    }
    if ordered && include_roll {
        opposite := flight.orientation_from_forward_and_up({0, 0, 1}, {0, 1, 0})
        air_style_append_controlled_exit(&samples, &state, opposite, definitions)
    } else {
        timeout_steps := int(definitions.candidate_timeout_seconds / AIR_STYLE_TEST_DT) + 4
        air_style_append_motion(&samples, &state, {}, timeout_steps)
    }
    return samples
}

@(test)
air_style_immelmann_requires_ordered_half_loop_apex_and_roll :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    ordered := air_style_build_immelmann(true, true, definitions)
    defer delete(ordered)
    _, ordered_events := air_style_run_stream(ordered[:], definitions)
    defer delete(ordered_events)
    testing.expect(t, air_style_event_count(ordered_events[:], .Immelmann, .Completed) == 1)
    testing.expect(t, air_style_event_count(ordered_events[:], .Loop, .Completed) == 0)
    testing.expect(t, air_style_event_count(ordered_events[:], .Aileron_Roll, .Completed) == 0)
    air_style_expect_composite_lifecycle(t, ordered_events[:], .Loop, .Immelmann, .Promoted_To_Immelmann)

    reversed := air_style_build_immelmann(false, true, definitions)
    defer delete(reversed)
    _, reversed_events := air_style_run_stream(reversed[:], definitions)
    defer delete(reversed_events)
    testing.expect(t, air_style_event_count(reversed_events[:], .Immelmann, .Completed) == 0)

    missing := air_style_build_immelmann(true, false, definitions)
    defer delete(missing)
    _, missing_events := air_style_run_stream(missing[:], definitions)
    defer delete(missing_events)
    testing.expect(t, air_style_event_count(missing_events[:], .Immelmann, .Completed) == 0)
}

air_style_build_split_s :: proc(
    include_roll: bool,
    pitch_fraction: f32,
    definitions: air_style.Definitions,
) -> [dynamic]air_style.Motion_Sample {
    state := air_style_synthetic_state(altitude = 300)
    samples: [dynamic]air_style.Motion_Sample
    half_steps := 63
    half_rate := air_style_target_rate(f32(math.PI * 1.05), half_steps)
    if include_roll {
        air_style_append_motion(&samples, &state, {0, 0, half_rate}, half_steps)
    }
    pitch_steps := max(1, int(f32(half_steps) * pitch_fraction))
    air_style_append_motion(&samples, &state, {half_rate, 0, 0}, pitch_steps)
    if include_roll && pitch_fraction >= 1 {
        opposite := flight.orientation_from_forward_and_up({0, 0, 1}, {0, 1, 0})
        air_style_append_controlled_exit(&samples, &state, opposite, definitions)
    } else {
        timeout_steps := int(definitions.candidate_timeout_seconds / AIR_STYLE_TEST_DT) + 4
        air_style_append_motion(&samples, &state, {}, timeout_steps)
    }
    return samples
}

@(test)
air_style_split_s_requires_inverted_roll_before_descending_half_loop :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    ordered := air_style_build_split_s(true, 1, definitions)
    defer delete(ordered)
    _, ordered_events := air_style_run_stream(ordered[:], definitions)
    defer delete(ordered_events)
    testing.expect(t, air_style_event_count(ordered_events[:], .Split_S, .Completed) == 1)
    testing.expect(t, air_style_event_count(ordered_events[:], .Aileron_Roll, .Completed) == 0)
    air_style_expect_composite_lifecycle(t, ordered_events[:], .Aileron_Roll, .Split_S, .Promoted_To_Split_S)

    premature := air_style_build_split_s(true, .4, definitions)
    defer delete(premature)
    _, premature_events := air_style_run_stream(premature[:], definitions)
    defer delete(premature_events)
    testing.expect(t, air_style_event_count(premature_events[:], .Split_S, .Completed) == 0)

    descending_loop_state := air_style_synthetic_state(altitude = 300)
    descending_loop_samples: [dynamic]air_style.Motion_Sample
    defer delete(descending_loop_samples)
    loop_steps := 126
    loop_rate := air_style_target_rate(f32(-math.PI * 2.1), loop_steps)
    air_style_append_motion(&descending_loop_samples, &descending_loop_state, {loop_rate, 0, 0}, loop_steps)
    air_style_append_controlled_exit(
        &descending_loop_samples,
        &descending_loop_state,
        flight.identity_orientation(),
        definitions,
    )
    _, descending_loop_events := air_style_run_stream(descending_loop_samples[:], definitions)
    defer delete(descending_loop_events)
    testing.expect(t, air_style_event_count(descending_loop_events[:], .Split_S, .Completed) == 0)
    testing.expect(t, air_style_event_count(descending_loop_events[:], .Loop, .Completed) == 1)
}

@(test)
air_style_pre_inversion_descent_does_not_qualify_split_s :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    state := air_style_synthetic_state(altitude = 300)
    samples: [dynamic]air_style.Motion_Sample
    defer delete(samples)
    half_steps := 63
    half_rate := air_style_target_rate(f32(math.PI * 1.05), half_steps)
    air_style_append_motion(&samples, &state, {0, 0, half_rate}, half_steps)
    air_style_append_motion(&samples, &state, {half_rate, 0, 0}, half_steps)

    descent_steps := 20
    prior_altitude := f32(300)
    for &sample, index in samples {
        altitude := f32(280)
        if index < descent_steps {
            altitude = 300 - 20 * f32(index + 1) / f32(descent_steps)
        }
        sample.previous_body.position.y = prior_altitude
        sample.body.position.y = altitude
        sample.ground_clearance = altitude
        prior_altitude = altitude
    }

    _, events := air_style_run_stream(samples[:], definitions)
    defer delete(events)
    testing.expect(t, air_style_reason_count(events[:], .Promoted_To_Split_S) == 0)
    testing.expect(t, air_style_event_count(events[:], .Split_S, .Completed) == 0)
}

@(test)
air_style_roll_before_apex_does_not_qualify_immelmann :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    state := air_style_synthetic_state(altitude = 250)
    samples: [dynamic]air_style.Motion_Sample
    defer delete(samples)
    pitch_steps := 54
    pitch_rate := air_style_target_rate(f32(math.PI * .9), pitch_steps)
    air_style_append_motion(&samples, &state, {pitch_rate, 0, 0}, pitch_steps)
    testing.expect(t, state.body.velocity.y > definitions.composite_apex_vertical_speed)
    roll_steps := 63
    roll_rate := air_style_target_rate(f32(math.PI * 1.05), roll_steps)
    air_style_append_motion(&samples, &state, {0, 0, roll_rate}, roll_steps)

    _, events := air_style_run_stream(samples[:], definitions)
    defer delete(events)
    testing.expect(t, air_style_reason_count(events[:], .Promoted_To_Immelmann) == 0)
    testing.expect(t, air_style_event_count(events[:], .Immelmann, .Completed) == 0)
}

@(test)
air_style_slow_near_prime_roll_and_loop_complete :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    definitions.candidate_timeout_seconds = 12

    roll_state := air_style_synthetic_state()
    roll_samples: [dynamic]air_style.Motion_Sample
    defer delete(roll_samples)
    roll_steps := 950
    roll_rate := air_style_target_rate(f32(math.PI * 2.1), roll_steps)
    testing.expect(t, roll_rate > definitions.roll_prime_rate)
    air_style_append_motion(&roll_samples, &roll_state, {0, 0, roll_rate}, roll_steps)
    air_style_append_controlled_exit(&roll_samples, &roll_state, flight.identity_orientation(), definitions)
    _, roll_events := air_style_run_stream(roll_samples[:], definitions)
    defer delete(roll_events)
    testing.expect(t, air_style_event_count(roll_events[:], .Aileron_Roll, .Completed) == 1)
    testing.expect(t, !air_style_has_failure(roll_events[:], .Timeout))

    loop_state := air_style_synthetic_state(altitude = 250)
    loop_samples: [dynamic]air_style.Motion_Sample
    defer delete(loop_samples)
    loop_steps := 1180
    loop_rate := air_style_target_rate(f32(math.PI * 2.1), loop_steps)
    testing.expect(t, loop_rate > definitions.pitch_prime_rate)
    air_style_append_motion(&loop_samples, &loop_state, {loop_rate, 0, 0}, loop_steps)
    air_style_append_controlled_exit(&loop_samples, &loop_state, flight.identity_orientation(), definitions)
    _, loop_events := air_style_run_stream(loop_samples[:], definitions)
    defer delete(loop_events)
    testing.expect(t, air_style_event_count(loop_events[:], .Loop, .Completed) == 1)
    testing.expect(t, !air_style_has_failure(loop_events[:], .Timeout))
}

@(test)
air_style_risk_summary_uses_full_stream_and_minimum_context :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    state := air_style_synthetic_state()
    samples: [dynamic]air_style.Motion_Sample
    defer delete(samples)
    roll_steps := 126
    roll_rate := air_style_target_rate(f32(math.PI * 2.1), roll_steps)
    air_style_append_motion(&samples, &state, {0, 0, roll_rate}, roll_steps)
    air_style_append_controlled_exit(&samples, &state, flight.identity_orientation(), definitions)

    minimum_context := air_style.Risk_Context_ID(99)
    ordinary_context := air_style.Risk_Context_ID(41)
    minimum_index := len(samples) / 2
    for &sample, index in samples {
        sample.pace = 30 + f32(index % 3) * 10
        sample.ground_clearance = 80 + f32(index % 7)
        sample.recovery_margin = .9 - f32(index % 6) * .1
        sample.has_ace_state = true
        sample.ace_energy = index % 4 == 0 ? f32(.2) : f32(.8)
        sample.damaged = index % 5 == 0
        sample.has_authored_clearance = index % 3 == 0
        sample.authored_clearance = 20 + f32(index % 5)
        sample.authored_risk_context_id = ordinary_context
        if index == minimum_index {
            sample.has_authored_clearance = true
            sample.authored_clearance = 3
            sample.authored_risk_context_id = minimum_context
        }
    }

    recognizer: air_style.Recognizer
    completion: air_style.Maneuver_Event
    completion_index := -1
    for sample, index in samples {
        buffer := air_style.recognize_step(&recognizer, definitions, sample)
        for event_index in 0 ..< buffer.count {
            event := buffer.events[event_index]
            if event.kind == .Aileron_Roll && event.lifecycle == .Completed {
                completion = event
                completion_index = index
                break
            }
        }
        if completion_index >= 0 do break
    }
    testing.expect(t, completion_index >= 0)
    if completion_index < 0 do return

    consumed_samples := samples[:completion_index + 1]
    expected_ground_sum, expected_pace_sum: f32
    expected_authored_sum: f32
    expected_authored_count, expected_low_energy_count: int
    expected_inverted_count, expected_knife_count, expected_damaged_count: int
    expected_minimum_ground := f32(1e6)
    expected_minimum_authored := f32(1e6)
    expected_minimum_recovery := f32(1e6)
    for sample in consumed_samples {
        expected_ground_sum += sample.ground_clearance
        expected_pace_sum += sample.pace
        expected_minimum_ground = min(expected_minimum_ground, sample.ground_clearance)
        expected_minimum_recovery = min(expected_minimum_recovery, sample.recovery_margin)
        if sample.has_authored_clearance {
            expected_authored_sum += sample.authored_clearance
            expected_authored_count += 1
            expected_minimum_authored = min(expected_minimum_authored, sample.authored_clearance)
        }
        if sample.ace_energy < .35 do expected_low_energy_count += 1
        if sample.damaged do expected_damaged_count += 1
        basis := flight.basis_from_orientation(sample.body.orientation)
        up_alignment := linalg.dot(basis.up, flight.Vec3{0, 1, 0})
        if up_alignment < 0 do expected_inverted_count += 1
        if math.abs(up_alignment) <= definitions.knife_up_alignment do expected_knife_count += 1
    }

    sample_count := f32(len(consumed_samples))
    risk := completion.risk
    air_style_expect_near(t, risk.duration, sample_count * AIR_STYLE_TEST_DT)
    air_style_expect_near(t, risk.minimum_ground_clearance, expected_minimum_ground)
    air_style_expect_near(t, risk.average_ground_clearance, expected_ground_sum / sample_count)
    testing.expect(t, risk.has_authored_clearance)
    air_style_expect_near(t, risk.minimum_authored_clearance, expected_minimum_authored)
    air_style_expect_near(t, risk.average_authored_clearance, expected_authored_sum / f32(expected_authored_count))
    air_style_expect_near(t, risk.authored_exposure_fraction, f32(expected_authored_count) / sample_count)
    testing.expect(t, risk.authored_risk_context_id == minimum_context)
    air_style_expect_near(t, risk.average_pace, expected_pace_sum / sample_count)
    air_style_expect_near(t, risk.low_energy_fraction, f32(expected_low_energy_count) / sample_count)
    air_style_expect_near(t, risk.inverted_fraction, f32(expected_inverted_count) / sample_count)
    air_style_expect_near(t, risk.knife_edge_fraction, f32(expected_knife_count) / sample_count)
    air_style_expect_near(t, risk.damaged_fraction, f32(expected_damaged_count) / sample_count)
    air_style_expect_near(t, risk.minimum_recovery_margin, expected_minimum_recovery)
}

@(test)
air_style_collision_reset_and_timeout_fail_without_completion :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()

    collision_state := air_style_synthetic_state()
    collision_samples: [dynamic]air_style.Motion_Sample
    defer delete(collision_samples)
    roll_steps := 126
    roll_rate := air_style_target_rate(f32(math.PI * 2.1), roll_steps)
    air_style_append_motion(&collision_samples, &collision_state, {0, 0, roll_rate}, roll_steps)
    air_style_append_motion(&collision_samples, &collision_state, {}, 1)
    collision_samples[len(collision_samples) - 1].collision = true
    _, collision_events := air_style_run_stream(collision_samples[:], definitions)
    defer delete(collision_events)
    testing.expect(t, air_style_has_failure(collision_events[:], .Collision))
    testing.expect(t, air_style_event_count(collision_events[:], .Aileron_Roll, .Completed) == 0)

    reset_state := air_style_synthetic_state()
    reset_samples: [dynamic]air_style.Motion_Sample
    defer delete(reset_samples)
    air_style_append_motion(&reset_samples, &reset_state, {0, 0, roll_rate}, 20)
    air_style_append_motion(&reset_samples, &reset_state, {}, 1)
    reset_samples[len(reset_samples) - 1].reset = true
    air_style_set_pose(&reset_state, flight.identity_orientation())
    air_style_append_motion(&reset_samples, &reset_state, {0, 0, roll_rate}, roll_steps)
    air_style_append_controlled_exit(&reset_samples, &reset_state, flight.identity_orientation(), definitions)
    _, reset_events := air_style_run_stream(reset_samples[:], definitions)
    defer delete(reset_events)
    testing.expect(t, air_style_has_failure(reset_events[:], .Reset))
    testing.expect(t, air_style_event_count(reset_events[:], .Aileron_Roll, .Completed) == 1)
    reset_failure, reset_found := air_style_find_event(reset_events[:], .Aileron_Roll, .Failed)
    reset_completion, completion_found := air_style_find_event(reset_events[:], .Aileron_Roll, .Completed)
    testing.expect(t, reset_found && completion_found)
    testing.expect(t, u64(reset_completion.gesture_id) > u64(reset_failure.gesture_id))

    timeout_state := air_style_synthetic_state()
    timeout_samples: [dynamic]air_style.Motion_Sample
    defer delete(timeout_samples)
    air_style_append_motion(&timeout_samples, &timeout_state, {0, 0, roll_rate}, 20)
    timeout_steps := int(definitions.candidate_timeout_seconds / AIR_STYLE_TEST_DT) + 4
    air_style_append_motion(&timeout_samples, &timeout_state, {}, timeout_steps)
    _, timeout_events := air_style_run_stream(timeout_samples[:], definitions)
    defer delete(timeout_events)
    testing.expect(t, air_style_has_failure(timeout_events[:], .Timeout))
    testing.expect(t, air_style_event_count(timeout_events[:], .Aileron_Roll, .Completed) == 0)
}

@(test)
air_style_ordinary_flight_and_turbulent_corrections_stay_quiet :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    state := air_style_synthetic_state()
    samples: [dynamic]air_style.Motion_Sample
    defer delete(samples)

    air_style_append_motion(&samples, &state, {}, 600)
    bank_steps := 120
    bank_rate := air_style_target_rate(.5, bank_steps)
    air_style_append_motion(&samples, &state, {0, 0, bank_rate}, bank_steps)
    air_style_append_motion(&samples, &state, {0, .25, 0}, 240)
    air_style_append_motion(&samples, &state, {0, 0, -bank_rate}, bank_steps)
    climb_steps := 60
    climb_rate := air_style_target_rate(.2, climb_steps)
    air_style_append_motion(&samples, &state, {climb_rate, 0, 0}, climb_steps)
    air_style_append_motion(&samples, &state, {}, 240)
    for index in 0 ..< 20 {
        sign := index % 2 == 0 ? f32(1) : f32(-1)
        air_style_append_motion(&samples, &state, {.5 * sign, .3 * sign, .6 * sign}, 12)
    }

    recognizer, events := air_style_run_stream(samples[:], definitions)
    defer delete(events)
    completed := 0
    for event in events {
        if event.lifecycle == .Completed do completed += 1
    }
    testing.expect(t, completed == 0)
    testing.expect(t, !recognizer.candidate.active)
}

@(test)
air_style_intent_without_body_motion_stays_quiet :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    state := air_style_synthetic_state()
    samples: [dynamic]air_style.Motion_Sample
    defer delete(samples)
    air_style_append_motion(&samples, &state, {}, 240)
    for &sample, index in samples {
        sign := index % 2 == 0 ? f32(1) : f32(-1)
        sample.intent = {
            pitch         = sign,
            yaw           = -sign,
            roll          = sign,
            throttle      = 1,
            flap_fraction = index % 3 == 0 ? f32(1) : f32(0),
        }
    }

    recognizer, events := air_style_run_stream(samples[:], definitions)
    defer delete(events)
    testing.expect(t, len(events) == 0)
    testing.expect(t, !recognizer.candidate.active)
}

@(test)
air_style_identical_motion_stream_produces_exact_events_without_mutation :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    state := air_style_synthetic_state()
    samples: [dynamic]air_style.Motion_Sample
    defer delete(samples)
    roll_steps := 126
    roll_rate := air_style_target_rate(f32(math.PI * 2.1), roll_steps)
    air_style_append_motion(&samples, &state, {0, 0, roll_rate}, roll_steps)
    air_style_append_controlled_exit(&samples, &state, flight.identity_orientation(), definitions)
    samples_before := make([]air_style.Motion_Sample, len(samples))
    defer delete(samples_before)
    copy(samples_before, samples[:])

    recognizer_a, events_a := air_style_run_stream(samples[:], definitions)
    defer delete(events_a)
    recognizer_b, events_b := air_style_run_stream(samples[:], definitions)
    defer delete(events_b)
    testing.expect(t, recognizer_a == recognizer_b)
    testing.expect(t, len(events_a) == len(events_b))
    if len(events_a) == len(events_b) {
        for event, index in events_a {
            testing.expect(t, event == events_b[index])
        }
    }
    testing.expect(t, len(samples_before) == len(samples))
    for sample, index in samples {
        testing.expect(t, sample == samples_before[index])
    }
}

air_style_score_event :: proc(gesture_id: u64, kind: air_style.Maneuver_Kind) -> air_style.Maneuver_Event {
    event := air_style.Maneuver_Event {
        gesture_id = air_style.Gesture_ID(gesture_id),
        kind = kind,
        lifecycle = .Completed,
        transition_reason = .Controlled_Exit,
        absolute_local_rotation = {f32(math.PI * 2), 0, f32(math.PI * 2)},
        duration = 1.2,
        entry_altitude = 200,
        completion = 1,
        continuity = 1,
        risk = {
            duration = 1.2,
            minimum_ground_clearance = 50,
            average_ground_clearance = 50,
            average_pace = 40,
            minimum_recovery_margin = 25,
        },
    }
    return event
}

air_style_score_send :: proc(
    state: ^air_style.Score_State,
    definitions: air_style.Scoring_Definitions,
    event: air_style.Maneuver_Event,
    route_continuing: bool = true,
) -> air_style.Score_Breakdown {
    input := air_style.Score_Input {
        delta_seconds = AIR_STYLE_TEST_DT,
        route_continuing = route_continuing,
        events = {count = 1},
    }
    input.events.events[0] = event
    result := air_style.score_step(state, definitions, input)
    if result.count == 0 do return {}
    return result.breakdowns[0]
}

air_style_score_complete :: proc(
    state: ^air_style.Score_State,
    definitions: air_style.Scoring_Definitions,
    completed: air_style.Maneuver_Event,
) -> air_style.Score_Breakdown {
    event := completed
    base_kind := completed.kind
    if completed.kind == .Immelmann do base_kind = .Loop
    if completed.kind == .Split_S do base_kind = .Aileron_Roll
    event.kind = base_kind
    event.lifecycle = .Primed
    event.transition_reason = .Motion_Primed
    _ = air_style_score_send(state, definitions, event)

    event.lifecycle = .Committed
    event.transition_reason = .Motion_Committed
    _ = air_style_score_send(state, definitions, event)

    if base_kind != completed.kind {
        event.kind = completed.kind
        if completed.kind == .Immelmann {
            event.transition_reason = .Promoted_To_Immelmann
        } else {
            event.transition_reason = .Promoted_To_Split_S
        }
        _ = air_style_score_send(state, definitions, event)
    }

    event.lifecycle = .Recovering
    event.transition_reason = .Rotation_Reached
    if event.kind == .Knife_Edge do event.transition_reason = .Hold_Reached
    _ = air_style_score_send(state, definitions, event)

    return air_style_score_send(state, definitions, completed)
}

air_style_score_fail :: proc(
    state: ^air_style.Score_State,
    definitions: air_style.Scoring_Definitions,
    gesture_id: u64,
    kind: air_style.Maneuver_Kind,
    failure: air_style.Failure_Reason,
) -> air_style.Score_Breakdown {
    event := air_style_score_event(gesture_id, kind)
    event.lifecycle = .Primed
    event.transition_reason = .Motion_Primed
    _ = air_style_score_send(state, definitions, event)
    event.lifecycle = .Committed
    event.transition_reason = .Motion_Committed
    _ = air_style_score_send(state, definitions, event)
    event.lifecycle = .Failed
    event.failure_reason = failure
    switch failure {
    case .Collision:
        event.transition_reason = .Collision
    case .Reset:
        event.transition_reason = .Reset
    case .Timeout:
        event.transition_reason = .Timeout
    case .Contradictory_Motion:
        event.transition_reason = .Contradictory_Motion
    case .Uncontrolled_Exit:
        event.transition_reason = .Uncontrolled_Exit
    case .None:
        event.transition_reason = .None
    }
    return air_style_score_send(state, definitions, event)
}

air_style_score_tick :: proc(
    state: ^air_style.Score_State,
    definitions: air_style.Scoring_Definitions,
    route_continuing: bool,
) {
    _ = air_style.score_step(
        state,
        definitions,
        {delta_seconds = definitions.maximum_delta_seconds, route_continuing = route_continuing},
    )
}

@(test)
air_style_knife_priming_tick_counts_at_exact_hold_threshold :: proc(t: ^testing.T) {
    definitions := air_style.default_definitions()
    state := air_style_synthetic_state()
    knife_orientation := flight.orientation_from_forward_and_up({0, 0, -1}, {1, 0, 0})
    air_style_set_pose(&state, knife_orientation)
    samples: [dynamic]air_style.Motion_Sample
    defer delete(samples)
    hold_steps := int(math.ceil(f64(definitions.knife_minimum_hold_seconds / AIR_STYLE_TEST_DT)))
    air_style_append_motion(&samples, &state, {}, hold_steps)
    air_style_append_controlled_exit(&samples, &state, flight.identity_orientation(), definitions)

    _, events := air_style_run_stream(samples[:], definitions)
    defer delete(events)
    completion, found := air_style_find_event(events[:], .Knife_Edge, .Completed)
    testing.expect(t, found)
    testing.expect(t, completion.completion == 1)
    testing.expect(t, completion.risk.duration >= definitions.knife_minimum_hold_seconds)
}

@(test)
air_style_score_defaults_resets_history_and_terminal_ids :: proc(t: ^testing.T) {
    definitions := air_style.default_scoring_definitions()
    testing.expect(t, air_style.scoring_definitions_are_valid(definitions))
    state: air_style.Score_State
    testing.expect(t, air_style.score_state_is_valid(state, definitions))

    first := air_style_score_complete(&state, definitions, air_style_score_event(1, .Loop))
    testing.expect(t, first.outcome == .Banked)
    banked := state.banked_run_score
    testing.expect(t, banked > 0)
    history_count := state.history_count
    idle_equivalent := state
    _ = air_style.score_step(
        &idle_equivalent,
        definitions,
        {delta_seconds = AIR_STYLE_TEST_DT, route_continuing = true},
    )
    duplicate_terminal := air_style_score_send(&state, definitions, air_style_score_event(1, .Loop))
    testing.expect(t, duplicate_terminal.rejection == .Duplicate_Gesture)
    testing.expect(t, state == idle_equivalent)
    testing.expect(t, state.banked_run_score == banked)
    testing.expect(t, state.history_count == history_count)

    active := air_style_score_event(2, .Aileron_Roll)
    active.lifecycle = .Primed
    active.transition_reason = .Motion_Primed
    _ = air_style_score_send(&state, definitions, active)
    active.lifecycle = .Committed
    active.transition_reason = .Motion_Committed
    _ = air_style_score_send(&state, definitions, active)
    rank_before_reset := state.rank_value
    air_style.score_reset_flight(&state, definitions)
    testing.expect(t, !state.pending.active)
    testing.expect(t, state.banked_run_score == banked)
    testing.expect(t, state.history_count == 1)
    testing.expect(t, state.last_processed_gesture_id == air_style.Gesture_ID(2))
    testing.expect(t, state.last_terminal_failed)
    testing.expect(t, state.rank_value <= rank_before_reset)

    late := air_style_score_event(2, .Aileron_Roll)
    rejection := air_style_score_send(&state, definitions, late)
    testing.expect(t, rejection.rejection == .Post_Failure_Completion)
    testing.expect(t, state.banked_run_score == banked)

    air_style.score_reset_run(&state)
    testing.expect(t, state == air_style.Score_State{})
    testing.expect(t, air_style.score_state_is_valid(state, definitions))

    kinds := [?]air_style.Maneuver_Kind{.Aileron_Roll, .Loop, .Knife_Edge, .Immelmann, .Split_S}
    for gesture_id in 1 ..= 9 {
        kind := kinds[(gesture_id - 1) % len(kinds)]
        _ = air_style_score_complete(&state, definitions, air_style_score_event(u64(gesture_id), kind))
    }
    testing.expect(t, state.history_count == air_style.SCORE_HISTORY_CAPACITY)
    testing.expect(t, state.history[0].gesture_id == air_style.Gesture_ID(2))
    testing.expect(t, state.history[state.history_count - 1].gesture_id == air_style.Gesture_ID(9))
}

@(test)
air_style_score_execution_banks_imperfect_control_and_rejects_uncontrolled_exit :: proc(t: ^testing.T) {
    definitions := air_style.default_scoring_definitions()
    clean_state, messy_state, failed_state: air_style.Score_State
    clean := air_style_score_event(1, .Loop)
    clean_result := air_style_score_complete(&clean_state, definitions, clean)

    messy := air_style_score_event(1, .Loop)
    messy.completion = .8
    messy.exit_heading_error = .3
    messy.exit_altitude_error = 20
    messy.continuity = .6
    messy.correction = .4
    messy_result := air_style_score_complete(&messy_state, definitions, messy)
    testing.expect(t, clean_result.banked_delta > messy_result.banked_delta)
    testing.expect(t, messy_result.banked_delta > 0)

    uncontrolled := air_style_score_event(1, .Loop)
    event := uncontrolled
    event.lifecycle = .Primed
    event.transition_reason = .Motion_Primed
    _ = air_style_score_send(&failed_state, definitions, event)
    event.lifecycle = .Committed
    event.transition_reason = .Motion_Committed
    _ = air_style_score_send(&failed_state, definitions, event)
    event.lifecycle = .Recovering
    event.transition_reason = .Rotation_Reached
    _ = air_style_score_send(&failed_state, definitions, event)
    uncontrolled.transition_reason = .Uncontrolled_Exit
    lost := air_style_score_send(&failed_state, definitions, uncontrolled)
    testing.expect(t, lost.outcome == .Lost)
    testing.expect(t, lost.rejection == .Uncontrolled_Exit)
    testing.expect(t, failed_state.banked_run_score == 0)
    testing.expect(t, !failed_state.pending.active)
}

@(test)
air_style_score_lifetime_risk_and_authored_context_resist_one_frame_cheese :: proc(t: ^testing.T) {
    definitions := air_style.default_scoring_definitions()
    high_state, low_state: air_style.Score_State
    high := air_style_score_event(1, .Aileron_Roll)
    low := high
    high.risk.minimum_ground_clearance = 40
    high.risk.average_ground_clearance = 40
    low.risk.minimum_ground_clearance = 5
    low.risk.average_ground_clearance = 5
    high_result := air_style_score_complete(&high_state, definitions, high)
    low_result := air_style_score_complete(&low_state, definitions, low)
    testing.expect(t, low_result.risk.multiplier > high_result.risk.multiplier)
    testing.expect(t, low_result.banked_delta > high_result.banked_delta)

    plain_state, proximity_state: air_style.Score_State
    plain := air_style_score_event(1, .Loop)
    proximity := plain
    proximity.risk.has_authored_clearance = true
    proximity.risk.minimum_authored_clearance = .5
    proximity.risk.average_authored_clearance = .5
    proximity.risk.authored_exposure_fraction = AIR_STYLE_TEST_DT / proximity.risk.duration
    proximity.risk.authored_risk_context_id = air_style.Risk_Context_ID(77)
    plain_result := air_style_score_complete(&plain_state, definitions, plain)
    proximity_result := air_style_score_complete(&proximity_state, definitions, proximity)
    testing.expect(t, proximity_result.risk.authored > 0)
    testing.expect(t, proximity_result.risk.multiplier - plain_result.risk.multiplier < .01)

    context_state: air_style.Score_State
    freshness: [3]f32
    for index in 0 ..< len(freshness) {
        event := air_style_score_event(u64(index + 1), .Loop)
        event.risk.has_authored_clearance = true
        event.risk.minimum_authored_clearance = 1
        event.risk.average_authored_clearance = 1
        event.risk.authored_exposure_fraction = 1
        event.risk.authored_risk_context_id = air_style.Risk_Context_ID(55)
        result := air_style_score_complete(&context_state, definitions, event)
        freshness[index] = result.risk.authored_context_freshness
    }
    testing.expect(t, freshness[0] == 1)
    testing.expect(t, freshness[1] == definitions.authored_context_reuse)
    testing.expect(t, freshness[2] == 0)

    refresh_state: air_style.Score_State
    first_context := air_style_score_event(1, .Loop)
    first_context.risk.has_authored_clearance = true
    first_context.risk.minimum_authored_clearance = 2
    first_context.risk.average_authored_clearance = 2
    first_context.risk.authored_exposure_fraction = 1
    first_context.risk.authored_risk_context_id = air_style.Risk_Context_ID(1)
    _ = air_style_score_complete(&refresh_state, definitions, first_context)
    second_context := first_context
    second_context.gesture_id = air_style.Gesture_ID(2)
    second_context.risk.authored_risk_context_id = air_style.Risk_Context_ID(2)
    refreshed := air_style_score_complete(&refresh_state, definitions, second_context)
    air_style_expect_near(
        t,
        refreshed.variety_multiplier,
        definitions.first_repeat_variety + definitions.context_variety_refresh,
    )
    testing.expect(t, refreshed.variety_multiplier < 1)
}

@(test)
air_style_score_variety_and_safe_roll_farm_decay_hard :: proc(t: ^testing.T) {
    definitions := air_style.default_scoring_definitions()
    repeats: air_style.Score_State
    awards: [4]f32
    repeat_counts: [4]int
    last_outcome: air_style.Score_Outcome
    for index in 0 ..< len(awards) {
        event := air_style_score_event(u64(index + 1), .Aileron_Roll)
        if index % 2 == 0 {
            event.signed_local_rotation.z = f32(math.PI * 2)
        } else {
            event.signed_local_rotation.z = f32(-math.PI * 2)
        }
        result := air_style_score_complete(&repeats, definitions, event)
        awards[index] = result.banked_delta
        repeat_counts[index] = result.repeat_count
        last_outcome = result.outcome
    }
    testing.expect(t, repeat_counts == [4]int{0, 1, 2, 3})
    testing.expect(t, awards[1] < awards[0])
    testing.expect(t, awards[2] < awards[1])
    testing.expect(t, awards[3] < awards[0] / 3)
    testing.expect(t, awards[3] == 0)
    testing.expect(t, last_outcome == .Rejected)

    distinct_state: air_style.Score_State
    _ = air_style_score_complete(&distinct_state, definitions, air_style_score_event(1, .Aileron_Roll))
    _ = air_style_score_complete(&distinct_state, definitions, air_style_score_event(2, .Loop))
    distinct_third := air_style_score_complete(&distinct_state, definitions, air_style_score_event(3, .Knife_Edge))
    testing.expect(t, distinct_third.repeat_count == 0)
    testing.expect(t, distinct_state.banked_run_score > repeats.banked_run_score)
}

@(test)
air_style_score_flow_uses_fixed_time_route_and_failure_boundaries :: proc(t: ^testing.T) {
    definitions := air_style.default_scoring_definitions()
    seed: air_style.Score_State
    _ = air_style_score_complete(&seed, definitions, air_style_score_event(1, .Loop))

    immediate := seed
    immediate_result := air_style_score_complete(&immediate, definitions, air_style_score_event(2, .Loop))
    testing.expect(t, immediate_result.flow_multiplier == definitions.flow_multiplier)

    short_pause := seed
    short_ticks := int(.4 / definitions.maximum_delta_seconds)
    for _ in 0 ..< short_ticks do air_style_score_tick(&short_pause, definitions, false)
    short_result := air_style_score_complete(&short_pause, definitions, air_style_score_event(2, .Loop))
    testing.expect(t, short_result.flow_multiplier == definitions.flow_multiplier)

    long_pause := seed
    long_ticks := int(.7 / definitions.maximum_delta_seconds)
    for _ in 0 ..< long_ticks do air_style_score_tick(&long_pause, definitions, false)
    long_result := air_style_score_complete(&long_pause, definitions, air_style_score_event(2, .Loop))
    testing.expect(t, long_result.flow_multiplier == 1)
    testing.expect(t, immediate_result.banked_delta > long_result.banked_delta)

    failed := seed
    banked := failed.banked_run_score
    lost := air_style_score_fail(&failed, definitions, 2, .Aileron_Roll, .Collision)
    testing.expect(t, lost.outcome == .Lost)
    testing.expect(t, failed.flow_seconds_remaining == 0)
    testing.expect(t, failed.combo_count == 0)
    testing.expect(t, failed.banked_run_score == banked)
}

@(test)
air_style_score_lifecycle_promotion_failures_duplicates_and_rank_decay :: proc(t: ^testing.T) {
    definitions := air_style.default_scoring_definitions()
    direct_composite: air_style.Score_State
    direct := air_style_score_event(1, .Immelmann)
    direct.lifecycle = .Primed
    direct.transition_reason = .Motion_Primed
    direct_result := air_style_score_send(&direct_composite, definitions, direct)
    testing.expect(t, direct_result.rejection == .Invalid_Event)
    testing.expect(t, !direct_composite.pending.active)

    state: air_style.Score_State
    event := air_style_score_event(1, .Loop)
    event.lifecycle = .Primed
    event.transition_reason = .Motion_Primed
    primed := air_style_score_send(&state, definitions, event)
    testing.expect(t, primed.outcome == .Pending)
    testing.expect(t, state.pending.pending_value == 0)

    duplicate := air_style_score_send(&state, definitions, event)
    testing.expect(t, duplicate.rejection == .Duplicate_Gesture)
    event.lifecycle = .Committed
    event.transition_reason = .Motion_Committed
    committed := air_style_score_send(&state, definitions, event)
    testing.expect(t, committed.pending_after > 0)

    committed_state := state
    poisoned_commit := event
    poisoned_commit.failure_reason = .Collision
    poisoned := air_style_score_send(&state, definitions, poisoned_commit)
    testing.expect(t, poisoned.rejection == .Invalid_Event)
    testing.expect(t, state == committed_state)

    wrong_failure := event
    wrong_failure.kind = .Aileron_Roll
    wrong_failure.lifecycle = .Failed
    wrong_failure.transition_reason = .Collision
    wrong_failure.failure_reason = .Collision
    wrong_result := air_style_score_send(&state, definitions, wrong_failure)
    testing.expect(t, wrong_result.rejection == .Out_Of_Order)
    testing.expect(t, state.pending.active)
    testing.expect(t, state.pending.kind == .Loop)

    event.kind = .Immelmann
    event.transition_reason = .Promoted_To_Immelmann
    promoted := air_style_score_send(&state, definitions, event)
    testing.expect(t, promoted.outcome == .Pending)
    testing.expect(t, state.pending.gesture_id == air_style.Gesture_ID(1))
    testing.expect(t, state.pending.kind == .Immelmann)
    event.lifecycle = .Recovering
    event.transition_reason = .Rotation_Reached
    _ = air_style_score_send(&state, definitions, event)
    event.lifecycle = .Completed
    event.transition_reason = .Controlled_Exit
    banked := air_style_score_send(&state, definitions, event)
    testing.expect(t, banked.outcome == .Banked)
    testing.expect(t, state.history_count == 1)

    bank_before_failure := state.banked_run_score
    for failure in air_style.Failure_Reason {
        if failure == .None do continue
        gesture_id := u64(state.last_processed_gesture_id) + 1
        result := air_style_score_fail(&state, definitions, gesture_id, .Aileron_Roll, failure)
        testing.expect(t, result.outcome == .Lost)
        testing.expect(t, state.banked_run_score == bank_before_failure)
    }

    rank_state: air_style.Score_State
    _ = air_style_score_complete(&rank_state, definitions, air_style_score_event(1, .Immelmann))
    _ = air_style_score_complete(&rank_state, definitions, air_style_score_event(2, .Split_S))
    bank_before_idle := rank_state.banked_run_score
    rank_before_idle := rank_state.rank_value
    idle_ticks := int((definitions.passive_rank_grace_seconds + 1) / definitions.maximum_delta_seconds)
    for _ in 0 ..< idle_ticks do air_style_score_tick(&rank_state, definitions, true)
    testing.expect(t, rank_state.rank_value < rank_before_idle)
    testing.expect(t, rank_state.banked_run_score == bank_before_idle)
}

@(test)
air_style_score_invalid_and_identical_streams_are_atomic_and_exact :: proc(t: ^testing.T) {
    definitions := air_style.default_scoring_definitions()
    original: air_style.Score_State
    _ = air_style_score_complete(&original, definitions, air_style_score_event(1, .Loop))
    invalid_state := original
    invalid := air_style_score_event(2, .Loop)
    invalid.completion = 2
    rejection := air_style_score_send(&invalid_state, definitions, invalid)
    testing.expect(t, rejection.rejection == .Invalid_Event)
    testing.expect(t, invalid_state == original)

    a, b: air_style.Score_State
    kinds := [?]air_style.Maneuver_Kind{.Aileron_Roll, .Loop, .Knife_Edge, .Immelmann, .Split_S}
    for kind, index in kinds {
        event := air_style_score_event(u64(index + 1), kind)
        event.risk.average_ground_clearance = 10 + f32(index)
        event.risk.minimum_ground_clearance = 5 + f32(index)
        result_a := air_style_score_complete(&a, definitions, event)
        result_b := air_style_score_complete(&b, definitions, event)
        testing.expect(t, result_a == result_b)
        testing.expect(t, a == b)
    }
}
