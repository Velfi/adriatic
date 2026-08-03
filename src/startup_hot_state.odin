package main

import hs "../packages/hs"
import vehicles "../packages/vehicles"
import "core:math"
import "core:mem"
import "core:os"
import canvas2d "zelda_engine:canvas2d"

draw_startup_loading_screen :: proc(
    width, height: i32,
    progress: f32,
    message: cstring,
    postcard: canvas2d.Texture = {},
) {
    w, h := f32(width), f32(height)
    center := canvas2d.Vector2{w * .5, h * .5}
    scale := min(w / 1280, h / 720)
    ui_scale := max(scale, f32(.85))
    animation_time := f32(canvas2d.GetTime())
    normalized_progress := clamp(progress, 0, 1)
    title: cstring = "ADRIATIC"
    greeting: cstring = "GREETINGS FROM"
    title_font_size := max(48 * scale, f32(32))
    greeting_font_size := max(14 * scale, f32(11))
    message_font_size := max(14 * scale, f32(13))
    title_size := canvas2d.MeasureTextEx(canvas2d.Font{}, title, title_font_size, 7 * scale)
    greeting_size := canvas2d.MeasureTextEx(canvas2d.Font{}, greeting, greeting_font_size, 3 * scale)
    message_size := canvas2d.MeasureTextEx(canvas2d.Font{}, message, message_font_size, 1)
    track_width := min(w - 96, 420 * ui_scale)
    track := canvas2d.Rectangle {
        x      = center.x - track_width * .5,
        y      = h - 72 * ui_scale,
        width  = track_width,
        height = 7 * ui_scale,
    }

    if postcard.ready {
        canvas2d.BeginDrawing()
        canvas2d.DrawTexturePro(
            postcard,
            {0, 0, f32(postcard.width), f32(postcard.height)},
            {0, 0, w, h},
            {255, 255, 255, 255},
        )

        // Live ink strokes retain the gentle movement of the procedural
        // version without competing with the illustrated background.
        for ripple in 0 ..< 7 {
            ripple_y := h * .73 + f32(ripple) * 18 * scale
            ripple_x :=
                center.x -
                430 * scale +
                f32((ripple * 149) % 710) * scale +
                math.sin(animation_time * .8 + f32(ripple)) * 7 * scale
            canvas2d.DrawLineEx(
                {ripple_x, ripple_y},
                {ripple_x + (25 + f32(ripple % 3) * 11) * scale, ripple_y},
                max(1, scale),
                {225, 207, 155, 75},
            )
        }

        boat_x := center.x - 390 * scale + normalized_progress * 245 * scale
        boat_y := h * .73 + math.sin(animation_time * 1.7) * 2.5 * scale
        canvas2d.DrawLineEx({boat_x, boat_y - 42 * scale}, {boat_x, boat_y + 2 * scale}, 2 * scale, {54, 42, 36, 255})
        for sail_row in 0 ..< 9 {
            sail_y := boat_y - (38 - f32(sail_row) * 4) * scale
            sail_width := (2 + f32(sail_row) * 2.1) * scale
            canvas2d.DrawLineEx(
                {boat_x + 2 * scale, sail_y},
                {boat_x + 2 * scale + sail_width, sail_y},
                3.5 * scale,
                {244, 224, 177, 245},
            )
        }
        canvas2d.DrawLineEx(
            {boat_x - 16 * scale, boat_y + 4 * scale},
            {boat_x + 22 * scale, boat_y + 4 * scale},
            7 * scale,
            {135, 59, 43, 255},
        )
        for wake in 0 ..< 3 {
            wake_y := boat_y + (11 + f32(wake) * 6) * scale
            wake_half_width := (16 + f32(wake) * 9) * scale
            canvas2d.DrawLineEx(
                {boat_x - wake_half_width, wake_y},
                {boat_x + wake_half_width, wake_y},
                max(1, scale),
                {226, 214, 174, u8(105 - wake * 22)},
            )
        }

        canvas2d.DrawTextEx(
            canvas2d.Font{},
            greeting,
            {center.x - greeting_size.x * .5, 55 * ui_scale},
            greeting_font_size,
            3 * scale,
            {246, 222, 172, 230},
        )
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            title,
            {center.x - title_size.x * .5 + 2 * scale, 77 * ui_scale + 2 * scale},
            title_font_size,
            7 * scale,
            {154, 58, 49, 210},
        )
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            title,
            {center.x - title_size.x * .5, 76 * ui_scale},
            title_font_size,
            7 * scale,
            {248, 239, 203, 255},
        )
        canvas2d.DrawRectangleRounded(track, 1, 8, {5, 24, 34, 220})
        if normalized_progress > 0 {
            fill := track
            fill.width *= normalized_progress
            canvas2d.DrawRectangleRounded(fill, 1, 8, {241, 188, 93, 255})
            if fill.width > 24 * scale {
                glint_phase := math.sin(animation_time * 1.1) * .5 + .5
                glint_x := fill.x + 8 * scale + (fill.width - 16 * scale) * glint_phase
                canvas2d.DrawLineEx(
                    {glint_x, fill.y + scale},
                    {glint_x, fill.y + fill.height - scale},
                    2 * scale,
                    {255, 238, 177, 180},
                )
            }
        }
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            message,
            {center.x - message_size.x * .5, track.y + track.height + 12 * ui_scale},
            message_font_size,
            1,
            {226, 226, 204, 255},
        )

        frame_width := max(10 * scale, f32(8))
        frame_color := canvas2d.Color{238, 221, 181, 255}
        canvas2d.DrawRectangle(0, 0, width, i32(frame_width), frame_color)
        canvas2d.DrawRectangle(0, height - i32(frame_width), width, i32(frame_width), frame_color)
        canvas2d.DrawRectangle(0, 0, i32(frame_width), height, frame_color)
        canvas2d.DrawRectangle(width - i32(frame_width), 0, i32(frame_width), height, frame_color)
        canvas2d.DrawRectangleRoundedLinesEx(
            {frame_width, frame_width, w - frame_width * 2, h - frame_width * 2},
            .01,
            2,
            max(1, 2 * scale),
            {104, 59, 49, 180},
        )
        live_capture_poll()
        canvas2d.EndDrawing()
        return
    }
}

