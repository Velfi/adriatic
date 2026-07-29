package main

import architecture "../packages/architecture"
import fixture_file "../packages/fixture_file"
import fixture_v0001 "../packages/fixture_history/v0001"
import hs "../packages/hs"
import quest "../packages/quest"
import story "../packages/story"
import "base:runtime"
import "core:mem"
import "core:testing"

when ODIN_TEST {
    Fixture_Migration_Story_Test_Case :: struct {
        romance:            int,
        repair:             int,
        active:             bool,
        kind:               int,
        repeat_deliveries:  int,
        metadata_mode:      int,
        completed_override: int,
        stamps_override:    int,
        wing_override:      int,
        completed_negative: bool,
        stamps_negative:    bool,
    }

    fixture_migration_story_test_apply_story :: proc(
        historical: ^fixture_v0001.Fixture,
        test_case: Fixture_Migration_Story_Test_Case,
    ) {
        historical.story_state.romance = fixture_v0001.History_Type_0072(test_case.romance)
        historical.story_state.repair = fixture_v0001.History_Type_0070(test_case.repair)
        historical.story_state.repeat_deliveries = test_case.repeat_deliveries
        main_delivery_table := [6]int{0, 1, 2, 3, 4, 4}
        completed := 0
        if test_case.repeat_deliveries <= max(int) - main_delivery_table[test_case.romance] {
            completed = main_delivery_table[test_case.romance] + test_case.repeat_deliveries
        }
        if test_case.completed_override >= 0 do completed = test_case.completed_override
        if test_case.completed_negative do completed = -1
        historical.story_state.completed_deliveries = completed
        historical.story_state.stamps_earned = completed
        if test_case.stamps_override >= 0 do historical.story_state.stamps_earned = test_case.stamps_override
        if test_case.stamps_negative do historical.story_state.stamps_earned = -1
        wing_patch_table := [5]bool{false, false, true, false, false}
        historical.story_state.has_wing_patch = wing_patch_table[test_case.repair]
        if test_case.wing_override >= 0 do historical.story_state.has_wing_patch = test_case.wing_override != 0

        historical.story_state.delivery.active = test_case.active
        historical.story_state.delivery.kind = fixture_v0001.History_Type_0068(test_case.kind)
        switch test_case.kind {
        case 1, 3, 5:
            historical.story_state.delivery.from = fixture_v0001.History_Type_0071(2)
            historical.story_state.delivery.to = fixture_v0001.History_Type_0071(3)
            historical.story_state.delivery.origin = fixture_v0001.History_Type_0069(0)
            historical.story_state.delivery.destination = fixture_v0001.History_Type_0069(1)
        case 2, 4, 6:
            historical.story_state.delivery.from = fixture_v0001.History_Type_0071(3)
            historical.story_state.delivery.to = fixture_v0001.History_Type_0071(2)
            historical.story_state.delivery.origin = fixture_v0001.History_Type_0069(1)
            historical.story_state.delivery.destination = fixture_v0001.History_Type_0069(0)
        }
        switch test_case.kind {
        case 1:
            historical.story_state.delivery.subject = "A recipe for a clear morning"
        case 2:
            historical.story_state.delivery.subject = "The lighthouse keeper's reply"
        case 3:
            historical.story_state.delivery.subject = "An invitation for the regatta"
        case 4:
            historical.story_state.delivery.subject = "Meet me beneath the blue awning"
        case 5:
            historical.story_state.delivery.subject = "Bread, postcards, and one pressed flower"
        case 6:
            historical.story_state.delivery.subject = "Lamp glass and a note for supper"
        }
        switch test_case.metadata_mode {
        case 1:
            historical.story_state.delivery.subject = "wrong subject"
        case 2:
            historical.story_state.delivery.from = fixture_v0001.History_Type_0071(0)
        case 3:
            historical.story_state.delivery.to = fixture_v0001.History_Type_0071(0)
        case 4:
            historical.story_state.delivery.origin = fixture_v0001.History_Type_0069(0)
        case 5:
            historical.story_state.delivery.destination = fixture_v0001.History_Type_0069(1)
        }
    }

    fixture_migration_story_test_baseline_case :: proc(
        test_case: Fixture_Migration_Story_Test_Case,
    ) -> Fixture_Migration_Story_Test_Case {
        baseline := test_case
        baseline.metadata_mode = 0
        baseline.completed_override = -1
        baseline.stamps_override = -1
        baseline.wing_override = -1
        baseline.completed_negative = false
        baseline.stamps_negative = false

        if test_case.repeat_deliveries < 0 || test_case.repeat_deliveries == max(int) || test_case.romance < 5 {
            baseline.repeat_deliveries = 0
        }
        if baseline.active {
            switch baseline.kind {
            case 0:
                baseline.active = false
            case 1:
                baseline.romance = 0
                baseline.repair = 0
                baseline.repeat_deliveries = 0
            case 2:
                baseline.romance = 1
                baseline.repair = 0
                baseline.repeat_deliveries = 0
            case 3:
                baseline.romance = 2
                baseline.repair = 0
                baseline.repeat_deliveries = 0
            case 4:
                baseline.romance = 3
                baseline.repair = 4
                baseline.repeat_deliveries = 0
            case 5:
                baseline.romance = 5
                baseline.repair = 4
                baseline.repeat_deliveries = 0
            case 6:
                baseline.romance = 5
                baseline.repair = 4
                baseline.repeat_deliveries = 1
            }
        }
        if test_case.active && test_case.kind == 5 && test_case.repeat_deliveries == 1 {
            baseline.kind = 6
            baseline.repeat_deliveries = 1
        }
        if test_case.active && test_case.kind == 6 && test_case.repeat_deliveries == 0 {
            baseline.kind = 5
            baseline.repeat_deliveries = 0
        }
        return baseline
    }

    fixture_migration_story_test_container :: proc(test_case: Fixture_Migration_Story_Test_Case) -> ([]byte, bool) {
        historical := new(fixture_v0001.Fixture)
        historical.project.structure_count = 1
        historical.project.structures[0].id = 0x101
        historical.architecture_city_plan.count = 1
        historical.architecture_city_plan.structures[0].id = 0x201
        historical.architecture_city_plan.parcel_count = 1
        historical.architecture_city_plan.parcels[0].seed = 0x301
        historical.architecture_city_plan.alley_count = 1
        historical.architecture_city_plan.alleys[0].end_x = 401
        historical.architecture_city_plan.lamp_count = 1
        historical.architecture_city_plan.lamps[0].x = 501
        historical.architecture_brush_radius = 44
        historical.aircraft.slots[0].kind = .Postale
        historical.aircraft.slots[1].kind = .Libellula
        historical.aircraft.slots[2].kind = .Libellula_Mk2
        historical.aircraft.active = .Postale
        historical.aircraft.count = 3

        fixture_migration_story_test_apply_story(historical, test_case)

        payload, portable_error, payload_ok := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0001.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        free(historical)
        hs.portable_error_dispose(&portable_error)
        if !payload_ok do return nil, false
        defer delete(payload)
        container, container_error, container_ok := fixture_file.fixture_container_encode(
            payload,
            1,
            alloc = context.allocator,
        )
        _ = container_error
        return container, container_ok
    }

    fixture_migration_story_test_decode :: proc(container: []byte) -> (fixture_file.Fixture_Container_View, bool) {
        view, error, ok := fixture_file.fixture_container_decode(container)
        _ = error
        return view, ok && view.schema_version == 1
    }

    fixture_migration_story_test_activate :: proc(state: ^quest.State, index: int, status: quest.Status) {
        state.statuses[index] = status
        state.revision += 1
        state.activated_at[index] = state.revision
    }

    fixture_migration_story_test_accept :: proc(state: ^quest.State, index: int) {
        state.statuses[index] = .Active
        state.revision += 1
    }

    fixture_migration_story_test_complete :: proc(state: ^quest.State, index: int) {
        state.statuses[index] = .Completed
        state.completion_counts[index] += 1
        state.revision += 1
        state.completed_at[index] = state.revision
    }

    fixture_migration_story_test_expected_quest :: proc(test_case: Fixture_Migration_Story_Test_Case) -> quest.State {
        expected: quest.State
        expected.definition_id = "two-island-story"
        expected.node_count = 13
        started := test_case.romance != 0 || test_case.repair != 0 || test_case.active
        if !started {
            expected.statuses[11] = .Available
            expected.revision = 1
            expected.activated_at[11] = 1
            return expected
        }

        fixture_migration_story_test_activate(&expected, 11, .Available)
        fixture_migration_story_test_accept(&expected, 11)
        fixture_migration_story_test_complete(&expected, 11)
        fixture_migration_story_test_activate(&expected, 0, .Available)
        fixture_migration_story_test_activate(&expected, 3, .Available)
        fixture_migration_story_test_activate(&expected, 12, .Active)
        fixture_migration_story_test_complete(&expected, 12)

        if test_case.repair >= 1 {
            fixture_migration_story_test_accept(&expected, 3)
            fixture_migration_story_test_complete(&expected, 3)
            fixture_migration_story_test_activate(&expected, 4, .Active)
        }
        if test_case.repair >= 2 {
            fixture_migration_story_test_complete(&expected, 4)
            fixture_migration_story_test_activate(&expected, 5, .Active)
        }
        if test_case.repair >= 3 {
            fixture_migration_story_test_complete(&expected, 5)
            fixture_migration_story_test_activate(&expected, 6, .Active)
        }
        if test_case.repair >= 4 {
            fixture_migration_story_test_complete(&expected, 6)
        }

        if test_case.romance == 0 {
            if test_case.active do fixture_migration_story_test_accept(&expected, 0)
        } else {
            fixture_migration_story_test_accept(&expected, 0)
            fixture_migration_story_test_complete(&expected, 0)
            fixture_migration_story_test_activate(&expected, 1, .Active)
        }
        if test_case.romance >= 2 {
            fixture_migration_story_test_complete(&expected, 1)
            fixture_migration_story_test_activate(&expected, 2, .Active)
        }
        if test_case.romance >= 3 {
            fixture_migration_story_test_complete(&expected, 2)
            if test_case.repair == 4 {
                fixture_migration_story_test_activate(&expected, 7, .Active)
                fixture_migration_story_test_complete(&expected, 7)
                fixture_migration_story_test_activate(&expected, 8, .Active)
            }
        }
        if test_case.romance >= 4 {
            fixture_migration_story_test_complete(&expected, 8)
            fixture_migration_story_test_activate(&expected, 9, .Active)
        }
        if test_case.romance >= 5 {
            fixture_migration_story_test_complete(&expected, 9)
            fixture_migration_story_test_activate(&expected, 10, .Active)
            expected.completion_counts[10] = test_case.repeat_deliveries
            if test_case.repeat_deliveries > 0 {
                expected.revision += u64(test_case.repeat_deliveries)
                expected.completed_at[10] = expected.revision
            }
        }
        return expected
    }

    fixture_migration_story_test_expect_checkpoint :: proc(
        t: ^testing.T,
        migrated: ^story.State,
        test_case: Fixture_Migration_Story_Test_Case,
    ) {
        expected_revision: u64 = 0
        if test_case.romance == 0 && test_case.repair == 0 && test_case.active && test_case.kind == 1 {
            expected_revision = 8
        } else if test_case.romance == 0 && test_case.repair == 4 && !test_case.active {
            expected_revision = 15
        } else if test_case.romance == 3 && test_case.repair == 0 && !test_case.active {
            expected_revision = 13
        } else if test_case.romance == 3 && test_case.repair == 4 && !test_case.active {
            expected_revision = 24
        } else if test_case.romance == 4 && test_case.repair == 4 && !test_case.active {
            expected_revision = 26
        } else if test_case.romance == 5 && test_case.repair == 4 {
            if test_case.repeat_deliveries == 0 {
                expected_revision = 28
                testing.expect(t, migrated.quest.statuses[10] == .Active)
                testing.expect(t, migrated.quest.completion_counts[10] == 0)
                testing.expect(t, migrated.quest.completed_at[10] == 0)
            } else if test_case.repeat_deliveries == 1 {
                expected_revision = 29
                testing.expect(t, migrated.quest.statuses[10] == .Active)
                testing.expect(t, migrated.quest.completion_counts[10] == 1)
                testing.expect(t, migrated.quest.completed_at[10] == 29)
            }
        }
        if expected_revision != 0 do testing.expect(t, migrated.quest.revision == expected_revision)
    }

    fixture_migration_story_test_expect_success :: proc(
        t: ^testing.T,
        result: Fixture_Migration_Result,
        test_case: Fixture_Migration_Story_Test_Case,
    ) {
        testing.expect(t, result.fixture != nil)
        if result.fixture == nil do return
        migrated := &result.fixture.story_state
        expected := fixture_migration_story_test_expected_quest(test_case)
        testing.expect(t, migrated.quest.definition_id == expected.definition_id)
        testing.expect(t, migrated.quest.node_count == expected.node_count)
        testing.expect(t, migrated.quest.revision == expected.revision)
        for index in 0 ..< len(migrated.quest.statuses) {
            testing.expect(t, migrated.quest.statuses[index] == expected.statuses[index])
            testing.expect(t, migrated.quest.completion_counts[index] == expected.completion_counts[index])
            testing.expect(t, migrated.quest.activated_at[index] == expected.activated_at[index])
            testing.expect(t, migrated.quest.completed_at[index] == expected.completed_at[index])
        }
        if test_case.romance >= 1 do testing.expect(t, migrated.quest.completion_counts[0] == 1)
        if test_case.romance >= 2 do testing.expect(t, migrated.quest.completion_counts[1] == 1)
        if test_case.romance >= 3 do testing.expect(t, migrated.quest.completion_counts[2] == 1)
        if test_case.romance >= 4 do testing.expect(t, migrated.quest.completion_counts[8] == 1)
        if test_case.romance >= 5 {
            testing.expect(t, migrated.quest.completion_counts[9] == 1)
            testing.expect(t, migrated.quest.completion_counts[10] == test_case.repeat_deliveries)
            testing.expect(t, migrated.quest.statuses[10] == .Active)
        }
        if test_case.repair >= 1 do testing.expect(t, migrated.quest.completion_counts[3] == 1)
        if test_case.repair >= 2 do testing.expect(t, migrated.quest.completion_counts[4] == 1)
        if test_case.repair >= 3 do testing.expect(t, migrated.quest.completion_counts[5] == 1)
        if test_case.repair >= 4 do testing.expect(t, migrated.quest.completion_counts[6] == 1)
        if test_case.romance >= 4 || test_case.repair >= 4 {
            testing.expect(t, migrated.quest.statuses[7] == .Completed || test_case.romance < 3)
        }
        started := test_case.romance != 0 || test_case.repair != 0 || test_case.active
        expected_airfield := story.Airfield_Errand_Stage.Not_Offered
        if started do expected_airfield = .Completed
        testing.expect(t, migrated.airfield_errand == expected_airfield)
        if test_case.completed_override >= 0 {
            testing.expect(t, migrated.completed_deliveries == test_case.completed_override)
        }
        testing.expect(t, migrated.repeat_deliveries == test_case.repeat_deliveries)
        expected_stamps := migrated.completed_deliveries
        if started do expected_stamps += 1
        testing.expect(t, migrated.stamps_earned == expected_stamps)
        testing.expect(t, result.fixture.tracked_quest_node == quest.Node_ID(-1))
        testing.expect(t, !result.fixture.quest_tracking_suppressed)
        testing.expect(t, result.fixture.quest_tracking_revision == migrated.quest.revision)
        testing.expect(t, result.fixture.occupant == .On_Foot)
        fixture_migration_story_test_expect_checkpoint(t, migrated, test_case)
        catalog: story.Quest_Catalog
        story.init_quest_catalog(&catalog)
        projected := migrated^
        testing.expect(t, story.apply_quest_projection(&projected, &projected.quest, &catalog))
        testing.expect(t, int(projected.romance) == test_case.romance)
        testing.expect(t, int(projected.repair) == test_case.repair)
        testing.expect(t, projected.repeat_deliveries == test_case.repeat_deliveries)
    }

    fixture_migration_story_test_expect_direct_failure :: proc(
        t: ^testing.T,
        test_case: Fixture_Migration_Story_Test_Case,
    ) {
        baseline_case := fixture_migration_story_test_baseline_case(test_case)
        baseline_historical, baseline_tentative := fixture_migration_structural_manual()
        fixture_migration_story_test_apply_story(baseline_historical, baseline_case)
        baseline_error := fixture_migrate_v0001_to_v0002(baseline_historical^, baseline_tentative, context.allocator)
        testing.expect(t, baseline_error.kind == .None)
        fixture_migration_error_dispose(&baseline_error)
        fixture_migration_structural_manual_destroy(baseline_historical, baseline_tentative)

        historical, tentative := fixture_migration_structural_manual()
        fixture_migration_story_test_apply_story(historical, test_case)
        snapshot, snapshot_ok := fixture_migration_structural_snapshot(tentative, context.allocator)
        testing.expect(t, snapshot_ok)
        if snapshot_ok {
            error := fixture_migrate_v0001_to_v0002(historical^, tentative, context.allocator)
            testing.expect(t, error.kind == .Invalid_Source)
            testing.expect(t, error.change_id == FIXTURE_MIGRATION_V0001_STORY_QUEST_ID)
            testing.expect(t, fixture_migration_structural_snapshot_matches(snapshot, tentative))
            fixture_migration_error_dispose(&error)
            fixture_migration_structural_snapshot_dispose(&snapshot)
        }
        fixture_migration_structural_manual_destroy(historical, tentative)
    }

    fixture_migration_story_test_expect_production_failure :: proc(t: ^testing.T, container: []byte) {
        view, view_ok := fixture_migration_story_test_decode(container)
        testing.expect(t, view_ok)
        if !view_ok do return
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        result, error, ok := fixture_migration_run(
            view.payload,
            1,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_test_allocator(&state),
        )
        testing.expect(t, !ok && error.kind == .Step_Failure)
        testing.expect(t, error.change_id == FIXTURE_MIGRATION_V0001_STORY_QUEST_ID)
        testing.expect(t, fixture_migration_result_empty(&result))
        fixture_migration_error_dispose(&error)
        fixture_migration_error_dispose(&error)
        fixture_migration_result_dispose(&result)
        fixture_migration_result_dispose(&result)
        testing.expect(t, state.outstanding == 0)
    }

    @(test)
    fixture_migration_story_golden_matrix_and_failures :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        for romance in 0 ..< 6 {
            for repair in 0 ..< 5 {
                if romance >= 4 && repair != 4 do continue
                test_case := Fixture_Migration_Story_Test_Case {
                    romance            = romance,
                    repair             = repair,
                    completed_override = -1,
                    stamps_override    = -1,
                    wing_override      = -1,
                }
                container, container_ok := fixture_migration_story_test_container(test_case)
                testing.expect(t, container_ok)
                if !container_ok do continue
                view, view_ok := fixture_migration_story_test_decode(container)
                testing.expect(t, view_ok)
                if view_ok {
                    result, error, ok := fixture_migration_run(
                        view.payload,
                        1,
                        FIXTURE_SCHEMA_VERSION,
                        runtime.default_allocator(),
                    )
                    testing.expect(t, ok && error.kind == .None)
                    if ok {
                        fixture_migration_story_test_expect_success(t, result, test_case)
                    }
                    fixture_migration_error_dispose(&error)
                    fixture_migration_result_dispose(&result)
                }
                delete(container)
            }
        }

        active_cases := [6]Fixture_Migration_Story_Test_Case {
            {
                romance = 0,
                repair = 0,
                active = true,
                kind = 1,
                completed_override = -1,
                stamps_override = -1,
                wing_override = -1,
            },
            {
                romance = 1,
                repair = 0,
                active = true,
                kind = 2,
                completed_override = -1,
                stamps_override = -1,
                wing_override = -1,
            },
            {
                romance = 2,
                repair = 0,
                active = true,
                kind = 3,
                completed_override = -1,
                stamps_override = -1,
                wing_override = -1,
            },
            {
                romance = 3,
                repair = 4,
                active = true,
                kind = 4,
                completed_override = -1,
                stamps_override = -1,
                wing_override = -1,
            },
            {
                romance = 5,
                repair = 4,
                active = true,
                kind = 5,
                repeat_deliveries = 0,
                completed_override = -1,
                stamps_override = -1,
                wing_override = -1,
            },
            {
                romance = 5,
                repair = 4,
                active = true,
                kind = 6,
                repeat_deliveries = 1,
                completed_override = -1,
                stamps_override = -1,
                wing_override = -1,
            },
        }
        for test_case in active_cases {
            container, container_ok := fixture_migration_story_test_container(test_case)
            testing.expect(t, container_ok)
            if !container_ok do continue
            view, view_ok := fixture_migration_story_test_decode(container)
            testing.expect(t, view_ok)
            if view_ok {
                result, error, ok := fixture_migration_run(
                    view.payload,
                    1,
                    FIXTURE_SCHEMA_VERSION,
                    runtime.default_allocator(),
                )
                testing.expect(t, ok && error.kind == .None)
                if ok {
                    fixture_migration_story_test_expect_success(t, result, test_case)
                    testing.expect(t, result.fixture.story_state.delivery.active)
                    testing.expect(t, int(result.fixture.story_state.delivery.kind) == test_case.kind)
                    testing.expect(t, result.fixture.story_state.delivery.subject != "")
                    if test_case.kind == 1 || test_case.kind == 3 || test_case.kind == 5 {
                        testing.expect(t, int(result.fixture.story_state.delivery.from) == 2)
                        testing.expect(t, int(result.fixture.story_state.delivery.to) == 3)
                        testing.expect(t, int(result.fixture.story_state.delivery.origin) == 0)
                        testing.expect(t, int(result.fixture.story_state.delivery.destination) == 1)
                    } else {
                        testing.expect(t, int(result.fixture.story_state.delivery.from) == 3)
                        testing.expect(t, int(result.fixture.story_state.delivery.to) == 2)
                        testing.expect(t, int(result.fixture.story_state.delivery.origin) == 1)
                        testing.expect(t, int(result.fixture.story_state.delivery.destination) == 0)
                    }
                    switch test_case.kind {
                    case 1:
                        testing.expect(
                            t,
                            result.fixture.story_state.delivery.subject == "A recipe for a clear morning",
                        )
                    case 2:
                        testing.expect(
                            t,
                            result.fixture.story_state.delivery.subject == "The lighthouse keeper's reply",
                        )
                    case 3:
                        testing.expect(
                            t,
                            result.fixture.story_state.delivery.subject == "An invitation for the regatta",
                        )
                    case 4:
                        testing.expect(
                            t,
                            result.fixture.story_state.delivery.subject == "Meet me beneath the blue awning",
                        )
                    case 5:
                        testing.expect(
                            t,
                            result.fixture.story_state.delivery.subject == "Bread, postcards, and one pressed flower",
                        )
                    case 6:
                        testing.expect(
                            t,
                            result.fixture.story_state.delivery.subject == "Lamp glass and a note for supper",
                        )
                    }
                }
                fixture_migration_error_dispose(&error)
                fixture_migration_result_dispose(&result)
            }
            delete(container)
        }

        stale_case := Fixture_Migration_Story_Test_Case {
            romance            = 1,
            repair             = 0,
            kind               = 6,
            repeat_deliveries  = 0,
            completed_override = -1,
            stamps_override    = -1,
            wing_override      = -1,
        }
        stale_container, stale_ok := fixture_migration_story_test_container(stale_case)
        testing.expect(t, stale_ok)
        if stale_ok {
            stale_view, stale_view_ok := fixture_migration_story_test_decode(stale_container)
            testing.expect(t, stale_view_ok)
            if stale_view_ok {
                stale_result, stale_error, stale_run_ok := fixture_migration_run(
                    stale_view.payload,
                    1,
                    FIXTURE_SCHEMA_VERSION,
                    runtime.default_allocator(),
                )
                testing.expect(t, stale_run_ok && stale_error.kind == .None)
                if stale_run_ok {
                    testing.expect(t, !stale_result.fixture.story_state.delivery.active)
                    testing.expect(t, int(stale_result.fixture.story_state.delivery.kind) == 6)
                    testing.expect(
                        t,
                        stale_result.fixture.story_state.delivery.subject == "Lamp glass and a note for supper",
                    )
                }
                fixture_migration_error_dispose(&stale_error)
                fixture_migration_result_dispose(&stale_result)
            }
            delete(stale_container)
        }

        invalid_cases := [29]Fixture_Migration_Story_Test_Case {
            {romance = 0, repair = 0, stamps_override = 0, wing_override = 0, completed_negative = true},
            {romance = 0, repair = 0, completed_override = 1, stamps_override = 1, wing_override = 0},
            {
                romance = 5,
                repair = 4,
                repeat_deliveries = max(int),
                completed_override = 0,
                stamps_override = 0,
                wing_override = 0,
            },
            {romance = 0, repair = 0, wing_override = 1, completed_override = 0, stamps_override = 0},
            {
                romance = 5,
                repair = 3,
                active = true,
                kind = 5,
                completed_override = 4,
                stamps_override = 4,
                wing_override = 0,
            },
            {
                romance = 5,
                repair = 3,
                active = true,
                kind = 6,
                repeat_deliveries = 1,
                completed_override = 5,
                stamps_override = 5,
                wing_override = 0,
            },
            {
                romance = 0,
                repair = 0,
                repeat_deliveries = -1,
                completed_override = 0,
                stamps_override = 0,
                wing_override = 0,
            },
            {
                romance = 0,
                repair = 0,
                active = true,
                kind = 0,
                completed_override = 0,
                stamps_override = 0,
                wing_override = 0,
            },
            {
                romance = 1,
                repair = 0,
                active = true,
                kind = 1,
                completed_override = 1,
                stamps_override = 1,
                wing_override = 0,
            },
            {
                romance = 0,
                repair = 0,
                active = true,
                kind = 2,
                completed_override = 0,
                stamps_override = 0,
                wing_override = 0,
            },
            {
                romance = 1,
                repair = 0,
                active = true,
                kind = 3,
                completed_override = 1,
                stamps_override = 1,
                wing_override = 0,
            },
            {
                romance = 3,
                repair = 0,
                active = true,
                kind = 4,
                completed_override = 3,
                stamps_override = 3,
                wing_override = 0,
            },
            {
                romance = 3,
                repair = 3,
                active = true,
                kind = 4,
                completed_override = 3,
                stamps_override = 3,
                wing_override = 0,
            },
            {
                romance = 4,
                repair = 4,
                active = true,
                kind = 5,
                completed_override = 4,
                stamps_override = 4,
                wing_override = 0,
            },
            {
                romance = 4,
                repair = 4,
                active = true,
                kind = 6,
                repeat_deliveries = 1,
                completed_override = 5,
                stamps_override = 5,
                wing_override = 0,
            },
            {
                romance = 5,
                repair = 4,
                active = true,
                kind = 5,
                repeat_deliveries = 1,
                completed_override = 5,
                stamps_override = 5,
                wing_override = 0,
            },
            {
                romance = 5,
                repair = 4,
                active = true,
                kind = 6,
                repeat_deliveries = 0,
                completed_override = 4,
                stamps_override = 4,
                wing_override = 0,
            },
            {
                romance = 4,
                repair = 4,
                repeat_deliveries = 1,
                completed_override = 5,
                stamps_override = 5,
                wing_override = 0,
            },
            {
                romance = 1,
                repair = 0,
                active = true,
                kind = 2,
                metadata_mode = 1,
                completed_override = 1,
                stamps_override = 1,
                wing_override = 0,
            },
            {
                romance = 1,
                repair = 0,
                active = true,
                kind = 2,
                metadata_mode = 2,
                completed_override = 1,
                stamps_override = 1,
                wing_override = 0,
            },
            {
                romance = 1,
                repair = 0,
                active = true,
                kind = 2,
                metadata_mode = 3,
                completed_override = 1,
                stamps_override = 1,
                wing_override = 0,
            },
            {
                romance = 1,
                repair = 0,
                active = true,
                kind = 2,
                metadata_mode = 4,
                completed_override = 1,
                stamps_override = 1,
                wing_override = 0,
            },
            {
                romance = 1,
                repair = 0,
                active = true,
                kind = 2,
                metadata_mode = 5,
                completed_override = 1,
                stamps_override = 1,
                wing_override = 0,
            },
            {romance = 1, repair = 0, completed_override = 1, stamps_override = 2, wing_override = 0},
            {romance = 0, repair = 0, stamps_negative = true, completed_override = 0, wing_override = 0},
            {romance = 1, repair = 1, completed_override = 1, stamps_override = 1, wing_override = 1},
            {romance = 1, repair = 2, completed_override = 1, stamps_override = 1, wing_override = 0},
            {romance = 1, repair = 3, completed_override = 1, stamps_override = 1, wing_override = 1},
            {romance = 1, repair = 4, completed_override = 1, stamps_override = 1, wing_override = 1},
        }
        for test_case in invalid_cases {
            fixture_migration_story_test_expect_direct_failure(t, test_case)
            container, container_ok := fixture_migration_story_test_container(test_case)
            testing.expect(t, container_ok)
            if container_ok {
                fixture_migration_story_test_expect_production_failure(t, container)
                delete(container)
            }
        }

        deterministic_case := Fixture_Migration_Story_Test_Case {
            romance            = 5,
            repair             = 4,
            active             = true,
            kind               = 6,
            repeat_deliveries  = 1,
            completed_override = -1,
            stamps_override    = -1,
            wing_override      = -1,
        }
        first_container, first_container_ok := fixture_migration_story_test_container(deterministic_case)
        second_container, second_container_ok := fixture_migration_story_test_container(deterministic_case)
        testing.expect(t, first_container_ok && second_container_ok)
        if first_container_ok && second_container_ok {
            first_view, first_view_ok := fixture_migration_story_test_decode(first_container)
            second_view, second_view_ok := fixture_migration_story_test_decode(second_container)
            testing.expect(t, first_view_ok && second_view_ok)
            if first_view_ok && second_view_ok {
                first_result, first_error, first_ok := fixture_migration_run(
                    first_view.payload,
                    1,
                    FIXTURE_SCHEMA_VERSION,
                    runtime.default_allocator(),
                )
                second_result, second_error, second_ok := fixture_migration_run(
                    second_view.payload,
                    1,
                    FIXTURE_SCHEMA_VERSION,
                    runtime.default_allocator(),
                )
                testing.expect(t, first_ok && second_ok && first_error.kind == .None && second_error.kind == .None)
                if first_ok && second_ok {
                    first_serialized, first_codec_error, first_serialized_ok := fixture_codec_encode(
                        first_result.fixture,
                        context.allocator,
                    )
                    second_serialized, second_codec_error, second_serialized_ok := fixture_codec_encode(
                        second_result.fixture,
                        context.allocator,
                    )
                    testing.expect(t, first_serialized_ok && second_serialized_ok)
                    testing.expect(t, fixture_migration_test_bytes_equal(first_serialized, second_serialized))
                    delete(first_serialized)
                    delete(second_serialized)
                    fixture_codec_error_dispose(&first_codec_error)
                    fixture_codec_error_dispose(&second_codec_error)

                    first_lamps := cast(^runtime.Raw_Dynamic_Array)(&first_result.fixture.architecture_city_plan.lamps)
                    second_lamps := cast(^runtime.Raw_Dynamic_Array)(&second_result.fixture.architecture_city_plan.lamps)
                    testing.expect(t, first_lamps.allocator.data == rawptr(first_result.arena))
                    testing.expect(t, second_lamps.allocator.data == rawptr(second_result.arena))
                    first_previous_length := len(first_result.fixture.architecture_city_plan.lamps)
                    second_previous_length := len(second_result.fixture.architecture_city_plan.lamps)
                    append(&first_result.fixture.architecture_city_plan.lamps, architecture.City_Lamp{x = 9001})
                    append(&second_result.fixture.architecture_city_plan.lamps, architecture.City_Lamp{x = 9001})
                    testing.expect(
                        t,
                        len(first_result.fixture.architecture_city_plan.lamps) == first_previous_length + 1,
                    )
                    testing.expect(
                        t,
                        len(second_result.fixture.architecture_city_plan.lamps) == second_previous_length + 1,
                    )
                    testing.expect(
                        t,
                        first_result.fixture.architecture_city_plan.lamps[len(first_result.fixture.architecture_city_plan.lamps) - 1].x ==
                        9001,
                    )
                    testing.expect(
                        t,
                        second_result.fixture.architecture_city_plan.lamps[len(second_result.fixture.architecture_city_plan.lamps) - 1].x ==
                        9001,
                    )
                }
                fixture_migration_error_dispose(&first_error)
                fixture_migration_error_dispose(&second_error)
                fixture_migration_result_dispose(&first_result)
                fixture_migration_result_dispose(&second_result)
            }
            delete(first_container)
            delete(second_container)
        }

        combined_container, combined_ok := fixture_migration_story_test_container(deterministic_case)
        testing.expect(t, combined_ok)
        if combined_ok {
            combined_view, combined_view_ok := fixture_migration_story_test_decode(combined_container)
            testing.expect(t, combined_view_ok)
            if combined_view_ok {
                state := fixture_migration_test_allocator_state {
                    base    = runtime.default_allocator(),
                    fail_at = -1,
                }
                historical, tentative, arena, prepared := fixture_migration_structural_prepare(
                    combined_view.payload,
                    fixture_migration_test_allocator(&state),
                )
                testing.expect(t, prepared)
                if prepared {
                    allocations_before_step := state.allocation_calls
                    error := fixture_migrate_v0001_to_v0002(historical^, tentative, mem.dynamic_arena_allocator(arena))
                    testing.expect(t, error.kind == .None)
                    testing.expect(t, state.allocation_calls == allocations_before_step)
                    fixture_migration_error_dispose(&error)
                    fixture_migration_arena_dispose(arena, fixture_migration_test_allocator(&state))
                }
                testing.expect(t, state.outstanding == 0)
            }
            delete(combined_container)
        }
    }
}
