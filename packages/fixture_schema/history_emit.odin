package fixture_schema

import "core:crypto/sha2"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"

HISTORY_MAX_EMITTED_BYTES :: 16 * 1024 * 1024

history_manifest_sha256_hex :: proc(data: []byte, allocator: mem.Allocator) -> (string, bool) {
    if allocator.procedure == nil do return "", false
    ctx: sha2.Context_256
    sha2.init_256(&ctx)
    sha2.update(&ctx, data)
    digest: [sha2.DIGEST_SIZE_256]byte
    sha2.final(&ctx, digest[:])
    builder, err := strings.builder_make_len_cap(0, 64, allocator)
    if err != nil do return "", false
    for value in digest {
        fmt.sbprintf(&builder, "%02x", value)
    }
    return strings.to_string(builder), true
}

history_is_hex_sha256 :: proc(value: string) -> bool {
    if len(value) != 64 do return false
    for ch in value {
        if !(ch >= '0' && ch <= '9' || ch >= 'a' && ch <= 'f' || ch >= 'A' && ch <= 'F') do return false
    }
    return true
}

history_sorted_records :: proc(
    manifest: ^History_Manifest,
    allocator: mem.Allocator,
) -> (
    [dynamic]^History_Record,
    bool,
) {
    sorted, make_error := make([dynamic]^History_Record, 0, len(manifest.records), allocator)
    if make_error != nil do return nil, false
    for index := 0; index < len(manifest.records); index += 1 {
        appended, append_error := append_elem(&sorted, &manifest.records[index])
        if append_error != nil || appended != 1 {
            delete(sorted)
            return nil, false
        }
    }
    slice.sort_by(sorted[:], proc(a, b: ^History_Record) -> bool { return a.id < b.id })
    return sorted, true
}

history_sorted_index :: proc(sorted: [dynamic]^History_Record, id: string) -> (int, bool) {
    for index := 0; index < len(sorted); index += 1 {
        if sorted[index].id == id do return index, true
    }
    return 0, false
}

history_emit_symbol :: proc(
    builder: ^strings.Builder,
    manifest: ^History_Manifest,
    sorted: [dynamic]^History_Record,
    id: string,
) -> bool {
    if id == manifest.root {
        strings.write_string(builder, "Fixture")
        return true
    }
    index, found := history_sorted_index(sorted, id)
    if !found do return false
    fmt.sbprintf(builder, "History_Type_%04d", index)
    return true
}

