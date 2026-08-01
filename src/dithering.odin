package main

import atmosphere "../packages/atmosphere"
import dither "../packages/dither"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:testing"
import canvas2d "zelda_engine:canvas2d"
import render2d "zelda_engine:render2d"

Dither_Mode :: dither.Mode
dither_mode_label :: dither.mode_label
dither_adjust_mode :: dither.adjust_mode
dither_next_mode :: dither.next_mode
dither_wrap_angle :: dither.wrap_angle
dither_pattern_offset :: dither.pattern_offset
dither_pixel_phase_delta :: dither.pixel_phase_delta
dither_wrap_pixel_phase :: dither.wrap_pixel_phase

Visual_Style :: enum {
    Standard,
    Dither,
}

Photo_Filter_Mode :: enum i32 {
    Off,
    Oil,
    Watercolor,
    Pastel,
    Charcoal,
    Ink,
    Hatch,
    Kuwahara,
    Quantize,
    Black_White,
    Greyscale,
    Sharpen,
    Mottle,
    Distort,
    Vignette,
    Adjuster,
    Composite,
    Depth_Of_Field,
    Color_Fog,
    Monochrome_Fog,
    LUT,
    Outline,
    Splash,
    Window,
    Floyd_Steinberg,
}

PHOTO_FILTER_MODE_COUNT :: int(Photo_Filter_Mode.Floyd_Steinberg) + 1
PHOTO_FILTER_CONTROL_COUNT :: 10
photo_filter_capture_enabled: bool

Photo_Filter_Settings :: struct {
    initialized:   bool,
    panel_open:    bool,
    focus:         int,
    mode:          Photo_Filter_Mode,
    intensity:     f32,
    radius:        f32,
    detail:        f32,
    saturation:    f32,
    contrast:      f32,
    brightness:    f32,
    grain:         f32,
    vignette:      f32,
    distortion:    f32,
    preset_values: [PHOTO_FILTER_MODE_COUNT][9]f32,
}

photo_filter_store_active :: proc(settings: ^Photo_Filter_Settings) {
    if settings == nil do return
    settings.preset_values[int(settings.mode)] = {
        settings.intensity,
        settings.radius,
        settings.detail,
        settings.saturation,
        settings.contrast,
        settings.brightness,
        settings.grain,
        settings.vignette,
        settings.distortion,
    }
}

photo_filter_load_active :: proc(settings: ^Photo_Filter_Settings) {
    if settings == nil do return
    values := settings.preset_values[int(settings.mode)]
    settings.intensity, settings.radius, settings.detail = values[0], values[1], values[2]
    settings.saturation, settings.contrast, settings.brightness = values[3], values[4], values[5]
    settings.grain, settings.vignette, settings.distortion = values[6], values[7], values[8]
}

photo_filter_reset_mode :: proc(settings: ^Photo_Filter_Settings, mode: Photo_Filter_Mode) {
    values := [9]f32{1, .35, .55, 1, 1, 0, .2, 0, 0}
    #partial switch mode {
    case .Depth_Of_Field:
        values = {1, .30, .24, 1, 1, 0, .1, .08, 0}
    case .Color_Fog:
        values = {1, .48, .28, 1, 1, 0, .05, 0, .05}
    case .Monochrome_Fog:
        values = {1, .50, .30, 0, 1, .35, .04, .05, 0}
    case .LUT:
        values = {1, .12, .5, 1, 1, 0, .05, .05, 0}
    case .Outline:
        values = {1, .22, .42, 1, .72, 0, .05, 0, .08}
    case .Window:
        values = {1, .82, .50, 1, 1, 0, 0, 0, 0}
    case .Floyd_Steinberg:
        values = {1, .30, 1, 1, 1, 0, 0, 0, 1}
    case .Vignette:
        values = {1, .35, .55, 1, 1, 0, .05, 1, 0}
    case:
    }
    settings.preset_values[int(mode)] = values
    if settings.mode == mode do photo_filter_load_active(settings)
}

