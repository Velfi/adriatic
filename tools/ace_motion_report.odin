package main

import air_compare "../packages/air_compare"
import flight "../packages/flight"
import postale "../packages/postale"
import "core:fmt"
import "core:math"
import "core:math/linalg"

model_label :: proc(model: postale.Flight_Model) -> string {
    switch model {
    case .Current_Aero:
        return "Current_Aero"
    case .Ace_Arcade:
        return "Ace_Arcade"
    }
    return "Invalid"
}

print_tuning :: proc() {
    tuning := postale.ace_tuning_preset()
    derived := flight.derive_ace_tuning(tuning)
    fmt.println("ACE TUNING")
    fmt.printf(
        "knobs pace=%.2f punch=%.2f coast=%.2f brake=%.2f roll_snap=%.2f pull_strength=%.2f rudder_bite=%.2f weight=%.2f settle=%.2f air_grip=%.2f drift=%.2f turn_hold=%.2f climb_generosity=%.2f dive_payoff=%.2f hang_time=%.2f break_drama=%.2f recovery_punch=%.2f low_speed_authority=%.2f steadiness=%.2f line_hold=%.2f commitment=%.2f exit_catch=%.2f\n",
        tuning.pace,
        tuning.punch,
        tuning.coast,
        tuning.brake,
        tuning.roll_snap,
        tuning.pull_strength,
        tuning.rudder_bite,
        tuning.weight,
        tuning.settle,
        tuning.air_grip,
        tuning.drift,
        tuning.turn_hold,
        tuning.climb_generosity,
        tuning.dive_payoff,
        tuning.hang_time,
        tuning.break_drama,
        tuning.recovery_punch,
        tuning.low_speed_authority,
        tuning.steadiness,
        tuning.line_hold,
        tuning.commitment,
        tuning.exit_catch,
    )
    fmt.printf(
        "pace minimum=%.3f cruise=%.3f dive=%.3f rates pitch=%.3f roll=%.3f yaw=%.3f\n",
        derived.minimum_pace,
        derived.cruise_pace,
        derived.dive_pace,
        derived.maximum_pitch_rate,
        derived.maximum_roll_rate,
        derived.maximum_yaw_rate,
    )
    fmt.printf(
        "response engage=%.3f roll_engage=%.3f release=%.3f punch=%.3f coast=%.3f brake=%.3f grip=%.3f retention=%.3f\n",
        derived.engage_response,
        derived.roll_engage_response,
        derived.release_response,
        derived.pace_punch_response,
        derived.pace_coast_loss_response,
        derived.pace_brake_response,
        derived.track_grip_response,
        derived.track_retention,
    )
    fmt.printf(
        "energy throttle=%.3f dive=%.3f climb_cost=%.3f turn_cost=%.3f slip_cost=%.3f inverted_cost=%.3f edge_cost=%.3f\n",
        derived.throttle_energy_gain,
        derived.dive_energy_gain,
        derived.climb_energy_cost,
        derived.turn_energy_cost,
        derived.slip_energy_cost,
        derived.inverted_energy_cost,
        derived.edge_energy_cost,
    )
    fmt.printf(
        "edge warning=%.3f hang=%.3f break=%.3f recovery=%.3f warn_s=%.3f hang_s=%.3f break_s=%.3f recovery_s=%.3f\n",
        derived.warning_margin,
        derived.hang_margin,
        derived.break_margin,
        derived.recovery_margin,
        derived.warning_min_seconds,
        derived.hang_seconds,
        derived.break_min_seconds,
        derived.recovery_min_seconds,
    )
    fmt.printf(
        "drama pitch=%.3f roll=%.3f track=%.3f recovery_response=%.3f recovery_energy=%.3f low_energy=(%.3f,%.3f,%.3f) steadiness=%.3f line_hold=%.3f commitment=%.3f exit=(%.3f,%.3f)\n",
        derived.break_pitch_drama,
        derived.break_roll_drama,
        derived.break_track_drama,
        derived.recovery_response,
        derived.recovery_energy_gain,
        derived.low_energy_pitch_authority,
        derived.low_energy_yaw_authority,
        derived.low_energy_roll_authority,
        derived.steadiness_response,
        derived.line_hold_response,
        derived.commitment_threshold,
        derived.exit_catch_seconds,
        derived.exit_catch_response,
    )
}

