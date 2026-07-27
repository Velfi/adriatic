package main

import cinematic "../packages/cinematic"
import third_person "../packages/third_person"
import "core:math"
import rl "zelda_engine:canvas2d"

cinematic_play :: proc(editor: ^Editor, script: ^cinematic.Script) -> bool {
    if editor == nil do return false
    return cinematic.play(&editor.cinematic_playback, script)
}

cinematic_stop :: proc(editor: ^Editor) {
    if editor == nil do return
    cinematic.stop(&editor.cinematic_playback)
}

cinematic_is_playing :: proc(editor: ^Editor) -> bool {
    return editor != nil && editor.cinematic_playback.playing
}

story_meeting_cinematic_play :: proc(editor: ^Editor) -> bool {
    if editor == nil || editor.story_state.romance != .Meeting do return false
    niko, iva, center, rotation, found := world_story_meeting_pose(editor)
    if !found do return false

    side := third_person.Vec3 {
        math.cos(rotation),
        0,
        math.sin(rotation),
    }
    outward := third_person.Vec3 {
        -math.sin(rotation),
        0,
        math.cos(rotation),
    }
    target := third_person.Vec3 {
        (niko.x + iva.x) * .5,
        max(niko.y, iva.y) + .72,
        (niko.z + iva.z) * .5,
    }
    wide := third_person.Vec3 {
        center.x + outward.x * 2.85 + side.x * 1.25,
        center.y + 1.85,
        center.z + outward.z * 2.85 + side.z * 1.25,
    }
    close := third_person.Vec3 {
        center.x + outward.x * 2.15 - side.x * .72,
        center.y + 1.48,
        center.z + outward.z * 2.15 - side.z * .72,
    }
    current := cinematic.camera(
        {editor.camera_pose.position.x, editor.camera_pose.position.y, editor.camera_pose.position.z},
        {editor.camera_pose.target.x, editor.camera_pose.target.y, editor.camera_pose.target.z},
        1.35,
    )
    wide_camera := cinematic.camera({wide.x, wide.y, wide.z}, {target.x, target.y, target.z}, 1.45)
    close_camera := cinematic.camera({close.x, close.y, close.z}, {target.x, target.y, target.z}, 1.62)
    editor.story_cinematic_shots = {
        cinematic.move("meeting-arrival", 1.35, current, wide_camera, .Smoother),
        cinematic.hold("meeting-awning", 1.25, wide_camera),
        cinematic.move("meeting-pair", 1.35, wide_camera, close_camera, .Smoother),
    }
    editor.story_cinematic_script = {
        id    = "blue-awning-meeting",
        shots = editor.story_cinematic_shots[:],
    }
    editor.story_cinematic_restore_pose = editor.camera_pose
    editor.story_cinematic_active = true
    return cinematic_play(editor, &editor.story_cinematic_script)
}

cinematic_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || editor.cinematic_playback.script == nil do return
    cinematic.step(&editor.cinematic_playback, delta_seconds)
    value := cinematic.sample(&editor.cinematic_playback)
    editor.cinematic_focal_length = value.camera.focal_length
    editor.camera_pose = third_person.Camera_Pose {
        position = {value.camera.position[0], value.camera.position[1], value.camera.position[2]},
        target = {value.camera.target[0], value.camera.target[1], value.camera.target[2]},
    }
    if editor.story_cinematic_active && editor.cinematic_playback.completed {
        editor.camera_pose = editor.story_cinematic_restore_pose
        editor.cinematic_playback.script = nil
        editor.story_cinematic_active = false
    }
}

cinematic_wipe_coverage :: proc(progress: f32) -> f32 {
    p := clamp(progress, 0, 1)
    return p <= .5 ? p * 2 : (1 - p) * 2
}

cinematic_wipe_color :: proc(value: cinematic.Wipe) -> rl.Color {
    return {value.color[0], value.color[1], value.color[2], value.color[3]}
}

cinematic_draw_clock :: proc(width, height: i32, coverage: f32, color: rl.Color) {
    if coverage <= 0 do return
    center := rl.Vector2{f32(width) * .5, f32(height) * .5}
    radius := f32(math.sqrt(f64(width * width + height * height))) * .55
    segments := 72
    drawn := int(math.ceil(f64(coverage * f32(segments))))
    thickness := radius * f32(2 * math.PI) / f32(segments) + 2
    for index in 0 ..< drawn {
        angle := -math.PI * .5 + f32(index) * 2 * math.PI / f32(segments)
        edge := rl.Vector2 {
            center.x + radius * f32(math.cos(f64(angle))),
            center.y + radius * f32(math.sin(f64(angle))),
        }
        rl.DrawLineEx(center, edge, thickness, color)
    }
}

cinematic_draw_wipe :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil || editor.cinematic_playback.script == nil do return
    value := cinematic.sample(&editor.cinematic_playback)
    if value.wipe.kind == .None do return
    coverage := cinematic_wipe_coverage(value.wipe_progress)
    if coverage <= 0 do return
    color := cinematic_wipe_color(value.wipe)
    w, h := f32(width), f32(height)

    switch value.wipe.kind {
    case .None:
    case .Left:
        rl.DrawRectangleRec({0, 0, w * coverage, h}, color)
    case .Right:
        amount := w * coverage
        rl.DrawRectangleRec({w - amount, 0, amount, h}, color)
    case .Up:
        rl.DrawRectangleRec({0, h * (1 - coverage), w, h * coverage}, color)
    case .Down:
        rl.DrawRectangleRec({0, 0, w, h * coverage}, color)
    case .Iris:
        radius := f32(math.sqrt(f64(width * width + height * height))) * .55 * coverage
        rl.DrawCircleV({w * .5, h * .5}, radius, color)
    case .Clockwise:
        cinematic_draw_clock(width, height, coverage, color)
    case .Blinds:
        blind_count := 12
        blind_height := h / f32(blind_count)
        for index in 0 ..< blind_count {
            y := f32(index) * blind_height
            rl.DrawRectangleRec({0, y, w * coverage, blind_height + 1}, color)
        }
    case .Checker:
        columns, rows := 12, 8
        cell_width, cell_height := w / f32(columns), h / f32(rows)
        threshold := coverage * 2
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                phase := f32((row + column) & 1)
                cell_coverage := clamp(threshold - phase, 0, 1)
                if cell_coverage <= 0 do continue
                x, y := f32(column) * cell_width, f32(row) * cell_height
                rl.DrawRectangleRec({x, y, cell_width * cell_coverage + 1, cell_height + 1}, color)
            }
        }
    }
}
