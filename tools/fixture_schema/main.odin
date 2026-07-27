package main

import fixture_schema "../../packages/fixture_schema"
import "core:fmt"
import "core:os"

usage :: proc() {
    fmt.eprintln("usage: fixture_schema generate|check <repository-root> <zelda-engine-packages>")
    fmt.eprintln("       fixture_schema history-generate|history-check <version> <repository-root>")
    fmt.eprintln(
        "       fixture_schema migration-diff <from-version> <to-version> <repository-root> <zelda-engine-packages>",
    )
    fmt.eprintln(
        "       fixture_schema migration-scaffold|migration-scaffold-check <from-version> <to-version> <repository-root> <zelda-engine-packages>",
    )
}

history_version :: proc(text: string) -> (int, bool) {
    return fixture_schema.history_parse_schema_version(text)
}

migration_version :: proc(text: string) -> (int, bool) {
    return fixture_schema.history_parse_schema_version(text)
}

migration_scaffold_target_path :: proc(repo_root: string, from_version, to_version: int) -> string {
    return fmt.tprintf("%s/src/fixture_migration_v%04d_to_v%04d.odin", repo_root, from_version, to_version)
}

migration_candidate_data :: proc(repo_root, collection_root: string, from_version, to_version: int) -> ([]byte, bool) {
    target_path := fixture_schema.manifest_path(repo_root, to_version)
    if target_path == "" do return nil, false
    if os.exists(target_path) {
        data, read_error := os.read_entire_file(target_path, context.allocator)
        if read_error != nil do return nil, false
        return data, true
    }
    candidate, candidate_version, candidate_ok, _ := fixture_schema.build_manifest_report(repo_root, collection_root)
    if !candidate_ok do return nil, false
    if candidate_version != from_version && candidate_version != to_version {
        delete(candidate)
        return nil, false
    }
    return transmute([]byte)candidate, true
}

migration_scaffold_report :: proc(
    repo_root, collection_root: string,
    from_version, to_version: int,
) -> (
    report: fixture_schema.Schema_Diff_Report,
    ok: bool,
) {
    frozen_path := fixture_schema.manifest_path(repo_root, from_version)
    if frozen_path == "" {
        fmt.eprintln("fixture migration scaffold: cannot resolve frozen manifest path")
        return {}, false
    }
    frozen_data, frozen_error := os.read_entire_file(frozen_path, context.allocator)
    if frozen_error != nil {
        fmt.eprintln("fixture migration scaffold: missing or unreadable frozen manifest ", frozen_path)
        return {}, false
    }
    defer delete(frozen_data)
    candidate_data, candidate_ok := migration_candidate_data(repo_root, collection_root, from_version, to_version)
    if !candidate_ok {
        fmt.eprintln("fixture migration scaffold: candidate schema failed or target manifest is unreadable")
        return {}, false
    }
    defer delete(candidate_data)
    built_report, diff_error, diff_ok := fixture_schema.schema_diff_build_report(
        frozen_data,
        candidate_data,
        from_version,
        to_version,
        context.allocator,
    )
    if !diff_ok {
        fmt.eprintln(
            "fixture migration scaffold: report error line ",
            diff_error.line,
            " path ",
            diff_error.path,
            ": ",
            diff_error.message,
        )
        fixture_schema.schema_diff_error_dispose(&diff_error)
        return {}, false
    }
    return built_report, true
}

migration_scaffold_print_error :: proc(target, kind: string, diagnostic: ^fixture_schema.Migration_Scaffold_Error) {
    fmt.eprintln(
        "fixture migration scaffold: ",
        target,
        " ",
        kind,
        " error line ",
        diagnostic.line,
        " column ",
        diagnostic.column,
        " path ",
        diagnostic.path,
        ": ",
        diagnostic.message,
    )
}

migration_scaffold_read_existing :: proc(
    target: string,
) -> (
    scaffold: fixture_schema.Migration_Scaffold,
    error: fixture_schema.Migration_Scaffold_Error,
    ok: bool,
) {
    source, read_error := os.read_entire_file(target, context.allocator)
    if read_error != nil {
        fmt.eprintln("fixture migration scaffold: target is unreadable ", target)
        return {}, {}, false
    }
    scaffold, error, ok = fixture_schema.migration_scaffold_parse(source, context.allocator)
    delete(source)
    return scaffold, error, ok
}

