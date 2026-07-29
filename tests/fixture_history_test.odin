package tests

import fixture_v0001 "../packages/fixture_history/v0001"
import fixture_v0003 "../packages/fixture_history/v0003"
import fixture_v0004 "../packages/fixture_history/v0004"
import fixture_schema "../packages/fixture_schema"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:odin/parser"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"

#assert(size_of(fixture_v0001.Fixture) > 0)
#assert(offset_of(fixture_v0001.Fixture, project) >= 0)
#assert(offset_of(fixture_v0001.History_Type_0123, city_plan) >= 0)
#assert(fixture_v0003.FIXTURE_SCHEMA_VERSION == 3)
#assert(offset_of(fixture_v0003.Fixture, occupant) >= 0)
#assert(size_of(fixture_v0003.History_Type_0103) == size_of(u8))
#assert(int(fixture_v0003.History_Type_0103.On_Foot) == 0)
#assert(int(fixture_v0003.History_Type_0103.Car) == 1)
#assert(int(fixture_v0003.History_Type_0103.Postale) == 2)
#assert(int(fixture_v0003.History_Type_0103.Libellula) == 3)
#assert(int(fixture_v0003.History_Type_0103.Libellula_Mk2) == 4)
#assert(fixture_v0004.FIXTURE_SCHEMA_VERSION == 4)
#assert(offset_of(fixture_v0004.Fixture, occupant) >= 0)
#assert(size_of(fixture_v0004.History_Type_0107) == size_of(u8))
#assert(int(fixture_v0004.History_Type_0107.On_Foot) == 0)
#assert(int(fixture_v0004.History_Type_0107.Car) == 1)
#assert(int(fixture_v0004.History_Type_0107.Postale) == 2)
#assert(int(fixture_v0004.History_Type_0107.Libellula) == 3)
#assert(int(fixture_v0004.History_Type_0107.Libellula_Mk2) == 4)
#assert(int(fixture_v0004.History_Type_0107.Rondine) == 5)

HISTORY_SYNTHETIC_MANIFEST ::
    "format_version=1\n" +
    "fixture_schema_version=1\n" +
    "root=adriatic:src.Fixture\n" +
    "type=adriatic:src.Fixture|kind=struct|detail=packed\\=0;raw_union\\=0;no_copy\\=0;all_or_none\\=0;simple\\=0;align\\=none;min_field_align\\=none;max_field_align\\=none\n" +
    "field=adriatic:src.Fixture|name=embedded|using=1|tag=hello\\|world\\=ok\\\\path|type=adriatic:src.Forward\n" +
    "field=adriatic:src.Fixture|name=mode|using=0|tag=|type=adriatic:src.Mode\n" +
    "field=adriatic:src.Fixture|name=alias_value|using=0|tag=|type=adriatic:src.Alias\n" +
    "field=adriatic:src.Fixture|name=distinct_value|using=0|tag=|type=adriatic:src.Distinct\n" +
    "type=adriatic:src.Alias|kind=alias|detail=target\\=array[256]<array[2]<builtin:u8>>\n" +
    "type=adriatic:src.Distinct|kind=distinct|detail=target\\=builtin:i32\n" +
    "type=adriatic:src.Forward|kind=struct|detail=packed\\=0;raw_union\\=0;no_copy\\=0;all_or_none\\=0;simple\\=0;align\\=none;min_field_align\\=none;max_field_align\\=none\n" +
    "field=adriatic:src.Forward|name=value|using=0|tag=|type=builtin:i16\n" +
    "type=adriatic:src.Mode|kind=enum|detail=using\\=0;base\\=builtin:i16\n" +
    "enum=adriatic:src.Mode|name=Negative|value=-4\n" +
    "enum=adriatic:src.Mode|name=Five|value=5\n" +
    "enum=adriatic:src.Mode|name=Six|value=6\n"

HISTORY_LINE_FIELD_MANIFEST ::
    "format_version=1\n" +
    "fixture_schema_version=1\n" +
    "root=adriatic:src.Fixture\n" +
    "type=adriatic:src.Fixture|kind=struct|detail=packed\\=0;raw_union\\=0;no_copy\\=0;all_or_none\\=0;simple\\=0;align\\=none;min_field_align\\=none;max_field_align\\=none\n" +
    "field=adriatic:src.Fixture|name=value|using=0|tag=|type=builtin:cstring\n"

HISTORY_LINE_ENUM_MANIFEST ::
    "format_version=1\n" +
    "fixture_schema_version=1\n" +
    "root=adriatic:src.Fixture\n" +
    "type=adriatic:src.Fixture|kind=struct|detail=packed\\=0;raw_union\\=0;no_copy\\=0;all_or_none\\=0;simple\\=0;align\\=none;min_field_align\\=none;max_field_align\\=none\n" +
    "field=adriatic:src.Fixture|name=mode|using=0|tag=|type=adriatic:src.Mode\n" +
    "type=adriatic:src.Mode|kind=enum|detail=using\\=0;base\\=builtin:u8\n" +
    "enum=adriatic:src.Mode|name=Too_High|value=256\n"

HISTORY_ENUMERATED_ARRAY_MANIFEST ::
    "format_version=1\n" +
    "fixture_schema_version=1\n" +
    "root=adriatic:src.Fixture\n" +
    "type=adriatic:src.Fixture|kind=struct|detail=packed\\=0;raw_union\\=0;no_copy\\=0;all_or_none\\=0;simple\\=0;align\\=none;min_field_align\\=none;max_field_align\\=none\n" +
    "field=adriatic:src.Fixture|name=slots|using=0|tag=|type=enumerated_array[3;adriatic:src.Index]<adriatic:src.Element>\n" +
    "type=adriatic:src.Index|kind=enum|detail=using\\=0;base\\=builtin:i8\n" +
    "enum=adriatic:src.Index|name=West|value=-1\n" +
    "enum=adriatic:src.Index|name=Center|value=0\n" +
    "enum=adriatic:src.Index|name=East|value=1\n" +
    "type=adriatic:src.Element|kind=distinct|detail=target\\=builtin:u64\n"

Fixture_History_Fault_Allocator :: struct {
    backing:     mem.Allocator,
    attempts:    int,
    fail_index:  int,
    outstanding: int,
}

