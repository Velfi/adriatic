package main

import libellula_game "../packages/libellula"
import flight "../packages/flight"
import postale_game "../packages/postale"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import rl "zelda_engine:canvas2d"

VEHICLE_PAINT_TEXTURE_WIDTH :: 512
VEHICLE_PAINT_TEXTURE_HEIGHT :: 256
VEHICLE_PAINT_TEXTURE_BYTE_COUNT :: VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_HEIGHT * 4
VEHICLE_PAINT_AIRCRAFT_COUNT :: 3
VEHICLE_PAINT_HISTORY_CAPACITY :: 16

Vehicle_Paint_History_Change :: struct {
    texel:  u32,
    before: [4]u8,
    after:  [4]u8,
}

Vehicle_Paint_History_Entry :: struct {
    changes: [dynamic]Vehicle_Paint_History_Change,
}

Vehicle_Paint_Tool :: enum u8 {
    Brush,
    Bucket,
    Shape,
    Blend,
    Gradient,
    Pattern,
    Strip,
}

VEHICLE_PAINT_TOOL_NAMES :: [7]string {
    "BRUSH",
    "BUCKET",
    "SHAPE",
    "BLEND",
    "GRADIENT",
    "PATTERN",
    "STRIP",
}

VEHICLE_PAINT_COMPONENT_NAMES :: [5]string{"BODY", "WINGS", "TAIL", "ENGINE", "FLOATS"}

VEHICLE_PAINT_COLORS :: [16]rl.Color {
    {220, 66, 54, 255},
    {240, 112, 72, 255},
    {238, 160, 61, 255},
    {240, 208, 74, 255},
    {143, 196, 78, 255},
    {72, 174, 103, 255},
    {42, 166, 157, 255},
    {54, 181, 211, 255},
    {53, 111, 194, 255},
    {54, 66, 132, 255},
    {112, 78, 167, 255},
    {178, 72, 153, 255},
    {224, 91, 133, 255},
    {239, 224, 190, 255},
    {139, 148, 151, 255},
    {46, 49, 57, 255},
}

vehicle_paint_layer_index :: proc(kind: vehicles.Aircraft_Kind) -> int {
    return clamp(int(kind), 0, VEHICLE_PAINT_AIRCRAFT_COUNT - 1)
}

vehicle_paint_pixels :: proc(editor: ^Editor) -> []u8 {
    if editor == nil do return nil
    return editor.vehicle_paint_layers[vehicle_paint_layer_index(editor.aircraft.active)][:]
}

vehicle_paint_settings_initialize :: proc(editor: ^Editor) {
    if editor == nil || editor.vehicle_paint_settings_initialized do return
    editor.vehicle_paint_color = 0
    editor.vehicle_paint_secondary_color = 13
    editor.vehicle_paint_tool = .Brush
    editor.vehicle_paint_component = 0
    editor.vehicle_paint_component_mask = [5]bool{true, true, true, true, true}
    editor.vehicle_paint_brush_radius = 14
    editor.vehicle_paint_brush_hardness = .75
    editor.vehicle_paint_symmetry = false
    editor.vehicle_paint_settings_initialized = true
}

vehicle_paint_open :: proc(editor: ^Editor) {
    if editor == nil do return
    vehicle_paint_settings_initialize(editor)
    editor.vehicle_paint_scene = true
    editor.vehicle_showcase_scene = true
    editor.vehicle_showcase_target =
        editor.aircraft.active == .Postale ? "postale" : (editor.aircraft.active == .Libellula_Mk2 ? "libellula-mk2" : "libellula")
    editor.vehicle_paint_yaw = -.92
    editor.vehicle_paint_pitch = .24
    editor.vehicle_paint_distance = 6.1
    editor.vehicle_paint_cursor_x = f32(ADRIATIC_WORLD_WIDTH) * .5
    editor.vehicle_paint_cursor_y = f32(ADRIATIC_WORLD_HEIGHT) * .5
    editor.vehicle_paint_panel_visible = true
    // Erasing is intentionally transient even though the broader working
    // setup is retained; reopening should never begin in a destructive mode.
    editor.vehicle_paint_erase = false
    editor.vehicle_paint_stroke_active = false
    editor.vehicle_paint_stroke_uv_valid = false
    editor.vehicle_paint_stroke_mirror_valid = false
    editor.vehicle_paint_tool_drag_active = false
    clear(&editor.vehicle_paint_tool_drag_texels)
    editor.vehicle_paint_tool_drag_mirror_valid = false
    clear(&editor.vehicle_paint_tool_drag_mirror_texels)
    editor.vehicle_paint_hover_hit = false
    editor.vehicle_paint_clear_confirm_until = 0
    editor.vehicle_paint_sound_until = 0
    editor.vehicle_paint_postale_mesh = vehicles.postale_mesh()
    if editor.aircraft.active == .Postale {
        vehicles.animate_postale_mesh(&editor.vehicle_paint_postale_mesh, editor.postale.flap_fraction, 0, 0, 0, 0)
        vehicle_paint_build_texel_parts(editor, &editor.vehicle_paint_postale_mesh)
    } else if editor.aircraft.active == .Libellula_Mk2 {
        vehicles.libellula_mk2_mesh_build(&editor.libellula_mk2_visual_mesh)
        vehicle_paint_build_texel_parts(editor, &editor.libellula_mk2_visual_mesh)
    } else {
        vehicles.libellula_mesh_build(&editor.libellula_visual_mesh)
        vehicle_paint_build_texel_parts(editor, &editor.libellula_visual_mesh)
    }
    editor.vehicle_paint_texture_dirty = false
    editor.vehicle_paint_saved_postale_position = editor.postale.body.position
    editor.vehicle_paint_saved_libellula_position = editor.libellula.body.position
    editor.postale_visible = editor.aircraft.active == .Postale
    editor.libellula_visible = editor.aircraft.active != .Postale
    if editor.aircraft.active == .Postale {
        editor.postale.body.position = {
            y = postale_game.GROUND_CLEARANCE,
        }
        editor.postale.vehicle.position = {
            x = editor.postale.body.position.x,
            y = editor.postale.body.position.y,
            z = editor.postale.body.position.z,
        }
    } else {
        editor.libellula.body.position = {
            y = libellula_game.GROUND_CLEARANCE,
        }
        editor.libellula.vehicle.position = {
            x = editor.libellula.body.position.x,
            y = editor.libellula.body.position.y,
            z = editor.libellula.body.position.z,
        }
    }
    editor.camera_pose = third_person.camera_pose(
        {y = 1},
        {
            yaw_radians = editor.vehicle_paint_yaw,
            pitch_radians = editor.vehicle_paint_pitch,
            distance = editor.vehicle_paint_distance,
            height = 0,
        },
    )
    editor.map_time = f32(rl.GetTime())
    vehicle_paint_upload_texture(editor)
    set_pointer_locked(false)
}

vehicle_paint_component_for_part :: proc(part: vehicles.Aircraft_Mesh_Part) -> int {
    #partial switch part {
    case .Wing, .Left_Flap, .Right_Flap, .Left_Aileron, .Right_Aileron:
        return 1
    case .Tail, .Elevator, .Rudder:
        return 2
    case .Engine, .Propeller, .Left_Propeller, .Right_Propeller:
        return 3
    case .Float, .Frame, .Carriage, .Wheel:
        return 4
    }
    return 0
}

vehicle_paint_component_mask_activate :: proc(editor: ^Editor, index: int, solo: bool) {
    if editor == nil || index < 0 || index >= len(editor.vehicle_paint_component_mask) do return
    editor.vehicle_paint_component = index
    if !solo {
        editor.vehicle_paint_component_mask[index] = !editor.vehicle_paint_component_mask[index]
        return
    }
    enabled_count := 0
    for enabled in editor.vehicle_paint_component_mask {
        if enabled do enabled_count += 1
    }
    already_solo :=
        enabled_count == 1 &&
        editor.vehicle_paint_component_mask[index]
    for mask_index in 0 ..< len(editor.vehicle_paint_component_mask) {
        editor.vehicle_paint_component_mask[mask_index] = already_solo || mask_index == index
    }
}

vehicle_paint_face_normal :: proc(a, b, c: [3]f32) -> [3]f32 {
    ab := b - a
    ac := c - a
    normal := [3]f32{ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0]}
    length := f32(math.sqrt(f64(normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2])))
    if length <= .0001 do return {0, 1, 0}
    return normal / length
}

vehicle_paint_clear_texture :: proc(editor: ^Editor) {
    if editor == nil do return
    pixels := vehicle_paint_pixels(editor)
    for index in 0 ..< len(pixels) {
        pixels[index] = 0
    }
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_clear_confirm :: proc(editor: ^Editor, now: f32) -> bool {
    if editor == nil do return false
    if editor.vehicle_paint_clear_confirm_until > 0 &&
       now <= editor.vehicle_paint_clear_confirm_until {
        editor.vehicle_paint_clear_confirm_until = 0
        return true
    }
    editor.vehicle_paint_clear_confirm_until = now + 2.5
    return false
}

vehicle_paint_sound_pulse :: proc(editor: ^Editor, seconds: f32 = .1) {
    if editor == nil do return
    editor.vehicle_paint_sound_until =
        max(editor.vehicle_paint_sound_until, f32(rl.GetTime()) + max(seconds, .02))
}

vehicle_paint_history_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    copy(editor.vehicle_paint_history_pixels[:], vehicle_paint_pixels(editor))
    editor.vehicle_paint_history_capturing = true
}

vehicle_paint_history_entries_clear :: proc(entries: ^[dynamic]Vehicle_Paint_History_Entry) {
    if entries == nil do return
    for &entry in entries^ do delete(entry.changes)
    clear(entries)
}

vehicle_paint_history_init :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.vehicle_paint_tool_drag_texels = make([dynamic]int, 0, 4096)
    editor.vehicle_paint_tool_drag_mirror_texels = make([dynamic]int, 0, 4096)
    for layer in 0 ..< VEHICLE_PAINT_AIRCRAFT_COUNT {
        editor.vehicle_paint_undo[layer] =
            make([dynamic]Vehicle_Paint_History_Entry, 0, VEHICLE_PAINT_HISTORY_CAPACITY)
        editor.vehicle_paint_redo[layer] =
            make([dynamic]Vehicle_Paint_History_Entry, 0, VEHICLE_PAINT_HISTORY_CAPACITY)
    }
}