photo_filter_defaults :: proc(settings: ^Photo_Filter_Settings) {
    if settings == nil do return
    settings^ = {
        initialized = true,
        mode        = .Off,
        intensity   = 1,
        radius      = .35,
        detail      = .55,
        saturation  = 1,
        contrast    = 1,
        grain       = .2,
        vignette    = 0,
    }
    for index in 0 ..< PHOTO_FILTER_MODE_COUNT {
        photo_filter_reset_mode(settings, Photo_Filter_Mode(index))
    }
    photo_filter_load_active(settings)
}

photo_filter_mode_label :: proc(mode: Photo_Filter_Mode) -> cstring {
    #partial switch mode {
    case .Off:
        return "OFF"
    case .Oil:
        return "OIL"
    case .Watercolor:
        return "WATERCOLOR"
    case .Pastel:
        return "PASTEL"
    case .Charcoal:
        return "CHARCOAL"
    case .Ink:
        return "INK"
    case .Hatch:
        return "HATCH"
    case .Kuwahara:
        return "KUWAHARA"
    case .Quantize:
        return "QUANTIZE"
    case .Black_White:
        return "BLACK + WHITE"
    case .Greyscale:
        return "GREYSCALE"
    case .Sharpen:
        return "SHARPEN"
    case .Mottle:
        return "MOTTLE"
    case .Distort:
        return "DISTORT"
    case .Vignette:
        return "VIGNETTE"
    case .Adjuster:
        return "ADJUSTER"
    case .Composite:
        return "MIXED MEDIA"
    case .Depth_Of_Field:
        return "DEPTH OF FIELD"
    case .Color_Fog:
        return "COLOR FOG"
    case .Monochrome_Fog:
        return "MONO FOG"
    case .LUT:
        return "COLOR GRADE"
    case .Outline:
        return "OUTLINE"
    case .Splash:
        return "SPLASH"
    case .Window:
        return "WINDOW"
    case .Floyd_Steinberg:
        return "FLOYD-STEINBERG"
    }
    return "OFF"
}

photo_filter_control_label :: proc(mode: Photo_Filter_Mode, row: int) -> cstring {
    if row == 0 do return "MODE"
    if row == 1 do return "INTENSITY"
    #partial switch mode {
    case .Adjuster:
        labels := [8]cstring{"", "", "BRIGHTNESS", "CONTRAST", "SATURATION", "HUE", "VIGNETTE", "GRAIN"}
        if row < len(labels) do return labels[row]
    case .Depth_Of_Field:
        labels := [8]cstring{"", "", "FOCUS", "FOCUS RANGE", "BLUR", "BOKEH", "VIGNETTE", "GRAIN"}
        if row < len(labels) do return labels[row]
    case .Color_Fog, .Monochrome_Fog:
        labels := [8]cstring{"", "", "DISTANCE", "FALLOFF", "DENSITY", "COLOR", "VIGNETTE", "GRAIN"}
        if row < len(labels) do return labels[row]
    case .LUT:
        labels := [8]cstring{"", "", "GRADE", "CONTRAST", "SATURATION", "EXPOSURE", "VIGNETTE", "GRAIN"}
        if row < len(labels) do return labels[row]
    case .Window:
        labels := [8]cstring{"", "", "FRAME SIZE", "FEATHER", "ASPECT", "ROTATION", "VIGNETTE", "GRAIN"}
        if row < len(labels) do return labels[row]
    case .Outline:
        labels := [8]cstring{"", "", "THICKNESS", "THRESHOLD", "DARKNESS", "WOBBLE", "VIGNETTE", "GRAIN"}
        if row < len(labels) do return labels[row]
    case .Floyd_Steinberg:
        labels := [10]cstring {
            "MODE",
            "INTENSITY",
            "PALETTE LEVELS",
            "DIFFUSION",
            "SATURATION",
            "CONTRAST",
            "BRIGHTNESS",
            "ERROR JITTER",
            "VIGNETTE",
            "SERPENTINE",
        }
        if row < len(labels) do return labels[row]
    case:
    }
    labels := [10]cstring {
        "MODE",
        "INTENSITY",
        "RADIUS",
        "DETAIL",
        "SATURATION",
        "CONTRAST",
        "BRIGHTNESS",
        "GRAIN",
        "VIGNETTE",
        "DISTORTION",
    }
    return labels[clamp(row, 0, len(labels) - 1)]
}

