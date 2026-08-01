package main

import "core:mem"
import "core:os"
import "core:strings"

MOUSE_PREFERENCE_MAGIC :: [8]u8{'A', 'D', 'R', 'M', 'O', 'U', 'S', 'E'}
MOUSE_PREFERENCE_MAGIC_V5 :: [8]u8{'A', 'D', 'R', 'P', 'R', 'E', 'F', 'S'}
MOUSE_PREFERENCE_VERSION :: u32(5)

Mouse_Preference_Payload :: struct {
    fur:                 u8,
    pattern:             u8,
    headgear:            u8,
    scarf_enabled:       bool,
    scarf_color:         [4]u8,
    look_sensitivity:    f32,
    sound_fx_level:      f32,
    invert_look_x:       bool,
    invert_look_y:       bool,
    invert_flight_pitch: bool,
    show_hud:            bool,
    crunchiness:         u8,
    visual_style:        u8,
    dither_mode:         u8,
    hdr_exposure:        bool,
    theme_mode:          u8,
}

Mouse_Preference_File_V4 :: struct {
    magic:    [8]u8,
    version:  u32,
    payload:  Mouse_Preference_Payload,
    checksum: u64,
}

Mouse_Preference_Header :: struct {
    magic:        [8]u8,
    version:      u32,
    payload_size: u32,
}

Mouse_Preference_File :: struct {
    header:   Mouse_Preference_Header,
    payload:  Mouse_Preference_Payload,
    checksum: u64,
}

mouse_preference_checksum :: proc(payload: ^Mouse_Preference_Payload) -> u64 {
    bytes := mem.slice_ptr(cast([^]u8)payload, size_of(payload^))
    hash: u64 = 14695981039346656037
    for byte in bytes {
        hash = (hash ~ u64(byte)) * 1099511628211
    }
    return hash
}

Mouse_Preference_Payload_V1 :: struct {
    fur:           u8,
    pattern:       u8,
    headgear:      u8,
    scarf_enabled: bool,
    scarf_color:   [4]u8,
}

Mouse_Preference_File_V1 :: struct {
    magic:    [8]u8,
    version:  u32,
    payload:  Mouse_Preference_Payload_V1,
    checksum: u64,
}

Mouse_Preference_Payload_V2 :: struct {
    fur:                 u8,
    pattern:             u8,
    headgear:            u8,
    scarf_enabled:       bool,
    scarf_color:         [4]u8,
    look_sensitivity:    f32,
    invert_look_x:       bool,
    invert_look_y:       bool,
    invert_flight_pitch: bool,
    show_hud:            bool,
    crunchiness:         u8,
    dither_mode:         u8,
    hdr_exposure:        bool,
    theme_mode:          u8,
}

Mouse_Preference_File_V2 :: struct {
    magic:    [8]u8,
    version:  u32,
    payload:  Mouse_Preference_Payload_V2,
    checksum: u64,
}

Mouse_Preference_Payload_V3 :: struct {
    fur:                 u8,
    pattern:             u8,
    headgear:            u8,
    scarf_enabled:       bool,
    scarf_color:         [4]u8,
    look_sensitivity:    f32,
    sound_fx_level:      f32,
    invert_look_x:       bool,
    invert_look_y:       bool,
    invert_flight_pitch: bool,
    show_hud:            bool,
    crunchiness:         u8,
    dither_mode:         u8,
    hdr_exposure:        bool,
    theme_mode:          u8,
}

Mouse_Preference_File_V3 :: struct {
    magic:    [8]u8,
    version:  u32,
    payload:  Mouse_Preference_Payload_V3,
    checksum: u64,
}

mouse_preference_checksum_v3 :: proc(payload: ^Mouse_Preference_Payload_V3) -> u64 {
    bytes := mem.slice_ptr(cast([^]u8)payload, size_of(payload^))
    hash: u64 = 14695981039346656037
    for byte in bytes {
        hash = (hash ~ u64(byte)) * 1099511628211
    }
    return hash
}

mouse_preference_legacy_style :: proc(mode: Dither_Mode) -> Visual_Style {
    return mode == .Off ? .Standard : .Dither
}

mouse_preference_checksum_v2 :: proc(payload: ^Mouse_Preference_Payload_V2) -> u64 {
    bytes := mem.slice_ptr(cast([^]u8)payload, size_of(payload^))
    hash: u64 = 14695981039346656037
    for byte in bytes {
        hash = (hash ~ u64(byte)) * 1099511628211
    }
    return hash
}

mouse_preference_checksum_v1 :: proc(payload: ^Mouse_Preference_Payload_V1) -> u64 {
    bytes := mem.slice_ptr(cast([^]u8)payload, size_of(payload^))
    hash: u64 = 14695981039346656037
    for byte in bytes {
        hash = (hash ~ u64(byte)) * 1099511628211
    }
    return hash
}

