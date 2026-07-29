package main

import fixture_file "../packages/fixture_file"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"

FIXTURE_UPGRADE_MAX_DEPTH :: 64
FIXTURE_UPGRADE_MAX_FILES :: 16 * 1024

Fixture_Upgrade_Error_Kind :: enum {
    None,
    Invalid_Argument,
    Out_Of_Memory,
    Stat_Source,
    Invalid_Source_Type,
    Read_Source,
    Container,
    Codec,
    Encode,
    Store,
    Traverse,
    Limit_Exceeded,
}

Fixture_Upgrade_Error :: struct {
    kind:           Fixture_Upgrade_Error_Kind,
    path:           string,
    path_allocator: mem.Allocator,
    os_error:       os.Error,
    container:      fixture_file.Fixture_Container_Error,
    codec:          Fixture_Codec_Error,
    store:          Fixture_Editor_Store_Error,
}

Fixture_Upgrade_Result :: struct {
    source_version: int,
    target_version: int,
    changed:        bool,
}

Fixture_Upgrade_Summary :: struct {
    total:   int,
    changed: int,
    current: int,
}

Fixture_Upgrade_Report_Proc :: #type proc(data: rawptr, path: string, result: Fixture_Upgrade_Result, dry_run: bool)

Fixture_Upgrade_Options :: struct {
    store: Fixture_Editor_Store_Options,
}

fixture_upgrade_default_options :: proc() -> Fixture_Upgrade_Options {
    return {store = {operations = Fixture_Editor_Store_Default_File_Ops()}}
}

fixture_upgrade_error_dispose :: proc(error: ^Fixture_Upgrade_Error) {
    if error == nil do return
    fixture_codec_error_dispose(&error.codec)
    fixture_editor_store_error_dispose(&error.store)
    if len(error.path) > 0 && error.path_allocator.procedure != nil {
        delete(error.path, error.path_allocator)
    }
    error^ = {}
}

fixture_upgrade_error :: proc(
    kind: Fixture_Upgrade_Error_Kind,
    path: string,
    allocator: mem.Allocator,
) -> Fixture_Upgrade_Error {
    if len(path) == 0 do return {kind = kind}
    owned_path, allocation_error := strings.clone(path, allocator)
    if allocation_error != nil {
        return {kind = .Out_Of_Memory}
    }
    return {kind = kind, path = owned_path, path_allocator = allocator}
}

fixture_upgrade_os_error_kind :: proc(
    error: os.Error,
    fallback: Fixture_Upgrade_Error_Kind,
) -> Fixture_Upgrade_Error_Kind {
    if _, is_allocator_error := error.(runtime.Allocator_Error); is_allocator_error {
        return .Out_Of_Memory
    }
    return fallback
}

