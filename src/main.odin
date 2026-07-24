package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import chase_camera "../packages/chase_camera"
import dialogue "../packages/dialogue"
import flight "../packages/flight"
import particle_systems "../packages/particles"
import postale_game "../packages/postale"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:os"
import sdl "vendor:sdl3"
import rl "zelda_engine:canvas2d"

ADRIATIC_WORLD_WIDTH :: 854
ADRIATIC_WORLD_HEIGHT :: 480
STRUCTURE_HISTORY_CAPACITY :: 24

Structure_History_State :: struct {
    structures: [terrain.STRUCTURE_CAPACITY]terrain.Structure,
    count:      int,
    next_id:    u64,
}

CURVE_POINT_CAPACITY :: 48

Curve_Point :: struct {
    x, z: f32,
}

Editor :: struct {
    project:                                                terrain.Project,
    tool:                                                   terrain.Tool,
    radius:                                                 f32,
    strength:                                               f32,
    structure_selected:                                     int,
    structure_placing:                                      bool,
    structure_moving:                                       bool,
    structure_anchor_x:                                     f32,
    structure_anchor_z:                                     f32,
    structure_preview_end_x:                                f32,
    structure_preview_end_z:                                f32,
    structure_grab_offset_x:                                f32,
    structure_grab_offset_z:                                f32,
    structure_preview:                                      terrain.Structure,
    structure_kind:                                         terrain.Formation_Kind,
    structure_auto_kind:                                    bool,
    structure_force_box:                                    bool,
    structure_cliff_mode:                                   bool,
    structure_scatter_mode:                                 bool,
    structure_scatter_count:                                int,
    architecture_node_mode:                                 bool,
    architecture_paint_mode:                                bool,
    architecture_painting:                                  bool,
    architecture_paint_start_x, architecture_paint_start_z: f32,
    architecture_paint_end_x, architecture_paint_end_z:     f32,
    architecture_sample_radius:                             f32,
    architecture_building_height:                           f32,
    curve_points:                                           [CURVE_POINT_CAPACITY]Curve_Point,
    curve_point_count:                                      int,
    curve_drawing:                                          bool,
    curve_mode:                                             bool,
    curve_cliff_mode:                                       bool,
    curve_width:                                            f32,
    curve_height:                                           f32,
    structure_undo:                                         [STRUCTURE_HISTORY_CAPACITY]Structure_History_State,
    structure_redo:                                         [STRUCTURE_HISTORY_CAPACITY]Structure_History_State,
    structure_undo_count:                                   int,
    structure_redo_count:                                   int,
    in_map:                                                 bool,
    player:                                                 third_person.State,
    camera:                                                 third_person.Camera,
    camera_pose:                                            third_person.Camera_Pose,
    cameras:                                                third_person.Camera_System,
    flight_camera:                                          chase_camera.State,
    editor_camera:                                          third_person.Camera,
    editor_focus:                                           third_person.Vec3,
    map_time:                                               f32,
    pilot:                                                  vehicles.Character,
    car:                                                    vehicles.Vehicle,
    car_drive:                                              vehicles.Car_Drive_State,
    postale:                                                postale_game.Runtime,
    libellula:                                              vehicles.Vehicle,
    postale_visible:                                        bool,
    libellula_visible:                                      bool,
    libellula_active:                                       bool,
    attendant_dialogue:                                     dialogue.Conversation,
    attendant_dialogue_open:                                bool,
    camera_target_lock:                                     bool,
    flight_control:                                         postale_game.Control,
    atmosphere:                                             atmosphere.Atmosphere,
    particles:                                              particle_systems.Cpu_System,
    vehicle_effects:                                        particle_systems.Vehicle_Effects,
    wing_trails:                                            particle_systems.Wing_Trails,
    tweak:                                                  Tweak_State,
    tweak_status:                                           Tweak_Status,
}

structure_history_capture :: proc(editor: ^Editor) -> Structure_History_State {
    state: Structure_History_State
    if editor == nil do return state
    state.count = editor.project.structure_count
    state.next_id = editor.project.next_structure_id
    for index in 0 ..< terrain.STRUCTURE_CAPACITY {
        state.structures[index] = editor.project.structures[index]
    }
    return state
}

structure_history_restore :: proc(editor: ^Editor, state: Structure_History_State) {
    if editor == nil do return
    for index in 0 ..< terrain.STRUCTURE_CAPACITY {
        editor.project.structures[index] = state.structures[index]
    }
    editor.project.structure_count = state.count
    editor.project.next_structure_id = state.next_id
    editor.project.revision += 1
    if editor.structure_selected >= editor.project.structure_count do editor.structure_selected = -1
}

structure_history_push_undo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.structure_undo_count < STRUCTURE_HISTORY_CAPACITY {
        editor.structure_undo[editor.structure_undo_count] = structure_history_capture(editor)
        editor.structure_undo_count += 1
    } else {
        for index in 1 ..< STRUCTURE_HISTORY_CAPACITY {
            editor.structure_undo[index - 1] = editor.structure_undo[index]
        }
        editor.structure_undo[STRUCTURE_HISTORY_CAPACITY - 1] = structure_history_capture(editor)
    }
    editor.structure_redo_count = 0
}

structure_history_push_redo :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.structure_redo_count < STRUCTURE_HISTORY_CAPACITY {
        editor.structure_redo[editor.structure_redo_count] = structure_history_capture(editor)
        editor.structure_redo_count += 1
    } else {
        for index in 1 ..< STRUCTURE_HISTORY_CAPACITY {
            editor.structure_redo[index - 1] = editor.structure_redo[index]
        }
        editor.structure_redo[STRUCTURE_HISTORY_CAPACITY - 1] = structure_history_capture(editor)
    }
}

structure_undo :: proc(editor: ^Editor) {
    if editor == nil || editor.structure_undo_count <= 0 do return
    structure_history_push_redo(editor)
    editor.structure_undo_count -= 1
    structure_history_restore(editor, editor.structure_undo[editor.structure_undo_count])
    if editor.structure_selected >= 0 && editor.structure_selected >= editor.project.structure_count {
        editor.structure_selected = -1
    }
}

structure_redo :: proc(editor: ^Editor) {
    if editor == nil || editor.structure_redo_count <= 0 do return
    if editor.structure_undo_count < STRUCTURE_HISTORY_CAPACITY {
        editor.structure_undo[editor.structure_undo_count] = structure_history_capture(editor)
        editor.structure_undo_count += 1
    } else {
        for index in 1 ..< STRUCTURE_HISTORY_CAPACITY {
            editor.structure_undo[index - 1] = editor.structure_undo[index]
        }
        editor.structure_undo[STRUCTURE_HISTORY_CAPACITY - 1] = structure_history_capture(editor)
    }
    editor.structure_redo_count -= 1
    structure_history_restore(editor, editor.structure_redo[editor.structure_redo_count])
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
    case .Architecture:
        return "ADRIATIC NODES"
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
    if editor.structure_force_box {
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
    structure.base_y = terrain.sample_height(&editor.project, 0, structure.center_x, structure.center_z)
}

capture_add_formation :: proc(editor: ^Editor, x, z, width, depth, height: f32, kind: terrain.Formation_Kind) -> int {
    if editor == nil do return -1
    structure := terrain.structure_make(x, z, width, depth, 0, height)
    structure.kind = kind
    structure.base_y = terrain.sample_height(&editor.project, 0, x, z)
    return terrain.add_structure(&editor.project, structure)
}

structure_commit_placement :: proc(editor: ^Editor, end_x, end_z: f32) -> int {
    if editor == nil do return -1
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
        copy.base_y = terrain.sample_height(&editor.project, 0, copy.center_x, copy.center_z)
        if !editor.structure_force_box && !editor.structure_cliff_mode {
            copy.kind = terrain.formation_kind_for_gesture(copy.width, copy.depth, copy.height)
        }
        last_index = terrain.add_structure(&editor.project, copy)
    }
    return last_index
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
    structure.base_y = terrain.sample_height(&editor.project, 0, structure.center_x, structure.center_z)
    return structure
}

curve_commit :: proc(editor: ^Editor) -> int {
    if editor == nil || editor.curve_point_count < 2 do return -1
    last_index := -1
    for index in 0 ..< editor.curve_point_count - 1 {
        last_index = terrain.add_structure(
            &editor.project,
            curve_segment_structure(editor, editor.curve_points[index], editor.curve_points[index + 1]),
        )
        if last_index < 0 do break
    }
    return last_index
}

curve_reset :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.curve_point_count = 0
    editor.curve_drawing = false
}

curve_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || editor.tool != .Structure || !editor.curve_mode || (!editor.curve_drawing && editor.curve_point_count == 0) do return
    if !cursor_hit {
        if rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT) do curve_reset(editor)
        return
    }
    cell := editor.project.levels[0].cell_size
    if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
        structure_history_push_undo(editor)
        editor.curve_cliff_mode = rl.IsMouseButtonPressed(.RIGHT)
        editor.curve_point_count = 1
        editor.curve_points[0] = {structure_editor_snap(world_x, editor), structure_editor_snap(world_z, editor)}
        editor.curve_drawing = true
    }
    if editor.curve_drawing && (rl.IsMouseButtonDown(.LEFT) || rl.IsMouseButtonDown(.RIGHT)) {
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
    if editor.curve_drawing && (rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT)) {
        if editor.curve_point_count >= 2 {
            last_index := curve_commit(editor)
            if last_index >= 0 do editor.structure_selected = last_index
        }
        curve_reset(editor)
    }
}

seed_formation_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    architecture.generate_poisson(
        &editor.project,
        center - 105,
        center - 78,
        center + 105,
        center + 78,
        28,
        30,
        0xA71D3,
    )
    editor.tool = .Structure
    editor.structure_selected = -1
    editor.structure_placing = false
    editor.structure_scatter_mode = false
    editor.structure_auto_kind = false
    editor.architecture_node_mode = true
    editor.architecture_paint_mode = true
    editor.architecture_sample_radius = 28
    editor.architecture_building_height = 30
    editor.architecture_paint_start_x = center - 105
    editor.architecture_paint_start_z = center - 78
    editor.architecture_paint_end_x = center + 105
    editor.architecture_paint_end_z = center + 78
}

architecture_paint_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.architecture_paint_mode do return
    if !cursor_hit {
        if rl.IsMouseButtonReleased(.LEFT) do editor.architecture_painting = false
        return
    }
    if rl.IsMouseButtonPressed(.LEFT) {
        editor.architecture_painting = true
        editor.architecture_paint_start_x = structure_editor_snap(world_x, editor)
        editor.architecture_paint_start_z = structure_editor_snap(world_z, editor)
        editor.architecture_paint_end_x = editor.architecture_paint_start_x
        editor.architecture_paint_end_z = editor.architecture_paint_start_z
    }
    if editor.architecture_painting {
        editor.architecture_paint_end_x = structure_editor_snap(world_x, editor)
        editor.architecture_paint_end_z = structure_editor_snap(world_z, editor)
        if rl.IsMouseButtonReleased(.LEFT) {
            min_x, max_x :=
                min(editor.architecture_paint_start_x, editor.architecture_paint_end_x),
                max(editor.architecture_paint_start_x, editor.architecture_paint_end_x)
            min_z, max_z :=
                min(editor.architecture_paint_start_z, editor.architecture_paint_end_z),
                max(editor.architecture_paint_start_z, editor.architecture_paint_end_z)
            architecture.generate_poisson(
                &editor.project,
                min_x,
                min_z,
                max_x,
                max_z,
                editor.architecture_sample_radius,
                editor.architecture_building_height,
                u32(editor.project.revision + 0xA71D3),
            )
            editor.architecture_painting = false
        }
    }
}

structure_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || editor.tool != .Structure do return
    cell := editor.project.levels[0].cell_size
    if control_key_down() && rl.IsKeyPressed(.Z) {
        structure_undo(editor)
        editor.structure_placing = false
        editor.structure_moving = false
        return
    }
    if control_key_down() && rl.IsKeyPressed(.Y) {
        structure_redo(editor)
        editor.structure_placing = false
        editor.structure_moving = false
        return
    }
    if rl.IsKeyPressed(.BACKSPACE) && editor.structure_selected >= 0 && !editor.structure_placing {
        structure_history_push_undo(editor)
        terrain.remove_structure(&editor.project, editor.structure_selected)
        editor.structure_selected = -1
    }
    if control_key_down() && rl.IsKeyPressed(.D) && editor.structure_selected >= 0 {
        structure_history_push_undo(editor)
        index := terrain.duplicate_structure(&editor.project, editor.structure_selected, cell * 2, cell * 2)
        if index >= 0 do editor.structure_selected = index
    }
    if rl.IsKeyPressed(.R) {
        if editor.structure_placing {
            editor.structure_preview.rotation += math.PI / 12
        } else if editor.structure_selected >= 0 {
            structure_history_push_undo(editor)
            editor.project.structures[editor.structure_selected].rotation += math.PI / 12
            editor.project.revision += 1
        }
    }
    if !cursor_hit {
        if rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT) {
            editor.structure_placing = false
            editor.structure_moving = false
        }
        return
    }
    if rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT) {
        index := rl.IsMouseButtonPressed(.LEFT) ? terrain.structure_index_at(&editor.project, world_x, world_z) : -1
        if index >= 0 {
            editor.structure_selected = index
            editor.structure_moving = true
            structure_history_push_undo(editor)
            editor.structure_grab_offset_x = editor.project.structures[index].center_x - world_x
            editor.structure_grab_offset_z = editor.project.structures[index].center_z - world_z
        } else {
            editor.structure_selected = -1
            editor.structure_placing = true
            editor.structure_anchor_x = structure_editor_snap(world_x, editor)
            editor.structure_anchor_z = structure_editor_snap(world_z, editor)
            editor.structure_preview_end_x = editor.structure_anchor_x
            editor.structure_preview_end_z = editor.structure_anchor_z
            editor.structure_preview = terrain.structure_make(
                editor.structure_anchor_x,
                editor.structure_anchor_z,
                cell,
                cell,
                0,
                cell * 12,
            )
            editor.structure_force_box = control_key_down()
            editor.structure_cliff_mode = rl.IsMouseButtonPressed(.RIGHT)
            editor.structure_scatter_mode = alt_key_down()
            structure_update_preview_kind(editor)
            structure_update_base(editor, &editor.structure_preview)
        }
    }
    if editor.structure_placing {
        end_x := structure_editor_snap(world_x, editor)
        end_z := structure_editor_snap(world_z, editor)
        editor.structure_preview_end_x = end_x
        editor.structure_preview_end_z = end_z
        editor.structure_preview.center_x = (editor.structure_anchor_x + end_x) * .5
        editor.structure_preview.center_z = (editor.structure_anchor_z + end_z) * .5
        editor.structure_preview.width = max(math.abs(end_x - editor.structure_anchor_x), cell)
        editor.structure_preview.depth = max(math.abs(end_z - editor.structure_anchor_z), cell)
        structure_update_preview_kind(editor)
        structure_update_base(editor, &editor.structure_preview)
        if rl.IsMouseButtonReleased(.LEFT) || rl.IsMouseButtonReleased(.RIGHT) {
            structure_history_push_undo(editor)
            index := structure_commit_placement(editor, world_x, world_z)
            if index >= 0 do editor.structure_selected = index
            editor.structure_placing = false
        }
    } else if editor.structure_moving && editor.structure_selected >= 0 {
        structure := &editor.project.structures[editor.structure_selected]
        structure.center_x = structure_editor_snap(world_x + editor.structure_grab_offset_x, editor)
        structure.center_z = structure_editor_snap(world_z + editor.structure_grab_offset_z, editor)
        structure_update_base(editor, structure)
        if rl.IsMouseButtonReleased(.LEFT) do editor.structure_moving = false
    }
}

