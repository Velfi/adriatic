package fixture_schema

import "core:fmt"
import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

MIGRATION_SCAFFOLD_MAX_SOURCE_BYTES :: 8 * 1024 * 1024
MIGRATION_SCAFFOLD_MAX_OBLIGATIONS :: 1024
MIGRATION_SCAFFOLD_MAX_VERSION :: 9999
MIGRATION_SCAFFOLD_BY_PTR_FLAGS :: ast.Field_Flags{.By_Ptr}

Migration_Scaffold_Resolution_Kind :: enum {
    Unresolved,
    Automatic,
    Scripted,
}

Migration_Scaffold_Resolution :: struct {
    change_id: string,
    kind:      Migration_Scaffold_Resolution_Kind,
    line:      int,
    column:    int,
}

Migration_Scaffold_Limits :: struct {
    max_bytes:       int,
    max_obligations: int,
}

MIGRATION_SCAFFOLD_DEFAULT_LIMITS :: Migration_Scaffold_Limits {
    max_bytes       = MIGRATION_SCAFFOLD_MAX_SOURCE_BYTES,
    max_obligations = MIGRATION_SCAFFOLD_MAX_OBLIGATIONS,
}

Migration_Scaffold_Error_Kind :: enum {
    None,
    Invalid_Input,
    Limit_Exceeded,
    Out_Of_Memory,
}

Migration_Scaffold_Reserved_Name_Kind :: enum {
    None,
    From_Version,
    To_Version,
    Resolutions,
    Procedure,
}

Migration_Scaffold_Error :: struct {
    kind:          Migration_Scaffold_Error_Kind,
    line:          int,
    column:        int,
    path:          string,
    message:       string,
    path_owned:    bool,
    message_owned: bool,
    allocator:     mem.Allocator,
}

Migration_Scaffold :: struct {
    allocator:          mem.Allocator,
    from_version:       int,
    to_version:         int,
    from_line:          int,
    from_column:        int,
    to_line:            int,
    to_column:          int,
    resolutions_line:   int,
    resolutions_column: int,
    resolutions:        [dynamic]Migration_Scaffold_Resolution,
}

migration_scaffold_allocator_valid :: proc(allocator: mem.Allocator) -> bool {
    return allocator.procedure != nil
}

migration_scaffold_stored_pos :: proc(line, column: int) -> tokenizer.Pos {
    return tokenizer.Pos{line = max(1, line), column = max(1, column)}
}

migration_scaffold_resolution_kind_valid :: proc(kind: Migration_Scaffold_Resolution_Kind) -> bool {
    switch kind {
    case .Unresolved, .Automatic, .Scripted:
        return true
    }
    return false
}

migration_scaffold_resolution_kind_name :: proc(kind: Migration_Scaffold_Resolution_Kind) -> string {
    switch kind {
    case .Unresolved:
        return "Unresolved"
    case .Automatic:
        return "Automatic"
    case .Scripted:
        return "Scripted"
    }
    return ""
}

migration_scaffold_error_dispose :: proc(error: ^Migration_Scaffold_Error) {
    if error == nil do return
    if error.path_owned do delete(error.path, error.allocator)
    if error.message_owned do delete(error.message, error.allocator)
    error^ = {}
}

migration_scaffold_dispose :: proc(scaffold: ^Migration_Scaffold) {
    if scaffold == nil do return
    for &resolution in scaffold.resolutions {
        delete(resolution.change_id, scaffold.allocator)
    }
    delete(scaffold.resolutions)
    scaffold^ = {}
}

migration_scaffold_make_error :: proc(
    kind: Migration_Scaffold_Error_Kind,
    pos: tokenizer.Pos,
    path, message: string,
    allocator: mem.Allocator,
) -> Migration_Scaffold_Error {
    error := Migration_Scaffold_Error {
        kind      = kind,
        line      = max(1, pos.line),
        column    = max(1, pos.column),
        path      = "$",
        message   = message,
        allocator = allocator,
    }
    if owned, clone_error := strings.clone(path, allocator); clone_error == nil {
        error.path = owned
        error.path_owned = true
    }
    if owned, clone_error := strings.clone(message, allocator); clone_error == nil {
        error.message = owned
        error.message_owned = true
    }
    return error
}

migration_scaffold_fail :: proc(
    error: ^Migration_Scaffold_Error,
    kind: Migration_Scaffold_Error_Kind,
    pos: tokenizer.Pos,
    path, message: string,
    allocator: mem.Allocator,
) {
    if error != nil && error.kind == .None {
        error^ = migration_scaffold_make_error(kind, pos, path, message, allocator)
    }
}