Hot_State_File_Header :: struct {
    magic:        [8]u8,
    version:      u32,
    type_hash:    u64,
    payload_size: u64,
}

HOT_STATE_FILE_MAGIC :: [8]u8{'A', 'D', 'R', 'H', 'S', 'T', '1', 0}
HOT_STATE_FILE_VERSION :: u32(1)

Hot_State_Load_Result :: enum {
    Missing,
    Loaded,
    Invalid,
}

hot_state_header_valid :: proc(header: ^Hot_State_File_Header, payload_size: int) -> bool {
    if header == nil || payload_size < 0 do return false
    magic := HOT_STATE_FILE_MAGIC
    for i in 0 ..< len(HOT_STATE_FILE_MAGIC) {
        if header.magic[i] != magic[i] do return false
    }
    return header.version == HOT_STATE_FILE_VERSION && header.payload_size == u64(payload_size)
}

hot_state_save :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || path == "" do return false

    state := new(Editor, context.temp_allocator)
    state^ = editor^
    state.fixture_owner = {}
    lifecycle_error := fixture_lifecycle_detach(&editor.fixture, &state.fixture)
    if lifecycle_error.kind != .None do return false
    state.car_physics_world = nil
    state.car_physics_vehicle = nil
    state.gameplay_physics = {}
    state.engine_audio.stream = nil

    // These values belong to the loaded dylib or the GPU. Never preserve their
    // pointers across an unload. Canvas textures live in the host-owned canvas
    // state and are intentionally serialized with the editor.
    state.libellula_visual_mesh = {}
    state.libellula_projected_faces = {}
    state.attendant_dialogue = {}
    state.attendant_dialogue_open = false
    state.dialogue_session = {}

    payload := hs.serialize(state, {.Dynamics}, context.allocator)
    defer delete(payload)
    if len(payload) == 0 do return false

    header := Hot_State_File_Header {
        magic        = HOT_STATE_FILE_MAGIC,
        version      = HOT_STATE_FILE_VERSION,
        type_hash    = hs.type_hash(Editor),
        payload_size = u64(len(payload)),
    }
    output := make([dynamic]byte, 0, size_of(header) + len(payload), context.allocator)
    append(&output, ..mem.ptr_to_bytes(&header))
    append(&output, ..payload)
    defer delete(output)
    return os.write_entire_file(path, output[:]) == nil
}

hot_state_load :: proc(editor: ^Editor, path: string) -> Hot_State_Load_Result {
    if editor == nil || path == "" do return .Missing

    data, err := os.read_entire_file_from_path(path, context.temp_allocator)
    if err == .Not_Exist do return .Missing
    if err != nil || len(data) < size_of(Hot_State_File_Header) do return .Invalid

    header := cast(^Hot_State_File_Header)(&data[0])
    payload := data[size_of(Hot_State_File_Header):]
    if !hot_state_header_valid(header, len(payload)) do return .Invalid
    if len(payload) == 0 do return .Invalid

    // Validate fixture-backed lab state before replacing any live allocations.
    // Hot-state deserialization itself is intentionally a direct memory restore,
    // so use temporary storage for this atomic preflight pass.
    probe := new(Editor, context.temp_allocator)
    _ = hs.deserialize(probe, payload, {.Dynamics}, context.temp_allocator)
    if lab_fixture_preflight(probe.lab) != "" do return .Invalid

    // Existing allocations are runtime-owned. hs rebuilds dynamic data from
    // the blob, so release these before it replaces their descriptors.
    vehicles.libellula_mesh_destroy(&editor.libellula_visual_mesh)
    delete(editor.libellula_projected_faces)
    attendant_dialogue_definition_release(editor)
    fixture_editor_paint_history_destroy(editor)
    structure_storage_destroy(editor)
    fixture_migration_result_dispose(&editor.fixture_owner)

    identical := hs.deserialize(editor, payload, {.Dynamics}, context.allocator)
    _ = identical // hs already used mem.copy for every identical subtree.
    lifecycle_error := fixture_lifecycle_bind(&editor.fixture)
    if lifecycle_error.kind != .None do return .Invalid

    editor.libellula_visual_mesh = {}
    vehicles.libellula_mesh_init(&editor.libellula_visual_mesh)
    editor.libellula_projected_faces = make(
        [dynamic]Projected_Aircraft_Face,
        0,
        vehicles.LIBELLULA_MESH_TRIANGLE_CAPACITY,
    )
    editor.attendant_dialogue = {}
    editor.attendant_dialogue_open = false
    editor.dialogue_session = {}
    editor.quit_requested = false
    dunes_lab_rehydrate(editor)
    return .Loaded
}
