package main

import harbor "../packages/harbor"
import marina "../packages/marina"
import terrain "../packages/terrain"

island_translate_pair :: #force_inline proc(point: ^[2]f32, dx, dz: f32) {
    point[0] += dx
    point[1] += dz
}

island_translate_structure_value :: #force_inline proc(structure: ^terrain.Structure, dx, dz: f32) {
    structure.center_x += dx
    structure.center_z += dz
}

island_translate_settlement :: proc(plan: ^Settlement_Plan, dx, dz: f32) {
    if plan == nil do return
    island_translate_pair(&plan.request.center, dx, dz)
    for &piece in plan.brush_pieces[:plan.brush_piece_count] do island_translate_pair(&piece.center, dx, dz)
    for &point in plan.activity_points[:plan.activity_point_count] do island_translate_pair(&point.position, dx, dz)
    for &neighborhood in plan.neighborhoods[:plan.neighborhood_count] do island_translate_pair(&neighborhood.center, dx, dz)
    for &cell in plan.macro_cells[:plan.macro_cell_count] do island_translate_pair(&cell.center, dx, dz)
    for &route in plan.routes[:plan.route_count] {
        for &point in route.geometry.points[:route.geometry.count] do island_translate_pair(&point, dx, dz)
    }
    for &event in plan.growth_events[:plan.growth_event_count] {
        island_translate_pair(&event.frontage_start, dx, dz)
        island_translate_pair(&event.frontage_finish, dx, dz)
    }
    for &block in plan.blocks[:plan.block_count] {
        island_translate_pair(&block.center, dx, dz)
        for &corner in block.corners[:block.corner_count] do island_translate_pair(&corner, dx, dz)
    }
    for &site in plan.sites[:plan.site_count] {
        island_translate_structure_value(&site.structure, dx, dz)
        for &corner in site.parcel.corners do island_translate_pair(&corner, dx, dz)
    }
    for &site in plan.rejected_sites[:plan.rejected_site_count] {
        island_translate_structure_value(&site.structure, dx, dz)
        for &corner in site.parcel.corners do island_translate_pair(&corner, dx, dz)
    }
    for &garden in plan.gardens[:plan.garden_count] do island_translate_pair(&garden.center, dx, dz)
    for &patio in plan.patios[:plan.patio_count] do island_translate_pair(&patio.center, dx, dz)
    for &structure in plan.decorative_foliage[:plan.decorative_foliage_count] {
        island_translate_structure_value(&structure, dx, dz)
    }
    for &edit in plan.terrain_edits[:plan.terrain_edit_count] do island_translate_pair(&edit.center, dx, dz)
}

editor_island_set_center :: proc(editor: ^Editor, id: terrain.Island_ID, x, z: f32) -> bool {
    if editor == nil || id == .World || !terrain.island_center_valid(x, z) do return false
    old_x, old_z, found := terrain.island_center(&editor.project, id)
    if !found do return false
    dx, dz := x - old_x, z - old_z
    if dx == 0 && dz == 0 do return true

    if editor.marina_authored &&
       terrain.island_at(
           &editor.project,
           editor.marina_authored_plan.world_origin.x,
           editor.marina_authored_plan.world_origin.z,
       ) ==
           id {
        marina.translate_world(&editor.marina_authored_plan, dx, dz)
        harbor.translate_plan(&editor.harbor_authored_plan, dx, dz)
        harbor.translate_intervention(&editor.harbor_authored_intervention, dx, dz)
    }
    if editor.settlement_plan.valid &&
       terrain.island_at(
           &editor.project,
           editor.settlement_plan.request.center[0],
           editor.settlement_plan.request.center[1],
       ) ==
           id {
        island_translate_settlement(&editor.settlement_plan, dx, dz)
    }
    for &farm in editor.farms[:editor.farm_count] {
        if terrain.island_at(&editor.project, farm.origin_x, farm.origin_z) != id do continue
        farm.origin_x += dx
        farm.origin_z += dz
    }
    for &wreck in editor.wrecks[:editor.wreck_count] {
        if terrain.island_at(&editor.project, wreck.origin_x, wreck.origin_z) != id do continue
        wreck.origin_x += dx
        wreck.origin_z += dz
    }
    for &placement in editor.greek_placements[:editor.greek_placement_count] {
        if terrain.island_at(&editor.project, placement.x, placement.z) != id do continue
        placement.x += dx
        placement.z += dz
    }

    target_index, _ := terrain.island_index(id)
    for index in 0 ..< editor.default_marina_count {
        expected := editor.default_marina_islands[index]
        belongs := (target_index == 0 && expected == .West) || (target_index == 1 && expected == .East)
        if !belongs do continue
        marina.translate_world(&editor.default_marinas[index], dx, dz)
        harbor.translate_plan(&editor.default_harbors[index], dx, dz)
        harbor.translate_intervention(&editor.default_harbor_interventions[index], dx, dz)
    }

    if !terrain.island_set_center(&editor.project, id, x, z) do return false
    world_renderer_fixture_invalidate(editor)
    gameplay_physics_rebuild_structures(editor)
    return true
}
