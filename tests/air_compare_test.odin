package tests

import air_compare "../packages/air_compare"
import flight "../packages/flight"
import postale "../packages/postale"
import "core:math/bits"
import "core:mem"
import "core:testing"

air_compare_expect_samples_equal :: proc(
    t: ^testing.T,
    a, b: []air_compare.Sample,
) {
    testing.expect(t, len(a) == len(b))
    if len(a) != len(b) do return
    for sample, index in a {
        testing.expect(t, sample == b[index])
    }
}

air_compare_expect_runs_equal :: proc(
    t: ^testing.T,
    a, b: air_compare.Run_Result,
) {
    testing.expect(t, a.final_checkpoint == b.final_checkpoint)
    testing.expect(t, a.metrics == b.metrics)
    air_compare_expect_samples_equal(t, a.samples, b.samples)
}

@(test)
air_compare_rejects_invalid_scenarios_and_accepts_empty_run :: proc(t: ^testing.T) {
    testing.expect(t, !air_compare.scenario_is_valid({}))

    scenario, made := air_compare.make_scenario(.Level_Cruise)
    testing.expect(t, made)
    if !made do return
    defer air_compare.destroy_scenario(&scenario)

    invalid := scenario
    invalid.delta_seconds = 0
    testing.expect(t, !air_compare.scenario_is_valid(invalid))
    invalid.delta_seconds = -.1
    testing.expect(t, !air_compare.scenario_is_valid(invalid))
    invalid.delta_seconds = .051
    testing.expect(t, !air_compare.scenario_is_valid(invalid))
    invalid.delta_seconds = f32(0h7fc0_0000)
    testing.expect(t, !air_compare.scenario_is_valid(invalid))
    invalid = scenario
    invalid.ground_height = f32(0h7f80_0000)
    testing.expect(t, !air_compare.scenario_is_valid(invalid))

    poisoned := scenario
    poisoned.checkpoint.airframe.wing_area = f32(0h7fc0_0000)
    testing.expect(t, !air_compare.scenario_is_valid(poisoned))
    poisoned = scenario
    poisoned.checkpoint.flight_runtime.drag_multiplier = f32(0h7f80_0000)
    testing.expect(t, !air_compare.scenario_is_valid(poisoned))
    poisoned = scenario
    poisoned.checkpoint.telemetry.airspeed = f32(0hff80_0000)
    testing.expect(t, !air_compare.scenario_is_valid(poisoned))
    poisoned = scenario
    poisoned.checkpoint.ace_tuning.pace = f32(0h7fc0_0000)
    testing.expect(t, !air_compare.scenario_is_valid(poisoned))
    poisoned = scenario
    poisoned.checkpoint.ace_runtime.edge_seconds = f32(0h7f80_0000)
    testing.expect(t, !air_compare.scenario_is_valid(poisoned))
    poisoned = scenario
    poisoned.checkpoint.ace_telemetry.pace = f32(0h7fc0_0000)
    testing.expect(t, !air_compare.scenario_is_valid(poisoned))
    poisoned = scenario
    poisoned.checkpoint.throttle = f32(0h7f80_0000)
    testing.expect(t, !air_compare.scenario_is_valid(poisoned))

    command_before := scenario.commands[0]
    scenario.commands[0].roll = 2
    testing.expect(t, !air_compare.scenario_is_valid(scenario))
    scenario.commands[0] = command_before

    empty := scenario
    empty.commands = nil
    empty_result, ran := air_compare.run_model(empty, .Ace_Arcade, mem.Allocator{})
    testing.expect(t, ran)
    testing.expect(t, empty_result.samples == nil)
    testing.expect(t, empty_result.final_checkpoint.valid)
    air_compare.destroy_run_result(&empty_result, mem.Allocator{})
    testing.expect(t, empty_result.samples == nil)
    testing.expect(t, !empty_result.final_checkpoint.valid)
    testing.expect(t, empty_result.metrics == air_compare.Metrics{})
}

