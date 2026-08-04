package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import chase_camera "../packages/chase_camera"
import dialogue "../packages/dialogue"
import roads "../packages/roads"
import rondine_game "../packages/rondine"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

road_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.road_mode do return
    if editor.road_design_redesign_active {
        _ = road_design_preview_step(editor)
        if canvas2d.IsMouseButtonPressed(.RIGHT) {
            road_preview_clear(editor)
            editor.road_construction_phase = .Choose_End
        } else if canvas2d.IsMouseButtonReleased(.LEFT) {
            _ = road_preview_commit(editor)
        }
        return
    }
    graph := &editor.project.road_graph
    editor.road_hover_edge, editor.road_hover_handle = -1, -1
    if cursor_hit &&
       editor.road_drag_edge < 0 &&
       editor.road_construction_phase != .Drag_Start_Tangent &&
       editor.road_construction_phase != .Drag_End_Tangent {
        editor.road_hover_edge, editor.road_hover_handle = road_handle_at(editor, world_x, world_z)
    }
    if editor.road_construction_phase == .Drag_Start_Tangent {
        if canvas2d.IsMouseButtonDown(.LEFT) && cursor_hit {
            editor.road_preview_control_from = {
                world_x,
                terrain.sample_surface_height(&editor.project, 0, world_x, world_z) + .08,
                world_z,
            }
        }
        if canvas2d.IsMouseButtonReleased(.LEFT) {
            editor.road_construction_phase = .Choose_End
            editor.road_preview_cell_valid = false
        }
        return
    }
    if editor.road_construction_phase == .Drag_End_Tangent {
        if canvas2d.IsMouseButtonDown(.LEFT) && cursor_hit {
            editor.road_preview_control_to = {
                world_x,
                terrain.sample_surface_height(&editor.project, 0, world_x, world_z) + .08,
                world_z,
            }
            road_preview_rebuild(editor, editor.road_preview_snap)
        }
        if canvas2d.IsMouseButtonReleased(.LEFT) do _ = road_preview_commit(editor)
        return
    }
    if editor.road_drag_node >= 0 {
        road_preview_clear(editor)
        if canvas2d.IsMouseButtonDown(.LEFT) && cursor_hit {
            node := &graph.nodes[editor.road_drag_node]
            snapped_x := structure_editor_snap(world_x, editor)
            snapped_z := structure_editor_snap(world_z, editor)
            dx, dz := snapped_x - node.position.x, snapped_z - node.position.z
            if dx != 0 || dz != 0 {
                if !editor.road_drag_node_moved {
                    structure_history_push_undo(editor)
                    editor.road_drag_node_moved = true
                }
                node.position.x = snapped_x
                node.position.z = snapped_z
                node.position.y = terrain.sample_surface_height(&editor.project, 0, snapped_x, snapped_z)
                for &edge in graph.edges[:graph.edge_count] {
                    if edge.from == editor.road_drag_node {
                        edge.control_from.x += dx
                        edge.control_from.z += dz
                        edge.control_from.y =
                            terrain.sample_surface_height(
                                &editor.project,
                                0,
                                edge.control_from.x,
                                edge.control_from.z,
                            ) +
                            .08
                    }
                    if edge.to == editor.road_drag_node {
                        edge.control_to.x += dx
                        edge.control_to.z += dz
                        edge.control_to.y =
                            terrain.sample_surface_height(&editor.project, 0, edge.control_to.x, edge.control_to.z) +
                            .08
                    }
                }
                editor.project.revision += 1
            }
        }
        if canvas2d.IsMouseButtonReleased(.LEFT) {
            dragged_node := editor.road_drag_node
            if !editor.road_drag_node_moved &&
               editor.road_drag_node_previous_selection >= 0 &&
               editor.road_drag_node_previous_selection != dragged_node {
                if roads.edge_between(graph, editor.road_drag_node_previous_selection, dragged_node) < 0 {
                    structure_history_push_undo(editor)
                    _ = road_connect(editor, editor.road_drag_node_previous_selection, dragged_node)
                    editor.project.revision += 1
                }
            }
            editor.road_selected_node = dragged_node
            editor.road_drag_node = -1
            editor.road_drag_node_previous_selection = -1
            editor.road_drag_node_moved = false
        }
        return
    }
    if editor.road_drag_edge >= 0 {
        road_preview_clear(editor)
        if canvas2d.IsMouseButtonDown(.LEFT) && cursor_hit {
            edge := &graph.edges[editor.road_drag_edge]
            snapped_x := structure_editor_snap(world_x, editor)
            snapped_z := structure_editor_snap(world_z, editor)
            point := roads.Vec3 {
                snapped_x,
                terrain.sample_surface_height(&editor.project, 0, snapped_x, snapped_z) + .08,
                snapped_z,
            }
            changed := false
            if editor.road_drag_handle == 0 {
                if edge.control_from != point {
                    if !editor.road_drag_handle_moved do structure_history_push_undo(editor)
                    edge.control_from = point
                    editor.road_drag_handle_moved = true
                    changed = true
                }
            } else {
                if edge.control_to != point {
                    if !editor.road_drag_handle_moved do structure_history_push_undo(editor)
                    edge.control_to = point
                    editor.road_drag_handle_moved = true
                    changed = true
                }
            }
            if changed do editor.project.revision += 1
        }
        if canvas2d.IsMouseButtonReleased(.LEFT) {
            editor.road_drag_edge = -1
            editor.road_drag_handle = -1
            editor.road_drag_handle_moved = false
        }
        return
    }
    if canvas2d.IsMouseButtonPressed(.RIGHT) {
        if editor.road_construction_phase == .Drag_Start_Tangent ||
           editor.road_construction_phase == .Drag_End_Tangent {
            editor.road_construction_phase = .Choose_End
            road_preview_clear(editor)
            return
        }
        editor.road_selected_node = -1
        editor.road_construction_phase = .Idle
        road_preview_clear(editor)
        return
    }
    if editor.road_construction_mode != .Authored_Curve || editor.road_construction_phase == .Choose_End {
        road_preview_update(editor, world_x, world_z, cursor_hit)
    }
    if !cursor_hit || !canvas2d.IsMouseButtonPressed(.LEFT) do return
    edge_index, handle_index := editor.road_hover_edge, editor.road_hover_handle
    if edge_index >= 0 {
        editor.road_drag_edge = edge_index
        editor.road_drag_handle = handle_index
        editor.road_drag_handle_moved = false
        return
    }
    clicked_node := road_node_at(editor, world_x, world_z)
    if clicked_node >= 0 {
        if editor.road_construction_mode == .Authored_Curve && editor.road_selected_node == clicked_node {
            editor.road_construction_phase = .Drag_Start_Tangent
            editor.road_preview_start = graph.nodes[clicked_node].position
            editor.road_preview_control_from = editor.road_preview_start
            road_preview_clear(editor)
            return
        }
        if editor.road_selected_node >= 0 &&
           editor.road_selected_node != clicked_node &&
           editor.road_preview_status == .Valid {
            if editor.road_construction_mode == .Authored_Curve {
                editor.road_construction_phase = .Drag_End_Tangent
                editor.road_preview_control_to = editor.road_preview_endpoint
            } else {
                _ = road_preview_commit(editor)
            }
            return
        }
        editor.road_drag_node = clicked_node
        editor.road_drag_node_previous_selection = editor.road_selected_node
        editor.road_drag_node_moved = false
        editor.road_selected_node = clicked_node
        return
    }
    if editor.road_selected_node >= 0 {
        if editor.road_preview_status != .Valid do return
        if editor.road_construction_mode == .Authored_Curve {
            editor.road_construction_phase = .Drag_End_Tangent
            editor.road_preview_control_to = editor.road_preview_endpoint
        } else {
            _ = road_preview_commit(editor)
        }
        return
    }
    structure_history_push_undo(editor)
    new_node := road_add_node(editor, world_x, world_z)
    if new_node >= 0 {
        editor.road_selected_node = new_node
        editor.road_construction_phase = editor.road_construction_mode == .Authored_Curve ? .Idle : .Choose_End
        editor.project.revision += 1
    }
    road_preview_clear(editor)
}