vehicle_paint_history_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    delete(editor.vehicle_paint_tool_drag_texels)
    delete(editor.vehicle_paint_tool_drag_mirror_texels)
    for layer in 0 ..< VEHICLE_PAINT_AIRCRAFT_COUNT {
        vehicle_paint_history_entries_clear(&editor.vehicle_paint_undo[layer])
        vehicle_paint_history_entries_clear(&editor.vehicle_paint_redo[layer])
        delete(editor.vehicle_paint_undo[layer])
        delete(editor.vehicle_paint_redo[layer])
    }
}

vehicle_paint_history_push :: proc(
    entries: ^[dynamic]Vehicle_Paint_History_Entry,
    entry: Vehicle_Paint_History_Entry,
) {
    if entries == nil do return
    if len(entries^) >= VEHICLE_PAINT_HISTORY_CAPACITY {
        delete(entries^[0].changes)
        for index in 1 ..< len(entries^) {
            entries^[index - 1] = entries^[index]
        }
        resize(entries, len(entries^) - 1)
    }
    append(entries, entry)
}

vehicle_paint_history_pop :: proc(
    entries: ^[dynamic]Vehicle_Paint_History_Entry,
) -> (Vehicle_Paint_History_Entry, bool) {
    if entries == nil || len(entries^) == 0 do return {}, false
    last := len(entries^) - 1
    entry := entries^[last]
    entries^[last] = {}
    resize(entries, last)
    return entry, true
}

vehicle_paint_history_commit :: proc(editor: ^Editor) -> bool {
    if editor == nil || !editor.vehicle_paint_history_capturing do return false
    editor.vehicle_paint_history_capturing = false
    pixels := vehicle_paint_pixels(editor)
    entry := Vehicle_Paint_History_Entry {
        changes = make([dynamic]Vehicle_Paint_History_Change, 0, 512),
    }
    for texel in 0 ..< VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_HEIGHT {
        index := texel * 4
        before := [4]u8 {
            editor.vehicle_paint_history_pixels[index],
            editor.vehicle_paint_history_pixels[index + 1],
            editor.vehicle_paint_history_pixels[index + 2],
            editor.vehicle_paint_history_pixels[index + 3],
        }
        after := [4]u8 {
            pixels[index],
            pixels[index + 1],
            pixels[index + 2],
            pixels[index + 3],
        }
        if before != after {
            append(
                &entry.changes,
                Vehicle_Paint_History_Change{texel = u32(texel), before = before, after = after},
            )
        }
    }
    if len(entry.changes) == 0 {
        delete(entry.changes)
        return false
    }
    layer := vehicle_paint_layer_index(editor.aircraft.active)
    vehicle_paint_history_entries_clear(&editor.vehicle_paint_redo[layer])
    vehicle_paint_history_push(&editor.vehicle_paint_undo[layer], entry)
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_save_pending = true
    return true
}

vehicle_paint_history_apply :: proc(editor: ^Editor, entry: ^Vehicle_Paint_History_Entry, after: bool) {
    if editor == nil || entry == nil do return
    pixels := vehicle_paint_pixels(editor)
    for change in entry.changes {
        index := int(change.texel) * 4
        color := after ? change.after : change.before
        copy(pixels[index:index + 4], color[:])
    }
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_history_undo :: proc(editor: ^Editor) {
    if editor == nil do return
    layer := vehicle_paint_layer_index(editor.aircraft.active)
    entry, ok := vehicle_paint_history_pop(&editor.vehicle_paint_undo[layer])
    if !ok do return
    vehicle_paint_history_apply(editor, &entry, false)
    vehicle_paint_history_push(&editor.vehicle_paint_redo[layer], entry)
}

vehicle_paint_history_redo :: proc(editor: ^Editor) {
    if editor == nil do return
    layer := vehicle_paint_layer_index(editor.aircraft.active)
    entry, ok := vehicle_paint_history_pop(&editor.vehicle_paint_redo[layer])
    if !ok do return
    vehicle_paint_history_apply(editor, &entry, true)
    vehicle_paint_history_push(&editor.vehicle_paint_undo[layer], entry)
}

vehicle_paint_schedule_save :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.vehicle_paint_save_pending = true
    editor.vehicle_paint_save_failed = false
    editor.vehicle_paint_save_due_at = f32(rl.GetTime()) + .65
}

vehicle_paint_process_save :: proc(editor: ^Editor) {
    if editor == nil ||
       !editor.vehicle_paint_save_pending ||
       editor.vehicle_paint_stroke_active ||
       editor.vehicle_paint_tool_drag_active ||
       f32(rl.GetTime()) < editor.vehicle_paint_save_due_at {
        return
    }
    if vehicle_paint_save(editor) {
        editor.vehicle_paint_save_failed = false
    } else {
        editor.vehicle_paint_save_failed = true
        editor.vehicle_paint_save_due_at = f32(rl.GetTime()) + 3
    }
}

vehicle_paint_build_texel_parts :: proc(editor: ^Editor, mesh: ^$Mesh) {
    if editor == nil || mesh == nil do return
    for index in 0 ..< len(editor.vehicle_paint_texel_part) {
        editor.vehicle_paint_texel_part[index] = 0
    }
    for triangle in mesh.triangles[:mesh.triangle_count] {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        min_x := clamp(int(math.floor(f64(min(a.uv[0], b.uv[0], c.uv[0]) * VEHICLE_PAINT_TEXTURE_WIDTH))), 0, VEHICLE_PAINT_TEXTURE_WIDTH - 1)
        max_x := clamp(int(math.ceil(f64(max(a.uv[0], b.uv[0], c.uv[0]) * VEHICLE_PAINT_TEXTURE_WIDTH))), 0, VEHICLE_PAINT_TEXTURE_WIDTH - 1)
        min_y := clamp(int(math.floor(f64(min(a.uv[1], b.uv[1], c.uv[1]) * VEHICLE_PAINT_TEXTURE_HEIGHT))), 0, VEHICLE_PAINT_TEXTURE_HEIGHT - 1)
        max_y := clamp(int(math.ceil(f64(max(a.uv[1], b.uv[1], c.uv[1]) * VEHICLE_PAINT_TEXTURE_HEIGHT))), 0, VEHICLE_PAINT_TEXTURE_HEIGHT - 1)
        uv_a := rl.Vector2{a.uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH, a.uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT}
        uv_b := rl.Vector2{b.uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH, b.uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT}
        uv_c := rl.Vector2{c.uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH, c.uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT}
        for y in min_y ..= max_y {
            for x in min_x ..= max_x {
                _, inside := vehicle_paint_barycentric(uv_a, uv_b, uv_c, {f32(x) + .5, f32(y) + .5})
                if inside {
                    editor.vehicle_paint_texel_part[y * VEHICLE_PAINT_TEXTURE_WIDTH + x] = u8(a.part) + 1
                }
            }
        }
    }
}

vehicle_paint_upload_texture :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.vehicle_paint_texture_dirty = true
}

vehicle_paint_brush_coverage :: proc(distance, hardness: f32) -> f32 {
    if distance > 1 do return 0
    normalized_hardness := clamp(hardness, 0, 1)
    if distance <= normalized_hardness || normalized_hardness >= .999 do return 1
    return clamp(
        1 - (distance - normalized_hardness) / (1 - normalized_hardness),
        0,
        1,
    )
}

vehicle_paint_stamp_texture :: proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part, uv: [2]f32, color: rl.Color) {
    if editor == nil do return
    pixels := vehicle_paint_pixels(editor)
    component := vehicle_paint_component_for_part(part)
    if !editor.vehicle_paint_component_mask[component] do return
    radius := editor.vehicle_paint_brush_radius
    center_x := int(uv[0] * f32(VEHICLE_PAINT_TEXTURE_WIDTH))
    center_y := int(uv[1] * f32(VEHICLE_PAINT_TEXTURE_HEIGHT))
    for y in max(0, center_y - radius) ..< min(VEHICLE_PAINT_TEXTURE_HEIGHT, center_y + radius + 1) {
        for x in max(0, center_x - radius) ..< min(VEHICLE_PAINT_TEXTURE_WIDTH, center_x + radius + 1) {
            dx, dy := x - center_x, y - center_y
            distance := f32(math.sqrt(f64(dx * dx + dy * dy))) / f32(radius)
            if distance > 1 do continue
            if editor.vehicle_paint_texel_part[y * VEHICLE_PAINT_TEXTURE_WIDTH + x] != u8(part) + 1 do continue
            coverage := vehicle_paint_brush_coverage(distance, editor.vehicle_paint_brush_hardness)
            alpha := u8(clamp(coverage * 255, 0, 255))
            index := (y * VEHICLE_PAINT_TEXTURE_WIDTH + x) * 4
            old_alpha := pixels[index + 3]
            if editor.vehicle_paint_erase {
                erase_amount := alpha
                pixels[index + 3] =
                    old_alpha > erase_amount ? old_alpha - erase_amount : 0
                continue
            }
            blend := f32(alpha) / 255
            if old_alpha > 0 {
                blend = max(blend, f32(old_alpha) / 255)
            }
            pixels[index + 0] = u8(
                f32(color.r) * blend + f32(pixels[index + 0]) * (1 - blend),
            )
            pixels[index + 1] = u8(
                f32(color.g) * blend + f32(pixels[index + 1]) * (1 - blend),
            )
            pixels[index + 2] = u8(
                f32(color.b) * blend + f32(pixels[index + 2]) * (1 - blend),
            )
            pixels[index + 3] = max(old_alpha, alpha)
        }
    }
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_set_texel :: proc(pixels: []u8, texel: int, color: rl.Color, alpha: u8 = 255) {
    if texel < 0 || texel >= VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_HEIGHT do return
    index := texel * 4
    pixels[index] = color.r
    pixels[index + 1] = color.g
    pixels[index + 2] = color.b
    pixels[index + 3] = alpha
}

vehicle_paint_seed_texel :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    uv: [2]f32,
) -> (int, bool) {
    if editor == nil do return 0, false
    center_x := clamp(int(uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH), 0, VEHICLE_PAINT_TEXTURE_WIDTH - 1)
    center_y := clamp(int(uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT), 0, VEHICLE_PAINT_TEXTURE_HEIGHT - 1)
    owner := u8(part) + 1
    center := center_y * VEHICLE_PAINT_TEXTURE_WIDTH + center_x
    if editor.vehicle_paint_texel_part[center] == owner do return center, true
    for radius in 1 ..= 4 {
        for y in max(0, center_y - radius) ..= min(VEHICLE_PAINT_TEXTURE_HEIGHT - 1, center_y + radius) {
            for x in max(0, center_x - radius) ..= min(VEHICLE_PAINT_TEXTURE_WIDTH - 1, center_x + radius) {
                texel := y * VEHICLE_PAINT_TEXTURE_WIDTH + x
                if editor.vehicle_paint_texel_part[texel] == owner do return texel, true
            }
        }
    }
    return 0, false
}

