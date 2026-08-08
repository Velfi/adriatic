package main

import atmosphere "../packages/atmosphere"
import chase_camera "../packages/chase_camera"
import flight "../packages/flight"
import postale_game "../packages/postale"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:strconv"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

LANDFORM_MAZE_CELLS :: 15
LANDFORM_MAZE_GRID :: LANDFORM_MAZE_CELLS * 2 + 1
LANDFORM_MAZE_DEFAULT_SEED :: u32(0x4d415a45)

Landform_Maze_Lab_State :: struct {
    walls:       [LANDFORM_MAZE_GRID * LANDFORM_MAZE_GRID]bool,
    visited:     [LANDFORM_MAZE_CELLS * LANDFORM_MAZE_CELLS]bool,
    seed:        u32,
    cell_size:   f32,
    wall_height: f32,
    flying:      bool,
}

landform_maze_lab: Landform_Maze_Lab_State

landform_maze_hash :: #force_inline proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * 0x7feb352d
    result = (result ~ (result >> 15)) * 0x846ca68b
    return result ~ (result >> 16)
}

landform_maze_index :: #force_inline proc(x, z: int) -> int {
    return z * LANDFORM_MAZE_GRID + x
}

landform_maze_generate :: proc(seed: u32) {
    landform_maze_lab.walls = {}
    landform_maze_lab.visited = {}
    for &wall in landform_maze_lab.walls do wall = true

    stack_x: [LANDFORM_MAZE_CELLS * LANDFORM_MAZE_CELLS]int
    stack_z: [LANDFORM_MAZE_CELLS * LANDFORM_MAZE_CELLS]int
    stack_count := 1
    stack_x[0], stack_z[0] = LANDFORM_MAZE_CELLS / 2, LANDFORM_MAZE_CELLS - 1
    landform_maze_lab.visited[stack_z[0] * LANDFORM_MAZE_CELLS + stack_x[0]] = true
    landform_maze_lab.walls[landform_maze_index(stack_x[0] * 2 + 1, stack_z[0] * 2 + 1)] = false
    random_state := seed

    directions := [4][2]int{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
    for stack_count > 0 {
        x, z := stack_x[stack_count - 1], stack_z[stack_count - 1]
        choices: [4]int
        choice_count := 0
        for direction, index in directions {
            nx, nz := x + direction[0], z + direction[1]
            if nx >= 0 &&
               nx < LANDFORM_MAZE_CELLS &&
               nz >= 0 &&
               nz < LANDFORM_MAZE_CELLS &&
               !landform_maze_lab.visited[nz * LANDFORM_MAZE_CELLS + nx] {
                choices[choice_count] = index
                choice_count += 1
            }
        }
        if choice_count == 0 {
            stack_count -= 1
            continue
        }
        random_state = landform_maze_hash(random_state + u32(stack_count) * 0x9e3779b9)
        direction := directions[choices[int(random_state % u32(choice_count))]]
        nx, nz := x + direction[0], z + direction[1]
        landform_maze_lab.walls[landform_maze_index(x * 2 + 1 + direction[0], z * 2 + 1 + direction[1])] = false
        landform_maze_lab.walls[landform_maze_index(nx * 2 + 1, nz * 2 + 1)] = false
        landform_maze_lab.visited[nz * LANDFORM_MAZE_CELLS + nx] = true
        stack_x[stack_count], stack_z[stack_count] = nx, nz
        stack_count += 1
    }

    // Open opposite edges so the route reads as a journey through the landform.
    entrance_x := (LANDFORM_MAZE_CELLS / 2) * 2 + 1
    landform_maze_lab.walls[landform_maze_index(entrance_x, LANDFORM_MAZE_GRID - 1)] = false
    landform_maze_lab.walls[landform_maze_index(entrance_x, 0)] = false
}

landform_maze_height :: proc(x, z: f32) -> f32 {
    tile_size := landform_maze_lab.cell_size * .5
    extent := f32(LANDFORM_MAZE_GRID) * tile_size * .5
    gx, gz := (x + extent) / tile_size, (z + extent) / tile_size
    ix, iz := int(math.floor(gx)), int(math.floor(gz))
    ground := f32(5) + f32(math.sin(f64(x * .006))) * 1.8 + f32(math.sin(f64(z * .0047))) * 1.3
    if ix < 0 || iz < 0 || ix >= LANDFORM_MAZE_GRID || iz >= LANDFORM_MAZE_GRID do return ground
    if !landform_maze_lab.walls[landform_maze_index(ix, iz)] do return ground

    // Taper only at exposed edges. Adjacent wall tiles share their full height,
    // turning a run of cells into one continuous ridge instead of a row of
    // individually shouldered, crenellated blocks.
    local_x, local_z := gx - f32(ix), gz - f32(iz)
    edge := f32(.5)
    if ix == 0 || !landform_maze_lab.walls[landform_maze_index(ix - 1, iz)] do edge = min(edge, local_x)
    if ix == LANDFORM_MAZE_GRID - 1 || !landform_maze_lab.walls[landform_maze_index(ix + 1, iz)] do edge = min(edge, 1 - local_x)
    if iz == 0 || !landform_maze_lab.walls[landform_maze_index(ix, iz - 1)] do edge = min(edge, local_z)
    if iz == LANDFORM_MAZE_GRID - 1 || !landform_maze_lab.walls[landform_maze_index(ix, iz + 1)] do edge = min(edge, 1 - local_z)
    shoulder := clamp(edge / .18, 0, 1)
    shoulder = shoulder * shoulder * (3 - 2 * shoulder)
    crown := f32(math.sin(f64((x + z) * .021))) * 3.5
    return ground + shoulder * (landform_maze_lab.wall_height + crown)
}

landform_maze_apply_terrain :: proc(editor: ^Editor) {
    editor.project.sea_level = -18
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        level := &editor.project.levels[level_index]
        half_grid := f32(terrain.TERRAIN_RESOLUTION - 1) * .5 * level.cell_size
        level.origin_x, level.origin_z = -half_grid, -half_grid
        for z in 0 ..< terrain.TERRAIN_RESOLUTION {
            world_z := level.origin_z + f32(z) * level.cell_size
            for x in 0 ..< terrain.TERRAIN_RESOLUTION {
                world_x := level.origin_x + f32(x) * level.cell_size
                index := z * terrain.TERRAIN_RESOLUTION + x
                height := landform_maze_height(world_x, world_z)
                level.heights[index] = height
                level.material[index] = clamp((height - 8) / max(landform_maze_lab.wall_height, f32(1)), -1, 1)
            }
        }
    }
    editor.project.road_graph = {}
    editor.project.revision += 1
    world_terrain_invalidate_all(editor)
}