structure_adjust_with_wheel :: proc(editor: ^Editor, wheel: f32) {
    if editor == nil || editor.tool != .Structure || wheel == 0 do return
    cell := editor.project.levels[0].cell_size
    if editor.structure_placing {
        if editor.structure_scatter_mode && alt_key_down() {
            editor.structure_scatter_count = clamp(editor.structure_scatter_count + int(wheel), 2, 8)
        } else if shift_key_down() {
            editor.structure_preview.width = max(cell, editor.structure_preview.width + wheel * cell * 2)
            editor.structure_preview.depth = max(cell, editor.structure_preview.depth + wheel * cell * 2)
        } else {
            editor.structure_preview.height = max(cell, editor.structure_preview.height + wheel * cell * 2)
        }
    } else if editor.structure_selected >= 0 {
        structure_history_push_undo(editor)
        structure := &editor.project.structures[editor.structure_selected]
        if shift_key_down() {
            structure.width = max(cell, structure.width + wheel * cell * 2)
            structure.depth = max(cell, structure.depth + wheel * cell * 2)
        } else {
            structure.height = max(cell, structure.height + wheel * cell * 2)
        }
        editor.project.revision += 1
    }
}

set_pointer_locked :: proc(locked: bool) {
    if window := sdl.GetKeyboardFocus(); window != nil {
        _ = sdl.SetWindowRelativeMouseMode(window, locked)
    }
}

project_point :: proc(x, z, height: f32, center: rl.Vector2, scale: f32) -> rl.Vector2 {
    return {center.x + (x - z) * scale, center.y + (x + z) * scale * .46 - height * scale}
}

Perspective_Camera :: struct {
    position, right, up, forward: third_person.Vec3,
    focal_length:                 f32,
}

Screen_Point :: struct {
    position: rl.Vector2,
    depth:    f32,
    visible:  bool,
}

vec_sub :: proc(a, b: third_person.Vec3) -> third_person.Vec3 {return {a.x - b.x, a.y - b.y, a.z - b.z}}
vec_dot :: proc(a, b: third_person.Vec3) -> f32 { return a.x * b.x + a.y * b.y + a.z * b.z }
vec_cross :: proc(a, b: third_person.Vec3) -> third_person.Vec3 {
    return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}
vec_normalize :: proc(v: third_person.Vec3) -> third_person.Vec3 {
    length := f32(math.sqrt(f64(vec_dot(v, v))))
    if length < .0001 do return {}
    return {v.x / length, v.y / length, v.z / length}
}

shape_flight_axis :: proc(value: f32) -> f32 {
    dead_zone := f32(.16)
    magnitude := math.abs(value)
    if magnitude <= dead_zone do return 0
    return math.sign(value) * clamp((magnitude - dead_zone) / (1 - dead_zone), 0, 1)
}

stronger_axis :: proc(first, second: f32) -> f32 {
    if math.abs(second) > math.abs(first) do return second
    return first
}

control_key_down :: proc() -> bool {
    keys := sdl.GetKeyboardState(nil)
    return keys[int(sdl.Scancode.LCTRL)] || keys[int(sdl.Scancode.RCTRL)]
}

shift_key_down :: proc() -> bool {
    keys := sdl.GetKeyboardState(nil)
    return keys[int(sdl.Scancode.LSHIFT)] || keys[int(sdl.Scancode.RSHIFT)]
}

alt_key_down :: proc() -> bool {
    keys := sdl.GetKeyboardState(nil)
    return keys[int(sdl.Scancode.LALT)] || keys[int(sdl.Scancode.RALT)]
}

postale_spawn_position :: proc(editor: ^Editor) -> flight.Vec3 {
    half_extent := f32(terrain.RING_RESOLUTION - 1) * editor.project.levels[0].cell_size * .5
    x := half_extent * terrain.DEFAULT_ISLAND_OFFSET + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET
    z := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    ground := postale_game.drivable_surface_height(
        terrain.sample_height(&editor.project, 0, x, z),
        editor.project.sea_level,
    )
    return {x = x, y = ground + postale_game.GROUND_CLEARANCE, z = z}
}

flight_to_world :: proc(value: flight.Vec3) -> third_person.Vec3 {
    return {value.x, value.y, value.z}
}

POSTALE_PRESENTATION_SCALE :: f32(.68)
LIBELLULA_PRESENTATION_SCALE :: f32(.72)

// These are points on the visible wing's trailing edge in mesh-local space.
// Keep them in the same local coordinate system and presentation scale as
// draw_postale_3d so wing streams begin on the rendered wing tips.
POSTALE_WING_TRAIL_LOCAL_Y :: f32(1.05)
POSTALE_WING_TRAIL_LOCAL_Z :: f32(.6)

postale_vertex_world :: proc(runtime: ^postale_game.Runtime, position: [3]f32, scale: f32) -> third_person.Vec3 {
    body := runtime.body
    return {
        x = body.position.x +
        body.basis.right.x * position[0] * scale +
        body.basis.up.x * position[1] * scale -
        body.basis.forward.x * position[2] * scale,
        y = body.position.y +
        body.basis.right.y * position[0] * scale +
        body.basis.up.y * position[1] * scale -
        body.basis.forward.y * position[2] * scale,
        z = body.position.z +
        body.basis.right.z * position[0] * scale +
        body.basis.up.z * position[1] * scale -
        body.basis.forward.z * position[2] * scale,
    }
}

postale_camera_target :: proc(editor: ^Editor) -> chase_camera.Target {
    return {
        position = editor.postale.body.position,
        basis = editor.postale.body.basis,
        airspeed = editor.postale.telemetry.airspeed,
        roll_input = editor.flight_control.roll,
        grounded = editor.postale.grounded,
    }
}

libellula_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    half_extent := f32(terrain.RING_RESOLUTION - 1) * editor.project.levels[0].cell_size * .5
    x := half_extent * terrain.DEFAULT_ISLAND_OFFSET + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET + 12
    z := half_extent * terrain.DEFAULT_ISLAND_OFFSET + 8
    return {x = x, y = terrain.sample_height(&editor.project, 0, x, z) + 2.1, z = z}
}

attendant_speaker :: proc(_: ^dialogue.Context) -> string { return "MARTA — AIRFIELD ATTENDANT" }
attendant_text :: proc(_: ^dialogue.Context) -> string {
    return "The Libellula is fueled and ready. Switch out the Postale for the tri-rotor?"
}

open_attendant_dialogue :: proc(editor: ^Editor) {
    choices := make([]dialogue.Choice, 2)
    choices[0] = dialogue.choice("Switch to the Libellula", dialogue.no_next_node)
    choices[1] = dialogue.choice("Keep the Postale", dialogue.no_next_node)
    nodes := make([]dialogue.Node, 1)
    nodes[0] = dialogue.node("vehicle_swap", attendant_text, choices, attendant_speaker)
    definition := new(dialogue.Definition)
    definition^ = {
        id         = "libellula_attendant",
        start_node = 0,
        nodes      = nodes,
    }
    conversation, opened := dialogue.open(
        definition,
        {data = rawptr(editor), location_id = "airfield", resident_index = 0},
    )
    if opened {
        editor.attendant_dialogue = conversation
        editor.attendant_dialogue_open = true
    }
}

libellula_attendant_near :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.pilot.mode != .On_Foot do return false
    delta := vec_sub(editor.player.position, editor.libellula.position)
    return vec_dot(delta, delta) <= 4.5 * 4.5
}

draw_libellula_3d :: proc(editor: ^Editor, camera: Perspective_Camera, width, height: i32) {
    mesh := vehicles.libellula_mesh()
    vehicles.animate_libellula_mesh(
        &mesh,
        f32(rl.GetTime()) * .35,
        f32(rl.GetTime()) * .35 + .333,
        f32(rl.GetTime()) * .35 + .667,
    )
    faces: [vehicles.AIRCRAFT_MESH_TRIANGLE_CAPACITY]Projected_Aircraft_Face
    face_count := 0
    for triangle in vehicles.mesh_triangles(&mesh) {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        pa := project_3d(
            camera,
            {
                x = editor.libellula.position.x + a.position[0] * LIBELLULA_PRESENTATION_SCALE,
                y = editor.libellula.position.y + a.position[1] * LIBELLULA_PRESENTATION_SCALE,
                z = editor.libellula.position.z - a.position[2] * LIBELLULA_PRESENTATION_SCALE,
            },
            width,
            height,
        )
        pb := project_3d(
            camera,
            {
                x = editor.libellula.position.x + b.position[0] * LIBELLULA_PRESENTATION_SCALE,
                y = editor.libellula.position.y + b.position[1] * LIBELLULA_PRESENTATION_SCALE,
                z = editor.libellula.position.z - b.position[2] * LIBELLULA_PRESENTATION_SCALE,
            },
            width,
            height,
        )
        pc := project_3d(
            camera,
            {
                x = editor.libellula.position.x + c.position[0] * LIBELLULA_PRESENTATION_SCALE,
                y = editor.libellula.position.y + c.position[1] * LIBELLULA_PRESENTATION_SCALE,
                z = editor.libellula.position.z - c.position[2] * LIBELLULA_PRESENTATION_SCALE,
            },
            width,
            height,
        )
        if !(pa.visible && pb.visible && pc.visible) do continue
        // The Libellula is an animated mesh, not a HUD proxy. Submit each
        // generated triangle directly so the rotor geometry remains visible even
        // when its depth ordering crosses the carriage.
        rl.DrawQuadHatched(
            pa.position,
            pb.position,
            pc.position,
            pc.position,
            aircraft_part_color(a.part),
            rl.HATCH_DISABLED,
        )
        faces[face_count] = {
            a     = pa.position,
            b     = pb.position,
            c     = pc.position,
            depth = (pa.depth + pb.depth + pc.depth) / 3,
            color = aircraft_part_color(a.part),
        }
        face_count += 1
    }
    for index in 1 ..< face_count {
        face := faces[index]
        cursor := index
        for cursor > 0 && faces[cursor - 1].depth < face.depth {
            faces[cursor] = faces[cursor - 1]
            cursor -= 1
        }
        faces[cursor] = face
    }
    for face in faces[:face_count] {
        rl.DrawQuadHatched(face.a, face.b, face.c, face.c, face.color, rl.HATCH_DISABLED)
    }
    label := project_3d(
        camera,
        {x = editor.libellula.position.x, y = editor.libellula.position.y + 3.2, z = editor.libellula.position.z},
        width,
        height,
    )
    if label.visible do rl.DrawTextEx(rl.Font{}, "LIBELLULA", {label.position.x - 35, label.position.y - 12}, 13, 1, {r = 255, g = 239, b = 192, a = 255})
}

draw_attendant_3d :: proc(editor: ^Editor, camera: Perspective_Camera, width, height: i32) {
    // Marta stands just off the Libellula's left side, where the interaction
    // prompt is already active. The simple high-contrast silhouette keeps her
    // readable at the map camera's wide zoom.
    base := third_person.Vec3 {
        x = editor.libellula.position.x - 3.3,
        y = terrain.sample_height(
            &editor.project,
            0,
            editor.libellula.position.x - 3.3,
            editor.libellula.position.z + 2.2,
        ),
        z = editor.libellula.position.z + 2.2,
    }
    head := third_person.Vec3 {
        x = base.x,
        y = base.y + 1.62,
        z = base.z,
    }
    shoulders := third_person.Vec3 {
        x = base.x,
        y = base.y + 1.18,
        z = base.z,
    }
    left_hand := third_person.Vec3 {
        x = shoulders.x - .32,
        y = shoulders.y - .38,
        z = shoulders.z,
    }
    right_hand := third_person.Vec3 {
        x = shoulders.x + .32,
        y = shoulders.y - .38,
        z = shoulders.z,
    }
    left_foot := third_person.Vec3 {
        x = base.x - .22,
        y = base.y + .02,
        z = base.z,
    }
    right_foot := third_person.Vec3 {
        x = base.x + .22,
        y = base.y + .02,
        z = base.z,
    }
    head_screen := project_3d(camera, head, width, height)
    if head_screen.visible do rl.DrawCircleV(head_screen.position, 7, {r = 226, g = 184, b = 112, a = 255})
    draw_line_3d(camera, shoulders, left_hand, width, height, 4, {r = 35, g = 77, b = 84, a = 255})
    draw_line_3d(camera, shoulders, right_hand, width, height, 4, {r = 35, g = 77, b = 84, a = 255})
    draw_line_3d(camera, shoulders, base, width, height, 7, {r = 211, g = 80, b = 57, a = 255})
    draw_line_3d(camera, base, left_foot, width, height, 4, {r = 35, g = 48, b = 54, a = 255})
    draw_line_3d(camera, base, right_foot, width, height, 4, {r = 35, g = 48, b = 54, a = 255})
    label := project_3d(camera, {x = head.x, y = head.y + .28, z = head.z}, width, height)
    if label.visible do rl.DrawTextEx(rl.Font{}, "MARTA", {label.position.x - 22, label.position.y - 12}, 11, 1, {r = 255, g = 239, b = 192, a = 255})
}