vehicle_paint_sample_palette :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    uv: [2]f32,
) -> (int, bool) {
    texel, owned := vehicle_paint_seed_texel(editor, part, uv)
    if !owned do return 0, false
    pixels := vehicle_paint_pixels(editor)
    pixel := texel * 4
    if pixel + 3 >= len(pixels) || pixels[pixel + 3] < 16 do return 0, false

    best_index := 0
    best_distance := 2_000_000_000
    for color, index in VEHICLE_PAINT_COLORS {
        dr := int(pixels[pixel]) - int(color.r)
        dg := int(pixels[pixel + 1]) - int(color.g)
        db := int(pixels[pixel + 2]) - int(color.b)
        distance := dr * dr + dg * dg + db * db
        if distance < best_distance {
            best_distance = distance
            best_index = index
        }
    }
    return best_index, true
}

vehicle_paint_colors_near :: proc(pixels: []u8, a, b: int, tolerance: int) -> bool {
    index_a, index_b := a * 4, b * 4
    for channel in 0 ..< 4 {
        if abs(int(pixels[index_a + channel]) - int(pixels[index_b + channel])) > tolerance do return false
    }
    return true
}

vehicle_paint_connected_texels :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    uv: [2]f32,
    match_seed_color: bool,
) -> [dynamic]int {
    result := make([dynamic]int, 0, 1024, context.temp_allocator)
    seed, found := vehicle_paint_seed_texel(editor, part, uv)
    if !found do return result
    texel_count := VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_HEIGHT
    visited := make([]bool, texel_count, context.temp_allocator)
    queue := make([dynamic]int, 0, 1024, context.temp_allocator)
    append(&queue, seed)
    visited[seed] = true
    owner := u8(part) + 1
    pixels := vehicle_paint_pixels(editor)
    read := 0
    for read < len(queue) {
        texel := queue[read]
        read += 1
        append(&result, texel)
        x, y := texel % VEHICLE_PAINT_TEXTURE_WIDTH, texel / VEHICLE_PAINT_TEXTURE_WIDTH
        neighbors := [4]int {
            x > 0 ? texel - 1 : -1,
            x + 1 < VEHICLE_PAINT_TEXTURE_WIDTH ? texel + 1 : -1,
            y > 0 ? texel - VEHICLE_PAINT_TEXTURE_WIDTH : -1,
            y + 1 < VEHICLE_PAINT_TEXTURE_HEIGHT ? texel + VEHICLE_PAINT_TEXTURE_WIDTH : -1,
        }
        for neighbor in neighbors {
            if neighbor < 0 ||
               visited[neighbor] ||
               editor.vehicle_paint_texel_part[neighbor] != owner {
                continue
            }
            if match_seed_color && !vehicle_paint_colors_near(pixels, seed, neighbor, 20) do continue
            visited[neighbor] = true
            append(&queue, neighbor)
        }
    }
    return result
}

vehicle_paint_bucket :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    uv: [2]f32,
    color: rl.Color,
) {
    pixels := vehicle_paint_pixels(editor)
    for texel in vehicle_paint_connected_texels(editor, part, uv, true) {
        vehicle_paint_set_texel(pixels, texel, color)
    }
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_shape :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    uv: [2]f32,
    color: rl.Color,
) {
    pixels := vehicle_paint_pixels(editor)
    center_x := int(uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH)
    center_y := int(uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT)
    radius := editor.vehicle_paint_brush_radius
    owner := u8(part) + 1
    for y in max(0, center_y - radius) ..= min(VEHICLE_PAINT_TEXTURE_HEIGHT - 1, center_y + radius) {
        for x in max(0, center_x - radius) ..= min(VEHICLE_PAINT_TEXTURE_WIDTH - 1, center_x + radius) {
            // A hard-edged diamond reads clearly as a shape rather than a
            // pressure-softened brush dab.
            if abs(x - center_x) + abs(y - center_y) > radius do continue
            texel := y * VEHICLE_PAINT_TEXTURE_WIDTH + x
            if editor.vehicle_paint_texel_part[texel] == owner {
                vehicle_paint_set_texel(pixels, texel, color)
            }
        }
    }
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_blend :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    uv: [2]f32,
) {
    pixels := vehicle_paint_pixels(editor)
    center_x := int(uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH)
    center_y := int(uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT)
    radius := editor.vehicle_paint_brush_radius
    owner := u8(part) + 1
    updates := make([dynamic]Vehicle_Paint_History_Change, 0, radius * radius * 2, context.temp_allocator)
    for y in max(0, center_y - radius) ..= min(VEHICLE_PAINT_TEXTURE_HEIGHT - 1, center_y + radius) {
        for x in max(0, center_x - radius) ..= min(VEHICLE_PAINT_TEXTURE_WIDTH - 1, center_x + radius) {
            dx, dy := x - center_x, y - center_y
            distance := f32(math.sqrt(f64(dx * dx + dy * dy)))
            if distance > f32(radius) do continue
            texel := y * VEHICLE_PAINT_TEXTURE_WIDTH + x
            if editor.vehicle_paint_texel_part[texel] != owner do continue
            sum: [4]int
            count := 0
            for sample_y in max(0, y - 1) ..= min(VEHICLE_PAINT_TEXTURE_HEIGHT - 1, y + 1) {
                for sample_x in max(0, x - 1) ..= min(VEHICLE_PAINT_TEXTURE_WIDTH - 1, x + 1) {
                    sample := sample_y * VEHICLE_PAINT_TEXTURE_WIDTH + sample_x
                    if editor.vehicle_paint_texel_part[sample] != owner do continue
                    index := sample * 4
                    for channel in 0 ..< 4 do sum[channel] += int(pixels[index + channel])
                    count += 1
                }
            }
            if count == 0 do continue
            index := texel * 4
            before := [4]u8{pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3]}
            strength := (1 - distance / f32(radius)) * .45
            after: [4]u8
            for channel in 0 ..< 4 {
                average := f32(sum[channel]) / f32(count)
                after[channel] = u8(clamp(f32(before[channel]) + (average - f32(before[channel])) * strength, 0, 255))
            }
            append(
                &updates,
                Vehicle_Paint_History_Change{texel = u32(texel), before = before, after = after},
            )
        }
    }
    for update in updates {
        index := int(update.texel) * 4
        for channel in 0 ..< 4 do pixels[index + channel] = update.after[channel]
    }
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_gradient_texels :: proc(
    editor: ^Editor,
    texels: []int,
    start_uv, end_uv: [2]f32,
    primary, secondary: rl.Color,
) {
    delta := [2]f32 {
        (end_uv[0] - start_uv[0]) * VEHICLE_PAINT_TEXTURE_WIDTH,
        (end_uv[1] - start_uv[1]) * VEHICLE_PAINT_TEXTURE_HEIGHT,
    }
    length_squared := delta[0] * delta[0] + delta[1] * delta[1]
    if length_squared < 1 do return
    start := [2]f32 {
        start_uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH,
        start_uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT,
    }
    pixels := vehicle_paint_pixels(editor)
    for texel in texels {
        point := [2]f32 {
            f32(texel % VEHICLE_PAINT_TEXTURE_WIDTH) + .5,
            f32(texel / VEHICLE_PAINT_TEXTURE_WIDTH) + .5,
        }
        t := clamp(((point[0] - start[0]) * delta[0] + (point[1] - start[1]) * delta[1]) / length_squared, 0, 1)
        color := rl.Color {
            u8(f32(primary.r) + (f32(secondary.r) - f32(primary.r)) * t),
            u8(f32(primary.g) + (f32(secondary.g) - f32(primary.g)) * t),
            u8(f32(primary.b) + (f32(secondary.b) - f32(primary.b)) * t),
            255,
        }
        vehicle_paint_set_texel(pixels, texel, color)
    }
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_gradient :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    start_uv, end_uv: [2]f32,
    primary, secondary: rl.Color,
) {
    texels := vehicle_paint_connected_texels(editor, part, start_uv, false)
    vehicle_paint_gradient_texels(editor, texels[:], start_uv, end_uv, primary, secondary)
}

