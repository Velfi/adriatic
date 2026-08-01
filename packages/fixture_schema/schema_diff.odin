package fixture_schema

import "core:fmt"
import "core:mem"
import "core:strconv"
import "core:strings"

SCHEMA_DIFF_FORMAT_VERSION :: 1
SCHEMA_DIFF_MAX_BYTES :: 8 * 1024 * 1024
SCHEMA_DIFF_MAX_LINES :: 16384
SCHEMA_DIFF_MAX_RECORDS :: 1024
SCHEMA_DIFF_MAX_FIELDS :: 131072
SCHEMA_DIFF_MAX_ENUMS :: 131072
SCHEMA_DIFF_MAX_IDENTIFIER_BYTES :: 256
SCHEMA_DIFF_MAX_TYPE_DEPTH :: 64
SCHEMA_DIFF_MAX_ARRAY_LENGTH :: 16 * 1024 * 1024

Schema_Diff_Limits :: struct {
    max_bytes:        int,
    max_lines:        int,
    max_records:      int,
    max_fields:       int,
    max_enums:        int,
    max_identifier:   int,
    max_type_depth:   int,
    max_array_length: int,
}

SCHEMA_DIFF_DEFAULT_LIMITS :: Schema_Diff_Limits {
    max_bytes        = SCHEMA_DIFF_MAX_BYTES,
    max_lines        = SCHEMA_DIFF_MAX_LINES,
    max_records      = SCHEMA_DIFF_MAX_RECORDS,
    max_fields       = SCHEMA_DIFF_MAX_FIELDS,
    max_enums        = SCHEMA_DIFF_MAX_ENUMS,
    max_identifier   = SCHEMA_DIFF_MAX_IDENTIFIER_BYTES,
    max_type_depth   = SCHEMA_DIFF_MAX_TYPE_DEPTH,
    max_array_length = SCHEMA_DIFF_MAX_ARRAY_LENGTH,
}

Schema_Diff_Error_Kind :: enum {
    None,
    Invalid_Input,
    Limit_Exceeded,
    Out_Of_Memory,
    Unresolved_Reference,
    Unreachable_Record,
}

Schema_Diff_Error :: struct {
    kind:          Schema_Diff_Error_Kind,
    line:          int,
    path:          string,
    message:       string,
    path_owned:    bool,
    message_owned: bool,
    allocator:     mem.Allocator,
}

Schema_Diff_Field :: struct {
    name:     string,
    tag:      string,
    type:     string,
    is_using: bool,
    line:     int,
}

Schema_Diff_Enum :: struct {
    name:  string,
    value: i64,
    line:  int,
}

Schema_Diff_Record :: struct {
    id:     string,
    kind:   string,
    detail: string,
    line:   int,
    fields: [dynamic]Schema_Diff_Field,
    enums:  [dynamic]Schema_Diff_Enum,
}

Schema_Diff_Snapshot :: struct {
    allocator:      mem.Allocator,
    format_version: int,
    schema_version: int,
    root:           string,
    records:        [dynamic]Schema_Diff_Record,
}

Schema_Diff_Change_Kind :: enum {
    Type_Add,
    Type_Remove,
    Type_Kind,
    Type_Detail,
    Field_Add,
    Field_Remove,
    Field_Type,
    Field_Tag,
    Field_Using,
    Field_Order,
    Enum_Add,
    Enum_Remove,
    Enum_Value,
    Root,
}

Schema_Diff_Class :: enum {
    Supporting,
    State,
}

Schema_Diff_Policy :: enum {
    Automatic,
    Script_Required,
}

Schema_Diff_Change :: struct {
    id:     string,
    kind:   Schema_Diff_Change_Kind,
    class:  Schema_Diff_Class,
    policy: Schema_Diff_Policy,
    path:   string,
    before: string,
    after:  string,
}

Schema_Diff_Report :: struct {
    allocator:              mem.Allocator,
    format_version:         int,
    from_version:           int,
    to_version:             int,
    frozen_sha256:          string,
    candidate_sha256:       string,
    candidate_line_count:   int,
    candidate_record_count: int,
    candidate_root_fields:  int,
    changes:                [dynamic]Schema_Diff_Change,
}

schema_diff_error_dispose :: proc(error: ^Schema_Diff_Error) {
    if error == nil do return
    if error.path_owned do delete(error.path, error.allocator)
    if error.message_owned do delete(error.message, error.allocator)
    error^ = {}
}

schema_diff_record_dispose :: proc(record: ^Schema_Diff_Record, allocator: mem.Allocator) {
    if record == nil do return
    delete(record.id, allocator)
    delete(record.kind, allocator)
    delete(record.detail, allocator)
    for &field in record.fields {
        delete(field.name, allocator)
        delete(field.tag, allocator)
        delete(field.type, allocator)
    }
    for &entry in record.enums {
        delete(entry.name, allocator)
    }
    delete(record.fields)
    delete(record.enums)
    record^ = {}
}

schema_diff_snapshot_dispose :: proc(snapshot: ^Schema_Diff_Snapshot) {
    if snapshot == nil do return
    for &record in snapshot.records {
        schema_diff_record_dispose(&record, snapshot.allocator)
    }
    delete(snapshot.records)
    delete(snapshot.root, snapshot.allocator)
    snapshot^ = {}
}

schema_diff_change_dispose :: proc(change: ^Schema_Diff_Change, allocator: mem.Allocator) {
    if change == nil do return
    delete(change.id, allocator)
    delete(change.path, allocator)
    delete(change.before, allocator)
    delete(change.after, allocator)
    change^ = {}
}

schema_diff_report_dispose :: proc(report: ^Schema_Diff_Report) {
    if report == nil do return
    delete(report.frozen_sha256, report.allocator)
    delete(report.candidate_sha256, report.allocator)
    for &change in report.changes {
        schema_diff_change_dispose(&change, report.allocator)
    }
    delete(report.changes)
    report^ = {}
}

schema_diff_make_error :: proc(
    kind: Schema_Diff_Error_Kind,
    line: int,
    path, message: string,
    allocator: mem.Allocator,
) -> Schema_Diff_Error {
    error := Schema_Diff_Error {
        kind      = kind,
        line      = line,
        path      = "$",
        message   = message,
        allocator = allocator,
    }
    if owned, err := strings.clone(path, allocator); err == nil {
        error.path = owned
        error.path_owned = true
    }
    if owned, err := strings.clone(message, allocator); err == nil {
        error.message = owned
        error.message_owned = true
    }
    return error
}

schema_diff_fail :: proc(
    error: ^Schema_Diff_Error,
    kind: Schema_Diff_Error_Kind,
    line: int,
    path, message: string,
    allocator: mem.Allocator,
) {
    if error.kind == .None {
        error^ = schema_diff_make_error(kind, line, path, message, allocator)
    }
}

schema_diff_fail_if_none :: proc(
    error: ^Schema_Diff_Error,
    kind: Schema_Diff_Error_Kind,
    line: int,
    path, message: string,
    allocator: mem.Allocator,
) {
    if error != nil && error.kind == .None do schema_diff_fail(error, kind, line, path, message, allocator)
}

schema_diff_kind_text :: proc(kind: Schema_Diff_Change_Kind) -> string {
    switch kind {
    case .Type_Add:
        return "type-add"
    case .Type_Remove:
        return "type-remove"
    case .Type_Kind:
        return "type-kind"
    case .Type_Detail:
        return "type-detail"
    case .Field_Add:
        return "field-add"
    case .Field_Remove:
        return "field-remove"
    case .Field_Type:
        return "field-type"
    case .Field_Tag:
        return "field-tag"
    case .Field_Using:
        return "field-using"
    case .Field_Order:
        return "field-order"
    case .Enum_Add:
        return "enum-add"
    case .Enum_Remove:
        return "enum-remove"
    case .Enum_Value:
        return "enum-value"
    case .Root:
        return "root"
    }
    return ""
}

schema_diff_kind_valid :: proc(kind: Schema_Diff_Change_Kind) -> bool {
    switch kind {
    case .Type_Add,
         .Type_Remove,
         .Type_Kind,
         .Type_Detail,
         .Field_Add,
         .Field_Remove,
         .Field_Type,
         .Field_Tag,
         .Field_Using,
         .Field_Order,
         .Enum_Add,
         .Enum_Remove,
         .Enum_Value,
         .Root:
        return true
    }
    return false
}

schema_diff_kind_from_text :: proc(text: string) -> (Schema_Diff_Change_Kind, bool) {
    switch text {
    case "type-add":
        return .Type_Add, true
    case "type-remove":
        return .Type_Remove, true
    case "type-kind":
        return .Type_Kind, true
    case "type-detail":
        return .Type_Detail, true
    case "field-add":
        return .Field_Add, true
    case "field-remove":
        return .Field_Remove, true
    case "field-type":
        return .Field_Type, true
    case "field-tag":
        return .Field_Tag, true
    case "field-using":
        return .Field_Using, true
    case "field-order":
        return .Field_Order, true
    case "enum-add":
        return .Enum_Add, true
    case "enum-remove":
        return .Enum_Remove, true
    case "enum-value":
        return .Enum_Value, true
    case "root":
        return .Root, true
    }
    return .Type_Add, false
}

schema_diff_class_text :: proc(class: Schema_Diff_Class) -> string {
    switch class {
    case .Supporting:
        return "supporting"
    case .State:
        return "state"
    }
    return ""
}

schema_diff_class_valid :: proc(class: Schema_Diff_Class) -> bool {
    switch class {
    case .Supporting, .State:
        return true
    }
    return false
}

schema_diff_class_from_text :: proc(text: string) -> (Schema_Diff_Class, bool) {
    switch text {
    case "supporting":
        return .Supporting, true
    case "state":
        return .State, true
    }
    return .State, false
}

schema_diff_policy_text :: proc(policy: Schema_Diff_Policy) -> string {
    switch policy {
    case .Automatic:
        return "automatic"
    case .Script_Required:
        return "script_required"
    }
    return ""
}

schema_diff_policy_valid :: proc(policy: Schema_Diff_Policy) -> bool {
    switch policy {
    case .Automatic, .Script_Required:
        return true
    }
    return false
}

schema_diff_policy_from_text :: proc(text: string) -> (Schema_Diff_Policy, bool) {
    switch text {
    case "automatic":
        return .Automatic, true
    case "script_required":
        return .Script_Required, true
    }
    return .Script_Required, false
}

schema_diff_clone :: proc(value: string, allocator: mem.Allocator) -> (string, bool) {
    copy, err := strings.clone(value, allocator)
    return copy, err == nil
}

schema_diff_allocator_valid :: proc(allocator: mem.Allocator) -> bool {
    return allocator.procedure != nil
}

SCHEMA_DIFF_MAX_BUILDER_BYTES :: 64 * 1024 * 1024

schema_diff_builder_capacity_add :: proc(capacity: ^int, amount: int) -> bool {
    if amount < 0 || capacity^ < 0 || capacity^ > SCHEMA_DIFF_MAX_BUILDER_BYTES - amount do return false
    capacity^ += amount
    return true
}

schema_diff_builder_make :: proc(capacity: int, allocator: mem.Allocator) -> (strings.Builder, bool) {
    if !schema_diff_allocator_valid(allocator) || capacity < 0 || capacity > SCHEMA_DIFF_MAX_BUILDER_BYTES do return {}, false
    builder_capacity := max(1, capacity)
    builder, err := strings.builder_make_len_cap(0, builder_capacity, allocator)
    return builder, err == nil
}

