package air_style

import "core:math"

SCORE_HISTORY_CAPACITY :: 8
SCORE_BREAKDOWN_CAPACITY :: EVENT_BUFFER_CAPACITY

Style_Rank :: enum {
    Composed,
    Daring,
    Audacious,
    Ace,
    Legendary,
}

Score_Outcome :: enum {
    None,
    Pending,
    Banked,
    Lost,
    Rejected,
}

Rejection_Reason :: enum {
    None,
    Invalid_Input,
    Invalid_Event,
    Out_Of_Order,
    Duplicate_Gesture,
    No_Pending,
    Uncontrolled_Exit,
    Safe_Repetition_Farm,
    Post_Failure_Completion,
}

History_Entry :: struct {
    gesture_id:               Gesture_ID,
    kind:                     Maneuver_Kind,
    authored_risk_context_id: Risk_Context_ID,
    awarded_value:            f32,
}

Pending_Maneuver :: struct {
    active:          bool,
    gesture_id:      Gesture_ID,
    kind:            Maneuver_Kind,
    lifecycle:       Lifecycle,
    base_value:      f32,
    flow_multiplier: f32,
    pending_value:   f32,
}

Score_State :: struct {
    pending:                   Pending_Maneuver,
    banked_run_score:          f32,
    combo_count:               u32,
    history:                   [SCORE_HISTORY_CAPACITY]History_Entry,
    history_count:             int,
    flow_seconds_remaining:    f32,
    route_pause_seconds:       f32,
    passive_seconds:           f32,
    rank_value:                f32,
    rank:                      Style_Rank,
    has_processed_gesture:     bool,
    last_processed_gesture_id: Gesture_ID,
    last_terminal_failed:      bool,
}

Score_Input :: struct {
    delta_seconds:    f32,
    route_continuing: bool,
    events:           Event_Buffer,
}

Execution_Breakdown :: struct {
    completion:         f32,
    exit_control:       f32,
    heading_recovery:   f32,
    altitude_recovery:  f32,
    continuity:         f32,
    correction_control: f32,
    multiplier:         f32,
}

Risk_Breakdown :: struct {
    ground:                     f32,
    authored:                   f32,
    pace:                       f32,
    low_energy:                 f32,
    attitude:                   f32,
    damage:                     f32,
    recovery_margin:            f32,
    authored_context_freshness: f32,
    multiplier:                 f32,
    reused_authored_context:    bool,
}

Score_Breakdown :: struct {
    gesture_id:                    Gesture_ID,
    kind:                          Maneuver_Kind,
    lifecycle:                     Lifecycle,
    outcome:                       Score_Outcome,
    rejection:                     Rejection_Reason,
    base_value:                    f32,
    execution:                     Execution_Breakdown,
    risk:                          Risk_Breakdown,
    repeat_count:                  int,
    variety_multiplier:            f32,
    repeat_award_cap:              f32,
    flow_multiplier:               f32,
    pending_before, pending_after: f32,
    awarded_value:                 f32,
    banked_delta:                  f32,
    rank_before, rank_after:       f32,
}

Score_Result :: struct {
    breakdowns: [SCORE_BREAKDOWN_CAPACITY]Score_Breakdown,
    count:      int,
}

score_finite :: proc(value: f32) -> bool {
    return value == value && !math.is_inf_f32(value)
}

score_finite_vector :: proc(value: [3]f32) -> bool {
    return score_finite(value.x) && score_finite(value.y) && score_finite(value.z)
}

score_rank_for_value :: proc(value: f32, definitions: Scoring_Definitions) -> Style_Rank {
    if value >= definitions.legendary_rank_value do return .Legendary
    if value >= definitions.ace_rank_value do return .Ace
    if value >= definitions.audacious_rank_value do return .Audacious
    if value >= definitions.daring_rank_value do return .Daring
    return .Composed
}