@(test)
air_compare_command_segments_expand_exactly_and_reject_bad_counts :: proc(t: ^testing.T) {
    first := flight.Control_Command{pitch = .25, throttle = .7}
    second := flight.Control_Command{roll = -.5, yaw = .3, throttle = 1}
    segments := [?]air_compare.Command_Segment {
        {steps = 2, command = first},
        {steps = 0, command = {pitch = 1}},
        {steps = 3, command = second},
    }

    commands, expanded := air_compare.expand_command_segments(segments[:])
    testing.expect(t, expanded)
    defer air_compare.destroy_commands(&commands)
    testing.expect(t, len(commands) == 5)
    testing.expect(t, commands[0] == first)
    testing.expect(t, commands[1] == first)
    testing.expect(t, commands[2] == second)
    testing.expect(t, commands[4] == second)

    repeated, repeated_ok := air_compare.expand_command_segments(segments[:])
    testing.expect(t, repeated_ok)
    defer air_compare.destroy_commands(&repeated)
    testing.expect(t, len(repeated) == len(commands))
    for command, index in repeated {
        testing.expect(t, command == commands[index])
    }

    zero, zero_ok := air_compare.expand_command_segments(
        []air_compare.Command_Segment{{steps = 0}},
    )
    testing.expect(t, zero_ok)
    testing.expect(t, zero == nil)

    negative, negative_ok := air_compare.expand_command_segments(
        []air_compare.Command_Segment{{steps = -1}},
    )
    testing.expect(t, !negative_ok)
    testing.expect(t, negative == nil)

    overflow, overflow_ok := air_compare.expand_command_segments(
        []air_compare.Command_Segment{{steps = bits.INT_MAX}, {steps = 1}},
    )
    testing.expect(t, !overflow_ok)
    testing.expect(t, overflow == nil)
}

@(test)
air_compare_replays_each_model_exactly_without_advancing_inactive_state :: proc(t: ^testing.T) {
    scenario, made := air_compare.make_scenario(.Full_Roll)
    testing.expect(t, made)
    if !made do return
    defer air_compare.destroy_scenario(&scenario)
    checkpoint_before := scenario.checkpoint
    first_command, last_command := scenario.commands[0], scenario.commands[len(scenario.commands) - 1]

    legacy_a, legacy_a_ok := air_compare.run_model(scenario, .Current_Aero, context.allocator)
    testing.expect(t, legacy_a_ok)
    defer air_compare.destroy_run_result(&legacy_a, context.allocator)
    legacy_b, legacy_b_ok := air_compare.run_model(scenario, .Current_Aero, context.allocator)
    testing.expect(t, legacy_b_ok)
    defer air_compare.destroy_run_result(&legacy_b, context.allocator)
    ace_a, ace_a_ok := air_compare.run_model(scenario, .Ace_Arcade, context.allocator)
    testing.expect(t, ace_a_ok)
    defer air_compare.destroy_run_result(&ace_a, context.allocator)
    ace_b, ace_b_ok := air_compare.run_model(scenario, .Ace_Arcade, context.allocator)
    testing.expect(t, ace_b_ok)
    defer air_compare.destroy_run_result(&ace_b, context.allocator)

    air_compare_expect_runs_equal(t, legacy_a, legacy_b)
    air_compare_expect_runs_equal(t, ace_a, ace_b)
    testing.expect(t, len(legacy_a.samples) == len(scenario.commands))
    testing.expect(t, len(ace_a.samples) == len(scenario.commands))
    testing.expect(t, legacy_a.final_checkpoint.ace_runtime == checkpoint_before.ace_runtime)
    testing.expect(t, legacy_a.final_checkpoint.ace_telemetry == checkpoint_before.ace_telemetry)
    testing.expect(t, ace_a.final_checkpoint.flight_runtime == checkpoint_before.flight_runtime)
    testing.expect(t, ace_a.final_checkpoint.telemetry == checkpoint_before.telemetry)
    testing.expect(t, scenario.checkpoint == checkpoint_before)
    testing.expect(t, scenario.commands[0] == first_command)
    testing.expect(t, scenario.commands[len(scenario.commands) - 1] == last_command)
}