editor_cancel_interaction :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.terrain_sculpt.session.active {
        terrain_sculpt_cancel(editor)
        return
    }
    if editor.road_mode && editor.road_selected_node >= 0 && editor.road_construction_phase != .Idle {
        editor.road_construction_phase = .Idle
        editor.road_preview_control_from = {}
        editor.road_preview_control_to = {}
        road_preview_clear(editor)
        return
    }
    editor.structure_placing = false
    editor.structure_moving = false
    editor.architecture_painting = false
    architecture.city_plan_destroy(&editor.architecture_preview_plan)
    editor.architecture_dirty_bounds = {}
    editor.road_selected_node = -1
    editor.road_construction_phase = .Idle
    road_preview_clear(editor)
    editor.road_drag_node = -1
    editor.road_drag_node_previous_selection = -1
    editor.road_drag_node_moved = false
    editor.road_drag_edge = -1
    editor.road_drag_handle = -1
    editor.road_hover_edge = -1
    editor.road_hover_handle = -1
    editor.road_drag_handle_moved = false
    curve_reset(editor)
}

curve_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || editor.tool != .Structure || !editor.curve_mode do return
    if !cursor_hit {
        if canvas2d.IsMouseButtonReleased(.LEFT) || canvas2d.IsMouseButtonReleased(.RIGHT) do curve_reset(editor)
        return
    }
    cell := editor.project.levels[0].cell_size
    if canvas2d.IsMouseButtonPressed(.LEFT) || canvas2d.IsMouseButtonPressed(.RIGHT) {
        // RIDGE and CLIFF are persistent palette tools. Do not derive the
        // profile from the button used to begin the stroke, or a normal
        // left-click immediately turns the selected CLIFF tool into RIDGE.
        editor.curve_point_count = 1
        editor.curve_points[0] = {structure_editor_snap(world_x, editor), structure_editor_snap(world_z, editor)}
        editor.curve_drawing = true
    }
    if editor.curve_drawing && (canvas2d.IsMouseButtonDown(.LEFT) || canvas2d.IsMouseButtonDown(.RIGHT)) {
        if editor.curve_point_count < CURVE_POINT_CAPACITY {
            last := editor.curve_points[editor.curve_point_count - 1]
            x, z := structure_editor_snap(world_x, editor), structure_editor_snap(world_z, editor)
            dx, dz := x - last.x, z - last.z
            if dx * dx + dz * dz >= cell * cell * .45 {
                editor.curve_points[editor.curve_point_count] = {x, z}
                editor.curve_point_count += 1
            }
        }
    }
    if editor.curve_drawing && (canvas2d.IsMouseButtonReleased(.LEFT) || canvas2d.IsMouseButtonReleased(.RIGHT)) {
        if editor.curve_point_count >= 2 {
            if editor.curve_cliff_mode {
                terrain_history_push_undo(editor)
                if cliff_commit(editor) {
                    world_terrain_invalidate_all(editor)
                } else if editor.terrain_undo_count > 0 {
                    editor.terrain_undo_count -= 1
                }
            } else {
                structure_history_push_undo(editor)
                last_index := curve_commit(editor)
                if last_index >= 0 do editor.structure_selected = last_index
            }
        }
        curve_reset(editor)
    }
}

