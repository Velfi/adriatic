package main

import road_designer "../packages/road_designer"
import road_planner "../packages/road_planner"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

road_preview_status_text :: proc(status: Road_Preview_Status) -> cstring {
    switch status {
    case .Idle:
        return ""
    case .Valid:
        return "Preview ready — click to commit."
    case .Stale:
        return "Updating terrain route…"
    case .Degenerate:
        return "Road is too short to build."
    case .No_Route:
        return "No terrain route satisfies the current costs."
    case .Capacity:
        return "Road graph has no capacity for this route."
    case .Invalid_Junction:
        return "Cannot split the target road at this point."
    }
    return ""
}

road_snap_world_radius :: proc(editor: ^Editor, point: roads.Vec3) -> f32 {
    if editor == nil do return 8
    dx := editor.camera_pose.position.x - point.x
    dy := editor.camera_pose.position.y - point.y
    dz := editor.camera_pose.position.z - point.z
    distance := f32(math.sqrt(f64(dx * dx + dy * dy + dz * dz)))
    return clamp(distance * .018, f32(3), f32(24))
}

road_snap_candidate :: proc(editor: ^Editor, x, z: f32) -> Road_Snap {
    if editor == nil do return {node = -1, edge = -1}
    result := Road_Snap {
        kind     = .Raw,
        position = {x, terrain.sample_surface_height(&editor.project, 0, x, z), z},
        node     = -1,
        edge     = -1,
        valid    = true,
    }
    graph := &editor.project.road_graph
    radius := road_snap_world_radius(editor, result.position)
    radius_squared := radius * radius
    if editor.road_preview_snap.valid &&
       (editor.road_preview_snap.kind == .Node || editor.road_preview_snap.kind == .Edge) {
        dx := editor.road_preview_snap.position.x - x
        dz := editor.road_preview_snap.position.z - z
        release_radius := radius * 1.35
        if dx * dx + dz * dz <= release_radius * release_radius do return editor.road_preview_snap
    }

    if editor.road_snap_nodes {
        best := radius_squared
        for node, index in graph.nodes[:graph.node_count] {
            dx, dz := node.position.x - x, node.position.z - z
            candidate := dx * dx + dz * dz
            if candidate <= best {
                best = candidate
                result.kind, result.position, result.node = .Node, node.position, index
            }
        }
        if result.kind == .Node do return result
    }

    if editor.road_snap_edges {
        nearest := roads.nearest_edge_point(graph, result.position)
        if nearest.found && nearest.distance_squared <= radius_squared {
            edge := graph.edges[nearest.edge_index]
            endpoint_threshold := f32(.035)
            if nearest.amount <= endpoint_threshold {
                result.kind, result.position, result.node = .Node, graph.nodes[edge.from].position, edge.from
            } else if nearest.amount >= 1 - endpoint_threshold {
                result.kind, result.position, result.node = .Node, graph.nodes[edge.to].position, edge.to
            } else {
                result.kind = .Edge
                result.position = nearest.position
                result.edge = nearest.edge_index
                result.edge_t = nearest.amount
            }
            return result
        }
    }

    if editor.road_selected_node >= 0 && editor.road_selected_node < graph.node_count {
        start := graph.nodes[editor.road_selected_node].position
        raw_dx, raw_dz := x - start.x, z - start.z
        raw_length := f32(math.sqrt(f64(raw_dx * raw_dx + raw_dz * raw_dz)))
        if raw_length > .001 {
            if editor.road_snap_tangents {
                best_distance := radius_squared
                best_position: roads.Vec3
                found := false
                for edge in graph.edges[:graph.edge_count] {
                    if edge.from != editor.road_selected_node && edge.to != editor.road_selected_node do continue
                    tangent :=
                        edge.from == editor.road_selected_node ? roads.edge_tangent(graph, edge, 0) : -roads.edge_tangent(graph, edge, 1)
                    tangent.y = 0
                    tangent_length := f32(math.sqrt(f64(tangent.x * tangent.x + tangent.z * tangent.z)))
                    if tangent_length <= .001 do continue
                    tangent /= tangent_length
                    along := raw_dx * tangent.x + raw_dz * tangent.z
                    if along <= 0 do continue
                    candidate := start + tangent * along
                    dx, dz := candidate.x - x, candidate.z - z
                    distance_squared := dx * dx + dz * dz
                    if distance_squared <= best_distance {
                        best_distance, best_position, found = distance_squared, candidate, true
                    }
                }
                if found {
                    best_position.y = terrain.sample_surface_height(&editor.project, 0, best_position.x, best_position.z)
                    result.kind, result.position, result.guide_from = .Tangent, best_position, start
                    return result
                }
            }
            if editor.road_snap_perpendiculars {
                nearest := roads.nearest_edge_point(graph, result.position)
                if nearest.found {
                    tangent := nearest.tangent
                    tangent.y = 0
                    tangent_length := f32(math.sqrt(f64(tangent.x * tangent.x + tangent.z * tangent.z)))
                    if tangent_length > .001 {
                        tangent /= tangent_length
                        normal := roads.Vec3{-tangent.z, 0, tangent.x}
                        along := raw_dx * normal.x + raw_dz * normal.z
                        candidate := start + normal * along
                        dx, dz := candidate.x - x, candidate.z - z
                        if dx * dx + dz * dz <= radius_squared {
                            candidate.y = terrain.sample_surface_height(&editor.project, 0, candidate.x, candidate.z)
                            result.kind, result.position, result.guide_from = .Perpendicular, candidate, start
                            return result
                        }
                    }
                }
            }
            if editor.road_snap_angles {
                angle := f32(math.atan2(f64(raw_dz), f64(raw_dx)))
                step := f32(math.PI / 12)
                snapped_angle := f32(math.round(f64(angle / step))) * step
                candidate := roads.Vec3 {
                    start.x + f32(math.cos(f64(snapped_angle))) * raw_length,
                    0,
                    start.z + f32(math.sin(f64(snapped_angle))) * raw_length,
                }
                dx, dz := candidate.x - x, candidate.z - z
                if dx * dx + dz * dz <= radius_squared {
                    candidate.y = terrain.sample_surface_height(&editor.project, 0, candidate.x, candidate.z)
                    result.kind, result.position, result.guide_from = .Angle, candidate, start
                    return result
                }
            }
        }
    }
    if editor.road_snap_grid {
        grid_x := terrain.snap_to_grid(x, editor.project.levels[0].cell_size)
        grid_z := terrain.snap_to_grid(z, editor.project.levels[0].cell_size)
        result.kind = .Grid
        result.position = {grid_x, terrain.sample_surface_height(&editor.project, 0, grid_x, grid_z), grid_z}
    }
    return result
}

