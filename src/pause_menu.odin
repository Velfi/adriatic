package main

import atmosphere "../packages/atmosphere"
import game_input "../packages/game_input"
import player_mail "../packages/player_mail"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"

Pause_Screen :: enum {
    Closed,
    World_Select,
    World_Map,
    Pause,
    Journal,
    Mail,
    Options,
    Customization,
    Scrapbook,
    Photo,
}

pause_menu_pointer_enabled := true
PAUSE_MENU_BUTTON_COUNT :: 7

Gameplay_Options :: struct {
    look_sensitivity:    f32,
    sound_fx_level:      f32,
    invert_look_x:       bool,
    invert_look_y:       bool,
    invert_flight_pitch: bool,
    show_hud:            bool,
    crunchiness:         Crunchiness,
    visual_style:        Visual_Style,
    dither_mode:         Dither_Mode,
    hdr_exposure:        bool,
    theme_mode:          UI_Theme_Mode,
}

Crunchiness :: enum {
    P240,
    P480,
    P720,
    Full,
}

gameplay_options_default :: proc() -> Gameplay_Options {
    return {
        look_sensitivity = .012,
        sound_fx_level = 1,
        invert_look_x = true,
        invert_look_y = false,
        invert_flight_pitch = false,
        show_hud = true,
        crunchiness = .P480,
        visual_style = .Standard,
        dither_mode = .Off,
        hdr_exposure = true,
        theme_mode = .Light,
    }
}

crunchiness_label :: proc(value: Crunchiness) -> cstring {
    switch value {
    case .P240:
        return "240P"
    case .P480:
        return "480P"
    case .P720:
        return "720P"
    case .Full:
        return "FULL"
    }
    return "480P"
}

crunchiness_render_width :: proc(render_height, viewport_width, viewport_height: i32) -> u32 {
    if render_height <= 0 || viewport_width <= 0 || viewport_height <= 0 do return 0
    // The preset names describe vertical resolution. Derive the horizontal
    // resolution from the user's viewport so reduced-resolution rendering
    // preserves the same aspect ratio instead of forcing 16:9.
    width := (render_height * viewport_width + viewport_height / 2) / viewport_height
    return u32(max(width, 1))
}

crunchiness_apply :: proc(value: Crunchiness) {
    viewport_width, viewport_height := canvas2d.GetScreenWidth(), canvas2d.GetScreenHeight()
    switch value {
    case .P240:
        canvas2d.SetWorldRenderSize(crunchiness_render_width(240, viewport_width, viewport_height), 240)
    case .P480:
        canvas2d.SetWorldRenderSize(crunchiness_render_width(480, viewport_width, viewport_height), 480)
    case .P720:
        canvas2d.SetWorldRenderSize(crunchiness_render_width(720, viewport_width, viewport_height), 720)
    case .Full:
        canvas2d.SetWorldRenderSize(0, 0)
    }
}

@(no_instrumentation)
pause_menu_is_open :: #force_inline proc(editor: ^Editor) -> bool {
    return editor != nil && (editor.console.open || editor.main_menu_active || editor.pause_screen != .Closed)
}

// Keep audio live while Options is visible so changes to the sound-effects
// slider can be heard immediately. Other overlays retain the existing mute.
@(no_instrumentation)
sound_fx_muted :: #force_inline proc(editor: ^Editor) -> bool {
    if editor == nil do return true
    if editor.pause_screen == .Options do return false
    return pause_menu_is_open(editor)
}

@(no_instrumentation)
pause_menu_panel :: #force_inline proc(width, height: i32, options: bool) -> canvas2d.Rectangle {
    panel_width := min(f32(500), f32(width) - 40)
    panel_height := options ? f32(560) : f32(546)
    panel_height = min(panel_height, f32(height) - 32)
    return {(f32(width) - panel_width) * .5, (f32(height) - panel_height) * .5, panel_width, panel_height}
}

@(no_instrumentation)
pause_menu_button_bounds :: #force_inline proc(panel: canvas2d.Rectangle, row: int) -> canvas2d.Rectangle {
    return {panel.x + 44, panel.y + 126 + f32(row) * 58, panel.width - 88, 46}
}

MAIN_MENU_BUTTON_COUNT :: 3
WORLD_SELECT_FOCUS_COUNT :: 3
WORLD_SELECT_MAP_FOCUS :: 0
WORLD_SELECT_WEATHER_FOCUS :: 1
WORLD_SELECT_START_FOCUS :: 2

@(no_instrumentation)
main_menu_panel :: #force_inline proc(width, height: i32) -> canvas2d.Rectangle {
    panel_width := min(f32(430), f32(width) - 48)
    panel_height := min(f32(360), f32(height) - 48)
    return {f32(width) - panel_width - 54, (f32(height) - panel_height) * .5, panel_width, panel_height}
}

@(no_instrumentation)
main_menu_button_bounds :: #force_inline proc(panel: canvas2d.Rectangle, row: int) -> canvas2d.Rectangle {
    return {panel.x + 42, panel.y + 128 + f32(row) * 62, panel.width - 84, 48}
}

@(no_instrumentation)
world_select_panel :: #force_inline proc(width, height: i32) -> canvas2d.Rectangle {
    panel_width := min(f32(820), f32(width) - 48)
    // The map is a true 8 km x 8 km orthographic plan, so give the world
    // selector enough vertical room to present it at a square aspect.
    panel_height := min(f32(820), f32(height) - 48)
    return {(f32(width) - panel_width) * .5, (f32(height) - panel_height) * .5, panel_width, panel_height}
}

@(no_instrumentation)
world_select_map_bounds :: #force_inline proc(panel: canvas2d.Rectangle) -> canvas2d.Rectangle {
    available_width := panel.width - 68
    available_height := panel.height - 238
    size := min(available_width, available_height)
    return {panel.x + (panel.width - size) * .5, panel.y + 112, size, size}
}

@(no_instrumentation)
world_select_weather_bounds :: #force_inline proc(panel: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {panel.x + 34, panel.y + panel.height - 108, 236, 44}
}

@(no_instrumentation)
world_select_start_bounds :: #force_inline proc(panel: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {panel.x + panel.width - 254, panel.y + panel.height - 108, 220, 44}
}

OPTIONS_ROW_COUNT :: 12
OPTIONS_RESTORE_FOCUS :: OPTIONS_ROW_COUNT
OPTIONS_BACK_FOCUS :: OPTIONS_ROW_COUNT + 1
OPTIONS_CONTENT_HEIGHT :: f32(930)

@(no_instrumentation)
options_menu_viewport :: #force_inline proc(panel: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {panel.x + 30, panel.y + 108, panel.width - 54, max(panel.height - 178, f32(80))}
}

@(no_instrumentation)
options_menu_max_scroll :: #force_inline proc(panel: canvas2d.Rectangle) -> f32 {
    return max(OPTIONS_CONTENT_HEIGHT - options_menu_viewport(panel).height, f32(0))
}

@(no_instrumentation)
options_menu_row_bounds :: #force_inline proc(
    panel: canvas2d.Rectangle,
    row: int,
    scroll_y: f32 = 0,
) -> canvas2d.Rectangle {
    viewport := options_menu_viewport(panel)
    return {panel.x + 40, viewport.y + 10 + f32(row) * 72 - scroll_y, panel.width - 80, 58}
}

@(no_instrumentation)
options_menu_restore_bounds :: #force_inline proc(panel: canvas2d.Rectangle, scroll_y: f32 = 0) -> canvas2d.Rectangle {
    viewport := options_menu_viewport(panel)
    return {panel.x + 44, viewport.y + 874 - scroll_y, panel.width - 88, 46}
}

@(no_instrumentation)
options_menu_back_bounds :: #force_inline proc(panel: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {panel.x + 44, panel.y + panel.height - 54, panel.width - 88, 46}
}

@(no_instrumentation)
options_menu_scrollbar_track :: #force_inline proc(panel: canvas2d.Rectangle) -> canvas2d.Rectangle {
    viewport := options_menu_viewport(panel)
    return {panel.x + panel.width - 19, viewport.y + 8, 4, max(viewport.height - 16, f32(16))}
}

options_menu_scrollbar_thumb :: proc(panel: canvas2d.Rectangle, scroll_y: f32) -> canvas2d.Rectangle {
    track := options_menu_scrollbar_track(panel)
    viewport := options_menu_viewport(panel)
    maximum := options_menu_max_scroll(panel)
    if maximum <= 0 do return track
    thumb_height := max(f32(36), track.height * viewport.height / OPTIONS_CONTENT_HEIGHT)
    travel := max(track.height - thumb_height, f32(0))
    return {track.x - 3, track.y + travel * clamp(scroll_y / maximum, 0, 1), track.width + 6, thumb_height}
}

@(no_instrumentation)
options_menu_slider_track :: #force_inline proc(bounds: canvas2d.Rectangle) -> canvas2d.Rectangle {
    return {bounds.x + 14, bounds.y + 41, bounds.width - 28, 6}
}

pause_menu_button :: proc(bounds: canvas2d.Rectangle, label: cstring, accent: bool = false, focused: bool = false) {
    hovered := pause_menu_pointer_enabled && canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
    fill := ui_theme_control()
    border := ui_theme_border()
    text := ui_theme_text()
    if hovered {
        fill = ui_theme_control_hover()
        border = ui_theme_border_strong()
    }
    if accent {
        fill = hovered ? ui_theme_accent_hover() : ui_theme_accent()
        border = ui_theme_border_strong()
        text = ui_theme_text_inverse()
    }
    if focused {
        border = ui_theme_focus()
        if !accent do fill = ui_theme_surface_elevated()
    }
    canvas2d.DrawRectangleRounded(bounds, .12, 8, fill)
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .12, 8, accent || focused ? 2 : 1, border)
    size := ui_measure_text(.Label, label, .5)
    ui_draw_text(
        .Label,
        label,
        {bounds.x + (bounds.width - size.x) * .5, bounds.y + (bounds.height - size.y) * .5 + 4},
        .5,
        text,
    )
}

pause_menu_open :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map do return
    editor.pause_screen = .Pause
    editor.pause_focus = 0
    editor.map_time = f32(canvas2d.GetTime())
    set_pointer_locked(false)
}

pause_menu_resume :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.pause_screen = .Closed
    editor.controller_disconnect_notice = false
    editor.map_time = f32(canvas2d.GetTime())
    set_pointer_locked(editor.in_map)
}

photo_mode_open :: proc(editor: ^Editor) {
    if editor == nil do return
    photo_filter_defaults(&editor.photo_filter)
    editor.photo_restore_pose = editor.camera_pose
    editor.photo_restore_inspection = editor.cameras.poses[third_person.Camera_Slot.Inspection]
    editor.photo_restore_slot = editor.cameras.active
    direction := editor.camera_pose.target - editor.camera_pose.position
    length := f32(math.sqrt(f64(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)))
    if length < .001 {
        direction = {0, 0, -1}
    } else {
        direction /= length
    }
    editor.photo_yaw = f32(math.atan2(f64(-direction.x), f64(-direction.z)))
    editor.photo_pitch = f32(math.asin(f64(clamp(direction.y, -1, 1))))
    editor.pause_screen = .Photo
    photo_filter_apply_pass_plan(editor)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    set_pointer_locked(true)
}

photo_mode_close :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.camera_pose = editor.photo_restore_pose
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.photo_restore_inspection)
    if editor.photo_restore_slot != .Inspection {
        third_person.camera_set_pose(&editor.cameras, editor.photo_restore_slot, editor.photo_restore_pose)
    }
    third_person.camera_set_active(&editor.cameras, editor.photo_restore_slot)
    editor.pause_screen = .Pause
    photo_filter_apply_pass_plan(editor)
    editor.pause_focus = 0
    editor.photo_capture_pending = false
    set_pointer_locked(false)
}

SCRAPBOOK_PHOTO_COUNT :: 12
SCRAPBOOK_COLUMNS :: 4

Scrapbook_Sort :: enum {
    Manual,
    Newest,
    Favorites,
}

scrapbook_focus := 0
scrapbook_sort := Scrapbook_Sort.Manual
scrapbook_manage := false
scrapbook_viewing := false
scrapbook_initialized := false
scrapbook_count := 0
scrapbook_favorites: [SCRAPBOOK_PHOTO_COUNT]bool
scrapbook_archived: [SCRAPBOOK_PHOTO_COUNT]bool
scrapbook_order: [SCRAPBOOK_PHOTO_COUNT]int
scrapbook_paths: [SCRAPBOOK_PHOTO_COUNT]string
scrapbook_textures: [SCRAPBOOK_PHOTO_COUNT]canvas2d.Texture