score_state_is_valid :: proc(state: Score_State, definitions := DEFAULT_SCORING_DEFINITIONS) -> bool {
    if !scoring_definitions_are_valid(definitions) ||
       state.history_count < 0 ||
       state.history_count > len(state.history) ||
       !score_finite(state.banked_run_score) ||
       !score_finite(state.flow_seconds_remaining) ||
       !score_finite(state.route_pause_seconds) ||
       !score_finite(state.passive_seconds) ||
       !score_finite(state.rank_value) ||
       state.banked_run_score < 0 ||
       state.flow_seconds_remaining < 0 ||
       state.route_pause_seconds < 0 ||
       state.passive_seconds < 0 ||
       state.rank_value < 0 ||
       state.rank != score_rank_for_value(state.rank_value, definitions) {
        return false
    }
    if state.has_processed_gesture && state.last_processed_gesture_id == 0 do return false
    if state.last_terminal_failed && !state.has_processed_gesture do return false
    if state.pending.active {
        if state.pending.gesture_id == 0 ||
           state.pending.kind == .None ||
           (state.pending.lifecycle != .Primed &&
                   state.pending.lifecycle != .Committed &&
                   state.pending.lifecycle != .Recovering) ||
           !score_finite(state.pending.base_value) ||
           !score_finite(state.pending.flow_multiplier) ||
           !score_finite(state.pending.pending_value) ||
           state.pending.base_value <= 0 ||
           state.pending.flow_multiplier < 1 ||
           state.pending.pending_value < 0 {
            return false
        }
    } else if state.pending != (Pending_Maneuver{}) {
        return false
    }
    for index in 0 ..< state.history_count {
        entry := state.history[index]
        if entry.gesture_id == 0 ||
           entry.kind == .None ||
           !score_finite(entry.awarded_value) ||
           entry.awarded_value < 0 {
            return false
        }
    }
    return true
}

score_event_is_valid :: proc(event: Maneuver_Event) -> bool {
    if event.gesture_id == 0 || event.kind == .None do return false
    if event.lifecycle == .Failed {
        if event.failure_reason == .None do return false
    } else if event.failure_reason != .None {
        return false
    }
    values := [?]f32 {
        event.duration,
        event.entry_heading,
        event.exit_heading_error,
        event.entry_altitude,
        event.exit_altitude_error,
        event.hold_quality,
        event.completion,
        event.continuity,
        event.correction,
        event.risk.duration,
        event.risk.minimum_ground_clearance,
        event.risk.average_ground_clearance,
        event.risk.minimum_authored_clearance,
        event.risk.average_authored_clearance,
        event.risk.authored_exposure_fraction,
        event.risk.average_pace,
        event.risk.low_energy_fraction,
        event.risk.inverted_fraction,
        event.risk.knife_edge_fraction,
        event.risk.damaged_fraction,
        event.risk.minimum_recovery_margin,
    }
    for value in values {
        if !score_finite(value) do return false
    }
    if !score_finite_vector(event.signed_local_rotation) ||
       !score_finite_vector(event.absolute_local_rotation) ||
       event.duration < 0 ||
       event.exit_heading_error < 0 ||
       event.hold_quality < 0 ||
       event.hold_quality > 1 ||
       event.completion < 0 ||
       event.completion > 1 ||
       event.continuity < 0 ||
       event.continuity > 1 ||
       event.correction < 0 ||
       event.correction > 1 ||
       event.risk.duration < 0 ||
       event.risk.minimum_ground_clearance < 0 ||
       event.risk.average_ground_clearance < 0 ||
       event.risk.average_pace < 0 ||
       event.risk.authored_exposure_fraction < 0 ||
       event.risk.authored_exposure_fraction > 1 ||
       event.risk.low_energy_fraction < 0 ||
       event.risk.low_energy_fraction > 1 ||
       event.risk.inverted_fraction < 0 ||
       event.risk.inverted_fraction > 1 ||
       event.risk.knife_edge_fraction < 0 ||
       event.risk.knife_edge_fraction > 1 ||
       event.risk.damaged_fraction < 0 ||
       event.risk.damaged_fraction > 1 {
        return false
    }
    if event.absolute_local_rotation.x < 0 ||
       event.absolute_local_rotation.y < 0 ||
       event.absolute_local_rotation.z < 0 {
        return false
    }
    if event.risk.has_authored_clearance {
        if event.risk.authored_risk_context_id == 0 ||
           event.risk.minimum_authored_clearance < 0 ||
           event.risk.average_authored_clearance < 0 {
            return false
        }
    } else if event.risk.authored_risk_context_id != 0 {
        return false
    }
    return true
}