migration_scaffold_builder_capacity_add :: proc(capacity: ^int, amount: int) -> bool {
    if capacity == nil || amount < 0 || capacity^ > MIGRATION_SCAFFOLD_MAX_SOURCE_BYTES - amount do return false
    capacity^ += amount
    return true
}

migration_scaffold_write_odin_string :: proc(builder: ^strings.Builder, value: string) -> bool {
    if builder == nil do return false
    strings.write_byte(builder, '"')
    for ch in value {
        switch ch {
        case '\\':
            strings.write_string(builder, "\\\\")
        case '"':
            strings.write_string(builder, "\\\"")
        case '\n':
            strings.write_string(builder, "\\n")
        case '\r':
            strings.write_string(builder, "\\r")
        case '\t':
            strings.write_string(builder, "\\t")
        case:
            if ch < 0x20 || ch == 0x7f do return false
            strings.write_rune(builder, ch)
        }
    }
    strings.write_byte(builder, '"')
    return true
}

migration_scaffold_expr_ident :: proc(expr: ^ast.Expr) -> (string, bool) {
    if expr == nil do return "", false
    value := ast.unparen_expr(expr)
    if ident, ok := value.derived_expr.(^ast.Ident); ok do return ident.name, true
    return "", false
}

migration_scaffold_expr_is_ident :: proc(expr: ^ast.Expr, expected: string) -> bool {
    value, ok := migration_scaffold_expr_ident(expr)
    return ok && value == expected
}

migration_scaffold_expr_selector :: proc(expr: ^ast.Expr, package_name, type_name: string) -> bool {
    if expr == nil do return false
    value := ast.unparen_expr(expr)
    selector, ok := value.derived_expr.(^ast.Selector_Expr)
    if !ok || selector.op.kind != .Period do return false
    root, root_ok := migration_scaffold_expr_ident(selector.expr)
    field, field_ok := migration_scaffold_expr_ident(selector.field)
    return root_ok && field_ok && root == package_name && field == type_name
}

migration_scaffold_expr_basic_lit :: proc(
    expr: ^ast.Expr,
    kind: tokenizer.Token_Kind,
) -> (
    string,
    tokenizer.Pos,
    bool,
) {
    if expr == nil do return "", {}, false
    value := ast.unparen_expr(expr)
    literal, ok := value.derived_expr.(^ast.Basic_Lit)
    if !ok || literal.tok.kind != kind do return "", value.pos, false
    return literal.tok.text, value.pos, true
}

migration_scaffold_string_literal :: proc(expr: ^ast.Expr) -> (string, tokenizer.Pos, bool) {
    text, pos, ok := migration_scaffold_expr_basic_lit(expr, .String)
    if !ok || len(text) < 2 || text[0] != '"' || text[len(text) - 1] != '"' do return "", pos, false
    value := text[1:len(text) - 1]
    for ch in value {
        if ch == '\\' || ch == '"' || ch < 0x20 || ch == 0x7f do return "", pos, false
    }
    return value, pos, true
}

migration_scaffold_integer_literal :: proc(expr: ^ast.Expr) -> (int, tokenizer.Pos, bool) {
    text, pos, ok := migration_scaffold_expr_basic_lit(expr, .Integer)
    if !ok || len(text) == 0 || len(text) > 4 do return 0, pos, false
    if len(text) > 1 && text[0] == '0' do return 0, pos, false
    for ch in text {
        if ch < '0' || ch > '9' do return 0, pos, false
    }
    value, parse_ok := strconv.parse_i64(text)
    if !parse_ok || value < 1 || value > MIGRATION_SCAFFOLD_MAX_VERSION do return 0, pos, false
    return int(value), pos, true
}

migration_scaffold_implicit_selector :: proc(expr: ^ast.Expr) -> (string, tokenizer.Pos, bool) {
    if expr == nil do return "", {}, false
    value := ast.unparen_expr(expr)
    selector, ok := value.derived_expr.(^ast.Implicit_Selector_Expr)
    if !ok || selector.field == nil do return "", value.pos, false
    return selector.field.name, value.pos, true
}

migration_scaffold_decl_name :: proc(decl: ^ast.Value_Decl) -> (string, bool) {
    if decl == nil || len(decl.names) != 1 do return "", false
    return migration_scaffold_expr_ident(decl.names[0])
}