scrapbook_is_photo :: proc(name: string) -> bool {
    return strings.has_prefix(name, "adriatic-photo-") && strings.has_suffix(name, ".png")
}

// Keep the most recent photos without making the UI or texture use unbounded.
scrapbook_collect_paths :: proc(directory: string) -> ([SCRAPBOOK_PHOTO_COUNT]string, int) {
    result: [SCRAPBOOK_PHOTO_COUNT]string
    count := 0
    entries, err := os.read_all_directory_by_path(directory, context.temp_allocator)
    if err != nil do return result, 0
    defer os.file_info_slice_delete(entries, context.temp_allocator)
    for entry in entries {
        if entry.type != .Regular || !scrapbook_is_photo(entry.name) do continue
        if count == SCRAPBOOK_PHOTO_COUNT {
            if entry.name <= result[0] do continue
            for position in 0 ..< SCRAPBOOK_PHOTO_COUNT - 1 do result[position] = result[position + 1]
            count -= 1
        }
        insert := count
        for insert > 0 && entry.name < result[insert - 1] do insert -= 1
        for position := count; position > insert; position -= 1 do result[position] = result[position - 1]
        result[insert] = entry.fullpath
        count += 1
    }
    return result, count
}

scrapbook_refresh :: proc() {
    pictures, pictures_error := os.user_pictures_dir(context.temp_allocator)
    if pictures_error != nil || pictures == "" do return
    directory, directory_error := strings.concatenate({pictures, "/Adriatic"}, context.temp_allocator)
    if directory_error != nil do return
    paths, count := scrapbook_collect_paths(directory)

    old_paths := scrapbook_paths
    old_textures := scrapbook_textures
    old_favorites := scrapbook_favorites
    old_archived := scrapbook_archived
    scrapbook_paths = {}
    scrapbook_textures = {}
    scrapbook_favorites = {}
    scrapbook_archived = {}
    for index in 0 ..< count {
        for old_index in 0 ..< scrapbook_count {
            if old_paths[old_index] != paths[index] do continue
            scrapbook_textures[index] = old_textures[old_index]
            scrapbook_favorites[index] = old_favorites[old_index]
            scrapbook_archived[index] = old_archived[old_index]
            break
        }
        scrapbook_paths[index] = strings.clone(paths[index], context.allocator) or_else ""
        if !scrapbook_textures[index].ready && scrapbook_paths[index] != "" {
            scrapbook_textures[index] = canvas2d.LoadTexture(scrapbook_paths[index])
        }
        scrapbook_order[index] = index
    }
    for index in 0 ..< scrapbook_count {
        if old_paths[index] != "" do delete(old_paths[index])
    }
    scrapbook_count = count
}

scrapbook_init :: proc() {
    if scrapbook_initialized do return
    scrapbook_refresh()
    scrapbook_initialized = true
}

scrapbook_visible_count :: proc() -> int {
    count := 0
    for index in 0 ..< scrapbook_count {
        if !scrapbook_archived[index] do count += 1
    }
    return count
}

scrapbook_photo_at :: proc(visible_index: int) -> int {
    scrapbook_init()
    seen := 0
    if scrapbook_sort == .Newest {
        for reverse in 0 ..< scrapbook_count {
            photo := scrapbook_order[scrapbook_count - 1 - reverse]
            if scrapbook_archived[photo] do continue
            if seen == visible_index do return photo
            seen += 1
        }
    } else if scrapbook_sort == .Favorites {
        for wanted_favorite in 0 ..< 2 {
            favorite := wanted_favorite == 0
            for position in 0 ..< scrapbook_count {
                photo := scrapbook_order[position]
                if scrapbook_archived[photo] || scrapbook_favorites[photo] != favorite do continue
                if seen == visible_index do return photo
                seen += 1
            }
        }
    } else {
        for position in 0 ..< scrapbook_count {
            photo := scrapbook_order[position]
            if scrapbook_archived[photo] do continue
            if seen == visible_index do return photo
            seen += 1
        }
    }
    return 0
}

scrapbook_sort_label :: proc() -> cstring {
    switch scrapbook_sort {
    case .Manual:
        return "CUSTOM ORDER"
    case .Newest:
        return "NEWEST FIRST"
    case .Favorites:
        return "FAVORITES FIRST"
    }
    return "CUSTOM ORDER"
}

scrapbook_open :: proc(editor: ^Editor) {
    if editor == nil do return
    scrapbook_init()
    scrapbook_refresh()
    scrapbook_focus = clamp(scrapbook_focus, 0, max(scrapbook_visible_count() - 1, 0))
    scrapbook_manage = false
    scrapbook_viewing = false
    editor.pause_screen = .Scrapbook
}

scrapbook_move_manual :: proc(direction: int) {
    if scrapbook_sort != .Manual || direction == 0 do return
    count := scrapbook_visible_count()
    if count < 2 do return
    target := clamp(scrapbook_focus + direction, 0, count - 1)
    if target == scrapbook_focus do return
    a := scrapbook_photo_at(scrapbook_focus)
    b := scrapbook_photo_at(target)
    a_position, b_position := -1, -1
    for position in 0 ..< scrapbook_count {
        if scrapbook_order[position] == a do a_position = position
        if scrapbook_order[position] == b do b_position = position
    }
    if a_position >= 0 && b_position >= 0 {
        scrapbook_order[a_position], scrapbook_order[b_position] =
            scrapbook_order[b_position], scrapbook_order[a_position]
        scrapbook_focus = target
    }
}

scrapbook_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil do return
    if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
        if scrapbook_viewing {
            scrapbook_viewing = false
        } else if scrapbook_manage {
            scrapbook_manage = false
        } else {
            editor.pause_screen = .Pause
            editor.pause_focus = 2
        }
        return
    }
    count := scrapbook_visible_count()
    if count == 0 do return
    mouse := canvas2d.GetMousePosition()
    mouse_delta := canvas2d.GetMouseDelta()
    mouse_active := canvas2d.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    if mouse_active && !scrapbook_viewing {
        panel := canvas2d.Rectangle{32, 26, f32(width) - 64, f32(height) - 52}
        for visible_index in 0 ..< count {
            if canvas2d.CheckCollisionPointRec(mouse, scrapbook_card_bounds(panel, visible_index)) {
                if canvas2d.IsMouseButtonPressed(.LEFT) && scrapbook_focus == visible_index && !scrapbook_manage {
                    scrapbook_viewing = true
                    return
                }
                scrapbook_focus = visible_index
            }
        }
    }
    if input_action_pressed(.Menu_Accept) {
        scrapbook_viewing = !scrapbook_viewing
        return
    }
    if canvas2d.IsKeyPressed(.M) || gamepad_pressed(.North) {
        scrapbook_manage = !scrapbook_manage
        scrapbook_viewing = false
    }
    photo := scrapbook_photo_at(scrapbook_focus)
    if canvas2d.IsKeyPressed(.F) || gamepad_pressed(.West) do scrapbook_favorites[photo] = !scrapbook_favorites[photo]
    if scrapbook_manage && (canvas2d.IsKeyPressed(.BACKSPACE) || gamepad_pressed(.East)) {
        scrapbook_archived[photo] = true
        scrapbook_focus = clamp(scrapbook_focus, 0, max(scrapbook_visible_count() - 1, 0))
        return
    }
    if !scrapbook_manage && (canvas2d.IsKeyPressed(.Q) || gamepad_pressed(.Left_Shoulder)) {
        scrapbook_sort = Scrapbook_Sort((int(scrapbook_sort) + 2) % 3)
    }
    if !scrapbook_manage && (canvas2d.IsKeyPressed(.E) || gamepad_pressed(.Right_Shoulder)) {
        scrapbook_sort = Scrapbook_Sort((int(scrapbook_sort) + 1) % 3)
    }
    horizontal, vertical := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    if canvas2d.IsKeyPressed(.LEFT) || gamepad_pressed(.Dpad_Left) do horizontal = -1
    if canvas2d.IsKeyPressed(.RIGHT) || gamepad_pressed(.Dpad_Right) do horizontal = 1
    if canvas2d.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do vertical = -1
    if canvas2d.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do vertical = 1
    if scrapbook_manage && horizontal != 0 {
        scrapbook_move_manual(horizontal)
    } else {
        scrapbook_focus = clamp(scrapbook_focus + horizontal + vertical * SCRAPBOOK_COLUMNS, 0, count - 1)
    }
}

photo_mode_process_input :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
        photo_mode_close(editor)
        return
    }

    if canvas2d.IsKeyPressed(.TAB) || gamepad_pressed(.West) {
        editor.photo_filter.panel_open = !editor.photo_filter.panel_open
        set_pointer_locked(!editor.photo_filter.panel_open)
    }
    if editor.photo_filter.panel_open {
        if canvas2d.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) {
            editor.photo_filter.focus =
                (editor.photo_filter.focus + PHOTO_FILTER_CONTROL_COUNT - 1) % PHOTO_FILTER_CONTROL_COUNT
        }
        if canvas2d.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) {
            editor.photo_filter.focus = (editor.photo_filter.focus + 1) % PHOTO_FILTER_CONTROL_COUNT
        }
        direction := 0
        if canvas2d.IsKeyPressed(.LEFT) || gamepad_pressed(.Dpad_Left) do direction -= 1
        if canvas2d.IsKeyPressed(.RIGHT) || gamepad_pressed(.Dpad_Right) do direction += 1
        if direction != 0 {
            filter := &editor.photo_filter
            if filter.focus == 0 {
                photo_filter_store_active(filter)
                filter.mode = photo_filter_adjust_mode(filter.mode, direction)
                photo_filter_load_active(filter)
                photo_filter_apply_pass_plan(editor)
            } else {
                delta := f32(direction) * .05
                switch filter.focus {
                case 1:
                    filter.intensity = clamp(filter.intensity + delta, f32(0), f32(1))
                case 2:
                    filter.radius = clamp(filter.radius + delta, f32(0), f32(1))
                case 3:
                    filter.detail = clamp(filter.detail + delta, f32(0), f32(1))
                case 4:
                    filter.saturation = clamp(filter.saturation + delta, f32(0), f32(2))
                case 5:
                    filter.contrast = clamp(filter.contrast + delta, f32(0), f32(2))
                case 6:
                    filter.brightness = clamp(filter.brightness + delta, f32(-1), f32(1))
                case 7:
                    filter.grain = clamp(filter.grain + delta, f32(0), f32(1))
                case 8:
                    filter.vignette = clamp(filter.vignette + delta, f32(0), f32(1))
                case 9:
                    filter.distortion = clamp(filter.distortion + delta, f32(0), f32(1))
                }
                photo_filter_store_active(filter)
            }
        }
        if canvas2d.IsKeyPressed(.R) {
            photo_filter_reset_mode(&editor.photo_filter, editor.photo_filter.mode)
            editor.photo_filter.panel_open = true
        }
        if canvas2d.IsKeyPressed(.ENTER) || gamepad_pressed(.South) do editor.photo_capture_pending = true
        return
    }

    mouse := canvas2d.GetMouseDelta()
    look_x := editor.gameplay_options.invert_look_x ? -mouse.x : mouse.x
    look_y := editor.gameplay_options.invert_look_y ? -mouse.y : mouse.y
    look_x += gamepad_axis(.Right_X) * 180 * delta_seconds
    look_y += gamepad_axis(.Right_Y) * 180 * delta_seconds
    editor.photo_yaw += look_x * editor.gameplay_options.look_sensitivity
    editor.photo_pitch = clamp(
        editor.photo_pitch - look_y * editor.gameplay_options.look_sensitivity,
        f32(-1.48),
        f32(1.48),
    )

    cos_pitch := f32(math.cos(f64(editor.photo_pitch)))
    forward := third_person.Vec3 {
        -f32(math.sin(f64(editor.photo_yaw))) * cos_pitch,
        f32(math.sin(f64(editor.photo_pitch))),
        -f32(math.cos(f64(editor.photo_yaw))) * cos_pitch,
    }
    right := third_person.Vec3{f32(math.cos(f64(editor.photo_yaw))), 0, -f32(math.sin(f64(editor.photo_yaw)))}
    move_x, move_y, move_z := f32(0), f32(0), f32(0)
    if canvas2d.IsKeyDown(.D) do move_x += 1
    if canvas2d.IsKeyDown(.A) do move_x -= 1
    if canvas2d.IsKeyDown(.W) do move_z += 1
    if canvas2d.IsKeyDown(.S) do move_z -= 1
    if canvas2d.IsKeyDown(.E) do move_y += 1
    if canvas2d.IsKeyDown(.Q) do move_y -= 1
    move_x = stronger_axis(move_x, gamepad_axis(.Left_X))
    move_z = stronger_axis(move_z, -gamepad_axis(.Left_Y))
    if gamepad_down(.Right_Shoulder) do move_y += 1
    if gamepad_down(.Left_Shoulder) do move_y -= 1
    move_length_squared := move_x * move_x + move_y * move_y + move_z * move_z
    if move_length_squared > 1 {
        inverse_length := f32(1 / math.sqrt(f64(move_length_squared)))
        move_x *= inverse_length
        move_y *= inverse_length
        move_z *= inverse_length
    }
    speed := (canvas2d.IsKeyDown(.LEFT_SHIFT) || canvas2d.IsKeyDown(.RIGHT_SHIFT)) ? f32(18) : f32(6)
    editor.camera_pose.position +=
        (right * move_x + forward * move_z + third_person.Vec3{0, move_y, 0}) * speed * delta_seconds
    editor.camera_pose.target = editor.camera_pose.position + forward
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)

    if canvas2d.IsKeyPressed(.ENTER) || canvas2d.IsKeyPressed(.F) || gamepad_pressed(.South) {
        editor.photo_capture_pending = true
    }
}

