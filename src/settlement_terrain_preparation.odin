package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"

settlement_plan_prepare_block_terrain :: proc(
    plan: ^Settlement_Plan,
    project: ^terrain.Project,
    city_plan: ^architecture.City_Plan = nil,
) {
    if plan == nil || project == nil do return
    if plan.request.scale == .Town && city_plan != nil {
        // Preserve the elevation steps that give a hillside town its profile.
        // Flattening each block's full bounding box caused neighboring edits
        // to overlap into one broad plateau. Compact per-building pads still
        // seat foundations, while same-frontage houses blend into a narrow
        // contour terrace and adjacent runs retain their height difference.
        budget := 28
        prepared := 0
        for structure in city_plan.structures[:city_plan.count] {
            if prepared >= budget do break
            local_slope := settlement_terrain_slope(project, structure.center_x, structure.center_z)
            if local_slope < .035 do continue
            half_x := min(structure.width * .5 + .35, f32(12))
            half_z := min(structure.depth * .5 + .35, f32(9))
            settlement_plan_record_terrain_edit(
                plan,
                project,
                .Building_Pad,
                structure.center_x,
                structure.center_z,
                half_x,
                half_z,
                .7,
                .54,
                .78,
            )
            prepared += 1
        }
        return
    }
    budget := 24
    switch plan.request.scale {
    case .City:
        budget = 24
    case .Town:
        budget = 12
    case .Village:
        budget = 4
    }
    prepared := 0
    for block in plan.blocks[:plan.block_count] {
        if prepared >= budget do break
        minimum_height, maximum_height := f32(1e30), f32(-1e30)
        lowest_corner := block.center
        for corner_index in 0 ..< block.corner_count {
            corner := block.corners[corner_index]
            height := terrain.sample_surface_height(project, 0, corner[0], corner[1])
            if height < minimum_height {
                minimum_height = height
                lowest_corner = corner
            }
            maximum_height = max(maximum_height, height)
        }
        if minimum_height <= project.sea_level + .6 || maximum_height - minimum_height < .65 {
            continue
        }
        half_x := min(block.short_side * .44, f32(14))
        half_z := min(block.long_side * .44, f32(20))
        edit_kind := Settlement_Terrain_Edit_Kind.Building_Pad
        if block.tissue == .Hillside_Accretion ||
           block.tissue == .Contour_Terrace ||
           block.tissue == .Cycladic_Accretion {
            edit_kind = .Neighborhood_Terrace
        }
        settlement_plan_record_terrain_edit(
            plan,
            project,
            edit_kind,
            block.center[0],
            block.center[1],
            half_x,
            half_z,
            4,
        )
        if maximum_height - minimum_height >= 2 && plan.terrain_edit_count < len(plan.terrain_edits) {
            settlement_plan_record_terrain_edit(
                plan,
                project,
                .Retaining_Edge,
                lowest_corner[0],
                lowest_corner[1],
                min(half_x, f32(8)),
                .5,
                0,
            )
        }
        prepared += 1
    }
}
