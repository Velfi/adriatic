package air_style

import "core:math"

DEFINITIONS_VERSION :: u32(1)
SCORING_DEFINITIONS_VERSION :: u32(1)

Definitions :: struct {
    version:                           u32,
    maximum_delta_seconds:             f32,
    minimum_pace:                      f32,
    roll_prime_rate:                   f32,
    pitch_prime_rate:                  f32,
    dominance_ratio:                   f32,
    commitment_rotation:               f32,
    half_rotation:                     f32,
    full_rotation:                     f32,
    maximum_correction_rotation:       f32,
    exit_rate:                         f32,
    exit_hold_seconds:                 f32,
    candidate_timeout_seconds:         f32,
    heading_exit_tolerance:            f32,
    altitude_exit_tolerance:           f32,
    knife_up_alignment:                f32,
    knife_track_angle:                 f32,
    knife_minimum_hold_seconds:        f32,
    knife_maximum_altitude_loss:       f32,
    composite_phase_timeout_seconds:   f32,
    composite_minimum_vertical_travel: f32,
    composite_apex_vertical_speed:     f32,
    low_energy_risk_threshold:         f32,
}

default_definitions :: proc() -> Definitions {
    return {
        version = DEFINITIONS_VERSION,
        maximum_delta_seconds = .05,
        minimum_pace = 12,
        roll_prime_rate = .8,
        pitch_prime_rate = .65,
        dominance_ratio = 1.35,
        commitment_rotation = .65,
        half_rotation = f32(math.PI * .82),
        full_rotation = f32(math.PI * 1.78),
        maximum_correction_rotation = 1.2,
        exit_rate = .3,
        exit_hold_seconds = .2,
        candidate_timeout_seconds = 12,
        heading_exit_tolerance = .45,
        altitude_exit_tolerance = 30,
        knife_up_alignment = .28,
        knife_track_angle = .35,
        knife_minimum_hold_seconds = 1,
        knife_maximum_altitude_loss = 15,
        composite_phase_timeout_seconds = 2.5,
        composite_minimum_vertical_travel = 8,
        composite_apex_vertical_speed = 2,
        low_energy_risk_threshold = .35,
    }
}

definitions_are_valid :: proc(value: Definitions) -> bool {
    if value.version != DEFINITIONS_VERSION do return false
    values := [?]f32 {
        value.maximum_delta_seconds,
        value.minimum_pace,
        value.roll_prime_rate,
        value.pitch_prime_rate,
        value.dominance_ratio,
        value.commitment_rotation,
        value.half_rotation,
        value.full_rotation,
        value.maximum_correction_rotation,
        value.exit_rate,
        value.exit_hold_seconds,
        value.candidate_timeout_seconds,
        value.heading_exit_tolerance,
        value.altitude_exit_tolerance,
        value.knife_up_alignment,
        value.knife_track_angle,
        value.knife_minimum_hold_seconds,
        value.knife_maximum_altitude_loss,
        value.composite_phase_timeout_seconds,
        value.composite_minimum_vertical_travel,
        value.composite_apex_vertical_speed,
        value.low_energy_risk_threshold,
    }
    for item in values {
        if item != item || math.is_inf_f32(item) || item < 0 do return false
    }
    return(
        value.maximum_delta_seconds > 0 &&
        value.roll_prime_rate > 0 &&
        value.pitch_prime_rate > 0 &&
        value.dominance_ratio >= 1 &&
        value.commitment_rotation < value.half_rotation &&
        value.half_rotation < value.full_rotation &&
        value.candidate_timeout_seconds >=
            value.full_rotation / min(value.roll_prime_rate, value.pitch_prime_rate) + value.exit_hold_seconds &&
        value.composite_phase_timeout_seconds <= value.candidate_timeout_seconds &&
        value.low_energy_risk_threshold <= 1 &&
        value.knife_up_alignment <= 1 &&
        value.knife_track_angle <= math.PI \
    )
}

Scoring_Definitions :: struct {
    version:                       u32,
    maximum_delta_seconds:         f32,
    aileron_roll_value:            f32,
    loop_value:                    f32,
    knife_edge_value:              f32,
    immelmann_value:               f32,
    split_s_value:                 f32,
    heading_recovery_tolerance:    f32,
    altitude_recovery_tolerance:   f32,
    ground_close_clearance:        f32,
    ground_far_clearance:          f32,
    authored_close_clearance:      f32,
    authored_far_clearance:        f32,
    pace_risk_start:               f32,
    pace_risk_full:                f32,
    safe_recovery_margin:          f32,
    ground_risk_weight:            f32,
    authored_risk_weight:          f32,
    pace_risk_weight:              f32,
    low_energy_risk_weight:        f32,
    attitude_risk_weight:          f32,
    damage_risk_weight:            f32,
    recovery_margin_risk_weight:   f32,
    authored_context_reuse:        f32,
    first_repeat_variety:          f32,
    second_repeat_variety:         f32,
    third_repeat_variety:          f32,
    repeat_variety_decay:          f32,
    minimum_variety:               f32,
    context_variety_refresh:       f32,
    fourth_repeat_award_cap:       f32,
    safe_roll_risk_ceiling:        f32,
    safe_roll_reject_after:        int,
    flow_window_seconds:           f32,
    route_pause_grace_seconds:     f32,
    flow_multiplier:               f32,
    passive_rank_grace_seconds:    f32,
    passive_rank_decay_per_second: f32,
    rank_failure_loss:             f32,
    daring_rank_value:             f32,
    audacious_rank_value:          f32,
    ace_rank_value:                f32,
    legendary_rank_value:          f32,
}

