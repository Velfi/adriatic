package main

import "core:mem"

Fixture_Migration_Resolution_Kind :: enum {
    Unresolved,
    Automatic,
    Scripted,
}

Fixture_Migration_Resolution :: struct {
    change_id: string,
    kind:      Fixture_Migration_Resolution_Kind,
}

Fixture_Migration_Error_Kind :: enum {
    None,
    Unresolved,
    Invalid_Argument,
    Invalid_Registry,
    Unsupported_Version,
    Tentative_Decode,
    Historical_Decode,
    Step_Failure,
    Invalid_Source,
    Out_Of_Memory,
}

Fixture_Migration_Error :: struct {
    kind:      Fixture_Migration_Error_Kind,
    change_id: string,
}

Fixture_Migration_Step_Context :: struct {
    source_payload:        []byte,
    source_version:        int,
    target_version:        int,
    step_from_version:     int,
    step_to_version:       int,
    tentative:             ^Fixture,
    transaction_allocator: mem.Allocator,
}

Fixture_Migration_Step_Proc :: #type proc(step_context: ^Fixture_Migration_Step_Context) -> Fixture_Migration_Error

Fixture_Migration_Step :: struct {
    from_version: int,
    to_version:   int,
    wrapper:      Fixture_Migration_Step_Proc,
    change_id:    string,
}

Fixture_Migration_Registry :: struct {
    steps: []Fixture_Migration_Step,
}

Fixture_Migration_Result :: struct {
    fixture:         ^Fixture,
    arena:           ^mem.Dynamic_Arena,
    arena_allocator: mem.Allocator,
}

fixture_migration_error_dispose :: proc(error: ^Fixture_Migration_Error) {
    if error == nil do return
    error.kind = .None
    error.change_id = ""
}

fixture_migration_result_dispose :: proc(result: ^Fixture_Migration_Result) {
    if result == nil do return
    if result.arena != nil {
        mem.dynamic_arena_destroy(result.arena)
        _ = mem.free(rawptr(result.arena), result.arena_allocator)
    }
    result.fixture = nil
    result.arena = nil
    result.arena_allocator = {}
}

fixture_migration_result_empty :: proc(result: ^Fixture_Migration_Result) -> bool {
    return result == nil || result.fixture == nil
}
