package main

import fixture_v0008 "../packages/fixture_history/v0008"
import hs "../packages/hs"
import terrain "../packages/terrain"
import "base:runtime"
import "core:testing"

when ODIN_TEST {
    @(test)
    fixture_migration_v0008_to_v0009_initializes_generation_provenance :: proc(t: ^testing.T) {
        historical := new(fixture_v0008.Fixture)
        testing.expect(t, historical != nil)
        if historical == nil do return
        defer free(historical)

        payload, portable_error, encoded := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0008.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        testing.expect(t, encoded && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        if !encoded do return
        defer delete(payload)

        result, migration_error, migrated := fixture_migration_run_with_registry(
            payload,
            8,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_production_registry(),
            runtime.default_allocator(),
        )
        defer fixture_migration_error_dispose(&migration_error)
        defer fixture_migration_result_dispose(&result)
        testing.expect(t, migrated && migration_error.kind == .None)
        if !migrated do return

        testing.expect_value(t, result.fixture.default_map_regeneration_seeds, terrain.DEFAULT_ISLAND_SEEDS)
        testing.expect(t, result.fixture.default_marina_count == 0)
        testing.expect(t, !result.fixture.default_marinas[0].valid)
        testing.expect(t, !result.fixture.default_harbors[0].valid)

        registry := fixture_migration_production_registry()
        testing.expect(t, len(registry.steps) == FIXTURE_SCHEMA_VERSION - 1)
        testing.expect(t, registry.steps[7].from_version == 8)
        testing.expect(t, registry.steps[7].to_version == 9)
        testing.expect(t, registry.steps[7].wrapper == fixture_migration_step_v0008_to_v0009)
    }
}
