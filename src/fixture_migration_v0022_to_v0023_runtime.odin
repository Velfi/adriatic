package main

import fixture_v0022 "../packages/fixture_history/v0022"
import "core:mem"

fixture_migration_step_v0022_to_v0023 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 22 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0022_TO_V0023_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0022_TO_V0023_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    return fixture_migrate_v0022_to_v0023(
        fixture_v0022.Fixture{},
        step_context.tentative,
        step_context.transaction_allocator,
    )
}
