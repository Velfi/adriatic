package main

import road_designer "../packages/road_designer"
import road_planner "../packages/road_planner"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:fmt"
import "core:math"
import "core:strconv"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

ROAD_PLANNING_LAB_GRID :: 112
ROAD_PLANNING_LAB_SAMPLE_COUNT :: ROAD_PLANNING_LAB_GRID * ROAD_PLANNING_LAB_GRID
ROAD_PLANNING_LAB_SLIDER_COUNT :: 9
ROAD_PLANNING_LAB_INPUT_DEBOUNCE_SECONDS :: f64(.20)

Road_Planning_Lab_State :: struct {
    config:                road_planner.Config,
    workspace:             ^road_planner.Workspace,
    heights:               [ROAD_PLANNING_LAB_SAMPLE_COUNT]f32,
    result:                road_planner.Result,
    points:                [2]road_planner.Point,
    point_count:           int,
    seed:                  u32,
    next_endpoint:         int,
    graph_too_complex:     bool,
    route_bend_count:      int,
    dragging:              int,
    editing:               int,
    input:                 [24]u8,
    input_length:          int,
    regen_pending:         bool,
    regen_at:              f64,
    optimizer:             ^road_designer.Optimizer,
    design_work:           ^road_designer.Workspace,
    pavement:              roads.Pavement,
    alternative:           road_designer.Named_Alternative,
    paused:                bool,
    show_all:              bool,
    committed:             bool,
    evaluations_per_frame: int,
}

road_planning_lab: Road_Planning_Lab_State

road_planning_lab_panel :: proc(width: i32) -> canvas2d.Rectangle {
    return {f32(width) - 430, 24, 406, 672}
}

road_planning_lab_slider_bounds :: proc(width, index: int) -> canvas2d.Rectangle {
    panel := road_planning_lab_panel(i32(width))
    return {panel.x + 190, panel.y + 102 + f32(index) * 48, panel.width - 286, 30}
}

road_planning_lab_input_bounds :: proc(width, index: int) -> canvas2d.Rectangle {
    panel := road_planning_lab_panel(i32(width))
    return {panel.x + panel.width - 84, panel.y + 99 + f32(index) * 48, 64, 30}
}

road_planning_lab_slider_value :: proc(index: int) -> (value, low, high: f32) {
    switch index {
    case 0:
        return road_planning_lab.config.cell_size, 6, 48
    case 1:
        return road_planning_lab.config.length_cost, .1, 4
    case 2:
        return road_planning_lab.config.grade_cost, 0, 150
    case 3:
        return road_planning_lab.config.steep_grade_cost, 0, 1000
    case 4:
        return road_planning_lab.config.water_cost, 0, 1500
    case 5:
        return road_planning_lab.config.turn_cost, 0, 30
    case 6:
        return road_planning_lab.config.switchback_cost, 0, 100
    case 7:
        return road_planning_lab.config.maximum_grade, .02, .6
    case 8:
        return road_planning_lab.config.heuristic_weight, .8, 1.5
    }
    return 0, 0, 1
}

road_planning_lab_set_slider :: proc(index: int, normalized: f32) -> bool {
    previous, low, high := road_planning_lab_slider_value(index)
    value := low + clamp(normalized, 0, 1) * (high - low)
    if value == previous do return false
    switch index {
    case 0:
        road_planning_lab.config.cell_size = value
    case 1:
        road_planning_lab.config.length_cost = value
    case 2:
        road_planning_lab.config.grade_cost = value
    case 3:
        road_planning_lab.config.steep_grade_cost = value
    case 4:
        road_planning_lab.config.water_cost = value
    case 5:
        road_planning_lab.config.turn_cost = value
    case 6:
        road_planning_lab.config.switchback_cost = value
    case 7:
        road_planning_lab.config.maximum_grade = value
    case 8:
        road_planning_lab.config.heuristic_weight = value
    }
    road_planner.set_generation_config(road_planning_lab.config)
    return true
}

road_planning_lab_input_text :: proc() -> string {
    return string(road_planning_lab.input[:road_planning_lab.input_length])
}

road_planning_lab_begin_input :: proc(index: int) {
    road_planning_lab.editing = index
    road_planning_lab.dragging = -1
    road_planning_lab.input = {}
    value, _, _ := road_planning_lab_slider_value(index)
    if index == 7 do value *= 100
    formatted := fmt.bprintf(road_planning_lab.input[:], "%.3f", value)
    road_planning_lab.input_length = len(formatted)
    _ = canvas2d.StartTextInput()
}