schema_diff_unescape :: proc(raw: string, allocator: mem.Allocator) -> (string, History_Unescape_Result) {
    if !schema_diff_allocator_valid(allocator) do return "", .Out_Of_Memory
    has_escape := false
    for index := 0; index < len(raw); index += 1 {
        ch := raw[index]
        if ch == '\\' {
            has_escape = true
            index += 1
            if index >= len(raw) do return "", .Invalid
            switch raw[index] {
            case '\\', 't', 'n', '=', '|':
            case:
                return "", .Invalid
            }
            continue
        }
        if ch < 0x20 || ch == 0x7f do return "", .Invalid
    }
    if !has_escape {
        owned, err := strings.clone(raw, allocator)
        if err != nil do return "", .Out_Of_Memory
        return owned, .Ok
    }
    builder, builder_ok := schema_diff_builder_make(len(raw), allocator)
    if !builder_ok do return "", .Out_Of_Memory
    for index := 0; index < len(raw); index += 1 {
        ch := raw[index]
        if ch != '\\' {
            strings.write_byte(&builder, ch)
            continue
        }
        index += 1
        switch raw[index] {
        case '\\':
            strings.write_byte(&builder, '\\')
        case 't':
            strings.write_byte(&builder, '\t')
        case 'n':
            strings.write_byte(&builder, '\n')
        case '=':
            strings.write_byte(&builder, '=')
        case '|':
            strings.write_byte(&builder, '|')
        }
    }
    return strings.to_string(builder), .Ok
}

schema_diff_map_capacity :: proc(count: int) -> int {
    if count <= 0 do return 8
    if count > (SCHEMA_DIFF_MAX_RECORDS / 2) do return SCHEMA_DIFF_MAX_RECORDS
    return max(8, count * 2)
}

schema_diff_is_identifier :: proc(name: string, limits: Schema_Diff_Limits) -> bool {
    return len(name) <= limits.max_identifier && history_is_identifier(name)
}

schema_diff_is_logical_id :: proc(id: string, limits: Schema_Diff_Limits) -> bool {
    return len(id) <= limits.max_identifier && history_is_logical_id(id)
}

schema_diff_parse_positive :: proc(text: string) -> (int, bool) {
    return history_parse_schema_version(text)
}

schema_diff_enumerated_array_header :: proc(
    expr: string,
    cursor: ^int,
    limits: Schema_Diff_Limits,
) -> (
    count: i64,
    index_id: string,
    ok: bool,
) {
    if !strings.has_prefix(expr[cursor^:], "enumerated_array[") do return
    cursor^ += len("enumerated_array[")
    count_start := cursor^
    for cursor^ < len(expr) && expr[cursor^] >= '0' && expr[cursor^] <= '9' {
        cursor^ += 1
    }
    if count_start == cursor^ || cursor^ >= len(expr) || expr[cursor^] != ';' do return
    parsed_count, count_ok := history_parse_i64(expr[count_start:cursor^], false)
    if !count_ok || parsed_count <= 0 || parsed_count > i64(limits.max_array_length) do return
    cursor^ += 1
    index_start := cursor^
    for cursor^ < len(expr) && expr[cursor^] != ']' {
        cursor^ += 1
    }
    if index_start == cursor^ || cursor^ >= len(expr) || expr[cursor^] != ']' do return
    parsed_index := expr[index_start:cursor^]
    if !schema_diff_is_logical_id(parsed_index, limits) do return
    cursor^ += 1
    return parsed_count, parsed_index, true
}

schema_diff_enumerated_array_record_valid :: proc(record: ^Schema_Diff_Record, count: i64) -> bool {
    if record == nil || record.kind != "enum" || count <= 0 || count != i64(len(record.enums)) do return false
    minimum := record.enums[0].value
    maximum := minimum
    for entry, index in record.enums {
        minimum = min(minimum, entry.value)
        maximum = max(maximum, entry.value)
        for previous_index in 0 ..< index {
            if record.enums[previous_index].value == entry.value do return false
        }
    }
    if maximum < minimum do return false
    offset := count - 1
    if minimum > max(i64) - offset do return false
    return maximum == minimum + offset
}

