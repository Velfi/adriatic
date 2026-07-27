package air_style

import flight "../flight"
import "core:math"
import "core:math/linalg"

recognizer_finite :: proc(value: f32) -> bool {
    return value == value && !math.is_inf_f32(value)
}

recognizer_finite_vector :: proc(value: flight.Vec3) -> bool {
    return recognizer_finite(value.x) && recognizer_finite(value.y) && recognizer_finite(value.z)
}

recognizer_body_is_valid :: proc(body: flight.Body_State) -> bool {
    orientation := body.orientation
    return(
        recognizer_finite_vector(body.position) &&
        recognizer_finite_vector(body.velocity) &&
        recognizer_finite_vector(body.angular_velocity_world) &&
        recognizer_finite(orientation.x) &&
        recognizer_finite(orientation.y) &&
        recognizer_finite(orientation.z) &&
        recognizer_finite(orientation.w) &&
        orientation.x * orientation.x +
                orientation.y * orientation.y +
                orientation.z * orientation.z +
                orientation.w * orientation.w >
            1e-12 \
    )
}

motion_sample_is_valid :: proc(sample: Motion_Sample, definitions: Definitions) -> bool {
    if !definitions_are_valid(definitions) do return false
    if !recognizer_body_is_valid(sample.previous_body) || !recognizer_body_is_valid(sample.body) do return false
    values := [?]f32 {
        sample.pace,
        sample.ground_clearance,
        sample.authored_clearance,
        sample.recovery_margin,
        sample.delta_seconds,
        sample.intent.pitch,
        sample.intent.roll,
        sample.intent.yaw,
        sample.intent.throttle,
        sample.intent.flap_fraction,
        sample.ace_energy,
    }
    for value in values {
        if !recognizer_finite(value) do return false
    }
    if sample.has_ace_state && (sample.ace_energy < 0 || sample.ace_energy > 1) do return false
    return(
        sample.pace >= 0 &&
        sample.ground_clearance >= 0 &&
        (!sample.has_authored_clearance || sample.authored_clearance >= 0) &&
        (!sample.has_authored_clearance || sample.authored_risk_context_id != 0) &&
        sample.intent.pitch >= -1 &&
        sample.intent.pitch <= 1 &&
        sample.intent.roll >= -1 &&
        sample.intent.roll <= 1 &&
        sample.intent.yaw >= -1 &&
        sample.intent.yaw <= 1 &&
        sample.intent.throttle >= 0 &&
        sample.intent.throttle <= 1 &&
        sample.intent.flap_fraction >= 0 &&
        sample.intent.flap_fraction <= 1 &&
        sample.delta_seconds > 0 &&
        sample.delta_seconds <= definitions.maximum_delta_seconds \
    )
}

recognizer_heading :: proc(body: flight.Body_State) -> f32 {
    forward := flight.basis_from_orientation(body.orientation).forward
    return math.atan2(-forward.x, -forward.z)
}

recognizer_wrapped_angle :: proc(value: f32) -> f32 {
    return math.atan2(math.sin(value), math.cos(value))
}

recognizer_heading_error :: proc(current, target: f32) -> f32 {
    return math.abs(recognizer_wrapped_angle(current - target))
}

recognizer_opposite_heading_error :: proc(current, entry: f32) -> f32 {
    return math.abs(math.PI - recognizer_heading_error(current, entry))
}

recognizer_reached :: proc(value, target: f32) -> bool {
    return value + 1e-5 >= target
}

recognizer_track_angle :: proc(sample: Motion_Sample, basis: flight.Basis) -> f32 {
    speed_squared := linalg.dot(sample.body.velocity, sample.body.velocity)
    if speed_squared <= 1e-8 do return math.PI
    track := sample.body.velocity / math.sqrt(speed_squared)
    return math.acos(clamp(linalg.dot(track, basis.forward), -1, 1))
}

recognizer_knife_pose :: proc(sample: Motion_Sample, definitions: Definitions, basis: flight.Basis) -> bool {
    world_up := flight.Vec3{0, 1, 0}
    return(
        math.abs(linalg.dot(basis.up, world_up)) <= definitions.knife_up_alignment &&
        recognizer_track_angle(sample, basis) <= definitions.knife_track_angle \
    )
}

recognizer_upright :: proc(basis: flight.Basis) -> bool {
    return linalg.dot(basis.up, flight.Vec3{0, 1, 0}) >= .65
}