road_planning_lab_apply_input :: proc() -> bool {
    if road_planning_lab.editing < 0 do return false
    parsed, ok := strconv.parse_f32(road_planning_lab_input_text())
    if !ok do return false
    _, low, high := road_planning_lab_slider_value(road_planning_lab.editing)
    value := parsed
    if road_planning_lab.editing == 7 do value *= .01
    value = clamp(value, low, high)
    return road_planning_lab_set_slider(road_planning_lab.editing, (value - low) / (high - low))
}

road_planning_lab_append_input :: proc(text: string) -> bool {
    changed := false
    for byte in transmute([]u8)text {
        if road_planning_lab.input_length >= len(road_planning_lab.input) do break
        if (byte >= '0' && byte <= '9') || byte == '.' || byte == '-' || byte == 'e' || byte == 'E' {
            road_planning_lab.input[road_planning_lab.input_length] = byte
            road_planning_lab.input_length += 1
            changed = true
        }
    }
    return changed
}

road_planning_lab_hash :: #force_inline proc(value: u32) -> u32 {
    result := value
    result = result ~ (result >> 16)
    result *= 0x7feb352d
    result = result ~ (result >> 15)
    result *= 0x846ca68b
    return result ~ (result >> 16)
}

road_planning_lab_noise_lattice :: #force_inline proc(x, z: i32, seed: u32) -> f32 {
    value := road_planning_lab_hash(u32(x) * 0x1f123bb5 ~ u32(z) * 0x5f356495 ~ seed)
    return f32(value & 0x00ffffff) / f32(0x00800000) - 1
}

road_planning_lab_noise :: proc(x, z: f32, seed: u32) -> f32 {
    ix, iz := i32(math.floor(x)), i32(math.floor(z))
    tx, tz := x - f32(ix), z - f32(iz)
    sx, sz := tx * tx * (3 - 2 * tx), tz * tz * (3 - 2 * tz)
    a := road_planning_lab_noise_lattice(ix, iz, seed)
    b := road_planning_lab_noise_lattice(ix + 1, iz, seed)
    c := road_planning_lab_noise_lattice(ix, iz + 1, seed)
    d := road_planning_lab_noise_lattice(ix + 1, iz + 1, seed)
    lower := a + (b - a) * sx
    upper := c + (d - c) * sx
    return lower + (upper - lower) * sz
}

road_planning_lab_fbm :: proc(x, z: f32, seed: u32, octaves: int = 5) -> f32 {
    value, amplitude, normalization := f32(0), f32(1), f32(0)
    frequency := f32(1)
    for octave in 0 ..< octaves {
        octave_seed := road_planning_lab_hash(seed + u32(octave) * 0x9e3779b9)
        value += road_planning_lab_noise(x * frequency, z * frequency, octave_seed) * amplitude
        normalization += amplitude
        amplitude *= .5
        frequency *= 2.03
    }
    return value / max(normalization, f32(.001))
}

road_planning_lab_height :: proc(x, z: f32, seed: u32) -> f32 {
    // Domain-warped FBM moves entire landforms between seeds instead of only
    // shifting a fixed set of sine waves.
    warp_x := road_planning_lab_fbm(x * .00072, z * .00072, seed ~ 0x57415250, 3) * 260
    warp_z := road_planning_lab_fbm(x * .00072 + 31.7, z * .00072 - 19.3, seed ~ 0x444f4d41, 3) * 260
    wx, wz := x + warp_x, z + warp_z
    continental := road_planning_lab_fbm(wx * .00105, wz * .00105, seed ~ 0x434f4e54, 5)
    hills := road_planning_lab_fbm(wx * .0034, wz * .0034, seed ~ 0x48494c4c, 6)
    ridge_signal := road_planning_lab_fbm(wx * .00215 + 11.2, wz * .00215 - 7.8, seed ~ 0x52494447, 5)
    ridges := (1 - math.abs(ridge_signal)) * 38
    // Retain a guaranteed water-crossing problem, but vary its banks, course,
    // and width with separate FBM fields.
    river_center := road_planning_lab_fbm(x * .0009, 4.7, seed ~ 0x52495652, 4) * 310
    river_width := 105 + (road_planning_lab_fbm(x * .0017, z * .0004, seed ~ 0x57494454, 4) + 1) * 42
    river_distance := z - river_center
    valley := -72 * math.exp(-f64(river_distance * river_distance / (river_width * river_width)))
    terrace := road_planning_lab_fbm(wx * .00048, wz * .00048, seed ~ 0x54455252, 4) * 34
    return 4 + continental * 54 + hills * 24 + ridges + terrace + f32(valley)
}

