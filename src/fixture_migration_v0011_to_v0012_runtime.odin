package main

import atmosphere "../packages/atmosphere"
import "core:mem"

fixture_migration_step_v0011_to_v0012 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 11 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0011_TO_V0012_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0011_TO_V0012_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    step_context.tentative.atmosphere.climate = {}
    atmosphere.initialize_climate(&step_context.tentative.atmosphere)
    step_context.tentative.tweak.atmosphere.climate = {}
    atmosphere.initialize_climate(&step_context.tentative.tweak.atmosphere)
    return {}
}
