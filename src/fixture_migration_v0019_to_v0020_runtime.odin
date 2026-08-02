package main

import fixture_v0019 "../packages/fixture_history/v0019"
import "core:mem"

fixture_migration_step_v0019_to_v0020 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 19 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0019_TO_V0020_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0019_TO_V0020_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    return fixture_migrate_v0019_to_v0020(
        fixture_v0019.Fixture{},
        step_context.tentative,
        step_context.transaction_allocator,
    )
}
