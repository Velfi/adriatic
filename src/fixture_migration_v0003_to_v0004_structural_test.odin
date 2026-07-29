package main

import architecture "../packages/architecture"
import fixture_v0003 "../packages/fixture_history/v0003"
import story "../packages/story"
import terrain "../packages/terrain"
import "base:runtime"
import "core:math"
import "core:testing"

when ODIN_TEST {
    fixture_migration_v0003_structural_test_make :: proc(
        t: ^testing.T,
    ) -> (
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        ok: bool,
    ) {
        historical, tentative, ok = fixture_migration_v0003_enum_test_make(t)
        if !ok do return
        historical.architecture_city_plan.alleys = make([dynamic]fixture_v0003.History_Type_0000, 3, context.allocator)
        tentative.architecture_city_plan.alleys = make([dynamic]architecture.City_Alley, 3, context.allocator)
        testing.expect(
            t,
            historical.architecture_city_plan.alleys != nil && tentative.architecture_city_plan.alleys != nil,
        )
        if historical.architecture_city_plan.alleys == nil || tentative.architecture_city_plan.alleys == nil {
            delete(historical.architecture_city_plan.alleys)
            delete(tentative.architecture_city_plan.alleys)
            fixture_migration_v0003_enum_test_destroy(historical, tentative)
            return nil, nil, false
        }
        historical.architecture_brush_radius = 64
        historical.postale.airframe.maximum_speed = 101
        historical.postale.airframe.stall_speed = 102
        historical.tweak.postale_airframe.maximum_speed = 103
        historical.tweak.postale_airframe.stall_speed = 104
        historical.postale.flight_runtime.stall_speed_modifier = 105
        historical.tweak.postale_runtime.stall_speed_modifier = 106
        historical.postale.takeoff_armed = true
        historical.postale.tuning.takeoff_stall_speed_scale = 107
        historical.postale.tuning.takeoff_vertical_assist = 108
        historical.tweak.postale_tuning.takeoff_stall_speed_scale = 109
        historical.tweak.postale_tuning.takeoff_vertical_assist = 110
        historical.player_tail.initialized = true
        return historical, tentative, true
    }

    fixture_migration_v0003_structural_test_destroy :: proc(historical: ^fixture_v0003.Fixture, tentative: ^Fixture) {
        if historical != nil do delete(historical.architecture_city_plan.alleys)
        if tentative != nil do delete(tentative.architecture_city_plan.alleys)
        fixture_migration_v0003_enum_test_destroy(historical, tentative)
    }

    fixture_migration_v0003_structural_test_set_sentinels :: proc(tentative: ^Fixture) {
        fixture_migration_v0003_enum_test_set_sentinels(tentative)
        tentative.structure_selected = 909

        for &alley, index in tentative.architecture_city_plan.alleys {
            alley.start_x = f32(10 + index)
            alley.end_z = f32(20 + index)
            alley.curve_control_from = {31, 32}
            alley.curve_control_to = {33, 34}
            alley.curve_ready = true
            alley.start_terminal = .Door
            alley.end_terminal = .Public_Space
            alley.household_demand = 35
        }

        for &structure, index in tentative.project.structures {
            structure.id = u64(100 + index)
            structure.entrance_side = .Rear
        }
        for &structure, index in tentative.architecture_city_plan.structures {
            structure.id = u64(200 + index)
            structure.entrance_side = .Rear
        }
        for &site, index in tentative.settlement_plan.sites {
            site.structure.id = u64(300 + index)
            site.structure.entrance_side = .Rear
        }
        for &site, index in tentative.settlement_plan.rejected_sites {
            site.structure.id = u64(600 + index)
            site.structure.entrance_side = .Rear
        }
        for &structure, index in tentative.settlement_plan.decorative_foliage {
            structure.id = u64(700 + index)
            structure.entrance_side = .Rear
        }

        tentative.postale.airframe.parasitic_drag_area = 201
        tentative.postale.airframe.mass_kg = 202
        tentative.tweak.postale_airframe.parasitic_drag_area = 203
        tentative.tweak.postale_airframe.mass_kg = 204
        tentative.postale.ground_brake_amount = 205
        tentative.postale.ground_pitch_radians = 206
        tentative.postale.landing_intent = true
        tentative.postale.landing_intent_seconds = 207
        tentative.postale.throttle = 208
        tentative.postale.flight_runtime.engine_output = 209
        tentative.tweak.postale_runtime.engine_output = 210
        tentative.postale.tuning.propeller_base_rate = 211
        tentative.tweak.postale_tuning.propeller_base_rate = 212

        tentative.story_state.clinic_visits = 213
        for &seen, index in tentative.story_state.resident_action_seen {
            seen = u64(214 + int(index))
        }
        tentative.story_state.tarot_seed = 225

        tentative.architecture_brush_shape = .Macaroni
        tentative.architecture_brush_preset = .Large
        tentative.architecture_brush_strength = 226
        tentative.player_tail.points[0].position = {227, 228, 229}
        tentative.player_tail.last_root = {230, 231, 232}
        tentative.player_tail.initialized = true
    }

    fixture_migration_v0003_structural_test_call :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
    ) -> Fixture_Migration_Error {
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = 0,
        }
        error := fixture_migration_v0003_structural_slice(
            historical^,
            tentative,
            fixture_migration_test_allocator(&state),
        )
        testing.expect(t, state.allocation_calls == 0 && state.outstanding == 0)
        return error
    }

    fixture_migration_v0003_structural_test_expect_state :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        expected_preset: Settlement_Brush_Preset,
        root_applied := false,
    ) {
        fixture_migration_v0003_enum_test_expect_mapping(t, historical, tentative, root_applied)

        for alley, index in tentative.architecture_city_plan.alleys {
            testing.expect(
                t,
                alley.start_x == f32(10 + index) &&
                alley.end_z == f32(20 + index) &&
                alley.curve_control_from == [2]f32{} &&
                alley.curve_control_to == [2]f32{} &&
                !alley.curve_ready &&
                alley.start_terminal == .None &&
                alley.end_terminal == .None &&
                alley.household_demand == 0,
            )
        }

        testing.expect(
            t,
            tentative.postale.airframe.parasitic_drag_area == f32(1.33) &&
            tentative.postale.airframe.mass_kg == 202 &&
            tentative.tweak.postale_airframe.parasitic_drag_area == f32(1.33) &&
            tentative.tweak.postale_airframe.mass_kg == 204,
        )
        testing.expect(
            t,
            tentative.postale.ground_brake_amount == 0 &&
            tentative.postale.ground_pitch_radians == 0 &&
            !tentative.postale.landing_intent &&
            tentative.postale.landing_intent_seconds == 0 &&
            tentative.postale.throttle == 208,
        )
        testing.expect(
            t,
            tentative.postale.flight_runtime.engine_output == 209 &&
            tentative.tweak.postale_runtime.engine_output == 210 &&
            tentative.postale.tuning.propeller_base_rate == 211 &&
            tentative.tweak.postale_tuning.propeller_base_rate == 212,
        )

        testing.expect(
            t,
            tentative.story_state.clinic_visits == 0 &&
            tentative.story_state.resident_action_seen == [story.Resident]u64{} &&
            tentative.story_state.tarot_seed == 225,
        )
        for structure, index in tentative.project.structures {
            testing.expect(t, structure.id == u64(100 + index) && structure.entrance_side == .Front)
        }
        for structure, index in tentative.architecture_city_plan.structures {
            testing.expect(t, structure.id == u64(200 + index) && structure.entrance_side == .Front)
        }
        for site, index in tentative.settlement_plan.sites {
            testing.expect(t, site.structure.id == u64(300 + index) && site.structure.entrance_side == .Front)
        }
        for site, index in tentative.settlement_plan.rejected_sites {
            testing.expect(t, site.structure.id == u64(600 + index) && site.structure.entrance_side == .Front)
        }
        for structure, index in tentative.settlement_plan.decorative_foliage {
            testing.expect(t, structure.id == u64(700 + index) && structure.entrance_side == .Front)
        }

        testing.expect(
            t,
            tentative.architecture_brush_shape == .Circle &&
            tentative.architecture_brush_preset == expected_preset &&
            tentative.architecture_brush_strength == 226 &&
            tentative.structure_selected == 909 &&
            !tentative.player_tail.initialized &&
            tentative.player_tail.points[0].position == [3]f32{} &&
            tentative.player_tail.last_root == [3]f32{},
        )
    }

    fixture_migration_v0003_structural_test_expect_success :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        expected_preset: Settlement_Brush_Preset,
    ) {
        error := fixture_migration_v0003_structural_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .Unresolved && error.change_id == FIXTURE_MIGRATION_V0003_ROOT_ID)
        fixture_migration_v0003_structural_test_expect_state(t, historical, tentative, expected_preset)
    }

    fixture_migration_v0003_structural_test_expect_atomic_failure :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        expected_id: string,
    ) {
        snapshot, snapshot_ok := fixture_migration_structural_snapshot(tentative, context.allocator)
        testing.expect(t, snapshot_ok)
        if !snapshot_ok do return
        error := fixture_migration_v0003_structural_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .Invalid_Source && error.change_id == expected_id)
        testing.expect(t, fixture_migration_structural_snapshot_matches(snapshot, tentative))
        fixture_migration_structural_snapshot_dispose(&snapshot)
        fixture_migration_structural_snapshot_dispose(&snapshot)
    }

    @(test)
    fixture_migration_v0003_to_v0004_structural_defaults_and_failures :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        historical, tentative, made := fixture_migration_v0003_structural_test_make(t)
        if !made {
            fixture_migration_v0003_structural_test_destroy(historical, tentative)
            return
        }
        defer fixture_migration_v0003_structural_test_destroy(historical, tentative)

        valid_radii := [?]struct {
            radius: f32,
            preset: Settlement_Brush_Preset,
        }{{0, .Small}, {44.999, .Small}, {45, .Medium}, {84.999, .Medium}, {85, .Large}, {3e30, .Large}}
        for value in valid_radii {
            historical.architecture_brush_radius = value.radius
            fixture_migration_v0003_structural_test_set_sentinels(tentative)
            fixture_migration_v0003_structural_test_expect_success(t, historical, tentative, value.preset)
        }

        invalid_radii := [?]f32{math.nan_f32(), math.inf_f32(1), math.inf_f32(-1), -0.001}
        for radius in invalid_radii {
            historical.architecture_brush_radius = radius
            fixture_migration_v0003_structural_test_set_sentinels(tentative)
            fixture_migration_v0003_structural_test_expect_atomic_failure(
                t,
                historical,
                tentative,
                FIXTURE_MIGRATION_V0003_BRUSH_PRESET_ID,
            )
        }
        historical.architecture_brush_radius = 64

        historical.marina_authored_plan.shoreline_form = fixture_v0003.History_Type_0045(5)
        fixture_migration_v0003_structural_test_set_sentinels(tentative)
        fixture_migration_v0003_structural_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_SHORELINE_ID,
        )
        historical.marina_authored_plan.shoreline_form = .Straight_Quay

        project_raw := cast(^runtime.Raw_Dynamic_Array)&tentative.project.structures
        project_length := project_raw.len
        project_raw.len = project_length - 1
        fixture_migration_v0003_structural_test_set_sentinels(tentative)
        fixture_migration_v0003_structural_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        project_raw.len = project_length

        city_raw := cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.structures
        city_length := city_raw.len
        city_raw.len = city_length - 1
        fixture_migration_v0003_structural_test_set_sentinels(tentative)
        fixture_migration_v0003_structural_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_ARCHETYPE_ID,
        )
        city_raw.len = city_length

        alleys_raw := cast(^runtime.Raw_Dynamic_Array)&tentative.architecture_city_plan.alleys
        alley_length := alleys_raw.len
        alleys_raw.len = alley_length - 1
        fixture_migration_v0003_structural_test_set_sentinels(tentative)
        fixture_migration_v0003_structural_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_STRUCTURAL_ID,
        )
        alleys_raw.len = alley_length

        nil_error := fixture_migration_v0003_structural_test_call(t, historical, nil)
        testing.expect(t, nil_error.kind == .Invalid_Argument && nil_error.change_id == "")
    }
}
