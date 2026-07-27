package fixture_schema

import "core:fmt"
import "core:io"
import "core:os"

Migration_Scaffold_Install_Result :: enum {
    Not_Installed,
    Installed,
    Already_Exists,
}

Migration_Scaffold_Install_Error_Kind :: enum {
    None,
    Invalid_Source,
    Invalid_Operations,
    Open_Temporary,
    Write_Temporary,
    Sync_Temporary,
    Close_Temporary,
    Link_Target,
    Cleanup_Temporary,
}

Migration_Scaffold_Install_Error :: struct {
    kind:      Migration_Scaffold_Install_Error_Kind,
    operation: string,
    os_error:  os.Error,
}

Migration_Scaffold_File_Ops :: struct {
    data:      rawptr,
    exists:    proc(data: rawptr, path: string) -> bool,
    open_excl: proc(data: rawptr, path: string) -> (^os.File, os.Error),
    write:     proc(data: rawptr, file: ^os.File, bytes: []byte) -> (int, os.Error),
    sync:      proc(data: rawptr, file: ^os.File) -> os.Error,
    close:     proc(data: rawptr, file: ^os.File) -> os.Error,
    link:      proc(data: rawptr, old_path, new_path: string) -> os.Error,
    remove:    proc(data: rawptr, path: string) -> os.Error,
}

Migration_Scaffold_Install_Options :: struct {
    operations:     Migration_Scaffold_File_Ops,
    temporary_path: string,
}

migration_scaffold_default_exists :: proc(_: rawptr, path: string) -> bool {
    return os.exists(path)
}