fixture_history_fault_allocator_proc :: proc(
    data: rawptr,
    mode: mem.Allocator_Mode,
    size, alignment: int,
    old_memory: rawptr,
    old_size: int,
    location := #caller_location,
) -> (
    []byte,
    mem.Allocator_Error,
) {
    state := (^Fixture_History_Fault_Allocator)(data)
    allocation := mode == .Alloc || mode == .Alloc_Non_Zeroed || mode == .Resize || mode == .Resize_Non_Zeroed
    if allocation {
        attempt := state.attempts
        state.attempts += 1
        if state.fail_index >= 0 && attempt == state.fail_index do return nil, .Out_Of_Memory
    }
    result, error := state.backing.procedure(state.backing.data, mode, size, alignment, old_memory, old_size, location)
    if error == nil {
        switch mode {
        case .Alloc, .Alloc_Non_Zeroed:
            if result != nil do state.outstanding += 1
        case .Free:
            if old_memory != nil do state.outstanding -= 1
        case .Free_All:
            state.outstanding = 0
        case .Resize, .Resize_Non_Zeroed:
            if old_memory == nil && result != nil do state.outstanding += 1
            if old_memory != nil && result == nil do state.outstanding -= 1
        case .Query_Features, .Query_Info:
        }
    }
    return result, error
}

fixture_history_fault_allocator :: proc(state: ^Fixture_History_Fault_Allocator) -> mem.Allocator {
    return {procedure = fixture_history_fault_allocator_proc, data = rawptr(state)}
}

history_replace :: proc(source, old, new: string) -> string {
    output, _ := strings.replace_all(source, old, new, context.allocator)
    return output
}

history_join :: proc(first, second: string) -> string {
    parts := [2]string{first, second}
    output, _ := strings.concatenate(parts[:], context.allocator)
    return output
}

history_deep_type :: proc(depth: int) -> string {
    builder, _ := strings.builder_make(context.allocator)
    for _ in 0 ..< depth {
        strings.write_string(&builder, "array[1]<")
    }
    strings.write_string(&builder, "builtin:i16")
    for _ in 0 ..< depth {
        strings.write_byte(&builder, '>')
    }
    return strings.to_string(builder)
}

history_struct_fields :: proc(source: string, count: int) -> string {
    builder, _ := strings.builder_make(context.allocator)
    strings.write_string(&builder, source)
    strings.write_string(
        &builder,
        "type=adriatic:src.Cap|kind=struct|detail=packed\\=0;raw_union\\=0;no_copy\\=0;all_or_none\\=0;simple\\=0;align\\=none;min_field_align\\=none;max_field_align\\=none\n",
    )
    for index in 0 ..< count {
        fmt.sbprintf(&builder, "field=adriatic:src.Cap|name=f%d|using=0|tag=|type=builtin:i16\n", index)
    }
    return strings.to_string(builder)
}

history_records :: proc(source: string, count: int) -> string {
    builder, _ := strings.builder_make(context.allocator)
    strings.write_string(&builder, source)
    for index in 0 ..< count {
        fmt.sbprintf(&builder, "type=adriatic:src.Cap%d|kind=alias|detail=target\\=builtin:i16\n", index)
    }
    return strings.to_string(builder)
}

history_expect_failure :: proc(t: ^testing.T, source: string) {
    manifest, error, ok := fixture_schema.history_parse_manifest(transmute([]byte)source, context.allocator)
    testing.expect(t, !ok)
    testing.expect(t, error.kind != .None)
    testing.expect(t, error.line > 0)
    fixture_schema.history_manifest_dispose(&manifest)
    fixture_schema.history_error_dispose(&error)
    fixture_schema.history_error_dispose(&error)
}

history_expect_failure_kind :: proc(t: ^testing.T, source: string, expected: fixture_schema.History_Error_Kind) {
    manifest, error, ok := fixture_schema.history_parse_manifest(transmute([]byte)source, context.allocator)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == expected)
    testing.expect(t, error.line > 0)
    fixture_schema.history_manifest_dispose(&manifest)
    fixture_schema.history_error_dispose(&error)
    fixture_schema.history_error_dispose(&error)
}

history_expect_failure_exact :: proc(
    t: ^testing.T,
    source: string,
    expected: fixture_schema.History_Error_Kind,
    line: int,
    path: string,
) {
    manifest, error, ok := fixture_schema.history_parse_manifest(transmute([]byte)source, context.allocator)
    testing.expect(t, !ok)
    testing.expect(t, error.kind == expected)
    testing.expect(t, error.line == line)
    testing.expect(t, error.path == path)
    fixture_schema.history_manifest_dispose(&manifest)
    fixture_schema.history_error_dispose(&error)
    fixture_schema.history_error_dispose(&error)
}

history_expect_success :: proc(t: ^testing.T, source: string) {
    manifest, error, ok := fixture_schema.history_parse_manifest(transmute([]byte)source, context.allocator)
    testing.expect(t, ok && error.kind == .None)
    fixture_schema.history_manifest_dispose(&manifest)
    fixture_schema.history_error_dispose(&error)
}

@(test)
fixture_history_manifest_accepts_frozen_grammar :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := string(HISTORY_SYNTHETIC_MANIFEST)
    manifest, error, ok := fixture_schema.history_parse_manifest(transmute([]byte)source, context.allocator)
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    if !ok do return
    defer fixture_schema.history_manifest_dispose(&manifest)
    testing.expect(t, len(manifest.records) == 5)
    testing.expect(t, manifest.root == "adriatic:src.Fixture")
    testing.expect(t, len(manifest.records[0].fields) == 4)
    testing.expect(t, manifest.records[0].fields[0].is_using)
    testing.expect(t, manifest.records[0].fields[0].tag == "hello|world=ok\\path")
    testing.expect(t, manifest.records[4].enums[0].value == -4)

    sha, sha_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)source, context.allocator)
    testing.expect(t, sha_ok)
    if !sha_ok do return
    defer delete(sha)
    generated, generated_ok := fixture_schema.history_emit_package(&manifest, sha, context.allocator)
    testing.expect(t, generated_ok)
    if !generated_ok do return
    defer delete(generated)
    testing.expect(t, strings.contains(generated, "package fixture_v0001"))
    testing.expect(t, strings.contains(generated, "Fixture :: struct"))
    testing.expect(t, strings.contains(generated, "using embedded: History_Type_"))
    testing.expect(t, strings.contains(generated, "[256][2]u8"))
    testing.expect(t, strings.contains(generated, ":: distinct i32"))
    testing.expect(t, strings.contains(generated, ":: enum i16"))
}