road_preview_metrics :: proc(editor: ^Editor) {
    graph := &editor.road_preview_graph
    editor.road_preview_distance = 0
    editor.road_preview_maximum_grade = 0
    if editor.road_preview_first_edge < 0 do return
    for edge in graph.edges[editor.road_preview_first_edge:graph.edge_count] {
        previous := roads.edge_point(graph, edge, 0)
        for sample in 1 ..= 16 {
            point := roads.edge_point(graph, edge, f32(sample) / 16)
            dx, dz := point.x - previous.x, point.z - previous.z
            horizontal := f32(math.sqrt(f64(dx * dx + dz * dz)))
            editor.road_preview_distance += horizontal
            if horizontal > .001 {
                editor.road_preview_maximum_grade = max(
                    editor.road_preview_maximum_grade,
                    math.abs(point.y - previous.y) / horizontal,
                )
            }
            previous = point
        }
    }
    dx := editor.road_preview_endpoint.x - editor.road_preview_start.x
    dz := editor.road_preview_endpoint.z - editor.road_preview_start.z
    editor.road_preview_angle = f32(math.atan2(f64(dz), f64(dx))) * 180 / math.PI
    editor.road_preview_rise = editor.road_preview_endpoint.y - editor.road_preview_start.y
}

road_preview_clear :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.road_design_optimizer != nil && editor.road_design_optimizer.status == .Running {
        road_designer.cancel(editor.road_design_optimizer)
    }
    editor.road_preview_graph = {}
    editor.road_preview_first_edge = -1
    editor.road_preview_target_node = -1
    editor.road_preview_status = .Idle
    editor.road_preview_snap = {}
    editor.road_preview_pending_snap = {}
    editor.road_preview_pending_since = 0
    editor.road_preview_cell_valid = false
    editor.road_design_request_key = 0
    editor.road_design_redesign_active = false
}

