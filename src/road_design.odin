package main

import road_designer "../packages/road_designer"
import road_planner "../packages/road_planner"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

ROAD_EDIT_HISTORY_CAPACITY :: 8

Road_Terrain_Delta :: struct {
    level, index: int,
    before, after:f32,
}

Road_Edit_Transaction :: struct {
    before_graph, after_graph: roads.Graph,
    terrain:                   [dynamic]Road_Terrain_Delta,
    design_id:                 u32,
    revision_before:           u64,
    revision_after:            u64,
    sequence:                  u64,
}

road_edit_transaction_destroy :: proc(transaction: ^Road_Edit_Transaction) {
    if transaction == nil do return
    delete(transaction.terrain)
    transaction^ = {}
}

road_design_runtime_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.road_design_optimizer != nil do free(editor.road_design_optimizer)
    if editor.road_design_workspace != nil do free(editor.road_design_workspace)
    editor.road_design_optimizer = nil
    editor.road_design_workspace = nil
    delete(editor.road_design_heights)
    editor.road_design_heights = nil
    for &transaction in editor.road_design_undo do road_edit_transaction_destroy(&transaction)
    for &transaction in editor.road_design_redo do road_edit_transaction_destroy(&transaction)
    editor.road_design_undo_count = 0
    editor.road_design_redo_count = 0
}

road_design_next_id :: proc(graph: ^roads.Graph) -> u32 {
    if graph == nil do return 1
    result := u32(1)
    for edge in graph.edges[:graph.edge_count] do result = max(result, edge.design_id + 1)
    if result == 0 do result = 1
    return result
}

road_design_history_push :: proc(
    history: ^[ROAD_EDIT_HISTORY_CAPACITY]Road_Edit_Transaction,
    count: ^int,
    transaction: Road_Edit_Transaction,
) {
    if history == nil || count == nil do return
    if count^ >= ROAD_EDIT_HISTORY_CAPACITY {
        road_edit_transaction_destroy(&history[0])
        for index in 1 ..< ROAD_EDIT_HISTORY_CAPACITY do history[index - 1] = history[index]
        history[ROAD_EDIT_HISTORY_CAPACITY - 1] = {}
        count^ = ROAD_EDIT_HISTORY_CAPACITY - 1
    }
    history[count^] = transaction
    count^ += 1
}

road_design_history_clear :: proc(history: ^[ROAD_EDIT_HISTORY_CAPACITY]Road_Edit_Transaction, count: ^int) {
    if history == nil || count == nil do return
    for index in 0 ..< count^ do road_edit_transaction_destroy(&history[index])
    count^ = 0
}

road_design_apply_transaction :: proc(editor: ^Editor, transaction: ^Road_Edit_Transaction, forward: bool) {
    if editor == nil || transaction == nil do return
    editor.project.road_graph = forward ? transaction.after_graph : transaction.before_graph
    for delta in transaction.terrain {
        if delta.level < 0 || delta.level >= terrain.CLIPMAP_LEVELS ||
           delta.index < 0 || delta.index >= terrain.SAMPLES_PER_LEVEL {
            continue
        }
        editor.project.levels[delta.level].heights[delta.index] = forward ? delta.after : delta.before
    }
    editor.project.revision = max(editor.project.revision, forward ? transaction.revision_after : transaction.revision_before) + 1
    // One consolidated invalidation covers terrain clipmaps, retained roads,
    // pavement/spatial queries, and downstream physics revisions.
    world_renderer_fixture_invalidate(editor)
}

road_design_undo_last :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.road_design_undo_count <= 0 do return false
    editor.road_design_undo_count -= 1
    transaction := editor.road_design_undo[editor.road_design_undo_count]
    editor.road_design_undo[editor.road_design_undo_count] = {}
    road_design_apply_transaction(editor, &transaction, false)
    road_design_history_push(&editor.road_design_redo, &editor.road_design_redo_count, transaction)
    return true
}

road_design_redo_last :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.road_design_redo_count <= 0 do return false
    editor.road_design_redo_count -= 1
    transaction := editor.road_design_redo[editor.road_design_redo_count]
    editor.road_design_redo[editor.road_design_redo_count] = {}
    road_design_apply_transaction(editor, &transaction, true)
    road_design_history_push(&editor.road_design_undo, &editor.road_design_undo_count, transaction)
    return true
}