schema_diff_type_node :: proc(
    expr: string,
    cursor: ^int,
    snapshot: ^Schema_Diff_Snapshot,
    indexes: map[string]int,
    limits: Schema_Diff_Limits,
    depth: int,
) -> bool {
    if cursor^ >= len(expr) || depth > limits.max_type_depth do return false
    if strings.has_prefix(expr[cursor^:], "enumerated_array[") {
        count, index_id, header_ok := schema_diff_enumerated_array_header(expr, cursor, limits)
        if !header_ok do return false
        index, found := indexes[index_id]
        if !found || !schema_diff_enumerated_array_record_valid(&snapshot.records[index], count) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '<' do return false
        cursor^ += 1
        if !schema_diff_type_node(expr, cursor, snapshot, indexes, limits, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    if strings.has_prefix(expr[cursor^:], "array[") {
        cursor^ += len("array[")
        start := cursor^
        for cursor^ < len(expr) && expr[cursor^] >= '0' && expr[cursor^] <= '9' {
            cursor^ += 1
        }
        if start == cursor^ || cursor^ >= len(expr) || expr[cursor^] != ']' do return false
        length, ok := history_parse_i64(expr[start:cursor^], false)
        if !ok || length < 0 || length > i64(limits.max_array_length) do return false
        cursor^ += 1
        if cursor^ >= len(expr) || expr[cursor^] != '<' do return false
        cursor^ += 1
        if !schema_diff_type_node(expr, cursor, snapshot, indexes, limits, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    if strings.has_prefix(expr[cursor^:], "dynamic<") {
        cursor^ += len("dynamic<")
        if !schema_diff_type_node(expr, cursor, snapshot, indexes, limits, depth + 1) do return false
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
        return history_is_builtin(atom[len("builtin:"):])
    }
    if !schema_diff_is_logical_id(atom, limits) do return false
    _, found := indexes[atom]
    return found
}

schema_diff_validate_type :: proc(
    expr: string,
    snapshot: ^Schema_Diff_Snapshot,
    indexes: map[string]int,
    limits: Schema_Diff_Limits,
) -> bool {
    cursor := 0
    return schema_diff_type_node(expr, &cursor, snapshot, indexes, limits, 0) && cursor == len(expr)
}

schema_diff_validate_target :: proc(
    expr: string,
    snapshot: ^Schema_Diff_Snapshot,
    indexes: map[string]int,
    limits: Schema_Diff_Limits,
) -> bool {
    return schema_diff_validate_type(expr, snapshot, indexes, limits)
}

schema_diff_path :: proc(parent, child: string, allocator: mem.Allocator) -> (string, bool) {
    parts := [3]string{parent, ".", child}
    path, err := strings.concatenate(parts[:], allocator)
    return path, err == nil
}

schema_diff_fail_child :: proc(
    error: ^Schema_Diff_Error,
    kind: Schema_Diff_Error_Kind,
    line: int,
    parent, child, message: string,
    allocator: mem.Allocator,
) {
    path, ok := schema_diff_path(parent, child, allocator)
    if !ok {
        schema_diff_fail(error, .Out_Of_Memory, line, parent, "cannot own error path", allocator)
        return
    }
    schema_diff_fail(error, kind, line, path, message, allocator)
    delete(path, allocator)
}

schema_diff_parse_semantic_snapshot :: proc(
    data: []byte,
    allocator: mem.Allocator,
    limits: Schema_Diff_Limits,
) -> (
    snapshot: Schema_Diff_Snapshot,
    error: Schema_Diff_Error,
    ok: bool,
) {
    snapshot.allocator = allocator
    if !schema_diff_allocator_valid(allocator) {
        error = Schema_Diff_Error {
            kind      = .Out_Of_Memory,
            line      = 1,
            path      = "$",
            message   = "schema snapshot allocator is invalid",
            allocator = allocator,
        }
        return {}, error, false
    }
    if len(data) == 0 || len(data) > limits.max_bytes {
        schema_diff_fail(&error, .Limit_Exceeded, 1, "$", "schema snapshot byte limit exceeded", allocator)
        return {}, error, false
    }
    if data[len(data) - 1] != '\n' {
        schema_diff_fail(&error, .Invalid_Input, 1, "$", "schema snapshot must end with newline", allocator)
        return {}, error, false
    }
    records, records_error := make([dynamic]Schema_Diff_Record, allocator)
    if records_error != nil {
        schema_diff_fail(&error, .Out_Of_Memory, 1, "$", "cannot allocate schema records", allocator)
        return {}, error, false
    }
    snapshot.records = records
    indexes, indexes_error := make(map[string]int, schema_diff_map_capacity(limits.max_records), allocator)
    if indexes_error != nil {
        schema_diff_fail(&error, .Out_Of_Memory, 1, "$", "cannot allocate schema indexes", allocator)
        delete(snapshot.records)
        return {}, error, false
    }
    defer delete(indexes)
    cursor := 0
    line_number := 0
    line, line_ok := history_next_line(data, &cursor)
    line_number += 1
    if !line_ok || line != "format_version=1" {
        schema_diff_fail(&error, .Invalid_Input, line_number, "$", "format_version header must equal 1", allocator)
        schema_diff_snapshot_dispose(&snapshot)
        return {}, error, false
    }
    line, line_ok = history_next_line(data, &cursor)
    line_number += 1
    if !line_ok {
        schema_diff_fail(&error, .Invalid_Input, line_number, "$", "schema version header is missing", allocator)
        schema_diff_snapshot_dispose(&snapshot)
        return {}, error, false
    }
    version_pairs, version_count, version_pairs_ok := history_parse_key_values(line, '|')
    if !version_pairs_ok || version_count != 1 || version_pairs[0].key != "fixture_schema_version" {
        schema_diff_fail(&error, .Invalid_Input, line_number, "$", "schema version header is malformed", allocator)
        schema_diff_snapshot_dispose(&snapshot)
        return {}, error, false
    }
    schema_version, schema_version_ok := schema_diff_parse_positive(version_pairs[0].value)
    if !schema_version_ok {
        schema_diff_fail(&error, .Invalid_Input, line_number, "$", "schema version is invalid", allocator)
        schema_diff_snapshot_dispose(&snapshot)
        return {}, error, false
    }
    snapshot.format_version = SCHEMA_DIFF_FORMAT_VERSION
    snapshot.schema_version = schema_version

    line, line_ok = history_next_line(data, &cursor)
    line_number += 1
    root_pairs, root_count, root_ok := history_parse_key_values(line, '|')
    if !line_ok ||
       !root_ok ||
       root_count != 1 ||
       root_pairs[0].key != "root" ||
       !schema_diff_is_logical_id(root_pairs[0].value, limits) {
        schema_diff_fail(&error, .Invalid_Input, line_number, "$", "root header is malformed", allocator)
        schema_diff_snapshot_dispose(&snapshot)
        return {}, error, false
    }
    root, root_copy_ok := schema_diff_clone(root_pairs[0].value, allocator)
    if !root_copy_ok {
        schema_diff_fail(&error, .Out_Of_Memory, line_number, "$", "cannot own root identifier", allocator)
        schema_diff_snapshot_dispose(&snapshot)
        return {}, error, false
    }
    snapshot.root = root
    current_record := -1
    field_count := 0
    enum_count := 0
    for cursor < len(data) {
        if line_number >= limits.max_lines {
            schema_diff_fail(
                &error,
                .Limit_Exceeded,
                line_number,
                "$",
                "schema snapshot line limit exceeded",
                allocator,
            )
            schema_diff_snapshot_dispose(&snapshot)
            return {}, error, false
        }
        line, line_ok = history_next_line(data, &cursor)
        line_number += 1
        if !line_ok || len(line) == 0 {
            schema_diff_fail(&error, .Invalid_Input, line_number, "$", "schema snapshot line is invalid", allocator)
            schema_diff_snapshot_dispose(&snapshot)
            return {}, error, false
        }
        pairs, count, pairs_ok := history_parse_key_values(line, '|')
        if !pairs_ok || count == 0 {
            schema_diff_fail(&error, .Invalid_Input, line_number, "$", "schema snapshot line is malformed", allocator)
            schema_diff_snapshot_dispose(&snapshot)
            return {}, error, false
        }
        switch pairs[0].key {
        case "type":
            if count != 3 || pairs[1].key != "kind" || pairs[2].key != "detail" {
                schema_diff_fail(&error, .Invalid_Input, line_number, "$", "type line keys are invalid", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            if len(snapshot.records) >= limits.max_records {
                schema_diff_fail(&error, .Limit_Exceeded, line_number, "$", "type record limit exceeded", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            id := pairs[0].value
            kind := pairs[1].value
            detail, detail_status := schema_diff_unescape(pairs[2].value, allocator)
            if !schema_diff_is_logical_id(id, limits) ||
               (kind != "struct" && kind != "enum" && kind != "alias" && kind != "distinct") ||
               detail_status != .Ok ||
               !history_validate_detail(kind, detail) {
                if detail_status == .Ok do delete(detail, allocator)
                failure_kind := Schema_Diff_Error_Kind(.Invalid_Input)
                if detail_status == .Out_Of_Memory do failure_kind = .Out_Of_Memory
                schema_diff_fail(&error, failure_kind, line_number, id, "type record is invalid", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            if _, found := indexes[id]; found {
                schema_diff_fail(&error, .Invalid_Input, line_number, id, "duplicate type record", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            owned_id, id_ok := schema_diff_clone(id, allocator)
            owned_kind, kind_ok := schema_diff_clone(kind, allocator)
            owned_detail := detail
            detail_ok := detail_status == .Ok
            if !id_ok || !kind_ok || !detail_ok {
                if id_ok do delete(owned_id, allocator)
                if kind_ok do delete(owned_kind, allocator)
                if detail_ok do delete(owned_detail, allocator)
                schema_diff_fail(&error, .Out_Of_Memory, line_number, id, "cannot own type record", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            record := Schema_Diff_Record {
                id     = owned_id,
                kind   = owned_kind,
                detail = owned_detail,
                line   = line_number,
            }
            fields, fields_error := make([dynamic]Schema_Diff_Field, allocator)
            enums, enums_error := make([dynamic]Schema_Diff_Enum, allocator)
            record.fields = fields
            record.enums = enums
            if fields_error != nil || enums_error != nil {
                if fields_error == nil do delete(record.fields)
                if enums_error == nil do delete(record.enums)
                schema_diff_record_dispose(&record, allocator)
                schema_diff_fail(&error, .Out_Of_Memory, line_number, id, "cannot allocate type children", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            appended, append_error := append_elem(&snapshot.records, record)
            if append_error != nil || appended != 1 {
                schema_diff_record_dispose(&record, allocator)
                schema_diff_fail(&error, .Out_Of_Memory, line_number, id, "cannot append type record", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            current_record = len(snapshot.records) - 1
            indexes[id] = current_record
        case "field":
            if count != 5 ||
               pairs[1].key != "name" ||
               pairs[2].key != "using" ||
               pairs[3].key != "tag" ||
               pairs[4].key != "type" ||
               current_record < 0 {
                schema_diff_fail(&error, .Invalid_Input, line_number, "$", "field line keys are invalid", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            record := &snapshot.records[current_record]
            if pairs[0].value != record.id || !schema_diff_is_identifier(pairs[1].value, limits) {
                schema_diff_fail(
                    &error,
                    .Invalid_Input,
                    line_number,
                    record.id,
                    "field record or name is invalid",
                    allocator,
                )
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            if record.kind != "struct" {
                schema_diff_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    record.id,
                    pairs[1].value,
                    "field belongs to non-struct record",
                    allocator,
                )
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            using_value, using_ok := history_parse_bool(pairs[2].value)
            if !using_ok {
                schema_diff_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    record.id,
                    pairs[1].value,
                    "field using value is invalid",
                    allocator,
                )
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            for field in record.fields {
                if field.name == pairs[1].value {
                    schema_diff_fail_child(
                        &error,
                        .Invalid_Input,
                        line_number,
                        record.id,
                        pairs[1].value,
                        "duplicate field name",
                        allocator,
                    )
                    schema_diff_snapshot_dispose(&snapshot)
                    return {}, error, false
                }
            }
            if field_count >= limits.max_fields {
                schema_diff_fail_child(
                    &error,
                    .Limit_Exceeded,
                    line_number,
                    record.id,
                    pairs[1].value,
                    "field limit exceeded",
                    allocator,
                )
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            tag, tag_status := schema_diff_unescape(pairs[3].value, allocator)
            type_name, type_status := schema_diff_unescape(pairs[4].value, allocator)
            owned_name, name_ok := schema_diff_clone(pairs[1].value, allocator)
            if tag_status != .Ok || type_status != .Ok || !name_ok {
                if tag_status == .Ok do delete(tag, allocator)
                if type_status == .Ok do delete(type_name, allocator)
                if name_ok do delete(owned_name, allocator)
                failure_kind := Schema_Diff_Error_Kind(.Invalid_Input)
                if tag_status == .Out_Of_Memory ||
                   type_status == .Out_Of_Memory ||
                   (tag_status == .Ok && type_status == .Ok && !name_ok) {
                    failure_kind = .Out_Of_Memory
                }
                schema_diff_fail_child(
                    &error,
                    failure_kind,
                    line_number,
                    record.id,
                    pairs[1].value,
                    "field ownership or escaping is invalid",
                    allocator,
                )
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            field := Schema_Diff_Field {
                name     = owned_name,
                tag      = tag,
                type     = type_name,
                is_using = using_value,
                line     = line_number,
            }
            appended, append_error := append_elem(&record.fields, field)
            if append_error != nil || appended != 1 {
                delete(field.name, allocator)
                delete(field.tag, allocator)
                delete(field.type, allocator)
                schema_diff_fail(&error, .Out_Of_Memory, line_number, record.id, "cannot append field", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            field_count += 1
        case "enum":
            if count != 3 || pairs[1].key != "name" || pairs[2].key != "value" || current_record < 0 {
                schema_diff_fail(&error, .Invalid_Input, line_number, "$", "enum line keys are invalid", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            record := &snapshot.records[current_record]
            if pairs[0].value != record.id ||
               !schema_diff_is_identifier(pairs[1].value, limits) ||
               record.kind != "enum" {
                schema_diff_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    record.id,
                    pairs[1].value,
                    "enum record or name is invalid",
                    allocator,
                )
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            value, value_ok := history_parse_i64(pairs[2].value, true)
            if !value_ok {
                schema_diff_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    record.id,
                    pairs[1].value,
                    "enum value is invalid",
                    allocator,
                )
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            for entry in record.enums {
                if entry.name == pairs[1].value || entry.value == value {
                    schema_diff_fail_child(
                        &error,
                        .Invalid_Input,
                        line_number,
                        record.id,
                        pairs[1].value,
                        "duplicate enum name or value",
                        allocator,
                    )
                    schema_diff_snapshot_dispose(&snapshot)
                    return {}, error, false
                }
            }
            if enum_count >= limits.max_enums {
                schema_diff_fail_child(
                    &error,
                    .Limit_Exceeded,
                    line_number,
                    record.id,
                    pairs[1].value,
                    "enum limit exceeded",
                    allocator,
                )
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            owned_name, name_ok := schema_diff_clone(pairs[1].value, allocator)
            if !name_ok {
                schema_diff_fail_child(
                    &error,
                    .Out_Of_Memory,
                    line_number,
                    record.id,
                    pairs[1].value,
                    "cannot own enum name",
                    allocator,
                )
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            entry := Schema_Diff_Enum {
                name  = owned_name,
                value = value,
                line  = line_number,
            }
            appended, append_error := append_elem(&record.enums, entry)
            if append_error != nil || appended != 1 {
                delete(entry.name, allocator)
                schema_diff_fail(&error, .Out_Of_Memory, line_number, record.id, "cannot append enum", allocator)
                schema_diff_snapshot_dispose(&snapshot)
                return {}, error, false
            }
            enum_count += 1
        case:
            schema_diff_fail(&error, .Invalid_Input, line_number, "$", "unknown schema snapshot line", allocator)
            schema_diff_snapshot_dispose(&snapshot)
            return {}, error, false
        }
    }
    if len(snapshot.records) == 0 {
        schema_diff_fail(&error, .Invalid_Input, line_number, "$", "schema snapshot has no records", allocator)
        schema_diff_snapshot_dispose(&snapshot)
        return {}, error, false
    }
    if !schema_diff_validate_snapshot(&snapshot, &error, limits) {
        schema_diff_snapshot_dispose(&snapshot)
        return {}, error, false
    }
    return snapshot, error, true
}

schema_diff_using_resolves_struct :: proc(
    index: int,
    snapshot: ^Schema_Diff_Snapshot,
    indexes: map[string]int,
    state: []u8,
    limits: Schema_Diff_Limits,
) -> bool {
    if index < 0 || index >= len(snapshot.records) do return false
    if state[index] == 1 do return false
    if state[index] == 2 do return true
    state[index] = 1
    record := &snapshot.records[index]
    switch record.kind {
    case "struct":
        state[index] = 2
        return true
    case "alias":
        target, found := history_detail_value(record.detail, "target")
        if !found || !schema_diff_is_logical_id(target, limits) do return false
        target_index, target_found := indexes[target]
        if !target_found || !schema_diff_using_resolves_struct(target_index, snapshot, indexes, state, limits) do return false
        state[index] = 2
        return true
    }
    return false
}

schema_diff_visit_type_node :: proc(
    expr: string,
    cursor: ^int,
    snapshot: ^Schema_Diff_Snapshot,
    indexes: map[string]int,
    state: []u8,
    reachable: []bool,
    limits: Schema_Diff_Limits,
    depth: int,
) -> bool {
    if cursor^ >= len(expr) || depth > limits.max_type_depth do return false
    if strings.has_prefix(expr[cursor^:], "enumerated_array[") {
        count, index_id, header_ok := schema_diff_enumerated_array_header(expr, cursor, limits)
        if !header_ok do return false
        index, found := indexes[index_id]
        if !found || !schema_diff_enumerated_array_record_valid(&snapshot.records[index], count) do return false
        if !schema_diff_visit_record(index, snapshot, indexes, state, reachable, limits) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '<' do return false
        cursor^ += 1
        if !schema_diff_visit_type_node(expr, cursor, snapshot, indexes, state, reachable, limits, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    if strings.has_prefix(expr[cursor^:], "array[") {
        cursor^ += len("array[")
        start := cursor^
        for cursor^ < len(expr) && expr[cursor^] >= '0' && expr[cursor^] <= '9' {
            cursor^ += 1
        }
        if start == cursor^ || cursor^ >= len(expr) || expr[cursor^] != ']' do return false
        cursor^ += 1
        if cursor^ >= len(expr) || expr[cursor^] != '<' do return false
        cursor^ += 1
        if !schema_diff_visit_type_node(expr, cursor, snapshot, indexes, state, reachable, limits, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    if strings.has_prefix(expr[cursor^:], "dynamic<") {
        cursor^ += len("dynamic<")
        if !schema_diff_visit_type_node(expr, cursor, snapshot, indexes, state, reachable, limits, depth + 1) do return false
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
    if strings.has_prefix(atom, "builtin:") do return history_is_builtin(atom[len("builtin:"):])
    index, found := indexes[atom]
    if !found do return false
    return schema_diff_visit_record(index, snapshot, indexes, state, reachable, limits)
}

schema_diff_visit_type :: proc(
    expr: string,
    snapshot: ^Schema_Diff_Snapshot,
    indexes: map[string]int,
    state: []u8,
    reachable: []bool,
    limits: Schema_Diff_Limits,
) -> bool {
    cursor := 0
    return(
        schema_diff_visit_type_node(expr, &cursor, snapshot, indexes, state, reachable, limits, 0) &&
        cursor == len(expr) \
    )
}

schema_diff_visit_record :: proc(
    index: int,
    snapshot: ^Schema_Diff_Snapshot,
    indexes: map[string]int,
    state: []u8,
    reachable: []bool,
    limits: Schema_Diff_Limits,
) -> bool {
    if index < 0 || index >= len(snapshot.records) do return false
    if state[index] == 1 do return false
    if state[index] == 2 {
        reachable[index] = true
        return true
    }
    state[index] = 1
    reachable[index] = true
    record := &snapshot.records[index]
    switch record.kind {
    case "struct":
        for field in record.fields {
            if !schema_diff_visit_type(field.type, snapshot, indexes, state, reachable, limits) do return false
        }
    case "alias", "distinct":
        target, found := history_detail_value(record.detail, "target")
        if !found || !schema_diff_visit_type(target, snapshot, indexes, state, reachable, limits) do return false
    }
    state[index] = 2
    return true
}

schema_diff_validate_snapshot :: proc(
    snapshot: ^Schema_Diff_Snapshot,
    error: ^Schema_Diff_Error,
    limits: Schema_Diff_Limits,
) -> bool {
    indexes, indexes_error := make(map[string]int, schema_diff_map_capacity(len(snapshot.records)), snapshot.allocator)
    if indexes_error != nil {
        schema_diff_fail(error, .Out_Of_Memory, 1, "$", "cannot allocate schema indexes", snapshot.allocator)
        return false
    }
    defer delete(indexes)
    for index := 0; index < len(snapshot.records); index += 1 {
        record := &snapshot.records[index]
        if _, found := indexes[record.id]; found {
            schema_diff_fail(
                error,
                .Invalid_Input,
                record.line,
                record.id,
                "duplicate type record",
                snapshot.allocator,
            )
            return false
        }
        indexes[record.id] = index
    }
    root_index, root_found := indexes[snapshot.root]
    if !root_found {
        schema_diff_fail(
            error,
            .Unresolved_Reference,
            3,
            snapshot.root,
            "root type is not declared",
            snapshot.allocator,
        )
        return false
    }
    if snapshot.records[root_index].kind != "struct" {
        schema_diff_fail(error, .Invalid_Input, 3, snapshot.root, "root type must be a struct", snapshot.allocator)
        return false
    }
    using_state, using_state_error := make([]u8, len(snapshot.records), snapshot.allocator)
    if using_state_error != nil {
        schema_diff_fail(error, .Out_Of_Memory, 1, "$", "cannot allocate using state", snapshot.allocator)
        return false
    }
    defer delete(using_state, snapshot.allocator)
    for record in snapshot.records {
        switch record.kind {
        case "struct":
            for field in record.fields {
                if !schema_diff_validate_type(field.type, snapshot, indexes, limits) {
                    kind := Schema_Diff_Error_Kind(.Unresolved_Reference)
                    if schema_diff_type_has_builtin(field.type) do kind = .Invalid_Input
                    schema_diff_fail_child(
                        error,
                        kind,
                        field.line,
                        record.id,
                        field.name,
                        "invalid or unresolved field type",
                        snapshot.allocator,
                    )
                    return false
                }
                if field.is_using {
                    if !schema_diff_is_logical_id(field.type, limits) {
                        schema_diff_fail_child(
                            error,
                            .Invalid_Input,
                            field.line,
                            record.id,
                            field.name,
                            "using field must embed a struct type",
                            snapshot.allocator,
                        )
                        return false
                    }
                    target_index, target_found := indexes[field.type]
                    if !target_found ||
                       !schema_diff_using_resolves_struct(target_index, snapshot, indexes, using_state, limits) {
                        schema_diff_fail_child(
                            error,
                            .Invalid_Input,
                            field.line,
                            record.id,
                            field.name,
                            "using field must embed a struct type",
                            snapshot.allocator,
                        )
                        return false
                    }
                }
            }
        case "enum":
            base, base_found := history_detail_value(record.detail, "base")
            minimum, maximum, bounds_ok := history_enum_bounds(base)
            if !base_found || !history_validate_base(base) || !bounds_ok || len(record.enums) == 0 {
                schema_diff_fail(
                    error,
                    .Invalid_Input,
                    record.line,
                    record.id,
                    "enum body or base is invalid",
                    snapshot.allocator,
                )
                return false
            }
            for entry in record.enums {
                if entry.value < minimum || entry.value > maximum {
                    schema_diff_fail_child(
                        error,
                        .Invalid_Input,
                        entry.line,
                        record.id,
                        entry.name,
                        "enum value does not fit base",
                        snapshot.allocator,
                    )
                    return false
                }
            }
        case "alias", "distinct":
            target, target_found := history_detail_value(record.detail, "target")
            if !target_found || !schema_diff_validate_target(target, snapshot, indexes, limits) {
                schema_diff_fail(
                    error,
                    .Unresolved_Reference,
                    record.line,
                    record.id,
                    "invalid or unresolved target",
                    snapshot.allocator,
                )
                return false
            }
        }
    }
    state, state_error := make([]u8, len(snapshot.records), snapshot.allocator)
    if state_error != nil {
        schema_diff_fail(error, .Out_Of_Memory, 1, "$", "cannot allocate graph state", snapshot.allocator)
        return false
    }
    reachable, reachable_error := make([]bool, len(snapshot.records), snapshot.allocator)
    if reachable_error != nil {
        delete(state, snapshot.allocator)
        schema_diff_fail(error, .Out_Of_Memory, 1, "$", "cannot allocate reachability state", snapshot.allocator)
        return false
    }
    defer delete(state, snapshot.allocator)
    defer delete(reachable, snapshot.allocator)
    if !schema_diff_visit_record(root_index, snapshot, indexes, state, reachable, limits) {
        schema_diff_fail(
            error,
            .Invalid_Input,
            snapshot.records[root_index].line,
            snapshot.root,
            "recursive or invalid type graph",
            snapshot.allocator,
        )
        return false
    }
    for index := 0; index < len(snapshot.records); index += 1 {
        record := &snapshot.records[index]
        if !reachable[index] {
            schema_diff_fail(
                error,
                .Unreachable_Record,
                record.line,
                record.id,
                "record is not reachable from root",
                snapshot.allocator,
            )
            return false
        }
    }
    return true
}

schema_diff_type_has_builtin :: proc(expr: string) -> bool {
    return strings.contains(expr, "builtin:")
}

schema_diff_copy_history_record :: proc(
    target: ^Schema_Diff_Record,
    source: History_Record,
    allocator: mem.Allocator,
) -> bool {
    id, id_ok := schema_diff_clone(source.id, allocator)
    kind, kind_ok := schema_diff_clone(source.kind, allocator)
    detail, detail_ok := schema_diff_clone(source.detail, allocator)
    if !id_ok || !kind_ok || !detail_ok {
        if id_ok do delete(id, allocator)
        if kind_ok do delete(kind, allocator)
        if detail_ok do delete(detail, allocator)
        return false
    }
    target^ = Schema_Diff_Record {
        id     = id,
        kind   = kind,
        detail = detail,
        line   = source.line,
    }
    fields, fields_error := make([dynamic]Schema_Diff_Field, allocator)
    enums, enums_error := make([dynamic]Schema_Diff_Enum, allocator)
    target.fields = fields
    target.enums = enums
    if fields_error != nil || enums_error != nil {
        schema_diff_record_dispose(target, allocator)
        return false
    }
    for field in source.fields {
        name, name_ok := schema_diff_clone(field.name, allocator)
        tag, tag_ok := schema_diff_clone(field.tag, allocator)
        type_name, type_ok := schema_diff_clone(field.type, allocator)
        if !name_ok || !tag_ok || !type_ok {
            if name_ok do delete(name, allocator)
            if tag_ok do delete(tag, allocator)
            if type_ok do delete(type_name, allocator)
            schema_diff_record_dispose(target, allocator)
            return false
        }
        appended, append_error := append_elem(
            &target.fields,
            Schema_Diff_Field{name = name, tag = tag, type = type_name, is_using = field.is_using, line = field.line},
        )
        if append_error != nil || appended != 1 {
            delete(name, allocator)
            delete(tag, allocator)
            delete(type_name, allocator)
            schema_diff_record_dispose(target, allocator)
            return false
        }
    }
    for entry in source.enums {
        name, name_ok := schema_diff_clone(entry.name, allocator)
        if !name_ok {
            schema_diff_record_dispose(target, allocator)
            return false
        }
        appended, append_error := append_elem(
            &target.enums,
            Schema_Diff_Enum{name = name, value = entry.value, line = entry.line},
        )
        if append_error != nil || appended != 1 {
            delete(name, allocator)
            schema_diff_record_dispose(target, allocator)
            return false
        }
    }
    return true
}

schema_diff_parse_frozen_snapshot :: proc(
    data: []byte,
    allocator: mem.Allocator,
    limits := SCHEMA_DIFF_DEFAULT_LIMITS,
) -> (
    snapshot: Schema_Diff_Snapshot,
    error: Schema_Diff_Error,
    ok: bool,
) {
    if !schema_diff_allocator_valid(allocator) {
        error = Schema_Diff_Error {
            kind      = .Out_Of_Memory,
            line      = 1,
            path      = "$",
            message   = "frozen snapshot allocator is invalid",
            allocator = allocator,
        }
        return {}, error, false
    }
    if len(data) > limits.max_bytes {
        schema_diff_fail(&error, .Limit_Exceeded, 1, "$", "frozen snapshot byte limit exceeded", allocator)
        return {}, error, false
    }
    history, history_error, history_ok := history_parse_manifest(data, allocator)
    if !history_ok {
        schema_diff_fail(
            &error,
            Schema_Diff_Error_Kind(history_error.kind),
            history_error.line,
            history_error.path,
            history_error.message,
            allocator,
        )
        history_error_dispose(&history_error)
        return {}, error, false
    }
    if history.format_version != HISTORY_SUPPORTED_FORMAT_VERSION {
        schema_diff_fail(&error, .Invalid_Input, 1, "$", "frozen snapshot format version is unsupported", allocator)
        history_manifest_dispose(&history)
        return {}, error, false
    }
    snapshot.allocator = allocator
    snapshot.format_version = history.format_version
    snapshot.schema_version = history.schema_version
    root, root_ok := schema_diff_clone(history.root, allocator)
    snapshot.root = root
    if !root_ok {
        schema_diff_fail(&error, .Out_Of_Memory, 3, "$", "cannot own frozen root", allocator)
        history_manifest_dispose(&history)
        return {}, error, false
    }
    records, records_error := make([dynamic]Schema_Diff_Record, 0, len(history.records), allocator)
    if records_error != nil {
        schema_diff_fail(&error, .Out_Of_Memory, 1, "$", "cannot allocate frozen records", allocator)
        history_manifest_dispose(&history)
        delete(snapshot.root, allocator)
        return {}, error, false
    }
    snapshot.records = records
    for source in history.records {
        record: Schema_Diff_Record
        if !schema_diff_copy_history_record(&record, source, allocator) {
            schema_diff_fail(&error, .Out_Of_Memory, source.line, source.id, "cannot copy frozen snapshot", allocator)
            schema_diff_snapshot_dispose(&snapshot)
            history_manifest_dispose(&history)
            return {}, error, false
        }
        appended, append_error := append_elem(&snapshot.records, record)
        if append_error != nil || appended != 1 {
            schema_diff_record_dispose(&record, allocator)
            schema_diff_fail(&error, .Out_Of_Memory, source.line, source.id, "cannot append frozen record", allocator)
            schema_diff_snapshot_dispose(&snapshot)
            history_manifest_dispose(&history)
            return {}, error, false
        }
    }
    history_manifest_dispose(&history)
    if !schema_diff_validate_snapshot(&snapshot, &error, limits) {
        schema_diff_snapshot_dispose(&snapshot)
        return {}, error, false
    }
    return snapshot, error, true
}

schema_diff_parse_candidate_snapshot :: proc(
    data: []byte,
    allocator: mem.Allocator,
    limits := SCHEMA_DIFF_DEFAULT_LIMITS,
) -> (
    snapshot: Schema_Diff_Snapshot,
    error: Schema_Diff_Error,
    ok: bool,
) {
    return schema_diff_parse_semantic_snapshot(data, allocator, limits)
}

schema_diff_record_index :: proc(indexes: map[string]int, id: string) -> (int, bool) {
    index, found := indexes[id]
    return index, found
}

schema_diff_field_index :: proc(record: ^Schema_Diff_Record, name: string) -> (int, bool) {
    for index := 0; index < len(record.fields); index += 1 {
        field := &record.fields[index]
        if field.name == name do return index, true
    }
    return 0, false
}

schema_diff_enum_index :: proc(record: ^Schema_Diff_Record, name: string) -> (int, bool) {
    for index := 0; index < len(record.enums); index += 1 {
        entry := &record.enums[index]
        if entry.name == name do return index, true
    }
    return 0, false
}

schema_diff_record_body :: proc(record: ^Schema_Diff_Record, allocator: mem.Allocator) -> (string, bool) {
    if record == nil do return "", false
    capacity := 64
    if !schema_diff_builder_capacity_add(&capacity, len(record.id)) ||
       !schema_diff_builder_capacity_add(&capacity, len(record.kind)) ||
       !schema_diff_builder_capacity_add(&capacity, len(record.detail)) {
        return "", false
    }
    for field in record.fields {
        if !schema_diff_builder_capacity_add(&capacity, 128) ||
           !schema_diff_builder_capacity_add(&capacity, len(record.id)) ||
           !schema_diff_builder_capacity_add(&capacity, len(field.name)) ||
           !schema_diff_builder_capacity_add(&capacity, len(field.tag)) ||
           !schema_diff_builder_capacity_add(&capacity, len(field.type)) {
            return "", false
        }
    }
    for entry in record.enums {
        if !schema_diff_builder_capacity_add(&capacity, 64) ||
           !schema_diff_builder_capacity_add(&capacity, len(record.id)) ||
           !schema_diff_builder_capacity_add(&capacity, len(entry.name)) {
            return "", false
        }
    }
    builder, builder_ok := schema_diff_builder_make(capacity, allocator)
    if !builder_ok do return "", false
    fmt.sbprintf(&builder, "type=%s|kind=%s|detail=%s", record.id, record.kind, record.detail)
    for field in record.fields {
        fmt.sbprintf(
            &builder,
            "\nfield=%s|name=%s|using=%d|tag=%s|type=%s",
            record.id,
            field.name,
            bool_int(field.is_using),
            field.tag,
            field.type,
        )
    }
    for entry in record.enums {
        fmt.sbprintf(&builder, "\nenum=%s|name=%s|value=%d", record.id, entry.name, entry.value)
    }
    return strings.to_string(builder), true
}

schema_diff_field_body :: proc(field: ^Schema_Diff_Field, allocator: mem.Allocator) -> (string, bool) {
    if field == nil do return "", false
    capacity := 64
    if !schema_diff_builder_capacity_add(&capacity, len(field.tag)) ||
       !schema_diff_builder_capacity_add(&capacity, len(field.type)) {
        return "", false
    }
    builder, builder_ok := schema_diff_builder_make(capacity, allocator)
    if !builder_ok do return "", false
    fmt.sbprintf(&builder, "using=%d;tag=%s;type=%s", bool_int(field.is_using), field.tag, field.type)
    return strings.to_string(builder), true
}

schema_diff_enum_value_text :: proc(value: i64, allocator: mem.Allocator) -> (string, bool) {
    builder, builder_ok := schema_diff_builder_make(32, allocator)
    if !builder_ok do return "", false
    fmt.sbprintf(&builder, "%d", value)
    return strings.to_string(builder), true
}

schema_diff_field_names :: proc(record: ^Schema_Diff_Record, allocator: mem.Allocator) -> (string, bool) {
    if record == nil do return "", false
    capacity := 1
    for field in record.fields {
        if !schema_diff_builder_capacity_add(&capacity, len(field.name)) ||
           !schema_diff_builder_capacity_add(&capacity, 1) {
            return "", false
        }
    }
    builder, builder_ok := schema_diff_builder_make(capacity, allocator)
    if !builder_ok do return "", false
    for index := 0; index < len(record.fields); index += 1 {
        field := &record.fields[index]
        if index > 0 do strings.write_byte(&builder, ',')
        strings.write_string(&builder, field.name)
    }
    return strings.to_string(builder), true
}

schema_diff_change_id :: proc(
    kind: Schema_Diff_Change_Kind,
    path: string,
    allocator: mem.Allocator,
) -> (
    string,
    bool,
) {
    if !schema_diff_allocator_valid(allocator) do return "", false
    parts := [3]string{schema_diff_kind_text(kind), ":", path}
    id, err := strings.concatenate(parts[:], allocator)
    return id, err == nil
}

schema_diff_append_change :: proc(
    report: ^Schema_Diff_Report,
    error: ^Schema_Diff_Error,
    kind: Schema_Diff_Change_Kind,
    class: Schema_Diff_Class,
    policy: Schema_Diff_Policy,
    path, before, after: string,
) -> bool {
    id, id_ok := schema_diff_change_id(kind, path, report.allocator)
    if !id_ok {
        schema_diff_fail(error, .Out_Of_Memory, 0, path, "cannot own change id", report.allocator)
        return false
    }
    owned_id, id_copy_ok := schema_diff_clone(id, report.allocator)
    owned_path, path_ok := schema_diff_clone(path, report.allocator)
    owned_before, before_ok := schema_diff_clone(before, report.allocator)
    owned_after, after_ok := schema_diff_clone(after, report.allocator)
    delete(id, report.allocator)
    if !id_copy_ok || !path_ok || !before_ok || !after_ok {
        if id_copy_ok do delete(owned_id, report.allocator)
        if path_ok do delete(owned_path, report.allocator)
        if before_ok do delete(owned_before, report.allocator)
        if after_ok do delete(owned_after, report.allocator)
        schema_diff_fail(error, .Out_Of_Memory, 0, path, "cannot own schema change", report.allocator)
        return false
    }
    appended, append_error := append_elem(
        &report.changes,
        Schema_Diff_Change {
            id = owned_id,
            kind = kind,
            class = class,
            policy = policy,
            path = owned_path,
            before = owned_before,
            after = owned_after,
        },
    )
    if append_error != nil || appended != 1 {
        delete(owned_id, report.allocator)
        delete(owned_path, report.allocator)
        delete(owned_before, report.allocator)
        delete(owned_after, report.allocator)
        schema_diff_fail(error, .Out_Of_Memory, 0, path, "cannot append schema change", report.allocator)
        return false
    }
    return true
}

schema_diff_mark_type_refs :: proc(
    expr: string,
    new_snapshot: ^Schema_Diff_Snapshot,
    old_indexes: map[string]int,
    new_indexes: map[string]int,
    supporting: ^map[string]bool,
    limits: Schema_Diff_Limits,
    depth: int,
) {
    if depth > limits.max_type_depth do return
    cursor := 0
    for cursor < len(expr) {
        if strings.has_prefix(expr[cursor:], "enumerated_array[") {
            count, index_id, header_ok := schema_diff_enumerated_array_header(expr, &cursor, limits)
            if !header_ok do return
            if index, found := new_indexes[index_id];
               !found || !schema_diff_enumerated_array_record_valid(&new_snapshot.records[index], count) {
                return
            }
            schema_diff_mark_type_refs(index_id, new_snapshot, old_indexes, new_indexes, supporting, limits, depth + 1)
            if cursor >= len(expr) || expr[cursor] != '<' do return
            cursor += 1
            start := cursor
            nested := 1
            for cursor < len(expr) && nested > 0 {
                if expr[cursor] == '<' do nested += 1
                if expr[cursor] == '>' do nested -= 1
                cursor += 1
            }
            if cursor > start {
                schema_diff_mark_type_refs(
                    expr[start:cursor - 1],
                    new_snapshot,
                    old_indexes,
                    new_indexes,
                    supporting,
                    limits,
                    depth + 1,
                )
            }
            return
        }
        if strings.has_prefix(expr[cursor:], "array[") {
            cursor += len("array[")
            for cursor < len(expr) && expr[cursor] != '<' {
                cursor += 1
            }
            if cursor < len(expr) do cursor += 1
            start := cursor
            nested := 1
            for cursor < len(expr) && nested > 0 {
                if expr[cursor] == '<' do nested += 1
                if expr[cursor] == '>' do nested -= 1
                cursor += 1
            }
            if cursor > start do schema_diff_mark_type_refs(expr[start:cursor - 1], new_snapshot, old_indexes, new_indexes, supporting, limits, depth + 1)
            return
        }
        if strings.has_prefix(expr[cursor:], "dynamic<") {
            cursor += len("dynamic<")
            start := cursor
            nested := 1
            for cursor < len(expr) && nested > 0 {
                if expr[cursor] == '<' do nested += 1
                if expr[cursor] == '>' do nested -= 1
                cursor += 1
            }
            if cursor > start do schema_diff_mark_type_refs(expr[start:cursor - 1], new_snapshot, old_indexes, new_indexes, supporting, limits, depth + 1)
            return
        }
        atom := expr[cursor:]
        if strings.has_prefix(atom, "builtin:") do return
        if index, found := new_indexes[atom]; found {
            if _, existed := old_indexes[atom]; !existed {
                if supporting^[atom] do return
                supporting^[atom] = true
                record := &new_snapshot.records[index]
                for field in record.fields {
                    schema_diff_mark_type_refs(
                        field.type,
                        new_snapshot,
                        old_indexes,
                        new_indexes,
                        supporting,
                        limits,
                        depth + 1,
                    )
                }
                if record.kind == "alias" || record.kind == "distinct" {
                    target, target_ok := history_detail_value(record.detail, "target")
                    if target_ok do schema_diff_mark_type_refs(target, new_snapshot, old_indexes, new_indexes, supporting, limits, depth + 1)
                }
            }
        }
        return
    }
}

schema_diff_validate_change_ids :: proc(report: ^Schema_Diff_Report, error: ^Schema_Diff_Error) -> bool {
    for index := 1; index < len(report.changes); index += 1 {
        change := report.changes[index]
        cursor := index
        for cursor > 0 && strings.compare(change.id, report.changes[cursor - 1].id) < 0 {
            report.changes[cursor] = report.changes[cursor - 1]
            cursor -= 1
        }
        report.changes[cursor] = change
    }
    for index := 1; index < len(report.changes); index += 1 {
        if report.changes[index - 1].id == report.changes[index].id {
            schema_diff_fail(
                error,
                .Invalid_Input,
                0,
                report.changes[index].id,
                "duplicate or contradictory schema change",
                report.allocator,
            )
            return false
        }
    }
    return true
}

schema_diff_build_report :: proc(
    frozen_data, candidate_data: []byte,
    from_version, to_version: int,
    allocator: mem.Allocator,
    limits := SCHEMA_DIFF_DEFAULT_LIMITS,
) -> (
    report: Schema_Diff_Report,
    error: Schema_Diff_Error,
    ok: bool,
) {
    if !schema_diff_allocator_valid(allocator) {
        error = Schema_Diff_Error {
            kind    = .Out_Of_Memory,
            line    = 1,
            path    = "$",
            message = "schema diff allocator is invalid",
        }
        return {}, error, false
    }
    if !history_schema_version_supported(from_version) ||
       !history_schema_version_supported(to_version) ||
       to_version != from_version + 1 {
        schema_diff_fail(
            &error,
            .Invalid_Input,
            0,
            "$",
            "schema diff requires contiguous positive versions",
            allocator,
        )
        return {}, error, false
    }
    frozen, frozen_error, frozen_ok := schema_diff_parse_frozen_snapshot(frozen_data, allocator, limits)
    if !frozen_ok {
        return {}, frozen_error, false
    }
    defer schema_diff_snapshot_dispose(&frozen)
    if frozen.schema_version != from_version {
        schema_diff_fail(
            &error,
            .Invalid_Input,
            2,
            "$",
            "frozen schema version does not match migration source",
            allocator,
        )
        return {}, error, false
    }
    candidate, candidate_error, candidate_ok := schema_diff_parse_candidate_snapshot(candidate_data, allocator, limits)
    if !candidate_ok {
        return {}, candidate_error, false
    }
    defer schema_diff_snapshot_dispose(&candidate)
    if candidate.schema_version != from_version && candidate.schema_version != to_version {
        schema_diff_fail(
            &error,
            .Invalid_Input,
            2,
            "$",
            "candidate schema version must match migration source or target",
            allocator,
        )
        return {}, error, false
    }
    report.allocator = allocator
    report.format_version = SCHEMA_DIFF_FORMAT_VERSION
    report.from_version = from_version
    report.to_version = to_version
    report.candidate_line_count = 0
    for value in candidate_data {
        if value == '\n' do report.candidate_line_count += 1
    }
    report.candidate_record_count = len(candidate.records)
    for record in candidate.records {
        if record.id == candidate.root {
            report.candidate_root_fields = len(record.fields)
            break
        }
    }
    frozen_sha256, frozen_sha_ok := history_manifest_sha256_hex(frozen_data, allocator)
    candidate_sha256, candidate_sha_ok := history_manifest_sha256_hex(candidate_data, allocator)
    report.frozen_sha256 = frozen_sha256
    report.candidate_sha256 = candidate_sha256
    if !frozen_sha_ok || !candidate_sha_ok {
        schema_diff_fail(&error, .Out_Of_Memory, 0, "$", "cannot hash schema snapshots", allocator)
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    changes, changes_error := make([dynamic]Schema_Diff_Change, allocator)
    if changes_error != nil {
        schema_diff_fail(&error, .Out_Of_Memory, 0, "$", "cannot allocate schema changes", allocator)
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    report.changes = changes
    old_indexes, old_indexes_error := make(map[string]int, schema_diff_map_capacity(len(frozen.records)), allocator)
    if old_indexes_error != nil {
        schema_diff_fail(&error, .Out_Of_Memory, 0, "$", "cannot allocate frozen schema indexes", allocator)
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    new_indexes, new_indexes_error := make(map[string]int, schema_diff_map_capacity(len(candidate.records)), allocator)
    if new_indexes_error != nil {
        delete(old_indexes)
        schema_diff_fail(&error, .Out_Of_Memory, 0, "$", "cannot allocate candidate schema indexes", allocator)
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    supporting, supporting_error := make(map[string]bool, schema_diff_map_capacity(len(candidate.records)), allocator)
    if supporting_error != nil {
        delete(old_indexes)
        delete(new_indexes)
        schema_diff_fail(&error, .Out_Of_Memory, 0, "$", "cannot allocate supporting schema indexes", allocator)
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    defer delete(old_indexes)
    defer delete(new_indexes)
    defer delete(supporting)
    for index := 0; index < len(frozen.records); index += 1 {
        record := &frozen.records[index]
        old_indexes[record.id] = index
    }
    for index := 0; index < len(candidate.records); index += 1 {
        record := &candidate.records[index]
        new_indexes[record.id] = index
    }
    for candidate_index := 0; candidate_index < len(candidate.records); candidate_index += 1 {
        record := &candidate.records[candidate_index]
        old_index, old_found := old_indexes[record.id]
        if !old_found do continue
        old_record := &frozen.records[old_index]
        for field in record.fields {
            old_field_index, field_found := schema_diff_field_index(old_record, field.name)
            if !field_found || old_record.fields[old_field_index].type != field.type {
                schema_diff_mark_type_refs(field.type, &candidate, old_indexes, new_indexes, &supporting, limits, 0)
            }
        }
    }
    for frozen_index := 0; frozen_index < len(frozen.records); frozen_index += 1 {
        record := &frozen.records[frozen_index]
        if _, found := new_indexes[record.id]; !found {
            body, body_ok := schema_diff_record_body(record, allocator)
            if !body_ok ||
               !schema_diff_append_change(
                       &report,
                       &error,
                       .Type_Remove,
                       .State,
                       .Script_Required,
                       record.id,
                       body,
                       "",
                   ) {
                if !body_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, 0, record.id, "cannot build removed type body", allocator)
                if body_ok do delete(body, allocator)
                schema_diff_report_dispose(&report)
                return {}, error, false
            }
            delete(body, allocator)
        }
    }
    for candidate_index := 0; candidate_index < len(candidate.records); candidate_index += 1 {
        record := &candidate.records[candidate_index]
        if _, found := old_indexes[record.id]; !found {
            body, body_ok := schema_diff_record_body(record, allocator)
            class := Schema_Diff_Class(.State)
            policy := Schema_Diff_Policy(.Script_Required)
            if supporting[record.id] {
                class = .Supporting
                policy = .Automatic
            }
            if !body_ok || !schema_diff_append_change(&report, &error, .Type_Add, class, policy, record.id, "", body) {
                if !body_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, 0, record.id, "cannot build added type body", allocator)
                if body_ok do delete(body, allocator)
                schema_diff_report_dispose(&report)
                return {}, error, false
            }
            delete(body, allocator)
        }
    }
    if frozen.root != candidate.root {
        if !schema_diff_append_change(
            &report,
            &error,
            .Root,
            .State,
            .Script_Required,
            "root",
            frozen.root,
            candidate.root,
        ) {
            schema_diff_report_dispose(&report)
            return {}, error, false
        }
    }
    for frozen_index := 0; frozen_index < len(frozen.records); frozen_index += 1 {
        record := &frozen.records[frozen_index]
        old_record_index := old_indexes[record.id]
        new_record_index, new_found := new_indexes[record.id]
        if !new_found do continue
        old_record := &frozen.records[old_record_index]
        new_record := &candidate.records[new_record_index]
        if old_record.kind != new_record.kind {
            if !schema_diff_append_change(
                &report,
                &error,
                .Type_Kind,
                .State,
                .Script_Required,
                record.id,
                old_record.kind,
                new_record.kind,
            ) {
                schema_diff_report_dispose(&report)
                return {}, error, false
            }
            continue
        }
        if old_record.detail != new_record.detail {
            if !schema_diff_append_change(
                &report,
                &error,
                .Type_Detail,
                .State,
                .Script_Required,
                record.id,
                old_record.detail,
                new_record.detail,
            ) {
                schema_diff_report_dispose(&report)
                return {}, error, false
            }
        }
        if record.kind == "struct" {
            for old_field_index := 0; old_field_index < len(old_record.fields); old_field_index += 1 {
                old_field := &old_record.fields[old_field_index]
                new_field_index, new_field_found := schema_diff_field_index(new_record, old_field.name)
                if !new_field_found {
                    body, body_ok := schema_diff_field_body(old_field, allocator)
                    path, path_ok := schema_diff_path(record.id, old_field.name, allocator)
                    change_ok :=
                        body_ok &&
                        path_ok &&
                        schema_diff_append_change(
                            &report,
                            &error,
                            .Field_Remove,
                            .State,
                            .Script_Required,
                            path,
                            body,
                            "",
                        )
                    if body_ok do delete(body, allocator)
                    if path_ok do delete(path, allocator)
                    if !change_ok {
                        if !body_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, old_field.line, record.id, "cannot build removed field body", allocator)
                        if !path_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, old_field.line, record.id, "cannot build removed field path", allocator)
                        schema_diff_report_dispose(&report)
                        return {}, error, false
                    }
                    continue
                }
                new_field := &new_record.fields[new_field_index]
                path, path_ok := schema_diff_path(record.id, old_field.name, allocator)
                if !path_ok {
                    schema_diff_fail(&error, .Out_Of_Memory, 0, record.id, "cannot own field path", allocator)
                    schema_diff_report_dispose(&report)
                    return {}, error, false
                }
                if old_field.type != new_field.type {
                    if !schema_diff_append_change(
                        &report,
                        &error,
                        .Field_Type,
                        .State,
                        .Script_Required,
                        path,
                        old_field.type,
                        new_field.type,
                    ) {
                        delete(path, allocator)
                        schema_diff_report_dispose(&report)
                        return {}, error, false
                    }
                }
                if old_field.tag != new_field.tag {
                    if !schema_diff_append_change(
                        &report,
                        &error,
                        .Field_Tag,
                        .State,
                        .Script_Required,
                        path,
                        old_field.tag,
                        new_field.tag,
                    ) {
                        delete(path, allocator)
                        schema_diff_report_dispose(&report)
                        return {}, error, false
                    }
                }
                if old_field.is_using != new_field.is_using {
                    before := old_field.is_using ? "1" : "0"
                    after := new_field.is_using ? "1" : "0"
                    if !schema_diff_append_change(
                        &report,
                        &error,
                        .Field_Using,
                        .State,
                        .Script_Required,
                        path,
                        before,
                        after,
                    ) {
                        delete(path, allocator)
                        schema_diff_report_dispose(&report)
                        return {}, error, false
                    }
                }
                delete(path, allocator)
            }
            for new_field_index := 0; new_field_index < len(new_record.fields); new_field_index += 1 {
                new_field := &new_record.fields[new_field_index]
                if _, found := schema_diff_field_index(old_record, new_field.name); found do continue
                body, body_ok := schema_diff_field_body(new_field, allocator)
                path, path_ok := schema_diff_path(record.id, new_field.name, allocator)
                change_ok :=
                    body_ok &&
                    path_ok &&
                    schema_diff_append_change(&report, &error, .Field_Add, .State, .Script_Required, path, "", body)
                if body_ok do delete(body, allocator)
                if path_ok do delete(path, allocator)
                if !change_ok {
                    if !body_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, new_field.line, record.id, "cannot build added field body", allocator)
                    if !path_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, new_field.line, record.id, "cannot build added field path", allocator)
                    schema_diff_report_dispose(&report)
                    return {}, error, false
                }
            }
            if len(old_record.fields) == len(new_record.fields) {
                order_same := true
                for index := 0; index < len(old_record.fields); index += 1 {
                    if old_record.fields[index].name != new_record.fields[index].name {
                        order_same = false
                        break
                    }
                }
                if !order_same {
                    before, before_ok := schema_diff_field_names(old_record, allocator)
                    after, after_ok := schema_diff_field_names(new_record, allocator)
                    if !before_ok ||
                       !after_ok ||
                       !schema_diff_append_change(
                               &report,
                               &error,
                               .Field_Order,
                               .State,
                               .Script_Required,
                               record.id,
                               before,
                               after,
                           ) {
                        if !before_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, record.line, record.id, "cannot build old field order", allocator)
                        if !after_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, record.line, record.id, "cannot build new field order", allocator)
                        if before_ok do delete(before, allocator)
                        if after_ok do delete(after, allocator)
                        schema_diff_report_dispose(&report)
                        return {}, error, false
                    }
                    delete(before, allocator)
                    delete(after, allocator)
                }
            }
        } else if record.kind == "enum" {
            for old_entry_index := 0; old_entry_index < len(old_record.enums); old_entry_index += 1 {
                old_entry := &old_record.enums[old_entry_index]
                new_entry_index, new_entry_found := schema_diff_enum_index(new_record, old_entry.name)
                path, path_ok := schema_diff_path(record.id, old_entry.name, allocator)
                if !path_ok {
                    schema_diff_fail(&error, .Out_Of_Memory, 0, record.id, "cannot own enum path", allocator)
                    schema_diff_report_dispose(&report)
                    return {}, error, false
                }
                if !new_entry_found {
                    before, before_ok := schema_diff_enum_value_text(old_entry.value, allocator)
                    change_ok :=
                        before_ok &&
                        schema_diff_append_change(
                            &report,
                            &error,
                            .Enum_Remove,
                            .State,
                            .Script_Required,
                            path,
                            before,
                            "",
                        )
                    if before_ok do delete(before, allocator)
                    if !change_ok {
                        if !before_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, old_entry.line, record.id, "cannot build removed enum value", allocator)
                        delete(path, allocator)
                        schema_diff_report_dispose(&report)
                        return {}, error, false
                    }
                } else if old_entry.value != new_record.enums[new_entry_index].value {
                    before, before_ok := schema_diff_enum_value_text(old_entry.value, allocator)
                    after, after_ok := schema_diff_enum_value_text(new_record.enums[new_entry_index].value, allocator)
                    change_ok :=
                        before_ok &&
                        after_ok &&
                        schema_diff_append_change(
                            &report,
                            &error,
                            .Enum_Value,
                            .State,
                            .Script_Required,
                            path,
                            before,
                            after,
                        )
                    if before_ok do delete(before, allocator)
                    if after_ok do delete(after, allocator)
                    if !change_ok {
                        if !before_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, old_entry.line, record.id, "cannot build old enum value", allocator)
                        if !after_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, old_entry.line, record.id, "cannot build new enum value", allocator)
                        delete(path, allocator)
                        schema_diff_report_dispose(&report)
                        return {}, error, false
                    }
                }
                delete(path, allocator)
            }
            for new_entry_index := 0; new_entry_index < len(new_record.enums); new_entry_index += 1 {
                new_entry := &new_record.enums[new_entry_index]
                if _, found := schema_diff_enum_index(old_record, new_entry.name); found do continue
                after, after_ok := schema_diff_enum_value_text(new_entry.value, allocator)
                path, path_ok := schema_diff_path(record.id, new_entry.name, allocator)
                change_ok :=
                    after_ok &&
                    path_ok &&
                    schema_diff_append_change(&report, &error, .Enum_Add, .State, .Script_Required, path, "", after)
                if after_ok do delete(after, allocator)
                if path_ok do delete(path, allocator)
                if !change_ok {
                    if !after_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, new_entry.line, record.id, "cannot build added enum value", allocator)
                    if !path_ok do schema_diff_fail_if_none(&error, .Out_Of_Memory, new_entry.line, record.id, "cannot build added enum path", allocator)
                    schema_diff_report_dispose(&report)
                    return {}, error, false
                }
            }
        }
    }
    if !schema_diff_validate_change_ids(&report, &error) {
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    return report, error, true
}

schema_diff_write_escaped :: proc(builder: ^strings.Builder, value: string) {
    for ch in value {
        switch ch {
        case '\\':
            strings.write_string(builder, "\\\\")
        case '\t':
            strings.write_string(builder, "\\t")
        case '\n':
            strings.write_string(builder, "\\n")
        case '=':
            strings.write_string(builder, "\\=")
        case '|':
            strings.write_string(builder, "\\|")
        case:
            strings.write_rune(builder, ch)
        }
    }
}

schema_diff_report_counts :: proc(report: ^Schema_Diff_Report) -> (int, int) {
    state := 0
    supporting := 0
    for change in report.changes {
        if change.class == .State {
            state += 1
        } else {
            supporting += 1
        }
    }
    return state, supporting
}

schema_diff_report_render :: proc(report: ^Schema_Diff_Report, allocator: mem.Allocator) -> (string, bool) {
    if report == nil || !schema_diff_allocator_valid(allocator) || !schema_diff_allocator_valid(report.allocator) do return "", false
    validation_error: Schema_Diff_Error
    if !schema_diff_report_validate(report, &validation_error) {
        schema_diff_error_dispose(&validation_error)
        return "", false
    }
    schema_diff_error_dispose(&validation_error)
    capacity := 1024
    for change in report.changes {
        if len(change.id) > SCHEMA_DIFF_MAX_BUILDER_BYTES / 2 ||
           len(change.path) > SCHEMA_DIFF_MAX_BUILDER_BYTES / 2 ||
           len(change.before) > SCHEMA_DIFF_MAX_BUILDER_BYTES / 2 ||
           len(change.after) > SCHEMA_DIFF_MAX_BUILDER_BYTES / 2 {
            return "", false
        }
        if !schema_diff_builder_capacity_add(&capacity, 256) ||
           !schema_diff_builder_capacity_add(&capacity, len(change.id) * 2) ||
           !schema_diff_builder_capacity_add(&capacity, len(change.path) * 2) ||
           !schema_diff_builder_capacity_add(&capacity, len(change.before) * 2) ||
           !schema_diff_builder_capacity_add(&capacity, len(change.after) * 2) {
            return "", false
        }
    }
    state_count, supporting_count := schema_diff_report_counts(report)
    builder, builder_ok := schema_diff_builder_make(capacity, allocator)
    if !builder_ok do return "", false
    fmt.sbprintf(&builder, "schema_diff_format_version=1\n")
    fmt.sbprintf(&builder, "from_version=%d\n", report.from_version)
    fmt.sbprintf(&builder, "to_version=%d\n", report.to_version)
    fmt.sbprintf(&builder, "frozen_schema_sha256=%s\n", report.frozen_sha256)
    fmt.sbprintf(&builder, "candidate_schema_sha256=%s\n", report.candidate_sha256)
    fmt.sbprintf(&builder, "candidate_line_count=%d\n", report.candidate_line_count)
    fmt.sbprintf(&builder, "candidate_record_count=%d\n", report.candidate_record_count)
    fmt.sbprintf(&builder, "candidate_root_fields=%d\n", report.candidate_root_fields)
    fmt.sbprintf(&builder, "change_count=%d\n", len(report.changes))
    fmt.sbprintf(&builder, "state_change_count=%d\n", state_count)
    fmt.sbprintf(&builder, "supporting_change_count=%d\n", supporting_count)
    for change in report.changes {
        strings.write_string(&builder, "change=")
        schema_diff_write_escaped(&builder, change.id)
        fmt.sbprintf(
            &builder,
            "|kind=%s|class=%s|policy=%s|path=",
            schema_diff_kind_text(change.kind),
            schema_diff_class_text(change.class),
            schema_diff_policy_text(change.policy),
        )
        schema_diff_write_escaped(&builder, change.path)
        strings.write_string(&builder, "|before=")
        schema_diff_write_escaped(&builder, change.before)
        strings.write_string(&builder, "|after=")
        schema_diff_write_escaped(&builder, change.after)
        strings.write_byte(&builder, '\n')
    }
    return strings.to_string(builder), true
}

schema_diff_report_parse_owned :: proc(raw: string, allocator: mem.Allocator) -> (string, History_Unescape_Result) {
    return schema_diff_unescape(raw, allocator)
}

schema_diff_report_parse_integer :: proc(text: string, allow_zero: bool) -> (int, bool) {
    if !history_is_digits(text, false) do return 0, false
    value, ok := strconv.parse_i64(text)
    if !ok || value < 0 || !allow_zero && value == 0 || value > i64(1) << 62 do return 0, false
    return int(value), true
}

schema_diff_report_header_dispose :: proc(values: ^[11]string, owned: ^[11]bool, allocator: mem.Allocator) {
    for index := 0; index < len(values^); index += 1 {
        if owned^[index] {
            delete(values^[index], allocator)
            owned^[index] = false
        }
    }
}

schema_diff_change_id_matches :: proc(change: ^Schema_Diff_Change) -> bool {
    if change == nil do return false
    kind_text := schema_diff_kind_text(change.kind)
    prefix_length := len(kind_text) + 1
    if kind_text == "" || len(change.id) < prefix_length do return false
    if change.id[:len(kind_text)] != kind_text || change.id[len(kind_text)] != ':' do return false
    return change.id[prefix_length:] == change.path
}

schema_diff_change_shape_valid :: proc(change: ^Schema_Diff_Change) -> bool {
    if change == nil || !schema_diff_kind_valid(change.kind) || !schema_diff_change_id_matches(change) do return false
    switch change.kind {
    case .Type_Add, .Field_Add, .Enum_Add:
        if len(change.before) != 0 || len(change.after) == 0 do return false
    case .Type_Remove, .Field_Remove, .Enum_Remove:
        if len(change.before) == 0 || len(change.after) != 0 do return false
    case .Field_Using:
        if (change.before != "0" && change.before != "1") || (change.after != "0" && change.after != "1") do return false
    case .Field_Tag:
        return true
    case .Root, .Type_Kind, .Type_Detail, .Field_Type, .Field_Order, .Enum_Value:
        if len(change.before) == 0 || len(change.after) == 0 do return false
    case:
        return false
    }
    return true
}

schema_diff_report_validate :: proc(report: ^Schema_Diff_Report, error: ^Schema_Diff_Error) -> bool {
    if report == nil || error == nil || !schema_diff_allocator_valid(report.allocator) do return false
    if report.format_version != SCHEMA_DIFF_FORMAT_VERSION ||
       !history_schema_version_supported(report.from_version) ||
       !history_schema_version_supported(report.to_version) ||
       report.to_version != report.from_version + 1 ||
       !history_is_hex_sha256(report.frozen_sha256) ||
       !history_is_hex_sha256(report.candidate_sha256) ||
       report.candidate_line_count < 0 ||
       report.candidate_record_count < 0 ||
       report.candidate_root_fields < 0 {
        schema_diff_fail(error, .Invalid_Input, 1, "$", "schema diff report header is invalid", report.allocator)
        return false
    }
    state_count, supporting_count := schema_diff_report_counts(report)
    for index := 0; index < len(report.changes); index += 1 {
        change := &report.changes[index]
        if index > 0 && strings.compare(report.changes[index - 1].id, change.id) >= 0 {
            schema_diff_fail(
                error,
                .Invalid_Input,
                index + 1,
                change.id,
                "schema changes are not strictly sorted",
                report.allocator,
            )
            return false
        }
        if !schema_diff_kind_valid(change.kind) ||
           !schema_diff_class_valid(change.class) ||
           !schema_diff_policy_valid(change.policy) {
            schema_diff_fail(
                error,
                .Invalid_Input,
                index + 1,
                change.id,
                "schema change discriminant is invalid",
                report.allocator,
            )
            return false
        }
        if !schema_diff_change_shape_valid(change) {
            schema_diff_fail(
                error,
                .Invalid_Input,
                index + 1,
                change.id,
                "schema change is contradictory or malformed",
                report.allocator,
            )
            return false
        }
        if change.class == .Supporting {
            if change.policy != .Automatic || change.kind != .Type_Add {
                schema_diff_fail(
                    error,
                    .Invalid_Input,
                    index + 1,
                    change.id,
                    "supporting change policy is invalid",
                    report.allocator,
                )
                return false
            }
        } else if change.policy != .Script_Required {
            schema_diff_fail(
                error,
                .Invalid_Input,
                index + 1,
                change.id,
                "state change policy is invalid",
                report.allocator,
            )
            return false
        }
    }
    if state_count + supporting_count != len(report.changes) {
        schema_diff_fail(error, .Invalid_Input, 1, "$", "schema diff change counts are invalid", report.allocator)
        return false
    }
    return true
}

schema_diff_report_parse :: proc(
    data: []byte,
    allocator: mem.Allocator,
    limits := SCHEMA_DIFF_DEFAULT_LIMITS,
) -> (
    report: Schema_Diff_Report,
    error: Schema_Diff_Error,
    ok: bool,
) {
    report.allocator = allocator
    if !schema_diff_allocator_valid(allocator) {
        error = Schema_Diff_Error {
            kind    = .Out_Of_Memory,
            line    = 1,
            path    = "$",
            message = "schema diff report allocator is invalid",
        }
        return {}, error, false
    }
    if len(data) == 0 || len(data) > limits.max_bytes {
        schema_diff_fail(&error, .Limit_Exceeded, 1, "$", "schema diff report byte limit exceeded", allocator)
        return {}, error, false
    }
    if data[len(data) - 1] != '\n' {
        schema_diff_fail(&error, .Invalid_Input, 1, "$", "schema diff report must end with newline", allocator)
        return {}, error, false
    }
    cursor := 0
    line_number := 0
    header_values: [11]string
    header_owned: [11]bool
    for header_index := 0; header_index < len(header_values); header_index += 1 {
        line, line_ok := history_next_line(data, &cursor)
        line_number += 1
        if !line_ok {
            schema_diff_fail(
                &error,
                .Invalid_Input,
                line_number,
                "$",
                "schema diff report header is truncated",
                allocator,
            )
            schema_diff_report_header_dispose(&header_values, &header_owned, allocator)
            schema_diff_report_dispose(&report)
            return {}, error, false
        }
        pairs, pair_count, pairs_ok := history_parse_key_values(line, '|')
        if !pairs_ok || pair_count != 1 {
            schema_diff_fail(
                &error,
                .Invalid_Input,
                line_number,
                "$",
                "schema diff report header line is malformed",
                allocator,
            )
            schema_diff_report_header_dispose(&header_values, &header_owned, allocator)
            schema_diff_report_dispose(&report)
            return {}, error, false
        }
        expected_key := ""
        switch header_index {
        case 0:
            expected_key = "schema_diff_format_version"
        case 1:
            expected_key = "from_version"
        case 2:
            expected_key = "to_version"
        case 3:
            expected_key = "frozen_schema_sha256"
        case 4:
            expected_key = "candidate_schema_sha256"
        case 5:
            expected_key = "candidate_line_count"
        case 6:
            expected_key = "candidate_record_count"
        case 7:
            expected_key = "candidate_root_fields"
        case 8:
            expected_key = "change_count"
        case 9:
            expected_key = "state_change_count"
        case 10:
            expected_key = "supporting_change_count"
        }
        if pairs[0].key != expected_key {
            schema_diff_fail(
                &error,
                .Invalid_Input,
                line_number,
                "$",
                "schema diff report header key is missing or reordered",
                allocator,
            )
            schema_diff_report_header_dispose(&header_values, &header_owned, allocator)
            schema_diff_report_dispose(&report)
            return {}, error, false
        }
        value, status := schema_diff_report_parse_owned(pairs[0].value, allocator)
        if status != .Ok {
            failure_kind := Schema_Diff_Error_Kind(.Invalid_Input)
            if status == .Out_Of_Memory do failure_kind = .Out_Of_Memory
            schema_diff_fail(
                &error,
                failure_kind,
                line_number,
                expected_key,
                "schema diff report value escaping is invalid",
                allocator,
            )
            schema_diff_report_header_dispose(&header_values, &header_owned, allocator)
            schema_diff_report_dispose(&report)
            return {}, error, false
        }
        header_values[header_index] = value
        header_owned[header_index] = true
    }
    format_version, format_ok := schema_diff_report_parse_integer(header_values[0], true)
    from_version, from_ok := schema_diff_parse_positive(header_values[1])
    to_version, to_ok := schema_diff_parse_positive(header_values[2])
    candidate_line_count, line_count_ok := schema_diff_report_parse_integer(header_values[5], true)
    candidate_record_count, record_count_ok := schema_diff_report_parse_integer(header_values[6], true)
    candidate_root_fields, root_fields_ok := schema_diff_report_parse_integer(header_values[7], true)
    change_count, change_count_ok := schema_diff_report_parse_integer(header_values[8], true)
    state_count, state_count_ok := schema_diff_report_parse_integer(header_values[9], true)
    supporting_count, supporting_count_ok := schema_diff_report_parse_integer(header_values[10], true)
    if !format_ok ||
       format_version != SCHEMA_DIFF_FORMAT_VERSION ||
       !from_ok ||
       !to_ok ||
       to_version != from_version + 1 ||
       !history_is_hex_sha256(header_values[3]) ||
       !history_is_hex_sha256(header_values[4]) ||
       !line_count_ok ||
       !record_count_ok ||
       !root_fields_ok ||
       !change_count_ok ||
       !state_count_ok ||
       !supporting_count_ok ||
       change_count > limits.max_lines - 11 {
        schema_diff_fail(&error, .Invalid_Input, 1, "$", "schema diff report header values are invalid", allocator)
        schema_diff_report_header_dispose(&header_values, &header_owned, allocator)
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    report.format_version = format_version
    report.from_version = from_version
    report.to_version = to_version
    report.frozen_sha256 = header_values[3]
    report.candidate_sha256 = header_values[4]
    report.candidate_line_count = candidate_line_count
    report.candidate_record_count = candidate_record_count
    report.candidate_root_fields = candidate_root_fields
    header_owned[3] = false
    header_owned[4] = false
    for index := 0; index < 3; index += 1 do delete(header_values[index], allocator)
    for index := 5; index < len(header_values); index += 1 do delete(header_values[index], allocator)
    changes, changes_error := make([dynamic]Schema_Diff_Change, 0, change_count, allocator)
    if changes_error != nil {
        schema_diff_fail(&error, .Out_Of_Memory, 1, "$", "cannot allocate schema diff changes", allocator)
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    report.changes = changes
    for change_index := 0; change_index < change_count; change_index += 1 {
        line, line_ok := history_next_line(data, &cursor)
        line_number += 1
        pairs, pair_count, pairs_ok := history_parse_key_values(line, '|')
        if !line_ok ||
           !pairs_ok ||
           pair_count != 7 ||
           pairs[0].key != "change" ||
           pairs[1].key != "kind" ||
           pairs[2].key != "class" ||
           pairs[3].key != "policy" ||
           pairs[4].key != "path" ||
           pairs[5].key != "before" ||
           pairs[6].key != "after" {
            schema_diff_fail(
                &error,
                .Invalid_Input,
                line_number,
                "$",
                "schema diff change line keys are invalid",
                allocator,
            )
            schema_diff_report_dispose(&report)
            return {}, error, false
        }
        kind, kind_ok := schema_diff_kind_from_text(pairs[1].value)
        class, class_ok := schema_diff_class_from_text(pairs[2].value)
        policy, policy_ok := schema_diff_policy_from_text(pairs[3].value)
        values: [4]string
        owned: [4]bool
        raws := [4]string{pairs[0].value, pairs[4].value, pairs[5].value, pairs[6].value}
        values_ok := true
        values_out_of_memory := false
        for value_index := 0; value_index < len(values); value_index += 1 {
            value, status := schema_diff_report_parse_owned(raws[value_index], allocator)
            if status != .Ok {
                values_ok = false
                if status == .Out_Of_Memory do values_out_of_memory = true
                break
            }
            values[value_index] = value
            owned[value_index] = true
        }
        if !kind_ok || !class_ok || !policy_ok || !values_ok {
            for value_index := 0; value_index < len(values); value_index += 1 {
                if owned[value_index] do delete(values[value_index], allocator)
            }
            schema_diff_fail(
                &error,
                values_out_of_memory ? .Out_Of_Memory : .Invalid_Input,
                line_number,
                "$",
                "schema diff change value is invalid",
                allocator,
            )
            schema_diff_report_dispose(&report)
            return {}, error, false
        }
        change := Schema_Diff_Change {
            id     = values[0],
            kind   = kind,
            class  = class,
            policy = policy,
            path   = values[1],
            before = values[2],
            after  = values[3],
        }
        appended, append_error := append_elem(&report.changes, change)
        if append_error != nil || appended != 1 {
            schema_diff_change_dispose(&change, allocator)
            schema_diff_fail(&error, .Out_Of_Memory, line_number, "$", "cannot append schema diff change", allocator)
            schema_diff_report_dispose(&report)
            return {}, error, false
        }
    }
    if cursor != len(data) || len(report.changes) != change_count {
        schema_diff_fail(
            &error,
            .Invalid_Input,
            line_number,
            "$",
            "schema diff report has trailing or missing changes",
            allocator,
        )
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    actual_state_count, actual_supporting_count := schema_diff_report_counts(&report)
    if state_count != actual_state_count || supporting_count != actual_supporting_count {
        schema_diff_fail(&error, .Invalid_Input, 1, "$", "schema diff report counts do not match changes", allocator)
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    if !schema_diff_report_validate(&report, &error) {
        schema_diff_report_dispose(&report)
        return {}, error, false
    }
    return report, error, true
}
