package main

import flight "../packages/flight"
import libellula_game "../packages/libellula"
import postale_game "../packages/postale"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import rl "zelda_engine:canvas2d"

VEHICLE_PAINT_TEXTURE_WIDTH :: 2048
VEHICLE_PAINT_TEXTURE_HEIGHT :: 1024
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
    Shade,
}

VEHICLE_PAINT_TOOL_NAMES :: [8]string{"BRUSH", "BUCKET", "SHAPE", "BLEND", "GRADIENT", "PATTERN", "STRIP", "SHADE"}

VEHICLE_PAINT_COMPONENT_NAMES :: [5]string{"BODY", "WINGS", "TAIL", "ENGINE", "FLOATS"}
POSTALE_PAINT_COMPONENT_NAMES :: [5]string{"FUSELAGE", "WINGS", "TAIL", "ENGINE", "GEAR"}

VEHICLE_PAINT_PATTERN_NAMES :: [12]string {
    "CHECK",
    "STRIPE",
    "PIN",
    "DIAG",
    "CROSS",
    "DOTS",
    "SPOTS",
    "DIAMOND",
    "HERRING",
    "WAVES",
    "BRICK",
    "PLAID",
}

VEHICLE_PAINT_SHAPE_NAMES :: [6]string{"DIAM", "CIRCLE", "SQUARE", "TRI", "HEX", "STAR"}

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

@(no_instrumentation)
vehicle_paint_layer_index :: #force_inline proc(kind: vehicles.Aircraft_Kind) -> int {
    return clamp(int(kind), 0, VEHICLE_PAINT_AIRCRAFT_COUNT - 1)
}

vehicle_paint_pixels :: proc(editor: ^Editor) -> []u8 {
    if editor == nil do return nil
    return editor.vehicle_paint_layers[vehicle_paint_layer_index(editor.aircraft.active)][:]
}

vehicle_paint_mark_texture_dirty :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.vehicle_paint_texture_dirty = true
    editor.vehicle_paint_propeller_color_dirty = true
}

vehicle_paint_propeller_color :: proc(editor: ^Editor) -> rl.Color {
    base := rl.Color{54, 43, 35, 255}
    if editor == nil do return base
    if !editor.vehicle_paint_propeller_color_valid || editor.vehicle_paint_propeller_color_dirty {
        if editor.aircraft.active == .Postale && editor.vehicle_paint_postale_mesh.vertex_count == 0 {
            editor.vehicle_paint_postale_mesh = vehicles.postale_mesh()
            vehicle_paint_build_texel_parts(editor, &editor.vehicle_paint_postale_mesh)
        }
        pixels := vehicle_paint_pixels(editor)
        owner := int(u8(vehicles.Aircraft_Mesh_Part.Propeller) + 1)
        red, green, blue, weight: u64
        for value, texel in editor.vehicle_paint_texel_part {
            if u8(value) != u8(owner) do continue
            alpha := u64(pixels[texel * 4 + 3])
            if alpha == 0 do continue
            red += u64(pixels[texel * 4 + 0]) * alpha
            green += u64(pixels[texel * 4 + 1]) * alpha
            blue += u64(pixels[texel * 4 + 2]) * alpha
            weight += alpha
        }
        if weight > 0 {
            base = {u8(red / weight), u8(green / weight), u8(blue / weight), 255}
        }
        editor.vehicle_paint_propeller_color = base
        editor.vehicle_paint_propeller_color_dirty = false
        editor.vehicle_paint_propeller_color_valid = true
    }
    return editor.vehicle_paint_propeller_color
}

vehicle_paint_preview_clear :: proc(editor: ^Editor) {
    if editor == nil do return
    mem.zero_slice(editor.vehicle_paint_preview_pixels[:])
    editor.vehicle_paint_preview_texture_dirty = true
}

vehicle_paint_preview_set :: proc(editor: ^Editor, texel: int, color: rl.Color, alpha: u8) {
    if editor == nil || texel < 0 || texel >= VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_HEIGHT do return
    index := texel * 4
    editor.vehicle_paint_preview_pixels[index] = color.r
    editor.vehicle_paint_preview_pixels[index + 1] = color.g
    editor.vehicle_paint_preview_pixels[index + 2] = color.b
    editor.vehicle_paint_preview_pixels[index + 3] = alpha
}

vehicle_paint_settings_initialize :: proc(editor: ^Editor) {
    if editor == nil || editor.vehicle_paint_settings_initialized do return
    editor.vehicle_paint_color = 0
    editor.vehicle_paint_secondary_color = 13
    editor.vehicle_paint_pattern = 0
    editor.vehicle_paint_pattern_size = 32
    editor.vehicle_paint_pattern_rotation = 0
    editor.vehicle_paint_shape_kind = 0
    editor.vehicle_paint_shape_size = 32
    editor.vehicle_paint_shape_rotation = 0
    editor.vehicle_paint_tool = .Brush
    editor.vehicle_paint_component = 0
    editor.vehicle_paint_component_mask = [5]bool{true, true, true, true, true}
    editor.vehicle_paint_brush_radius = 14
    editor.vehicle_paint_brush_hardness = .75
    editor.vehicle_paint_brush_strength = .75
    editor.vehicle_paint_brush_slider_active = -1
    editor.vehicle_paint_symmetry = false
    editor.vehicle_paint_settings_initialized = true
}

vehicle_paint_open :: proc(editor: ^Editor) {
    if editor == nil do return
    vehicle_paint_settings_initialize(editor)
    copy(editor.vehicle_paint_open_pixels, vehicle_paint_pixels(editor))
    editor.vehicle_paint_scene = true
    editor.vehicle_showcase_scene = true
    editor.vehicle_showcase_target =
        editor.aircraft.active == .Postale ? "postale" : (editor.aircraft.active == .Libellula_Mk2 ? "libellula-mk2" : "libellula")
    editor.vehicle_paint_yaw = -.92
    editor.vehicle_paint_pitch = .24
    editor.vehicle_paint_distance = 6.1
    editor.vehicle_paint_cursor_x = f32(ADRIATIC_WORLD_WIDTH) * .5
    editor.vehicle_paint_cursor_y = f32(ADRIATIC_WORLD_HEIGHT) * .5
    editor.vehicle_paint_orbit_drag_active = false
    editor.vehicle_paint_brush_slider_active = -1
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
    vehicle_paint_preview_clear(editor)
    editor.vehicle_paint_saved_postale_position = editor.postale.body.position
    editor.vehicle_paint_saved_libellula_position = editor.libellula.body.position
    editor.postale_visible = editor.aircraft.active == .Postale
    editor.libellula_visible = editor.aircraft.active != .Postale
    if editor.aircraft.active == .Postale {
        editor.postale.body.position = {0, postale_game.GROUND_CLEARANCE, 0}
        editor.postale.vehicle.position = {
            editor.postale.body.position.x,
            editor.postale.body.position.y,
            editor.postale.body.position.z,
        }
    } else {
        editor.libellula.body.position = {0, libellula_game.GROUND_CLEARANCE, 0}
        editor.libellula.vehicle.position = {
            editor.libellula.body.position.x,
            editor.libellula.body.position.y,
            editor.libellula.body.position.z,
        }
    }
    editor.camera_pose = third_person.camera_pose(
        {0, 1, 0},
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

vehicle_paint_component_names :: proc(editor: ^Editor) -> [5]string {
    if editor != nil && editor.aircraft.active == .Postale {
        return POSTALE_PAINT_COMPONENT_NAMES
    }
    return VEHICLE_PAINT_COMPONENT_NAMES
}

@(no_instrumentation)
vehicle_paint_part_is_paintable :: #force_inline proc(part: vehicles.Aircraft_Mesh_Part) -> bool {
    // Rubber and glass keep their authored materials instead of accepting the
    // vehicle paint atlas.
    return(
        part != .Wheel &&
        part != .Glass &&
        part != .Propeller_Blur &&
        part != .Red_Paint &&
        part != .Marking &&
        part != .Strap \
    )
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
    already_solo := enabled_count == 1 && editor.vehicle_paint_component_mask[index]
    for mask_index in 0 ..< len(editor.vehicle_paint_component_mask) {
        editor.vehicle_paint_component_mask[mask_index] = already_solo || mask_index == index
    }
}

vehicle_paint_face_normal :: proc(a, b, c: [3]f32) -> [3]f32 {
    ab := b - a
    ac := c - a
    normal := linalg.cross(ab, ac)
    length := linalg.length(normal)
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
    if editor.vehicle_paint_clear_confirm_until > 0 && now <= editor.vehicle_paint_clear_confirm_until {
        editor.vehicle_paint_clear_confirm_until = 0
        return true
    }
    editor.vehicle_paint_clear_confirm_until = now + 2.5
    return false
}

vehicle_paint_sound_pulse :: proc(editor: ^Editor, seconds: f32 = .1) {
    if editor == nil do return
    editor.vehicle_paint_sound_until = max(editor.vehicle_paint_sound_until, f32(rl.GetTime()) + max(seconds, .02))
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
    editor.vehicle_paint_open_pixels = make([]u8, VEHICLE_PAINT_TEXTURE_BYTE_COUNT)
    editor.vehicle_paint_tool_drag_texels = make([dynamic]int, 0, 4096)
    editor.vehicle_paint_tool_drag_mirror_texels = make([dynamic]int, 0, 4096)
    for layer in 0 ..< VEHICLE_PAINT_AIRCRAFT_COUNT {
        editor.vehicle_paint_undo[layer] = make(
            [dynamic]Vehicle_Paint_History_Entry,
            0,
            VEHICLE_PAINT_HISTORY_CAPACITY,
        )
        editor.vehicle_paint_redo[layer] = make(
            [dynamic]Vehicle_Paint_History_Entry,
            0,
            VEHICLE_PAINT_HISTORY_CAPACITY,
        )
    }
}

vehicle_paint_history_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    delete(editor.vehicle_paint_open_pixels)
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
) -> (
    Vehicle_Paint_History_Entry,
    bool,
) {
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
        after := [4]u8{pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3]}
        if before != after {
            append(&entry.changes, Vehicle_Paint_History_Change{texel = u32(texel), before = before, after = after})
        }
    }
    if len(entry.changes) == 0 {
        delete(entry.changes)
        return false
    }
    layer := vehicle_paint_layer_index(editor.aircraft.active)
    vehicle_paint_history_entries_clear(&editor.vehicle_paint_redo[layer])
    vehicle_paint_history_push(&editor.vehicle_paint_undo[layer], entry)
    vehicle_paint_mark_texture_dirty(editor)
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
    vehicle_paint_mark_texture_dirty(editor)
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
        if !vehicle_paint_part_is_paintable(a.part) do continue
        min_x := clamp(
            int(math.floor(f64(min(a.uv[0], b.uv[0], c.uv[0]) * VEHICLE_PAINT_TEXTURE_WIDTH))),
            0,
            VEHICLE_PAINT_TEXTURE_WIDTH - 1,
        )
        max_x := clamp(
            int(math.ceil(f64(max(a.uv[0], b.uv[0], c.uv[0]) * VEHICLE_PAINT_TEXTURE_WIDTH))),
            0,
            VEHICLE_PAINT_TEXTURE_WIDTH - 1,
        )
        min_y := clamp(
            int(math.floor(f64(min(a.uv[1], b.uv[1], c.uv[1]) * VEHICLE_PAINT_TEXTURE_HEIGHT))),
            0,
            VEHICLE_PAINT_TEXTURE_HEIGHT - 1,
        )
        max_y := clamp(
            int(math.ceil(f64(max(a.uv[1], b.uv[1], c.uv[1]) * VEHICLE_PAINT_TEXTURE_HEIGHT))),
            0,
            VEHICLE_PAINT_TEXTURE_HEIGHT - 1,
        )
        uv_a := rl.Vector2{a.uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH, a.uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT}
        uv_b := rl.Vector2{b.uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH, b.uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT}
        uv_c := rl.Vector2{c.uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH, c.uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT}
        for y in min_y ..= max_y {
            for x in min_x ..= max_x {
                if vehicle_paint_texel_overlaps_triangle(uv_a, uv_b, uv_c, {f32(x) + .5, f32(y) + .5}) {
                    editor.vehicle_paint_texel_part[y * VEHICLE_PAINT_TEXTURE_WIDTH + x] = u8(a.part) + 1
                }
            }
        }
    }
}