road_preview_rebuild :: proc(editor: ^Editor, snap: Road_Snap) {
    if editor == nil ||
       editor.road_selected_node < 0 ||
       editor.road_selected_node >= editor.project.road_graph.node_count {
        return
    }
    start_graph := &editor.project.road_graph
    start := start_graph.nodes[editor.road_selected_node].position
    dx, dz := snap.position.x - start.x, snap.position.z - start.z
    if dx * dx + dz * dz < 1 {
        road_preview_clear(editor)
        editor.road_preview_status = .Degenerate
        return
    }
    preview := start_graph^
    target := -1
    if snap.kind == .Node {
        target = snap.node
    } else if snap.kind == .Edge {
        if !roads.can_split_edge(&preview, snap.edge, snap.edge_t) {
            road_preview_clear(editor)
            editor.road_preview_status = .Invalid_Junction
            return
        }
        target = roads.split_edge(&preview, snap.edge, snap.edge_t, max(editor.road_width * .8, f32(2)))
    } else {
        if !roads.can_add(&preview, 1, 0) {
            road_preview_clear(editor)
            editor.road_preview_status = .Capacity
            return
        }
        target = roads.add_node(&preview, snap.position, max(editor.road_width * .8, f32(2)))
    }
    if target < 0 || target == editor.road_selected_node {
        road_preview_clear(editor)
        editor.road_preview_status = .Degenerate
        return
    }
    editor.road_preview_first_edge = preview.edge_count
    if editor.road_construction_mode == .Terrain_Route {
        editor.road_preview_target_node = target
        editor.road_preview_snap = snap
        editor.road_preview_start = start
        editor.road_preview_endpoint = snap.position
        if !road_design_preview_begin(editor, preview, editor.road_selected_node, target) ||
           !road_design_preview_step(editor) {
            editor.road_preview_status = .No_Route
            return
        }
        return
    }
    added := -1
    switch editor.road_construction_mode {
    case .Straight:
        added = roads.add_straight_edge(
            &preview,
            editor.road_selected_node,
            target,
            editor.road_width,
            editor.road_shoulder_width,
            editor.road_pavement,
        )
    case .Terrain_Route:
    // Handled above by the progressive shared road designer.
    case .Authored_Curve:
        control_from := editor.road_preview_control_from
        control_to := editor.road_preview_control_to
        if editor.road_construction_phase == .Idle {
            control_from = start + (snap.position - start) / 3
        }
        if editor.road_construction_phase != .Drag_End_Tangent {
            control_to = start + (snap.position - start) * (f32(2) / 3)
        }
        added = roads.add_edge(
            &preview,
            editor.road_selected_node,
            target,
            control_from,
            control_to,
            editor.road_width,
            editor.road_shoulder_width,
            editor.road_pavement,
        )
    }
    if added < 0 {
        road_preview_clear(editor)
        editor.road_preview_status = editor.road_construction_mode == .Terrain_Route ? .No_Route : .Capacity
        return
    }
    editor.road_preview_graph = preview
    editor.road_preview_target_node = target
    editor.road_preview_status = .Valid
    editor.road_preview_snap = snap
    editor.road_preview_start = start
    editor.road_preview_endpoint = snap.position
    road_preview_metrics(editor)
}

road_preview_commit :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.road_preview_status != .Valid do return false
    if editor.road_construction_mode == .Terrain_Route {
        if !road_design_commit_graph(editor, editor.road_preview_graph, editor.road_design_preview_id) do return false
    } else {
        structure_history_push_undo(editor)
        road_design_history_clear(&editor.road_design_redo, &editor.road_design_redo_count)
        editor.project.road_graph = editor.road_preview_graph
        editor.project.revision += 1
    }
    editor.road_selected_node = editor.road_preview_target_node
    road_preview_clear(editor)
    editor.road_construction_phase = editor.road_construction_mode == .Authored_Curve ? .Idle : .Choose_End
    editor.road_preview_control_from = {}
    editor.road_preview_control_to = {}
    return true
}

