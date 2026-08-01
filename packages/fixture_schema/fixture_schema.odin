package fixture_schema

import "base:runtime"
import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:path/filepath"
import "core:reflect"
import "core:strconv"
import "core:strings"

FORMAT_VERSION :: 1
ROOT_PACKAGE_ID :: "adriatic:src"
ROOT_TYPE_NAME :: "Fixture"

Symbol :: struct {
    name:       string,
    name_index: int,
    value:      ^ast.Value_Decl,
    file:       ^ast.File,
}

Package_Info :: struct {
    id:           string,
    path:         string,
    pkg:          ^ast.Package,
    symbols:      map[string]^Symbol,
    imports:      map[string]^Import_Scope,
    dependencies: map[string]bool,
}

Import_Scope :: struct {
    aliases: map[string]string,
}

Field_Record :: struct {
    name:     string,
    tag:      string,
    type:     string,
    is_using: bool,
}

Enum_Record :: struct {
    name:  string,
    value: i64,
}

Type_Record :: struct {
    id:       string,
    kind:     string,
    detail:   string,
    complete: bool,
    fields:   [dynamic]Field_Record,
    enums:    [dynamic]Enum_Record,
}

Builder :: struct {
    repo_root:       string,
    collection_root: string,
    packages:        map[string]^Package_Info,
    package_paths:   map[string]string,
    package_loading: map[string]bool,
    import_states:   map[string]int,
    type_states:     map[string]int,
    constant_states: map[string]int,
    constant_values: map[string]i64,
    records:         map[string]^Type_Record,
    failed:          bool,
    errors:          [dynamic]string,
}

new_builder :: proc(repo_root, collection_root: string) -> Builder {
    return Builder {
        repo_root = repo_root,
        collection_root = collection_root,
        packages = make(map[string]^Package_Info),
        package_paths = make(map[string]string),
        package_loading = make(map[string]bool),
        import_states = make(map[string]int),
        type_states = make(map[string]int),
        constant_states = make(map[string]int),
        constant_values = make(map[string]i64),
        records = make(map[string]^Type_Record),
    }
}

diagnostic :: proc(b: ^Builder, pos: tokenizer.Pos, type_path, message: string) {
    b.failed = true
    append(&b.errors, fmt.tprintf("%s:%d:%d: %s: %s", pos.file, pos.line, pos.column, type_path, message))
}

diagnostic_at :: proc(b: ^Builder, expr: ^ast.Expr, type_path, message: string) {
    if expr != nil {
        diagnostic(b, expr.pos, type_path, message)
    } else {
        b.failed = true
        append(&b.errors, fmt.tprintf("%s: %s: %s", ROOT_PACKAGE_ID, type_path, message))
    }
}

builder_error :: proc(b: ^Builder, message: string) {
    b.failed = true
    append(&b.errors, message)
}

file_tag_target_matches :: proc(value: string) -> (recognized, matches: bool) {
    name, _, _ := strings.partition(value, ":")
    for os in reflect.enum_fields_zipped(runtime.Odin_OS_Type) {
        os_type := runtime.Odin_OS_Type(os.value)
        if os_type != .Unknown && strings.equal_fold(os.name, name) {
            return true, ODIN_OS == os_type
        }
    }
    for arch in reflect.enum_fields_zipped(runtime.Odin_Arch_Type) {
        arch_type := runtime.Odin_Arch_Type(arch.value)
        if arch_type != .Unknown && strings.equal_fold(arch.name, name) {
            return true, ODIN_ARCH == arch_type
        }
    }
    return false, false
}

file_tag_line_matches :: proc(text: string) -> (matches, ignored: bool) {
    source := strings.trim_space(text)
    if len(source) == 0 || source[0] != '+' do return true, false
    index := 1
    directive_start := index
    for index < len(source) && source[index] != ' ' && source[index] != '\t' && source[index] != ',' {
        index += 1
    }
    directive := source[directive_start:index]
    if directive == "ignore" do return false, true
    if directive != "build" {
        return true, false
    }

    line_matches := false
    group_matches := true
    for index < len(source) {
        for index < len(source) && (source[index] == ' ' || source[index] == '\t') {
            index += 1
        }
        if index >= len(source) {
            line_matches ||= group_matches
            break
        }
        if source[index] == ',' {
            line_matches ||= group_matches
            group_matches = true
            index += 1
            continue
        }
        start := index
        for index < len(source) && source[index] != ' ' && source[index] != '\t' && source[index] != ',' {
            index += 1
        }
        value := source[start:index]
        if value == "ignore" do return false, true
        negative := len(value) > 0 && value[0] == '!'
        if negative do value = value[1:]
        recognized, target_matches := file_tag_target_matches(value)
        if recognized && (negative == target_matches) {
            group_matches = false
        }
    }
    line_matches ||= group_matches
    return line_matches, false
}

file_matches_build_target :: proc(file: ^ast.File) -> bool {
    if file.docs != nil {
        for comment in file.docs.list {
            if len(comment.text) < 3 || comment.text[:2] != "//" do continue
            matches, ignored := file_tag_line_matches(comment.text[2:])
            if ignored || !matches do return false
        }
    }
    for tag in file.tags {
        if tag.kind != .File_Tag || len(tag.text) < 2 || tag.text[:2] != "#+" do continue
        matches, ignored := file_tag_line_matches(tag.text[1:])
        if ignored || !matches do return false
    }
    return true
}

package_files :: proc(pkg: ^ast.Package) -> [dynamic]^ast.File {
    files: [dynamic]^ast.File
    for _, file in pkg.files {
        if !file_matches_build_target(file) do continue
        append(&files, file)
    }
    for index := 1; index < len(files); index += 1 {
        file := files[index]
        cursor := index
        for cursor > 0 && strings.compare(file.fullpath, files[cursor - 1].fullpath) < 0 {
            files[cursor] = files[cursor - 1]
            cursor -= 1
        }
        files[cursor] = file
    }
    return files
}

path_relative_to :: proc(base, path: string) -> string {
    relative, err := os.get_relative_path(base, path, context.allocator)
    if err != nil {
        return ""
    }
    normalized, _ := strings.replace_all(relative, "\\", "/")
    return normalized
}

logical_package_id :: proc(b: ^Builder, path: string) -> string {
    if strings.has_prefix(path, fmt.tprintf("%s/", b.collection_root)) {
        return fmt.tprintf("zelda_engine:%s", path_relative_to(b.collection_root, path))
    }
    if strings.has_prefix(path, fmt.tprintf("%s/", b.repo_root)) {
        relative := path_relative_to(b.repo_root, path)
        if relative == "src" {
            return ROOT_PACKAGE_ID
        }
        if strings.has_prefix(relative, "packages/") {
            return fmt.tprintf("adriatic:%s", relative)
        }
    }
    return fmt.tprintf("adriatic:%s", path_relative_to(b.repo_root, path))
}

