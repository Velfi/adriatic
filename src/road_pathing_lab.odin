package main

import road_planner "../packages/road_planner"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:math"
import "core:strconv"
import canvas2d "zelda_engine:canvas2d"

ROAD_PATHING_LAB_NETWORK_COUNT :: 3
ROAD_PATHING_LAB_ROUTE_CAPACITY :: 21
ROAD_PATHING_LAB_SLIDER_COUNT :: 9

Road_Pathing_Lab_Route :: struct {
    result: road_planner.Result,
    scale:  int,
}

Road_Pathing_Lab_State :: struct {
    config:       road_planner.Config,
    workspace:    ^road_planner.Workspace,
    heights:      [ROAD_PLANNING_LAB_SAMPLE_COUNT]f32,
    routes:       [ROAD_PATHING_LAB_ROUTE_CAPACITY]Road_Pathing_Lab_Route,
    route_count:  int,
    found_count:  [ROAD_PATHING_LAB_NETWORK_COUNT]int,
    requested:    [ROAD_PATHING_LAB_NETWORK_COUNT]int,
    seed:         u32,
    dragging:     int,
    editing:      int,
    input:        [24]u8,
    input_length: int,
    dirty:        bool,
}

road_pathing_lab: Road_Pathing_Lab_State

road_pathing_lab_panel :: proc(width: i32) -> canvas2d.Rectangle {
    return {f32(width) - 430, 24, 406, 672}
}

road_pathing_lab_slider_bounds :: proc(width, index: int) -> canvas2d.Rectangle {
    panel := road_pathing_lab_panel(i32(width))
    return {panel.x + 190, panel.y + 102 + f32(index) * 48, panel.width - 286, 30}
}

road_pathing_lab_input_bounds :: proc(width, index: int) -> canvas2d.Rectangle {
    panel := road_pathing_lab_panel(i32(width))
    return {panel.x + panel.width - 84, panel.y + 99 + f32(index) * 48, 64, 30}
}

road_pathing_lab_regen_bounds :: proc(width: i32) -> canvas2d.Rectangle {
    panel := road_pathing_lab_panel(width)
    return {panel.x + 20, panel.y + 548, panel.width - 40, 42}
}

road_pathing_lab_slider_value :: proc(index: int) -> (value, low, high: f32) {
    switch index {
    case 0:
        return road_pathing_lab.config.cell_size, 6, 48
    case 1:
        return road_pathing_lab.config.length_cost, .1, 4
    case 2:
        return road_pathing_lab.config.grade_cost, 0, 150
    case 3:
        return road_pathing_lab.config.steep_grade_cost, 0, 1000
    case 4:
        return road_pathing_lab.config.water_cost, 0, 1500
    case 5:
        return road_pathing_lab.config.turn_cost, 0, 30
    case 6:
        return road_pathing_lab.config.switchback_cost, 0, 100
    case 7:
        return road_pathing_lab.config.maximum_grade, .02, .6
    case 8:
        return road_pathing_lab.config.heuristic_weight, .8, 1.5
    }
    return 0, 0, 1
}

road_pathing_lab_set_slider :: proc(index: int, normalized: f32) -> bool {
    previous, low, high := road_pathing_lab_slider_value(index)
    value := low + clamp(normalized, 0, 1) * (high - low)
    if value == previous do return false
    switch index {
    case 0:
        road_pathing_lab.config.cell_size = value
    case 1:
        road_pathing_lab.config.length_cost = value
    case 2:
        road_pathing_lab.config.grade_cost = value
    case 3:
        road_pathing_lab.config.steep_grade_cost = value
    case 4:
        road_pathing_lab.config.water_cost = value
    case 5:
        road_pathing_lab.config.turn_cost = value
    case 6:
        road_pathing_lab.config.switchback_cost = value
    case 7:
        road_pathing_lab.config.maximum_grade = value
    case 8:
        road_pathing_lab.config.heuristic_weight = value
    }
    road_pathing_lab.dirty = true
    return true
}

road_pathing_lab_begin_input :: proc(index: int) {
    road_pathing_lab.editing = index
    road_pathing_lab.dragging = -1
    road_pathing_lab.input = {}
    value, _, _ := road_pathing_lab_slider_value(index)
    if index == 7 do value *= 100
    formatted := fmt.bprintf(road_pathing_lab.input[:], "%.3f", value)
    road_pathing_lab.input_length = len(formatted)
    _ = canvas2d.StartTextInput()
}