seed_foliage_capture :: proc(editor: ^Editor, target := "") {
    if editor == nil do return
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    if target == "field" {
        field_x, field_z := center, center
        best_water_distance_squared := f32(999999)
        for z_index in -40 ..= 40 {
            for x_index in -40 ..= 40 {
                x := center + f32(x_index) * 4
                z := center + f32(z_index) * 4
                land_height, _, land_found := terrain.sample_land(&editor.project, 0, x, z)
                waterway := terrain.active_waterway_at(&editor.project, 0, x, z)
                if !waterway &&
                   (!land_found || land_height > editor.project.sea_level + CROP_FIELD_DRY_LAND_CLEARANCE) {
                    continue
                }
                enclosed := true
                enclosure_offsets := [4][2]f32{{-64, 0}, {64, 0}, {0, -64}, {0, 64}}
                for offset in enclosure_offsets {
                    enclosure_height, _, enclosure_found := terrain.sample_land(
                        &editor.project,
                        0,
                        x + offset.x,
                        z + offset.y,
                    )
                    if !enclosure_found ||
                       terrain.active_waterway_at(&editor.project, 0, x + offset.x, z + offset.y) ||
                       enclosure_height <= editor.project.sea_level + CROP_FIELD_DRY_LAND_CLEARANCE {
                        enclosed = false
                        break
                    }
                }
                if !enclosed do continue
                distance_squared := f32(x_index * x_index + z_index * z_index)
                if distance_squared >= best_water_distance_squared do continue
                best_water_distance_squared = distance_squared
                field_x, field_z = x, z
            }
        }
        field := capture_add_formation(editor, field_x, field_z, 220, 220, 1.4, .Field)
        if field >= 0 do editor.project.structures[field].rotation = -.14
        editor.authoring_tool = .Foliage
        editor.tool = .Structure
        editor.structure_kind = .Field
        editor.structure_auto_kind = false
        editor.structure_selected = -1
        editor.structure_placing = false
        editor.architecture_node_mode = false
        editor.architecture_paint_mode = false
        editor.road_mode = false
        editor.editor_focus.x = field_x
        editor.editor_focus.z = field_z
        editor.editor_focus.y = terrain.sample_surface_height(&editor.project, 0, field_x, field_z) + 8
        editor.editor_camera.pitch_radians = .32
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
        return
    }
    _ = capture_add_formation(editor, center - 70, center + 35, 115, 92, 52, .Foliage)
    hedge := capture_add_formation(editor, center + 38, center + 58, 185, 42, 46, .Foliage)
    if hedge >= 0 do editor.project.structures[hedge].rotation = -.18
    _ = capture_add_formation(editor, center + 45, center - 72, 170, 145, 68, .Foliage)
    editor.authoring_tool = .Foliage
    editor.tool = .Structure
    editor.structure_kind = .Foliage
    editor.structure_auto_kind = false
    editor.structure_selected = -1
    editor.structure_placing = false
    editor.architecture_node_mode = false
    editor.architecture_paint_mode = false
    editor.road_mode = false
}

