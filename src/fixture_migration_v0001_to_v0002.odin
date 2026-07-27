package main

import fixture_v0001 "../packages/fixture_history/v0001"
import quest "../packages/quest"
import story "../packages/story"
import "core:mem"

FIXTURE_MIGRATION_V0001_TO_V0002_FROM_VERSION :: 1
FIXTURE_MIGRATION_V0001_TO_V0002_TO_VERSION :: 2
FIXTURE_MIGRATION_V0001_TO_V0002_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/farmland.Plan.height", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/farmland.Plan.tradition", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/farmland.Plan.width", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.airfield_errand",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:packages/story.State.quest", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Farm_Instance.scale_x", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Farm_Instance.scale_z", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Fixture.quest_tracking_revision",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Fixture.quest_tracking_suppressed",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.tracked_quest_node", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Settlement_Plan.city_plan", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/architecture.City_Plan.alleys",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/architecture.City_Plan.lamps",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/architecture.City_Plan.parcels",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/architecture.City_Plan.structures",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/terrain.Project.structures",
        kind = .Scripted,
    },
}

FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_CAPACITY :: 256
FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_CAPACITY :: 256
FIXTURE_MIGRATION_V0001_CITY_PARCELS_CAPACITY :: 256
FIXTURE_MIGRATION_V0001_CITY_ALLEYS_CAPACITY :: 128
FIXTURE_MIGRATION_V0001_CITY_LAMPS_CAPACITY :: 256
FIXTURE_MIGRATION_V0001_FARMS_CAPACITY :: 16

FIXTURE_MIGRATION_V0001_FARM_DEFAULT_ID :: "field-add:adriatic:packages/farmland.Plan.height"
FIXTURE_MIGRATION_V0001_CITY_REMOVE_ID :: "field-remove:adriatic:src.Settlement_Plan.city_plan"
FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID :: "field-type:adriatic:packages/terrain.Project.structures"
FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_ID :: "field-type:adriatic:packages/architecture.City_Plan.structures"
FIXTURE_MIGRATION_V0001_CITY_PARCELS_ID :: "field-type:adriatic:packages/architecture.City_Plan.parcels"
FIXTURE_MIGRATION_V0001_CITY_ALLEYS_ID :: "field-type:adriatic:packages/architecture.City_Plan.alleys"
FIXTURE_MIGRATION_V0001_CITY_LAMPS_ID :: "field-type:adriatic:packages/architecture.City_Plan.lamps"
FIXTURE_MIGRATION_V0001_STORY_QUEST_ID :: "field-add:adriatic:packages/story.State.quest"

fixture_migration_v0001_invalid_source :: proc(change_id: string) -> Fixture_Migration_Error {
    return {kind = .Invalid_Source, change_id = change_id}
}

fixture_migration_v0001_story_activate :: proc(state: ^quest.State, index: int, status: quest.Status) {
    state.statuses[index] = status
    state.revision += 1
    state.activated_at[index] = state.revision
}

fixture_migration_v0001_story_accept :: proc(state: ^quest.State, index: int) {
    state.statuses[index] = .Active
    state.revision += 1
}

fixture_migration_v0001_story_complete :: proc(state: ^quest.State, index: int) {
    state.statuses[index] = .Completed
    state.completion_counts[index] += 1
    state.revision += 1
    state.completed_at[index] = state.revision
}

fixture_migration_v0001_story_delivery_valid :: proc(
    delivery: fixture_v0001.History_Type_0067,
    romance, repair, repeat_deliveries: int,
) -> bool {
    kind := int(delivery.kind)
    if kind < 0 || kind > 6 do return false
    if int(delivery.from) < 0 || int(delivery.from) > 5 do return false
    if int(delivery.to) < 0 || int(delivery.to) > 5 do return false
    if int(delivery.origin) < 0 || int(delivery.origin) > 1 do return false
    if int(delivery.destination) < 0 || int(delivery.destination) > 1 do return false
    if !delivery.active do return true

    expected_romance := -1
    expected_repair := -1
    expected_from := -1
    expected_to := -1
    expected_origin := -1
    expected_destination := -1
    expected_subject := ""
    switch kind {
    case 1:
        expected_romance = 0
        expected_from = 2
        expected_to = 3
        expected_origin = 0
        expected_destination = 1
        expected_subject = "A recipe for a clear morning"
    case 2:
        expected_romance = 1
        expected_from = 3
        expected_to = 2
        expected_origin = 1
        expected_destination = 0
        expected_subject = "The lighthouse keeper's reply"
    case 3:
        expected_romance = 2
        expected_from = 2
        expected_to = 3
        expected_origin = 0
        expected_destination = 1
        expected_subject = "An invitation for the regatta"
    case 4:
        expected_romance = 3
        expected_repair = 4
        expected_from = 3
        expected_to = 2
        expected_origin = 1
        expected_destination = 0
        expected_subject = "Meet me beneath the blue awning"
    case 5:
        if repeat_deliveries % 2 != 0 do return false
        expected_romance = 5
        expected_from = 2
        expected_to = 3
        expected_origin = 0
        expected_destination = 1
        expected_subject = "Bread, postcards, and one pressed flower"
    case 6:
        if repeat_deliveries % 2 != 1 do return false
        expected_romance = 5
        expected_from = 3
        expected_to = 2
        expected_origin = 1
        expected_destination = 0
        expected_subject = "Lamp glass and a note for supper"
    case 0:
        return false
    }
    return(
        romance == expected_romance &&
        (expected_repair < 0 || repair == expected_repair) &&
        int(delivery.from) == expected_from &&
        int(delivery.to) == expected_to &&
        int(delivery.origin) == expected_origin &&
        int(delivery.destination) == expected_destination &&
        delivery.subject == expected_subject \
    )
}