migration_scaffold_reserved_name_kind :: proc(name: string) -> Migration_Scaffold_Reserved_Name_Kind {
    if strings.has_prefix(name, "FIXTURE_MIGRATION_V") && strings.has_suffix(name, "_FROM_VERSION") {
        return .From_Version
    }
    if strings.has_prefix(name, "FIXTURE_MIGRATION_V") && strings.has_suffix(name, "_TO_VERSION") {
        return .To_Version
    }
    if strings.has_prefix(name, "FIXTURE_MIGRATION_V") && strings.has_suffix(name, "_RESOLUTIONS") {
        return .Resolutions
    }
    if strings.has_prefix(name, "fixture_migrate_v") do return .Procedure
    return .None
}

migration_scaffold_reserved_name_path :: proc(kind: Migration_Scaffold_Reserved_Name_Kind) -> string {
    switch kind {
    case .From_Version:
        return "from_version"
    case .To_Version:
        return "to_version"
    case .Resolutions:
        return "resolutions"
    case .Procedure:
        return "procedure"
    case .None:
    }
    return "metadata"
}

migration_scaffold_resolution_type :: proc(expr: ^ast.Expr) -> bool {
    if expr == nil do return false
    value := ast.unparen_expr(expr)
    array, ok := value.derived_expr.(^ast.Array_Type)
    if !ok || array.tag != nil || array.len == nil do return false
    length := ast.unparen_expr(array.len)
    unary, unary_ok := length.derived_expr.(^ast.Unary_Expr)
    if !unary_ok || unary.op.kind != .Question do return false
    return migration_scaffold_expr_is_ident(array.elem, "Fixture_Migration_Resolution")
}

migration_scaffold_resolution_entry :: proc(
    expr: ^ast.Expr,
) -> (
    string,
    Migration_Scaffold_Resolution_Kind,
    tokenizer.Pos,
    bool,
) {
    if expr == nil do return "", .Unresolved, {}, false
    value := ast.unparen_expr(expr)
    literal, literal_ok := value.derived_expr.(^ast.Comp_Lit)
    if !literal_ok || !migration_scaffold_expr_is_ident(literal.type, "Fixture_Migration_Resolution") {
        return "", .Unresolved, value.pos, false
    }
    if len(literal.elems) != 2 do return "", .Unresolved, value.pos, false
    change_id := ""
    kind := Migration_Scaffold_Resolution_Kind.Unresolved
    have_change_id := false
    have_kind := false
    for element in literal.elems {
        field, field_ok := element.derived_expr.(^ast.Field_Value)
        if !field_ok do return "", .Unresolved, element.pos, false
        field_name, field_name_ok := migration_scaffold_expr_ident(field.field)
        if !field_name_ok do return "", .Unresolved, field.pos, false
        switch field_name {
        case "change_id":
            if have_change_id do return "", .Unresolved, field.pos, false
            value_text, _, value_ok := migration_scaffold_string_literal(field.value)
            if !value_ok || len(value_text) == 0 do return "", .Unresolved, field.pos, false
            change_id = value_text
            have_change_id = true
        case "kind":
            if have_kind do return "", .Unresolved, field.pos, false
            kind_name, _, kind_ok := migration_scaffold_implicit_selector(field.value)
            if !kind_ok do return "", .Unresolved, field.pos, false
            switch kind_name {
            case "Unresolved":
                kind = .Unresolved
            case "Automatic":
                kind = .Automatic
            case "Scripted":
                kind = .Scripted
            case:
                return "", .Unresolved, field.pos, false
            }
            have_kind = true
        case:
            return "", .Unresolved, field.pos, false
        }
    }
    if !have_change_id || !have_kind do return "", .Unresolved, value.pos, false
    return change_id, kind, value.pos, true
}