photo_filter_draw :: proc(editor: ^Editor) {
    if editor == nil || !editor.photo_filter.panel_open do return
    filter := &editor.photo_filter
    panel := canvas2d.Rectangle{24, 24, 330, 390}
    canvas2d.DrawRectangleRounded(panel, .08, 8, ui_theme_scrim(225))
    canvas2d.DrawRectangleRoundedLinesEx(panel, .08, 8, 1, ui_theme_border_strong())
    ui_draw_text(.Label, "PAINT FILTER", {panel.x + 18, panel.y + 16}, .42, ui_theme_text_inverse())
    values := [PHOTO_FILTER_CONTROL_COUNT]f32 {
        0,
        filter.intensity,
        filter.radius,
        filter.detail,
        filter.saturation,
        filter.contrast,
        filter.brightness,
        filter.grain,
        filter.vignette,
        filter.distortion,
    }
    for row in 0 ..< PHOTO_FILTER_CONTROL_COUNT {
        y := panel.y + 58 + f32(row) * 29
        color := row == filter.focus ? ui_theme_focus() : ui_theme_text_muted()
        ui_draw_text(.Data, photo_filter_control_label(filter.mode, row), {panel.x + 18, y}, .23, color)
        value: cstring
        if row == 0 {
            value = photo_filter_mode_label(filter.mode)
        } else if filter.mode == .Floyd_Steinberg && row == 2 {
            value = fmt.ctprintf("%d", int(2 + filter.radius * 14))
        } else if filter.mode == .Floyd_Steinberg && row == 9 {
            value = filter.distortion > .5 ? "ON" : "OFF"
        } else {
            value = fmt.ctprintf("%+.2f", values[row])
        }
        size := ui_measure_text(.Data, value, .23)
        ui_draw_text(.Data, value, {panel.x + panel.width - size.x - 18, y}, .23, color)
    }
    ui_draw_text(
        .Data,
        "UP/DOWN SELECT  LEFT/RIGHT ADJUST  R RESET",
        {panel.x + 18, panel.y + panel.height - 25},
        .17,
        ui_theme_text_muted(),
    )
}

photo_mode_capture_pending :: proc(editor: ^Editor) {
    if editor == nil || !editor.photo_capture_pending do return
    editor.photo_capture_pending = false
    pictures, pictures_error := os.user_pictures_dir(context.temp_allocator)
    if pictures_error != nil || pictures == "" do pictures = "."
    directory, directory_error := strings.concatenate({pictures, "/Adriatic"}, context.temp_allocator)
    if directory_error != nil do return
    if make_error := os.make_directory_all(directory); make_error != nil && make_error != .Exist do return
    path := fmt.ctprintf("%s/adriatic-photo-%d.png", directory, i64(canvas2d.GetTime() * 1000))
    canvas2d.TakeScreenshot(path)
    // TakeScreenshot queues the write, so add this capture to the live catalog
    // now; the next scrapbook open also rescans disk as a fallback.
    scrapbook_initialized = false
    editor.photo_capture_notice_until = canvas2d.GetTime() + 2.5
}

pause_menu_return_to_editor :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.pause_screen = .Closed
    editor.in_map = false
    game_state_reset(editor)
    third_person.camera_set_active(&editor.cameras, .Player)
    editor.map_time = f32(canvas2d.GetTime())
    editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
}

options_menu_focus_bounds :: proc(panel: canvas2d.Rectangle, focus: int, scroll_y: f32) -> canvas2d.Rectangle {
    if focus >= 0 && focus < OPTIONS_ROW_COUNT do return options_menu_row_bounds(panel, focus, scroll_y)
    if focus == OPTIONS_RESTORE_FOCUS do return options_menu_restore_bounds(panel, scroll_y)
    return options_menu_back_bounds(panel)
}

options_menu_reveal_focus :: proc(editor: ^Editor, panel: canvas2d.Rectangle) {
    if editor == nil || editor.options_focus < 0 || editor.options_focus > OPTIONS_RESTORE_FOCUS do return
    viewport := options_menu_viewport(panel)
    bounds := options_menu_focus_bounds(panel, editor.options_focus, editor.options_scroll_y)
    top := viewport.y + 6
    bottom := viewport.y + viewport.height - 6
    if bounds.y < top {
        editor.options_scroll_y -= top - bounds.y
    } else if bounds.y + bounds.height > bottom {
        editor.options_scroll_y += bounds.y + bounds.height - bottom
    }
    editor.options_scroll_y = clamp(editor.options_scroll_y, 0, options_menu_max_scroll(panel))
}

options_menu_adjust_focused :: proc(editor: ^Editor, direction: int) {
    if editor == nil || direction == 0 do return
    switch editor.options_focus {
    case 0:
        editor.gameplay_options.look_sensitivity = clamp(
            editor.gameplay_options.look_sensitivity + f32(direction) * .001,
            .004,
            .024,
        )
    case 1:
        editor.gameplay_options.sound_fx_level = clamp(
            editor.gameplay_options.sound_fx_level + f32(direction) * .05,
            0,
            1,
        )
    case 2:
        editor.gameplay_options.invert_look_x = direction > 0
    case 3:
        editor.gameplay_options.invert_look_y = direction > 0
    case 4:
        editor.gameplay_options.invert_flight_pitch = direction > 0
    case 5:
        editor.gameplay_options.show_hud = direction > 0
    case 6:
        selected := clamp(int(editor.gameplay_options.crunchiness) + direction, 0, 3)
        editor.gameplay_options.crunchiness = Crunchiness(selected)
        crunchiness_apply(editor.gameplay_options.crunchiness)
    case 7:
        visual_style_set(editor, visual_style_adjust(editor.gameplay_options.visual_style, direction))
    case 8:
        if editor.gameplay_options.visual_style != .Dither do return
        editor.gameplay_options.dither_mode = dither_adjust_variant(editor.gameplay_options.dither_mode, direction)
        dither_apply(editor)
    case 9:
        editor.gameplay_options.hdr_exposure = direction > 0
        dither_apply(editor)
    case 10:
        editor.gameplay_options.theme_mode = direction > 0 ? .Dark : .Light
        ui_theme_set_mode(editor.gameplay_options.theme_mode)
    }
}

