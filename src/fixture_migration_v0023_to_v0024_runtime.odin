package main

import fixture_v0023 "../packages/fixture_history/v0023"
import "core:mem"

fixture_migration_step_v0023_to_v0024 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 23 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0023_TO_V0024_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0023_TO_V0024_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    return fixture_migrate_v0023_to_v0024(
        fixture_v0023.Fixture{},
        step_context.tentative,
        step_context.transaction_allocator,
    )
}