recognizer_inverted :: proc(basis: flight.Basis) -> bool {
    return linalg.dot(basis.up, flight.Vec3{0, 1, 0}) <= -.65
}

recognizer_next_id :: proc(recognizer: ^Recognizer) -> Gesture_ID {
    if recognizer.next_gesture_id == 0 do recognizer.next_gesture_id = 1
    result := recognizer.next_gesture_id
    recognizer.next_gesture_id += 1
    if recognizer.next_gesture_id == 0 do recognizer.next_gesture_id = 1
    return result
}

recognizer_begin_candidate :: proc(
    recognizer: ^Recognizer,
    kind: Maneuver_Kind,
    phase: Composite_Phase,
    completion_target: f32,
    sample: Motion_Sample,
) {
    candidate := Candidate {
        active = true,
        gesture_id = recognizer_next_id(recognizer),
        kind = kind,
        lifecycle = .Primed,
        phase = phase,
        completion_target = completion_target,
        composite_available = true,
        entry_heading = recognizer_heading(sample.previous_body),
        entry_altitude = sample.previous_body.position.y,
        minimum_altitude = min(sample.previous_body.position.y, sample.body.position.y),
        maximum_altitude = max(sample.previous_body.position.y, sample.body.position.y),
        phase_entry_altitude = sample.previous_body.position.y,
        phase_minimum_altitude = min(sample.previous_body.position.y, sample.body.position.y),
        risk = {
            minimum_ground_clearance = sample.ground_clearance,
            has_authored_clearance = sample.has_authored_clearance,
            minimum_authored_clearance = sample.authored_clearance,
            authored_risk_context_id = sample.authored_risk_context_id,
            minimum_recovery_margin = sample.recovery_margin,
        },
    }
    recognizer.candidate = candidate
}

recognizer_update_risk :: proc(
    candidate: ^Candidate,
    sample: Motion_Sample,
    definitions: Definitions,
    basis: flight.Basis,
) {
    dt := sample.delta_seconds
    candidate.risk.duration += dt
    candidate.risk.minimum_ground_clearance = min(candidate.risk.minimum_ground_clearance, sample.ground_clearance)
    candidate.risk_ground_clearance_seconds += sample.ground_clearance * dt
    candidate.risk_pace_seconds += sample.pace * dt
    candidate.risk.minimum_recovery_margin = min(candidate.risk.minimum_recovery_margin, sample.recovery_margin)
    if sample.has_authored_clearance {
        if !candidate.risk.has_authored_clearance {
            candidate.risk.has_authored_clearance = true
            candidate.risk.minimum_authored_clearance = sample.authored_clearance
            candidate.risk.authored_risk_context_id = sample.authored_risk_context_id
        } else {
            if sample.authored_clearance < candidate.risk.minimum_authored_clearance {
                candidate.risk.minimum_authored_clearance = sample.authored_clearance
                candidate.risk.authored_risk_context_id = sample.authored_risk_context_id
            }
        }
        candidate.risk_authored_clearance_seconds += sample.authored_clearance * dt
        candidate.risk_authored_seconds += dt
    }
    if sample.has_ace_state && sample.ace_energy < definitions.low_energy_risk_threshold {
        candidate.risk_low_energy_seconds += dt
    }
    up_alignment := linalg.dot(basis.up, flight.Vec3{0, 1, 0})
    if up_alignment < 0 do candidate.risk_inverted_seconds += dt
    if math.abs(up_alignment) <= definitions.knife_up_alignment {
        candidate.risk_knife_edge_seconds += dt
    }
    if sample.damaged do candidate.risk_damaged_seconds += dt
}

recognizer_finalize_risk :: proc(candidate: ^Candidate) {
    duration := max(candidate.risk.duration, f32(1e-6))
    candidate.risk.average_ground_clearance = candidate.risk_ground_clearance_seconds / duration
    candidate.risk.average_pace = candidate.risk_pace_seconds / duration
    candidate.risk.low_energy_fraction = clamp(candidate.risk_low_energy_seconds / duration, 0, 1)
    candidate.risk.inverted_fraction = clamp(candidate.risk_inverted_seconds / duration, 0, 1)
    candidate.risk.knife_edge_fraction = clamp(candidate.risk_knife_edge_seconds / duration, 0, 1)
    candidate.risk.damaged_fraction = clamp(candidate.risk_damaged_seconds / duration, 0, 1)
    if candidate.risk_authored_seconds > 0 {
        candidate.risk.average_authored_clearance =
            candidate.risk_authored_clearance_seconds / candidate.risk_authored_seconds
        candidate.risk.authored_exposure_fraction = clamp(candidate.risk_authored_seconds / duration, 0, 1)
    }
}