vehicle_paint_pattern :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    uv: [2]f32,
    primary, secondary: rl.Color,
) {
    pixels := vehicle_paint_pixels(editor)
    tile_size := max(editor.vehicle_paint_brush_radius, 4)
    for texel in vehicle_paint_connected_texels(editor, part, uv, false) {
        x, y := texel % VEHICLE_PAINT_TEXTURE_WIDTH, texel / VEHICLE_PAINT_TEXTURE_WIDTH
        color := ((x / tile_size) + (y / tile_size)) % 2 == 0 ? primary : secondary
        vehicle_paint_set_texel(pixels, texel, color)
    }
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_strip_texels :: proc(
    editor: ^Editor,
    texels: []int,
    start_uv, end_uv: [2]f32,
    color: rl.Color,
) {
    start := [2]f32 {
        start_uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH,
        start_uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT,
    }
    end := [2]f32 {
        end_uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH,
        end_uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT,
    }
    delta := end - start
    length_squared := delta[0] * delta[0] + delta[1] * delta[1]
    if length_squared < 1 do return
    pixels := vehicle_paint_pixels(editor)
    radius_squared := f32(editor.vehicle_paint_brush_radius * editor.vehicle_paint_brush_radius)
    for texel in texels {
        point := [2]f32 {
            f32(texel % VEHICLE_PAINT_TEXTURE_WIDTH) + .5,
            f32(texel / VEHICLE_PAINT_TEXTURE_WIDTH) + .5,
        }
        t := clamp(((point[0] - start[0]) * delta[0] + (point[1] - start[1]) * delta[1]) / length_squared, 0, 1)
        nearest := start + delta * t
        offset := point - nearest
        if offset[0] * offset[0] + offset[1] * offset[1] <= radius_squared {
            vehicle_paint_set_texel(pixels, texel, color)
        }
    }
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_strip :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    start_uv, end_uv: [2]f32,
    color: rl.Color,
) {
    texels := vehicle_paint_connected_texels(editor, part, start_uv, false)
    vehicle_paint_strip_texels(editor, texels[:], start_uv, end_uv, color)
}

vehicle_paint_close :: proc(editor: ^Editor) {
    if editor == nil do return
    if editor.vehicle_paint_texture_dirty do vehicle_paint_upload_texture(editor)
    if editor.vehicle_paint_save_pending do _ = vehicle_paint_save(editor)
    editor.postale.body.position = editor.vehicle_paint_saved_postale_position
    editor.postale.vehicle.position = {
        x = editor.postale.body.position.x,
        y = editor.postale.body.position.y,
        z = editor.postale.body.position.z,
    }
    editor.libellula.body.position = editor.vehicle_paint_saved_libellula_position
    editor.libellula.vehicle.position = {
        x = editor.libellula.body.position.x,
        y = editor.libellula.body.position.y,
        z = editor.libellula.body.position.z,
    }
    editor.vehicle_paint_scene = false
    editor.vehicle_paint_sound_until = 0
    editor.vehicle_showcase_scene = false
    editor.vehicle_showcase_target = ""
    editor.postale_visible = true
    editor.libellula_visible = true
    editor.in_map = true
    editor.camera = third_person.default_camera()
    editor.camera_pose = third_person.camera_pose(editor.player.position, editor.camera)
    set_pointer_locked(true)
}

vehicle_paint_camera_step :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    mouse := rl.GetMouseDelta()
    stick_x := gamepad_axis(.Right_X)
    stick_y := gamepad_axis(.Right_Y)
    if math.abs(stick_x) > .08 || math.abs(stick_y) > .08 {
        editor.vehicle_paint_yaw -= stick_x * delta_seconds * 2.4
        editor.vehicle_paint_pitch = clamp(editor.vehicle_paint_pitch - stick_y * delta_seconds * 1.8, -.18, .85)
    }
    if rl.IsMouseButtonDown(.RIGHT) || rl.IsMouseButtonDown(.MIDDLE) {
        editor.vehicle_paint_yaw -= mouse.x * .008
        editor.vehicle_paint_pitch = clamp(editor.vehicle_paint_pitch - mouse.y * .006, -.18, .85)
    }
    if rl.IsKeyDown(.J) do editor.vehicle_paint_yaw += delta_seconds * 1.8
    if rl.IsKeyDown(.L) do editor.vehicle_paint_yaw -= delta_seconds * 1.8
    if rl.IsKeyDown(.I) do editor.vehicle_paint_pitch = clamp(editor.vehicle_paint_pitch + delta_seconds * 1.4, -.18, .85)
    if rl.IsKeyDown(.K) do editor.vehicle_paint_pitch = clamp(editor.vehicle_paint_pitch - delta_seconds * 1.4, -.18, .85)
    if rl.IsKeyDown(.Z) do editor.vehicle_paint_distance = max(editor.vehicle_paint_distance - delta_seconds * 2.4, f32(4.2))
    if rl.IsKeyDown(.X) do editor.vehicle_paint_distance = min(editor.vehicle_paint_distance + delta_seconds * 2.4, f32(9.5))
    wheel := rl.GetMouseWheelMove()
    if shift_key_down() && math.abs(wheel) > .01 {
        editor.vehicle_paint_brush_radius = clamp(
            editor.vehicle_paint_brush_radius + int(math.round(f64(wheel * 3))),
            4,
            40,
        )
    } else {
        editor.vehicle_paint_distance = clamp(editor.vehicle_paint_distance - wheel * .38, 4.2, 9.5)
    }
    editor.camera_pose = third_person.camera_pose(
        {y = 1},
        {
            yaw_radians = editor.vehicle_paint_yaw,
            pitch_radians = editor.vehicle_paint_pitch,
            distance = editor.vehicle_paint_distance,
            height = 0,
        },
    )
    _ = delta_seconds
}

vehicle_paint_edge :: proc(a, b, point: rl.Vector2) -> f32 {
    return (point.x - a.x) * (b.y - a.y) - (point.y - a.y) * (b.x - a.x)
}

vehicle_paint_barycentric :: proc(a, b, c, point: rl.Vector2) -> ([3]f32, bool) {
    area := vehicle_paint_edge(a, b, c)
    if math.abs(area) <= .0001 do return {}, false
    weights := [3]f32 {
        vehicle_paint_edge(b, c, point) / area,
        vehicle_paint_edge(c, a, point) / area,
        vehicle_paint_edge(a, b, point) / area,
    }
    return weights, weights[0] >= 0 && weights[1] >= 0 && weights[2] >= 0
}

vehicle_paint_camera_ray :: proc(
    camera: Perspective_Camera,
    mouse: rl.Vector2,
    width, height: i32,
) -> ([3]f32, [3]f32) {
    screen_x := (mouse.x / f32(width) - .5) * 2
    screen_y := (.5 - mouse.y / f32(height)) * 2
    aspect := f32(width) / f32(height)
    direction := vec_normalize({
        x = camera.forward.x +
            camera.right.x * screen_x * aspect / camera.focal_length +
            camera.up.x * screen_y / camera.focal_length,
        y = camera.forward.y +
            camera.right.y * screen_x * aspect / camera.focal_length +
            camera.up.y * screen_y / camera.focal_length,
        z = camera.forward.z +
            camera.right.z * screen_x * aspect / camera.focal_length +
            camera.up.z * screen_y / camera.focal_length,
    })
    return {
        camera.position.x,
        camera.position.y,
        camera.position.z,
    }, {direction.x, direction.y, direction.z}
}

vehicle_paint_ray_triangle :: proc(
    origin, direction, a, b, c: [3]f32,
) -> (bool, f32, f32, f32) {
    edge_ab := b - a
    edge_ac := c - a
    p := [3]f32 {
        direction[1] * edge_ac[2] - direction[2] * edge_ac[1],
        direction[2] * edge_ac[0] - direction[0] * edge_ac[2],
        direction[0] * edge_ac[1] - direction[1] * edge_ac[0],
    }
    determinant := edge_ab[0] * p[0] + edge_ab[1] * p[1] + edge_ab[2] * p[2]
    if math.abs(determinant) < .000001 do return false, 0, 0, 0
    inverse := 1 / determinant
    offset := origin - a
    u := (offset[0] * p[0] + offset[1] * p[1] + offset[2] * p[2]) * inverse
    if u < 0 || u > 1 do return false, 0, 0, 0
    q := [3]f32 {
        offset[1] * edge_ab[2] - offset[2] * edge_ab[1],
        offset[2] * edge_ab[0] - offset[0] * edge_ab[2],
        offset[0] * edge_ab[1] - offset[1] * edge_ab[0],
    }
    v := (direction[0] * q[0] + direction[1] * q[1] + direction[2] * q[2]) * inverse
    if v < 0 || u + v > 1 do return false, 0, 0, 0
    distance := (edge_ac[0] * q[0] + edge_ac[1] * q[1] + edge_ac[2] * q[2]) * inverse
    return distance > .001, distance, u, v
}

vehicle_paint_ray_to_local :: proc(
    origin, direction: [3]f32,
    position: flight.Vec3,
    basis: flight.Basis,
    scale: f32,
) -> ([3]f32, [3]f32) {
    offset := flight.Vec3 {
        origin[0] - position.x,
        origin[1] - position.y,
        origin[2] - position.z,
    }
    ray := flight.Vec3{direction[0], direction[1], direction[2]}
    return {
        flight.dot(offset, basis.right) / scale,
        flight.dot(offset, basis.up) / scale,
        -flight.dot(offset, basis.forward) / scale,
    }, {
        flight.dot(ray, basis.right) / scale,
        flight.dot(ray, basis.up) / scale,
        -flight.dot(ray, basis.forward) / scale,
    }
}

vehicle_paint_projected_hit_libellula :: proc(
    editor: ^Editor,
    width, height: i32,
    mouse: rl.Vector2,
) -> (
    bool,
    [3]f32,
    [3]f32,
    vehicles.Aircraft_Mesh_Part,
    [2]f32,
) {
    camera := perspective_camera(editor.camera_pose, VEHICLE_SHOWCASE_FOCAL_LENGTH)
    origin, direction := vehicle_paint_camera_ray(camera, mouse, width, height)
    origin, direction = vehicle_paint_ray_to_local(
        origin,
        direction,
        editor.libellula.body.position,
        editor.libellula.body.basis,
        LIBELLULA_PRESENTATION_SCALE,
    )
    mesh := &editor.libellula_visual_mesh
    if editor.aircraft.active == .Libellula_Mk2 do mesh = &editor.libellula_mk2_visual_mesh
    best_distance := f32(1.0e30)
    best: [3]f32
    best_normal: [3]f32
    best_part: vehicles.Aircraft_Mesh_Part
    best_uv: [2]f32
    found := false
    for triangle in mesh.triangles[:mesh.triangle_count] {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        normal := vehicle_paint_face_normal(a.position, b.position, c.position)
        hit, distance, u, v := vehicle_paint_ray_triangle(
            origin,
            direction,
            a.position,
            b.position,
            c.position,
        )
        if !hit || distance >= best_distance do continue
        best_distance = distance
        best = a.position * (1 - u - v) + b.position * u + c.position * v
        best_normal = normal
        best_part = a.part
        best_uv = a.uv * (1 - u - v) + b.uv * u + c.uv * v
        found = true
    }
    return found, best, best_normal, best_part, best_uv
}

vehicle_paint_projected_hit :: proc(
    editor: ^Editor,
    width, height: i32,
    mouse: rl.Vector2,
) -> (
    bool,
    [3]f32,
    [3]f32,
    vehicles.Aircraft_Mesh_Part,
    [2]f32,
) {
    if editor.aircraft.active != .Postale {
        return vehicle_paint_projected_hit_libellula(editor, width, height, mouse)
    }
    camera := perspective_camera(editor.camera_pose, VEHICLE_SHOWCASE_FOCAL_LENGTH)
    origin, direction := vehicle_paint_camera_ray(camera, mouse, width, height)
    origin, direction = vehicle_paint_ray_to_local(
        origin,
        direction,
        editor.postale.body.position,
        editor.postale.body.basis,
        POSTALE_PRESENTATION_SCALE,
    )
    mesh := &editor.vehicle_paint_postale_mesh
    best_distance := f32(1.0e30)
    best: [3]f32
    best_normal: [3]f32
    best_part: vehicles.Aircraft_Mesh_Part
    best_uv: [2]f32
    found := false
    for triangle in mesh.triangles[:mesh.triangle_count] {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        if a.part == .Glass || a.part == .Propeller_Blur do continue
        normal := vehicle_paint_face_normal(a.position, b.position, c.position)
        hit, distance, u, v := vehicle_paint_ray_triangle(
            origin,
            direction,
            a.position,
            b.position,
            c.position,
        )
        if !hit || distance >= best_distance do continue
        best_distance = distance
        best = a.position * (1 - u - v) + b.position * u + c.position * v
        best_normal = normal
        best_part = a.part
        best_uv = a.uv * (1 - u - v) + b.uv * u + c.uv * v
        found = true
    }
    return found, best, best_normal, best_part, best_uv
}