photo_filter_adjust_mode :: proc(mode: Photo_Filter_Mode, direction: int) -> Photo_Filter_Mode {
    value := (int(mode) + direction) % PHOTO_FILTER_MODE_COUNT
    if value < 0 do value += PHOTO_FILTER_MODE_COUNT
    return Photo_Filter_Mode(value)
}

photo_filter_mode_parse :: proc(value: string) -> (Photo_Filter_Mode, bool) {
    switch value {
    case "off":
        return .Off, true
    case "oil":
        return .Oil, true
    case "watercolor":
        return .Watercolor, true
    case "pastel":
        return .Pastel, true
    case "charcoal":
        return .Charcoal, true
    case "ink":
        return .Ink, true
    case "hatch":
        return .Hatch, true
    case "kuwahara":
        return .Kuwahara, true
    case "quantize":
        return .Quantize, true
    case "black-white":
        return .Black_White, true
    case "greyscale":
        return .Greyscale, true
    case "sharpen":
        return .Sharpen, true
    case "mottle":
        return .Mottle, true
    case "distort":
        return .Distort, true
    case "vignette":
        return .Vignette, true
    case "adjuster":
        return .Adjuster, true
    case "composite":
        return .Composite, true
    case "depth-of-field":
        return .Depth_Of_Field, true
    case "color-fog":
        return .Color_Fog, true
    case "mono-fog":
        return .Monochrome_Fog, true
    case "lut":
        return .LUT, true
    case "outline":
        return .Outline, true
    case "splash":
        return .Splash, true
    case "window":
        return .Window, true
    case "floyd-steinberg":
        return .Floyd_Steinberg, true
    }
    return .Off, false
}

visual_style_label :: proc(style: Visual_Style) -> cstring {
    switch style {
    case .Standard:
        return "STANDARD"
    case .Dither:
        return "DITHER"
    }
    return "STANDARD"
}

visual_style_adjust :: proc(style: Visual_Style, direction: int) -> Visual_Style {
    return Visual_Style(clamp(int(style) + direction, 0, 1))
}

visual_style_next :: proc(style: Visual_Style) -> Visual_Style {
    return Visual_Style((int(style) + 1) % 2)
}

dither_adjust_variant :: proc(mode: Dither_Mode, direction: int) -> Dither_Mode {
    current := clamp(int(mode), int(Dither_Mode.Bayer), int(Dither_Mode.Matriax_8))
    return Dither_Mode(clamp(current + direction, int(Dither_Mode.Bayer), int(Dither_Mode.Matriax_8)))
}

dither_next_variant :: proc(mode: Dither_Mode) -> Dither_Mode {
    current := clamp(int(mode), int(Dither_Mode.Bayer), int(Dither_Mode.Matriax_8))
    return current == int(Dither_Mode.Matriax_8) ? .Bayer : Dither_Mode(current + 1)
}

visual_style_set :: proc(editor: ^Editor, style: Visual_Style) {
    if editor == nil do return
    editor.gameplay_options.visual_style = style
    if style == .Dither && editor.gameplay_options.dither_mode == .Off {
        editor.gameplay_options.dither_mode = .Bayer
    }
    dither_apply(editor)
}