package_path_from_import :: proc(b: ^Builder, current: ^Package_Info, import_path: string) -> (id, path: string) {
    if strings.has_prefix(import_path, "zelda_engine:") {
        relative := import_path[len("zelda_engine:"):]
        return fmt.tprintf("zelda_engine:%s", relative), fmt.tprintf("%s/%s", b.collection_root, relative)
    }
    if strings.has_prefix(import_path, "core:") ||
       strings.has_prefix(import_path, "base:") ||
       strings.has_prefix(import_path, "vendor:") {
        return import_path, ""
    }
    joined_path := fmt.tprintf("%s/%s", current.path, import_path)
    abs, abs_err := os.get_absolute_path(joined_path, context.allocator)
    if abs_err != nil do return
    return logical_package_id(b, abs), abs
}

import_alias :: proc(import_path: string) -> string {
    path := import_path
    if strings.has_prefix(path, "core:") {
        path = path[len("core:"):]
    } else if strings.has_prefix(path, "base:") {
        path = path[len("base:"):]
    } else if strings.has_prefix(path, "vendor:") {
        path = path[len("vendor:"):]
    } else if strings.has_prefix(path, "zelda_engine:") {
        path = path[len("zelda_engine:"):]
    }
    if i := strings.last_index_byte(path, '/'); i >= 0 {
        path = path[i + 1:]
    }
    if i := strings.last_index_byte(path, '\\'); i >= 0 {
        path = path[i + 1:]
    }
    return path
}

load_package :: proc(b: ^Builder, id, path: string) -> ^Package_Info {
    if info, ok := b.packages[id]; ok {
        return info
    }
    if path == "" {
        return nil
    }
    if b.package_loading[id] {
        builder_error(b, fmt.tprintf("%s: import cycle while loading %s", id, id))
        return nil
    }
    if !os.exists(path) {
        builder_error(b, fmt.tprintf("%s: package path does not exist: %s", id, path))
        return nil
    }

    b.package_loading[id] = true
    defer b.package_loading[id] = false
    pkg, ok := parser.parse_package_from_path(path)
    if !ok {
        builder_error(b, fmt.tprintf("%s: parser failed for package", id))
        return nil
    }

    info := new(Package_Info)
    info.id = id
    info.path = path
    info.pkg = pkg
    info.symbols = make(map[string]^Symbol)
    info.imports = make(map[string]^Import_Scope)
    info.dependencies = make(map[string]bool)
    b.packages[id] = info
    b.package_paths[id] = path

    for file in package_files(pkg) {
        for decl in file.decls {
            value := decl.derived_stmt.(^ast.Value_Decl) or_continue
            for name_expr, name_index in value.names {
                name := name_expr.derived_expr.(^ast.Ident) or_continue
                if _, duplicate := info.symbols[name.name]; duplicate {
                    diagnostic(b, name_expr.pos, id, fmt.tprintf("duplicate declaration %s", name.name))
                    continue
                }
                symbol := new(Symbol)
                symbol.name = name.name
                symbol.name_index = name_index
                symbol.value = value
                symbol.file = file
                info.symbols[name.name] = symbol
            }
        }
    }

    for file in package_files(pkg) {
        file_imports := new(Import_Scope)
        file_imports.aliases = make(map[string]string)
        info.imports[file.fullpath] = file_imports
        for import_decl in file.imports {
            import_path := strip_tag_delimiters(import_decl.relpath.text)
            target_id, target_path := package_path_from_import(b, info, import_path)
            if target_id == "" {
                diagnostic(b, import_decl.pos, id, fmt.tprintf("cannot resolve import %s", import_path))
                continue
            }
            if target_path != "" && !os.exists(target_path) {
                diagnostic(b, import_decl.pos, id, fmt.tprintf("import path does not exist: %s", target_id))
                continue
            }
            alias := import_decl.name.text
            if alias == "" && target_path != "" {
                target_info := load_package(b, target_id, target_path)
                if target_info != nil && target_info.pkg != nil {
                    alias = target_info.pkg.name
                }
            }
            if alias == "" {
                alias = import_alias(import_path)
            }
            if alias == "" {
                diagnostic(b, import_decl.pos, id, fmt.tprintf("import has no package name: %s", import_path))
                continue
            }
            if _, duplicate := file_imports.aliases[alias]; duplicate {
                diagnostic(b, import_decl.pos, id, fmt.tprintf("duplicate import alias %s", alias))
                continue
            }
            file_imports.aliases[alias] = target_id
            info.dependencies[target_id] = true
            if target_path != "" {
                b.package_paths[target_id] = target_path
            }
        }
    }
    return info
}

lookup_symbol :: proc(b: ^Builder, package_id, name: string) -> ^Symbol {
    info, ok := b.packages[package_id]
    if !ok do return nil
    return info.symbols[name]
}

import_target_for_expr :: proc(info: ^Package_Info, expr: ^ast.Expr, alias: string) -> (target: string, found: bool) {
    imports, ok := info.imports[expr.pos.file]
    if !ok do return
    target = imports.aliases[alias]
    return target, target != ""
}

resolve_selector :: proc(
    b: ^Builder,
    package_id: string,
    expr: ^ast.Selector_Expr,
    type_path: string,
) -> (
    target_package: string,
    symbol: ^Symbol,
) {
    root := ast.unparen_expr(expr.expr)
    ident, ident_ok := root.derived_expr.(^ast.Ident)
    if !ident_ok do ident = nil
    if ident == nil {
        diagnostic_at(b, expr.expr, type_path, "qualified selector has unsupported root")
        return
    }
    info, info_ok := b.packages[package_id]
    if !info_ok do info = nil
    if info == nil {
        diagnostic_at(b, expr.expr, type_path, "package is not loaded")
        return
    }
    found: bool
    target_package, found = import_target_for_expr(info, expr, ident.name)
    if !found {
        diagnostic_at(b, expr.expr, type_path, fmt.tprintf("unknown import alias %s", ident.name))
        return
    }
    target_path := b.package_paths[target_package]
    if target_path != "" {
        load_package(b, target_package, target_path)
        check_import_cycles(b, target_package)
    } else if strings.has_prefix(target_package, "core:") ||
       strings.has_prefix(target_package, "base:") ||
       strings.has_prefix(target_package, "vendor:") {
        diagnostic_at(
            b,
            expr,
            type_path,
            fmt.tprintf("reachable import %s cannot be resolved by fixture schema tool", target_package),
        )
        return
    }
    symbol = lookup_symbol(b, target_package, expr.field.name)
    if symbol == nil {
        diagnostic_at(b, expr.field, type_path, fmt.tprintf("missing symbol %s.%s", ident.name, expr.field.name))
    }
    return
}

check_import_cycles :: proc(b: ^Builder, package_id: string) -> bool {
    state := b.import_states[package_id]
    if state == 2 {
        return true
    }
    if state == 1 {
        builder_error(b, fmt.tprintf("%s: import cycle detected", package_id))
        return false
    }
    info := b.packages[package_id]
    if info == nil {
        return true
    }
    b.import_states[package_id] = 1
    for target_package, _ in info.dependencies {
        target_path := b.package_paths[target_package]
        if target_path == "" do continue
        if load_package(b, target_package, target_path) == nil do continue
        if !check_import_cycles(b, target_package) {
            return false
        }
    }
    b.import_states[package_id] = 2
    return true
}

