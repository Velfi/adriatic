package main

import buildings "../packages/buildings"
import fixture_v0003 "../packages/fixture_history/v0003"
import marina "../packages/marina"
import roads "../packages/roads"
import story "../packages/story"
import vehicles "../packages/vehicles"
import "core:math"
import "core:mem"

FIXTURE_MIGRATION_V0003_TO_V0004_FROM_VERSION :: 3
FIXTURE_MIGRATION_V0003_TO_V0004_TO_VERSION :: 4
FIXTURE_MIGRATION_V0003_TO_V0004_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/buildings.Archetype.Mixed_Use_Dwelling",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/buildings.Archetype.Post_Office",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/buildings.Landmark_Kind.Post_Office",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/marina.Shoreline_Form.Natural_Shore",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:packages/story.Resident.Anica", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:packages/story.Resident.Lena", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:packages/story.Resident.Petar", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:packages/story.Resident.Toma", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:packages/story.Resident.Vesna", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/vehicles.Aircraft_Kind.Rondine",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:packages/vehicles.Fixture_Occupant.Rondine",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:src.Authoring_Tool.Wreck", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:src.Mouse_Accessory.Sailor_Hat", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "enum-add:adriatic:src.Settlement_Acceptance_Failure.Building_Access",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:packages/marina.Shoreline_Form.East_Apron",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:packages/marina.Shoreline_Form.Split_Aprons",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:packages/marina.Shoreline_Form.Stepped_Quays",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:packages/marina.Shoreline_Form.Straight_Quay",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:packages/marina.Shoreline_Form.West_Apron",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Authoring_Tool.ClimbingLeaves",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "enum-value:adriatic:src.Authoring_Tool.GreekAssets", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "enum-value:adriatic:src.Authoring_Tool.Roads", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Fabric_Form",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Height_Band",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Height_Outlier",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Insufficient_Buildings",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Landmark_Count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Missing_Blocks",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Missing_Buildings",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Missing_Village_Program",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Park_Count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Route_Grade",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Submerged_Route",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "enum-value:adriatic:src.Settlement_Acceptance_Failure.Submerged_Site",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/architecture.City_Alley.curve_control_from",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/architecture.City_Alley.curve_control_to",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/architecture.City_Alley.curve_ready",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/architecture.City_Alley.end_terminal",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/architecture.City_Alley.household_demand",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/architecture.City_Alley.start_terminal",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/flight.Airframe.parasitic_drag_area",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/postale.Runtime.ground_brake_amount",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/postale.Runtime.ground_pitch_radians",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/postale.Runtime.landing_intent",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/postale.Runtime.landing_intent_seconds",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.clinic_visits",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/story.State.resident_action_seen",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:packages/terrain.Structure.entrance_side",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Fixture.architecture_brush_preset",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Fixture.architecture_brush_shape",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.farm_brush_yaw", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.rondine", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.rondine_visible", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.wreck_brush_size", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.wreck_brush_yaw", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.wreck_count", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.wreck_paint_mode", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.wrecks", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.dead_end_frontage",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Metrics.road_badness",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_bad_door_approaches",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_bad_road_approaches",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_connected_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_crossings",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_excessive_grades",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_hairpin_bends",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_max_degree",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_max_shared_width_step",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_orphan_endpoints",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_required_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_routes_truncated",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_shallow_junctions",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_shared_segments",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_stair_routes",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_unsplit_junctions",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.access_widened_segments",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.activity_point_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.activity_points",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.brush_piece_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Settlement_Plan.brush_pieces", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.inhabitant_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Settlement_Plan.inhabitants", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.next_brush_component_id",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Settlement_Plan.program", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.road_badness_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.road_badness_sum",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.route_piece_ids",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-add:adriatic:src.Settlement_Plan.site_piece_ids",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Settlement_Request.density", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/flight.Airframe.maximum_speed",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/flight.Airframe.stall_speed",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/flight.Runtime.stall_speed_modifier",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/postale.Runtime.takeoff_armed",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/postale.Tuning.takeoff_stall_speed_scale",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:packages/postale.Tuning.takeoff_vertical_assist",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.architecture_brush_radius",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.player_tail", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-type:adriatic:src.Settlement_Plan.routes", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/mouse_tail.Point", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/mouse_tail.State", kind = .Scripted},
}

