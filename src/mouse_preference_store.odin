package main

import "core:mem"
import "core:os"
import "core:strings"

MOUSE_PREFERENCE_MAGIC :: [8]u8{'A', 'D', 'R', 'M', 'O', 'U', 'S', 'E'}
MOUSE_PREFERENCE_VERSION :: u32(1)

Mouse_Preference_Payload :: struct {
    fur:           u8,
    pattern:       u8,
    headgear:      u8,
    scarf_enabled: bool,
    scarf_color:   [4]u8,
}

Mouse_Preference_File :: struct {
    magic:    [8]u8,
    version:  u32,
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
        magic   = MOUSE_PREFERENCE_MAGIC,
        version = MOUSE_PREFERENCE_VERSION,
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
    if err != nil || len(bytes) != size_of(Mouse_Preference_File) do return false
    file_data := cast(^Mouse_Preference_File)raw_data(bytes)
    payload := &file_data.payload
    if file_data.magic != MOUSE_PREFERENCE_MAGIC ||
       file_data.version != MOUSE_PREFERENCE_VERSION ||
       file_data.checksum != mouse_preference_checksum(payload) ||
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

mouse_preference_save :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    directory, directory_ok := mouse_preference_save_directory(context.temp_allocator)
    if !directory_ok || os.make_directory_all(directory) != nil do return false
    path, path_ok := mouse_preference_save_path(context.temp_allocator)
    return path_ok && mouse_preference_save_to_path(editor, path)
}

mouse_preference_load :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    path, ok := mouse_preference_save_path(context.temp_allocator)
    return ok && mouse_preference_load_from_path(editor, path)
}