road_planning_lab_apply_terrain :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.project.sea_level = 0
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        level := &editor.project.levels[level_index]
        half_grid := f32(terrain.TERRAIN_RESOLUTION - 1) * .5 * level.cell_size
        level.origin_x, level.origin_z = -half_grid, -half_grid
        for z in 0 ..< terrain.TERRAIN_RESOLUTION {
            world_z := level.origin_z + f32(z) * level.cell_size
            for x in 0 ..< terrain.TERRAIN_RESOLUTION {
                world_x := level.origin_x + f32(x) * level.cell_size
                index := z * terrain.TERRAIN_RESOLUTION + x
                height := road_planning_lab_height(world_x, world_z, road_planning_lab.seed)
                level.heights[index] = height
                level.material[index] = height <= 0 ? f32(-2) : clamp((height - 8) / f32(85), -1, 1)
            }
        }
    }
    editor.project.road_graph = {}
    editor.project.revision += 1
    world_terrain_invalidate_all(editor)
}

road_planning_lab_sample_grid :: proc() -> road_planner.Grid {
    config := road_planning_lab.config
    extent := f32(ROAD_PLANNING_LAB_GRID - 1) * config.cell_size
    origin := -extent * .5
    for z in 0 ..< ROAD_PLANNING_LAB_GRID {
        for x in 0 ..< ROAD_PLANNING_LAB_GRID {
            world_x, world_z := origin + f32(x) * config.cell_size, origin + f32(z) * config.cell_size
            road_planning_lab.heights[z * ROAD_PLANNING_LAB_GRID + x] = road_planning_lab_height(
                world_x,
                world_z,
                road_planning_lab.seed,
            )
        }
    }
    return {
        origin_x = origin,
        origin_z = origin,
        width = ROAD_PLANNING_LAB_GRID,
        height = ROAD_PLANNING_LAB_GRID,
        sea_level = 0,
        heights = road_planning_lab.heights[:],
    }
}

road_planning_smooth_tangent :: proc(points: []roads.Vec3, index: int) -> roads.Vec3 {
    if len(points) < 2 do return {1, 0, 0}
    if index <= 0 {
        value := points[1] - points[0]
        length := math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
        return length > .001 ? value / length : roads.Vec3{1, 0, 0}
    }
    if index >= len(points) - 1 {
        value := points[index] - points[index - 1]
        length := math.sqrt(value.x * value.x + value.y * value.y + value.z * value.z)
        return length > .001 ? value / length : roads.Vec3{1, 0, 0}
    }
    incoming, outgoing := points[index] - points[index - 1], points[index + 1] - points[index]
    incoming_length := math.sqrt(incoming.x * incoming.x + incoming.y * incoming.y + incoming.z * incoming.z)
    outgoing_length := math.sqrt(outgoing.x * outgoing.x + outgoing.y * outgoing.y + outgoing.z * outgoing.z)
    if incoming_length <= .001 || outgoing_length <= .001 do return {1, 0, 0}
    incoming /= incoming_length
    outgoing /= outgoing_length
    tangent := incoming + outgoing
    tangent_length := math.sqrt(tangent.x * tangent.x + tangent.y * tangent.y + tangent.z * tangent.z)
    if tangent_length > .18 do return tangent / tangent_length
    // At a near reversal the ordinary bisector collapses. A horizontal
    // tangent rounds the shared node into a hairpin and gives both incident
    // splines the same carriageway orientation at the acute connection.
    cross := incoming.x * outgoing.z - incoming.z * outgoing.x
    side: f32 = cross < 0 ? -1 : 1
    tangent = {-incoming.z * side, 0, incoming.x * side}
    tangent_length = math.sqrt(tangent.x * tangent.x + tangent.z * tangent.z)
    return tangent_length > .001 ? tangent / tangent_length : roads.Vec3{1, 0, 0}
}

road_planning_add_smooth_chain :: proc(
    graph: ^roads.Graph,
    nodes: []int,
    points: []roads.Vec3,
    width, shoulder: f32,
    pavement: roads.Pavement,
) -> int {
    if graph == nil || len(nodes) != len(points) || len(nodes) < 2 do return -1
    last_edge := -1
    for index in 0 ..< len(nodes) - 1 {
        segment := points[index + 1] - points[index]
        segment_length := math.sqrt(segment.x * segment.x + segment.y * segment.y + segment.z * segment.z)
        if segment_length <= .001 do return -1
        from_tangent := road_planning_smooth_tangent(points, index)
        to_tangent := road_planning_smooth_tangent(points, index + 1)
        handle := min(segment_length / 3, max(width * .75, segment_length * .22))
        last_edge = roads.add_edge(
            graph,
            nodes[index],
            nodes[index + 1],
            points[index] + from_tangent * handle,
            points[index + 1] - to_tangent * handle,
            width,
            shoulder,
            pavement,
        )
        if last_edge < 0 do return -1
    }
    return last_edge
}