road_pathing_lab_apply_input :: proc() -> bool {
    if road_pathing_lab.editing < 0 do return false
    parsed, ok := strconv.parse_f32(string(road_pathing_lab.input[:road_pathing_lab.input_length]))
    if !ok do return false
    _, low, high := road_pathing_lab_slider_value(road_pathing_lab.editing)
    value := parsed
    if road_pathing_lab.editing == 7 do value *= .01
    value = clamp(value, low, high)
    return road_pathing_lab_set_slider(road_pathing_lab.editing, (value - low) / (high - low))
}

road_pathing_lab_append_input :: proc(text: string) -> bool {
    changed := false
    for byte in transmute([]u8)text {
        if road_pathing_lab.input_length >= len(road_pathing_lab.input) do break
        if (byte >= '0' && byte <= '9') || byte == '.' || byte == '-' || byte == 'e' || byte == 'E' {
            road_pathing_lab.input[road_pathing_lab.input_length] = byte
            road_pathing_lab.input_length += 1
            changed = true
        }
    }
    return changed
}

road_pathing_lab_grid :: proc(center: road_planner.Point) -> road_planner.Grid {
    extent := f32(ROAD_PLANNING_LAB_GRID - 1) * road_pathing_lab.config.cell_size
    origin_x, origin_z := center.x - extent * .5, center.z - extent * .5
    for z in 0 ..< ROAD_PLANNING_LAB_GRID {
        for x in 0 ..< ROAD_PLANNING_LAB_GRID {
            world_x := origin_x + f32(x) * road_pathing_lab.config.cell_size
            world_z := origin_z + f32(z) * road_pathing_lab.config.cell_size
            road_pathing_lab.heights[z * ROAD_PLANNING_LAB_GRID + x] = road_planning_lab_height(
                world_x,
                world_z,
                road_pathing_lab.seed,
            )
        }
    }
    return {
        origin_x = origin_x,
        origin_z = origin_z,
        width = ROAD_PLANNING_LAB_GRID,
        height = ROAD_PLANNING_LAB_GRID,
        sea_level = 0,
        heights = road_pathing_lab.heights[:],
    }
}

road_pathing_lab_add_route :: proc(grid: road_planner.Grid, scale: int, a, b: road_planner.Point) {
    if road_pathing_lab.route_count >= len(road_pathing_lab.routes) do return
    route := &road_pathing_lab.routes[road_pathing_lab.route_count]
    route^ = {}
    route.scale = scale
    route.result = road_planner.plan(road_pathing_lab.workspace, grid, road_pathing_lab.config, a, b)
    road_pathing_lab.requested[scale] += 1
    if route.result.found do road_pathing_lab.found_count[scale] += 1
    road_pathing_lab.route_count += 1
}

road_pathing_lab_generate_network :: proc(scale: int, center: road_planner.Point, radius: f32, spokes, rings: int) {
    grid := road_pathing_lab_grid(center)
    points: [10]road_planner.Point
    for spoke in 0 ..< spokes {
        angle := f32(spoke) / f32(spokes) * math.TAU
        wobble := road_planning_lab_noise(f32(spoke) * 1.7, f32(scale) * 3.1, road_pathing_lab.seed) * .13
        distance := radius * (1 + wobble)
        points[spoke] = {center.x + math.cos(angle) * distance, center.z + math.sin(angle) * distance}
        road_pathing_lab_add_route(grid, scale, center, points[spoke])
    }
    if rings > 0 {
        for spoke in 0 ..< spokes {
            next := (spoke + 1) % spokes
            road_pathing_lab_add_route(grid, scale, points[spoke], points[next])
        }
    }
}

road_pathing_lab_regenerate :: proc(editor: ^Editor, advance_seed: bool = false) {
    if editor == nil || road_pathing_lab.workspace == nil do return
    if advance_seed {
        road_pathing_lab.seed += 0x9e3779b9
        road_planning_lab.seed = road_pathing_lab.seed
        road_planning_lab_apply_terrain(editor)
    }
    road_planner.set_generation_config(road_pathing_lab.config)
    road_pathing_lab.route_count = 0
    road_pathing_lab.found_count = {}
    road_pathing_lab.requested = {}
    road_pathing_lab_generate_network(0, {-760, 0}, 125, 3, 0)
    road_pathing_lab_generate_network(1, {0, 0}, 205, 5, 1)
    road_pathing_lab_generate_network(2, {820, 0}, 315, 6, 1)
    road_pathing_lab.dirty = false
    editor.project.revision += 1
}