vehicle_paint_mirror_part :: proc(part: vehicles.Aircraft_Mesh_Part) -> vehicles.Aircraft_Mesh_Part {
    #partial switch part {
    case .Left_Flap:
        return .Right_Flap
    case .Right_Flap:
        return .Left_Flap
    case .Left_Aileron:
        return .Right_Aileron
    case .Right_Aileron:
        return .Left_Aileron
    case .Left_Propeller:
        return .Right_Propeller
    case .Right_Propeller:
        return .Left_Propeller
    case .Left_Rotor:
        return .Right_Rotor
    case .Right_Rotor:
        return .Left_Rotor
    }
    return part
}

vehicle_paint_dot3 :: proc(a, b: [3]f32) -> f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

vehicle_paint_closest_triangle_weights :: proc(
    point, a, b, c: [3]f32,
) -> ([3]f32, [3]f32) {
    ab, ac, ap := b - a, c - a, point - a
    d1, d2 := vehicle_paint_dot3(ab, ap), vehicle_paint_dot3(ac, ap)
    if d1 <= 0 && d2 <= 0 do return a, {1, 0, 0}
    bp := point - b
    d3, d4 := vehicle_paint_dot3(ab, bp), vehicle_paint_dot3(ac, bp)
    if d3 >= 0 && d4 <= d3 do return b, {0, 1, 0}
    vc := d1 * d4 - d3 * d2
    if vc <= 0 && d1 >= 0 && d3 <= 0 {
        v := d1 / (d1 - d3)
        return a + ab * v, {1 - v, v, 0}
    }
    cp := point - c
    d5, d6 := vehicle_paint_dot3(ab, cp), vehicle_paint_dot3(ac, cp)
    if d6 >= 0 && d5 <= d6 do return c, {0, 0, 1}
    vb := d5 * d2 - d1 * d6
    if vb <= 0 && d2 >= 0 && d6 <= 0 {
        w := d2 / (d2 - d6)
        return a + ac * w, {1 - w, 0, w}
    }
    va := d3 * d6 - d5 * d4
    if va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0 {
        w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return b + (c - b) * w, {0, 1 - w, w}
    }
    denominator := 1 / (va + vb + vc)
    v, w := vb * denominator, vc * denominator
    return a + ab * v + ac * w, {1 - v - w, v, w}
}

vehicle_paint_mirror_uv_mesh :: proc(
    mesh: ^$Mesh,
    position: [3]f32,
    part: vehicles.Aircraft_Mesh_Part,
) -> (bool, vehicles.Aircraft_Mesh_Part, [2]f32) {
    if mesh == nil do return false, part, {}
    mirrored := position
    mirrored[0] = -mirrored[0]
    target_part := vehicle_paint_mirror_part(part)
    best_distance_squared := f32(1.0e30)
    best_uv: [2]f32
    for triangle in mesh.triangles[:mesh.triangle_count] {
        a := mesh.vertices[triangle.a]
        if a.part != target_part do continue
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        closest, weights := vehicle_paint_closest_triangle_weights(
            mirrored,
            a.position,
            b.position,
            c.position,
        )
        offset := closest - mirrored
        distance_squared := vehicle_paint_dot3(offset, offset)
        if distance_squared < best_distance_squared {
            best_distance_squared = distance_squared
            best_uv = a.uv * weights[0] + b.uv * weights[1] + c.uv * weights[2]
        }
    }
    // A missing or genuinely asymmetric counterpart should not spray paint
    // onto the nearest unrelated surface.
    return best_distance_squared <= .25, target_part, best_uv
}

vehicle_paint_mirror_uv :: proc(
    editor: ^Editor,
    position: [3]f32,
    part: vehicles.Aircraft_Mesh_Part,
) -> (bool, vehicles.Aircraft_Mesh_Part, [2]f32) {
    if editor == nil || !editor.vehicle_paint_symmetry do return false, part, {}
    if editor.aircraft.active == .Postale {
        return vehicle_paint_mirror_uv_mesh(&editor.vehicle_paint_postale_mesh, position, part)
    }
    if editor.aircraft.active == .Libellula_Mk2 {
        return vehicle_paint_mirror_uv_mesh(&editor.libellula_mk2_visual_mesh, position, part)
    }
    return vehicle_paint_mirror_uv_mesh(&editor.libellula_visual_mesh, position, part)
}