when ODIN_TEST {
    @(test)
    visual_style_labels_and_selection_are_stable :: proc(t: ^testing.T) {
        testing.expect_value(t, visual_style_label(.Standard), cstring("STANDARD"))
        testing.expect_value(t, visual_style_label(.Dither), cstring("DITHER"))
        testing.expect_value(t, visual_style_adjust(.Standard, -1), Visual_Style.Standard)
        testing.expect_value(t, visual_style_next(.Dither), Visual_Style.Standard)
        testing.expect_value(t, dither_adjust_variant(.Off, 1), Dither_Mode.Blue_Noise)
        testing.expect_value(t, dither_next_variant(.Matriax_8), Dither_Mode.Bayer)
    }

    @(test)
    photo_filter_modes_wrap_and_defaults_are_stable :: proc(t: ^testing.T) {
        settings: Photo_Filter_Settings
        photo_filter_defaults(&settings)
        testing.expect(t, settings.initialized)
        testing.expect_value(t, settings.mode, Photo_Filter_Mode.Off)
        testing.expect_value(t, settings.intensity, f32(1))
        testing.expect_value(t, settings.saturation, f32(1))
        testing.expect_value(t, settings.contrast, f32(1))
        testing.expect_value(t, photo_filter_adjust_mode(.Off, -1), Photo_Filter_Mode.Floyd_Steinberg)
        testing.expect_value(t, photo_filter_adjust_mode(.Floyd_Steinberg, 1), Photo_Filter_Mode.Off)
        testing.expect_value(t, photo_filter_mode_label(.Kuwahara), cstring("KUWAHARA"))
        testing.expect_value(t, photo_filter_mode_label(.Floyd_Steinberg), cstring("FLOYD-STEINBERG"))
        parsed_floyd, parsed_floyd_ok := photo_filter_mode_parse("floyd-steinberg")
        testing.expect(t, parsed_floyd_ok)
        testing.expect_value(t, parsed_floyd, Photo_Filter_Mode.Floyd_Steinberg)
        testing.expect_value(t, PHOTO_FILTER_MODE_COUNT, 25)
        testing.expect_value(t, photo_filter_pass_count(.Adjuster), 1)
        testing.expect_value(t, photo_filter_pass_count(.Watercolor), 2)
        testing.expect_value(t, photo_filter_pass_count(.Oil), 3)
        settings.mode = .Oil
        photo_filter_load_active(&settings)
        settings.radius = .91
        photo_filter_store_active(&settings)
        settings.mode = .Watercolor
        photo_filter_load_active(&settings)
        testing.expect(t, settings.radius != .91)
        settings.mode = .Oil
        photo_filter_load_active(&settings)
        testing.expect_value(t, settings.radius, f32(.91))
        photo_filter_defaults(&settings)
        settings.mode = .Oil
        photo_filter_load_active(&settings)
        testing.expect(t, settings.radius != .91)
    }
}

Dither_State :: struct {
    initialized:            bool,
    previous_mode:          Dither_Mode,
    previous_customization: bool,
    previous_yaw:           f32,
    previous_pitch:         f32,
    horizontal_phase:       f32,
    vertical_phase:         f32,
    previous_position:      third_person.Vec3,
    exposure_initialized:   bool,
    exposure:               f32,
    sun_glare:              f32,
    exposure_seconds:       f64,
}

dither_reset :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.dither_state = {}
}

dither_apply :: proc(editor: ^Editor) {
    if editor == nil do return
    dither_reset(editor)
    // Exposure adaptation also lives in the world post pass and must remain
    // active when palette dithering is disabled.
    canvas2d.SetWorldPostProcessEnabled(true)
    photo_filter_apply_pass_plan(editor)
}

photo_filter_pass_count :: proc(mode: Photo_Filter_Mode) -> int {
    #partial switch mode {
    case .Oil, .Pastel, .Composite, .Depth_Of_Field:
        return 3
    case .Watercolor, .Charcoal, .Hatch, .Kuwahara, .Sharpen, .Outline, .Splash:
        return 2
    }
    return 1
}

// Keep the renderer's transient pass plan synchronized with the active preset.
photo_filter_apply_pass_plan :: proc(editor: ^Editor) {
    count := 1
    if editor != nil && (menu_scene_current(editor) == .Photo || photo_filter_capture_enabled) {
        count = photo_filter_pass_count(editor.photo_filter.mode)
    }
    requests: [canvas2d.WORLD_POST_MAX_PASSES]canvas2d.World_Post_Pass_Request
    for index in 0 ..< count do requests[index].resolution = .Full
    canvas2d.SetWorldPostPassPlan(requests[:count])
}

sun_exposure_smoothstep :: proc(edge0, edge1, value: f32) -> f32 {
    amount := clamp((value - edge0) / max(edge1 - edge0, f32(.0001)), f32(0), f32(1))
    return amount * amount * (3 - 2 * amount)
}