FIXTURE_MIGRATION_V0003_SETTLEMENT_ID :: "field-add:adriatic:src.Settlement_Metrics.dead_end_frontage"
FIXTURE_MIGRATION_V0003_STRUCTURAL_ID :: "field-add:adriatic:packages/architecture.City_Alley.curve_control_from"
FIXTURE_MIGRATION_V0003_ROOT_ID :: "field-add:adriatic:src.Fixture.farm_brush_yaw"
FIXTURE_MIGRATION_V0003_RONDINE_ID :: "field-add:adriatic:src.Fixture.rondine"
FIXTURE_MIGRATION_V0003_BRUSH_PRESET_ID :: "field-add:adriatic:src.Fixture.architecture_brush_preset"
FIXTURE_MIGRATION_V0003_ARCHETYPE_ID :: "enum-add:adriatic:packages/buildings.Archetype.Mixed_Use_Dwelling"
FIXTURE_MIGRATION_V0003_LANDMARK_ID :: "enum-add:adriatic:packages/buildings.Landmark_Kind.Post_Office"
FIXTURE_MIGRATION_V0003_SHORELINE_ID :: "enum-add:adriatic:packages/marina.Shoreline_Form.Natural_Shore"
FIXTURE_MIGRATION_V0003_RESIDENT_ID :: "enum-add:adriatic:packages/story.Resident.Anica"
FIXTURE_MIGRATION_V0003_AIRCRAFT_ID :: "enum-add:adriatic:packages/vehicles.Aircraft_Kind.Rondine"
FIXTURE_MIGRATION_V0003_OCCUPANT_ID :: "enum-add:adriatic:packages/vehicles.Fixture_Occupant.Rondine"
FIXTURE_MIGRATION_V0003_AUTHORING_ID :: "enum-add:adriatic:src.Authoring_Tool.Wreck"
FIXTURE_MIGRATION_V0003_MOUSE_ACCESSORY_ID :: "enum-add:adriatic:src.Mouse_Accessory.Sailor_Hat"
FIXTURE_MIGRATION_V0003_SETTLEMENT_FAILURE_ID :: "enum-add:adriatic:src.Settlement_Acceptance_Failure.Building_Access"

fixture_migration_v0003_enum_valid :: proc(value, maximum: int) -> bool {
    return value >= 0 && value <= maximum
}

fixture_migration_v0003_invalid_source :: proc(change_id: string) -> Fixture_Migration_Error {
    return {kind = .Invalid_Source, change_id = change_id}
}

fixture_migration_v0003_archetypes_valid :: proc(#by_ptr historical: fixture_v0003.Fixture) -> bool {
    for structure in historical.project.structures {
        if !fixture_migration_v0003_enum_valid(int(structure.building.archetype), 17) do return false
    }
    for structure in historical.architecture_city_plan.structures {
        if !fixture_migration_v0003_enum_valid(int(structure.building.archetype), 17) do return false
    }
    for site in historical.settlement_plan.sites {
        if !fixture_migration_v0003_enum_valid(int(site.structure.building.archetype), 17) do return false
    }
    for site in historical.settlement_plan.rejected_sites {
        if !fixture_migration_v0003_enum_valid(int(site.structure.building.archetype), 17) do return false
    }
    for structure in historical.settlement_plan.decorative_foliage {
        if !fixture_migration_v0003_enum_valid(int(structure.building.archetype), 17) do return false
    }
    return true
}

fixture_migration_v0003_landmarks_valid :: proc(#by_ptr historical: fixture_v0003.Fixture) -> bool {
    for structure in historical.project.structures {
        if !fixture_migration_v0003_enum_valid(int(structure.building.landmark_kind), 8) do return false
    }
    for structure in historical.architecture_city_plan.structures {
        if !fixture_migration_v0003_enum_valid(int(structure.building.landmark_kind), 8) do return false
    }
    for site in historical.settlement_plan.sites {
        if !fixture_migration_v0003_enum_valid(int(site.structure.building.landmark_kind), 8) do return false
    }
    for site in historical.settlement_plan.rejected_sites {
        if !fixture_migration_v0003_enum_valid(int(site.structure.building.landmark_kind), 8) do return false
    }
    for structure in historical.settlement_plan.decorative_foliage {
        if !fixture_migration_v0003_enum_valid(int(structure.building.landmark_kind), 8) do return false
    }
    return true
}

