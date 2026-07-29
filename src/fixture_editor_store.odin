package main

import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"

FIXTURE_EDITOR_PATH :: "adriatic.fixture"

Fixture_Editor_Store_Error_Kind :: enum {
    None,
    Invalid_Argument,
    Out_Of_Memory,
    Lifecycle,
    Codec,
    Open_Temporary,
    Write_Temporary,
    Sync_Temporary,
    Close_Temporary,
    Rename_Target,
    Cleanup_Temporary,
    Read_Source,
    Load,
}

Fixture_Editor_Store_Error :: struct {
    kind:      Fixture_Editor_Store_Error_Kind,
    path:      string,
    os_error:  os.Error,
    lifecycle: Fixture_Lifecycle_Error,
    codec:     Fixture_Codec_Error,
    load:      Fixture_Editor_Load_Error,
}

fixture_editor_store_error_dispose :: proc(error: ^Fixture_Editor_Store_Error) {
    if error == nil do return
    fixture_codec_error_dispose(&error.codec)
    fixture_editor_load_error_dispose(&error.load)
    error^ = {}
}

Fixture_Editor_Store_File_Ops :: struct {
    data:      rawptr,
    open_excl: proc(data: rawptr, path: string) -> (^os.File, os.Error),
    write:     proc(data: rawptr, file: ^os.File, bytes: []byte) -> (int, os.Error),
    sync:      proc(data: rawptr, file: ^os.File) -> os.Error,
    close:     proc(data: rawptr, file: ^os.File) -> os.Error,
    rename:    proc(data: rawptr, old_path, new_path: string) -> os.Error,
    remove:    proc(data: rawptr, path: string) -> os.Error,
    read:      proc(data: rawptr, path: string, alloc: mem.Allocator) -> ([]byte, os.Error),
}

Fixture_Editor_Store_Options :: struct {
    operations:     Fixture_Editor_Store_File_Ops,
    temporary_path: string,
}