landform_maze_spawn_postale :: proc(editor: ^Editor) -> bool {
    if editor == nil || !lab_scene_is_active(editor, "landform-maze") do return false
    if editor.pilot.mode == .Driving do _ = vehicles.try_exit(&editor.pilot, true)
    if !vehicles.aircraft_fleet_unlock(&editor.aircraft, .Postale) ||
       !vehicles.aircraft_fleet_switch(&editor.aircraft, .Postale) {
        return false
    }

    tile_size := landform_maze_lab.cell_size * .5
    extent := f32(LANDFORM_MAZE_GRID) * tile_size * .5
    spawn := flight.Vec3{0, 24, extent + landform_maze_lab.cell_size * 1.6}
    orientation := flight.orientation_from_basis({forward = {0, 0, -1}, up = {0, 1, 0}, right = {1, 0, 0}})
    postale_game.reset(&editor.postale, 0)
    editor.postale.spawn_position = spawn
    editor.postale.spawn_orientation = orientation
    editor.postale.body.position = spawn
    editor.postale.body.orientation = orientation
    editor.postale.body.velocity = {0, 0, -42}
    editor.postale.vehicle.position = spawn
    editor.postale.vehicle.yaw_radians = 0
    editor.postale.vehicle.locked = false
    editor.postale.grounded = false
    editor.postale.was_grounded = false
    editor.postale.throttle = .7
    editor.postale_visible, editor.libellula_visible, editor.rondine_visible = true, false, false
    editor.pilot.mode = .Driving
    editor.pilot.vehicle = &editor.postale.vehicle
    editor.postale.vehicle.driver = &editor.pilot
    vehicles.sync_driver(&editor.pilot)
    editor.in_map = true
    editor.capture_world_only = false
    editor.aircraft_fixed_accumulator = 0
    editor.aircraft_previous_body_valid = false
    editor.map_time = f32(canvas2d.GetTime())
    chase_camera.reset(&editor.flight_camera, aircraft_camera_target(editor))
    editor.camera_pose = editor.flight_camera.pose
    third_person.camera_set_pose(&editor.cameras, .Player, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Player)
    landform_maze_lab.flying = true
    set_pointer_locked(true)
    _ = sdl.HideCursor()
    return true
}