options_menu_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    options_before := editor.gameplay_options
    defer {
        if editor.gameplay_options != options_before && !mouse_preference_save(editor) {
            fmt.eprintln("adriatic could not save gameplay preferences")
        }
    }
    panel := pause_menu_panel(width, height, true)
    mouse := canvas2d.GetMousePosition()
    pressed := canvas2d.IsMouseButtonPressed(.LEFT)
    mouse_delta := canvas2d.GetMouseDelta()
    mouse_active := pressed || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    viewport := options_menu_viewport(panel)
    maximum_scroll := options_menu_max_scroll(panel)
    editor.options_scroll_y = clamp(editor.options_scroll_y, 0, maximum_scroll)
    stick_x, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )

    focus_direction := 0
    if canvas2d.IsKeyPressed(.UP) || (canvas2d.GamepadAvailable() && canvas2d.IsGamepadButtonPressed(.Dpad_Up)) {
        focus_direction -= 1
    }
    if canvas2d.IsKeyPressed(.DOWN) || (canvas2d.GamepadAvailable() && canvas2d.IsGamepadButtonPressed(.Dpad_Down)) {
        focus_direction += 1
    }
    if focus_direction == 0 do focus_direction = stick_y
    if focus_direction != 0 {
        editor.options_focus = clamp(editor.options_focus + focus_direction, 0, OPTIONS_BACK_FOCUS)
        options_menu_reveal_focus(editor, panel)
    }

    adjust_direction := 0
    if canvas2d.IsKeyPressed(.LEFT) || (canvas2d.GamepadAvailable() && canvas2d.IsGamepadButtonPressed(.Dpad_Left)) {
        adjust_direction -= 1
    }
    if canvas2d.IsKeyPressed(.RIGHT) || (canvas2d.GamepadAvailable() && canvas2d.IsGamepadButtonPressed(.Dpad_Right)) {
        adjust_direction += 1
    }
    if adjust_direction == 0 do adjust_direction = stick_x
    if adjust_direction != 0 do options_menu_adjust_focused(editor, adjust_direction)

    confirm := input_action_pressed(.Menu_Accept)
    if confirm {
        switch editor.options_focus {
        case 2:
            editor.gameplay_options.invert_look_x = !editor.gameplay_options.invert_look_x
        case 3:
            editor.gameplay_options.invert_look_y = !editor.gameplay_options.invert_look_y
        case 4:
            editor.gameplay_options.invert_flight_pitch = !editor.gameplay_options.invert_flight_pitch
        case 5:
            editor.gameplay_options.show_hud = !editor.gameplay_options.show_hud
        case 7:
            visual_style_set(editor, visual_style_next(editor.gameplay_options.visual_style))
        case 8:
            if editor.gameplay_options.visual_style == .Dither {
                editor.gameplay_options.dither_mode = dither_next_variant(editor.gameplay_options.dither_mode)
                dither_apply(editor)
            }
        case 9:
            editor.gameplay_options.hdr_exposure = !editor.gameplay_options.hdr_exposure
            dither_apply(editor)
        case 10:
            editor.gameplay_options.theme_mode = editor.gameplay_options.theme_mode == .Dark ? .Light : .Dark
            ui_theme_set_mode(editor.gameplay_options.theme_mode)
        case OPTIONS_RESTORE_FOCUS:
            editor.gameplay_options = gameplay_options_default()
            crunchiness_apply(editor.gameplay_options.crunchiness)
            dither_apply(editor)
            ui_theme_set_mode(editor.gameplay_options.theme_mode)
        case 11:
            editor.pause_screen = .Customization
            editor.customization_focus = 0
        case OPTIONS_BACK_FOCUS:
            editor.pause_screen = editor.main_menu_active ? .Closed : .Pause
            editor.options_scroll_dragging = false
        }
        if editor.options_focus != 0 &&
           editor.options_focus != 1 &&
           editor.options_focus != 6 &&
           editor.options_focus != 7 &&
           editor.options_focus != 8 &&
           editor.options_focus != 9 &&
           editor.options_focus != 10 {
            return
        }
    }

    if canvas2d.CheckCollisionPointRec(mouse, viewport) {
        wheel := canvas2d.GetMouseWheelMove()
        if wheel != 0 do editor.options_scroll_y = clamp(editor.options_scroll_y - wheel * 42, 0, maximum_scroll)
    }

    scrollbar := options_menu_scrollbar_track(panel)
    thumb := options_menu_scrollbar_thumb(panel, editor.options_scroll_y)
    if maximum_scroll > 0 && pressed && canvas2d.CheckCollisionPointRec(mouse, thumb) {
        editor.options_scroll_dragging = true
        editor.options_scroll_drag_offset = mouse.y - thumb.y
    } else if maximum_scroll > 0 &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, {scrollbar.x - 8, scrollbar.y, 20, scrollbar.height}) {
        thumb_height := thumb.height
        travel := max(scrollbar.height - thumb_height, f32(1))
        normalized := clamp((mouse.y - scrollbar.y - thumb_height * .5) / travel, 0, 1)
        editor.options_scroll_y = normalized * maximum_scroll
        editor.options_scroll_dragging = true
        editor.options_scroll_drag_offset = thumb_height * .5
    }
    if editor.options_scroll_dragging {
        if canvas2d.IsMouseButtonDown(.LEFT) {
            thumb = options_menu_scrollbar_thumb(panel, editor.options_scroll_y)
            travel := max(scrollbar.height - thumb.height, f32(1))
            normalized := clamp((mouse.y - editor.options_scroll_drag_offset - scrollbar.y) / travel, 0, 1)
            editor.options_scroll_y = normalized * maximum_scroll
        } else {
            editor.options_scroll_dragging = false
        }
    }

    content_hovered := canvas2d.CheckCollisionPointRec(mouse, viewport)
    scroll_y := editor.options_scroll_y
    if content_hovered && mouse_active {
        for index in 0 ..< OPTIONS_ROW_COUNT {
            if canvas2d.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, index, scroll_y)) {
                editor.options_focus = index
            }
        }
        if canvas2d.CheckCollisionPointRec(mouse, options_menu_restore_bounds(panel, scroll_y)) {
            editor.options_focus = OPTIONS_RESTORE_FOCUS
        }
    }
    if mouse_active && canvas2d.CheckCollisionPointRec(mouse, options_menu_back_bounds(panel)) {
        editor.options_focus = OPTIONS_BACK_FOCUS
    }

    sensitivity := options_menu_row_bounds(panel, 0, scroll_y)
    track := options_menu_slider_track(sensitivity)
    if content_hovered &&
       canvas2d.IsMouseButtonDown(.LEFT) &&
       canvas2d.CheckCollisionPointRec(mouse, {track.x - 8, track.y - 12, track.width + 16, 30}) {
        editor.options_focus = 0
        normalized := clamp((mouse.x - track.x) / track.width, 0, 1)
        editor.gameplay_options.look_sensitivity = .004 + normalized * .020
    }
    sound_fx := options_menu_row_bounds(panel, 1, scroll_y)
    sound_fx_track := options_menu_slider_track(sound_fx)
    if content_hovered &&
       canvas2d.IsMouseButtonDown(.LEFT) &&
       canvas2d.CheckCollisionPointRec(
           mouse,
           {sound_fx_track.x - 8, sound_fx_track.y - 12, sound_fx_track.width + 16, 30},
       ) {
        editor.options_focus = 1
        editor.gameplay_options.sound_fx_level = clamp((mouse.x - sound_fx_track.x) / sound_fx_track.width, 0, 1)
    }
    if content_hovered &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 2, scroll_y)) {
        editor.options_focus = 2
        editor.gameplay_options.invert_look_x = !editor.gameplay_options.invert_look_x
        return
    }
    if content_hovered &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 3, scroll_y)) {
        editor.options_focus = 3
        editor.gameplay_options.invert_look_y = !editor.gameplay_options.invert_look_y
        return
    }
    if content_hovered &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 4, scroll_y)) {
        editor.options_focus = 4
        editor.gameplay_options.invert_flight_pitch = !editor.gameplay_options.invert_flight_pitch
        return
    }
    if content_hovered &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 5, scroll_y)) {
        editor.options_focus = 5
        editor.gameplay_options.show_hud = !editor.gameplay_options.show_hud
        return
    }
    crunchiness := options_menu_row_bounds(panel, 6, scroll_y)
    segment_gap := f32(6)
    segment_width := (crunchiness.width - segment_gap * 3) / 4
    if content_hovered && pressed {
        for index in 0 ..< 4 {
            segment := canvas2d.Rectangle {
                crunchiness.x + f32(index) * (segment_width + segment_gap),
                crunchiness.y + 28,
                segment_width,
                30,
            }
            if canvas2d.CheckCollisionPointRec(mouse, segment) {
                editor.options_focus = 6
                editor.gameplay_options.crunchiness = Crunchiness(index)
                crunchiness_apply(editor.gameplay_options.crunchiness)
                return
            }
        }
    }
    if content_hovered &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, options_menu_restore_bounds(panel, scroll_y)) {
        editor.options_focus = OPTIONS_RESTORE_FOCUS
        editor.gameplay_options = gameplay_options_default()
        crunchiness_apply(editor.gameplay_options.crunchiness)
        dither_apply(editor)
        ui_theme_set_mode(editor.gameplay_options.theme_mode)
        return
    }
    style := options_menu_row_bounds(panel, 7, scroll_y)
    style_gap := f32(6)
    style_segment_width := (style.width - style_gap * 2) / 3
    if content_hovered && pressed {
        for index in 0 ..< 3 {
            segment := canvas2d.Rectangle {
                style.x + f32(index) * (style_segment_width + style_gap),
                style.y + 28,
                style_segment_width,
                30,
            }
            if canvas2d.CheckCollisionPointRec(mouse, segment) {
                editor.options_focus = 7
                visual_style_set(editor, Visual_Style(index))
                return
            }
        }
    }
    dither := options_menu_row_bounds(panel, 8, scroll_y)
    dither_gap := f32(6)
    dither_segment_width := (dither.width - dither_gap * 2) / 3
    if editor.gameplay_options.visual_style == .Dither && content_hovered && pressed {
        for index in 1 ..= 3 {
            segment := canvas2d.Rectangle {
                dither.x + f32(index - 1) * (dither_segment_width + dither_gap),
                dither.y + 28,
                dither_segment_width,
                30,
            }
            if canvas2d.CheckCollisionPointRec(mouse, segment) {
                editor.options_focus = 8
                editor.gameplay_options.dither_mode = Dither_Mode(index)
                dither_apply(editor)
                return
            }
        }
    }
    if content_hovered &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 9, scroll_y)) {
        editor.options_focus = 9
        editor.gameplay_options.hdr_exposure = !editor.gameplay_options.hdr_exposure
        dither_apply(editor)
        return
    }
    if content_hovered &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 10, scroll_y)) {
        editor.options_focus = 10
        editor.gameplay_options.theme_mode = editor.gameplay_options.theme_mode == .Dark ? .Light : .Dark
        ui_theme_set_mode(editor.gameplay_options.theme_mode)
        return
    }
    if content_hovered &&
       pressed &&
       canvas2d.CheckCollisionPointRec(mouse, options_menu_row_bounds(panel, 11, scroll_y)) {
        editor.options_focus = 11
        editor.pause_screen = .Customization
        editor.customization_focus = 0
        return
    }
    if pressed && canvas2d.CheckCollisionPointRec(mouse, options_menu_back_bounds(panel)) {
        editor.options_focus = OPTIONS_BACK_FOCUS
        editor.pause_screen = editor.main_menu_active ? .Closed : .Pause
        editor.options_scroll_dragging = false
    }
}

main_menu_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil || !editor.main_menu_active do return
    if editor.pause_screen == .World_Select {
        world_select_process_input(editor, width, height, delta_seconds)
        return
    }
    if editor.pause_screen == .Customization {
        if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
            editor.pause_screen = .Options
            return
        }
        customization_scene_process_input(editor, width, height, delta_seconds)
        return
    }
    if editor.pause_screen == .Options {
        if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
            editor.pause_screen = .Closed
            editor.options_scroll_dragging = false
            return
        }
        options_menu_process_input(editor, width, height, delta_seconds)
        return
    }

    panel := main_menu_panel(width, height)
    mouse := canvas2d.GetMousePosition()
    mouse_delta := canvas2d.GetMouseDelta()
    mouse_active :=
        canvas2d.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    focus_direction := 0
    _, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    if canvas2d.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do focus_direction -= 1
    if canvas2d.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do focus_direction += 1
    if focus_direction == 0 do focus_direction = stick_y
    if focus_direction != 0 {
        editor.main_menu_focus = clamp(editor.main_menu_focus + focus_direction, 0, MAIN_MENU_BUTTON_COUNT - 1)
    }
    if mouse_active {
        for index in 0 ..< MAIN_MENU_BUTTON_COUNT {
            if canvas2d.CheckCollisionPointRec(mouse, main_menu_button_bounds(panel, index)) {
                editor.main_menu_focus = index
            }
        }
    }

    activated := -1
    if input_action_pressed(.Menu_Accept) do activated = editor.main_menu_focus
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        for index in 0 ..< MAIN_MENU_BUTTON_COUNT {
            if canvas2d.CheckCollisionPointRec(mouse, main_menu_button_bounds(panel, index)) do activated = index
        }
    }
    switch activated {
    case 0:
        editor.pause_screen = .World_Select
        editor.world_select_focus = WORLD_SELECT_MAP_FOCUS
    case 1:
        editor.pause_screen = .Options
        editor.options_focus = 0
        editor.options_scroll_y = 0
    case 2:
        editor.quit_requested = true
    }
}

world_select_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil do return
    if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
        editor.pause_screen = .Closed
        editor.main_menu_focus = 0
        return
    }

    panel := world_select_panel(width, height)
    map_bounds := world_select_map_bounds(panel)
    weather_bounds := world_select_weather_bounds(panel)
    start_bounds := world_select_start_bounds(panel)
    _, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    direction := 0
    if canvas2d.IsKeyPressed(.UP) || canvas2d.IsKeyPressed(.LEFT) || gamepad_pressed(.Dpad_Up) || gamepad_pressed(.Dpad_Left) do direction -= 1
    if canvas2d.IsKeyPressed(.DOWN) || canvas2d.IsKeyPressed(.RIGHT) || gamepad_pressed(.Dpad_Down) || gamepad_pressed(.Dpad_Right) do direction += 1
    if direction == 0 do direction = stick_y
    if direction != 0 {
        editor.world_select_focus = clamp(editor.world_select_focus + direction, 0, WORLD_SELECT_FOCUS_COUNT - 1)
    }

    mouse := canvas2d.GetMousePosition()
    mouse_delta := canvas2d.GetMouseDelta()
    mouse_active :=
        canvas2d.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    if mouse_active {
        if canvas2d.CheckCollisionPointRec(mouse, map_bounds) do editor.world_select_focus = WORLD_SELECT_MAP_FOCUS
        if canvas2d.CheckCollisionPointRec(mouse, weather_bounds) do editor.world_select_focus = WORLD_SELECT_WEATHER_FOCUS
        if canvas2d.CheckCollisionPointRec(mouse, start_bounds) do editor.world_select_focus = WORLD_SELECT_START_FOCUS
    }

    activated := input_action_pressed(.Menu_Accept)
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        activated =
            canvas2d.CheckCollisionPointRec(mouse, map_bounds) ||
            canvas2d.CheckCollisionPointRec(mouse, weather_bounds) ||
            canvas2d.CheckCollisionPointRec(mouse, start_bounds)
    }
    if !activated do return
    if editor.world_select_focus == WORLD_SELECT_WEATHER_FOCUS {
        editor.world_select_weather = !editor.world_select_weather
    } else if editor.world_select_focus == WORLD_SELECT_START_FOCUS {
        editor.main_menu_active = false
        editor.pause_screen = .Closed
        editor_spawn_into_world(editor)
    }
}

world_map_open :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map do return
    editor.pause_screen = .World_Map
    editor.world_select_focus = WORLD_SELECT_MAP_FOCUS
    editor.map_time = f32(canvas2d.GetTime())
    set_pointer_locked(false)
}

world_map_close :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.pause_screen = .Closed
    editor.map_time = f32(canvas2d.GetTime())
    set_pointer_locked(true)
}

world_map_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil do return
    if gamepad_pressed(.Left_Shoulder) || gamepad_pressed(.Right_Shoulder) {
        quest_log_open(editor)
        return
    }
    if gamepad_pressed(.Back) || input_action_pressed(.Menu_Cancel) {
        world_map_close(editor)
        return
    }

    panel := world_select_panel(width, height)
    map_bounds := world_select_map_bounds(panel)
    weather_bounds := world_select_weather_bounds(panel)
    return_bounds := world_select_start_bounds(panel)
    _, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    direction := 0
    if canvas2d.IsKeyPressed(.UP) || canvas2d.IsKeyPressed(.LEFT) || gamepad_pressed(.Dpad_Up) || gamepad_pressed(.Dpad_Left) do direction -= 1
    if canvas2d.IsKeyPressed(.DOWN) || canvas2d.IsKeyPressed(.RIGHT) || gamepad_pressed(.Dpad_Down) || gamepad_pressed(.Dpad_Right) do direction += 1
    if direction == 0 do direction = stick_y
    if direction != 0 {
        editor.world_select_focus = clamp(editor.world_select_focus + direction, 0, WORLD_SELECT_FOCUS_COUNT - 1)
    }

    mouse := canvas2d.GetMousePosition()
    mouse_delta := canvas2d.GetMouseDelta()
    mouse_active :=
        canvas2d.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    if mouse_active {
        if canvas2d.CheckCollisionPointRec(mouse, map_bounds) do editor.world_select_focus = WORLD_SELECT_MAP_FOCUS
        if canvas2d.CheckCollisionPointRec(mouse, weather_bounds) do editor.world_select_focus = WORLD_SELECT_WEATHER_FOCUS
        if canvas2d.CheckCollisionPointRec(mouse, return_bounds) do editor.world_select_focus = WORLD_SELECT_START_FOCUS
    }

    activated := input_action_pressed(.Menu_Accept)
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        activated =
            canvas2d.CheckCollisionPointRec(mouse, map_bounds) ||
            canvas2d.CheckCollisionPointRec(mouse, weather_bounds) ||
            canvas2d.CheckCollisionPointRec(mouse, return_bounds)
    }
    if !activated do return
    if editor.world_select_focus == WORLD_SELECT_WEATHER_FOCUS {
        editor.world_select_weather = !editor.world_select_weather
    } else if editor.world_select_focus == WORLD_SELECT_START_FOCUS {
        world_map_close(editor)
    }
}