migration_scaffold_validate_source :: proc(
    target: string,
    source: string,
    report: ^fixture_schema.Schema_Diff_Report,
) -> bool {
    scaffold, parse_error, parse_ok := fixture_schema.migration_scaffold_parse(
        transmute([]byte)source,
        context.allocator,
    )
    if !parse_ok {
        migration_scaffold_print_error(target, "parse", &parse_error)
        fixture_schema.migration_scaffold_dispose(&scaffold)
        fixture_schema.migration_scaffold_error_dispose(&parse_error)
        return false
    }
    validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&scaffold, report)
    if !validation_ok {
        migration_scaffold_print_error(target, "validation", &validation_error)
    }
    fixture_schema.migration_scaffold_dispose(&scaffold)
    fixture_schema.migration_scaffold_error_dispose(&parse_error)
    fixture_schema.migration_scaffold_error_dispose(&validation_error)
    return validation_ok
}

migration_scaffold_command :: proc(
    operation: string,
    repo_root, collection_root: string,
    from_version, to_version: int,
) -> bool {
    target := migration_scaffold_target_path(repo_root, from_version, to_version)
    if target == "" {
        fmt.eprintln("fixture migration scaffold: cannot resolve target path")
        return false
    }
    target_exists := os.exists(target)
    if target_exists {
        existing, parse_error, parse_ok := migration_scaffold_read_existing(target)
        if !parse_ok {
            if parse_error.kind != .None {
                migration_scaffold_print_error(target, "parse", &parse_error)
            }
            fixture_schema.migration_scaffold_dispose(&existing)
            fixture_schema.migration_scaffold_error_dispose(&parse_error)
            return false
        }
        report, report_ok := migration_scaffold_report(repo_root, collection_root, from_version, to_version)
        if !report_ok {
            fixture_schema.migration_scaffold_dispose(&existing)
            fixture_schema.migration_scaffold_error_dispose(&parse_error)
            return false
        }
        validation_error, validation_ok := fixture_schema.migration_scaffold_validate(&existing, &report)
        if !validation_ok {
            migration_scaffold_print_error(target, "validation", &validation_error)
        }
        fixture_schema.migration_scaffold_dispose(&existing)
        fixture_schema.migration_scaffold_error_dispose(&parse_error)
        fixture_schema.migration_scaffold_error_dispose(&validation_error)
        fixture_schema.schema_diff_report_dispose(&report)
        if !validation_ok do return false
        if operation == "migration-scaffold-check" do return true
        fmt.eprintln("fixture migration scaffold: already exists ", target)
        return true
    }
    if operation == "migration-scaffold-check" {
        fmt.eprintln("fixture migration scaffold: target is missing ", target)
        return false
    }
    report, report_ok := migration_scaffold_report(repo_root, collection_root, from_version, to_version)
    if !report_ok do return false
    defer fixture_schema.schema_diff_report_dispose(&report)

    generated, render_error, render_ok := fixture_schema.migration_scaffold_render(&report, context.allocator)
    if !render_ok {
        fmt.eprintln("fixture migration scaffold: render error path ", render_error.path, ": ", render_error.message)
        fixture_schema.migration_scaffold_error_dispose(&render_error)
        return false
    }
    defer delete(generated)
    if !migration_scaffold_validate_source(target, generated, &report) {
        return false
    }
    if target_exists {
        existing, read_error := os.read_entire_file(target, context.allocator)
        if read_error != nil {
            fmt.eprintln("fixture migration scaffold: existing target is unreadable ", target)
            return false
        }
        defer delete(existing)
        if !migration_scaffold_validate_source(target, string(existing), &report) {
            return false
        }
        fmt.eprintln("fixture migration scaffold: already exists ", target)
        return true
    }

    result, install_error, install_ok := fixture_schema.migration_scaffold_install(generated, target)
    if result == .Installed {
        if !install_ok {
            fmt.eprintln("fixture migration scaffold: installed ", target, " but ", install_error.operation)
            return false
        }
        fmt.eprintln("fixture migration scaffold: installed ", target)
        return true
    }
    if result == .Already_Exists {
        fmt.eprintln("fixture migration scaffold: target appeared during install ", target)
    } else {
        fmt.eprintln("fixture migration scaffold: install failed during ", install_error.operation, " for ", target)
    }
    return false
}