@(test)
air_compare_derives_rotation_extrema_and_recovery_from_samples :: proc(t: ^testing.T) {
    initial := flight.Body_State {
        position    = {0, 100, 0},
        orientation = flight.identity_orientation(),
    }
    samples: [4]air_compare.Sample
    altitudes := [?]f32{99, 97, 96, 98}
    paces := [?]f32{10, 12, 9, 11}
    states := [?]flight.Ace_Edge_State{.Free, .Recovery, .Recovery, .Free}
    for &sample, index in samples {
        sample = {
            body = {
                position               = {f32(index), altitudes[index], 0},
                orientation            = flight.identity_orientation(),
                angular_velocity_world = {0, 0, -2},
            },
            pace = paces[index],
            ace_telemetry = {
                pace       = paces[index],
                edge_state = states[index],
            },
        }
    }

    ace := air_compare.derive_metrics(samples[:], initial, 10, .5, .Ace_Arcade)
    testing.expect(t, ace.local_rotation == flight.Vec3{0, 0, 4})
    testing.expect(t, ace.min_altitude == 96)
    testing.expect(t, ace.max_altitude == 99)
    testing.expect(t, ace.min_pace == 9)
    testing.expect(t, ace.max_pace == 12)
    testing.expect(t, ace.final_position == samples[3].body.position)
    testing.expect(t, ace.recovery_seconds == 1)
    testing.expect(t, ace.recovery_altitude_loss == 3)

    legacy := air_compare.derive_metrics(samples[:], initial, 10, .5, .Current_Aero)
    testing.expect(t, legacy.local_rotation == ace.local_rotation)
    testing.expect(t, legacy.recovery_seconds == 0)
    testing.expect(t, legacy.recovery_altitude_loss == 0)
}

@(test)
air_compare_all_frozen_scenarios_run_both_models_and_report_values :: proc(t: ^testing.T) {
    kinds := [?]air_compare.Scenario_Kind {
        .Level_Cruise,
        .Coordinated_Turn,
        .Full_Roll,
        .Loop,
        .Low_Energy_Recovery,
        .Aggressive_Roll_Yaw,
    }

    for kind in kinds {
        scenario, made := air_compare.make_scenario(kind)
        testing.expect(t, made)
        if !made do continue
        testing.expect(t, air_compare.scenario_is_valid(scenario))
        testing.expect(t, scenario.delta_seconds == air_compare.SCENARIO_DELTA_SECONDS)
        testing.expect(t, len(scenario.commands) > 0)
        testing.expect(t, scenario.checkpoint.flight_runtime.engine_output > 0)
        testing.expect(t, flight.ace_tuning_is_valid(scenario.checkpoint.ace_tuning))

        legacy, legacy_ok := air_compare.run_model(scenario, .Current_Aero, context.allocator)
        ace, ace_ok := air_compare.run_model(scenario, .Ace_Arcade, context.allocator)
        testing.expect(t, legacy_ok)
        testing.expect(t, ace_ok)
        if legacy_ok && ace_ok {
            testing.expect(t, len(legacy.samples) == len(scenario.commands))
            testing.expect(t, len(ace.samples) == len(scenario.commands))
            testing.expect(t, legacy.final_checkpoint.valid)
            testing.expect(t, ace.final_checkpoint.valid)
            testing.expect(t, legacy.metrics.min_pace >= 0)
            testing.expect(t, legacy.metrics.max_pace >= legacy.metrics.min_pace)
            testing.expect(t, ace.metrics.min_pace > 0)
            testing.expect(t, ace.metrics.max_pace >= ace.metrics.min_pace)
            testing.expect(t, air_compare.scenario_result_is_within_envelope(kind, .Current_Aero, legacy))
            testing.expect(t, air_compare.scenario_result_is_within_envelope(kind, .Ace_Arcade, ace))

            report := air_compare.comparison_report(scenario, .Ace_Arcade, ace)
            testing.expect(t, report.valid)
            testing.expect(t, report.scenario_name == scenario.name)
            testing.expect(t, report.model == .Ace_Arcade)
            testing.expect(t, report.sample_count == len(ace.samples))
            testing.expect(t, report.metrics == ace.metrics)
            testing.expect(t, report.final_ace_energy == ace.final_checkpoint.ace_runtime.energy)
            testing.expect(t, report.final_ace_edge_state == ace.final_checkpoint.ace_runtime.edge_state)
        }
        air_compare.destroy_run_result(&legacy, context.allocator)
        air_compare.destroy_run_result(&ace, context.allocator)
        air_compare.destroy_scenario(&scenario)
        testing.expect(t, scenario.name == "")
        testing.expect(t, scenario.commands == nil)
        testing.expect(t, !scenario.checkpoint.valid)
    }
}
