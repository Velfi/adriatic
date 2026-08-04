package main

import fixture_v0022 "../packages/fixture_history/v0022"
import "core:testing"

when ODIN_TEST {
    @(test)
    fixture_migration_v0022_defaults_mouse_placement_state :: proc(t: ^testing.T) {
        target := new(Fixture, context.temp_allocator)
        target.mouse_placement_count = 4
        target.mouse_placement_rotation = 1
        error := fixture_migrate_v0022_to_v0023(fixture_v0022.Fixture{}, target, context.allocator)
        testing.expect(t, error.kind == .None)
        testing.expect(t, target.mouse_placement_count == 0)
        testing.expect(t, target.mouse_placement_rotation == 0)
        testing.expect(t, len(fixture_migration_production_registry().steps) == FIXTURE_SCHEMA_VERSION - 1)
    }
}
