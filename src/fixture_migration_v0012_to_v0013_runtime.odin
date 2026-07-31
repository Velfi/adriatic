package main

import "core:mem"

fixture_migration_step_v0012_to_v0013 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 12 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0012_TO_V0013_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0012_TO_V0013_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    // Clinic is append-only in both enums; every v12 ordinal is already the
    // corresponding v13 ordinal after portable decode.
    return {}
}