migration_scaffold_validate_proc_decl :: proc(
    decl: ^ast.Value_Decl,
    expected_name, expected_history_alias: string,
    error: ^Migration_Scaffold_Error,
    allocator: mem.Allocator,
) -> bool {
    name, name_ok := migration_scaffold_decl_name(decl)
    if !name_ok || name != expected_name || decl.is_mutable || len(decl.values) != 1 {
        migration_scaffold_fail(
            error,
            .Invalid_Input,
            decl.pos,
            "procedure",
            "migration procedure declaration is invalid",
            allocator,
        )
        return false
    }
    literal, literal_ok := ast.unparen_expr(decl.values[0]).derived_expr.(^ast.Proc_Lit)
    if !literal_ok || literal.type == nil || literal.type.params == nil || literal.type.results == nil {
        migration_scaffold_fail(
            error,
            .Invalid_Input,
            decl.pos,
            "procedure",
            "migration procedure type is invalid",
            allocator,
        )
        return false
    }
    proc_type := literal.type
    if len(proc_type.params.list) != 3 || len(proc_type.results.list) != 1 {
        migration_scaffold_fail(
            error,
            .Invalid_Input,
            decl.pos,
            "procedure",
            "migration procedure parameter count is invalid",
            allocator,
        )
        return false
    }
    names := [?]string{"historical", "tentative", "allocator"}
    no_field_flags := ast.Field_Flags{}
    for field, index in proc_type.params.list {
        if len(field.names) != 1 || !migration_scaffold_expr_is_ident(field.names[0], names[index]) {
            migration_scaffold_fail(
                error,
                .Invalid_Input,
                field.pos,
                "procedure.parameters",
                "migration parameter name is invalid",
                allocator,
            )
            return false
        }
        switch index {
        case 0:
            historical_type_ok := migration_scaffold_expr_selector(field.type, expected_history_alias, "Fixture")
            historical_flags_ok := field.flags == MIGRATION_SCAFFOLD_BY_PTR_FLAGS
            if !historical_flags_ok || !historical_type_ok {
                migration_scaffold_fail(
                    error,
                    .Invalid_Input,
                    field.pos,
                    "procedure.historical",
                    "historical parameter must use #by_ptr historical fixture type",
                    allocator,
                )
                return false
            }
        case 1:
            pointer: ^ast.Pointer_Type
            pointer_ok := false
            if field.type != nil {
                pointer, pointer_ok = ast.unparen_expr(field.type).derived_expr.(^ast.Pointer_Type)
            }
            tentative_type_ok := pointer_ok && migration_scaffold_expr_is_ident(pointer.elem, "Fixture")
            if field.flags != no_field_flags || !tentative_type_ok {
                migration_scaffold_fail(
                    error,
                    .Invalid_Input,
                    field.pos,
                    "procedure.tentative",
                    "tentative parameter type is invalid",
                    allocator,
                )
                return false
            }
        case 2:
            allocator_type_ok := migration_scaffold_expr_selector(field.type, "mem", "Allocator")
            if field.flags != no_field_flags || !allocator_type_ok {
                migration_scaffold_fail(
                    error,
                    .Invalid_Input,
                    field.pos,
                    "procedure.allocator",
                    "allocator parameter type is invalid",
                    allocator,
                )
                return false
            }
        }
    }
    result := proc_type.results.list[0]
    result_type_ok := migration_scaffold_expr_is_ident(result.type, "Fixture_Migration_Error")
    if len(result.names) != 0 || result.flags != no_field_flags || !result_type_ok {
        migration_scaffold_fail(
            error,
            .Invalid_Input,
            result.pos,
            "procedure.result",
            "migration result type is invalid",
            allocator,
        )
        return false
    }
    return true
}