pause_menu_process_input :: proc(editor: ^Editor, width, height: i32, delta_seconds: f32) {
    if editor == nil do return
    if editor.main_menu_active {
        main_menu_process_input(editor, width, height, delta_seconds)
        return
    }
    if !editor.in_map do return
    if canvas2d.GamepadAvailable() do editor.controller_disconnect_notice = false

    if editor.pause_screen == .Closed {
        if gamepad_pressed(.Back) {
            world_map_open(editor)
            return
        }
        if input_action_pressed(.Journal) {
            quest_log_open(editor)
            return
        }
        if input_action_pressed(.Pause) {
            pause_menu_open(editor)
        }
        return
    }


    if editor.pause_screen == .World_Map {
        world_map_process_input(editor, width, height, delta_seconds)
        return
    }

    if editor.pause_screen == .Journal {
        if gamepad_pressed(.Left_Shoulder) || gamepad_pressed(.Right_Shoulder) {
            world_map_open(editor)
            return
        }
        if input_action_pressed(.Journal) || input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
            quest_log_close(editor)
            return
        }
        quest_log_process_input(editor, width, height, delta_seconds)
        return
    }
    if editor.pause_screen == .Mail {
        if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
            editor.pause_screen = .Pause
            return
        }
        player_mail_process_input(editor, delta_seconds)
        return
    }
    if editor.pause_screen == .Scrapbook {
        scrapbook_process_input(editor, width, height, delta_seconds)
        return
    }
    if editor.pause_screen == .Photo {
        photo_mode_process_input(editor, delta_seconds)
        return
    }

    if input_action_pressed(.Menu_Cancel) || gamepad_pressed(.Start) {
        if editor.pause_screen == .Customization {
            editor.pause_screen = .Options
        } else if editor.pause_screen == .Options {
            editor.pause_screen = .Pause
        } else {
            pause_menu_resume(editor)
        }
        return
    }

    if editor.pause_screen == .Options {
        options_menu_process_input(editor, width, height, delta_seconds)
        return
    }
    if editor.pause_screen == .Customization {
        customization_scene_process_input(editor, width, height, delta_seconds)
        return
    }

    panel := pause_menu_panel(width, height, false)
    mouse := canvas2d.GetMousePosition()
    mouse_delta := canvas2d.GetMouseDelta()
    mouse_active :=
        canvas2d.IsMouseButtonPressed(.LEFT) || math.abs(mouse_delta.x) > .01 || math.abs(mouse_delta.y) > .01
    focus_direction := 0
    _, stick_y := game_input.menu_steps(
        &editor.runtime_input,
        gamepad_axis(.Left_X),
        gamepad_axis(.Left_Y),
        delta_seconds,
    )
    if canvas2d.IsKeyPressed(.UP) || gamepad_pressed(.Dpad_Up) do focus_direction -= 1
    if canvas2d.IsKeyPressed(.DOWN) || gamepad_pressed(.Dpad_Down) do focus_direction += 1
    if focus_direction == 0 do focus_direction = stick_y
    if focus_direction != 0 {
        editor.pause_focus = clamp(editor.pause_focus + focus_direction, 0, PAUSE_MENU_BUTTON_COUNT - 1)
    }
    if mouse_active {
        for index in 0 ..< PAUSE_MENU_BUTTON_COUNT {
            if canvas2d.CheckCollisionPointRec(mouse, pause_menu_button_bounds(panel, index)) {
                editor.pause_focus = index
            }
        }
    }
    activated := -1
    if input_action_pressed(.Menu_Accept) do activated = editor.pause_focus
    if canvas2d.IsMouseButtonPressed(.LEFT) {
        for index in 0 ..< PAUSE_MENU_BUTTON_COUNT {
            if canvas2d.CheckCollisionPointRec(mouse, pause_menu_button_bounds(panel, index)) do activated = index
        }
    }
    switch activated {
    case 0:
        pause_menu_resume(editor)
    case 1:
        player_mail_open(editor)
    case 2:
        scrapbook_open(editor)
    case 3:
        photo_mode_open(editor)
    case 4:
        editor.pause_screen = .Options
        editor.options_focus = 0
    case 5:
        if editor.vehicle_paint_scene {
            if vehicle_paint_close(editor) do editor.pause_screen = .Closed
        } else if markov_wreck_return_from_flight(editor) {
            // The wreck lab owns this flight session, so return to its
            // inspection view instead of the ordinary terrain editor.
        } else {
            pause_menu_return_to_editor(editor)
        }
    case 6:
        if editor.vehicle_paint_scene {
            if vehicle_paint_discard(editor) do editor.pause_screen = .Closed
        } else {
            editor.quit_requested = true
        }
    }
}

pause_menu_draw_header :: proc(panel: canvas2d.Rectangle, eyebrow, title: cstring) {
    if eyebrow != "" {
        ui_draw_text(.Data, eyebrow, {panel.x + 40, panel.y + 28}, .6, ui_theme_accent())
    }
    title_y := panel.y + 57
    if eyebrow == "" do title_y = panel.y + 38
    ui_draw_text(.Display, title, {panel.x + 40, title_y}, .5, ui_theme_text())
    canvas2d.DrawLineEx({panel.x + 40, panel.y + 96}, {panel.x + panel.width - 40, panel.y + 96}, 1, ui_theme_border())
}

options_menu_draw_toggle :: proc(bounds: canvas2d.Rectangle, label: cstring, enabled: bool, focused: bool = false) {
    hovered := pause_menu_pointer_enabled && canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), bounds)
    fill := hovered ? ui_theme_control_hover() : ui_theme_control()
    border := hovered ? ui_theme_border_strong() : ui_theme_border()
    if focused {
        fill = ui_theme_surface_elevated()
        border = ui_theme_focus()
    }
    canvas2d.DrawRectangleRounded(bounds, .1, 8, fill)
    canvas2d.DrawRectangleRoundedLinesEx(bounds, .1, 8, focused ? 2 : 1, border)
    ui_draw_text(.Label, label, {bounds.x + 14, bounds.y + 18}, .4, ui_theme_text())
    toggle := canvas2d.Rectangle{bounds.x + bounds.width - 70, bounds.y + 14, 56, 30}
    status: cstring = enabled ? "ON" : "OFF"
    status_size := ui_measure_text(.Data, status, .2)
    ui_draw_text(
        .Data,
        status,
        {toggle.x - status_size.x - 12, bounds.y + 19},
        .2,
        enabled ? ui_theme_positive() : ui_theme_disabled(),
    )

    // A soft underlay and outlined track keep the switch legible against both
    // the resting and hovered row colors.
    canvas2d.DrawRectangleRounded({toggle.x, toggle.y + 2, toggle.width, toggle.height}, 1, 12, ui_theme_scrim(65))
    track_fill := enabled ? ui_theme_positive() : ui_theme_disabled()
    track_border := enabled ? ui_theme_border_strong() : ui_theme_border()
    canvas2d.DrawRectangleRounded(toggle, 1, 12, track_fill)
    canvas2d.DrawRectangleRoundedLinesEx(toggle, 1, 12, 1, track_border)

    knob_x := enabled ? toggle.x + toggle.width - 15 : toggle.x + 15
    knob_center := canvas2d.Vector2{knob_x, toggle.y + toggle.height * .5}
    canvas2d.DrawCircleV({knob_center.x, knob_center.y + 2}, 11, ui_theme_scrim(80))
    canvas2d.DrawCircleV(knob_center, 11, ui_theme_surface_elevated())
    canvas2d.DrawCircleV(knob_center, 4, enabled ? ui_theme_positive() : ui_theme_disabled())
}

options_menu_draw_scrollbar :: proc(panel: canvas2d.Rectangle, scroll_y: f32) {
    track := options_menu_scrollbar_track(panel)
    thumb := options_menu_scrollbar_thumb(panel, scroll_y)
    canvas2d.DrawRectangleRounded(track, 1, 6, ui_theme_control(190))
    thumb_color := options_menu_max_scroll(panel) > 0 ? ui_theme_border_strong() : ui_theme_disabled(150)
    canvas2d.DrawRectangleRounded(thumb, 1, 8, thumb_color)
}