road_history_undo :: proc(editor: ^Editor) {
    if editor == nil do return
    road_sequence, structure_sequence: u64
    if editor.road_design_undo_count > 0 do road_sequence = editor.road_design_undo[editor.road_design_undo_count - 1].sequence
    if editor.structure_undo_count > 0 do structure_sequence = editor.structure_undo[editor.structure_undo_count - 1].sequence
    if road_sequence > structure_sequence {
        _ = road_design_undo_last(editor)
    } else {
        structure_undo(editor)
    }
}

road_history_redo :: proc(editor: ^Editor) {
    if editor == nil do return
    road_sequence, structure_sequence: u64
    if editor.road_design_redo_count > 0 do road_sequence = editor.road_design_redo[editor.road_design_redo_count - 1].sequence
    if editor.structure_redo_count > 0 do structure_sequence = editor.structure_redo[editor.structure_redo_count - 1].sequence
    if road_sequence > 0 && (structure_sequence == 0 || road_sequence < structure_sequence) {
        _ = road_design_redo_last(editor)
    } else {
        structure_redo(editor)
    }
}

road_design_grade :: proc(editor: ^Editor, graph: ^roads.Graph, design_id: u32) -> [dynamic]Road_Terrain_Delta {
    deltas := make([dynamic]Road_Terrain_Delta)
    if editor == nil || graph == nil || design_id == 0 do return deltas
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        level := &editor.project.levels[level_index]
        best_distance := make([]f32, terrain.SAMPLES_PER_LEVEL)
        proposed := make([]f32, terrain.SAMPLES_PER_LEVEL)
        touched := make([]bool, terrain.SAMPLES_PER_LEVEL)
        for &value in best_distance do value = f32(1e30)
        for edge in graph.edges[:graph.edge_count] {
            if !edge.engineering_designed || edge.design_id != design_id || edge.structure_kind == .Bridge do continue
            approximate_length := max(roads.edge_control_polygon_length(graph, edge), f32(1))
            sample_count := clamp(int(math.ceil(f64(approximate_length / max(level.cell_size * .5, f32(1))))), 2, 1024)
            platform := edge.half_width + edge.shoulder_width
            feather := platform + max(f32(6), edge.half_width * 3)
            for sample_index in 0 ..= sample_count {
                t := f32(sample_index) / f32(sample_count)
                center := roads.edge_point(graph, edge, t)
                min_x := clamp(int(math.floor(f64((center.x - feather - level.origin_x) / level.cell_size))), 0, terrain.TERRAIN_RESOLUTION - 1)
                max_x := clamp(int(math.ceil(f64((center.x + feather - level.origin_x) / level.cell_size))), 0, terrain.TERRAIN_RESOLUTION - 1)
                min_z := clamp(int(math.floor(f64((center.z - feather - level.origin_z) / level.cell_size))), 0, terrain.TERRAIN_RESOLUTION - 1)
                max_z := clamp(int(math.ceil(f64((center.z + feather - level.origin_z) / level.cell_size))), 0, terrain.TERRAIN_RESOLUTION - 1)
                for z in min_z ..= max_z {
                    world_z := level.origin_z + f32(z) * level.cell_size
                    for x in min_x ..= max_x {
                        world_x := level.origin_x + f32(x) * level.cell_size
                        dx, dz := world_x - center.x, world_z - center.z
                        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
                        if distance > feather do continue
                        index := z * terrain.TERRAIN_RESOLUTION + x
                        if distance >= best_distance[index] do continue
                        blend := f32(1)
                        if distance > platform {
                            normalized := clamp((distance - platform) / max(feather - platform, f32(.001)), f32(0), f32(1))
                            blend = 1 - normalized * normalized * (3 - 2 * normalized)
                        }
                        original := level.heights[index]
                        proposed[index] = original + (center.y - original) * blend
                        best_distance[index] = distance
                        touched[index] = true
                    }
                }
            }
        }
        for touched_value, index in touched {
            if !touched_value do continue
            before, after := level.heights[index], proposed[index]
            if math.abs(after - before) <= .001 do continue
            append(&deltas, Road_Terrain_Delta{level = level_index, index = index, before = before, after = after})
        }
        delete(best_distance)
        delete(proposed)
        delete(touched)
    }
    return deltas
}