history_package_path :: proc(repo_root: string, version: int) -> string {
    return fmt.tprintf("%s/packages/fixture_history/v%04d/schema.generated.odin", repo_root, version)
}

history_read_manifest :: proc(repo_root: string, version: int) -> ([]byte, fixture_schema.History_Manifest, bool) {
    path := fixture_schema.manifest_path(repo_root, version)
    if path == "" {
        fmt.eprintln("fixture history: cannot resolve manifest path")
        return nil, {}, false
    }
    data, read_err := os.read_entire_file(path, context.allocator)
    if read_err != nil {
        fmt.eprintln("fixture history: missing or unreadable manifest ", path)
        return nil, {}, false
    }
    manifest, parse_error, ok := fixture_schema.history_parse_manifest(data, context.allocator)
    if !ok {
        fmt.eprintln(
            "fixture history: manifest error line ",
            parse_error.line,
            " path ",
            parse_error.path,
            ": ",
            parse_error.message,
        )
        fixture_schema.history_error_dispose(&parse_error)
        delete(data)
        return nil, {}, false
    }
    return data, manifest, true
}

history_generate :: proc(repo_root: string, version: int) -> bool {
    data, manifest, ok := history_read_manifest(repo_root, version)
    if !ok do return false
    defer fixture_schema.history_manifest_dispose(&manifest)
    sha, sha_ok := fixture_schema.history_manifest_sha256_hex(data, context.allocator)
    if !sha_ok {
        delete(data)
        return false
    }
    generated, generated_ok := fixture_schema.history_emit_package(&manifest, sha, context.allocator)
    delete(sha)
    delete(data)
    if !generated_ok do return false
    defer delete(generated)
    path := history_package_path(repo_root, version)
    directory := os.dir(path)
    if err := os.make_directory_all(directory); err != nil && err != .Exist {
        fmt.eprintln("fixture history: cannot create generated package directory ", directory)
        return false
    }
    temporary := fmt.tprintf("%s.tmp", path)
    if err := os.write_entire_file(temporary, generated); err != nil {
        os.remove(temporary)
        fmt.eprintln("fixture history: cannot write temporary generated package")
        return false
    }
    if err := os.rename(temporary, path); err != nil {
        os.remove(temporary)
        fmt.eprintln("fixture history: cannot install generated package")
        return false
    }
    return true
}

history_check :: proc(repo_root: string, version: int) -> bool {
    data, manifest, ok := history_read_manifest(repo_root, version)
    if !ok do return false
    defer fixture_schema.history_manifest_dispose(&manifest)
    sha, sha_ok := fixture_schema.history_manifest_sha256_hex(data, context.allocator)
    if !sha_ok {
        delete(data)
        return false
    }
    generated, generated_ok := fixture_schema.history_emit_package(&manifest, sha, context.allocator)
    delete(sha)
    delete(data)
    if !generated_ok do return false
    defer delete(generated)
    path := history_package_path(repo_root, version)
    existing, read_err := os.read_entire_file(path, context.allocator)
    if read_err != nil {
        fmt.eprintln("fixture history: generated package is missing ", path)
        return false
    }
    defer delete(existing)
    if string(existing) != generated {
        _, message := fixture_schema.compare_manifest(string(existing), generated)
        fmt.eprintln("fixture history: generated package mismatch: ", message)
        return false
    }
    return true
}