@(test)
fixture_history_enumerated_arrays_are_exact_strict_and_owned :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := string(HISTORY_ENUMERATED_ARRAY_MANIFEST)
    manifest, error, ok := fixture_schema.history_parse_manifest(transmute([]byte)source, context.allocator)
    testing.expect(t, ok && error.kind == .None)
    if !ok {
        fixture_schema.history_error_dispose(&error)
        return
    }
    defer fixture_schema.history_manifest_dispose(&manifest)
    sha, sha_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)source, context.allocator)
    testing.expect(t, sha_ok)
    if !sha_ok do return
    defer delete(sha)
    generated, generated_ok := fixture_schema.history_emit_package(&manifest, sha, context.allocator)
    testing.expect(t, generated_ok)
    if !generated_ok do return
    defer delete(generated)
    testing.expect(t, strings.contains(generated, "\tslots: [History_Type_0002]History_Type_0000,\n"))

    index_record: ^fixture_schema.History_Record
    for &record in manifest.records {
        if record.id == "adriatic:src.Index" {
            index_record = &record
            break
        }
    }
    testing.expect(t, index_record != nil)
    if index_record != nil {
        original_kind := index_record.kind
        index_record.kind = "struct"
        rejected, rejected_ok := fixture_schema.history_emit_package(&manifest, sha, context.allocator)
        testing.expect(t, !rejected_ok && len(rejected) == 0)
        delete(rejected)
        index_record.kind = original_kind
    }

    hostile := [?]string {
        history_replace(source, "enumerated_array[3;", "enumerated_array[2;"),
        history_replace(source, ";adriatic:src.Index]", ";adriatic:src.Element]"),
        history_replace(source, ";adriatic:src.Index]", ";adriatic:src.Missing]"),
        history_replace(source, "enumerated_array[3;", "enumerated_array[3"),
        history_replace(source, "name=East|value=1", "name=East|value=2"),
    }
    for invalid in hostile {
        history_expect_failure_exact(t, invalid, .Unresolved_Reference, 5, "adriatic:src.Fixture.slots")
        delete(invalid)
    }
    duplicate := history_replace(source, "name=East|value=1", "name=East|value=0")
    history_expect_failure_exact(t, duplicate, .Invalid_Input, 9, "adriatic:src.Index.East")
    delete(duplicate)

    success_state := Fixture_History_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_history_fault_allocator(&success_state)
    owned, owned_error, owned_ok := fixture_schema.history_parse_manifest(transmute([]byte)source, success_allocator)
    testing.expect(t, owned_ok && owned_error.kind == .None && success_state.attempts > 0)
    fixture_schema.history_manifest_dispose(&owned)
    fixture_schema.history_manifest_dispose(&owned)
    fixture_schema.history_error_dispose(&owned_error)
    fixture_schema.history_error_dispose(&owned_error)
    testing.expect(t, success_state.outstanding == 0)
    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_History_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_history_fault_allocator(&state)
        failed, failed_error, failed_ok := fixture_schema.history_parse_manifest(transmute([]byte)source, allocator)
        testing.expect(t, !failed_ok && failed_error.kind == .Out_Of_Memory)
        fixture_schema.history_manifest_dispose(&failed)
        fixture_schema.history_manifest_dispose(&failed)
        fixture_schema.history_error_dispose(&failed_error)
        fixture_schema.history_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }
}