road_pathing_lab_configure :: proc(editor: ^Editor, _: string) -> bool {
    if editor == nil do return false
    if road_pathing_lab.workspace != nil do free(road_pathing_lab.workspace)
    road_pathing_lab = {
        config    = road_planner.default_config(),
        workspace = new(road_planner.Workspace),
        seed      = 0x56494c4c,
        dragging  = -1,
        editing   = -1,
    }
    road_planning_lab.seed = road_pathing_lab.seed
    road_planning_lab_apply_terrain(editor)
    road_pathing_lab_regenerate(editor)
    editor.in_map = false
    editor.capture_world_only = false
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.rondine_visible = false
    set_pointer_locked(false)
    eye := third_person.Vec3{100, 1780, -2050}
    target := third_person.Vec3{80, 12, 0}
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

road_pathing_lab_exit :: proc(_: ^Editor) {
    if road_pathing_lab.workspace != nil do free(road_pathing_lab.workspace)
    road_pathing_lab.workspace = nil
    road_pathing_lab.dragging = -1
    road_pathing_lab.editing = -1
    _ = canvas2d.StopTextInput()
}

road_pathing_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    width := canvas2d.GetScreenWidth()
    panel := road_pathing_lab_panel(width)
    mouse := canvas2d.GetMousePosition()
    if canvas2d.IsMouseButtonPressed(.LEFT) && canvas2d.CheckCollisionPointRec(mouse, panel) {
        if canvas2d.CheckCollisionPointRec(mouse, road_pathing_lab_regen_bounds(width)) {
            road_pathing_lab_regenerate(editor)
            return
        }
        for index in 0 ..< ROAD_PATHING_LAB_SLIDER_COUNT {
            input_bounds := road_pathing_lab_input_bounds(int(width), index)
            if canvas2d.CheckCollisionPointRec(mouse, input_bounds) {
                road_pathing_lab_begin_input(index)
                break
            }
            bounds := road_pathing_lab_slider_bounds(int(width), index)
            if canvas2d.CheckCollisionPointRec(mouse, bounds) {
                road_pathing_lab.editing = -1
                _ = canvas2d.StopTextInput()
                road_pathing_lab.dragging = index
                _ = road_pathing_lab_set_slider(index, (mouse.x - bounds.x) / bounds.width)
                break
            }
        }
    }
    if road_pathing_lab.editing >= 0 {
        input_bounds := road_pathing_lab_input_bounds(int(width), road_pathing_lab.editing)
        _ = canvas2d.SetTextInputArea(input_bounds, road_pathing_lab.input_length)
        input_changed := road_pathing_lab_append_input(canvas2d.GetTextInput())
        if canvas2d.IsKeyPressed(.BACKSPACE) && road_pathing_lab.input_length > 0 {
            road_pathing_lab.input_length -= 1
            input_changed = true
        }
        if input_changed do _ = road_pathing_lab_apply_input()
        if canvas2d.IsKeyPressed(.ENTER) ||
           canvas2d.IsKeyPressed(.ESCAPE) ||
           (canvas2d.IsMouseButtonPressed(.LEFT) && !canvas2d.CheckCollisionPointRec(mouse, input_bounds)) {
            road_pathing_lab.editing = -1
            _ = canvas2d.StopTextInput()
        }
    }
    if canvas2d.IsMouseButtonDown(.LEFT) && road_pathing_lab.dragging >= 0 {
        bounds := road_pathing_lab_slider_bounds(int(width), road_pathing_lab.dragging)
        _ = road_pathing_lab_set_slider(road_pathing_lab.dragging, (mouse.x - bounds.x) / bounds.width)
    }
    if canvas2d.IsMouseButtonReleased(.LEFT) do road_pathing_lab.dragging = -1
    if canvas2d.IsKeyPressed(.R) do road_pathing_lab_regenerate(editor, true)
    if canvas2d.IsKeyPressed(.SPACE) do road_pathing_lab_regenerate(editor)
}