// Conservatively rasterize UV ownership. Testing only the texel center leaves an
// unpaintable half-texel border around every island, which is especially visible
// along narrow and diagonal aircraft edges.
vehicle_paint_texel_overlaps_triangle :: proc(a, b, c, center: rl.Vector2) -> bool {
    area := vehicle_paint_edge(a, b, c)
    if math.abs(area) <= .0001 do return false
    orientation: f32 = area > 0 ? 1 : -1
    vertices := [3]rl.Vector2{a, b, c}
    for index in 0 ..< 3 {
        edge_a := vertices[index]
        edge_b := vertices[(index + 1) % 3]
        edge_value := vehicle_paint_edge(edge_a, edge_b, center) * orientation
        // Maximum edge-function change anywhere in a half-texel square.
        half_texel_extent := .5 * (math.abs(edge_b.x - edge_a.x) + math.abs(edge_b.y - edge_a.y))
        if edge_value < -half_texel_extent do return false
    }
    return true
}

vehicle_paint_upload_texture :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.vehicle_paint_texture_dirty = true
}

vehicle_paint_brush_coverage :: proc(distance, hardness: f32) -> f32 {
    if distance > 1 do return 0
    normalized_hardness := clamp(hardness, 0, 1)
    if distance <= normalized_hardness || normalized_hardness >= .999 do return 1
    return clamp(1 - (distance - normalized_hardness) / (1 - normalized_hardness), 0, 1)
}

vehicle_paint_mix_color :: proc(a, b: rl.Color, amount: f32) -> rl.Color {
    t := clamp(amount, 0, 1)
    return {
        u8(clamp(f32(a.r) + (f32(b.r) - f32(a.r)) * t, 0, 255)),
        u8(clamp(f32(a.g) + (f32(b.g) - f32(a.g)) * t, 0, 255)),
        u8(clamp(f32(a.b) + (f32(b.b) - f32(a.b)) * t, 0, 255)),
        255,
    }
}

// A compact cel-paint ramp: two cool, widely separated shadow values and two
// progressively warmer/desaturated reflections. The asymmetric spacing keeps
// the body color dominant and gives hard-surface forms a strong terminator plus
// a narrow highlight, instead of looking like a generic five-step gradient.
vehicle_paint_shade_ramp :: proc(base: rl.Color) -> [5]rl.Color {
    cool_deep := rl.Color{12, 22, 39, 255}
    cool_shadow := rl.Color{24, 42, 61, 255}
    warm_light := rl.Color{255, 238, 205, 255}
    warm_glint := rl.Color{255, 248, 224, 255}
    return {
        vehicle_paint_mix_color(base, cool_deep, .72),
        vehicle_paint_mix_color(base, cool_shadow, .43),
        {base.r, base.g, base.b, 255},
        vehicle_paint_mix_color(base, warm_light, .30),
        vehicle_paint_mix_color(base, warm_glint, .68),
    }
}

vehicle_paint_shade_step :: proc(pixel: [4]u8, base: rl.Color, lighter: bool) -> (rl.Color, bool) {
    if pixel[3] < 16 do return {}, false
    ramp := vehicle_paint_shade_ramp(base)
    nearest := 0
    nearest_distance := 2_000_000_000
    for color, index in ramp {
        dr := int(pixel[0]) - int(color.r)
        dg := int(pixel[1]) - int(color.g)
        db := int(pixel[2]) - int(color.b)
        distance := dr * dr + dg * dg + db * db
        if distance < nearest_distance {
            nearest = index
            nearest_distance = distance
        }
    }
    // Avoid pulling unrelated liveries into the selected hue family. The
    // tolerance still accepts soft brush/texture filtering residue.
    if nearest_distance > 48 * 48 * 3 do return {}, false
    target := lighter ? min(nearest + 1, len(ramp) - 1) : max(nearest - 1, 0)
    return ramp[target], target != nearest
}

vehicle_paint_shade_texture :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    uv: [2]f32,
    base: rl.Color,
    lighter: bool,
) {
    if editor == nil do return
    pixels := vehicle_paint_pixels(editor)
    component := vehicle_paint_component_for_part(part)
    if !editor.vehicle_paint_component_mask[component] do return
    radius := editor.vehicle_paint_brush_radius
    center_x := int(uv[0] * f32(VEHICLE_PAINT_TEXTURE_WIDTH))
    center_y := int(uv[1] * f32(VEHICLE_PAINT_TEXTURE_HEIGHT))
    owner := u8(part) + 1
    changed := false
    for y in max(0, center_y - radius) ..= min(VEHICLE_PAINT_TEXTURE_HEIGHT - 1, center_y + radius) {
        for x in max(0, center_x - radius) ..= min(VEHICLE_PAINT_TEXTURE_WIDTH - 1, center_x + radius) {
            dx, dy := x - center_x, y - center_y
            distance := f32(math.sqrt(f64(dx * dx + dy * dy))) / f32(radius)
            // Cel shading needs a stable, exact palette edge. Hardness controls
            // that edge; strength intentionally does not create in-between hues.
            if vehicle_paint_brush_coverage(distance, editor.vehicle_paint_brush_hardness) < .5 do continue
            texel := y * VEHICLE_PAINT_TEXTURE_WIDTH + x
            if editor.vehicle_paint_texel_part[texel] != owner do continue
            index := texel * 4
            before := [4]u8{pixels[index], pixels[index + 1], pixels[index + 2], pixels[index + 3]}
            if shade, ok := vehicle_paint_shade_step(before, base, lighter); ok {
                vehicle_paint_set_texel(pixels, texel, shade, before[3])
                changed = true
            }
        }
    }
    if changed {
        vehicle_paint_mark_texture_dirty(editor)
        editor.vehicle_paint_save_pending = true
    }
}

vehicle_paint_stamp_texture :: proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part, uv: [2]f32, color: rl.Color) {
    if editor == nil do return
    pixels := vehicle_paint_pixels(editor)
    component := vehicle_paint_component_for_part(part)
    if !editor.vehicle_paint_component_mask[component] do return
    radius := clamp(editor.vehicle_paint_shape_size, 8, 256) / 2
    center_x := int(uv[0] * f32(VEHICLE_PAINT_TEXTURE_WIDTH))
    center_y := int(uv[1] * f32(VEHICLE_PAINT_TEXTURE_HEIGHT))
    for y in max(0, center_y - radius) ..< min(VEHICLE_PAINT_TEXTURE_HEIGHT, center_y + radius + 1) {
        for x in max(0, center_x - radius) ..< min(VEHICLE_PAINT_TEXTURE_WIDTH, center_x + radius + 1) {
            dx, dy := x - center_x, y - center_y
            distance := f32(math.sqrt(f64(dx * dx + dy * dy))) / f32(radius)
            if distance > 1 do continue
            if editor.vehicle_paint_texel_part[y * VEHICLE_PAINT_TEXTURE_WIDTH + x] != u8(part) + 1 do continue
            coverage := vehicle_paint_brush_coverage(distance, editor.vehicle_paint_brush_hardness)
            strength := clamp(editor.vehicle_paint_brush_strength, 0, 1)
            alpha := u8(clamp(coverage * strength * 255, 0, 255))
            index := (y * VEHICLE_PAINT_TEXTURE_WIDTH + x) * 4
            old_alpha := pixels[index + 3]
            if editor.vehicle_paint_erase {
                erase_amount := alpha
                pixels[index + 3] = old_alpha > erase_amount ? old_alpha - erase_amount : 0
                continue
            }
            blend := f32(alpha) / 255
            pixels[index + 0] = u8(f32(color.r) * blend + f32(pixels[index + 0]) * (1 - blend))
            pixels[index + 1] = u8(f32(color.g) * blend + f32(pixels[index + 1]) * (1 - blend))
            pixels[index + 2] = u8(f32(color.b) * blend + f32(pixels[index + 2]) * (1 - blend))
            pixels[index + 3] = max(old_alpha, alpha)
        }
    }
    vehicle_paint_mark_texture_dirty(editor)
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

vehicle_paint_seed_texel :: proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part, uv: [2]f32) -> (int, bool) {
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

vehicle_paint_sample_palette :: proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part, uv: [2]f32) -> (int, bool) {
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
            if neighbor < 0 || visited[neighbor] || editor.vehicle_paint_texel_part[neighbor] != owner {
                continue
            }
            if match_seed_color && !vehicle_paint_colors_near(pixels, seed, neighbor, 20) do continue
            visited[neighbor] = true
            append(&queue, neighbor)
        }
    }
    return result
}