@(test)
fixture_history_manifest_rejects_malformed_inputs :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := string(HISTORY_SYNTHETIC_MANIFEST)
    cases := [?]string {
        history_join("fixture_schema_version=1\n", source[len("format_version=1\n"):]),
        history_join(source, "unknown=value\n"),
        source[:len(source) - 1],
        history_replace(source, "tag=hello\\|world", "tag=hello|world"),
        history_replace(source, "tag=hello\\|world", "tag=hello\\qworld"),
        history_replace(source, "kind=alias|detail=target\\=array", "kind=alias|detail=unknown\\=array"),
        history_replace(source, "type=adriatic:src.Distinct", "type=adriatic:src.Distinct|kind=distinct"),
        history_replace(
            source,
            "type=adriatic:src.Distinct|kind=distinct|detail=target\\=builtin:i32",
            "type=adriatic:src.Distinct|kind=distinct|detail=target\\=dynamic<int>",
        ),
        history_replace(source, "type=builtin:i16", "type=[]builtin:i16"),
        history_replace(
            source,
            "type=adriatic:src.Forward|kind=struct",
            "type=adriatic:src.Forward|kind=struct|detail=bad\\=0",
        ),
    }
    for case_source in cases {
        history_expect_failure(t, case_source)
    }

    history_expect_failure_exact(
        t,
        history_replace(source, "tag=hello\\|world", "tag=hello\\qworld"),
        .Invalid_Input,
        5,
        "adriatic:src.Fixture.embedded",
    )
    history_expect_failure_exact(
        t,
        history_replace(source, "type=builtin:i16", "type=builtin:i16\\q"),
        .Invalid_Input,
        12,
        "adriatic:src.Forward.value",
    )
    history_expect_failure_exact(
        t,
        string(HISTORY_LINE_FIELD_MANIFEST),
        .Invalid_Input,
        5,
        "adriatic:src.Fixture.value",
    )
    history_expect_failure_exact(
        t,
        history_replace(HISTORY_LINE_FIELD_MANIFEST, "builtin:cstring", "adriatic:src.Missing"),
        .Unresolved_Reference,
        5,
        "adriatic:src.Fixture.value",
    )
    history_expect_failure_kind(t, history_replace(source, "type=builtin:i16", "type=builtin:cstring"), .Invalid_Input)
    history_expect_failure_kind(t, history_replace(source, "type=builtin:i16", "type=builtin:i128"), .Invalid_Input)
    history_expect_failure_kind(
        t,
        history_replace(source, "type=builtin:i16", "type=builtin:complex64"),
        .Invalid_Input,
    )
    history_expect_failure_kind(
        t,
        history_replace(source, "type=builtin:i16", "type=builtin:quaternion64"),
        .Invalid_Input,
    )
    history_expect_failure_kind(t, history_replace(source, "raw_union\\=0", "raw_union\\=1"), .Invalid_Input)
    history_expect_failure_kind(t, history_replace(source, "packed\\=0", "packed\\=1"), .Invalid_Input)
    history_expect_failure_kind(t, history_replace(source, "no_copy\\=0", "no_copy\\=1"), .Invalid_Input)
    history_expect_failure_kind(t, history_replace(source, "all_or_none\\=0", "all_or_none\\=1"), .Invalid_Input)
    history_expect_failure_kind(t, history_replace(source, "simple\\=0", "simple\\=1"), .Invalid_Input)
    history_expect_failure_kind(t, history_replace(source, "align\\=none", "align\\=1"), .Invalid_Input)
    history_expect_failure_kind(
        t,
        history_replace(source, "min_field_align\\=none", "min_field_align\\=1"),
        .Invalid_Input,
    )
    history_expect_failure_kind(
        t,
        history_replace(source, "max_field_align\\=none", "max_field_align\\=1"),
        .Invalid_Input,
    )
    history_expect_failure_kind(
        t,
        history_replace(source, "type=adriatic:src.Forward", "type=builtin:i16"),
        .Invalid_Input,
    )
    history_expect_failure_kind(t, history_replace(source, "name=embedded", "name=using"), .Invalid_Input)
    history_expect_failure_kind(t, history_replace(source, "name=Six", "name=package"), .Invalid_Input)

    u8_values := history_replace(source, "base\\=builtin:i16", "base\\=builtin:u8")
    u8_values = history_replace(u8_values, "value=-4", "value=0")
    u8_values = history_replace(u8_values, "value=5", "value=255")
    u8_values = history_replace(u8_values, "value=6", "value=256")
    history_expect_failure_kind(t, u8_values, .Invalid_Input)
    history_expect_failure_kind(t, history_replace(u8_values, "value=256", "value=-1"), .Invalid_Input)
    i8_high := history_replace(source, "base\\=builtin:i16", "base\\=builtin:i8")
    history_expect_failure_kind(t, history_replace(i8_high, "value=6", "value=128"), .Invalid_Input)
    history_expect_failure_kind(t, history_replace(i8_high, "value=-4", "value=-129"), .Invalid_Input)
    u64_values := history_replace(source, "base\\=builtin:i16", "base\\=builtin:u64")
    history_expect_failure_kind(
        t,
        history_replace(u64_values, "value=-4", "value=9223372036854775808"),
        .Invalid_Input,
    )

    empty_enum := history_replace(source, "enum=adriatic:src.Mode|name=Negative|value=-4\n", "")
    empty_enum = history_replace(empty_enum, "enum=adriatic:src.Mode|name=Five|value=5\n", "")
    empty_enum = history_replace(empty_enum, "enum=adriatic:src.Mode|name=Six|value=6\n", "")
    history_expect_failure_kind(t, empty_enum, .Invalid_Input)

    malformed_using := history_replace(
        source,
        "field=adriatic:src.Fixture|name=embedded|using=1",
        "field=adriatic:src.Fixture|name=embedded|using=2",
    )
    history_expect_failure_exact(t, malformed_using, .Invalid_Input, 5, "adriatic:src.Fixture.embedded")
    duplicate_field := history_replace(
        source,
        "field=adriatic:src.Fixture|name=mode|",
        "field=adriatic:src.Fixture|name=embedded|",
    )
    history_expect_failure_exact(t, duplicate_field, .Invalid_Input, 6, "adriatic:src.Fixture.embedded")
    duplicate_enum := history_replace(source, "name=Six|value=6", "name=Six|value=5")
    history_expect_failure_exact(t, duplicate_enum, .Invalid_Input, 16, "adriatic:src.Mode.Six")
    invalid_enum_text := history_replace(source, "name=Six|value=6", "name=Six|value=not_a_number")
    history_expect_failure_exact(t, invalid_enum_text, .Invalid_Input, 16, "adriatic:src.Mode.Six")
    out_of_i64_enum := history_replace(source, "name=Six|value=6", "name=Six|value=9223372036854775808")
    history_expect_failure_exact(t, out_of_i64_enum, .Invalid_Input, 16, "adriatic:src.Mode.Six")
    history_expect_failure_exact(
        t,
        history_replace(HISTORY_LINE_ENUM_MANIFEST, "value=256", "value=-1"),
        .Invalid_Input,
        7,
        "adriatic:src.Mode.Too_High",
    )
    unresolved := history_replace(source, "type=adriatic:src.Mode", "type=adriatic:src.Missing")
    history_expect_failure(t, unresolved)
    unreachable := history_join(
        source,
        "type=adriatic:src.Orphan|kind=struct|detail=packed\\=0;raw_union\\=0;no_copy\\=0;all_or_none\\=0;simple\\=0;align\\=none;min_field_align\\=none;max_field_align\\=none\n",
    )
    history_expect_failure(t, unreachable)
    recursive := history_replace(
        source,
        "field=adriatic:src.Forward|name=value|using=0|tag=|type=builtin:i16",
        "field=adriatic:src.Forward|name=value|using=0|tag=|type=adriatic:src.Forward",
    )
    history_expect_failure(t, recursive)

    scalar_using := history_replace(source, "type=adriatic:src.Forward\n", "type=builtin:i16\n")
    history_expect_failure_exact(t, scalar_using, .Invalid_Input, 5, "adriatic:src.Fixture.embedded")
    array_using := history_replace(source, "type=adriatic:src.Forward\n", "type=array[1]<builtin:i16>\n")
    history_expect_failure_exact(t, array_using, .Invalid_Input, 5, "adriatic:src.Fixture.embedded")
    enum_using := history_replace(source, "type=adriatic:src.Forward\n", "type=adriatic:src.Mode\n")
    history_expect_failure_exact(t, enum_using, .Invalid_Input, 5, "adriatic:src.Fixture.embedded")
    distinct_using := history_replace(source, "type=adriatic:src.Forward\n", "type=adriatic:src.Distinct\n")
    history_expect_failure_exact(t, distinct_using, .Invalid_Input, 5, "adriatic:src.Fixture.embedded")
    cyclic_using := history_replace(source, "type=adriatic:src.Forward\n", "type=adriatic:src.Cycle_A\n")
    cyclic_using = history_join(
        cyclic_using,
        "type=adriatic:src.Cycle_A|kind=alias|detail=target\\=adriatic:src.Cycle_B\n" +
        "type=adriatic:src.Cycle_B|kind=alias|detail=target\\=adriatic:src.Cycle_A\n",
    )
    history_expect_failure_exact(t, cyclic_using, .Invalid_Input, 5, "adriatic:src.Fixture.embedded")
    alias_using := history_replace(
        source,
        "field=adriatic:src.Fixture|name=alias_value|using=0",
        "field=adriatic:src.Fixture|name=alias_value|using=1",
    )
    alias_using = history_replace(
        alias_using,
        "target\\=array[256]<array[2]<builtin:u8>>",
        "target\\=adriatic:src.Forward",
    )
    history_expect_success(t, alias_using)

    i64_edges := history_replace(source, "base\\=builtin:i16", "base\\=builtin:i64")
    i64_edges = history_replace(i64_edges, "value=-4", "value=-9223372036854775808")
    i64_edges = history_replace(i64_edges, "value=5", "value=9223372036854775807")
    i64_edges = history_replace(i64_edges, "value=6", "value=0")
    history_expect_success(t, i64_edges)
    u64_edges := history_replace(source, "base\\=builtin:i16", "base\\=builtin:u64")
    u64_edges = history_replace(u64_edges, "value=-4", "value=0")
    u64_edges = history_replace(u64_edges, "value=5", "value=9223372036854775807")
    u64_edges = history_replace(u64_edges, "value=6", "value=1")
    history_expect_success(t, u64_edges)
    uint_edges := history_replace(source, "base\\=builtin:i16", "base\\=builtin:uint")
    uint_edges = history_replace(uint_edges, "value=-4", "value=0")
    uint_edges = history_replace(uint_edges, "value=5", "value=9223372036854775807")
    uint_edges = history_replace(uint_edges, "value=6", "value=1")
    history_expect_success(t, uint_edges)

    oversized := make([]byte, fixture_schema.HISTORY_MANIFEST_MAX_BYTES + 1, context.allocator)
    history_expect_failure_kind(t, string(oversized), .Limit_Exceeded)
    history_expect_failure_kind(
        t,
        history_struct_fields(source, fixture_schema.HISTORY_MANIFEST_MAX_LINES),
        .Limit_Exceeded,
    )
    history_expect_failure_kind(
        t,
        history_records(source, fixture_schema.HISTORY_MANIFEST_MAX_RECORDS),
        .Limit_Exceeded,
    )
    too_deep := history_deep_type(fixture_schema.HISTORY_MANIFEST_MAX_TYPE_DEPTH + 1)
    deep_type_line := history_join("type=", too_deep)
    history_expect_failure_kind(t, history_replace(source, "type=builtin:i16", deep_type_line), .Invalid_Input)
    history_expect_failure_kind(t, history_replace(source, "array[256]", "array[16777217]"), .Invalid_Input)
}

