package main

import "core:mem"
import "core:os"
import "core:strings"

VEHICLE_PAINT_SAVE_MAGIC :: [8]u8{'A', 'D', 'R', 'P', 'A', 'I', 'N', 'T'}

Vehicle_Paint_Save_Header :: struct {
    magic:        [8]u8,
    width:        u32,
    height:       u32,
    layer_count:  u32,
    payload_size: u64,
    checksum:     u64,
}

vehicle_paint_checksum :: proc(bytes: []u8) -> u64 {
    hash: u64 = 14695981039346656037
    for byte in bytes {
        hash = (hash ~ u64(byte)) * 1099511628211
    }
    return hash
}

vehicle_paint_save_directory :: proc(allocator := context.allocator) -> (string, bool) {
    base, err := os.user_data_dir(allocator)
    if err != nil || base == "" do return "", false
    path, concatenate_err := strings.concatenate({base, "/Adriatic"}, allocator)
    return path, concatenate_err == nil
}

vehicle_paint_save_path :: proc(allocator := context.allocator) -> (string, bool) {
    directory, ok := vehicle_paint_save_directory(allocator)
    if !ok do return "", false
    path, err := strings.concatenate({directory, "/vehicle-paint.bin"}, allocator)
    return path, err == nil
}

vehicle_paint_layer_bytes :: proc(editor: ^Editor) -> []u8 {
    if editor == nil do return nil
    return mem.slice_ptr(cast([^]u8)&editor.vehicle_paint_layers, size_of(editor.vehicle_paint_layers))
}

vehicle_paint_save_to_path :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || path == "" do return false
    payload := vehicle_paint_layer_bytes(editor)
    header := Vehicle_Paint_Save_Header {
        magic        = VEHICLE_PAINT_SAVE_MAGIC,
        width        = VEHICLE_PAINT_TEXTURE_WIDTH,
        height       = VEHICLE_PAINT_TEXTURE_HEIGHT,
        layer_count  = VEHICLE_PAINT_AIRCRAFT_COUNT,
        payload_size = u64(len(payload)),
        checksum     = vehicle_paint_checksum(payload),
    }
    temporary, temporary_err := strings.concatenate({path, ".tmp"}, context.temp_allocator)
    if temporary_err != nil do return false
    file, open_err := os.create(temporary)
    if open_err != nil do return false
    header_bytes := mem.slice_ptr(cast([^]u8)&header, size_of(header))
    header_written, header_err := os.write(file, header_bytes)
    payload_written, payload_err := os.write(file, payload)
    close_err := os.close(file)
    if header_err != nil ||
       payload_err != nil ||
       close_err != nil ||
       header_written != len(header_bytes) ||
       payload_written != len(payload) {
        _ = os.remove(temporary)
        return false
    }
    if os.rename(temporary, path) == nil do return true
    // Windows does not replace an existing destination with its basic rename
    // operation. The temporary file is complete and checksummed before this
    // fallback removes the older destination.
    _ = os.remove(path)
    return os.rename(temporary, path) == nil
}

vehicle_paint_load_from_path :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || path == "" do return false
    bytes, err := os.read_entire_file(path, context.temp_allocator)
    if err != nil || len(bytes) < size_of(Vehicle_Paint_Save_Header) do return false
    header := cast(^Vehicle_Paint_Save_Header)raw_data(bytes)
    expected_payload_size := size_of(editor.vehicle_paint_layers)
    if header.magic != VEHICLE_PAINT_SAVE_MAGIC ||
       header.width != VEHICLE_PAINT_TEXTURE_WIDTH ||
       header.height != VEHICLE_PAINT_TEXTURE_HEIGHT ||
       header.layer_count != VEHICLE_PAINT_AIRCRAFT_COUNT ||
       header.payload_size != u64(expected_payload_size) ||
       len(bytes) != size_of(Vehicle_Paint_Save_Header) + int(header.payload_size) {
        return false
    }
    payload := bytes[size_of(Vehicle_Paint_Save_Header):]
    if vehicle_paint_checksum(payload) != header.checksum do return false
    copy(vehicle_paint_layer_bytes(editor), payload)
    vehicle_paint_mark_texture_dirty(editor)
    return true
}

vehicle_paint_save :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    directory, directory_ok := vehicle_paint_save_directory(context.temp_allocator)
    if !directory_ok do return false
    directory_err := os.make_directory_all(directory)
    if directory_err != nil && directory_err != .Exist do return false
    path, path_ok := vehicle_paint_save_path(context.temp_allocator)
    if !path_ok do return false
    saved := vehicle_paint_save_to_path(editor, path)
    if saved do editor.vehicle_paint_save_pending = false
    return saved
}

vehicle_paint_load :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    path, ok := vehicle_paint_save_path(context.temp_allocator)
    return ok && vehicle_paint_load_from_path(editor, path)
}
