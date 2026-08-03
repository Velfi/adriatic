package main

import "core:fmt"
import "core:io"
import "core:mem"
import "core:os"
import "core:strings"
import spy "zelda_engine:spy"

FIXTURE_EDITOR_PRODUCT_DIRECTORY :: "Adriatic"
FIXTURE_EDITOR_FILE_NAME :: "adriatic.fixture"

Fixture_Editor_Store_Error_Kind :: enum {
    None,
    Invalid_Argument,
    Out_Of_Memory,
    Resolve_Path,
    Create_Directory,
    Lifecycle,
    Codec,
    Map_Source,
    Resolve_Sidecar,
    Open_Sidecar_Temporary,
    Write_Sidecar_Temporary,
    Sync_Sidecar_Temporary,
    Close_Sidecar_Temporary,
    Link_Sidecar,
    Read_Sidecar,
    Sidecar_Digest_Mismatch,
    Cleanup_Sidecar_Temporary,
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
    map_error: Map_Artifact_Error,
    sidecar:   Fixture_Map_Sidecar,
    load:      Fixture_Editor_Load_Error,
}

fixture_editor_store_error_dispose :: proc(error: ^Fixture_Editor_Store_Error) {
    if error == nil do return
    fixture_codec_error_dispose(&error.codec)
    map_artifact_error_dispose(&error.map_error)
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
    link:      proc(data: rawptr, old_path, new_path: string) -> os.Error,
    remove:    proc(data: rawptr, path: string) -> os.Error,
    read:      proc(data: rawptr, path: string, alloc: mem.Allocator) -> ([]byte, os.Error),
}