vehicle_paint_bucket :: proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part, uv: [2]f32, color: rl.Color) {
    if editor == nil do return
    pixels := vehicle_paint_pixels(editor)
    for owner, texel in editor.vehicle_paint_texel_part {
        if owner == 0 do continue
        owned_part := vehicles.Aircraft_Mesh_Part(owner - 1)
        component := vehicle_paint_component_for_part(owned_part)
        if !editor.vehicle_paint_component_mask[component] do continue
        vehicle_paint_set_texel(pixels, texel, color)
    }
    vehicle_paint_mark_texture_dirty(editor)
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_shape :: proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part, uv: [2]f32, color: rl.Color) {
    pixels := vehicle_paint_pixels(editor)
    center_x := int(uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH)
    center_y := int(uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT)
    radius := editor.vehicle_paint_brush_radius
    owner := u8(part) + 1
    for y in max(0, center_y - radius) ..= min(VEHICLE_PAINT_TEXTURE_HEIGHT - 1, center_y + radius) {
        for x in max(0, center_x - radius) ..= min(VEHICLE_PAINT_TEXTURE_WIDTH - 1, center_x + radius) {
            if !vehicle_paint_shape_contains(
                editor.vehicle_paint_shape_kind,
                f32(x - center_x),
                f32(y - center_y),
                f32(radius),
                editor.vehicle_paint_shape_rotation,
            ) {
                continue
            }
            texel := y * VEHICLE_PAINT_TEXTURE_WIDTH + x
            if editor.vehicle_paint_texel_part[texel] == owner {
                vehicle_paint_set_texel(pixels, texel, color)
            }
        }
    }
    vehicle_paint_mark_texture_dirty(editor)
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_shape_contains :: proc(kind: int, x, y, radius: f32, rotation_degrees: f32 = 0) -> bool {
    if radius <= 0 do return false
    radians := -rotation_degrees * f32(math.PI) / 180
    rotation_cos := f32(math.cos(f64(radians)))
    rotation_sin := f32(math.sin(f64(radians)))
    nx := (x * rotation_cos - y * rotation_sin) / radius
    ny := (x * rotation_sin + y * rotation_cos) / radius
    switch kind {
    case 1:
        return nx * nx + ny * ny <= 1
    case 2:
        return math.abs(nx) <= 1 && math.abs(ny) <= 1
    case 3:
        // Upright equilateral triangle.
        return ny >= -.9 && ny <= 1 && math.abs(nx) <= (1 - ny) * .58
    case 4:
        // Flat-topped regular hexagon.
        return math.abs(nx) <= 1 && math.abs(ny) <= .866 && math.abs(nx) * .866 + math.abs(ny) * .5 <= .866
    case 5:
        angle := f32(math.atan2(f64(ny), f64(nx))) + f32(math.PI) * .5
        distance := f32(math.sqrt(f64(nx * nx + ny * ny)))
        spoke := vehicle_paint_pattern_mod(angle, f32(math.PI) * .4)
        spoke_distance := math.abs(spoke - f32(math.PI) * .2)
        boundary := .42 + .58 * math.cos(spoke_distance * 2.5)
        return distance <= boundary
    }
    return math.abs(nx) + math.abs(ny) <= 1
}

vehicle_paint_preview_rebuild :: proc(
    editor: ^Editor,
    part: vehicles.Aircraft_Mesh_Part,
    uv: [2]f32,
    color, secondary: rl.Color,
) {
    vehicle_paint_preview_clear(editor)
    if editor == nil || !editor.vehicle_paint_hover_hit do return
    owner := u8(part) + 1
    center_x := int(uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH)
    center_y := int(uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT)
    #partial switch editor.vehicle_paint_tool {
    case .Brush:
        radius := editor.vehicle_paint_brush_radius
        for y in max(0, center_y - radius) ..= min(VEHICLE_PAINT_TEXTURE_HEIGHT - 1, center_y + radius) {
            for x in max(0, center_x - radius) ..= min(VEHICLE_PAINT_TEXTURE_WIDTH - 1, center_x + radius) {
                texel := y * VEHICLE_PAINT_TEXTURE_WIDTH + x
                if editor.vehicle_paint_texel_part[texel] != owner do continue
                dx, dy := x - center_x, y - center_y
                distance := f32(math.sqrt(f64(dx * dx + dy * dy))) / f32(radius)
                coverage := vehicle_paint_brush_coverage(distance, editor.vehicle_paint_brush_hardness)
                alpha := u8(clamp(coverage * editor.vehicle_paint_brush_strength * 255, 0, 255))
                if alpha > 0 do vehicle_paint_preview_set(editor, texel, color, alpha)
            }
        }
    case .Shape:
        radius := clamp(editor.vehicle_paint_shape_size, 8, 256) / 2
        for y in max(0, center_y - radius) ..= min(VEHICLE_PAINT_TEXTURE_HEIGHT - 1, center_y + radius) {
            for x in max(0, center_x - radius) ..= min(VEHICLE_PAINT_TEXTURE_WIDTH - 1, center_x + radius) {
                texel := y * VEHICLE_PAINT_TEXTURE_WIDTH + x
                if editor.vehicle_paint_texel_part[texel] != owner do continue
                if vehicle_paint_shape_contains(
                    editor.vehicle_paint_shape_kind,
                    f32(x - center_x),
                    f32(y - center_y),
                    f32(radius),
                    editor.vehicle_paint_shape_rotation,
                ) {
                    vehicle_paint_preview_set(editor, texel, color, 180)
                }
            }
        }
    case .Pattern:
        tile_size := f32(clamp(editor.vehicle_paint_pattern_size, 8, 256))
        radians := editor.vehicle_paint_pattern_rotation * f32(math.PI) / 180
        rotation_cos := f32(math.cos(f64(radians)))
        rotation_sin := f32(math.sin(f64(radians)))
        for owned, texel in editor.vehicle_paint_texel_part {
            if owned == 0 do continue
            owned_part := vehicles.Aircraft_Mesh_Part(owned - 1)
            component := vehicle_paint_component_for_part(owned_part)
            if !editor.vehicle_paint_component_mask[component] do continue
            x, y := texel % VEHICLE_PAINT_TEXTURE_WIDTH, texel / VEHICLE_PAINT_TEXTURE_WIDTH
            coverage := vehicle_paint_pattern_coverage(
                editor.vehicle_paint_pattern,
                f32(x) + .5,
                f32(y) + .5,
                tile_size,
                rotation_cos,
                rotation_sin,
            )
            preview_color := rl.Color {
                u8(f32(color.r) + (f32(secondary.r) - f32(color.r)) * coverage),
                u8(f32(color.g) + (f32(secondary.g) - f32(color.g)) * coverage),
                u8(f32(color.b) + (f32(secondary.b) - f32(color.b)) * coverage),
                255,
            }
            vehicle_paint_preview_set(editor, texel, preview_color, 180)
        }
    }
}

vehicle_paint_blend :: proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part, uv: [2]f32) {
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
            append(&updates, Vehicle_Paint_History_Change{texel = u32(texel), before = before, after = after})
        }
    }
    for update in updates {
        index := int(update.texel) * 4
        for channel in 0 ..< 4 do pixels[index + channel] = update.after[channel]
    }
    vehicle_paint_mark_texture_dirty(editor)
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
    start := [2]f32{start_uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH, start_uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT}
    pixels := vehicle_paint_pixels(editor)
    for texel in texels {
        point := [2]f32{f32(texel % VEHICLE_PAINT_TEXTURE_WIDTH) + .5, f32(texel / VEHICLE_PAINT_TEXTURE_WIDTH) + .5}
        t := clamp(((point[0] - start[0]) * delta[0] + (point[1] - start[1]) * delta[1]) / length_squared, 0, 1)
        color := rl.Color {
            u8(f32(primary.r) + (f32(secondary.r) - f32(primary.r)) * t),
            u8(f32(primary.g) + (f32(secondary.g) - f32(primary.g)) * t),
            u8(f32(primary.b) + (f32(secondary.b) - f32(primary.b)) * t),
            255,
        }
        vehicle_paint_set_texel(pixels, texel, color)
    }
    vehicle_paint_mark_texture_dirty(editor)
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
    if editor == nil do return
    pixels := vehicle_paint_pixels(editor)
    tile_size := f32(clamp(editor.vehicle_paint_pattern_size, 8, 256))
    radians := editor.vehicle_paint_pattern_rotation * f32(math.PI) / 180
    rotation_cos := f32(math.cos(f64(radians)))
    rotation_sin := f32(math.sin(f64(radians)))
    for owner, texel in editor.vehicle_paint_texel_part {
        if owner == 0 do continue
        owned_part := vehicles.Aircraft_Mesh_Part(owner - 1)
        component := vehicle_paint_component_for_part(owned_part)
        if !editor.vehicle_paint_component_mask[component] do continue
        x, y := texel % VEHICLE_PAINT_TEXTURE_WIDTH, texel / VEHICLE_PAINT_TEXTURE_WIDTH
        coverage := vehicle_paint_pattern_coverage(
            editor.vehicle_paint_pattern,
            f32(x) + .5,
            f32(y) + .5,
            tile_size,
            rotation_cos,
            rotation_sin,
        )
        color := rl.Color {
            u8(f32(primary.r) + (f32(secondary.r) - f32(primary.r)) * coverage),
            u8(f32(primary.g) + (f32(secondary.g) - f32(primary.g)) * coverage),
            u8(f32(primary.b) + (f32(secondary.b) - f32(primary.b)) * coverage),
            255,
        }
        vehicle_paint_set_texel(pixels, texel, color)
    }
    vehicle_paint_mark_texture_dirty(editor)
    editor.vehicle_paint_save_pending = true
}

vehicle_paint_pattern_mod :: proc(value, divisor: f32) -> f32 {
    return value - f32(math.floor(f64(value / divisor))) * divisor
}

