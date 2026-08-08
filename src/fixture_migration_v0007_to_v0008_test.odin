package main

import fixture_v0007 "../packages/fixture_history/v0007"
import story "../packages/story"
import "base:runtime"
import "core:testing"
import hs "zelda_engine:hs"

when ODIN_TEST {
    @(test)
    fixture_migration_v0007_to_v0008_preserves_residents_and_initializes_mirna :: proc(t: ^testing.T) {
        historical := new(fixture_v0007.Fixture)
        testing.expect(t, historical != nil)
        if historical == nil do return
        defer free(historical)

        for index in 0 ..< len(historical.story_state.resident_action_seen) {
            resident := fixture_v0007.History_Type_0108(index)
            historical.story_state.resident_action_seen[resident] = u64(index + 101)
        }
        payload, portable_error, encoded := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0007.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        testing.expect(t, encoded && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        if !encoded do return
        defer delete(payload)

        result, migration_error, migrated := fixture_migration_run_with_registry(
            payload,
            7,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_production_registry(),
            runtime.default_allocator(),
        )
        defer fixture_migration_error_dispose(&migration_error)
        defer fixture_migration_result_dispose(&result)
        testing.expect(t, migrated && migration_error.kind == .None)
        if !migrated do return

        for index in 0 ..< len(historical.story_state.resident_action_seen) {
            historical_resident := fixture_v0007.History_Type_0108(index)
            testing.expect(
                t,
                result.fixture.story_state.resident_action_seen[story.Resident(index)] ==
                historical.story_state.resident_action_seen[historical_resident],
            )
        }
        testing.expect(t, result.fixture.story_state.resident_action_seen[.Mirna] == 0)

        registry := fixture_migration_production_registry()
        testing.expect(t, len(registry.steps) == FIXTURE_SCHEMA_VERSION - 1)
        testing.expect(t, registry.steps[6].from_version == 7)
        testing.expect(t, registry.steps[6].to_version == 8)
        testing.expect(t, registry.steps[6].wrapper == fixture_migration_step_v0007_to_v0008)
    }
}
