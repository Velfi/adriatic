package main

import fixture_v0001 "../packages/fixture_history/v0001"
import fixture_v0002 "../packages/fixture_history/v0002"
import fixture_v0003 "../packages/fixture_history/v0003"
import fixture_v0004 "../packages/fixture_history/v0004"
import flight "../packages/flight"
import hs "../packages/hs"
import postale_game "../packages/postale"
import "base:runtime"
import "core:math"
import "core:mem"
import "core:testing"

when ODIN_TEST {
    fixture_migration_v0004_runtime_steps: [4]Fixture_Migration_Step = {
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
        {
            from_version = 4,
            to_version = 5,
            wrapper = fixture_migration_step_v0004_to_v0005,
            change_id = FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID,
        },
    }

    fixture_migration_v0004_runtime_registry :: proc() -> Fixture_Migration_Registry {
        return {steps = fixture_migration_v0004_runtime_steps[:]}
    }

    fixture_migration_v0004_runtime_basis :: proc(index: int) -> flight.Basis {
        switch index {
        case 0:
            return {forward = {0, 0, -1}, up = {0, 1, 0}, right = {1, 0, 0}}
        case 1:
            return {forward = {1, 0, 0}, up = {0, 1, 0}, right = {0, 0, 1}}
        case 2:
            return {forward = {0, 0, 1}, up = {0, 1, 0}, right = {-1, 0, 0}}
        case 3:
            return {forward = {-1, 0, 0}, up = {0, 1, 0}, right = {0, 0, -1}}
        case:
            return {forward = {0, -1, 0}, up = {0, 0, -1}, right = {1, 0, 0}}
        }
    }

    fixture_migration_v0004_runtime_set_vec3 :: proc(destination: ^$T, source: flight.Vec3) {
        for &component, index in destination {
            component = source[index]
        }
    }

    fixture_migration_v0004_runtime_set_basis :: proc(destination: ^$T, source: flight.Basis) {
        fixture_migration_v0004_runtime_set_vec3(&destination.forward, source.forward)
        fixture_migration_v0004_runtime_set_vec3(&destination.up, source.up)
        fixture_migration_v0004_runtime_set_vec3(&destination.right, source.right)
    }

    fixture_migration_v0004_runtime_seed_legacy_flight :: proc(source: ^$T, source_version: int) {
        base := f32(source_version * 10)
        fixture_migration_v0004_runtime_set_vec3(&source.postale.body.angular_velocity, {base + 1, base + 2, base + 3})
        fixture_migration_v0004_runtime_set_basis(
            &source.postale.body.basis,
            fixture_migration_v0004_runtime_basis((source_version + 0) % 5),
        )
        fixture_migration_v0004_runtime_set_basis(
            &source.postale.spawn_basis,
            fixture_migration_v0004_runtime_basis((source_version + 3) % 5),
        )
        fixture_migration_v0004_runtime_set_vec3(
            &source.libellula.body.angular_velocity,
            {-(base + 4), base + 5, -(base + 6)},
        )
        fixture_migration_v0004_runtime_set_basis(
            &source.libellula.body.basis,
            fixture_migration_v0004_runtime_basis((source_version + 1) % 5),
        )
        fixture_migration_v0004_runtime_set_basis(
            &source.libellula.spawn_basis,
            fixture_migration_v0004_runtime_basis((source_version + 2) % 5),
        )
    }

    fixture_migration_v0004_runtime_seed_legacy :: proc(source: ^$T, source_version: int) {
        base := f32(source_version * 10)
        fixture_migration_v0004_runtime_seed_legacy_flight(source, source_version)
        fixture_migration_v0004_runtime_set_vec3(&source.postale.body.position, {base + 7, base + 8, base + 9})
        fixture_migration_v0004_runtime_set_vec3(&source.postale.body.velocity, {base + 10, base + 11, base + 12})
        source.architecture_brush_strength = base + 13
        source.structure_selected = source_version * 100 + 14
        source.vehicle_showcase_target = "v4-runtime-target"
        source.active_lab_scene = "v4-runtime-lab"
        switch source_version {
        case 1:
            source.aircraft.active = .Postale
        case 2:
            source.aircraft.active = .Libellula
        case:
            source.aircraft.active = .Libellula_Mk2
        }
    }

    fixture_migration_v0004_runtime_seed_common :: proc(source: ^$T, source_version: int) {
        fixture_migration_v0003_runtime_seed_common(source, f32(40 + source_version * 10), f32(10 + source_version))
        fixture_migration_v0004_runtime_seed_legacy(source, source_version)
    }

    fixture_migration_v0004_runtime_v1_payload :: proc(t: ^testing.T, invalid_body_basis := false) -> ([]byte, bool) {
        source := new(fixture_v0001.Fixture)
        fixture_migration_v0004_runtime_seed_common(source, 1)
        if invalid_body_basis do source.postale.body.basis = {}
        source.project.structure_count = 1
        source.project.structures[0].id = 101
        source.architecture_city_plan.count = 1
        source.architecture_city_plan.structures[0].id = 102
        source.architecture_city_plan.alley_count = 1
        source.architecture_city_plan.alleys[0].start_x = 103
        source.farm_count = 1
        payload, ok := fixture_migration_v0003_runtime_encode(t, source)
        free(source)
        return payload, ok
    }

    fixture_migration_v0004_runtime_v2_payload :: proc(t: ^testing.T, invalid_angular := false) -> ([]byte, bool) {
        source := new(fixture_v0002.Fixture)
        fixture_migration_v0004_runtime_seed_common(source, 2)
        if invalid_angular do source.libellula.body.angular_velocity[0] = math.nan_f32()
        source.pilot.mode = .Driving
        payload, ok := fixture_migration_v0003_runtime_encode(t, source)
        free(source)
        return payload, ok
    }

    fixture_migration_v0004_runtime_v3_payload :: proc(t: ^testing.T, invalid_spawn_basis := false) -> ([]byte, bool) {
        source := new(fixture_v0003.Fixture)
        fixture_migration_v0004_runtime_seed_common(source, 3)
        if invalid_spawn_basis do source.libellula.spawn_basis = {}
        source.occupant = .Libellula
        source.pilot.mode = .Driving
        payload, ok := fixture_migration_v0003_runtime_encode(t, source)
        free(source)
        return payload, ok
    }

    fixture_migration_v0004_runtime_v4_payload :: proc(
        t: ^testing.T,
        invalid_basis := false,
        invalid_angular := false,
    ) -> (
        []byte,
        bool,
    ) {
        source := new(fixture_v0004.Fixture)
        fixture_migration_v0004_runtime_seed_legacy(source, 4)
        source.aircraft.slots[0].kind = .Postale
        source.aircraft.slots[1].kind = .Libellula
        source.aircraft.slots[2].kind = .Libellula_Mk2
        source.aircraft.slots[3].kind = .Rondine
        source.aircraft.count = 4
        source.aircraft.active = .Libellula
        source.rondine_visible = true
        source.rondine.vehicle.locked = false
        fixture_migration_v0004_runtime_set_vec3(&source.rondine.body.angular_velocity, {47, 48, 49})
        fixture_migration_v0004_runtime_set_basis(&source.rondine.body.basis, fixture_migration_v0004_runtime_basis(3))
        fixture_migration_v0004_runtime_set_vec3(&source.rondine.body.position, {50, 51, 52})
        if invalid_basis do source.postale.body.basis = {}
        if invalid_angular do source.libellula.body.angular_velocity[0] = math.nan_f32()
        payload, ok := fixture_migration_v0003_runtime_encode(t, source)
        free(source)
        return payload, ok
    }

    fixture_migration_v0004_runtime_expected_angular :: proc(source_version: int, postale: bool) -> flight.Vec3 {
        base := f32(source_version * 10)
        if postale do return {base + 1, base + 2, base + 3}
        return {-(base + 4), base + 5, -(base + 6)}
    }

    fixture_migration_v0004_runtime_expect_result :: proc(
        t: ^testing.T,
        result: ^Fixture_Migration_Result,
        source_version: int,
    ) {
        testing.expect(t, result.fixture != nil && result.arena != nil)
        if result.fixture == nil do return
        fixture := result.fixture
        expected_postale_orientation := flight.orientation_from_basis(
            fixture_migration_v0004_runtime_basis((source_version + 0) % 5),
        )
        expected_libellula_orientation := flight.orientation_from_basis(
            fixture_migration_v0004_runtime_basis((source_version + 1) % 5),
        )
        expected_libellula_spawn := flight.orientation_from_basis(
            fixture_migration_v0004_runtime_basis((source_version + 2) % 5),
        )
        expected_postale_spawn := flight.orientation_from_basis(
            fixture_migration_v0004_runtime_basis((source_version + 3) % 5),
        )
        expected_rondine_orientation := flight.identity_orientation()
        expected_rondine_angular := flight.Vec3{}
        if source_version == 4 {
            expected_rondine_orientation = flight.orientation_from_basis(fixture_migration_v0004_runtime_basis(3))
            expected_rondine_angular = {47, 48, 49}
        }
        expected_tuning := postale_game.ace_tuning_preset()
        expected_body := fixture.postale.body
        expected_runtime := flight.default_ace_runtime(expected_body, expected_tuning)
        base := f32(source_version * 10)

        testing.expect(
            t,
            fixture.postale.body.angular_velocity_world ==
                fixture_migration_v0004_runtime_expected_angular(source_version, true) &&
            fixture.libellula.body.angular_velocity_world ==
                fixture_migration_v0004_runtime_expected_angular(source_version, false) &&
            fixture.rondine.body.angular_velocity_world == expected_rondine_angular,
        )
        testing.expect(
            t,
            fixture.postale.body.orientation == expected_postale_orientation &&
            fixture.libellula.body.orientation == expected_libellula_orientation &&
            fixture.rondine.body.orientation == expected_rondine_orientation &&
            fixture.libellula.spawn_orientation == expected_libellula_spawn &&
            fixture.postale.spawn_orientation == expected_postale_spawn,
        )
        testing.expect(
            t,
            fixture.postale.flight_model == .Current_Aero &&
            fixture.postale.ace_tuning == expected_tuning &&
            fixture.postale.ace_runtime == expected_runtime &&
            fixture.postale.ace_runtime.energy == 0 &&
            fixture.postale.ace_runtime.edge_state == .Free &&
            fixture.postale.ace_runtime.edge_seconds == 0,
        )
        testing.expect(
            t,
            fixture.postale.body.position == flight.Vec3{base + 7, base + 8, base + 9} &&
            fixture.postale.body.velocity == flight.Vec3{base + 10, base + 11, base + 12} &&
            fixture.architecture_brush_strength == base + 13 &&
            fixture.structure_selected == source_version * 100 + 14 &&
            fixture.vehicle_showcase_target == "v4-runtime-target" &&
            fixture.active_lab_scene == "v4-runtime-lab",
        )
        if source_version < 4 {
            testing.expect(
                t,
                !fixture.rondine_visible &&
                fixture.rondine.vehicle.locked &&
                fixture.rondine.body.position == flight.Vec3{} &&
                fixture.rondine.body.velocity == flight.Vec3{} &&
                fixture.aircraft.active != .Rondine,
            )
        } else {
            testing.expect(
                t,
                fixture.rondine_visible &&
                !fixture.rondine.vehicle.locked &&
                fixture.rondine.body.position == flight.Vec3{50, 51, 52},
            )
        }
        if source_version == 1 {
            project_raw := cast(^runtime.Raw_Dynamic_Array)&fixture.project.structures
            testing.expect(
                t,
                len(fixture.project.structures) == 1 &&
                fixture.project.structures[0].id == 101 &&
                project_raw.allocator.data == rawptr(result.arena),
            )
            if len(fixture.project.structures) == 1 {
                previous_length := len(fixture.project.structures)
                appended, append_error := append_elem(&fixture.project.structures, fixture.project.structures[0])
                testing.expect(
                    t,
                    appended == 1 &&
                    append_error == nil &&
                    len(fixture.project.structures) == previous_length + 1 &&
                    project_raw.allocator.data == rawptr(result.arena),
                )
            }
        }
    }

    fixture_migration_v0004_runtime_prepare_step :: proc(
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
            fixture_codec_portable_config(),
            transaction_allocator,
        )
        testing.expect(t, portable_ok && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        if !portable_ok {
            fixture_migration_arena_dispose(arena, block_allocator)
            return nil, nil, {}, false
        }

        for step_index := source_version - 1; step_index < 3; step_index += 1 {
            step := fixture_migration_v0004_runtime_steps[step_index]
            prior_context := Fixture_Migration_Step_Context {
                source_payload        = payload,
                source_version        = source_version,
                target_version        = 5,
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
            target_version        = 5,
            step_from_version     = 4,
            step_to_version       = 5,
            tentative             = tentative,
            transaction_allocator = transaction_allocator,
        }
        return arena, tentative, step_context, true
    }

    fixture_migration_v0004_runtime_snapshot :: proc(
        t: ^testing.T,
        tentative: ^Fixture,
    ) -> (
        snapshot: Fixture_Migration_Structural_Snapshot,
        ok: bool,
    ) {
        allocator := runtime.default_allocator()
        ambient := context.allocator
        context.allocator = allocator
        snapshot, ok = fixture_migration_structural_snapshot(tentative, allocator)
        context.allocator = ambient
        testing.expect(t, ok)
        return
    }

    fixture_migration_v0004_runtime_snapshot_dispose :: proc(snapshot: ^Fixture_Migration_Structural_Snapshot) {
        allocator := runtime.default_allocator()
        ambient := context.allocator
        context.allocator = allocator
        fixture_migration_structural_snapshot_dispose(snapshot)
        context.allocator = ambient
    }

    fixture_migration_v0004_runtime_split_arena_prepare :: proc(
        arena: ^mem.Dynamic_Arena,
        block_allocator, array_allocator: mem.Allocator,
    ) -> bool {
        if arena == nil || block_allocator.procedure == nil || array_allocator.procedure == nil {
            return false
        }
        mem.dynamic_arena_init(
            arena,
            block_allocator = block_allocator,
            array_allocator = array_allocator,
            block_size = FIXTURE_MIGRATION_ARENA_BLOCK_SIZE,
            out_band_size = FIXTURE_MIGRATION_ARENA_OUT_OF_BAND_SIZE,
        )
        return true
    }

    @(test)
    fixture_migration_v0004_to_v0005_runtime_direct_and_complete_chains :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        v1, v1_ok := fixture_migration_v0004_runtime_v1_payload(t)
        v2, v2_ok := fixture_migration_v0004_runtime_v2_payload(t)
        v3, v3_ok := fixture_migration_v0004_runtime_v3_payload(t)
        v4, v4_ok := fixture_migration_v0004_runtime_v4_payload(t)
        if !v1_ok || !v2_ok || !v3_ok || !v4_ok {
            delete(v1)
            delete(v2)
            delete(v3)
            delete(v4)
            return
        }
        defer delete(v1)
        defer delete(v2)
        defer delete(v3)
        defer delete(v4)
        payloads := [?][]byte{v1, v2, v3, v4}
        for payload, index in payloads {
            source_version := index + 1
            payload_snapshot := fixture_codec_test_copy(payload)
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = -1,
            }
            result, error, ok := fixture_migration_run_with_registry(
                payload,
                source_version,
                FIXTURE_SCHEMA_VERSION,
                fixture_migration_production_registry(),
                fixture_migration_test_allocator(&state),
            )
            testing.expect(
                t,
                ok && error.kind == .None && fixture_migration_test_bytes_equal(payload, payload_snapshot),
            )
            if ok do fixture_migration_v0004_runtime_expect_result(t, &result, source_version)
            fixture_migration_error_dispose(&error)
            fixture_migration_error_dispose(&error)
            fixture_migration_result_dispose(&result)
            fixture_migration_result_dispose(&result)
            delete(payload_snapshot)
            testing.expect(t, state.outstanding == 0)
        }

        block_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        array_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        block_allocator := fixture_migration_test_allocator(&block_state)
        array_allocator := fixture_migration_test_allocator(&array_state)
        split_arena: mem.Dynamic_Arena
        split_ready := fixture_migration_v0004_runtime_split_arena_prepare(
            &split_arena,
            block_allocator,
            array_allocator,
        )
        testing.expect(t, split_ready)
        if split_ready {
            split_allocator := mem.dynamic_arena_allocator(&split_arena)
            split_tentative := new(Fixture, split_allocator)
            testing.expect(t, split_tentative != nil)
            if split_tentative != nil {
                portable_error, portable_ok := hs.portable_decode(
                    fixture_codec_value(split_tentative),
                    v4,
                    fixture_codec_portable_config(),
                    split_allocator,
                )
                testing.expect(t, portable_ok && portable_error.kind == .None)
                hs.portable_error_dispose(&portable_error)
                if portable_ok {
                    split_context := Fixture_Migration_Step_Context {
                        source_payload        = v4,
                        source_version        = 4,
                        target_version        = 5,
                        step_from_version     = 4,
                        step_to_version       = 5,
                        tentative             = split_tentative,
                        transaction_allocator = split_allocator,
                    }
                    split_error := fixture_migration_step_v0004_to_v0005(&split_context)
                    testing.expect(t, split_error.kind == .None)
                    split_result := Fixture_Migration_Result {
                        fixture = split_tentative,
                        arena   = &split_arena,
                    }
                    if split_error.kind == .None {
                        fixture_migration_v0004_runtime_expect_result(t, &split_result, 4)
                    }
                    fixture_migration_error_dispose(&split_error)
                }
            }
            mem.dynamic_arena_destroy(&split_arena)
        }
        testing.expect(t, block_state.outstanding == 0)
        testing.expect(t, array_state.outstanding == 0)
        testing.expect(t, block_state.allocation_calls > 0)
        testing.expect(t, array_state.allocation_calls > 0)

        production := fixture_migration_production_registry()
        testing.expect(
            t,
            FIXTURE_SCHEMA_VERSION == 9 &&
            len(production.steps) == 8 &&
            production.steps[0].from_version == 1 &&
            production.steps[0].to_version == 2 &&
            production.steps[0].wrapper == fixture_migration_step_v0001_to_v0002 &&
            production.steps[0].change_id == "field-add:adriatic:packages/farmland.Plan.height" &&
            production.steps[1].from_version == 2 &&
            production.steps[1].to_version == 3 &&
            production.steps[1].wrapper == fixture_migration_step_v0002_to_v0003 &&
            production.steps[1].change_id == "field-add:adriatic:src.Fixture.occupant" &&
            production.steps[2].from_version == 3 &&
            production.steps[2].to_version == 4 &&
            production.steps[2].wrapper == fixture_migration_step_v0003_to_v0004 &&
            production.steps[2].change_id == FIXTURE_MIGRATION_V0003_SETTLEMENT_ID &&
            production.steps[3].from_version == 4 &&
            production.steps[3].to_version == 5 &&
            production.steps[3].wrapper == fixture_migration_step_v0004_to_v0005 &&
            production.steps[3].change_id == FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID &&
            production.steps[4].from_version == 5 &&
            production.steps[4].to_version == 6 &&
            production.steps[4].wrapper == fixture_migration_step_v0005_to_v0006 &&
            production.steps[4].change_id == "field-type:adriatic:packages/terrain.Clipmap_Level.heights",
        )

        result, migration_error, migrated := fixture_migration_run_with_registry(
            v4,
            4,
            FIXTURE_SCHEMA_VERSION,
            production,
            runtime.default_allocator(),
        )
        testing.expect(t, migrated && migration_error.kind == .None)
        if migrated {
            container, encode_error, encoded := fixture_codec_encode(result.fixture, context.allocator)
            testing.expect(t, encoded && encode_error.kind == .None)
            if encoded {
                decoded, decode_error, decoded_ok := fixture_codec_decode(container, runtime.default_allocator())
                testing.expect(t, decoded_ok && decode_error.kind == .None)
                fixture_codec_error_dispose(&decode_error)
                fixture_codec_error_dispose(&decode_error)
                fixture_migration_result_dispose(&decoded)
                fixture_migration_result_dispose(&decoded)
                delete(container)
            }
            fixture_codec_error_dispose(&encode_error)
            fixture_codec_error_dispose(&encode_error)
        }
        fixture_migration_error_dispose(&migration_error)
        fixture_migration_result_dispose(&result)

        provenance_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        provenance_result, provenance_error, provenance_ok := fixture_migration_run(
            v4,
            FIXTURE_SCHEMA_VERSION,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_test_allocator(&provenance_state),
        )
        testing.expect(t, !provenance_ok && provenance_error.kind == .Tentative_Decode)
        testing.expect(t, fixture_migration_result_empty(&provenance_result))
        fixture_migration_error_dispose(&provenance_error)
        fixture_migration_result_dispose(&provenance_result)
        testing.expect(t, provenance_state.outstanding == 0)

        future_result, future_error, future_ok := fixture_migration_run(
            v4,
            FIXTURE_SCHEMA_VERSION,
            FIXTURE_SCHEMA_VERSION + 1,
            runtime.default_allocator(),
        )
        testing.expect(t, !future_ok && future_error.kind == .Unsupported_Version)
        testing.expect(t, fixture_migration_result_empty(&future_result))
        fixture_migration_error_dispose(&future_error)
        fixture_migration_result_dispose(&future_result)
    }

    fixture_migration_v0004_runtime_expect_invalid_context :: proc(
        t: ^testing.T,
        step_context: ^Fixture_Migration_Step_Context,
        tentative: ^Fixture,
        state: ^fixture_migration_test_allocator_state,
        snapshot: Fixture_Migration_Structural_Snapshot,
    ) {
        before_calls := state.allocation_calls
        before_outstanding := state.outstanding
        error := fixture_migration_step_v0004_to_v0005(step_context)
        testing.expect(
            t,
            error.kind == .Invalid_Argument &&
            error.change_id == "" &&
            state.allocation_calls == before_calls &&
            state.outstanding == before_outstanding &&
            fixture_migration_structural_snapshot_matches(snapshot, tentative),
        )
        fixture_migration_error_dispose(&error)
        fixture_migration_error_dispose(&error)
    }

    @(test)
    fixture_migration_v0004_to_v0005_runtime_hostile_contexts_and_payloads :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        v2, v2_ok := fixture_migration_v0004_runtime_v2_payload(t)
        v3, v3_ok := fixture_migration_v0004_runtime_v3_payload(t)
        v4, v4_ok := fixture_migration_v0004_runtime_v4_payload(t)
        bad_v1_basis, bad_v1_basis_ok := fixture_migration_v0004_runtime_v1_payload(t, invalid_body_basis = true)
        bad_v2_angular, bad_v2_angular_ok := fixture_migration_v0004_runtime_v2_payload(t, invalid_angular = true)
        bad_v3_spawn, bad_v3_spawn_ok := fixture_migration_v0004_runtime_v3_payload(t, invalid_spawn_basis = true)
        bad_basis, bad_basis_ok := fixture_migration_v0004_runtime_v4_payload(t, invalid_basis = true)
        bad_angular, bad_angular_ok := fixture_migration_v0004_runtime_v4_payload(t, invalid_angular = true)
        if !v2_ok ||
           !v3_ok ||
           !v4_ok ||
           !bad_v1_basis_ok ||
           !bad_v2_angular_ok ||
           !bad_v3_spawn_ok ||
           !bad_basis_ok ||
           !bad_angular_ok {
            return
        }
        defer delete(v2)
        defer delete(v3)
        defer delete(v4)
        defer delete(bad_v1_basis)
        defer delete(bad_v2_angular)
        defer delete(bad_v3_spawn)
        defer delete(bad_basis)
        defer delete(bad_angular)

        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        allocator := fixture_migration_test_allocator(&state)
        arena, tentative, valid_context, prepared := fixture_migration_v0004_runtime_prepare_step(t, v4, 4, allocator)
        if !prepared do return
        defer {
            fixture_migration_arena_dispose(arena, allocator)
            testing.expect(t, state.outstanding == 0)
        }
        snapshot, snapshot_ok := fixture_migration_v0004_runtime_snapshot(t, tentative)
        if !snapshot_ok do return
        defer fixture_migration_v0004_runtime_snapshot_dispose(&snapshot)

        nil_error := fixture_migration_step_v0004_to_v0005(nil)
        testing.expect(t, nil_error.kind == .Invalid_Argument)
        bad := valid_context
        bad.tentative = nil
        fixture_migration_v0004_runtime_expect_invalid_context(t, &bad, tentative, &state, snapshot)
        bad = valid_context
        bad.source_version = 0
        fixture_migration_v0004_runtime_expect_invalid_context(t, &bad, tentative, &state, snapshot)
        bad.source_version = 5
        fixture_migration_v0004_runtime_expect_invalid_context(t, &bad, tentative, &state, snapshot)
        bad = valid_context
        bad.target_version = 4
        fixture_migration_v0004_runtime_expect_invalid_context(t, &bad, tentative, &state, snapshot)
        bad = valid_context
        bad.step_from_version = 3
        fixture_migration_v0004_runtime_expect_invalid_context(t, &bad, tentative, &state, snapshot)
        bad = valid_context
        bad.step_to_version = 6
        fixture_migration_v0004_runtime_expect_invalid_context(t, &bad, tentative, &state, snapshot)
        bad = valid_context
        bad.transaction_allocator = {}
        fixture_migration_v0004_runtime_expect_invalid_context(t, &bad, tentative, &state, snapshot)
        bad.transaction_allocator = {
            procedure = mem.dynamic_arena_allocator_proc,
            data      = nil,
        }
        fixture_migration_v0004_runtime_expect_invalid_context(t, &bad, tentative, &state, snapshot)

        block_allocator := arena.block_allocator
        arena.block_allocator = {}
        fixture_migration_v0004_runtime_expect_invalid_context(t, &valid_context, tentative, &state, snapshot)
        arena.block_allocator = block_allocator

        claimed_v2 := valid_context
        claimed_v2.source_payload = v3
        claimed_v2.source_version = 2
        error := fixture_migration_step_v0004_to_v0005(&claimed_v2)
        testing.expect(
            t,
            error.kind == .Historical_Decode && fixture_migration_structural_snapshot_matches(snapshot, tentative),
        )
        fixture_migration_error_dispose(&error)

        corrupted := fixture_codec_test_copy(v4)
        corrupted[0] = corrupted[0] ~ 0xff
        corrupt_context := valid_context
        corrupt_context.source_payload = corrupted
        error = fixture_migration_step_v0004_to_v0005(&corrupt_context)
        testing.expect(
            t,
            error.kind == .Historical_Decode && fixture_migration_structural_snapshot_matches(snapshot, tentative),
        )
        fixture_migration_error_dispose(&error)
        delete(corrupted)

        project_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        project_allocator := fixture_migration_test_allocator(&project_state)
        project_arena, project_tentative, project_context, project_prepared :=
            fixture_migration_v0004_runtime_prepare_step(t, v3, 3, project_allocator)
        if project_prepared {
            raw := cast(^runtime.Raw_Dynamic_Array)&project_tentative.project.structures
            old_len, old_cap := raw.len, raw.cap
            raw.len, raw.cap = -1, -1
            root_snapshot := make([]byte, size_of(Fixture), runtime.default_allocator())
            copy(root_snapshot, mem.slice_ptr(cast([^]u8)project_tentative, size_of(Fixture)))
            error = fixture_migration_step_v0004_to_v0005(&project_context)
            testing.expect(
                t,
                error.kind == .Step_Failure &&
                fixture_migration_test_bytes_equal(
                    root_snapshot,
                    mem.slice_ptr(cast([^]u8)project_tentative, size_of(Fixture)),
                ),
            )
            fixture_migration_error_dispose(&error)
            delete(root_snapshot, runtime.default_allocator())
            raw.len, raw.cap = old_len, old_cap
            fixture_migration_arena_dispose(project_arena, project_allocator)
            testing.expect(t, project_state.outstanding == 0)
        }

        hostile_payloads := [?][]byte{bad_v1_basis, bad_v2_angular, bad_v3_spawn, bad_basis, bad_angular}
        hostile_versions := [?]int{1, 2, 3, 4, 4}
        hostile_ids := [?]string {
            FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID,
            FIXTURE_MIGRATION_V0004_TO_V0005_ANGULAR_ID,
            FIXTURE_MIGRATION_V0004_TO_V0005_LIBELLULA_SPAWN_ID,
            FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID,
            FIXTURE_MIGRATION_V0004_TO_V0005_ANGULAR_ID,
        }
        for hostile_payload, index in hostile_payloads {
            payload_snapshot := fixture_codec_test_copy(hostile_payload)
            hostile_state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = -1,
            }
            result, hostile_error, ok := fixture_migration_run_with_registry(
                hostile_payload,
                hostile_versions[index],
                FIXTURE_SCHEMA_VERSION,
                fixture_migration_production_registry(),
                fixture_migration_test_allocator(&hostile_state),
            )
            testing.expect(
                t,
                !ok &&
                hostile_error.kind == .Step_Failure &&
                hostile_error.change_id == hostile_ids[index] &&
                fixture_migration_result_empty(&result) &&
                fixture_migration_test_bytes_equal(hostile_payload, payload_snapshot),
            )
            fixture_migration_error_dispose(&hostile_error)
            fixture_migration_error_dispose(&hostile_error)
            fixture_migration_result_dispose(&result)
            fixture_migration_result_dispose(&result)
            delete(payload_snapshot)
            testing.expect(t, hostile_state.outstanding == 0)
        }
    }

    fixture_migration_v0004_runtime_wrapper_oom_sweep :: proc(t: ^testing.T, payload: []byte, source_version: int) {
        measurement_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        measurement_allocator := fixture_migration_test_allocator(&measurement_state)
        measurement_arena, _, measurement_context, prepared := fixture_migration_v0004_runtime_prepare_step(
            t,
            payload,
            source_version,
            measurement_allocator,
        )
        if !prepared do return
        measurement_state.allocation_calls = 0
        error := fixture_migration_step_v0004_to_v0005(&measurement_context)
        allocation_calls := measurement_state.allocation_calls
        testing.expect(t, error.kind == .None && allocation_calls > 0)
        fixture_migration_error_dispose(&error)
        fixture_migration_arena_dispose(measurement_arena, measurement_allocator)
        testing.expect(t, measurement_state.outstanding == 0)

        payload_snapshot := fixture_codec_test_copy(payload)
        defer delete(payload_snapshot)
        for fail_at in 0 ..< allocation_calls {
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = -1,
            }
            allocator := fixture_migration_test_allocator(&state)
            arena, tentative, step_context, step_prepared := fixture_migration_v0004_runtime_prepare_step(
                t,
                payload,
                source_version,
                allocator,
            )
            if !step_prepared do return
            snapshot, snapshot_ok := fixture_migration_v0004_runtime_snapshot(t, tentative)
            if !snapshot_ok {
                fixture_migration_arena_dispose(arena, allocator)
                return
            }
            outstanding := state.outstanding
            state.allocation_calls = 0
            state.fail_at = fail_at
            error = fixture_migration_step_v0004_to_v0005(&step_context)
            testing.expect(
                t,
                error.kind == .Out_Of_Memory &&
                error.change_id == "" &&
                state.outstanding == outstanding &&
                fixture_migration_structural_snapshot_matches(snapshot, tentative) &&
                fixture_migration_test_bytes_equal(payload, payload_snapshot),
            )
            fixture_migration_error_dispose(&error)
            fixture_migration_error_dispose(&error)
            fixture_migration_v0004_runtime_snapshot_dispose(&snapshot)
            state.fail_at = -1
            fixture_migration_arena_dispose(arena, allocator)
            testing.expect(t, state.outstanding == 0)
        }
    }

    fixture_migration_v0004_runtime_transaction_oom_sweep :: proc(
        t: ^testing.T,
        payload: []byte,
        source_version: int,
    ) {
        measurement_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        result, error, ok := fixture_migration_run_with_registry(
            payload,
            source_version,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_production_registry(),
            fixture_migration_test_allocator(&measurement_state),
        )
        allocation_calls := measurement_state.allocation_calls
        testing.expect(t, ok && error.kind == .None && allocation_calls > 0)
        fixture_migration_error_dispose(&error)
        fixture_migration_result_dispose(&result)
        testing.expect(t, measurement_state.outstanding == 0)

        payload_snapshot := fixture_codec_test_copy(payload)
        defer delete(payload_snapshot)
        for fail_at in 0 ..< allocation_calls {
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = fail_at,
            }
            result, error, ok = fixture_migration_run_with_registry(
                payload,
                source_version,
                FIXTURE_SCHEMA_VERSION,
                fixture_migration_production_registry(),
                fixture_migration_test_allocator(&state),
            )
            testing.expect(
                t,
                !ok &&
                error.kind == .Out_Of_Memory &&
                fixture_migration_result_empty(&result) &&
                fixture_migration_test_bytes_equal(payload, payload_snapshot),
            )
            fixture_migration_error_dispose(&error)
            fixture_migration_error_dispose(&error)
            fixture_migration_result_dispose(&result)
            fixture_migration_result_dispose(&result)
            testing.expect(t, state.outstanding == 0)
        }
    }

    fixture_migration_v0004_runtime_projection_arena_prepare :: proc(
        arena: ^mem.Dynamic_Arena,
        allocator: mem.Allocator,
    ) -> bool {
        if arena == nil || allocator.procedure == nil do return false
        mem.dynamic_arena_init(
            arena,
            block_allocator = allocator,
            array_allocator = allocator,
            block_size = 8 * mem.Megabyte,
            out_band_size = mem.Megabyte,
        )
        unused_blocks, allocation_error := make([dynamic]rawptr, 0, 64, allocator)
        if allocation_error != nil {
            mem.dynamic_arena_destroy(arena)
            return false
        }
        arena.unused_blocks = unused_blocks
        used_blocks: [dynamic]rawptr
        used_blocks, allocation_error = make([dynamic]rawptr, 0, 64, allocator)
        if allocation_error != nil {
            mem.dynamic_arena_destroy(arena)
            return false
        }
        arena.used_blocks = used_blocks
        out_band_allocations: [dynamic]rawptr
        out_band_allocations, allocation_error = make([dynamic]rawptr, 0, 64, allocator)
        if allocation_error != nil {
            mem.dynamic_arena_destroy(arena)
            return false
        }
        arena.out_band_allocations = out_band_allocations
        return true
    }

    fixture_migration_v0004_runtime_projection_decode_oom_sweep :: proc(t: ^testing.T) {
        live := new(Fixture)
        testing.expect(t, live != nil)
        if live == nil do return
        projected_payload, encode_error, encoded := hs.portable_encode(
            fixture_codec_value(live),
            fixture_codec_portable_config(),
            context.allocator,
        )
        free(live)
        testing.expect(t, encoded && encode_error.kind == .None)
        hs.portable_error_dispose(&encode_error)
        if !encoded do return
        defer delete(projected_payload)
        payload_snapshot := fixture_codec_test_copy(projected_payload)
        defer delete(payload_snapshot)

        measurement_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        measurement_allocator := fixture_migration_test_allocator(&measurement_state)
        measurement_arena: mem.Dynamic_Arena
        measurement_ready := fixture_migration_v0004_runtime_projection_arena_prepare(
            &measurement_arena,
            measurement_allocator,
        )
        testing.expect(t, measurement_ready)
        if !measurement_ready do return
        historical := new(fixture_v0004.Fixture, runtime.default_allocator())
        testing.expect(t, historical != nil)
        if historical == nil {
            mem.dynamic_arena_destroy(&measurement_arena)
            return
        }
        measurement_state.allocation_calls = 0
        error := fixture_migration_v0004_decode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0004.Fixture)},
            projected_payload,
            false,
            mem.dynamic_arena_allocator(&measurement_arena),
            .Step_Failure,
        )
        allocation_calls := measurement_state.allocation_calls
        testing.expect(t, error.kind == .None && allocation_calls > 0)
        fixture_migration_error_dispose(&error)
        free(historical, runtime.default_allocator())
        mem.dynamic_arena_destroy(&measurement_arena)
        testing.expect(t, measurement_state.outstanding == 0)

        for fail_at in 0 ..< allocation_calls {
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = -1,
            }
            allocator := fixture_migration_test_allocator(&state)
            arena: mem.Dynamic_Arena
            arena_ready := fixture_migration_v0004_runtime_projection_arena_prepare(&arena, allocator)
            testing.expect(t, arena_ready)
            if !arena_ready do return
            historical = new(fixture_v0004.Fixture, runtime.default_allocator())
            testing.expect(t, historical != nil)
            if historical == nil {
                mem.dynamic_arena_destroy(&arena)
                return
            }
            state.allocation_calls = 0
            state.fail_at = fail_at
            error = fixture_migration_v0004_decode(
                any{data = rawptr(historical), id = typeid_of(fixture_v0004.Fixture)},
                projected_payload,
                false,
                mem.dynamic_arena_allocator(&arena),
                .Step_Failure,
            )
            testing.expect(
                t,
                error.kind == .Out_Of_Memory &&
                error.change_id == "" &&
                fixture_migration_test_bytes_equal(projected_payload, payload_snapshot),
            )
            fixture_migration_error_dispose(&error)
            fixture_migration_error_dispose(&error)
            free(historical, runtime.default_allocator())
            state.fail_at = -1
            mem.dynamic_arena_destroy(&arena)
            testing.expect(t, state.outstanding == 0)
        }
    }

    @(test)
    fixture_migration_v0004_to_v0005_runtime_allocation_failures :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        v1, v1_ok := fixture_migration_v0004_runtime_v1_payload(t)
        v2, v2_ok := fixture_migration_v0004_runtime_v2_payload(t)
        v3, v3_ok := fixture_migration_v0004_runtime_v3_payload(t)
        v4, v4_ok := fixture_migration_v0004_runtime_v4_payload(t)
        if !v1_ok || !v2_ok || !v3_ok || !v4_ok {
            delete(v1)
            delete(v2)
            delete(v3)
            delete(v4)
            return
        }
        defer delete(v1)
        defer delete(v2)
        defer delete(v3)
        defer delete(v4)

        payloads := [?][]byte{v1, v2, v3, v4}
        for payload, index in payloads {
            source_version := index + 1
            fixture_migration_v0004_runtime_wrapper_oom_sweep(t, payload, source_version)
            fixture_migration_v0004_runtime_transaction_oom_sweep(t, payload, source_version)
        }
        fixture_migration_v0004_runtime_projection_decode_oom_sweep(t)
    }
}