recognizer_primary_axis :: proc(candidate: ^Candidate) -> int {
    switch candidate.kind {
    case .Aileron_Roll:
        return 2
    case .Loop:
        return 0
    case .Knife_Edge:
        return 2
    case .Immelmann:
        if candidate.phase == .Roll_Upright do return 2
        return 0
    case .Split_S:
        if candidate.phase == .Descending_Half_Loop do return 0
        return 2
    case .None:
        return 0
    }
    return 0
}

recognizer_update_rotation :: proc(candidate: ^Candidate, local_rate: flight.Vec3, dt: f32) {
    delta := local_rate * dt
    candidate.signed_rotation += delta
    candidate.absolute_rotation += {math.abs(delta.x), math.abs(delta.y), math.abs(delta.z)}
    axis := recognizer_primary_axis(candidate)
    primary_delta := delta[axis]
    if math.abs(primary_delta) > 1e-6 {
        sign: f32 = 1
        if primary_delta < 0 do sign = -1
        if candidate.last_primary_sign != 0 && sign != candidate.last_primary_sign {
            candidate.correction_rotation += math.abs(primary_delta)
        }
        candidate.last_primary_sign = sign
    }
}

recognizer_event :: proc(
    candidate: ^Candidate,
    sample: Motion_Sample,
    lifecycle: Lifecycle,
    reason: Transition_Reason,
    failure: Failure_Reason = .None,
) -> Maneuver_Event {
    recognizer_finalize_risk(candidate)
    heading := recognizer_heading(sample.body)
    heading_error := recognizer_heading_error(heading, candidate.entry_heading)
    if candidate.kind == .Immelmann || candidate.kind == .Split_S {
        heading_error = recognizer_opposite_heading_error(heading, candidate.entry_heading)
    }
    primary_axis := recognizer_primary_axis(candidate)
    primary_rotation := candidate.absolute_rotation[primary_axis]
    completion: f32
    if candidate.completion_target > 0 {
        if candidate.kind == .Knife_Edge {
            if recognizer_reached(candidate.controlled_hold_seconds, candidate.completion_target) {
                completion = 1
            } else {
                completion = clamp(candidate.controlled_hold_seconds / candidate.completion_target, 0, 1)
            }
        } else if recognizer_reached(primary_rotation, candidate.completion_target) {
            completion = 1
        } else {
            completion = clamp(primary_rotation / candidate.completion_target, 0, 1)
        }
    }
    correction := clamp(candidate.correction_rotation / f32(math.PI), 0, 1)
    hold_quality: f32
    if candidate.duration > 0 {
        hold_quality = clamp(candidate.controlled_hold_seconds / candidate.duration, 0, 1)
    }
    return {
        gesture_id = candidate.gesture_id,
        kind = candidate.kind,
        lifecycle = lifecycle,
        transition_reason = reason,
        failure_reason = failure,
        signed_local_rotation = candidate.signed_rotation,
        absolute_local_rotation = candidate.absolute_rotation,
        duration = candidate.duration,
        entry_heading = candidate.entry_heading,
        exit_heading_error = heading_error,
        entry_altitude = candidate.entry_altitude,
        exit_altitude_error = sample.body.position.y - candidate.entry_altitude,
        hold_quality = hold_quality,
        completion = completion,
        continuity = 1 - correction,
        correction = correction,
        risk = candidate.risk,
    }
}

recognizer_transition :: proc(
    buffer: ^Event_Buffer,
    candidate: ^Candidate,
    sample: Motion_Sample,
    lifecycle: Lifecycle,
    reason: Transition_Reason,
) {
    candidate.lifecycle = lifecycle
    candidate.state_seconds = 0
    _ = event_buffer_push(buffer, recognizer_event(candidate, sample, lifecycle, reason))
}