Fixture_Editor_Store_Options :: struct {
    operations:             Fixture_Editor_Store_File_Ops,
    temporary_path:         string,
    sidecar_temporary_path: string,
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

fixture_editor_store_default_link :: proc(_: rawptr, old_path, new_path: string) -> os.Error {
    return os.link(old_path, new_path)
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
        link = fixture_editor_store_default_link,
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
        operations.link != nil &&
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

fixture_editor_store_default_path :: proc(
    alloc := context.allocator,
) -> (
    path: string,
    error: Fixture_Editor_Store_Error,
    ok: bool,
) {
    if alloc.procedure == nil {
        return "", fixture_editor_store_error(.Invalid_Argument, ""), false
    }

    base, base_error := os.user_data_dir(alloc)
    if base_error != nil || len(base) == 0 {
        if len(base) > 0 do delete(base, alloc)
        return "", fixture_editor_store_error(.Resolve_Path, "", base_error), false
    }
    defer delete(base, alloc)

    concatenate_error: mem.Allocator_Error
    path, concatenate_error = strings.concatenate(
        {base, "/", FIXTURE_EDITOR_PRODUCT_DIRECTORY, "/", FIXTURE_EDITOR_FILE_NAME},
        alloc,
    )
    if concatenate_error != nil || len(path) == 0 {
        if len(path) > 0 do delete(path, alloc)
        return "", fixture_editor_store_error(.Out_Of_Memory, ""), false
    }
    return path, {}, true
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

fixture_editor_store_sidecar_error :: proc(
    kind: Fixture_Editor_Store_Error_Kind,
    fixture_path: string,
    sidecar: Fixture_Map_Sidecar,
    os_error: os.Error = nil,
) -> Fixture_Editor_Store_Error {
    return {kind = kind, path = fixture_path, os_error = os_error, sidecar = sidecar}
}

fixture_editor_store_cleanup_sidecar_temporary :: proc(
    operations: Fixture_Editor_Store_File_Ops,
    temporary_path, fixture_path: string,
    sidecar: Fixture_Map_Sidecar,
    error: ^Fixture_Editor_Store_Error,
) {
    if len(temporary_path) == 0 do return
    remove_error := operations.remove(operations.data, temporary_path)
    if remove_error != nil && remove_error != .Not_Exist && error != nil {
        error^ = fixture_editor_store_sidecar_error(.Cleanup_Sidecar_Temporary, fixture_path, sidecar, remove_error)
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

fixture_editor_store_publish_sidecar_with_options :: proc(
    fixture_path, sidecar_path: string,
    sidecar: Fixture_Map_Sidecar,
    data: []byte,
    options: Fixture_Editor_Store_Options,
    alloc: mem.Allocator,
) -> (
    error: Fixture_Editor_Store_Error,
    ok: bool,
) {
    if len(fixture_path) == 0 ||
       len(sidecar_path) == 0 ||
       !fixture_map_sidecar_matches_encoded(sidecar, data) ||
       !fixture_editor_store_file_ops_valid(options.operations) ||
       alloc.procedure == nil {
        return fixture_editor_store_error(.Invalid_Argument, fixture_path), false
    }

    operations := options.operations
    sidecar_options := options
    sidecar_options.temporary_path = options.sidecar_temporary_path
    file, temporary_path, open_error, opened := fixture_editor_store_open_temporary(sidecar_path, sidecar_options)
    if !opened {
        return fixture_editor_store_sidecar_error(.Open_Sidecar_Temporary, fixture_path, sidecar, open_error.os_error),
            false
    }
    closed := false
    defer {
        if !closed do _ = operations.close(operations.data, file)
    }

    offset := 0
    for offset < len(data) {
        written, write_error := operations.write(operations.data, file, data[offset:])
        remaining := len(data) - offset
        if write_error != nil || written <= 0 || written > remaining {
            error = fixture_editor_store_sidecar_error(
                .Write_Sidecar_Temporary,
                fixture_path,
                sidecar,
                write_error if write_error != nil else io.Error.Short_Write,
            )
            _ = operations.close(operations.data, file)
            closed = true
            fixture_editor_store_cleanup_sidecar_temporary(operations, temporary_path, fixture_path, sidecar, &error)
            return error, false
        }
        offset += written
    }

    if sync_error := operations.sync(operations.data, file); sync_error != nil {
        error = fixture_editor_store_sidecar_error(.Sync_Sidecar_Temporary, fixture_path, sidecar, sync_error)
        _ = operations.close(operations.data, file)
        closed = true
        fixture_editor_store_cleanup_sidecar_temporary(operations, temporary_path, fixture_path, sidecar, &error)
        return error, false
    }
    if close_error := operations.close(operations.data, file); close_error != nil {
        closed = true
        error = fixture_editor_store_sidecar_error(.Close_Sidecar_Temporary, fixture_path, sidecar, close_error)
        fixture_editor_store_cleanup_sidecar_temporary(operations, temporary_path, fixture_path, sidecar, &error)
        return error, false
    }
    closed = true

    link_error := operations.link(operations.data, temporary_path, sidecar_path)
    if link_error == nil {
        fixture_editor_store_cleanup_sidecar_temporary(operations, temporary_path, fixture_path, sidecar, &error)
        if error.kind != .None do return error, false
        return {}, true
    }
    fixture_editor_store_cleanup_sidecar_temporary(operations, temporary_path, fixture_path, sidecar, &error)
    if error.kind != .None do return error, false
    if link_error != .Exist {
        return fixture_editor_store_sidecar_error(.Link_Sidecar, fixture_path, sidecar, link_error), false
    }

    existing, read_error := operations.read(operations.data, sidecar_path, alloc)
    if read_error != nil || existing == nil {
        if existing != nil do delete(existing, alloc)
        return fixture_editor_store_sidecar_error(
                .Read_Sidecar,
                fixture_path,
                sidecar,
                read_error if read_error != nil else io.Error.Unexpected_EOF,
            ),
            false
    }
    defer delete(existing, alloc)
    if !fixture_map_sidecar_matches_encoded(sidecar, existing) {
        return fixture_editor_store_sidecar_error(.Sidecar_Digest_Mismatch, fixture_path, sidecar), false
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
    map_source, map_error, captured := fixture_map_source_capture_inline(snapshot, alloc)
    defer map_artifact_error_dispose(&map_error)
    if !captured {
        return fixture_editor_store_error(.Codec, path), false
    }
    snapshot.map_source = map_source
    defer delete(snapshot.map_source.inline_bytes[:], alloc)
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

fixture_editor_store_externalize_inline_fixture_with_options :: proc(
    fixture: ^Fixture,
    path: string,
    options: Fixture_Editor_Store_Options,
    alloc := context.allocator,
) -> (
    error: Fixture_Editor_Store_Error,
    ok: bool,
) {
    if fixture == nil ||
       len(path) == 0 ||
       alloc.procedure == nil ||
       !fixture_editor_store_file_ops_valid(options.operations) ||
       !fixture_map_source_valid(fixture.map_source) ||
       fixture.map_source.kind != .Inline {
        return fixture_editor_store_error(.Invalid_Argument, path), false
    }

    encoded_map := fixture.map_source.inline_bytes[:]
    artifact, map_error, decoded := map_artifact_decode(encoded_map, alloc)
    if !decoded {
        kind: Fixture_Editor_Store_Error_Kind =
            map_artifact_error_is_allocation_failure(map_error) ? .Out_Of_Memory : .Map_Source
        error = {
            kind      = kind,
            path      = path,
            map_error = map_error,
        }
        map_error = {}
        return error, false
    }
    defer map_artifact_destroy(artifact, alloc)

    sidecar, derived := fixture_map_sidecar_derive(encoded_map)
    if !derived {
        return fixture_editor_store_error(.Map_Source, path), false
    }
    sidecar_path, resolved := fixture_map_sidecar_resolve(path, sidecar, alloc)
    if !resolved {
        return fixture_editor_store_sidecar_error(.Resolve_Sidecar, path, sidecar), false
    }
    defer delete(sidecar_path, alloc)

    snapshot_bytes, allocation_error := mem.alloc_bytes(size_of(Fixture), align_of(Fixture), alloc)
    if allocation_error != nil || snapshot_bytes == nil {
        return fixture_editor_store_error(.Out_Of_Memory, path), false
    }
    defer delete(snapshot_bytes, alloc)
    snapshot := cast(^Fixture)raw_data(snapshot_bytes)
    snapshot^ = fixture^
    snapshot.map_source = {
        kind    = .Sidecar,
        sidecar = sidecar,
    }
    fixture_map_source_clear_excluded(snapshot)

    container, codec_error, encoded := fixture_codec_encode(snapshot, alloc)
    if !encoded {
        return {kind = .Codec, path = path, codec = codec_error}, false
    }
    defer delete(container, alloc)

    sidecar_error, sidecar_published := fixture_editor_store_publish_sidecar_with_options(
        path,
        sidecar_path,
        sidecar,
        encoded_map,
        options,
        alloc,
    )
    if !sidecar_published do return sidecar_error, false
    return fixture_editor_store_replace_bytes_with_options(path, container, options)
}

fixture_editor_save_pair_to_path_with_options :: proc(
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

    map_source, map_error, captured := fixture_map_source_capture_inline(snapshot, alloc)
    if !captured {
        kind: Fixture_Editor_Store_Error_Kind =
            map_artifact_error_is_allocation_failure(map_error) ? .Out_Of_Memory : .Map_Source
        error = {
            kind      = kind,
            path      = path,
            map_error = map_error,
        }
        map_error = {}
        return error, false
    }
    snapshot.map_source = map_source
    defer delete(snapshot.map_source.inline_bytes[:], alloc)
    return fixture_editor_store_externalize_inline_fixture_with_options(snapshot, path, options, alloc)
}

fixture_editor_save_pair_to_path :: proc(
    editor: ^Editor,
    path: string,
    alloc := context.allocator,
) -> (
    Fixture_Editor_Store_Error,
    bool,
) {
    return fixture_editor_save_pair_to_path_with_options(
        editor,
        path,
        {operations = Fixture_Editor_Store_Default_File_Ops()},
        alloc,
    )
}

fixture_editor_save_path :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || len(path) == 0 do return false
    directory_error := os.make_directory_all(os.dir(path))
    if directory_error != nil && directory_error != .Exist {
        error := fixture_editor_store_error(.Create_Directory, path, directory_error)
        fixture_editor_store_log_failure("save", &error)
        terrain_file_feedback(editor, "FIXTURE SAVE FAILED")
        return false
    }

    error, ok := fixture_editor_save_pair_to_path(editor, path)
    defer fixture_editor_store_error_dispose(&error)
    if !ok {
        fixture_editor_store_log_failure("save", &error)
        terrain_file_feedback(editor, "FIXTURE SAVE FAILED")
        return false
    }
    fixture_editor_set_path(editor, path)
    editor.terrain_saved_revision = editor.project.revision
    fixture_notes_mark_saved()
    spy.debugf("fixture saved path=%q", path)
    terrain_file_feedback(editor, "FIXTURE SAVED")
    return true
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

    candidate, codec_error, decoded := fixture_codec_decode(data, alloc)
    if !decoded {
        return {kind = .Load, path = path, load = {kind = .Decode, codec = codec_error}}, false
    }
    defer fixture_migration_result_dispose(&candidate)

    sidecar: Fixture_Map_Sidecar
    sidecar_bytes: []byte
    sidecar_read_error: os.Error
    if candidate.fixture.map_source.kind == .Sidecar {
        sidecar = candidate.fixture.map_source.sidecar
        sidecar_path, resolved := fixture_map_sidecar_resolve(path, sidecar, alloc)
        if !resolved {
            return fixture_editor_store_sidecar_error(.Resolve_Sidecar, path, sidecar), false
        }
        defer delete(sidecar_path, alloc)

        sidecar_bytes, sidecar_read_error = options.operations.read(options.operations.data, sidecar_path, alloc)
        if sidecar_read_error != nil || sidecar_bytes == nil {
            if sidecar_bytes != nil do delete(sidecar_bytes, alloc)
            return fixture_editor_store_sidecar_error(
                    .Read_Sidecar,
                    path,
                    sidecar,
                    sidecar_read_error if sidecar_read_error != nil else io.Error.Unexpected_EOF,
                ),
                false
        }
        defer delete(sidecar_bytes, alloc)
        if !fixture_map_sidecar_matches_encoded(sidecar, sidecar_bytes) {
            return fixture_editor_store_sidecar_error(.Sidecar_Digest_Mismatch, path, sidecar), false
        }
    }

    load_error, loaded := fixture_editor_load_decoded(editor, &candidate, sidecar_bytes, alloc)
    if !loaded {
        return {kind = .Load, path = path, sidecar = sidecar, load = load_error}, false
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

fixture_editor_load_path :: proc(editor: ^Editor, path: string) -> bool {
    if editor == nil || len(path) == 0 do return false
    error, ok := fixture_editor_load_from_path(editor, path)
    defer fixture_editor_store_error_dispose(&error)
    if !ok {
        fixture_editor_store_log_failure("restore", &error)
        terrain_file_feedback(editor, "FIXTURE LOAD FAILED")
        return false
    }
    fixture_editor_set_path(editor, path)
    editor.terrain_saved_revision = editor.project.revision
    spy.debugf("fixture loaded path=%q", path)
    terrain_file_feedback(editor, "FIXTURE LOADED")
    return true
}

fixture_editor_store_log_failure :: proc(operation: string, error: ^Fixture_Editor_Store_Error) {
    if error == nil || error.kind == .None do return

    codec := &error.codec
    lifecycle := &error.lifecycle
    map_error := &error.map_error
    load_stage := error.load.kind
    state_path := error.load.path
    sidecar_basename_count := error.sidecar.basename_count
    if sidecar_basename_count < 0 do sidecar_basename_count = 0
    if sidecar_basename_count > len(error.sidecar.basename) do sidecar_basename_count = len(error.sidecar.basename)
    sidecar_basename := string(error.sidecar.basename[:sidecar_basename_count])
    if error.kind == .Load {
        codec = &error.load.codec
        lifecycle = &error.load.lifecycle
        map_error = &error.load.map_error
    }
    spy.errorf(
        "fixture %s failed stage=%v path=%q os=%v load_stage=%v state_path=%q lifecycle_kind=%v lifecycle_slot=%d codec_stage=%v portable_kind=%v portable_offset=%d portable_path=%q portable_detail=%q container_kind=%v container_offset=%d container_detail=%q migration_kind=%v migration_change=%q map_kind=%v map_offset=%d map_detail=%q sidecar_basename=%q sidecar_container=%d sidecar_format=%d sidecar_generator=%d sidecar_digest=%v",
        operation,
        error.kind,
        error.path,
        error.os_error,
        load_stage,
        state_path,
        lifecycle.kind,
        lifecycle.slot_index,
        codec.kind,
        codec.portable.kind,
        codec.portable.offset,
        codec.portable.path,
        codec.portable.message,
        codec.container.kind,
        codec.container.offset,
        codec.container.message,
        codec.migration.kind,
        codec.migration.change_id,
        map_error.kind,
        map_error.offset,
        map_error.message,
        sidecar_basename,
        error.sidecar.container_version,
        error.sidecar.format_version,
        error.sidecar.generator_version,
        error.sidecar.encoded_sha256,
    )
}

fixture_editor_save :: proc(editor: ^Editor) {
    if editor == nil || fixture_editor_file_dialog_is_open(editor) do return
    path := fixture_editor_current_path(editor)
    if path == "" {
        fixture_editor_file_dialog_open(editor, .Save)
        return
    }
    _ = fixture_editor_save_path(editor, path)
}

fixture_editor_restore :: proc(editor: ^Editor) {
    if editor == nil || fixture_editor_file_dialog_is_open(editor) do return
    fixture_editor_file_dialog_open(editor, .Load)
}
