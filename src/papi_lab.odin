package main

import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

PAPI_LAB_RUNWAY_HALF_LENGTH :: f32(120)
PAPI_LAB_RUNWAY_HALF_WIDTH :: f32(10)
PAPI_LAB_APPROACH_DISTANCE :: f32(28)

papi_lab_glide_angle: f32
papi_lab_time_minutes: f32
papi_lab_active_slider: int

papi_lab_angle_slider_bounds :: proc() -> rl.Rectangle {
    return {x = 38, y = 118, width = 380, height = 8}
}

papi_lab_time_slider_bounds :: proc() -> rl.Rectangle {
    return {x = 38, y = 183, width = 380, height = 8}
}

papi_lab_white_count :: proc(angle: f32) -> int {
    if angle >= 3.50 do return 4
    if angle >= 3.20 do return 3
    if angle >= 2.80 do return 2
    if angle >= 2.50 do return 1
    return 0
}

papi_lab_state_name :: proc(white_count: int) -> string {
    switch white_count {
    case 4:
        return "TOO HIGH"
    case 3:
        return "SLIGHTLY HIGH"
    case 2:
        return "ON GLIDE PATH"
    case 1:
        return "SLIGHTLY LOW"
    case 0:
        return "TOO LOW"
    }
    return ""
}

papi_lab_apply_camera :: proc(editor: ^Editor) {
    papi_x := -PAPI_LAB_RUNWAY_HALF_LENGTH + 45
    height := f32(math.tan(f64(papi_lab_glide_angle) * math.PI / 180)) * PAPI_LAB_APPROACH_DISTANCE
    eye := third_person.Vec3{papi_x - PAPI_LAB_APPROACH_DISTANCE, height + .08, 0}
    editor.camera_pose = third_person.camera_look_at(eye, {papi_x + 12, .45, 12})
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

papi_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    papi_lab_glide_angle = 3
    papi_lab_time_minutes = 18 * 60 + 20
    papi_lab_active_slider = 0
    switch target {
    case "low":
        papi_lab_glide_angle = 2.35
    case "slightly-low":
        papi_lab_glide_angle = 2.65
    case "", "on":
        papi_lab_glide_angle = 3
    case "slightly-high":
        papi_lab_glide_angle = 3.35
    case "high":
        papi_lab_glide_angle = 3.65
    case:
        return false
    }

    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.project.sea_level = -8
    atmosphere.set_world_minutes(&editor.atmosphere, papi_lab_time_minutes)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    set_pointer_locked(false)
    papi_lab_apply_camera(editor)
    return true
}

papi_lab_process_input :: proc(editor: ^Editor) {
    angle_track := papi_lab_angle_slider_bounds()
    time_track := papi_lab_time_slider_bounds()
    mouse := rl.GetMousePosition()
    if rl.IsMouseButtonPressed(.LEFT) {
        angle_hit := rl.Rectangle {
            x      = angle_track.x - 8,
            y      = angle_track.y - 14,
            width  = angle_track.width + 16,
            height = 36,
        }
        time_hit := rl.Rectangle {
            x      = time_track.x - 8,
            y      = time_track.y - 14,
            width  = time_track.width + 16,
            height = 36,
        }
        if rl.CheckCollisionPointRec(mouse, angle_hit) {
            papi_lab_active_slider = 1
        } else if rl.CheckCollisionPointRec(mouse, time_hit) {
            papi_lab_active_slider = 2
        }
    }
    if !rl.IsMouseButtonDown(.LEFT) do papi_lab_active_slider = 0
    switch papi_lab_active_slider {
    case 1:
        normalized := clamp((mouse.x - angle_track.x) / angle_track.width, 0, 1)
        next_angle := 2 + normalized * 2.25
        if next_angle != papi_lab_glide_angle {
            papi_lab_glide_angle = next_angle
            papi_lab_apply_camera(editor)
        }
    case 2:
        normalized := clamp((mouse.x - time_track.x) / time_track.width, 0, 1)
        next_minutes := normalized * (24 * 60 - 1)
        if next_minutes != papi_lab_time_minutes {
            papi_lab_time_minutes = next_minutes
            atmosphere.set_world_minutes(&editor.atmosphere, papi_lab_time_minutes)
        }
    }
}