road_planning_lab_rebuild_road :: proc(editor: ^Editor) {
    if editor == nil || road_planning_lab.workspace == nil do return
    editor.project.road_graph = {}
    road_planning_lab.result = {}
    road_planning_lab.route_bend_count = 0
    road_planning_lab.graph_too_complex = false
    road_planning_lab.committed = false
    if road_planning_lab.point_count < 2 do return
    grid := road_planning_lab_sample_grid()
    road_planning_lab.result = road_planner.plan(
        road_planning_lab.workspace,
        grid,
        road_planning_lab.config,
        road_planning_lab.points[0],
        road_planning_lab.points[1],
    )
    if !road_planning_lab.result.found do return
    bend_count := 0
    previous_dx, previous_dz := f32(0), f32(0)
    for index in 0 ..< road_planning_lab.result.point_count {
        if index == 0 || index == road_planning_lab.result.point_count - 1 {
            bend_count += 1
            continue
        }
        previous := road_planning_lab.result.points[index - 1]
        point := road_planning_lab.result.points[index]
        dx, dz := point.x - previous.x, point.z - previous.z
        if index == 1 || dx != previous_dx || dz != previous_dz do bend_count += 1
        previous_dx, previous_dz = dx, dz
    }
    road_planning_lab.route_bend_count = bend_count
    road_planning_lab.graph_too_complex = false
    if road_planning_lab.optimizer == nil || road_planning_lab.design_work == nil do return
    _ = road_designer.begin(road_planning_lab.optimizer, {
            grid            = grid,
            cell_size       = road_planning_lab.config.cell_size,
            start           = road_planning_lab.points[0],
            finish          = road_planning_lab.points[1],
            pavement        = road_planning_lab.pavement,
            width           = 4.2,
            shoulder        = 1.2,
            sea_level       = grid.sea_level,
            available_nodes = roads.MAX_NODES,
            available_edges = roads.MAX_EDGES,
            seed            = road_planning_lab.seed,
        }, road_planning_lab.design_work)
    editor.project.revision += 1
}

road_planning_lab_status :: proc() -> cstring {
    if road_planning_lab.graph_too_complex {
        return fmt.ctprintf(
            "ROUTE HAS %d BENDS; ROAD GRAPH LIMIT IS %d",
            road_planning_lab.route_bend_count,
            roads.MAX_NODES,
        )
    }
    if road_planning_lab.optimizer != nil && road_planning_lab.result.found {
        state := "RUNNING"
        switch road_planning_lab.optimizer.status {
        case .Complete:
            state = "COMPLETE"
        case .Cancelled:
            state = "CANCELLED"
        case .No_Route:
            state = "NO ROUTE"
        case .Capacity:
            state = "CAPACITY"
        case .Idle:
            state = "IDLE"
        case .Running:
        }
        return fmt.ctprintf(
            "%s • GEN %d / %d EVAL",
            state,
            road_planning_lab.optimizer.generation,
            road_planning_lab.optimizer.evaluations,
        )
    }
    if road_planning_lab.workspace == nil do return "PLANNER WORKSPACE IS UNAVAILABLE"
    if road_planning_lab.point_count < 2 do return "SELECT BOTH ROAD ENDPOINTS"
    if road_planning_lab.config.cell_size <= 0 do return "CELL SIZE MUST BE GREATER THAN ZERO"
    grid := road_planning_lab_sample_grid()
    start, finish := road_planning_lab.points[0], road_planning_lab.points[1]
    start_x := clamp(
        int(math.round((start.x - grid.origin_x) / road_planning_lab.config.cell_size)),
        0,
        grid.width - 1,
    )
    start_z := clamp(
        int(math.round((start.z - grid.origin_z) / road_planning_lab.config.cell_size)),
        0,
        grid.height - 1,
    )
    finish_x := clamp(
        int(math.round((finish.x - grid.origin_x) / road_planning_lab.config.cell_size)),
        0,
        grid.width - 1,
    )
    finish_z := clamp(
        int(math.round((finish.z - grid.origin_z) / road_planning_lab.config.cell_size)),
        0,
        grid.height - 1,
    )
    if start_x == finish_x && start_z == finish_z do return "ENDPOINTS SNAP TO THE SAME PLANNER CELL"
    return fmt.ctprintf("SEARCH EXHAUSTED AFTER %d EXPANDED STATES", road_planning_lab.result.expanded)
}