mouse_preference_payload :: proc(editor: ^Editor) -> Mouse_Preference_Payload {
    return {
        fur = u8(editor.mouse_fur),
        pattern = u8(editor.mouse_pattern),
        headgear = u8(editor.mouse_headgear),
        scarf_enabled = editor.mouse_scarf_enabled,
        scarf_color = {
            editor.mouse_scarf_color.r,
            editor.mouse_scarf_color.g,
            editor.mouse_scarf_color.b,
            editor.mouse_scarf_color.a,
        },
        look_sensitivity = editor.gameplay_options.look_sensitivity,
        sound_fx_level = editor.gameplay_options.sound_fx_level,
        invert_look_x = editor.gameplay_options.invert_look_x,
        invert_look_y = editor.gameplay_options.invert_look_y,
        invert_flight_pitch = editor.gameplay_options.invert_flight_pitch,
        show_hud = editor.gameplay_options.show_hud,
        crunchiness = u8(editor.gameplay_options.crunchiness),
        visual_style = u8(editor.gameplay_options.visual_style),
        dither_mode = u8(editor.gameplay_options.dither_mode),
        hdr_exposure = editor.gameplay_options.hdr_exposure,
        theme_mode = u8(editor.gameplay_options.theme_mode),
    }
}

mouse_preference_save_directory :: proc(allocator := context.allocator) -> (string, bool) {
    base, err := os.user_data_dir(allocator)
    if err != nil || base == "" do return "", false
    path, concatenate_err := strings.concatenate({base, "/Adriatic"}, allocator)
    return path, concatenate_err == nil
}

mouse_preference_save_path :: proc(allocator := context.allocator) -> (string, bool) {
    directory, ok := mouse_preference_save_directory(allocator)
    if !ok do return "", false
    path, err := strings.concatenate({directory, "/mouse-preference.bin"}, allocator)
    return path, err == nil
}

mouse_preference_save_to_path :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || path == "" do return false
    file_data := Mouse_Preference_File {
        header = {
            magic = MOUSE_PREFERENCE_MAGIC_V5,
            version = MOUSE_PREFERENCE_VERSION,
            payload_size = u32(size_of(Mouse_Preference_Payload)),
        },
        payload = mouse_preference_payload(editor),
    }
    file_data.checksum = mouse_preference_checksum(&file_data.payload)
    bytes := mem.slice_ptr(cast([^]u8)&file_data, size_of(file_data))
    temporary, temporary_err := strings.concatenate({path, ".tmp"}, context.temp_allocator)
    if temporary_err != nil do return false
    file, open_err := os.create(temporary)
    if open_err != nil do return false
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

