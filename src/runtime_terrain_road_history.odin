package main

import architecture "../packages/architecture"
import boats "../packages/boats"
import libellula_game "../packages/libellula"
import postale_game "../packages/postale"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

terrain_history_push_undo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.terrain_undo_count < TERRAIN_HISTORY_CAPACITY {
        terrain_history_capture(editor, &editor.terrain_undo[editor.terrain_undo_count])
        editor.terrain_undo_count += 1
    } else {
        for index in 1 ..< TERRAIN_HISTORY_CAPACITY {
            editor.terrain_undo[index - 1] = editor.terrain_undo[index]
        }
        terrain_history_capture(editor, &editor.terrain_undo[TERRAIN_HISTORY_CAPACITY - 1])
    }
    editor.terrain_redo_count = 0
    road_design_history_clear(&editor.road_design_redo, &editor.road_design_redo_count)
}

terrain_history_push_redo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.terrain_redo_count < TERRAIN_HISTORY_CAPACITY {
        terrain_history_capture(editor, &editor.terrain_redo[editor.terrain_redo_count])
        editor.terrain_redo_count += 1
    } else {
        for index in 1 ..< TERRAIN_HISTORY_CAPACITY {
            editor.terrain_redo[index - 1] = editor.terrain_redo[index]
        }
        terrain_history_capture(editor, &editor.terrain_redo[TERRAIN_HISTORY_CAPACITY - 1])
    }
}

terrain_undo :: proc(editor: ^Editor) {
    if editor == nil || editor.terrain_undo_count <= 0 do return
    terrain_history_push_redo(editor)
    editor.terrain_undo_count -= 1
    terrain_history_restore(editor, &editor.terrain_undo[editor.terrain_undo_count])
}

terrain_redo :: proc(editor: ^Editor) {
    if editor == nil || editor.terrain_redo_count <= 0 do return
    if editor.terrain_undo_count < TERRAIN_HISTORY_CAPACITY {
        terrain_history_capture(editor, &editor.terrain_undo[editor.terrain_undo_count])
        editor.terrain_undo_count += 1
    } else {
        for index in 1 ..< TERRAIN_HISTORY_CAPACITY {
            editor.terrain_undo[index - 1] = editor.terrain_undo[index]
        }
        terrain_history_capture(editor, &editor.terrain_undo[TERRAIN_HISTORY_CAPACITY - 1])
    }
    editor.terrain_redo_count -= 1
    terrain_history_restore(editor, &editor.terrain_redo[editor.terrain_redo_count])
}

terrain_file_feedback :: proc(editor: ^Editor, message: cstring) {
    if editor == nil do return
    editor.terrain_file_status = message
    editor.terrain_file_status_until = f32(canvas2d.GetTime()) + 2
}

terrain_project_save :: proc(editor: ^Editor) {
    map_editor_save(editor)
}

architecture_regenerate_all :: proc(editor: ^Editor) {
    if editor == nil do return
    bounds := architecture.city_density_bounds(&editor.project.city_density)
    if !bounds.valid {
        architecture.clear_architecture(&editor.project)
        architecture.city_plan_destroy(&editor.architecture_city_plan)
        return
    }
    for island in editor.project.island_transforms {
        if island.current_x == island.source_x && island.current_z == island.source_z do continue
        half := f32(terrain.WORLD_SIZE_METERS * .5)
        bounds = {
            min_x = -half,
            min_z = -half,
            max_x = half,
            max_z = half,
            valid = true,
        }
        break
    }
    plan := architecture.city_plan_density(&editor.project, &editor.project.city_density, bounds)
    _ = architecture.city_commit_plan(&editor.project, &editor.project.city_density, bounds, &plan)
    architecture.city_plan_replace(&editor.architecture_city_plan, plan)
}

regenerate_default_map :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.default_map_regeneration_seeds = terrain.next_default_island_seeds(editor.default_map_regeneration_seeds)
    editor.default_map_regeneration_stage = .Terrain
    editor.default_map_regeneration_loading_ready = false
    editor.default_map_regeneration_active = true
    editor.tweak_panel_visible = false
}

