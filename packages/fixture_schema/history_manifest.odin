package fixture_schema

import "core:mem"
import "core:strconv"
import "core:strings"

HISTORY_MANIFEST_MAX_BYTES :: 8 * 1024 * 1024
HISTORY_MANIFEST_MAX_LINES :: 8192
HISTORY_MANIFEST_MAX_RECORDS :: 512
HISTORY_MANIFEST_MAX_FIELDS :: 65536
HISTORY_MANIFEST_MAX_ENUMS :: 65536
HISTORY_MANIFEST_MAX_IDENTIFIER_BYTES :: 256
HISTORY_MANIFEST_MAX_TYPE_DEPTH :: 64
HISTORY_MANIFEST_MAX_ARRAY_LENGTH :: 16 * 1024 * 1024

HISTORY_SUPPORTED_FORMAT_VERSION :: 1
HISTORY_SUPPORTED_SCHEMA_VERSION_MIN :: 1
HISTORY_SUPPORTED_SCHEMA_VERSION_MAX :: 9999
HISTORY_SUPPORTED_SCHEMA_VERSION :: HISTORY_SUPPORTED_SCHEMA_VERSION_MIN

History_Error_Kind :: enum {
    None,
    Invalid_Input,
    Limit_Exceeded,
    Out_Of_Memory,
    Unresolved_Reference,
    Unreachable_Record,
}

History_Error :: struct {
    kind:          History_Error_Kind,
    line:          int,
    path:          string,
    message:       string,
    path_owned:    bool,
    message_owned: bool,
    allocator:     mem.Allocator,
}

History_Field :: struct {
    name:     string,
    tag:      string,
    type:     string,
    is_using: bool,
    line:     int,
}

History_Enum :: struct {
    name:  string,
    value: i64,
    line:  int,
}

History_Record :: struct {
    id:     string,
    kind:   string,
    detail: string,
    line:   int,
    fields: [dynamic]History_Field,
    enums:  [dynamic]History_Enum,
}

History_Manifest :: struct {
    allocator:      mem.Allocator,
    format_version: int,
    schema_version: int,
    root:           string,
    records:        [dynamic]History_Record,
}

History_Pair :: struct {
    key:   string,
    value: string,
}

history_allocator_valid :: proc(allocator: mem.Allocator) -> bool {
    return allocator.procedure != nil
}

history_error_dispose :: proc(error: ^History_Error) {
    if error == nil do return
    if error.path_owned {
        delete(error.path, error.allocator)
    }
    if error.message_owned {
        delete(error.message, error.allocator)
    }
    error^ = {}
}