resolve_name :: proc(
    b: ^Builder,
    package_id, name, type_path: string,
    expr: ^ast.Expr,
) -> (
    target_package: string,
    symbol: ^Symbol,
) {
    if symbol = lookup_symbol(b, package_id, name); symbol != nil {
        return package_id, symbol
    }
    diagnostic_at(b, expr, type_path, fmt.tprintf("missing symbol %s.%s", package_id, name))
    return
}

is_builtin :: proc(name: string) -> bool {
    switch name {
    case "bool",
         "b8",
         "u8",
         "u16",
         "u32",
         "u64",
         "u128",
         "i8",
         "i16",
         "i32",
         "i64",
         "i128",
         "int",
         "uint",
         "uintptr",
         "f16",
         "f32",
         "f64",
         "complex32",
         "complex64",
         "quaternion64",
         "quaternion128",
         "rune",
         "string",
         "cstring",
         "byte",
         "rawbyte":
        return true
    }
    return false
}

is_integer_type :: proc(name: string) -> bool {
    switch name {
    case "u8",
         "u16",
         "u32",
         "u64",
         "u128",
         "i8",
         "i16",
         "i32",
         "i64",
         "i128",
         "int",
         "uint",
         "uintptr",
         "byte",
         "rune":
        return true
    }
    return false
}

bool_int :: proc(value: bool) -> int {
    if value do return 1
    return 0
}

type_name :: proc(expr: ^ast.Expr) -> string {
    value := ast.unparen_expr(expr)
    if ident, ok := value.derived_expr.(^ast.Ident); ok {
        return ident.name
    }
    return ""
}

strip_tag_delimiters :: proc(text: string) -> string {
    if len(text) >= 2 &&
       ((text[0] == '`' && text[len(text) - 1] == '`') || (text[0] == '"' && text[len(text) - 1] == '"')) {
        return text[1:len(text) - 1]
    }
    return text
}

fixture_tag :: proc(field: ^ast.Field) -> (excluded: bool, tag: string) {
    if field.tag.kind == .Invalid {
        return false, ""
    }
    raw := strip_tag_delimiters(field.tag.text)
    value, ok := reflect.struct_tag_lookup(reflect.Struct_Tag(raw), "fixture")
    if ok && value == "-" {
        return true, ""
    }
    return false, raw
}

type_key :: proc(package_id, name: string) -> string {
    return fmt.tprintf("%s.%s", package_id, name)
}

declaration_type_expr :: proc(b: ^Builder, symbol: ^Symbol, type_path: string) -> ^ast.Expr {
    declaration := symbol.value
    if len(declaration.values) > 0 {
        if len(declaration.names) != len(declaration.values) {
            diagnostic_at(b, declaration.values[0], type_path, "multi-name declaration must have one value per name")
            return nil
        }
        if symbol.name_index >= len(declaration.values) {
            diagnostic_at(b, declaration.values[0], type_path, "declaration name has no matching value")
            return nil
        }
        return ast.unparen_expr(declaration.values[symbol.name_index])
    }
    if len(declaration.names) != 1 {
        diagnostic(b, declaration.pos, type_path, "multi-name declaration has no type value")
        return nil
    }
    if declaration.type != nil {
        return ast.unparen_expr(declaration.type)
    }
    diagnostic(b, declaration.pos, type_path, "declaration has no type expression")
    return nil
}

struct_detail :: proc(b: ^Builder, package_id: string, node: ^ast.Struct_Type, type_path: string) -> string {
    if node.poly_params != nil || len(node.where_clauses) > 0 {
        diagnostic_at(
            b,
            &node.node,
            type_path,
            "generic struct modifiers are not supported in persisted fixture schema",
        )
        return "invalid"
    }
    detail := fmt.tprintf(
        "packed=%d;raw_union=%d;no_copy=%d;all_or_none=%d;simple=%d",
        bool_int(node.is_packed),
        bool_int(node.is_raw_union),
        bool_int(node.is_no_copy),
        bool_int(node.is_all_or_none),
        bool_int(node.is_simple),
    )
    alignments := [3]^ast.Expr{node.align, node.min_field_align, node.max_field_align}
    names := [3]string{"align", "min_field_align", "max_field_align"}
    for expr, index in alignments {
        if expr == nil {
            detail = fmt.tprintf("%s;%s=none", detail, names[index])
            continue
        }
        value, ok := eval_constant_expr(b, package_id, expr, fmt.tprintf("%s.%s", type_path, names[index]))
        if !ok do return "invalid"
        if value < 0 {
            diagnostic_at(b, expr, type_path, fmt.tprintf("%s is negative", names[index]))
            return "invalid"
        }
        detail = fmt.tprintf("%s;%s=%d", detail, names[index], value)
    }
    return detail
}

