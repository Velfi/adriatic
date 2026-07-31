package main

import "core:mem"

fixture_migration_step_v0014_to_v0015 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 14 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0014_TO_V0015_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0014_TO_V0015_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    return fixture_v0015_validate_wing_trails(step_context.tentative)
}