draw_postale_3d :: proc(editor: ^Editor, camera: Perspective_Camera, width, height: i32) {
    mesh := vehicles.postale_mesh()
    vehicles.animate_postale_mesh(
        &mesh,
        editor.postale.flap_fraction,
        editor.flight_control.pitch,
        editor.flight_control.roll,
        editor.flight_control.yaw,
        editor.postale.propeller_turns,
    )
    // The canvas renderer is painter ordered, so submit the generated aircraft
    // faces back-to-front just like the terrain cells.
    faces: [vehicles.AIRCRAFT_MESH_TRIANGLE_CAPACITY]Projected_Aircraft_Face
    face_count := 0
    for triangle in vehicles.mesh_triangles(&mesh) {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        pa := project_3d(
            camera,
            postale_vertex_world(&editor.postale, a.position, POSTALE_PRESENTATION_SCALE),
            width,
            height,
        )
        pb := project_3d(
            camera,
            postale_vertex_world(&editor.postale, b.position, POSTALE_PRESENTATION_SCALE),
            width,
            height,
        )
        pc := project_3d(
            camera,
            postale_vertex_world(&editor.postale, c.position, POSTALE_PRESENTATION_SCALE),
            width,
            height,
        )
        if !(pa.visible && pb.visible && pc.visible) do continue
        faces[face_count] = {
            a     = pa.position,
            b     = pb.position,
            c     = pc.position,
            depth = (pa.depth + pb.depth + pc.depth) / 3,
            color = aircraft_part_color(a.part),
        }
        face_count += 1
    }
    for index in 1 ..< face_count {
        face := faces[index]
        cursor := index
        for cursor > 0 && faces[cursor - 1].depth < face.depth {
            faces[cursor] = faces[cursor - 1]
            cursor -= 1
        }
        faces[cursor] = face
    }
    for face in faces[:face_count] {
        rl.DrawQuadHatched(face.a, face.b, face.c, face.c, face.color, rl.HATCH_DISABLED)
    }
}

Projected_Aircraft_Face :: struct {
    a, b, c: rl.Vector2,
    depth:   f32,
    color:   rl.Color,
}

aircraft_part_color :: proc(part: vehicles.Aircraft_Mesh_Part) -> rl.Color {
    #partial switch part {
    case .Wing, .Tail, .Left_Flap, .Right_Flap, .Left_Aileron, .Right_Aileron, .Elevator, .Rudder:
        return {r = 238, g = 207, b = 120, a = 255}
    case .Glass:
        return {r = 142, g = 207, b = 220, a = 255}
    case .Engine:
        return {r = 177, g = 54, b = 39, a = 255}
    case .Propeller, .Left_Propeller, .Right_Propeller, .Left_Rotor, .Right_Rotor, .Rear_Rotor:
        return {r = 54, g = 43, b = 35, a = 255}
    case .Float, .Frame:
        return {r = 63, g = 145, b = 160, a = 255}
    case .Carriage:
        return {r = 190, g = 78, b = 48, a = 255}
    case .Wheel:
        return {r = 25, g = 31, b = 36, a = 255}
    case .Bumper:
        return {r = 174, g = 184, b = 188, a = 255}
    case .Headlight:
        return {r = 255, g = 239, b = 164, a = 255}
    case .Tail_Light:
        return {r = 211, g = 43, b = 42, a = 255}
    case:
        return {r = 34, g = 166, b = 204, a = 255}
    }
}

color_lerp :: proc(a, b: rl.Color, amount: f32) -> rl.Color {
    t := clamp(amount, 0, 1)
    return {
        r = u8(f32(a.r) + (f32(b.r) - f32(a.r)) * t),
        g = u8(f32(a.g) + (f32(b.g) - f32(a.g)) * t),
        b = u8(f32(a.b) + (f32(b.b) - f32(a.b)) * t),
        a = u8(f32(a.a) + (f32(b.a) - f32(a.a)) * t),
    }
}

draw_instrument_dial :: proc(center: rl.Vector2, label: cstring, value, minimum, maximum: f32, value_text: cstring) {
    dial := rl.Color {
        r = 12,
        g = 25,
        b = 35,
        a = 245,
    }
    mark := rl.Color {
        r = 185,
        g = 217,
        b = 216,
        a = 255,
    }
    accent := rl.Color {
        r = 239,
        g = 203,
        b = 111,
        a = 255,
    }
    rl.DrawCircleV(center, 48, dial)
    for tick in 0 ..= 10 {
        angle := -math.PI * .75 + f32(tick) / 10 * math.PI * 1.5
        outer := rl.Vector2{center.x + math.cos(angle) * 42, center.y + math.sin(angle) * 42}
        inner := rl.Vector2{center.x + math.cos(angle) * 36, center.y + math.sin(angle) * 36}
        rl.DrawLineEx(inner, outer, tick % 5 == 0 ? f32(2) : f32(1), mark)
    }
    fraction := clamp((value - minimum) / max(f32(.001), maximum - minimum), 0, 1)
    needle_angle := -math.PI * .75 + fraction * math.PI * 1.5
    needle_end := rl.Vector2{center.x + math.cos(needle_angle) * 31, center.y + math.sin(needle_angle) * 31}
    rl.DrawLineEx(center, needle_end, 2.5, accent)
    rl.DrawCircleV(center, 3, accent)
    label_size := rl.MeasureTextEx(rl.Font{}, label, 10, 1)
    value_size := rl.MeasureTextEx(rl.Font{}, value_text, 13, 1)
    rl.DrawTextEx(rl.Font{}, label, {center.x - label_size.x * .5, center.y - 24}, 10, 1, mark)
    rl.DrawTextEx(rl.Font{}, value_text, {center.x - value_size.x * .5, center.y + 19}, 13, 1, accent)
}

draw_attitude_indicator :: proc(center: rl.Vector2, pitch, bank: f32) {
    dial := rl.Color {
        r = 12,
        g = 25,
        b = 35,
        a = 245,
    }
    sky := rl.Color {
        r = 62,
        g = 130,
        b = 153,
        a = 255,
    }
    earth := rl.Color {
        r = 127,
        g = 91,
        b = 57,
        a = 255,
    }
    mark := rl.Color {
        r = 224,
        g = 232,
        b = 207,
        a = 255,
    }
    accent := rl.Color {
        r = 239,
        g = 203,
        b = 111,
        a = 255,
    }
    rl.DrawCircleV(center, 48, dial)
    // The moving horizon gives an immediate read of bank and pitch without
    // obscuring the third-person view with a full-screen artificial horizon.
    pitch_offset := clamp(pitch * 34, -24, 24)
    c, s := math.cos(bank), math.sin(bank)
    horizon_center := rl.Vector2{center.x + s * pitch_offset, center.y - c * pitch_offset}
    horizon_left := rl.Vector2{horizon_center.x - c * 39, horizon_center.y - s * 39}
    horizon_right := rl.Vector2{horizon_center.x + c * 39, horizon_center.y + s * 39}
    rl.DrawLineEx(horizon_left, horizon_right, 13, sky)
    rl.DrawLineEx(
        {horizon_left.x - s * 8, horizon_left.y + c * 8},
        {horizon_right.x - s * 8, horizon_right.y + c * 8},
        13,
        earth,
    )
    rl.DrawLineEx(horizon_left, horizon_right, 2, mark)
    rl.DrawLineEx({center.x - 19, center.y}, {center.x - 5, center.y}, 3, accent)
    rl.DrawLineEx({center.x + 5, center.y}, {center.x + 19, center.y}, 3, accent)
    rl.DrawCircleV(center, 2.5, accent)
    label: cstring = "ATTITUDE"
    label_size := rl.MeasureTextEx(rl.Font{}, label, 10, 1)
    rl.DrawTextEx(rl.Font{}, label, {center.x - label_size.x * .5, center.y - 42}, 10, 1, mark)
}

draw_flight_instruments :: proc(editor: ^Editor, width, height: i32, altitude: f32) {
    panel_width := f32(400)
    panel_left := f32(width) * .5 - panel_width * .5
    panel_top := f32(height) - 144
    rl.DrawRectangle(i32(panel_left), i32(panel_top), i32(panel_width), 130, {r = 5, g = 16, b = 25, a = 215})
    airspeed := editor.postale.telemetry.airspeed
    vertical_speed := editor.postale.body.velocity.y
    bank := postale_game.bank_radians(editor.postale.body.basis)
    pitch := math.asin(clamp(editor.postale.body.basis.forward.y, -1, 1))
    heading := postale_game.yaw_radians(editor.postale.body.basis) * 180 / math.PI
    if heading < 0 do heading += 360
    y := panel_top + 64
    draw_instrument_dial({panel_left + 67, y}, "AIRSPEED", airspeed, 0, 60, fmt.ctprintf("%.0f m/s", airspeed))
    draw_attitude_indicator({panel_left + 200, y}, pitch, bank)
    draw_instrument_dial({panel_left + 333, y}, "ALTITUDE", altitude, 0, 500, fmt.ctprintf("%.0f m", altitude))
    readout := fmt.tprintf(
        "HDG %03.0f°     VSI %+4.1f m/s     WIND %2.1f m/s     POWER %3.0f%%",
        heading,
        vertical_speed,
        f32(
            math.sqrt(
                f64(
                    editor.atmosphere.weather.wind[0] * editor.atmosphere.weather.wind[0] +
                    editor.atmosphere.weather.wind[1] * editor.atmosphere.weather.wind[1],
                ),
            ),
        ),
        editor.postale.throttle * 100,
    )
    readout_size := rl.MeasureTextEx(rl.Font{}, fmt.ctprintf("%s", readout), 11, 1)
    rl.DrawTextEx(
        rl.Font{},
        fmt.ctprintf("%s", readout),
        {f32(width) * .5 - readout_size.x * .5, panel_top + 113},
        11,
        1,
        {r = 185, g = 217, b = 216, a = 255},
    )
}

perspective_camera :: proc(pose: third_person.Camera_Pose, focal_length: f32 = 1.35) -> Perspective_Camera {
    forward := vec_normalize(vec_sub(pose.target, pose.position))
    right := vec_normalize(vec_cross(forward, {y = 1}))
    return {
        position = pose.position,
        forward = forward,
        right = right,
        up = vec_cross(right, forward),
        focal_length = focal_length,
    }
}

project_3d :: proc(camera: Perspective_Camera, point: third_person.Vec3, width, height: i32) -> Screen_Point {
    view := vec_sub(point, camera.position)
    depth := vec_dot(view, camera.forward)
    if depth <= .08 do return {}
    x := vec_dot(view, camera.right) * camera.focal_length / depth
    y := vec_dot(view, camera.up) * camera.focal_length / depth
    return {position = {f32(width) * (.5 + x * .5), f32(height) * (.5 - y * .5)}, depth = depth, visible = true}
}

world_under_cursor :: proc(mouse, center: rl.Vector2, scale: f32) -> (f32, f32) {
    a := (mouse.x - center.x) / scale
    b := (mouse.y - center.y) / (scale * .46)
    return (a + b) * .5, (b - a) * .5
}

terrain_color :: proc(height, painted, sea_level: f32) -> rl.Color {
    water := rl.Color {
        r = 26,
        g = 80,
        b = 104,
        a = 255,
    }
    sand := rl.Color {
        r = 205,
        g = 183,
        b = 126,
        a = 255,
    }
    soil := rl.Color {
        r = 145,
        g = 101,
        b = 61,
        a = 255,
    }
    grass := rl.Color {
        r = 70,
        g = 133,
        b = 80,
        a = 255,
    }
    if height <= sea_level do return water
    if painted > .5 do return soil

    elevation := height - sea_level
    // Broad blends keep the elevation bands from turning the heightfield cells
    // into hard material rings. The normal-based light applied by each renderer
    // then provides the small-scale shape and slope definition.
    if elevation < .9 {
        return color_lerp(sand, soil, clamp((elevation - .18) / .72, 0, 1))
    }
    return color_lerp(soil, grass, clamp((elevation - .9) / 3.1, 0, 1))
}

draw_line_3d :: proc(
    camera: Perspective_Camera,
    a, b: third_person.Vec3,
    width, height: i32,
    thickness: f32,
    color: rl.Color,
) {
    pa := project_3d(camera, a, width, height)
    pb := project_3d(camera, b, width, height)
    if pa.visible && pb.visible do rl.DrawLineEx(pa.position, pb.position, thickness, color)
}

draw_quad_3d :: proc(camera: Perspective_Camera, a, b, c, d: third_person.Vec3, width, height: i32, color: rl.Color) {
    pa := project_3d(camera, a, width, height)
    pb := project_3d(camera, b, width, height)
    pc := project_3d(camera, c, width, height)
    pd := project_3d(camera, d, width, height)
    if pa.visible && pb.visible && pc.visible && pd.visible {
        rl.DrawQuadHatched(pa.position, pb.position, pc.position, pd.position, color, rl.HATCH_DISABLED)
    }
}

world_under_cursor_3d :: proc(
    camera: Perspective_Camera,
    mouse: rl.Vector2,
    width, height: i32,
    plane_height: f32,
) -> (
    f32,
    f32,
    bool,
) {
    if width <= 0 || height <= 0 do return 0, 0, false
    screen_x := (mouse.x / f32(width) - .5) * 2
    screen_y := (.5 - mouse.y / f32(height)) * 2
    aspect := f32(width) / f32(height)
    direction := vec_normalize(
        third_person.Vec3 {
            x = camera.forward.x +
            camera.right.x * screen_x * aspect / camera.focal_length +
            camera.up.x * screen_y / camera.focal_length,
            y = camera.forward.y +
            camera.right.y * screen_x * aspect / camera.focal_length +
            camera.up.y * screen_y / camera.focal_length,
            z = camera.forward.z +
            camera.right.z * screen_x * aspect / camera.focal_length +
            camera.up.z * screen_y / camera.focal_length,
        },
    )
    if math.abs(direction.y) < .0001 do return 0, 0, false
    distance := (plane_height - camera.position.y) / direction.y
    if distance <= 0 do return 0, 0, false
    return camera.position.x + direction.x * distance, camera.position.z + direction.z * distance, true
}