default_map_respawn_mobile_actors :: proc(editor: ^Editor) {
    if editor == nil do return

    // Regeneration replaces the terrain beneath every mobile actor. Return the
    // player and locally controlled vehicles to spawn points derived from the
    // new map without resetting story progress or aircraft unlocks.
    player_place(editor, runway_spawn_position(editor), .Reset)
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(editor.player.position, editor.camera)
    third_person.camera_set_pose(&editor.cameras, .Player, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Player)
    editor.camera_target_lock = false
    editor.flight_control = {}

    previous_fleet := editor.aircraft
    editor.postale = postale_game.new_runtime(postale_spawn_position(editor))
    libellula_spawn := libellula_spawn_position(editor)
    editor.libellula = libellula_game.new_runtime({libellula_spawn.x, libellula_spawn.y, libellula_spawn.z})
    editor.rondine = rondine_game.new_runtime(rondine_spawn_position(editor))
    editor.aircraft = {}
    vehicles.aircraft_fleet_add(
        &editor.aircraft,
        .Postale,
        "Postale",
        &editor.postale.vehicle,
        aircraft_kind_was_available(&previous_fleet, .Postale),
    )
    when LIBELLULA_MK1_ENABLED {
        vehicles.aircraft_fleet_add(
            &editor.aircraft,
            .Libellula,
            "Libellula",
            &editor.libellula.vehicle,
            aircraft_kind_was_available(&previous_fleet, .Libellula),
        )
    }
    vehicles.aircraft_fleet_add(
        &editor.aircraft,
        .Libellula_Mk2,
        "Libellula Mk2",
        &editor.libellula.vehicle,
        aircraft_kind_was_available(&previous_fleet, .Libellula_Mk2),
    )
    vehicles.aircraft_fleet_add(
        &editor.aircraft,
        .Rondine,
        "Rondine",
        &editor.rondine.vehicle,
        aircraft_kind_was_available(&previous_fleet, .Rondine),
    )
    if vehicles.aircraft_fleet_slot(&editor.aircraft, previous_fleet.active) != nil {
        editor.aircraft.active = previous_fleet.active
    }
    editor.postale_visible = true
    editor.libellula_visible = true
    editor.rondine_visible = false
    editor.libellula.vehicle.locked = true
    editor.rondine.vehicle.locked = true
    editor.aircraft_fixed_accumulator = 0
    editor.aircraft_previous_body_valid = false

    editor.car = vehicles.default_vehicle(car_spawn_position(editor))
    editor.car.interaction_radius = 2.2
    editor.car.exit_distance = 1.1
    editor.car.yaw_radians = -math.PI * .5
    editor.car_drive = {}
    editor.car_wheels = {}
    editor.car_impact_detector = {}
    editor.car_audio_damage = 0
    editor.car_audio_gearbox = {}
    editor.car_physics_accumulator = 0
    car_physics_teleport(editor)
    editor.car_trailer = {}
    editor.car_trailer_attached = true
    editor.car_trailer_position = editor.car.position
    editor.car_trailer_yaw = editor.car.yaw_radians

    editor.boat_traffic = new_world_boat_traffic(&editor.project)
    editor.ocean_traffic = boats.new_ocean_traffic()
    gameplay_physics_rebuild_boats(editor)
}

aircraft_kind_was_available :: proc(fleet: ^vehicles.Aircraft_Fleet, kind: vehicles.Aircraft_Kind) -> bool {
    slot := vehicles.aircraft_fleet_slot(fleet, kind)
    return slot != nil && slot.available
}

default_map_regeneration_progress :: proc(editor: ^Editor) -> (f32, cstring) {
    if editor == nil do return 0, "Preparing a new archipelago"
    switch editor.default_map_regeneration_stage {
    case .Terrain:
        return .08, "Generating new islands"
    case .Marinas:
        return .42, "Surveying coasts and building marinas"
    case .Towns:
        return .67, "Laying out towns and roads"
    case .Finalize:
        return .92, "Rebuilding the world"
    }
    return 0, "Preparing a new archipelago"
}

