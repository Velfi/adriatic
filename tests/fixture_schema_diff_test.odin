package tests

import fixture_schema "../packages/fixture_schema"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:testing"

DIFF_TEST_ROOT :: "adriatic:src.Fixture"
DIFF_TEST_OTHER :: "adriatic:src.Other"
DIFF_TEST_ENUM :: "adriatic:src.Mode"
DIFF_TEST_DETAIL :: "packed\\=0;raw_union\\=0;no_copy\\=0;all_or_none\\=0;simple\\=0;align\\=none;min_field_align\\=none;max_field_align\\=none"

DIFF_SWEEP_ROOT :: "adriatic:test.src.Root"
DIFF_SWEEP_FROZEN ::
    "format_version=1\n" +
    "fixture_schema_version=1\n" +
    "root=adriatic:test.src.Root\n" +
    "type=adriatic:test.src.Root|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n" +
    "field=adriatic:test.src.Root|name=embedded|using=1|tag=hello\\|world\\=ok\\\\path|type=adriatic:test.src.Embedded\n" +
    "field=adriatic:test.src.Root|name=grid|using=0|tag=|type=array[2]<array[2]<adriatic:test.src.Payload>>\n" +
    "field=adriatic:test.src.Root|name=payload|using=0|tag=|type=adriatic:test.src.Payload\n" +
    "field=adriatic:test.src.Root|name=alias_value|using=0|tag=|type=adriatic:test.src.Alias\n" +
    "field=adriatic:test.src.Root|name=distinct_value|using=0|tag=|type=adriatic:test.src.Distinct\n" +
    "field=adriatic:test.src.Root|name=mode|using=0|tag=|type=adriatic:test.src.Mode\n" +
    "field=adriatic:test.src.Root|name=tagged|using=0|tag=old\\|tag\\=x|type=builtin:i16\n" +
    "type=adriatic:test.src.Embedded|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n" +
    "field=adriatic:test.src.Embedded|name=inner|using=1|tag=embedded\\=tag|type=adriatic:test.src.Inner\n" +
    "type=adriatic:test.src.Inner|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n" +
    "field=adriatic:test.src.Inner|name=value|using=0|tag=|type=builtin:i32\n" +
    "field=adriatic:test.src.Inner|name=remove_me|using=0|tag=|type=adriatic:test.src.Removed\n" +
    "type=adriatic:test.src.Payload|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n" +
    "field=adriatic:test.src.Payload|name=data|using=0|tag=|type=array[2]<array[2]<builtin:u8>>\n" +
    "type=adriatic:test.src.Alias|kind=alias|detail=target\\=array[2]<adriatic:test.src.Payload>\n" +
    "type=adriatic:test.src.Distinct|kind=distinct|detail=target\\=builtin:i32\n" +
    "type=adriatic:test.src.Mode|kind=enum|detail=using\\=0;base\\=builtin:u8\n" +
    "enum=adriatic:test.src.Mode|name=Idle|value=0\n" +
    "enum=adriatic:test.src.Mode|name=Busy|value=1\n" +
    "type=adriatic:test.src.Removed|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n"

DIFF_SWEEP_CANDIDATE ::
    "format_version=1\n" +
    "fixture_schema_version=1\n" +
    "root=adriatic:test.src.Root\n" +
    "type=adriatic:test.src.Root|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n" +
    "field=adriatic:test.src.Root|name=embedded|using=1|tag=hello\\|world\\=ok\\\\path|type=adriatic:test.src.Embedded\n" +
    "field=adriatic:test.src.Root|name=grid|using=0|tag=|type=dynamic<array[2]<array[2]<adriatic:test.src.Payload>>>\n" +
    "field=adriatic:test.src.Root|name=payload|using=0|tag=|type=adriatic:test.src.Added\n" +
    "field=adriatic:test.src.Root|name=alias_value|using=0|tag=|type=adriatic:test.src.Alias\n" +
    "field=adriatic:test.src.Root|name=distinct_value|using=0|tag=|type=adriatic:test.src.Distinct\n" +
    "field=adriatic:test.src.Root|name=mode|using=0|tag=|type=adriatic:test.src.Mode\n" +
    "field=adriatic:test.src.Root|name=tagged|using=0|tag=new\\|tag\\=x|type=builtin:i16\n" +
    "field=adriatic:test.src.Root|name=new_field|using=0|tag=|type=builtin:u8\n" +
    "type=adriatic:test.src.Embedded|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n" +
    "field=adriatic:test.src.Embedded|name=inner|using=1|tag=embedded\\=tag|type=adriatic:test.src.Inner\n" +
    "type=adriatic:test.src.Inner|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n" +
    "field=adriatic:test.src.Inner|name=value|using=0|tag=|type=builtin:i32\n" +
    "type=adriatic:test.src.Payload|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n" +
    "field=adriatic:test.src.Payload|name=data|using=0|tag=|type=array[2]<array[2]<builtin:u8>>\n" +
    "type=adriatic:test.src.Alias|kind=alias|detail=target\\=array[2]<adriatic:test.src.Payload>\n" +
    "type=adriatic:test.src.Distinct|kind=distinct|detail=target\\=builtin:i32\n" +
    "type=adriatic:test.src.Mode|kind=enum|detail=using\\=0;base\\=builtin:u8\n" +
    "enum=adriatic:test.src.Mode|name=Idle|value=0\n" +
    "enum=adriatic:test.src.Mode|name=Busy|value=1\n" +
    "enum=adriatic:test.src.Mode|name=On|value=2\n" +
    "type=adriatic:test.src.Added|kind=struct|detail=" +
    DIFF_TEST_DETAIL +
    "\n" +
    "field=adriatic:test.src.Added|name=child|using=0|tag=child\\=text|type=builtin:i16\n" +
    "field=adriatic:test.src.Added|name=mode|using=0|tag=|type=adriatic:test.src.Mode\n"