seed_foliage_stress :: proc(editor: ^Editor) {
    if editor == nil do return
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    for z_index in -3 ..= 3 {
        for x_index in -3 ..= 3 {
            index := (z_index + 3) * 7 + x_index + 3
            jitter_x := f32(math.sin(f64(index) * 2.17 + .4)) * 14
            jitter_z := f32(math.sin(f64(index) * 1.43 + 2.1)) * 14
            x := center + f32(x_index) * 68 + jitter_x
            z := center + f32(z_index) * 62 + jitter_z
            width := f32(92 + (index % 4) * 9)
            depth := f32(82 + ((index + 2) % 4) * 8)
            height := f32(42 + (index % 5) * 7)
            foliage := capture_add_formation(editor, x, z, width, depth, height, .Foliage)
            if foliage >= 0 {
                editor.project.structures[foliage].rotation = f32(math.sin(f64(index) * .73)) * .34
            }
        }
    }
    editor.authoring_tool = .Foliage
    editor.tool = .Structure
    editor.structure_kind = .Foliage
    editor.structure_auto_kind = false
    editor.structure_selected = -1
    editor.structure_placing = false
    editor.architecture_node_mode = false
    editor.architecture_paint_mode = false
    editor.road_mode = false
    editor.editor_camera.distance = 610
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
}

seed_structure_lod_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    seed_city_capture(editor)
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    kinds := [5]terrain.Formation_Kind{.Rock, .Spire, .Mountain, .Ridge, .Cliff}
    for ring in 0 ..< 3 {
        for item in 0 ..< 10 {
            angle := f32(item) * math.TAU / 10 + f32(ring) * .31
            radius := f32(180 + ring * 115)
            kind := kinds[(item + ring) % len(kinds)]
            _ = capture_add_formation(
                editor,
                center + math.cos(angle) * radius,
                center + math.sin(angle) * radius,
                f32(34 + (item % 4) * 13),
                f32(28 + ((item + 2) % 4) * 11),
                f32(24 + (item % 5) * 12),
                kind,
            )
        }
    }
    for item in 0 ..< 12 {
        angle := f32(item) * math.TAU / 12 + .17
        radius := f32(245 + (item % 3) * 42)
        _ = capture_add_formation(
            editor,
            center + math.cos(angle) * radius,
            center + math.sin(angle) * radius,
            f32(88 + (item % 4) * 12),
            f32(76 + ((item + 1) % 4) * 10),
            f32(48 + (item % 3) * 9),
            .Foliage,
        )
    }
    editor.structure_selected = -1
    editor.editor_camera.distance = 760
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
}