recognizer_fail :: proc(
    buffer: ^Event_Buffer,
    recognizer: ^Recognizer,
    sample: Motion_Sample,
    reason: Transition_Reason,
    failure: Failure_Reason,
) {
    candidate := &recognizer.candidate
    _ = event_buffer_push(buffer, recognizer_event(candidate, sample, .Failed, reason, failure))
    recognizer.candidate = {}
}

recognizer_complete :: proc(buffer: ^Event_Buffer, recognizer: ^Recognizer, sample: Motion_Sample) {
    candidate := &recognizer.candidate
    _ = event_buffer_push(buffer, recognizer_event(candidate, sample, .Completed, .Controlled_Exit))
    recognizer.candidate = {}
}

recognizer_promote :: proc(
    buffer: ^Event_Buffer,
    candidate: ^Candidate,
    sample: Motion_Sample,
    kind: Maneuver_Kind,
    phase: Composite_Phase,
    reason: Transition_Reason,
    completion_target: f32,
) {
    candidate.kind = kind
    candidate.phase = phase
    candidate.phase_rotation_origin = candidate.signed_rotation
    candidate.completion_target = completion_target
    candidate.last_primary_sign = 0
    candidate.state_seconds = 0
    _ = event_buffer_push(buffer, recognizer_event(candidate, sample, candidate.lifecycle, reason))
}

recognizer_exit_is_controlled :: proc(
    candidate: ^Candidate,
    sample: Motion_Sample,
    definitions: Definitions,
    basis: flight.Basis,
    local_rate: flight.Vec3,
) -> bool {
    if linalg.length(local_rate) > definitions.exit_rate || !recognizer_upright(basis) do return false
    heading := recognizer_heading(sample.body)
    error := recognizer_heading_error(heading, candidate.entry_heading)
    if candidate.kind == .Immelmann || candidate.kind == .Split_S {
        error = recognizer_opposite_heading_error(heading, candidate.entry_heading)
    }
    if error > definitions.heading_exit_tolerance do return false
    if candidate.kind == .Aileron_Roll || candidate.kind == .Loop || candidate.kind == .Knife_Edge {
        altitude_error := math.abs(sample.body.position.y - candidate.entry_altitude)
        if altitude_error > definitions.altitude_exit_tolerance do return false
    }
    return true
}

recognizer_step_roll :: proc(
    buffer: ^Event_Buffer,
    recognizer: ^Recognizer,
    sample: Motion_Sample,
    definitions: Definitions,
    basis: flight.Basis,
    local_rate: flight.Vec3,
) {
    candidate := &recognizer.candidate
    roll := math.abs(candidate.signed_rotation.z)
    if candidate.lifecycle == .Primed && roll >= definitions.commitment_rotation {
        recognizer_transition(buffer, candidate, sample, .Committed, .Motion_Committed)
    }
    if candidate.phase == .None &&
       candidate.composite_available &&
       roll >= definitions.half_rotation &&
       recognizer_inverted(basis) {
        candidate.phase = .Roll_Inverted
        candidate.phase_rotation_origin = candidate.signed_rotation
        candidate.phase_entry_altitude = sample.body.position.y
        candidate.phase_minimum_altitude = sample.body.position.y
        candidate.state_seconds = 0
    }
    if candidate.phase == .Roll_Inverted {
        candidate.phase_minimum_altitude = min(candidate.phase_minimum_altitude, sample.body.position.y)
        pitch_since_inverted := math.abs(candidate.signed_rotation.x - candidate.phase_rotation_origin.x)
        descended := candidate.phase_entry_altitude - candidate.phase_minimum_altitude
        if pitch_since_inverted >= definitions.half_rotation &&
           descended >= definitions.composite_minimum_vertical_travel {
            recognizer_promote(
                buffer,
                candidate,
                sample,
                .Split_S,
                .Descending_Half_Loop,
                .Promoted_To_Split_S,
                definitions.half_rotation,
            )
            recognizer_transition(buffer, candidate, sample, .Recovering, .Rotation_Reached)
            return
        }
        if candidate.state_seconds > definitions.composite_phase_timeout_seconds {
            candidate.phase = .None
            candidate.composite_available = false
            candidate.state_seconds = 0
        }
    }
    if candidate.lifecycle == .Committed && roll >= definitions.full_rotation {
        recognizer_transition(buffer, candidate, sample, .Recovering, .Rotation_Reached)
    }
    if candidate.lifecycle == .Recovering {
        if recognizer_exit_is_controlled(candidate, sample, definitions, basis, local_rate) {
            candidate.exit_seconds += sample.delta_seconds
            if candidate.exit_seconds >= definitions.exit_hold_seconds {
                recognizer_complete(buffer, recognizer, sample)
            }
        } else {
            candidate.exit_seconds = 0
        }
    }
}

