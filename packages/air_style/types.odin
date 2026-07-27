package air_style

import flight "../flight"

Gesture_ID :: distinct u64
Risk_Context_ID :: distinct u64

Maneuver_Kind :: enum {
    None,
    Aileron_Roll,
    Loop,
    Knife_Edge,
    Immelmann,
    Split_S,
}

Lifecycle :: enum {
    Idle,
    Primed,
    Committed,
    Recovering,
    Completed,
    Failed,
}

Transition_Reason :: enum {
    None,
    Motion_Primed,
    Motion_Committed,
    Rotation_Reached,
    Hold_Reached,
    Controlled_Exit,
    Promoted_To_Immelmann,
    Promoted_To_Split_S,
    Collision,
    Reset,
    Timeout,
    Contradictory_Motion,
    Uncontrolled_Exit,
}

Failure_Reason :: enum {
    None,
    Collision,
    Reset,
    Timeout,
    Contradictory_Motion,
    Uncontrolled_Exit,
}

Composite_Phase :: enum {
    None,
    Pitch_Half_Loop,
    Roll_Upright,
    Roll_Inverted,
    Descending_Half_Loop,
    Knife_Hold,
}

Motion_Sample :: struct {
    previous_body, body:       flight.Body_State,
    pace:                      f32,
    has_ace_state:             bool,
    ace_energy:                f32,
    ace_edge_state:            flight.Ace_Edge_State,
    intent:                    flight.Control_Command,
    ground_clearance:          f32,
    has_authored_clearance:    bool,
    authored_clearance:        f32,
    authored_risk_context_id:  Risk_Context_ID,
    recovery_margin:           f32,
    damaged, collision, reset: bool,
    delta_seconds:             f32,
}

Risk_Summary :: struct {
    duration:                   f32,
    minimum_ground_clearance:   f32,
    average_ground_clearance:   f32,
    has_authored_clearance:     bool,
    minimum_authored_clearance: f32,
    average_authored_clearance: f32,
    authored_exposure_fraction: f32,
    authored_risk_context_id:   Risk_Context_ID,
    average_pace:               f32,
    low_energy_fraction:        f32,
    inverted_fraction:          f32,
    knife_edge_fraction:        f32,
    damaged_fraction:           f32,
    minimum_recovery_margin:    f32,
}

Maneuver_Event :: struct {
    gesture_id:                                       Gesture_ID,
    kind:                                             Maneuver_Kind,
    lifecycle:                                        Lifecycle,
    transition_reason:                                Transition_Reason,
    failure_reason:                                   Failure_Reason,
    signed_local_rotation:                            flight.Vec3,
    absolute_local_rotation:                          flight.Vec3,
    duration:                                         f32,
    entry_heading, exit_heading_error:                f32,
    entry_altitude, exit_altitude_error:              f32,
    hold_quality, completion, continuity, correction: f32,
    risk:                                             Risk_Summary,
}

EVENT_BUFFER_CAPACITY :: 4

Event_Buffer :: struct {
    events: [EVENT_BUFFER_CAPACITY]Maneuver_Event,
    count:  int,
}

event_buffer_push :: proc(buffer: ^Event_Buffer, event: Maneuver_Event) -> bool {
    if buffer == nil || buffer.count >= len(buffer.events) do return false
    buffer.events[buffer.count] = event
    buffer.count += 1
    return true
}

Candidate :: struct {
    active:                                bool,
    gesture_id:                            Gesture_ID,
    kind:                                  Maneuver_Kind,
    lifecycle:                             Lifecycle,
    phase:                                 Composite_Phase,
    duration, state_seconds:               f32,
    signed_rotation, absolute_rotation:    flight.Vec3,
    correction_rotation:                   f32,
    phase_rotation_origin:                 flight.Vec3,
    completion_target:                     f32,
    entry_heading, entry_altitude:         f32,
    minimum_altitude, maximum_altitude:    f32,
    phase_entry_altitude:                  f32,
    phase_minimum_altitude:                f32,
    composite_available:                   bool,
    hold_seconds, controlled_hold_seconds: f32,
    exit_seconds:                          f32,
    last_primary_sign:                     f32,
    risk_pace_seconds:                     f32,
    risk_ground_clearance_seconds:         f32,
    risk_authored_clearance_seconds:       f32,
    risk_authored_seconds:                 f32,
    risk_low_energy_seconds:               f32,
    risk_inverted_seconds:                 f32,
    risk_knife_edge_seconds:               f32,
    risk_damaged_seconds:                  f32,
    risk:                                  Risk_Summary,
}

Recognizer :: struct {
    // One candidate owns one physical gesture. A pitch owner may replace Loop
    // with Immelmann only after a climbing half-loop followed by roll. A roll
    // owner may replace Aileron_Roll with Split_S only after reaching inverted
    // and then descending through pitch. Replacement keeps the gesture ID and
    // prevents the base maneuver from completing. Knife_Edge may own motion
    // only after a settled vertical-bank, controlled-track hold.
    next_gesture_id: Gesture_ID,
    candidate:       Candidate,
}
