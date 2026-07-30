package main

import "core:mem"

fixture_migration_step_v0005_to_v0006 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 5 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0005_TO_V0006_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0005_TO_V0006_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    transaction_arena := cast(^mem.Dynamic_Arena)step_context.transaction_allocator.data
    if transaction_arena == nil || transaction_arena.block_allocator.procedure == nil {
        return {kind = .Invalid_Argument}
    }
    return fixture_migration_v0005_to_v0006_tentative(step_context.tentative, step_context.transaction_allocator)
}