recognizer_step_loop :: proc(
    buffer: ^Event_Buffer,
    recognizer: ^Recognizer,
    sample: Motion_Sample,
    definitions: Definitions,
    basis: flight.Basis,
    local_rate: flight.Vec3,
) {
    candidate := &recognizer.candidate
    pitch := math.abs(candidate.signed_rotation.x)
    if candidate.lifecycle == .Primed && pitch >= definitions.commitment_rotation {
        recognizer_transition(buffer, candidate, sample, .Committed, .Motion_Committed)
    }
    climbed := candidate.maximum_altitude - candidate.entry_altitude
    if candidate.phase == .Pitch_Half_Loop &&
       pitch >= definitions.half_rotation &&
       climbed >= definitions.composite_minimum_vertical_travel &&
       sample.body.velocity.y <= definitions.composite_apex_vertical_speed {
        candidate.phase = .Roll_Upright
        candidate.phase_rotation_origin = candidate.signed_rotation
        candidate.last_primary_sign = 0
        candidate.state_seconds = 0
    }
    if candidate.phase == .Roll_Upright {
        roll_since_half := math.abs(candidate.signed_rotation.z - candidate.phase_rotation_origin.z)
        if roll_since_half >= definitions.half_rotation && recognizer_upright(basis) {
            recognizer_promote(
                buffer,
                candidate,
                sample,
                .Immelmann,
                .Roll_Upright,
                .Promoted_To_Immelmann,
                definitions.half_rotation,
            )
            recognizer_transition(buffer, candidate, sample, .Recovering, .Rotation_Reached)
            return
        }
        if candidate.state_seconds > definitions.composite_phase_timeout_seconds {
            candidate.phase = .None
            candidate.composite_available = false
            candidate.state_seconds = 0
        }
    }
    vertical_travel := candidate.maximum_altitude - candidate.minimum_altitude
    if candidate.lifecycle == .Committed &&
       pitch >= definitions.full_rotation &&
       vertical_travel >= definitions.composite_minimum_vertical_travel {
        recognizer_transition(buffer, candidate, sample, .Recovering, .Rotation_Reached)
    }
    if candidate.lifecycle == .Recovering {
        if recognizer_exit_is_controlled(candidate, sample, definitions, basis, local_rate) {
            candidate.exit_seconds += sample.delta_seconds
            if candidate.exit_seconds >= definitions.exit_hold_seconds {
                recognizer_complete(buffer, recognizer, sample)
            }
        } else {
            candidate.exit_seconds = 0
        }
    }
}

recognizer_step_knife :: proc(
    buffer: ^Event_Buffer,
    recognizer: ^Recognizer,
    sample: Motion_Sample,
    definitions: Definitions,
    basis: flight.Basis,
    local_rate: flight.Vec3,
) {
    candidate := &recognizer.candidate
    pose_is_controlled :=
        recognizer_knife_pose(sample, definitions, basis) && linalg.length(local_rate) <= definitions.exit_rate
    altitude_loss := candidate.entry_altitude - candidate.minimum_altitude
    if altitude_loss > definitions.knife_maximum_altitude_loss {
        recognizer_fail(buffer, recognizer, sample, .Uncontrolled_Exit, .Uncontrolled_Exit)
        return
    }
    if candidate.lifecycle == .Primed || candidate.lifecycle == .Committed {
        if pose_is_controlled {
            candidate.hold_seconds += sample.delta_seconds
            candidate.controlled_hold_seconds += sample.delta_seconds
            if candidate.lifecycle == .Primed &&
               recognizer_reached(candidate.hold_seconds, definitions.knife_minimum_hold_seconds * .2) {
                recognizer_transition(buffer, candidate, sample, .Committed, .Motion_Committed)
            }
            if candidate.lifecycle == .Committed &&
               recognizer_reached(candidate.hold_seconds, definitions.knife_minimum_hold_seconds) {
                recognizer_transition(buffer, candidate, sample, .Recovering, .Hold_Reached)
            }
        } else if candidate.hold_seconds < definitions.knife_minimum_hold_seconds {
            recognizer_fail(buffer, recognizer, sample, .Uncontrolled_Exit, .Uncontrolled_Exit)
            return
        }
    } else if candidate.lifecycle == .Recovering {
        if !recognizer_knife_pose(sample, definitions, basis) &&
           recognizer_exit_is_controlled(candidate, sample, definitions, basis, local_rate) {
            candidate.exit_seconds += sample.delta_seconds
            if candidate.exit_seconds >= definitions.exit_hold_seconds {
                recognizer_complete(buffer, recognizer, sample)
            }
        } else {
            candidate.exit_seconds = 0
        }
    }
}