default_map_regeneration_step :: proc(editor: ^Editor) {
    if editor == nil || !editor.default_map_regeneration_active do return
    // Present at least one loading frame before beginning the first expensive
    // phase so regeneration never appears to freeze on the Tweaks button.
    if !editor.default_map_regeneration_loading_ready {
        editor.default_map_regeneration_loading_ready = true
        return
    }
    switch editor.default_map_regeneration_stage {
    case .Terrain:
        terrain.init_project_seeded(&editor.project, editor.default_map_regeneration_seeds)
        editor.terrain_undo_count = 0
        editor.terrain_redo_count = 0
        editor.default_map_regeneration_stage = .Marinas
    case .Marinas:
        seed_default_island_marinas_seeded(editor, editor.default_map_regeneration_seeds)
        editor.default_map_regeneration_stage = .Towns
    case .Towns:
        seed_default_island_towns_seeded(editor, editor.default_map_regeneration_seeds)
        editor.default_map_regeneration_stage = .Finalize
    case .Finalize:
        west_airport_x, west_airport_z := terrain.default_airport_center_for_project(&editor.project, -1)
        east_airport_x, east_airport_z := terrain.default_airport_center_for_project(&editor.project, 1)
        editor.attendant_position = {
            east_airport_x,
            terrain.sample_surface_height(&editor.project, 0, east_airport_x, east_airport_z),
            east_airport_z,
        }
        editor.gerta_position = {
            west_airport_x,
            terrain.sample_surface_height(&editor.project, 0, west_airport_x, west_airport_z),
            west_airport_z,
        }
        world_renderer_fixture_invalidate(editor)
        gameplay_physics_rebuild_structures(editor)
        gameplay_physics_sync_revisions(editor)
        default_map_respawn_mobile_actors(editor)
        editor.default_map_regeneration_active = false
        terrain_file_feedback(editor, "DEFAULT MAP REGENERATED")
    }
}

terrain_project_load :: proc(editor: ^Editor) {
    map_editor_load(editor)
}

formation_kind_name :: proc(kind: terrain.Formation_Kind) -> cstring {
    switch kind {
    case .Box:
        return "BOX"
    case .Rock:
        return "ROCK"
    case .Spire:
        return "SPIRE"
    case .Mountain:
        return "MOUNTAIN"
    case .Ridge:
        return "RIDGE"
    case .Cliff:
        return "CLIFF"
    case .Foliage:
        return "FOLIAGE"
    case .Architecture:
        return "ADRIATIC NODES"
    case .Ruins:
        return "RUINS"
    }
    return "FORMATION"
}

structure_cycle_kind :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.structure_auto_kind = false
    if editor.structure_selected >= 0 && !editor.structure_placing {
        structure_history_push_undo(editor)
        structure := &editor.project.structures[editor.structure_selected]
        structure.kind = terrain.formation_kind_next(structure.kind)
        editor.structure_kind = structure.kind
        editor.project.revision += 1
    } else {
        editor.structure_kind = terrain.formation_kind_next(editor.structure_kind)
        if editor.structure_placing do editor.structure_preview.kind = editor.structure_kind
    }
}

structure_update_preview_kind :: proc(editor: ^Editor) {
    if editor == nil || !editor.structure_placing do return
    if editor.authoring_tool == .Foliage {
        editor.structure_preview.kind = .Foliage
    } else if editor.structure_force_box {
        editor.structure_preview.kind = .Box
    } else if editor.structure_cliff_mode {
        editor.structure_preview.kind = .Cliff
    } else if editor.structure_auto_kind {
        editor.structure_preview.kind = terrain.formation_kind_for_gesture(
            editor.structure_preview.width,
            editor.structure_preview.depth,
            editor.structure_preview.height,
        )
    } else {
        editor.structure_preview.kind = editor.structure_kind
    }
}

structure_editor_snap :: proc(value: f32, editor: ^Editor) -> f32 {
    if shift_key_down() do return value
    return terrain.snap_to_grid(value, editor.project.levels[0].cell_size)
}

structure_update_base :: proc(editor: ^Editor, structure: ^terrain.Structure) {
    if editor == nil || structure == nil do return
    structure.base_y = terrain.sample_surface_height(&editor.project, 0, structure.center_x, structure.center_z)
}

capture_add_formation :: proc(editor: ^Editor, x, z, width, depth, height: f32, kind: terrain.Formation_Kind) -> int {
    if editor == nil do return -1
    structure := terrain.structure_make(x, z, width, depth, 0, height)
    structure.kind = kind
    structure.base_y = terrain.sample_surface_height(&editor.project, 0, x, z)
    return terrain.add_structure(&editor.project, structure)
}