migration_scaffold_parse :: proc(
    source: []byte,
    allocator: mem.Allocator,
    limits := MIGRATION_SCAFFOLD_DEFAULT_LIMITS,
) -> (
    scaffold: Migration_Scaffold,
    error: Migration_Scaffold_Error,
    ok: bool,
) {
    scaffold.allocator = allocator
    if !migration_scaffold_allocator_valid(allocator) {
        migration_scaffold_fail(&error, .Out_Of_Memory, {}, "$", "scaffold allocator is invalid", allocator)
        return {}, error, false
    }
    if limits.max_bytes < 0 ||
       limits.max_obligations < 0 ||
       limits.max_bytes > MIGRATION_SCAFFOLD_MAX_SOURCE_BYTES ||
       limits.max_obligations > MIGRATION_SCAFFOLD_MAX_OBLIGATIONS {
        migration_scaffold_fail(&error, .Invalid_Input, {}, "$", "scaffold limits are invalid", allocator)
        return {}, error, false
    }
    if len(source) > limits.max_bytes {
        migration_scaffold_fail(&error, .Limit_Exceeded, {}, "$", "scaffold source byte limit exceeded", allocator)
        return {}, error, false
    }
    source_text := string(source)
    if !utf8.valid_string(source_text) {
        migration_scaffold_fail(&error, .Invalid_Input, {}, "$", "scaffold source is not valid UTF-8", allocator)
        return {}, error, false
    }
    previous_allocator := context.allocator
    context.allocator = context.temp_allocator
    defer context.allocator = previous_allocator
    file := ast.new(ast.File, tokenizer.Pos{}, tokenizer.Pos{})
    file.src = source_text
    file.fullpath = "migration_scaffold.odin"
    parser_state: parser.Parser
    parser_state.flags += {.Optional_Semicolons}
    if !parser.parse_file(&parser_state, file) || file.syntax_error_count != 0 || file.syntax_warning_count != 0 {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            file.pos,
            "$",
            "scaffold source has Odin syntax errors",
            allocator,
        )
        return {}, error, false
    }
    if file.pkg_decl == nil {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            file.pos,
            "package",
            "scaffold package must be main",
            allocator,
        )
        return {}, error, false
    }
    if file.pkg_decl.name != "main" {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            file.pkg_decl.pos,
            "package",
            "scaffold package must be main",
            allocator,
        )
        return {}, error, false
    }
    mem_imports := 0
    for import_decl in file.imports {
        if import_decl.name.text == "" && import_decl.relpath.text == "\"core:mem\"" {
            mem_imports += 1
        }
    }
    if mem_imports != 1 {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            file.pos,
            "imports.core_mem",
            "required core:mem import is missing or duplicated",
            allocator,
        )
        return {}, error, false
    }
    from_decl: ^ast.Value_Decl
    to_decl: ^ast.Value_Decl
    resolutions_decl: ^ast.Value_Decl
    procedure_decl: ^ast.Value_Decl
    from_name := ""
    to_name := ""
    resolutions_name := ""
    procedure_name := ""
    for stmt in file.decls {
        decl, decl_ok := stmt.derived_stmt.(^ast.Value_Decl)
        if !decl_ok do continue
        for name_expr in decl.names {
            name, name_ok := migration_scaffold_expr_ident(name_expr)
            if !name_ok do continue
            reserved_kind := migration_scaffold_reserved_name_kind(name)
            if reserved_kind == .None do continue
            if len(decl.names) != 1 {
                migration_scaffold_fail(
                    &error,
                    .Invalid_Input,
                    decl.pos,
                    migration_scaffold_reserved_name_path(reserved_kind),
                    "reserved migration declaration must have exactly one name",
                    allocator,
                )
                return {}, error, false
            }
            switch reserved_kind {
            case .From_Version:
                if from_decl != nil {
                    migration_scaffold_fail(
                        &error,
                        .Invalid_Input,
                        decl.pos,
                        "from_version",
                        "duplicate migration metadata",
                        allocator,
                    )
                    return {}, error, false
                }
                from_decl = decl
                from_name = name
            case .To_Version:
                if to_decl != nil {
                    migration_scaffold_fail(
                        &error,
                        .Invalid_Input,
                        decl.pos,
                        "to_version",
                        "duplicate migration metadata",
                        allocator,
                    )
                    return {}, error, false
                }
                to_decl = decl
                to_name = name
            case .Resolutions:
                if resolutions_decl != nil {
                    migration_scaffold_fail(
                        &error,
                        .Invalid_Input,
                        decl.pos,
                        "resolutions",
                        "duplicate migration metadata",
                        allocator,
                    )
                    return {}, error, false
                }
                resolutions_decl = decl
                resolutions_name = name
            case .Procedure:
                if procedure_decl != nil {
                    migration_scaffold_fail(
                        &error,
                        .Invalid_Input,
                        decl.pos,
                        "procedure",
                        "duplicate migration procedure",
                        allocator,
                    )
                    return {}, error, false
                }
                procedure_decl = decl
                procedure_name = name
            case .None:
            }
        }
    }
    if from_decl == nil || to_decl == nil || resolutions_decl == nil || procedure_decl == nil {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            file.pos,
            "metadata",
            "required migration metadata is incomplete",
            allocator,
        )
        return {}, error, false
    }
    from_values_ok := len(from_decl.values) == 1
    to_values_ok := len(to_decl.values) == 1
    from_version, from_pos, from_ok := 0, tokenizer.Pos{}, false
    to_version, to_pos, to_ok := 0, tokenizer.Pos{}, false
    if from_values_ok {
        from_version, from_pos, from_ok = migration_scaffold_integer_literal(from_decl.values[0])
    }
    if to_values_ok {
        to_version, to_pos, to_ok = migration_scaffold_integer_literal(to_decl.values[0])
    }
    if !from_values_ok || from_decl.is_mutable || from_decl.type != nil || !from_ok {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            from_pos,
            "from_version",
            "from version must be an immutable decimal literal",
            allocator,
        )
        return {}, error, false
    }
    if !to_values_ok || to_decl.is_mutable || to_decl.type != nil || !to_ok {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            to_pos,
            "to_version",
            "to version must be an immutable decimal literal",
            allocator,
        )
        return {}, error, false
    }
    if to_version != from_version + 1 {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            to_pos,
            "versions",
            "migration versions must be contiguous",
            allocator,
        )
        return {}, error, false
    }
    expected_from_name := fmt.tprintf("FIXTURE_MIGRATION_V%04d_TO_V%04d_FROM_VERSION", from_version, to_version)
    expected_to_name := fmt.tprintf("FIXTURE_MIGRATION_V%04d_TO_V%04d_TO_VERSION", from_version, to_version)
    expected_resolutions_name := fmt.tprintf("FIXTURE_MIGRATION_V%04d_TO_V%04d_RESOLUTIONS", from_version, to_version)
    expected_procedure_name := fmt.tprintf("fixture_migrate_v%04d_to_v%04d", from_version, to_version)
    if from_name != expected_from_name {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            from_decl.pos,
            "from_version",
            "from metadata symbol is invalid",
            allocator,
        )
        return {}, error, false
    }
    if to_name != expected_to_name {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            to_decl.pos,
            "to_version",
            "to metadata symbol is invalid",
            allocator,
        )
        return {}, error, false
    }
    if resolutions_name != expected_resolutions_name {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            resolutions_decl.pos,
            "resolutions",
            "resolution metadata symbol is invalid",
            allocator,
        )
        return {}, error, false
    }
    if procedure_name != expected_procedure_name {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            procedure_decl.pos,
            "procedure",
            "migration procedure symbol is invalid",
            allocator,
        )
        return {}, error, false
    }
    history_alias := fmt.tprintf("fixture_v%04d", from_version)
    history_path := fmt.tprintf("\"../packages/fixture_history/v%04d\"", from_version)
    history_imports := 0
    for import_decl in file.imports {
        if import_decl.name.text == "mem" {
            migration_scaffold_fail(
                &error,
                .Invalid_Input,
                import_decl.pos,
                "imports.core_mem",
                "mem import alias is reserved",
                allocator,
            )
            return {}, error, false
        }
        if import_decl.name.text == history_alias && import_decl.relpath.text != history_path {
            migration_scaffold_fail(
                &error,
                .Invalid_Input,
                import_decl.pos,
                "imports.fixture_history",
                "historical import alias is reserved",
                allocator,
            )
            return {}, error, false
        }
        if import_decl.name.text == history_alias && import_decl.relpath.text == history_path {
            history_imports += 1
        }
    }
    if history_imports != 1 {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            file.pos,
            "imports.fixture_history",
            "required historical import is missing or duplicated",
            allocator,
        )
        return {}, error, false
    }
    resolutions_value_ok := len(resolutions_decl.values) == 1
    literal: ^ast.Comp_Lit
    literal_ok := false
    if resolutions_value_ok {
        literal, literal_ok = ast.unparen_expr(resolutions_decl.values[0]).derived_expr.(^ast.Comp_Lit)
    }
    resolutions_type_ok := literal_ok && migration_scaffold_resolution_type(literal.type)
    if !resolutions_value_ok || !resolutions_type_ok || resolutions_decl.is_mutable {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            resolutions_decl.pos,
            "resolutions",
            "resolution declaration type is invalid",
            allocator,
        )
        return {}, error, false
    }
    if !migration_scaffold_validate_proc_decl(
        procedure_decl,
        expected_procedure_name,
        history_alias,
        &error,
        allocator,
    ) {
        return {}, error, false
    }
    if len(literal.elems) > limits.max_obligations || len(literal.elems) > MIGRATION_SCAFFOLD_MAX_OBLIGATIONS {
        migration_scaffold_fail(
            &error,
            .Limit_Exceeded,
            literal.pos,
            "resolutions",
            "migration obligation limit exceeded",
            allocator,
        )
        return {}, error, false
    }
    resolutions, resolutions_error := make([dynamic]Migration_Scaffold_Resolution, 0, len(literal.elems), allocator)
    if resolutions_error != nil {
        migration_scaffold_fail(
            &error,
            .Out_Of_Memory,
            resolutions_decl.pos,
            "resolutions",
            "cannot allocate migration resolutions",
            allocator,
        )
        return {}, error, false
    }
    scaffold.from_version = from_version
    scaffold.to_version = to_version
    scaffold.from_line = from_decl.pos.line
    scaffold.from_column = from_decl.pos.column
    scaffold.to_line = to_decl.pos.line
    scaffold.to_column = to_decl.pos.column
    scaffold.resolutions_line = resolutions_decl.pos.line
    scaffold.resolutions_column = resolutions_decl.pos.column
    scaffold.resolutions = resolutions
    previous_id := ""
    for element, index in literal.elems {
        change_id, kind, pos, entry_ok := migration_scaffold_resolution_entry(element)
        if !entry_ok || (index > 0 && change_id <= previous_id) {
            migration_scaffold_fail(
                &error,
                .Invalid_Input,
                pos,
                fmt.tprintf("resolutions[%d]", index),
                "resolution entry is invalid or unsorted",
                allocator,
            )
            migration_scaffold_dispose(&scaffold)
            return {}, error, false
        }
        owned_id, id_error := strings.clone(change_id, allocator)
        if id_error != nil {
            migration_scaffold_fail(
                &error,
                .Out_Of_Memory,
                pos,
                fmt.tprintf("resolutions[%d]", index),
                "cannot own resolution change ID",
                allocator,
            )
            migration_scaffold_dispose(&scaffold)
            return {}, error, false
        }
        resolution := Migration_Scaffold_Resolution {
            change_id = owned_id,
            kind      = kind,
            line      = pos.line,
            column    = pos.column,
        }
        appended, append_error := append_elem(&scaffold.resolutions, resolution)
        if append_error != nil || appended != 1 {
            delete(resolution.change_id, allocator)
            migration_scaffold_fail(
                &error,
                .Out_Of_Memory,
                pos,
                fmt.tprintf("resolutions[%d]", index),
                "cannot append resolution",
                allocator,
            )
            migration_scaffold_dispose(&scaffold)
            return {}, error, false
        }
        previous_id = change_id
    }
    return scaffold, error, true
}