road_planning_lab_configure :: proc(editor: ^Editor, _: string) -> bool {
    if editor == nil do return false
    if road_planning_lab.workspace != nil do free(road_planning_lab.workspace)
    road_planning_lab = {
        config                = road_planner.default_config(),
        workspace             = new(road_planner.Workspace),
        seed                  = 0x524f4144,
        dragging              = -1,
        editing               = -1,
        optimizer             = new(road_designer.Optimizer),
        design_work           = new(road_designer.Workspace),
        pavement              = .Gravel,
        alternative           = .Recommended,
        show_all              = true,
        evaluations_per_frame = 8,
    }
    road_planning_lab.points = {{-720, -420}, {720, 430}}
    road_planning_lab.point_count = 2
    road_planner.set_generation_config(road_planning_lab.config)
    road_planning_lab_apply_terrain(editor)
    road_planning_lab_rebuild_road(editor)
    editor.in_map = false
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    set_pointer_locked(false)
    eye := third_person.Vec3{920, 1120, -1020}
    target := third_person.Vec3{0, 20, 0}
    delta := eye - target
    distance := f32(math.sqrt(f64(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)))
    editor.editor_focus = target
    editor.editor_camera = {
        yaw_radians   = f32(math.atan2(f64(delta.x), f64(delta.z))),
        pitch_radians = f32(math.asin(f64(clamp(delta.y / distance, -1, 1)))),
        distance      = distance,
    }
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

road_planning_lab_exit :: proc(_: ^Editor) {
    if road_planning_lab.workspace != nil do free(road_planning_lab.workspace)
    road_planning_lab.workspace = nil
    if road_planning_lab.optimizer != nil do free(road_planning_lab.optimizer)
    if road_planning_lab.design_work != nil do free(road_planning_lab.design_work)
    road_planning_lab.optimizer = nil
    road_planning_lab.design_work = nil
    road_planning_lab.dragging = -1
    road_planning_lab.editing = -1
    _ = canvas2d.StopTextInput()
}

road_planning_lab_cursor_position :: proc(editor: ^Editor) -> (x, z: f32, hit: bool) {
    if editor == nil do return 0, 0, false
    // Lab input runs before the editor's shared cursor raycast. Reading
    // editor.cursor_world_* here would therefore place an endpoint at the
    // previous frame's mouse position, which is especially visible when a
    // press follows a quick pointer move.
    world_mouse, world_mouse_inside := canvas2d.GetWorldMousePosition()
    if !world_mouse_inside do return 0, 0, false
    world_render_width, world_render_height := canvas2d.GetWorldRenderSize()
    camera := perspective_camera(editor.camera_pose, 1.35)
    return terrain_under_cursor_3d(editor, camera, world_mouse, world_render_width, world_render_height)
}

road_planning_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    changed := false
    width := canvas2d.GetScreenWidth()
    panel := road_planning_lab_panel(width)
    mouse := canvas2d.GetMousePosition()
    pointer_in_panel := canvas2d.CheckCollisionPointRec(mouse, panel)
    if canvas2d.IsMouseButtonPressed(.LEFT) && pointer_in_panel {
        for index in 0 ..< ROAD_PLANNING_LAB_SLIDER_COUNT {
            input_bounds := road_planning_lab_input_bounds(int(width), index)
            if canvas2d.CheckCollisionPointRec(mouse, input_bounds) {
                road_planning_lab_begin_input(index)
                break
            }
            bounds := road_planning_lab_slider_bounds(int(width), index)
            if canvas2d.CheckCollisionPointRec(mouse, bounds) {
                if road_planning_lab.regen_pending {
                    changed = true
                    road_planning_lab.regen_pending = false
                }
                road_planning_lab.editing = -1
                _ = canvas2d.StopTextInput()
                road_planning_lab.dragging = index
                changed = road_planning_lab_set_slider(index, (mouse.x - bounds.x) / bounds.width) || changed
                break
            }
        }
    }
    if road_planning_lab.editing >= 0 {
        input_bounds := road_planning_lab_input_bounds(int(width), road_planning_lab.editing)
        _ = canvas2d.SetTextInputArea(input_bounds, road_planning_lab.input_length)
        input_changed := road_planning_lab_append_input(canvas2d.GetTextInput())
        if canvas2d.IsKeyPressed(.BACKSPACE) && road_planning_lab.input_length > 0 {
            road_planning_lab.input_length -= 1
            input_changed = true
        }
        if input_changed && road_planning_lab_apply_input() {
            road_planning_lab.regen_pending = true
            road_planning_lab.regen_at = canvas2d.GetTime() + ROAD_PLANNING_LAB_INPUT_DEBOUNCE_SECONDS
        }
        if canvas2d.IsKeyPressed(.ENTER) ||
           canvas2d.IsKeyPressed(.ESCAPE) ||
           (canvas2d.IsMouseButtonPressed(.LEFT) && !canvas2d.CheckCollisionPointRec(mouse, input_bounds)) {
            if road_planning_lab.regen_pending {
                changed = true
                road_planning_lab.regen_pending = false
            }
            road_planning_lab.editing = -1
            _ = canvas2d.StopTextInput()
        }
    }
    if canvas2d.IsMouseButtonDown(.LEFT) && road_planning_lab.dragging >= 0 {
        bounds := road_planning_lab_slider_bounds(int(width), road_planning_lab.dragging)
        changed =
            road_planning_lab_set_slider(road_planning_lab.dragging, (mouse.x - bounds.x) / bounds.width) || changed
    }
    if canvas2d.IsMouseButtonReleased(.LEFT) do road_planning_lab.dragging = -1
    if !pointer_in_panel && canvas2d.IsMouseButtonPressed(.LEFT) {
        cursor_x, cursor_z, cursor_hit := road_planning_lab_cursor_position(editor)
        if cursor_hit {
            slot := road_planning_lab.next_endpoint
            extent := f32(ROAD_PLANNING_LAB_GRID - 1) * road_planning_lab.config.cell_size * .5
            road_planning_lab.points[slot] = {clamp(cursor_x, -extent, extent), clamp(cursor_z, -extent, extent)}
            road_planning_lab.point_count = min(road_planning_lab.point_count + 1, 2)
            road_planning_lab.next_endpoint = (slot + 1) % 2
            changed = true
        }
    }
    if canvas2d.IsKeyPressed(.R) {
        road_planning_lab.seed += 0x9e3779b9
        road_planning_lab_apply_terrain(editor)
        changed = true
    }
    if canvas2d.IsKeyPressed(.SPACE) do changed = true
    if canvas2d.IsKeyPressed(.S) {
        switch road_planning_lab.pavement {
        case .Asphalt:
            road_planning_lab.pavement = .Gravel
        case .Gravel:
            road_planning_lab.pavement = .Cobblestone
        case .Cobblestone:
            road_planning_lab.pavement = .Dirt
        case .Dirt:
            road_planning_lab.pavement = .Asphalt
        case .Steps:
            road_planning_lab.pavement = .Gravel
        }
        changed = true
    }
    if canvas2d.IsKeyPressed(.ONE) do road_planning_lab.alternative = .Recommended
    if canvas2d.IsKeyPressed(.TWO) do road_planning_lab.alternative = .Cheapest
    if canvas2d.IsKeyPressed(.THREE) do road_planning_lab.alternative = .Fastest
    if canvas2d.IsKeyPressed(.FOUR) do road_planning_lab.alternative = .Lightest_Impact
    if canvas2d.IsKeyPressed(.P) do road_planning_lab.paused = !road_planning_lab.paused
    if canvas2d.IsKeyPressed(.O) do road_planning_lab.show_all = !road_planning_lab.show_all
    if road_planning_lab.regen_pending && canvas2d.GetTime() >= road_planning_lab.regen_at {
        changed = true
        road_planning_lab.regen_pending = false
    }
    if changed do road_planning_lab_rebuild_road(editor)
    if road_planning_lab.optimizer != nil &&
       !road_planning_lab.paused &&
       !road_planning_lab.committed &&
       road_planning_lab.optimizer.status == .Running {
        started := canvas2d.GetTime()
        _ = road_designer.step(road_planning_lab.optimizer, road_planning_lab.evaluations_per_frame)
        elapsed_ms := (canvas2d.GetTime() - started) * 1000
        if elapsed_ms > 4 && road_planning_lab.evaluations_per_frame > 1 {
            road_planning_lab.evaluations_per_frame = max(1, road_planning_lab.evaluations_per_frame / 2)
        } else if elapsed_ms < 2 && road_planning_lab.evaluations_per_frame < 8 {
            road_planning_lab.evaluations_per_frame += 1
        }
    }
    if canvas2d.IsKeyPressed(.ENTER) && road_planning_lab.optimizer != nil && !road_planning_lab.committed {
        if selected, ok := road_designer.candidate(road_planning_lab.optimizer, road_planning_lab.alternative); ok {
            graph: roads.Graph
            design_id := road_design_next_id(&graph)
            if result := road_designer.materialize(selected, &graph, design_id);
               result.ok && road_design_commit_graph(editor, graph, design_id) {
                road_planning_lab.committed = true
                road_planning_lab.paused = true
            }
        }
    }
}