options_menu_draw :: proc(editor: ^Editor, panel: canvas2d.Rectangle) {
    pause_menu_draw_header(panel, "", "OPTIONS")
    navigation_hint: cstring = "ARROWS SELECT + ADJUST"
    if controller_prompt_active(editor) do navigation_hint = "D-PAD / LS SELECT + ADJUST"
    navigation_size := ui_measure_text(.Data, navigation_hint, .2)
    ui_draw_text(
        .Data,
        navigation_hint,
        {panel.x + panel.width - navigation_size.x - 40, panel.y + 64},
        .2,
        ui_theme_text_muted(),
    )
    viewport := options_menu_viewport(panel)
    scroll_y := clamp(editor.options_scroll_y, 0, options_menu_max_scroll(panel))
    canvas2d.BeginScissorMode(viewport)

    sensitivity := options_menu_row_bounds(panel, 0, scroll_y)
    sensitivity_hovered :=
        pause_menu_pointer_enabled && canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), sensitivity)
    sensitivity_fill := sensitivity_hovered ? ui_theme_control_hover() : ui_theme_control()
    sensitivity_border := sensitivity_hovered ? ui_theme_border_strong() : ui_theme_border()
    if editor.options_focus == 0 {
        sensitivity_fill = ui_theme_surface_elevated()
        sensitivity_border = ui_theme_focus()
    }
    canvas2d.DrawRectangleRounded(sensitivity, .1, 8, sensitivity_fill)
    canvas2d.DrawRectangleRoundedLinesEx(sensitivity, .1, 8, editor.options_focus == 0 ? 2 : 1, sensitivity_border)
    ui_draw_text(.Label, "LOOK SENSITIVITY", {sensitivity.x + 14, sensitivity.y + 8}, .4, ui_theme_text())
    percent := editor.gameplay_options.look_sensitivity / .012
    value := fmt.ctprintf("%d%%", int(percent * 100 + .5))
    value_size := ui_measure_text(.Data, value, .3)
    ui_draw_text(
        .Data,
        value,
        {sensitivity.x + sensitivity.width - value_size.x - 14, sensitivity.y + 8},
        .3,
        ui_theme_accent(),
    )
    track := options_menu_slider_track(sensitivity)
    canvas2d.DrawRectangleRounded(track, 1, 6, ui_theme_border(180))
    for tick in 0 ..= 4 {
        tick_x := track.x + track.width * f32(tick) / 4
        canvas2d.DrawLineEx(
            {tick_x, track.y - 2},
            {tick_x, track.y + track.height + 2},
            1,
            ui_theme_border_strong(120),
        )
    }
    normalized := clamp((editor.gameplay_options.look_sensitivity - .004) / .020, 0, 1)
    canvas2d.DrawRectangleRounded({track.x, track.y, track.width * normalized, track.height}, 1, 6, ui_theme_accent())
    knob := canvas2d.Vector2{track.x + track.width * normalized, track.y + track.height * .5}
    canvas2d.DrawCircleV({knob.x, knob.y + 2}, 9, ui_theme_scrim(80))
    canvas2d.DrawCircleV(knob, 9, ui_theme_surface_elevated())
    canvas2d.DrawCircleV(knob, 3, ui_theme_accent())

    sound_fx := options_menu_row_bounds(panel, 1, scroll_y)
    sound_fx_hovered :=
        pause_menu_pointer_enabled && canvas2d.CheckCollisionPointRec(canvas2d.GetMousePosition(), sound_fx)
    sound_fx_fill := sound_fx_hovered ? ui_theme_control_hover() : ui_theme_control()
    sound_fx_border := sound_fx_hovered ? ui_theme_border_strong() : ui_theme_border()
    if editor.options_focus == 1 {
        sound_fx_fill = ui_theme_surface_elevated()
        sound_fx_border = ui_theme_focus()
    }
    canvas2d.DrawRectangleRounded(sound_fx, .1, 8, sound_fx_fill)
    canvas2d.DrawRectangleRoundedLinesEx(sound_fx, .1, 8, editor.options_focus == 1 ? 2 : 1, sound_fx_border)
    ui_draw_text(.Label, "SOUND FX LEVEL", {sound_fx.x + 14, sound_fx.y + 8}, .4, ui_theme_text())
    sound_fx_value := fmt.ctprintf("%d%%", int(editor.gameplay_options.sound_fx_level * 100 + .5))
    sound_fx_value_size := ui_measure_text(.Data, sound_fx_value, .3)
    ui_draw_text(
        .Data,
        sound_fx_value,
        {sound_fx.x + sound_fx.width - sound_fx_value_size.x - 14, sound_fx.y + 8},
        .3,
        ui_theme_accent(),
    )
    sound_fx_track := options_menu_slider_track(sound_fx)
    canvas2d.DrawRectangleRounded(sound_fx_track, 1, 6, ui_theme_border(180))
    sound_fx_normalized := clamp(editor.gameplay_options.sound_fx_level, 0, 1)
    canvas2d.DrawRectangleRounded(
        {sound_fx_track.x, sound_fx_track.y, sound_fx_track.width * sound_fx_normalized, sound_fx_track.height},
        1,
        6,
        ui_theme_accent(),
    )
    sound_fx_knob := canvas2d.Vector2 {
        sound_fx_track.x + sound_fx_track.width * sound_fx_normalized,
        sound_fx_track.y + sound_fx_track.height * .5,
    }
    canvas2d.DrawCircleV({sound_fx_knob.x, sound_fx_knob.y + 2}, 9, ui_theme_scrim(80))
    canvas2d.DrawCircleV(sound_fx_knob, 9, ui_theme_surface_elevated())
    canvas2d.DrawCircleV(sound_fx_knob, 3, ui_theme_accent())

    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 2, scroll_y),
        "INVERT HORIZONTAL LOOK",
        editor.gameplay_options.invert_look_x,
        editor.options_focus == 2,
    )
    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 3, scroll_y),
        "INVERT VERTICAL LOOK",
        editor.gameplay_options.invert_look_y,
        editor.options_focus == 3,
    )
    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 4, scroll_y),
        "INVERT FLIGHT PITCH",
        editor.gameplay_options.invert_flight_pitch,
        editor.options_focus == 4,
    )
    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 5, scroll_y),
        "SHOW ON-SCREEN INFO",
        editor.gameplay_options.show_hud,
        editor.options_focus == 5,
    )

    crunchiness := options_menu_row_bounds(panel, 6, scroll_y)
    if editor.options_focus == 6 {
        canvas2d.DrawRectangleRounded(
            {crunchiness.x - 4, crunchiness.y - 4, crunchiness.width + 8, crunchiness.height + 8},
            .08,
            8,
            ui_theme_surface_elevated(220),
        )
        canvas2d.DrawRectangleRoundedLinesEx(
            {crunchiness.x - 4, crunchiness.y - 4, crunchiness.width + 8, crunchiness.height + 8},
            .08,
            8,
            2,
            ui_theme_focus(),
        )
    }
    ui_draw_text(.Label, "CRUNCHINESS", {crunchiness.x, crunchiness.y + 2}, .4, ui_theme_text())
    segment_gap := f32(6)
    segment_width := (crunchiness.width - segment_gap * 3) / 4
    for index in 0 ..< 4 {
        value := Crunchiness(index)
        pause_menu_button(
            {crunchiness.x + f32(index) * (segment_width + segment_gap), crunchiness.y + 28, segment_width, 30},
            crunchiness_label(value),
            editor.gameplay_options.crunchiness == value,
        )
    }

    style := options_menu_row_bounds(panel, 7, scroll_y)
    if editor.options_focus == 7 {
        canvas2d.DrawRectangleRounded(
            {style.x - 4, style.y - 4, style.width + 8, style.height + 8},
            .08,
            8,
            ui_theme_surface_elevated(220),
        )
        canvas2d.DrawRectangleRoundedLinesEx(
            {style.x - 4, style.y - 4, style.width + 8, style.height + 8},
            .08,
            8,
            2,
            ui_theme_focus(),
        )
    }
    ui_draw_text(.Label, "RENDER STYLE", {style.x, style.y + 2}, .4, ui_theme_text())
    style_gap := f32(6)
    style_segment_width := (style.width - style_gap * 2) / 3
    for index in 0 ..< 3 {
        value := Visual_Style(index)
        pause_menu_button(
            {style.x + f32(index) * (style_segment_width + style_gap), style.y + 28, style_segment_width, 30},
            visual_style_label(value),
            editor.gameplay_options.visual_style == value,
        )
    }

    dither := options_menu_row_bounds(panel, 8, scroll_y)
    if editor.options_focus == 8 && editor.gameplay_options.visual_style == .Dither {
        canvas2d.DrawRectangleRoundedLinesEx(
            {dither.x - 4, dither.y - 4, dither.width + 8, dither.height + 8},
            .08,
            8,
            2,
            ui_theme_focus(),
        )
    }
    dither_color := editor.gameplay_options.visual_style == .Dither ? ui_theme_text() : ui_theme_disabled()
    ui_draw_text(.Label, "DITHER PATTERN", {dither.x, dither.y + 2}, .4, dither_color)
    dither_gap := f32(6)
    dither_segment_width := (dither.width - dither_gap * 2) / 3
    for index in 1 ..= 3 {
        value := Dither_Mode(index)
        pause_menu_button(
            {dither.x + f32(index - 1) * (dither_segment_width + dither_gap), dither.y + 28, dither_segment_width, 30},
            dither_mode_label(value),
            editor.gameplay_options.visual_style == .Dither && editor.gameplay_options.dither_mode == value,
        )
    }

    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 9, scroll_y),
        "HDR EXPOSURE",
        editor.gameplay_options.hdr_exposure,
        editor.options_focus == 9,
    )

    options_menu_draw_toggle(
        options_menu_row_bounds(panel, 10, scroll_y),
        "DARK MODE",
        editor.gameplay_options.theme_mode == .Dark,
        editor.options_focus == 10,
    )

    pause_menu_button(
        options_menu_row_bounds(panel, 11, scroll_y),
        "CUSTOMIZE MOUSE",
        true,
        editor.options_focus == 11,
    )

    pause_menu_button(
        options_menu_restore_bounds(panel, scroll_y),
        "RESTORE DEFAULTS",
        false,
        editor.options_focus == OPTIONS_RESTORE_FOCUS,
    )
    canvas2d.EndScissorMode()
    options_menu_draw_scrollbar(panel, scroll_y)
    canvas2d.DrawLineEx(
        {panel.x + 30, viewport.y + viewport.height + 4},
        {panel.x + panel.width - 30, viewport.y + viewport.height + 4},
        1,
        ui_theme_border(),
    )
    pause_menu_button(options_menu_back_bounds(panel), "BACK", true, editor.options_focus == OPTIONS_BACK_FOCUS)
}

main_menu_draw :: proc(editor: ^Editor, width, height: i32, postcard: canvas2d.Texture) {
    if editor == nil || !editor.main_menu_active do return
    pause_menu_pointer_enabled = !controller_prompt_active(editor)

    if postcard.ready {
        canvas2d.DrawTexturePro(
            postcard,
            {0, 0, f32(postcard.width), f32(postcard.height)},
            {0, 0, f32(width), f32(height)},
            {255, 255, 255, 255},
        )
    } else {
        canvas2d.ClearBackground(ui_theme_border_strong())
    }
    canvas2d.DrawRectangle(0, 0, width, height, ui_theme_scrim(72))

    frame_width := max(i32(8), i32(min(f32(width) / 1280, f32(height) / 720) * 10))
    frame_color := ui_theme_surface_elevated()
    canvas2d.DrawRectangle(0, 0, width, frame_width, frame_color)
    canvas2d.DrawRectangle(0, height - frame_width, width, frame_width, frame_color)
    canvas2d.DrawRectangle(0, 0, frame_width, height, frame_color)
    canvas2d.DrawRectangle(width - frame_width, 0, frame_width, height, frame_color)

    if editor.pause_screen == .Customization {
        customization_scene_draw(editor, width, height)
        return
    }
    if editor.pause_screen == .Journal {
        quest_log_draw(editor, width, height)
        return
    }
    if editor.pause_screen == .Mail {
        player_mail_draw(editor, width, height)
        return
    }
    if editor.pause_screen == .Scrapbook {
        scrapbook_draw(editor, width, height)
        return
    }
    if editor.pause_screen == .World_Select {
        world_select_draw(editor, width, height, false)
        return
    }

    options := editor.pause_screen == .Options
    panel := options ? pause_menu_panel(width, height, true) : main_menu_panel(width, height)
    canvas2d.DrawRectangleRounded(panel, .035, 12, ui_theme_surface(245))
    canvas2d.DrawRectangleRoundedLinesEx(panel, .035, 12, 1, ui_theme_border_strong(220))
    if options {
        options_menu_draw(editor, panel)
        return
    }

    pause_menu_draw_header(panel, "GREETINGS FROM", "ADRIATIC")
    pause_menu_button(main_menu_button_bounds(panel, 0), "PLAY", true, editor.main_menu_focus == 0)
    pause_menu_button(main_menu_button_bounds(panel, 1), "OPTIONS", false, editor.main_menu_focus == 1)
    pause_menu_button(main_menu_button_bounds(panel, 2), "QUIT", false, editor.main_menu_focus == 2)
    hint: cstring = "ARROWS SELECT  |  ENTER CONFIRMS"
    if controller_prompt_active(editor) {
        hint = fmt.ctprintf("D-PAD / LS SELECTS  |  %s CONFIRMS", controller_face_label(editor, .South))
    }
    hint_size := ui_measure_text(.Data, hint, .2)
    ui_draw_text(
        .Data,
        hint,
        {panel.x + (panel.width - hint_size.x) * .5, panel.y + panel.height - 24},
        .2,
        ui_theme_text_muted(),
    )
}

scrapbook_card_bounds :: proc(panel: canvas2d.Rectangle, visible_index: int) -> canvas2d.Rectangle {
    gap := f32(14)
    card_width := (panel.width - 88 - gap * f32(SCRAPBOOK_COLUMNS - 1)) / SCRAPBOOK_COLUMNS
    card_height := min(f32(154), card_width * .86)
    column := visible_index % SCRAPBOOK_COLUMNS
    row := visible_index / SCRAPBOOK_COLUMNS
    return {
        panel.x + 44 + f32(column) * (card_width + gap),
        panel.y + 126 + f32(row) * (card_height + 14),
        card_width,
        card_height,
    }
}

scrapbook_draw_photo :: proc(bounds: canvas2d.Rectangle, photo: int) {
    image := canvas2d.Rectangle{bounds.x + 7, bounds.y + 7, bounds.width - 14, bounds.height - 43}
    texture := scrapbook_textures[photo]
    if !texture.ready do return
    source_width, source_height := f32(texture.width), f32(texture.height)
    source_aspect, target_aspect := source_width / source_height, image.width / image.height
    source := canvas2d.Rectangle{0, 0, source_width, source_height}
    if source_aspect > target_aspect {
        source.width = source_height * target_aspect
        source.x = (source_width - source.width) * .5
    } else {
        source.height = source_width / target_aspect
        source.y = (source_height - source.height) * .5
    }
    canvas2d.DrawTexturePro(texture, source, image)
}