road_design_commit_graph :: proc(editor: ^Editor, graph: roads.Graph, design_id: u32) -> bool {
    if editor == nil || design_id == 0 do return false
    after_graph := graph
    editor.road_edit_sequence += 1
    transaction := Road_Edit_Transaction {
        before_graph = editor.project.road_graph,
        after_graph = after_graph,
        design_id = design_id,
        revision_before = editor.project.revision,
        sequence = editor.road_edit_sequence,
    }
    transaction.terrain = road_design_grade(editor, &after_graph, design_id)
    transaction.revision_after = editor.project.revision + 1
    road_design_history_clear(&editor.road_design_redo, &editor.road_design_redo_count)
    editor.structure_redo_count = 0
    editor.terrain_redo_count = 0
    road_design_apply_transaction(editor, &transaction, true)
    road_design_history_push(&editor.road_design_undo, &editor.road_design_undo_count, transaction)
    return true
}

road_design_commit_candidate :: proc(
    editor: ^Editor,
    candidate: ^road_designer.Design_Candidate,
    from, to: int,
) -> bool {
    if editor == nil || candidate == nil do return false
    graph := editor.project.road_graph
    design_id := road_design_next_id(&graph)
    result := road_designer.materialize_between(candidate, &graph, design_id, from, to)
    if !result.ok do return false
    return road_design_commit_graph(editor, graph, design_id)
}

road_design_preview_begin :: proc(editor: ^Editor, base_graph: roads.Graph, from, to: int) -> bool {
    if editor == nil || from < 0 || to < 0 || from >= base_graph.node_count || to >= base_graph.node_count do return false
    if editor.road_design_optimizer == nil do editor.road_design_optimizer = new(road_designer.Optimizer)
    if editor.road_design_workspace == nil do editor.road_design_workspace = new(road_designer.Workspace)
    delete(editor.road_design_heights)
    editor.road_design_heights = nil
    a, b := base_graph.nodes[from].position, base_graph.nodes[to].position
    config := road_planner.get_generation_config()
    span_x, span_z := math.abs(b.x - a.x), math.abs(b.z - a.z)
    config.cell_size = max(config.cell_size, max(span_x, span_z) / f32(road_planner.MAX_GRID_WIDTH - 13))
    tube := max(config.cell_size * 4, f32(math.sqrt(f64(span_x * span_x + span_z * span_z))) * .12)
    margin := max(tube, config.cell_size * 6)
    origin_x, origin_z := min(a.x, b.x) - margin, min(a.z, b.z) - margin
    width := clamp(int(math.ceil(f64((max(a.x, b.x) + margin - origin_x) / config.cell_size))) + 1, 2, road_planner.MAX_GRID_WIDTH)
    height := clamp(int(math.ceil(f64((max(a.z, b.z) + margin - origin_z) / config.cell_size))) + 1, 2, road_planner.MAX_GRID_HEIGHT)
    editor.road_design_heights = make([dynamic]f32, width * height)
    for z in 0 ..< height {
        for x in 0 ..< width {
            world_x := origin_x + f32(x) * config.cell_size
            world_z := origin_z + f32(z) * config.cell_size
            land_height, _, found := terrain.sample_land(&editor.project, 0, world_x, world_z)
            editor.road_design_heights[z * width + x] = found ? land_height : terrain.sample_water_interface(&editor.project, world_x, world_z).water_level
        }
    }
    request := road_designer.Design_Request {
        grid = {origin_x = origin_x, origin_z = origin_z, width = width, height = height,
            sea_level = editor.project.sea_level, heights = editor.road_design_heights[:]},
        cell_size = config.cell_size,
        start = {a.x, a.z}, finish = {b.x, b.z},
        pavement = editor.road_pavement,
        width = editor.road_width,
        shoulder = editor.road_shoulder_width,
        sea_level = editor.project.sea_level,
        available_nodes = roads.MAX_NODES - base_graph.node_count,
        available_edges = roads.MAX_EDGES - base_graph.edge_count,
        seed = u32(from * 73856093 ~ to * 19349663 ~ width * 83492791 ~ height),
    }
    status := road_designer.begin(editor.road_design_optimizer, request, editor.road_design_workspace)
    editor.road_design_base_graph = base_graph
    editor.road_design_start_node = from
    editor.road_design_target_node = to
    preview_id := u32(1)
    for edge_index in 0 ..< base_graph.edge_count {
        preview_id = max(preview_id, base_graph.edges[edge_index].design_id + 1)
    }
    editor.road_design_preview_id = preview_id
    editor.road_design_source_revision = editor.project.revision
    editor.road_design_terrain_revision = editor.terrain_revision
    editor.road_design_frame_budget = 8
    editor.road_design_paused = false
    return status == .Running || status == .Complete
}