mouse_preference_load_from_path :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || path == "" do return false
    bytes, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil do return false
    if len(bytes) == size_of(Mouse_Preference_File_V1) {
        file_data := cast(^Mouse_Preference_File_V1)raw_data(bytes)
        payload := &file_data.payload
        if file_data.magic != MOUSE_PREFERENCE_MAGIC ||
           file_data.version != 1 ||
           file_data.checksum != mouse_preference_checksum_v1(payload) ||
           int(payload.fur) >= CUSTOMIZATION_COLOR_COUNT ||
           int(payload.pattern) >= CUSTOMIZATION_PATTERN_COUNT ||
           int(payload.headgear) >= CUSTOMIZATION_HEADGEAR_COUNT {
            return false
        }
        editor.mouse_fur = Mouse_Fur(payload.fur)
        editor.mouse_pattern = Mouse_Fur_Pattern(payload.pattern)
        editor.mouse_headgear = Mouse_Accessory(payload.headgear)
        editor.mouse_scarf_enabled = payload.scarf_enabled
        editor.mouse_scarf_color = {
            payload.scarf_color[0],
            payload.scarf_color[1],
            payload.scarf_color[2],
            payload.scarf_color[3],
        }
        return true
    }
    if len(bytes) == size_of(Mouse_Preference_File_V2) {
        file_data := cast(^Mouse_Preference_File_V2)raw_data(bytes)
        payload := &file_data.payload
        if file_data.magic != MOUSE_PREFERENCE_MAGIC ||
           file_data.version != 2 ||
           file_data.checksum != mouse_preference_checksum_v2(payload) ||
           int(payload.fur) >= CUSTOMIZATION_COLOR_COUNT ||
           int(payload.pattern) >= CUSTOMIZATION_PATTERN_COUNT ||
           int(payload.headgear) >= CUSTOMIZATION_HEADGEAR_COUNT ||
           payload.look_sensitivity < .004 ||
           payload.look_sensitivity > .024 ||
           int(payload.crunchiness) > int(Crunchiness.Full) ||
           int(payload.dither_mode) > int(Dither_Mode.Matriax_8) ||
           int(payload.theme_mode) > int(UI_Theme_Mode.Dark) {
            return false
        }
        editor.mouse_fur = Mouse_Fur(payload.fur)
        editor.mouse_pattern = Mouse_Fur_Pattern(payload.pattern)
        editor.mouse_headgear = Mouse_Accessory(payload.headgear)
        editor.mouse_scarf_enabled = payload.scarf_enabled
        editor.mouse_scarf_color = {
            payload.scarf_color[0],
            payload.scarf_color[1],
            payload.scarf_color[2],
            payload.scarf_color[3],
        }
        editor.gameplay_options = {
            look_sensitivity    = payload.look_sensitivity,
            sound_fx_level      = 1,
            invert_look_x       = payload.invert_look_x,
            invert_look_y       = payload.invert_look_y,
            invert_flight_pitch = payload.invert_flight_pitch,
            show_hud            = payload.show_hud,
            crunchiness         = Crunchiness(payload.crunchiness),
            visual_style        = mouse_preference_legacy_style(Dither_Mode(payload.dither_mode)),
            dither_mode         = Dither_Mode(payload.dither_mode),
            hdr_exposure        = payload.hdr_exposure,
            theme_mode          = UI_Theme_Mode(payload.theme_mode),
        }
        return true
    }
    // V3 and V4 are both 48 bytes on the current ABI: the visual_style byte
    // added in V4 consumed tail padding. Select the legacy decoder by version
    // as well as size so a V4 file can reach its decoder below.
    if len(bytes) == size_of(Mouse_Preference_File_V3) &&
       (cast(^Mouse_Preference_File_V3)raw_data(bytes)).version == 3 {
        file_data := cast(^Mouse_Preference_File_V3)raw_data(bytes)
        payload := &file_data.payload
        if file_data.magic != MOUSE_PREFERENCE_MAGIC ||
           file_data.version != 3 ||
           file_data.checksum != mouse_preference_checksum_v3(payload) ||
           int(payload.fur) >= CUSTOMIZATION_COLOR_COUNT ||
           int(payload.pattern) >= CUSTOMIZATION_PATTERN_COUNT ||
           int(payload.headgear) >= CUSTOMIZATION_HEADGEAR_COUNT ||
           payload.look_sensitivity < .004 ||
           payload.look_sensitivity > .024 ||
           payload.sound_fx_level < 0 ||
           payload.sound_fx_level > 1 ||
           int(payload.crunchiness) > int(Crunchiness.Full) ||
           int(payload.dither_mode) > int(Dither_Mode.Matriax_8) ||
           int(payload.theme_mode) > int(UI_Theme_Mode.Dark) {
            return false
        }
        editor.mouse_fur = Mouse_Fur(payload.fur)
        editor.mouse_pattern = Mouse_Fur_Pattern(payload.pattern)
        editor.mouse_headgear = Mouse_Accessory(payload.headgear)
        editor.mouse_scarf_enabled = payload.scarf_enabled
        editor.mouse_scarf_color = {
            payload.scarf_color[0], payload.scarf_color[1], payload.scarf_color[2], payload.scarf_color[3],
        }
        editor.gameplay_options = {
            look_sensitivity    = payload.look_sensitivity,
            sound_fx_level      = payload.sound_fx_level,
            invert_look_x       = payload.invert_look_x,
            invert_look_y       = payload.invert_look_y,
            invert_flight_pitch = payload.invert_flight_pitch,
            show_hud            = payload.show_hud,
            crunchiness         = Crunchiness(payload.crunchiness),
            visual_style        = mouse_preference_legacy_style(Dither_Mode(payload.dither_mode)),
            dither_mode         = Dither_Mode(payload.dither_mode),
            hdr_exposure        = payload.hdr_exposure,
            theme_mode          = UI_Theme_Mode(payload.theme_mode),
        }
        return true
    }
    if len(bytes) == size_of(Mouse_Preference_File_V4) {
        file_data := cast(^Mouse_Preference_File_V4)raw_data(bytes)
        payload := &file_data.payload
        if file_data.magic != MOUSE_PREFERENCE_MAGIC ||
           file_data.version != 4 ||
           file_data.checksum != mouse_preference_checksum(payload) ||
           int(payload.fur) >= CUSTOMIZATION_COLOR_COUNT ||
           int(payload.pattern) >= CUSTOMIZATION_PATTERN_COUNT ||
           int(payload.headgear) >= CUSTOMIZATION_HEADGEAR_COUNT ||
           payload.look_sensitivity < .004 ||
           payload.look_sensitivity > .024 ||
           payload.sound_fx_level < 0 ||
           payload.sound_fx_level > 1 ||
           int(payload.crunchiness) > int(Crunchiness.Full) ||
           int(payload.visual_style) > 2 ||
           int(payload.dither_mode) > int(Dither_Mode.Matriax_8) ||
           (Visual_Style(payload.visual_style) == .Dither && payload.dither_mode == u8(Dither_Mode.Off)) ||
           int(payload.theme_mode) > int(UI_Theme_Mode.Dark) {
            return false
        }
        editor.mouse_fur = Mouse_Fur(payload.fur)
        editor.mouse_pattern = Mouse_Fur_Pattern(payload.pattern)
        editor.mouse_headgear = Mouse_Accessory(payload.headgear)
        editor.mouse_scarf_enabled = payload.scarf_enabled
        editor.mouse_scarf_color = {
            payload.scarf_color[0], payload.scarf_color[1], payload.scarf_color[2], payload.scarf_color[3],
        }
        editor.gameplay_options = {
            look_sensitivity = payload.look_sensitivity,
            sound_fx_level = payload.sound_fx_level,
            invert_look_x = payload.invert_look_x,
            invert_look_y = payload.invert_look_y,
            invert_flight_pitch = payload.invert_flight_pitch,
            show_hud = payload.show_hud,
            crunchiness = Crunchiness(payload.crunchiness),
            visual_style = payload.visual_style == 2 ? .Standard : Visual_Style(payload.visual_style),
            dither_mode = Dither_Mode(payload.dither_mode),
            hdr_exposure = payload.hdr_exposure,
            theme_mode = UI_Theme_Mode(payload.theme_mode),
        }
        return true
    }
    if len(bytes) != size_of(Mouse_Preference_File) do return false
    file_data := cast(^Mouse_Preference_File)raw_data(bytes)
    payload := &file_data.payload
    if file_data.header.magic != MOUSE_PREFERENCE_MAGIC_V5 ||
       file_data.header.version != MOUSE_PREFERENCE_VERSION ||
       file_data.header.payload_size != u32(size_of(Mouse_Preference_Payload)) ||
       file_data.checksum != mouse_preference_checksum(payload) ||
       int(payload.fur) >= CUSTOMIZATION_COLOR_COUNT ||
       int(payload.pattern) >= CUSTOMIZATION_PATTERN_COUNT ||
       int(payload.headgear) >= CUSTOMIZATION_HEADGEAR_COUNT ||
       payload.look_sensitivity < .004 ||
       payload.look_sensitivity > .024 ||
       payload.sound_fx_level < 0 ||
       payload.sound_fx_level > 1 ||
       int(payload.crunchiness) > int(Crunchiness.Full) ||
       // Value 2 was the removed Painterly style. Accept it for backward
       // compatibility and restore it as Standard below.
       int(payload.visual_style) > 2 ||
       int(payload.dither_mode) > int(Dither_Mode.Matriax_8) ||
       (Visual_Style(payload.visual_style) == .Dither && payload.dither_mode == u8(Dither_Mode.Off)) ||
       int(payload.theme_mode) > int(UI_Theme_Mode.Dark) {
        return false
    }
    editor.mouse_fur = Mouse_Fur(payload.fur)
    editor.mouse_pattern = Mouse_Fur_Pattern(payload.pattern)
    editor.mouse_headgear = Mouse_Accessory(payload.headgear)
    editor.mouse_scarf_enabled = payload.scarf_enabled
    editor.mouse_scarf_color = {
        payload.scarf_color[0],
        payload.scarf_color[1],
        payload.scarf_color[2],
        payload.scarf_color[3],
    }
    editor.gameplay_options = {
        look_sensitivity    = payload.look_sensitivity,
        sound_fx_level      = payload.sound_fx_level,
        invert_look_x       = payload.invert_look_x,
        invert_look_y       = payload.invert_look_y,
        invert_flight_pitch = payload.invert_flight_pitch,
        show_hud            = payload.show_hud,
        crunchiness         = Crunchiness(payload.crunchiness),
        visual_style        = payload.visual_style == 2 ? .Standard : Visual_Style(payload.visual_style),
        dither_mode         = Dither_Mode(payload.dither_mode),
        hdr_exposure        = payload.hdr_exposure,
        theme_mode          = UI_Theme_Mode(payload.theme_mode),
    }
    return true
}

mouse_preference_save :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    directory, directory_ok := mouse_preference_save_directory(context.temp_allocator)
    if !directory_ok do return false
    directory_err := os.make_directory_all(directory)
    if directory_err != nil && directory_err != .Exist do return false
    path, path_ok := mouse_preference_save_path(context.temp_allocator)
    return path_ok && mouse_preference_save_to_path(editor, path)
}

mouse_preference_load :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    path, ok := mouse_preference_save_path(context.temp_allocator)
    return ok && mouse_preference_load_from_path(editor, path)
}