Fixture_Schema_Diff_Fault_Allocator :: struct {
    backing:     mem.Allocator,
    attempts:    int,
    fail_index:  int,
    outstanding: int,
}

fixture_schema_diff_fault_allocator_proc :: proc(
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
    state := (^Fixture_Schema_Diff_Fault_Allocator)(data)
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

fixture_schema_diff_fault_allocator :: proc(state: ^Fixture_Schema_Diff_Fault_Allocator) -> mem.Allocator {
    return {procedure = fixture_schema_diff_fault_allocator_proc, data = rawptr(state)}
}

schema_diff_test_join :: proc(first, second: string) -> string {
    return fmt.tprintf("%s%s", first, second)
}

schema_diff_test_field :: proc(record, name, using_value, tag, type_name: string) -> string {
    return fmt.tprintf("field=%s|name=%s|using=%s|tag=%s|type=%s\n", record, name, using_value, tag, type_name)
}

schema_diff_test_struct :: proc(id, fields: string, detail := DIFF_TEST_DETAIL) -> string {
    return fmt.tprintf("type=%s|kind=struct|detail=%s\n%s", id, detail, fields)
}

schema_diff_test_enum :: proc(entries: string, id := DIFF_TEST_ENUM) -> string {
    return fmt.tprintf("type=%s|kind=enum|detail=using\\=0;base\\=builtin:u8\n%s", id, entries)
}

schema_diff_test_enum_entry :: proc(id, name, value: string) -> string {
    return fmt.tprintf("enum=%s|name=%s|value=%s\n", id, name, value)
}

schema_diff_test_common_records :: proc(fixture_fields, other_fields, mode_entries: string) -> string {
    first := schema_diff_test_struct(DIFF_TEST_ROOT, fixture_fields)
    second := schema_diff_test_struct(DIFF_TEST_OTHER, other_fields)
    third := schema_diff_test_enum(mode_entries)
    return schema_diff_test_join(schema_diff_test_join(first, second), third)
}

schema_diff_test_manifest :: proc(root, records: string, version := 1) -> string {
    return fmt.tprintf("format_version=1\nfixture_schema_version=%d\nroot=%s\n%s", version, root, records)
}

schema_diff_test_base_manifest :: proc(version := 1) -> string {
    fixture_fields := schema_diff_test_join(
        schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "", DIFF_TEST_OTHER),
        schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
    )
    other_fields := schema_diff_test_join(
        schema_diff_test_field(DIFF_TEST_OTHER, "number", "0", "", "builtin:u8"),
        schema_diff_test_field(DIFF_TEST_OTHER, "mode", "0", "", DIFF_TEST_ENUM),
    )
    mode_entries := schema_diff_test_join(
        schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Idle", "0"),
        schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Busy", "1"),
    )
    return schema_diff_test_manifest(
        DIFF_TEST_ROOT,
        schema_diff_test_common_records(fixture_fields, other_fields, mode_entries),
        version,
    )
}

schema_diff_test_report_for :: proc(
    t: ^testing.T,
    frozen, candidate: string,
    from_version := 1,
    to_version := 2,
) -> (
    fixture_schema.Schema_Diff_Report,
    bool,
) {
    report, error, ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)candidate,
        from_version,
        to_version,
        context.allocator,
    )
    testing.expect(t, ok)
    testing.expect(t, error.kind == .None)
    if !ok {
        fixture_schema.schema_diff_error_dispose(&error)
        return {}, false
    }
    return report, true
}

schema_diff_test_has_kind :: proc(
    report: ^fixture_schema.Schema_Diff_Report,
    kind: fixture_schema.Schema_Diff_Change_Kind,
) -> bool {
    for change in report.changes {
        if change.kind == kind do return true
    }
    return false
}

schema_diff_test_assert_top_level_report :: proc(t: ^testing.T, report: ^fixture_schema.Schema_Diff_Report) {
    expected_ids := [?]string {
        "enum-add:adriatic:test.src.Mode.On",
        "field-add:adriatic:test.src.Root.new_field",
        "field-remove:adriatic:test.src.Inner.remove_me",
        "field-tag:adriatic:test.src.Root.tagged",
        "field-type:adriatic:test.src.Root.grid",
        "field-type:adriatic:test.src.Root.payload",
        "type-add:adriatic:test.src.Added",
        "type-remove:adriatic:test.src.Removed",
    }
    testing.expect(t, len(report.changes) == len(expected_ids))
    expected := make(map[string]bool, context.allocator)
    for id in expected_ids do expected[id] = true
    state_count, supporting_count := fixture_schema.schema_diff_report_counts(report)
    testing.expect(t, state_count == 7 && supporting_count == 1)
    for change in report.changes {
        _, found := expected[change.id]
        testing.expect(t, found)
        if found do delete_key(&expected, change.id)
        if change.id == "type-add:adriatic:test.src.Added" {
            testing.expect(t, change.class == .Supporting && change.policy == .Automatic)
        } else {
            testing.expect(t, change.class == .State && change.policy == .Script_Required)
        }
        if change.id == "field-type:adriatic:test.src.Root.grid" {
            testing.expect(
                t,
                change.before == "array[2]<array[2]<adriatic:test.src.Payload>>" &&
                change.after == "dynamic<array[2]<array[2]<adriatic:test.src.Payload>>>",
            )
        }
        if change.id == "field-tag:adriatic:test.src.Root.tagged" {
            testing.expect(t, change.before == "old|tag=x" && change.after == "new|tag=x")
        }
    }
    testing.expect(t, len(expected) == 0)
}

