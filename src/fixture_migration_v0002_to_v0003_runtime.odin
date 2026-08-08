package main

import fixture_v0002 "../packages/fixture_history/v0002"
import "core:mem"
import hs "zelda_engine:hs"

fixture_migration_step_v0002_to_v0003 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       (step_context.source_version != 1 && step_context.source_version != 2) ||
       step_context.target_version < 3 ||
       step_context.step_from_version != 2 ||
       step_context.step_to_version != 3 ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    transaction_arena := cast(^mem.Dynamic_Arena)step_context.transaction_allocator.data
    if transaction_arena == nil || transaction_arena.block_allocator.procedure == nil {
        return {kind = .Invalid_Argument}
    }

    if step_context.source_version == 1 {
        return fixture_migration_v0002_to_v0003_resolve_occupant(step_context.tentative)
    }

    historical_arena: mem.Dynamic_Arena
    historical_allocator, arena_ok := fixture_migration_arena_prepare(
        &historical_arena,
        transaction_arena.block_allocator,
    )
    if !arena_ok do return {kind = .Out_Of_Memory}
    defer mem.dynamic_arena_destroy(&historical_arena)

    historical := new(fixture_v0002.Fixture, historical_allocator)
    if historical == nil do return {kind = .Out_Of_Memory}
    historical_value := any {
        data = rawptr(historical),
        id   = typeid_of(fixture_v0002.Fixture),
    }
    portable_error, portable_ok := hs.portable_decode(
        historical_value,
        step_context.source_payload,
        fixture_codec_historical_portable_config(),
        historical_allocator,
    )
    if !portable_ok {
        error_kind := fixture_migration_decode_kind(portable_error, .Historical_Decode)
        hs.portable_error_dispose(&portable_error)
        return {kind = error_kind}
    }
    hs.portable_error_dispose(&portable_error)

    return fixture_migrate_v0002_to_v0003(historical^, step_context.tentative, step_context.transaction_allocator)
}