score_base_value :: proc(kind: Maneuver_Kind, definitions: Scoring_Definitions) -> f32 {
    switch kind {
    case .Aileron_Roll:
        return definitions.aileron_roll_value
    case .Loop:
        return definitions.loop_value
    case .Knife_Edge:
        return definitions.knife_edge_value
    case .Immelmann:
        return definitions.immelmann_value
    case .Split_S:
        return definitions.split_s_value
    case .None:
        return 0
    }
    return 0
}

score_kind_can_prime :: proc(kind: Maneuver_Kind) -> bool {
    return kind == .Aileron_Roll || kind == .Loop || kind == .Knife_Edge
}

score_inverse_range :: proc(value, close, far: f32) -> f32 {
    return 1 - clamp((value - close) / (far - close), 0, 1)
}

score_execution :: proc(event: Maneuver_Event, definitions: Scoring_Definitions) -> Execution_Breakdown {
    result := Execution_Breakdown {
        completion         = clamp(event.completion, 0, 1),
        heading_recovery   = 1 - clamp(event.exit_heading_error / definitions.heading_recovery_tolerance, 0, 1),
        continuity         = clamp(event.continuity, 0, 1),
        correction_control = 1 - clamp(event.correction, 0, 1),
    }
    if event.lifecycle == .Completed && event.transition_reason == .Controlled_Exit && event.failure_reason == .None {
        result.exit_control = 1
    }
    if event.kind == .Immelmann || event.kind == .Split_S {
        result.altitude_recovery = 1
    } else {
        result.altitude_recovery =
            1 - clamp(math.abs(event.exit_altitude_error) / definitions.altitude_recovery_tolerance, 0, 1)
    }
    result.multiplier =
        result.completion * .25 +
        result.exit_control * .25 +
        result.heading_recovery * .15 +
        result.altitude_recovery * .10 +
        result.continuity * .15 +
        result.correction_control * .10
    return result
}

score_same_context_count :: proc(state: Score_State, context_id: Risk_Context_ID) -> int {
    if context_id == 0 do return 0
    count := 0
    for index in 0 ..< state.history_count {
        if state.history[index].authored_risk_context_id == context_id do count += 1
    }
    return count
}

score_risk :: proc(state: Score_State, event: Maneuver_Event, definitions: Scoring_Definitions) -> Risk_Breakdown {
    result: Risk_Breakdown
    result.ground = score_inverse_range(
        event.risk.average_ground_clearance,
        definitions.ground_close_clearance,
        definitions.ground_far_clearance,
    )
    if event.risk.has_authored_clearance {
        context_count := score_same_context_count(state, event.risk.authored_risk_context_id)
        result.authored_context_freshness = 1
        if context_count == 1 {
            result.authored_context_freshness = definitions.authored_context_reuse
            result.reused_authored_context = true
        } else if context_count >= 2 {
            result.authored_context_freshness = 0
            result.reused_authored_context = true
        }
        result.authored =
            score_inverse_range(
                event.risk.average_authored_clearance,
                definitions.authored_close_clearance,
                definitions.authored_far_clearance,
            ) *
            event.risk.authored_exposure_fraction *
            result.authored_context_freshness
    }
    result.pace = clamp(
        (event.risk.average_pace - definitions.pace_risk_start) /
        (definitions.pace_risk_full - definitions.pace_risk_start),
        0,
        1,
    )
    result.low_energy = event.risk.low_energy_fraction
    result.attitude = max(event.risk.inverted_fraction, event.risk.knife_edge_fraction)
    result.damage = event.risk.damaged_fraction
    result.recovery_margin = 1 - clamp(event.risk.minimum_recovery_margin / definitions.safe_recovery_margin, 0, 1)
    result.multiplier =
        1 +
        result.ground * definitions.ground_risk_weight +
        result.authored * definitions.authored_risk_weight +
        result.pace * definitions.pace_risk_weight +
        result.low_energy * definitions.low_energy_risk_weight +
        result.attitude * definitions.attitude_risk_weight +
        result.damage * definitions.damage_risk_weight +
        result.recovery_margin * definitions.recovery_margin_risk_weight
    return result
}