road_design_preview_step :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.road_design_optimizer == nil do return false
    optimizer := editor.road_design_optimizer
    if !editor.road_design_paused && optimizer.status == .Running {
        started := canvas2d.GetTime()
        _ = road_designer.step(optimizer, max(editor.road_design_frame_budget, 1))
        elapsed_ms := (canvas2d.GetTime() - started) * 1000
        if elapsed_ms > 4 && editor.road_design_frame_budget > 1 {
            editor.road_design_frame_budget = max(1, editor.road_design_frame_budget / 2)
        } else if elapsed_ms < 2 && editor.road_design_frame_budget < 8 {
            editor.road_design_frame_budget += 1
        }
    }
    selected, ok := road_designer.candidate(optimizer, editor.road_design_alternative)
    if !ok do return false
    preview := editor.road_design_base_graph
    result := road_designer.materialize_between(
        selected, &preview, editor.road_design_preview_id,
        editor.road_design_start_node, editor.road_design_target_node,
    )
    if !result.ok do return false
    editor.road_preview_graph = preview
    editor.road_preview_first_edge = result.first_edge
    editor.road_preview_target_node = editor.road_design_target_node
    editor.road_preview_distance = selected.metrics.length
    editor.road_preview_maximum_grade = selected.metrics.maximum_grade
    editor.road_preview_status = .Valid
    return true
}

road_design_redesign_selected_chain :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    graph := &editor.project.road_graph
    selected := editor.road_selected_node
    if selected < 0 || selected >= graph.node_count || roads.node_degree(graph, selected) != 2 do return false
    remove_edges: [roads.MAX_EDGES]bool
    remove_nodes: [roads.MAX_NODES]bool
    endpoints: [2]int
    endpoint_count := 0
    pavement := editor.road_pavement
    prior_design_id := u32(0)
    for edge_index in 0 ..< graph.edge_count {
        edge := graph.edges[edge_index]
        if edge.from != selected && edge.to != selected do continue
        pavement = edge.pavement
        if prior_design_id == 0 do prior_design_id = edge.design_id
        previous, current := selected, edge.from == selected ? edge.to : edge.from
        current_edge := edge_index
        for steps in 0 ..< graph.node_count {
            remove_edges[current_edge] = true
            if roads.node_degree(graph, current) != 2 {
                endpoints[endpoint_count] = current
                endpoint_count += 1
                break
            }
            remove_nodes[current] = true
            next_edge := -1
            next_node := -1
            for candidate_index in 0 ..< graph.edge_count {
                if candidate_index == current_edge do continue
                candidate := graph.edges[candidate_index]
                if candidate.from == current {
                    next_edge, next_node = candidate_index, candidate.to
                    break
                } else if candidate.to == current {
                    next_edge, next_node = candidate_index, candidate.from
                    break
                }
            }
            if next_edge < 0 || next_node == previous || next_node == selected do return false
            previous, current, current_edge = current, next_node, next_edge
        }
        if endpoint_count >= 2 do break
    }
    if endpoint_count != 2 || endpoints[0] == endpoints[1] do return false
    remove_nodes[selected] = true
    base := graph^
    original_edge_count := base.edge_count
    for reverse in 0 ..< original_edge_count {
        index := original_edge_count - 1 - reverse
        if remove_edges[index] do _ = roads.remove_edge(&base, index)
    }
    from, to := endpoints[0], endpoints[1]
    for index := graph.node_count - 1; index >= 0; index -= 1 {
        if !remove_nodes[index] do continue
        _ = roads.remove_node(&base, index)
        if from > index do from -= 1
        if to > index do to -= 1
    }
    editor.road_pavement = pavement
    if !road_design_preview_begin(editor, base, from, to) do return false
    if prior_design_id != 0 do editor.road_design_preview_id = prior_design_id
    editor.road_preview_start = base.nodes[from].position
    editor.road_preview_endpoint = base.nodes[to].position
    editor.road_preview_snap = {kind = .Node, node = to, position = base.nodes[to].position}
    editor.road_design_redesign_active = true
    return road_design_preview_step(editor)
}
