package main

import "core:mem"

fixture_migration_step_v0015_to_v0016 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 15 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0015_TO_V0016_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0015_TO_V0016_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    // Structural decode zero-initializes fields absent from the source schema.
    step_context.tentative.note_count = 0
    return fixture_v0016_validate_notes(step_context.tentative)
}
