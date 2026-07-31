package main

import terrain "../packages/terrain"
import "core:mem"

fixture_migration_step_v0008_to_v0009 :: proc(
    step_context: ^Fixture_Migration_Step_Context,
) -> Fixture_Migration_Error {
    if step_context == nil ||
       step_context.tentative == nil ||
       step_context.source_version < 1 ||
       step_context.source_version > 8 ||
       step_context.step_from_version != FIXTURE_MIGRATION_V0008_TO_V0009_FROM_VERSION ||
       step_context.step_to_version != FIXTURE_MIGRATION_V0008_TO_V0009_TO_VERSION ||
       step_context.target_version < step_context.step_to_version ||
       step_context.transaction_allocator.procedure != mem.dynamic_arena_allocator_proc {
        return {kind = .Invalid_Argument}
    }
    step_context.tentative.default_map_regeneration_seeds = terrain.DEFAULT_ISLAND_SEEDS
    step_context.tentative.default_marinas = {}
    step_context.tentative.default_harbors = {}
    step_context.tentative.default_marina_islands = {}
    step_context.tentative.default_marina_count = 0
    return {}
}
