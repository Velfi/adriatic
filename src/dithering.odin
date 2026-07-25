package main

import "core:math"
import "core:mem"
import rl "zelda_engine:canvas2d"
import render2d "zelda_engine:render2d"
import dither "../packages/dither"
import third_person "../packages/third_person"

Dither_Mode :: dither.Mode
dither_mode_label :: dither.mode_label
dither_adjust_mode :: dither.adjust_mode
dither_next_mode :: dither.next_mode
dither_wrap_angle :: dither.wrap_angle
dither_pattern_offset :: dither.pattern_offset
dither_pixel_phase_delta :: dither.pixel_phase_delta
dither_wrap_pixel_phase :: dither.wrap_pixel_phase

Dither_State :: struct {
    initialized:            bool,
    previous_mode:          Dither_Mode,
    previous_customization: bool,
    previous_yaw:           f32,
    previous_pitch:         f32,
    horizontal_phase:       f32,
    vertical_phase:         f32,
    previous_position:      third_person.Vec3,
}

dither_reset :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.dither_state = {}
}

dither_apply :: proc(editor: ^Editor) {
    if editor == nil do return
    dither_reset(editor)
    rl.SetWorldPostProcessEnabled(editor.gameplay_options.dither_mode != .Off)
}

dither_camera_angles :: proc(pose: third_person.Camera_Pose) -> (yaw, pitch: f32) {
    forward := vec_normalize(vec_sub(pose.target, pose.position))
    yaw = math.atan2(-forward.x, -forward.z)
    pitch = math.asin(clamp(forward.y, f32(-1), f32(1)))
    return
}

dither_position_cut :: proc(a, b: third_person.Vec3) -> bool {
    delta := vec_sub(a, b)
    return vec_dot(delta, delta) > 400
}

dither_update_tracking :: proc(
    editor: ^Editor,
    pose: third_person.Camera_Pose,
    mode: Dither_Mode,
    field_of_view: f32,
    viewport_width, viewport_height: int,
) {
    state := &editor.dither_state
    customization := editor.pause_screen == .Customization
    yaw, pitch := dither_camera_angles(pose)
    yaw_delta := dither_wrap_angle(yaw - state.previous_yaw)
    pitch_delta := pitch - state.previous_pitch
    camera_cut :=
        !state.initialized ||
        state.previous_mode != mode ||
        state.previous_customization != customization ||
        dither_position_cut(pose.position, state.previous_position) ||
        math.abs(yaw_delta) > 1 ||
        math.abs(pitch_delta) > .75
    if camera_cut {
        state.horizontal_phase = 0
        state.vertical_phase = 0
    } else {
        // Accumulate the incremental phase using the FOV for this frame.
        // Recomputing the entire phase from the latest FOV makes a dynamic
        // flight-camera zoom shift the pattern even without camera rotation.
        state.horizontal_phase += dither_pixel_phase_delta(yaw_delta, field_of_view, viewport_width)
        state.vertical_phase += dither_pixel_phase_delta(pitch_delta, field_of_view, viewport_height)
    }
    state.initialized = true
    state.previous_mode = mode
    state.previous_customization = customization
    state.previous_yaw = yaw
    state.previous_pitch = pitch
    state.previous_position = pose.position
}

dither_encode_world_post_push :: proc(
    destination: []u8,
    ctx: render2d.World_Post_Context,
    _: rawptr,
) -> bool {
    if len(destination) < size_of(rl.Push) do return false
    push := rl.Push{}
    editor := world_renderer.editor
    if editor != nil {
        mode := editor.gameplay_options.dither_mode
        render_pose :=
            editor.pause_screen == .Customization ? customization_preview_camera_pose() : editor.camera_pose
        focal_length := editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : f32(1.35)
        focal_length = max(focal_length, f32(.1))
        field_of_view := f32(2 * math.atan(1 / f64(focal_length)))
        pattern_size := mode == .Blue_Noise || mode == .Matriax_8 ? 64 : 8
        dither_update_tracking(
            editor,
            render_pose,
            mode,
            field_of_view,
            int(ctx.composite_extent[0]),
            int(ctx.composite_extent[1]),
        )
        offset_x := dither_wrap_pixel_phase(editor.dither_state.horizontal_phase, pattern_size)
        offset_y := dither_wrap_pixel_phase(editor.dither_state.vertical_phase, pattern_size)
        push.viewport = {
            f32(ctx.target_extent[0]),
            f32(ctx.target_extent[1]),
            f32(ctx.composite_extent[0]),
            f32(ctx.composite_extent[1]),
        }
        push.texture_hatch = {f32(mode), f32(offset_x), f32(offset_y), 0}
        push.hatch_shape = {
            f32(ctx.source_extent[0]),
            f32(ctx.source_extent[1]),
            field_of_view,
            0,
        }
    }
    mem.copy_non_overlapping(raw_data(destination), &push, size_of(push))
    return true
}