fixture_migration_v0001_story_build :: proc(
    #by_ptr historical: fixture_v0001.Fixture,
    tentative: ^Fixture,
) -> (
    story.State,
    bool,
) {
    if tentative == nil do return {}, false

    romance := int(historical.story_state.romance)
    repair := int(historical.story_state.repair)
    if romance < 0 || romance > 5 || repair < 0 || repair > 4 do return {}, false
    if historical.story_state.repeat_deliveries < 0 do return {}, false

    main_delivery_table := [6]int{0, 1, 2, 3, 4, 4}
    main_deliveries := main_delivery_table[romance]
    if romance < 5 && historical.story_state.repeat_deliveries != 0 do return {}, false
    if main_deliveries > max(int) - historical.story_state.repeat_deliveries do return {}, false
    expected_completed := main_deliveries + historical.story_state.repeat_deliveries
    if historical.story_state.completed_deliveries != expected_completed do return {}, false
    if historical.story_state.stamps_earned != historical.story_state.completed_deliveries do return {}, false
    if historical.story_state.stamps_earned == max(int) do return {}, false

    wing_patch_table := [5]bool{false, false, true, false, false}
    expected_wing_patch := wing_patch_table[repair]
    if historical.story_state.has_wing_patch != expected_wing_patch do return {}, false
    if romance >= 4 && repair != 4 do return {}, false
    if !fixture_migration_v0001_story_delivery_valid(
        historical.story_state.delivery,
        romance,
        repair,
        historical.story_state.repeat_deliveries,
    ) {
        return {}, false
    }

    started := romance != 0 || repair != 0 || historical.story_state.delivery.active
    migrated := tentative.story_state
    migrated.quest = {}
    migrated.quest.definition_id = "two-island-story"
    migrated.quest.node_count = 13
    if !started {
        migrated.quest.statuses[11] = .Available
        migrated.quest.revision = 1
        migrated.quest.activated_at[11] = 1
    } else {
        fixture_migration_v0001_story_activate(&migrated.quest, 11, .Available)
        fixture_migration_v0001_story_accept(&migrated.quest, 11)
        fixture_migration_v0001_story_complete(&migrated.quest, 11)
        fixture_migration_v0001_story_activate(&migrated.quest, 0, .Available)
        fixture_migration_v0001_story_activate(&migrated.quest, 3, .Available)
        fixture_migration_v0001_story_activate(&migrated.quest, 12, .Active)
        fixture_migration_v0001_story_complete(&migrated.quest, 12)
    }

    if started {
        if repair >= 1 {
            fixture_migration_v0001_story_accept(&migrated.quest, 3)
            fixture_migration_v0001_story_complete(&migrated.quest, 3)
            fixture_migration_v0001_story_activate(&migrated.quest, 4, .Active)
        }
        if repair >= 2 {
            fixture_migration_v0001_story_complete(&migrated.quest, 4)
            fixture_migration_v0001_story_activate(&migrated.quest, 5, .Active)
        }
        if repair >= 3 {
            fixture_migration_v0001_story_complete(&migrated.quest, 5)
            fixture_migration_v0001_story_activate(&migrated.quest, 6, .Active)
        }
        if repair >= 4 {
            fixture_migration_v0001_story_complete(&migrated.quest, 6)
        }

        if romance == 0 {
            if historical.story_state.delivery.active {
                fixture_migration_v0001_story_accept(&migrated.quest, 0)
            }
        } else {
            fixture_migration_v0001_story_accept(&migrated.quest, 0)
            fixture_migration_v0001_story_complete(&migrated.quest, 0)
            fixture_migration_v0001_story_activate(&migrated.quest, 1, .Active)
        }
        if romance >= 2 {
            fixture_migration_v0001_story_complete(&migrated.quest, 1)
            fixture_migration_v0001_story_activate(&migrated.quest, 2, .Active)
        }
        if romance >= 3 {
            fixture_migration_v0001_story_complete(&migrated.quest, 2)
            if repair == 4 {
                fixture_migration_v0001_story_activate(&migrated.quest, 7, .Active)
                fixture_migration_v0001_story_complete(&migrated.quest, 7)
                fixture_migration_v0001_story_activate(&migrated.quest, 8, .Active)
            }
        }
        if romance >= 4 {
            fixture_migration_v0001_story_complete(&migrated.quest, 8)
            fixture_migration_v0001_story_activate(&migrated.quest, 9, .Active)
        }
        if romance >= 5 {
            fixture_migration_v0001_story_complete(&migrated.quest, 9)
            fixture_migration_v0001_story_activate(&migrated.quest, 10, .Active)
            migrated.quest.completion_counts[10] = historical.story_state.repeat_deliveries
            if historical.story_state.repeat_deliveries > 0 {
                migrated.quest.revision += u64(historical.story_state.repeat_deliveries)
                migrated.quest.completed_at[10] = migrated.quest.revision
            }
        }
    }

    migrated.airfield_errand = .Not_Offered
    if started do migrated.airfield_errand = .Completed
    migrated.completed_deliveries = historical.story_state.completed_deliveries
    migrated.repeat_deliveries = historical.story_state.repeat_deliveries
    migrated.stamps_earned = historical.story_state.stamps_earned
    if started do migrated.stamps_earned += 1
    return migrated, true
}

