package main

import toml "zelda_engine:toml"
import "core:os"
import "core:strings"
import canvas2d "zelda_engine:canvas2d"

PLAYER_SETTINGS_FILENAME :: "player-settings.toml"
PLAYER_SETTINGS_VERSION :: i64(1)

Player_Mouse_Settings :: struct {
    fur:           Mouse_Fur,
    pattern:       Mouse_Fur_Pattern,
    headgear:      Mouse_Accessory,
    scarf_enabled: bool,
    scarf_color:   [4]u8,
}

Player_Settings_Document :: struct {
    version:  i64,
    gameplay: Gameplay_Options,
    mouse:    Player_Mouse_Settings,
}

player_settings_capture :: proc(editor: ^Editor) -> Player_Settings_Document {
    if editor == nil do return {version = PLAYER_SETTINGS_VERSION, gameplay = gameplay_options_default()}
    return {
        version = PLAYER_SETTINGS_VERSION,
        gameplay = editor.gameplay_options,
        mouse = {
            fur = editor.mouse_fur,
            pattern = editor.mouse_pattern,
            headgear = editor.mouse_headgear,
            scarf_enabled = editor.mouse_scarf_enabled,
            scarf_color = {
                editor.mouse_scarf_color.r,
                editor.mouse_scarf_color.g,
                editor.mouse_scarf_color.b,
                editor.mouse_scarf_color.a,
            },
        },
    }
}

player_settings_valid :: proc(settings: ^Gameplay_Options) -> bool {
    if settings == nil do return false
    return(
        settings.look_sensitivity >= .004 &&
        settings.look_sensitivity <= .024 &&
        settings.sound_fx_level >= 0 &&
        settings.sound_fx_level <= 1 &&
        settings.controller_stick_deadzone >= 0 &&
        settings.controller_stick_deadzone <= .5 &&
        settings.controller_trigger_deadzone >= 0 &&
        settings.controller_trigger_deadzone <= .5 &&
        int(settings.crunchiness) >= int(Crunchiness.P240) &&
        int(settings.crunchiness) <= int(Crunchiness.Full) &&
        int(settings.visual_style) >= int(Visual_Style.Standard) &&
        int(settings.visual_style) <= int(Visual_Style.Dither) &&
        int(settings.dither_mode) >= int(Dither_Mode.Off) &&
        int(settings.dither_mode) <= int(Dither_Mode.Matriax_8) &&
        (settings.visual_style != .Dither || settings.dither_mode != .Off) &&
        int(settings.theme_mode) >= int(UI_Theme_Mode.Light) &&
        int(settings.theme_mode) <= int(UI_Theme_Mode.Dark) &&
        int(settings.anti_aliasing) >= int(Anti_Aliasing.Off) &&
        int(settings.anti_aliasing) <= int(Anti_Aliasing.MSAA_4X) \
    )
}

player_settings_valid_mouse :: proc(settings: ^Player_Mouse_Settings) -> bool {
    if settings == nil do return false
    return(
        int(settings.fur) >= 0 &&
        int(settings.fur) < CUSTOMIZATION_COLOR_COUNT &&
        int(settings.pattern) >= 0 &&
        int(settings.pattern) < CUSTOMIZATION_PATTERN_COUNT &&
        int(settings.headgear) >= 0 &&
        int(settings.headgear) < CUSTOMIZATION_HEADGEAR_COUNT \
    )
}

player_settings_directory :: proc(allocator := context.allocator) -> (string, bool) {
    base, err := os.user_config_dir(allocator)
    if err != nil || base == "" do return "", false
    directory, concatenate_err := strings.concatenate({base, "/Adriatic"}, allocator)
    return directory, concatenate_err == nil
}

player_settings_path :: proc(allocator := context.allocator) -> (string, bool) {
    directory, ok := player_settings_directory(allocator)
    if !ok do return "", false
    path, err := strings.concatenate({directory, "/", PLAYER_SETTINGS_FILENAME}, allocator)
    return path, err == nil
}

player_settings_save_to_path :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || path == "" do return false
    document := player_settings_capture(editor)
    table := toml.marshal(&document, context.temp_allocator)
    defer toml.deep_delete(table, context.temp_allocator)
    encoded := toml.emit(table)
    defer delete_string(encoded)

    temporary, temporary_err := strings.concatenate({path, ".tmp"}, context.temp_allocator)
    if temporary_err != nil do return false
    file, open_err := os.create(temporary)
    if open_err != nil do return false
    bytes := transmute([]u8)encoded
    written, write_err := os.write(file, bytes)
    close_err := os.close(file)
    if write_err != nil || close_err != nil || written != len(bytes) {
        _ = os.remove(temporary)
        return false
    }
    if os.rename(temporary, path) == nil do return true
    _ = os.remove(path)
    return os.rename(temporary, path) == nil
}

player_settings_load_from_path :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || path == "" do return false
    bytes, read_err := os.read_entire_file(path, context.temp_allocator)
    if read_err != nil || len(bytes) == 0 do return false

    document := player_settings_capture(editor)
    if toml.unmarshal_string(string(bytes), &document, context.temp_allocator) != .None do return false
    if document.version != PLAYER_SETTINGS_VERSION ||
       !player_settings_valid(&document.gameplay) ||
       !player_settings_valid_mouse(&document.mouse) {
        return false
    }

    editor.gameplay_options = document.gameplay
    editor.mouse_fur = document.mouse.fur
    editor.mouse_pattern = document.mouse.pattern
    editor.mouse_headgear = document.mouse.headgear
    editor.mouse_scarf_enabled = document.mouse.scarf_enabled
    editor.mouse_scarf_color = {
        document.mouse.scarf_color[0],
        document.mouse.scarf_color[1],
        document.mouse.scarf_color[2],
        document.mouse.scarf_color[3],
    }
    return true
}

player_settings_save :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    directory, directory_ok := player_settings_directory(context.temp_allocator)
    if !directory_ok do return false
    directory_err := os.make_directory_all(directory)
    if directory_err != nil && directory_err != .Exist do return false
    path, path_ok := player_settings_path(context.temp_allocator)
    return path_ok && player_settings_save_to_path(editor, path)
}

player_settings_load :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    path, ok := player_settings_path(context.temp_allocator)
    return ok && player_settings_load_from_path(editor, path)
}

player_settings_apply :: proc(editor: ^Editor) {
    if editor == nil do return
    controller_deadzone_apply(editor.gameplay_options)
    canvas2d.SetVSyncEnabled(editor.gameplay_options.vsync)
    crunchiness_apply(editor.gameplay_options.crunchiness)
    anti_aliasing_apply(editor.gameplay_options.anti_aliasing)
    dither_apply(editor)
    ui_theme_set_mode(editor.gameplay_options.theme_mode)
}