fixture_schema_diff_v0002_to_v0003_frozen_report :: proc(
    t: ^testing.T,
) -> (
    report: fixture_schema.Schema_Diff_Report,
    ok: bool,
) {
    repo_root, root_error := os.get_working_directory(context.allocator)
    testing.expect(t, root_error == nil)
    if root_error != nil do return {}, false

    frozen, frozen_error := os.read_entire_file(fixture_schema.manifest_path(repo_root, 2), context.allocator)
    testing.expect(t, frozen_error == nil)
    if frozen_error != nil do return {}, false
    defer delete(frozen)

    candidate, candidate_error := os.read_entire_file(fixture_schema.manifest_path(repo_root, 3), context.allocator)
    testing.expect(t, candidate_error == nil)
    if candidate_error != nil do return {}, false
    defer delete(candidate)

    built_report, error, report_ok := fixture_schema.schema_diff_build_report(
        frozen,
        candidate,
        2,
        3,
        context.allocator,
    )
    testing.expect(t, report_ok && error.kind == .None)
    fixture_schema.schema_diff_error_dispose(&error)
    if !report_ok {
        fixture_schema.schema_diff_report_dispose(&built_report)
        return {}, false
    }
    return built_report, true
}

@(test)
fixture_schema_diff_v0002_to_v0003_frozen_is_exact :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := fixture_schema_diff_v0002_to_v0003_frozen_report(t)
    if !report_ok do return
    defer fixture_schema.schema_diff_report_dispose(&report)

    testing.expect(t, report.from_version == 2 && report.to_version == 3)
    testing.expect(t, len(report.changes) == 2)
    expected_ids := [?]string {
        "field-add:adriatic:src.Fixture.occupant",
        "type-add:adriatic:packages/vehicles.Fixture_Occupant",
    }
    expected := make(map[string]bool, context.allocator)
    for id in expected_ids do expected[id] = true
    for change in report.changes {
        _, found := expected[change.id]
        testing.expect(t, found)
        if found do delete_key(&expected, change.id)
        switch change.id {
        case "field-add:adriatic:src.Fixture.occupant":
            testing.expect(
                t,
                change.class == .State &&
                change.policy == .Script_Required &&
                change.after == "using=0;tag=;type=adriatic:packages/vehicles.Fixture_Occupant",
            )
        case "type-add:adriatic:packages/vehicles.Fixture_Occupant":
            testing.expect(t, change.class == .Supporting && change.policy == .Automatic)
            expected_enum :=
                "type=adriatic:packages/vehicles.Fixture_Occupant|kind=enum|detail=using=0;base=builtin:u8\n" +
                "enum=adriatic:packages/vehicles.Fixture_Occupant|name=On_Foot|value=0\n" +
                "enum=adriatic:packages/vehicles.Fixture_Occupant|name=Car|value=1\n" +
                "enum=adriatic:packages/vehicles.Fixture_Occupant|name=Postale|value=2\n" +
                "enum=adriatic:packages/vehicles.Fixture_Occupant|name=Libellula|value=3\n" +
                "enum=adriatic:packages/vehicles.Fixture_Occupant|name=Libellula_Mk2|value=4"
            testing.expect(t, strings.contains(change.after, expected_enum))
        }
    }
    testing.expect(t, len(expected) == 0)
    state_count, supporting_count := fixture_schema.schema_diff_report_counts(&report)
    testing.expect(t, state_count == 1 && supporting_count == 1)
    testing.expect(t, report.frozen_sha256 == "0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2")
    testing.expect(t, report.candidate_sha256 == "210c2d82c27ac668bcdae75f18c5735726f7d88ca48609a8795bdaec56225b9f")
    testing.expect(
        t,
        report.candidate_line_count == 1378 &&
        report.candidate_record_count == 150 &&
        report.candidate_root_fields == 146,
    )

    rendered, render_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
    testing.expect(t, render_ok && len(rendered) == 1236)
    if !render_ok do return
    defer delete(rendered)
    parsed, parse_error, parse_ok := fixture_schema.schema_diff_report_parse(
        transmute([]byte)rendered,
        context.allocator,
    )
    testing.expect(t, parse_ok && parse_error.kind == .None)
    fixture_schema.schema_diff_error_dispose(&parse_error)
    if !parse_ok {
        fixture_schema.schema_diff_report_dispose(&parsed)
        return
    }
    defer fixture_schema.schema_diff_report_dispose(&parsed)
    rendered_again, rendered_again_ok := fixture_schema.schema_diff_report_render(&parsed, context.allocator)
    testing.expect(t, rendered_again_ok && rendered_again == rendered)
    if rendered_again_ok do delete(rendered_again)
}

schema_diff_test_mode_entries :: proc(extra := "") -> string {
    idle := schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Idle", "0")
    busy := schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Busy", "1")
    return schema_diff_test_join(schema_diff_test_join(idle, busy), extra)
}

schema_diff_test_default_fields :: proc() -> (string, string) {
    fixture_fields := schema_diff_test_join(
        schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "", DIFF_TEST_OTHER),
        schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
    )
    other_fields := schema_diff_test_join(
        schema_diff_test_field(DIFF_TEST_OTHER, "number", "0", "", "builtin:u8"),
        schema_diff_test_field(DIFF_TEST_OTHER, "mode", "0", "", DIFF_TEST_ENUM),
    )
    return fixture_fields, other_fields
}