fixture_migrate_v0001_to_v0002 :: proc(
    #by_ptr historical: fixture_v0001.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}

    if historical.project.structure_count < 0 ||
       historical.project.structure_count > FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_CAPACITY ||
       len(tentative.project.structures) != FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_CAPACITY {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID)
    }

    tentative_city := &tentative.architecture_city_plan
    if historical.architecture_city_plan.count < 0 ||
       historical.architecture_city_plan.count > FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_CAPACITY ||
       len(tentative_city.structures) != FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_CAPACITY {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_ID)
    }
    if historical.architecture_city_plan.parcel_count < 0 ||
       historical.architecture_city_plan.parcel_count > FIXTURE_MIGRATION_V0001_CITY_PARCELS_CAPACITY ||
       len(tentative_city.parcels) != FIXTURE_MIGRATION_V0001_CITY_PARCELS_CAPACITY {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_CITY_PARCELS_ID)
    }
    if historical.architecture_city_plan.alley_count < 0 ||
       historical.architecture_city_plan.alley_count > FIXTURE_MIGRATION_V0001_CITY_ALLEYS_CAPACITY ||
       len(tentative_city.alleys) != FIXTURE_MIGRATION_V0001_CITY_ALLEYS_CAPACITY {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_CITY_ALLEYS_ID)
    }
    if historical.architecture_city_plan.lamp_count < 0 ||
       historical.architecture_city_plan.lamp_count > FIXTURE_MIGRATION_V0001_CITY_LAMPS_CAPACITY ||
       len(tentative_city.lamps) != FIXTURE_MIGRATION_V0001_CITY_LAMPS_CAPACITY {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_CITY_LAMPS_ID)
    }

    if historical.farm_count < 0 || historical.farm_count > FIXTURE_MIGRATION_V0001_FARMS_CAPACITY {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_FARM_DEFAULT_ID)
    }

    historical_removed_city := historical.settlement_plan.city_plan
    if historical_removed_city.count < 0 ||
       historical_removed_city.count > FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_CAPACITY ||
       historical_removed_city.count != 0 ||
       historical_removed_city.parcel_count < 0 ||
       historical_removed_city.parcel_count > FIXTURE_MIGRATION_V0001_CITY_PARCELS_CAPACITY ||
       historical_removed_city.parcel_count != 0 ||
       historical_removed_city.alley_count < 0 ||
       historical_removed_city.alley_count > FIXTURE_MIGRATION_V0001_CITY_ALLEYS_CAPACITY ||
       historical_removed_city.alley_count != 0 ||
       historical_removed_city.lamp_count < 0 ||
       historical_removed_city.lamp_count > FIXTURE_MIGRATION_V0001_CITY_LAMPS_CAPACITY ||
       historical_removed_city.lamp_count != 0 {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_CITY_REMOVE_ID)
    }

    migrated_story, story_ok := fixture_migration_v0001_story_build(historical, tentative)
    if !story_ok do return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_STORY_QUEST_ID)

    if resize(&tentative.project.structures, historical.project.structure_count) != nil {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID)
    }
    if resize(&tentative_city.structures, historical.architecture_city_plan.count) != nil {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_CITY_STRUCTURES_ID)
    }
    if resize(&tentative_city.parcels, historical.architecture_city_plan.parcel_count) != nil {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_CITY_PARCELS_ID)
    }
    if resize(&tentative_city.alleys, historical.architecture_city_plan.alley_count) != nil {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_CITY_ALLEYS_ID)
    }
    if resize(&tentative_city.lamps, historical.architecture_city_plan.lamp_count) != nil {
        return fixture_migration_v0001_invalid_source(FIXTURE_MIGRATION_V0001_CITY_LAMPS_ID)
    }

    for index in 0 ..< historical.farm_count {
        tentative.farms[index].plan.width = 25
        tentative.farms[index].plan.height = 19
        tentative.farms[index].plan.tradition = .Ancient_Enclosure
        tentative.farms[index].scale_x = 1
        tentative.farms[index].scale_z = 1
    }

    tentative.story_state = migrated_story
    tentative.tracked_quest_node = quest.Node_ID(-1)
    tentative.quest_tracking_suppressed = false
    tentative.quest_tracking_revision = migrated_story.quest.revision
    return {}
}