world_road_planning_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    graph := &editor.project.road_graph
    if !road_planning_lab.committed && road_planning_lab.result.found && road_planning_lab.result.point_count >= 2 {
        previous_point := road_planning_lab.result.points[0]
        previous := roads.Vec3 {
            previous_point.x,
            terrain.sample_surface_height(&editor.project, 0, previous_point.x, previous_point.z),
            previous_point.z,
        }
        for point in road_planning_lab.result.points[1:road_planning_lab.result.point_count] {
            current := roads.Vec3 {
                point.x,
                terrain.sample_surface_height(&editor.project, 0, point.x, point.z),
                point.z,
            }
            world_road_editor_link(previous, current, 2.2, {211, 177, 101, 90})
            previous = current
        }
    }
    if !road_planning_lab.committed && road_planning_lab.optimizer != nil {
        alternatives := [4]road_designer.Named_Alternative{.Recommended, .Cheapest, .Fastest, .Lightest_Impact}
        colors := [4]canvas2d.Color {
            {75, 211, 239, 235},
            {245, 190, 82, 190},
            {238, 112, 99, 190},
            {125, 211, 129, 190},
        }
        for alternative, alternative_index in alternatives {
            if !road_planning_lab.show_all && alternative != road_planning_lab.alternative do continue
            selected, ok := road_designer.candidate(road_planning_lab.optimizer, alternative)
            if !ok || selected.point_count < 2 do continue
            color := colors[alternative_index]
            width := alternative == road_planning_lab.alternative ? f32(4.2) : f32(2.1)
            previous := selected.centerline[0]
            for current in selected.centerline[1:selected.point_count] {
                world_road_editor_link(previous, current, width, color)
                previous = current
            }
        }
    }
    // The planner result remains useful even when it contains more bends than
    // the fixed road graph can store. Show that route directly so a capacity
    // warning never reduces the world view to endpoint handles alone.
    if road_planning_lab.optimizer == nil &&
       graph.edge_count == 0 &&
       road_planning_lab.result.found &&
       road_planning_lab.result.point_count >= 2 {
        previous_point := road_planning_lab.result.points[0]
        previous := roads.Vec3 {
            previous_point.x,
            terrain.sample_surface_height(&editor.project, 0, previous_point.x, previous_point.z),
            previous_point.z,
        }
        for point in road_planning_lab.result.points[1:road_planning_lab.result.point_count] {
            current := roads.Vec3 {
                point.x,
                terrain.sample_surface_height(&editor.project, 0, point.x, point.z),
                point.z,
            }
            world_road_editor_link(previous, current, 6.6, {211, 177, 101, 92})
            world_road_editor_link(previous, current, 4.2, {75, 211, 239, 180})
            previous = current
        }
    }
    // This lab replaces the ordinary world tail, so its generated graph never
    // reaches world_roads_transient. Draw the planned carriageway here as the
    // lab's dedicated preview instead of relying on the editor brush path.
    for edge in graph.edges[:graph.edge_count] {
        previous := roads.edge_point(graph, edge, 0)
        for segment in 1 ..= 32 {
            current := roads.edge_point(graph, edge, f32(segment) / 32)
            previous.y = terrain.sample_surface_height(&editor.project, 0, previous.x, previous.z)
            current.y = terrain.sample_surface_height(&editor.project, 0, current.x, current.z)
            world_road_editor_link(
                previous,
                current,
                edge.half_width * 2 + edge.shoulder_width * 2,
                {211, 177, 101, 92},
            )
            world_road_editor_link(previous, current, edge.half_width * 2, {75, 211, 239, 180})
            previous = current
        }
    }
    colors := [2]canvas2d.Color{{75, 211, 239, 255}, {245, 160, 70, 255}}
    for point, index in road_planning_lab.points[:road_planning_lab.point_count] {
        y := terrain.sample_surface_height(&editor.project, 0, point.x, point.z)
        world_box({point.x, y + 5, point.z}, {8, 10, 8}, colors[index])
    }
}