vehicle_paint_pattern_secondary_sample :: proc(pattern: int, x, y, tile: f32) -> bool {
    half := tile * .5
    quarter := tile * .25
    local_x := vehicle_paint_pattern_mod(x, tile)
    local_y := vehicle_paint_pattern_mod(y, tile)
    switch pattern {
    case 1:
        // broad horizontal stripes
        return vehicle_paint_pattern_mod(y, tile) >= half
    case 2:
        // narrow pinstripes
        return local_y < quarter
    case 3:
        // diagonal stripes
        return vehicle_paint_pattern_mod(x + y, tile) >= half
    case 4:
        // crosshatch
        return vehicle_paint_pattern_mod(x + y, tile) < quarter || vehicle_paint_pattern_mod(x - y, tile) < quarter
    case 5:
        // dots
        dx, dy := local_x - half, local_y - half
        return dx * dx + dy * dy <= quarter * quarter
    case 6:
        // large staggered spots
        row := int(math.floor(f64(y / tile)))
        spot_x := vehicle_paint_pattern_mod(x + (row % 2 == 0 ? 0 : half), tile)
        dx, dy := spot_x - half, local_y - half
        radius := tile * .4
        return dx * dx + dy * dy <= radius * radius
    case 7:
        // diamonds
        return math.abs(local_x - half) + math.abs(local_y - half) <= tile / 3
    case 8:
        // herringbone
        block := int(math.floor(f64(x / tile)))
        if block % 2 == 0 do return vehicle_paint_pattern_mod(x + y, tile) < quarter
        return vehicle_paint_pattern_mod(x - y, tile) < quarter
    case 9:
        // waves
        wave_y := vehicle_paint_pattern_mod(y + math.abs(vehicle_paint_pattern_mod(x, tile * 2) - tile) * .5, tile)
        return wave_y < quarter
    case 10:
        // brick
        row := int(math.floor(f64(y / half)))
        mortar_x := vehicle_paint_pattern_mod(x + (row % 2 == 0 ? 0 : half), tile)
        return vehicle_paint_pattern_mod(y, half) < quarter * .5 || mortar_x < quarter * .5
    case 11:
        // plaid
        return local_x < quarter || local_y < quarter || (local_x < half && local_y < half)
    }
    // A tile contains a two-by-two checker repeat. Treating `tile` as the
    // width of one whole square made the nominal checker size twice as large
    // as every other pattern and left nearby samples in the same color.
    checker_size := max(tile * .5, f32(2))
    tile_x := int(math.floor(f64(x / checker_size)))
    tile_y := int(math.floor(f64(y / checker_size)))
    return (tile_x + tile_y) % 2 != 0
}

vehicle_paint_pattern_coverage :: proc(pattern: int, x, y, tile, rotation_cos, rotation_sin: f32) -> f32 {
    coverage: f32
    offsets := [4][2]f32{{-.25, -.25}, {.25, -.25}, {-.25, .25}, {.25, .25}}
    for offset in offsets {
        sample_x, sample_y := x + offset[0], y + offset[1]
        rotated_x := sample_x * rotation_cos + sample_y * rotation_sin
        rotated_y := -sample_x * rotation_sin + sample_y * rotation_cos
        if vehicle_paint_pattern_secondary_sample(pattern, rotated_x, rotated_y, max(tile, 4)) {
            coverage += .25
        }
    }
    return coverage
}

vehicle_paint_pattern_secondary :: proc(pattern, x, y, tile_size: int) -> bool {
    return vehicle_paint_pattern_coverage(pattern, f32(x) + .5, f32(y) + .5, f32(tile_size), 1, 0) >= .5
}

vehicle_paint_pattern_active :: proc(editor: ^Editor) -> bool {
    return editor != nil && editor.vehicle_paint_tool == .Pattern && !editor.vehicle_paint_erase
}

vehicle_paint_shape_active :: proc(editor: ^Editor) -> bool {
    return editor != nil && editor.vehicle_paint_tool == .Shape && !editor.vehicle_paint_erase
}

vehicle_paint_panel_bounds :: proc(editor: ^Editor) -> rl.Rectangle {
    height: f32 = 618
    if vehicle_paint_pattern_active(editor) do height = 700
    if vehicle_paint_shape_active(editor) do height = 686
    return {8, 10, 304, height}
}

vehicle_paint_color_bounds :: proc(index: int) -> rl.Rectangle {
    return {18 + f32(index % 8) * 35, 122 + f32(index / 8) * 34, 30, 28}
}

vehicle_paint_tool_bounds :: proc(index: int) -> rl.Rectangle {
    return {18 + f32(index % 2) * 142, 226 + f32(index / 2) * 38, 134, 34}
}

vehicle_paint_pattern_palette_bounds :: proc() -> rl.Rectangle {
    return {14, 376, 292, 88}
}

vehicle_paint_pattern_swatch_bounds :: proc(index: int) -> rl.Rectangle {
    return {18 + f32(index % 6) * 47, 380 + f32(index / 6) * 31, 42, 28}
}

vehicle_paint_pattern_control_bounds :: proc(index: int) -> rl.Rectangle {
    return {18 + f32(index) * 68, 442, 62, 20}
}

vehicle_paint_shape_bounds :: proc(index: int) -> rl.Rectangle {
    return {18 + f32(index) * 47, 380, 42, 28}
}

vehicle_paint_shape_control_bounds :: proc(index: int) -> rl.Rectangle {
    return {18 + f32(index) * 68, 414, 62, 22}
}

vehicle_paint_brush_slider_bounds :: proc(index: int) -> rl.Rectangle {
    return {326, 22 + f32(index) * 42, 210, 34}
}

vehicle_paint_brush_slider_update :: proc(editor: ^Editor, index: int, mouse_x: f32) {
    if editor == nil || index < 0 || index > 2 do return
    bounds := vehicle_paint_brush_slider_bounds(index)
    normalized := clamp((mouse_x - bounds.x - 10) / (bounds.width - 20), 0, 1)
    switch index {
    case 0:
        editor.vehicle_paint_brush_radius = int(math.round(f64(4 + normalized * 36)))
    case 1:
        editor.vehicle_paint_brush_hardness = .05 + normalized * .95
    case 2:
        editor.vehicle_paint_brush_strength = .05 + normalized * .95
    }
}

vehicle_paint_parts_top :: proc(editor: ^Editor) -> f32 {
    if vehicle_paint_pattern_active(editor) do return 470
    if vehicle_paint_shape_active(editor) do return 450
    return 382
}

vehicle_paint_component_bounds :: proc(editor: ^Editor, index: int) -> rl.Rectangle {
    top := vehicle_paint_parts_top(editor)
    return {18 + f32(index % 2) * 142, top + 22 + f32(index / 2) * 38, 134, 34}
}

vehicle_paint_actions_top :: proc(editor: ^Editor) -> f32 {
    return vehicle_paint_parts_top(editor) + 142
}

vehicle_paint_undo_bounds :: proc(editor: ^Editor) -> rl.Rectangle {
    return {18, vehicle_paint_actions_top(editor), 62, 34}
}

vehicle_paint_redo_bounds :: proc(editor: ^Editor) -> rl.Rectangle {
    return {84, vehicle_paint_actions_top(editor), 62, 34}
}

vehicle_paint_erase_bounds :: proc(editor: ^Editor) -> rl.Rectangle {
    return {150, vehicle_paint_actions_top(editor), 76, 34}
}

vehicle_paint_clear_bounds :: proc(editor: ^Editor) -> rl.Rectangle {
    return {230, vehicle_paint_actions_top(editor), 72, 34}
}

vehicle_paint_save_exit_bounds :: proc(editor: ^Editor) -> rl.Rectangle {
    return {172, vehicle_paint_actions_top(editor) + 42, 130, 32}
}

