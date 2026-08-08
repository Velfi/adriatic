package main

import fixture_v0001 "../packages/fixture_history/v0001"
import fixture_v0002 "../packages/fixture_history/v0002"
import fixture_v0003 "../packages/fixture_history/v0003"
import "base:runtime"
import "core:mem"
import "core:testing"
import hs "zelda_engine:hs"

when ODIN_TEST {
    fixture_migration_v0003_runtime_seed_common :: proc(source: ^$T, radius, route_width: f32) {
        source.architecture_brush_radius = radius
        source.aircraft.slots[0].kind = .Postale
        source.aircraft.slots[1].kind = .Libellula
        source.aircraft.slots[2].kind = .Libellula_Mk2
        source.aircraft.active = .Postale
        source.aircraft.count = 3
        source.settlement_plan.route_count = 1
        source.settlement_plan.routes[0].geometry.count = 2
        source.settlement_plan.routes[0].geometry.points[0] = {11, 12}
        source.settlement_plan.routes[0].geometry.points[1] = {13, 14}
        source.settlement_plan.routes[0].class = .Stair
        source.settlement_plan.routes[0].width = route_width
        source.settlement_plan.routes[0].shoulder = route_width + 1
        source.settlement_plan.routes[0].pavement = .Cobblestone
        source.settlement_plan.routes[0].required = true
        source.settlement_plan.routes[0].drivable = false
        source.settlement_plan.routes[0].average_grade = route_width + 2
        source.settlement_plan.routes[0].maximum_grade = route_width + 3
        source.marina_authored_plan.shoreline_form = .West_Apron
        source.authoring_tool = .Roads
    }

    fixture_migration_v0003_runtime_encode :: proc(t: ^testing.T, source: ^$T) -> (payload: []byte, ok: bool) {
        portable_error: hs.Portable_Error
        payload, portable_error, ok = hs.portable_encode(
            any{data = rawptr(source), id = typeid_of(T)},
            fixture_codec_historical_portable_config(),
            context.allocator,
        )
        testing.expect(t, ok && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        return payload, ok
    }

    fixture_migration_v0003_runtime_v1_payload :: proc(
        t: ^testing.T,
        invalid_farm_count := false,
        invalid_radius := false,
    ) -> (
        []byte,
        bool,
    ) {
        source := new(fixture_v0001.Fixture)
        fixture_migration_v0003_runtime_seed_common(source, 44, 11)
        fixture_migration_v0004_runtime_seed_legacy_flight(source, 1)
        if invalid_radius do source.architecture_brush_radius = -1
        source.project.structure_count = 1
        source.project.structures[0].id = 101
        source.architecture_city_plan.count = 1
        source.architecture_city_plan.structures[0].id = 102
        source.architecture_city_plan.alley_count = 1
        source.architecture_city_plan.alleys[0].start_x = 103
        source.farm_count = invalid_farm_count ? 17 : 1
        payload, ok := fixture_migration_v0003_runtime_encode(t, source)
        free(source)
        return payload, ok
    }

    fixture_migration_v0003_runtime_v2_payload :: proc(t: ^testing.T, invalid_radius := false) -> ([]byte, bool) {
        source := new(fixture_v0002.Fixture)
        fixture_migration_v0003_runtime_seed_common(source, 45, 21)
        fixture_migration_v0004_runtime_seed_legacy_flight(source, 2)
        if invalid_radius do source.architecture_brush_radius = -1
        source.project.structures = make([dynamic]fixture_v0002.History_Type_0087, 1, context.allocator)
        source.architecture_city_plan.structures = make([dynamic]fixture_v0002.History_Type_0087, 1, context.allocator)
        source.architecture_city_plan.alleys = make([dynamic]fixture_v0002.History_Type_0000, 1, context.allocator)
        source.project.structures[0].id = 201
        source.architecture_city_plan.structures[0].id = 202
        source.architecture_city_plan.alleys[0].start_x = 203
        source.pilot.mode = .Driving
        source.structure_selected = 204
        source.vehicle_showcase_target = "runtime-v2-target"
        source.active_lab_scene = "runtime-v2-lab"
        payload, ok := fixture_migration_v0003_runtime_encode(t, source)
        delete(source.project.structures)
        delete(source.architecture_city_plan.structures)
        delete(source.architecture_city_plan.alleys)
        free(source)
        return payload, ok
    }

    fixture_migration_v0003_runtime_v3_payload :: proc(
        t: ^testing.T,
        invalid_route_count := false,
        invalid_radius := false,
        invalid_aircraft_count := false,
    ) -> (
        []byte,
        bool,
    ) {
        source := new(fixture_v0003.Fixture)
        fixture_migration_v0003_runtime_seed_common(source, 85, 31)
        fixture_migration_v0004_runtime_seed_legacy_flight(source, 3)
        if invalid_radius do source.architecture_brush_radius = -1
        if invalid_aircraft_count do source.aircraft.count = 2
        source.occupant = .Libellula
        source.project.structures = make([dynamic]fixture_v0003.History_Type_0087, 1, context.allocator)
        source.architecture_city_plan.structures = make([dynamic]fixture_v0003.History_Type_0087, 1, context.allocator)
        source.architecture_city_plan.alleys = make([dynamic]fixture_v0003.History_Type_0000, 1, context.allocator)
        source.project.structures[0].id = 301
        source.architecture_city_plan.structures[0].id = 302
        source.architecture_city_plan.alleys[0].start_x = 303
        source.pilot.mode = .Driving
        source.structure_selected = 304
        source.vehicle_showcase_target = "runtime-v3-target"
        source.active_lab_scene = "runtime-v3-lab"
        if invalid_route_count do source.settlement_plan.routes[47].geometry.count = 13
        payload, ok := fixture_migration_v0003_runtime_encode(t, source)
        delete(source.project.structures)
        delete(source.architecture_city_plan.structures)
        delete(source.architecture_city_plan.alleys)
        free(source)
        return payload, ok
    }

    fixture_migration_v0003_runtime_steps: [3]Fixture_Migration_Step = {
        {
            from_version = 1,
            to_version = 2,
            wrapper = fixture_migration_step_v0001_to_v0002,
            change_id = FIXTURE_MIGRATION_V0001_FARM_DEFAULT_ID,
        },
        {
            from_version = 2,
            to_version = 3,
            wrapper = fixture_migration_step_v0002_to_v0003,
            change_id = "field-add:adriatic:src.Fixture.occupant",
        },
        {
            from_version = 3,
            to_version = 4,
            wrapper = fixture_migration_step_v0003_to_v0004,
            change_id = FIXTURE_MIGRATION_V0003_SETTLEMENT_ID,
        },
    }

    fixture_migration_v0003_runtime_registry :: proc() -> Fixture_Migration_Registry {
        return {steps = fixture_migration_v0003_runtime_steps[:]}
    }

    fixture_migration_v0003_runtime_prepare_step :: proc(
        t: ^testing.T,
        payload: []byte,
        source_version: int,
        block_allocator: mem.Allocator,
    ) -> (
        arena: ^mem.Dynamic_Arena,
        tentative: ^Fixture,
        step_context: Fixture_Migration_Step_Context,
        ok: bool,
    ) {
        arena_ok: bool
        arena, arena_ok = fixture_migration_arena_allocate(block_allocator)
        testing.expect(t, arena_ok)
        if !arena_ok do return
        transaction_allocator := mem.dynamic_arena_allocator(arena)
        tentative = new(Fixture, transaction_allocator)
        testing.expect(t, tentative != nil)
        if tentative == nil {
            fixture_migration_arena_dispose(arena, block_allocator)
            return nil, nil, {}, false
        }

        portable_error, portable_ok := hs.portable_decode(
            fixture_codec_value(tentative),
            payload,
            fixture_codec_migration_portable_config(),
            transaction_allocator,
        )
        testing.expect(t, portable_ok && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        if !portable_ok {
            fixture_migration_arena_dispose(arena, block_allocator)
            return nil, nil, {}, false
        }

        for step_index := source_version - 1; step_index < 2; step_index += 1 {
            step := fixture_migration_v0003_runtime_steps[step_index]
            prior_context := Fixture_Migration_Step_Context {
                source_payload        = payload,
                source_version        = source_version,
                target_version        = 4,
                step_from_version     = step.from_version,
                step_to_version       = step.to_version,
                tentative             = tentative,
                transaction_allocator = transaction_allocator,
            }
            prior_error := step.wrapper(&prior_context)
            testing.expect(t, prior_error.kind == .None)
            prior_ok := prior_error.kind == .None
            fixture_migration_error_dispose(&prior_error)
            if !prior_ok {
                fixture_migration_arena_dispose(arena, block_allocator)
                return nil, nil, {}, false
            }
        }

        step_context = {
            source_payload        = payload,
            source_version        = source_version,
            target_version        = 4,
            step_from_version     = 3,
            step_to_version       = 4,
            tentative             = tentative,
            transaction_allocator = transaction_allocator,
        }
        return arena, tentative, step_context, true
    }

    fixture_migration_v0003_runtime_expect_result :: proc(
        t: ^testing.T,
        result: ^Fixture_Migration_Result,
        source_version: int,
        expected_preset: Settlement_Brush_Preset,
        expected_route_width: f32,
        expected_occupant: int,
    ) {
        testing.expect(t, result.fixture != nil && result.arena != nil)
        if result.fixture == nil do return
        fixture := result.fixture
        testing.expect(
            t,
            fixture.architecture_brush_preset == expected_preset &&
            fixture.architecture_brush_shape == .Circle &&
            fixture.aircraft.count == 4 &&
            fixture.aircraft.slots[3].kind == .Rondine &&
            fixture.rondine.vehicle.locked &&
            !fixture.rondine_visible &&
            int(fixture.occupant) == expected_occupant &&
            fixture.settlement_plan.request.density == 0 &&
            fixture.settlement_plan.routes[0].width == expected_route_width &&
            fixture.settlement_plan.routes[0].geometry.points[1] == [2]f32{13, 14} &&
            fixture.settlement_plan.routes[0].class == .Stair &&
            fixture.settlement_plan.routes[0].pavement == .Cobblestone &&
            fixture.settlement_plan.routes[48] == Settlement_Planned_Route{},
        )
        expected_id := u64(source_version * 100)
        testing.expect(
            t,
            len(fixture.project.structures) == 1 &&
            fixture.project.structures[0].id == expected_id + 1 &&
            len(fixture.architecture_city_plan.structures) == 1 &&
            fixture.architecture_city_plan.structures[0].id == expected_id + 2 &&
            len(fixture.architecture_city_plan.alleys) == 1 &&
            fixture.architecture_city_plan.alleys[0].start_x == f32(expected_id + 3),
        )
        if source_version == 1 {
            testing.expect(
                t,
                fixture.farm_count == 1 &&
                fixture.farms[0].plan.width == 25 &&
                fixture.farms[0].plan.height == 19 &&
                fixture.farms[0].plan.tradition == .Ancient_Enclosure &&
                fixture.farms[0].scale_x == 1 &&
                fixture.farms[0].scale_z == 1 &&
                fixture.story_state.quest.definition_id == "two-island-story" &&
                fixture.story_state.quest.node_count == 13 &&
                fixture.story_state.quest.statuses[11] == .Available &&
                fixture.story_state.quest.revision == 1 &&
                fixture.quest_tracking_revision == 1,
            )
        } else if source_version == 2 {
            testing.expect(
                t,
                fixture.pilot.mode == .Driving &&
                fixture.structure_selected == 204 &&
                fixture.vehicle_showcase_target == "runtime-v2-target" &&
                fixture.lab.kind == .None,
            )
        } else {
            testing.expect(
                t,
                fixture.pilot.mode == .Driving &&
                fixture.structure_selected == 304 &&
                fixture.vehicle_showcase_target == "runtime-v3-target" &&
                fixture.lab.kind == .None,
            )
        }
        project_raw := cast(^runtime.Raw_Dynamic_Array)&fixture.project.structures
        city_raw := cast(^runtime.Raw_Dynamic_Array)&fixture.architecture_city_plan.structures
        alley_raw := cast(^runtime.Raw_Dynamic_Array)&fixture.architecture_city_plan.alleys
        testing.expect(
            t,
            project_raw.allocator.data == rawptr(result.arena) &&
            city_raw.allocator.data == rawptr(result.arena) &&
            alley_raw.allocator.data == rawptr(result.arena),
        )
        previous_length := len(fixture.architecture_city_plan.alleys)
        appended, append_error := append_elem(
            &fixture.architecture_city_plan.alleys,
            fixture.architecture_city_plan.alleys[0],
        )
        testing.expect(
            t,
            appended == 1 &&
            append_error == nil &&
            len(fixture.architecture_city_plan.alleys) == previous_length + 1 &&
            cast(^runtime.Raw_Dynamic_Array)&fixture.architecture_city_plan.alleys != nil,
        )
    }

    fixture_migration_v0003_runtime_expect_step_failure :: proc(
        t: ^testing.T,
        payload: []byte,
        source_version: int,
        expected_kind: Fixture_Migration_Error_Kind,
        expected_change_id: string,
    ) {
        payload_snapshot := fixture_codec_test_copy(payload)
        defer delete(payload_snapshot)
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        allocator := fixture_migration_test_allocator(&state)
        arena, tentative, step_context, prepared := fixture_migration_v0003_runtime_prepare_step(
            t,
            payload,
            source_version,
            allocator,
        )
        if !prepared do return
        snapshot, snapshot_ok := fixture_migration_structural_snapshot(tentative, runtime.default_allocator())
        testing.expect(t, snapshot_ok)
        outstanding := state.outstanding
        step_error := fixture_migration_step_v0003_to_v0004(&step_context)
        testing.expect(
            t,
            step_error.kind == expected_kind &&
            step_error.change_id == expected_change_id &&
            fixture_migration_structural_snapshot_matches(snapshot, tentative) &&
            fixture_migration_test_bytes_equal(payload, payload_snapshot) &&
            state.outstanding == outstanding,
        )
        fixture_migration_error_dispose(&step_error)
        fixture_migration_error_dispose(&step_error)
        fixture_migration_structural_snapshot_dispose(&snapshot)
        fixture_migration_structural_snapshot_dispose(&snapshot)
        fixture_migration_arena_dispose(arena, allocator)
        testing.expect(t, state.outstanding == 0)
    }

    fixture_migration_v0003_runtime_wrapper_oom_sweep :: proc(t: ^testing.T, payload: []byte, source_version: int) {
        payload_snapshot := fixture_codec_test_copy(payload)
        defer delete(payload_snapshot)
        measurement_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        measurement_allocator := fixture_migration_test_allocator(&measurement_state)
        measurement_arena, _, measurement_context, measurement_prepared :=
            fixture_migration_v0003_runtime_prepare_step(t, payload, source_version, measurement_allocator)
        if !measurement_prepared do return
        measurement_state.allocation_calls = 0
        measurement_error := fixture_migration_step_v0003_to_v0004(&measurement_context)
        wrapper_calls := measurement_state.allocation_calls
        testing.expect(t, measurement_error.kind == .None && wrapper_calls > 0)
        fixture_migration_error_dispose(&measurement_error)
        fixture_migration_arena_dispose(measurement_arena, measurement_allocator)
        testing.expect(t, measurement_state.outstanding == 0)

        for fail_at in 0 ..< wrapper_calls {
            state := fixture_migration_test_allocator_state {
                    base    = runtime.default_allocator(),
                    fail_at = -1,
                }
            allocator := fixture_migration_test_allocator(&state)
            arena, tentative, step_context, prepared := fixture_migration_v0003_runtime_prepare_step(
                t,
                payload,
                source_version,
                allocator,
            )
            if !prepared do return
            snapshot, snapshot_ok := fixture_migration_structural_snapshot(tentative, runtime.default_allocator())
            testing.expect(t, snapshot_ok)
            outstanding := state.outstanding
            state.allocation_calls = 0
            state.fail_at = fail_at
            step_error := fixture_migration_step_v0003_to_v0004(&step_context)
            testing.expect(
                t,
                step_error.kind == .Out_Of_Memory &&
                fixture_migration_structural_snapshot_matches(snapshot, tentative) &&
                state.outstanding == outstanding,
            )
            fixture_migration_error_dispose(&step_error)
            fixture_migration_error_dispose(&step_error)
            fixture_migration_structural_snapshot_dispose(&snapshot)
            state.fail_at = -1
            fixture_migration_arena_dispose(arena, allocator)
            testing.expect(t, state.outstanding == 0)
        }
        testing.expect(t, fixture_migration_test_bytes_equal(payload, payload_snapshot))
    }

    fixture_migration_v0003_runtime_expect_runner_failure :: proc(
        t: ^testing.T,
        payload: []byte,
        source_version: int,
        expected_change_id: string,
    ) {
        payload_snapshot := fixture_codec_test_copy(payload)
        defer delete(payload_snapshot)
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        result, migration_error, ok := fixture_migration_run_with_registry(
            payload,
            source_version,
            4,
            fixture_migration_v0003_runtime_registry(),
            fixture_migration_test_allocator(&state),
        )
        testing.expect(
            t,
            !ok &&
            migration_error.kind == .Step_Failure &&
            migration_error.change_id == expected_change_id &&
            fixture_migration_result_empty(&result) &&
            fixture_migration_test_bytes_equal(payload, payload_snapshot),
        )
        fixture_migration_error_dispose(&migration_error)
        fixture_migration_error_dispose(&migration_error)
        fixture_migration_result_dispose(&result)
        fixture_migration_result_dispose(&result)
        testing.expect(t, state.outstanding == 0)
    }

    fixture_migration_v0003_runtime_runner_oom_sweep :: proc(t: ^testing.T, payload: []byte, source_version: int) {
        payload_snapshot := fixture_codec_test_copy(payload)
        defer delete(payload_snapshot)
        measurement_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        measurement_result, measurement_error, measurement_ok := fixture_migration_run_with_registry(
            payload,
            source_version,
            4,
            fixture_migration_v0003_runtime_registry(),
            fixture_migration_test_allocator(&measurement_state),
        )
        allocation_calls := measurement_state.allocation_calls
        testing.expect(t, measurement_ok && measurement_error.kind == .None && allocation_calls > 0)
        fixture_migration_error_dispose(&measurement_error)
        fixture_migration_result_dispose(&measurement_result)
        testing.expect(t, measurement_state.outstanding == 0)

        for fail_at in 0 ..< allocation_calls {
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = fail_at,
            }
            result, migration_error, ok := fixture_migration_run_with_registry(
                payload,
                source_version,
                4,
                fixture_migration_v0003_runtime_registry(),
                fixture_migration_test_allocator(&state),
            )
            testing.expect(
                t,
                !ok &&
                migration_error.kind == .Out_Of_Memory &&
                fixture_migration_result_empty(&result) &&
                fixture_migration_test_bytes_equal(payload, payload_snapshot),
            )
            fixture_migration_error_dispose(&migration_error)
            fixture_migration_error_dispose(&migration_error)
            fixture_migration_result_dispose(&result)
            fixture_migration_result_dispose(&result)
            testing.expect(t, state.outstanding == 0)
        }
    }

    @(test)
    fixture_migration_v0003_to_v0004_runtime_direct_and_chains :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        v1_payload, v1_ok := fixture_migration_v0003_runtime_v1_payload(t)
        v2_payload, v2_ok := fixture_migration_v0003_runtime_v2_payload(t)
        v3_payload, v3_ok := fixture_migration_v0003_runtime_v3_payload(t)
        if !v1_ok || !v2_ok || !v3_ok {
            delete(v1_payload)
            delete(v2_payload)
            delete(v3_payload)
            return
        }
        defer delete(v1_payload)
        defer delete(v2_payload)
        defer delete(v3_payload)
        v1_snapshot := fixture_codec_test_copy(v1_payload)
        v2_snapshot := fixture_codec_test_copy(v2_payload)
        v3_snapshot := fixture_codec_test_copy(v3_payload)
        defer delete(v1_snapshot)
        defer delete(v2_snapshot)
        defer delete(v3_snapshot)

        payloads := [?][]byte{v1_payload, v2_payload, v3_payload}
        presets := [?]Settlement_Brush_Preset{.Small, .Medium, .Large}
        widths := [?]f32{11, 21, 31}
        occupants := [?]int{0, 0, 3}
        for payload, index in payloads {
            result, error, ok := fixture_migration_run_with_registry(
                payload,
                index + 1,
                4,
                fixture_migration_v0003_runtime_registry(),
                runtime.default_allocator(),
            )
            testing.expect(t, ok && error.kind == .None)
            if ok {
                fixture_migration_v0003_runtime_expect_result(
                    t,
                    &result,
                    index + 1,
                    presets[index],
                    widths[index],
                    occupants[index],
                )
                first, first_error, first_ok := fixture_codec_encode(result.fixture, context.allocator)
                second, second_error, second_ok := fixture_codec_encode(result.fixture, context.allocator)
                testing.expect(
                    t,
                    first_ok &&
                    second_ok &&
                    first_error.kind == .None &&
                    second_error.kind == .None &&
                    fixture_migration_test_bytes_equal(first, second),
                )
                production_result, production_error, production_ok := fixture_migration_run_with_registry(
                    payload,
                    index + 1,
                    4,
                    fixture_migration_v0003_runtime_registry(),
                    runtime.default_allocator(),
                )
                testing.expect(t, production_ok && production_error.kind == .None)
                if production_ok {
                    fixture_migration_v0003_runtime_expect_result(
                        t,
                        &production_result,
                        index + 1,
                        presets[index],
                        widths[index],
                        occupants[index],
                    )
                    production_encoded, production_encode_error, production_encoded_ok := fixture_codec_encode(
                        production_result.fixture,
                        context.allocator,
                    )
                    testing.expect(
                        t,
                        production_encoded_ok &&
                        production_encode_error.kind == .None &&
                        first_ok &&
                        fixture_migration_test_bytes_equal(first, production_encoded),
                    )
                    if production_encoded_ok do delete(production_encoded)
                    fixture_codec_error_dispose(&production_encode_error)
                    fixture_codec_error_dispose(&production_encode_error)
                }
                fixture_migration_error_dispose(&production_error)
                fixture_migration_error_dispose(&production_error)
                fixture_migration_result_dispose(&production_result)
                fixture_migration_result_dispose(&production_result)
                delete(first)
                delete(second)
                fixture_codec_error_dispose(&first_error)
                fixture_codec_error_dispose(&second_error)
            }
            fixture_migration_error_dispose(&error)
            fixture_migration_error_dispose(&error)
            fixture_migration_result_dispose(&result)
            fixture_migration_result_dispose(&result)
        }
        testing.expect(t, fixture_migration_test_bytes_equal(v1_payload, v1_snapshot))
        testing.expect(t, fixture_migration_test_bytes_equal(v2_payload, v2_snapshot))
        testing.expect(t, fixture_migration_test_bytes_equal(v3_payload, v3_snapshot))
    }

    @(test)
    fixture_migration_v0003_to_v0004_runtime_hostile_and_atomic :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        v1_payload, v1_ok := fixture_migration_v0003_runtime_v1_payload(t)
        v2_payload, v2_ok := fixture_migration_v0003_runtime_v2_payload(t)
        v3_payload, v3_ok := fixture_migration_v0003_runtime_v3_payload(t)
        invalid_farm_payload, invalid_farm_ok := fixture_migration_v0003_runtime_v1_payload(
            t,
            invalid_farm_count = true,
        )
        invalid_radius_payload, invalid_radius_ok := fixture_migration_v0003_runtime_v3_payload(
            t,
            invalid_radius = true,
        )
        invalid_route_payload, invalid_route_ok := fixture_migration_v0003_runtime_v3_payload(
            t,
            invalid_route_count = true,
        )
        invalid_fleet_payload, invalid_fleet_ok := fixture_migration_v0003_runtime_v3_payload(
            t,
            invalid_aircraft_count = true,
        )
        defer delete(v1_payload)
        defer delete(v2_payload)
        defer delete(v3_payload)
        defer delete(invalid_farm_payload)
        defer delete(invalid_radius_payload)
        defer delete(invalid_route_payload)
        defer delete(invalid_fleet_payload)
        if !v1_ok ||
           !v2_ok ||
           !v3_ok ||
           !invalid_farm_ok ||
           !invalid_radius_ok ||
           !invalid_route_ok ||
           !invalid_fleet_ok {
            return
        }

        v3_snapshot := fixture_codec_test_copy(v3_payload)
        defer delete(v3_snapshot)
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        allocator := fixture_migration_test_allocator(&state)
        arena, tentative, step_context, prepared := fixture_migration_v0003_runtime_prepare_step(
            t,
            v3_payload,
            3,
            allocator,
        )
        if !prepared do return
        snapshot, snapshot_ok := fixture_migration_structural_snapshot(tentative, runtime.default_allocator())
        testing.expect(t, snapshot_ok)
        allocation_calls := state.allocation_calls

        nil_error := fixture_migration_step_v0003_to_v0004(nil)
        testing.expect(t, nil_error.kind == .Invalid_Argument)
        fixture_migration_error_dispose(&nil_error)

        forged_arena: mem.Dynamic_Arena
        invalid_contexts := [8]Fixture_Migration_Step_Context {
            step_context,
            step_context,
            step_context,
            step_context,
            step_context,
            step_context,
            step_context,
            step_context,
        }
        invalid_contexts[0].tentative = nil
        invalid_contexts[1].source_version = 0
        invalid_contexts[2].source_version = 4
        invalid_contexts[3].target_version = 3
        invalid_contexts[4].step_from_version = 2
        invalid_contexts[5].step_to_version = 5
        invalid_contexts[6].transaction_allocator = {}
        invalid_contexts[7].transaction_allocator = {
            procedure = mem.dynamic_arena_allocator_proc,
            data      = rawptr(&forged_arena),
        }
        for &invalid_context in invalid_contexts {
            invalid_error := fixture_migration_step_v0003_to_v0004(&invalid_context)
            testing.expect(
                t,
                invalid_error.kind == .Invalid_Argument &&
                fixture_migration_structural_snapshot_matches(snapshot, tentative) &&
                state.allocation_calls == allocation_calls,
            )
            fixture_migration_error_dispose(&invalid_error)
            fixture_migration_error_dispose(&invalid_error)
        }

        malformed_context := step_context
        malformed_context.source_payload = v3_payload[:len(v3_payload) - 1]
        malformed_error := fixture_migration_step_v0003_to_v0004(&malformed_context)
        testing.expect(
            t,
            malformed_error.kind == .Historical_Decode &&
            fixture_migration_structural_snapshot_matches(snapshot, tentative),
        )
        fixture_migration_error_dispose(&malformed_error)
        fixture_migration_error_dispose(&malformed_error)

        wrong_schema_context := step_context
        wrong_schema_context.source_payload = v2_payload
        wrong_schema_error := fixture_migration_step_v0003_to_v0004(&wrong_schema_context)
        testing.expect(
            t,
            wrong_schema_error.kind == .Historical_Decode &&
            fixture_migration_structural_snapshot_matches(snapshot, tentative),
        )
        fixture_migration_error_dispose(&wrong_schema_error)
        fixture_migration_error_dispose(&wrong_schema_error)
        testing.expect(t, fixture_migration_test_bytes_equal(v3_payload, v3_snapshot))
        fixture_migration_structural_snapshot_dispose(&snapshot)
        fixture_migration_arena_dispose(arena, allocator)
        testing.expect(t, state.outstanding == 0)

        fixture_migration_v0003_runtime_expect_step_failure(
            t,
            invalid_radius_payload,
            3,
            .Invalid_Source,
            FIXTURE_MIGRATION_V0003_BRUSH_PRESET_ID,
        )
        fixture_migration_v0003_runtime_expect_step_failure(
            t,
            invalid_route_payload,
            3,
            .Invalid_Source,
            FIXTURE_MIGRATION_V0003_SETTLEMENT_ID,
        )
        fixture_migration_v0003_runtime_expect_step_failure(
            t,
            invalid_fleet_payload,
            3,
            .Invalid_Source,
            FIXTURE_MIGRATION_V0003_RONDINE_ID,
        )
        fixture_migration_v0003_runtime_expect_runner_failure(
            t,
            invalid_farm_payload,
            1,
            FIXTURE_MIGRATION_V0001_FARM_DEFAULT_ID,
        )
        fixture_migration_v0003_runtime_expect_runner_failure(
            t,
            invalid_radius_payload,
            3,
            FIXTURE_MIGRATION_V0003_BRUSH_PRESET_ID,
        )
        fixture_migration_v0003_runtime_expect_runner_failure(
            t,
            invalid_route_payload,
            3,
            FIXTURE_MIGRATION_V0003_SETTLEMENT_ID,
        )
        fixture_migration_v0003_runtime_expect_runner_failure(
            t,
            invalid_fleet_payload,
            3,
            FIXTURE_MIGRATION_V0003_RONDINE_ID,
        )

        projected_invalid_radius_payloads := [2][]byte{}
        projected_radius_oks := [2]bool{}
        projected_invalid_radius_payloads[0], projected_radius_oks[0] = fixture_migration_v0003_runtime_v1_payload(
            t,
            invalid_radius = true,
        )
        projected_invalid_radius_payloads[1], projected_radius_oks[1] = fixture_migration_v0003_runtime_v2_payload(
            t,
            invalid_radius = true,
        )
        for payload, index in projected_invalid_radius_payloads {
            defer delete(payload)
            if !projected_radius_oks[index] do continue
            payload_snapshot := fixture_codec_test_copy(payload)
            result, migration_error, ok := fixture_migration_run_with_registry(
                payload,
                index + 1,
                4,
                fixture_migration_v0003_runtime_registry(),
                runtime.default_allocator(),
            )
            testing.expect(
                t,
                !ok &&
                migration_error.kind == .Step_Failure &&
                migration_error.change_id == FIXTURE_MIGRATION_V0003_BRUSH_PRESET_ID &&
                fixture_migration_result_empty(&result) &&
                fixture_migration_test_bytes_equal(payload, payload_snapshot),
            )
            delete(payload_snapshot)
            fixture_migration_error_dispose(&migration_error)
            fixture_migration_error_dispose(&migration_error)
            fixture_migration_result_dispose(&result)
            fixture_migration_result_dispose(&result)
        }

        future_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        future_allocator := fixture_migration_test_allocator(&future_state)
        future_arena, future_tentative, future_context, future_prepared :=
            fixture_migration_v0003_runtime_prepare_step(t, v3_payload, 3, future_allocator)
        if future_prepared {
            future_context.target_version = 5
            future_error := fixture_migration_step_v0003_to_v0004(&future_context)
            testing.expect(t, future_error.kind == .None && future_tentative.architecture_brush_preset == .Large)
            fixture_migration_error_dispose(&future_error)
            fixture_migration_arena_dispose(future_arena, future_allocator)
            testing.expect(t, future_state.outstanding == 0)
        }

    }

    @(test)
    fixture_migration_v0003_to_v0004_runtime_allocation_failures :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        v1_payload, v1_ok := fixture_migration_v0003_runtime_v1_payload(t)
        v2_payload, v2_ok := fixture_migration_v0003_runtime_v2_payload(t)
        v3_payload, v3_ok := fixture_migration_v0003_runtime_v3_payload(t)
        if !v1_ok || !v2_ok || !v3_ok {
            delete(v1_payload)
            delete(v2_payload)
            delete(v3_payload)
            return
        }
        defer delete(v1_payload)
        defer delete(v2_payload)
        defer delete(v3_payload)

        payloads := [?][]byte{v1_payload, v2_payload, v3_payload}
        for payload, index in payloads {
            fixture_migration_v0003_runtime_wrapper_oom_sweep(t, payload, index + 1)
            fixture_migration_v0003_runtime_runner_oom_sweep(t, payload, index + 1)
        }
    }
}