score_repeat_state :: proc(
    state: Score_State,
    kind: Maneuver_Kind,
) -> (
    repeat_count: int,
    anchor_value: f32,
    last_context: Risk_Context_ID,
) {
    index := state.history_count - 1
    for index >= 0 {
        entry := state.history[index]
        if entry.kind != kind do break
        if repeat_count == 0 do last_context = entry.authored_risk_context_id
        repeat_count += 1
        anchor_value = entry.awarded_value
        index -= 1
    }
    return
}

score_variety :: proc(
    repeat_count: int,
    last_context, context_id: Risk_Context_ID,
    definitions: Scoring_Definitions,
) -> f32 {
    result: f32 = 1
    switch repeat_count {
    case 0:
        result = 1
    case 1:
        result = definitions.first_repeat_variety
    case 2:
        result = definitions.second_repeat_variety
    case:
        result = definitions.third_repeat_variety
        remaining := repeat_count - 3
        for remaining > 0 {
            result *= definitions.repeat_variety_decay
            remaining -= 1
        }
        result = max(result, definitions.minimum_variety)
    }
    if repeat_count > 0 && last_context != 0 && context_id != 0 && last_context != context_id {
        result = min(result + definitions.context_variety_refresh, 1)
    }
    return result
}

score_append_history :: proc(state: ^Score_State, entry: History_Entry) {
    if state.history_count < len(state.history) {
        state.history[state.history_count] = entry
        state.history_count += 1
        return
    }
    for index in 0 ..< len(state.history) - 1 {
        state.history[index] = state.history[index + 1]
    }
    state.history[len(state.history) - 1] = entry
}

score_update_rank :: proc(state: ^Score_State, definitions: Scoring_Definitions) {
    state.rank_value = max(state.rank_value, 0)
    state.rank = score_rank_for_value(state.rank_value, definitions)
}

score_clear_flow :: proc(state: ^Score_State) {
    state.combo_count = 0
    state.flow_seconds_remaining = 0
    state.route_pause_seconds = 0
}

score_mark_terminal :: proc(state: ^Score_State, gesture_id: Gesture_ID, failed: bool) {
    state.has_processed_gesture = true
    state.last_processed_gesture_id = gesture_id
    state.last_terminal_failed = failed
    state.pending = {}
}

score_reset_flight :: proc(state: ^Score_State, definitions: Scoring_Definitions = DEFAULT_SCORING_DEFINITIONS) {
    if state == nil do return
    if !scoring_definitions_are_valid(definitions) do return
    if state.pending.active {
        gesture_id := state.pending.gesture_id
        state.rank_value = max(0, state.rank_value - definitions.rank_failure_loss)
        score_mark_terminal(state, gesture_id, true)
    }
    score_clear_flow(state)
    state.passive_seconds = 0
    score_update_rank(state, definitions)
}

score_reset_run :: proc(state: ^Score_State) {
    if state == nil do return
    state^ = {}
}

score_result_push :: proc(result: ^Score_Result, breakdown: Score_Breakdown) {
    if result.count >= len(result.breakdowns) do return
    result.breakdowns[result.count] = breakdown
    result.count += 1
}

score_rejection :: proc(event: Maneuver_Event, reason: Rejection_Reason, state: Score_State) -> Score_Breakdown {
    return {
        gesture_id = event.gesture_id,
        kind = event.kind,
        lifecycle = event.lifecycle,
        outcome = .Rejected,
        rejection = reason,
        pending_before = state.pending.pending_value,
        pending_after = state.pending.pending_value,
        rank_before = state.rank_value,
        rank_after = state.rank_value,
    }
}

score_terminal_order_rejection :: proc(state: Score_State, event: Maneuver_Event) -> (Rejection_Reason, bool) {
    if !state.has_processed_gesture do return .None, false
    if event.gesture_id == state.last_processed_gesture_id {
        if event.lifecycle == .Completed && state.last_terminal_failed {
            return .Post_Failure_Completion, true
        }
        return .Duplicate_Gesture, true
    }
    if u64(event.gesture_id) < u64(state.last_processed_gesture_id) {
        return .Out_Of_Order, true
    }
    return .None, false
}