ensure_record :: proc(b: ^Builder, package_id, name, type_path: string) -> string {
    key := type_key(package_id, name)
    if state := b.type_states[key]; state == 2 {
        return key
    } else if state == 1 {
        diagnostic_at(b, nil, type_path, fmt.tprintf("type alias cycle at %s", key))
        return "invalid"
    } else if state == 3 {
        return "invalid"
    }
    symbol := lookup_symbol(b, package_id, name)
    if symbol == nil {
        diagnostic_at(b, nil, type_path, fmt.tprintf("missing type %s", key))
        return "invalid"
    }
    b.type_states[key] = 1
    record := new(Type_Record)
    record.id = key
    record.kind = "alias"
    b.records[key] = record

    value_expr := declaration_type_expr(b, symbol, type_path)
    if value_expr == nil {
        b.type_states[key] = 3
        return "invalid"
    }

    #partial switch node in value_expr.derived_expr {
    case ^ast.Struct_Type:
        record.kind = "struct"
        record.detail = struct_detail(b, package_id, node, type_path)
        if record.detail == "invalid" {
            b.type_states[key] = 3
            return "invalid"
        }
        if node.fields != nil {
            for field in node.fields.list {
                excluded, tag := fixture_tag(field)
                if excluded do continue
                for name_expr in field.names {
                    field_name := name_expr.derived_expr.(^ast.Ident) or_continue
                    field_type_path := fmt.tprintf("%s.%s", type_path, field_name.name)
                    field_type_name := type_repr(b, package_id, field.type, field_type_path)
                    if field_type_name == "invalid" {
                        b.type_states[key] = 3
                        return "invalid"
                    }
                    append(
                        &record.fields,
                        Field_Record {
                            name = field_name.name,
                            tag = tag,
                            type = field_type_name,
                            is_using = bool_int(.Using in field.flags) != 0,
                        },
                    )
                }
            }
        }
    case ^ast.Enum_Type:
        record.kind = "enum"
        record.detail = fmt.tprintf("using=%d", bool_int(node.is_using))
        if node.base_type != nil {
            base_type := type_repr(b, package_id, node.base_type, fmt.tprintf("%s.base", type_path))
            if base_type == "invalid" {
                b.type_states[key] = 3
                return "invalid"
            }
            record.detail = fmt.tprintf("%s;base=%s", record.detail, base_type)
        } else {
            record.detail = fmt.tprintf("%s;base=int", record.detail)
        }
        current: i64 = -1
        for enum_expr in node.fields {
            name_expr := enum_expr
            enum_value_expr := enum_expr
            if field_value, ok := enum_expr.derived_expr.(^ast.Field_Value); ok {
                name_expr = field_value.field
                enum_value_expr = field_value.value
            }
            name_ident := ast.unparen_expr(name_expr).derived_expr.(^ast.Ident) or_continue
            if enum_value_expr == enum_expr {
                if current == I64_MAX {
                    diagnostic_at(b, enum_expr, type_path, "enum value overflow")
                    b.type_states[key] = 3
                    return "invalid"
                }
                current += 1
            } else {
                value, ok := eval_constant_expr(
                    b,
                    package_id,
                    enum_value_expr,
                    fmt.tprintf("%s.%s", type_path, name_ident.name),
                )
                if !ok {
                    b.type_states[key] = 3
                    return "invalid"
                }
                current = value
            }
            append(&record.enums, Enum_Record{name = name_ident.name, value = current})
        }
    case ^ast.Union_Type:
        record.kind = "union"
        record.detail = fmt.tprintf("kind=%v", node.kind)
        if node.align != nil {
            align, align_ok := eval_constant_expr(b, package_id, node.align, fmt.tprintf("%s.align", type_path))
            if !align_ok {
                b.type_states[key] = 3
                return "invalid"
            }
            record.detail = fmt.tprintf("%s;align=%d", record.detail, align)
        }
        for variant, index in node.variants {
            variant_type := type_repr(b, package_id, variant, fmt.tprintf("%s.variant%d", type_path, index))
            if variant_type == "invalid" {
                b.type_states[key] = 3
                return "invalid"
            }
            append(&record.fields, Field_Record{name = fmt.tprintf("variant%d", index), type = variant_type})
        }
    case ^ast.Distinct_Type:
        record.kind = "distinct"
        target := type_repr(b, package_id, node.type, fmt.tprintf("%s.target", type_path))
        if target == "invalid" {
            b.type_states[key] = 3
            return "invalid"
        }
        record.detail = fmt.tprintf("target=%s", target)
    case:
        target := type_repr(b, package_id, value_expr, fmt.tprintf("%s.target", type_path))
        if target == "invalid" {
            b.type_states[key] = 3
            return "invalid"
        }
        record.detail = fmt.tprintf("target=%s", target)
    }
    record.complete = true
    b.type_states[key] = 2
    return key
}

enumerated_array_info :: proc(
    b: ^Builder,
    package_id: string,
    expr: ^ast.Expr,
    type_path: string,
) -> (
    length: i64,
    index_type: string,
    matched: bool,
    ok: bool,
) {
    target_package := package_id
    symbol: ^Symbol
    value := ast.unparen_expr(expr)
    #partial switch node in value.derived_expr {
    case ^ast.Ident:
        symbol = lookup_symbol(b, package_id, node.name)
        if symbol == nil do return 0, "", false, true
    case ^ast.Selector_Expr:
        root := ast.unparen_expr(node.expr)
        root_ident, root_ok := root.derived_expr.(^ast.Ident)
        info, info_ok := b.packages[package_id]
        if !root_ok || !info_ok {
            return 0, "", false, true
        }
        _, imported := import_target_for_expr(info, value, root_ident.name)
        if !imported {
            return 0, "", false, true
        }
        target_package, symbol = resolve_selector(b, package_id, node, type_path)
        if symbol == nil do return 0, "", true, false
    case:
        return 0, "", false, true
    }

    declaration := symbol.value
    if len(declaration.names) != len(declaration.values) || symbol.name_index >= len(declaration.values) {
        return 0, "", false, true
    }
    declaration_expr := ast.unparen_expr(declaration.values[symbol.name_index])
    if _, is_enum := declaration_expr.derived_expr.(^ast.Enum_Type); !is_enum {
        return 0, "", false, true
    }

    key := ensure_record(b, target_package, symbol.name, type_path)
    if key == "invalid" do return 0, "", true, false
    record := b.records[key]
    if record == nil || record.kind != "enum" {
        diagnostic_at(b, expr, type_path, "enumerated array index is not an enum")
        return 0, "", true, false
    }
    if len(record.enums) == 0 {
        diagnostic_at(b, expr, type_path, "enumerated array index enum is empty")
        return 0, "", true, false
    }

    min_value := record.enums[0].value
    max_value := min_value
    for member, index in record.enums {
        min_value = min(min_value, member.value)
        max_value = max(max_value, member.value)
        for previous_index in 0 ..< index {
            if record.enums[previous_index].value == member.value {
                diagnostic_at(b, expr, type_path, "enumerated array index enum has duplicate values")
                return 0, "", true, false
            }
        }
    }
    span, span_ok := checked_sub(max_value, min_value)
    if !span_ok {
        diagnostic_at(b, expr, type_path, "enumerated array index range overflows")
        return 0, "", true, false
    }
    computed_length, length_ok := checked_add(span, 1)
    if !length_ok {
        diagnostic_at(b, expr, type_path, "enumerated array index range overflows")
        return 0, "", true, false
    }
    if computed_length != i64(len(record.enums)) {
        diagnostic_at(b, expr, type_path, "enumerated array index enum must be contiguous")
        return 0, "", true, false
    }
    return computed_length, key, true, true
}