@(test)
fixture_schema_diff_synthetic_change_kinds :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    frozen := schema_diff_test_base_manifest()
    fixture_fields, other_fields := schema_diff_test_default_fields()
    mode_entries := schema_diff_test_mode_entries()
    candidates := [14]string {
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_join(
                schema_diff_test_common_records(
                    schema_diff_test_join(
                        schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "", "adriatic:src.New"),
                        schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
                    ),
                    other_fields,
                    mode_entries,
                ),
                schema_diff_test_struct("adriatic:src.New", ""),
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_struct(
                DIFF_TEST_ROOT,
                schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "", "builtin:int"),
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_join(
                schema_diff_test_struct(DIFF_TEST_ROOT, fixture_fields),
                "type=adriatic:src.Other|kind=distinct|detail=target\\=builtin:u8\n",
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_join(
                schema_diff_test_struct(DIFF_TEST_ROOT, fixture_fields),
                schema_diff_test_join(
                    schema_diff_test_struct(DIFF_TEST_OTHER, other_fields),
                    fmt.tprintf(
                        "type=%s|kind=enum|detail=using\\=0;base\\=builtin:u16\n%s",
                        DIFF_TEST_ENUM,
                        mode_entries,
                    ),
                ),
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_common_records(
                schema_diff_test_join(
                    fixture_fields,
                    schema_diff_test_field(DIFF_TEST_ROOT, "added", "0", "", "builtin:u8"),
                ),
                other_fields,
                mode_entries,
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_common_records(
                schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
                other_fields,
                mode_entries,
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_common_records(
                schema_diff_test_join(
                    schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "", "dynamic<" + DIFF_TEST_OTHER + ">"),
                    schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
                ),
                other_fields,
                mode_entries,
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_common_records(
                schema_diff_test_join(
                    schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "changed\\=tag", DIFF_TEST_OTHER),
                    schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
                ),
                other_fields,
                mode_entries,
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_common_records(
                schema_diff_test_join(
                    schema_diff_test_field(DIFF_TEST_ROOT, "value", "1", "", DIFF_TEST_OTHER),
                    schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
                ),
                other_fields,
                mode_entries,
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_common_records(
                schema_diff_test_join(
                    schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
                    schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "", DIFF_TEST_OTHER),
                ),
                other_fields,
                mode_entries,
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_common_records(
                fixture_fields,
                other_fields,
                schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Idle", "0"),
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_common_records(
                fixture_fields,
                other_fields,
                schema_diff_test_mode_entries(schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Done", "2")),
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_ROOT,
            schema_diff_test_common_records(
                fixture_fields,
                other_fields,
                schema_diff_test_join(
                    schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Idle", "0"),
                    schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Busy", "7"),
                ),
            ),
        ),
        schema_diff_test_manifest(
            DIFF_TEST_OTHER,
            schema_diff_test_join(
                schema_diff_test_struct(DIFF_TEST_OTHER, other_fields),
                schema_diff_test_enum(mode_entries),
            ),
        ),
    }
    expected_kinds := [14]fixture_schema.Schema_Diff_Change_Kind {
        .Type_Add,
        .Type_Remove,
        .Type_Kind,
        .Type_Detail,
        .Field_Add,
        .Field_Remove,
        .Field_Type,
        .Field_Tag,
        .Field_Using,
        .Field_Order,
        .Enum_Remove,
        .Enum_Add,
        .Enum_Value,
        .Root,
    }
    for index in 0 ..< len(candidates) {
        report, ok := schema_diff_test_report_for(t, frozen, candidates[index])
        if !ok do continue
        testing.expect(t, schema_diff_test_has_kind(&report, expected_kinds[index]))
        fixture_schema.schema_diff_report_dispose(&report)
    }
}

@(test)
fixture_schema_diff_production_is_exact_and_round_trips :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    repo_root, root_error := os.get_working_directory(context.allocator)
    testing.expect(t, root_error == nil)
    if root_error != nil do return
    frozen_path := fixture_schema.manifest_path(repo_root, 1)
    frozen, frozen_error := os.read_entire_file(frozen_path, context.allocator)
    testing.expect(t, frozen_error == nil)
    if frozen_error != nil do return
    defer delete(frozen)
    candidate_path := fixture_schema.manifest_path(repo_root, 2)
    candidate, candidate_error := os.read_entire_file(candidate_path, context.allocator)
    testing.expect(t, candidate_error == nil)
    if candidate_error != nil do return
    defer delete(candidate)
    report, error, diff_ok := fixture_schema.schema_diff_build_report(frozen, candidate, 1, 2, context.allocator)
    testing.expect(t, diff_ok && error.kind == .None)
    if !diff_ok {
        fixture_schema.schema_diff_error_dispose(&error)
        return
    }
    defer fixture_schema.schema_diff_report_dispose(&report)
    testing.expect(t, len(report.changes) == 21)
    expected_ids := [?]string {
        "field-type:adriatic:packages/architecture.City_Plan.structures",
        "field-type:adriatic:packages/architecture.City_Plan.parcels",
        "field-type:adriatic:packages/architecture.City_Plan.alleys",
        "field-type:adriatic:packages/architecture.City_Plan.lamps",
        "field-add:adriatic:packages/farmland.Plan.width",
        "field-add:adriatic:packages/farmland.Plan.height",
        "field-add:adriatic:packages/farmland.Plan.tradition",
        "field-type:adriatic:packages/terrain.Project.structures",
        "field-add:adriatic:src.Farm_Instance.scale_x",
        "field-add:adriatic:src.Farm_Instance.scale_z",
        "field-remove:adriatic:src.Settlement_Plan.city_plan",
        "field-add:adriatic:packages/story.State.quest",
        "field-add:adriatic:packages/story.State.airfield_errand",
        "field-add:adriatic:src.Fixture.tracked_quest_node",
        "field-add:adriatic:src.Fixture.quest_tracking_suppressed",
        "field-add:adriatic:src.Fixture.quest_tracking_revision",
        "type-add:adriatic:packages/farmland.Tradition",
        "type-add:adriatic:packages/quest.Node_ID",
        "type-add:adriatic:packages/quest.State",
        "type-add:adriatic:packages/quest.Status",
        "type-add:adriatic:packages/story.Airfield_Errand_Stage",
    }
    expected := make(map[string]bool, context.allocator)
    for id in expected_ids do expected[id] = true
    state_count, supporting_count := fixture_schema.schema_diff_report_counts(&report)
    testing.expect(t, state_count == 16 && supporting_count == 5)
    for change in report.changes {
        _, found := expected[change.id]
        testing.expect(t, found)
        if found do delete_key(&expected, change.id)
        testing.expect(
            t,
            change.class == .Supporting ? change.policy == .Automatic : change.policy == .Script_Required,
        )
    }
    testing.expect(t, len(expected) == 0)
    rendered, render_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
    testing.expect(t, render_ok)
    if !render_ok do return
    defer delete(rendered)
    parsed, parse_error, parse_ok := fixture_schema.schema_diff_report_parse(
        transmute([]byte)rendered,
        context.allocator,
    )
    testing.expect(t, parse_ok && parse_error.kind == .None)
    if !parse_ok {
        fixture_schema.schema_diff_error_dispose(&parse_error)
        return
    }
    defer fixture_schema.schema_diff_report_dispose(&parsed)
    rendered_again, rendered_again_ok := fixture_schema.schema_diff_report_render(&parsed, context.allocator)
    testing.expect(t, rendered_again_ok && rendered_again == rendered)
    if rendered_again_ok do delete(rendered_again)
    testing.expect(t, report.frozen_sha256 == "2f29187e4a2587e9c6319e953a9801232d67cdaefb308435f74b2cc53a4abd12")
    testing.expect(t, report.candidate_sha256 == "0ea3c776f7eb17745ea7db78a929c48cf2b35daf439f56047908ec5e22c01ff2")
    testing.expect(
        t,
        report.candidate_line_count == 1371 &&
        report.candidate_record_count == 149 &&
        report.candidate_root_fields == 145,
    )
}

@(test)
fixture_schema_diff_ignores_version_and_record_enum_order :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    frozen := schema_diff_test_base_manifest()
    fixture_fields, other_fields := schema_diff_test_default_fields()
    mode_entries := schema_diff_test_join(
        schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Busy", "1"),
        schema_diff_test_enum_entry(DIFF_TEST_ENUM, "Idle", "0"),
    )
    first := schema_diff_test_struct(DIFF_TEST_OTHER, other_fields)
    second := schema_diff_test_struct(DIFF_TEST_ROOT, fixture_fields)
    candidate := schema_diff_test_manifest(
        DIFF_TEST_ROOT,
        schema_diff_test_join(schema_diff_test_join(schema_diff_test_enum(mode_entries), first), second),
        2,
    )
    report, ok := schema_diff_test_report_for(t, frozen, candidate)
    if !ok do return
    testing.expect(t, len(report.changes) == 0)
    fixture_schema.schema_diff_report_dispose(&report)
}

@(test)
fixture_schema_diff_rejects_hostile_inputs_and_version_pairs :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    frozen := schema_diff_test_base_manifest()
    bad_header, _ := strings.replace_all(frozen, "format_version=1", "format_version=2", context.allocator)
    duplicate := schema_diff_test_join(frozen, schema_diff_test_struct(DIFF_TEST_OTHER, ""))
    unresolved := schema_diff_test_manifest(
        DIFF_TEST_ROOT,
        schema_diff_test_struct(
            DIFF_TEST_ROOT,
            schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "", "adriatic:src.Missing"),
        ),
    )
    unreachable := schema_diff_test_manifest(
        DIFF_TEST_ROOT,
        schema_diff_test_join(
            schema_diff_test_struct(
                DIFF_TEST_ROOT,
                schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "", "builtin:int"),
            ),
            schema_diff_test_join(
                schema_diff_test_struct(DIFF_TEST_OTHER, ""),
                schema_diff_test_enum(schema_diff_test_mode_entries()),
            ),
        ),
    )
    cyclic := schema_diff_test_manifest(
        DIFF_TEST_ROOT,
        schema_diff_test_struct(
            DIFF_TEST_ROOT,
            schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "", DIFF_TEST_ROOT),
        ),
    )
    invalid_inputs := [?]string{bad_header, duplicate, unresolved, unreachable, cyclic}
    for invalid in invalid_inputs {
        report, error, ok := fixture_schema.schema_diff_build_report(
            transmute([]byte)frozen,
            transmute([]byte)invalid,
            1,
            2,
            context.allocator,
        )
        testing.expect(t, !ok && error.kind != .None)
        if ok do fixture_schema.schema_diff_report_dispose(&report)
        fixture_schema.schema_diff_error_dispose(&error)
    }
    _, error, ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)frozen,
        1,
        3,
        context.allocator,
    )
    testing.expect(t, !ok && error.kind == .Invalid_Input)
    fixture_schema.schema_diff_error_dispose(&error)
    nil_allocator := mem.Allocator{}
    _, error, ok = fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)frozen,
        1,
        2,
        nil_allocator,
    )
    testing.expect(t, !ok)
    fixture_schema.schema_diff_error_dispose(&error)
    _, error, ok = fixture_schema.schema_diff_parse_candidate_snapshot(transmute([]byte)frozen, nil_allocator)
    testing.expect(t, !ok && error.kind == .Out_Of_Memory)
    fixture_schema.schema_diff_error_dispose(&error)
    _, error, ok = fixture_schema.schema_diff_parse_frozen_snapshot(transmute([]byte)frozen, nil_allocator)
    testing.expect(t, !ok && error.kind == .Out_Of_Memory)
    fixture_schema.schema_diff_error_dispose(&error)
}