history_emit_type_node :: proc(
    builder: ^strings.Builder,
    expr: string,
    cursor: ^int,
    manifest: ^History_Manifest,
    sorted: [dynamic]^History_Record,
    allow_raw_builtin: bool,
    depth: int,
) -> bool {
    if cursor^ >= len(expr) do return false
    if depth > HISTORY_MANIFEST_MAX_TYPE_DEPTH do return false
    if strings.has_prefix(expr[cursor^:], "array[") {
        cursor^ += len("array[")
        length_start := cursor^
        for cursor^ < len(expr) && expr[cursor^] >= '0' && expr[cursor^] <= '9' {
            cursor^ += 1
        }
        if length_start == cursor^ || cursor^ >= len(expr) || expr[cursor^] != ']' do return false
        strings.write_byte(builder, '[')
        strings.write_string(builder, expr[length_start:cursor^])
        strings.write_byte(builder, ']')
        cursor^ += 1
        if cursor^ >= len(expr) || expr[cursor^] != '<' do return false
        cursor^ += 1
        if !history_emit_type_node(builder, expr, cursor, manifest, sorted, false, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    if strings.has_prefix(expr[cursor^:], "dynamic<") {
        cursor^ += len("dynamic<")
        strings.write_string(builder, "[dynamic]")
        if !history_emit_type_node(builder, expr, cursor, manifest, sorted, false, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    start := cursor^
    for cursor^ < len(expr) && expr[cursor^] != '>' && expr[cursor^] != ']' && expr[cursor^] != '<' {
        cursor^ += 1
    }
    if start == cursor^ do return false
    atom := expr[start:cursor^]
    if strings.has_prefix(atom, "builtin:") {
        strings.write_string(builder, atom[len("builtin:"):])
        return true
    }
    if allow_raw_builtin && history_is_builtin(atom) {
        strings.write_string(builder, atom)
        return true
    }
    return history_emit_symbol(builder, manifest, sorted, atom)
}

history_emit_type :: proc(
    builder: ^strings.Builder,
    expr: string,
    manifest: ^History_Manifest,
    sorted: [dynamic]^History_Record,
    allow_raw_builtin: bool,
) -> bool {
    cursor := 0
    if !history_emit_type_node(builder, expr, &cursor, manifest, sorted, allow_raw_builtin, 0) do return false
    return cursor == len(expr)
}

history_emit_record_name :: proc(
    builder: ^strings.Builder,
    manifest: ^History_Manifest,
    sorted: [dynamic]^History_Record,
    record: ^History_Record,
) -> bool {
    return history_emit_symbol(builder, manifest, sorted, record.id)
}

history_emit_size_estimate :: proc(manifest: ^History_Manifest) -> (int, bool) {
    estimate := 1024
    for record in manifest.records {
        addition := 512 + len(record.id) + len(record.kind) + len(record.detail)
        if addition > HISTORY_MAX_EMITTED_BYTES - estimate do return 0, false
        estimate += addition
        for field in record.fields {
            addition = 256 + len(field.name) + len(field.tag) + len(field.type) * 2
            if addition > HISTORY_MAX_EMITTED_BYTES - estimate do return 0, false
            estimate += addition
        }
        for entry in record.enums {
            addition = 128 + len(entry.name)
            if addition > HISTORY_MAX_EMITTED_BYTES - estimate do return 0, false
            estimate += addition
        }
    }
    return estimate, true
}

history_emit_package :: proc(
    manifest: ^History_Manifest,
    manifest_sha256: string,
    allocator: mem.Allocator,
) -> (
    string,
    bool,
) {
    if manifest == nil ||
       manifest.format_version != HISTORY_SUPPORTED_FORMAT_VERSION ||
       manifest.schema_version < HISTORY_SUPPORTED_SCHEMA_VERSION_MIN ||
       manifest.schema_version > HISTORY_SUPPORTED_SCHEMA_VERSION_MAX {
        return "", false
    }
    if allocator.procedure == nil || !history_is_hex_sha256(manifest_sha256) do return "", false
    if _, estimate_ok := history_emit_size_estimate(manifest); !estimate_ok do return "", false
    sorted, sorted_ok := history_sorted_records(manifest, allocator)
    if !sorted_ok do return "", false
    defer delete(sorted)
    estimate, estimate_ok := history_emit_size_estimate(manifest)
    if !estimate_ok do return "", false
    builder, err := strings.builder_make_len_cap(0, estimate, allocator)
    if err != nil do return "", false
    strings.write_string(&builder, "// Code generated from immutable fixture history. DO NOT EDIT.\n")
    fmt.sbprintf(&builder, "// fixture-history-format-version: %d\n", manifest.format_version)
    fmt.sbprintf(&builder, "// fixture-history-schema-version: %d\n", manifest.schema_version)
    fmt.sbprintf(&builder, "// fixture-history-manifest-sha256: %s\n", manifest_sha256)
    fmt.sbprintf(&builder, "package fixture_v%04d\n\n", manifest.schema_version)
    fmt.sbprintf(&builder, "FIXTURE_SCHEMA_VERSION :: %d\n\n", manifest.schema_version)
    for record in sorted {
        fmt.sbprintf(&builder, "// fixture-history-id: %s\n", record.id)
        if record.kind == "enum" {
            using_value, _ := history_detail_value(record.detail, "using")
            if using_value == "1" do strings.write_string(&builder, "using ")
            if !history_emit_record_name(&builder, manifest, sorted, record) {
                strings.builder_destroy(&builder)
                return "", false
            }
            strings.write_string(&builder, " :: enum ")
            base, base_found := history_detail_value(record.detail, "base")
            if !base_found || !history_emit_type(&builder, base, manifest, sorted, true) {
                strings.builder_destroy(&builder)
                return "", false
            }
            strings.write_string(&builder, " {\n")
            for entry in record.enums {
                fmt.sbprintf(&builder, "\t%s = %d,\n", entry.name, entry.value)
            }
            strings.write_string(&builder, "}\n\n")
            continue
        }
        if !history_emit_record_name(&builder, manifest, sorted, record) {
            strings.builder_destroy(&builder)
            return "", false
        }
        switch record.kind {
        case "struct":
            strings.write_string(&builder, " :: struct {\n")
            for field in record.fields {
                if field.is_using {
                    strings.write_string(&builder, "\tusing ")
                } else {
                    strings.write_byte(&builder, '\t')
                }
                fmt.sbprintf(&builder, "%s: ", field.name)
                if !history_emit_type(&builder, field.type, manifest, sorted, false) {
                    strings.builder_destroy(&builder)
                    return "", false
                }
                strings.write_string(&builder, ",\n")
            }
            strings.write_string(&builder, "}\n\n")
        case "alias", "distinct":
            target, target_found := history_detail_value(record.detail, "target")
            if !target_found {
                strings.builder_destroy(&builder)
                return "", false
            }
            strings.write_string(&builder, " :: ")
            if record.kind == "distinct" do strings.write_string(&builder, "distinct ")
            if !history_emit_type(&builder, target, manifest, sorted, true) {
                strings.builder_destroy(&builder)
                return "", false
            }
            strings.write_string(&builder, "\n\n")
        case:
            strings.builder_destroy(&builder)
            return "", false
        }
        if len(builder.buf) > HISTORY_MAX_EMITTED_BYTES {
            strings.builder_destroy(&builder)
            return "", false
        }
    }
    return strings.to_string(builder), true
}