sun_exposure_update :: proc(editor: ^Editor, pose: third_person.Camera_Pose) -> (exposure, glare: f32) {
    if editor == nil do return 1, 0
    state := &editor.dither_state
    if !editor.gameplay_options.hdr_exposure {
        state.exposure_initialized = false
        state.exposure = 1
        state.sun_glare = 0
        return 1, 0
    }
    sky := atmosphere_sky(editor)
    forward := linalg.normalize0(pose.target - pose.position)
    sun := third_person.Vec3{sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2]}
    alignment := clamp(linalg.dot(forward, sun), f32(-1), f32(1))
    centered := sun_exposure_smoothstep(.88, .998, alignment)
    above_horizon := sun_exposure_smoothstep(-.025, .075, sky.sun_direction[1])
    cloud_visibility := 1 - clamp(sky.weather.cloud_cover, f32(0), f32(1)) * .82
    target_glare := centered * above_horizon * cloud_visibility
    target_exposure := 1 - target_glare * .50

    now := canvas2d.GetTime()
    if !state.exposure_initialized {
        state.exposure_initialized = true
        state.exposure = target_exposure
        state.sun_glare = target_glare
        state.exposure_seconds = now
    } else {
        delta := f32(clamp(now - state.exposure_seconds, f64(0), f64(.1)))
        // Iris closure is quick; recovery after looking away is deliberately
        // slower so the response reads as adaptation rather than a toggle.
        rate := target_exposure < state.exposure ? f32(4.2) : f32(1.15)
        blend := 1 - f32(math.exp(f64(-rate * delta)))
        state.exposure += (target_exposure - state.exposure) * blend
        state.sun_glare += (target_glare - state.sun_glare) * blend
        state.exposure_seconds = now
    }
    return state.exposure, state.sun_glare
}

dither_camera_angles :: proc(pose: third_person.Camera_Pose) -> (yaw, pitch: f32) {
    forward := linalg.normalize0((pose.target - pose.position))
    yaw = math.atan2(-forward.x, -forward.z)
    pitch = math.asin(clamp(forward.y, f32(-1), f32(1)))
    return
}

dither_position_cut :: proc(a, b: third_person.Vec3) -> bool {
    delta := (a - b)
    return linalg.dot(delta, delta) > 400
}

dither_update_tracking :: proc(
    editor: ^Editor,
    pose: third_person.Camera_Pose,
    mode: Dither_Mode,
    field_of_view: f32,
    viewport_width, viewport_height: int,
) {
    state := &editor.dither_state
    customization := menu_scene_current(editor) == .Customization
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

dither_encode_world_post_push :: proc(destination: []u8, ctx: render2d.World_Post_Context, _: rawptr) -> bool {
    if len(destination) < size_of(canvas2d.Push) do return false
    push := canvas2d.Push{}
    push.hatch_tone = {1, 0, 0, 0}
    editor := world_renderer.editor
    if editor != nil {
        style := editor.gameplay_options.visual_style
        mode := style == .Dither ? editor.gameplay_options.dither_mode : Dither_Mode.Off
        render_pose := menu_scene_current(editor) == .Customization ? customization_preview_camera_pose() : editor.camera_pose
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
        push.texture_hatch = {f32(mode), f32(offset_x), f32(offset_y), f32(style)}
        animation_time := photo_filter_capture_enabled ? f32(1.25) : f32(canvas2d.GetTime())
        push.hatch_shape = {f32(ctx.source_extent[0]), f32(ctx.source_extent[1]), field_of_view, animation_time}
        exposure, glare := sun_exposure_update(editor, render_pose)
        // Depth presets reconstruct view distance from the active projection.
        push.hatch_tone = {exposure, glare, world_camera_near_clip(editor), WORLD_FAR_CLIP}
        if (menu_scene_current(editor) == .Photo || photo_filter_capture_enabled) && editor.photo_filter.initialized {
            filter := editor.photo_filter
            push.hatch_offset = {f32(filter.mode), filter.intensity, filter.radius, filter.detail}
            push.hatch_angles = {filter.saturation, filter.contrast, filter.brightness, filter.grain}
            push.hatch_levels = {filter.vignette, filter.distortion, f32(ctx.pass_index), f32(ctx.pass_count)}
        }
    }
    mem.copy_non_overlapping(raw_data(destination), &push, size_of(push))
    return true
}