@(test)
fixture_schema_diff_report_rejects_duplicate_and_bad_escape :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    frozen := schema_diff_test_base_manifest()
    fixture_fields, other_fields := schema_diff_test_default_fields()
    candidate_fields := schema_diff_test_join(
        schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "changed\\=tag", DIFF_TEST_OTHER),
        schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
    )
    candidate := schema_diff_test_manifest(
        DIFF_TEST_ROOT,
        schema_diff_test_common_records(candidate_fields, other_fields, schema_diff_test_mode_entries()),
    )
    report, ok := schema_diff_test_report_for(t, frozen, candidate)
    if !ok do return
    rendered, rendered_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
    testing.expect(t, rendered_ok)
    if rendered_ok {
        first := strings.index(rendered, "change=")
        duplicate := schema_diff_test_join(rendered, rendered[first:])
        _, parse_error, parse_ok := fixture_schema.schema_diff_report_parse(
            transmute([]byte)duplicate,
            context.allocator,
        )
        testing.expect(t, !parse_ok)
        fixture_schema.schema_diff_error_dispose(&parse_error)
        bad_escape, _ := strings.replace_all(rendered, "changed\\=tag", "changed\\qtag", context.allocator)
        _, parse_error, parse_ok = fixture_schema.schema_diff_report_parse(
            transmute([]byte)bad_escape,
            context.allocator,
        )
        testing.expect(t, !parse_ok && parse_error.kind == .Invalid_Input)
        fixture_schema.schema_diff_error_dispose(&parse_error)
        delete(duplicate)
        delete(bad_escape)
        delete(rendered)
    }
    fixture_schema.schema_diff_report_dispose(&report)
}

