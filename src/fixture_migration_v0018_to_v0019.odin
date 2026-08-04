package main

import fixture_v0018 "../packages/fixture_history/v0018"
import terrain "../packages/terrain"
import "core:mem"

FIXTURE_MIGRATION_V0018_TO_V0019_FROM_VERSION :: 18
FIXTURE_MIGRATION_V0018_TO_V0019_TO_VERSION :: 19
FIXTURE_MIGRATION_V0018_TO_V0019_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution{change_id = "enum-add:adriatic:src.Authoring_Tool.Obstacles", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.lab", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.map_source", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.sdf_obstacle_count", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.sdf_obstacle_selected", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-add:adriatic:src.Fixture.sdf_obstacles", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.active_lab_scene", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.default_harbors", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.default_map_regeneration_seeds",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.default_marina_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.default_marina_islands",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.default_marinas", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.farm_count", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.farms", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.greek_placement_count",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.greek_placements", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.harbor_authored_intervention",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.harbor_authored_plan",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.marina_authored", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.marina_authored_plan",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.project", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.settlement_plan", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "field-remove:adriatic:src.Fixture.vehicle_paint_layers",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.wreck_count", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "field-remove:adriatic:src.Fixture.wrecks", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/farmland.Crop", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/farmland.Parcel", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/farmland.Plan", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/farmland.Tradition", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/fountains.Style", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Archetype", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Berth", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Berth_Kind", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Bounds", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/harbor.Coastal_Opportunity",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Contour", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/harbor.Harbor_Diagnostics",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/harbor.Harbor_Intervention",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Harbor_Plan", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Harbor_Program", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Harbor_Purpose", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Harbor_Site", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Harbor_Strategy", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/harbor.Historical_Phase",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/harbor.Historical_Phase_Kind",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Route", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Settlement_Role", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Structure_Kind", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/harbor.Structure_Material",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Structure_Path", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Terrain_Edit", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/harbor.Terrain_Edit_Kind",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Vec2", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Waterfront_Use", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/harbor.Waterfront_Zone", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Basin_Style", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Berth_Kind", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Boundary_Form", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Cell", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Plan", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Prop", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Prop_Kind", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Route", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Segment", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Segment_Kind", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Shoreline_Form", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Slip", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/marina.Vec2", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/roads.Alignment_Element_Kind",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/roads.Edge", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/roads.Graph", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/roads.Node", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:packages/roads.Structure_Span_Kind",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/roads.Vec3", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/terrain.Clipmap_Level", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:packages/terrain.Project", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Farm_Instance", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Greek_Placement", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Markov_Wreck_Cell", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Markov_Wreck_Form", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Markov_Wreck_Part_State", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Markov_Wreck_Quality", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:src.Settlement_Acceptance_Failure",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Activity_Kind", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Activity_Point", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Block", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Brush_Piece", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Building_Purpose", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Garden_Plot", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Garden_Style", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Growth_Event", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:src.Settlement_Growth_Event_Kind",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Inhabitant", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Landmark_Kind", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Metrics", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Neighborhood", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Patio", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Patio_Style", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Plan", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Planned_Route", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Program", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Program_Count", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Region", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Request", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Route", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Route_Class", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Scalar_Stats", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Scale", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Site", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Site_Kind", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Terrain_Edit", kind = .Scripted},
    Fixture_Migration_Resolution {
        change_id = "type-remove:adriatic:src.Settlement_Terrain_Edit_Kind",
        kind = .Scripted,
    },
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Settlement_Tissue", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Village_Reason", kind = .Scripted},
    Fixture_Migration_Resolution{change_id = "type-remove:adriatic:src.Wreck_Instance", kind = .Scripted},
}

fixture_migration_v0018_to_v0019_empty_grid_metadata :: proc(project: terrain.Project) -> bool {
    for level in project.levels {
        if level.cell_size != 0 || level.origin_x != 0 || level.origin_z != 0 do return false
    }
    return true
}

fixture_migration_v0018_to_v0019_normalize_empty_grid_metadata :: proc(project: ^terrain.Project) {
    if project == nil do return
    for &level, index in project.levels {
        level.cell_size = terrain.FINE_CELL_SIZE * f32(u32(1) << u32(index))
        half_grid := f32(terrain.TERRAIN_RESOLUTION - 1) * .5 * level.cell_size
        level.origin_x = -half_grid
        level.origin_z = -half_grid
    }
}

fixture_migrate_v0018_to_v0019 :: proc(
    #by_ptr historical: fixture_v0018.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    return fixture_v0019_apply_map_source(historical.active_lab_scene, tentative, allocator)
}

fixture_v0019_apply_map_source :: proc(
    active_lab_scene: string,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    if tentative == nil || allocator.procedure == nil do return {kind = .Invalid_Argument}

    if fixture_migration_v0018_to_v0019_empty_grid_metadata(tentative.project) {
        fixture_migration_v0018_to_v0019_normalize_empty_grid_metadata(&tentative.project)
    }

    map_source, map_error, captured := fixture_map_source_capture_inline(tentative, allocator)
    defer map_artifact_error_dispose(&map_error)
    if !captured {
        if map_artifact_error_is_allocation_failure(map_error) do return {kind = .Out_Of_Memory}
        return {kind = .Invalid_Source, change_id = "field-add:adriatic:src.Fixture.map_source"}
    }
    tentative.map_source = map_source
    fixture_map_source_clear_excluded(tentative)

    tentative.sdf_obstacles = {}
    tentative.sdf_obstacle_count = 0
    tentative.sdf_obstacle_selected = -1
    tentative.lab = {}
    return {}
}