world_road_pathing_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    colors := [ROAD_PATHING_LAB_NETWORK_COUNT]canvas2d.Color {
        {114, 211, 133, 230},
        {238, 183, 77, 230},
        {75, 211, 239, 235},
    }
    widths := [ROAD_PATHING_LAB_NETWORK_COUNT]f32{3.2, 4.8, 6.4}
    centers := [ROAD_PATHING_LAB_NETWORK_COUNT]road_planner.Point{{-760, 0}, {0, 0}, {820, 0}}
    for &route in road_pathing_lab.routes[:road_pathing_lab.route_count] {
        if !route.result.found || route.result.point_count < 2 do continue
        previous_point := route.result.points[0]
        previous := roads.Vec3 {
            previous_point.x,
            terrain.sample_surface_height(&editor.project, 0, previous_point.x, previous_point.z),
            previous_point.z,
        }
        for point in route.result.points[1:route.result.point_count] {
            current := roads.Vec3 {
                point.x,
                terrain.sample_surface_height(&editor.project, 0, point.x, point.z),
                point.z,
            }
            world_road_editor_link(previous, current, widths[route.scale], colors[route.scale])
            previous = current
        }
    }
    for center, index in centers {
        y := terrain.sample_surface_height(&editor.project, 0, center.x, center.z)
        world_box({center.x, y + 6, center.z}, {12, 12, 12}, colors[index])
    }
}

road_pathing_lab_draw_ui :: proc(_: ^Editor, width, _: i32) {
    panel := road_pathing_lab_panel(width)
    canvas2d.DrawRectangleRounded(panel, .05, 9, {15, 23, 26, 244})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .05, 9, 1, {75, 211, 239, 255})
    ui_draw_text(.Label, "SETTLEMENT ROAD PATHING", {panel.x + 20, panel.y + 18}, .46, {111, 222, 239, 255})
    ui_draw_text(.Data, "VILLAGE • TOWN • CITY", {panel.x + 20, panel.y + 50}, .20, {152, 179, 183, 255})
    ui_draw_text(
        .Data,
        fmt.ctprintf(
            "ROUTES %d/%d  •  %d/%d  •  %d/%d",
            road_pathing_lab.found_count[0],
            road_pathing_lab.requested[0],
            road_pathing_lab.found_count[1],
            road_pathing_lab.requested[1],
            road_pathing_lab.found_count[2],
            road_pathing_lab.requested[2],
        ),
        {panel.x + 20, panel.y + 76},
        .18,
        {181, 216, 218, 255},
    )
    labels := [ROAD_PATHING_LAB_SLIDER_COUNT]cstring {
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
        value, low, high := road_pathing_lab_slider_value(index)
        normalized := (value - low) / (high - low)
        bounds := road_pathing_lab_slider_bounds(int(width), index)
        input_bounds := road_pathing_lab_input_bounds(int(width), index)
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
            index == road_pathing_lab.editing ? canvas2d.Color{42, 63, 68, 255} : canvas2d.Color{30, 42, 45, 255},
        )
        canvas2d.DrawRectangleRoundedLinesEx(
            input_bounds,
            .14,
            5,
            1,
            index == road_pathing_lab.editing ? canvas2d.Color{111, 222, 239, 255} : canvas2d.Color{67, 88, 92, 255},
        )
        display: cstring
        if index == road_pathing_lab.editing {
            display = fmt.ctprintf("%s", string(road_pathing_lab.input[:road_pathing_lab.input_length]))
        } else if index == 7 {
            display = fmt.ctprintf("%.1f%%", value * 100)
        } else if index == 0 || index == 3 || index == 4 {
            display = fmt.ctprintf("%.1f", value)
        } else {
            display = fmt.ctprintf("%.2f", value)
        }
        ui_draw_text(.Data, display, {input_bounds.x + 7, input_bounds.y + 9}, .17, {202, 218, 218, 255})
    }
    button := road_pathing_lab_regen_bounds(width)
    fill := road_pathing_lab.dirty ? canvas2d.Color{45, 118, 128, 255} : canvas2d.Color{30, 57, 61, 255}
    canvas2d.DrawRectangleRounded(button, .16, 6, fill)
    canvas2d.DrawRectangleRoundedLinesEx(button, .16, 6, 1, {111, 222, 239, 255})
    label: cstring = road_pathing_lab.dirty ? "APPLY SETTINGS & REGENERATE" : "REGENERATE"
    ui_draw_text(.Label, label, {button.x + 20, button.y + 13}, .23, {226, 239, 236, 255})
    ui_draw_text(
        .Data,
        "SPACE APPLY • R NEW SEED",
        {panel.x + 20, panel.y + panel.height - 48},
        .17,
        {160, 180, 181, 255},
    )
    ui_draw_text(
        .Data,
        "GREEN VILLAGE • GOLD TOWN • CYAN CITY",
        {panel.x + 20, panel.y + panel.height - 24},
        .15,
        {239, 178, 91, 255},
    )
}