type_repr :: proc(b: ^Builder, package_id: string, expr: ^ast.Expr, type_path: string) -> string {
    if expr == nil {
        diagnostic_at(b, expr, type_path, "missing type expression")
        return "invalid"
    }
    value := ast.unparen_expr(expr)
    #partial switch node in value.derived_expr {
    case ^ast.Ident:
        switch node.name {
        case "rawptr", "cstring", "any", "typeid":
            diagnostic_at(
                b,
                expr,
                type_path,
                fmt.tprintf("%s is not supported in persisted fixture schema", node.name),
            )
            return "invalid"
        }
        if is_builtin(node.name) {
            return fmt.tprintf("builtin:%s", node.name)
        }
        target_package, symbol := resolve_name(b, package_id, node.name, type_path, expr)
        if symbol == nil {
            return "invalid"
        }
        return ensure_record(b, target_package, node.name, type_path)
    case ^ast.Selector_Expr:
        target_package, symbol := resolve_selector(b, package_id, node, type_path)
        if symbol == nil {
            return "invalid"
        }
        return ensure_record(b, target_package, node.field.name, type_path)
    case ^ast.Pointer_Type:
        diagnostic_at(b, expr, type_path, "raw pointer is not allowed in persisted fixture schema")
        return "invalid"
    case ^ast.Multi_Pointer_Type:
        diagnostic_at(b, expr, type_path, "multi pointer is not allowed in persisted fixture schema")
        return "invalid"
    case ^ast.Relative_Type:
        diagnostic_at(b, expr, type_path, "relative pointer is not allowed in persisted fixture schema")
        return "invalid"
    case ^ast.Array_Type:
        if node.tag != nil {
            diagnostic_at(b, node.tag, type_path, "array type modifier is not supported in persisted fixture schema")
            return "invalid"
        }
        elem := type_repr(b, package_id, node.elem, fmt.tprintf("%s[]", type_path))
        if elem == "invalid" do return "invalid"
        if node.len == nil {
            return fmt.tprintf("slice<%s>", elem)
        }
        if unary, ok := ast.unparen_expr(node.len).derived_expr.(^ast.Unary_Expr); ok && unary.op.kind == .Question {
            return fmt.tprintf("dynamic_any<%s>", elem)
        }
        if length, index_type, matched, ok := enumerated_array_info(
            b,
            package_id,
            node.len,
            fmt.tprintf("%s.length", type_path),
        ); matched {
            if !ok do return "invalid"
            return fmt.tprintf("enumerated_array[%d;%s]<%s>", length, index_type, elem)
        }
        length, ok := eval_constant_expr(b, package_id, node.len, fmt.tprintf("%s.length", type_path))
        if !ok {
            return "invalid"
        }
        if length < 0 {
            diagnostic_at(b, node.len, type_path, "array length is negative")
            return "invalid"
        }
        return fmt.tprintf("array[%d]<%s>", length, elem)
    case ^ast.Dynamic_Array_Type:
        if node.tag != nil {
            diagnostic_at(
                b,
                node.tag,
                type_path,
                "dynamic array type modifier is not supported in persisted fixture schema",
            )
            return "invalid"
        }
        elem := type_repr(b, package_id, node.elem, fmt.tprintf("%s[]", type_path))
        if elem == "invalid" do return "invalid"
        return fmt.tprintf("dynamic<%s>", elem)
    case ^ast.Fixed_Capacity_Dynamic_Array_Type:
        if node.tag != nil {
            diagnostic_at(
                b,
                node.tag,
                type_path,
                "dynamic array type modifier is not supported in persisted fixture schema",
            )
            return "invalid"
        }
        capacity, ok := eval_constant_expr(b, package_id, node.capacity, fmt.tprintf("%s.capacity", type_path))
        if !ok do return "invalid"
        if capacity < 0 {
            diagnostic_at(b, node.capacity, type_path, "dynamic array capacity is negative")
            return "invalid"
        }
        elem := type_repr(b, package_id, node.elem, fmt.tprintf("%s[]", type_path))
        if elem == "invalid" do return "invalid"
        return fmt.tprintf("dynamic[%d]<%s>", capacity, elem)
    case ^ast.Map_Type:
        key := type_repr(b, package_id, node.key, fmt.tprintf("%s.key", type_path))
        value := type_repr(b, package_id, node.value, fmt.tprintf("%s.value", type_path))
        if key == "invalid" || value == "invalid" do return "invalid"
        return fmt.tprintf("map<%s,%s>", key, value)
    case ^ast.Matrix_Type:
        rows, rows_ok := eval_constant_expr(b, package_id, node.row_count, fmt.tprintf("%s.rows", type_path))
        columns, columns_ok := eval_constant_expr(
            b,
            package_id,
            node.column_count,
            fmt.tprintf("%s.columns", type_path),
        )
        if !rows_ok || !columns_ok do return "invalid"
        if rows < 0 || columns < 0 {
            diagnostic_at(b, expr, type_path, "matrix dimension is negative")
            return "invalid"
        }
        elem := type_repr(b, package_id, node.elem, fmt.tprintf("%s[]", type_path))
        if elem == "invalid" do return "invalid"
        return fmt.tprintf("matrix[%d,%d]<%s>", rows, columns, elem)
    case ^ast.Bit_Set_Type:
        elem := type_repr(b, package_id, node.elem, fmt.tprintf("%s.element", type_path))
        if elem == "invalid" do return "invalid"
        underlying := ""
        if node.underlying != nil {
            underlying_type := type_repr(b, package_id, node.underlying, fmt.tprintf("%s.underlying", type_path))
            if underlying_type == "invalid" do return "invalid"
            underlying = fmt.tprintf(";%s", underlying_type)
        }
        return fmt.tprintf("bitset<%s%s>", elem, underlying)
    case ^ast.Bit_Field_Type:
        backing := type_repr(b, package_id, node.backing_type, fmt.tprintf("%s.backing", type_path))
        if backing == "invalid" do return "invalid"
        detail := fmt.tprintf("bitfield<%s", backing)
        for field, index in node.fields {
            field_name, field_name_ok := field.name.derived_expr.(^ast.Ident)
            if !field_name_ok {
                diagnostic_at(
                    b,
                    field.name,
                    fmt.tprintf("%s.field%d", type_path, index),
                    "bit-field member name must be an identifier",
                )
                return "invalid"
            }
            field_type := type_repr(b, package_id, field.type, fmt.tprintf("%s.%s", type_path, field_name.name))
            if field_type == "invalid" do return "invalid"
            if field.bit_size == nil {
                diagnostic_at(b, field.name, type_path, "bit-field member is missing its width")
                return "invalid"
            }
            width, width_ok := eval_constant_expr(
                b,
                package_id,
                field.bit_size,
                fmt.tprintf("%s.%s.width", type_path, field_name.name),
            )
            if !width_ok do return "invalid"
            if width < 0 {
                diagnostic_at(b, field.bit_size, type_path, "bit-field width is negative")
                return "invalid"
            }
            tag := ""
            if field.tag.kind != .Invalid {
                tag = strip_tag_delimiters(field.tag.text)
            }
            detail = fmt.tprintf(
                "%s;field=%s;type=%s;width=%d;tag=%s",
                detail,
                field_name.name,
                field_type,
                width,
                tag,
            )
        }
        return fmt.tprintf("%s>", detail)
    case ^ast.Distinct_Type:
        target := type_repr(b, package_id, node.type, fmt.tprintf("%s.target", type_path))
        if target == "invalid" do return "invalid"
        return fmt.tprintf("distinct<%s>", target)
    case ^ast.Helper_Type:
        target := type_repr(b, package_id, node.type, type_path)
        if target == "invalid" do return "invalid"
        return fmt.tprintf("helper<%s>", target)
    case ^ast.Typeid_Type:
        diagnostic_at(b, expr, type_path, "typeid is not supported in persisted fixture schema")
        return "invalid"
    case ^ast.Proc_Type:
        diagnostic_at(b, expr, type_path, "procedure type is not allowed in persisted fixture schema")
        return "invalid"
    case ^ast.Struct_Type:
        key := fmt.tprintf("anonymous:%s", type_path)
        if _, exists := b.records[key]; !exists {
            anonymous := new(Type_Record)
            anonymous.id = key
            anonymous.kind = "struct"
            b.records[key] = anonymous
            anonymous.detail = struct_detail(b, package_id, node, type_path)
            if anonymous.detail == "invalid" do return "invalid"
            for field in node.fields.list {
                excluded, tag := fixture_tag(field)
                if excluded do continue
                for name_expr in field.names {
                    name := name_expr.derived_expr.(^ast.Ident) or_continue
                    field_type := type_repr(b, package_id, field.type, fmt.tprintf("%s.%s", type_path, name.name))
                    if field_type == "invalid" do return "invalid"
                    append(
                        &anonymous.fields,
                        Field_Record{name = name.name, tag = tag, type = field_type, is_using = .Using in field.flags},
                    )
                }
            }
            anonymous.complete = true
        }
        return key
    case ^ast.Union_Type, ^ast.Enum_Type:
        key := fmt.tprintf("anonymous:%s", type_path)
        if _, exists := b.records[key]; exists {
            return key
        }
        anonymous := new(Type_Record)
        anonymous.id = key
        b.records[key] = anonymous
        #partial switch node in value.derived_expr {
        case ^ast.Union_Type:
            anonymous.kind = "union"
            anonymous.detail = fmt.tprintf("kind=%v", node.kind)
            if node.align != nil {
                align, align_ok := eval_constant_expr(b, package_id, node.align, fmt.tprintf("%s.align", type_path))
                if !align_ok do return "invalid"
                anonymous.detail = fmt.tprintf("%s;align=%d", anonymous.detail, align)
            }
            for variant, index in node.variants {
                variant_type := type_repr(b, package_id, variant, fmt.tprintf("%s.variant%d", type_path, index))
                if variant_type == "invalid" do return "invalid"
                append(&anonymous.fields, Field_Record{name = fmt.tprintf("variant%d", index), type = variant_type})
            }
            anonymous.complete = true
        case ^ast.Enum_Type:
            anonymous.kind = "enum"
            anonymous.detail = fmt.tprintf("using=%d", bool_int(node.is_using))
            if node.base_type != nil {
                base_type := type_repr(b, package_id, node.base_type, fmt.tprintf("%s.base", type_path))
                if base_type == "invalid" do return "invalid"
                anonymous.detail = fmt.tprintf("%s;base=%s", anonymous.detail, base_type)
            } else {
                anonymous.detail = fmt.tprintf("%s;base=int", anonymous.detail)
            }
            current: i64 = -1
            for enum_expr in node.fields {
                name_expr := enum_expr
                enum_value_expr := enum_expr
                if field_value, ok := enum_expr.derived_expr.(^ast.Field_Value); ok {
                    name_expr = field_value.field
                    enum_value_expr = field_value.value
                }
                name_ident := ast.unparen_expr(name_expr).derived_expr.(^ast.Ident) or_continue
                if enum_value_expr == enum_expr {
                    if current == I64_MAX {
                        diagnostic_at(b, enum_expr, type_path, "enum value overflow")
                        return "invalid"
                    }
                    current += 1
                } else {
                    value, ok := eval_constant_expr(
                        b,
                        package_id,
                        enum_value_expr,
                        fmt.tprintf("%s.%s", type_path, name_ident.name),
                    )
                    if !ok do return "invalid"
                    current = value
                }
                append(&anonymous.enums, Enum_Record{name = name_ident.name, value = current})
            }
            anonymous.complete = true
        }
        return key
    case:
        diagnostic_at(b, expr, type_path, fmt.tprintf("unsupported type syntax %T", node))
        return "invalid"
    }
}