fixture_upgrade_file_with_options :: proc(
    path: string,
    dry_run: bool,
    options: Fixture_Upgrade_Options,
    allocator := context.allocator,
) -> (
    result: Fixture_Upgrade_Result,
    error: Fixture_Upgrade_Error,
    ok: bool,
) {
    if len(path) == 0 || allocator.procedure == nil || !fixture_editor_store_file_ops_valid(options.store.operations) {
        return {}, {kind = .Invalid_Argument}, false
    }

    operations := options.store.operations
    source, read_error := operations.read(operations.data, path, allocator)
    if read_error != nil {
        if source != nil do delete(source, allocator)
        kind := fixture_upgrade_os_error_kind(read_error, .Read_Source)
        error = fixture_upgrade_error(kind, path, allocator)
        error.os_error = read_error
        return {}, error, false
    }
    if source == nil {
        return {}, fixture_upgrade_error(.Read_Source, path, allocator), false
    }
    defer delete(source, allocator)

    view, container_error, container_ok := fixture_file.fixture_container_decode(source)
    if !container_ok {
        error = fixture_upgrade_error(.Container, path, allocator)
        error.container = container_error
        return {}, error, false
    }
    result = {
        source_version = int(view.schema_version),
        target_version = FIXTURE_SCHEMA_VERSION,
        changed        = int(view.schema_version) != FIXTURE_SCHEMA_VERSION,
    }

    decoded, codec_error, decoded_ok := fixture_codec_decode(source, allocator)
    if !decoded_ok {
        error = fixture_upgrade_error(.Codec, path, allocator)
        if error.kind == .Out_Of_Memory {
            fixture_codec_error_dispose(&codec_error)
            return {}, error, false
        }
        error.codec = codec_error
        return {}, error, false
    }
    defer fixture_migration_result_dispose(&decoded)

    if !result.changed || dry_run {
        return result, {}, true
    }

    encoded, encode_error, encoded_ok := fixture_codec_encode(decoded.fixture, allocator)
    if !encoded_ok {
        error = fixture_upgrade_error(.Encode, path, allocator)
        if error.kind == .Out_Of_Memory {
            fixture_codec_error_dispose(&encode_error)
            return {}, error, false
        }
        error.codec = encode_error
        return {}, error, false
    }
    defer delete(encoded, allocator)

    encoded_view, encoded_container_error, encoded_container_ok := fixture_file.fixture_container_decode(encoded)
    if !encoded_container_ok || encoded_view.schema_version != u32(FIXTURE_SCHEMA_VERSION) {
        error = fixture_upgrade_error(.Encode, path, allocator)
        error.container = encoded_container_error
        return {}, error, false
    }

    store_error, stored := fixture_editor_store_replace_bytes_with_options(path, encoded, options.store)
    if !stored {
        error = fixture_upgrade_error(.Store, path, allocator)
        if error.kind == .Out_Of_Memory {
            fixture_editor_store_error_dispose(&store_error)
            return {}, error, false
        }
        store_error.path = ""
        error.store = store_error
        return {}, error, false
    }
    return result, {}, true
}

fixture_upgrade_file :: proc(
    path: string,
    dry_run: bool,
    allocator := context.allocator,
) -> (
    Fixture_Upgrade_Result,
    Fixture_Upgrade_Error,
    bool,
) {
    return fixture_upgrade_file_with_options(path, dry_run, fixture_upgrade_default_options(), allocator)
}

fixture_upgrade_path_list_destroy :: proc(paths: ^[dynamic]string) {
    if paths == nil do return
    for path in paths^ {
        delete(path, paths.allocator)
    }
    delete(paths^)
    paths^ = nil
}

fixture_upgrade_collect :: proc(
    directory: string,
    depth: int,
    paths: ^[dynamic]string,
    allocator: mem.Allocator,
) -> (
    error: Fixture_Upgrade_Error,
    ok: bool,
) {
    if depth > FIXTURE_UPGRADE_MAX_DEPTH {
        return fixture_upgrade_error(.Limit_Exceeded, directory, allocator), false
    }
    entries, read_error := os.read_all_directory_by_path(directory, allocator)
    if read_error != nil {
        kind := fixture_upgrade_os_error_kind(read_error, .Traverse)
        error = fixture_upgrade_error(kind, directory, allocator)
        error.os_error = read_error
        return error, false
    }
    defer os.file_info_slice_delete(entries, allocator)

    for entry in entries {
        switch entry.type {
        case .Directory:
            collect_error, collected := fixture_upgrade_collect(entry.fullpath, depth + 1, paths, allocator)
            if !collected do return collect_error, false
        case .Regular:
            if !strings.has_suffix(entry.fullpath, ".fixture") do continue
            if len(paths^) >= FIXTURE_UPGRADE_MAX_FILES {
                return fixture_upgrade_error(.Limit_Exceeded, entry.fullpath, allocator), false
            }
            owned_path, allocation_error := strings.clone(entry.fullpath, allocator)
            if allocation_error != nil {
                return fixture_upgrade_error(.Out_Of_Memory, entry.fullpath, allocator), false
            }
            appended, append_error := append_elem(paths, owned_path)
            if append_error != nil || appended != 1 {
                delete(owned_path, allocator)
                return fixture_upgrade_error(.Out_Of_Memory, entry.fullpath, allocator), false
            }
        case .Symlink, .Undetermined, .Named_Pipe, .Socket, .Block_Device, .Character_Device:
        }
    }
    return {}, true
}