terrain_under_cursor_3d :: proc(
    editor: ^Editor,
    camera: Perspective_Camera,
    mouse: rl.Vector2,
    width, height: i32,
) -> (
    f32,
    f32,
    bool,
) {
    if editor == nil || width <= 0 || height <= 0 do return 0, 0, false
    screen_x := (mouse.x / f32(width) - .5) * 2
    screen_y := (.5 - mouse.y / f32(height)) * 2
    aspect := f32(width) / f32(height)
    direction := vec_normalize(
        third_person.Vec3 {
            x = camera.forward.x +
            camera.right.x * screen_x * aspect / camera.focal_length +
            camera.up.x * screen_y / camera.focal_length,
            y = camera.forward.y +
            camera.right.y * screen_x * aspect / camera.focal_length +
            camera.up.y * screen_y / camera.focal_length,
            z = camera.forward.z +
            camera.right.z * screen_x * aspect / camera.focal_length +
            camera.up.z * screen_y / camera.focal_length,
        },
    )
    step := max(f32(terrain.BASE_CELL_SIZE * .5), f32(2))
    half := f32(terrain.WORLD_SIZE_METERS * .5)
    previous_distance := f32(.1)
    previous_delta := f32(1.0e30)
    for distance := step; distance <= terrain.WORLD_SIZE_METERS * 2; distance += step {
        x := camera.position.x + direction.x * distance
        y := camera.position.y + direction.y * distance
        z := camera.position.z + direction.z * distance
        if math.abs(x) > half || math.abs(z) > half {
            previous_distance = distance
            continue
        }
        delta := y - terrain.sample_height(&editor.project, 0, x, z)
        if delta <= 0 && previous_delta > 0 {
            low, high := previous_distance, distance
            for _ in 0 ..< 10 {
                mid := (low + high) * .5
                mx := camera.position.x + direction.x * mid
                my := camera.position.y + direction.y * mid
                mz := camera.position.z + direction.z * mid
                if my > terrain.sample_height(&editor.project, 0, mx, mz) {
                    low = mid
                } else {
                    high = mid
                }
            }
            hit_distance := (low + high) * .5
            return camera.position.x + direction.x * hit_distance, camera.position.z + direction.z * hit_distance, true
        }
        previous_distance = distance
        previous_delta = delta
    }
    return 0, 0, false
}

update_editor_camera :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    if rl.IsMouseButtonDown(.MIDDLE) {
        mouse_delta := rl.GetMouseDelta()
        third_person.look(&editor.editor_camera, mouse_delta.x, -mouse_delta.y, .006)
    }
    wheel := rl.GetMouseWheelMove()
    if shift_key_down() && wheel != 0 {
        editor.editor_camera.distance = clamp(
            editor.editor_camera.distance * f32(math.pow(0.82, f64(wheel))),
            80,
            5000,
        )
    }
    move_x, move_z := f32(0), f32(0)
    if rl.IsKeyDown(.D) do move_x += 1
    if rl.IsKeyDown(.A) do move_x -= 1
    if rl.IsKeyDown(.W) do move_z += 1
    if rl.IsKeyDown(.S) do move_z -= 1
    yaw := editor.editor_camera.yaw_radians
    forward := third_person.Vec3 {
        x = -math.sin(yaw),
        z = -math.cos(yaw),
    }
    right := third_person.Vec3 {
        x = math.cos(yaw),
        z = -math.sin(yaw),
    }
    speed := clamp(editor.editor_camera.distance * .8, 80, 1600)
    if shift_key_down() do speed *= 2
    editor.editor_focus.x += (forward.x * move_z + right.x * move_x) * speed * delta_seconds
    editor.editor_focus.z += (forward.z * move_z + right.z * move_x) * speed * delta_seconds
    half := f32(terrain.WORLD_SIZE_METERS * .5)
    editor.editor_focus.x = clamp(editor.editor_focus.x, -half, half)
    editor.editor_focus.z = clamp(editor.editor_focus.z, -half, half)
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    editor.cameras = third_person.camera_system(editor.camera_pose)
}

draw_infrastructure_3d :: proc(editor: ^Editor, camera: Perspective_Camera, width, height: i32) {
    level := 0
    half_extent := f32(terrain.RING_RESOLUTION - 1) * editor.project.levels[level].cell_size * .5
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        island_x := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        island_z := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        runway_half_length := half_extent * terrain.DEFAULT_RUNWAY_HALF_LENGTH
        runway_half_width := half_extent * terrain.DEFAULT_RUNWAY_HALF_WIDTH
        runway_height := terrain.sample_height(&editor.project, level, island_x, island_z) + .04
        draw_quad_3d(
            camera,
            {x = island_x - runway_half_length, y = runway_height, z = island_z - runway_half_width},
            {x = island_x + runway_half_length, y = runway_height, z = island_z - runway_half_width},
            {x = island_x + runway_half_length, y = runway_height, z = island_z + runway_half_width},
            {x = island_x - runway_half_length, y = runway_height, z = island_z + runway_half_width},
            width,
            height,
            {r = 60, g = 66, b = 67, a = 255},
        )
        draw_line_3d(
            camera,
            {x = island_x - runway_half_length * .82, y = runway_height + .02, z = island_z},
            {x = island_x + runway_half_length * .82, y = runway_height + .02, z = island_z},
            width,
            height,
            2,
            {r = 238, g = 232, b = 186, a = 255},
        )

        pier_inner_x := island_x + sign * half_extent * terrain.DEFAULT_PIER_INNER_OFFSET
        pier_inner_z := island_z - sign * half_extent * .08
        pier_outer_x := island_x + sign * half_extent * terrain.DEFAULT_ISLAND_RADIUS
        pier_outer_z := island_z - sign * half_extent * .16
        pier_width := half_extent * .035
        pier_inner_height := terrain.sample_height(&editor.project, level, pier_inner_x, pier_inner_z) + .09
        pier_outer_height := editor.project.sea_level + .09
        draw_quad_3d(
            camera,
            {x = pier_inner_x, y = pier_inner_height, z = pier_inner_z - pier_width},
            {x = pier_outer_x, y = pier_outer_height, z = pier_outer_z - pier_width},
            {x = pier_outer_x, y = pier_outer_height, z = pier_outer_z + pier_width},
            {x = pier_inner_x, y = pier_inner_height, z = pier_inner_z + pier_width},
            width,
            height,
            {r = 137, g = 89, b = 48, a = 255},
        )
    }

    if editor.postale_visible do draw_postale_3d(editor, camera, width, height)
    // The spawned inspection craft is a world object; keep it in the
    // infrastructure pass even when the parked-vehicle presentation toggles.
    draw_libellula_3d(editor, camera, width, height)
    if editor.libellula_visible do draw_attendant_3d(editor, camera, width, height)
}

draw_terrain_3d :: proc(editor: ^Editor, width, height: i32) {
    sky := atmosphere.sample(&editor.atmosphere)
    horizon_day := rl.Color {
        r = 154,
        g = 205,
        b = 224,
        a = 255,
    }
    horizon_night := rl.Color {
        r = 19,
        g = 28,
        b = 55,
        a = 255,
    }
    sky_color := color_lerp(horizon_night, horizon_day, sky.daylight)
    storm_horizon := rl.Color {
        r = 104,
        g = 122,
        b = 130,
        a = 255,
    }
    sky_color = color_lerp(sky_color, storm_horizon, sky.weather.severity * .72)
    // The fallback extends the ocean beyond the finite detail mesh. Match the
    // lit water presentation so the near-plane edge never becomes visible.
    ocean_color := rl.Color {
        r = 86,
        g = 146,
        b = 165,
        a = 255,
    }
    rl.ClearBackground(ocean_color)
    camera := perspective_camera(editor.camera_pose)
    // Build terrain in camera-space order: far rows first give the canvas pass
    // stable painter's depth while each face is still perspective-projected.
    forward_flat := vec_normalize(third_person.Vec3{x = camera.forward.x, z = camera.forward.z})
    right_flat := vec_normalize(third_person.Vec3{x = camera.right.x, z = camera.right.z})
    horizon := project_3d(
        camera,
        {
            x = camera.position.x + forward_flat.x * 10000,
            y = editor.project.sea_level,
            z = camera.position.z + forward_flat.z * 10000,
        },
        width,
        height,
    )
    if horizon.visible {
        horizon_y := i32(clamp(horizon.position.y, 0, f32(height)))
        rl.DrawRectangle(0, 0, width, horizon_y + 1, sky_color)
    }
    // Match the finest clipmap spacing. Sampling every other heightfield point
    // made nearby slopes visibly faceted and discarded half of the authored
    // terrain detail.
    cell_size := editor.project.levels[0].cell_size
    // Keep the same world-space coverage as the former two-unit grid.
    near_rows := 48
    far_rows := 176
    side_rows := 180
    light_direction := vec_normalize(third_person.Vec3{x = -.45, y = .85, z = -.3})
    fog_start := f32(terrain.WORLD_SIZE_METERS * .55)
    fog_end := f32(terrain.WORLD_SIZE_METERS * 1.5)
    for depth_order in 0 ..< near_rows + far_rows {
        depth_index := near_rows + far_rows - 1 - depth_order
        depth := f32(depth_index - near_rows) * cell_size
        for side_index in -side_rows ..= side_rows {
            side := f32(side_index) * cell_size
            base_x := editor.camera_pose.target.x + forward_flat.x * depth + right_flat.x * side
            base_z := editor.camera_pose.target.z + forward_flat.z * depth + right_flat.z * side
            next_x := base_x + right_flat.x * cell_size
            next_z := base_z + right_flat.z * cell_size
            far_x := base_x + forward_flat.x * cell_size
            far_z := base_z + forward_flat.z * cell_size
            far_next_x := far_x + right_flat.x * cell_size
            far_next_z := far_z + right_flat.z * cell_size
            h00 := terrain.sample_height(&editor.project, 0, base_x, base_z)
            h10 := terrain.sample_height(&editor.project, 0, next_x, next_z)
            h01 := terrain.sample_height(&editor.project, 0, far_x, far_z)
            h11 := terrain.sample_height(&editor.project, 0, far_next_x, far_next_z)
            p00 := project_3d(camera, {x = base_x, y = h00, z = base_z}, width, height)
            p10 := project_3d(camera, {x = next_x, y = h10, z = next_z}, width, height)
            p11 := project_3d(camera, {x = far_next_x, y = h11, z = far_next_z}, width, height)
            p01 := project_3d(camera, {x = far_x, y = h01, z = far_z}, width, height)
            if !(p00.visible && p10.visible && p11.visible && p01.visible) do continue
            average_height := (h00 + h10 + h11 + h01) * .25
            surface_right := third_person.Vec3 {
                x = next_x - base_x,
                y = h10 - h00,
                z = next_z - base_z,
            }
            surface_forward := third_person.Vec3 {
                x = far_x - base_x,
                y = h01 - h00,
                z = far_z - base_z,
            }
            surface_normal := vec_normalize(vec_cross(surface_right, surface_forward))
            diffuse := max(vec_dot(surface_normal, light_direction), 0)
            shade := clamp(.52 + diffuse * .48 + average_height * .012, .42, 1.05)
            base_color := terrain_color(
                average_height,
                terrain.sample_material(&editor.project, 0, base_x, base_z),
                editor.project.sea_level,
            )
            color := rl.Color {
                r = u8(f32(base_color.r) * shade),
                g = u8(f32(base_color.g) * shade),
                b = u8(f32(base_color.b) * shade),
                a = 255,
            }
            average_depth := (p00.depth + p10.depth + p11.depth + p01.depth) * .25
            fog := clamp((average_depth - fog_start) / (fog_end - fog_start), 0, 1)
            color = color_lerp(color, sky_color, fog)
            rl.DrawQuadHatched(p00.position, p10.position, p11.position, p01.position, color, rl.HATCH_DISABLED)
        }
    }

    draw_infrastructure_3d(editor, camera, width, height)

    if editor.in_map && editor.pilot.mode == .On_Foot {
        // A compact articulated silhouette grounds the character in the 3D world.
        p := editor.player.position
        body := rl.Color {
            r = 42,
            g = 213,
            b = 201,
            a = 255,
        }
        skin := rl.Color {
            r = 247,
            g = 221,
            b = 167,
            a = 255,
        }
        draw_line_3d(
            camera,
            {x = p.x, y = p.y + .2, z = p.z},
            {x = p.x, y = p.y + 1.35, z = p.z},
            width,
            height,
            7,
            body,
        )
        draw_line_3d(
            camera,
            {x = p.x, y = p.y + 1.35, z = p.z},
            {x = p.x, y = p.y + 1.62, z = p.z},
            width,
            height,
            12,
            skin,
        )
        forward := third_person.Vec3 {
            x = -math.sin(editor.player.facing_yaw_radians),
            z = -math.cos(editor.player.facing_yaw_radians),
        }
        draw_line_3d(
            camera,
            {x = p.x, y = p.y + 1.12, z = p.z},
            {x = p.x + forward.x * .48, y = p.y + 1.12, z = p.z + forward.z * .48},
            width,
            height,
            4,
            skin,
        )

    }

    if editor.in_map {
        driving := editor.pilot.mode == .Driving
        panel_width := driving ? i32(650) : i32(430)
        help_text: cstring = "WASD move  Mouse look  Wheel zoom  Space jump  Esc editor"
        if driving do help_text = "W/S pitch  A/D roll  Q/E yaw  Mouse orbit  C camera  Shift/Ctrl power  F exit  R reset"
        rl.DrawRectangle(14, 14, panel_width, 72, {r = 8, g = 28, b = 45, a = 210})
        rl.DrawTextEx(
            rl.Font{},
            driving ? "POSTALE FLIGHT" : "THIRD-PERSON 3D",
            {26, 25},
            19,
            1,
            {r = 211, g = 250, b = 242, a = 255},
        )
        rl.DrawTextEx(rl.Font{}, help_text, {26, 49}, 13, 1, {r = 183, g = 219, b = 221, a = 255})
        if driving {
            ground := postale_game.drivable_surface_height(
                terrain.sample_height(
                    &editor.project,
                    0,
                    editor.postale.body.position.x,
                    editor.postale.body.position.z,
                ),
                editor.project.sea_level,
            )
            altitude := max(f32(0), editor.postale.body.position.y - ground - postale_game.GROUND_CLEARANCE)
            hud := fmt.tprintf(
                "THR %3.0f%%   AIR %3.0f m/s   ALT %3.0f m",
                editor.postale.throttle * 100,
                editor.postale.telemetry.airspeed,
                altitude,
            )
            rl.DrawTextEx(rl.Font{}, fmt.ctprintf("%s", hud), {26, 68}, 13, 1, {r = 236, g = 239, b = 190, a = 255})
            draw_flight_instruments(editor, width, height, altitude)
            if editor.postale.crashed {
                rl.DrawRectangle(width / 2 - 155, height / 2 - 35, 310, 70, {r = 71, g = 18, b = 20, a = 225})
                rl.DrawTextEx(
                    rl.Font{},
                    "POSTALE CRASHED — PRESS R TO RESET",
                    {f32(width / 2 - 139), f32(height / 2 - 8)},
                    16,
                    1,
                    {r = 255, g = 221, b = 195, a = 255},
                )
            } else if editor.postale.telemetry.is_stalling {
                rl.DrawTextEx(
                    rl.Font{},
                    "STALL",
                    {f32(width / 2 - 28), 28},
                    22,
                    1,
                    {r = 255, g = 110, b = 83, a = 255},
                )
            }
        } else {
            delta := vec_sub(editor.player.position, editor.postale.vehicle.position)
            if vec_dot(delta, delta) <=
               editor.postale.vehicle.interaction_radius * editor.postale.vehicle.interaction_radius {
                rl.DrawRectangle(width / 2 - 116, height - 92, 232, 42, {r = 8, g = 28, b = 45, a = 220})
                rl.DrawTextEx(
                    rl.Font{},
                    "PRESS F TO ENTER POSTALE",
                    {f32(width / 2 - 99), f32(height - 77)},
                    15,
                    1,
                    {r = 245, g = 239, b = 192, a = 255},
                )
            }
        }
    } else {
        world_x, world_z, hit := world_under_cursor_3d(
            camera,
            rl.GetMousePosition(),
            width,
            height,
            terrain.DEFAULT_ISLAND_HEIGHT,
        )
        if hit {
            brush_height := terrain.sample_height(&editor.project, 0, world_x, world_z) + .08
            brush_center := project_3d(camera, {x = world_x, y = brush_height, z = world_z}, width, height)
            brush_edge := project_3d(
                camera,
                {x = world_x + editor.radius, y = brush_height, z = world_z},
                width,
                height,
            )
            if brush_center.visible && brush_edge.visible {
                brush_radius := f32(
                    math.sqrt(
                        f64(
                            (brush_edge.position.x - brush_center.position.x) *
                                (brush_edge.position.x - brush_center.position.x) +
                            (brush_edge.position.y - brush_center.position.y) *
                                (brush_edge.position.y - brush_center.position.y),
                        ),
                    ),
                )
                rl.DrawCircleV(brush_center.position, brush_radius, {r = 230, g = 244, b = 218, a = 55})
            }
        }
        rl.DrawRectangle(14, 14, 520, 54, {r = 8, g = 28, b = 45, a = 210})
        rl.DrawTextEx(rl.Font{}, "ADRIATIC TERRAIN LAB — 3D", {26, 25}, 19, 1, {r = 211, g = 250, b = 242, a = 255})
        rl.DrawTextEx(
            rl.Font{},
            "Q/E/T tools  WASD pan  Middle orbit  Shift+wheel zoom  Wheel radius  Left/Right brush",
            {26, 49},
            12,
            1,
            {r = 183, g = 219, b = 221, a = 255},
        )
        draw_spawn_button()
    }
    minutes := int(sky.world_minutes)
    weather_label := atmosphere.preset_name(editor.atmosphere.override)
    clock := fmt.tprintf(
        "%02d:%02d  %s%s  [P] pause  [←/→] time  [4] auto  [1/2/3] weather",
        minutes / 60,
        minutes % 60,
        weather_label,
        editor.atmosphere.paused ? " PAUSED" : "",
    )
    rl.DrawTextEx(
        rl.Font{},
        fmt.ctprintf("%s", clock),
        {f32(width) - 545, 18},
        13,
        1,
        {r = 224, g = 239, b = 231, a = 240},
    )
}