@(test)
fixture_schema_diff_candidate_parser_allocation_failures :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    candidate := schema_diff_test_base_manifest()
    success_state := Fixture_Schema_Diff_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_schema_diff_fault_allocator(&success_state)
    snapshot, error, ok := fixture_schema.schema_diff_parse_candidate_snapshot(
        transmute([]byte)candidate,
        success_allocator,
    )
    testing.expect(t, ok && error.kind == .None)
    if ok do fixture_schema.schema_diff_snapshot_dispose(&snapshot)
    fixture_schema.schema_diff_snapshot_dispose(&snapshot)
    fixture_schema.schema_diff_error_dispose(&error)
    fixture_schema.schema_diff_error_dispose(&error)
    testing.expect(t, success_state.attempts > 0)
    testing.expect(t, success_state.outstanding == 0)

    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_Schema_Diff_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_schema_diff_fault_allocator(&state)
        failed_snapshot, failed_error, failed_ok := fixture_schema.schema_diff_parse_candidate_snapshot(
            transmute([]byte)candidate,
            allocator,
        )
        testing.expect(t, !failed_ok)
        testing.expect(t, failed_error.kind == .Out_Of_Memory)
        fixture_schema.schema_diff_snapshot_dispose(&failed_snapshot)
        fixture_schema.schema_diff_snapshot_dispose(&failed_snapshot)
        fixture_schema.schema_diff_error_dispose(&failed_error)
        fixture_schema.schema_diff_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }
}

@(test)
fixture_schema_diff_report_parser_allocation_failures_and_discriminants :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    frozen := schema_diff_test_base_manifest()
    _, other_fields := schema_diff_test_default_fields()
    candidate := schema_diff_test_manifest(
        DIFF_TEST_ROOT,
        schema_diff_test_common_records(
            schema_diff_test_join(
                schema_diff_test_field(DIFF_TEST_ROOT, "value", "0", "changed\\=tag", DIFF_TEST_OTHER),
                schema_diff_test_field(DIFF_TEST_ROOT, "keep", "0", "", DIFF_TEST_OTHER),
            ),
            other_fields,
            schema_diff_test_mode_entries(),
        ),
    )
    report, report_ok := schema_diff_test_report_for(t, frozen, candidate)
    if !report_ok do return
    rendered, rendered_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
    testing.expect(t, rendered_ok)
    if !rendered_ok {
        fixture_schema.schema_diff_report_dispose(&report)
        return
    }

    success_state := Fixture_Schema_Diff_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_schema_diff_fault_allocator(&success_state)
    parsed, error, ok := fixture_schema.schema_diff_report_parse(transmute([]byte)rendered, success_allocator)
    testing.expect(t, ok && error.kind == .None)
    if ok do fixture_schema.schema_diff_report_dispose(&parsed)
    fixture_schema.schema_diff_report_dispose(&parsed)
    fixture_schema.schema_diff_error_dispose(&error)
    fixture_schema.schema_diff_error_dispose(&error)
    testing.expect(t, success_state.attempts > 0)
    testing.expect(t, success_state.outstanding == 0)

    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_Schema_Diff_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_schema_diff_fault_allocator(&state)
        failed_report, failed_error, failed_ok := fixture_schema.schema_diff_report_parse(
            transmute([]byte)rendered,
            allocator,
        )
        testing.expect(t, !failed_ok)
        testing.expect(t, failed_error.kind == .Out_Of_Memory)
        fixture_schema.schema_diff_report_dispose(&failed_report)
        fixture_schema.schema_diff_report_dispose(&failed_report)
        fixture_schema.schema_diff_error_dispose(&failed_error)
        fixture_schema.schema_diff_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }

    for discriminant_index in 0 ..< 3 {
        forged, forged_ok := schema_diff_test_report_for(t, frozen, candidate)
        if !forged_ok do continue
        switch discriminant_index {
        case 0:
            forged.changes[0].kind = fixture_schema.Schema_Diff_Change_Kind(99)
        case 1:
            forged.changes[0].class = fixture_schema.Schema_Diff_Class(99)
        case 2:
            forged.changes[0].policy = fixture_schema.Schema_Diff_Policy(99)
        }
        forged_error: fixture_schema.Schema_Diff_Error
        valid := fixture_schema.schema_diff_report_validate(&forged, &forged_error)
        testing.expect(t, !valid && forged_error.kind == .Invalid_Input)
        rejected_render, rejected_render_ok := fixture_schema.schema_diff_report_render(&forged, context.allocator)
        testing.expect(t, !rejected_render_ok)
        if rejected_render_ok do delete(rejected_render)
        fixture_schema.schema_diff_error_dispose(&forged_error)
        fixture_schema.schema_diff_report_dispose(&forged)
    }
    delete(rendered)
    fixture_schema.schema_diff_report_dispose(&report)
}