fixture_editor_store_default_open_excl :: proc(_: rawptr, path: string) -> (^os.File, os.Error) {
    return os.open(path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
}

fixture_editor_store_default_write :: proc(_: rawptr, file: ^os.File, bytes: []byte) -> (int, os.Error) {
    return os.write(file, bytes)
}

fixture_editor_store_default_sync :: proc(_: rawptr, file: ^os.File) -> os.Error {
    return os.sync(file)
}

fixture_editor_store_default_close :: proc(_: rawptr, file: ^os.File) -> os.Error {
    return os.close(file)
}

fixture_editor_store_default_rename :: proc(_: rawptr, old_path, new_path: string) -> os.Error {
    return os.rename(old_path, new_path)
}

fixture_editor_store_default_remove :: proc(_: rawptr, path: string) -> os.Error {
    return os.remove(path)
}

fixture_editor_store_default_read :: proc(_: rawptr, path: string, alloc: mem.Allocator) -> ([]byte, os.Error) {
    return os.read_entire_file(path, alloc)
}

Fixture_Editor_Store_Default_File_Ops :: proc() -> Fixture_Editor_Store_File_Ops {
    return {
        open_excl = fixture_editor_store_default_open_excl,
        write = fixture_editor_store_default_write,
        sync = fixture_editor_store_default_sync,
        close = fixture_editor_store_default_close,
        rename = fixture_editor_store_default_rename,
        remove = fixture_editor_store_default_remove,
        read = fixture_editor_store_default_read,
    }
}

fixture_editor_store_file_ops_valid :: proc(operations: Fixture_Editor_Store_File_Ops) -> bool {
    return(
        operations.open_excl != nil &&
        operations.write != nil &&
        operations.sync != nil &&
        operations.close != nil &&
        operations.rename != nil &&
        operations.remove != nil &&
        operations.read != nil \
    )
}

fixture_editor_store_error :: proc(
    kind: Fixture_Editor_Store_Error_Kind,
    path: string,
    os_error: os.Error = nil,
) -> Fixture_Editor_Store_Error {
    return {kind = kind, path = path, os_error = os_error}
}

fixture_editor_store_cleanup_temporary :: proc(
    operations: Fixture_Editor_Store_File_Ops,
    temporary_path, target_path: string,
    error: ^Fixture_Editor_Store_Error,
) {
    if len(temporary_path) == 0 do return
    remove_error := operations.remove(operations.data, temporary_path)
    if remove_error != nil && remove_error != .Not_Exist && error != nil {
        error^ = fixture_editor_store_error(.Cleanup_Temporary, target_path, remove_error)
    }
}

fixture_editor_store_serial: u64

fixture_editor_store_open_temporary :: proc(
    target_path: string,
    options: Fixture_Editor_Store_Options,
) -> (
    file: ^os.File,
    temporary_path: string,
    error: Fixture_Editor_Store_Error,
    ok: bool,
) {
    operations := options.operations
    if len(options.temporary_path) > 0 {
        opened_file, open_error := operations.open_excl(operations.data, options.temporary_path)
        file = opened_file
        if open_error != nil || file == nil {
            if file != nil {
                _ = operations.close(operations.data, file)
                fixture_editor_store_cleanup_temporary(operations, options.temporary_path, target_path, nil)
            }
            return nil, "", fixture_editor_store_error(.Open_Temporary, target_path, open_error), false
        }
        return file, options.temporary_path, {}, true
    }

    parent := os.dir(target_path)
    for _ in 0 ..< 32 {
        fixture_editor_store_serial += 1
        candidate := fmt.tprintf("%s/.adriatic-fixture.%d.%d.tmp", parent, os.get_pid(), fixture_editor_store_serial)
        opened_file, open_error := operations.open_excl(operations.data, candidate)
        file = opened_file
        if open_error == nil && file != nil {
            return file, candidate, {}, true
        }
        if file != nil {
            _ = operations.close(operations.data, file)
            fixture_editor_store_cleanup_temporary(operations, candidate, target_path, nil)
        }
        if open_error != .Exist {
            return nil, "", fixture_editor_store_error(.Open_Temporary, target_path, open_error), false
        }
    }
    return nil, "", fixture_editor_store_error(.Open_Temporary, target_path, .Exist), false
}

fixture_editor_store_replace_bytes_with_options :: proc(
    path: string,
    data: []byte,
    options: Fixture_Editor_Store_Options,
) -> (
    error: Fixture_Editor_Store_Error,
    ok: bool,
) {
    if len(path) == 0 || !fixture_editor_store_file_ops_valid(options.operations) {
        return fixture_editor_store_error(.Invalid_Argument, path), false
    }

    operations := options.operations
    file, temporary_path, open_error, opened := fixture_editor_store_open_temporary(path, options)
    if !opened {
        return open_error, false
    }
    closed := false
    defer {
        if !closed {
            _ = operations.close(operations.data, file)
        }
    }

    offset := 0
    for offset < len(data) {
        written, write_error := operations.write(operations.data, file, data[offset:])
        remaining := len(data) - offset
        if write_error != nil || written <= 0 || written > remaining {
            error = fixture_editor_store_error(
                .Write_Temporary,
                path,
                write_error if write_error != nil else io.Error.Short_Write,
            )
            _ = operations.close(operations.data, file)
            closed = true
            fixture_editor_store_cleanup_temporary(operations, temporary_path, path, &error)
            return error, false
        }
        offset += written
    }

    if sync_error := operations.sync(operations.data, file); sync_error != nil {
        error = fixture_editor_store_error(.Sync_Temporary, path, sync_error)
        _ = operations.close(operations.data, file)
        closed = true
        fixture_editor_store_cleanup_temporary(operations, temporary_path, path, &error)
        return error, false
    }
    if close_error := operations.close(operations.data, file); close_error != nil {
        closed = true
        error = fixture_editor_store_error(.Close_Temporary, path, close_error)
        fixture_editor_store_cleanup_temporary(operations, temporary_path, path, &error)
        return error, false
    }
    closed = true

    if rename_error := operations.rename(operations.data, temporary_path, path); rename_error != nil {
        error = fixture_editor_store_error(.Rename_Target, path, rename_error)
        fixture_editor_store_cleanup_temporary(operations, temporary_path, path, &error)
        return error, false
    }
    return {}, true
}

fixture_editor_save_to_path_with_options :: proc(
    editor: ^Editor,
    path: string,
    options: Fixture_Editor_Store_Options,
    alloc := context.allocator,
) -> (
    error: Fixture_Editor_Store_Error,
    ok: bool,
) {
    if editor == nil ||
       len(path) == 0 ||
       alloc.procedure == nil ||
       !fixture_editor_store_file_ops_valid(options.operations) {
        return fixture_editor_store_error(.Invalid_Argument, path), false
    }

    snapshot_bytes, allocation_error := mem.alloc_bytes(size_of(Fixture), align_of(Fixture), alloc)
    if allocation_error != nil || snapshot_bytes == nil {
        return fixture_editor_store_error(.Out_Of_Memory, path), false
    }
    defer delete(snapshot_bytes, alloc)
    snapshot := cast(^Fixture)raw_data(snapshot_bytes)
    snapshot^ = editor.fixture
    if lifecycle_error := fixture_lifecycle_detach(&editor.fixture, snapshot); lifecycle_error.kind != .None {
        return {kind = .Lifecycle, path = path, lifecycle = lifecycle_error}, false
    }
    container, codec_error, encoded := fixture_codec_encode(snapshot, alloc)
    if !encoded {
        return {kind = .Codec, path = path, codec = codec_error}, false
    }
    defer delete(container, alloc)

    return fixture_editor_store_replace_bytes_with_options(path, container, options)
}

fixture_editor_save_to_path :: proc(
    editor: ^Editor,
    path: string,
    alloc := context.allocator,
) -> (
    Fixture_Editor_Store_Error,
    bool,
) {
    return fixture_editor_save_to_path_with_options(
        editor,
        path,
        {operations = Fixture_Editor_Store_Default_File_Ops()},
        alloc,
    )
}

fixture_editor_load_from_path_with_options :: proc(
    editor: ^Editor,
    path: string,
    options: Fixture_Editor_Store_Options,
    alloc := context.allocator,
) -> (
    error: Fixture_Editor_Store_Error,
    ok: bool,
) {
    if editor == nil ||
       len(path) == 0 ||
       alloc.procedure == nil ||
       !fixture_editor_store_file_ops_valid(options.operations) {
        return fixture_editor_store_error(.Invalid_Argument, path), false
    }
    data, read_error := options.operations.read(options.operations.data, path, alloc)
    if read_error != nil {
        if data != nil do delete(data, alloc)
        return fixture_editor_store_error(.Read_Source, path, read_error), false
    }
    if data == nil {
        return fixture_editor_store_error(.Read_Source, path, io.Error.Unexpected_EOF), false
    }
    defer delete(data, alloc)

    load_error, loaded := fixture_editor_load(editor, data, alloc)
    if !loaded {
        return {kind = .Load, path = path, load = load_error}, false
    }
    return {}, true
}

fixture_editor_load_from_path :: proc(
    editor: ^Editor,
    path: string,
    alloc := context.allocator,
) -> (
    Fixture_Editor_Store_Error,
    bool,
) {
    return fixture_editor_load_from_path_with_options(
        editor,
        path,
        {operations = Fixture_Editor_Store_Default_File_Ops()},
        alloc,
    )
}

fixture_editor_save :: proc(editor: ^Editor) {
    if editor == nil do return
    error, ok := fixture_editor_save_to_path(editor, FIXTURE_EDITOR_PATH)
    defer fixture_editor_store_error_dispose(&error)
    if ok {
        editor.terrain_saved_revision = editor.project.revision
        terrain_file_feedback(editor, "FIXTURE SAVED")
    } else {
        terrain_file_feedback(editor, "FIXTURE SAVE FAILED")
    }
}

fixture_editor_restore :: proc(editor: ^Editor) {
    if editor == nil do return
    error, ok := fixture_editor_load_from_path(editor, FIXTURE_EDITOR_PATH)
    defer fixture_editor_store_error_dispose(&error)
    if ok {
        editor.terrain_saved_revision = editor.project.revision
        terrain_file_feedback(editor, "FIXTURE LOADED")
    } else {
        terrain_file_feedback(editor, "FIXTURE LOAD FAILED")
    }
}
