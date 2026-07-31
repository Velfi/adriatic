package main

import atmosphere "../packages/atmosphere"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

rainbow_lab_minutes: f32
rainbow_lab_rain: f32

rainbow_lab_apply_weather :: proc(editor: ^Editor) {
    atmosphere.set_world_minutes(&editor.atmosphere, rainbow_lab_minutes)
    atmosphere.set_weather_override(&editor.atmosphere, .Storm)
    editor.atmosphere.weather = atmosphere.weather_for(.Storm)
    // A sun shower needs falling rain without the fully closed cloud deck of
    // the storm preset. The sky shader still decides visibility from these
    // physical inputs rather than from a lab-only rainbow switch.
    editor.atmosphere.weather.precipitation = rainbow_lab_rain
    editor.atmosphere.weather.cloud_cover = .28 + rainbow_lab_rain * .34
    editor.atmosphere.weather.haze = .10 + rainbow_lab_rain * .20
    editor.atmosphere.weather.severity = .08 + rainbow_lab_rain * .25
    editor.atmosphere.paused = true
}

rainbow_lab_apply_camera :: proc(editor: ^Editor) {
    sky := atmosphere_sky(editor)
    eye := third_person.Vec3{0, 7, 0}
    // Face away from the Sun: the bow is a cone around this antisolar axis.
    target := third_person.Vec3 {
        eye.x - sky.sun_direction[0] * 120,
        eye.y - sky.sun_direction[1] * 22 + 18,
        eye.z - sky.sun_direction[2] * 120,
    }
    editor.camera_pose = third_person.camera_look_at(eye, target)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
}

rainbow_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    rainbow_lab_minutes = 17 * 60 + 20
    rainbow_lab_rain = .68
    switch target {
    case "", "shower":
    case "dry":
        rainbow_lab_rain = 0
    case "double":
        rainbow_lab_rain = .94
    case:
        return false
    }
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.project.sea_level = 0
    rainbow_lab_apply_weather(editor)
    rainbow_lab_apply_camera(editor)
    set_pointer_locked(false)
    return true
}

rainbow_lab_process_input :: proc(editor: ^Editor) {
    changed_light := false
    if canvas2d.IsKeyPressed(.LEFT) {
        rainbow_lab_minutes = max(rainbow_lab_minutes - 20, f32(6 * 60))
        changed_light = true
    }
    if canvas2d.IsKeyPressed(.RIGHT) {
        rainbow_lab_minutes = min(rainbow_lab_minutes + 20, f32(19 * 60))
        changed_light = true
    }
    if canvas2d.IsKeyPressed(.DOWN) do rainbow_lab_rain = max(rainbow_lab_rain - .1, f32(0))
    if canvas2d.IsKeyPressed(.UP) do rainbow_lab_rain = min(rainbow_lab_rain + .1, f32(1))
    if canvas2d.IsKeyPressed(.ONE) do rainbow_lab_rain = 0
    if canvas2d.IsKeyPressed(.TWO) do rainbow_lab_rain = .68
    if canvas2d.IsKeyPressed(.THREE) do rainbow_lab_rain = .94
    rainbow_lab_apply_weather(editor)
    if changed_light do rainbow_lab_apply_camera(editor)
}

world_rainbow_lab :: proc(_: ^Editor) {
    // An uncluttered wet horizon makes the sky phenomenon and its dependence
    // on solar elevation easy to judge.
    water := canvas2d.Color{52, 106, 124, 235}
    world_water_quad({-900, 0, -900}, {-900, 0, 900}, {900, 0, 900}, {900, 0, -900}, water)
}

rainbow_lab_draw_ui :: proc(editor: ^Editor, width, height: i32) {
    sky := atmosphere_sky(editor)
    sun_degrees := f32(math.asin(f64(clamp(sky.sun_direction[1], f32(-1), f32(1)))) * 180 / math.PI)
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 460,
        height = 136,
    }
    canvas2d.DrawRectangleRounded(panel, .10, 8, {10, 24, 34, 228})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {112, 170, 184, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "LIGHT + RAIN / RAINBOW LAB", {38, 38}, 19, 1, {244, 238, 198, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        fmt.ctprintf("SUN %.0f°   RAIN %.0f%%   PRIMARY 42°", sun_degrees, rainbow_lab_rain * 100),
        {38, 72},
        14,
        1,
        {203, 235, 237, 255},
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, "LEFT / RIGHT LIGHT    UP / DOWN RAIN", {38, 101}, 13, 1, {171, 202, 211, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "1 DRY    2 SHOWER    3 DOUBLE BOW", {38, 123}, 13, 1, {171, 202, 211, 255})
    _ = width
    _ = height
}