@(test)
fixture_schema_diff_custom_limits_and_array_crossings :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    base := schema_diff_test_base_manifest()
    dynamic_manifest, dynamic_ok := strings.replace_all(
        base,
        "|type=adriatic:src.Other",
        "|type=dynamic<adriatic:src.Other>",
        context.allocator,
    )
    testing.expect(t, dynamic_ok)
    if !dynamic_ok do return
    fixed, fixed_ok := strings.replace_all(
        base,
        "|type=adriatic:src.Other",
        "|type=array[4]<adriatic:src.Other>",
        context.allocator,
    )
    testing.expect(t, fixed_ok)
    if !fixed_ok do return

    dynamic_snapshot, dynamic_error, dynamic_parse_ok := fixture_schema.schema_diff_parse_candidate_snapshot(
        transmute([]byte)dynamic_manifest,
        context.allocator,
    )
    testing.expect(t, dynamic_parse_ok && dynamic_error.kind == .None)
    if dynamic_parse_ok do fixture_schema.schema_diff_snapshot_dispose(&dynamic_snapshot)
    fixture_schema.schema_diff_error_dispose(&dynamic_error)

    fixed_snapshot, fixed_error, fixed_parse_ok := fixture_schema.schema_diff_parse_candidate_snapshot(
        transmute([]byte)fixed,
        context.allocator,
    )
    testing.expect(t, fixed_parse_ok && fixed_error.kind == .None)
    if fixed_parse_ok do fixture_schema.schema_diff_snapshot_dispose(&fixed_snapshot)
    fixture_schema.schema_diff_error_dispose(&fixed_error)

    limits := fixture_schema.SCHEMA_DIFF_DEFAULT_LIMITS
    limits.max_type_depth = 0
    _, error, ok := fixture_schema.schema_diff_parse_candidate_snapshot(
        transmute([]byte)dynamic_manifest,
        context.allocator,
        limits,
    )
    testing.expect(t, !ok && error.kind == .Unresolved_Reference)
    fixture_schema.schema_diff_error_dispose(&error)

    limits = fixture_schema.SCHEMA_DIFF_DEFAULT_LIMITS
    limits.max_array_length = 3
    _, error, ok = fixture_schema.schema_diff_parse_candidate_snapshot(
        transmute([]byte)fixed,
        context.allocator,
        limits,
    )
    testing.expect(t, !ok && error.kind == .Unresolved_Reference)
    fixture_schema.schema_diff_error_dispose(&error)
}

@(test)
fixture_schema_diff_top_level_allocation_failures :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    frozen := string(DIFF_SWEEP_FROZEN)
    candidate := string(DIFF_SWEEP_CANDIDATE)
    frozen_before := frozen
    candidate_before := candidate
    success_state := Fixture_Schema_Diff_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_schema_diff_fault_allocator(&success_state)
    report, error, ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)candidate,
        1,
        2,
        success_allocator,
    )
    testing.expect(t, ok && error.kind == .None)
    if ok do schema_diff_test_assert_top_level_report(t, &report)
    testing.expect(t, success_state.attempts > 0)
    testing.expect(t, frozen == frozen_before && candidate == candidate_before)
    fixture_schema.schema_diff_report_dispose(&report)
    fixture_schema.schema_diff_report_dispose(&report)
    fixture_schema.schema_diff_error_dispose(&error)
    fixture_schema.schema_diff_error_dispose(&error)
    testing.expect(t, success_state.outstanding == 0)

    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_Schema_Diff_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_schema_diff_fault_allocator(&state)
        failed_report, failed_error, failed_ok := fixture_schema.schema_diff_build_report(
            transmute([]byte)frozen,
            transmute([]byte)candidate,
            1,
            2,
            allocator,
        )
        testing.expect(t, !failed_ok)
        testing.expect(t, failed_error.kind == .Out_Of_Memory)
        testing.expect(t, frozen == frozen_before && candidate == candidate_before)
        fixture_schema.schema_diff_report_dispose(&failed_report)
        fixture_schema.schema_diff_report_dispose(&failed_report)
        fixture_schema.schema_diff_error_dispose(&failed_error)
        fixture_schema.schema_diff_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }

    nil_report, nil_error, nil_ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)candidate,
        1,
        2,
        mem.Allocator{},
    )
    testing.expect(t, !nil_ok && nil_error.kind == .Out_Of_Memory)
    fixture_schema.schema_diff_report_dispose(&nil_report)
    fixture_schema.schema_diff_report_dispose(&nil_report)
    fixture_schema.schema_diff_error_dispose(&nil_error)
    fixture_schema.schema_diff_error_dispose(&nil_error)
}

@(test)
fixture_schema_diff_top_level_render_allocation_failures :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()
    report, report_ok := schema_diff_test_report_for(t, string(DIFF_SWEEP_FROZEN), string(DIFF_SWEEP_CANDIDATE))
    if !report_ok do return
    baseline, baseline_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
    testing.expect(t, baseline_ok)
    if !baseline_ok {
        fixture_schema.schema_diff_report_dispose(&report)
        return
    }

    success_state := Fixture_Schema_Diff_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_schema_diff_fault_allocator(&success_state)
    rendered, rendered_ok := fixture_schema.schema_diff_report_render(&report, success_allocator)
    testing.expect(t, rendered_ok && rendered == baseline)
    testing.expect(t, success_state.attempts > 0)
    if rendered_ok do delete(rendered, success_allocator)
    testing.expect(t, success_state.outstanding == 0)

    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_Schema_Diff_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_schema_diff_fault_allocator(&state)
        failed, failed_ok := fixture_schema.schema_diff_report_render(&report, allocator)
        testing.expect(t, !failed_ok && len(failed) == 0)
        delete(failed, allocator)
        testing.expect(t, state.outstanding == 0)
    }

    nil_render, nil_render_ok := fixture_schema.schema_diff_report_render(&report, mem.Allocator{})
    testing.expect(t, !nil_render_ok && len(nil_render) == 0)
    delete(baseline)
    fixture_schema.schema_diff_report_dispose(&report)
    fixture_schema.schema_diff_report_dispose(&report)
}