scrapbook_draw :: proc(editor: ^Editor, width, height: i32) {
    if editor == nil do return
    scrapbook_init()
    panel := canvas2d.Rectangle{32, 26, f32(width) - 64, f32(height) - 52}
    canvas2d.DrawRectangleRounded(panel, .025, 12, ui_theme_surface())
    canvas2d.DrawRectangleRoundedLinesEx(panel, .025, 12, 1, ui_theme_border_strong())
    ui_draw_text(.Data, "BECK'S COLLECTION", {panel.x + 44, panel.y + 24}, .35, ui_theme_accent())
    title: cstring = scrapbook_manage ? "ARRANGE SCRAPBOOK" : "SCRAPBOOK"
    ui_draw_text(.Display, title, {panel.x + 44, panel.y + 48}, .54, ui_theme_text())
    sort_label := fmt.ctprintf("%s  ·  %d PHOTOS", scrapbook_sort_label(), scrapbook_visible_count())
    sort_size := ui_measure_text(.Data, sort_label, .22)
    ui_draw_text(
        .Data,
        sort_label,
        {panel.x + panel.width - 44 - sort_size.x, panel.y + 67},
        .22,
        ui_theme_text_muted(),
    )
    canvas2d.DrawLineEx(
        {panel.x + 44, panel.y + 101},
        {panel.x + panel.width - 44, panel.y + 101},
        1,
        ui_theme_border(),
    )

    count := scrapbook_visible_count()
    if count == 0 {
        empty: cstring = "NO PHOTOS IN THIS SCRAPBOOK"
        size := ui_measure_text(.Label, empty, .5)
        ui_draw_text(
            .Label,
            empty,
            {panel.x + (panel.width - size.x) * .5, panel.y + panel.height * .5},
            .5,
            ui_theme_text_muted(),
        )
    } else if scrapbook_viewing {
        photo := scrapbook_photo_at(scrapbook_focus)
        preview_width := min(panel.width * .68, f32(760))
        preview := canvas2d.Rectangle {
            panel.x + (panel.width - preview_width) * .5,
            panel.y + 120,
            preview_width,
            panel.height - 205,
        }
        canvas2d.DrawRectangleRounded(
            {preview.x - 10, preview.y - 10, preview.width + 20, preview.height + 56},
            .02,
            8,
            ui_theme_surface_elevated(),
        )
        scrapbook_draw_photo({preview.x, preview.y, preview.width, preview.height + 36}, photo)
        label := fmt.ctprintf(
            "%02d  /  %02d     PHOTO %02d",
            scrapbook_focus + 1,
            count,
            photo + 1,
        )
        ui_draw_text(.Label, label, {preview.x + 8, preview.y + preview.height + 19}, .38, ui_theme_text())
        if scrapbook_favorites[photo] do ui_draw_text(.Data, "FAVORITE", {preview.x + preview.width - 76, preview.y + 12}, .2, {255, 247, 228, 255})
    } else {
        for visible_index in 0 ..< count {
            photo := scrapbook_photo_at(visible_index)
            card := scrapbook_card_bounds(panel, visible_index)
            focused := visible_index == scrapbook_focus
            canvas2d.DrawRectangleRounded(card, .035, 7, focused ? ui_theme_surface_elevated() : ui_theme_control())
            canvas2d.DrawRectangleRoundedLinesEx(
                card,
                .035,
                7,
                focused ? 3 : 1,
                focused ? ui_theme_focus() : ui_theme_border(),
            )
            scrapbook_draw_photo(card, photo)
            photo_label := fmt.ctprintf("PHOTO %02d", photo + 1)
            ui_draw_text(.Data, photo_label, {card.x + 9, card.y + card.height - 28}, .19, ui_theme_text())
            saved_label: cstring = "SAVED"
            date_size := ui_measure_text(.Data, saved_label, .17)
            ui_draw_text(
                .Data,
                saved_label,
                {card.x + card.width - date_size.x - 9, card.y + card.height - 27},
                .17,
                ui_theme_text_muted(),
            )
            if scrapbook_favorites[photo] {
                canvas2d.DrawCircleV({card.x + card.width - 18, card.y + 18}, 10, ui_theme_accent())
                ui_draw_text(.Data, "*", {card.x + card.width - 21, card.y + 14}, .26, ui_theme_text_inverse())
            }
            if focused && scrapbook_manage {
                tag: cstring = scrapbook_sort == .Manual ? "MOVE" : "SWITCH TO CUSTOM ORDER"
                tag_size := ui_measure_text(.Data, tag, .17)
                canvas2d.DrawRectangleRounded(
                    {card.x + 8, card.y + 8, tag_size.x + 12, 18},
                    .2,
                    6,
                    ui_theme_scrim(170),
                )
                ui_draw_text(.Data, tag, {card.x + 14, card.y + 13}, .17, {255, 247, 228, 255})
            }
        }
    }
    hint: cstring = "ARROWS SELECT  ·  ENTER VIEW  ·  Q/E SORT  ·  F FAVORITE  ·  M MANAGE  ·  ESC BACK"
    if scrapbook_manage do hint = "LEFT/RIGHT REORDER  ·  BACKSPACE ARCHIVE  ·  F FAVORITE  ·  M DONE  ·  ESC BACK"
    if controller_prompt_active(editor) {
        hint =
            scrapbook_manage ? "D-PAD MOVE  ·  X FAVORITE  ·  B ARCHIVE  ·  Y DONE" : "D-PAD SELECT  ·  A VIEW  ·  LB/RB SORT  ·  X FAVORITE  ·  Y MANAGE"
    }
    hint_size := ui_measure_text(.Data, hint, .2)
    ui_draw_text(
        .Data,
        hint,
        {panel.x + (panel.width - hint_size.x) * .5, panel.y + panel.height - 22},
        .2,
        ui_theme_text_muted(),
    )
}

WORLD_MAP_HALF_EXTENT :: f32(terrain.WORLD_SIZE_METERS * .5)
// Keep posterization in the palette, not the coastline geometry. Equal sample
// counts preserve equal world-space resolution on the square orthographic map.
WORLD_MAP_COLUMNS :: 256
WORLD_MAP_ROWS :: 256

world_map_project :: #force_inline proc(map_bounds: canvas2d.Rectangle, world_x, world_z: f32) -> canvas2d.Vector2 {
    return {
        map_bounds.x + (world_x / WORLD_MAP_HALF_EXTENT + 1) * .5 * map_bounds.width,
        map_bounds.y + (world_z / WORLD_MAP_HALF_EXTENT + 1) * .5 * map_bounds.height,
    }
}

world_map_unproject :: #force_inline proc(map_bounds: canvas2d.Rectangle, screen_x, screen_y: f32) -> (f32, f32) {
    world_x := ((screen_x - map_bounds.x) / map_bounds.width * 2 - 1) * WORLD_MAP_HALF_EXTENT
    world_z := ((screen_y - map_bounds.y) / map_bounds.height * 2 - 1) * WORLD_MAP_HALF_EXTENT
    return world_x, world_z
}

world_map_ink :: #force_inline proc(editor: ^Editor, world_x, world_z: f32) -> canvas2d.Color {
    height := terrain.sample_height(&editor.project, 0, world_x, world_z)
    sea := editor.project.sea_level
    if height <= sea + .04 do return {31, 82, 101, 255}
    if height <= sea + .32 do return {197, 180, 119, 255}

    material := terrain.sample_material(&editor.project, 0, world_x, world_z)
    surface := terrain.classify_ground(material, height, sea)
    elevation := height - sea
    switch surface {
    case .Sand:
        return elevation < .85 ? canvas2d.Color{211, 194, 132, 255} : canvas2d.Color{190, 169, 108, 255}
    case .Dirt:
        return elevation < 2.4 ? canvas2d.Color{165, 145, 91, 255} : canvas2d.Color{142, 124, 78, 255}
    case .Grass:
        if elevation < 2.2 do return {111, 137, 91, 255}
        if elevation < 4.8 do return {82, 113, 76, 255}
        return {61, 88, 67, 255}
    }
    return {111, 137, 91, 255}
}

world_map_draw_orthographic :: proc(editor: ^Editor, map_bounds: canvas2d.Rectangle) {
    cell_width := map_bounds.width / f32(WORLD_MAP_COLUMNS)
    cell_height := map_bounds.height / f32(WORLD_MAP_ROWS)
    for row in 0 ..< WORLD_MAP_ROWS {
        for column in 0 ..< WORLD_MAP_COLUMNS {
            x := map_bounds.x + f32(column) * cell_width
            y := map_bounds.y + f32(row) * cell_height
            world_x, world_z := world_map_unproject(map_bounds, x + cell_width * .5, y + cell_height * .5)
            canvas2d.DrawRectangleRec({x, y, cell_width + 1, cell_height + 1}, world_map_ink(editor, world_x, world_z))
        }
    }

    // Roads and buildings are simplified into the same limited chart ink as
    // the terrain. Curves retain their authored control points.
    graph := &editor.project.road_graph
    route_ink := canvas2d.Color{235, 218, 165, 205}
    for edge in graph.edges[:graph.edge_count] {
        previous := graph.nodes[edge.from].position
        for segment in 1 ..= 10 {
            amount := f32(segment) / 10
            current := roads.edge_point(graph, edge, amount)
            canvas2d.DrawLineEx(
                world_map_project(map_bounds, previous.x, previous.z),
                world_map_project(map_bounds, current.x, current.z),
                1.35,
                route_ink,
            )
            previous = current
        }
    }
    building_ink := canvas2d.Color{74, 67, 52, 220}
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture && structure.kind != .Ruins do continue
        point := world_map_project(map_bounds, structure.center_x, structure.center_z)
        size := clamp(max(structure.width, structure.depth) / 32, f32(1.4), f32(4))
        canvas2d.DrawRectangleRec({point.x - size * .5, point.y - size * .5, size, size}, building_ink)
    }

    // The player's white-centered vermilion pin remains legible over every
    // posterized terrain band.
    player := world_map_project(map_bounds, editor.pilot.position.x, editor.pilot.position.z)
    canvas2d.DrawCircleV(player, 7, canvas2d.Color{181, 70, 43, 255})
    canvas2d.DrawCircleV(player, 2.5, canvas2d.Color{246, 235, 203, 255})
}

world_map_front_point :: #force_inline proc(
    editor: ^Editor,
    map_bounds: canvas2d.Rectangle,
    lateral, band_offset: f32,
    seconds_ago: f32 = 0,
) -> canvas2d.Vector2 {
    front := &editor.atmosphere.schedule.front
    age := max(editor.atmosphere.schedule.elapsed_seconds - front.start_seconds - seconds_ago, f32(0))
    center_x := front.origin[0] + front.direction[0] * front.speed * age
    center_z := front.origin[1] + front.direction[1] * front.speed * age
    distortion :=
        f32(math.sin(f64(lateral / max(front.cell_scale, f32(1)) * 2.1 + front.cell_phase))) * front.width * .12
    along := band_offset - distortion
    world_x := center_x + front.direction[0] * along - front.direction[1] * lateral
    world_z := center_z + front.direction[1] * along + front.direction[0] * lateral
    return world_map_project(map_bounds, world_x, world_z)
}

world_map_draw_front_curve :: proc(
    editor: ^Editor,
    map_bounds: canvas2d.Rectangle,
    band_offset, seconds_ago, thickness: f32,
    ink: canvas2d.Color,
    dashed: bool = false,
) {
    previous := world_map_front_point(editor, map_bounds, -7600, band_offset, seconds_ago)
    for segment in 1 ..= 64 {
        lateral := -7600 + f32(segment) / 64 * 15200
        current := world_map_front_point(editor, map_bounds, lateral, band_offset, seconds_ago)
        if !dashed || (segment / 3) % 2 == 0 {
            canvas2d.DrawLineEx(previous, current, thickness, ink)
        }
        previous = current
    }
}

world_map_draw_weather_key :: proc(map_bounds: canvas2d.Rectangle) {
    key := canvas2d.Rectangle{map_bounds.x + map_bounds.width - 232, map_bounds.y + 10, 220, 78}
    canvas2d.DrawRectangleRec(key, canvas2d.Color{22, 58, 71, 218})
    ui_draw_text(.Data, "FRONT KEY", {key.x + 9, key.y + 7}, .15, canvas2d.Color{242, 237, 211, 245})
    canvas2d.DrawLineEx({key.x + 10, key.y + 29}, {key.x + 35, key.y + 29}, 2.4, canvas2d.Color{184, 224, 231, 225})
    ui_draw_text(.Data, "NOW: RAIN/GUSTS/HAZE", {key.x + 43, key.y + 24}, .105, canvas2d.Color{226, 239, 241, 235})
    for dash in 0 ..< 3 {
        x := key.x + 10 + f32(dash) * 9
        canvas2d.DrawLineEx({x, key.y + 47}, {x + 5, key.y + 47}, 1.7, canvas2d.Color{159, 205, 215, 135})
    }
    ui_draw_text(.Data, "HISTORY: 1 / 2 MINUTES AGO", {key.x + 43, key.y + 42}, .105, canvas2d.Color{204, 224, 228, 220})
    canvas2d.DrawLineEx({key.x + 10, key.y + 65}, {key.x + 35, key.y + 65}, 2.5, canvas2d.Color{242, 231, 190, 235})
    canvas2d.DrawLineEx({key.x + 35, key.y + 65}, {key.x + 29, key.y + 61}, 2.5, canvas2d.Color{242, 231, 190, 235})
    canvas2d.DrawLineEx({key.x + 35, key.y + 65}, {key.x + 29, key.y + 69}, 2.5, canvas2d.Color{242, 231, 190, 235})
    ui_draw_text(.Data, "TRAVEL DIRECTION", {key.x + 43, key.y + 60}, .105, canvas2d.Color{225, 225, 205, 225})
}