main :: proc() {
    if len(os.args) < 2 {
        usage()
        os.exit(2)
    }
    operation := os.args[1]
    if operation == "migration-diff" {
        if len(os.args) != 6 {
            usage()
            os.exit(2)
        }
        from_version, from_ok := migration_version(os.args[2])
        to_version, to_ok := migration_version(os.args[3])
        if !from_ok || !to_ok || to_version != from_version + 1 {
            fmt.eprintln("fixture migration diff: versions must be contiguous supported canonical decimals")
            os.exit(2)
        }
        repo_root := os.args[4]
        collection_root := os.args[5]
        frozen_path := fixture_schema.manifest_path(repo_root, from_version)
        if frozen_path == "" {
            fmt.eprintln("fixture migration diff: cannot resolve frozen manifest path")
            os.exit(1)
        }
        frozen_data, frozen_read_error := os.read_entire_file(frozen_path, context.allocator)
        if frozen_read_error != nil {
            fmt.eprintln("fixture migration diff: missing or unreadable frozen manifest ", frozen_path)
            os.exit(1)
        }
        defer delete(frozen_data)
        candidate_data, candidate_ok := migration_candidate_data(repo_root, collection_root, from_version, to_version)
        if !candidate_ok {
            fmt.eprintln("fixture migration diff: candidate schema failed or target manifest is unreadable")
            os.exit(1)
        }
        defer delete(candidate_data)
        report, diff_error, diff_ok := fixture_schema.schema_diff_build_report(
            frozen_data,
            candidate_data,
            from_version,
            to_version,
            context.allocator,
        )
        if !diff_ok {
            fmt.eprintln(
                "fixture migration diff: error line ",
                diff_error.line,
                " path ",
                diff_error.path,
                ": ",
                diff_error.message,
            )
            fixture_schema.schema_diff_error_dispose(&diff_error)
            os.exit(1)
        }
        defer fixture_schema.schema_diff_report_dispose(&report)
        rendered, render_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
        if !render_ok {
            fmt.eprintln("fixture migration diff: cannot render report")
            os.exit(1)
        }
        defer delete(rendered)
        fmt.print(rendered)
        return
    }
    if operation == "migration-scaffold" || operation == "migration-scaffold-check" {
        if len(os.args) != 6 {
            usage()
            os.exit(2)
        }
        from_version, from_ok := migration_version(os.args[2])
        to_version, to_ok := migration_version(os.args[3])
        if !from_ok || !to_ok || to_version != from_version + 1 {
            fmt.eprintln("fixture migration scaffold: versions must be contiguous supported canonical decimals")
            os.exit(2)
        }
        if !migration_scaffold_command(operation, os.args[4], os.args[5], from_version, to_version) {
            os.exit(1)
        }
        return
    }
    if len(os.args) != 4 {
        usage()
        os.exit(2)
    }
    if operation == "history-generate" || operation == "history-check" {
        version, version_ok := history_version(os.args[2])
        if !version_ok {
            fmt.eprintln("fixture history: version must be a supported canonical decimal")
            os.exit(2)
        }
        repo_root := os.args[3]
        if operation == "history-generate" {
            if !history_generate(repo_root, version) do os.exit(1)
        } else if !history_check(repo_root, version) {
            os.exit(1)
        }
        return
    }
    repo_root := os.args[2]
    collection_root := os.args[3]
    if operation != "generate" && operation != "check" {
        usage()
        os.exit(2)
    }

    manifest, version, built := fixture_schema.build_manifest(repo_root, collection_root)
    if !built do os.exit(1)
    path := fixture_schema.manifest_path(repo_root, version)
    if path == "" {
        fmt.eprintln("fixture schema: cannot resolve versioned manifest path")
        os.exit(1)
    }

    if operation == "check" {
        data, err := os.read_entire_file(path, context.allocator)
        if err != nil {
            fmt.eprintln("fixture schema: missing manifest ", path)
            fmt.eprintln("generate it with: make fixture-schema-generate")
            os.exit(1)
        }
        same, message := fixture_schema.compare_manifest(string(data), manifest)
        if !same {
            fmt.eprintln("fixture schema: ", message)
            fmt.eprintln("bump FIXTURE_SCHEMA_VERSION before changing the committed manifest")
            os.exit(1)
        }
        return
    }

    if os.exists(path) {
        data, err := os.read_entire_file(path, context.allocator)
        if err != nil {
            fmt.eprintln("fixture schema: cannot read existing manifest ", path)
            os.exit(1)
        }
        same, message := fixture_schema.compare_manifest(string(data), manifest)
        if !same {
            fmt.eprintln("fixture schema: refusing to overwrite historical manifest")
            fmt.eprintln(message)
            fmt.eprintln("bump FIXTURE_SCHEMA_VERSION before generating a new manifest")
            os.exit(1)
        }
        return
    }

    if !fixture_schema.write_manifest(repo_root, path, manifest) do os.exit(1)
}