score_is_promotion :: proc(pending: Pending_Maneuver, event: Maneuver_Event) -> bool {
    if pending.lifecycle != .Committed || event.lifecycle != .Committed do return false
    if pending.kind == .Aileron_Roll && event.kind == .Split_S && event.transition_reason == .Promoted_To_Split_S {
        return true
    }
    return pending.kind == .Loop && event.kind == .Immelmann && event.transition_reason == .Promoted_To_Immelmann
}

score_failure_is_explained :: proc(event: Maneuver_Event) -> bool {
    switch event.failure_reason {
    case .Collision:
        return event.transition_reason == .Collision
    case .Reset:
        return event.transition_reason == .Reset
    case .Timeout:
        return event.transition_reason == .Timeout
    case .Contradictory_Motion:
        return event.transition_reason == .Contradictory_Motion
    case .Uncontrolled_Exit:
        return event.transition_reason == .Uncontrolled_Exit
    case .None:
        return false
    }
    return false
}

score_components :: proc(
    state: Score_State,
    event: Maneuver_Event,
    definitions: Scoring_Definitions,
) -> (
    execution: Execution_Breakdown,
    risk: Risk_Breakdown,
    repeat_count: int,
    anchor_value: f32,
    variety: f32,
) {
    execution = score_execution(event, definitions)
    risk = score_risk(state, event, definitions)
    last_context: Risk_Context_ID
    repeat_count, anchor_value, last_context = score_repeat_state(state, event.kind)
    variety = score_variety(repeat_count, last_context, event.risk.authored_risk_context_id, definitions)
    return
}

score_advance_time :: proc(
    state: ^Score_State,
    definitions: Scoring_Definitions,
    input: Score_Input,
    accepted_event_tick: bool,
) {
    previous_flow := state.flow_seconds_remaining
    state.flow_seconds_remaining = max(0, state.flow_seconds_remaining - input.delta_seconds)
    if state.flow_seconds_remaining > 0 {
        if input.route_continuing {
            state.route_pause_seconds = 0
        } else {
            state.route_pause_seconds += input.delta_seconds
            if state.route_pause_seconds > definitions.route_pause_grace_seconds {
                state.flow_seconds_remaining = 0
                state.route_pause_seconds = 0
            }
        }
    } else {
        state.route_pause_seconds = 0
    }
    if previous_flow > 0 && state.flow_seconds_remaining == 0 {
        state.combo_count = 0
    }

    if !accepted_event_tick && !state.pending.active {
        previous_passive := state.passive_seconds
        state.passive_seconds += input.delta_seconds
        previous_decay_seconds := max(previous_passive - definitions.passive_rank_grace_seconds, f32(0))
        decay_seconds :=
            max(state.passive_seconds - definitions.passive_rank_grace_seconds, f32(0)) - previous_decay_seconds
        if decay_seconds > 0 {
            state.rank_value = max(0, state.rank_value - definitions.passive_rank_decay_per_second * decay_seconds)
        }
    }
    score_update_rank(state, definitions)
}