vehicle_paint_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil || !editor.vehicle_paint_scene do return
    palette := VEHICLE_PAINT_COLORS
    vehicle_paint_camera_step(editor, delta_seconds)
    vehicle_paint_process_save(editor)
    controller := rl.GamepadAvailable()
    if controller {
        editor.vehicle_paint_cursor_x = clamp(
            editor.vehicle_paint_cursor_x + gamepad_axis(.Left_X) * delta_seconds * 420,
            8,
            f32(width - 8),
        )
        editor.vehicle_paint_cursor_y = clamp(
            editor.vehicle_paint_cursor_y + gamepad_axis(.Left_Y) * delta_seconds * 420,
            8,
            f32(height - 8),
        )
    } else {
        mouse := rl.GetMousePosition()
        editor.vehicle_paint_cursor_x = mouse.x
        editor.vehicle_paint_cursor_y = mouse.y
    }
    if rl.IsKeyDown(.LEFT) do editor.vehicle_paint_cursor_x -= delta_seconds * 420
    if rl.IsKeyDown(.RIGHT) do editor.vehicle_paint_cursor_x += delta_seconds * 420
    if rl.IsKeyDown(.UP) do editor.vehicle_paint_cursor_y -= delta_seconds * 420
    if rl.IsKeyDown(.DOWN) do editor.vehicle_paint_cursor_y += delta_seconds * 420
    editor.vehicle_paint_cursor_x = clamp(editor.vehicle_paint_cursor_x, 8, f32(width - 8))
    editor.vehicle_paint_cursor_y = clamp(editor.vehicle_paint_cursor_y, 8, f32(height - 8))
    if rl.IsKeyPressed(.TAB) do editor.vehicle_paint_panel_visible = !editor.vehicle_paint_panel_visible
    if input_action_pressed(.Menu_Cancel) || rl.IsKeyPressed(.ESCAPE) {
        vehicle_paint_close(editor)
        return
    }
    if rl.IsKeyPressed(.ONE) do editor.vehicle_paint_color = 0
    if rl.IsKeyPressed(.TWO) do editor.vehicle_paint_color = 1
    if rl.IsKeyPressed(.THREE) do editor.vehicle_paint_color = 2
    if rl.IsKeyPressed(.FOUR) do editor.vehicle_paint_color = 3
    if rl.IsKeyPressed(.P) do editor.vehicle_paint_color = 4
    if rl.IsKeyPressed(.U) do editor.vehicle_paint_brush_radius = max(4, editor.vehicle_paint_brush_radius - 3)
    if rl.IsKeyPressed(.O) do editor.vehicle_paint_brush_radius = min(40, editor.vehicle_paint_brush_radius + 3)
    if rl.IsKeyPressed(.H) {
        editor.vehicle_paint_brush_hardness += .25
        if editor.vehicle_paint_brush_hardness > 1 do editor.vehicle_paint_brush_hardness = .25
    }
    if rl.IsKeyPressed(.B) {
        editor.vehicle_paint_erase = !editor.vehicle_paint_erase
        if editor.vehicle_paint_erase do editor.vehicle_paint_tool = .Brush
    }
    if rl.IsKeyPressed(.S) do editor.vehicle_paint_symmetry = !editor.vehicle_paint_symmetry
    if control_key_down() && rl.IsKeyPressed(.Z) {
        if shift_key_down() {
            vehicle_paint_history_redo(editor)
        } else {
            vehicle_paint_history_undo(editor)
        }
        if editor.vehicle_paint_save_pending do vehicle_paint_schedule_save(editor)
    }
    if control_key_down() && rl.IsKeyPressed(.Y) {
        vehicle_paint_history_redo(editor)
        if editor.vehicle_paint_save_pending do vehicle_paint_schedule_save(editor)
    }
    if rl.IsKeyPressed(.Q) do vehicle_paint_component_mask_activate(editor, 0, shift_key_down())
    if rl.IsKeyPressed(.W) do vehicle_paint_component_mask_activate(editor, 1, shift_key_down())
    if rl.IsKeyPressed(.E) do vehicle_paint_component_mask_activate(editor, 2, shift_key_down())
    if rl.IsKeyPressed(.R) do vehicle_paint_component_mask_activate(editor, 3, shift_key_down())
    if rl.IsKeyPressed(.T) do vehicle_paint_component_mask_activate(editor, 4, shift_key_down())
    if gamepad_pressed(.Dpad_Left) do editor.vehicle_paint_color = (editor.vehicle_paint_color + len(VEHICLE_PAINT_COLORS) - 1) % len(VEHICLE_PAINT_COLORS)
    if gamepad_pressed(.Dpad_Right) do editor.vehicle_paint_color = (editor.vehicle_paint_color + 1) % len(VEHICLE_PAINT_COLORS)
    if gamepad_pressed(.Dpad_Up) do editor.vehicle_paint_component = (editor.vehicle_paint_component + 4) % 5
    if gamepad_pressed(.Dpad_Down) do editor.vehicle_paint_component = (editor.vehicle_paint_component + 1) % 5
    if gamepad_pressed(.Left_Shoulder) do editor.vehicle_paint_component_mask[editor.vehicle_paint_component] = !editor.vehicle_paint_component_mask[editor.vehicle_paint_component]
    if gamepad_pressed(.Right_Shoulder) {
        editor.vehicle_paint_tool = Vehicle_Paint_Tool(
            (int(editor.vehicle_paint_tool) + 1) % len(VEHICLE_PAINT_TOOL_NAMES),
        )
        editor.vehicle_paint_erase = false
    }
    if gamepad_pressed(.North) {
        editor.vehicle_paint_erase = !editor.vehicle_paint_erase
        if editor.vehicle_paint_erase do editor.vehicle_paint_tool = .Brush
    }
    if gamepad_pressed(.West) do editor.vehicle_paint_symmetry = !editor.vehicle_paint_symmetry
    mouse := rl.Vector2{editor.vehicle_paint_cursor_x, editor.vehicle_paint_cursor_y}
    hit, hover_position, _, hover_part, hover_uv := vehicle_paint_projected_hit(editor, width, height, mouse)
    editor.vehicle_paint_hover_component = vehicle_paint_component_for_part(hover_part)
    editor.vehicle_paint_hover_hit =
        hit &&
        editor.vehicle_paint_component_mask[editor.vehicle_paint_hover_component]
    mirror_hit, mirror_part, mirror_uv := vehicle_paint_mirror_uv(editor, hover_position, hover_part)
    if mirror_hit {
        mirror_hit = editor.vehicle_paint_component_mask[vehicle_paint_component_for_part(mirror_part)]
    }
    if alt_key_down() && rl.IsMouseButtonPressed(.LEFT) {
        if editor.vehicle_paint_hover_hit {
            if sampled_color, sampled := vehicle_paint_sample_palette(editor, hover_part, hover_uv); sampled {
                editor.vehicle_paint_color = sampled_color
                editor.vehicle_paint_erase = false
            }
        }
        return
    }

    paint_down := rl.IsMouseButtonDown(.LEFT) || rl.IsKeyDown(.ENTER) || rl.IsKeyDown(.SPACE) || gamepad_down(.South)
    paint_pressed :=
        rl.IsMouseButtonPressed(.LEFT) ||
        rl.IsKeyPressed(.ENTER) ||
        rl.IsKeyPressed(.SPACE) ||
        gamepad_pressed(.South)
    if paint_pressed &&
       rl.IsMouseButtonPressed(.LEFT) &&
       editor.vehicle_paint_clear_confirm_until > 0 &&
       !rl.CheckCollisionPointRec(mouse, {262, 423, 60, 28}) {
        editor.vehicle_paint_clear_confirm_until = 0
    }
    if paint_down {
        if editor.vehicle_paint_panel_visible &&
           paint_pressed &&
           rl.IsMouseButtonPressed(.LEFT) {
            for index in 0 ..< len(VEHICLE_PAINT_COMPONENT_NAMES) {
                bounds := rl.Rectangle{42 + f32(index % 3) * 104, 349 + f32(index / 3) * 34, 96, 30}
                if rl.CheckCollisionPointRec(mouse, bounds) {
                    vehicle_paint_component_mask_activate(editor, index, shift_key_down())
                    return
                }
            }
        }
        if editor.vehicle_paint_panel_visible {
            for index in 0 ..< len(VEHICLE_PAINT_COLORS) {
                bounds := rl.Rectangle{42 + f32(index % 8) * 34, 136 + f32(index / 8) * 34, 28, 28}
                if rl.CheckCollisionPointRec(mouse, bounds) {
                    if shift_key_down() {
                        editor.vehicle_paint_secondary_color = index
                    } else {
                        editor.vehicle_paint_color = index
                        editor.vehicle_paint_erase = false
                    }
                    return
                }
            }
        }
        if editor.vehicle_paint_panel_visible &&
           paint_pressed &&
           rl.IsMouseButtonPressed(.LEFT) {
            symmetry_bounds := rl.Rectangle{252, 201, 112, 20}
            if rl.CheckCollisionPointRec(mouse, symmetry_bounds) {
                editor.vehicle_paint_symmetry = !editor.vehicle_paint_symmetry
                return
            }
            for index in 0 ..< len(VEHICLE_PAINT_TOOL_NAMES) {
                bounds := rl.Rectangle{42 + f32(index % 3) * 104, 224 + f32(index / 3) * 34, 96, 30}
                if rl.CheckCollisionPointRec(mouse, bounds) {
                    editor.vehicle_paint_tool = Vehicle_Paint_Tool(index)
                    editor.vehicle_paint_erase = false
                    return
                }
            }
            undo_bounds := rl.Rectangle{42, 423, 62, 28}
            redo_bounds := rl.Rectangle{112, 423, 62, 28}
            erase_bounds := rl.Rectangle{182, 423, 72, 28}
            clear_bounds := rl.Rectangle{262, 423, 60, 28}
            if rl.CheckCollisionPointRec(mouse, undo_bounds) {
                vehicle_paint_history_undo(editor)
                if editor.vehicle_paint_save_pending do vehicle_paint_schedule_save(editor)
                return
            }
            if rl.CheckCollisionPointRec(mouse, redo_bounds) {
                vehicle_paint_history_redo(editor)
                if editor.vehicle_paint_save_pending do vehicle_paint_schedule_save(editor)
                return
            }
            if rl.CheckCollisionPointRec(mouse, erase_bounds) {
                editor.vehicle_paint_erase = !editor.vehicle_paint_erase
                if editor.vehicle_paint_erase do editor.vehicle_paint_tool = .Brush
                return
            }
            if rl.CheckCollisionPointRec(mouse, clear_bounds) {
                if vehicle_paint_clear_confirm(editor, f32(rl.GetTime())) {
                    vehicle_paint_history_capture(editor)
                    vehicle_paint_clear_texture(editor)
                    editor.vehicle_paint_texture_dirty = true
                    _ = vehicle_paint_history_commit(editor)
                    vehicle_paint_schedule_save(editor)
                }
                return
            }
            if rl.CheckCollisionPointRec(mouse, {24, 22, 360, 470}) do return
        }
        if editor.vehicle_paint_hover_hit {
            primary := palette[editor.vehicle_paint_color]
            secondary := palette[editor.vehicle_paint_secondary_color]
            #partial switch editor.vehicle_paint_tool {
            case .Bucket:
                if paint_pressed {
                    vehicle_paint_history_capture(editor)
                    vehicle_paint_bucket(editor, hover_part, hover_uv, primary)
                    if mirror_hit do vehicle_paint_bucket(editor, mirror_part, mirror_uv, primary)
                    if vehicle_paint_history_commit(editor) do vehicle_paint_schedule_save(editor)
                    vehicle_paint_sound_pulse(editor, .14)
                }
            case .Shape:
                if paint_pressed {
                    vehicle_paint_history_capture(editor)
                    vehicle_paint_shape(editor, hover_part, hover_uv, primary)
                    if mirror_hit do vehicle_paint_shape(editor, mirror_part, mirror_uv, primary)
                    if vehicle_paint_history_commit(editor) do vehicle_paint_schedule_save(editor)
                    vehicle_paint_sound_pulse(editor, .14)
                }
            case .Pattern:
                if paint_pressed {
                    vehicle_paint_history_capture(editor)
                    vehicle_paint_pattern(editor, hover_part, hover_uv, primary, secondary)
                    if mirror_hit {
                        vehicle_paint_pattern(editor, mirror_part, mirror_uv, primary, secondary)
                    }
                    if vehicle_paint_history_commit(editor) do vehicle_paint_schedule_save(editor)
                    vehicle_paint_sound_pulse(editor, .14)
                }
            case .Gradient, .Strip:
                if paint_pressed {
                    vehicle_paint_history_capture(editor)
                    editor.vehicle_paint_tool_drag_active = true
                    editor.vehicle_paint_tool_drag_start_uv = hover_uv
                    editor.vehicle_paint_tool_drag_start_screen = mouse
                    editor.vehicle_paint_tool_drag_part = hover_part
                    clear(&editor.vehicle_paint_tool_drag_texels)
                    drag_texels := vehicle_paint_connected_texels(editor, hover_part, hover_uv, false)
                    append(&editor.vehicle_paint_tool_drag_texels, ..drag_texels[:])
                    editor.vehicle_paint_tool_drag_mirror_valid = mirror_hit
                    editor.vehicle_paint_tool_drag_mirror_start_uv = mirror_uv
                    editor.vehicle_paint_tool_drag_mirror_part = mirror_part
                    clear(&editor.vehicle_paint_tool_drag_mirror_texels)
                    if mirror_hit {
                        mirror_texels := vehicle_paint_connected_texels(editor, mirror_part, mirror_uv, false)
                        append(&editor.vehicle_paint_tool_drag_mirror_texels, ..mirror_texels[:])
                    }
                    editor.vehicle_paint_component = editor.vehicle_paint_hover_component
                }
                if editor.vehicle_paint_tool_drag_active &&
                   editor.vehicle_paint_tool_drag_part == hover_part {
                    vehicle_paint_sound_pulse(editor)
                    copy(vehicle_paint_pixels(editor), editor.vehicle_paint_history_pixels[:])
                    if editor.vehicle_paint_tool == .Gradient {
                        vehicle_paint_gradient_texels(
                            editor,
                            editor.vehicle_paint_tool_drag_texels[:],
                            editor.vehicle_paint_tool_drag_start_uv,
                            hover_uv,
                            primary,
                            secondary,
                        )
                    } else {
                        vehicle_paint_strip_texels(
                            editor,
                            editor.vehicle_paint_tool_drag_texels[:],
                            editor.vehicle_paint_tool_drag_start_uv,
                            hover_uv,
                            primary,
                        )
                    }
                    if editor.vehicle_paint_tool_drag_mirror_valid &&
                       mirror_hit &&
                       editor.vehicle_paint_tool_drag_mirror_part == mirror_part {
                        if editor.vehicle_paint_tool == .Gradient {
                            vehicle_paint_gradient_texels(
                                editor,
                                editor.vehicle_paint_tool_drag_mirror_texels[:],
                                editor.vehicle_paint_tool_drag_mirror_start_uv,
                                mirror_uv,
                                primary,
                                secondary,
                            )
                        } else {
                            vehicle_paint_strip_texels(
                                editor,
                                editor.vehicle_paint_tool_drag_mirror_texels[:],
                                editor.vehicle_paint_tool_drag_mirror_start_uv,
                                mirror_uv,
                                primary,
                            )
                        }
                    }
                }
            case .Brush, .Blend:
                vehicle_paint_sound_pulse(editor)
                if !editor.vehicle_paint_stroke_active {
                    vehicle_paint_history_capture(editor)
                    editor.vehicle_paint_component = editor.vehicle_paint_hover_component
                    editor.vehicle_paint_stroke_active = true
                    editor.vehicle_paint_stroke_uv_valid = false
                    editor.vehicle_paint_stroke_mirror_valid = false
                }
                if editor.vehicle_paint_stroke_uv_valid &&
                   editor.vehicle_paint_stroke_part == hover_part {
                    delta_uv := hover_uv - editor.vehicle_paint_stroke_uv
                    pixel_distance := f32(math.sqrt(
                        f64(
                            delta_uv[0] * delta_uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_WIDTH +
                            delta_uv[1] * delta_uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT * VEHICLE_PAINT_TEXTURE_HEIGHT,
                        ),
                    ))
                    if pixel_distance < f32(editor.vehicle_paint_brush_radius * 6) {
                        steps := clamp(
                            int(math.ceil(f64(pixel_distance / max(f32(editor.vehicle_paint_brush_radius) * .35, 1)))),
                            1,
                            32,
                        )
                        for step in 1 ..= steps {
                            fraction := f32(step) / f32(steps)
                            dab_uv := editor.vehicle_paint_stroke_uv + delta_uv * fraction
                            if editor.vehicle_paint_tool == .Blend {
                                vehicle_paint_blend(editor, hover_part, dab_uv)
                            } else {
                                vehicle_paint_stamp_texture(editor, hover_part, dab_uv, primary)
                            }
                        }
                    } else if editor.vehicle_paint_tool == .Blend {
                        vehicle_paint_blend(editor, hover_part, hover_uv)
                    } else {
                        vehicle_paint_stamp_texture(editor, hover_part, hover_uv, primary)
                    }
                } else if editor.vehicle_paint_tool == .Blend {
                    vehicle_paint_blend(editor, hover_part, hover_uv)
                } else {
                    vehicle_paint_stamp_texture(editor, hover_part, hover_uv, primary)
                }
                editor.vehicle_paint_stroke_uv = hover_uv
                editor.vehicle_paint_stroke_part = hover_part
                editor.vehicle_paint_stroke_uv_valid = true
                if mirror_hit {
                    if editor.vehicle_paint_stroke_mirror_valid &&
                       editor.vehicle_paint_stroke_mirror_part == mirror_part {
                        mirror_delta := mirror_uv - editor.vehicle_paint_stroke_mirror_uv
                        mirror_distance := f32(math.sqrt(
                            f64(
                                mirror_delta[0] * mirror_delta[0] * VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_WIDTH +
                                mirror_delta[1] * mirror_delta[1] * VEHICLE_PAINT_TEXTURE_HEIGHT * VEHICLE_PAINT_TEXTURE_HEIGHT,
                            ),
                        ))
                        mirror_steps := clamp(
                            int(math.ceil(f64(mirror_distance / max(f32(editor.vehicle_paint_brush_radius) * .35, 1)))),
                            1,
                            32,
                        )
                        if mirror_distance < f32(editor.vehicle_paint_brush_radius * 6) {
                            for step in 1 ..= mirror_steps {
                                fraction := f32(step) / f32(mirror_steps)
                                dab_uv := editor.vehicle_paint_stroke_mirror_uv + mirror_delta * fraction
                                if editor.vehicle_paint_tool == .Blend {
                                    vehicle_paint_blend(editor, mirror_part, dab_uv)
                                } else {
                                    vehicle_paint_stamp_texture(editor, mirror_part, dab_uv, primary)
                                }
                            }
                        } else if editor.vehicle_paint_tool == .Blend {
                            vehicle_paint_blend(editor, mirror_part, mirror_uv)
                        } else {
                            vehicle_paint_stamp_texture(editor, mirror_part, mirror_uv, primary)
                        }
                    } else if editor.vehicle_paint_tool == .Blend {
                        vehicle_paint_blend(editor, mirror_part, mirror_uv)
                    } else {
                        vehicle_paint_stamp_texture(editor, mirror_part, mirror_uv, primary)
                    }
                    editor.vehicle_paint_stroke_mirror_uv = mirror_uv
                    editor.vehicle_paint_stroke_mirror_part = mirror_part
                    editor.vehicle_paint_stroke_mirror_valid = true
                } else {
                    editor.vehicle_paint_stroke_mirror_valid = false
                }
            }
        }
    }
    if !paint_down {
        committed := false
        if editor.vehicle_paint_stroke_active || editor.vehicle_paint_tool_drag_active {
            committed = vehicle_paint_history_commit(editor)
        }
        if committed do vehicle_paint_schedule_save(editor)
        editor.vehicle_paint_stroke_active = false
        editor.vehicle_paint_stroke_uv_valid = false
        editor.vehicle_paint_stroke_mirror_valid = false
        editor.vehicle_paint_tool_drag_active = false
        clear(&editor.vehicle_paint_tool_drag_texels)
        editor.vehicle_paint_tool_drag_mirror_valid = false
        clear(&editor.vehicle_paint_tool_drag_mirror_texels)
    }
}

