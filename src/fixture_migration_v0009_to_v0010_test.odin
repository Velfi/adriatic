package main

import fixture_v0009 "../packages/fixture_history/v0009"
import hs "../packages/hs"
import "base:runtime"
import "core:testing"

when ODIN_TEST {
    @(test)
    fixture_migration_v0009_to_v0010_initializes_empty_mailbox :: proc(t: ^testing.T) {
        historical := new(fixture_v0009.Fixture)
        testing.expect(t, historical != nil)
        if historical == nil do return
        defer free(historical)
        historical.story_state.completed_deliveries = 7
        payload, portable_error, encoded := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0009.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        testing.expect(t, encoded && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        if !encoded do return
        defer delete(payload)
        result, migration_error, migrated := fixture_migration_run_with_registry(
            payload, 9, FIXTURE_SCHEMA_VERSION, fixture_migration_production_registry(), runtime.default_allocator(),
        )
        defer fixture_migration_error_dispose(&migration_error)
        defer fixture_migration_result_dispose(&result)
        testing.expect(t, migrated && migration_error.kind == .None)
        if !migrated do return
        testing.expect(t, result.fixture.player_mail.received == [3]bool{})
        testing.expect(t, result.fixture.player_mail.read == [3]bool{})
        registry := fixture_migration_production_registry()
        testing.expect(t, len(registry.steps) == FIXTURE_SCHEMA_VERSION - 1)
        testing.expect(t, registry.steps[8].wrapper == fixture_migration_step_v0009_to_v0010)
    }
}
