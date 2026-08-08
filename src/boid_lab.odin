package main

import atmosphere "../packages/atmosphere"
import flocks "../packages/flocks"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

boid_lab_system: flocks.System
boid_lab_paused: bool
boid_lab_show_vectors: bool
boid_lab_wind_index: int
boid_lab_last_time: f32
boid_lab_mode: int
boid_lab_follow: bool
boid_lab_follow_index: int

BOID_LAB_WINDS := [3][2]f32{{0, 0}, {4, -1.5}, {10, 3}}
BOID_LAB_WIND_NAMES := [3]string{"CALM", "BREEZE", "STRONG"}

boid_lab_reset :: proc() {
    boid_lab_system = {}
    anchors: [flocks.MAX_FLOCKS]flocks.Anchor
    count := 0
    if boid_lab_mode == 3 {
        columns := 34
        for index in 0 ..< flocks.MAX_FLOCKS {
            column := index % columns
            row := index / columns
            anchors[count] = {
                position = {(f32(column) - 16.5) * 10, 0, (f32(row) - 16) * 10},
                kind     = index & 1 == 0 ? .Harbor : .Fishing,
                seed     = 0x10b01d00 + u32(index),
            }
            count += 1
        }
    } else if boid_lab_mode != 2 && boid_lab_mode != 4 {
        anchors[count] = {
            position = {-18, 0, 0},
            kind     = .Harbor,
            seed     = 0x48415242,
        }
        count += 1
    }
    if boid_lab_mode != 1 && boid_lab_mode != 3 && boid_lab_mode != 4 {
        anchors[count] = {
            position = {18, 0, 0},
            kind     = .Fishing,
            seed     = 0x46495348,
        }
        count += 1
    }
    flocks.sync_anchors(&boid_lab_system, anchors[:count])
    if boid_lab_mode == 3 do boid_lab_system.boid_count = flocks.STRESS_BOID_COUNT
    // Let the flock settle before its first rendered frame.
    for _ in 0 ..< 180 {
        flocks.step(&boid_lab_system, 1.0 / 60.0, BOID_LAB_WINDS[boid_lab_wind_index])
    }
}

boid_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    boid_lab_mode = 0
    switch target {
    case "", "both", "follow":
    case "harbor":
        boid_lab_mode = 1
    case "fishing":
        boid_lab_mode = 2
    case "stress-10k":
        boid_lab_mode = 3
    case "stress-0":
        boid_lab_mode = 4
    case:
        return false
    }
    boid_lab_paused = false
    boid_lab_show_vectors = false
    boid_lab_wind_index = 1
    boid_lab_follow = false
    boid_lab_follow_index = 0
    boid_lab_last_time = editor.map_time
    boid_lab_reset()
    if target == "follow" do boid_lab_follow = true

    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.project.sea_level = 0
    atmosphere.set_world_minutes(&editor.atmosphere, 8 * 60 + 20)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    set_pointer_locked(false)
    editor.camera_pose = third_person.camera_look_at({54, 35, 58}, {0, 11, 0})
    if boid_lab_mode == 3 || boid_lab_mode == 4 {
        editor.camera_pose = third_person.camera_look_at({230, 190, 260}, {0, 13, 0})
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    return true
}

boid_lab_set_overview_camera :: proc(editor: ^Editor) {
    editor.camera_pose = third_person.camera_look_at({54, 35, 58}, {0, 11, 0})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
}

boid_lab_process_input :: proc(editor: ^Editor) {
    if canvas2d.IsKeyPressed(.SPACE) do boid_lab_paused = !boid_lab_paused
    if canvas2d.IsKeyPressed(.R) do boid_lab_reset()
    if canvas2d.IsKeyPressed(.V) do boid_lab_show_vectors = !boid_lab_show_vectors
    if canvas2d.IsKeyPressed(.W) {
        boid_lab_wind_index = (boid_lab_wind_index + 1) % len(BOID_LAB_WINDS)
    }
    if canvas2d.IsKeyPressed(.C) {
        boid_lab_follow = !boid_lab_follow
        if !boid_lab_follow do boid_lab_set_overview_camera(editor)
    }
    if canvas2d.IsKeyPressed(.N) && boid_lab_system.boid_count > 0 {
        boid_lab_follow_index = (boid_lab_follow_index + 1) % boid_lab_system.boid_count
        boid_lab_follow = true
    }
    if canvas2d.IsKeyPressed(.ONE) {
        boid_lab_mode = 1
        boid_lab_reset()
    }
    if canvas2d.IsKeyPressed(.TWO) {
        boid_lab_mode = 2
        boid_lab_reset()
    }
    if canvas2d.IsKeyPressed(.THREE) {
        boid_lab_mode = 0
        boid_lab_reset()
    }
}

