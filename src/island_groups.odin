package main

import boats "../packages/boats"
import harbor "../packages/harbor"
import marina "../packages/marina"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"

island_translate_pair :: #force_inline proc(point: ^[2]f32, dx, dz: f32) {
    point[0] += dx
    point[1] += dz
}

island_translate_structure_value :: #force_inline proc(structure: ^terrain.Structure, dx, dz: f32) {
    structure.center_x += dx
    structure.center_z += dz
}

island_translate_vehicle :: #force_inline proc(vehicle: ^vehicles.Vehicle, dx, dz: f32) {
    if vehicle == nil do return
    vehicle.position.x += dx
    vehicle.position.z += dz
}

island_boat_owner_position :: #force_inline proc(agent: ^boats.Agent) -> boats.Vec2 {
    if agent.behavior == .Moored do return agent.mooring_position
    if agent.route_count > 0 do return agent.route[0]
    return agent.loiter_center
}

island_translate_boat_agent :: proc(agent: ^boats.Agent, dx, dz: f32) {
    if agent == nil do return
    offset := boats.Vec2{dx, dz}
    agent.position += offset
    agent.loiter_center += offset
    agent.mooring_position += offset
    for &point in agent.route[:agent.route_count] do point += offset
    for &sample in agent.wake[:agent.wake_count] do sample.position += offset
}