migration_scaffold_validate :: proc(
    scaffold: ^Migration_Scaffold,
    report: ^Schema_Diff_Report,
) -> (
    error: Migration_Scaffold_Error,
    ok: bool,
) {
    if scaffold == nil || report == nil {
        migration_scaffold_fail(&error, .Invalid_Input, {}, "$", "scaffold or report is nil", context.allocator)
        return error, false
    }
    allocator := scaffold.allocator
    if !migration_scaffold_allocator_valid(allocator) {
        migration_scaffold_fail(&error, .Out_Of_Memory, {}, "$", "scaffold allocator is invalid", allocator)
        return error, false
    }
    report_error: Schema_Diff_Error
    if !schema_diff_report_validate(report, &report_error) {
        schema_diff_error_dispose(&report_error)
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            {},
            "report",
            "accepted schema diff report is invalid",
            allocator,
        )
        return error, false
    }
    schema_diff_error_dispose(&report_error)
    if scaffold.from_version <= 0 ||
       scaffold.to_version != scaffold.from_version + 1 ||
       scaffold.from_version > MIGRATION_SCAFFOLD_MAX_VERSION ||
       scaffold.to_version > MIGRATION_SCAFFOLD_MAX_VERSION ||
       scaffold.from_version != report.from_version ||
       scaffold.to_version != report.to_version {
        version_pos := migration_scaffold_stored_pos(scaffold.to_line, scaffold.to_column)
        if scaffold.from_version != report.from_version {
            version_pos = migration_scaffold_stored_pos(scaffold.from_line, scaffold.from_column)
        }
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            version_pos,
            "versions",
            "scaffold versions do not match report",
            allocator,
        )
        return error, false
    }
    state_count := 0
    for change in report.changes {
        if change.class == .State do state_count += 1
    }
    if len(scaffold.resolutions) != state_count {
        migration_scaffold_fail(
            &error,
            .Invalid_Input,
            migration_scaffold_stored_pos(scaffold.resolutions_line, scaffold.resolutions_column),
            "resolutions",
            "resolution count does not match state changes",
            allocator,
        )
        return error, false
    }
    resolution_index := 0
    previous_id := ""
    for change in report.changes {
        if change.class != .State do continue
        resolution := scaffold.resolutions[resolution_index]
        if !migration_scaffold_resolution_kind_valid(resolution.kind) {
            migration_scaffold_fail(
                &error,
                .Invalid_Input,
                migration_scaffold_stored_pos(resolution.line, resolution.column),
                fmt.tprintf("resolutions[%d]", resolution_index),
                "resolution kind is unknown",
                allocator,
            )
            return error, false
        }
        if resolution.change_id <= previous_id || resolution.change_id != change.id {
            migration_scaffold_fail(
                &error,
                .Invalid_Input,
                migration_scaffold_stored_pos(resolution.line, resolution.column),
                fmt.tprintf("resolutions[%d]", resolution_index),
                "resolution IDs do not match report order",
                allocator,
            )
            return error, false
        }
        previous_id = resolution.change_id
        resolution_index += 1
    }
    return error, true
}