fixture_migration_v0003_apply_identity :: proc(
    historical: fixture_v0003.History_Type_0015,
    tentative: ^buildings.Identity,
) {
    tentative.archetype = buildings.Archetype(int(historical.archetype))
    tentative.landmark_kind = buildings.Landmark_Kind(int(historical.landmark_kind))
}

fixture_migration_v0003_apply_buildings :: proc(#by_ptr historical: fixture_v0003.Fixture, tentative: ^Fixture) {
    for structure, index in historical.project.structures {
        fixture_migration_v0003_apply_identity(structure.building, &tentative.project.structures[index].building)
    }
    for structure, index in historical.architecture_city_plan.structures {
        fixture_migration_v0003_apply_identity(
            structure.building,
            &tentative.architecture_city_plan.structures[index].building,
        )
    }
    for site, index in historical.settlement_plan.sites {
        fixture_migration_v0003_apply_identity(
            site.structure.building,
            &tentative.settlement_plan.sites[index].structure.building,
        )
    }
    for site, index in historical.settlement_plan.rejected_sites {
        fixture_migration_v0003_apply_identity(
            site.structure.building,
            &tentative.settlement_plan.rejected_sites[index].structure.building,
        )
    }
    for structure, index in historical.settlement_plan.decorative_foliage {
        fixture_migration_v0003_apply_identity(
            structure.building,
            &tentative.settlement_plan.decorative_foliage[index].building,
        )
    }
}

fixture_migration_v0003_enum_preflight :: proc(
    #by_ptr historical: fixture_v0003.Fixture,
    tentative: ^Fixture,
) -> Fixture_Migration_Error {
    if len(historical.project.structures) != len(tentative.project.structures) ||
       len(historical.architecture_city_plan.structures) != len(tentative.architecture_city_plan.structures) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_ARCHETYPE_ID)
    }
    if !fixture_migration_v0003_archetypes_valid(historical) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_ARCHETYPE_ID)
    }
    if !fixture_migration_v0003_landmarks_valid(historical) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_LANDMARK_ID)
    }
    if !fixture_migration_v0003_enum_valid(int(historical.marina_authored_plan.shoreline_form), 4) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SHORELINE_ID)
    }
    if !fixture_migration_v0003_enum_valid(int(historical.story_state.delivery.from), 5) ||
       !fixture_migration_v0003_enum_valid(int(historical.story_state.delivery.to), 5) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_RESIDENT_ID)
    }
    for slot in historical.aircraft.slots {
        if !fixture_migration_v0003_enum_valid(int(slot.kind), 2) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_AIRCRAFT_ID)
        }
    }
    if !fixture_migration_v0003_enum_valid(int(historical.aircraft.active), 2) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_AIRCRAFT_ID)
    }
    if !fixture_migration_v0003_enum_valid(int(historical.occupant), 4) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_OCCUPANT_ID)
    }
    if !fixture_migration_v0003_enum_valid(int(historical.authoring_tool), 12) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_AUTHORING_ID)
    }
    if !fixture_migration_v0003_enum_valid(int(historical.mouse_headgear), 10) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_MOUSE_ACCESSORY_ID)
    }
    if !fixture_migration_v0003_enum_valid(int(historical.settlement_plan.acceptance_failure), 16) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_FAILURE_ID)
    }
    return {}
}

