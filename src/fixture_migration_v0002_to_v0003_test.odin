package main

import fixture_v0001 "../packages/fixture_history/v0001"
import fixture_v0002 "../packages/fixture_history/v0002"
import hs "../packages/hs"
import vehicles "../packages/vehicles"
import "base:runtime"
import "core:mem"
import "core:testing"

when ODIN_TEST {
    fixture_migration_v0002_to_v0003_test_v2_payload :: proc(t: ^testing.T) -> ([]byte, bool) {
        historical := new(fixture_v0002.Fixture)
        fixture_migration_v0004_runtime_seed_legacy_flight(historical, 2)
        historical.pilot.mode = .Driving
        historical.architecture_brush_radius = 45
        historical.aircraft.slots[0].kind = .Postale
        historical.aircraft.slots[1].kind = .Libellula
        historical.aircraft.slots[2].kind = .Libellula_Mk2
        historical.aircraft.active = .Libellula_Mk2
        historical.aircraft.count = 3
        historical.structure_selected = 731
        historical.vehicle_showcase_target = "b3-v2-target"
        historical.active_lab_scene = "b3-v2-lab"
        payload, portable_error, ok := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0002.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        free(historical)
        testing.expect(t, ok && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        return payload, ok
    }

    fixture_migration_v0002_to_v0003_test_v1_payload :: proc(t: ^testing.T) -> ([]byte, bool) {
        source_payload, source_ok := fixture_migration_test_historical_payload(t)
        if !source_ok do return nil, false

        arena, arena_ok := fixture_migration_arena_allocate(context.allocator)
        if !arena_ok {
            delete(source_payload)
            return nil, false
        }
        historical_allocator := mem.dynamic_arena_allocator(arena)
        historical := new(fixture_v0001.Fixture, historical_allocator)
        if historical == nil {
            fixture_migration_arena_dispose(arena, context.allocator)
            delete(source_payload)
            return nil, false
        }
        portable_error, portable_ok := hs.portable_decode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0001.Fixture)},
            source_payload,
            fixture_codec_portable_config(),
            historical_allocator,
        )
        if !portable_ok {
            hs.portable_error_dispose(&portable_error)
            fixture_migration_arena_dispose(arena, context.allocator)
            delete(source_payload)
            return nil, false
        }
        hs.portable_error_dispose(&portable_error)
        historical.pilot.mode = .Driving
        historical.aircraft.active = .Libellula_Mk2
        payload, encode_error, encode_ok := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0001.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        hs.portable_error_dispose(&encode_error)
        fixture_migration_arena_dispose(arena, context.allocator)
        delete(source_payload)
        testing.expect(t, encode_ok)
        return payload, encode_ok
    }

    fixture_migration_v0002_to_v0003_test_invalid_enum_payload :: proc(t: ^testing.T) -> ([]byte, bool) {
        historical := new(fixture_v0002.Fixture)
        historical.aircraft.active = fixture_v0002.History_Type_0097(99)
        payload, portable_error, ok := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0002.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        free(historical)
        testing.expect(t, ok && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        return payload, ok
    }

    fixture_migration_v0002_to_v0003_test_call_direct :: proc(
        payload: []byte,
        source_version: int,
    ) -> (
        Fixture_Migration_Error,
        vehicles.Fixture_Occupant,
        int,
    ) {
        arena, arena_ok := fixture_migration_arena_allocate(context.allocator)
        if !arena_ok do return {kind = .Out_Of_Memory}, .Car, -1
        transaction_allocator := mem.dynamic_arena_allocator(arena)
        tentative := new(Fixture, transaction_allocator)
        if tentative == nil {
            fixture_migration_arena_dispose(arena, context.allocator)
            return {kind = .Out_Of_Memory}, .Car, -1
        }
        tentative.occupant = .Car
        tentative.structure_selected = 909
        step_context := Fixture_Migration_Step_Context {
            source_payload        = payload,
            source_version        = source_version,
            target_version        = 3,
            step_from_version     = 2,
            step_to_version       = 3,
            tentative             = tentative,
            transaction_allocator = transaction_allocator,
        }
        error := fixture_migration_step_v0002_to_v0003(&step_context)
        occupant := tentative.occupant
        structure_selected := tentative.structure_selected
        fixture_migration_arena_dispose(arena, context.allocator)
        return error, occupant, structure_selected
    }

    @(test)
    fixture_migration_v0002_to_v0003_direct_chained_and_failures :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        v2_payload, v2_ok := fixture_migration_v0002_to_v0003_test_v2_payload(t)
        if !v2_ok do return
        defer delete(v2_payload)
        v2_snapshot := make([]byte, len(v2_payload), context.allocator)
        copy(v2_snapshot, v2_payload)
        defer delete(v2_snapshot)

        v2_steps := [1]Fixture_Migration_Step {
            {
                from_version = 2,
                to_version = 3,
                wrapper = fixture_migration_step_v0002_to_v0003,
                change_id = "field-add:adriatic:src.Fixture.occupant",
            },
        }
        direct_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        direct_result, direct_error, direct_ok := fixture_migration_run(
            v2_payload,
            2,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_test_allocator(&direct_state),
        )
        testing.expect(t, direct_ok && direct_error.kind == .None)
        if direct_ok {
            testing.expect(t, direct_result.fixture.occupant == .On_Foot)
            testing.expect(t, direct_result.fixture.pilot.mode == .Driving)
            testing.expect(t, direct_result.fixture.aircraft.active == .Libellula_Mk2)
            testing.expect(t, direct_result.fixture.aircraft.count == 4)
            testing.expect(t, direct_result.fixture.aircraft.slots[3].kind == .Rondine)
            testing.expect(t, direct_result.fixture.structure_selected == 731)
            testing.expect(t, direct_result.fixture.vehicle_showcase_target == "b3-v2-target")
            testing.expect(t, direct_result.fixture.active_lab_scene == "b3-v2-lab")
        }
        testing.expect(t, fixture_migration_test_bytes_equal(v2_payload, v2_snapshot))
        fixture_migration_error_dispose(&direct_error)
        fixture_migration_error_dispose(&direct_error)
        fixture_migration_result_dispose(&direct_result)
        fixture_migration_result_dispose(&direct_result)
        testing.expect(t, fixture_migration_result_empty(&direct_result))
        testing.expect(t, direct_state.outstanding == 0)

        current_provenance_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        current_provenance_result, current_provenance_error, current_provenance_ok := fixture_migration_run(
            v2_payload,
            FIXTURE_SCHEMA_VERSION,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_test_allocator(&current_provenance_state),
        )
        testing.expect(t, !current_provenance_ok && current_provenance_error.kind == .Tentative_Decode)
        testing.expect(t, fixture_migration_result_empty(&current_provenance_result))
        testing.expect(t, fixture_migration_test_bytes_equal(v2_payload, v2_snapshot))
        fixture_migration_error_dispose(&current_provenance_error)
        fixture_migration_error_dispose(&current_provenance_error)
        fixture_migration_result_dispose(&current_provenance_result)
        fixture_migration_result_dispose(&current_provenance_result)
        testing.expect(t, fixture_migration_result_empty(&current_provenance_result))
        testing.expect(t, current_provenance_state.outstanding == 0)

        v1_payload, v1_ok := fixture_migration_v0002_to_v0003_test_v1_payload(t)
        if !v1_ok do return
        defer delete(v1_payload)
        chained_result, chained_error, chained_ok := fixture_migration_run(
            v1_payload,
            1,
            FIXTURE_SCHEMA_VERSION,
            runtime.default_allocator(),
        )
        testing.expect(t, chained_ok && chained_error.kind == .None)
        if chained_ok {
            testing.expect(t, chained_result.fixture.occupant == .On_Foot)
            testing.expect(t, chained_result.fixture.pilot.mode == .Driving)
            testing.expect(t, chained_result.fixture.aircraft.active == .Libellula_Mk2)
            testing.expect(t, chained_result.fixture.aircraft.count == 4)
            testing.expect(t, chained_result.fixture.aircraft.slots[3].kind == .Rondine)
            testing.expect(t, chained_result.fixture.structure_selected == 4)
            testing.expect(t, chained_result.fixture.story_state.quest.definition_id == "two-island-story")
            testing.expect(t, chained_result.fixture.vehicle_showcase_target == "historical-target")
            testing.expect(t, chained_result.fixture.active_lab_scene == "historical-lab")
        }
        fixture_migration_error_dispose(&chained_error)
        fixture_migration_result_dispose(&chained_result)
        fixture_migration_result_dispose(&chained_result)

        testing.expect(t, len(FIXTURE_MIGRATION_V0002_TO_V0003_RESOLUTIONS) == 1)
        if len(FIXTURE_MIGRATION_V0002_TO_V0003_RESOLUTIONS) == 1 {
            resolution := FIXTURE_MIGRATION_V0002_TO_V0003_RESOLUTIONS[0]
            testing.expect(t, resolution.change_id == "field-add:adriatic:src.Fixture.occupant")
            testing.expect(t, resolution.kind == .Scripted)
        }
        nil_error := fixture_migration_v0002_to_v0003_resolve_occupant(nil)
        testing.expect(t, nil_error.kind == .Invalid_Argument)
        fixture_migration_error_dispose(&nil_error)
        for value in 1 ..< 5 {
            tentative := new(Fixture)
            tentative.occupant = vehicles.Fixture_Occupant(value)
            tentative.structure_selected = 818
            first_error := fixture_migration_v0002_to_v0003_resolve_occupant(tentative)
            second_error := fixture_migration_v0002_to_v0003_resolve_occupant(tentative)
            testing.expect(t, first_error.kind == .None && second_error.kind == .None)
            testing.expect(t, tentative.occupant == .On_Foot && tentative.structure_selected == 818)
            fixture_migration_error_dispose(&first_error)
            fixture_migration_error_dispose(&second_error)
            free(tentative)
        }

        invalid_tentative := new(Fixture)
        invalid_tentative.occupant = .Car
        invalid_tentative.structure_selected = 707
        invalid_context := Fixture_Migration_Step_Context {
            tentative = invalid_tentative,
        }
        invalid_error := fixture_migration_step_v0002_to_v0003(&invalid_context)
        testing.expect(t, invalid_error.kind == .Invalid_Argument)
        testing.expect(t, invalid_tentative.occupant == .Car && invalid_tentative.structure_selected == 707)
        fixture_migration_error_dispose(&invalid_error)
        forged_live_context := Fixture_Migration_Step_Context {
            source_version = 1,
            target_version = 3,
            step_from_version = 2,
            step_to_version = 3,
            tentative = invalid_tentative,
            transaction_allocator = {procedure = mem.dynamic_arena_allocator_proc},
        }
        forged_live_error := fixture_migration_step_v0002_to_v0003(&forged_live_context)
        testing.expect(t, forged_live_error.kind == .Invalid_Argument)
        testing.expect(t, invalid_tentative.occupant == .Car && invalid_tentative.structure_selected == 707)
        fixture_migration_error_dispose(&forged_live_error)
        free(invalid_tentative)

        live_context_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        live_context_arena, live_context_arena_ok := fixture_migration_arena_allocate(
            fixture_migration_test_allocator(&live_context_state),
        )
        testing.expect(t, live_context_arena_ok)
        if live_context_arena_ok {
            live_context_allocator := mem.dynamic_arena_allocator(live_context_arena)
            live_context_tentative := new(Fixture, live_context_allocator)
            testing.expect(t, live_context_tentative != nil)
            if live_context_tentative != nil {
                invalid_live_contexts := [6]Fixture_Migration_Step_Context {
                    {
                        source_payload = v2_payload,
                        source_version = 0,
                        target_version = 3,
                        step_from_version = 2,
                        step_to_version = 3,
                        tentative = live_context_tentative,
                        transaction_allocator = live_context_allocator,
                    },
                    {
                        source_payload = v2_payload,
                        source_version = 3,
                        target_version = 3,
                        step_from_version = 2,
                        step_to_version = 3,
                        tentative = live_context_tentative,
                        transaction_allocator = live_context_allocator,
                    },
                    {
                        source_payload = v2_payload,
                        source_version = 2,
                        target_version = 2,
                        step_from_version = 2,
                        step_to_version = 3,
                        tentative = live_context_tentative,
                        transaction_allocator = live_context_allocator,
                    },
                    {
                        source_payload = v2_payload,
                        source_version = 2,
                        target_version = 3,
                        step_from_version = 1,
                        step_to_version = 3,
                        tentative = live_context_tentative,
                        transaction_allocator = live_context_allocator,
                    },
                    {
                        source_payload = v2_payload,
                        source_version = 2,
                        target_version = 3,
                        step_from_version = 2,
                        step_to_version = 4,
                        tentative = live_context_tentative,
                        transaction_allocator = live_context_allocator,
                    },
                    {
                        source_payload = v2_payload,
                        source_version = 2,
                        target_version = 3,
                        step_from_version = 2,
                        step_to_version = 3,
                        tentative = nil,
                        transaction_allocator = live_context_allocator,
                    },
                }
                for &live_context in invalid_live_contexts {
                    live_context_tentative.occupant = .Car
                    live_context_tentative.structure_selected = 606
                    allocation_calls := live_context_state.allocation_calls
                    live_context_error := fixture_migration_step_v0002_to_v0003(&live_context)
                    testing.expect(t, live_context_error.kind == .Invalid_Argument)
                    testing.expect(
                        t,
                        live_context_tentative.occupant == .Car && live_context_tentative.structure_selected == 606,
                    )
                    testing.expect(t, live_context_state.allocation_calls == allocation_calls)
                    fixture_migration_error_dispose(&live_context_error)
                    fixture_migration_error_dispose(&live_context_error)
                }
            }
            fixture_migration_arena_dispose(live_context_arena, fixture_migration_test_allocator(&live_context_state))
            testing.expect(t, live_context_state.outstanding == 0)
        }

        truncated_error, truncated_occupant, truncated_structure := fixture_migration_v0002_to_v0003_test_call_direct(
            v2_payload[:len(v2_payload) - 1],
            2,
        )
        testing.expect(t, truncated_error.kind == .Historical_Decode)
        testing.expect(t, truncated_occupant == .Car && truncated_structure == 909)
        fixture_migration_error_dispose(&truncated_error)

        wrong_schema_error, wrong_schema_occupant, wrong_schema_structure :=
            fixture_migration_v0002_to_v0003_test_call_direct(v1_payload, 2)
        testing.expect(t, wrong_schema_error.kind == .Historical_Decode)
        testing.expect(t, wrong_schema_occupant == .Car && wrong_schema_structure == 909)
        fixture_migration_error_dispose(&wrong_schema_error)

        invalid_enum_payload, invalid_enum_ok := fixture_migration_v0002_to_v0003_test_invalid_enum_payload(t)
        if invalid_enum_ok {
            defer delete(invalid_enum_payload)
            invalid_enum_error, invalid_enum_occupant, invalid_enum_structure :=
                fixture_migration_v0002_to_v0003_test_call_direct(invalid_enum_payload, 2)
            testing.expect(t, invalid_enum_error.kind == .Historical_Decode)
            testing.expect(t, invalid_enum_occupant == .Car && invalid_enum_structure == 909)
            fixture_migration_error_dispose(&invalid_enum_error)
        }

        transaction_failure_state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = -1,
            }
        transaction_failure_result, transaction_failure_error, transaction_failure_ok :=
            fixture_migration_run_with_registry(
                v2_payload[:len(v2_payload) - 1],
                2,
                3,
                {steps = v2_steps[:]},
                fixture_migration_test_allocator(&transaction_failure_state),
            )
        testing.expect(t, !transaction_failure_ok && transaction_failure_error.kind == .Tentative_Decode)
        testing.expect(t, fixture_migration_result_empty(&transaction_failure_result))
        fixture_migration_error_dispose(&transaction_failure_error)
        fixture_migration_error_dispose(&transaction_failure_error)
        fixture_migration_result_dispose(&transaction_failure_result)
        fixture_migration_result_dispose(&transaction_failure_result)
        testing.expect(t, fixture_migration_result_empty(&transaction_failure_result))
        testing.expect(t, transaction_failure_state.outstanding == 0)

        direct_fault_state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = -1,
            }
        fault_arena, fault_arena_ok := fixture_migration_arena_allocate(
            fixture_migration_test_allocator(&direct_fault_state),
        )
        testing.expect(t, fault_arena_ok)
        if fault_arena_ok {
            fault_allocator := mem.dynamic_arena_allocator(fault_arena)
            fault_tentative := new(Fixture, fault_allocator)
            fault_tentative.occupant = .Car
            fault_tentative.structure_selected = 505
            fault_context := Fixture_Migration_Step_Context {
                source_payload        = v2_payload,
                source_version        = 2,
                target_version        = 3,
                step_from_version     = 2,
                step_to_version       = 3,
                tentative             = fault_tentative,
                transaction_allocator = fault_allocator,
            }
            direct_fault_state.allocation_calls = 0
            success_error := fixture_migration_step_v0002_to_v0003(&fault_context)
            wrapper_calls := direct_fault_state.allocation_calls
            testing.expect(t, success_error.kind == .None)
            fixture_migration_error_dispose(&success_error)
            for fail_at in 0 ..< wrapper_calls {
                fault_tentative.occupant = .Car
                fault_tentative.structure_selected = 505
                direct_fault_state.allocation_calls = 0
                direct_fault_state.fail_at = fail_at
                failure := fixture_migration_step_v0002_to_v0003(&fault_context)
                testing.expect(t, failure.kind == .Out_Of_Memory)
                testing.expect(t, fault_tentative.occupant == .Car && fault_tentative.structure_selected == 505)
                fixture_migration_error_dispose(&failure)
            }
            direct_fault_state.fail_at = -1
            fixture_migration_arena_dispose(fault_arena, fixture_migration_test_allocator(&direct_fault_state))
            testing.expect(t, direct_fault_state.outstanding == 0)
        }

        no_decode_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        no_decode_arena, no_decode_ok := fixture_migration_arena_allocate(
            fixture_migration_test_allocator(&no_decode_state),
        )
        testing.expect(t, no_decode_ok)
        if no_decode_ok {
            no_decode_allocator := mem.dynamic_arena_allocator(no_decode_arena)
            no_decode_tentative := new(Fixture, no_decode_allocator)
            no_decode_tentative.occupant = .Car
            no_decode_context := Fixture_Migration_Step_Context {
                source_payload        = v1_payload,
                source_version        = 1,
                target_version        = 3,
                step_from_version     = 2,
                step_to_version       = 3,
                tentative             = no_decode_tentative,
                transaction_allocator = no_decode_allocator,
            }
            no_decode_state.allocation_calls = 0
            no_decode_state.fail_at = 0
            no_decode_error := fixture_migration_step_v0002_to_v0003(&no_decode_context)
            testing.expect(t, no_decode_error.kind == .None)
            testing.expect(t, no_decode_state.allocation_calls == 0 && no_decode_tentative.occupant == .On_Foot)
            fixture_migration_error_dispose(&no_decode_error)
            no_decode_state.fail_at = -1
            fixture_migration_arena_dispose(no_decode_arena, fixture_migration_test_allocator(&no_decode_state))
            testing.expect(t, no_decode_state.outstanding == 0)
        }
    }
}