migration_scaffold_render :: proc(
    report: ^Schema_Diff_Report,
    allocator: mem.Allocator,
) -> (
    source: string,
    error: Migration_Scaffold_Error,
    ok: bool,
) {
    if !migration_scaffold_allocator_valid(allocator) {
        migration_scaffold_fail(&error, .Out_Of_Memory, {}, "$", "scaffold allocator is invalid", allocator)
        return "", error, false
    }
    if report == nil {
        migration_scaffold_fail(&error, .Invalid_Input, {}, "report", "schema diff report is nil", allocator)
        return "", error, false
    }
    report_error: Schema_Diff_Error
    if !schema_diff_report_validate(report, &report_error) {
        schema_diff_error_dispose(&report_error)
        migration_scaffold_fail(&error, .Invalid_Input, {}, "report", "schema diff report is invalid", allocator)
        return "", error, false
    }
    schema_diff_error_dispose(&report_error)
    if report.from_version <= 0 ||
       report.to_version != report.from_version + 1 ||
       report.from_version > MIGRATION_SCAFFOLD_MAX_VERSION ||
       report.to_version > MIGRATION_SCAFFOLD_MAX_VERSION {
        migration_scaffold_fail(&error, .Invalid_Input, {}, "versions", "schema diff versions are invalid", allocator)
        return "", error, false
    }
    state_count := 0
    for change in report.changes {
        if change.class == .State do state_count += 1
    }
    if state_count > MIGRATION_SCAFFOLD_MAX_OBLIGATIONS {
        migration_scaffold_fail(
            &error,
            .Limit_Exceeded,
            {},
            "report.changes",
            "migration obligation hard limit exceeded",
            allocator,
        )
        return "", error, false
    }
    capacity := 4096
    for change in report.changes {
        if change.class == .State {
            if !migration_scaffold_builder_capacity_add(&capacity, len(change.id) * 2 + 128) {
                migration_scaffold_fail(
                    &error,
                    .Limit_Exceeded,
                    {},
                    "report",
                    "migration scaffold source is too large",
                    allocator,
                )
                return "", error, false
            }
        }
    }
    builder, builder_error := strings.builder_make_len_cap(0, capacity, allocator)
    if builder_error != nil {
        migration_scaffold_fail(
            &error,
            .Out_Of_Memory,
            {},
            "source",
            "cannot allocate migration scaffold source",
            allocator,
        )
        return "", error, false
    }
    fmt.sbprintf(&builder, "package main\n\n")
    fmt.sbprintf(
        &builder,
        "import fixture_v%04d \"../packages/fixture_history/v%04d\"\n",
        report.from_version,
        report.from_version,
    )
    strings.write_string(&builder, "import \"core:mem\"\n\n")
    fmt.sbprintf(
        &builder,
        "FIXTURE_MIGRATION_V%04d_TO_V%04d_FROM_VERSION :: %d\n",
        report.from_version,
        report.to_version,
        report.from_version,
    )
    fmt.sbprintf(
        &builder,
        "FIXTURE_MIGRATION_V%04d_TO_V%04d_TO_VERSION :: %d\n",
        report.from_version,
        report.to_version,
        report.to_version,
    )
    fmt.sbprintf(
        &builder,
        "FIXTURE_MIGRATION_V%04d_TO_V%04d_RESOLUTIONS :: [?]Fixture_Migration_Resolution {{\n",
        report.from_version,
        report.to_version,
    )
    for change in report.changes {
        if change.class != .State do continue
        strings.write_string(&builder, "\tFixture_Migration_Resolution {\n\t\tchange_id = ")
        if !migration_scaffold_write_odin_string(&builder, change.id) {
            strings.builder_destroy(&builder)
            migration_scaffold_fail(
                &error,
                .Invalid_Input,
                {},
                "resolutions",
                "change ID cannot be rendered as an Odin string",
                allocator,
            )
            return "", error, false
        }
        strings.write_string(&builder, ",\n\t\tkind = .Unresolved,\n\t},\n")
    }
    strings.write_string(&builder, "}\n\n")
    fmt.sbprintf(&builder, "fixture_migrate_v%04d_to_v%04d :: proc(\n", report.from_version, report.to_version)
    fmt.sbprintf(&builder, "\t#by_ptr historical: fixture_v%04d.Fixture,\n", report.from_version)
    strings.write_string(&builder, "\ttentative: ^Fixture,\n")
    strings.write_string(&builder, "\tallocator: mem.Allocator,\n")
    strings.write_string(&builder, ") -> Fixture_Migration_Error {\n")
    strings.write_string(&builder, "\t_ = historical\n\t_ = tentative\n\t_ = allocator\n")
    strings.write_string(&builder, "\treturn Fixture_Migration_Error{kind = .Unresolved}\n}\n")
    return strings.to_string(builder), error, true
}