I64_MIN :: i64(-9223372036854775807 - 1)
I64_MAX :: i64(9223372036854775807)

constant_symbol_key :: proc(package_id, name: string) -> string {
    return fmt.tprintf("const:%s.%s", package_id, name)
}

eval_constant_symbol :: proc(b: ^Builder, package_id, name, type_path: string) -> (value: i64, ok: bool) {
    key := constant_symbol_key(package_id, name)
    if state := b.constant_states[key]; state == 2 {
        return b.constant_values[key], true
    } else if state == 1 {
        diagnostic_at(b, nil, type_path, fmt.tprintf("constant cycle at %s.%s", package_id, name))
        return 0, false
    } else if state == 3 {
        return 0, false
    }
    symbol := lookup_symbol(b, package_id, name)
    if symbol == nil || len(symbol.value.values) == 0 {
        diagnostic_at(b, nil, type_path, fmt.tprintf("missing constant %s.%s", package_id, name))
        b.constant_states[key] = 3
        return 0, false
    }
    if len(symbol.value.names) != len(symbol.value.values) {
        diagnostic_at(b, symbol.value.values[0], type_path, "multi-name constant must have one value per name")
        b.constant_states[key] = 3
        return 0, false
    }
    if symbol.name_index >= len(symbol.value.values) {
        diagnostic_at(b, symbol.value.values[0], type_path, "constant name has no matching value")
        b.constant_states[key] = 3
        return 0, false
    }
    b.constant_states[key] = 1
    value, ok = eval_constant_expr(b, package_id, symbol.value.values[symbol.name_index], type_path)
    if ok {
        b.constant_values[key] = value
        b.constant_states[key] = 2
    } else {
        b.constant_states[key] = 3
    }
    return
}

enum_member_value :: proc(
    b: ^Builder,
    package_id, enum_name, member_name, type_path: string,
) -> (
    value: i64,
    ok: bool,
) {
    key := ensure_record(b, package_id, enum_name, type_path)
    if key == "invalid" do return 0, false
    record := b.records[key]
    if record == nil || record.kind != "enum" {
        diagnostic_at(b, nil, type_path, fmt.tprintf("%s is not an enum", enum_name))
        return 0, false
    }
    for member in record.enums {
        if member.name == member_name {
            return member.value, true
        }
    }
    diagnostic_at(b, nil, type_path, fmt.tprintf("missing enum member %s.%s", enum_name, member_name))
    return 0, false
}

checked_add :: proc(lhs, rhs: i64) -> (i64, bool) {
    if rhs > 0 && lhs > I64_MAX - rhs do return 0, false
    if rhs < 0 && lhs < I64_MIN - rhs do return 0, false
    return lhs + rhs, true
}

checked_sub :: proc(lhs, rhs: i64) -> (i64, bool) {
    if rhs < 0 && lhs > I64_MAX + rhs do return 0, false
    if rhs > 0 && lhs < I64_MIN + rhs do return 0, false
    return lhs - rhs, true
}

checked_mul :: proc(lhs, rhs: i64) -> (i64, bool) {
    if lhs == 0 || rhs == 0 do return 0, true
    if lhs == -1 && rhs == I64_MIN || rhs == -1 && lhs == I64_MIN do return 0, false
    result := lhs * rhs
    if result / rhs != lhs do return 0, false
    return result, true
}