fixture_upgrade_path_with_options :: proc(
    path: string,
    dry_run: bool,
    options: Fixture_Upgrade_Options,
    report: Fixture_Upgrade_Report_Proc = nil,
    report_data: rawptr = nil,
    allocator := context.allocator,
) -> (
    summary: Fixture_Upgrade_Summary,
    error: Fixture_Upgrade_Error,
    ok: bool,
) {
    if len(path) == 0 || allocator.procedure == nil || !fixture_editor_store_file_ops_valid(options.store.operations) {
        return {}, {kind = .Invalid_Argument}, false
    }

    info, stat_error := os.lstat(path, allocator)
    if stat_error != nil {
        kind := fixture_upgrade_os_error_kind(stat_error, .Stat_Source)
        error = fixture_upgrade_error(kind, path, allocator)
        error.os_error = stat_error
        return {}, error, false
    }
    defer os.file_info_delete(info, allocator)

    paths, make_error := make([dynamic]string, 0, 16, allocator)
    if make_error != nil {
        return {}, fixture_upgrade_error(.Out_Of_Memory, path, allocator), false
    }
    defer fixture_upgrade_path_list_destroy(&paths)

    switch info.type {
    case .Regular:
        owned_path, allocation_error := strings.clone(path, allocator)
        if allocation_error != nil {
            return {}, fixture_upgrade_error(.Out_Of_Memory, path, allocator), false
        }
        appended, append_error := append_elem(&paths, owned_path)
        if append_error != nil || appended != 1 {
            delete(owned_path, allocator)
            return {}, fixture_upgrade_error(.Out_Of_Memory, path, allocator), false
        }
    case .Directory:
        collect_error, collected := fixture_upgrade_collect(path, 0, &paths, allocator)
        if !collected do return {}, collect_error, false
        slice.sort_by(paths[:], proc(a, b: string) -> bool { return a < b })
    case .Symlink, .Undetermined, .Named_Pipe, .Socket, .Block_Device, .Character_Device:
        return {}, fixture_upgrade_error(.Invalid_Source_Type, path, allocator), false
    }

    for fixture_path in paths {
        result, file_error, upgraded := fixture_upgrade_file_with_options(fixture_path, dry_run, options, allocator)
        if !upgraded do return summary, file_error, false
        summary.total += 1
        if result.changed {
            summary.changed += 1
        } else {
            summary.current += 1
        }
        if report != nil do report(report_data, fixture_path, result, dry_run)
    }
    return summary, {}, true
}

fixture_upgrade_path :: proc(
    path: string,
    dry_run: bool,
    report: Fixture_Upgrade_Report_Proc = nil,
    report_data: rawptr = nil,
    allocator := context.allocator,
) -> (
    Fixture_Upgrade_Summary,
    Fixture_Upgrade_Error,
    bool,
) {
    return fixture_upgrade_path_with_options(
        path,
        dry_run,
        fixture_upgrade_default_options(),
        report,
        report_data,
        allocator = allocator,
    )
}

fixture_upgrade_cli_report :: proc(_: rawptr, path: string, result: Fixture_Upgrade_Result, dry_run: bool) {
    if !result.changed {
        fmt.printf("current v%d %s\n", result.target_version, path)
    } else if dry_run {
        fmt.printf("would migrate v%d -> v%d %s\n", result.source_version, result.target_version, path)
    } else {
        fmt.printf("migrated v%d -> v%d %s\n", result.source_version, result.target_version, path)
    }
}

adriatic_cli_fixture_upgrade :: proc(args: []string) -> bool {
    dry_run := false
    path := ""
    if len(args) == 3 {
        path = args[2]
    } else if len(args) == 4 && args[2] == "--dry-run" {
        dry_run = true
        path = args[3]
    } else {
        adriatic_cli_usage()
        return false
    }

    summary, error, ok := fixture_upgrade_path(path, dry_run, fixture_upgrade_cli_report)
    defer fixture_upgrade_error_dispose(&error)
    if !ok {
        fmt.eprintf("adriatic: fixture upgrade %v failed at %s", error.kind, error.path)
        if error.os_error != nil do fmt.eprintf(": %v", error.os_error)
        fmt.eprintln()
        return false
    }
    fmt.printf(
        "fixtures: %d total, %d %s, %d current\n",
        summary.total,
        summary.changed,
        "would migrate" if dry_run else "migrated",
        summary.current,
    )
    return true
}