editor_island_translate_mobile_actors :: proc(editor: ^Editor, id: terrain.Island_ID, dx, dz: f32) {
    if editor == nil do return

    player_on_island := terrain.island_at(&editor.project, editor.player.position.x, editor.player.position.z) == id
    car_on_island := terrain.island_at(&editor.project, editor.car.position.x, editor.car.position.z) == id
    trailer_on_island :=
        terrain.island_at(&editor.project, editor.car_trailer_position.x, editor.car_trailer_position.z) == id
    postale_on_island :=
        terrain.island_at(&editor.project, editor.postale.body.position.x, editor.postale.body.position.z) == id
    libellula_on_island :=
        terrain.island_at(&editor.project, editor.libellula.body.position.x, editor.libellula.body.position.z) == id
    rondine_on_island :=
        terrain.island_at(&editor.project, editor.rondine.body.position.x, editor.rondine.body.position.z) == id
    attendant_on_island :=
        terrain.island_at(&editor.project, editor.attendant_position.x, editor.attendant_position.z) == id
    gerta_on_island := terrain.island_at(&editor.project, editor.gerta_position.x, editor.gerta_position.z) == id

    if player_on_island {
        editor.player.position.x += dx
        editor.player.position.z += dz
        editor.pilot.position.x += dx
        editor.pilot.position.z += dz
    }
    if car_on_island {
        island_translate_vehicle(&editor.car, dx, dz)
        car_physics_teleport(editor)
    }
    if trailer_on_island {
        editor.car_trailer_position.x += dx
        editor.car_trailer_position.z += dz
    }
    if postale_on_island {
        editor.postale.body.position.x += dx
        editor.postale.body.position.z += dz
        island_translate_vehicle(&editor.postale.vehicle, dx, dz)
    }
    if libellula_on_island {
        editor.libellula.body.position.x += dx
        editor.libellula.body.position.z += dz
        island_translate_vehicle(&editor.libellula.vehicle, dx, dz)
    }
    if rondine_on_island {
        editor.rondine.body.position.x += dx
        editor.rondine.body.position.z += dz
        island_translate_vehicle(&editor.rondine.vehicle, dx, dz)
    }
    if attendant_on_island {
        editor.attendant_position.x += dx
        editor.attendant_position.z += dz
    }
    if gerta_on_island {
        editor.gerta_position.x += dx
        editor.gerta_position.z += dz
    }
    boats_moved := false
    for &agent in editor.boat_traffic.agents[:editor.boat_traffic.count] {
        anchor := island_boat_owner_position(&agent)
        if terrain.island_at(&editor.project, anchor.x, anchor.y) != id do continue
        island_translate_boat_agent(&agent, dx, dz)
        boats_moved = true
    }
    if boats_moved do gameplay_physics_rebuild_boats(editor)

    if terrain.island_at(&editor.project, editor.postale.spawn_position.x, editor.postale.spawn_position.z) == id {
        editor.postale.spawn_position.x += dx
        editor.postale.spawn_position.z += dz
    }
    if terrain.island_at(&editor.project, editor.libellula.spawn_position.x, editor.libellula.spawn_position.z) == id {
        editor.libellula.spawn_position.x += dx
        editor.libellula.spawn_position.z += dz
    }
    if terrain.island_at(&editor.project, editor.rondine.spawn_position.x, editor.rondine.spawn_position.z) == id {
        editor.rondine.spawn_position.x += dx
        editor.rondine.spawn_position.z += dz
    }
    vehicles.sync_driver(&editor.pilot)
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

editor_island_translate_architecture_plan :: proc(editor: ^Editor, id: terrain.Island_ID, dx, dz: f32) {
    plan := &editor.architecture_city_plan
    for &structure in plan.structures[:plan.count] {
        if terrain.island_at(&editor.project, structure.center_x, structure.center_z) != id do continue
        island_translate_structure_value(&structure, dx, dz)
    }
    for &parcel in plan.parcels[:plan.parcel_count] {
        center := [2]f32{}
        for corner in parcel.corners do center += corner
        center /= f32(len(parcel.corners))
        if terrain.island_at(&editor.project, center.x, center.y) != id do continue
        for &corner in parcel.corners do island_translate_pair(&corner, dx, dz)
    }
    for &alley in plan.alleys[:plan.alley_count] {
        if terrain.island_at(&editor.project, alley.start_x, alley.start_z) == id {
            alley.start_x += dx
            alley.start_z += dz
            island_translate_pair(&alley.curve_control_from, dx, dz)
        }
        if terrain.island_at(&editor.project, alley.end_x, alley.end_z) == id {
            alley.end_x += dx
            alley.end_z += dz
            island_translate_pair(&alley.curve_control_to, dx, dz)
        }
    }
    for &lamp in plan.lamps[:plan.lamp_count] {
        if terrain.island_at(&editor.project, lamp.x, lamp.z) != id do continue
        lamp.x += dx
        lamp.z += dz
    }
}

editor_island_translate_fixture_positions :: proc(editor: ^Editor, id: terrain.Island_ID, dx, dz: f32) {
    notes_moved := false
    for &note in editor.notes[:editor.note_count] {
        if terrain.island_at(&editor.project, note.fallback_position.x, note.fallback_position.z) != id do continue
        note.fallback_position.x += dx
        note.fallback_position.z += dz
        notes_moved = true
    }
    if notes_moved do fixture_notes_mark_dirty()
    for &point in editor.curve_points[:editor.curve_point_count] {
        if terrain.island_at(&editor.project, point.x, point.z) != id do continue
        point.x += dx
        point.z += dz
    }
    for &obstacle in editor.sdf_obstacles[:editor.sdf_obstacle_count] {
        if terrain.island_at(&editor.project, obstacle.position.x, obstacle.position.z) != id do continue
        obstacle.position.x += dx
        obstacle.position.z += dz
    }
    if terrain.island_at(&editor.project, editor.crash_recovery_position.x, editor.crash_recovery_position.z) == id {
        editor.crash_recovery_position.x += dx
        editor.crash_recovery_position.z += dz
    }
    if terrain.island_at(
           &editor.project,
           editor.vehicle_paint_saved_postale_position.x,
           editor.vehicle_paint_saved_postale_position.z,
       ) ==
       id {
        editor.vehicle_paint_saved_postale_position.x += dx
        editor.vehicle_paint_saved_postale_position.z += dz
    }
    if terrain.island_at(
           &editor.project,
           editor.vehicle_paint_saved_libellula_position.x,
           editor.vehicle_paint_saved_libellula_position.z,
       ) ==
       id {
        editor.vehicle_paint_saved_libellula_position.x += dx
        editor.vehicle_paint_saved_libellula_position.z += dz
    }
}

editor_island_translate_effects :: proc(editor: ^Editor, id: terrain.Island_ID, dx, dz: f32) {
    for &particle in editor.vehicle_effects.dust[:editor.vehicle_effects.dust_count] {
        if terrain.island_at(&editor.project, particle.position.x, particle.position.z) != id do continue
        particle.position.x += dx
        particle.position.z += dz
    }
    for &particle in editor.wing_trails.particles[:editor.wing_trails.count] {
        if terrain.island_at(&editor.project, particle.position.x, particle.position.z) != id do continue
        particle.position.x += dx
        particle.position.z += dz
    }
    for &particle in editor.petal_effects.particles[:editor.petal_effects.count] {
        if terrain.island_at(&editor.project, particle.position.x, particle.position.z) != id do continue
        particle.position.x += dx
        particle.position.z += dz
    }
}

editor_island_translate_dependent_state :: proc(editor: ^Editor, id: terrain.Island_ID, dx, dz: f32) {
    editor_island_translate_mobile_actors(editor, id, dx, dz)
    editor_island_translate_architecture_plan(editor, id, dx, dz)
    editor_island_translate_fixture_positions(editor, id, dx, dz)
    editor_island_translate_effects(editor, id, dx, dz)
}

editor_island_center_separated :: proc(editor: ^Editor, id: terrain.Island_ID, x, z: f32) -> bool {
    other := id == .West ? terrain.Island_ID.East : terrain.Island_ID.West
    other_x, other_z, found := terrain.island_center(&editor.project, other)
    if !found do return false
    radius_x := (terrain.DEFAULT_GENERATED_ISLAND_HALF_X + 180) * 2
    radius_z := (terrain.DEFAULT_GENERATED_ISLAND_HALF_Z + 180) * 2
    nx, nz := (x - other_x) / radius_x, (z - other_z) / radius_z
    return nx * nx + nz * nz >= 1
}

editor_island_set_center :: proc(editor: ^Editor, id: terrain.Island_ID, x, z: f32) -> bool {
    if editor == nil ||
       id == .World ||
       !terrain.island_center_valid(x, z) ||
       !editor_island_center_separated(editor, id, x, z) {
        return false
    }
    old_x, old_z, found := terrain.island_center(&editor.project, id)
    if !found do return false
    dx, dz := x - old_x, z - old_z
    if dx == 0 && dz == 0 do return true

    editor_island_translate_dependent_state(editor, id, dx, dz)

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
    editor.terrain_revision += 1
    world_renderer_fixture_invalidate(editor)
    gameplay_physics_rebuild_structures(editor)
    gameplay_physics_sync_revisions(editor)
    return true
}
