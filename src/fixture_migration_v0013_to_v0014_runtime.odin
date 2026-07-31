package main

import "core:mem"

fixture_migration_step_v0013_to_v0014 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 13 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0013_TO_V0014_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0013_TO_V0014_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    fixture_v0014_initialize_cliff_tool(step_context.tentative)
    return {}
}