vehicle_paint_strip_texels :: proc(editor: ^Editor, texels: []int, start_uv, end_uv: [2]f32, color: rl.Color) {
    start := [2]f32{start_uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH, start_uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT}
    end := [2]f32{end_uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH, end_uv[1] * VEHICLE_PAINT_TEXTURE_HEIGHT}
    delta := end - start
    length_squared := delta[0] * delta[0] + delta[1] * delta[1]
    if length_squared < 1 do return
    pixels := vehicle_paint_pixels(editor)
    radius_squared := f32(editor.vehicle_paint_brush_radius * editor.vehicle_paint_brush_radius)
    for texel in texels {
        point := [2]f32{f32(texel % VEHICLE_PAINT_TEXTURE_WIDTH) + .5, f32(texel / VEHICLE_PAINT_TEXTURE_WIDTH) + .5}
        t := clamp(((point[0] - start[0]) * delta[0] + (point[1] - start[1]) * delta[1]) / length_squared, 0, 1)
        nearest := start + delta * t
        offset := point - nearest
        if offset[0] * offset[0] + offset[1] * offset[1] <= radius_squared {
            vehicle_paint_set_texel(pixels, texel, color)
        }
    }
    vehicle_paint_mark_texture_dirty(editor)
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

vehicle_paint_close :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    if editor.vehicle_paint_texture_dirty do vehicle_paint_upload_texture(editor)
    // Closing is an explicit save operation. Do not let the autosave debounce
    // flag decide whether it writes: it can be clear after an earlier autosave
    // or stale while input is transitioning into the pause menu. A successful
    // close must always leave the complete paint atlas on disk.
    if !vehicle_paint_save(editor) {
        editor.vehicle_paint_save_failed = true
        editor.vehicle_paint_save_due_at = f32(rl.GetTime()) + 3
        return false
    }
    editor.vehicle_paint_save_failed = false
    editor.postale.body.position = editor.vehicle_paint_saved_postale_position
    editor.postale.vehicle.position = {
        editor.postale.body.position.x,
        editor.postale.body.position.y,
        editor.postale.body.position.z,
    }
    editor.libellula.body.position = editor.vehicle_paint_saved_libellula_position
    editor.libellula.vehicle.position = {
        editor.libellula.body.position.x,
        editor.libellula.body.position.y,
        editor.libellula.body.position.z,
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
    return true
}

vehicle_paint_discard :: proc(editor: ^Editor) -> bool {
    if editor == nil || len(editor.vehicle_paint_open_pixels) != VEHICLE_PAINT_TEXTURE_BYTE_COUNT do return false
    copy(vehicle_paint_pixels(editor), editor.vehicle_paint_open_pixels)
    vehicle_paint_mark_texture_dirty(editor)
    editor.vehicle_paint_save_pending = true
    return vehicle_paint_close(editor)
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
    if rl.IsMouseButtonDown(.RIGHT) ||
       rl.IsMouseButtonDown(.MIDDLE) ||
       (editor.vehicle_paint_orbit_drag_active && rl.IsMouseButtonDown(.LEFT)) {
        editor.vehicle_paint_yaw -= mouse.x * .008
        editor.vehicle_paint_pitch = clamp(editor.vehicle_paint_pitch - mouse.y * .006, -.18, .85)
    }
    if rl.IsKeyDown(.J) do editor.vehicle_paint_yaw += delta_seconds * 1.8
    if rl.IsKeyDown(.L) do editor.vehicle_paint_yaw -= delta_seconds * 1.8
    if rl.IsKeyDown(.I) do editor.vehicle_paint_pitch = clamp(editor.vehicle_paint_pitch + delta_seconds * 1.4, -.18, .85)
    if rl.IsKeyDown(.K) do editor.vehicle_paint_pitch = clamp(editor.vehicle_paint_pitch - delta_seconds * 1.4, -.18, .85)
    if rl.IsKeyDown(.Z) do editor.vehicle_paint_distance = max(editor.vehicle_paint_distance - delta_seconds * 2.4, f32(4.2))
    if rl.IsKeyDown(.X) do editor.vehicle_paint_distance = min(editor.vehicle_paint_distance + delta_seconds * 2.4, f32(9.5))
    wheel_delta := rl.GetMouseWheelMoveV()
    wheel := wheel_delta.y
    if control_key_down() && math.abs(wheel) > .01 {
        editor.vehicle_paint_brush_strength = clamp(editor.vehicle_paint_brush_strength + wheel * .05, .05, 1)
    } else if (vehicle_paint_pattern_active(editor) || vehicle_paint_shape_active(editor)) &&
       alt_key_down() &&
       math.abs(wheel) > .01 {
        rotation := &editor.vehicle_paint_pattern_rotation
        if vehicle_paint_shape_active(editor) do rotation = &editor.vehicle_paint_shape_rotation
        rotation^ += wheel > 0 ? 15 : -15
        if rotation^ >= 360 do rotation^ -= 360
        if rotation^ < 0 do rotation^ += 360
    } else if shift_key_down() && math.abs(wheel) > .01 {
        if vehicle_paint_pattern_active(editor) {
            editor.vehicle_paint_pattern_size = clamp(
                editor.vehicle_paint_pattern_size + int(math.round(f64(wheel * 8))),
                8,
                256,
            )
        } else if vehicle_paint_shape_active(editor) {
            editor.vehicle_paint_shape_size = clamp(
                editor.vehicle_paint_shape_size + int(math.round(f64(wheel * 8))),
                8,
                256,
            )
        } else {
            editor.vehicle_paint_brush_radius = clamp(
                editor.vehicle_paint_brush_radius + int(math.round(f64(wheel * 3))),
                4,
                40,
            )
        }
    } else if vehicle_paint_touchpad_orbit_gesture(wheel_delta) {
        editor.vehicle_paint_yaw -= wheel_delta.x * .025
        editor.vehicle_paint_pitch = clamp(editor.vehicle_paint_pitch + wheel_delta.y * .02, -.18, .85)
    } else {
        editor.vehicle_paint_distance = clamp(editor.vehicle_paint_distance - wheel * .38, 4.2, 9.5)
    }
    pinch_scale := rl.GetMousePinchScale()
    if math.abs(pinch_scale - 1) > .001 {
        editor.vehicle_paint_distance = clamp(editor.vehicle_paint_distance / pinch_scale, 4.2, 9.5)
    }
    editor.camera_pose = third_person.camera_pose(
        third_person.Vec3{0, 1, 0},
        {
            yaw_radians = editor.vehicle_paint_yaw,
            pitch_radians = editor.vehicle_paint_pitch,
            distance = editor.vehicle_paint_distance,
            height = 0,
        },
    )
    _ = delta_seconds
}

vehicle_paint_touchpad_orbit_gesture :: proc(delta: rl.Vector2) -> bool {
    if math.abs(delta.x) > .001 do return true
    // Conventional mouse wheels report integral vertical notches. Trackpads
    // supply precise fractional deltas, including their inertial tail.
    return math.abs(delta.y - f32(math.round(f64(delta.y)))) > .001
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
) -> (
    [3]f32,
    [3]f32,
) {
    screen_x := (mouse.x / f32(width) - .5) * 2
    screen_y := (.5 - mouse.y / f32(height)) * 2
    aspect := f32(width) / f32(height)
    direction := linalg.normalize0(
        third_person.Vec3 {
            camera.forward.x +
            camera.right.x * screen_x * aspect / camera.focal_length +
            camera.up.x * screen_y / camera.focal_length,
            camera.forward.y +
            camera.right.y * screen_x * aspect / camera.focal_length +
            camera.up.y * screen_y / camera.focal_length,
            camera.forward.z +
            camera.right.z * screen_x * aspect / camera.focal_length +
            camera.up.z * screen_y / camera.focal_length,
        },
    )
    return {camera.position.x, camera.position.y, camera.position.z}, {direction.x, direction.y, direction.z}
}

vehicle_paint_ray_triangle :: proc(origin, direction, a, b, c: [3]f32) -> (bool, f32, f32, f32) {
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
) -> (
    [3]f32,
    [3]f32,
) {
    offset := flight.Vec3{origin[0] - position.x, origin[1] - position.y, origin[2] - position.z}
    ray := flight.Vec3{direction[0], direction[1], direction[2]}
    return {
        linalg.dot(offset, basis.right) / scale,
        linalg.dot(offset, basis.up) / scale,
        -linalg.dot(offset, basis.forward) / scale,
    }, {linalg.dot(ray, basis.right) / scale, linalg.dot(ray, basis.up) / scale, -linalg.dot(ray, basis.forward) / scale}
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
        flight.basis_from_orientation(editor.libellula.body.orientation),
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
        hit, distance, u, v := vehicle_paint_ray_triangle(origin, direction, a.position, b.position, c.position)
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
        flight.basis_from_orientation(editor.postale.body.orientation),
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
        hit, distance, u, v := vehicle_paint_ray_triangle(origin, direction, a.position, b.position, c.position)
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

vehicle_paint_closest_triangle_weights :: proc(point, a, b, c: [3]f32) -> ([3]f32, [3]f32) {
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
) -> (
    bool,
    vehicles.Aircraft_Mesh_Part,
    [2]f32,
) {
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
        closest, weights := vehicle_paint_closest_triangle_weights(mirrored, a.position, b.position, c.position)
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
) -> (
    bool,
    vehicles.Aircraft_Mesh_Part,
    [2]f32,
) {
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
    if !rl.IsMouseButtonDown(.LEFT) {
        editor.vehicle_paint_orbit_drag_active = false
        editor.vehicle_paint_brush_slider_active = -1
    }
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
        _ = vehicle_paint_close(editor)
        return
    }
    if rl.IsKeyPressed(.ONE) do editor.vehicle_paint_color = 0
    if rl.IsKeyPressed(.TWO) do editor.vehicle_paint_color = 1
    if rl.IsKeyPressed(.THREE) do editor.vehicle_paint_color = 2
    if rl.IsKeyPressed(.FOUR) do editor.vehicle_paint_color = 3
    if rl.IsKeyPressed(.P) do editor.vehicle_paint_color = 4
    if rl.IsKeyPressed(.U) {
        if vehicle_paint_pattern_active(editor) {
            editor.vehicle_paint_pattern_size = max(8, editor.vehicle_paint_pattern_size - 8)
        } else if vehicle_paint_shape_active(editor) {
            editor.vehicle_paint_shape_size = max(8, editor.vehicle_paint_shape_size - 8)
        } else {
            editor.vehicle_paint_brush_radius = max(4, editor.vehicle_paint_brush_radius - 3)
        }
    }
    if rl.IsKeyPressed(.O) {
        if vehicle_paint_pattern_active(editor) {
            editor.vehicle_paint_pattern_size = min(256, editor.vehicle_paint_pattern_size + 8)
        } else if vehicle_paint_shape_active(editor) {
            editor.vehicle_paint_shape_size = min(256, editor.vehicle_paint_shape_size + 8)
        } else {
            editor.vehicle_paint_brush_radius = min(40, editor.vehicle_paint_brush_radius + 3)
        }
    }
    if rl.IsKeyPressed(.H) {
        if vehicle_paint_pattern_active(editor) || vehicle_paint_shape_active(editor) {
            rotation := &editor.vehicle_paint_pattern_rotation
            if vehicle_paint_shape_active(editor) do rotation = &editor.vehicle_paint_shape_rotation
            rotation^ += shift_key_down() ? -15 : 15
            if rotation^ >= 360 do rotation^ -= 360
            if rotation^ < 0 do rotation^ += 360
        } else {
            editor.vehicle_paint_brush_hardness += .25
            if editor.vehicle_paint_brush_hardness > 1 do editor.vehicle_paint_brush_hardness = .25
        }
    }
    if rl.IsKeyPressed(.G) {
        editor.vehicle_paint_brush_strength += .25
        if editor.vehicle_paint_brush_strength > 1 do editor.vehicle_paint_brush_strength = .25
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
    if editor.vehicle_paint_panel_visible && rl.IsMouseButtonPressed(.LEFT) {
        for index in 0 ..< 3 {
            if rl.CheckCollisionPointRec(mouse, vehicle_paint_brush_slider_bounds(index)) {
                editor.vehicle_paint_brush_slider_active = index
                vehicle_paint_brush_slider_update(editor, index, mouse.x)
                return
            }
        }
    }
    if editor.vehicle_paint_brush_slider_active >= 0 && rl.IsMouseButtonDown(.LEFT) {
        vehicle_paint_brush_slider_update(editor, editor.vehicle_paint_brush_slider_active, mouse.x)
        return
    }
    if editor.vehicle_paint_panel_visible && rl.IsMouseButtonPressed(.RIGHT) {
        for index in 0 ..< len(VEHICLE_PAINT_COLORS) {
            bounds := vehicle_paint_color_bounds(index)
            if rl.CheckCollisionPointRec(mouse, bounds) {
                editor.vehicle_paint_secondary_color = index
                return
            }
        }
    }
    hit, hover_position, _, hover_part, hover_uv := vehicle_paint_projected_hit(editor, width, height, mouse)
    editor.vehicle_paint_hover_uv = hover_uv
    editor.vehicle_paint_hover_component = vehicle_paint_component_for_part(hover_part)
    editor.vehicle_paint_hover_hit =
        hit &&
        vehicle_paint_part_is_paintable(hover_part) &&
        editor.vehicle_paint_component_mask[editor.vehicle_paint_hover_component]
    vehicle_paint_preview_rebuild(
        editor,
        hover_part,
        hover_uv,
        palette[editor.vehicle_paint_color],
        palette[editor.vehicle_paint_secondary_color],
    )
    mirror_hit, mirror_part, mirror_uv := vehicle_paint_mirror_uv(editor, hover_position, hover_part)
    if mirror_hit {
        mirror_hit =
            vehicle_paint_part_is_paintable(mirror_part) &&
            editor.vehicle_paint_component_mask[vehicle_paint_component_for_part(mirror_part)]
    }
    if rl.IsMouseButtonPressed(.LEFT) &&
       !hit &&
       (!editor.vehicle_paint_panel_visible || !rl.CheckCollisionPointRec(mouse, vehicle_paint_panel_bounds(editor))) {
        editor.vehicle_paint_orbit_drag_active = true
    }
    if editor.vehicle_paint_orbit_drag_active {
        return
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
        rl.IsMouseButtonPressed(.LEFT) || rl.IsKeyPressed(.ENTER) || rl.IsKeyPressed(.SPACE) || gamepad_pressed(.South)
    if paint_pressed &&
       rl.IsMouseButtonPressed(.LEFT) &&
       editor.vehicle_paint_clear_confirm_until > 0 &&
       !rl.CheckCollisionPointRec(mouse, vehicle_paint_clear_bounds(editor)) {
        editor.vehicle_paint_clear_confirm_until = 0
    }
    if paint_down {
        if editor.vehicle_paint_panel_visible && paint_pressed && rl.IsMouseButtonPressed(.LEFT) {
            for index in 0 ..< len(VEHICLE_PAINT_COMPONENT_NAMES) {
                bounds := vehicle_paint_component_bounds(editor, index)
                if rl.CheckCollisionPointRec(mouse, bounds) {
                    vehicle_paint_component_mask_activate(editor, index, shift_key_down())
                    return
                }
            }
        }
        if editor.vehicle_paint_panel_visible {
            for index in 0 ..< len(VEHICLE_PAINT_COLORS) {
                bounds := vehicle_paint_color_bounds(index)
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
        if editor.vehicle_paint_panel_visible && paint_pressed && rl.IsMouseButtonPressed(.LEFT) {
            if editor.vehicle_paint_tool == .Shape {
                for index in 0 ..< len(VEHICLE_PAINT_SHAPE_NAMES) {
                    if rl.CheckCollisionPointRec(mouse, vehicle_paint_shape_bounds(index)) {
                        editor.vehicle_paint_shape_kind = index
                        return
                    }
                }
                for index in 0 ..< 4 {
                    if !rl.CheckCollisionPointRec(mouse, vehicle_paint_shape_control_bounds(index)) do continue
                    switch index {
                    case 0:
                        editor.vehicle_paint_shape_size = max(8, editor.vehicle_paint_shape_size - 8)
                    case 1:
                        editor.vehicle_paint_shape_size = min(256, editor.vehicle_paint_shape_size + 8)
                    case 2:
                        editor.vehicle_paint_shape_rotation -= 15
                        if editor.vehicle_paint_shape_rotation < 0 do editor.vehicle_paint_shape_rotation += 360
                    case 3:
                        editor.vehicle_paint_shape_rotation += 15
                        if editor.vehicle_paint_shape_rotation >= 360 do editor.vehicle_paint_shape_rotation -= 360
                    }
                    return
                }
            }
            if editor.vehicle_paint_tool == .Pattern {
                for index in 0 ..< len(VEHICLE_PAINT_PATTERN_NAMES) {
                    if rl.CheckCollisionPointRec(mouse, vehicle_paint_pattern_swatch_bounds(index)) {
                        editor.vehicle_paint_pattern = index
                        return
                    }
                }
                for index in 0 ..< 4 {
                    if !rl.CheckCollisionPointRec(mouse, vehicle_paint_pattern_control_bounds(index)) do continue
                    switch index {
                    case 0:
                        editor.vehicle_paint_pattern_size = max(8, editor.vehicle_paint_pattern_size - 8)
                    case 1:
                        editor.vehicle_paint_pattern_size = min(256, editor.vehicle_paint_pattern_size + 8)
                    case 2:
                        editor.vehicle_paint_pattern_rotation -= 15
                        if editor.vehicle_paint_pattern_rotation < 0 do editor.vehicle_paint_pattern_rotation += 360
                    case 3:
                        editor.vehicle_paint_pattern_rotation += 15
                        if editor.vehicle_paint_pattern_rotation >= 360 do editor.vehicle_paint_pattern_rotation -= 360
                    }
                    return
                }
            }
            symmetry_bounds := rl.Rectangle{190, 190, 112, 30}
            if rl.CheckCollisionPointRec(mouse, symmetry_bounds) {
                editor.vehicle_paint_symmetry = !editor.vehicle_paint_symmetry
                return
            }
            for index in 0 ..< len(VEHICLE_PAINT_TOOL_NAMES) {
                bounds := vehicle_paint_tool_bounds(index)
                if rl.CheckCollisionPointRec(mouse, bounds) {
                    editor.vehicle_paint_tool = Vehicle_Paint_Tool(index)
                    editor.vehicle_paint_erase = false
                    return
                }
            }
            undo_bounds := vehicle_paint_undo_bounds(editor)
            redo_bounds := vehicle_paint_redo_bounds(editor)
            erase_bounds := vehicle_paint_erase_bounds(editor)
            clear_bounds := vehicle_paint_clear_bounds(editor)
            save_exit_bounds := vehicle_paint_save_exit_bounds(editor)
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
                    vehicle_paint_mark_texture_dirty(editor)
                    _ = vehicle_paint_history_commit(editor)
                    vehicle_paint_schedule_save(editor)
                }
                return
            }
            if rl.CheckCollisionPointRec(mouse, save_exit_bounds) {
                _ = vehicle_paint_close(editor)
                return
            }
            if rl.CheckCollisionPointRec(mouse, vehicle_paint_panel_bounds(editor)) {
                return
            }
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
                if editor.vehicle_paint_tool_drag_active && editor.vehicle_paint_tool_drag_part == hover_part {
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
            case .Brush, .Shade, .Blend:
                vehicle_paint_sound_pulse(editor)
                if !editor.vehicle_paint_stroke_active {
                    vehicle_paint_history_capture(editor)
                    editor.vehicle_paint_component = editor.vehicle_paint_hover_component
                    editor.vehicle_paint_stroke_active = true
                    editor.vehicle_paint_stroke_uv_valid = false
                    editor.vehicle_paint_stroke_mirror_valid = false
                }
                if editor.vehicle_paint_stroke_uv_valid && editor.vehicle_paint_stroke_part == hover_part {
                    delta_uv := hover_uv - editor.vehicle_paint_stroke_uv
                    pixel_distance := f32(
                        math.sqrt(
                            f64(
                                delta_uv[0] * delta_uv[0] * VEHICLE_PAINT_TEXTURE_WIDTH * VEHICLE_PAINT_TEXTURE_WIDTH +
                                delta_uv[1] *
                                    delta_uv[1] *
                                    VEHICLE_PAINT_TEXTURE_HEIGHT *
                                    VEHICLE_PAINT_TEXTURE_HEIGHT,
                            ),
                        ),
                    )
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
                            } else if editor.vehicle_paint_tool == .Shade {
                                vehicle_paint_shade_texture(editor, hover_part, dab_uv, primary, shift_key_down())
                            } else {
                                vehicle_paint_stamp_texture(editor, hover_part, dab_uv, primary)
                            }
                        }
                    } else if editor.vehicle_paint_tool == .Blend {
                        vehicle_paint_blend(editor, hover_part, hover_uv)
                    } else if editor.vehicle_paint_tool == .Shade {
                        vehicle_paint_shade_texture(editor, hover_part, hover_uv, primary, shift_key_down())
                    } else {
                        vehicle_paint_stamp_texture(editor, hover_part, hover_uv, primary)
                    }
                } else if editor.vehicle_paint_tool == .Blend {
                    vehicle_paint_blend(editor, hover_part, hover_uv)
                } else if editor.vehicle_paint_tool == .Shade {
                    vehicle_paint_shade_texture(editor, hover_part, hover_uv, primary, shift_key_down())
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
                        mirror_distance := f32(
                            math.sqrt(
                                f64(
                                    mirror_delta[0] *
                                        mirror_delta[0] *
                                        VEHICLE_PAINT_TEXTURE_WIDTH *
                                        VEHICLE_PAINT_TEXTURE_WIDTH +
                                    mirror_delta[1] *
                                        mirror_delta[1] *
                                        VEHICLE_PAINT_TEXTURE_HEIGHT *
                                        VEHICLE_PAINT_TEXTURE_HEIGHT,
                                ),
                            ),
                        )
                        mirror_steps := clamp(
                            int(
                                math.ceil(f64(mirror_distance / max(f32(editor.vehicle_paint_brush_radius) * .35, 1))),
                            ),
                            1,
                            32,
                        )
                        if mirror_distance < f32(editor.vehicle_paint_brush_radius * 6) {
                            for step in 1 ..= mirror_steps {
                                fraction := f32(step) / f32(mirror_steps)
                                dab_uv := editor.vehicle_paint_stroke_mirror_uv + mirror_delta * fraction
                                if editor.vehicle_paint_tool == .Blend {
                                    vehicle_paint_blend(editor, mirror_part, dab_uv)
                                } else if editor.vehicle_paint_tool == .Shade {
                                    vehicle_paint_shade_texture(editor, mirror_part, dab_uv, primary, shift_key_down())
                                } else {
                                    vehicle_paint_stamp_texture(editor, mirror_part, dab_uv, primary)
                                }
                            }
                        } else if editor.vehicle_paint_tool == .Blend {
                            vehicle_paint_blend(editor, mirror_part, mirror_uv)
                        } else if editor.vehicle_paint_tool == .Shade {
                            vehicle_paint_shade_texture(editor, mirror_part, mirror_uv, primary, shift_key_down())
                        } else {
                            vehicle_paint_stamp_texture(editor, mirror_part, mirror_uv, primary)
                        }
                    } else if editor.vehicle_paint_tool == .Blend {
                        vehicle_paint_blend(editor, mirror_part, mirror_uv)
                    } else if editor.vehicle_paint_tool == .Shade {
                        vehicle_paint_shade_texture(editor, mirror_part, mirror_uv, primary, shift_key_down())
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
    if editor == nil || !editor.vehicle_paint_tool_icons.ready || icon_index < 0 || icon_index >= 12 {
        return
    }
    atlas_width := f32(editor.vehicle_paint_tool_icons.width) / 2
    cell_width := atlas_width / 4
    cell_height := f32(editor.vehicle_paint_tool_icons.height) / 3
    row := f32(icon_index / 4)
    source := rl.Rectangle{atlas_width + f32(icon_index % 4) * cell_width, row * cell_height, cell_width, cell_height}
    rl.DrawTexturePro(editor.vehicle_paint_tool_icons, source, destination, tint)
}

vehicle_paint_draw_circle_outline :: proc(center: rl.Vector2, radius, thickness: f32, color: rl.Color) {
    if radius <= 0 do return
    previous := rl.Vector2{center.x + radius, center.y}
    for segment in 1 ..= 24 {
        angle := f64(segment) / 24 * math.PI * 2
        point := rl.Vector2{center.x + radius * f32(math.cos(angle)), center.y + radius * f32(math.sin(angle))}
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
        rl.DrawRectangleRounded(vehicle_paint_panel_bounds(editor), .06, 8, {15, 31, 38, 248})
        slider_labels := [3]cstring {
            fmt.ctprintf("RADIUS  %d", editor.vehicle_paint_brush_radius),
            fmt.ctprintf("HARDNESS  %d%%", int(editor.vehicle_paint_brush_hardness * 100 + .5)),
            fmt.ctprintf("STRENGTH  %d%%", int(editor.vehicle_paint_brush_strength * 100 + .5)),
        }
        slider_values := [3]f32 {
            (f32(editor.vehicle_paint_brush_radius) - 4) / 36,
            (editor.vehicle_paint_brush_hardness - .05) / .95,
            (editor.vehicle_paint_brush_strength - .05) / .95,
        }
        for label, index in slider_labels {
            bounds := vehicle_paint_brush_slider_bounds(index)
            active := editor.vehicle_paint_brush_slider_active == index
            rl.DrawRectangleRounded(bounds, .16, 6, {15, 31, 38, 238})
            rl.DrawRectangleRoundedLinesEx(
                bounds,
                .16,
                6,
                active ? 2 : 1,
                active ? rl.Color{255, 245, 193, 255} : rl.Color{91, 143, 139, 255},
            )
            rl.DrawTextEx(rl.Font{}, label, {bounds.x + 10, bounds.y + 5}, 11, 1, {236, 243, 224, 255})
            track := rl.Rectangle{bounds.x + 10, bounds.y + 23, bounds.width - 20, 4}
            rl.DrawRectangleRounded(track, 1, 4, {48, 63, 66, 255})
            value := clamp(slider_values[index], 0, 1)
            filled := track
            filled.width *= value
            rl.DrawRectangleRounded(filled, 1, 4, {70, 164, 137, 255})
            knob_x := track.x + track.width * value
            rl.DrawCircleV(
                {knob_x, track.y + track.height * .5},
                active ? 6 : 5,
                active ? rl.Color{255, 245, 193, 255} : rl.Color{183, 219, 201, 255},
            )
        }
        rl.DrawTextEx(rl.Font{}, "ALTOBERTO'S PAINT HANGAR", {18, 24}, 20, 1, {244, 255, 250, 255})
        rl.DrawTextEx(rl.Font{}, "LMB PAINT   RMB ORBIT   TAB HIDE", {18, 54}, 16, 1, {211, 235, 235, 255})
        rl.DrawTextEx(rl.Font{}, "ESC LEAVE   B ERASE   S SYMMETRY", {18, 76}, 16, 1, {255, 226, 163, 255})
        hint: cstring = "ALT SAMPLE   SHIFT+WHEEL SIZE   H HARD"
        if editor.vehicle_paint_tool == .Shade do hint = "SHADE: LMB DARK   SHIFT+LMB LIGHT"
        rl.DrawTextEx(rl.Font{}, hint, {18, 98}, 16, 1, {255, 226, 163, 255})
        for index in 0 ..< len(VEHICLE_PAINT_COLORS) {
            bounds := vehicle_paint_color_bounds(index)
            if editor.vehicle_paint_tool == .Shade {
                ramp := vehicle_paint_shade_ramp(palette[index])
                shade_width := bounds.width / f32(len(ramp))
                for shade, shade_index in ramp {
                    rl.DrawRectangleRec(
                        {bounds.x + f32(shade_index) * shade_width, bounds.y, shade_width + .25, bounds.height},
                        shade,
                    )
                }
            } else {
                rl.DrawRectangleRounded(bounds, .25, 5, palette[index])
            }
            if index == editor.vehicle_paint_color {
                rl.DrawRectangleRoundedLinesEx(bounds, .25, 5, 3, {248, 245, 214, 255})
            }
            if index == editor.vehicle_paint_secondary_color {
                secondary_bounds := rl.Rectangle{bounds.x + 4, bounds.y + 4, bounds.width - 8, bounds.height - 8}
                rl.DrawRectangleRoundedLinesEx(secondary_bounds, .22, 5, 2, {70, 32, 44, 255})
            }
        }
        symmetry_bounds := rl.Rectangle{190, 190, 112, 30}
        symmetry_fill := rl.Color{29, 61, 65, 225}
        rl.DrawRectangleRounded(symmetry_bounds, .18, 6, symmetry_fill)
        rl.DrawRectangleRoundedLinesEx(symmetry_bounds, .18, 6, 1, {91, 143, 139, 255})
        rl.DrawTextEx(
            rl.Font{},
            "SYMMETRY",
            {symmetry_bounds.x + 8, symmetry_bounds.y + 8},
            12,
            1,
            {246, 252, 240, 255},
        )
        toggle_bounds := rl.Rectangle{symmetry_bounds.x + 67, symmetry_bounds.y + 7, 36, 16}
        toggle_fill := editor.vehicle_paint_symmetry ? rl.Color{70, 164, 137, 255} : rl.Color{48, 63, 66, 255}
        rl.DrawRectangleRounded(toggle_bounds, 1, 8, toggle_fill)
        rl.DrawRectangleRoundedLinesEx(toggle_bounds, 1, 8, 1, {127, 174, 164, 255})
        knob_x := editor.vehicle_paint_symmetry ? toggle_bounds.x + toggle_bounds.width - 9 : toggle_bounds.x + 9
        rl.DrawCircleV(
            {knob_x, toggle_bounds.y + toggle_bounds.height * .5},
            6,
            editor.vehicle_paint_symmetry ? rl.Color{255, 245, 193, 255} : rl.Color{183, 199, 192, 255},
        )
        for index in 0 ..< len(VEHICLE_PAINT_TOOL_NAMES) {
            bounds := vehicle_paint_tool_bounds(index)
            selected := int(editor.vehicle_paint_tool) == index && !editor.vehicle_paint_erase
            fill := selected ? rl.Color{46, 104, 94, 245} : rl.Color{29, 61, 65, 225}
            border := selected ? rl.Color{255, 245, 193, 255} : rl.Color{91, 143, 139, 255}
            rl.DrawRectangleRounded(bounds, .12, 6, fill)
            rl.DrawRectangleRoundedLinesEx(bounds, .12, 6, selected ? 2 : 1, border)
            tool_name := fmt.ctprintf("%s", tool_names[index])
            if Vehicle_Paint_Tool(index) == .Shade {
                ramp := vehicle_paint_shade_ramp(palette[editor.vehicle_paint_color])
                for shade, shade_index in ramp {
                    rl.DrawRectangle(i32(bounds.x + 6 + f32(shade_index) * 5), i32(bounds.y + 7), 5, 22, shade)
                }
            } else {
                vehicle_paint_draw_icon(editor, index, {bounds.x + 6, bounds.y + 6, 24, 24})
            }
            rl.DrawTextEx(rl.Font{}, tool_name, {bounds.x + 36, bounds.y + 9}, 16, 1, {236, 243, 224, 255})
        }
        if editor.vehicle_paint_tool == .Pattern && !editor.vehicle_paint_erase {
            pattern_panel := vehicle_paint_pattern_palette_bounds()
            pattern_names := VEHICLE_PAINT_PATTERN_NAMES
            rl.DrawRectangleRounded(pattern_panel, .06, 8, {15, 31, 38, 248})
            rl.DrawRectangleRoundedLinesEx(pattern_panel, .06, 8, 1, {91, 143, 139, 255})
            primary := palette[editor.vehicle_paint_color]
            secondary := palette[editor.vehicle_paint_secondary_color]
            radians := editor.vehicle_paint_pattern_rotation * f32(math.PI) / 180
            preview_cos := f32(math.cos(f64(radians)))
            preview_sin := f32(math.sin(f64(radians)))
            for index in 0 ..< len(VEHICLE_PAINT_PATTERN_NAMES) {
                bounds := vehicle_paint_pattern_swatch_bounds(index)
                selected := editor.vehicle_paint_pattern == index
                rl.DrawRectangleRounded(bounds, .10, 5, {29, 61, 65, 245})
                preview := rl.Rectangle{bounds.x + 3, bounds.y + 2, bounds.width - 6, 13}
                rl.DrawRectangleRec(preview, primary)
                cell_width := preview.width / 16
                cell_height := preview.height / 6
                for sample_y in 0 ..< 6 {
                    for sample_x in 0 ..< 16 {
                        coverage := vehicle_paint_pattern_coverage(
                            index,
                            f32(sample_x) * 2,
                            f32(sample_y) * 2,
                            8,
                            preview_cos,
                            preview_sin,
                        )
                        color := rl.Color {
                            u8(f32(primary.r) + (f32(secondary.r) - f32(primary.r)) * coverage),
                            u8(f32(primary.g) + (f32(secondary.g) - f32(primary.g)) * coverage),
                            u8(f32(primary.b) + (f32(secondary.b) - f32(primary.b)) * coverage),
                            255,
                        }
                        rl.DrawRectangleRec(
                            {
                                preview.x + f32(sample_x) * cell_width,
                                preview.y + f32(sample_y) * cell_height,
                                cell_width + .25,
                                cell_height + .25,
                            },
                            color,
                        )
                    }
                }
                border := selected ? rl.Color{255, 245, 193, 255} : rl.Color{91, 143, 139, 255}
                rl.DrawRectangleRoundedLinesEx(bounds, .10, 5, selected ? 3 : 1, border)
                name := fmt.ctprintf("%s", pattern_names[index])
                rl.DrawTextEx(rl.Font{}, name, {bounds.x + 3, bounds.y + 18}, 7, 1, {236, 243, 224, 255})
            }
            control_labels := [4]cstring {
                fmt.ctprintf("SIZE -"),
                fmt.ctprintf("+  %d", editor.vehicle_paint_pattern_size),
                fmt.ctprintf("ROT -"),
                fmt.ctprintf("+  %d°", int(editor.vehicle_paint_pattern_rotation)),
            }
            for label, index in control_labels {
                bounds := vehicle_paint_pattern_control_bounds(index)
                rl.DrawRectangleRounded(bounds, .15, 5, {29, 61, 65, 245})
                rl.DrawRectangleRoundedLinesEx(bounds, .15, 5, 1, {91, 143, 139, 255})
                rl.DrawTextEx(rl.Font{}, label, {bounds.x + 5, bounds.y + 6}, 10, 1, {236, 243, 224, 255})
            }
        }
        if editor.vehicle_paint_tool == .Shape && !editor.vehicle_paint_erase {
            for name, index in VEHICLE_PAINT_SHAPE_NAMES {
                bounds := vehicle_paint_shape_bounds(index)
                selected := editor.vehicle_paint_shape_kind == index
                fill := selected ? rl.Color{46, 104, 94, 245} : rl.Color{29, 61, 65, 225}
                border := selected ? rl.Color{255, 245, 193, 255} : rl.Color{91, 143, 139, 255}
                rl.DrawRectangleRounded(bounds, .12, 5, fill)
                rl.DrawRectangleRoundedLinesEx(bounds, .12, 5, selected ? 2 : 1, border)
                label := fmt.ctprintf("%s", name)
                rl.DrawTextEx(rl.Font{}, label, {bounds.x + 3, bounds.y + 9}, 8, 1, {236, 243, 224, 255})
            }
            control_labels := [4]cstring {
                fmt.ctprintf("SIZE -"),
                fmt.ctprintf("+  %d", editor.vehicle_paint_shape_size),
                fmt.ctprintf("ROT -"),
                fmt.ctprintf("+  %d°", int(editor.vehicle_paint_shape_rotation)),
            }
            for label, index in control_labels {
                bounds := vehicle_paint_shape_control_bounds(index)
                rl.DrawRectangleRounded(bounds, .15, 5, {29, 61, 65, 245})
                rl.DrawRectangleRoundedLinesEx(bounds, .15, 5, 1, {91, 143, 139, 255})
                rl.DrawTextEx(rl.Font{}, label, {bounds.x + 5, bounds.y + 6}, 10, 1, {236, 243, 224, 255})
            }
        }
        component_names := vehicle_paint_component_names(editor)
        parts_top := vehicle_paint_parts_top(editor)
        rl.DrawTextEx(rl.Font{}, "PAINTABLE PARTS", {18, parts_top}, 16, 1, {255, 245, 193, 255})
        rl.DrawTextEx(rl.Font{}, "SHIFT = SOLO", {168, parts_top}, 14, 1, {211, 235, 235, 255})
        brush_label := fmt.ctprintf(
            "R%d H%d%% S%d%%",
            editor.vehicle_paint_brush_radius,
            int(editor.vehicle_paint_brush_hardness * 100 + .5),
            int(editor.vehicle_paint_brush_strength * 100 + .5),
        )
        rl.DrawTextEx(rl.Font{}, brush_label, {176, parts_top - 19}, 13, 1, {255, 226, 163, 255})
        for index in 0 ..< len(component_names) {
            bounds := vehicle_paint_component_bounds(editor, index)
            enabled := editor.vehicle_paint_component_mask[index]
            focused := index == editor.vehicle_paint_component
            fill := enabled ? rl.Color{30, 81, 78, 230} : rl.Color{35, 43, 47, 230}
            border := focused ? rl.Color{255, 245, 193, 255} : rl.Color{91, 143, 139, 255}
            rl.DrawRectangleRounded(bounds, .12, 6, fill)
            rl.DrawRectangleRoundedLinesEx(bounds, .12, 6, focused ? 2 : 1, border)
            checkbox := rl.Rectangle{bounds.x + 7, bounds.y + 7, 22, 22}
            rl.DrawRectangleRounded(
                checkbox,
                .16,
                4,
                enabled ? rl.Color{236, 243, 224, 255} : rl.Color{19, 29, 32, 255},
            )
            rl.DrawRectangleRoundedLinesEx(checkbox, .16, 4, 1, {127, 174, 164, 255})
            if enabled {
                rl.DrawLineEx(
                    {checkbox.x + 4, checkbox.y + 11},
                    {checkbox.x + 9, checkbox.y + 16},
                    3,
                    {30, 81, 78, 255},
                )
                rl.DrawLineEx(
                    {checkbox.x + 9, checkbox.y + 16},
                    {checkbox.x + 19, checkbox.y + 5},
                    3,
                    {30, 81, 78, 255},
                )
            }
            component_name := fmt.ctprintf("%s", component_names[index])
            rl.DrawTextEx(rl.Font{}, component_name, {bounds.x + 36, bounds.y + 9}, 16, 1, {246, 252, 240, 255})
        }
        layer := vehicle_paint_layer_index(editor.aircraft.active)
        undo_available := len(editor.vehicle_paint_undo[layer]) > 0
        redo_available := len(editor.vehicle_paint_redo[layer]) > 0
        undo_bounds := vehicle_paint_undo_bounds(editor)
        redo_bounds := vehicle_paint_redo_bounds(editor)
        erase_bounds := vehicle_paint_erase_bounds(editor)
        clear_bounds := vehicle_paint_clear_bounds(editor)
        clear_armed :=
            editor.vehicle_paint_clear_confirm_until > 0 &&
            f32(rl.GetTime()) <= editor.vehicle_paint_clear_confirm_until
        undo_fill := undo_available ? rl.Color{35, 86, 82, 240} : rl.Color{42, 49, 53, 210}
        rl.DrawRectangleRounded(undo_bounds, .14, 6, undo_fill)
        rl.DrawRectangleRoundedLinesEx(undo_bounds, .14, 6, 1, {103, 153, 146, 255})
        vehicle_paint_draw_icon(editor, 8, {undo_bounds.x + 4, undo_bounds.y + 7, 22, 22})
        rl.DrawTextEx(rl.Font{}, "UNDO", {undo_bounds.x + 27, undo_bounds.y + 9}, 14, 1, {246, 252, 240, 255})
        redo_fill := redo_available ? rl.Color{35, 86, 82, 240} : rl.Color{42, 49, 53, 210}
        rl.DrawRectangleRounded(redo_bounds, .14, 6, redo_fill)
        rl.DrawRectangleRoundedLinesEx(redo_bounds, .14, 6, 1, {103, 153, 146, 255})
        vehicle_paint_draw_icon(editor, 9, {redo_bounds.x + 4, redo_bounds.y + 7, 22, 22})
        rl.DrawTextEx(rl.Font{}, "REDO", {redo_bounds.x + 27, redo_bounds.y + 9}, 14, 1, {246, 252, 240, 255})
        erase_fill := editor.vehicle_paint_erase ? rl.Color{192, 139, 74, 245} : rl.Color{35, 86, 82, 240}
        rl.DrawRectangleRounded(erase_bounds, .14, 6, erase_fill)
        rl.DrawRectangleRoundedLinesEx(erase_bounds, .14, 6, editor.vehicle_paint_erase ? 2 : 1, {224, 192, 128, 255})
        erase_label: cstring = editor.vehicle_paint_erase ? "ERASING" : "ERASER"
        vehicle_paint_draw_icon(editor, 7, {erase_bounds.x + 5, erase_bounds.y + 7, 22, 22})
        rl.DrawTextEx(rl.Font{}, erase_label, {erase_bounds.x + 28, erase_bounds.y + 9}, 13, 1, {255, 242, 211, 255})
        clear_fill := clear_armed ? rl.Color{151, 63, 48, 250} : rl.Color{86, 48, 47, 235}
        clear_border := clear_armed ? rl.Color{255, 211, 139, 255} : rl.Color{174, 103, 91, 255}
        rl.DrawRectangleRounded(clear_bounds, .14, 6, clear_fill)
        rl.DrawRectangleRoundedLinesEx(clear_bounds, .14, 6, clear_armed ? 2 : 1, clear_border)
        vehicle_paint_draw_icon(editor, 11, {clear_bounds.x + 5, clear_bounds.y + 7, 22, 22})
        clear_label: cstring = clear_armed ? "AGAIN" : "CLEAR"
        rl.DrawTextEx(rl.Font{}, clear_label, {clear_bounds.x + 29, clear_bounds.y + 9}, 14, 1, {255, 231, 211, 255})
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
        save_exit_bounds := vehicle_paint_save_exit_bounds(editor)
        rl.DrawRectangleRounded(save_exit_bounds, .14, 6, {35, 86, 82, 245})
        rl.DrawRectangleRoundedLinesEx(save_exit_bounds, .14, 6, 1, {127, 174, 164, 255})
        rl.DrawTextEx(
            rl.Font{},
            "SAVE & EXIT",
            {save_exit_bounds.x + 12, save_exit_bounds.y + 8},
            16,
            1,
            {246, 252, 240, 255},
        )
        tool_hint: cstring
        #partial switch editor.vehicle_paint_tool {
        case .Brush:
            tool_hint = "DRAG TO PAINT"
        case .Bucket:
            tool_hint = "CLICK CONNECTED REGION"
        case .Shape:
            tool_hint = "CHOOSE A SHAPE, THEN CLICK TO APPLY"
        case .Blend:
            tool_hint = "DRAG TO SMOOTH"
        case .Gradient:
            tool_hint = "DRAG COLOR DIRECTION"
        case .Pattern:
            tool_hint = "CLICK TO APPLY PATTERN"
        case .Strip:
            tool_hint = "DRAG STRAIGHT BAND"
        case .Shade:
            tool_hint = "LMB DARKER — SHIFT+LMB LIGHTER"
        }
        if clear_armed do tool_hint = "CLICK AGAIN TO CLEAR — UNDO AVAILABLE"
        footer_y := vehicle_paint_actions_top(editor) + 50
        rl.DrawTextEx(rl.Font{}, save_label, {18, footer_y}, 14, 1, save_color)
        rl.DrawTextEx(rl.Font{}, tool_hint, {18, footer_y + 18}, 12, 1, {211, 235, 235, 255})
    } else {
        compact_label := fmt.ctprintf(
            "TAB SHOW TOOLS   %s   R%d H%d%% S%d%%",
            editor.vehicle_paint_erase ? "ERASER" : tool_names[int(editor.vehicle_paint_tool)],
            editor.vehicle_paint_brush_radius,
            int(editor.vehicle_paint_brush_hardness * 100 + .5),
            int(editor.vehicle_paint_brush_strength * 100 + .5),
        )
        rl.DrawRectangleRounded({12, 14, 424, 38}, .18, 6, {15, 31, 38, 238})
        rl.DrawTextEx(rl.Font{}, compact_label, {22, 25}, 16, 1, {244, 255, 250, 255})
    }
    {
        cursor := rl.Vector2{editor.vehicle_paint_cursor_x, editor.vehicle_paint_cursor_y}
        cursor_radius := f32(8 + editor.vehicle_paint_brush_radius / 2)
        cursor_color :=
            editor.vehicle_paint_hover_hit ? palette[editor.vehicle_paint_color] : rl.Color{158, 166, 165, 255}
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
        rl.DrawLineEx(
            {cursor.x - cursor_radius - 7, cursor.y},
            {cursor.x - cursor_radius + 1, cursor.y},
            2,
            cursor_color,
        )
        rl.DrawLineEx(
            {cursor.x + cursor_radius - 1, cursor.y},
            {cursor.x + cursor_radius + 7, cursor.y},
            2,
            cursor_color,
        )
        rl.DrawLineEx(
            {cursor.x, cursor.y - cursor_radius - 7},
            {cursor.x, cursor.y - cursor_radius + 1},
            2,
            cursor_color,
        )
        rl.DrawLineEx(
            {cursor.x, cursor.y + cursor_radius - 1},
            {cursor.x, cursor.y + cursor_radius + 7},
            2,
            cursor_color,
        )
        cursor_label: cstring = "CAN'T PAINT HERE"
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
