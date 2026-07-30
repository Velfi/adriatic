package main

import "core:mem"

fixture_migration_step_v0007_to_v0008 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 7 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0007_TO_V0008_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0007_TO_V0008_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    step_context.tentative.story_state.resident_action_seen[.Mirna] = 0
    return {}
}