eval_constant_expr :: proc(
    b: ^Builder,
    package_id: string,
    expr: ^ast.Expr,
    type_path: string,
) -> (
    value: i64,
    ok: bool,
) {
    if expr == nil {
        diagnostic_at(b, expr, type_path, "missing constant expression")
        return 0, false
    }
    value_expr := ast.unparen_expr(expr)
    #partial switch node in value_expr.derived_expr {
    case ^ast.Basic_Lit:
        if node.tok.kind != .Integer {
            diagnostic_at(b, expr, type_path, "constant expression is not an integer")
            return 0, false
        }
        parsed_value, parse_ok := strconv.parse_i64(node.tok.text)
        if !parse_ok {
            diagnostic_at(b, expr, type_path, "integer literal is invalid or out of range")
            return 0, false
        }
        return parsed_value, true
    case ^ast.Ident:
        return eval_constant_symbol(b, package_id, node.name, type_path)
    case ^ast.Selector_Expr:
        root := ast.unparen_expr(node.expr)
        if root_ident, root_ok := root.derived_expr.(^ast.Ident); root_ok {
            if info, info_ok := b.packages[package_id]; info_ok {
                _, imported := import_target_for_expr(info, value_expr, root_ident.name)
                if !imported && lookup_symbol(b, package_id, root_ident.name) != nil {
                    return enum_member_value(b, package_id, root_ident.name, node.field.name, type_path)
                }
            }
        }
        target_package, symbol := resolve_selector(b, package_id, node, type_path)
        if symbol == nil do return 0, false
        return eval_constant_symbol(b, target_package, node.field.name, type_path)
    case ^ast.Unary_Expr:
        operand, operand_ok := eval_constant_expr(b, package_id, node.expr, type_path)
        if !operand_ok do return 0, false
        #partial switch node.op.kind {
        case .Add:
            return operand, true
        case .Sub:
            if operand == I64_MIN {
                diagnostic_at(b, expr, type_path, "integer negation overflow")
                return 0, false
            }
            return -operand, true
        case .Xor:
            return ~operand, true
        case:
            diagnostic_at(b, expr, type_path, "unsupported unary constant operator")
            return 0, false
        }
    case ^ast.Binary_Expr:
        lhs, lhs_ok := eval_constant_expr(b, package_id, node.left, type_path)
        rhs, rhs_ok := eval_constant_expr(b, package_id, node.right, type_path)
        if !lhs_ok || !rhs_ok do return 0, false
        #partial switch node.op.kind {
        case .Add:
            result, result_ok := checked_add(lhs, rhs)
            if !result_ok {
                diagnostic_at(b, expr, type_path, "integer addition overflow")
                return 0, false
            }
            return result, true
        case .Sub:
            result, result_ok := checked_sub(lhs, rhs)
            if !result_ok {
                diagnostic_at(b, expr, type_path, "integer subtraction overflow")
                return 0, false
            }
            return result, true
        case .Mul:
            result, result_ok := checked_mul(lhs, rhs)
            if !result_ok {
                diagnostic_at(b, expr, type_path, "integer multiplication overflow")
                return 0, false
            }
            return result, true
        case .Quo:
            if rhs == 0 {
                diagnostic_at(b, expr, type_path, "division by zero")
                return 0, false
            }
            if lhs == I64_MIN && rhs == -1 {
                diagnostic_at(b, expr, type_path, "integer division overflow")
                return 0, false
            }
            return lhs / rhs, true
        case .Mod:
            if rhs == 0 {
                diagnostic_at(b, expr, type_path, "modulo by zero")
                return 0, false
            }
            if lhs == I64_MIN && rhs == -1 {
                diagnostic_at(b, expr, type_path, "integer modulo overflow")
                return 0, false
            }
            return lhs % rhs, true
        case .And:
            return lhs & rhs, true
        case .Or:
            return lhs | rhs, true
        case .Xor:
            return lhs ~ rhs, true
        case .And_Not:
            return lhs &~ rhs, true
        case .Shl, .Shr:
            if rhs < 0 || rhs >= 64 {
                diagnostic_at(b, expr, type_path, "shift count must be between 0 and 63")
                return 0, false
            }
            if node.op.kind == .Shl {
                result := lhs << uint(rhs)
                if rhs > 0 && (result >> uint(rhs)) != lhs {
                    diagnostic_at(b, expr, type_path, "left shift overflow")
                    return 0, false
                }
                return result, true
            }
            return lhs >> uint(rhs), true
        case:
            diagnostic_at(b, expr, type_path, "unsupported binary constant operator")
            return 0, false
        }
    case ^ast.Type_Cast:
        name := type_name(node.type)
        if !is_integer_type(name) {
            diagnostic_at(b, node.type, type_path, "constant cast target is not an integer type")
            return 0, false
        }
        return eval_constant_expr(b, package_id, node.expr, type_path)
    case ^ast.Call_Expr:
        if type_name(node.expr) == "len" && len(node.args) == 1 {
            argument := ast.unparen_expr(node.args[0])
            target_package := package_id
            symbol: ^Symbol
            #partial switch node in argument.derived_expr {
            case ^ast.Ident:
                target_package, symbol = resolve_name(b, package_id, node.name, type_path, argument)
            case ^ast.Selector_Expr:
                target_package, symbol = resolve_selector(b, package_id, node, type_path)
            }
            if symbol != nil {
                declared_type := symbol.value.type
                if declared_type == nil {
                    if symbol.name_index < len(symbol.value.values) {
                        value := ast.unparen_expr(symbol.value.values[symbol.name_index])
                        if compound, compound_ok := value.derived_expr.(^ast.Comp_Lit); compound_ok {
                            declared_type = compound.type
                        }
                    }
                }
                if declared_type != nil {
                    if array, array_ok := ast.unparen_expr(declared_type).derived_expr.(^ast.Array_Type); array_ok {
                        if array.len != nil {
                            return eval_constant_expr(b, target_package, array.len, type_path)
                        }
                    }
                }
            }
            diagnostic_at(b, node.args[0], type_path, "len requires a fixed-size array constant")
            return 0, false
        }
        name := type_name(node.expr)
        if !is_integer_type(name) || len(node.args) != 1 {
            diagnostic_at(b, expr, type_path, "only one-argument integer casts are supported")
            return 0, false
        }
        return eval_constant_expr(b, package_id, node.args[0], type_path)
    case:
        diagnostic_at(b, expr, type_path, fmt.tprintf("unsupported constant syntax %T", node))
    }
    diagnostic_at(b, expr, type_path, "constant expression could not be evaluated")
    return 0, false
}

escape :: proc(value: string) -> string {
    b := strings.builder_make()
    for ch in value {
        switch ch {
        case '\\':
            strings.write_string(&b, "\\\\")
        case '\t':
            strings.write_string(&b, "\\t")
        case '\n':
            strings.write_string(&b, "\\n")
        case '=':
            strings.write_string(&b, "\\=")
        case '|':
            strings.write_string(&b, "\\|")
        case:
            strings.write_rune(&b, ch)
        }
    }
    return strings.to_string(b)
}