draw_default_infrastructure :: proc(editor: ^Editor, center: rl.Vector2, scale: f32) {
    level := 0
    half_extent := f32(terrain.RING_RESOLUTION - 1) * editor.project.levels[level].cell_size * .5
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        island_x := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        island_z := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        runway_half_length := half_extent * terrain.DEFAULT_RUNWAY_HALF_LENGTH
        runway_half_width := half_extent * terrain.DEFAULT_RUNWAY_HALF_WIDTH
        height := terrain.sample_height(&editor.project, level, island_x, island_z) + .03
        // The runway runs along the island's diagonal and remains clearly legible
        // on the simple grass island beneath it.
        a := project_point(island_x - runway_half_length, island_z - runway_half_width, height, center, scale)
        b := project_point(island_x + runway_half_length, island_z - runway_half_width, height, center, scale)
        c := project_point(island_x + runway_half_length, island_z + runway_half_width, height, center, scale)
        d := project_point(island_x - runway_half_length, island_z + runway_half_width, height, center, scale)
        rl.DrawQuadHatched(a, b, c, d, {r = 60, g = 66, b = 67, a = 255}, rl.HATCH_DISABLED)
        rl.DrawLineEx(
            project_point(island_x - runway_half_length * .82, island_z, height + .02, center, scale),
            project_point(island_x + runway_half_length * .82, island_z, height + .02, center, scale),
            1.5,
            {r = 238, g = 232, b = 186, a = 255},
        )

        // A short wooden pier points from the island toward its nearby map edge.
        pier_inner_x := island_x + sign * half_extent * terrain.DEFAULT_PIER_INNER_OFFSET
        pier_inner_z := island_z - sign * half_extent * .08
        // End at the shoreline without extending beyond the finite terrain map.
        pier_outer_x := island_x + sign * half_extent * terrain.DEFAULT_ISLAND_RADIUS
        pier_outer_z := island_z - sign * half_extent * .16
        pier_width := half_extent * .035
        p0 := project_point(
            pier_inner_x,
            pier_inner_z - pier_width,
            terrain.sample_height(&editor.project, level, pier_inner_x, pier_inner_z) + .08,
            center,
            scale,
        )
        p1 := project_point(pier_outer_x, pier_outer_z - pier_width, editor.project.sea_level + .08, center, scale)
        p2 := project_point(pier_outer_x, pier_outer_z + pier_width, editor.project.sea_level + .08, center, scale)
        p3 := project_point(
            pier_inner_x,
            pier_inner_z + pier_width,
            terrain.sample_height(&editor.project, level, pier_inner_x, pier_inner_z) + .08,
            center,
            scale,
        )
        rl.DrawQuadHatched(p0, p1, p2, p3, {r = 137, g = 89, b = 48, a = 255}, rl.HATCH_DISABLED)
    }
}

draw_infinite_ocean :: proc(width, height: i32, time: f32) {
    rl.ClearBackground({r = 14, g = 54, b = 79, a = 255})
    for row in 0 ..< 24 {
        y := f32(row) * f32(height) / 23
        phase := f32(math.sin(f64(time * .9 + f32(row) * .73)))
        rl.DrawLineEx({0, y}, {f32(width), y + phase * 3}, 1, {r = 35, g = 102, b = 128, a = 110})
    }
}

editor_palette_bounds :: proc() -> rl.Rectangle {
    return {x = 20, y = 116, width = 830, height = 38}
}

editor_palette_button_bounds :: proc(index: int) -> rl.Rectangle {
    palette := editor_palette_bounds()
    gap := f32(5)
    button_width := (palette.width - gap * 6) / 7
    return {
        x = palette.x + f32(index) * (button_width + gap),
        y = palette.y,
        width = button_width,
        height = palette.height,
    }
}

editor_palette_tool :: proc(index: int) -> terrain.Tool {
    switch index {
    case 0:
        return .Raise
    case 1:
        return .Smooth
    case 2:
        return .Paint
    case 3, 4, 5, 6:
        return .Structure
    }
    return .Raise
}

editor_palette_curve_mode :: proc(index: int) -> bool {
    return index == 4 || index == 5
}

editor_palette_architecture_mode :: proc(index: int) -> bool { return index == 6 }

editor_palette_index :: proc(position: rl.Vector2) -> int {
    for index in 0 ..< 7 {
        if rl.CheckCollisionPointRec(position, editor_palette_button_bounds(index)) do return index
    }
    return -1
}

editor_palette_hit :: proc() -> bool {
    return editor_palette_index(rl.GetMousePosition()) >= 0
}

draw_editor_palette :: proc(editor: ^Editor) {
    palette := editor_palette_bounds()
    rl.DrawRectangleRounded(palette, .16, 8, {r = 8, g = 28, b = 45, a = 242})
    labels := [?]cstring{"SCULPT", "SMOOTH", "PAINT", "FORMATIONS", "RIDGE CURVE", "CLIFF CURVE", "BUILDING PAINT"}
    for index in 0 ..< 7 {
        button := editor_palette_button_bounds(index)
        selected :=
            editor.tool == editor_palette_tool(index) &&
            (!editor_palette_curve_mode(index) &&
                        !editor.curve_mode &&
                        (!editor_palette_architecture_mode(index) || editor.architecture_paint_mode) ||
                    editor_palette_curve_mode(index) && editor.curve_mode && (index == 5) == editor.curve_cliff_mode)
        hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), button)
        fill: rl.Color = {
            r = 18,
            g = 53,
            b = 67,
            a = 255,
        }
        if hovered do fill = {
            r = 35,
            g = 83,
            b = 93,
            a = 255,
        }
        if selected do fill = {
            r = 59,
            g = 137,
            b = 129,
            a = 255,
        }
        border: rl.Color = {
            r = 86,
            g = 153,
            b = 158,
            a = 255,
        }
        if selected do border = {
            r = 211,
            g = 250,
            b = 242,
            a = 255,
        }
        rl.DrawRectangleRounded(button, .14, 8, fill)
        rl.DrawRectangleRoundedLinesEx(button, .14, 8, selected ? 2 : 1, border)
        text_width := ui_measure_text(.Label, labels[index], 1).x
        ui_draw_text(
            .Label,
            labels[index],
            {button.x + (button.width - text_width) * .5, button.y + 11},
            1,
            {r = 239, g = 255, b = 250, a = 255},
        )
    }
}

spawn_button_bounds :: proc() -> rl.Rectangle { return {x = 20, y = 164, width = 170, height = 34} }

draw_spawn_button :: proc() {
    bounds := spawn_button_bounds()
    hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), bounds)
    fill := rl.Color {
        r = 43,
        g = 112,
        b = 119,
        a = 255,
    }
    if hovered do fill = {
        r = 58,
        g = 142,
        b = 150,
        a = 255,
    }
    rl.DrawRectangleRounded(bounds, .18, 8, fill)
    rl.DrawRectangleRoundedLinesEx(bounds, .18, 8, 1, {r = 176, g = 239, b = 230, a = 255})
    ui_draw_text(.Body, "SPAWN INTO MAP", {bounds.x + 15, bounds.y + 9}, 1, {r = 245, g = 255, b = 247, a = 255})
}

runway_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    half_extent := f32(terrain.RING_RESOLUTION - 1) * editor.project.levels[0].cell_size * .5
    x := half_extent * terrain.DEFAULT_ISLAND_OFFSET + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET
    // Start beside the parked aircraft so the default camera presents it and
    // the runway immediately instead of placing the character inside its mesh.
    z := half_extent * terrain.DEFAULT_ISLAND_OFFSET + 2.2
    return {x = x, y = terrain.sample_height(&editor.project, 0, x, z), z = z}
}

car_spawn_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    // Park the car on the apron beside the runway rather than on the flight
    // surface. This keeps the aircraft arrival lane clear while leaving the car
    // close enough to reach from the default player spawn.
    runway := runway_spawn_position(editor)
    spawn := vehicles.car_spawn_near({x = runway.x + 8, y = runway.y, z = runway.z + 4})
    spawn.y = terrain.sample_height(&editor.project, 0, spawn.x, spawn.z)
    return spawn
}

driving_postale :: proc(editor: ^Editor) -> bool {
    return editor != nil && editor.pilot.mode == .Driving && editor.pilot.vehicle == &editor.postale.vehicle
}

driving_car :: proc(editor: ^Editor) -> bool {
    return editor != nil && editor.pilot.mode == .Driving && editor.pilot.vehicle == &editor.car
}

vehicle_entry_prompt :: proc(editor: ^Editor) -> cstring {
    if editor == nil || editor.pilot.mode != .On_Foot do return nil
    car_delta := vec_sub(editor.player.position, editor.car.position)
    car_distance := vec_dot(car_delta, car_delta)
    car_radius := editor.car.interaction_radius
    if car_radius <= 0 do car_radius = 2.5
    postale_delta := vec_sub(editor.player.position, editor.postale.vehicle.position)
    postale_distance := vec_dot(postale_delta, postale_delta)
    postale_radius := editor.postale.vehicle.interaction_radius
    if postale_radius <= 0 do postale_radius = 2.5
    libellula_delta := vec_sub(editor.player.position, editor.libellula.position)
    libellula_distance := vec_dot(libellula_delta, libellula_delta)
    libellula_near := editor.libellula_visible && libellula_distance <= 4.5 * 4.5
    if libellula_near do return "PRESS F TO TALK TO MARTA"
    car_near := car_distance <= car_radius * car_radius
    postale_near := postale_distance <= postale_radius * postale_radius
    if car_near && (!postale_near || car_distance <= postale_distance) {
        return "PRESS F TO ENTER CAR"
    }
    if postale_near do return editor.libellula_active ? "PRESS F TO ENTER LIBELLULA" : "PRESS F TO ENTER POSTALE"
    return nil
}