migration_scaffold_default_open_excl :: proc(_: rawptr, path: string) -> (^os.File, os.Error) {
    return os.open(path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
}

migration_scaffold_default_write :: proc(_: rawptr, file: ^os.File, bytes: []byte) -> (int, os.Error) {
    return os.write(file, bytes)
}

migration_scaffold_default_sync :: proc(_: rawptr, file: ^os.File) -> os.Error {
    return os.sync(file)
}

migration_scaffold_default_close :: proc(_: rawptr, file: ^os.File) -> os.Error {
    return os.close(file)
}

migration_scaffold_default_link :: proc(_: rawptr, old_path, new_path: string) -> os.Error {
    return os.link(old_path, new_path)
}

migration_scaffold_default_remove :: proc(_: rawptr, path: string) -> os.Error {
    return os.remove(path)
}

Migration_Scaffold_Default_File_Ops :: proc() -> Migration_Scaffold_File_Ops {
    return {
        exists = migration_scaffold_default_exists,
        open_excl = migration_scaffold_default_open_excl,
        write = migration_scaffold_default_write,
        sync = migration_scaffold_default_sync,
        close = migration_scaffold_default_close,
        link = migration_scaffold_default_link,
        remove = migration_scaffold_default_remove,
    }
}

migration_scaffold_install_error :: proc(
    kind: Migration_Scaffold_Install_Error_Kind,
    operation: string,
    os_error: os.Error = nil,
) -> Migration_Scaffold_Install_Error {
    return {kind = kind, operation = operation, os_error = os_error}
}

migration_scaffold_file_ops_valid :: proc(operations: Migration_Scaffold_File_Ops) -> bool {
    return(
        operations.exists != nil &&
        operations.open_excl != nil &&
        operations.write != nil &&
        operations.sync != nil &&
        operations.close != nil &&
        operations.link != nil &&
        operations.remove != nil \
    )
}

migration_scaffold_install_temp_path :: proc(target: string, serial: ^u64) -> string {
    if serial == nil do return ""
    serial^ += 1
    parent := os.dir(target)
    return fmt.tprintf("%s/.fixture-migration.%d.%d.tmp", parent, os.get_pid(), serial^)
}

migration_scaffold_install_cleanup :: proc(
    operations: Migration_Scaffold_File_Ops,
    temporary_path: string,
    error: ^Migration_Scaffold_Install_Error,
) -> bool {
    if len(temporary_path) == 0 do return true
    cleanup_error := operations.remove(operations.data, temporary_path)
    if cleanup_error != nil {
        if error != nil {
            error^ = migration_scaffold_install_error(.Cleanup_Temporary, "remove temporary file", cleanup_error)
        }
        return false
    }
    return true
}

migration_scaffold_install_with_options :: proc(
    source, target: string,
    options: Migration_Scaffold_Install_Options,
) -> (
    result: Migration_Scaffold_Install_Result,
    error: Migration_Scaffold_Install_Error,
    ok: bool,
) {
    result = .Not_Installed
    if len(source) == 0 || len(source) > MIGRATION_SCAFFOLD_MAX_SOURCE_BYTES {
        error = migration_scaffold_install_error(.Invalid_Source, "source")
        return result, error, false
    }
    if len(target) == 0 || !migration_scaffold_file_ops_valid(options.operations) {
        error = migration_scaffold_install_error(.Invalid_Operations, "file operations")
        return result, error, false
    }
    operations := options.operations
    if operations.exists(operations.data, target) {
        return .Already_Exists, {}, true
    }

    serial: u64
    temporary_path := options.temporary_path
    if len(temporary_path) == 0 {
        temporary_path = migration_scaffold_install_temp_path(target, &serial)
    }
    if len(temporary_path) == 0 {
        error = migration_scaffold_install_error(.Invalid_Operations, "temporary path")
        return result, error, false
    }

    file, open_error := operations.open_excl(operations.data, temporary_path)
    if open_error != nil || file == nil {
        if file != nil {
            _ = operations.close(operations.data, file)
            migration_scaffold_install_cleanup(operations, temporary_path, nil)
        }
        error = migration_scaffold_install_error(.Open_Temporary, "open temporary file", open_error)
        return result, error, false
    }
    offset := 0
    for offset < len(source) {
        written, write_error := operations.write(operations.data, file, transmute([]byte)source[offset:])
        remaining := len(source) - offset
        if write_error != nil || written <= 0 || written > remaining {
            close_error := operations.close(operations.data, file)
            _ = close_error
            if write_error != nil {
                error = migration_scaffold_install_error(.Write_Temporary, "write temporary file", write_error)
            } else {
                error = migration_scaffold_install_error(
                    .Write_Temporary,
                    "write temporary file",
                    io.Error.Short_Write,
                )
            }
            migration_scaffold_install_cleanup(operations, temporary_path, &error)
            return result, error, false
        }
        offset += written
    }

    sync_error := operations.sync(operations.data, file)
    close_error := operations.close(operations.data, file)
    if sync_error != nil {
        error = migration_scaffold_install_error(.Sync_Temporary, "sync temporary file", sync_error)
        migration_scaffold_install_cleanup(operations, temporary_path, &error)
        return result, error, false
    }
    if close_error != nil {
        error = migration_scaffold_install_error(.Close_Temporary, "close temporary file", close_error)
        migration_scaffold_install_cleanup(operations, temporary_path, &error)
        return result, error, false
    }

    link_error := operations.link(operations.data, temporary_path, target)
    if link_error != nil {
        result = link_error == .Exist ? .Already_Exists : .Not_Installed
        error = migration_scaffold_install_error(.Link_Target, "link target", link_error)
        migration_scaffold_install_cleanup(operations, temporary_path, &error)
        return result, error, false
    }
    cleanup_error := operations.remove(operations.data, temporary_path)
    if cleanup_error != nil {
        error = migration_scaffold_install_error(.Cleanup_Temporary, "remove linked temporary file", cleanup_error)
        return .Installed, error, false
    }
    return .Installed, {}, true
}

migration_scaffold_install :: proc(
    source, target: string,
) -> (
    result: Migration_Scaffold_Install_Result,
    error: Migration_Scaffold_Install_Error,
    ok: bool,
) {
    return migration_scaffold_install_with_options(
        source,
        target,
        {operations = Migration_Scaffold_Default_File_Ops()},
    )
}