sorted_records :: proc(b: ^Builder) -> [dynamic]^Type_Record {
    records: [dynamic]^Type_Record
    for _, record in b.records {
        append(&records, record)
    }
    for index := 1; index < len(records); index += 1 {
        record := records[index]
        cursor := index
        for cursor > 0 && strings.compare(record.id, records[cursor - 1].id) < 0 {
            records[cursor] = records[cursor - 1]
            cursor -= 1
        }
        records[cursor] = record
    }
    return records
}

records_complete :: proc(b: ^Builder) -> bool {
    complete := true
    for id, record in b.records {
        if record != nil && record.complete do continue
        builder_error(b, fmt.tprintf("%s: incomplete type record", id))
        complete = false
    }
    return complete
}

diagnostics_text :: proc(errors: [dynamic]string) -> string {
    builder := strings.builder_make()
    for error in errors {
        fmt.sbprintf(&builder, "%s\n", error)
    }
    return strings.to_string(builder)
}

build_manifest_report :: proc(
    repo_root, collection_root: string,
) -> (
    manifest: string,
    version: int,
    ok: bool,
    diagnostics: string,
) {
    repo_abs, repo_err := os.get_absolute_path(repo_root, context.allocator)
    if repo_err != nil {
        diagnostics = "fixture schema: invalid repository root\n"
        return
    }
    collection_abs, collection_err := os.get_absolute_path(collection_root, context.allocator)
    if collection_err != nil {
        diagnostics = "fixture schema: invalid collection root\n"
        return
    }
    b := new_builder(repo_abs, collection_abs)
    root_path, root_path_ok := filepath.join({repo_abs, "src"}, context.allocator)
    if root_path_ok != nil {
        builder_error(&b, "fixture schema: cannot resolve source root")
        diagnostics = diagnostics_text(b.errors)
        return
    }
    root := load_package(&b, ROOT_PACKAGE_ID, root_path)
    if root == nil {
        diagnostics = diagnostics_text(b.errors)
        return
    }
    version_symbol := root.symbols["FIXTURE_SCHEMA_VERSION"]
    if version_symbol == nil {
        builder_error(&b, "adriatic:src.FIXTURE_SCHEMA_VERSION: source-owned immutable integer declaration required")
        diagnostics = diagnostics_text(b.errors)
        return
    }
    if version_symbol.value.is_mutable {
        diagnostic(&b, version_symbol.value.pos, "FIXTURE_SCHEMA_VERSION", "schema version must be immutable")
        diagnostics = diagnostics_text(b.errors)
        return
    }
    if len(version_symbol.value.names) != 1 || len(version_symbol.value.values) != 1 {
        builder_error(&b, "adriatic:src.FIXTURE_SCHEMA_VERSION: source-owned immutable integer declaration required")
        diagnostics = diagnostics_text(b.errors)
        return
    }
    version_value, version_ok := eval_constant_expr(
        &b,
        ROOT_PACKAGE_ID,
        version_symbol.value.values[0],
        "FIXTURE_SCHEMA_VERSION",
    )
    if !version_ok || version_value <= 0 || version_value > 9999 {
        if version_ok {
            diagnostic_at(
                &b,
                version_symbol.value.values[0],
                "FIXTURE_SCHEMA_VERSION",
                "must resolve to a positive integer",
            )
        }
        diagnostics = diagnostics_text(b.errors)
        return
    }
    version = int(version_value)
    root_symbol := root.symbols[ROOT_TYPE_NAME]
    if root_symbol == nil {
        builder_error(&b, "adriatic:src.Fixture: root type not found")
        diagnostics = diagnostics_text(b.errors)
        return
    }
    root_type := ensure_record(&b, ROOT_PACKAGE_ID, ROOT_TYPE_NAME, ROOT_TYPE_NAME)
    if root_type == "invalid" || b.failed {
        diagnostics = diagnostics_text(b.errors)
        return
    }
    if !records_complete(&b) || b.failed {
        diagnostics = diagnostics_text(b.errors)
        return
    }

    builder := strings.builder_make()
    fmt.sbprintf(&builder, "format_version=1\n")
    fmt.sbprintf(&builder, "fixture_schema_version=%d\n", version)
    fmt.sbprintf(&builder, "root=%s\n", escape(root_type))
    for record in sorted_records(&b) {
        fmt.sbprintf(
            &builder,
            "type=%s|kind=%s|detail=%s\n",
            escape(record.id),
            escape(record.kind),
            escape(record.detail),
        )
        for field in record.fields {
            fmt.sbprintf(
                &builder,
                "field=%s|name=%s|using=%d|tag=%s|type=%s\n",
                escape(record.id),
                escape(field.name),
                bool_int(field.is_using),
                escape(field.tag),
                escape(field.type),
            )
        }
        for enum_record in record.enums {
            fmt.sbprintf(
                &builder,
                "enum=%s|name=%s|value=%d\n",
                escape(record.id),
                escape(enum_record.name),
                enum_record.value,
            )
        }
    }
    manifest = strings.to_string(builder)
    return manifest, version, true, ""
}

build_manifest :: proc(repo_root, collection_root: string) -> (manifest: string, version: int, ok: bool) {
    diagnostics: string
    manifest, version, ok, diagnostics = build_manifest_report(repo_root, collection_root)
    if !ok && diagnostics != "" {
        fmt.eprint(diagnostics)
    }
    return
}

manifest_path :: proc(repo_root: string, version: int) -> string {
    path, err := filepath.join(
        {repo_root, "fixtures", "schema", fmt.tprintf("v%04d.fixture-schema", version)},
        context.allocator,
    )
    if err != nil do return ""
    return path
}

compare_manifest :: proc(expected, actual: string) -> (same: bool, message: string) {
    if expected == actual {
        return true, ""
    }
    expected_lines := strings.split(expected, "\n")
    actual_lines := strings.split(actual, "\n")
    count := min(len(expected_lines), len(actual_lines))
    for index in 0 ..< count {
        if expected_lines[index] != actual_lines[index] {
            return false, fmt.tprintf(
                "first difference at line %d: expected %s, generated %s",
                index + 1,
                expected_lines[index],
                actual_lines[index],
            )
        }
    }
    return false, fmt.tprintf(
        "generated schema has %d lines, manifest has %d lines",
        len(actual_lines),
        len(expected_lines),
    )
}

write_manifest :: proc(repo_root, path, manifest: string) -> bool {
    directory := fmt.tprintf("%s/fixtures/schema", repo_root)
    if !os.exists(directory) {
        directory_error := os.make_directory_all(directory)
        if directory_error != nil && !os.exists(directory) {
            fmt.eprintln(
                "fixture schema: cannot create manifest directory ",
                directory,
                " (",
                os.error_string(directory_error),
                ")",
            )
            return false
        }
    }
    temporary := fmt.tprintf("%s.tmp", path)
    if err := os.write_entire_file(temporary, manifest); err != nil {
        fmt.eprintln("fixture schema: cannot write temporary manifest")
        return false
    }
    if err := os.rename(temporary, path); err != nil {
        os.remove(temporary)
        fmt.eprintln("fixture schema: cannot install manifest")
        return false
    }
    return true
}