fixture_migration_v0003_enum_apply :: proc(#by_ptr historical: fixture_v0003.Fixture, tentative: ^Fixture) {
    fixture_migration_v0003_apply_buildings(historical, tentative)
    tentative.marina_authored_plan.shoreline_form = marina.Shoreline_Form(
        int(historical.marina_authored_plan.shoreline_form) + 1,
    )
    tentative.story_state.delivery.from = story.Resident(int(historical.story_state.delivery.from))
    tentative.story_state.delivery.to = story.Resident(int(historical.story_state.delivery.to))
    for slot, index in historical.aircraft.slots {
        tentative.aircraft.slots[index].kind = vehicles.Aircraft_Kind(int(slot.kind))
    }
    tentative.aircraft.active = vehicles.Aircraft_Kind(int(historical.aircraft.active))
    tentative.occupant = vehicles.Fixture_Occupant(int(historical.occupant))
    authoring_tool := int(historical.authoring_tool)
    if authoring_tool >= 10 do authoring_tool += 1
    tentative.authoring_tool = Authoring_Tool(authoring_tool)
    tentative.mouse_headgear = Mouse_Accessory(int(historical.mouse_headgear))
    settlement_failure := int(historical.settlement_plan.acceptance_failure)
    if settlement_failure >= 5 do settlement_failure += 1
    tentative.settlement_plan.acceptance_failure = Settlement_Acceptance_Failure(settlement_failure)
}

fixture_migration_v0003_enum_slice :: proc(
    #by_ptr historical: fixture_v0003.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}
    preflight_error := fixture_migration_v0003_enum_preflight(historical, tentative)
    if preflight_error.kind != .None do return preflight_error
    fixture_migration_v0003_enum_apply(historical, tentative)
    return {kind = .Unresolved, change_id = FIXTURE_MIGRATION_V0003_STRUCTURAL_ID}
}

fixture_migration_v0003_structural_preflight :: proc(
    #by_ptr historical: fixture_v0003.Fixture,
    tentative: ^Fixture,
) -> Fixture_Migration_Error {
    if len(historical.architecture_city_plan.alleys) != len(tentative.architecture_city_plan.alleys) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_STRUCTURAL_ID)
    }
    radius := historical.architecture_brush_radius
    if radius < 0 || math.is_nan(radius) || math.is_inf(radius) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_BRUSH_PRESET_ID)
    }
    return {}
}

fixture_migration_v0003_structural_apply :: proc(#by_ptr historical: fixture_v0003.Fixture, tentative: ^Fixture) {
    for &alley in tentative.architecture_city_plan.alleys {
        alley.curve_control_from = {}
        alley.curve_control_to = {}
        alley.curve_ready = false
        alley.end_terminal = .None
        alley.household_demand = 0
        alley.start_terminal = .None
    }

    tentative.postale.airframe.parasitic_drag_area = 1.33
    tentative.tweak.postale_airframe.parasitic_drag_area = 1.33
    tentative.postale.ground_brake_amount = 0
    tentative.postale.ground_pitch_radians = 0
    tentative.postale.landing_intent = false
    tentative.postale.landing_intent_seconds = 0

    tentative.story_state.clinic_visits = 0
    tentative.story_state.resident_action_seen = {}

    for &structure in tentative.project.structures {
        structure.entrance_side = .Front
    }
    for &structure in tentative.architecture_city_plan.structures {
        structure.entrance_side = .Front
    }
    for &site in tentative.settlement_plan.sites {
        site.structure.entrance_side = .Front
    }
    for &site in tentative.settlement_plan.rejected_sites {
        site.structure.entrance_side = .Front
    }
    for &structure in tentative.settlement_plan.decorative_foliage {
        structure.entrance_side = .Front
    }

    tentative.architecture_brush_shape = .Circle
    radius := historical.architecture_brush_radius
    switch {
    case radius < 45:
        tentative.architecture_brush_preset = .Small
    case radius < 85:
        tentative.architecture_brush_preset = .Medium
    case:
        tentative.architecture_brush_preset = .Large
    }
    tentative.player_tail = {}
}

fixture_migration_v0003_structural_slice :: proc(
    #by_ptr historical: fixture_v0003.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}

    enum_error := fixture_migration_v0003_enum_preflight(historical, tentative)
    if enum_error.kind != .None do return enum_error
    structural_error := fixture_migration_v0003_structural_preflight(historical, tentative)
    if structural_error.kind != .None do return structural_error

    fixture_migration_v0003_enum_apply(historical, tentative)
    fixture_migration_v0003_structural_apply(historical, tentative)
    return {kind = .Unresolved, change_id = FIXTURE_MIGRATION_V0003_ROOT_ID}
}