DEFAULT_SCORING_DEFINITIONS :: Scoring_Definitions {
    version                       = SCORING_DEFINITIONS_VERSION,
    maximum_delta_seconds         = .05,
    aileron_roll_value            = 100,
    loop_value                    = 150,
    knife_edge_value              = 125,
    immelmann_value               = 200,
    split_s_value                 = 200,
    heading_recovery_tolerance    = .45,
    altitude_recovery_tolerance   = 30,
    ground_close_clearance        = 2,
    ground_far_clearance          = 50,
    authored_close_clearance      = .5,
    authored_far_clearance        = 12,
    pace_risk_start               = 25,
    pace_risk_full                = 80,
    safe_recovery_margin          = 25,
    ground_risk_weight            = .30,
    authored_risk_weight          = .25,
    pace_risk_weight              = .15,
    low_energy_risk_weight        = .08,
    attitude_risk_weight          = .08,
    damage_risk_weight            = .05,
    recovery_margin_risk_weight   = .03,
    authored_context_reuse        = .25,
    first_repeat_variety          = .70,
    second_repeat_variety         = .45,
    third_repeat_variety          = .25,
    repeat_variety_decay          = .5,
    minimum_variety               = .05,
    context_variety_refresh       = .05,
    fourth_repeat_award_cap       = .30,
    safe_roll_risk_ceiling        = 1.08,
    safe_roll_reject_after        = 3,
    flow_window_seconds           = 2,
    route_pause_grace_seconds     = .5,
    flow_multiplier               = 1.25,
    passive_rank_grace_seconds    = 3,
    passive_rank_decay_per_second = 40,
    rank_failure_loss             = 150,
    daring_rank_value             = 250,
    audacious_rank_value          = 600,
    ace_rank_value                = 1100,
    legendary_rank_value          = 1800,
}

default_scoring_definitions :: proc() -> Scoring_Definitions {
    return DEFAULT_SCORING_DEFINITIONS
}

scoring_definitions_are_valid :: proc(value: Scoring_Definitions) -> bool {
    if value.version != SCORING_DEFINITIONS_VERSION || value.safe_roll_reject_after < 1 {
        return false
    }
    values := [?]f32 {
        value.maximum_delta_seconds,
        value.aileron_roll_value,
        value.loop_value,
        value.knife_edge_value,
        value.immelmann_value,
        value.split_s_value,
        value.heading_recovery_tolerance,
        value.altitude_recovery_tolerance,
        value.ground_close_clearance,
        value.ground_far_clearance,
        value.authored_close_clearance,
        value.authored_far_clearance,
        value.pace_risk_start,
        value.pace_risk_full,
        value.safe_recovery_margin,
        value.ground_risk_weight,
        value.authored_risk_weight,
        value.pace_risk_weight,
        value.low_energy_risk_weight,
        value.attitude_risk_weight,
        value.damage_risk_weight,
        value.recovery_margin_risk_weight,
        value.authored_context_reuse,
        value.first_repeat_variety,
        value.second_repeat_variety,
        value.third_repeat_variety,
        value.repeat_variety_decay,
        value.minimum_variety,
        value.context_variety_refresh,
        value.fourth_repeat_award_cap,
        value.safe_roll_risk_ceiling,
        value.flow_window_seconds,
        value.route_pause_grace_seconds,
        value.flow_multiplier,
        value.passive_rank_grace_seconds,
        value.passive_rank_decay_per_second,
        value.rank_failure_loss,
        value.daring_rank_value,
        value.audacious_rank_value,
        value.ace_rank_value,
        value.legendary_rank_value,
    }
    for item in values {
        if item != item || math.is_inf_f32(item) || item < 0 do return false
    }
    return(
        value.maximum_delta_seconds > 0 &&
        value.aileron_roll_value > 0 &&
        value.loop_value > 0 &&
        value.knife_edge_value > 0 &&
        value.immelmann_value > 0 &&
        value.split_s_value > 0 &&
        value.heading_recovery_tolerance > 0 &&
        value.altitude_recovery_tolerance > 0 &&
        value.ground_close_clearance < value.ground_far_clearance &&
        value.authored_close_clearance < value.authored_far_clearance &&
        value.pace_risk_start < value.pace_risk_full &&
        value.safe_recovery_margin > 0 &&
        value.authored_context_reuse <= 1 &&
        value.first_repeat_variety <= 1 &&
        value.second_repeat_variety <= value.first_repeat_variety &&
        value.third_repeat_variety <= value.second_repeat_variety &&
        value.repeat_variety_decay <= 1 &&
        value.minimum_variety <= value.third_repeat_variety &&
        value.context_variety_refresh <= 1 - value.third_repeat_variety &&
        value.fourth_repeat_award_cap < 1.0 / 3.0 &&
        value.flow_multiplier >= 1 &&
        value.daring_rank_value < value.audacious_rank_value &&
        value.audacious_rank_value < value.ace_rank_value &&
        value.ace_rank_value < value.legendary_rank_value \
    )
}
