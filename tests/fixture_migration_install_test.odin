package tests

import fixture_schema "../packages/fixture_schema"
import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

Fixture_Migration_Install_Test_Failure :: enum {
    None,
    Short_Write,
    Write,
    Sync,
    Close,
    Link,
    Target_Race,
    Remove,
}

Fixture_Migration_Install_Test_State :: struct {
    failure:     Fixture_Migration_Install_Test_Failure,
    write_calls: int,
}

migration_install_test_exists :: proc(_: rawptr, path: string) -> bool {
    return os.exists(path)
}

migration_install_test_open :: proc(_: rawptr, path: string) -> (^os.File, os.Error) {
    return os.open(path, {.Write, .Create, .Excl}, os.Permissions_Default_File)
}

migration_install_test_write :: proc(data: rawptr, file: ^os.File, bytes: []byte) -> (int, os.Error) {
    state := (^Fixture_Migration_Install_Test_State)(data)
    state.write_calls += 1
    if state.failure == .Write do return 0, .Invalid_File
    if state.failure == .Short_Write && len(bytes) > 1 {
        prefix_length := max(1, len(bytes) / 2)
        return os.write(file, bytes[:prefix_length])
    }
    return os.write(file, bytes)
}

migration_install_test_sync :: proc(data: rawptr, file: ^os.File) -> os.Error {
    state := (^Fixture_Migration_Install_Test_State)(data)
    if state.failure == .Sync do return .Invalid_File
    return os.sync(file)
}

migration_install_test_close :: proc(data: rawptr, file: ^os.File) -> os.Error {
    state := (^Fixture_Migration_Install_Test_State)(data)
    close_error := os.close(file)
    if state.failure == .Close do return .Invalid_File
    return close_error
}

migration_install_test_link :: proc(data: rawptr, old_path, new_path: string) -> os.Error {
    state := (^Fixture_Migration_Install_Test_State)(data)
    if state.failure == .Target_Race {
        _ = os.write_entire_file(new_path, "racer")
        return .Exist
    }
    if state.failure == .Link do return .Invalid_File
    return os.link(old_path, new_path)
}

migration_install_test_remove :: proc(data: rawptr, path: string) -> os.Error {
    state := (^Fixture_Migration_Install_Test_State)(data)
    if state.failure == .Remove do return .Permission_Denied
    return os.remove(path)
}

migration_install_test_options :: proc(
    state: ^Fixture_Migration_Install_Test_State,
) -> fixture_schema.Migration_Scaffold_Install_Options {
    operations := fixture_schema.Migration_Scaffold_File_Ops {
        data      = rawptr(state),
        exists    = migration_install_test_exists,
        open_excl = migration_install_test_open,
        write     = migration_install_test_write,
        sync      = migration_install_test_sync,
        close     = migration_install_test_close,
        link      = migration_install_test_link,
        remove    = migration_install_test_remove,
    }
    return {operations = operations}
}

migration_install_test_root :: proc(t: ^testing.T) -> (root: string, ok: bool) {
    root_path, root_error := os.make_directory_temp("", "fixture-migration-install-*", context.allocator)
    testing.expect(t, root_error == nil)
    return root_path, root_error == nil
}

@(test)
fixture_migration_install_is_atomic_and_idempotent :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    root, root_ok := migration_install_test_root(t)
    if !root_ok do return
    defer os.remove_all(root)
    target := fmt.tprintf("%s/target.odin", root)
    temporary := fmt.tprintf("%s/target.tmp", root)
    source := "package main;\n"
    options := fixture_schema.Migration_Scaffold_Install_Options {
        operations     = fixture_schema.Migration_Scaffold_Default_File_Ops(),
        temporary_path = temporary,
    }
    result, error, ok := fixture_schema.migration_scaffold_install_with_options(source, target, options)
    testing.expect(t, ok && result == .Installed && error.kind == .None)
    testing.expect(t, os.exists(target) && !os.exists(temporary))
    existing, read_error := os.read_entire_file(target, context.allocator)
    testing.expect(t, read_error == nil && string(existing) == source)
    delete(existing)

    result, error, ok = fixture_schema.migration_scaffold_install_with_options("changed", target, options)
    testing.expect(t, ok && result == .Already_Exists && error.kind == .None)
    existing, read_error = os.read_entire_file(target, context.allocator)
    testing.expect(t, read_error == nil && string(existing) == source)
    delete(existing)
}

@(test)
fixture_migration_install_rejects_empty_oversized_and_missing_parent :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    root, root_ok := migration_install_test_root(t)
    if !root_ok do return
    defer os.remove_all(root)
    options := fixture_schema.Migration_Scaffold_Install_Options {
        operations     = fixture_schema.Migration_Scaffold_Default_File_Ops(),
        temporary_path = fmt.tprintf("%s/temp.odin", root),
    }
    _, empty_error, empty_ok := fixture_schema.migration_scaffold_install_with_options(
        "",
        fmt.tprintf("%s/empty.odin", root),
        options,
    )
    testing.expect(t, !empty_ok && empty_error.kind == .Invalid_Source)
    oversized_bytes := make([]byte, fixture_schema.MIGRATION_SCAFFOLD_MAX_SOURCE_BYTES + 1, context.allocator)
    _, oversized_error, oversized_ok := fixture_schema.migration_scaffold_install_with_options(
        string(oversized_bytes),
        fmt.tprintf("%s/oversized.odin", root),
        options,
    )
    testing.expect(t, !oversized_ok && oversized_error.kind == .Invalid_Source)
    missing_options := options
    missing_options.temporary_path = fmt.tprintf("%s/missing/temp.odin", root)
    _, missing_error, missing_ok := fixture_schema.migration_scaffold_install_with_options(
        "package main;\n",
        fmt.tprintf("%s/missing/target.odin", root),
        missing_options,
    )
    testing.expect(t, !missing_ok && missing_error.kind == .Open_Temporary)
}