fixture_migration_v0003_root_preflight :: proc(
    #by_ptr historical: fixture_v0003.Fixture,
    tentative: ^Fixture,
) -> Fixture_Migration_Error {
    if historical.aircraft.count != 3 || tentative.aircraft.count != historical.aircraft.count {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_RONDINE_ID)
    }

    kind_counts := [3]u8{}
    for index in 0 ..< historical.aircraft.count {
        kind := int(historical.aircraft.slots[index].kind)
        if kind < 0 || kind >= len(kind_counts) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_RONDINE_ID)
        }
        kind_counts[kind] += 1
    }
    active := int(historical.aircraft.active)
    if active < 0 || active >= len(kind_counts) || kind_counts[active] == 0 {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_RONDINE_ID)
    }
    for count in kind_counts {
        if count != 1 do return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_RONDINE_ID)
    }
    return {}
}

fixture_migration_v0003_root_apply :: proc(tentative: ^Fixture) {
    tentative.farm_brush_yaw = 0
    tentative.aircraft.slots[3] = {
        kind      = .Rondine,
        name      = "Rondine",
        vehicle   = nil,
        available = false,
    }
    tentative.aircraft.count = 4

    tentative.rondine = {}
    tentative.rondine.vehicle.locked = true
    tentative.rondine_visible = false

    tentative.wreck_paint_mode = false
    tentative.wreck_brush_size = 330
    tentative.wreck_brush_yaw = 0
    tentative.wrecks = {}
    tentative.wreck_count = 0
}

fixture_migration_v0003_root_slice :: proc(
    #by_ptr historical: fixture_v0003.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}

    enum_error := fixture_migration_v0003_enum_preflight(historical, tentative)
    if enum_error.kind != .None do return enum_error
    structural_error := fixture_migration_v0003_structural_preflight(historical, tentative)
    if structural_error.kind != .None do return structural_error
    root_error := fixture_migration_v0003_root_preflight(historical, tentative)
    if root_error.kind != .None do return root_error

    fixture_migration_v0003_enum_apply(historical, tentative)
    fixture_migration_v0003_structural_apply(historical, tentative)
    fixture_migration_v0003_root_apply(tentative)
    return {kind = .Unresolved, change_id = FIXTURE_MIGRATION_V0003_SETTLEMENT_ID}
}

fixture_migration_v0003_settlement_count_valid :: proc(value, capacity: int) -> bool {
    return value >= 0 && value <= capacity
}

fixture_migration_v0003_settlement_structure_valid :: proc(structure: fixture_v0003.History_Type_0087) -> bool {
    return(
        fixture_migration_v0003_enum_valid(int(structure.kind), 7) &&
        fixture_migration_v0003_enum_valid(int(structure.building.purpose), 7) &&
        fixture_migration_v0003_enum_valid(int(structure.building.region), 1) \
    )
}

fixture_migration_v0003_settlement_site_valid :: proc(site: fixture_v0003.History_Type_0137) -> bool {
    return(
        fixture_migration_v0003_settlement_structure_valid(site.structure) &&
        fixture_migration_v0003_enum_valid(int(site.kind), 3) &&
        fixture_migration_v0003_enum_valid(int(site.tissue), 8) &&
        fixture_migration_v0003_enum_valid(int(site.landmark_kind), 7) &&
        fixture_migration_v0003_enum_valid(int(site.purpose), 7) \
    )
}

fixture_migration_v0003_settlement_metrics_valid :: proc(metrics: fixture_v0003.History_Type_0127) -> bool {
    if metrics.route_length.count < 0 ||
       metrics.route_width.count < 0 ||
       metrics.route_grade.count < 0 ||
       metrics.intersection_spacing.count < 0 ||
       metrics.block_short_side.count < 0 ||
       metrics.block_long_side.count < 0 ||
       metrics.block_area.count < 0 ||
       metrics.block_aspect.count < 0 ||
       metrics.block_irregularity.count < 0 ||
       metrics.parcel_frontage.count < 0 ||
       metrics.parcel_depth.count < 0 ||
       metrics.building_height.count < 0 ||
       metrics.building_footprint.count < 0 ||
       metrics.building_floors.count < 0 {
        return false
    }
    for stats in metrics.route_length_by_class {
        if stats.count < 0 do return false
    }
    for stats in metrics.route_width_by_class {
        if stats.count < 0 do return false
    }
    for count in metrics.density_band_count {
        if count < 0 do return false
    }
    return(
        metrics.fabric_quadrants >= 0 &&
        metrics.landmark_count >= 0 &&
        metrics.park_count >= 0 &&
        metrics.rejected_count >= 0 \
    )
}

