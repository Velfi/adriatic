package main

import buildings "../packages/buildings"
import fixture_v0003 "../packages/fixture_history/v0003"
import fixture_schema "../packages/fixture_schema"
import marina "../packages/marina"
import story "../packages/story"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "base:runtime"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

when ODIN_TEST {
    fixture_migration_v0003_enum_test_make :: proc(
        t: ^testing.T,
    ) -> (
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        ok: bool,
    ) {
        historical = new(fixture_v0003.Fixture, context.allocator)
        tentative = new(Fixture, context.allocator)
        testing.expect(t, historical != nil && tentative != nil)
        if historical == nil || tentative == nil do return historical, tentative, false

        historical.project.structures = make([dynamic]fixture_v0003.History_Type_0087, 2, context.allocator)
        historical.architecture_city_plan.structures = make(
            [dynamic]fixture_v0003.History_Type_0087,
            2,
            context.allocator,
        )
        tentative.project.structures = make([dynamic]terrain.Structure, 2, context.allocator)
        tentative.architecture_city_plan.structures = make([dynamic]terrain.Structure, 2, context.allocator)

        historical.project.structures[0].building.archetype = .Cycladic_Bell
        historical.project.structures[0].building.landmark_kind = .Cycladic_Bell
        historical.architecture_city_plan.structures[1].building.archetype = .Market_Hall
        historical.architecture_city_plan.structures[1].building.landmark_kind = .Market_Hall
        historical.settlement_plan.sites[255].structure.building.archetype = .Harbor_Office
        historical.settlement_plan.sites[255].structure.building.landmark_kind = .Harbor_Office
        historical.settlement_plan.rejected_sites[31].structure.building.archetype = .Fortress_Gate
        historical.settlement_plan.rejected_sites[31].structure.building.landmark_kind = .Fortress_Gate
        historical.settlement_plan.decorative_foliage[31].building.archetype = .Monastery
        historical.settlement_plan.decorative_foliage[31].building.landmark_kind = .Monastery
        historical.marina_authored_plan.shoreline_form = .Stepped_Quays
        historical.story_state.delivery.from = .Zora
        historical.story_state.delivery.to = .Marta
        for &slot, index in historical.aircraft.slots {
            slot.kind = fixture_v0003.History_Type_0097(index % 3)
        }
        historical.aircraft.active = .Libellula_Mk2
        historical.occupant = .Libellula_Mk2
        historical.authoring_tool = .ClimbingLeaves
        historical.mouse_headgear = .Flat_Cap
        historical.settlement_plan.acceptance_failure = .Park_Count
        return historical, tentative, true
    }

    fixture_migration_v0003_enum_test_destroy :: proc(historical: ^fixture_v0003.Fixture, tentative: ^Fixture) {
        if historical != nil {
            delete(historical.project.structures)
            delete(historical.architecture_city_plan.structures)
            free(historical, context.allocator)
        }
        if tentative != nil {
            delete(tentative.project.structures)
            delete(tentative.architecture_city_plan.structures)
            free(tentative, context.allocator)
        }
    }

    fixture_migration_v0003_enum_test_set_sentinels :: proc(tentative: ^Fixture) {
        for &structure in tentative.project.structures {
            structure.building.archetype = .Post_Office
            structure.building.landmark_kind = .Post_Office
        }
        for &structure in tentative.architecture_city_plan.structures {
            structure.building.archetype = .Post_Office
            structure.building.landmark_kind = .Post_Office
        }
        for &site in tentative.settlement_plan.sites {
            site.structure.building.archetype = .Post_Office
            site.structure.building.landmark_kind = .Post_Office
        }
        for &site in tentative.settlement_plan.rejected_sites {
            site.structure.building.archetype = .Post_Office
            site.structure.building.landmark_kind = .Post_Office
        }
        for &structure in tentative.settlement_plan.decorative_foliage {
            structure.building.archetype = .Post_Office
            structure.building.landmark_kind = .Post_Office
        }
        tentative.marina_authored_plan.shoreline_form = .Natural_Shore
        tentative.story_state.delivery.from = .Lena
        tentative.story_state.delivery.to = .Lena
        for &slot in tentative.aircraft.slots do slot.kind = .Rondine
        tentative.aircraft.active = .Rondine
        tentative.occupant = .Rondine
        tentative.authoring_tool = .Wreck
        tentative.mouse_headgear = .Sailor_Hat
        tentative.settlement_plan.acceptance_failure = .Building_Access
    }

    fixture_migration_v0003_enum_test_expect_mapping :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        root_applied := false,
    ) {
        for structure, index in historical.project.structures {
            testing.expect(
                t,
                int(tentative.project.structures[index].building.archetype) == int(structure.building.archetype),
            )
            testing.expect(
                t,
                int(tentative.project.structures[index].building.landmark_kind) ==
                int(structure.building.landmark_kind),
            )
        }
        for structure, index in historical.architecture_city_plan.structures {
            testing.expect(
                t,
                int(tentative.architecture_city_plan.structures[index].building.archetype) ==
                int(structure.building.archetype),
            )
            testing.expect(
                t,
                int(tentative.architecture_city_plan.structures[index].building.landmark_kind) ==
                int(structure.building.landmark_kind),
            )
        }
        for site, index in historical.settlement_plan.sites {
            testing.expect(
                t,
                int(tentative.settlement_plan.sites[index].structure.building.archetype) ==
                int(site.structure.building.archetype),
            )
            testing.expect(
                t,
                int(tentative.settlement_plan.sites[index].structure.building.landmark_kind) ==
                int(site.structure.building.landmark_kind),
            )
        }
        for site, index in historical.settlement_plan.rejected_sites {
            testing.expect(
                t,
                int(tentative.settlement_plan.rejected_sites[index].structure.building.archetype) ==
                int(site.structure.building.archetype),
            )
            testing.expect(
                t,
                int(tentative.settlement_plan.rejected_sites[index].structure.building.landmark_kind) ==
                int(site.structure.building.landmark_kind),
            )
        }
        for structure, index in historical.settlement_plan.decorative_foliage {
            testing.expect(
                t,
                int(tentative.settlement_plan.decorative_foliage[index].building.archetype) ==
                int(structure.building.archetype),
            )
            testing.expect(
                t,
                int(tentative.settlement_plan.decorative_foliage[index].building.landmark_kind) ==
                int(structure.building.landmark_kind),
            )
        }
        testing.expect(
            t,
            int(tentative.marina_authored_plan.shoreline_form) ==
            int(historical.marina_authored_plan.shoreline_form) + 1,
        )
        testing.expect(
            t,
            int(tentative.story_state.delivery.from) == int(historical.story_state.delivery.from) &&
            int(tentative.story_state.delivery.to) == int(historical.story_state.delivery.to),
        )
        for slot, index in historical.aircraft.slots {
            if root_applied && index == 3 do continue
            testing.expect(t, int(tentative.aircraft.slots[index].kind) == int(slot.kind))
        }
        testing.expect(t, int(tentative.aircraft.active) == int(historical.aircraft.active))
        testing.expect(t, int(tentative.occupant) == int(historical.occupant))
        expected_authoring := int(historical.authoring_tool)
        if expected_authoring >= 10 do expected_authoring += 1
        testing.expect(t, int(tentative.authoring_tool) == expected_authoring)
        testing.expect(t, int(tentative.mouse_headgear) == int(historical.mouse_headgear))
        expected_failure := int(historical.settlement_plan.acceptance_failure)
        if expected_failure >= 5 do expected_failure += 1
        testing.expect(t, int(tentative.settlement_plan.acceptance_failure) == expected_failure)
    }

    fixture_migration_v0003_enum_test_call :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
    ) -> Fixture_Migration_Error {
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = 0,
        }
        error := fixture_migration_v0003_enum_slice(historical^, tentative, fixture_migration_test_allocator(&state))
        testing.expect(t, state.allocation_calls == 0 && state.outstanding == 0)
        return error
    }

    fixture_migration_v0003_enum_test_expect_failure :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        expected_id: string,
    ) {
        snapshot, snapshot_ok := fixture_migration_structural_snapshot(tentative, context.allocator)
        testing.expect(t, snapshot_ok)
        if !snapshot_ok do return
        error := fixture_migration_v0003_enum_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .Invalid_Source && error.change_id == expected_id)
        testing.expect(t, fixture_migration_structural_snapshot_matches(snapshot, tentative))
        fixture_migration_structural_snapshot_dispose(&snapshot)
    }

    fixture_migration_v0003_enum_test_validate_scaffold :: proc(t: ^testing.T) {
        source, source_error := os.read_entire_file("src/fixture_migration_v0003_to_v0004.odin", context.allocator)
        testing.expect(t, source_error == nil)
        if source_error != nil do return
        defer delete(source)
        scaffold, parse_error, parse_ok := fixture_schema.migration_scaffold_parse(source, context.allocator)
        testing.expect(t, parse_ok && parse_error.kind == .None)
        fixture_schema.migration_scaffold_error_dispose(&parse_error)
        if !parse_ok do return
        defer fixture_schema.migration_scaffold_dispose(&scaffold)

        v3, v3_error := os.read_entire_file("fixtures/schema/v0003.fixture-schema", context.allocator)
        testing.expect(t, v3_error == nil)
        if v3_error != nil do return
        defer delete(v3)
        v4, v4_error := os.read_entire_file("fixtures/schema/v0004.fixture-schema", context.allocator)
        testing.expect(t, v4_error == nil)
        if v4_error != nil do return
        defer delete(v4)
        report, report_error, report_ok := fixture_schema.schema_diff_build_report(v3, v4, 3, 4, context.allocator)
        testing.expect(t, report_ok && report_error.kind == .None)
        fixture_schema.schema_diff_error_dispose(&report_error)
        if !report_ok do return
        defer fixture_schema.schema_diff_report_dispose(&report)
        validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&scaffold, &report)
        testing.expect(t, validation_ok && validation_error.kind == .None)
        fixture_schema.migration_scaffold_error_dispose(&validation_error)

        testing.expect(t, len(scaffold.resolutions) == len(FIXTURE_MIGRATION_V0003_TO_V0004_RESOLUTIONS))
        scripted, unresolved, automatic := 0, 0, 0
        previous_id := ""
        for resolution, index in FIXTURE_MIGRATION_V0003_TO_V0004_RESOLUTIONS {
            testing.expect(t, resolution.change_id == scaffold.resolutions[index].change_id)
            testing.expect(t, resolution.kind == Fixture_Migration_Resolution_Kind(scaffold.resolutions[index].kind))
            if index > 0 do testing.expect(t, previous_id < resolution.change_id)
            previous_id = resolution.change_id
            switch resolution.kind {
            case .Scripted:
                scripted += 1
            case .Unresolved:
                unresolved += 1
            case .Automatic:
                automatic += 1
            }
        }
        testing.expect(t, scripted == 100 && unresolved == 0 && automatic == 0)
    }

    @(test)
    fixture_migration_v0003_to_v0004_enum_slice_and_failures :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
        fixture_migration_v0003_enum_test_validate_scaffold(t)

        historical, tentative, made := fixture_migration_v0003_enum_test_make(t)
        if !made {
            fixture_migration_v0003_enum_test_destroy(historical, tentative)
            return
        }
        defer fixture_migration_v0003_enum_test_destroy(historical, tentative)

        fixture_migration_v0003_enum_test_set_sentinels(tentative)
        before, before_ok := fixture_migration_structural_snapshot(tentative, context.allocator)
        testing.expect(t, before_ok)
        if !before_ok do return
        error := fixture_migration_v0003_enum_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .Unresolved && error.change_id == FIXTURE_MIGRATION_V0003_STRUCTURAL_ID)
        fixture_migration_v0003_enum_test_expect_mapping(t, historical, tentative)
        fixture_migration_v0003_enum_test_set_sentinels(tentative)
        testing.expect(t, fixture_migration_structural_snapshot_matches(before, tentative))
        fixture_migration_structural_snapshot_dispose(&before)

        for value in 0 ..= 4 {
            historical.marina_authored_plan.shoreline_form = fixture_v0003.History_Type_0045(value)
            error = fixture_migration_v0003_enum_test_call(t, historical, tentative)
            testing.expect(
                t,
                error.kind == .Unresolved && int(tentative.marina_authored_plan.shoreline_form) == value + 1,
            )
        }
        for value in 0 ..= 12 {
            historical.authoring_tool = fixture_v0003.History_Type_0106(value)
            error = fixture_migration_v0003_enum_test_call(t, historical, tentative)
            expected := value
            if expected >= 10 do expected += 1
            testing.expect(t, error.kind == .Unresolved && int(tentative.authoring_tool) == expected)
        }
        for value in 0 ..= 16 {
            historical.settlement_plan.acceptance_failure = fixture_v0003.History_Type_0123(value)
            error = fixture_migration_v0003_enum_test_call(t, historical, tentative)
            expected := value
            if expected >= 5 do expected += 1
            testing.expect(
                t,
                error.kind == .Unresolved && int(tentative.settlement_plan.acceptance_failure) == expected,
            )
        }

        historical.project.structures[1].building.archetype = fixture_v0003.History_Type_0014(18)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        historical.project.structures[1].building.archetype = .Legacy
        historical.project.structures[1].building.landmark_kind = fixture_v0003.History_Type_0016(9)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_LANDMARK_ID)
        historical.project.structures[1].building.landmark_kind = .None
        historical.architecture_city_plan.structures[0].building.archetype = fixture_v0003.History_Type_0014(18)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        historical.architecture_city_plan.structures[0].building.archetype = .Legacy
        historical.architecture_city_plan.structures[0].building.landmark_kind = fixture_v0003.History_Type_0016(9)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_LANDMARK_ID)
        historical.architecture_city_plan.structures[0].building.landmark_kind = .None
        historical.settlement_plan.sites[255].structure.building.archetype = fixture_v0003.History_Type_0014(18)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        historical.settlement_plan.sites[255].structure.building.archetype = .Legacy
        historical.settlement_plan.sites[255].structure.building.landmark_kind = fixture_v0003.History_Type_0016(9)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_LANDMARK_ID)
        historical.settlement_plan.sites[255].structure.building.landmark_kind = .None
        historical.settlement_plan.rejected_sites[31].structure.building.archetype = fixture_v0003.History_Type_0014(
            18,
        )
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        historical.settlement_plan.rejected_sites[31].structure.building.archetype = .Legacy
        historical.settlement_plan.rejected_sites[31].structure.building.landmark_kind =
            fixture_v0003.History_Type_0016(9)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_LANDMARK_ID)
        historical.settlement_plan.rejected_sites[31].structure.building.landmark_kind = .None
        historical.settlement_plan.decorative_foliage[31].building.archetype = fixture_v0003.History_Type_0014(18)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        historical.settlement_plan.decorative_foliage[31].building.archetype = .Legacy
        historical.settlement_plan.decorative_foliage[31].building.landmark_kind = fixture_v0003.History_Type_0016(9)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_LANDMARK_ID)
        historical.settlement_plan.decorative_foliage[31].building.landmark_kind = .None
        historical.marina_authored_plan.shoreline_form = fixture_v0003.History_Type_0045(5)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_SHORELINE_ID,
        )
        historical.marina_authored_plan.shoreline_form = .Straight_Quay
        historical.story_state.delivery.from = fixture_v0003.History_Type_0076(6)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_RESIDENT_ID)
        historical.story_state.delivery.from = .Marta
        historical.aircraft.slots[7].kind = fixture_v0003.History_Type_0097(3)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_AIRCRAFT_ID)
        historical.aircraft.slots[7].kind = .Postale
        historical.occupant = fixture_v0003.History_Type_0103(5)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_OCCUPANT_ID)
        historical.occupant = .On_Foot
        historical.authoring_tool = fixture_v0003.History_Type_0106(13)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_AUTHORING_ID,
        )
        historical.authoring_tool = .Sculpt
        historical.mouse_headgear = fixture_v0003.History_Type_0113(11)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_MOUSE_ACCESSORY_ID,
        )
        historical.mouse_headgear = .None
        historical.settlement_plan.acceptance_failure = fixture_v0003.History_Type_0123(17)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_SETTLEMENT_FAILURE_ID,
        )
        historical.settlement_plan.acceptance_failure = .None

        historical.project.structures[1].building.archetype = fixture_v0003.History_Type_0014(255)
        historical.project.structures[0].building.landmark_kind = fixture_v0003.History_Type_0016(9)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        historical.project.structures[1].building.archetype = .Legacy
        historical.project.structures[0].building.landmark_kind = .None
        historical.project.structures[0].building.landmark_kind = fixture_v0003.History_Type_0016(255)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_LANDMARK_ID)
        historical.project.structures[0].building.landmark_kind = .None
        historical.marina_authored_plan.shoreline_form = fixture_v0003.History_Type_0045(255)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_SHORELINE_ID,
        )
        historical.marina_authored_plan.shoreline_form = .Straight_Quay
        historical.aircraft.active = fixture_v0003.History_Type_0097(255)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_AIRCRAFT_ID)
        historical.aircraft.active = .Postale
        historical.occupant = fixture_v0003.History_Type_0103(255)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_OCCUPANT_ID)
        historical.occupant = .On_Foot
        historical.story_state.delivery.from = fixture_v0003.History_Type_0076(255)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_RESIDENT_ID)
        historical.story_state.delivery.from = .Marta
        historical.authoring_tool = fixture_v0003.History_Type_0106(255)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_AUTHORING_ID,
        )
        historical.authoring_tool = .Sculpt
        historical.mouse_headgear = fixture_v0003.History_Type_0113(255)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_MOUSE_ACCESSORY_ID,
        )
        historical.mouse_headgear = .None
        historical.settlement_plan.acceptance_failure = fixture_v0003.History_Type_0123(255)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_SETTLEMENT_FAILURE_ID,
        )
        historical.settlement_plan.acceptance_failure = .None

        historical.story_state.delivery.to = fixture_v0003.History_Type_0076(-1)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_RESIDENT_ID)
        historical.story_state.delivery.to = .Marta
        historical.authoring_tool = fixture_v0003.History_Type_0106(-1)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_AUTHORING_ID,
        )
        historical.authoring_tool = .Sculpt
        historical.mouse_headgear = fixture_v0003.History_Type_0113(-1)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_MOUSE_ACCESSORY_ID,
        )
        historical.mouse_headgear = .None
        historical.settlement_plan.acceptance_failure = fixture_v0003.History_Type_0123(-1)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_SETTLEMENT_FAILURE_ID,
        )
        historical.settlement_plan.acceptance_failure = .None

        historical.project.structures[0].building.landmark_kind = fixture_v0003.History_Type_0016(9)
        historical.marina_authored_plan.shoreline_form = fixture_v0003.History_Type_0045(5)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_LANDMARK_ID)
        historical.project.structures[0].building.landmark_kind = .None
        historical.marina_authored_plan.shoreline_form = .Straight_Quay
        historical.marina_authored_plan.shoreline_form = fixture_v0003.History_Type_0045(5)
        historical.story_state.delivery.from = fixture_v0003.History_Type_0076(6)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_SHORELINE_ID,
        )
        historical.marina_authored_plan.shoreline_form = .Straight_Quay
        historical.story_state.delivery.from = .Marta
        historical.story_state.delivery.from = fixture_v0003.History_Type_0076(6)
        historical.aircraft.slots[0].kind = fixture_v0003.History_Type_0097(3)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_RESIDENT_ID)
        historical.story_state.delivery.from = .Marta
        historical.aircraft.slots[0].kind = .Postale
        historical.aircraft.slots[0].kind = fixture_v0003.History_Type_0097(3)
        historical.occupant = fixture_v0003.History_Type_0103(5)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_AIRCRAFT_ID)
        historical.aircraft.slots[0].kind = .Postale
        historical.occupant = .On_Foot
        historical.occupant = fixture_v0003.History_Type_0103(5)
        historical.authoring_tool = fixture_v0003.History_Type_0106(13)
        fixture_migration_v0003_enum_test_expect_failure(t, historical, tentative, FIXTURE_MIGRATION_V0003_OCCUPANT_ID)
        historical.occupant = .On_Foot
        historical.authoring_tool = .Sculpt
        historical.authoring_tool = fixture_v0003.History_Type_0106(13)
        historical.mouse_headgear = fixture_v0003.History_Type_0113(11)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_AUTHORING_ID,
        )
        historical.authoring_tool = .Sculpt
        historical.mouse_headgear = .None
        historical.mouse_headgear = fixture_v0003.History_Type_0113(11)
        historical.settlement_plan.acceptance_failure = fixture_v0003.History_Type_0123(17)
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_MOUSE_ACCESSORY_ID,
        )
        historical.mouse_headgear = .None
        historical.settlement_plan.acceptance_failure = .None

        project_raw := cast(^runtime.Raw_Dynamic_Array)&tentative.project.structures
        project_length := project_raw.len
        project_raw.len = project_length - 1
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        project_raw.len = project_length
        city_raw := cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.structures
        city_length := city_raw.len
        city_raw.len = city_length - 1
        fixture_migration_v0003_enum_test_expect_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        city_raw.len = city_length

        nil_error := fixture_migration_v0003_enum_test_call(t, historical, nil)
        testing.expect(t, nil_error.kind == .Invalid_Argument && nil_error.change_id == "")
    }
}
