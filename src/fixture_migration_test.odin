package main

import architecture "../packages/architecture"
import fixture_v0001 "../packages/fixture_history/v0001"
import hs "../packages/hs"
import terrain "../packages/terrain"
import "base:runtime"
import "core:mem"
import "core:testing"

when ODIN_TEST {
    fixture_migration_test_current_payload :: proc(t: ^testing.T) -> ([]byte, bool) {
        source := fixture_codec_test_source()
        defer fixture_codec_test_destroy_source(source)
        payload, error, ok := hs.portable_encode(
            fixture_codec_value(source),
            fixture_codec_portable_config(),
            context.allocator,
        )
        testing.expect(t, ok && error.kind == .None)
        hs.portable_error_dispose(&error)
        return payload, ok
    }

    fixture_migration_test_historical_payload :: proc(t: ^testing.T) -> ([]byte, bool) {
        historical := new(fixture_v0001.Fixture)
        historical.project.sea_level = f32(12.75)
        historical.project.revision = 77
        historical.project.structures[0].id = 0x1111
        historical.project.structures[0].kind = .Rock
        historical.project.structures[0].center_x = 18
        historical.project.structures[0].center_z = -24
        historical.project.structure_count = 1
        historical.project.next_structure_id = 2

        historical.authoring_tool = .Marina
        historical.editor_ui.left_collapsed = true
        historical.tool = .Paint
        historical.radius = f32(6.25)
        historical.strength = f32(.73)
        historical.structure_selected = 4
        historical.structure_kind = .Rock
        historical.architecture_city_plan.count = 1
        historical.architecture_city_plan.structures[0].id = 0xabc
        historical.architecture_city_plan.structures[0].kind = .Architecture
        historical.architecture_city_plan.structures[0].center_x = 44
        historical.architecture_city_plan.structures[0].center_z = -11
        historical.architecture_city_plan.parcels[0].corners[0] = {1, 2}
        historical.architecture_city_plan.parcels[0].corners[1] = {3, 4}
        historical.architecture_city_plan.parcels[0].frontage_width = 12
        historical.architecture_city_plan.parcels[0].depth = 18
        historical.architecture_city_plan.parcels[0].density = f32(.75)
        historical.architecture_city_plan.parcels[0].seed = 0x50415243
        historical.architecture_city_plan.parcels[0].attached = true
        historical.architecture_city_plan.parcels[0].alley_frontage = true
        historical.architecture_city_plan.parcel_count = 1
        historical.architecture_city_plan.alleys[0] = {
            start_x    = 5,
            start_z    = -6,
            end_x      = 25,
            end_z      = 26,
            half_width = f32(1.5),
        }
        historical.architecture_city_plan.alley_count = 1
        historical.architecture_city_plan.lamps[0] = {
            x   = 33,
            z   = -34,
            yaw = f32(.6),
        }
        historical.architecture_city_plan.lamp_count = 1

        historical.marina_authored = true
        historical.farms[0].origin_x = f32(101)
        historical.farms[0].origin_z = f32(-202)
        historical.farms[0].yaw = f32(.35)
        historical.farms[0].plan.seed = 0x4641524d
        historical.farms[0].plan.parcels[0].min_x = 1
        historical.farms[0].plan.parcels[0].max_x = 25
        historical.farms[0].plan.parcels[0].min_z = -19
        historical.farms[0].plan.parcels[0].max_z = 19
        historical.farms[0].plan.parcel_count = 1
        historical.farms[0].plan.valid = true
        historical.farm_count = 1
        historical.vehicle_showcase_target = "historical-target"
        historical.active_lab_scene = "historical-lab"
        payload, error, ok := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0001.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        free(historical)
        testing.expect(t, ok && error.kind == .None)
        hs.portable_error_dispose(&error)
        return payload, ok
    }

    fixture_migration_test_step_one :: proc(step_context: ^Fixture_Migration_Step_Context) -> Fixture_Migration_Error {
        state := fixture_migration_test_context_state(step_context)
        if !fixture_migration_test_context_validate(step_context, state, 1, 2) {
            return {kind = .Invalid_Argument}
        }
        tentative := step_context.tentative
        allocator := step_context.transaction_allocator
        scratch, allocation_error := mem.alloc_bytes(64 * mem.Megabyte, 1, allocator)
        if allocation_error != nil || scratch == nil do return {kind = .Out_Of_Memory}
        _ = scratch
        if tentative.project.structures[0].id != 0x1111 || tentative.architecture_city_plan.structures[0].id != 0xabc {
            return {kind = .Step_Failure}
        }
        project_structures := cast(^runtime.Raw_Dynamic_Array)(&tentative.project.structures)
        city_structures := cast(^runtime.Raw_Dynamic_Array)(&tentative.architecture_city_plan.structures)
        city_parcels := cast(^runtime.Raw_Dynamic_Array)(&tentative.architecture_city_plan.parcels)
        city_alleys := cast(^runtime.Raw_Dynamic_Array)(&tentative.architecture_city_plan.alleys)
        city_lamps := cast(^runtime.Raw_Dynamic_Array)(&tentative.architecture_city_plan.lamps)
        if project_structures.len != 256 ||
           project_structures.cap != 256 ||
           city_structures.len != 256 ||
           city_structures.cap != 256 ||
           city_parcels.len != 256 ||
           city_parcels.cap != 256 ||
           city_alleys.len != 128 ||
           city_alleys.cap != 128 ||
           city_lamps.len != 256 ||
           city_lamps.cap != 256 ||
           tentative.authoring_tool != .Marina ||
           tentative.farm_count != 1 ||
           tentative.vehicle_showcase_target != "historical-target" {
            return {kind = .Step_Failure}
        }
        tentative.structure_selected += 1
        return {}
    }

    fixture_migration_test_step_two :: proc(step_context: ^Fixture_Migration_Step_Context) -> Fixture_Migration_Error {
        state := fixture_migration_test_context_state(step_context)
        if !fixture_migration_test_context_validate(step_context, state, 2, 3) {
            return {kind = .Invalid_Argument}
        }
        tentative := step_context.tentative
        allocator := step_context.transaction_allocator
        scratch, allocation_error := mem.alloc_bytes(64 * mem.Megabyte, 1, allocator)
        if allocation_error != nil || scratch == nil do return {kind = .Out_Of_Memory}
        _ = scratch
        if step_context.source_version == 1 {
            if tentative.structure_selected != 5 do return {kind = .Step_Failure}
            tentative.structure_selected = tentative.structure_selected * 10 + 2
        } else {
            if step_context.source_version != 2 || tentative.structure_selected != 0 do return {kind = .Step_Failure}
            tentative.structure_selected = 2
        }
        return {}
    }

    fixture_migration_test_step_mutate_then_fail :: proc(
        step_context: ^Fixture_Migration_Step_Context,
    ) -> Fixture_Migration_Error {
        state := fixture_migration_test_context_state(step_context)
        if !fixture_migration_test_context_validate(step_context, state, 1, 2) {
            return {kind = .Invalid_Argument}
        }
        if step_context.tentative != nil {
            step_context.tentative.structure_selected = 999
        }
        return {kind = .Step_Failure}
    }

    fixture_migration_test_step_incompatible_history :: proc(
        step_context: ^Fixture_Migration_Step_Context,
    ) -> Fixture_Migration_Error {
        if step_context == nil || step_context.tentative == nil || len(step_context.source_payload) == 0 {
            return {kind = .Invalid_Argument}
        }
        allocator := step_context.transaction_allocator
        historical := new(fixture_v0001.Fixture, allocator)
        if historical == nil do return {kind = .Out_Of_Memory}
        historical_value := any {
            data = rawptr(historical),
            id   = typeid_of(fixture_v0001.Fixture),
        }
        error, ok := hs.portable_decode(
            historical_value,
            step_context.source_payload[:len(step_context.source_payload) - 1],
            fixture_codec_portable_config(),
            allocator,
        )
        if ok {
            hs.portable_error_dispose(&error)
            return {kind = .Step_Failure}
        }
        error_kind := fixture_migration_decode_kind(error, .Historical_Decode)
        hs.portable_error_dispose(&error)
        return {kind = error_kind}
    }

    fixture_migration_test_bytes_equal :: proc(left, right: []byte) -> bool {
        if len(left) != len(right) do return false
        for index in 0 ..< len(left) {
            if left[index] != right[index] do return false
        }
        return true
    }

    fixture_migration_test_allocator_state :: struct {
        base:                    mem.Allocator,
        fail_at:                 int,
        allocation_calls:        int,
        outstanding:             int,
        expected_payload:        []byte,
        expected_source_version: int,
        expected_target_version: int,
        context_calls:           int,
    }

    fixture_migration_test_allocator_proc :: proc(
        data: rawptr,
        mode: mem.Allocator_Mode,
        size, alignment: int,
        old_memory: rawptr,
        old_size: int,
        location := #caller_location,
    ) -> (
        []byte,
        mem.Allocator_Error,
    ) {
        state := cast(^fixture_migration_test_allocator_state)data
        if state == nil || state.base.procedure == nil do return nil, .Invalid_Argument
        if mode == .Alloc || mode == .Alloc_Non_Zeroed {
            call_index := state.allocation_calls
            state.allocation_calls += 1
            if state.fail_at >= 0 && call_index == state.fail_at {
                return nil, .Out_Of_Memory
            }
        }
        result, error := state.base.procedure(state.base.data, mode, size, alignment, old_memory, old_size, location)
        if (mode == .Alloc || mode == .Alloc_Non_Zeroed) && error == nil && result != nil {
            state.outstanding += 1
        }
        if mode == .Free && error == nil && old_memory != nil {
            state.outstanding -= 1
        }
        return result, error
    }

    fixture_migration_test_allocator :: proc(state: ^fixture_migration_test_allocator_state) -> mem.Allocator {
        return {procedure = fixture_migration_test_allocator_proc, data = rawptr(state)}
    }

    fixture_migration_test_context_state :: proc(
        step_context: ^Fixture_Migration_Step_Context,
    ) -> ^fixture_migration_test_allocator_state {
        if step_context == nil || step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
            return nil
        }
        transaction_arena := cast(^mem.Dynamic_Arena)step_context.transaction_allocator.data
        if transaction_arena == nil ||
           transaction_arena.block_allocator.procedure != fixture_migration_test_allocator_proc {
            return nil
        }
        return cast(^fixture_migration_test_allocator_state)transaction_arena.block_allocator.data
    }

    fixture_migration_test_context_validate :: proc(
        step_context: ^Fixture_Migration_Step_Context,
        state: ^fixture_migration_test_allocator_state,
        expected_step_from, expected_step_to: int,
    ) -> bool {
        if step_context == nil ||
           step_context.tentative == nil ||
           step_context.source_version <= 0 ||
           step_context.target_version < step_context.source_version ||
           step_context.step_from_version != expected_step_from ||
           step_context.step_to_version != expected_step_to {
            return false
        }
        transaction_arena := cast(^mem.Dynamic_Arena)step_context.transaction_allocator.data
        if step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc ||
           transaction_arena == nil ||
           transaction_arena.block_allocator.procedure == nil {
            return false
        }
        tentative_structures := cast(^runtime.Raw_Dynamic_Array)(&step_context.tentative.project.structures)
        if tentative_structures.allocator.procedure != mem.dynamic_arena_allocator_proc ||
           tentative_structures.allocator.data != rawptr(transaction_arena) {
            return false
        }
        if state != nil {
            if transaction_arena.block_allocator.data != rawptr(state) {
                return false
            }
            if state.expected_source_version != 0 && step_context.source_version != state.expected_source_version {
                return false
            }
            if state.expected_target_version != 0 && step_context.target_version != state.expected_target_version {
                return false
            }
            if state.expected_payload != nil &&
               !fixture_migration_test_bytes_equal(step_context.source_payload, state.expected_payload) {
                return false
            }
            state.context_calls += 1
        }
        return true
    }

    @(test)
    fixture_migration_transaction_paths_and_ownership :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        current_payload, current_ok := fixture_migration_test_current_payload(t)
        if !current_ok do return
        defer delete(current_payload)
        current_snapshot := make([]byte, len(current_payload), context.allocator)
        copy(current_snapshot, current_payload)
        defer delete(current_snapshot)

        current_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        current_result, current_error, current_run_ok := fixture_migration_run(
            current_payload,
            FIXTURE_SCHEMA_VERSION,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_test_allocator(&current_state),
        )
        testing.expect(t, current_run_ok && current_error.kind == .None)
        if current_run_ok {
            testing.expect(t, current_result.fixture != nil)
            testing.expect(t, current_result.fixture.structure_selected == 0)
            testing.expect(t, current_result.fixture.occupant == .On_Foot)
            current_structures := cast(^runtime.Raw_Dynamic_Array)(&current_result.fixture.architecture_city_plan.structures)
            testing.expect(t, current_structures.allocator.data == rawptr(current_result.arena))
            previous_length := len(current_result.fixture.architecture_city_plan.structures)
            append(&current_result.fixture.architecture_city_plan.structures, terrain.Structure{})
            testing.expect(t, len(current_result.fixture.architecture_city_plan.structures) == previous_length + 1)
        }
        fixture_migration_error_dispose(&current_error)
        fixture_migration_result_dispose(&current_result)
        fixture_migration_result_dispose(&current_result)
        testing.expect(t, fixture_migration_result_empty(&current_result))
        testing.expect(t, current_state.context_calls == 0 && current_state.outstanding == 0)

        historical_payload, historical_ok := fixture_migration_test_historical_payload(t)
        if !historical_ok do return
        defer delete(historical_payload)
        historical_snapshot := make([]byte, len(historical_payload), context.allocator)
        copy(historical_snapshot, historical_payload)
        defer delete(historical_snapshot)

        test_steps := [2]Fixture_Migration_Step {
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_one, change_id = "test:one"},
            {from_version = 2, to_version = 3, wrapper = fixture_migration_test_step_two, change_id = "test:two"},
        }
        direct_state := fixture_migration_test_allocator_state {
            base                    = runtime.default_allocator(),
            fail_at                 = -1,
            expected_payload        = historical_payload,
            expected_source_version = 1,
            expected_target_version = 2,
        }
        direct_steps := [1]Fixture_Migration_Step {
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_one, change_id = "test:one"},
        }
        direct_result, direct_error, direct_ok := fixture_migration_run_with_registry(
            historical_payload,
            1,
            2,
            {steps = direct_steps[:]},
            fixture_migration_test_allocator(&direct_state),
        )
        testing.expect(t, direct_ok && direct_error.kind == .None)
        if direct_ok do testing.expect(t, direct_result.fixture.structure_selected == 5)
        testing.expect(t, direct_state.context_calls == 1)
        fixture_migration_error_dispose(&direct_error)
        fixture_migration_result_dispose(&direct_result)
        testing.expect(t, direct_state.outstanding == 0)

        ordered_state := fixture_migration_test_allocator_state {
            base                    = runtime.default_allocator(),
            fail_at                 = -1,
            expected_payload        = historical_payload,
            expected_source_version = 1,
            expected_target_version = 3,
        }
        ordered_result, ordered_error, ordered_ok := fixture_migration_run_with_registry(
            historical_payload,
            1,
            3,
            {steps = test_steps[:]},
            fixture_migration_test_allocator(&ordered_state),
        )
        testing.expect(t, ordered_ok && ordered_error.kind == .None)
        if ordered_ok {
            testing.expect(t, ordered_result.fixture.structure_selected == 52)
            testing.expect(t, ordered_result.fixture.project.sea_level == f32(12.75))
            testing.expect(t, ordered_result.fixture.project.structure_count == 1)
            testing.expect(t, ordered_result.fixture.project.structures[0].id == 0x1111)
            testing.expect(t, ordered_result.fixture.architecture_city_plan.structures[0].id == 0xabc)
            testing.expect(t, ordered_result.fixture.architecture_city_plan.parcels[0].seed == 0x50415243)
            testing.expect(t, ordered_result.fixture.architecture_city_plan.alleys[0].end_z == 26)
            testing.expect(t, ordered_result.fixture.architecture_city_plan.lamps[0].x == 33)
            testing.expect(t, ordered_result.fixture.authoring_tool == .Marina)
            testing.expect(t, ordered_result.fixture.radius == f32(6.25))
            testing.expect(t, ordered_result.fixture.strength == f32(.73))
            testing.expect(t, ordered_result.fixture.farm_count == 1)
            testing.expect(t, ordered_result.fixture.vehicle_showcase_target == "historical-target")
            testing.expect(t, ordered_result.fixture.active_lab_scene == "historical-lab")
            project_structures := cast(^runtime.Raw_Dynamic_Array)(&ordered_result.fixture.project.structures)
            city_structures := cast(^runtime.Raw_Dynamic_Array)(&ordered_result.fixture.architecture_city_plan.structures)
            city_parcels := cast(^runtime.Raw_Dynamic_Array)(&ordered_result.fixture.architecture_city_plan.parcels)
            city_alleys := cast(^runtime.Raw_Dynamic_Array)(&ordered_result.fixture.architecture_city_plan.alleys)
            city_lamps := cast(^runtime.Raw_Dynamic_Array)(&ordered_result.fixture.architecture_city_plan.lamps)
            testing.expect(t, project_structures.len == 256 && project_structures.cap == 256)
            testing.expect(t, city_structures.len == 256 && city_structures.cap == 256)
            testing.expect(t, city_parcels.len == 256 && city_parcels.cap == 256)
            testing.expect(t, city_alleys.len == 128 && city_alleys.cap == 128)
            testing.expect(t, city_lamps.len == 256 && city_lamps.cap == 256)
            testing.expect(t, city_structures.allocator.data == rawptr(ordered_result.arena))
            append(&ordered_result.fixture.architecture_city_plan.lamps, architecture.City_Lamp{})
            testing.expect(t, len(ordered_result.fixture.architecture_city_plan.lamps) == 257)
        }
        testing.expect(t, test_steps[0].from_version == 1 && test_steps[0].to_version == 2)
        testing.expect(t, test_steps[0].wrapper == fixture_migration_test_step_one)
        testing.expect(t, test_steps[0].change_id == "test:one")
        testing.expect(t, test_steps[1].from_version == 2 && test_steps[1].to_version == 3)
        testing.expect(t, test_steps[1].wrapper == fixture_migration_test_step_two)
        testing.expect(t, test_steps[1].change_id == "test:two")
        fixture_migration_error_dispose(&ordered_error)
        fixture_migration_result_dispose(&ordered_result)
        fixture_migration_result_dispose(&ordered_result)
        testing.expect(t, ordered_state.context_calls == 2 && ordered_state.outstanding == 0)

        direct_v2_state := fixture_migration_test_allocator_state {
            base                    = runtime.default_allocator(),
            fail_at                 = -1,
            expected_payload        = current_payload,
            expected_source_version = 2,
            expected_target_version = 3,
        }
        direct_v2_steps := [1]Fixture_Migration_Step {
            {from_version = 2, to_version = 3, wrapper = fixture_migration_test_step_two, change_id = "test:two"},
        }
        direct_v2_result, direct_v2_error, direct_v2_ok := fixture_migration_run_with_registry(
            current_payload,
            2,
            3,
            {steps = direct_v2_steps[:]},
            fixture_migration_test_allocator(&direct_v2_state),
        )
        testing.expect(t, direct_v2_ok && direct_v2_error.kind == .None)
        if direct_v2_ok do testing.expect(t, direct_v2_result.fixture.structure_selected == 2)
        testing.expect(t, direct_v2_state.context_calls == 1)
        fixture_migration_error_dispose(&direct_v2_error)
        fixture_migration_result_dispose(&direct_v2_result)
        testing.expect(t, direct_v2_state.outstanding == 0)

        migrated_result, migrated_error, migrated_ok := fixture_migration_run(
            historical_payload,
            1,
            FIXTURE_SCHEMA_VERSION,
            runtime.default_allocator(),
        )
        testing.expect(t, migrated_ok && migrated_error.kind == .None)
        testing.expect(t, migrated_result.fixture != nil)
        testing.expect(t, migrated_result.fixture.story_state.quest.definition_id == "two-island-story")
        testing.expect(t, migrated_result.fixture.occupant == .On_Foot)
        if migrated_ok {
            migrated_lamps := cast(^runtime.Raw_Dynamic_Array)(&migrated_result.fixture.architecture_city_plan.lamps)
            testing.expect(t, migrated_lamps.allocator.data == rawptr(migrated_result.arena))
            previous_length := len(migrated_result.fixture.architecture_city_plan.lamps)
            append(&migrated_result.fixture.architecture_city_plan.lamps, architecture.City_Lamp{x = 9002})
            testing.expect(t, len(migrated_result.fixture.architecture_city_plan.lamps) == previous_length + 1)
            testing.expect(t, migrated_result.fixture.architecture_city_plan.lamps[previous_length].x == 9002)
        }
        fixture_migration_error_dispose(&migrated_error)
        fixture_migration_error_dispose(&migrated_error)
        fixture_migration_result_dispose(&migrated_result)
        fixture_migration_result_dispose(&migrated_result)
        testing.expect(t, fixture_migration_result_empty(&migrated_result))

        incompatible_steps := [1]Fixture_Migration_Step {
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_incompatible_history},
        }
        incompatible_result, incompatible_error, incompatible_ok := fixture_migration_run_with_registry(
            current_payload,
            1,
            2,
            {steps = incompatible_steps[:]},
            runtime.default_allocator(),
        )
        testing.expect(t, !incompatible_ok && incompatible_error.kind == .Historical_Decode)
        testing.expect(t, fixture_migration_result_empty(&incompatible_result))
        fixture_migration_error_dispose(&incompatible_error)
        fixture_migration_result_dispose(&incompatible_result)

        corrupt_current := make([]byte, len(current_payload) - 1, context.allocator)
        copy(corrupt_current, current_payload[:len(current_payload) - 1])
        corrupt_result, corrupt_error, corrupt_ok := fixture_migration_run(
            corrupt_current,
            FIXTURE_SCHEMA_VERSION,
            FIXTURE_SCHEMA_VERSION,
            runtime.default_allocator(),
        )
        testing.expect(t, !corrupt_ok && corrupt_error.kind == .Tentative_Decode)
        testing.expect(t, fixture_migration_result_empty(&corrupt_result))
        fixture_migration_error_dispose(&corrupt_error)
        fixture_migration_result_dispose(&corrupt_result)
        delete(corrupt_current)

        corrupt_historical := make([]byte, len(historical_payload), context.allocator)
        copy(corrupt_historical, historical_payload)
        corrupt_historical[0] = corrupt_historical[0] ~ 1
        corrupt_history_result, corrupt_history_error, corrupt_history_ok := fixture_migration_run(
            corrupt_historical,
            1,
            FIXTURE_SCHEMA_VERSION,
            runtime.default_allocator(),
        )
        testing.expect(t, !corrupt_history_ok)
        testing.expect(t, corrupt_history_error.kind == .Tentative_Decode)
        testing.expect(t, fixture_migration_result_empty(&corrupt_history_result))
        fixture_migration_error_dispose(&corrupt_history_error)
        fixture_migration_result_dispose(&corrupt_history_result)
        delete(corrupt_historical)

        failing_steps := [1]Fixture_Migration_Step {
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_mutate_then_fail},
        }
        failing_state := fixture_migration_test_allocator_state {
            base                    = runtime.default_allocator(),
            fail_at                 = -1,
            expected_payload        = historical_payload,
            expected_source_version = 1,
            expected_target_version = 2,
        }
        failed_result, failed_error, failed_ok := fixture_migration_run_with_registry(
            historical_payload,
            1,
            2,
            {steps = failing_steps[:]},
            fixture_migration_test_allocator(&failing_state),
        )
        testing.expect(t, !failed_ok && failed_error.kind == .Step_Failure)
        testing.expect(t, fixture_migration_result_empty(&failed_result))
        fixture_migration_error_dispose(&failed_error)
        fixture_migration_result_dispose(&failed_result)
        testing.expect(t, failing_state.context_calls == 1 && failing_state.outstanding == 0)
        testing.expect(t, fixture_migration_test_bytes_equal(current_payload, current_snapshot))
        testing.expect(t, fixture_migration_test_bytes_equal(historical_payload, historical_snapshot))
        fixture_migration_result_dispose(nil)
        fixture_migration_error_dispose(nil)
    }

    fixture_migration_test_expect_rejected :: proc(
        t: ^testing.T,
        payload: []byte,
        source_version, target_version: int,
        registry: Fixture_Migration_Registry,
        expected: Fixture_Migration_Error_Kind,
        allocator := context.allocator,
    ) {
        result, error, ok := fixture_migration_run_with_registry(
            payload,
            source_version,
            target_version,
            registry,
            allocator,
        )
        testing.expect(t, !ok && error.kind == expected)
        testing.expect(t, fixture_migration_result_empty(&result))
        fixture_migration_error_dispose(&error)
        fixture_migration_result_dispose(&result)
    }

    @(test)
    fixture_migration_rejects_invalid_registries_before_decode :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
        payload := []byte{1, 2, 3, 4}

        fixture_migration_test_expect_rejected(t, payload, 1, 2, {}, .Invalid_Registry)
        nil_wrapper := [1]Fixture_Migration_Step{{from_version = 1, to_version = 2}}
        fixture_migration_test_expect_rejected(t, payload, 1, 2, {steps = nil_wrapper[:]}, .Invalid_Registry)
        zero_step := [1]Fixture_Migration_Step {
            {from_version = 0, to_version = 1, wrapper = fixture_migration_test_step_one},
        }
        fixture_migration_test_expect_rejected(t, payload, 1, 2, {steps = zero_step[:]}, .Invalid_Registry)
        reversed := [2]Fixture_Migration_Step {
            {from_version = 2, to_version = 3, wrapper = fixture_migration_test_step_one},
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_two},
        }
        fixture_migration_test_expect_rejected(t, payload, 1, 3, {steps = reversed[:]}, .Invalid_Registry)
        skipped := [2]Fixture_Migration_Step {
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_one},
            {from_version = 3, to_version = 4, wrapper = fixture_migration_test_step_two},
        }
        fixture_migration_test_expect_rejected(t, payload, 1, 4, {steps = skipped[:]}, .Invalid_Registry)
        duplicate := [2]Fixture_Migration_Step {
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_one},
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_two},
        }
        fixture_migration_test_expect_rejected(t, payload, 1, 2, {steps = duplicate[:]}, .Invalid_Registry)
        missing := [1]Fixture_Migration_Step {
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_one},
        }
        fixture_migration_test_expect_rejected(t, payload, 1, 3, {steps = missing[:]}, .Unsupported_Version)
        fixture_migration_test_expect_rejected(
            t,
            payload,
            1,
            1,
            fixture_migration_production_registry(),
            .Unsupported_Version,
        )
        fixture_migration_test_expect_rejected(
            t,
            payload,
            4,
            4,
            fixture_migration_production_registry(),
            .Unsupported_Version,
        )
        fixture_migration_test_expect_rejected(
            t,
            payload,
            1,
            4,
            fixture_migration_production_registry(),
            .Unsupported_Version,
        )
        fixture_migration_test_expect_rejected(
            t,
            payload,
            FIXTURE_SCHEMA_VERSION,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_production_registry(),
            .Tentative_Decode,
        )
        fixture_migration_test_expect_rejected(t, payload, 2, 1, {steps = missing[:]}, .Invalid_Argument)
        fixture_migration_test_expect_rejected(t, payload, 0, 1, {steps = missing[:]}, .Invalid_Argument)
        fixture_migration_test_expect_rejected(
            t,
            payload,
            FIXTURE_SCHEMA_VERSION,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_production_registry(),
            .Invalid_Argument,
            {},
        )
    }

    @(test)
    fixture_migration_caller_allocation_failures_dispose_everything :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
        current_payload, current_ok := fixture_migration_test_current_payload(t)
        if !current_ok do return
        defer delete(current_payload)
        historical_payload, historical_ok := fixture_migration_test_historical_payload(t)
        if !historical_ok do return
        defer delete(historical_payload)

        current_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        current_allocator := fixture_migration_test_allocator(&current_state)
        current_result, current_error, current_run_ok := fixture_migration_run(
            current_payload,
            FIXTURE_SCHEMA_VERSION,
            FIXTURE_SCHEMA_VERSION,
            current_allocator,
        )
        testing.expect(t, current_run_ok && current_error.kind == .None)
        current_calls := current_state.allocation_calls
        fixture_migration_error_dispose(&current_error)
        fixture_migration_result_dispose(&current_result)
        testing.expect(t, current_state.outstanding == 0)
        for fail_at in 0 ..< current_calls {
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = fail_at,
            }
            result, error, ok := fixture_migration_run(
                current_payload,
                FIXTURE_SCHEMA_VERSION,
                FIXTURE_SCHEMA_VERSION,
                fixture_migration_test_allocator(&state),
            )
            testing.expect(t, !ok && error.kind == .Out_Of_Memory)
            testing.expect(t, fixture_migration_result_empty(&result) && state.outstanding == 0)
            fixture_migration_error_dispose(&error)
            fixture_migration_result_dispose(&result)
        }

        wrapper_steps := [1]Fixture_Migration_Step {
            {from_version = 1, to_version = 2, wrapper = fixture_migration_test_step_one},
        }
        wrapper_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        wrapper_result, wrapper_error, wrapper_ok := fixture_migration_run_with_registry(
            historical_payload,
            1,
            2,
            {steps = wrapper_steps[:]},
            fixture_migration_test_allocator(&wrapper_state),
        )
        testing.expect(t, wrapper_ok && wrapper_error.kind == .None)
        wrapper_calls := wrapper_state.allocation_calls
        fixture_migration_error_dispose(&wrapper_error)
        fixture_migration_result_dispose(&wrapper_result)
        testing.expect(t, wrapper_state.outstanding == 0)
        for fail_at in 0 ..< wrapper_calls {
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = fail_at,
            }
            result, error, ok := fixture_migration_run_with_registry(
                historical_payload,
                1,
                2,
                {steps = wrapper_steps[:]},
                fixture_migration_test_allocator(&state),
            )
            testing.expect(t, !ok && error.kind == .Out_Of_Memory)
            testing.expect(t, fixture_migration_result_empty(&result) && state.outstanding == 0)
            fixture_migration_error_dispose(&error)
            fixture_migration_result_dispose(&result)
        }

        historical_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        historical_result, historical_error, historical_run_ok := fixture_migration_run(
            historical_payload,
            1,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_test_allocator(&historical_state),
        )
        testing.expect(t, historical_run_ok && historical_error.kind == .None)
        testing.expect(t, historical_result.fixture != nil)
        historical_calls := historical_state.allocation_calls
        fixture_migration_error_dispose(&historical_error)
        fixture_migration_result_dispose(&historical_result)
        testing.expect(t, historical_state.outstanding == 0)
        for fail_at in 0 ..< historical_calls {
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = fail_at,
            }
            result, error, ok := fixture_migration_run(
                historical_payload,
                1,
                FIXTURE_SCHEMA_VERSION,
                fixture_migration_test_allocator(&state),
            )
            testing.expect(t, !ok && error.kind == .Out_Of_Memory)
            testing.expect(t, fixture_migration_result_empty(&result) && state.outstanding == 0)
            fixture_migration_error_dispose(&error)
            fixture_migration_result_dispose(&result)
        }
    }
}