editor_camera_pose :: proc() -> third_person.Camera_Pose {
    island_center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    return {
        position = {x = island_center + 650, y = 720, z = island_center + 650},
        target = {x = island_center, y = 1.5, z = island_center},
    }
}

draw_terrain_isometric_legacy :: proc(editor: ^Editor, width, height: i32, time: f32) {
    draw_infinite_ocean(width, height, time)
    center := rl.Vector2{f32(width) * .5, f32(height) * .55}
    scale := min(f32(width) / 130, f32(height) / 78)
    if editor.in_map {
        // The rendered view follows the eased orbit target, rather than snapping
        // to the player. Distance is a true camera zoom in this 2D presentation.
        // (A 5-unit orbit is the authored, neutral field of view.)
        view_target := editor.camera_pose.target
        scale *= third_person.default_camera().distance / editor.camera.distance
        center.x -= (view_target.x - view_target.z) * scale
        center.y -= (view_target.x + view_target.z) * scale * .46
        center.y += view_target.y * scale
    }
    // The near clipmap level is a dense heightfield; all five levels are edited
    // together and their extents are shown as colored horizon rings below.
    level := 0
    cell := editor.project.levels[level].cell_size
    for z in 0 ..< terrain.RING_RESOLUTION - 1 {
        for x in 0 ..< terrain.RING_RESOLUTION - 1 {
            x0 := (f32(x) - f32(terrain.RING_RESOLUTION - 1) * .5) * cell
            z0 := (f32(z) - f32(terrain.RING_RESOLUTION - 1) * .5) * cell
            h00 := terrain.sample_height(&editor.project, level, x0, z0)
            h10 := terrain.sample_height(&editor.project, level, x0 + cell, z0)
            h11 := terrain.sample_height(&editor.project, level, x0 + cell, z0 + cell)
            h01 := terrain.sample_height(&editor.project, level, x0, z0 + cell)
            color := terrain_color(
                (h00 + h10 + h11 + h01) * .25,
                terrain.sample_material(&editor.project, level, x0, z0),
                editor.project.sea_level,
            )
            rl.DrawQuadHatched(
                project_point(x0, z0, h00, center, scale),
                project_point(x0 + cell, z0, h10, center, scale),
                project_point(x0 + cell, z0 + cell, h11, center, scale),
                project_point(x0, z0 + cell, h01, center, scale),
                color,
                rl.HATCH_DISABLED,
            )
        }
    }

    // draw_runway_spawn makes the starting position tangible: the amber beacon
    // remains visible beneath the parked aircraft and shows where a reset returns.
    draw_runway_spawn :: proc(editor: ^Editor, center: rl.Vector2, scale, x, z: f32) {
        height := terrain.sample_height(&editor.project, 0, x, z) + .12
        marker := project_point(x, z, height, center, scale)
        rl.DrawCircleV(marker, 5, {r = 248, g = 185, b = 62, a = 255})
        rl.DrawCircleV(marker, 2, {r = 255, g = 242, b = 196, a = 255})
        rl.DrawTextEx(rl.Font{}, "SPAWN", {marker.x - 72, marker.y + 14}, 12, 1, {r = 255, g = 234, b = 164, a = 255})
    }

    // draw_postale_on_runway adapts the generated presentation mesh to the
    // terrain lab's isometric view. The aircraft faces down the runway.
    draw_postale_on_runway :: proc(editor: ^Editor, center: rl.Vector2, scale, x, z: f32) {
        mesh := vehicles.postale_mesh()
        aircraft_scale := f32(.68)
        for triangle in vehicles.mesh_triangles(&mesh) {
            points: [3]rl.Vector2
            indices := [3]u16{triangle.a, triangle.b, triangle.c}
            part := mesh.vertices[triangle.a].part
            for index in 0 ..< 3 {
                position := mesh.vertices[indices[index]].position
                world_x := x + position[2] * aircraft_scale
                world_z := z - position[0] * aircraft_scale
                points[index] = project_point(
                    world_x,
                    world_z,
                    terrain.sample_height(&editor.project, 0, world_x, world_z) + .32 + position[1] * aircraft_scale,
                    center,
                    scale,
                )
            }
            rl.DrawQuadHatched(
                points[0],
                points[1],
                points[2],
                points[2],
                aircraft_part_color(part),
                rl.HATCH_DISABLED,
            )
        }
        label := project_point(x, z, terrain.sample_height(&editor.project, 0, x, z) + 2.15, center, scale)
        rl.DrawTextEx(rl.Font{}, "POSTALE", {label.x - 28, label.y - 30}, 12, 1, {r = 255, g = 239, b = 192, a = 255})
    }
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        half_extent := f32(terrain.RING_RESOLUTION - 1) * editor.project.levels[level].cell_size * .5
        shade := u8(96 + level * 26)
        outline := rl.Color {
            r = shade,
            g = 210,
            b = 240,
            a = 135,
        }
        a := project_point(-half_extent, -half_extent, editor.project.sea_level, center, scale)
        b := project_point(half_extent, -half_extent, editor.project.sea_level, center, scale)
        c := project_point(half_extent, half_extent, editor.project.sea_level, center, scale)
        d := project_point(-half_extent, half_extent, editor.project.sea_level, center, scale)
        rl.DrawLineEx(
            a,
            b,
            1,
            outline,
        ); rl.DrawLineEx(b, c, 1, outline); rl.DrawLineEx(c, d, 1, outline); rl.DrawLineEx(d, a, 1, outline)
    }
    draw_default_infrastructure(editor, center, scale)
    // The northeast runway is the playable arrival point: a Postale waits at
    // the threshold and the beacon provides an unambiguous respawn reference.
    half_extent := f32(terrain.RING_RESOLUTION - 1) * editor.project.levels[0].cell_size * .5
    spawn_x := half_extent * terrain.DEFAULT_ISLAND_OFFSET + half_extent * terrain.DEFAULT_RUNWAY_SPAWN_OFFSET
    spawn_z := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    draw_runway_spawn(editor, center, scale, spawn_x, spawn_z)
    draw_postale_on_runway(editor, center, scale, spawn_x, spawn_z)
    if editor.in_map {
        feet := project_point(
            editor.player.position.x,
            editor.player.position.z,
            editor.player.position.y + .08,
            center,
            scale,
        )
        head := project_point(
            editor.player.position.x,
            editor.player.position.z,
            editor.player.position.y + 1.55,
            center,
            scale,
        )
        // The body and a short facing marker make the controller's turn response
        // immediately legible in this intentionally lightweight map renderer.
        facing := rl.Vector2 {
            x = head.x - math.sin(editor.player.facing_yaw_radians) * 14,
            y = head.y - math.cos(editor.player.facing_yaw_radians) * 7,
        }
        rl.DrawLineEx(feet, head, 3, {r = 53, g = 226, b = 213, a = 255})
        rl.DrawCircleV(head, 6, {r = 247, g = 221, b = 167, a = 255})
        rl.DrawLineEx(head, facing, 3, {r = 247, g = 221, b = 167, a = 255})
    }
    mouse := rl.GetMousePosition()
    world_x, world_z := world_under_cursor(mouse, center, scale)
    brush := project_point(
        world_x,
        world_z,
        terrain.sample_height(&editor.project, 0, world_x, world_z),
        center,
        scale,
    )
    rl.DrawCircleV(brush, editor.radius * scale, {r = 230, g = 244, b = 218, a = 60})
    rl.DrawTextEx(rl.Font{}, "ADRIATIC TERRAIN LAB", {20, 18}, 24, 1, {r = 224, g = 245, b = 250, a = 255})
    tool_name := editor.tool == .Raise ? "SCULPT" : editor.tool == .Smooth ? "SMOOTH" : "PAINT"
    status := fmt.tprintf(
        "%s  radius %.1f  strength %.2f  |  five-level terrain clipmap in an infinite ocean",
        tool_name,
        editor.radius,
        editor.strength,
    )
    rl.DrawTextEx(rl.Font{}, fmt.ctprintf("%s", status), {20, 48}, 16, 1, {r = 196, g = 222, b = 227, a = 255})
    if editor.in_map {
        rl.DrawRectangle(14, 14, 248, 54, {r = 11, g = 39, b = 55, a = 220})
        rl.DrawTextEx(rl.Font{}, "THIRD-PERSON MAP", {26, 25}, 19, 1, {r = 211, g = 250, b = 242, a = 255})
        rl.DrawTextEx(
            rl.Font{},
            "WASD move  Mouse look  Wheel zoom  Space jump  Esc editor",
            {26, 49},
            13,
            1,
            {r = 183, g = 219, b = 221, a = 255},
        )
    } else {
        draw_spawn_button()
        rl.DrawTextEx(
            rl.Font{},
            "Q Sculpt   E Smooth   T Paint   B Formation Toolbox   Wheel Radius   Left/Right Brush",
            {20, f32(height) - 30},
            15,
            1,
            {r = 220, g = 238, b = 241, a = 230},
        )
    }
}

draw_terrain :: proc(editor: ^Editor, width, height: i32, time: f32) {
    // The depth-tested world pass has already drawn the game/editor scene.
    // Canvas commands from here onward are deliberately UI-only.
    rl.ClearBackground({r = 104, g = 154, b = 181, a = 255})
    if editor.in_map {
        flying := driving_postale(editor)
        in_car := driving_car(editor)
        driving := flying || in_car
        panel_width := driving ? i32(650) : i32(430)
        help_text: cstring = "WASD move  Mouse look  Wheel zoom  Space jump  Esc editor"
        if flying do help_text = "W/S pitch  A/D roll  Q/E yaw  Mouse orbit  C camera  Shift/Ctrl power  F exit  R reset"
        if in_car do help_text = "W/S drive  A/D steer  Space handbrake  F exit  Esc editor"
        rl.DrawRectangle(14, 14, panel_width, 72, {r = 8, g = 28, b = 45, a = 210})
        rl.DrawTextEx(
            rl.Font{},
            flying ? (editor.libellula_active ? "LIBELLULA FLIGHT" : "POSTALE FLIGHT") : (in_car ? "CAR DRIVE" : "THIRD-PERSON 3D"),
            {26, 25},
            19,
            1,
            {211, 250, 242, 255},
        )
        rl.DrawTextEx(rl.Font{}, help_text, {26, 49}, 13, 1, {183, 219, 221, 255})
        if flying {
            ground := postale_game.drivable_surface_height(
                terrain.sample_height(
                    &editor.project,
                    0,
                    editor.postale.body.position.x,
                    editor.postale.body.position.z,
                ),
                editor.project.sea_level,
            )
            altitude := max(f32(0), editor.postale.body.position.y - ground - postale_game.GROUND_CLEARANCE)
            hud := fmt.tprintf(
                "THR %3.0f%%   AIR %3.0f m/s   ALT %3.0f m",
                editor.postale.throttle * 100,
                editor.postale.telemetry.airspeed,
                altitude,
            )
            rl.DrawTextEx(rl.Font{}, fmt.ctprintf("%s", hud), {26, 68}, 13, 1, {236, 239, 190, 255})
            draw_flight_instruments(editor, width, height, altitude)
        } else if editor.attendant_dialogue_open {
            rl.DrawRectangle(width / 2 - 310, height - 190, 620, 142, {8, 28, 45, 238})
            conversation := &editor.attendant_dialogue
            if current := dialogue.current(conversation); current != nil {
                rl.DrawTextEx(
                    rl.Font{},
                    fmt.ctprintf("%s", current.speaker(&conversation.ctx)),
                    {f32(width / 2 - 286), f32(height - 170)},
                    15,
                    1,
                    {211, 250, 242, 255},
                )
                rl.DrawTextEx(
                    rl.Font{},
                    fmt.ctprintf("%s", current.text(&conversation.ctx)),
                    {f32(width / 2 - 286), f32(height - 140)},
                    14,
                    1,
                    {245, 239, 192, 255},
                )
                rl.DrawTextEx(
                    rl.Font{},
                    "[Y] Switch to Libellula     [N] Keep Postale",
                    {f32(width / 2 - 286), f32(height - 100)},
                    14,
                    1,
                    {183, 219, 221, 255},
                )
            }
        } else if prompt := vehicle_entry_prompt(editor); prompt != nil {
            rl.DrawRectangle(width / 2 - 116, height - 92, 232, 42, {8, 28, 45, 220})
            rl.DrawTextEx(rl.Font{}, prompt, {f32(width / 2 - 99), f32(height - 77)}, 15, 1, {245, 239, 192, 255})
        }
    } else {
        // Keep the authoring HUD readable over both the pale horizon and the
        // darker ocean. The status lines are intentionally larger than the
        // world labels because they are the primary interaction affordance.
        rl.DrawRectangle(14, 14, 826, 96, {8, 28, 45, 242})
        ui_draw_text(.Display, "ADRIATIC TERRAIN LAB — 3D", {26, 20}, 1, {239, 255, 250, 255})
        ui_draw_text(
            .Body,
            "Select a curve tool, then drag  G Adriatic geometry nodes  Alt cluster  Ctrl box  WASD pan  MMB orbit",
            {26, 51},
            1,
            {226, 248, 244, 255},
        )
        tool_name: cstring =
            editor.architecture_paint_mode ? "BUILDING PAINT" : editor.tool == .Raise ? "SCULPT" : editor.tool == .Smooth ? "SMOOTH" : editor.tool == .Paint ? "PAINT" : "STRUCTURES"
        formation_profile :=
            editor.architecture_node_mode ? "ADRIATIC NODES" : (editor.structure_auto_kind ? "AUTO" : formation_kind_name(editor.structure_kind))
        editor_status :=
            editor.architecture_paint_mode ? fmt.tprintf("%s  %d buildings  |  drag paint area  wheel height %.0f m  Shift+wheel spacing %.0f m", tool_name, editor.project.structure_count, editor.architecture_building_height, editor.architecture_sample_radius) : editor.tool == .Structure ? fmt.tprintf("%s/%s  %d placed  |  G regenerate node graph  Select RIDGE/CLIFF CURVE  Ctrl+Z/Y undo/redo", tool_name, formation_profile, editor.project.structure_count) : fmt.tprintf("%s  radius %.0f m  strength %.2f  |  4.0 km × 4.0 km  |  %.1f m cells", tool_name, editor.radius, editor.strength, terrain.BASE_CELL_SIZE)
        ui_draw_text(.Data, fmt.ctprintf("%s", editor_status), {26, 78}, 1, {255, 244, 190, 255})
        draw_editor_palette(editor)
        draw_spawn_button()
    }
    sky := atmosphere.sample(&editor.atmosphere)
    minutes := int(sky.world_minutes)
    clock := fmt.tprintf(
        "%02d:%02d  %s%s  [P] pause  [←/→] time  [4] auto  [1/2/3] weather",
        minutes / 60,
        minutes % 60,
        atmosphere.preset_name(editor.atmosphere.override),
        editor.atmosphere.paused ? " PAUSED" : "",
    )
    // The clock sits over the sky, so give it its own high-contrast backing.
    rl.DrawRectangle(width - 560, 14, 546, 40, {8, 28, 45, 242})
    ui_draw_text(.Data, fmt.ctprintf("%s", clock), {f32(width) - 548, 24}, 1, {239, 255, 250, 255})
}