vehicle_paint_draw_icon :: proc(
    editor: ^Editor,
    icon_index: int,
    destination: rl.Rectangle,
    tint: rl.Color = {255, 255, 255, 255},
) {
    if editor == nil ||
       !editor.vehicle_paint_tool_icons.ready ||
       icon_index < 0 ||
       icon_index >= 12 {
        return
    }
    atlas_width := f32(editor.vehicle_paint_tool_icons.width) / 2
    cell_width := atlas_width / 4
    cell_height := f32(editor.vehicle_paint_tool_icons.height) / 3
    row := f32(icon_index / 4)
    source := rl.Rectangle {
        atlas_width + f32(icon_index % 4) * cell_width,
        row * cell_height,
        cell_width,
        cell_height,
    }
    rl.DrawTexturePro(editor.vehicle_paint_tool_icons, source, destination, tint)
}

vehicle_paint_draw_circle_outline :: proc(center: rl.Vector2, radius, thickness: f32, color: rl.Color) {
    if radius <= 0 do return
    previous := rl.Vector2{center.x + radius, center.y}
    for segment in 1 ..= 24 {
        angle := f64(segment) / 24 * math.PI * 2
        point := rl.Vector2{
            center.x + radius * f32(math.cos(angle)),
            center.y + radius * f32(math.sin(angle)),
        }
        rl.DrawLineEx(previous, point, thickness, color)
        previous = point
    }
}