score_step_internal :: proc(
    state: ^Score_State,
    definitions: Scoring_Definitions,
    input: Score_Input,
    advance_time: bool,
    accepted_event_tick: bool,
) -> Score_Result {
    result: Score_Result
    if state == nil ||
       !score_state_is_valid(state^, definitions) ||
       !score_finite(input.delta_seconds) ||
       input.delta_seconds <= 0 ||
       input.delta_seconds > definitions.maximum_delta_seconds ||
       input.events.count < 0 ||
       input.events.count > len(input.events.events) {
        breakdown: Score_Breakdown
        breakdown.outcome = .Rejected
        breakdown.rejection = .Invalid_Input
        score_result_push(&result, breakdown)
        return result
    }
    for event_index in 0 ..< input.events.count {
        event := input.events.events[event_index]
        if !score_event_is_valid(event) {
            score_result_push(&result, score_rejection(event, .Invalid_Event, state^))
            return result
        }
    }

    if advance_time {
        score_advance_time(state, definitions, input, accepted_event_tick)
    }
    for event_index in 0 ..< input.events.count {
        event := input.events.events[event_index]
        order_reason, rejected := score_terminal_order_rejection(state^, event)
        if rejected {
            score_result_push(&result, score_rejection(event, order_reason, state^))
            continue
        }

        pending_before := state.pending.pending_value
        rank_before := state.rank_value
        breakdown := Score_Breakdown {
            gesture_id     = event.gesture_id,
            kind           = event.kind,
            lifecycle      = event.lifecycle,
            pending_before = pending_before,
            rank_before    = rank_before,
        }

        switch event.lifecycle {
        case .Primed:
            if event.transition_reason != .Motion_Primed ||
               event.failure_reason != .None ||
               !score_kind_can_prime(event.kind) {
                breakdown = score_rejection(event, .Invalid_Event, state^)
            } else if state.pending.active {
                reason := Rejection_Reason.Out_Of_Order
                if state.pending.gesture_id == event.gesture_id {
                    reason = .Duplicate_Gesture
                }
                breakdown = score_rejection(event, reason, state^)
            } else {
                flow_multiplier: f32 = 1
                if state.flow_seconds_remaining > 0 {
                    flow_multiplier = definitions.flow_multiplier
                }
                state.pending = {
                    active          = true,
                    gesture_id      = event.gesture_id,
                    kind            = event.kind,
                    lifecycle       = .Primed,
                    base_value      = score_base_value(event.kind, definitions),
                    flow_multiplier = flow_multiplier,
                }
                state.passive_seconds = 0
                breakdown.outcome = .Pending
                breakdown.base_value = state.pending.base_value
                breakdown.flow_multiplier = flow_multiplier
            }

        case .Committed:
            if !state.pending.active {
                breakdown = score_rejection(event, .No_Pending, state^)
            } else if state.pending.gesture_id != event.gesture_id {
                breakdown = score_rejection(event, .Out_Of_Order, state^)
            } else {
                promotion := score_is_promotion(state.pending, event)
                ordinary_commit :=
                    state.pending.lifecycle == .Primed &&
                    state.pending.kind == event.kind &&
                    event.transition_reason == .Motion_Committed
                if !promotion && !ordinary_commit {
                    reason := Rejection_Reason.Out_Of_Order
                    if state.pending.lifecycle == .Committed && state.pending.kind == event.kind {
                        reason = .Duplicate_Gesture
                    }
                    breakdown = score_rejection(event, reason, state^)
                } else {
                    repeat_count, _, last_context := score_repeat_state(state^, event.kind)
                    variety := score_variety(
                        repeat_count,
                        last_context,
                        event.risk.authored_risk_context_id,
                        definitions,
                    )
                    state.pending.kind = event.kind
                    state.pending.lifecycle = .Committed
                    state.pending.base_value = score_base_value(event.kind, definitions)
                    state.pending.pending_value = state.pending.base_value * variety * state.pending.flow_multiplier
                    state.passive_seconds = 0
                    breakdown.outcome = .Pending
                    breakdown.base_value = state.pending.base_value
                    breakdown.repeat_count = repeat_count
                    breakdown.variety_multiplier = variety
                    breakdown.flow_multiplier = state.pending.flow_multiplier
                }
            }

        case .Recovering:
            if !state.pending.active {
                breakdown = score_rejection(event, .No_Pending, state^)
            } else if state.pending.gesture_id != event.gesture_id ||
               state.pending.kind != event.kind ||
               state.pending.lifecycle != .Committed {
                breakdown = score_rejection(event, .Out_Of_Order, state^)
            } else if event.transition_reason != .Rotation_Reached && event.transition_reason != .Hold_Reached {
                breakdown = score_rejection(event, .Invalid_Event, state^)
            } else {
                execution, risk, repeat_count, anchor, variety := score_components(state^, event, definitions)
                state.pending.lifecycle = .Recovering
                state.pending.pending_value =
                    state.pending.base_value *
                    execution.multiplier *
                    risk.multiplier *
                    variety *
                    state.pending.flow_multiplier
                state.passive_seconds = 0
                breakdown.outcome = .Pending
                breakdown.base_value = state.pending.base_value
                breakdown.execution = execution
                breakdown.risk = risk
                breakdown.repeat_count = repeat_count
                breakdown.variety_multiplier = variety
                breakdown.repeat_award_cap = anchor * definitions.fourth_repeat_award_cap
                breakdown.flow_multiplier = state.pending.flow_multiplier
            }

        case .Completed:
            if !state.pending.active {
                reason := Rejection_Reason.No_Pending
                if state.has_processed_gesture && event.gesture_id == state.last_processed_gesture_id {
                    reason = .Post_Failure_Completion
                }
                breakdown = score_rejection(event, reason, state^)
            } else if state.pending.gesture_id != event.gesture_id ||
               state.pending.kind != event.kind ||
               state.pending.lifecycle != .Recovering {
                breakdown = score_rejection(event, .Out_Of_Order, state^)
            } else {
                execution, risk, repeat_count, anchor, variety := score_components(state^, event, definitions)
                breakdown.base_value = state.pending.base_value
                breakdown.execution = execution
                breakdown.risk = risk
                breakdown.repeat_count = repeat_count
                breakdown.variety_multiplier = variety
                breakdown.flow_multiplier = state.pending.flow_multiplier
                breakdown.repeat_award_cap = anchor * definitions.fourth_repeat_award_cap
                if execution.exit_control == 0 {
                    breakdown.outcome = .Lost
                    breakdown.rejection = .Uncontrolled_Exit
                    score_clear_flow(state)
                    state.rank_value = max(0, state.rank_value - definitions.rank_failure_loss)
                    score_mark_terminal(state, event.gesture_id, true)
                } else {
                    award :=
                        state.pending.base_value *
                        execution.multiplier *
                        risk.multiplier *
                        variety *
                        state.pending.flow_multiplier
                    if repeat_count >= 3 && anchor > 0 {
                        award = min(award, anchor * definitions.fourth_repeat_award_cap)
                    }
                    safe_roll_farm :=
                        event.kind == .Aileron_Roll &&
                        repeat_count >= definitions.safe_roll_reject_after &&
                        risk.multiplier <= definitions.safe_roll_risk_ceiling
                    state.rank_value = max(0, state.rank_value - state.pending.base_value * (1 - variety))
                    history_entry := History_Entry {
                        gesture_id               = event.gesture_id,
                        kind                     = event.kind,
                        authored_risk_context_id = event.risk.authored_risk_context_id,
                    }
                    if safe_roll_farm {
                        breakdown.outcome = .Rejected
                        breakdown.rejection = .Safe_Repetition_Farm
                        score_clear_flow(state)
                    } else {
                        history_entry.awarded_value = award
                        state.banked_run_score += award
                        state.combo_count += 1
                        state.flow_seconds_remaining = definitions.flow_window_seconds
                        state.route_pause_seconds = 0
                        state.rank_value += award
                        breakdown.outcome = .Banked
                        breakdown.awarded_value = award
                        breakdown.banked_delta = award
                    }
                    score_append_history(state, history_entry)
                    score_mark_terminal(state, event.gesture_id, false)
                }
                score_update_rank(state, definitions)
            }

        case .Failed:
            if !state.pending.active {
                breakdown = score_rejection(event, .No_Pending, state^)
            } else if state.pending.gesture_id != event.gesture_id || state.pending.kind != event.kind {
                breakdown = score_rejection(event, .Out_Of_Order, state^)
            } else if !score_failure_is_explained(event) {
                breakdown = score_rejection(event, .Invalid_Event, state^)
            } else {
                breakdown.outcome = .Lost
                breakdown.base_value = state.pending.base_value
                score_clear_flow(state)
                state.rank_value = max(0, state.rank_value - definitions.rank_failure_loss)
                score_mark_terminal(state, event.gesture_id, true)
                score_update_rank(state, definitions)
            }

        case .Idle:
            breakdown = score_rejection(event, .Invalid_Event, state^)
        }

        breakdown.pending_after = state.pending.pending_value
        breakdown.rank_after = state.rank_value
        score_result_push(&result, breakdown)
    }
    return result
}

score_step :: proc(state: ^Score_State, definitions: Scoring_Definitions, input: Score_Input) -> Score_Result {
    if state == nil {
        return score_step_internal(state, definitions, input, false, false)
    }
    probe := state^
    probe_result := score_step_internal(&probe, definitions, input, false, false)
    accepted_event_tick := false
    for index in 0 ..< probe_result.count {
        breakdown := probe_result.breakdowns[index]
        if breakdown.outcome != .Rejected || breakdown.rejection == .Safe_Repetition_Farm {
            accepted_event_tick = true
            break
        }
    }
    return score_step_internal(state, definitions, input, true, accepted_event_tick)
}