history_record_dispose :: proc(record: ^History_Record, allocator: mem.Allocator) {
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

history_manifest_dispose :: proc(manifest: ^History_Manifest) {
    if manifest == nil do return
    for &record in manifest.records {
        history_record_dispose(&record, manifest.allocator)
    }
    delete(manifest.records)
    delete(manifest.root, manifest.allocator)
    manifest^ = {}
}

history_make_error :: proc(
    kind: History_Error_Kind,
    line: int,
    path, message: string,
    allocator: mem.Allocator,
) -> History_Error {
    error := History_Error {
        kind      = kind,
        line      = line,
        path      = "$",
        message   = message,
        allocator = allocator,
    }
    if owned_path, path_error := strings.clone(path, allocator); path_error == nil {
        error.path = owned_path
        error.path_owned = true
    }
    if owned_message, message_error := strings.clone(message, allocator); message_error == nil {
        error.message = owned_message
        error.message_owned = true
    }
    return error
}

history_fail :: proc(
    error: ^History_Error,
    kind: History_Error_Kind,
    line: int,
    path, message: string,
    allocator: mem.Allocator,
) {
    if error.kind == .None {
        error^ = history_make_error(kind, line, path, message, allocator)
    }
}

history_is_identifier_start :: proc(ch: byte) -> bool {
    return ch == '_' || ch >= 'a' && ch <= 'z' || ch >= 'A' && ch <= 'Z'
}

history_is_identifier_continue :: proc(ch: byte) -> bool {
    return history_is_identifier_start(ch) || ch >= '0' && ch <= '9'
}

history_is_reserved_identifier :: proc(name: string) -> bool {
    switch name {
    case "as",
         "asm",
         "auto_cast",
         "bit_field",
         "bit_set",
         "break",
         "case",
         "cast",
         "context",
         "continue",
         "defer",
         "distinct",
         "do",
         "dynamic",
         "else",
         "enum",
         "fallthrough",
         "for",
         "foreign",
         "if",
         "ignore_nil",
         "import",
         "in",
         "map",
         "matrix",
         "not_in",
         "or_else",
         "or_return",
         "package",
         "proc",
         "return",
         "struct",
         "switch",
         "transmute",
         "typeid",
         "union",
         "using",
         "when",
         "where":
        return true
    }
    return false
}

history_is_identifier :: proc(name: string) -> bool {
    if len(name) == 0 || len(name) > HISTORY_MANIFEST_MAX_IDENTIFIER_BYTES do return false
    if !history_is_identifier_start(name[0]) do return false
    for index := 1; index < len(name); index += 1 {
        ch := name[index]
        if !history_is_identifier_continue(ch) do return false
    }
    return !history_is_reserved_identifier(name)
}

history_is_logical_id :: proc(id: string) -> bool {
    if len(id) == 0 || len(id) > HISTORY_MANIFEST_MAX_IDENTIFIER_BYTES do return false
    last_dot := -1
    colon_count := 0
    for index := 0; index < len(id); index += 1 {
        ch := id[index]
        if ch == '.' {
            last_dot = index
            continue
        }
        if ch == ':' {
            colon_count += 1
            continue
        }
        if ch == '\\' || ch == ';' || ch == '=' || ch == '|' || ch == '\r' || ch == '\n' || ch == '\t' {
            return false
        }
        if !(history_is_identifier_continue(ch) || ch == '/' || ch == '-') {
            return false
        }
    }
    if colon_count != 1 || last_dot <= 0 || last_dot + 1 >= len(id) do return false
    colon := strings.index_byte(id, ':')
    if colon <= 0 || colon + 1 >= last_dot do return false
    if id[colon + 1] == '/' || id[last_dot - 1] == '/' do return false
    if strings.contains(id, "..") || strings.contains(id, "//") do return false
    return history_is_identifier(id[last_dot + 1:])
}

History_Scalar_Kind :: enum {
    Invalid,
    Bool,
    Signed,
    Unsigned,
    Rune,
    Float,
    Quaternion,
    String,
}

History_Scalar :: struct {
    kind:   History_Scalar_Kind,
    width:  int,
    signed: bool,
}

history_scalar :: proc(name: string) -> History_Scalar {
    switch name {
    case "bool", "b8":
        return {kind = .Bool, width = 1}
    case "i8":
        return {kind = .Signed, width = 1, signed = true}
    case "i16":
        return {kind = .Signed, width = 2, signed = true}
    case "i32":
        return {kind = .Signed, width = 4, signed = true}
    case "i64":
        return {kind = .Signed, width = 8, signed = true}
    case "int":
        width := size_of(int)
        if width == 4 || width == 8 do return {kind = .Signed, width = width, signed = true}
    case "u8", "byte", "rawbyte":
        return {kind = .Unsigned, width = 1}
    case "u16":
        return {kind = .Unsigned, width = 2}
    case "u32":
        return {kind = .Unsigned, width = 4}
    case "u64":
        return {kind = .Unsigned, width = 8}
    case "uint", "uintptr":
        width := size_of(uint)
        if width == 4 || width == 8 do return {kind = .Unsigned, width = width}
    case "rune":
        return {kind = .Rune, width = 4, signed = true}
    case "f16":
        return {kind = .Float, width = 2}
    case "f32":
        return {kind = .Float, width = 4}
    case "f64":
        return {kind = .Float, width = 8}
    case "quaternion64":
        return {kind = .Quaternion, width = 8}
    case "quaternion128":
        return {kind = .Quaternion, width = 16}
    case "string":
        return {kind = .String}
    }
    return {}
}

history_is_integer_builtin :: proc(name: string) -> bool {
    scalar := history_scalar(name)
    return scalar.kind == .Signed || scalar.kind == .Unsigned || scalar.kind == .Rune
}

history_is_builtin :: proc(name: string) -> bool {
    return history_scalar(name).kind != .Invalid
}

history_parse_key_values :: proc(text: string, delimiter: byte) -> (pairs: [8]History_Pair, count: int, ok: bool) {
    if len(text) == 0 do return pairs, 0, false
    start := 0
    for index := 0; index <= len(text); index += 1 {
        at_end := index == len(text)
        if !at_end {
            if text[index] == '\\' {
                index += 1
                if index >= len(text) do return pairs, count, false
                continue
            }
            if text[index] != delimiter do continue
        }
        if index == start || count >= len(pairs) do return pairs, count, false
        segment := text[start:index]
        equal := -1
        for segment_index := 0; segment_index < len(segment); segment_index += 1 {
            switch segment[segment_index] {
            case '\\':
                segment_index += 1
                if segment_index >= len(segment) do return pairs, count, false
            case '=':
                if equal >= 0 do return pairs, count, false
                equal = segment_index
            }
        }
        if equal <= 0 do return pairs, count, false
        pairs[count] = History_Pair {
            key   = segment[:equal],
            value = segment[equal + 1:],
        }
        count += 1
        start = index + 1
    }
    return pairs, count, true
}

History_Unescape_Result :: enum {
    Ok,
    Invalid,
    Out_Of_Memory,
}

history_unescape :: proc(raw: string, allocator: mem.Allocator) -> (string, History_Unescape_Result) {
    if !history_allocator_valid(allocator) do return "", .Out_Of_Memory
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
    builder, err := strings.builder_make_len_cap(0, len(raw), allocator)
    if err != nil do return "", .Out_Of_Memory
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

history_is_digits :: proc(text: string, negative: bool) -> bool {
    if len(text) == 0 do return false
    start := 0
    if negative && text[0] == '-' {
        start = 1
    }
    if start == len(text) do return false
    for index := start; index < len(text); index += 1 {
        ch := text[index]
        if ch < '0' || ch > '9' do return false
    }
    return true
}

history_parse_i64 :: proc(text: string, negative: bool) -> (i64, bool) {
    if !history_is_digits(text, negative) do return 0, false
    value, ok := strconv.parse_i64(text)
    return value, ok
}

history_schema_version_supported :: proc(version: int) -> bool {
    return version >= HISTORY_SUPPORTED_SCHEMA_VERSION_MIN && version <= HISTORY_SUPPORTED_SCHEMA_VERSION_MAX
}

history_parse_schema_version :: proc(text: string) -> (int, bool) {
    if len(text) == 0 || len(text) > 4 || text[0] == '0' do return 0, false
    if !history_is_digits(text, false) do return 0, false
    value, ok := strconv.parse_i64(text)
    if !ok || !history_schema_version_supported(int(value)) {
        return 0, false
    }
    return int(value), true
}

history_parse_bool :: proc(text: string) -> (bool, bool) {
    value, ok := history_parse_i64(text, false)
    if !ok || value < 0 || value > 1 do return false, false
    return value == 1, true
}

history_detail_value :: proc(detail, key: string) -> (string, bool) {
    pairs, count, ok := history_parse_key_values(detail, ';')
    if !ok do return "", false
    for index in 0 ..< count {
        if pairs[index].key == key do return pairs[index].value, true
    }
    return "", false
}

history_detail_is_exact :: proc(detail: string, keys: []string) -> bool {
    pairs, count, ok := history_parse_key_values(detail, ';')
    if !ok || count != len(keys) do return false
    for index := 0; index < len(keys); index += 1 {
        key := keys[index]
        if pairs[index].key != key || len(pairs[index].value) == 0 do return false
    }
    return true
}

history_validate_detail :: proc(kind, detail: string) -> bool {
    switch kind {
    case "struct":
        keys := [?]string {
            "packed",
            "raw_union",
            "no_copy",
            "all_or_none",
            "simple",
            "align",
            "min_field_align",
            "max_field_align",
        }
        if !history_detail_is_exact(detail, keys[:]) do return false
        for key in keys[:5] {
            value, _ := history_detail_value(detail, key)
            if value != "0" do return false
        }
        for key in keys[5:] {
            value, _ := history_detail_value(detail, key)
            if value != "none" do return false
        }
        return true
    case "enum":
        keys := [?]string{"using", "base"}
        if !history_detail_is_exact(detail, keys[:]) do return false
        using_value, _ := history_detail_value(detail, "using")
        using_decl, using_ok := history_parse_bool(using_value)
        base, base_ok := history_detail_value(detail, "base")
        return using_ok && !using_decl && base_ok && len(base) > 0
    case "alias", "distinct":
        keys := [?]string{"target"}
        return history_detail_is_exact(detail, keys[:])
    }
    return false
}

history_enumerated_array_header :: proc(
    expr: string,
    cursor: ^int,
    maximum_length: i64,
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
    if !count_ok || parsed_count <= 0 || parsed_count > maximum_length do return
    cursor^ += 1
    index_start := cursor^
    for cursor^ < len(expr) && expr[cursor^] != ']' {
        cursor^ += 1
    }
    if index_start == cursor^ || cursor^ >= len(expr) || expr[cursor^] != ']' do return
    parsed_index := expr[index_start:cursor^]
    if !history_is_logical_id(parsed_index) do return
    cursor^ += 1
    return parsed_count, parsed_index, true
}

history_enumerated_array_record_valid :: proc(record: ^History_Record, count: i64) -> bool {
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

history_type_node :: proc(
    expr: string,
    cursor: ^int,
    manifest: ^History_Manifest,
    indexes: map[string]int,
    allow_raw_builtin: bool,
    depth: int,
) -> bool {
    if cursor^ >= len(expr) do return false
    if depth > HISTORY_MANIFEST_MAX_TYPE_DEPTH do return false
    if strings.has_prefix(expr[cursor^:], "enumerated_array[") {
        count, index_id, header_ok := history_enumerated_array_header(expr, cursor, HISTORY_MANIFEST_MAX_ARRAY_LENGTH)
        if !header_ok do return false
        index, found := indexes[index_id]
        if !found || !history_enumerated_array_record_valid(&manifest.records[index], count) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '<' do return false
        cursor^ += 1
        if !history_type_node(expr, cursor, manifest, indexes, false, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    if strings.has_prefix(expr[cursor^:], "array[") {
        cursor^ += len("array[")
        length_start := cursor^
        for cursor^ < len(expr) && expr[cursor^] >= '0' && expr[cursor^] <= '9' {
            cursor^ += 1
        }
        if length_start == cursor^ || cursor^ >= len(expr) || expr[cursor^] != ']' do return false
        length, length_ok := history_parse_i64(expr[length_start:cursor^], false)
        if !length_ok || length < 0 || length > HISTORY_MANIFEST_MAX_ARRAY_LENGTH do return false
        cursor^ += 1
        if cursor^ >= len(expr) || expr[cursor^] != '<' do return false
        cursor^ += 1
        if !history_type_node(expr, cursor, manifest, indexes, false, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    if strings.has_prefix(expr[cursor^:], "dynamic<") {
        cursor^ += len("dynamic<")
        if !history_type_node(expr, cursor, manifest, indexes, false, depth + 1) do return false
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
    if allow_raw_builtin && history_is_builtin(atom) {
        return true
    }
    if !history_is_logical_id(atom) do return false
    _, found := indexes[atom]
    return found
}

history_validate_type :: proc(expr: string, manifest: ^History_Manifest, indexes: map[string]int) -> bool {
    cursor := 0
    if !history_type_node(expr, &cursor, manifest, indexes, false, 0) do return false
    return cursor == len(expr)
}

history_validate_base :: proc(expr: string) -> bool {
    if strings.contains(expr, "<") || strings.contains(expr, ">") do return false
    if strings.has_prefix(expr, "builtin:") {
        return history_is_integer_builtin(expr[len("builtin:"):])
    }
    return history_is_integer_builtin(expr)
}

history_enum_bounds :: proc(expr: string) -> (minimum, maximum: i64, ok: bool) {
    name := expr
    if strings.has_prefix(name, "builtin:") {
        name = name[len("builtin:"):]
    }
    scalar := history_scalar(name)
    if scalar.kind != .Signed && scalar.kind != .Unsigned && scalar.kind != .Rune {
        return 0, 0, false
    }
    if scalar.signed {
        switch scalar.width {
        case 1:
            return -128, 127, true
        case 2:
            return -32768, 32767, true
        case 4:
            return -2147483648, 2147483647, true
        case 8:
            return min(i64), max(i64), true
        }
    } else {
        switch scalar.width {
        case 1:
            return 0, 255, true
        case 2:
            return 0, 65535, true
        case 4:
            return 0, 4294967295, true
        case 8:
            return 0, max(i64), true
        }
    }
    return 0, 0, false
}

history_type_has_builtin_prefix :: proc(expr: string) -> bool {
    return strings.contains(expr, "builtin:")
}

history_make_child_path :: proc(parent, child: string, allocator: mem.Allocator) -> (string, bool) {
    parts := [3]string{parent, ".", child}
    path, err := strings.concatenate(parts[:], allocator)
    return path, err == nil
}

history_fail_child :: proc(
    error: ^History_Error,
    kind: History_Error_Kind,
    line: int,
    parent, child, message: string,
    allocator: mem.Allocator,
) {
    path, path_ok := history_make_child_path(parent, child, allocator)
    if !path_ok {
        history_fail(error, .Out_Of_Memory, line, parent, "cannot own error path", allocator)
        return
    }
    history_fail(error, kind, line, path, message, allocator)
    delete(path, allocator)
}

history_fail_optional_child :: proc(
    error: ^History_Error,
    kind: History_Error_Kind,
    line: int,
    parent, child, message: string,
    allocator: mem.Allocator,
    child_available: bool,
) {
    if child_available {
        history_fail_child(error, kind, line, parent, child, message, allocator)
    } else {
        history_fail(error, kind, line, parent, message, allocator)
    }
}

history_using_resolves_to_struct :: proc(
    index: int,
    manifest: ^History_Manifest,
    indexes: map[string]int,
    state: []u8,
) -> bool {
    if index < 0 || index >= len(manifest.records) do return false
    if state[index] == 1 do return false
    if state[index] == 2 do return true
    state[index] = 1
    record := &manifest.records[index]
    switch record.kind {
    case "struct":
        state[index] = 2
        return true
    case "alias":
        target, found := history_detail_value(record.detail, "target")
        if !found || !history_is_logical_id(target) {
            return false
        }
        target_index, target_found := indexes[target]
        if !target_found || !history_using_resolves_to_struct(target_index, manifest, indexes, state) {
            return false
        }
        state[index] = 2
        return true
    }
    return false
}

history_using_field_is_struct :: proc(
    field_type: string,
    manifest: ^History_Manifest,
    indexes: map[string]int,
    state: []u8,
) -> bool {
    if !history_is_logical_id(field_type) do return false
    index, found := indexes[field_type]
    return found && history_using_resolves_to_struct(index, manifest, indexes, state)
}

history_validate_target :: proc(expr: string, manifest: ^History_Manifest, indexes: map[string]int) -> bool {
    cursor := 0
    if !history_type_node(expr, &cursor, manifest, indexes, true, 0) do return false
    return cursor == len(expr)
}

history_record_index :: proc(indexes: map[string]int, id: string) -> (int, bool) {
    index, found := indexes[id]
    return index, found
}

history_visit_type_node :: proc(
    expr: string,
    cursor: ^int,
    manifest: ^History_Manifest,
    indexes: map[string]int,
    state: []u8,
    reachable: []bool,
    depth: int,
) -> bool {
    if cursor^ >= len(expr) do return false
    if depth > HISTORY_MANIFEST_MAX_TYPE_DEPTH do return false
    if strings.has_prefix(expr[cursor^:], "enumerated_array[") {
        count, index_id, header_ok := history_enumerated_array_header(expr, cursor, HISTORY_MANIFEST_MAX_ARRAY_LENGTH)
        if !header_ok do return false
        index, found := history_record_index(indexes, index_id)
        if !found || !history_enumerated_array_record_valid(&manifest.records[index], count) do return false
        if !history_visit_record(index, manifest, indexes, state, reachable) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '<' do return false
        cursor^ += 1
        if !history_visit_type_node(expr, cursor, manifest, indexes, state, reachable, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    if strings.has_prefix(expr[cursor^:], "array[") {
        cursor^ += len("array[")
        length_start := cursor^
        for cursor^ < len(expr) && expr[cursor^] >= '0' && expr[cursor^] <= '9' {
            cursor^ += 1
        }
        if length_start == cursor^ || cursor^ >= len(expr) || expr[cursor^] != ']' do return false
        cursor^ += 1
        if cursor^ >= len(expr) || expr[cursor^] != '<' do return false
        cursor^ += 1
        if !history_visit_type_node(expr, cursor, manifest, indexes, state, reachable, depth + 1) do return false
        if cursor^ >= len(expr) || expr[cursor^] != '>' do return false
        cursor^ += 1
        return true
    }
    if strings.has_prefix(expr[cursor^:], "dynamic<") {
        cursor^ += len("dynamic<")
        if !history_visit_type_node(expr, cursor, manifest, indexes, state, reachable, depth + 1) do return false
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
    if history_is_builtin(atom) do return true
    index, found := history_record_index(indexes, atom)
    if !found do return false
    return history_visit_record(index, manifest, indexes, state, reachable)
}

history_visit_type :: proc(
    expr: string,
    manifest: ^History_Manifest,
    indexes: map[string]int,
    state: []u8,
    reachable: []bool,
) -> bool {
    cursor := 0
    if !history_visit_type_node(expr, &cursor, manifest, indexes, state, reachable, 0) do return false
    return cursor == len(expr)
}

history_visit_record :: proc(
    index: int,
    manifest: ^History_Manifest,
    indexes: map[string]int,
    state: []u8,
    reachable: []bool,
) -> bool {
    if index < 0 || index >= len(manifest.records) do return false
    if state[index] == 1 || state[index] > 2 do return false
    if state[index] == 2 {
        reachable[index] = true
        return true
    }
    state[index] = 1
    reachable[index] = true
    record := &manifest.records[index]
    switch record.kind {
    case "struct":
        for field in record.fields {
            if !history_visit_type(field.type, manifest, indexes, state, reachable) do return false
        }
    case "alias", "distinct":
        target, found := history_detail_value(record.detail, "target")
        if !found do return false
        if !history_visit_type(target, manifest, indexes, state, reachable) do return false
    }
    state[index] = 2
    return true
}

history_validate_manifest :: proc(manifest: ^History_Manifest, error: ^History_Error) -> bool {
    if manifest == nil || error == nil || !history_allocator_valid(manifest.allocator) do return false
    indexes, indexes_error := make(map[string]int, HISTORY_MANIFEST_MAX_RECORDS, manifest.allocator)
    if indexes_error != nil {
        history_fail(error, .Out_Of_Memory, 1, "$", "cannot allocate manifest indexes", manifest.allocator)
        return false
    }
    defer delete(indexes)
    for index := 0; index < len(manifest.records); index += 1 {
        record := manifest.records[index]
        if _, found := indexes[record.id]; found {
            history_fail(error, .Invalid_Input, record.line, record.id, "duplicate type id", manifest.allocator)
            return false
        }
        indexes[record.id] = index
    }
    root_index, root_found := indexes[manifest.root]
    if !root_found {
        history_fail(error, .Unresolved_Reference, 3, manifest.root, "root type is not declared", manifest.allocator)
        return false
    }
    if manifest.records[root_index].kind != "struct" {
        history_fail(error, .Invalid_Input, 3, manifest.root, "root type must be a struct", manifest.allocator)
        return false
    }
    using_state, using_state_error := make([]u8, len(manifest.records), manifest.allocator)
    if using_state_error != nil {
        history_fail(error, .Out_Of_Memory, 1, "$", "cannot allocate using state", manifest.allocator)
        return false
    }
    defer delete(using_state, manifest.allocator)
    for record_index := 0; record_index < len(manifest.records); record_index += 1 {
        record := &manifest.records[record_index]
        switch record.kind {
        case "struct":
            for field in record.fields {
                if !history_validate_type(field.type, manifest, indexes) {
                    kind := History_Error_Kind(.Unresolved_Reference)
                    if history_type_has_builtin_prefix(field.type) {
                        kind = .Invalid_Input
                    }
                    history_fail_child(
                        error,
                        kind,
                        field.line,
                        record.id,
                        field.name,
                        "invalid or unresolved field type",
                        manifest.allocator,
                    )
                    return false
                }
                if field.is_using && !history_using_field_is_struct(field.type, manifest, indexes, using_state) {
                    history_fail_child(
                        error,
                        .Invalid_Input,
                        field.line,
                        record.id,
                        field.name,
                        "using field must embed a struct type",
                        manifest.allocator,
                    )
                    return false
                }
            }
        case "enum":
            base, _ := history_detail_value(record.detail, "base")
            if !history_validate_base(base) {
                history_fail(
                    error,
                    .Invalid_Input,
                    record.line,
                    record.id,
                    "enum base must be an integer type",
                    manifest.allocator,
                )
                return false
            }
            minimum, maximum, bounds_ok := history_enum_bounds(base)
            if !bounds_ok || len(record.enums) == 0 {
                history_fail(
                    error,
                    .Invalid_Input,
                    record.line,
                    record.id,
                    "enum body or base is invalid",
                    manifest.allocator,
                )
                return false
            }
            for entry in record.enums {
                if entry.value < minimum || entry.value > maximum {
                    history_fail_child(
                        error,
                        .Invalid_Input,
                        entry.line,
                        record.id,
                        entry.name,
                        "enum value does not fit its base type",
                        manifest.allocator,
                    )
                    return false
                }
            }
        case "alias", "distinct":
            target, _ := history_detail_value(record.detail, "target")
            if !history_validate_target(target, manifest, indexes) {
                kind := History_Error_Kind(.Unresolved_Reference)
                if history_type_has_builtin_prefix(target) {
                    kind = .Invalid_Input
                }
                history_fail(
                    error,
                    kind,
                    record.line,
                    record.id,
                    "invalid or unresolved named target",
                    manifest.allocator,
                )
                return false
            }
        }
    }
    state, state_error := make([]u8, len(manifest.records), manifest.allocator)
    if state_error != nil {
        history_fail(error, .Out_Of_Memory, 1, "$", "cannot allocate graph state", manifest.allocator)
        return false
    }
    reachable, reachable_error := make([]bool, len(manifest.records), manifest.allocator)
    if reachable_error != nil {
        delete(state, manifest.allocator)
        history_fail(error, .Out_Of_Memory, 1, "$", "cannot allocate reachability state", manifest.allocator)
        return false
    }
    defer delete(state, manifest.allocator)
    defer delete(reachable, manifest.allocator)
    if !history_visit_record(root_index, manifest, indexes, state, reachable) {
        history_fail(
            error,
            .Invalid_Input,
            manifest.records[root_index].line,
            manifest.root,
            "recursive or invalid type graph",
            manifest.allocator,
        )
        return false
    }
    for index := 0; index < len(manifest.records); index += 1 {
        record := manifest.records[index]
        if !reachable[index] {
            history_fail(
                error,
                .Unreachable_Record,
                record.line,
                record.id,
                "record is not reachable from root",
                manifest.allocator,
            )
            return false
        }
    }
    return true
}

history_next_line :: proc(data: []byte, cursor: ^int) -> (string, bool) {
    if cursor^ >= len(data) do return "", false
    start := cursor^
    for cursor^ < len(data) && data[cursor^] != '\n' {
        cursor^ += 1
    }
    if cursor^ >= len(data) do return "", false
    line := string(data[start:cursor^])
    cursor^ += 1
    return line, true
}

history_reject_backslash :: proc(value: string) -> bool {
    return strings.contains(value, "\\")
}

history_parse_manifest :: proc(
    data: []byte,
    allocator: mem.Allocator,
) -> (
    manifest: History_Manifest,
    error: History_Error,
    ok: bool,
) {
    manifest.allocator = allocator
    if !history_allocator_valid(allocator) {
        error = History_Error {
            kind      = .Out_Of_Memory,
            line      = 1,
            path      = "$",
            message   = "manifest allocator is invalid",
            allocator = allocator,
        }
        return {}, error, false
    }
    if len(data) == 0 || len(data) > HISTORY_MANIFEST_MAX_BYTES {
        history_fail(&error, .Limit_Exceeded, 1, "$", "manifest byte limit exceeded", allocator)
        return {}, error, false
    }
    if data[len(data) - 1] != '\n' {
        history_fail(&error, .Invalid_Input, 1, "$", "manifest must end with one newline", allocator)
        return {}, error, false
    }
    records, records_error := make([dynamic]History_Record, allocator)
    if records_error != nil {
        history_fail(&error, .Out_Of_Memory, 1, "$", "cannot allocate manifest records", allocator)
        return {}, error, false
    }
    manifest.records = records
    cursor := 0
    line_number := 0
    line, line_ok := history_next_line(data, &cursor)
    line_number += 1
    if !line_ok || line != "format_version=1" {
        history_fail(
            &error,
            .Invalid_Input,
            line_number,
            "$",
            "format_version header must be first and equal to 1",
            allocator,
        )
        history_manifest_dispose(&manifest)
        return {}, error, false
    }
    line, line_ok = history_next_line(data, &cursor)
    line_number += 1
    schema_header_prefix := "fixture_schema_version="
    schema_version: int
    schema_version_ok := false
    if line_ok && strings.has_prefix(line, schema_header_prefix) {
        schema_version, schema_version_ok = history_parse_schema_version(line[len(schema_header_prefix):])
    }
    if !line_ok || !schema_version_ok {
        history_fail(
            &error,
            .Invalid_Input,
            line_number,
            "$",
            "fixture schema version header must be second and use a supported canonical version",
            allocator,
        )
        history_manifest_dispose(&manifest)
        return {}, error, false
    }
    manifest.format_version = HISTORY_SUPPORTED_FORMAT_VERSION
    manifest.schema_version = schema_version
    line, line_ok = history_next_line(data, &cursor)
    line_number += 1
    if !line_ok {
        history_fail(&error, .Invalid_Input, line_number, "$", "root header is missing", allocator)
        history_manifest_dispose(&manifest)
        return {}, error, false
    }
    root_pairs, root_count, root_pairs_ok := history_parse_key_values(line, '|')
    if !root_pairs_ok ||
       root_count != 1 ||
       root_pairs[0].key != "root" ||
       history_reject_backslash(root_pairs[0].value) ||
       !history_is_logical_id(root_pairs[0].value) {
        history_fail(&error, .Invalid_Input, line_number, "$", "root header is malformed", allocator)
        history_manifest_dispose(&manifest)
        return {}, error, false
    }
    owned_root, root_copy_err := strings.clone(root_pairs[0].value, allocator)
    if root_copy_err != nil {
        history_fail(&error, .Out_Of_Memory, line_number, "$", "cannot own root identifier", allocator)
        history_manifest_dispose(&manifest)
        return {}, error, false
    }
    manifest.root = owned_root
    indexes, indexes_error := make(map[string]int, HISTORY_MANIFEST_MAX_RECORDS, allocator)
    if indexes_error != nil {
        history_fail(&error, .Out_Of_Memory, 1, "$", "cannot allocate manifest indexes", allocator)
        history_manifest_dispose(&manifest)
        return {}, error, false
    }
    defer delete(indexes)
    current_record := -1
    field_count := 0
    enum_count := 0
    for cursor < len(data) {
        if line_number >= HISTORY_MANIFEST_MAX_LINES {
            history_fail(&error, .Limit_Exceeded, line_number, "$", "manifest line limit exceeded", allocator)
            history_manifest_dispose(&manifest)
            return {}, error, false
        }
        line, line_ok = history_next_line(data, &cursor)
        line_number += 1
        if !line_ok || len(line) == 0 {
            history_fail(
                &error,
                .Invalid_Input,
                line_number,
                "$",
                "manifest contains an empty or unterminated line",
                allocator,
            )
            history_manifest_dispose(&manifest)
            return {}, error, false
        }
        pairs, count, pairs_ok := history_parse_key_values(line, '|')
        if !pairs_ok || count == 0 {
            history_fail(
                &error,
                .Invalid_Input,
                line_number,
                "$",
                "manifest line has malformed key/value fields",
                allocator,
            )
            history_manifest_dispose(&manifest)
            return {}, error, false
        }
        switch pairs[0].key {
        case "type":
            if count != 3 ||
               pairs[1].key != "kind" ||
               pairs[2].key != "detail" ||
               history_reject_backslash(pairs[0].value) {
                history_fail(
                    &error,
                    .Invalid_Input,
                    line_number,
                    "$",
                    "type line has unknown, missing, or reordered keys",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            if len(manifest.records) >= HISTORY_MANIFEST_MAX_RECORDS {
                history_fail(&error, .Limit_Exceeded, line_number, "$", "record limit exceeded", allocator)
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            id := pairs[0].value
            kind := pairs[1].value
            if !history_is_logical_id(id) ||
               history_reject_backslash(kind) ||
               (kind != "struct" && kind != "enum" && kind != "alias" && kind != "distinct") {
                history_fail(&error, .Invalid_Input, line_number, id, "type identifier or kind is invalid", allocator)
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            if _, found := indexes[id]; found {
                history_fail(&error, .Invalid_Input, line_number, id, "duplicate type id", allocator)
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            detail, detail_status := history_unescape(pairs[2].value, allocator)
            if detail_status != .Ok || !history_validate_detail(kind, detail) {
                if detail_status == .Ok do delete(detail, allocator)
                failure_kind := History_Error_Kind(.Invalid_Input)
                if detail_status == .Out_Of_Memory {
                    failure_kind = .Out_Of_Memory
                }
                history_fail(&error, failure_kind, line_number, id, "type detail is invalid", allocator)
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            owned_id, id_err := strings.clone(id, allocator)
            owned_kind, kind_err := strings.clone(kind, allocator)
            if id_err != nil || kind_err != nil {
                if id_err == nil do delete(owned_id, allocator)
                if kind_err == nil do delete(owned_kind, allocator)
                delete(detail, allocator)
                history_fail(&error, .Out_Of_Memory, line_number, id, "cannot own type record", allocator)
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            record := History_Record {
                id     = owned_id,
                kind   = owned_kind,
                detail = detail,
                line   = line_number,
            }
            fields, fields_error := make([dynamic]History_Field, allocator)
            enums, enums_error := make([dynamic]History_Enum, allocator)
            record.fields = fields
            record.enums = enums
            if fields_error != nil || enums_error != nil {
                if fields_error == nil do delete(record.fields)
                if enums_error == nil do delete(record.enums)
                history_record_dispose(&record, allocator)
                history_fail(&error, .Out_Of_Memory, line_number, id, "cannot allocate type children", allocator)
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            appended, append_error := append_elem(&manifest.records, record)
            if append_error != nil || appended != 1 {
                history_record_dispose(&record, allocator)
                history_fail(&error, .Out_Of_Memory, line_number, id, "cannot append type record", allocator)
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            current_record = len(manifest.records) - 1
            indexes[id] = current_record
        case "field":
            if count != 5 ||
               pairs[1].key != "name" ||
               pairs[2].key != "using" ||
               pairs[3].key != "tag" ||
               pairs[4].key != "type" ||
               current_record < 0 {
                history_fail_optional_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    current_record >= 0 ? manifest.records[current_record].id : "$",
                    count > 1 && pairs[1].key == "name" ? pairs[1].value : "",
                    "field line has unknown, missing, or reordered keys",
                    allocator,
                    current_record >= 0 && count > 1 && pairs[1].key == "name",
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            if pairs[0].value != manifest.records[current_record].id || history_reject_backslash(pairs[0].value) {
                history_fail_optional_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "field belongs to an undeclared or non-current record",
                    allocator,
                    count > 1 && pairs[1].key == "name",
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            if history_reject_backslash(pairs[1].value) {
                history_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "field identifier is invalid",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            if manifest.records[current_record].kind != "struct" || !history_is_identifier(pairs[1].value) {
                history_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "field record or name is invalid",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            using_value, using_ok := history_parse_bool(pairs[2].value)
            if !using_ok {
                history_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "field using flag is invalid",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            for field in manifest.records[current_record].fields {
                if field.name == pairs[1].value {
                    history_fail_child(
                        &error,
                        .Invalid_Input,
                        line_number,
                        manifest.records[current_record].id,
                        pairs[1].value,
                        "duplicate field name",
                        allocator,
                    )
                    history_manifest_dispose(&manifest)
                    return {}, error, false
                }
            }
            if field_count >= HISTORY_MANIFEST_MAX_FIELDS {
                history_fail_child(
                    &error,
                    .Limit_Exceeded,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "field limit exceeded",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            tag, tag_status := history_unescape(pairs[3].value, allocator)
            type_name, type_status := history_unescape(pairs[4].value, allocator)
            owned_name, name_err := strings.clone(pairs[1].value, allocator)
            if tag_status != .Ok || type_status != .Ok || name_err != nil {
                if tag_status == .Ok do delete(tag, allocator)
                if type_status == .Ok do delete(type_name, allocator)
                if name_err == nil do delete(owned_name, allocator)
                failure_kind := History_Error_Kind(.Invalid_Input)
                if tag_status == .Out_Of_Memory ||
                   type_status == .Out_Of_Memory ||
                   (tag_status == .Ok && type_status == .Ok && name_err != nil) {
                    failure_kind = .Out_Of_Memory
                }
                history_fail_child(
                    &error,
                    failure_kind,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "field syntax or ownership is invalid",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            field := History_Field {
                name     = owned_name,
                tag      = tag,
                type     = type_name,
                is_using = using_value,
                line     = line_number,
            }
            appended, append_error := append_elem(&manifest.records[current_record].fields, field)
            if append_error != nil || appended != 1 {
                delete(field.name, allocator)
                delete(field.tag, allocator)
                delete(field.type, allocator)
                history_fail(
                    &error,
                    .Out_Of_Memory,
                    line_number,
                    manifest.records[current_record].id,
                    "cannot append field",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            field_count += 1
        case "enum":
            if count != 3 || pairs[1].key != "name" || pairs[2].key != "value" || current_record < 0 {
                history_fail_optional_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    current_record >= 0 ? manifest.records[current_record].id : "$",
                    count > 1 && pairs[1].key == "name" ? pairs[1].value : "",
                    "enum line has unknown, missing, or reordered keys",
                    allocator,
                    current_record >= 0 && count > 1 && pairs[1].key == "name",
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            if pairs[0].value != manifest.records[current_record].id || history_reject_backslash(pairs[0].value) {
                history_fail_optional_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "enum belongs to an undeclared or non-current record",
                    allocator,
                    count > 1 && pairs[1].key == "name",
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            if history_reject_backslash(pairs[1].value) {
                history_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "enum identifier is invalid",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            if manifest.records[current_record].kind != "enum" || !history_is_identifier(pairs[1].value) {
                history_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "enum record or name is invalid",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            value, value_ok := history_parse_i64(pairs[2].value, true)
            if !value_ok {
                history_fail_child(
                    &error,
                    .Invalid_Input,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "enum value is invalid",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            for entry in manifest.records[current_record].enums {
                if entry.name == pairs[1].value || entry.value == value {
                    history_fail_child(
                        &error,
                        .Invalid_Input,
                        line_number,
                        manifest.records[current_record].id,
                        pairs[1].value,
                        "duplicate enum name or value",
                        allocator,
                    )
                    history_manifest_dispose(&manifest)
                    return {}, error, false
                }
            }
            if enum_count >= HISTORY_MANIFEST_MAX_ENUMS {
                history_fail_child(
                    &error,
                    .Limit_Exceeded,
                    line_number,
                    manifest.records[current_record].id,
                    pairs[1].value,
                    "enum value limit exceeded",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            owned_name, name_err := strings.clone(pairs[1].value, allocator)
            if name_err != nil {
                history_fail(
                    &error,
                    .Out_Of_Memory,
                    line_number,
                    manifest.records[current_record].id,
                    "cannot own enum name",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            entry := History_Enum {
                name  = owned_name,
                value = value,
                line  = line_number,
            }
            appended, append_error := append_elem(&manifest.records[current_record].enums, entry)
            if append_error != nil || appended != 1 {
                delete(entry.name, allocator)
                history_fail(
                    &error,
                    .Out_Of_Memory,
                    line_number,
                    manifest.records[current_record].id,
                    "cannot append enum",
                    allocator,
                )
                history_manifest_dispose(&manifest)
                return {}, error, false
            }
            enum_count += 1
        case:
            history_fail(&error, .Invalid_Input, line_number, "$", "unknown manifest line kind", allocator)
            history_manifest_dispose(&manifest)
            return {}, error, false
        }
    }
    if len(manifest.records) == 0 {
        history_fail(&error, .Invalid_Input, line_number, "$", "manifest contains no type records", allocator)
        history_manifest_dispose(&manifest)
        return {}, error, false
    }
    if !history_validate_manifest(&manifest, &error) {
        history_manifest_dispose(&manifest)
        return {}, error, false
    }
    return manifest, error, true
}