structure_commit_placement :: proc(editor: ^Editor, end_x, end_z: f32) -> int {
    if editor == nil do return -1
    if editor.structure_preview.kind == .Architecture {
        editor.structure_preview.height = architecture.facade_fitted_height(editor.structure_preview.height)
    }
    index := terrain.add_structure(&editor.project, editor.structure_preview)
    last_index := index
    if !editor.structure_scatter_mode || index < 0 do return index

    dx := end_x - editor.structure_anchor_x
    dz := end_z - editor.structure_anchor_z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= 0 do return index
    direction_x, direction_z := dx / length, dz / length
    perpendicular_x, perpendicular_z := -direction_z, direction_x
    cell := editor.project.levels[0].cell_size
    for cluster_index in 0 ..< editor.structure_scatter_count - 1 {
        offset := f32(cluster_index) - f32(editor.structure_scatter_count - 2) * .5
        copy := editor.structure_preview
        copy.center_x += direction_x * offset * length * .22
        copy.center_z += direction_z * offset * length * .22
        jitter := f32(math.sin(f64(f32(cluster_index) * 2.31 + f32(editor.project.next_structure_id) * .17)))
        copy.center_x += perpendicular_x * jitter * length * .10
        copy.center_z += perpendicular_z * jitter * length * .10
        copy.width = max(cell, copy.width * (.58 + f32(cluster_index % 2) * .12))
        copy.depth = max(cell, copy.depth * (.58 + f32((cluster_index + 1) % 2) * .12))
        copy.height = max(cell, copy.height * (.72 + f32(cluster_index) * .06))
        copy.base_y = terrain.sample_surface_height(&editor.project, 0, copy.center_x, copy.center_z)
        if editor.authoring_tool == .Foliage {
            copy.kind = .Foliage
        } else if !editor.structure_force_box && !editor.structure_cliff_mode {
            copy.kind = terrain.formation_kind_for_gesture(copy.width, copy.depth, copy.height)
        }
        last_index = terrain.add_structure(&editor.project, copy)
    }
    return last_index
}

formation_brush_is_target :: proc(editor: ^Editor, kind: terrain.Formation_Kind) -> bool {
    if editor.authoring_tool == .Foliage do return kind == .Foliage
    if editor.rock_placement_mode do return kind == .Rock
    return kind != .Foliage && kind != .Architecture
}

rock_tool_color :: proc(editor: ^Editor) -> [4]u8 {
    if editor != nil {
        switch clamp(editor.rock_material_variant, 0, 2) {
        case 1:
            return {112, 116, 113, 254}
        case 2:
            return {61, 65, 66, 254}
        case 0:
        }
    }
    return {176, 164, 133, 254}
}

formation_brush_stamp :: proc(editor: ^Editor, world_x, world_z: f32, erase: bool) {
    if editor == nil do return
    radius := editor.formation_brush_radius
    if erase {
        for index := editor.project.structure_count - 1; index >= 0; index -= 1 {
            structure := editor.project.structures[index]
            if !formation_brush_is_target(editor, structure.kind) do continue
            dx, dz := structure.center_x - world_x, structure.center_z - world_z
            if dx * dx + dz * dz <= radius * radius {
                terrain.remove_structure(&editor.project, index)
            }
        }
        return
    }
    cell := editor.project.levels[0].cell_size
    stamp_count := max(1, 1 + int(editor.formation_brush_strength * 3))
    group_id := editor.formation_brush_group_id
    if group_id == 0 do group_id = editor.project.next_structure_id
    for stamp in 0 ..< stamp_count {
        // Stable noise keeps a stroke varied without making undo/redo or a
        // saved project depend on the runtime random-number stream.
        seed := f32(stamp) * 17.13 + world_x * .071 + world_z * .113 + f32(editor.project.next_structure_id) * .037
        radial_noise := f32(math.sin(f64(seed * 1.71))) * .5 + .5
        angle_noise := f32(math.sin(f64(seed * 2.43 + 4.1))) * .5 + .5
        radial_power := .55 + editor.formation_brush_hardness * 1.8
        radial := radius * f32(math.pow(f64(radial_noise), f64(radial_power)))
        angle := angle_noise * math.PI * 2
        x := world_x + math.cos(angle) * radial
        z := world_z + math.sin(angle) * radial
        size_noise := f32(math.sin(f64(seed * 3.19 + 1.7))) * .5 + .5
        width, depth, height: f32
        if editor.authoring_tool == .Foliage {
            width = max(cell, radius * (.18 + size_noise * .18))
            depth = max(cell, width * (.72 + size_noise * .42))
            height = max(cell, width * (.75 + size_noise * .8))
        } else {
            width = max(cell, radius * (.14 + size_noise * .16))
            depth = max(cell, width * (.72 + size_noise * .55))
            height = max(cell, radius * (.22 + size_noise * .44))
        }
        structure := terrain.structure_make(x, z, width, depth, 0, height)
        structure.rotation = angle + f32(math.sin(f64(seed * 1.13))) * .7
        structure.group_id = group_id
        structure.base_y = terrain.sample_surface_height(&editor.project, 0, x, z)
        if editor.authoring_tool == .Foliage {
            structure.kind = .Foliage
        } else if editor.rock_placement_mode {
            structure.kind = .Rock
            structure.color = rock_tool_color(editor)
        } else if editor.structure_auto_kind {
            structure.kind = terrain.formation_kind_for_gesture(width, depth, height)
        } else {
            structure.kind = editor.structure_kind
        }
        if editor.authoring_tool == .Foliage {
            if terrain.add_or_merge_foliage(&editor.project, structure, cell * .5) < 0 do return
        } else {
            merged_index := terrain.add_or_merge_formation(
                &editor.project,
                structure,
                cell * .5,
                editor.structure_auto_kind,
            )
            if merged_index < 0 do return
        }
    }
}

