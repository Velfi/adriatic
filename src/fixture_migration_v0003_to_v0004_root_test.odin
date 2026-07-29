package main

import fixture_v0003 "../packages/fixture_history/v0003"
import rondine_game "../packages/rondine"
import vehicles "../packages/vehicles"
import "base:runtime"
import "core:mem"
import "core:testing"

when ODIN_TEST {
    FIXTURE_MIGRATION_V0003_ROOT_ORDERS :: [6][3]fixture_v0003.History_Type_0097 {
        {.Postale, .Libellula, .Libellula_Mk2},
        {.Postale, .Libellula_Mk2, .Libellula},
        {.Libellula, .Postale, .Libellula_Mk2},
        {.Libellula, .Libellula_Mk2, .Postale},
        {.Libellula_Mk2, .Postale, .Libellula},
        {.Libellula_Mk2, .Libellula, .Postale},
    }

    fixture_migration_v0003_root_test_set_hostile_state :: proc(tentative: ^Fixture) {
        fixture_migration_v0003_structural_test_set_sentinels(tentative)
        tentative.farm_brush_yaw = 301
        tentative.rondine_visible = true
        rondine_bytes := mem.slice_ptr(cast([^]u8)&tentative.rondine, size_of(tentative.rondine))
        for &byte in rondine_bytes do byte = 0xa5
        tentative.wreck_paint_mode = true
        tentative.wreck_brush_size = 302
        tentative.wreck_brush_yaw = 303
        wreck_bytes := mem.slice_ptr(cast([^]u8)&tentative.wrecks, size_of(tentative.wrecks))
        for &byte in wreck_bytes do byte = 0xa5
        tentative.wreck_count = len(tentative.wrecks)
    }

    fixture_migration_v0003_root_test_set_fleet :: proc(
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        order: [3]fixture_v0003.History_Type_0097,
        active: fixture_v0003.History_Type_0097,
        occupant: fixture_v0003.History_Type_0103,
    ) {
        names := [8]string {
            "Old Alpha",
            "Old Beta",
            "Old Gamma",
            "Replace Me",
            "Tail Four",
            "Tail Five",
            "Tail Six",
            "Tail Seven",
        }
        vehicle_pointers := [8]^vehicles.Vehicle {
            &tentative.postale.vehicle,
            &tentative.libellula.vehicle,
            &tentative.car,
            &tentative.rondine.vehicle,
            &tentative.car,
            &tentative.postale.vehicle,
            &tentative.libellula.vehicle,
            &tentative.rondine.vehicle,
        }
        for index in 0 ..< len(historical.aircraft.slots) {
            kind := fixture_v0003.History_Type_0097((index + 1) % 3)
            if index < len(order) do kind = order[index]
            historical.aircraft.slots[index] = {
                kind      = kind,
                name      = names[index],
                available = index % 2 == 0,
            }
            tentative.aircraft.slots[index] = {
                kind      = vehicles.Aircraft_Kind(int(kind)),
                name      = names[index],
                vehicle   = vehicle_pointers[index],
                available = index % 2 == 0,
            }
        }
        historical.aircraft.count = 3
        historical.aircraft.active = active
        historical.occupant = occupant
        tentative.aircraft.count = 3
        tentative.aircraft.active = .Rondine
        tentative.occupant = .Rondine
    }

    fixture_migration_v0003_root_test_prepare :: proc(
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        order := FIXTURE_MIGRATION_V0003_ROOT_ORDERS[0],
        active: fixture_v0003.History_Type_0097 = .Postale,
        occupant: fixture_v0003.History_Type_0103 = .On_Foot,
    ) {
        historical.architecture_brush_radius = 64
        fixture_migration_v0003_root_test_set_hostile_state(tentative)
        fixture_migration_v0003_root_test_set_fleet(historical, tentative, order, active, occupant)
    }

    fixture_migration_v0003_root_test_call :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
    ) -> Fixture_Migration_Error {
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = 0,
        }
        error := fixture_migration_v0003_root_slice(historical^, tentative, fixture_migration_test_allocator(&state))
        testing.expect(t, state.allocation_calls == 0 && state.outstanding == 0)
        return error
    }

    fixture_migration_v0003_root_test_expect_atomic_failure :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        expected_id: string,
    ) {
        snapshot, snapshot_ok := fixture_migration_structural_snapshot(tentative, context.allocator)
        testing.expect(t, snapshot_ok)
        if !snapshot_ok do return
        error := fixture_migration_v0003_root_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .Invalid_Source && error.change_id == expected_id)
        testing.expect(t, fixture_migration_structural_snapshot_matches(snapshot, tentative))
        fixture_migration_structural_snapshot_dispose(&snapshot)
        fixture_migration_structural_snapshot_dispose(&snapshot)
    }

    fixture_migration_v0003_root_test_expect_runtime :: proc(t: ^testing.T, tentative: ^Fixture) {
        expected := rondine_game.Runtime{}
        expected.vehicle.locked = true
        expected_bytes := mem.slice_ptr(cast([^]u8)&expected, size_of(expected))
        actual_bytes := mem.slice_ptr(cast([^]u8)&tentative.rondine, size_of(tentative.rondine))
        testing.expect(t, fixture_migration_test_bytes_equal(actual_bytes, expected_bytes))
        testing.expect(t, tentative.rondine.vehicle.driver == nil && tentative.rondine.vehicle.locked)
        testing.expect(t, !tentative.rondine_visible)
    }

    fixture_migration_v0003_root_test_expect_wrecks :: proc(t: ^testing.T, tentative: ^Fixture) {
        expected := [WRECK_INSTANCE_CAPACITY]Wreck_Instance{}
        expected_bytes := mem.slice_ptr(cast([^]u8)&expected, size_of(expected))
        actual_bytes := mem.slice_ptr(cast([^]u8)&tentative.wrecks, size_of(tentative.wrecks))
        testing.expect(t, fixture_migration_test_bytes_equal(actual_bytes, expected_bytes))
        testing.expect(
            t,
            !tentative.wreck_paint_mode &&
            tentative.wreck_brush_size == f32(330) &&
            tentative.wreck_brush_yaw == 0 &&
            tentative.wreck_count == 0,
        )
    }

    fixture_migration_v0003_root_test_expect_success :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
    ) {
        before_slots := tentative.aircraft.slots
        error := fixture_migration_v0003_root_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .Unresolved && error.change_id == FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        fixture_migration_v0003_structural_test_expect_state(t, historical, tentative, .Medium, true)

        testing.expect(t, tentative.farm_brush_yaw == 0 && tentative.aircraft.count == 4)
        for index in 0 ..< 3 {
            testing.expect(t, tentative.aircraft.slots[index] == before_slots[index])
            before_bytes := mem.slice_ptr(cast([^]u8)&before_slots[index], size_of(before_slots[index]))
            after_bytes := mem.slice_ptr(
                cast([^]u8)&tentative.aircraft.slots[index],
                size_of(tentative.aircraft.slots[index]),
            )
            testing.expect(t, fixture_migration_test_bytes_equal(after_bytes, before_bytes))
            before_name := mem.slice_ptr(cast([^]u8)&before_slots[index].name, size_of(string))
            after_name := mem.slice_ptr(cast([^]u8)&tentative.aircraft.slots[index].name, size_of(string))
            testing.expect(t, fixture_migration_test_bytes_equal(after_name, before_name))
        }
        testing.expect(
            t,
            tentative.aircraft.slots[3].kind == .Rondine &&
            tentative.aircraft.slots[3].name == "Rondine" &&
            tentative.aircraft.slots[3].vehicle == nil &&
            !tentative.aircraft.slots[3].available,
        )
        for index in 4 ..< len(tentative.aircraft.slots) {
            testing.expect(t, tentative.aircraft.slots[index] == before_slots[index])
            before_bytes := mem.slice_ptr(cast([^]u8)&before_slots[index], size_of(before_slots[index]))
            after_bytes := mem.slice_ptr(
                cast([^]u8)&tentative.aircraft.slots[index],
                size_of(tentative.aircraft.slots[index]),
            )
            testing.expect(t, fixture_migration_test_bytes_equal(after_bytes, before_bytes))
            before_name := mem.slice_ptr(cast([^]u8)&before_slots[index].name, size_of(string))
            after_name := mem.slice_ptr(cast([^]u8)&tentative.aircraft.slots[index].name, size_of(string))
            testing.expect(t, fixture_migration_test_bytes_equal(after_name, before_name))
        }
        testing.expect(t, int(tentative.aircraft.active) == int(historical.aircraft.active))
        testing.expect(t, int(tentative.occupant) == int(historical.occupant))
        fixture_migration_v0003_root_test_expect_runtime(t, tentative)
        fixture_migration_v0003_root_test_expect_wrecks(t, tentative)
    }

    @(test)
    fixture_migration_v0003_to_v0004_root_defaults_and_failures :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        historical, tentative, made := fixture_migration_v0003_structural_test_make(t)
        if !made {
            fixture_migration_v0003_structural_test_destroy(historical, tentative)
            return
        }
        defer fixture_migration_v0003_structural_test_destroy(historical, tentative)

        for order, case_index in FIXTURE_MIGRATION_V0003_ROOT_ORDERS {
            active := fixture_v0003.History_Type_0097(case_index % 3)
            occupant := fixture_v0003.History_Type_0103(case_index % 5)
            fixture_migration_v0003_root_test_prepare(historical, tentative, order, active, occupant)
            fixture_migration_v0003_root_test_expect_success(t, historical, tentative)
        }

        invalid_counts := [?]int{-1, 0, 1, 2, 4, 7, 8}
        for count in invalid_counts {
            fixture_migration_v0003_root_test_prepare(historical, tentative)
            historical.aircraft.count = count
            fixture_migration_v0003_root_test_expect_atomic_failure(
                t,
                historical,
                tentative,
                FIXTURE_MIGRATION_V0003_RONDINE_ID,
            )
        }

        invalid_tentative_counts := [?]int{-1, 0, 2, 4, 8}
        for count in invalid_tentative_counts {
            fixture_migration_v0003_root_test_prepare(historical, tentative)
            tentative.aircraft.count = count
            fixture_migration_v0003_root_test_expect_atomic_failure(
                t,
                historical,
                tentative,
                FIXTURE_MIGRATION_V0003_RONDINE_ID,
            )
        }

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        historical.aircraft.slots[1].kind = .Postale
        historical.aircraft.slots[2].kind = .Libellula_Mk2
        historical.aircraft.active = .Postale
        fixture_migration_v0003_root_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_RONDINE_ID,
        )

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        historical.aircraft.slots[2].kind = .Libellula
        historical.aircraft.active = .Libellula_Mk2
        fixture_migration_v0003_root_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_RONDINE_ID,
        )

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        historical.aircraft.slots[7].kind = fixture_v0003.History_Type_0097(3)
        fixture_migration_v0003_root_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_AIRCRAFT_ID,
        )

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        historical.architecture_brush_radius = -1
        fixture_migration_v0003_root_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_BRUSH_PRESET_ID,
        )

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        project_raw := cast(^runtime.Raw_Dynamic_Array)&tentative.project.structures
        project_length := project_raw.len
        project_raw.len = project_length - 1
        fixture_migration_v0003_root_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        project_raw.len = project_length

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        city_raw := cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.structures
        city_length := city_raw.len
        city_raw.len = city_length - 1
        fixture_migration_v0003_root_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        city_raw.len = city_length

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        alleys_raw := cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.alleys
        alley_length := alleys_raw.len
        alleys_raw.len = alley_length - 1
        fixture_migration_v0003_root_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_STRUCTURAL_ID,
        )
        alleys_raw.len = alley_length

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        historical.aircraft.slots[7].kind = fixture_v0003.History_Type_0097(3)
        historical.architecture_brush_radius = -1
        historical.aircraft.count = 2
        fixture_migration_v0003_root_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_AIRCRAFT_ID,
        )

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        historical.architecture_brush_radius = -1
        historical.aircraft.count = 2
        fixture_migration_v0003_root_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_BRUSH_PRESET_ID,
        )

        fixture_migration_v0003_root_test_prepare(historical, tentative)
        nil_error := fixture_migration_v0003_root_test_call(t, historical, nil)
        testing.expect(t, nil_error.kind == .Invalid_Argument && nil_error.change_id == "")
    }
}