@(test)
fixture_schema_diff_supports_contiguous_later_versions :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

    frozen := schema_diff_test_base_manifest(2)
    fixture_fields, other_fields := schema_diff_test_default_fields()
    candidate_fields := schema_diff_test_join(
        fixture_fields,
        schema_diff_test_field(DIFF_TEST_ROOT, "later", "0", "", "builtin:u16"),
    )
    candidate := schema_diff_test_manifest(
        DIFF_TEST_ROOT,
        schema_diff_test_common_records(candidate_fields, other_fields, schema_diff_test_mode_entries()),
        3,
    )
    frozen_before := frozen
    candidate_before := candidate

    report, error, ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)candidate,
        2,
        3,
        context.allocator,
    )
    testing.expect(t, ok && error.kind == .None)
    if !ok {
        fixture_schema.schema_diff_error_dispose(&error)
        return
    }
    defer fixture_schema.schema_diff_report_dispose(&report)
    testing.expect(t, report.from_version == 2 && report.to_version == 3)
    testing.expect(t, len(report.changes) == 1)
    if len(report.changes) == 1 {
        testing.expect(t, report.changes[0].id == "field-add:adriatic:src.Fixture.later")
        testing.expect(t, report.changes[0].after == "using=0;tag=;type=builtin:u16")
    }
    rendered, rendered_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
    testing.expect(t, rendered_ok)
    if rendered_ok {
        defer delete(rendered)
        second_rendered, second_rendered_ok := fixture_schema.schema_diff_report_render(&report, context.allocator)
        testing.expect(t, second_rendered_ok && second_rendered == rendered)
        if second_rendered_ok do delete(second_rendered)
    }
    fixture_schema.schema_diff_error_dispose(&error)
    fixture_schema.schema_diff_error_dispose(&error)
    testing.expect(t, frozen == frozen_before && candidate == candidate_before)

    zero_candidate := schema_diff_test_base_manifest(2)
    zero_report, zero_error, zero_ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)zero_candidate,
        2,
        3,
        context.allocator,
    )
    testing.expect(t, zero_ok && zero_error.kind == .None && len(zero_report.changes) == 0)
    fixture_schema.schema_diff_report_dispose(&zero_report)
    fixture_schema.schema_diff_error_dispose(&zero_error)
    delete(zero_candidate)

    frozen_mismatch := schema_diff_test_base_manifest(1)
    _, mismatch_error, mismatch_ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen_mismatch,
        transmute([]byte)candidate,
        2,
        3,
        context.allocator,
    )
    testing.expect(t, !mismatch_ok && mismatch_error.kind == .Invalid_Input)
    fixture_schema.schema_diff_error_dispose(&mismatch_error)
    delete(frozen_mismatch)

    candidate_outside := schema_diff_test_base_manifest(4)
    _, outside_error, outside_ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)candidate_outside,
        2,
        3,
        context.allocator,
    )
    testing.expect(t, !outside_ok && outside_error.kind == .Invalid_Input)
    fixture_schema.schema_diff_error_dispose(&outside_error)
    delete(candidate_outside)

    _, noncontiguous_error, noncontiguous_ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)candidate,
        2,
        4,
        context.allocator,
    )
    testing.expect(t, !noncontiguous_ok && noncontiguous_error.kind == .Invalid_Input)
    fixture_schema.schema_diff_error_dispose(&noncontiguous_error)

    _, nil_error, nil_ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)candidate,
        2,
        3,
        mem.Allocator{},
    )
    testing.expect(t, !nil_ok && nil_error.kind == .Out_Of_Memory)
    fixture_schema.schema_diff_error_dispose(&nil_error)
    fixture_schema.schema_diff_error_dispose(&nil_error)

    success_state := Fixture_Schema_Diff_Fault_Allocator {
        backing    = runtime.default_allocator(),
        fail_index = -1,
    }
    success_allocator := fixture_schema_diff_fault_allocator(&success_state)
    swept_report, swept_error, swept_ok := fixture_schema.schema_diff_build_report(
        transmute([]byte)frozen,
        transmute([]byte)candidate,
        2,
        3,
        success_allocator,
    )
    testing.expect(t, swept_ok && swept_error.kind == .None && success_state.attempts > 0)
    fixture_schema.schema_diff_report_dispose(&swept_report)
    fixture_schema.schema_diff_report_dispose(&swept_report)
    fixture_schema.schema_diff_error_dispose(&swept_error)
    fixture_schema.schema_diff_error_dispose(&swept_error)
    testing.expect(t, success_state.outstanding == 0)
    for fail_index in 0 ..< success_state.attempts {
        state := Fixture_Schema_Diff_Fault_Allocator {
            backing    = runtime.default_allocator(),
            fail_index = fail_index,
        }
        allocator := fixture_schema_diff_fault_allocator(&state)
        failed_report, failed_error, failed_ok := fixture_schema.schema_diff_build_report(
            transmute([]byte)frozen,
            transmute([]byte)candidate,
            2,
            3,
            allocator,
        )
        testing.expect(t, !failed_ok && failed_error.kind == .Out_Of_Memory)
        fixture_schema.schema_diff_report_dispose(&failed_report)
        fixture_schema.schema_diff_report_dispose(&failed_report)
        fixture_schema.schema_diff_error_dispose(&failed_error)
        fixture_schema.schema_diff_error_dispose(&failed_error)
        testing.expect(t, state.outstanding == 0)
    }
}