seed_foliage_forest_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)

    // Two deliberately uneven canopy tiers frame an open glade. The inner
    // crowns stay low enough to reveal the taller back line, while varying
    // widths and rotations keep the forest edge from resolving into a ring.
    for index in 0 ..< 8 {
        // Leave a camera-facing break so the glade reads as an invitation into
        // the forest and the taller back tier exposes occasional trunks.
        if index == 0 || index == 1 do continue
        angle := f32(index) * math.PI * 2 / 8 + .22
        radius := f32(102 + (index % 3) * 9)
        x := center + math.cos(angle) * radius
        z := center + math.sin(angle) * radius * .82
        width := f32(82 + (index % 4) * 9)
        depth := f32(76 + ((index + 2) % 4) * 8)
        height := f32(40 + (index % 3) * 7)
        if index % 2 == 0 {
            // Alternate young trees with the low glade shrubs. This exposes
            // trunks and forked limbs at eye level while keeping a soft,
            // inhabited forest edge rather than a uniform wall of canopy.
            width = f32(108 + (index % 3) * 8)
            depth = f32(101 + ((index + 1) % 3) * 7)
            height = f32(60 + (index % 3) * 6)
        }
        foliage := capture_add_formation(editor, x, z, width, depth, height, .Foliage)
        if foliage >= 0 do editor.project.structures[foliage].rotation = angle * .31 - .45
    }
    for index in 0 ..< 13 {
        angle := f32(index) * math.PI * 2 / 13 - .11
        radius := f32(198 + ((index * 7) % 5) * 11)
        x := center + math.cos(angle) * radius
        z := center + math.sin(angle) * radius * .76
        width := f32(112 + (index % 5) * 10)
        depth := f32(96 + ((index + 3) % 5) * 9)
        height := f32(59 + (index % 4) * 9)
        foliage := capture_add_formation(editor, x, z, width, depth, height, .Foliage)
        if foliage >= 0 do editor.project.structures[foliage].rotation = -.28 + f32(index % 5) * .14
    }

    editor.authoring_tool = .Foliage
    editor.tool = .Structure
    editor.structure_kind = .Foliage
    editor.structure_auto_kind = false
    editor.structure_selected = -1
    editor.structure_placing = false
    editor.architecture_node_mode = false
    editor.architecture_paint_mode = false
    editor.road_mode = false
    editor.editor_focus.y = 18
    editor.editor_camera.pitch_radians = .40
    editor.editor_camera.distance = 540
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
}

configure_foliage_understory_camera :: proc(editor: ^Editor) {
    if editor == nil do return
    island_center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    // Reuse one deterministic walking-distance view for screenshot and
    // performance regression so the measured workload matches visible roots,
    // trunks, canopy attachment, and the lush fern LOD.
    target_index := 3
    target_angle := f32(target_index) * math.PI * 2 / 13 - .11
    target_radius := f32(198 + ((target_index * 7) % 5) * 11)
    editor.editor_focus.x = island_center + math.cos(target_angle) * target_radius
    editor.editor_focus.z = island_center + math.sin(target_angle) * target_radius * .76
    editor.editor_focus.y = 7
    editor.editor_camera.pitch_radians = .035
    editor.editor_camera.distance = 72
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
}

seed_road_grip_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    seed_road_capture(editor)
    if editor.project.road_graph.edge_count <= 0 do return
    edge := editor.project.road_graph.edges[0]
    point := roads.edge_point(&editor.project.road_graph, edge, .08)
    tangent := roads.edge_tangent(&editor.project.road_graph, edge, .08)
    editor.car.position = {point.x, point.y, point.z}
    editor.car.yaw_radians = math.atan2(tangent.z, tangent.x)
    car_physics_teleport(editor)
    editor.pilot.position = editor.car.position
    _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.car})
    if !entered do return
    editor.in_map = true
    editor.map_time = f32(canvas2d.GetTime())
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(editor.car.position, editor.camera)
}

seed_terrain_grip_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.project.road_graph = {}
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    center := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    editor.car.position = {center + half_extent * terrain.DEFAULT_ISLAND_RADIUS, 0, center}
    editor.car.position.y = terrain.sample_surface_height(
        &editor.project,
        0,
        editor.car.position.x,
        editor.car.position.z,
    )
    editor.car.yaw_radians = math.PI * .5
    car_physics_teleport(editor)
    editor.pilot.position = editor.car.position
    _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.car})
    if !entered do return
    editor.in_map = true
    editor.map_time = f32(canvas2d.GetTime())
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(editor.car.position, editor.camera)
}

seed_player_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    position := runway_spawn_position(editor)
    position.x += 24
    position.z += 20
    position.y = terrain.sample_surface_height(&editor.project, 0, position.x, position.z)
    player_place(editor, position, .Scene_Setup)
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.in_map = true
    editor.map_time = f32(canvas2d.GetTime())
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(editor.player.position, editor.camera)
}