print_result :: proc(
    scenario: air_compare.Scenario,
    model: postale.Flight_Model,
    result: air_compare.Run_Result,
) {
    maximum_position_step, maximum_pace_step: f32
    previous_position := scenario.checkpoint.body.position
    previous_pace := scenario.checkpoint.telemetry.airspeed
    if model == .Ace_Arcade do previous_pace = scenario.checkpoint.ace_telemetry.pace
    for sample in result.samples {
        maximum_position_step = max(
            maximum_position_step,
            linalg.length(sample.body.position - previous_position),
        )
        maximum_pace_step = max(maximum_pace_step, math.abs(sample.pace - previous_pace))
        previous_position = sample.body.position
        previous_pace = sample.pace
    }

    metrics := result.metrics
    fmt.printf(
        "%s | final=(%.2f,%.2f,%.2f) heading=%.3f alt=[%.2f,%.2f] pace=[%.2f,%.2f] rotation=(%.3f,%.3f,%.3f) recovery=%.3fs/%.2fm continuity=%.3fm/%.3fpace",
        model_label(model),
        metrics.final_position.x,
        metrics.final_position.y,
        metrics.final_position.z,
        metrics.final_heading,
        metrics.min_altitude,
        metrics.max_altitude,
        metrics.min_pace,
        metrics.max_pace,
        metrics.local_rotation.x,
        metrics.local_rotation.y,
        metrics.local_rotation.z,
        metrics.recovery_seconds,
        metrics.recovery_altitude_loss,
        maximum_position_step,
        maximum_pace_step,
    )
    if model == .Ace_Arcade {
        fmt.printf(
            " energy=%.3f->%.3f edge=%v",
            scenario.checkpoint.ace_runtime.energy,
            result.final_checkpoint.ace_runtime.energy,
            result.final_checkpoint.ace_runtime.edge_state,
        )
        previous_edge := scenario.checkpoint.ace_runtime.edge_state
        fmt.print(" transitions=")
        fmt.printf("%v", previous_edge)
        for sample in result.samples {
            if sample.ace_telemetry.edge_state != previous_edge {
                previous_edge = sample.ace_telemetry.edge_state
                fmt.printf(">%v", previous_edge)
            }
        }
    }
    fmt.println()
}

main :: proc() {
    fmt.println("ACE MOTION EVIDENCE")
    fmt.println("dt=1/120 ground=-1000 replay=exact-by-test")
    print_tuning()

    kinds := [?]air_compare.Scenario_Kind {
        .Level_Cruise,
        .Coordinated_Turn,
        .Full_Roll,
        .Loop,
        .Low_Energy_Recovery,
        .Aggressive_Roll_Yaw,
    }
    models := [?]postale.Flight_Model{.Current_Aero, .Ace_Arcade}
    for kind in kinds {
        scenario, made := air_compare.make_scenario(kind)
        if !made {
            fmt.eprintf("failed to build scenario %v\n", kind)
            continue
        }
        fmt.printf("\nSCENARIO %s steps=%d\n", scenario.name, len(scenario.commands))
        for model in models {
            result, ran := air_compare.run_model(scenario, model, context.allocator)
            if !ran {
                fmt.eprintf("failed to run %s/%s\n", scenario.name, model_label(model))
                continue
            }
            print_result(scenario, model, result)
            air_compare.destroy_run_result(&result, context.allocator)
        }
        air_compare.destroy_scenario(&scenario)
    }
}