world_papi_lab :: proc(editor: ^Editor) {
    if editor == nil do return
    runway_y := f32(.08)
    world_box({0, -.08, 0}, {620, .16, 180}, {75, 104, 73, 255})
    world_box(
        {0, runway_y * .5, 0},
        {PAPI_LAB_RUNWAY_HALF_LENGTH * 2, runway_y, PAPI_LAB_RUNWAY_HALF_WIDTH * 2},
        {54, 58, 60, 255},
    )
    for marker in -4 ..= 4 {
        world_box({f32(marker) * 22, runway_y + .02, 0}, {9, .025, .28}, {235, 231, 207, 255})
    }
    world_runway_papi(editor, 0, 0, runway_y, PAPI_LAB_RUNWAY_HALF_LENGTH, PAPI_LAB_RUNWAY_HALF_WIDTH, -1)
}

papi_lab_draw_ui :: proc(_: ^Editor, width, height: i32) {
    whites := papi_lab_white_count(papi_lab_glide_angle)
    reds := 4 - whites
    panel := rl.Rectangle {
        x      = 22,
        y      = 22,
        width  = 430,
        height = 204,
    }
    rl.DrawRectangleRounded(panel, .10, 8, {10, 24, 31, 230})
    rl.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {118, 169, 169, 255})
    rl.DrawTextEx(rl.Font{}, "PAPI APPROACH LIGHT LAB", {38, 38}, 19, 1, {245, 239, 192, 255})
    rl.DrawTextEx(
        rl.Font{},
        fmt.ctprintf(
            "%.2f DEG   %d WHITE / %d RED   %s",
            papi_lab_glide_angle,
            whites,
            reds,
            papi_lab_state_name(whites),
        ),
        {38, 72},
        14,
        1,
        whites == 2 ? rl.Color{158, 244, 190, 255} : rl.Color{246, 197, 134, 255},
    )
    angle_track := papi_lab_angle_slider_bounds()
    angle_normalized := (papi_lab_glide_angle - 2) / 2.25
    rl.DrawRectangleRounded(angle_track, 1, 4, {61, 83, 88, 255})
    rl.DrawRectangleRounded(
        {angle_track.x, angle_track.y, angle_track.width * angle_normalized, angle_track.height},
        1,
        4,
        {102, 206, 205, 255},
    )
    rl.DrawCircleV(
        {angle_track.x + angle_track.width * angle_normalized, angle_track.y + angle_track.height * .5},
        8,
        {235, 239, 217, 255},
    )
    rl.DrawTextEx(rl.Font{}, "2.00 DEG", {38, 132}, 10, 1, {169, 201, 201, 255})
    rl.DrawTextEx(rl.Font{}, "DRAG TO TEST GLIDE ANGLE", {152, 132}, 10, 1, {205, 235, 235, 255})
    rl.DrawTextEx(rl.Font{}, "4.25 DEG", {365, 132}, 10, 1, {169, 201, 201, 255})

    total_minutes := int(papi_lab_time_minutes)
    hour := total_minutes / 60
    minute := total_minutes % 60
    rl.DrawTextEx(
        rl.Font{},
        fmt.ctprintf("TIME OF DAY   %02d:%02d", hour, minute),
        {38, 157},
        12,
        1,
        {205, 235, 235, 255},
    )
    time_track := papi_lab_time_slider_bounds()
    time_normalized := papi_lab_time_minutes / (24 * 60 - 1)
    rl.DrawRectangleRounded(time_track, 1, 4, {61, 83, 88, 255})
    rl.DrawRectangleRounded(
        {time_track.x, time_track.y, time_track.width * time_normalized, time_track.height},
        1,
        4,
        {231, 174, 91, 255},
    )
    rl.DrawCircleV(
        {time_track.x + time_track.width * time_normalized, time_track.y + time_track.height * .5},
        8,
        {235, 239, 217, 255},
    )
    rl.DrawTextEx(rl.Font{}, "00:00", {38, 197}, 10, 1, {169, 201, 201, 255})
    rl.DrawTextEx(rl.Font{}, "DRAG TO TEST LIGHTING", {161, 197}, 10, 1, {205, 235, 235, 255})
    rl.DrawTextEx(rl.Font{}, "23:59", {382, 197}, 10, 1, {169, 201, 201, 255})
    _ = width
    _ = height
}