fixture_migration_v0003_settlement_plan_preflight :: proc(
    #by_ptr old: fixture_v0003.History_Type_0129,
    new: ^Settlement_Plan,
) -> Fixture_Migration_Error {
    if len(old.neighborhoods) != 96 ||
       len(new.neighborhoods) != 96 ||
       len(old.macro_cells) != 192 ||
       len(new.macro_cells) != 192 ||
       len(old.routes) != 48 ||
       len(new.routes) != 320 ||
       len(old.blocks) != 128 ||
       len(new.blocks) != 128 ||
       len(old.sites) != 256 ||
       len(new.sites) != 256 ||
       len(old.rejected_sites) != 32 ||
       len(new.rejected_sites) != 32 ||
       len(old.decorative_foliage) != 32 ||
       len(new.decorative_foliage) != 32 ||
       len(old.terrain_edits) != 192 ||
       len(new.terrain_edits) != 192 ||
       len(old.ordinary_purposes) != 256 ||
       len(new.ordinary_purposes) != 256 ||
       len(new.brush_pieces) != 64 ||
       len(new.activity_points) != 512 ||
       len(new.inhabitants) != 256 ||
       len(new.route_piece_ids) != 320 ||
       len(new.site_piece_ids) != 256 {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
    }
    if !fixture_migration_v0003_settlement_count_valid(old.neighborhood_count, len(old.neighborhoods)) ||
       !fixture_migration_v0003_settlement_count_valid(old.macro_cell_count, len(old.macro_cells)) ||
       !fixture_migration_v0003_settlement_count_valid(old.route_count, len(old.routes)) ||
       !fixture_migration_v0003_settlement_count_valid(old.block_count, len(old.blocks)) ||
       !fixture_migration_v0003_settlement_count_valid(old.site_count, len(old.sites)) ||
       !fixture_migration_v0003_settlement_count_valid(old.rejected_site_count, len(old.rejected_sites)) ||
       !fixture_migration_v0003_settlement_count_valid(old.decorative_foliage_count, len(old.decorative_foliage)) ||
       !fixture_migration_v0003_settlement_count_valid(old.terrain_edit_count, len(old.terrain_edits)) ||
       !fixture_migration_v0003_settlement_count_valid(old.ordinary_purpose_count, len(old.ordinary_purposes)) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
    }
    if new.neighborhood_count != old.neighborhood_count ||
       new.macro_cell_count != old.macro_cell_count ||
       new.route_count != old.route_count ||
       new.block_count != old.block_count ||
       new.site_count != old.site_count ||
       new.rejected_site_count != old.rejected_site_count ||
       new.decorative_foliage_count != old.decorative_foliage_count ||
       new.terrain_edit_count != old.terrain_edit_count ||
       new.ordinary_purpose_count != old.ordinary_purpose_count {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
    }
    if !fixture_migration_v0003_enum_valid(int(old.request.region), 1) ||
       !fixture_migration_v0003_enum_valid(int(old.request.scale), 2) ||
       !fixture_migration_v0003_enum_valid(int(old.village_reason), 3) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
    }
    for neighborhood in old.neighborhoods {
        if !fixture_migration_v0003_enum_valid(int(neighborhood.tissue), 8) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        }
    }
    for neighborhood in old.macro_cells {
        if !fixture_migration_v0003_enum_valid(int(neighborhood.tissue), 8) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        }
    }
    for route in old.routes {
        if !fixture_migration_v0003_settlement_count_valid(route.geometry.count, len(route.geometry.points)) ||
           !fixture_migration_v0003_enum_valid(int(route.class), 7) ||
           !fixture_migration_v0003_enum_valid(int(route.pavement), 3) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        }
    }
    for block in old.blocks {
        if !fixture_migration_v0003_settlement_count_valid(block.corner_count, len(block.corners)) ||
           !fixture_migration_v0003_enum_valid(int(block.tissue), 8) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        }
    }
    for site in old.sites {
        if !fixture_migration_v0003_settlement_site_valid(site) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        }
    }
    for site in old.rejected_sites {
        if !fixture_migration_v0003_settlement_site_valid(site) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        }
    }
    for structure in old.decorative_foliage {
        if !fixture_migration_v0003_settlement_structure_valid(structure) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        }
    }
    for edit in old.terrain_edits {
        if !fixture_migration_v0003_enum_valid(int(edit.kind), 4) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        }
    }
    for purpose in old.ordinary_purposes {
        if !fixture_migration_v0003_enum_valid(int(purpose), 7) {
            return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
        }
    }
    if !fixture_migration_v0003_settlement_metrics_valid(old.metrics) {
        return fixture_migration_v0003_invalid_source(FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
    }
    return {}
}