landform_maze_show_overview :: proc(editor: ^Editor) {
    if editor.pilot.mode == .Driving do _ = vehicles.try_exit(&editor.pilot, true)
    editor.postale_visible = false
    editor.in_map = false
    editor.capture_world_only = true
    landform_maze_lab.flying = false
    extent := f32(LANDFORM_MAZE_GRID) * landform_maze_lab.cell_size * .25
    editor.camera_pose = third_person.camera_look_at({extent * .9, extent * 1.35, extent * 1.05}, {0, 20, 0})
    editor.editor_focus = {0, 20, 0}
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
}

landform_maze_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    auto_fly := target == "flight"
    seed := LANDFORM_MAZE_DEFAULT_SEED
    if !auto_fly {
        if parsed, ok := strconv.parse_int(target); ok && parsed >= 0 && parsed <= 0xffffffff do seed = u32(parsed)
    }
    // A fixed-wing maze needs room for a banked 90-degree turn. Only part of
    // each pitch is open corridor, so use generous spacing while leaving the
    // ordinary Postale handling untouched.
    landform_maze_lab = {
        seed        = seed,
        cell_size   = 256,
        wall_height = 86,
    }
    landform_maze_generate(seed)
    landform_maze_apply_terrain(editor)
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 20)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    editor.libellula_visible, editor.rondine_visible = false, false
    landform_maze_show_overview(editor)
    if auto_fly do return landform_maze_spawn_postale(editor)
    return true
}

landform_maze_lab_process_input :: proc(editor: ^Editor) {
    if canvas2d.IsKeyPressed(.ENTER) {
        if landform_maze_lab.flying do landform_maze_show_overview(editor)
        else do _ = landform_maze_spawn_postale(editor)
        return
    }
    if canvas2d.IsKeyPressed(.R) && landform_maze_lab.flying {
        _ = landform_maze_spawn_postale(editor)
        return
    }
    if landform_maze_lab.flying do return
    changed := false
    if canvas2d.IsKeyPressed(.N) {
        landform_maze_lab.seed = landform_maze_hash(landform_maze_lab.seed + 0x9e3779b9)
        landform_maze_generate(landform_maze_lab.seed)
        changed = true
    }
    if canvas2d.IsKeyPressed(.ONE) {
        landform_maze_lab.wall_height = max(f32(40), landform_maze_lab.wall_height - 8)
        changed = true
    }
    if canvas2d.IsKeyPressed(.TWO) {
        landform_maze_lab.wall_height = min(f32(160), landform_maze_lab.wall_height + 8)
        changed = true
    }
    if canvas2d.IsKeyPressed(.THREE) {
        landform_maze_lab.cell_size = max(f32(128), landform_maze_lab.cell_size - 32)
        changed = true
    }
    if canvas2d.IsKeyPressed(.FOUR) {
        landform_maze_lab.cell_size = min(f32(384), landform_maze_lab.cell_size + 32)
        changed = true
    }
    if changed {
        landform_maze_apply_terrain(editor)
        landform_maze_show_overview(editor)
    }
}

landform_maze_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel := canvas2d.Rectangle{24, f32(height) - 132, 390, 100}
    canvas2d.DrawRectangleRec(panel, {15, 22, 20, 224})
    canvas2d.DrawTextEx(canvas2d.Font{}, "LANDFORM MAZE", {panel.x + 16, panel.y + 13}, 18, 1, {230, 221, 184, 255})
    if landform_maze_lab.flying {
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            "ENTER TO EDIT  •  R TO RESTART",
            {panel.x + 16, panel.y + 48},
            15,
            1,
            {205, 215, 197, 255},
        )
    } else {
        canvas2d.DrawTextEx(canvas2d.Font{}, "ENTER TO FLY", {panel.x + 16, panel.y + 43}, 16, 1, {205, 215, 197, 255})
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            fmt.ctprintf(
                "SEED %08X  •  RIDGES %.0f M  •  CORRIDORS %.0f M",
                landform_maze_lab.seed,
                landform_maze_lab.wall_height,
                landform_maze_lab.cell_size,
            ),
            {panel.x + 16, panel.y + 69},
            13,
            1,
            {151, 177, 157, 255},
        )
    }
    _ = width
}

landform_maze_lab_exit :: proc(editor: ^Editor) {
    if editor != nil && editor.pilot.mode == .Driving do _ = vehicles.try_exit(&editor.pilot, true)
    landform_maze_lab.flying = false
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
}