vehicle_paint_draw :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil || !editor.vehicle_paint_scene do return
    palette := VEHICLE_PAINT_COLORS
    tool_names := VEHICLE_PAINT_TOOL_NAMES
    overlay_alpha: u8 = editor.vehicle_paint_panel_visible ? 178 : 80
    rl.DrawRectangle(0, 0, width, height, {7, 15, 20, overlay_alpha})
    if editor.vehicle_paint_panel_visible {
    rl.DrawRectangleRounded({24, 22, 360, 470}, .08, 8, {15, 31, 38, 238})
    rl.DrawTextEx(rl.Font{}, "ALTOBERTO'S PAINT HANGAR", {42, 38}, 20, 1, {224, 245, 238, 255})
    rl.DrawTextEx(
        rl.Font{},
        "LMB paint   RMB orbit   wheel zoom   TAB canvas   ESC leave",
        {42, 70},
        11,
        1,
        {164, 203, 205, 255},
    )
    rl.DrawTextEx(rl.Font{}, "1-4 / P pigment   SHIFT+wheel size   H hardness   B erase   S symmetry", {42, 94}, 9, 1, {209, 190, 137, 255})
    rl.DrawTextEx(rl.Font{}, "ALT+click sample   SHIFT+color secondary   Q-W-E-R-T masks", {42, 116}, 10, 1, {209, 190, 137, 255})
    for index in 0 ..< len(VEHICLE_PAINT_COLORS) {
        bounds := rl.Rectangle{42 + f32(index % 8) * 34, 136 + f32(index / 8) * 34, 28, 28}
        rl.DrawRectangleRounded(bounds, .25, 5, palette[index])
        if index == editor.vehicle_paint_color {
            rl.DrawRectangleRoundedLinesEx(bounds, .25, 5, 3, {248, 245, 214, 255})
        }
        if index == editor.vehicle_paint_secondary_color {
            secondary_bounds := rl.Rectangle{bounds.x + 4, bounds.y + 4, bounds.width - 8, bounds.height - 8}
            rl.DrawRectangleRoundedLinesEx(secondary_bounds, .22, 5, 2, {70, 32, 44, 255})
        }
    }
    active_tool_label := fmt.ctprintf("TOOLS — %s", tool_names[int(editor.vehicle_paint_tool)])
    if editor.vehicle_paint_erase do active_tool_label = "TOOLS — ERASER"
    rl.DrawTextEx(rl.Font{}, active_tool_label, {42, 207}, 12, 1, {255, 245, 193, 255})
    symmetry_bounds := rl.Rectangle{252, 201, 112, 20}
    symmetry_fill := editor.vehicle_paint_symmetry ? rl.Color{46, 104, 94, 245} : rl.Color{29, 61, 65, 225}
    rl.DrawRectangleRounded(symmetry_bounds, .12, 6, symmetry_fill)
    rl.DrawRectangleRoundedLinesEx(
        symmetry_bounds,
        .12,
        6,
        editor.vehicle_paint_symmetry ? 2 : 1,
        editor.vehicle_paint_symmetry ? rl.Color{255, 245, 193, 255} : rl.Color{91, 143, 139, 255},
    )
    vehicle_paint_draw_icon(editor, 10, {symmetry_bounds.x + 4, symmetry_bounds.y + 1, 18, 18})
    rl.DrawTextEx(rl.Font{}, "SYMMETRY", {symmetry_bounds.x + 26, symmetry_bounds.y + 5}, 9, 1, {236, 243, 224, 255})
    for index in 0 ..< len(VEHICLE_PAINT_TOOL_NAMES) {
        bounds := rl.Rectangle{42 + f32(index % 3) * 104, 224 + f32(index / 3) * 34, 96, 30}
        selected := int(editor.vehicle_paint_tool) == index && !editor.vehicle_paint_erase
        fill := selected ? rl.Color{46, 104, 94, 245} : rl.Color{29, 61, 65, 225}
        border := selected ? rl.Color{255, 245, 193, 255} : rl.Color{91, 143, 139, 255}
        rl.DrawRectangleRounded(bounds, .12, 6, fill)
        rl.DrawRectangleRoundedLinesEx(bounds, .12, 6, selected ? 2 : 1, border)
        tool_name := fmt.ctprintf("%s", tool_names[index])
        vehicle_paint_draw_icon(editor, index, {bounds.x + 5, bounds.y + 4, 22, 22})
        rl.DrawTextEx(
            rl.Font{},
            tool_name,
            {bounds.x + 32, bounds.y + 10},
            9,
            1,
            {236, 243, 224, 255},
        )
    }
    component_names := VEHICLE_PAINT_COMPONENT_NAMES
    rl.DrawTextEx(rl.Font{}, "PAINTABLE PARTS", {42, 332}, 12, 1, {255, 245, 193, 255})
    rl.DrawTextEx(rl.Font{}, "SHIFT SOLO", {156, 333}, 9, 1, {164, 203, 205, 255})
    brush_label := fmt.ctprintf(
        "R%d  H%d%%",
        editor.vehicle_paint_brush_radius,
        int(editor.vehicle_paint_brush_hardness * 100 + .5),
    )
    rl.DrawTextEx(rl.Font{}, brush_label, {274, 332}, 11, 1, {209, 190, 137, 255})
    rl.DrawTextEx(rl.Font{}, "HAND-PAINTED AIRCRAFT", {f32(width) - 280, 32}, 14, 1, {223, 238, 225, 220})
    for index in 0 ..< len(component_names) {
        bounds := rl.Rectangle{42 + f32(index % 3) * 104, 349 + f32(index / 3) * 34, 96, 30}
        enabled := editor.vehicle_paint_component_mask[index]
        focused := index == editor.vehicle_paint_component
        fill := enabled ? rl.Color{30, 81, 78, 230} : rl.Color{35, 43, 47, 230}
        border := focused ? rl.Color{255, 245, 193, 255} : rl.Color{91, 143, 139, 255}
        rl.DrawRectangleRounded(bounds, .12, 6, fill)
        rl.DrawRectangleRoundedLinesEx(bounds, .12, 6, focused ? 2 : 1, border)
        checkbox := rl.Rectangle{bounds.x + 7, bounds.y + 7, 16, 16}
        rl.DrawRectangleRounded(checkbox, .16, 4, enabled ? rl.Color{236, 243, 224, 255} : rl.Color{19, 29, 32, 255})
        rl.DrawRectangleRoundedLinesEx(checkbox, .16, 4, 1, {127, 174, 164, 255})
        if enabled {
            rl.DrawLineEx({checkbox.x + 3, checkbox.y + 8}, {checkbox.x + 7, checkbox.y + 12}, 2, {30, 81, 78, 255})
            rl.DrawLineEx({checkbox.x + 7, checkbox.y + 12}, {checkbox.x + 14, checkbox.y + 4}, 2, {30, 81, 78, 255})
        }
        component_name := fmt.ctprintf("%s", component_names[index])
        rl.DrawTextEx(rl.Font{}, component_name, {bounds.x + 29, bounds.y + 9}, 10, 1, {236, 243, 224, 255})
    }
    layer := vehicle_paint_layer_index(editor.aircraft.active)
    undo_available := len(editor.vehicle_paint_undo[layer]) > 0
    redo_available := len(editor.vehicle_paint_redo[layer]) > 0
    undo_bounds := rl.Rectangle{42, 423, 62, 28}
    redo_bounds := rl.Rectangle{112, 423, 62, 28}
    erase_bounds := rl.Rectangle{182, 423, 72, 28}
    clear_bounds := rl.Rectangle{262, 423, 60, 28}
    clear_armed :=
        editor.vehicle_paint_clear_confirm_until > 0 &&
        f32(rl.GetTime()) <= editor.vehicle_paint_clear_confirm_until
    undo_fill := undo_available ? rl.Color{35, 86, 82, 240} : rl.Color{42, 49, 53, 210}
    rl.DrawRectangleRounded(undo_bounds, .14, 6, undo_fill)
    rl.DrawRectangleRoundedLinesEx(undo_bounds, .14, 6, 1, {103, 153, 146, 255})
    vehicle_paint_draw_icon(editor, 8, {undo_bounds.x + 4, undo_bounds.y + 5, 18, 18})
    rl.DrawTextEx(rl.Font{}, "UNDO", {undo_bounds.x + 25, undo_bounds.y + 9}, 8, 1, {236, 243, 224, 255})
    redo_fill := redo_available ? rl.Color{35, 86, 82, 240} : rl.Color{42, 49, 53, 210}
    rl.DrawRectangleRounded(redo_bounds, .14, 6, redo_fill)
    rl.DrawRectangleRoundedLinesEx(redo_bounds, .14, 6, 1, {103, 153, 146, 255})
    vehicle_paint_draw_icon(editor, 9, {redo_bounds.x + 4, redo_bounds.y + 5, 18, 18})
    rl.DrawTextEx(rl.Font{}, "REDO", {redo_bounds.x + 25, redo_bounds.y + 9}, 8, 1, {236, 243, 224, 255})
    erase_fill := editor.vehicle_paint_erase ? rl.Color{192, 139, 74, 245} : rl.Color{35, 86, 82, 240}
    rl.DrawRectangleRounded(erase_bounds, .14, 6, erase_fill)
    rl.DrawRectangleRoundedLinesEx(erase_bounds, .14, 6, editor.vehicle_paint_erase ? 2 : 1, {224, 192, 128, 255})
    erase_label: cstring = editor.vehicle_paint_erase ? "ERASING" : "ERASER"
    vehicle_paint_draw_icon(editor, 7, {erase_bounds.x + 4, erase_bounds.y + 5, 18, 18})
    rl.DrawTextEx(rl.Font{}, erase_label, {erase_bounds.x + 25, erase_bounds.y + 9}, 8, 1, {255, 242, 211, 255})
    clear_fill := clear_armed ? rl.Color{151, 63, 48, 250} : rl.Color{86, 48, 47, 235}
    clear_border := clear_armed ? rl.Color{255, 211, 139, 255} : rl.Color{174, 103, 91, 255}
    rl.DrawRectangleRounded(clear_bounds, .14, 6, clear_fill)
    rl.DrawRectangleRoundedLinesEx(clear_bounds, .14, 6, clear_armed ? 2 : 1, clear_border)
    vehicle_paint_draw_icon(editor, 11, {clear_bounds.x + 4, clear_bounds.y + 5, 18, 18})
    clear_label: cstring = clear_armed ? "AGAIN" : "CLEAR"
    rl.DrawTextEx(rl.Font{}, clear_label, {clear_bounds.x + 25, clear_bounds.y + 9}, 8, 1, {255, 231, 211, 255})
    save_label: cstring = "SAVED"
    save_color := rl.Color{127, 174, 164, 255}
    if editor.vehicle_paint_save_pending {
        save_label = "SAVING..."
        save_color = {224, 192, 128, 255}
    }
    if editor.vehicle_paint_save_failed {
        save_label = "SAVE ERROR"
        save_color = {239, 119, 103, 255}
    }
    tool_hint: cstring
    #partial switch editor.vehicle_paint_tool {
    case .Brush:
        tool_hint = "DRAG FREEHAND"
    case .Bucket:
        tool_hint = "CLICK CONNECTED REGION"
    case .Shape:
        tool_hint = "CLICK HARD SHAPE"
    case .Blend:
        tool_hint = "DRAG TO SMOOTH"
    case .Gradient:
        tool_hint = "DRAG COLOR DIRECTION"
    case .Pattern:
        tool_hint = "CLICK CONNECTED REGION"
    case .Strip:
        tool_hint = "DRAG STRAIGHT BAND"
    }
    if clear_armed do tool_hint = "CLICK AGAIN TO CLEAR — UNDO AVAILABLE"
    rl.DrawTextEx(rl.Font{}, save_label, {42, 464}, 9, 1, save_color)
    rl.DrawTextEx(rl.Font{}, tool_hint, {132, 464}, 9, 1, {164, 203, 205, 255})
    } else {
        compact_label := fmt.ctprintf(
            "TAB SHOW TOOLS   %s   R%d H%d%%",
            editor.vehicle_paint_erase ? "ERASER" : tool_names[int(editor.vehicle_paint_tool)],
            editor.vehicle_paint_brush_radius,
            int(editor.vehicle_paint_brush_hardness * 100 + .5),
        )
        rl.DrawRectangleRounded({24, 22, 300, 28}, .18, 6, {15, 31, 38, 210})
        rl.DrawTextEx(rl.Font{}, compact_label, {36, 31}, 10, 1, {224, 245, 238, 255})
    }
    {
        cursor := rl.Vector2{editor.vehicle_paint_cursor_x, editor.vehicle_paint_cursor_y}
        cursor_radius := f32(8 + editor.vehicle_paint_brush_radius / 2)
        cursor_color := editor.vehicle_paint_hover_hit ? palette[editor.vehicle_paint_color] : rl.Color{158, 166, 165, 255}
        if editor.vehicle_paint_erase do cursor_color = {255, 226, 174, 255}
        if alt_key_down() && editor.vehicle_paint_hover_hit do cursor_color = {255, 245, 193, 255}
        rl.DrawCircleV(cursor, cursor_radius + 2, {20, 35, 39, 180})
        rl.DrawCircleV(cursor, cursor_radius, {cursor_color.r, cursor_color.g, cursor_color.b, 48})
        if editor.vehicle_paint_tool == .Brush || editor.vehicle_paint_erase {
            hard_radius := cursor_radius * editor.vehicle_paint_brush_hardness
            vehicle_paint_draw_circle_outline(
                cursor,
                hard_radius,
                1,
                {cursor_color.r, cursor_color.g, cursor_color.b, 150},
            )
        }
        rl.DrawCircleV(cursor, 3, cursor_color)
        rl.DrawLineEx({cursor.x - cursor_radius - 7, cursor.y}, {cursor.x - cursor_radius + 1, cursor.y}, 2, cursor_color)
        rl.DrawLineEx({cursor.x + cursor_radius - 1, cursor.y}, {cursor.x + cursor_radius + 7, cursor.y}, 2, cursor_color)
        rl.DrawLineEx({cursor.x, cursor.y - cursor_radius - 7}, {cursor.x, cursor.y - cursor_radius + 1}, 2, cursor_color)
        rl.DrawLineEx({cursor.x, cursor.y + cursor_radius - 1}, {cursor.x, cursor.y + cursor_radius + 7}, 2, cursor_color)
        cursor_label: cstring = "MASKED / NO SURFACE"
        if editor.vehicle_paint_hover_hit {
            cursor_label = fmt.ctprintf("%s", tool_names[int(editor.vehicle_paint_tool)])
            if editor.vehicle_paint_erase do cursor_label = "ERASE"
            if alt_key_down() do cursor_label = "SAMPLE COLOR"
            if editor.vehicle_paint_symmetry && !alt_key_down() {
                cursor_label = fmt.ctprintf("%s  SYM", cursor_label)
            }
        }
        rl.DrawTextEx(rl.Font{}, cursor_label, {cursor.x + cursor_radius + 10, cursor.y + 8}, 11, 1, cursor_color)
        if editor.vehicle_paint_tool_drag_active {
            start := editor.vehicle_paint_tool_drag_start_screen
            direction := rl.Vector2{cursor.x - start.x, cursor.y - start.y}
            length := math.sqrt_f32(direction.x * direction.x + direction.y * direction.y)
            if length > 1 {
                normal := rl.Vector2{-direction.y / length, direction.x / length}
                half_width := editor.vehicle_paint_tool == .Strip ? f32(editor.vehicle_paint_brush_radius) * .35 : 2
                preview_color := rl.Color{cursor_color.r, cursor_color.g, cursor_color.b, 180}
                rl.DrawLineEx(start, cursor, 3, {20, 35, 39, 210})
                rl.DrawLineEx(start, cursor, 1, preview_color)
                if editor.vehicle_paint_tool == .Strip {
                    offset := rl.Vector2{normal.x * half_width, normal.y * half_width}
                    rl.DrawLineEx(
                        {start.x + offset.x, start.y + offset.y},
                        {cursor.x + offset.x, cursor.y + offset.y},
                        1,
                        preview_color,
                    )
                    rl.DrawLineEx(
                        {start.x - offset.x, start.y - offset.y},
                        {cursor.x - offset.x, cursor.y - offset.y},
                        1,
                        preview_color,
                    )
                }
                rl.DrawCircleV(start, 4, preview_color)
            }
        }
    }
}