@(test)
fixture_history_synthetic_output_parses :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := string(HISTORY_SYNTHETIC_MANIFEST)
    manifest, error, ok := fixture_schema.history_parse_manifest(transmute([]byte)source, context.allocator)
    testing.expect(t, ok && error.kind == .None)
    if !ok do return
    defer fixture_schema.history_manifest_dispose(&manifest)
    sha, sha_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)source, context.allocator)
    testing.expect(t, sha_ok)
    if !sha_ok do return
    defer delete(sha)
    generated, generated_ok := fixture_schema.history_emit_package(&manifest, sha, context.allocator)
    testing.expect(t, generated_ok)
    if !generated_ok do return
    defer delete(generated)

    root, root_error := os.make_directory_temp("", "fixture-history-*", context.allocator)
    testing.expect(t, root_error == nil)
    if root_error != nil do return
    defer os.remove_all(root)
    package_root, package_error := filepath.join({root, "synthetic"}, context.allocator)
    testing.expect(t, package_error == nil)
    if package_error != nil do return
    testing.expect(t, os.make_directory_all(package_root) == nil)
    package_file, file_error := filepath.join({package_root, "schema.generated.odin"}, context.allocator)
    testing.expect(t, file_error == nil)
    if file_error != nil do return
    testing.expect(t, os.write_entire_file(package_file, generated) == nil)
    parsed, parse_ok := parser.parse_package_from_path(package_root)
    testing.expect(t, parsed != nil && parse_ok)
}

@(test)
fixture_history_basename_symbols_are_distinct :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := string(HISTORY_SYNTHETIC_MANIFEST)
    other_field := "field=adriatic:src.Fixture|name=other_forward|using=0|tag=|type=adriatic:other.Forward\n"
    collision := history_replace(
        source,
        "field=adriatic:src.Fixture|name=embedded",
        history_join(other_field, "field=adriatic:src.Fixture|name=embedded"),
    )
    collision = history_join(
        collision,
        "type=adriatic:other.Forward|kind=struct|detail=packed\\=0;raw_union\\=0;no_copy\\=0;all_or_none\\=0;simple\\=0;align\\=none;min_field_align\\=none;max_field_align\\=none\n" +
        "field=adriatic:other.Forward|name=value|using=0|tag=|type=builtin:i16\n",
    )
    manifest, error, ok := fixture_schema.history_parse_manifest(transmute([]byte)collision, context.allocator)
    testing.expect(t, ok && error.kind == .None)
    if !ok do return
    defer fixture_schema.history_manifest_dispose(&manifest)
    sha, sha_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)collision, context.allocator)
    testing.expect(t, sha_ok)
    if !sha_ok do return
    defer delete(sha)
    generated, generated_ok := fixture_schema.history_emit_package(&manifest, sha, context.allocator)
    testing.expect(t, generated_ok)
    if !generated_ok do return
    defer delete(generated)
    first := strings.index(generated, "other_forward: History_Type_")
    second := strings.index(generated, "using embedded: History_Type_")
    testing.expect(t, first >= 0 && second >= 0)
    if first < 0 || second < 0 do return
    testing.expect(
        t,
        generated[first:first +
        len("other_forward: History_Type_") +
        4] !=
        generated[second:second + len("using embedded: History_Type_") + 4],
    )
}

@(test)
fixture_history_package_is_path_and_allocator_deterministic :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := string(HISTORY_SYNTHETIC_MANIFEST)
    first, first_error, first_ok := fixture_schema.history_parse_manifest(transmute([]byte)source, context.allocator)
    testing.expect(t, first_ok && first_error.kind == .None)
    if !first_ok do return
    defer fixture_schema.history_manifest_dispose(&first)
    second, second_error, second_ok := fixture_schema.history_parse_manifest(
        transmute([]byte)source,
        context.allocator,
    )
    testing.expect(t, second_ok && second_error.kind == .None)
    if !second_ok do return
    defer fixture_schema.history_manifest_dispose(&second)
    first_sha, first_sha_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)source, context.allocator)
    second_sha, second_sha_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)source, context.allocator)
    testing.expect(t, first_sha_ok && second_sha_ok && first_sha == second_sha)
    if !first_sha_ok || !second_sha_ok do return
    defer delete(first_sha)
    defer delete(second_sha)
    first_output, first_output_ok := fixture_schema.history_emit_package(&first, first_sha, context.allocator)
    second_output, second_output_ok := fixture_schema.history_emit_package(&second, second_sha, context.allocator)
    testing.expect(t, first_output_ok && second_output_ok)
    testing.expect(t, first_output == second_output)
    if first_output_ok do delete(first_output)
    if second_output_ok do delete(second_output)
}