boid_lab_update_camera :: proc(editor: ^Editor) {
    if !boid_lab_follow || boid_lab_system.boid_count <= 0 do return
    boid_lab_follow_index = clamp(boid_lab_follow_index, 0, boid_lab_system.boid_count - 1)
    boid := boid_lab_system.boids[boid_lab_follow_index]
    forward := third_person.Vec3{boid.velocity.x, 0, boid.velocity.z}
    speed := f32(math.sqrt(f64(forward.x * forward.x + forward.z * forward.z)))
    if speed <= .01 {
        forward = {0, 0, 1}
    } else {
        forward /= speed
    }
    focus := third_person.Vec3{boid.position.x, boid.position.y, boid.position.z}
    camera_right := third_person.Vec3{-forward.z, 0, forward.x}
    eye := focus - forward * 5.5 + camera_right * 1.8 + third_person.Vec3{0, 2.4, 0}
    editor.camera_pose = third_person.camera_look_at(eye, focus + forward * 1.7)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
}

world_boid_lab_water :: proc() {
    extent := f32(90)
    color := canvas2d.Color{38, 99, 127, 255}
    world_water_quad({-extent, 0, -extent}, {-extent, 0, extent}, {extent, 0, extent}, {extent, 0, -extent}, color)
}

world_boid_lab_anchor :: proc(anchor: flocks.Anchor) {
    base := third_person.Vec3{anchor.position.x, .12, anchor.position.z}
    color := anchor.kind == .Harbor ? canvas2d.Color{238, 183, 91, 255} : canvas2d.Color{91, 220, 205, 255}
    world_tube_between(base, base + third_person.Vec3{0, .55, 0}, {0, 0, 1}, 2.2, 1.7, color)
    for segment in 0 ..< 32 {
        a := f32(segment) / 32 * math.PI * 2
        b := f32(segment + 1) / 32 * math.PI * 2
        first := base + third_person.Vec3{math.cos(a) * 18, .06, math.sin(a) * 18}
        second := base + third_person.Vec3{math.cos(b) * 18, .06, math.sin(b) * 18}
        world_tube_between(first, second, {0, 1, 0}, .035, .035, color)
    }
}

world_boid_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    now := editor.map_time
    dt := clamp(now - boid_lab_last_time, f32(0), f32(.05))
    boid_lab_last_time = now
    if !boid_lab_paused {
        flocks.step(&boid_lab_system, dt, BOID_LAB_WINDS[boid_lab_wind_index])
    }
    boid_lab_update_camera(editor)

    world_boid_lab_water()
    for anchor in boid_lab_system.anchors[:boid_lab_system.anchor_count] do world_boid_lab_anchor(anchor)
    for boid, index in boid_lab_system.boids[:boid_lab_system.boid_count] {
        world_bird(boid.position, boid.velocity, editor.map_time * 8 + f32(index) * .73)
        if boid_lab_show_vectors {
            start := third_person.Vec3{boid.position.x, boid.position.y, boid.position.z}
            velocity := third_person.Vec3{boid.velocity.x, boid.velocity.y, boid.velocity.z}
            world_tube_between(start, start + velocity * .32, {0, 1, 0}, .025, .012, {244, 102, 86, 255})
        }
    }
}

boid_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 490,
        height = 181,
    }
    canvas2d.DrawRectangleRounded(panel, .10, 8, {10, 27, 37, 226})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {104, 168, 184, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "BOID FLOCK LAB", {38, 38}, 20, 1, {245, 238, 197, 255})
    status := fmt.ctprintf(
        "%d BIRDS   %d FLOCKS   WIND %s%s",
        boid_lab_system.boid_count,
        boid_lab_system.anchor_count,
        BOID_LAB_WIND_NAMES[boid_lab_wind_index],
        boid_lab_paused ? "   PAUSED" : boid_lab_follow ? "   FOLLOW" : "",
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, status, {38, 72}, 14, 1, {208, 239, 240, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "1 harbor   2 fishing   3 both   W wind",
        {38, 103},
        13,
        1,
        {171, 201, 207, 255},
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "SPACE pause   R reset   V velocity vectors",
        {38, 127},
        13,
        1,
        {171, 201, 207, 255},
    )
    camera_status := fmt.ctprintf("C follow / overview   N next boid   tracking %d", boid_lab_follow_index + 1)
    canvas2d.DrawTextEx(canvas2d.Font{}, camera_status, {38, 151}, 13, 1, {171, 201, 207, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "Gold: harbor anchor   Cyan: fishing anchor",
        {38, 175},
        12,
        1,
        {214, 192, 139, 255},
    )
    _ = width
    _ = height
}
