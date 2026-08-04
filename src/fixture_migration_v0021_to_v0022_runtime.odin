package main

import fixture_v0021 "../packages/fixture_history/v0021"
import "core:mem"

fixture_migration_step_v0021_to_v0022 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 21 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0021_TO_V0022_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0021_TO_V0022_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    return fixture_migrate_v0021_to_v0022(
        fixture_v0021.Fixture{},
        step_context.tentative,
        step_context.transaction_allocator,
    )
}