road_add_node :: proc(editor: ^Editor, x, z: f32) -> int {
    if editor == nil do return -1
    snapped_x := structure_editor_snap(x, editor)
    snapped_z := structure_editor_snap(z, editor)
    y := terrain.sample_surface_height(&editor.project, 0, snapped_x, snapped_z)
    return roads.add_node(
        &editor.project.road_graph,
        {snapped_x, y, snapped_z},
        max(editor.road_width * .8, terrain.BASE_CELL_SIZE * .35),
    )
}

road_connect_graph :: proc(editor: ^Editor, graph: ^roads.Graph, from, to: int) -> int {
    if editor == nil || graph == nil || from == to do return -1
    existing := roads.edge_between(graph, from, to)
    if existing >= 0 do return existing
    a, b := graph.nodes[from].position, graph.nodes[to].position
    config := road_planner.get_generation_config()
    span_x, span_z := math.abs(b.x - a.x), math.abs(b.z - a.z)
    config.cell_size = max(config.cell_size, max(span_x, span_z) / f32(road_planner.MAX_GRID_WIDTH - 13))
    margin := config.cell_size * 6
    origin_x, origin_z := min(a.x, b.x) - margin, min(a.z, b.z) - margin
    width := clamp(
        int(math.ceil(f64((max(a.x, b.x) + margin - origin_x) / config.cell_size))) + 1,
        2,
        road_planner.MAX_GRID_WIDTH,
    )
    height := clamp(
        int(math.ceil(f64((max(a.z, b.z) + margin - origin_z) / config.cell_size))) + 1,
        2,
        road_planner.MAX_GRID_HEIGHT,
    )
    heights := make([]f32, width * height)
    defer delete(heights)
    for z in 0 ..< height {
        for x in 0 ..< width {
            heights[z * width + x] = terrain.sample_surface_height(
                &editor.project,
                0,
                origin_x + f32(x) * config.cell_size,
                origin_z + f32(z) * config.cell_size,
            )
        }
    }
    workspace := new(road_planner.Workspace)
    defer free(workspace)
    route := road_planner.plan(
        workspace,
        {
            origin_x = origin_x,
            origin_z = origin_z,
            width = width,
            height = height,
            sea_level = editor.project.sea_level,
            heights = heights,
        },
        config,
        {a.x, a.z},
        {b.x, b.z},
    )
    if !route.found do return -1
    bends: [roads.MAX_NODES]road_planner.Point
    bend_count := 0
    for point, index in route.points[:route.point_count] {
        if index == 0 || index == route.point_count - 1 do continue
        before, after := route.points[index - 1], route.points[index + 1]
        if point.x - before.x == after.x - point.x && point.z - before.z == after.z - point.z do continue
        if bend_count >= len(bends) do return -1
        bends[bend_count] = point
        bend_count += 1
    }
    if graph.node_count + bend_count > roads.MAX_NODES || graph.edge_count + bend_count + 1 > roads.MAX_EDGES do return -1
    chain_nodes: [roads.MAX_NODES]int
    chain_points: [roads.MAX_NODES]roads.Vec3
    chain_nodes[0], chain_points[0] = from, a
    chain_count := 1
    for point in bends[:bend_count] {
        y := terrain.sample_surface_height(&editor.project, 0, point.x, point.z)
        position := roads.Vec3{point.x, y, point.z}
        local_radius := min(editor.road_width * .55, config.cell_size * .18)
        node := roads.add_node(graph, position, max(local_radius, f32(.75)))
        if node < 0 do return -1
        chain_nodes[chain_count] = node
        chain_points[chain_count] = position
        chain_count += 1
    }
    chain_nodes[chain_count], chain_points[chain_count] = to, b
    chain_count += 1
    return road_planning_add_smooth_chain(
        graph,
        chain_nodes[:chain_count],
        chain_points[:chain_count],
        editor.road_width,
        editor.road_shoulder_width,
        editor.road_pavement,
    )
}