@(test)
fixture_history_frozen_v1_is_complete :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    data, read_error := os.read_entire_file("fixtures/schema/v0001.fixture-schema", context.allocator)
    testing.expect(t, read_error == nil)
    if read_error != nil do return
    manifest, error, ok := fixture_schema.history_parse_manifest(data, context.allocator)
    testing.expect(t, ok && error.kind == .None)
    if !ok do return
    defer fixture_schema.history_manifest_dispose(&manifest)
    defer delete(data)
    testing.expect(t, len(manifest.records) == 144)
    root_fields := 0
    for record in manifest.records {
        if record.id == manifest.root {
            root_fields = len(record.fields)
        }
    }
    testing.expect(t, root_fields == 142)
    testing.expect(t, strings.contains(manifest.root, "adriatic:src.Fixture"))
    sha, sha_ok := fixture_schema.history_manifest_sha256_hex(data, context.allocator)
    testing.expect(t, sha_ok && sha == "2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12")
    if !sha_ok do return
    defer delete(sha)
    generated, generated_ok := fixture_schema.history_emit_package(&manifest, sha, context.allocator)
    testing.expect(t, generated_ok)
    if !generated_ok do return
    defer delete(generated)
    testing.expect(t, strings.contains(generated, "Settlement_Plan"))
    testing.expect(t, strings.contains(generated, "city_plan:"))
    testing.expect(t, strings.contains(generated, "vehicle_paint_layers: [3][8388608]u8"))
}

@(test)
fixture_history_manifest_parser_allocation_failures :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := string(HISTORY_SYNTHETIC_MANIFEST)

    success_state := Fixture_History_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_history_fault_allocator(&success_state)
    manifest, error, ok := fixture_schema.history_parse_manifest(transmute([]byte)source, success_allocator)
    testing.expect(t, ok && error.kind == .None)
    testing.expect(t, success_state.attempts > 0)
    if ok do fixture_schema.history_manifest_dispose(&manifest)
    fixture_schema.history_manifest_dispose(&manifest)
    fixture_schema.history_error_dispose(&error)
    fixture_schema.history_error_dispose(&error)
    testing.expect(t, success_state.outstanding == 0)

    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_History_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_history_fault_allocator(&state)
        failed_manifest, failed_error, failed_ok := fixture_schema.history_parse_manifest(
            transmute([]byte)source,
            allocator,
        )
        testing.expect(t, !failed_ok)
        testing.expect(t, failed_error.kind == .Out_Of_Memory)
        fixture_schema.history_manifest_dispose(&failed_manifest)
        fixture_schema.history_manifest_dispose(&failed_manifest)
        fixture_schema.history_error_dispose(&failed_error)
        fixture_schema.history_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }

    nil_manifest, nil_error, nil_ok := fixture_schema.history_parse_manifest(transmute([]byte)source, mem.Allocator{})
    testing.expect(t, !nil_ok && nil_error.kind == .Out_Of_Memory)
    fixture_schema.history_manifest_dispose(&nil_manifest)
    fixture_schema.history_error_dispose(&nil_error)
    fixture_schema.history_error_dispose(&nil_error)
}

@(test)
fixture_history_sha256_allocation_failures :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    source := string(HISTORY_SYNTHETIC_MANIFEST)
    expected, expected_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)source, context.allocator)
    testing.expect(t, expected_ok && fixture_schema.history_is_hex_sha256(expected))
    if !expected_ok do return
    defer delete(expected)

    success_state := Fixture_History_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_history_fault_allocator(&success_state)
    actual, actual_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)source, success_allocator)
    testing.expect(t, actual_ok && actual == expected)
    testing.expect(t, success_state.attempts > 0)
    if actual_ok do delete(actual, success_allocator)
    testing.expect(t, success_state.outstanding == 0)

    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_History_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_history_fault_allocator(&state)
        failed, failed_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)source, allocator)
        testing.expect(t, !failed_ok && len(failed) == 0)
        delete(failed, allocator)
        testing.expect(t, state.outstanding == 0)
    }

    nil_hash, nil_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)source, mem.Allocator{})
    testing.expect(t, !nil_ok && len(nil_hash) == 0)
    delete(nil_hash, mem.Allocator{})
}

