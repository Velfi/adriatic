package main

import buildings "../packages/buildings"
import fixture_v0012 "../packages/fixture_history/v0012"
import hs "zelda_engine:hs"
import "base:runtime"
import "core:testing"

when ODIN_TEST {
    @(test)
    fixture_migration_v0012_to_v0013_preserves_append_only_building_identities :: proc(t: ^testing.T) {
        historical := new(fixture_v0012.Fixture)
        testing.expect(t, historical != nil)
        if historical == nil do return
        defer free(historical)

        payload, portable_error, encoded := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0012.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        testing.expect(t, encoded && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        if !encoded do return
        defer delete(payload)

        registry := fixture_migration_production_registry()
        result, migration_error, migrated := fixture_migration_run_with_registry(
            payload,
            12,
            13,
            {steps = registry.steps[:12]},
            runtime.default_allocator(),
        )
        defer fixture_migration_error_dispose(&migration_error)
        defer fixture_migration_result_dispose(&result)
        testing.expect(t, migrated)
        testing.expect_value(t, migration_error.kind, Fixture_Migration_Error_Kind.None)
        testing.expect_value(t, int(buildings.Archetype.Clinic), 21)
        testing.expect_value(t, int(buildings.Landmark_Kind.Clinic), 11)
    }
}