road_connect :: proc(editor: ^Editor, from, to: int) -> int {
    if editor == nil do return -1
    return road_connect_graph(editor, &editor.project.road_graph, from, to)
}

road_preview_update :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil ||
       !cursor_hit ||
       editor.road_selected_node < 0 ||
       editor.road_selected_node >= editor.project.road_graph.node_count {
        road_preview_clear(editor)
        return
    }
    snap := road_snap_candidate(editor, world_x, world_z)
    if editor.road_construction_mode == .Terrain_Route {
        cell := max(road_planner.get_generation_config().cell_size, f32(.001))
        cell_x := int(math.round(f64(snap.position.x / cell)))
        cell_z := int(math.round(f64(snap.position.z / cell)))
        request_changed :=
            editor.road_design_optimizer == nil ||
            editor.road_design_source_revision != editor.project.revision ||
            editor.road_design_terrain_revision != editor.terrain_revision ||
            editor.road_design_start_node != editor.road_selected_node ||
            editor.road_design_optimizer.request.pavement != editor.road_pavement ||
            editor.road_design_optimizer.request.width != editor.road_width ||
            editor.road_design_optimizer.request.shoulder != editor.road_shoulder_width
        changed :=
            request_changed ||
            !editor.road_preview_cell_valid ||
            editor.road_preview_cell_x != cell_x ||
            editor.road_preview_cell_z != cell_z ||
            editor.road_preview_pending_snap.kind != snap.kind ||
            editor.road_preview_pending_snap.node != snap.node ||
            editor.road_preview_pending_snap.edge != snap.edge
        if changed {
            editor.road_preview_cell_x = cell_x
            editor.road_preview_cell_z = cell_z
            editor.road_preview_cell_valid = true
            editor.road_preview_pending_snap = snap
            editor.road_preview_pending_since = canvas2d.GetTime()
            editor.road_preview_status = .Stale
            editor.road_preview_snap = snap
            return
        }
        if editor.road_design_optimizer != nil &&
           editor.road_design_optimizer.status != .Cancelled &&
           editor.road_preview_status != .Stale {
            _ = road_design_preview_step(editor)
            return
        }
        if canvas2d.GetTime() - editor.road_preview_pending_since < .055 {
            return
        }
        snap = editor.road_preview_pending_snap
    }
    road_preview_rebuild(editor, snap)
}

road_set_pavement :: proc(editor: ^Editor, pavement: roads.Pavement) {
    if editor == nil || !editor.road_mode do return
    editor.road_pavement = pavement
    if editor.road_selected_node < 0 do return
    needs_change := false
    for edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
        if (edge.from == editor.road_selected_node || edge.to == editor.road_selected_node) &&
           edge.pavement != pavement {
            needs_change = true
            break
        }
    }
    if !needs_change do return
    structure_history_push_undo(editor)
    for &edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
        if edge.from == editor.road_selected_node || edge.to == editor.road_selected_node {
            edge.pavement = pavement
        }
    }
    editor.project.revision += 1
}

road_cycle_pavement :: proc(editor: ^Editor) {
    if editor == nil do return
    next := roads.pavement_next(editor.road_pavement)
    if editor.road_pavement == .Dirt do next = .Steps
    road_set_pavement(editor, next)
}

road_delete_selected :: proc(editor: ^Editor) {
    if editor == nil || editor.road_selected_node < 0 do return
    structure_history_push_undo(editor)
    if roads.remove_node(&editor.project.road_graph, editor.road_selected_node) {
        editor.project.revision += 1
    }
    editor.road_selected_node = -1
    editor.road_construction_phase = .Idle
    editor.road_preview_first_edge = -1
    editor.road_preview_target_node = -1
    editor.road_preview_status = .Idle
    editor.road_drag_node = -1
    editor.road_drag_node_previous_selection = -1
    editor.road_drag_node_moved = false
    editor.road_drag_edge = -1
    editor.road_drag_handle = -1
}