road_planning_lab_draw_ui :: proc(_: ^Editor, width, _: i32) {
    panel := road_planning_lab_panel(width)
    canvas2d.DrawRectangleRounded(panel, .05, 9, {15, 23, 26, 244})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .05, 9, 1, {75, 211, 239, 255})
    ui_draw_text(.Label, "ROAD PLANNING", {panel.x + 20, panel.y + 18}, .54, {111, 222, 239, 255})
    ui_draw_text(
        .Data,
        "EDIT COSTS • UPDATES AUTOMATICALLY",
        {panel.x + 20, panel.y + 50},
        .19,
        {152, 179, 183, 255},
    )
    status := road_planning_lab_status()
    ui_draw_text(.Data, status, {panel.x + 20, panel.y + 76}, .20, {181, 216, 218, 255})
    labels := [ROAD_PLANNING_LAB_SLIDER_COUNT]cstring {
        "CELL SIZE",
        "LENGTH COST",
        "GRADE",
        "STEEP GRADE",
        "WATER",
        "TURN",
        "SWITCHBACK",
        "MAX GRADE",
        "HEURISTIC",
    }
    for label, index in labels {
        value, low, high := road_planning_lab_slider_value(index)
        normalized := (value - low) / (high - low)
        bounds := road_planning_lab_slider_bounds(int(width), index)
        input_bounds := road_planning_lab_input_bounds(int(width), index)
        ui_draw_text(.Label, label, {panel.x + 20, bounds.y + 7}, .22, {188, 201, 202, 255})
        canvas2d.DrawRectangleRounded({bounds.x, bounds.y + 10, bounds.width, 8}, 1, 4, {44, 57, 60, 255})
        canvas2d.DrawRectangleRounded(
            {bounds.x, bounds.y + 10, bounds.width * normalized, 8},
            1,
            4,
            {75, 211, 239, 255},
        )
        canvas2d.DrawCircleV({bounds.x + bounds.width * normalized, bounds.y + 14}, 7, {236, 242, 235, 255})
        canvas2d.DrawRectangleRounded(
            input_bounds,
            .14,
            5,
            index == road_planning_lab.editing ? canvas2d.Color{42, 63, 68, 255} : canvas2d.Color{30, 42, 45, 255},
        )
        canvas2d.DrawRectangleRoundedLinesEx(
            input_bounds,
            .14,
            5,
            1,
            index == road_planning_lab.editing ? canvas2d.Color{111, 222, 239, 255} : canvas2d.Color{67, 88, 92, 255},
        )
        display: cstring
        if index == road_planning_lab.editing {
            display = fmt.ctprintf("%s", road_planning_lab_input_text())
        } else if index == 7 {
            display = fmt.ctprintf("%.1f%%", value * 100)
        } else if index == 0 || index == 3 || index == 4 {
            display = fmt.ctprintf("%.1f", value)
        } else {
            display = fmt.ctprintf("%.2f", value)
        }
        ui_draw_text(.Data, display, {input_bounds.x + 7, input_bounds.y + 9}, .17, {202, 218, 218, 255})
    }
    selected_name := "RECOMMENDED"
    switch road_planning_lab.alternative {
    case .Cheapest:
        selected_name = "CHEAPEST"
    case .Fastest:
        selected_name = "FASTEST"
    case .Lightest_Impact:
        selected_name = "LIGHTEST IMPACT"
    case .Recommended:
    }
    summary_y := panel.y + 548
    ui_draw_text(
        .Data,
        fmt.ctprintf("SURFACE %s • %s", roads.pavement_name(road_planning_lab.pavement), selected_name),
        {panel.x + 20, summary_y},
        .18,
        {111, 222, 239, 255},
    )
    if road_planning_lab.optimizer != nil {
        if selected, ok := road_designer.candidate(road_planning_lab.optimizer, road_planning_lab.alternative); ok {
            metrics := selected.metrics
            ui_draw_text(
                .Data,
                fmt.ctprintf(
                    "%.0fm • CUT %.0f / FILL %.0f • %.1f%% GRADE",
                    metrics.length,
                    metrics.cut_volume,
                    metrics.fill_volume,
                    metrics.maximum_grade * 100,
                ),
                {panel.x + 20, summary_y + 20},
                .16,
                {188, 201, 202, 255},
            )
            ui_draw_text(
                .Data,
                fmt.ctprintf("BRIDGE %.0fm • CULVERT %d", metrics.bridge_length, metrics.culvert_count),
                {panel.x + 20, summary_y + 40},
                .16,
                {188, 201, 202, 255},
            )
        }
    }
    ui_draw_text(
        .Data,
        "1–4 ALT • S SURFACE • P PAUSE • O OVERLAYS",
        {panel.x + 20, panel.y + panel.height - 54},
        .15,
        {160, 180, 181, 255},
    )
    ui_draw_text(
        .Data,
        "ENTER COMMIT • CLICK MAP MOVE ENDPOINT • R TERRAIN",
        {panel.x + 20, panel.y + panel.height - 34},
        .15,
        {160, 180, 181, 255},
    )
    ui_draw_text(
        .Data,
        "COMPARE LENGTH, GRADE, WATER, AND TURNS",
        {panel.x + 20, panel.y + panel.height - 16},
        .15,
        {239, 178, 91, 255},
    )
}
