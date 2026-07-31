package main

import atmosphere "../packages/atmosphere"
import "core:mem"

fixture_migration_step_v0010_to_v0011 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 10 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0010_TO_V0011_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0010_TO_V0011_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    step_context.tentative.atmosphere.schedule = {}
    atmosphere.initialize_schedule(&step_context.tentative.atmosphere)
    step_context.tentative.tweak.atmosphere.schedule = {}
    atmosphere.initialize_schedule(&step_context.tentative.tweak.atmosphere)
    return {}
}