@(test)
fixture_history_supports_later_schema_versions :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    v1_data, v1_read_error := os.read_entire_file("fixtures/schema/v0001.fixture-schema", context.allocator)
    testing.expect(t, v1_read_error == nil)
    if v1_read_error != nil do return
    defer delete(v1_data)
    v1_manifest, v1_error, v1_ok := fixture_schema.history_parse_manifest(v1_data, context.allocator)
    testing.expect(t, v1_ok && v1_error.kind == .None)
    if !v1_ok {
        fixture_schema.history_error_dispose(&v1_error)
        return
    }
    defer fixture_schema.history_manifest_dispose(&v1_manifest)
    v1_sha, v1_sha_ok := fixture_schema.history_manifest_sha256_hex(v1_data, context.allocator)
    testing.expect(t, v1_sha_ok)
    if !v1_sha_ok do return
    defer delete(v1_sha)
    v1_generated, v1_generated_ok := fixture_schema.history_emit_package(&v1_manifest, v1_sha, context.allocator)
    testing.expect(t, v1_generated_ok)
    if !v1_generated_ok do return
    defer delete(v1_generated)
    v1_expected, v1_expected_error := os.read_entire_file(
        "packages/fixture_history/v0001/schema.generated.odin",
        context.allocator,
    )
    testing.expect(t, v1_expected_error == nil && string(v1_expected) == v1_generated)
    defer delete(v1_expected)

    v2_source := history_replace(
        string(HISTORY_SYNTHETIC_MANIFEST),
        "fixture_schema_version=1",
        "fixture_schema_version=2",
    )
    defer delete(v2_source)
    v2_manifest, v2_error, v2_ok := fixture_schema.history_parse_manifest(
        transmute([]byte)v2_source,
        context.allocator,
    )
    testing.expect(t, v2_ok && v2_error.kind == .None)
    if !v2_ok {
        fixture_schema.history_error_dispose(&v2_error)
        return
    }
    defer fixture_schema.history_manifest_dispose(&v2_manifest)
    testing.expect(t, v2_manifest.schema_version == 2)
    v2_sha, v2_sha_ok := fixture_schema.history_manifest_sha256_hex(transmute([]byte)v2_source, context.allocator)
    testing.expect(t, v2_sha_ok)
    if !v2_sha_ok do return
    defer delete(v2_sha)
    v2_generated, v2_generated_ok := fixture_schema.history_emit_package(&v2_manifest, v2_sha, context.allocator)
    testing.expect(t, v2_generated_ok)
    if !v2_generated_ok do return
    defer delete(v2_generated)
    testing.expect(t, strings.contains(v2_generated, "package fixture_v0002"))
    testing.expect(t, strings.contains(v2_generated, "FIXTURE_SCHEMA_VERSION :: 2"))
    testing.expect(t, strings.contains(v2_generated, "fixture-history-schema-version: 2"))

    real_v2_data, real_v2_read_error := os.read_entire_file("fixtures/schema/v0002.fixture-schema", context.allocator)
    testing.expect(t, real_v2_read_error == nil)
    if real_v2_read_error != nil do return
    defer delete(real_v2_data)
    real_v2_manifest, real_v2_error, real_v2_ok := fixture_schema.history_parse_manifest(
        real_v2_data,
        context.allocator,
    )
    testing.expect(t, real_v2_ok && real_v2_error.kind == .None)
    if !real_v2_ok {
        fixture_schema.history_error_dispose(&real_v2_error)
        return
    }
    defer fixture_schema.history_manifest_dispose(&real_v2_manifest)
    testing.expect(t, real_v2_manifest.schema_version == 2)
    real_v2_sha, real_v2_sha_ok := fixture_schema.history_manifest_sha256_hex(real_v2_data, context.allocator)
    testing.expect(
        t,
        real_v2_sha_ok && real_v2_sha == "0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2",
    )
    if !real_v2_sha_ok do return
    defer delete(real_v2_sha)
    real_v2_generated, real_v2_generated_ok := fixture_schema.history_emit_package(
        &real_v2_manifest,
        real_v2_sha,
        context.allocator,
    )
    testing.expect(t, real_v2_generated_ok)
    if !real_v2_generated_ok do return
    defer delete(real_v2_generated)
    testing.expect(t, strings.contains(real_v2_generated, "package fixture_v0002"))
    testing.expect(t, strings.contains(real_v2_generated, "FIXTURE_SCHEMA_VERSION :: 2"))
    testing.expect(t, strings.contains(real_v2_generated, "[dynamic]"))
    testing.expect(t, !strings.contains(real_v2_generated, "dynamic<"))

    real_v3_data, real_v3_read_error := os.read_entire_file("fixtures/schema/v0003.fixture-schema", context.allocator)
    testing.expect(t, real_v3_read_error == nil)
    if real_v3_read_error != nil do return
    defer delete(real_v3_data)
    real_v3_manifest, real_v3_error, real_v3_ok := fixture_schema.history_parse_manifest(
        real_v3_data,
        context.allocator,
    )
    testing.expect(t, real_v3_ok && real_v3_error.kind == .None)
    if !real_v3_ok {
        fixture_schema.history_error_dispose(&real_v3_error)
        return
    }
    defer fixture_schema.history_manifest_dispose(&real_v3_manifest)
    testing.expect(t, real_v3_manifest.schema_version == 3 && len(real_v3_manifest.records) == 150)
    root_fields := 0
    occupant_found := false
    occupant_enum_found := false
    for record in real_v3_manifest.records {
        if record.id == real_v3_manifest.root {
            root_fields = len(record.fields)
            for field in record.fields {
                if field.name == "occupant" {
                    occupant_found =
                        !field.is_using &&
                        field.tag == "" &&
                        field.type == "adriatic:packages/vehicles.Fixture_Occupant"
                }
            }
        }
        if record.id == "adriatic:packages/vehicles.Fixture_Occupant" {
            occupant_enum_found =
                record.kind == "enum" &&
                record.detail == "using=0;base=builtin:u8" &&
                len(record.enums) == 5 &&
                record.enums[0].name == "On_Foot" &&
                record.enums[0].value == 0 &&
                record.enums[1].name == "Car" &&
                record.enums[1].value == 1 &&
                record.enums[2].name == "Postale" &&
                record.enums[2].value == 2 &&
                record.enums[3].name == "Libellula" &&
                record.enums[3].value == 3 &&
                record.enums[4].name == "Libellula_Mk2" &&
                record.enums[4].value == 4
        }
    }
    testing.expect(t, root_fields == 146 && occupant_found && occupant_enum_found)
    real_v3_sha, real_v3_sha_ok := fixture_schema.history_manifest_sha256_hex(real_v3_data, context.allocator)
    testing.expect(
        t,
        real_v3_sha_ok && real_v3_sha == "210c2d82c27ac668bcdae75f18c5735726f7d88ca48609a8795bdaec56225b9f",
    )
    if !real_v3_sha_ok do return
    defer delete(real_v3_sha)
    real_v3_generated, real_v3_generated_ok := fixture_schema.history_emit_package(
        &real_v3_manifest,
        real_v3_sha,
        context.allocator,
    )
    testing.expect(t, real_v3_generated_ok)
    if !real_v3_generated_ok do return
    defer delete(real_v3_generated)
    real_v3_expected, real_v3_expected_error := os.read_entire_file(
        "packages/fixture_history/v0003/schema.generated.odin",
        context.allocator,
    )
    testing.expect(t, real_v3_expected_error == nil)
    if real_v3_expected_error != nil do return
    defer delete(real_v3_expected)
    testing.expect(t, string(real_v3_expected) == real_v3_generated)
    real_v3_history_sha, real_v3_history_sha_ok := fixture_schema.history_manifest_sha256_hex(
        real_v3_expected,
        context.allocator,
    )
    testing.expect(
        t,
        real_v3_history_sha_ok &&
        real_v3_history_sha == "508e0c043c8886ff637132081f8fb27ec9b02a10a49142ec6dad1e0f20ba99bd",
    )
    if !real_v3_history_sha_ok do return
    defer delete(real_v3_history_sha)

    real_v4_data, real_v4_read_error := os.read_entire_file("fixtures/schema/v0004.fixture-schema", context.allocator)
    testing.expect(t, real_v4_read_error == nil)
    if real_v4_read_error != nil do return
    defer delete(real_v4_data)
    real_v4_manifest, real_v4_error, real_v4_ok := fixture_schema.history_parse_manifest(
        real_v4_data,
        context.allocator,
    )
    testing.expect(t, real_v4_ok && real_v4_error.kind == .None)
    if !real_v4_ok {
        fixture_schema.history_error_dispose(&real_v4_error)
        return
    }
    defer fixture_schema.history_manifest_dispose(&real_v4_manifest)
    testing.expect(t, real_v4_manifest.schema_version == 4 && len(real_v4_manifest.records) == 167)
    v4_root_fields := 0
    v4_occupant_found := false
    v4_occupant_enum_found := false
    v4_resident_action_seen_found := false
    for record in real_v4_manifest.records {
        if record.id == real_v4_manifest.root {
            v4_root_fields = len(record.fields)
            for field in record.fields {
                if field.name == "occupant" {
                    v4_occupant_found =
                        !field.is_using &&
                        field.tag == "" &&
                        field.type == "adriatic:packages/vehicles.Fixture_Occupant"
                }
            }
        }
        if record.id == "adriatic:packages/vehicles.Fixture_Occupant" {
            v4_occupant_enum_found =
                record.kind == "enum" &&
                record.detail == "using=0;base=builtin:u8" &&
                len(record.enums) == 6 &&
                record.enums[0].name == "On_Foot" &&
                record.enums[0].value == 0 &&
                record.enums[1].name == "Car" &&
                record.enums[1].value == 1 &&
                record.enums[2].name == "Postale" &&
                record.enums[2].value == 2 &&
                record.enums[3].name == "Libellula" &&
                record.enums[3].value == 3 &&
                record.enums[4].name == "Libellula_Mk2" &&
                record.enums[4].value == 4 &&
                record.enums[5].name == "Rondine" &&
                record.enums[5].value == 5
        }
        if record.id == "adriatic:packages/story.State" {
            for field in record.fields {
                if field.name == "resident_action_seen" {
                    v4_resident_action_seen_found =
                        field.type == "enumerated_array[11;adriatic:packages/story.Resident]<builtin:u64>"
                }
            }
        }
    }
    testing.expect(
        t,
        v4_root_fields == 154 && v4_occupant_found && v4_occupant_enum_found && v4_resident_action_seen_found,
    )
    real_v4_sha, real_v4_sha_ok := fixture_schema.history_manifest_sha256_hex(real_v4_data, context.allocator)
    testing.expect(
        t,
        real_v4_sha_ok && real_v4_sha == "fad52f4e0a38b35fffdf29ae3ffb3f91251780fe0ce2dc5990beba76f1e518fa",
    )
    if !real_v4_sha_ok do return
    defer delete(real_v4_sha)
    real_v4_generated, real_v4_generated_ok := fixture_schema.history_emit_package(
        &real_v4_manifest,
        real_v4_sha,
        context.allocator,
    )
    testing.expect(t, real_v4_generated_ok)
    if !real_v4_generated_ok do return
    defer delete(real_v4_generated)
    testing.expect(t, strings.contains(real_v4_generated, "resident_action_seen: [History_Type_0079]u64,"))
    real_v4_expected, real_v4_expected_error := os.read_entire_file(
        "packages/fixture_history/v0004/schema.generated.odin",
        context.allocator,
    )
    testing.expect(t, real_v4_expected_error == nil)
    if real_v4_expected_error != nil do return
    defer delete(real_v4_expected)
    testing.expect(t, string(real_v4_expected) == real_v4_generated)
    testing.expect(t, strings.count(string(real_v4_expected), "\n") == 2110)
    testing.expect(t, strings.count(string(real_v4_expected), "// fixture-history-id: ") == 167)
    real_v4_history_sha, real_v4_history_sha_ok := fixture_schema.history_manifest_sha256_hex(
        real_v4_expected,
        context.allocator,
    )
    testing.expect(
        t,
        real_v4_history_sha_ok &&
        real_v4_history_sha == "bc483f9afa929fd697868627ad8b0a7b46e03be61edb88670bc46825ec0a1076",
    )
    if !real_v4_history_sha_ok do return
    defer delete(real_v4_history_sha)
    resident_actions_info := type_info_of(typeid_of([fixture_v0004.History_Type_0079]u64))
    resident_actions, resident_actions_ok := resident_actions_info.variant.(runtime.Type_Info_Enumerated_Array)
    testing.expect(
        t,
        resident_actions_ok &&
        resident_actions.count == 11 &&
        resident_actions.elem.id == typeid_of(u64) &&
        resident_actions.index.id == typeid_of(fixture_v0004.History_Type_0079),
    )

    invalid_versions := [?]string{"0", "-1", "+1", "01", "1 ", "1x", "10000", "9223372036854775808"}
    for version in invalid_versions {
        invalid_source := history_replace(
            v2_source,
            "fixture_schema_version=2",
            fmt.tprintf("fixture_schema_version=%s", version),
        )
        history_expect_failure_kind(t, invalid_source, .Invalid_Input)
        delete(invalid_source)
    }

    _, nil_error, nil_ok := fixture_schema.history_parse_manifest(transmute([]byte)v2_source, mem.Allocator{})
    testing.expect(t, !nil_ok && nil_error.kind == .Out_Of_Memory)
    fixture_schema.history_error_dispose(&nil_error)
    fixture_schema.history_error_dispose(&nil_error)

    parse_success_state := Fixture_History_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    parse_allocator := fixture_history_fault_allocator(&parse_success_state)
    parsed, parse_error, parse_ok := fixture_schema.history_parse_manifest(transmute([]byte)v2_source, parse_allocator)
    testing.expect(t, parse_ok && parse_success_state.attempts > 0)
    fixture_schema.history_manifest_dispose(&parsed)
    fixture_schema.history_manifest_dispose(&parsed)
    fixture_schema.history_error_dispose(&parse_error)
    fixture_schema.history_error_dispose(&parse_error)
    testing.expect(t, parse_success_state.outstanding == 0)
    for fail_index in 0 ..< parse_success_state.attempts {
        state := Fixture_History_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_history_fault_allocator(&state)
        failed, failed_error, failed_ok := fixture_schema.history_parse_manifest(transmute([]byte)v2_source, allocator)
        testing.expect(t, !failed_ok && failed_error.kind == .Out_Of_Memory)
        fixture_schema.history_manifest_dispose(&failed)
        fixture_schema.history_manifest_dispose(&failed)
        fixture_schema.history_error_dispose(&failed_error)
        fixture_schema.history_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }

    emit_success_state := Fixture_History_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    emit_allocator := fixture_history_fault_allocator(&emit_success_state)
    emitted, emitted_ok := fixture_schema.history_emit_package(&v2_manifest, v2_sha, emit_allocator)
    testing.expect(t, emitted_ok && emitted == v2_generated && emit_success_state.attempts > 0)
    if emitted_ok do delete(emitted, emit_allocator)
    testing.expect(t, emit_success_state.outstanding == 0)
    for fail_index in 0 ..< emit_success_state.attempts {
        state := Fixture_History_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_history_fault_allocator(&state)
        failed, failed_ok := fixture_schema.history_emit_package(&v2_manifest, v2_sha, allocator)
        testing.expect(t, !failed_ok && len(failed) == 0)
        delete(failed, allocator)
        testing.expect(t, state.outstanding == 0)
    }
    _, nil_emit_ok := fixture_schema.history_emit_package(&v2_manifest, v2_sha, mem.Allocator{})
    testing.expect(t, !nil_emit_ok)
}
