package main

import fixture_v0018 "../packages/fixture_history/v0018"
import hs "../packages/hs"
import "core:mem"

fixture_migration_step_v0018_to_v0019 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 18 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0018_TO_V0019_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0018_TO_V0019_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }

    if step_context.source_version == 18 {
        transaction_arena := cast(^mem.Dynamic_Arena)step_context.transaction_allocator.data
        if transaction_arena == nil || transaction_arena.block_allocator.procedure == nil {
            return {kind = .Invalid_Argument}
        }
        historical_arena: mem.Dynamic_Arena
        historical_allocator, arena_ok := fixture_migration_arena_prepare(
            &historical_arena,
            transaction_arena.block_allocator,
        )
        if !arena_ok do return {kind = .Out_Of_Memory}
        defer mem.dynamic_arena_destroy(&historical_arena)

        historical_ptr := new(fixture_v0018.Fixture, historical_allocator)
        if historical_ptr == nil do return {kind = .Out_Of_Memory}
        portable_error, portable_ok := hs.portable_decode(
            any{data = rawptr(historical_ptr), id = typeid_of(fixture_v0018.Fixture)},
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
        return fixture_migrate_v0018_to_v0019(
            historical_ptr^,
            step_context.tentative,
            step_context.transaction_allocator,
        )
    }
    return fixture_v0019_apply_map_source("", step_context.tentative, step_context.transaction_allocator)
}
