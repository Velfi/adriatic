package main

import architecture "../packages/architecture"
import fixture_v0001 "../packages/fixture_history/v0001"
import terrain "../packages/terrain"
import "base:runtime"
import "core:mem"
import "core:testing"
import hs "zelda_engine:hs"

when ODIN_TEST {
    fixture_migration_structural_payload :: proc(
        terrain_count, city_structure_count, city_parcel_count, city_alley_count, city_lamp_count, farm_count: int,
        removed_city_structure_count := 0,
        removed_city_parcel_count := 0,
        removed_city_alley_count := 0,
        removed_city_lamp_count := 0,
    ) -> (
        []byte,
        bool,
    ) {
        historical := new(fixture_v0001.Fixture)
        fixture_migration_v0004_runtime_seed_legacy(historical, 1)
        historical.project.structure_count = terrain_count
        historical.project.structures[0].id = 0x100
        historical.project.structures[255].id = 0x1ff

        historical.architecture_city_plan.count = city_structure_count
        historical.architecture_city_plan.structures[0].id = 0x200
        historical.architecture_city_plan.structures[255].id = 0x2ff
        historical.architecture_city_plan.parcel_count = city_parcel_count
        historical.architecture_city_plan.parcels[0].seed = 0x300
        historical.architecture_city_plan.parcels[255].seed = 0x3ff
        historical.architecture_city_plan.alley_count = city_alley_count
        historical.architecture_city_plan.alleys[0].end_x = 400
        historical.architecture_city_plan.alleys[127].end_x = 499
        historical.architecture_city_plan.lamp_count = city_lamp_count
        historical.architecture_city_plan.lamps[0].x = 500
        historical.architecture_city_plan.lamps[255].x = 599

        historical.farm_count = farm_count
        historical.settlement_plan.city_plan.count = removed_city_structure_count
        historical.settlement_plan.city_plan.parcel_count = removed_city_parcel_count
        historical.settlement_plan.city_plan.alley_count = removed_city_alley_count
        historical.settlement_plan.city_plan.lamp_count = removed_city_lamp_count
        historical.farms[0].origin_x = 10
        historical.farms[0].plan.seed = 0x600
        historical.farms[1].origin_x = 20
        historical.farms[1].plan.seed = 0x601
        historical.farms[15].origin_x = 150
        historical.farms[15].plan.seed = 0x60f
        historical.farms[0].plan.parcel_count = 1
        historical.farms[0].plan.valid = true
        historical.farms[0].plan.parcels[0].min_x = 7
        historical.farms[0].plan.parcels[0].max_x = 19
        historical.architecture_brush_radius = 44
        historical.aircraft.slots[0].kind = .Postale
        historical.aircraft.slots[1].kind = .Libellula
        historical.aircraft.slots[2].kind = .Libellula_Mk2
        historical.aircraft.active = .Postale
        historical.aircraft.count = 3

        payload, portable_error, ok := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0001.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        free(historical)
        hs.portable_error_dispose(&portable_error)
        return payload, ok
    }

    fixture_migration_structural_payload_for_count :: proc(field, value: int) -> ([]byte, bool) {
        counts := [6]int{}
        counts[field] = value
        return fixture_migration_structural_payload(counts[0], counts[1], counts[2], counts[3], counts[4], counts[5])
    }

    fixture_migration_structural_prepare :: proc(
        payload: []byte,
        allocator: mem.Allocator,
    ) -> (
        historical: ^fixture_v0001.Fixture,
        tentative: ^Fixture,
        arena: ^mem.Dynamic_Arena,
        ok: bool,
    ) {
        allocated_arena, arena_ok := fixture_migration_arena_allocate(allocator)
        if !arena_ok do return
        arena = allocated_arena
        transaction_allocator := mem.dynamic_arena_allocator(arena)
        tentative = new(Fixture, transaction_allocator)
        historical = new(fixture_v0001.Fixture, transaction_allocator)
        if tentative == nil || historical == nil {
            fixture_migration_arena_dispose(arena, allocator)
            return nil, nil, nil, false
        }

        tentative_error, tentative_ok := hs.portable_decode(
            fixture_codec_value(tentative),
            payload,
            fixture_codec_migration_portable_config(),
            transaction_allocator,
        )
        if !tentative_ok {
            hs.portable_error_dispose(&tentative_error)
            fixture_migration_arena_dispose(arena, allocator)
            return nil, nil, nil, false
        }
        hs.portable_error_dispose(&tentative_error)

        historical_error, historical_ok := hs.portable_decode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0001.Fixture)},
            payload,
            fixture_codec_portable_config(),
            transaction_allocator,
        )
        if !historical_ok {
            hs.portable_error_dispose(&historical_error)
            fixture_migration_arena_dispose(arena, allocator)
            return nil, nil, nil, false
        }
        hs.portable_error_dispose(&historical_error)
        return historical, tentative, arena, true
    }

    fixture_migration_structural_manual :: proc() -> (^fixture_v0001.Fixture, ^Fixture) {
        historical := new(fixture_v0001.Fixture)
        tentative := new(Fixture)
        tentative.project.structures = make([dynamic]terrain.Structure, 256, context.allocator)
        tentative.architecture_city_plan.structures = make([dynamic]terrain.Structure, 256, context.allocator)
        tentative.architecture_city_plan.parcels = make([dynamic]architecture.City_Parcel, 256, context.allocator)
        tentative.architecture_city_plan.alleys = make([dynamic]architecture.City_Alley, 128, context.allocator)
        tentative.architecture_city_plan.lamps = make([dynamic]architecture.City_Lamp, 256, context.allocator)
        tentative.structure_selected = 123
        tentative.farm_count = 1
        tentative.farms[0].plan.width = 777
        tentative.farms[0].plan.height = 778
        tentative.farms[0].plan.tradition = .Parliamentary_Enclosure
        tentative.farms[0].scale_x = 779
        tentative.farms[0].scale_z = 780
        tentative.project.structures[0].id = 0x100
        tentative.project.structures[255].id = 0x1ff
        tentative.architecture_city_plan.structures[0].id = 0x200
        tentative.architecture_city_plan.structures[255].id = 0x2ff
        tentative.architecture_city_plan.parcels[0].seed = 0x300
        tentative.architecture_city_plan.parcels[255].seed = 0x3ff
        tentative.architecture_city_plan.alleys[0].end_x = 400
        tentative.architecture_city_plan.alleys[127].end_x = 499
        tentative.architecture_city_plan.lamps[0].x = 500
        tentative.architecture_city_plan.lamps[255].x = 599
        historical.farm_count = 1
        return historical, tentative
    }

    fixture_migration_structural_manual_destroy :: proc(historical: ^fixture_v0001.Fixture, tentative: ^Fixture) {
        if tentative != nil {
            architecture.city_plan_destroy(&tentative.architecture_city_plan)
            terrain.destroy_project(&tentative.project)
            free(tentative)
        }
        if historical != nil {
            free(historical)
        }
    }

    Fixture_Migration_Structural_Array_Snapshot :: struct {
        data:      rawptr,
        len:       int,
        cap:       int,
        allocator: mem.Allocator,
        bytes:     []byte,
    }

    Fixture_Migration_Structural_Snapshot :: struct {
        root_bytes:      []byte,
        project:         Fixture_Migration_Structural_Array_Snapshot,
        city_structures: Fixture_Migration_Structural_Array_Snapshot,
        city_parcels:    Fixture_Migration_Structural_Array_Snapshot,
        city_alleys:     Fixture_Migration_Structural_Array_Snapshot,
        city_lamps:      Fixture_Migration_Structural_Array_Snapshot,
    }

    fixture_migration_structural_snapshot_dispose :: proc(snapshot: ^Fixture_Migration_Structural_Snapshot) {
        if snapshot == nil do return
        delete(snapshot.root_bytes)
        delete(snapshot.project.bytes)
        delete(snapshot.city_structures.bytes)
        delete(snapshot.city_parcels.bytes)
        delete(snapshot.city_alleys.bytes)
        delete(snapshot.city_lamps.bytes)
        snapshot^ = {}
    }

    fixture_migration_structural_snapshot_array :: proc(
        raw: ^runtime.Raw_Dynamic_Array,
        element_size: int,
        allocator: mem.Allocator,
    ) -> (
        Fixture_Migration_Structural_Array_Snapshot,
        bool,
    ) {
        if raw == nil || element_size <= 0 || raw.len < 0 || raw.cap < raw.len {
            return {}, false
        }
        snapshot := Fixture_Migration_Structural_Array_Snapshot {
            data      = raw.data,
            len       = raw.len,
            cap       = raw.cap,
            allocator = raw.allocator,
        }
        byte_count := raw.cap * element_size
        if byte_count == 0 do return snapshot, true
        bytes, allocation_error := make([]byte, byte_count, allocator)
        if allocation_error != nil do return {}, false
        snapshot.bytes = bytes
        if raw.data == nil {
            delete(snapshot.bytes)
            return {}, false
        }
        copy(snapshot.bytes, mem.slice_ptr(cast([^]u8)raw.data, byte_count))
        return snapshot, true
    }

    fixture_migration_structural_snapshot :: proc(
        tentative: ^Fixture,
        allocator: mem.Allocator,
    ) -> (
        Fixture_Migration_Structural_Snapshot,
        bool,
    ) {
        if tentative == nil || allocator.procedure == nil do return {}, false
        snapshot := Fixture_Migration_Structural_Snapshot{}
        root_bytes, allocation_error := make([]byte, size_of(Fixture), allocator)
        if allocation_error != nil do return {}, false
        snapshot.root_bytes = root_bytes
        copy(snapshot.root_bytes, mem.slice_ptr(cast([^]u8)tentative, size_of(Fixture)))

        project, project_ok := fixture_migration_structural_snapshot_array(
            cast(^runtime.Raw_Dynamic_Array)&tentative.project.structures,
            size_of(terrain.Structure),
            allocator,
        )
        if !project_ok {
            fixture_migration_structural_snapshot_dispose(&snapshot)
            return {}, false
        }
        snapshot.project = project
        city_structures, city_structures_ok := fixture_migration_structural_snapshot_array(
            cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.structures,
            size_of(terrain.Structure),
            allocator,
        )
        if !city_structures_ok {
            fixture_migration_structural_snapshot_dispose(&snapshot)
            return {}, false
        }
        snapshot.city_structures = city_structures
        city_parcels, city_parcels_ok := fixture_migration_structural_snapshot_array(
            cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.parcels,
            size_of(architecture.City_Parcel),
            allocator,
        )
        if !city_parcels_ok {
            fixture_migration_structural_snapshot_dispose(&snapshot)
            return {}, false
        }
        snapshot.city_parcels = city_parcels
        city_alleys, city_alleys_ok := fixture_migration_structural_snapshot_array(
            cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.alleys,
            size_of(architecture.City_Alley),
            allocator,
        )
        if !city_alleys_ok {
            fixture_migration_structural_snapshot_dispose(&snapshot)
            return {}, false
        }
        snapshot.city_alleys = city_alleys
        city_lamps, city_lamps_ok := fixture_migration_structural_snapshot_array(
            cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.lamps,
            size_of(architecture.City_Lamp),
            allocator,
        )
        if !city_lamps_ok {
            fixture_migration_structural_snapshot_dispose(&snapshot)
            return {}, false
        }
        snapshot.city_lamps = city_lamps
        return snapshot, true
    }

    fixture_migration_structural_snapshot_array_matches :: proc(
        snapshot: Fixture_Migration_Structural_Array_Snapshot,
        raw: ^runtime.Raw_Dynamic_Array,
    ) -> bool {
        if raw == nil ||
           raw.data != snapshot.data ||
           raw.len != snapshot.len ||
           raw.cap != snapshot.cap ||
           raw.allocator.procedure != snapshot.allocator.procedure ||
           raw.allocator.data != snapshot.allocator.data {
            return false
        }
        if len(snapshot.bytes) == 0 do return true
        if raw.data == nil do return false
        current := mem.slice_ptr(cast([^]u8)raw.data, len(snapshot.bytes))
        return fixture_migration_test_bytes_equal(current, snapshot.bytes)
    }

    fixture_migration_structural_snapshot_matches :: proc(
        snapshot: Fixture_Migration_Structural_Snapshot,
        tentative: ^Fixture,
    ) -> bool {
        if tentative == nil do return false
        current_root := mem.slice_ptr(cast([^]u8)tentative, size_of(Fixture))
        if !fixture_migration_test_bytes_equal(current_root, snapshot.root_bytes) do return false
        return(
            fixture_migration_structural_snapshot_array_matches(
                snapshot.project,
                cast(^runtime.Raw_Dynamic_Array)&tentative.project.structures,
            ) &&
            fixture_migration_structural_snapshot_array_matches(
                snapshot.city_structures,
                cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.structures,
            ) &&
            fixture_migration_structural_snapshot_array_matches(
                snapshot.city_parcels,
                cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.parcels,
            ) &&
            fixture_migration_structural_snapshot_array_matches(
                snapshot.city_alleys,
                cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.alleys,
            ) &&
            fixture_migration_structural_snapshot_array_matches(
                snapshot.city_lamps,
                cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.lamps,
            ) \
        )
    }

    fixture_migration_structural_expect_direct_failure :: proc(
        t: ^testing.T,
        historical: ^fixture_v0001.Fixture,
        tentative: ^Fixture,
        expected_change_id: string,
    ) {
        snapshot, snapshot_ok := fixture_migration_structural_snapshot(tentative, context.allocator)
        testing.expect(t, snapshot_ok)
        if !snapshot_ok {
            fixture_migration_structural_manual_destroy(historical, tentative)
            return
        }
        error := fixture_migrate_v0001_to_v0002(historical^, tentative, context.allocator)
        testing.expect(t, error.kind == .Invalid_Source && error.change_id == expected_change_id)
        testing.expect(t, fixture_migration_structural_snapshot_matches(snapshot, tentative))
        fixture_migration_error_dispose(&error)
        fixture_migration_structural_snapshot_dispose(&snapshot)
        fixture_migration_structural_manual_destroy(historical, tentative)
    }

    fixture_migration_structural_expect_production_failure :: proc(
        t: ^testing.T,
        payload: []byte,
        expected_change_id: string,
    ) {
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        result, error, ok := fixture_migration_test_run_through_v0005(
            payload,
            1,
            fixture_migration_test_allocator(&state),
        )
        testing.expect(t, !ok && error.kind == .Step_Failure)
        testing.expect(t, error.change_id == expected_change_id)
        testing.expect(t, fixture_migration_result_empty(&result))
        fixture_migration_error_dispose(&error)
        fixture_migration_error_dispose(&error)
        fixture_migration_result_dispose(&result)
        fixture_migration_result_dispose(&result)
        testing.expect(t, fixture_migration_result_empty(&result))
        testing.expect(t, state.outstanding == 0)
    }

    @(test)
    fixture_migration_structural_migration_and_boundaries :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        expected_ids := [16]string {
            "field-add:adriatic:packages/farmland.Plan.height",
            "field-add:adriatic:packages/farmland.Plan.tradition",
            "field-add:adriatic:packages/farmland.Plan.width",
            "field-add:adriatic:packages/story.State.airfield_errand",
            "field-add:adriatic:packages/story.State.quest",
            "field-add:adriatic:src.Farm_Instance.scale_x",
            "field-add:adriatic:src.Farm_Instance.scale_z",
            "field-add:adriatic:src.Fixture.quest_tracking_revision",
            "field-add:adriatic:src.Fixture.quest_tracking_suppressed",
            "field-add:adriatic:src.Fixture.tracked_quest_node",
            "field-remove:adriatic:src.Settlement_Plan.city_plan",
            "field-type:adriatic:packages/architecture.City_Plan.alleys",
            "field-type:adriatic:packages/architecture.City_Plan.lamps",
            "field-type:adriatic:packages/architecture.City_Plan.parcels",
            "field-type:adriatic:packages/architecture.City_Plan.structures",
            "field-type:adriatic:packages/terrain.Project.structures",
        }
        scripted_count := 0
        unresolved_count := 0
        for resolution, index in FIXTURE_MIGRATION_V0001_TO_V0002_RESOLUTIONS {
            testing.expect(t, resolution.change_id == expected_ids[index])
            if resolution.kind == .Scripted {
                scripted_count += 1
            } else {
                testing.expect(t, false)
            }
        }
        testing.expect(t, scripted_count == 16 && unresolved_count == 0)

        for boundary in 0 ..< 2 {
            count := 0
            if boundary == 1 {
                count = 256
            }
            farm_count := 0
            alley_count := 0
            if boundary == 1 do farm_count = 16
            if boundary == 1 do alley_count = 128
            payload, payload_ok := fixture_migration_structural_payload(
                count,
                count,
                count,
                alley_count,
                count,
                farm_count,
            )
            testing.expect(t, payload_ok)
            historical, tentative, arena, prepared := fixture_migration_structural_prepare(
                payload,
                runtime.default_allocator(),
            )
            testing.expect(t, prepared)
            if !prepared {
                delete(payload)
                continue
            }

            project_raw := cast(^runtime.Raw_Dynamic_Array)(&tentative.project.structures)
            city_structures_raw := cast(^runtime.Raw_Dynamic_Array)(&tentative.architecture_city_plan.structures)
            city_parcels_raw := cast(^runtime.Raw_Dynamic_Array)(&tentative.architecture_city_plan.parcels)
            city_alleys_raw := cast(^runtime.Raw_Dynamic_Array)(&tentative.architecture_city_plan.alleys)
            city_lamps_raw := cast(^runtime.Raw_Dynamic_Array)(&tentative.architecture_city_plan.lamps)
            project_data, project_cap, project_allocator :=
                project_raw.data, project_raw.cap, project_raw.allocator.data
            city_structures_data, city_structures_cap, city_structures_allocator :=
                city_structures_raw.data, city_structures_raw.cap, city_structures_raw.allocator.data
            city_parcels_data, city_parcels_cap, city_parcels_allocator :=
                city_parcels_raw.data, city_parcels_raw.cap, city_parcels_raw.allocator.data
            city_alleys_data, city_alleys_cap, city_alleys_allocator :=
                city_alleys_raw.data, city_alleys_raw.cap, city_alleys_raw.allocator.data
            city_lamps_data, city_lamps_cap, city_lamps_allocator :=
                city_lamps_raw.data, city_lamps_raw.cap, city_lamps_raw.allocator.data

            error := fixture_migrate_v0001_to_v0002(historical^, tentative, mem.dynamic_arena_allocator(arena))
            testing.expect(t, error.kind == .None)
            testing.expect(
                t,
                project_raw.data == project_data &&
                project_raw.cap == project_cap &&
                project_raw.allocator.data == project_allocator,
            )
            testing.expect(
                t,
                city_structures_raw.data == city_structures_data &&
                city_structures_raw.cap == city_structures_cap &&
                city_structures_raw.allocator.data == city_structures_allocator,
            )
            testing.expect(
                t,
                city_parcels_raw.data == city_parcels_data &&
                city_parcels_raw.cap == city_parcels_cap &&
                city_parcels_raw.allocator.data == city_parcels_allocator,
            )
            testing.expect(
                t,
                city_alleys_raw.data == city_alleys_data &&
                city_alleys_raw.cap == city_alleys_cap &&
                city_alleys_raw.allocator.data == city_alleys_allocator,
            )
            testing.expect(
                t,
                city_lamps_raw.data == city_lamps_data &&
                city_lamps_raw.cap == city_lamps_cap &&
                city_lamps_raw.allocator.data == city_lamps_allocator,
            )
            testing.expect(t, len(tentative.project.structures) == count)
            testing.expect(t, len(tentative.architecture_city_plan.structures) == count)
            testing.expect(t, len(tentative.architecture_city_plan.parcels) == count)
            testing.expect(t, len(tentative.architecture_city_plan.alleys) == alley_count)
            testing.expect(t, len(tentative.architecture_city_plan.lamps) == count)
            if boundary == 1 {
                testing.expect(
                    t,
                    tentative.project.structures[0].id == 0x100 && tentative.project.structures[255].id == 0x1ff,
                )
                testing.expect(
                    t,
                    tentative.architecture_city_plan.structures[0].id == 0x200 &&
                    tentative.architecture_city_plan.structures[255].id == 0x2ff,
                )
                testing.expect(
                    t,
                    tentative.architecture_city_plan.parcels[0].seed == 0x300 &&
                    tentative.architecture_city_plan.parcels[255].seed == 0x3ff,
                )
                testing.expect(
                    t,
                    tentative.architecture_city_plan.alleys[0].end_x == 400 &&
                    tentative.architecture_city_plan.alleys[127].end_x == 499,
                )
                testing.expect(
                    t,
                    tentative.architecture_city_plan.lamps[0].x == 500 &&
                    tentative.architecture_city_plan.lamps[255].x == 599,
                )
                for farm in &tentative.farms {
                    testing.expect(t, farm.plan.width == 25 && farm.plan.height == 19)
                    testing.expect(t, farm.plan.tradition == .Ancient_Enclosure)
                    testing.expect(t, farm.scale_x == 1 && farm.scale_z == 1)
                }
            }
            fixture_migration_error_dispose(&error)
            fixture_migration_arena_dispose(arena, runtime.default_allocator())
            delete(payload)
        }

        payload, payload_ok := fixture_migration_structural_payload(1, 1, 1, 1, 1, 1)
        testing.expect(t, payload_ok)
        historical, tentative, arena, prepared := fixture_migration_structural_prepare(
            payload,
            runtime.default_allocator(),
        )
        testing.expect(t, prepared)
        if prepared {
            error := fixture_migrate_v0001_to_v0002(historical^, tentative, mem.dynamic_arena_allocator(arena))
            testing.expect(t, error.kind == .None)
            testing.expect(
                t,
                len(tentative.project.structures) == 1 && len(tentative.architecture_city_plan.structures) == 1,
            )
            testing.expect(
                t,
                tentative.farms[0].plan.width == 25 &&
                tentative.farms[0].plan.height == 19 &&
                tentative.farms[0].plan.tradition == .Ancient_Enclosure,
            )
            testing.expect(t, tentative.farms[0].scale_x == 1 && tentative.farms[0].scale_z == 1)
            testing.expect(t, tentative.farms[1].plan.width == 0 && tentative.farms[1].plan.height == 0)
            testing.expect(
                t,
                tentative.farms[1].plan.tradition == .Ancient_Enclosure &&
                tentative.farms[1].scale_x == 0 &&
                tentative.farms[1].scale_z == 0,
            )
            testing.expect(t, tentative.farms[0].origin_x == 10 && tentative.farms[0].plan.seed == 0x600)
            testing.expect(t, tentative.farms[0].plan.parcel_count == 1 && tentative.farms[0].plan.valid)
            testing.expect(
                t,
                tentative.farms[0].plan.parcels[0].min_x == 7 && tentative.farms[0].plan.parcels[0].max_x == 19,
            )
            testing.expect(t, tentative.farms[1].origin_x == 20 && tentative.farms[1].plan.seed == 0x601)
            fixture_migration_error_dispose(&error)
            fixture_migration_arena_dispose(arena, runtime.default_allocator())
        }
        delete(payload)

        for polarity in 0 ..< 2 {
            for field in 0 ..< 6 {
                case_historical, case_tentative := fixture_migration_structural_manual()
                invalid := -1
                if polarity == 1 {
                    invalid = 257
                    if field == 3 do invalid = 129
                    if field == 4 do invalid = 257
                    if field == 5 do invalid = 17
                }
                switch field {
                case 0:
                    case_historical.project.structure_count = invalid
                case 1:
                    case_historical.architecture_city_plan.count = invalid
                case 2:
                    case_historical.architecture_city_plan.parcel_count = invalid
                case 3:
                    case_historical.architecture_city_plan.alley_count = invalid
                case 4:
                    case_historical.architecture_city_plan.lamp_count = invalid
                case 5:
                    case_historical.farm_count = invalid
                }
                expected := FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID
                if field == 1 do expected = FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_ID
                if field == 2 do expected = FIXTURE_MIGRATION_V0001_CITY_PARCELS_ID
                if field == 3 do expected = FIXTURE_MIGRATION_V0001_CITY_ALLEYS_ID
                if field == 4 do expected = FIXTURE_MIGRATION_V0001_CITY_LAMPS_ID
                if field == 5 do expected = FIXTURE_MIGRATION_V0001_FARM_DEFAULT_ID
                fixture_migration_structural_expect_direct_failure(t, case_historical, case_tentative, expected)
            }
        }

        for field in 0 ..< 5 {
            for polarity in 0 ..< 2 {
                case_historical, case_tentative := fixture_migration_structural_manual()
                length := 255
                if field == 3 {
                    length = 127
                    if polarity == 1 do length = 129
                } else if polarity == 1 {
                    length = 257
                }
                switch field {
                case 0:
                    resize(&case_tentative.project.structures, length)
                case 1:
                    resize(&case_tentative.architecture_city_plan.structures, length)
                case 2:
                    resize(&case_tentative.architecture_city_plan.parcels, length)
                case 3:
                    resize(&case_tentative.architecture_city_plan.alleys, length)
                case 4:
                    resize(&case_tentative.architecture_city_plan.lamps, length)
                }
                expected := FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID
                if field == 1 do expected = FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_ID
                if field == 2 do expected = FIXTURE_MIGRATION_V0001_CITY_PARCELS_ID
                if field == 3 do expected = FIXTURE_MIGRATION_V0001_CITY_ALLEYS_ID
                if field == 4 do expected = FIXTURE_MIGRATION_V0001_CITY_LAMPS_ID
                fixture_migration_structural_expect_direct_failure(t, case_historical, case_tentative, expected)
            }
        }

        for field in 0 ..< 4 {
            for mode in 0 ..< 4 {
                case_historical, case_tentative := fixture_migration_structural_manual()
                value := -1
                if mode == 1 {
                    value = 256
                    if field == 2 do value = 128
                } else if mode == 2 {
                    value = 257
                    if field == 2 do value = 129
                } else if mode == 3 {
                    value = 1
                }
                switch field {
                case 0:
                    case_historical.settlement_plan.city_plan.count = value
                case 1:
                    case_historical.settlement_plan.city_plan.parcel_count = value
                case 2:
                    case_historical.settlement_plan.city_plan.alley_count = value
                case 3:
                    case_historical.settlement_plan.city_plan.lamp_count = value
                }
                fixture_migration_structural_expect_direct_failure(
                    t,
                    case_historical,
                    case_tentative,
                    FIXTURE_MIGRATION_V0001_CITY_REMOVE_ID,
                )
            }
        }

        preparation_payload, preparation_payload_ok := fixture_migration_structural_payload(1, 1, 1, 1, 1, 1)
        testing.expect(t, preparation_payload_ok)
        if preparation_payload_ok {
            preparation_state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = -1,
            }
            _, _, preparation_arena, preparation_ok := fixture_migration_structural_prepare(
                preparation_payload,
                fixture_migration_test_allocator(&preparation_state),
            )
            testing.expect(t, preparation_ok)
            preparation_allocation_count := preparation_state.allocation_calls
            if preparation_ok {
                fixture_migration_arena_dispose(
                    preparation_arena,
                    fixture_migration_test_allocator(&preparation_state),
                )
            }
            testing.expect(t, preparation_state.outstanding == 0)

            for fail_at := 0; fail_at < preparation_allocation_count; fail_at += 1 {
                preparation_state.fail_at = fail_at
                preparation_state.allocation_calls = 0
                preparation_state.outstanding = 0
                failed_historical, failed_tentative, failed_arena, failed_ok := fixture_migration_structural_prepare(
                    preparation_payload,
                    fixture_migration_test_allocator(&preparation_state),
                )
                testing.expect(t, !failed_ok)
                testing.expect(t, failed_historical == nil && failed_tentative == nil && failed_arena == nil)
                if failed_ok {
                    fixture_migration_arena_dispose(failed_arena, fixture_migration_test_allocator(&preparation_state))
                }
                testing.expect(t, preparation_state.outstanding == 0)
            }

            preparation_state.fail_at = -1
            preparation_state.allocation_calls = 0
            preparation_state.outstanding = 0
            zero_alloc_historical, zero_alloc_tentative, zero_alloc_arena, zero_alloc_ok :=
                fixture_migration_structural_prepare(
                    preparation_payload,
                    fixture_migration_test_allocator(&preparation_state),
                )
            testing.expect(t, zero_alloc_ok)
            if zero_alloc_ok {
                allocations_before_step := preparation_state.allocation_calls
                zero_alloc_error := fixture_migrate_v0001_to_v0002(
                    zero_alloc_historical^,
                    zero_alloc_tentative,
                    mem.dynamic_arena_allocator(zero_alloc_arena),
                )
                testing.expect(t, zero_alloc_error.kind == .None)
                testing.expect(t, preparation_state.allocation_calls == allocations_before_step)
                fixture_migration_error_dispose(&zero_alloc_error)
                fixture_migration_arena_dispose(zero_alloc_arena, fixture_migration_test_allocator(&preparation_state))
            }
            testing.expect(t, preparation_state.outstanding == 0)
        }
        delete(preparation_payload)

        for field in 0 ..< 6 {
            for polarity in 0 ..< 2 {
                value := -1
                if polarity == 1 {
                    value = 257
                    if field == 3 do value = 129
                }
                production_payload, production_payload_ok := fixture_migration_structural_payload_for_count(
                    field,
                    value,
                )
                testing.expect(t, production_payload_ok)
                if production_payload_ok {
                    expected := FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID
                    if field == 1 do expected = FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_ID
                    if field == 2 do expected = FIXTURE_MIGRATION_V0001_CITY_PARCELS_ID
                    if field == 3 do expected = FIXTURE_MIGRATION_V0001_CITY_ALLEYS_ID
                    if field == 4 do expected = FIXTURE_MIGRATION_V0001_CITY_LAMPS_ID
                    if field == 5 do expected = FIXTURE_MIGRATION_V0001_FARM_DEFAULT_ID
                    fixture_migration_structural_expect_production_failure(t, production_payload, expected)
                }
                delete(production_payload)
            }
        }

        for field in 0 ..< 4 {
            for mode in 0 ..< 4 {
                removed := [4]int{}
                value := -1
                if mode == 1 {
                    value = 256
                    if field == 2 do value = 128
                } else if mode == 2 {
                    value = 257
                    if field == 2 do value = 129
                } else if mode == 3 {
                    value = 1
                }
                removed[field] = value
                production_payload, production_payload_ok := fixture_migration_structural_payload(
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    removed[0],
                    removed[1],
                    removed[2],
                    removed[3],
                )
                testing.expect(t, production_payload_ok)
                if production_payload_ok {
                    fixture_migration_structural_expect_production_failure(
                        t,
                        production_payload,
                        FIXTURE_MIGRATION_V0001_CITY_REMOVE_ID,
                    )
                }
                delete(production_payload)
            }
        }

        invalid_payload, invalid_payload_ok := fixture_migration_structural_payload(-1, 0, 0, 0, 0, 0)
        testing.expect(t, invalid_payload_ok)
        invalid_result, invalid_error, invalid_ok := fixture_migration_test_run_through_v0005(
            invalid_payload,
            1,
            runtime.default_allocator(),
        )
        testing.expect(t, !invalid_ok && invalid_error.kind == .Step_Failure)
        testing.expect(t, invalid_error.change_id == FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID)
        testing.expect(t, fixture_migration_result_empty(&invalid_result))
        fixture_migration_error_dispose(&invalid_error)
        fixture_migration_result_dispose(&invalid_result)
        delete(invalid_payload)

        valid_payload, valid_payload_ok := fixture_migration_structural_payload(1, 1, 1, 1, 1, 1)
        testing.expect(t, valid_payload_ok)
        result, error, ok := fixture_migration_test_run_through_v0005(valid_payload, 1, runtime.default_allocator())
        testing.expect(t, ok && error.kind == .None)
        testing.expect(t, result.fixture != nil)
        testing.expect(t, result.fixture.story_state.quest.definition_id == "two-island-story")
        testing.expect(t, result.fixture.story_state.quest.node_count == 13)
        testing.expect(t, result.fixture.story_state.airfield_errand == .Not_Offered)
        testing.expect(t, result.fixture.quest_tracking_revision == result.fixture.story_state.quest.revision)
        testing.expect(t, result.fixture.occupant == .On_Foot)
        fixture_migration_error_dispose(&error)
        fixture_migration_result_dispose(&result)
        fixture_migration_result_dispose(&result)
        testing.expect(t, fixture_migration_result_empty(&result))
        delete(valid_payload)
    }
}