fixture_migration_v0003_settlement_preflight :: proc(
    #by_ptr historical: fixture_v0003.Fixture,
    tentative: ^Fixture,
) -> Fixture_Migration_Error {
    return fixture_migration_v0003_settlement_plan_preflight(historical.settlement_plan, &tentative.settlement_plan)
}

fixture_migration_v0003_settlement_copy_route :: proc(
    historical: fixture_v0003.History_Type_0130,
    tentative: ^Settlement_Planned_Route,
) {
    tentative.geometry.points = historical.geometry.points
    tentative.geometry.count = historical.geometry.count
    tentative.class = Settlement_Route_Class(int(historical.class))
    tentative.width = historical.width
    tentative.shoulder = historical.shoulder
    tentative.pavement = roads.Pavement(int(historical.pavement))
    tentative.required = historical.required
    tentative.drivable = historical.drivable
    tentative.average_grade = historical.average_grade
    tentative.maximum_grade = historical.maximum_grade
}

fixture_migration_v0003_settlement_apply :: proc(#by_ptr historical: fixture_v0003.Fixture, tentative: ^Fixture) {
    plan := &tentative.settlement_plan
    plan.request.density = 0
    plan.brush_pieces = {}
    plan.brush_piece_count = 0
    plan.next_brush_component_id = 0
    plan.program = {}
    plan.activity_points = {}
    plan.activity_point_count = 0
    plan.inhabitants = {}
    plan.inhabitant_count = 0
    plan.route_piece_ids = {}
    plan.access_routes_truncated = false
    plan.access_required_count = 0
    plan.access_connected_count = 0
    plan.access_max_degree = 0
    plan.access_shallow_junctions = 0
    plan.access_hairpin_bends = 0
    plan.access_crossings = 0
    plan.access_unsplit_junctions = 0
    plan.access_bad_door_approaches = 0
    plan.access_bad_road_approaches = 0
    plan.access_stair_routes = 0
    plan.access_excessive_grades = 0
    plan.access_shared_segments = 0
    plan.access_widened_segments = 0
    plan.access_max_shared_width_step = 0
    plan.access_orphan_endpoints = 0
    plan.road_badness_sum = 0
    plan.road_badness_count = 0
    plan.site_piece_ids = {}
    plan.metrics.dead_end_frontage = {}
    plan.metrics.road_badness = 0

    for route, index in historical.settlement_plan.routes {
        fixture_migration_v0003_settlement_copy_route(route, &plan.routes[index])
    }
    for index in len(historical.settlement_plan.routes) ..< len(plan.routes) {
        plan.routes[index] = {}
    }
}

fixture_migrate_v0003_to_v0004 :: proc(
    #by_ptr historical: fixture_v0003.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}

    enum_error := fixture_migration_v0003_enum_preflight(historical, tentative)
    if enum_error.kind != .None do return enum_error
    structural_error := fixture_migration_v0003_structural_preflight(historical, tentative)
    if structural_error.kind != .None do return structural_error
    root_error := fixture_migration_v0003_root_preflight(historical, tentative)
    if root_error.kind != .None do return root_error
    settlement_error := fixture_migration_v0003_settlement_preflight(historical, tentative)
    if settlement_error.kind != .None do return settlement_error

    fixture_migration_v0003_enum_apply(historical, tentative)
    fixture_migration_v0003_structural_apply(historical, tentative)
    fixture_migration_v0003_root_apply(tentative)
    fixture_migration_v0003_settlement_apply(historical, tentative)
    return {}
}