world_map_draw_weather_front :: proc(editor: ^Editor, map_bounds: canvas2d.Rectangle) {
    front := &editor.atmosphere.schedule.front
    if editor.atmosphere.override != .Automatic || !front.active {
        eta_minutes := int(atmosphere.front_seconds_until_next(&editor.atmosphere) / 60 + .5)
        label := fmt.ctprintf("NO ACTIVE FRONT  /  NEXT WINDOW ~%d MIN", eta_minutes)
        ui_draw_text(.Data, label, {map_bounds.x + 16, map_bounds.y + 14}, .19, canvas2d.Color{222, 235, 237, 220})
        return
    }

    half_width := front.width * .5
    age := editor.atmosphere.schedule.elapsed_seconds - front.start_seconds
    // Weather-channel motion history: the same front boundaries at earlier
    // simulation times, dashed and faded so the displacement reads instantly.
    history_seconds := [2]f32{120, 60}
    history_alpha := [2]u8{55, 105}
    for history_index in 0 ..< len(history_seconds) {
        seconds_ago := history_seconds[history_index]
        if age < seconds_ago do continue
        history_ink := canvas2d.Color{151, 203, 214, history_alpha[history_index]}
        world_map_draw_front_curve(editor, map_bounds, -half_width, seconds_ago, 1.7, history_ink, true)
        world_map_draw_front_curve(editor, map_bounds, half_width, seconds_ago, 1.7, history_ink, true)
    }

    // Parallel rain bands make intensity readable while the heavy outer
    // isobars preserve the exact moving, cellular front boundary.
    for band in 0 ..= 10 {
        amount := f32(band) / 10
        offset := -half_width + amount * front.width
        center_weight := 1 - math.abs(amount * 2 - 1)
        ink := canvas2d.Color{126, 195, 211, u8(38 + center_weight * 54 * front.intensity)}
        world_map_draw_front_curve(editor, map_bounds, offset, 0, 2.2, ink)
    }
    boundary_ink := canvas2d.Color{184, 224, 231, 225}
    boundaries := [2]f32{-half_width, half_width}
    for side in boundaries {
        world_map_draw_front_curve(editor, map_bounds, side, 0, 2.4, boundary_ink)
    }

    // One chart arrow communicates travel direction without covering either
    // island with repeated symbols.
    tail_world := world_map_front_point(editor, map_bounds, 0, 0)
    head_world := world_map_front_point(editor, map_bounds, 0, 520)
    canvas2d.DrawLineEx(tail_world, head_world, 3, canvas2d.Color{242, 231, 190, 235})
    direction_x, direction_y := head_world.x - tail_world.x, head_world.y - tail_world.y
    length := max(f32(math.sqrt(f64(direction_x * direction_x + direction_y * direction_y))), f32(1))
    direction_x, direction_y = direction_x / length, direction_y / length
    normal_x, normal_y := -direction_y, direction_x
    canvas2d.DrawLineEx(
        head_world,
        {head_world.x - direction_x * 10 + normal_x * 6, head_world.y - direction_y * 10 + normal_y * 6},
        3,
        canvas2d.Color{242, 231, 190, 235},
    )
    canvas2d.DrawLineEx(
        head_world,
        {head_world.x - direction_x * 10 - normal_x * 6, head_world.y - direction_y * 10 - normal_y * 6},
        3,
        canvas2d.Color{242, 231, 190, 235},
    )

    progress := int(atmosphere.front_progress(&editor.atmosphere) * 100 + .5)
    label := fmt.ctprintf("FRONT %d  /  %d%%  /  %.1f M/S", int(front.event_id), progress, front.speed)
    ui_draw_text(.Data, label, {map_bounds.x + 16, map_bounds.y + 14}, .19, canvas2d.Color{238, 247, 248, 245})
    world_map_draw_weather_key(map_bounds)
}

world_select_draw :: proc(editor: ^Editor, width, height: i32, in_game: bool) {
    panel := world_select_panel(width, height)
    canvas2d.DrawRectangleRounded(panel, .035, 12, ui_theme_surface(248))
    canvas2d.DrawRectangleRoundedLinesEx(panel, .035, 12, 1, ui_theme_border_strong(220))
    pause_menu_draw_header(panel, in_game ? "CHART YOUR ROUTE" : "CHOOSE YOUR ROUTE", "WORLD MAP")

    map_bounds := world_select_map_bounds(panel)
    map_focused := editor.world_select_focus == WORLD_SELECT_MAP_FOCUS
    canvas2d.DrawRectangleRounded(map_bounds, .025, 12, canvas2d.Color{35, 93, 112, 255})
    canvas2d.DrawRectangleRoundedLinesEx(
        map_bounds,
        .025,
        12,
        map_focused ? 3 : 1,
        map_focused ? ui_theme_focus() : ui_theme_border_strong(),
    )

    canvas2d.BeginScissorMode(map_bounds)
    world_map_draw_orthographic(editor, map_bounds)

    if editor.world_select_weather {
        world_map_draw_weather_front(editor, map_bounds)
    }

    canvas2d.EndScissorMode()
    canvas2d.DrawRectangleRoundedLinesEx(
        map_bounds,
        .025,
        12,
        map_focused ? 3 : 1,
        map_focused ? ui_theme_focus() : ui_theme_border_strong(),
    )
    ui_draw_text(
        .Label,
        "ADRIATIC",
        {map_bounds.x + 18, map_bounds.y + map_bounds.height - 35},
        .34,
        {255, 255, 255, 255},
    )
    ui_draw_text(
        .Data,
        "WEST ISLAND  /  EAST ISLAND",
        {map_bounds.x + map_bounds.width - 236, map_bounds.y + map_bounds.height - 29},
        .18,
        {225, 239, 241, 230},
    )

    weather_bounds := world_select_weather_bounds(panel)
    weather_focused := editor.world_select_focus == WORLD_SELECT_WEATHER_FOCUS
    pause_menu_button(
        weather_bounds,
        editor.world_select_weather ? "WEATHER  ON" : "WEATHER  OFF",
        false,
        weather_focused,
    )
    start_bounds := world_select_start_bounds(panel)
    pause_menu_button(
        start_bounds,
        in_game ? "RETURN TO GAME" : "ENTER ADRIATIC",
        true,
        editor.world_select_focus == WORLD_SELECT_START_FOCUS,
    )

    hint: cstring =
        in_game ? "ARROWS SELECT  |  ENTER CONFIRMS  |  ESC CLOSES" : "ARROWS SELECT  |  ENTER CONFIRMS  |  ESC BACK"
    if controller_prompt_active(editor) {
        if in_game {
            hint = fmt.ctprintf(
                "LB / RB QUESTS  |  D-PAD / LS SELECTS  |  %s CONFIRMS  |  BACK CLOSES",
                controller_face_label(editor, .South),
            )
        } else {
            hint = fmt.ctprintf(
                "D-PAD / LS SELECTS  |  %s CONFIRMS  |  START BACK",
                controller_face_label(editor, .South),
            )
        }
    }
    size := ui_measure_text(.Data, hint, .2)
    ui_draw_text(
        .Data,
        hint,
        {panel.x + (panel.width - size.x) * .5, panel.y + panel.height - 24},
        .2,
        ui_theme_text_muted(),
    )
}

pause_menu_draw :: proc(editor: ^Editor, width, height: i32, postcard: canvas2d.Texture = {}) {
    if editor == nil || (!editor.main_menu_active && editor.pause_screen == .Closed) do return
    if editor.main_menu_active {
        main_menu_draw(editor, width, height, postcard)
        return
    }
    pause_menu_pointer_enabled = !controller_prompt_active(editor)
    if editor.pause_screen == .Photo {
        if editor.photo_capture_pending do return
        photo_filter_draw(editor)
        hint: cstring = "WASD MOVE  |  MOUSE LOOK  |  TAB FILTERS  |  F CAPTURE  |  ESC BACK"
        if controller_prompt_active(editor) {
            hint = fmt.ctprintf(
                "LS MOVE  |  RS LOOK  |  LB/RB DOWN/UP  |  %s CAPTURE  |  START BACK",
                controller_face_label(editor, .South),
            )
        }
        if canvas2d.GetTime() < editor.photo_capture_notice_until {
            hint = "PHOTO SAVED TO PICTURES / ADRIATIC"
        }
        size := ui_measure_text(.Data, hint, .25)
        bounds := canvas2d.Rectangle{(f32(width) - size.x) * .5 - 16, f32(height) - 48, size.x + 32, 30}
        canvas2d.DrawRectangleRounded(bounds, .2, 8, ui_theme_scrim(150))
        ui_draw_text(.Data, hint, {(f32(width) - size.x) * .5, f32(height) - 40}, .25, {255, 255, 255, 255})
        return
    }
    overlay_alpha: u8 = editor.pause_screen == .Customization ? 58 : 190
    canvas2d.DrawRectangle(0, 0, width, height, ui_theme_scrim(overlay_alpha))

    if editor.pause_screen == .World_Map {
        world_select_draw(editor, width, height, true)
        return
    }

    if editor.pause_screen == .Customization {
        customization_scene_draw(editor, width, height)
        return
    }
    if editor.pause_screen == .Journal {
        quest_log_draw(editor, width, height)
        return
    }
    if editor.pause_screen == .Mail {
        player_mail_draw(editor, width, height)
        return
    }
    if editor.pause_screen == .Scrapbook {
        scrapbook_draw(editor, width, height)
        return
    }

    options := editor.pause_screen == .Options
    panel := pause_menu_panel(width, height, options)
    canvas2d.DrawRectangleRounded(panel, .035, 12, ui_theme_surface())
    canvas2d.DrawRectangleRoundedLinesEx(panel, .035, 12, 1, ui_theme_border())

    if options {
        options_menu_draw(editor, panel)
        return
    }

    if editor.controller_disconnect_notice {
        pause_menu_draw_header(panel, "", "CONTROLLER DISCONNECTED")
    } else if editor.vehicle_paint_scene {
        pause_menu_draw_header(panel, "", "PAUSED")
    } else {
        pause_menu_draw_header(panel, "", "PAUSED")
    }
    pause_menu_button(pause_menu_button_bounds(panel, 0), "RESUME", true, editor.pause_focus == 0)
    unread := player_mail.unread_count(&editor.player_mail)
    mail_label: cstring = unread > 0 ? fmt.ctprintf("LETTERS · %d NEW", unread) : "LETTERS"
    pause_menu_button(pause_menu_button_bounds(panel, 1), mail_label, false, editor.pause_focus == 1)
    pause_menu_button(pause_menu_button_bounds(panel, 2), "SCRAPBOOK", false, editor.pause_focus == 2)
    pause_menu_button(pause_menu_button_bounds(panel, 3), "PHOTO MODE", false, editor.pause_focus == 3)
    pause_menu_button(pause_menu_button_bounds(panel, 4), "OPTIONS", false, editor.pause_focus == 4)
    return_label: cstring = "RETURN TO EDITOR"
    if editor.vehicle_paint_scene {
        return_label = "SAVE AND EXIT"
    } else if lab_scene_is_active(editor, "markov-wreck") && markov_wreck_postale_spawned {
        return_label = "RETURN TO WRECK LAB"
    }
    quit_label: cstring = editor.vehicle_paint_scene ? "DISCARD AND EXIT" : "QUIT TO DESKTOP"
    pause_menu_button(pause_menu_button_bounds(panel, 5), return_label, false, editor.pause_focus == 5)
    pause_menu_button(pause_menu_button_bounds(panel, 6), quit_label, false, editor.pause_focus == 6)
    hint: cstring
    if editor.controller_disconnect_notice {
        hint = "Reconnect the controller or continue with keyboard and mouse"
    } else if controller_prompt_active(editor) {
        hint = fmt.ctprintf(
            "D-PAD / LS selects  |  %s confirms  |  %s resumes",
            controller_face_label(editor, .South),
            controller_face_label(editor, .East),
        )
    } else {
        hint = "ESC resumes  |  ENTER confirms"
    }
    hint_size := ui_measure_text(.Data, hint, .3)
    ui_draw_text(
        .Data,
        hint,
        {panel.x + (panel.width - hint_size.x) * .5, panel.y + panel.height - 28},
        .3,
        ui_theme_text_muted(),
    )
}