formation_brush_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || editor.tool != .Structure do return
    if editor.selection_tool_active do return
    if editor.authoring_tool != .Formations && editor.authoring_tool != .Foliage do return
    if editor.authoring_tool == .Foliage && editor.plant_stamp_mode == .Climbing do return
    if editor.authoring_tool == .Foliage && editor.foliage_hedgerow_mode do return
    if !cursor_hit {
        if canvas2d.IsMouseButtonReleased(.LEFT) || canvas2d.IsMouseButtonReleased(.RIGHT) {
            editor.formation_brush_painting = false
            editor.formation_brush_group_id = 0
        }
        return
    }
    pressed := canvas2d.IsMouseButtonPressed(.LEFT) || canvas2d.IsMouseButtonPressed(.RIGHT)
    down := canvas2d.IsMouseButtonDown(.LEFT) || canvas2d.IsMouseButtonDown(.RIGHT)
    erase := canvas2d.IsMouseButtonDown(.RIGHT)
    if pressed {
        structure_history_push_undo(editor)
        editor.formation_brush_group_id = editor.project.next_structure_id
        editor.formation_brush_painting = true
        editor.formation_brush_last_x, editor.formation_brush_last_z = world_x, world_z
        formation_brush_stamp(editor, world_x, world_z, erase)
    }
    if editor.formation_brush_painting && down && !pressed {
        dx, dz := world_x - editor.formation_brush_last_x, world_z - editor.formation_brush_last_z
        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
        step := max(editor.formation_brush_radius * .30, terrain.BASE_CELL_SIZE * .45)
        stamps := int(math.floor(f64(distance / step)))
        if stamps > 0 {
            direction_x, direction_z := dx / distance, dz / distance
            for stamp in 1 ..= stamps {
                travel := f32(stamp) * step
                x := editor.formation_brush_last_x + direction_x * travel
                z := editor.formation_brush_last_z + direction_z * travel
                formation_brush_stamp(editor, x, z, erase)
            }
            // Keep the unpainted tail so sub-step mouse movement accumulates
            // across frames instead of producing a stamp on every frame.
            editor.formation_brush_last_x += direction_x * f32(stamps) * step
            editor.formation_brush_last_z += direction_z * f32(stamps) * step
        }
    }
    if editor.formation_brush_painting &&
       (canvas2d.IsMouseButtonReleased(.LEFT) || canvas2d.IsMouseButtonReleased(.RIGHT)) {
        editor.formation_brush_painting = false
        editor.formation_brush_group_id = 0
    }
}