main :: proc() {
    assert(rl.SetRendererDescriptor(ADRIATIC_RENDERER_DESCRIPTOR))
    flags := rl.ConfigFlags{.WINDOW_RESIZABLE, .VSYNC_HINT}
    capture_mode :=
        len(os.args) >= 3 &&
        (os.args[1] == "--capture" ||
                os.args[1] == "--capture-map" ||
                os.args[1] == "--capture-flight" ||
                os.args[1] == "--capture-car" ||
                os.args[1] == "--capture-sky-noon" ||
                os.args[1] == "--capture-sky-sunset" ||
                os.args[1] == "--capture-sky-storm" ||
                os.args[1] == "--capture-sky-night")
    capture_sky_mode :=
        capture_mode &&
        (os.args[1] == "--capture-sky-noon" ||
                os.args[1] == "--capture-sky-sunset" ||
                os.args[1] == "--capture-sky-storm" ||
                os.args[1] == "--capture-sky-night")
    capture_map_mode := capture_mode && (os.args[1] == "--capture-map" || capture_sky_mode)
    capture_flight_mode := capture_mode && os.args[1] == "--capture-flight"
    capture_car_mode := capture_mode && os.args[1] == "--capture-car"
    capture_target := capture_mode && len(os.args) >= 4 ? os.args[3] : ""
    if capture_mode do flags += {.WINDOW_NOT_FOCUSABLE}
    rl.SetConfigFlags(flags)
    rl.SetWorldRenderSize(ADRIATIC_WORLD_WIDTH, ADRIATIC_WORLD_HEIGHT)
    rl.InitWindow(1280, 720, "Adriatic — Clipmap Terrain Authoring")
    defer rl.CloseWindow()
    editor := new(Editor)
    defer free(editor)
    terrain.init_project(&editor.project)
    editor.tool = .Raise
    editor.radius = 48
    editor.strength = .10
    editor.structure_selected = -1
    editor.structure_kind = .Box
    editor.structure_auto_kind = true
    editor.structure_scatter_count = 4
    editor.curve_width = terrain.BASE_CELL_SIZE * 2.5
    editor.curve_height = terrain.BASE_CELL_SIZE * 2.0
    editor.atmosphere = atmosphere.new(0x41c10)
    editor.particles = particle_systems.new_cpu(0x9e3779b9)
    editor.vehicle_effects = particle_systems.new_vehicle_effects(0x72b7e4a1)
    editor.wing_trails = particle_systems.new_wing_trails(0x1f123bb5)
    editor.tweak = tweak_default_state()
    editor.tweak_status = .Defaults
    island_center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    editor.editor_focus = {
        x = island_center,
        z = island_center,
    }
    particle_systems.step(&editor.particles, 2.4, particle_systems.Vec3{x = island_center, y = 6.0, z = island_center})
    editor.editor_camera = {
        yaw_radians   = math.PI * .25,
        pitch_radians = .58,
        distance      = 900,
    }
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    editor.postale = postale_game.new_runtime(postale_spawn_position(editor))
    editor.libellula = vehicles.default_vehicle(libellula_spawn_position(editor))
    editor.libellula.interaction_radius = 4.5
    editor.postale_visible = true
    editor.libellula_visible = true
    editor.libellula.locked = true
    editor.car = vehicles.default_vehicle(car_spawn_position(editor))
    editor.car.interaction_radius = 3
    editor.car.exit_distance = 1.45
    editor.car.yaw_radians = -math.PI * .5
    editor.pilot.position = runway_spawn_position(editor)
    if capture_mode && !capture_map_mode {
        seed_formation_capture(editor)
        editor.editor_camera.distance = 260
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    }
    if capture_sky_mode {
        preset := atmosphere.Weather_Preset.Clear
        minutes := f32(12 * 60)
        switch os.args[1] {
        case "--capture-sky-sunset":
            minutes = 18 * 60
        case "--capture-sky-storm":
            minutes = 13 * 60
            preset = .Storm
        case "--capture-sky-night":
            minutes = 0
        }
        atmosphere.set_world_minutes(&editor.atmosphere, minutes)
        atmosphere.set_weather_override(&editor.atmosphere, preset)
        editor.atmosphere.weather = atmosphere.weather_for(preset)
        editor.atmosphere.paused = true
    }
    world_renderer_attach(editor)
    defer world_renderer_destroy()
    if capture_map_mode || capture_flight_mode || capture_car_mode {
        editor.player = {
            position = runway_spawn_position(editor),
            grounded = true,
        }
        editor.camera = third_person.default_camera()
        editor.camera_pose = third_person.camera_pose(editor.player.position, editor.camera)
        editor.pilot.position = editor.player.position
        editor.in_map = true
        editor.map_time = f32(rl.GetTime())
        if capture_flight_mode {
            _, entered := vehicles.try_enter_nearest(&editor.pilot, []^vehicles.Vehicle{&editor.postale.vehicle})
            if entered {
                // Give the flight capture a reproducible airborne state so visual
                // verification exercises the wing-trail and wind-response systems.
                editor.postale.body.position.y += 85
                editor.postale.body.velocity = flight.scale(editor.postale.body.basis.forward, 38)
                editor.postale.grounded = false
                editor.postale.was_grounded = false
                editor.postale.throttle = .82
                atmosphere.set_weather_override(&editor.atmosphere, .Windy)
                editor.atmosphere.weather = atmosphere.weather_for(.Windy)
                editor.atmosphere.paused = true
                chase_camera.reset(&editor.flight_camera, postale_camera_target(editor))
                editor.camera_pose = editor.flight_camera.pose
            }
        }
        if capture_car_mode {
            car := car_spawn_position(editor)
            editor.player.position = {
                x = car.x + 100,
                y = car.y,
                z = car.z + 100,
            }
            editor.pilot.position = editor.player.position
            editor.camera_pose = {
                position = {x = car.x - 7.5, y = car.y + 4.6, z = car.z + 7.5},
                target = {x = car.x, y = car.y + .65, z = car.z},
            }
        }
        if capture_target == "libellula" {
            editor.camera_target_lock = true
            editor.player.position = {
                x = editor.libellula.position.x + 12,
                y = terrain.sample_height(
                    &editor.project,
                    0,
                    editor.libellula.position.x + 12,
                    editor.libellula.position.z + 12,
                ),
                z = editor.libellula.position.z + 12,
            }
            editor.pilot.position = editor.player.position
            inspection_pose := third_person.camera_near(editor.libellula.position, {x = 8, y = 5, z = 8})
            third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.camera_pose = inspection_pose
        }
        if capture_target == "postale" {
            editor.camera_target_lock = true
            postale_position := third_person.Vec3 {
                x = editor.postale.body.position.x,
                y = editor.postale.body.position.y,
                z = editor.postale.body.position.z,
            }
            editor.player.position = {
                x = postale_position.x + 12,
                y = terrain.sample_height(&editor.project, 0, postale_position.x + 12, postale_position.z + 12),
                z = postale_position.z + 12,
            }
            editor.pilot.position = editor.player.position
            inspection_pose := third_person.camera_near(postale_position, {x = 4.5, y = 2.6, z = 4.5})
            third_person.camera_set_pose(&editor.cameras, .Inspection, inspection_pose)
            third_person.camera_set_active(&editor.cameras, .Inspection)
            editor.camera_pose = inspection_pose
        }
    }
    frame := 0
    for !rl.WindowShouldClose() {
        frame_now := f32(rl.GetTime())
        frame_delta := frame == 0 ? f32(0) : min(frame_now - editor.map_time, f32(.1))
        driving := editor.pilot.mode == .Driving
        if !editor.in_map do editor.map_time = frame_now
        atmosphere.step(&editor.atmosphere, frame_delta)
        particle_systems.step(
            &editor.particles,
            frame_delta,
            particle_systems.Vec3{x = island_center, y = 6.0, z = island_center},
        )
        if rl.IsKeyPressed(.P) do editor.atmosphere.paused = !editor.atmosphere.paused
        if rl.IsKeyDown(.LEFT) do atmosphere.set_world_minutes(&editor.atmosphere, editor.atmosphere.world_minutes - frame_delta * 180)
        if rl.IsKeyDown(.RIGHT) do atmosphere.set_world_minutes(&editor.atmosphere, editor.atmosphere.world_minutes + frame_delta * 180)
        if rl.IsKeyPressed(.FOUR) do atmosphere.set_weather_override(&editor.atmosphere, .Automatic)
        if rl.IsKeyPressed(.ONE) do atmosphere.set_weather_override(&editor.atmosphere, .Clear)
        if rl.IsKeyPressed(.TWO) do atmosphere.set_weather_override(&editor.atmosphere, .Windy)
        if rl.IsKeyPressed(.THREE) do atmosphere.set_weather_override(&editor.atmosphere, .Storm)
        width, height := rl.GetScreenWidth(), rl.GetScreenHeight()
        if editor.in_map && rl.IsKeyPressed(.ESCAPE) {
            editor.in_map = false
            third_person.camera_set_active(&editor.cameras, .Player)
            editor.map_time = 0
            editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
            set_pointer_locked(false)
        }
        if !editor.in_map &&
           rl.IsMouseButtonPressed(.LEFT) &&
           rl.CheckCollisionPointRec(rl.GetMousePosition(), spawn_button_bounds()) {
            if editor.pilot.mode == .On_Foot {
                editor.player = {
                    position = editor.pilot.position,
                    grounded = true,
                }
            }
            editor.camera = third_person.default_camera()
            camera_target := editor.player.position
            if editor.pilot.mode == .Driving do camera_target = editor.pilot.vehicle.position
            editor.camera_pose = third_person.camera_pose(camera_target, editor.camera)
            editor.in_map = true
            editor.map_time = f32(rl.GetTime())
            set_pointer_locked(true)
        }
        if !editor.in_map {
            palette_index := editor_palette_index(rl.GetMousePosition())
            if rl.IsMouseButtonPressed(.LEFT) && palette_index >= 0 {
                editor.tool = editor_palette_tool(palette_index)
                editor.architecture_paint_mode = editor_palette_architecture_mode(palette_index)
                editor.architecture_node_mode = false
                editor.curve_mode = editor_palette_curve_mode(palette_index)
                if editor.curve_mode do editor.curve_cliff_mode = palette_index == 5
                curve_reset(editor)
                editor.structure_placing = false
                editor.structure_moving = false
            }
            if rl.IsKeyPressed(.Q) {
                editor.tool = .Raise
                editor.architecture_paint_mode = false
                editor.curve_mode = false
                curve_reset(editor)
            }
            if rl.IsKeyPressed(.E) {
                editor.tool = .Smooth
                editor.architecture_paint_mode = false
                editor.curve_mode = false
                curve_reset(editor)
            }
            if rl.IsKeyPressed(.T) {
                editor.tool = .Paint
                editor.architecture_paint_mode = false
                editor.curve_mode = false
                curve_reset(editor)
            }
            if rl.IsKeyPressed(.B) {
                editor.tool = .Structure
                editor.architecture_paint_mode = false
                editor.curve_mode = false
                curve_reset(editor)
                editor.structure_placing = false
                editor.structure_moving = false
            }
            if rl.IsKeyPressed(.G) {
                center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
                architecture.generate(&editor.project, center, center, 0xA71D3)
                editor.tool = .Structure
                editor.curve_mode = false
                curve_reset(editor)
                editor.structure_selected = -1
                editor.architecture_node_mode = true
                editor.architecture_paint_mode = false
            }
            if editor.tool == .Structure && rl.IsKeyPressed(.V) do structure_cycle_kind(editor)
            if editor.tool == .Structure && rl.IsKeyPressed(.X) {
                editor.structure_auto_kind = true
            }
            update_editor_camera(editor, min(frame_delta, f32(.05)))
            if editor.tool == .Structure && editor.curve_drawing {
                cell := editor.project.levels[0].cell_size
                wheel := rl.GetMouseWheelMove()
                editor.curve_width = max(cell, editor.curve_width + wheel * cell)
                editor.curve_height = max(cell, editor.curve_height + wheel * cell)
            } else if editor.tool == .Structure && editor.architecture_paint_mode {
                wheel := rl.GetMouseWheelMove()
                if shift_key_down() {
                    editor.architecture_sample_radius = clamp(
                        editor.architecture_sample_radius + wheel * terrain.BASE_CELL_SIZE,
                        terrain.BASE_CELL_SIZE * 2,
                        terrain.BASE_CELL_SIZE * 12,
                    )
                } else {
                    editor.architecture_building_height = clamp(
                        editor.architecture_building_height + wheel * terrain.BASE_CELL_SIZE,
                        terrain.BASE_CELL_SIZE * 3,
                        terrain.BASE_CELL_SIZE * 18,
                    )
                }
            } else if editor.tool == .Structure {
                structure_adjust_with_wheel(editor, rl.GetMouseWheelMove())
            } else if !shift_key_down() {
                editor.radius = clamp(
                    editor.radius + rl.GetMouseWheelMove() * terrain.BASE_CELL_SIZE,
                    terrain.BASE_CELL_SIZE,
                    400,
                )
            }
        }
        focal_length := f32(1.35)
        if editor.in_map && driving_postale(editor) {
            focal_length = editor.flight_camera.focal_length
        }
        editor_view_camera := perspective_camera(editor.camera_pose, focal_length)
        world_mouse, world_mouse_inside := rl.GetWorldMousePosition()
        world_x, world_z, cursor_hit := terrain_under_cursor_3d(
            editor,
            editor_view_camera,
            world_mouse,
            ADRIATIC_WORLD_WIDTH,
            ADRIATIC_WORLD_HEIGHT,
        )
        cursor_hit = cursor_hit && world_mouse_inside
        ui_hit := editor_palette_hit() || rl.CheckCollisionPointRec(rl.GetMousePosition(), spawn_button_bounds())
        architecture_paint_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        curve_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        if !editor.architecture_paint_mode &&
           !editor.curve_mode &&
           !editor.curve_drawing &&
           editor.curve_point_count == 0 {
            structure_process_input(editor, world_x, world_z, cursor_hit && !ui_hit)
        }
        if editor.in_map && !capture_car_mode {
            now := f32(rl.GetTime())
            delta_seconds := now - editor.map_time
            editor.map_time = now
            mouse_delta := rl.GetMouseDelta()
            flying := driving_postale(editor)
            in_car := driving_car(editor)
            if flying {
                chase_camera.look(&editor.flight_camera, mouse_delta.x, mouse_delta.y)
                if rl.IsKeyPressed(.C) {
                    chase_camera.reset(&editor.flight_camera, postale_camera_target(editor))
                }
                if rl.IsKeyPressed(.R) {
                    ground := postale_game.drivable_surface_height(
                        terrain.sample_height(
                            &editor.project,
                            0,
                            editor.postale.spawn_position.x,
                            editor.postale.spawn_position.z,
                        ),
                        editor.project.sea_level,
                    )
                    postale_game.reset(&editor.postale, ground)
                    vehicles.sync_driver(&editor.pilot)
                }
                control := postale_game.Control {
                    throttle_up   = rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT),
                    throttle_down = control_key_down(),
                }
                if rl.IsKeyDown(.S) do control.pitch += 1
                if rl.IsKeyDown(.W) do control.pitch -= 1
                if rl.IsKeyDown(.D) do control.roll += 1
                if rl.IsKeyDown(.A) do control.roll -= 1
                if rl.IsKeyDown(.E) do control.yaw += 1
                if rl.IsKeyDown(.Q) do control.yaw -= 1
                if rl.GamepadAvailable() {
                    control.pitch = stronger_axis(control.pitch, shape_flight_axis(rl.GetGamepadAxis(.Left_Y)))
                    control.roll = stronger_axis(control.roll, shape_flight_axis(rl.GetGamepadAxis(.Left_X)))
                    if rl.IsGamepadButtonDown(.Right_Shoulder) do control.yaw += 1
                    if rl.IsGamepadButtonDown(.Left_Shoulder) do control.yaw -= 1
                    control.throttle_up = control.throttle_up || rl.GetGamepadAxis(.Right_Trigger) > .1
                    control.throttle_down = control.throttle_down || rl.GetGamepadAxis(.Left_Trigger) > .1
                }
                control.pitch = clamp(control.pitch, -1, 1)
                control.roll = clamp(control.roll, -1, 1)
                control.yaw = clamp(control.yaw, -1, 1)
                editor.flight_control = control
                ground := postale_game.drivable_surface_height(
                    terrain.sample_height(
                        &editor.project,
                        0,
                        editor.postale.body.position.x,
                        editor.postale.body.position.z,
                    ),
                    editor.project.sea_level,
                )
                postale_game.step(
                    &editor.postale,
                    control,
                    ground,
                    min(delta_seconds, .05),
                )
                if editor.libellula_active {
                    editor.libellula.position = third_person.Vec3 {
                        x = editor.postale.body.position.x,
                        y = editor.postale.body.position.y,
                        z = editor.postale.body.position.z,
                    }
                }
                left_tip := postale_vertex_world(
                    &editor.postale,
                    {-5.35, POSTALE_WING_TRAIL_LOCAL_Y, POSTALE_WING_TRAIL_LOCAL_Z},
                    POSTALE_PRESENTATION_SCALE,
                )
                right_tip := postale_vertex_world(
                    &editor.postale,
                    {5.35, POSTALE_WING_TRAIL_LOCAL_Y, POSTALE_WING_TRAIL_LOCAL_Z},
                    POSTALE_PRESENTATION_SCALE,
                )
                particle_systems.step_wing_trails(
                    &editor.wing_trails,
                    min(delta_seconds, .05),
                    particle_systems.Vec3{left_tip.x, left_tip.y, left_tip.z},
                    particle_systems.Vec3{right_tip.x, right_tip.y, right_tip.z},
                    particle_systems.Vec3 {
                        editor.postale.body.basis.forward.x,
                        editor.postale.body.basis.forward.y,
                        editor.postale.body.basis.forward.z,
                    },
                    particle_systems.Vec3 {
                        editor.postale.body.basis.up.x,
                        editor.postale.body.basis.up.y,
                        editor.postale.body.basis.up.z,
                    },
                    particle_systems.Vec3{editor.atmosphere.weather.wind[0], 0, editor.atmosphere.weather.wind[1]},
                    editor.postale.telemetry.airspeed,
                )
                vehicles.sync_driver(&editor.pilot)
                if rl.IsKeyPressed(.F) && postale_game.can_exit(&editor.postale) {
                    if vehicles.try_exit(&editor.pilot, true) {
                        editor.flight_control = {}
                        editor.player.position = editor.pilot.position
                        editor.player.velocity = {}
                        editor.player.grounded = true
                        editor.camera = third_person.default_camera()
                    }
                }
                chase_camera.step(&editor.flight_camera, postale_camera_target(editor), min(delta_seconds, .05))
                editor.camera_pose = editor.flight_camera.pose
            }
            if in_car {
                if rl.IsKeyPressed(.F) {
                    if vehicles.try_exit(&editor.pilot, true) {
                        editor.player.position = editor.pilot.position
                        editor.player.velocity = {}
                        editor.player.grounded = true
                        editor.camera = third_person.default_camera()
                    }
                } else {
                    throttle, steering := f32(0), f32(0)
                    if rl.IsKeyDown(.W) || rl.IsKeyDown(.UP) do throttle += 1
                    if rl.IsKeyDown(.S) || rl.IsKeyDown(.DOWN) do throttle -= 1
                    if rl.IsKeyDown(.A) || rl.IsKeyDown(.LEFT) do steering -= 1
                    if rl.IsKeyDown(.D) || rl.IsKeyDown(.RIGHT) do steering += 1
                    if rl.GamepadAvailable() {
                        throttle += max(rl.GetGamepadAxis(.Right_Trigger), f32(0))
                        throttle -= max(rl.GetGamepadAxis(.Left_Trigger), f32(0))
                        steering = stronger_axis(steering, shape_flight_axis(rl.GetGamepadAxis(.Left_X)))
                    }
                    ground := terrain.sample_height(&editor.project, 0, editor.car.position.x, editor.car.position.z)
                    handbrake :=
                        rl.IsKeyDown(.SPACE) || (rl.GamepadAvailable() && rl.IsGamepadButtonDown(.Right_Shoulder))
                    vehicles.car_drive_step(
                        &editor.car_drive,
                        &editor.car,
                        {throttle = clamp(throttle, -1, 1), steering = clamp(steering, -1, 1), handbrake = handbrake},
                        ground,
                        min(delta_seconds, .05),
                    )
                    forward_x, forward_z := math.cos(editor.car.yaw_radians), math.sin(editor.car.yaw_radians)
                    right_x, right_z := -forward_z, forward_x
                    contacts := [4]particle_systems.Vehicle_Contact{}
                    wheel_x := [2]f32{-1, 1}
                    wheel_z := [2]f32{-1.12, 1.12}
                    contact_index := 0
                    for x in wheel_x {
                        for z in wheel_z {
                            contact_x := editor.car.position.x + right_x * x - forward_x * z
                            contact_z := editor.car.position.z + right_z * x - forward_z * z
                            contacts[contact_index] = {
                                position = {
                                    x = contact_x,
                                    y = terrain.sample_height(&editor.project, 0, contact_x, contact_z),
                                    z = contact_z,
                                },
                                grounded = true,
                            }
                            contact_index += 1
                        }
                    }
                    particle_systems.step_vehicle_effects(
                        &editor.vehicle_effects,
                        min(delta_seconds, .05),
                        particle_systems.Vec3{editor.car.position.x, editor.car.position.y, editor.car.position.z},
                        editor.car.yaw_radians,
                        vehicles.car_drive_speed(editor.car_drive),
                        editor.car_drive.steering,
                        throttle,
                        handbrake,
                        contacts,
                    )
                    vehicles.sync_driver(&editor.pilot)
                    speed_ratio := clamp(
                        vehicles.car_drive_speed(editor.car_drive) / vehicles.CAR_DRIVE_SEDAN_TUNE.max_forward,
                        0,
                        1,
                    )
                    target_yaw := -math.PI * .5 - editor.car.yaw_radians
                    editor.camera.yaw_radians = vehicles.car_drive_angle_step(
                        editor.camera.yaw_radians,
                        target_yaw,
                        clamp((3.8 + speed_ratio * 2.2) * min(delta_seconds, .05), 0, 1),
                    )
                    editor.camera.pitch_radians = .24
                    editor.camera.distance = 5.2 + speed_ratio * 1.8
                    editor.camera.height = 1.15 + speed_ratio * .32
                    desired_camera := third_person.camera_pose(editor.car.position, editor.camera)
                    editor.camera_pose = third_person.follow_camera(
                        editor.camera_pose,
                        desired_camera,
                        8,
                        min(delta_seconds, .05),
                    )
                }
            }
            // `driving` is the mode captured at the start of this frame. After
            // an exit, defer on-foot input until the next frame so the same F
            // press cannot immediately enter the nearby vehicle again.
            if editor.pilot.mode == .On_Foot && !driving {
                if editor.attendant_dialogue_open {
                    if rl.IsKeyPressed(.Y) {
                        if dialogue.choose(&editor.attendant_dialogue, 0) {
                            editor.postale_visible = false
                            editor.libellula_visible = true
                            editor.libellula_active = true
                            editor.postale.body.position = flight.Vec3 {
                                x = editor.libellula.position.x,
                                y = editor.libellula.position.y,
                                z = editor.libellula.position.z,
                            }
                            editor.postale.vehicle.position = editor.libellula.position
                            editor.player.position = {
                                x = editor.libellula.position.x,
                                y = editor.libellula.position.y,
                                z = editor.libellula.position.z + 3,
                            }
                            editor.pilot.position = editor.player.position
                        }
                        editor.attendant_dialogue_open = false
                    }
                    if rl.IsKeyPressed(.N) {
                        dialogue.choose(&editor.attendant_dialogue, 1)
                        editor.attendant_dialogue_open = false
                    }
                }
                third_person.look(&editor.camera, mouse_delta.x, -mouse_delta.y, .012)
                editor.camera.distance = clamp(editor.camera.distance - rl.GetMouseWheelMove() * .5, 3, 12)
                move_x, move_y := f32(0), f32(0)
                if rl.IsKeyDown(.D) do move_x += 1
                if rl.IsKeyDown(.A) do move_x -= 1
                if rl.IsKeyDown(.W) do move_y += 1
                if rl.IsKeyDown(.S) do move_y -= 1
                ground_height := terrain.sample_height(
                    &editor.project,
                    0,
                    editor.player.position.x,
                    editor.player.position.z,
                )
                input := third_person.Input {
                    move_x             = move_x,
                    move_y             = move_y,
                    jump_pressed       = rl.IsKeyPressed(.SPACE),
                    grounded           = editor.player.position.y <= ground_height + .01,
                    camera_yaw_radians = editor.camera.yaw_radians,
                }
                third_person.step(&editor.player, input, third_person.default_config(), min(delta_seconds, .05))
                ground_height = terrain.sample_height(
                    &editor.project,
                    0,
                    editor.player.position.x,
                    editor.player.position.z,
                )
                if editor.player.position.y <= ground_height {
                    editor.player.position.y = ground_height
                    editor.player.grounded = true
                }
                editor.pilot.position = editor.player.position
                editor.pilot.facing_yaw_radians = editor.player.facing_yaw_radians
                if rl.IsKeyPressed(.F) {
                    if libellula_attendant_near(editor) {
                        open_attendant_dialogue(editor)
                    } else {
                        _, entered := vehicles.try_enter_nearest(
                            &editor.pilot,
                            []^vehicles.Vehicle{&editor.car, &editor.postale.vehicle},
                        )
                        if entered {
                            editor.flight_control = {}
                            if driving_postale(editor) {
                                chase_camera.reset(&editor.flight_camera, postale_camera_target(editor))
                            }
                        }
                    }
                }
                if editor.camera_target_lock {
                    editor.camera_pose = third_person.camera_near(editor.libellula.position, {x = 8, y = 5, z = 8})
                } else {
                    desired_camera := third_person.camera_pose(editor.player.position, editor.camera)
                    editor.camera_pose = third_person.follow_camera(
                        editor.camera_pose,
                        desired_camera,
                        12,
                        min(delta_seconds, .05),
                    )
                }
            }
        }
        if editor.cameras.active != .Player {
            editor.camera_pose = third_person.camera_active_pose(&editor.cameras)
        }
        if !editor.in_map && editor.tool != .Structure && cursor_hit && !ui_hit {
            stroke_strength := editor.strength * min(frame_delta, f32(.05)) * 4
            if rl.IsMouseButtonDown(.LEFT) do terrain.apply_stroke(&editor.project, editor.tool, world_x, world_z, editor.radius, stroke_strength, 1)
            if rl.IsMouseButtonDown(.RIGHT) do terrain.apply_stroke(&editor.project, editor.tool, world_x, world_z, editor.radius, stroke_strength, -1)
        }
        rl.BeginDrawing()
        draw_terrain(editor, width, height, f32(rl.GetTime()))
        rl.EndDrawing()
        capture_frame := capture_flight_mode ? 20 : 2
        if capture_mode && frame == capture_frame do rl.TakeScreenshot(fmt.ctprintf("%s", os.args[2]))
        // Vulkan screenshot readback completes asynchronously; retain several
        // presented frames after the request so capture mode always writes its PNG.
        if capture_mode && frame >= 32 do break
        frame += 1
    }
}