@(test)
fixture_migration_install_short_writes_and_prelink_cleanup :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    failures := [?]Fixture_Migration_Install_Test_Failure{.Short_Write, .Write, .Sync, .Close, .Link}
    for failure in failures {
        root, root_ok := migration_install_test_root(t)
        if !root_ok do return
        defer os.remove_all(root)
        target := fmt.tprintf("%s/target.odin", root)
        temporary := fmt.tprintf("%s/target.tmp", root)
        state := Fixture_Migration_Install_Test_State {
            failure = failure,
        }
        options := migration_install_test_options(&state)
        options.temporary_path = temporary
        result, error, ok := fixture_schema.migration_scaffold_install_with_options("package main;\n", target, options)
        if failure == .Short_Write {
            testing.expect(t, ok && result == .Installed && error.kind == .None)
            testing.expect(t, state.write_calls > 1)
            installed, installed_error := os.read_entire_file(target, context.allocator)
            testing.expect(t, installed_error == nil && string(installed) == "package main;\n")
            delete(installed)
        } else {
            testing.expect(t, !ok && result == .Not_Installed && error.kind != .None)
            testing.expect(t, !os.exists(target) && !os.exists(temporary))
        }
    }
}

@(test)
fixture_migration_install_race_and_postlink_cleanup_status :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    root, root_ok := migration_install_test_root(t)
    if !root_ok do return
    defer os.remove_all(root)
    target := fmt.tprintf("%s/target.odin", root)
    temporary := fmt.tprintf("%s/target.tmp", root)
    race_state := Fixture_Migration_Install_Test_State {
        failure = .Target_Race,
    }
    race_options := migration_install_test_options(&race_state)
    race_options.temporary_path = temporary
    race_result, race_error, race_ok := fixture_schema.migration_scaffold_install_with_options(
        "package main;\n",
        target,
        race_options,
    )
    testing.expect(t, !race_ok && race_result == .Already_Exists && race_error.kind == .Link_Target)
    testing.expect(t, os.exists(target) && !os.exists(temporary))
    _ = os.remove(target)

    remove_state := Fixture_Migration_Install_Test_State {
        failure = .Remove,
    }
    remove_options := migration_install_test_options(&remove_state)
    remove_options.temporary_path = temporary
    remove_result, remove_error, remove_ok := fixture_schema.migration_scaffold_install_with_options(
        "package main;\n",
        target,
        remove_options,
    )
    testing.expect(t, !remove_ok && remove_result == .Installed && remove_error.kind == .Cleanup_Temporary)
    testing.expect(t, os.exists(target) && os.exists(temporary))
}

@(test)
fixture_migration_install_exclusive_temp_collision_preserves_bytes :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    root, root_ok := migration_install_test_root(t)
    if !root_ok do return
    defer os.remove_all(root)
    target := fmt.tprintf("%s/target.odin", root)
    temporary := fmt.tprintf("%s/target.tmp", root)
    sentinel := "owned by another writer\n"
    testing.expect(t, os.write_entire_file(temporary, sentinel) == nil)
    options := fixture_schema.Migration_Scaffold_Install_Options {
        operations     = fixture_schema.Migration_Scaffold_Default_File_Ops(),
        temporary_path = temporary,
    }
    result, error, ok := fixture_schema.migration_scaffold_install_with_options("package main;\n", target, options)
    testing.expect(t, !ok && result == .Not_Installed && error.kind == .Open_Temporary)
    existing, read_error := os.read_entire_file(temporary, context.allocator)
    testing.expect(t, read_error == nil && string(existing) == sentinel)
    delete(existing)
    testing.expect(t, !os.exists(target))
}

@(test)
fixture_migration_generated_script_is_exact_and_valid :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    repo_root, root_error := os.get_working_directory(context.allocator)
    testing.expect(t, root_error == nil)
    if root_error != nil do return
    path := fmt.tprintf("%s/src/fixture_migration_v0001_to_v0002.odin", repo_root)
    source_bytes, read_error := os.read_entire_file(path, context.allocator)
    testing.expect(t, read_error == nil)
    if read_error != nil do return
    defer delete(source_bytes)
    report, report_ok := migration_scaffold_production_report(t)
    testing.expect(t, report_ok)
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)
    source := string(source_bytes)
    scaffold, parse_error, parse_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)source,
        context.allocator,
    )
    testing.expect(t, parse_ok && len(scaffold.resolutions) == 16)
    if parse_ok {
        validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&scaffold, &report)
        testing.expect(t, validation_ok && validation_error.kind == .None)
        fixture_schema.migration_scaffold_error_dispose(&validation_error)
    }
    testing.expect(t, strings.contains(source, "#by_ptr historical: fixture_v0001.Fixture"))
    fixture_schema.migration_scaffold_dispose(&scaffold)
    fixture_schema.migration_scaffold_error_dispose(&parse_error)
}