seed_ocean_flight_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.aircraft.active = .Rondine
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = true
    editor.rondine.vehicle.locked = false
    editor.rondine.spawn_position = rondine_spawn_position(editor)
    rondine_game.reset(&editor.rondine, editor.project.sea_level)
    editor.pilot.position = editor.rondine.vehicle.position
    _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.rondine.vehicle})
    if !entered do return
    editor.in_map = true
    editor.map_time = f32(canvas2d.GetTime())
    chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
    editor.camera_pose = editor.flight_camera.pose
}

seed_land_flight_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.aircraft.active = .Postale
    editor.postale_visible = true
    editor.libellula_visible = false
    editor.rondine_visible = false
    editor.pilot.position = editor.postale.vehicle.position
    _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.postale.vehicle})
    if !entered do return
    editor.in_map = true
    editor.map_time = f32(canvas2d.GetTime())
}

seed_zora_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    seed_default_island_towns(editor)
    position, found := world_story_resident_position(editor, .Zora)
    if !found do return
    editor.camera_target_lock = false
    editor.postale_visible = false
    editor.libellula_visible = false
    player_position := third_person.Vec3 {
        position.x + 1.6,
        terrain.sample_surface_height(&editor.project, 0, position.x + 1.6, position.z),
        position.z,
    }
    player_facing := math.atan2(player_position.x - position.x, player_position.z - position.z)
    player_place(editor, player_position, .Scene_Setup, player_facing)
    editor.in_map = true
    editor.map_time = f32(canvas2d.GetTime())
    inspection_pose := third_person.camera_near({position.x, position.y + .48, position.z}, {1.35, .62, 1.35})
    third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    editor.camera_pose = inspection_pose
    if open_story_dialogue(editor, .Zora) {
        _ = dialogue.choose(&editor.attendant_dialogue, 1)
    }
}

seed_marta_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.camera_target_lock = false
    editor.postale_visible = false
    editor.libellula_visible = false
    attendant := airport_service_position(editor.attendant_position)
    player_place(
        editor,
        {
            attendant.x + 20,
            terrain.sample_surface_height(&editor.project, 0, attendant.x + 20, attendant.z),
            attendant.z,
        },
        .Scene_Setup,
    )
    editor.in_map = true
    editor.map_time = f32(canvas2d.GetTime())
    inspection_pose := third_person.camera_near({attendant.x, attendant.y + .48, attendant.z}, {1.35, .62, 1.35})
    third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    editor.camera_pose = inspection_pose
    open_attendant_dialogue(editor, .Marta)
}

seed_municipal_route_lamps :: proc(editor: ^Editor) {
    if editor == nil do return
    plan := &editor.architecture_city_plan
    clear(&plan.lamps)
    plan.lamp_count = 0
    segment_length := f32(49)
    spacing := settlement_route_lamp_spacing(.Town, .Street)
    sample_count := settlement_lamp_sample_count(segment_length, spacing)
    for row in 0 ..< 8 {
        z := editor.editor_focus.z + (f32(row) - 3.5) * 13
        for sample in 0 ..< sample_count {
            along := (f32(sample) + .5) / f32(sample_count)
            append(
                &plan.lamps,
                architecture.City_Lamp {
                    x = editor.editor_focus.x - segment_length * .5 + segment_length * along,
                    z = z,
                    yaw = 0,
                },
            )
            plan.lamp_count += 1
        }
    }
}

seed_municipal_route_night_benchmark :: proc(editor: ^Editor) {
    if editor == nil do return
    seed_city_capture(editor)
    seed_municipal_route_lamps(editor)
    editor.editor_camera.distance = 92
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
}

capture_target_is_generated_dunes :: #force_inline proc(target: string) -> bool {
    return target == "dunes" || target == "dunes-west" || target == "dunes-blowout"
}

capture_weather_regime :: proc(target: string) -> (atmosphere.Climate_Regime, bool) {
    switch target {
    case "weather-maestral":
        return .Maestral, true
    case "weather-bura-clear":
        return .Bura_Clear, true
    case "weather-bura-storm":
        return .Bura_Storm, true
    case "weather-jugo":
        return .Jugo, true
    case "weather-calm-humid":
        return .Calm_Humid, true
    case "weather-post-front":
        return .Post_Front, true
    }
    return .Maestral, false
}