recognize_step :: proc(recognizer: ^Recognizer, definitions: Definitions, sample: Motion_Sample) -> Event_Buffer {
    buffer: Event_Buffer
    if recognizer == nil || !motion_sample_is_valid(sample, definitions) do return buffer

    basis := flight.basis_from_orientation(sample.body.orientation)
    local_rate := flight.world_to_local(basis, sample.body.angular_velocity_world)
    candidate := &recognizer.candidate
    if !candidate.active {
        if sample.reset || sample.collision || sample.pace < definitions.minimum_pace do return buffer
        knife :=
            recognizer_knife_pose(sample, definitions, basis) && linalg.length(local_rate) <= definitions.exit_rate
        roll_dominant :=
            math.abs(local_rate.z) >= definitions.roll_prime_rate &&
            math.abs(local_rate.z) >= math.abs(local_rate.x) * definitions.dominance_ratio
        pitch_dominant :=
            math.abs(local_rate.x) >= definitions.pitch_prime_rate &&
            math.abs(local_rate.x) >= math.abs(local_rate.z) * definitions.dominance_ratio
        if knife {
            recognizer_begin_candidate(
                recognizer,
                .Knife_Edge,
                .Knife_Hold,
                definitions.knife_minimum_hold_seconds,
                sample,
            )
        } else if roll_dominant {
            recognizer_begin_candidate(recognizer, .Aileron_Roll, .None, definitions.full_rotation, sample)
        } else if pitch_dominant {
            recognizer_begin_candidate(recognizer, .Loop, .Pitch_Half_Loop, definitions.full_rotation, sample)
        } else {
            return buffer
        }
        candidate.duration = sample.delta_seconds
        candidate.state_seconds = sample.delta_seconds
        recognizer_update_rotation(candidate, local_rate, sample.delta_seconds)
        recognizer_update_risk(candidate, sample, definitions, basis)
        if candidate.kind == .Knife_Edge {
            candidate.hold_seconds = sample.delta_seconds
            candidate.controlled_hold_seconds = sample.delta_seconds
        }
        _ = event_buffer_push(&buffer, recognizer_event(&recognizer.candidate, sample, .Primed, .Motion_Primed))
        return buffer
    }

    candidate.duration += sample.delta_seconds
    candidate.state_seconds += sample.delta_seconds
    candidate.minimum_altitude = min(candidate.minimum_altitude, sample.body.position.y)
    candidate.maximum_altitude = max(candidate.maximum_altitude, sample.body.position.y)
    recognizer_update_rotation(candidate, local_rate, sample.delta_seconds)
    recognizer_update_risk(candidate, sample, definitions, basis)

    if sample.reset {
        recognizer_fail(&buffer, recognizer, sample, .Reset, .Reset)
        return buffer
    }
    if sample.collision {
        recognizer_fail(&buffer, recognizer, sample, .Collision, .Collision)
        return buffer
    }
    if candidate.correction_rotation > definitions.maximum_correction_rotation {
        recognizer_fail(&buffer, recognizer, sample, .Contradictory_Motion, .Contradictory_Motion)
        return buffer
    }
    if candidate.duration > definitions.candidate_timeout_seconds {
        recognizer_fail(&buffer, recognizer, sample, .Timeout, .Timeout)
        return buffer
    }
    switch candidate.kind {
    case .Aileron_Roll, .Split_S:
        recognizer_step_roll(&buffer, recognizer, sample, definitions, basis, local_rate)
    case .Loop, .Immelmann:
        recognizer_step_loop(&buffer, recognizer, sample, definitions, basis, local_rate)
    case .Knife_Edge:
        recognizer_step_knife(&buffer, recognizer, sample, definitions, basis, local_rate)
    case .None:
        recognizer.candidate = {}
    }
    return buffer
}