curve_segment_structure :: proc(editor: ^Editor, start, end: Curve_Point) -> terrain.Structure {
    dx, dz := end.x - start.x, end.z - start.z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    cell := editor.project.levels[0].cell_size
    structure := terrain.structure_make(
        (start.x + end.x) * .5,
        (start.z + end.z) * .5,
        max(length + cell * .35, cell),
        max(editor.curve_width, cell),
        0,
        max(editor.curve_height, cell),
    )
    structure.rotation = math.atan2(dz, dx)
    structure.kind = editor.curve_cliff_mode ? .Cliff : .Ridge
    structure.base_y = terrain.sample_surface_height(&editor.project, 0, structure.center_x, structure.center_z)
    return structure
}

curve_commit :: proc(editor: ^Editor) -> int {
    if editor == nil || editor.curve_point_count < 2 do return -1
    last_index := -1
    // Keep all segments from one freehand ridge in the same edit group so
    // post-placement sizing acts on the ridge as a whole.
    group_id := editor.project.next_structure_id
    segment_start := editor.curve_points[0]
    segment_end := editor.curve_points[1]
    for index in 2 ..< editor.curve_point_count {
        next := editor.curve_points[index]
        if terrain.formation_segments_can_merge(
            segment_start.x,
            segment_start.z,
            segment_end.x,
            segment_end.z,
            next.x,
            next.z,
            CURVE_MERGE_MINIMUM_COSINE,
        ) {
            segment_end = next
            continue
        }
        segment := curve_segment_structure(editor, segment_start, segment_end)
        segment.group_id = group_id
        last_index = terrain.add_structure(&editor.project, segment)
        if last_index < 0 do return last_index
        segment_start = segment_end
        segment_end = next
    }
    segment := curve_segment_structure(editor, segment_start, segment_end)
    segment.group_id = group_id
    last_index = terrain.add_structure(&editor.project, segment)
    return last_index
}

cliff_commit :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.curve_point_count < 2 do return false
    points: [CURVE_POINT_CAPACITY]terrain.Cliff_Point
    for point, index in editor.curve_points[:editor.curve_point_count] {
        points[index] = {point.x, point.z}
    }
    return terrain.apply_cliff_stroke(
        &editor.project,
        points[:editor.curve_point_count],
        editor.curve_width,
        editor.curve_height,
        editor.cliff_elevation_mode,
    )
}

curve_reset :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.curve_point_count = 0
    editor.curve_drawing = false
}

road_node_at :: proc(editor: ^Editor, x, z: f32) -> int {
    if editor == nil do return -1
    graph := &editor.project.road_graph
    hit_radius := max(editor.road_width, terrain.BASE_CELL_SIZE * .35)
    best_distance := hit_radius * hit_radius
    best := -1
    for node, index in graph.nodes[:graph.node_count] {
        dx, dz := x - node.position.x, z - node.position.z
        distance := dx * dx + dz * dz
        if distance <= best_distance {
            best_distance = distance
            best = index
        }
    }
    return best
}

road_handle_at :: proc(editor: ^Editor, x, z: f32) -> (edge_index, handle_index: int) {
    edge_index, handle_index = -1, -1
    if editor == nil || editor.road_selected_node < 0 do return
    graph := &editor.project.road_graph
    cursor := roads.Vec3{x, terrain.sample_surface_height(&editor.project, 0, x, z), z}
    // Match the snap affordances: the handle remains easy to acquire at an
    // overview zoom without becoming an enormous target close to the road.
    hit_radius := max(editor.road_width * .55, road_snap_world_radius(editor, cursor) * .46)
    best_distance := hit_radius * hit_radius
    for edge, index in graph.edges[:graph.edge_count] {
        if edge.from != editor.road_selected_node && edge.to != editor.road_selected_node do continue
        // Expose only the tangent owned by the selected junction. The far
        // control belongs to the opposite node and becomes editable when that
        // node is selected, matching a road-tool gizmo rather than a Bézier
        // debugger.
        handle := edge.from == editor.road_selected_node ? 0 : 1
        candidate := handle == 0 ? edge.control_from : edge.control_to
        dx, dz := x - candidate.x, z - candidate.z
        distance := dx * dx + dz * dz
        if distance <= best_distance {
            best_distance = distance
            edge_index = index
            handle_index = handle
        }
    }
    return
}

road_mode_name :: proc(mode: Road_Construction_Mode) -> string {
    switch mode {
    case .Straight:
        return "STRAIGHT"
    case .Terrain_Route:
        return "TERRAIN"
    case .Authored_Curve:
        return "CURVE"
    }
    return "TERRAIN ROUTE"
}
