package main

import fixture_v0010 "../packages/fixture_history/v0010"
import hs "../packages/hs"
import "base:runtime"
import "core:testing"

when ODIN_TEST {
    @(test)
    fixture_migration_v0010_to_v0011_initializes_front_schedules :: proc(t: ^testing.T) {
        historical := new(fixture_v0010.Fixture)
        testing.expect(t, historical != nil)
        if historical == nil do return
        defer free(historical)
        historical.atmosphere.seed = 0x41544d4f
        historical.atmosphere.world_minutes = 723
        historical.atmosphere.front_seconds = 8400
        historical.atmosphere.override = .Automatic
        historical.atmosphere.weather = {.7, .4, .3, .5, {9, -2}}
        historical.tweak.atmosphere.seed = 0x54574541
        payload, portable_error, encoded := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0010.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        testing.expect(t, encoded && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        if !encoded do return
        defer delete(payload)
        production := fixture_migration_production_registry()
        v11_registry := Fixture_Migration_Registry{steps = production.steps[:10]}
        result, migration_error, migrated := fixture_migration_run_with_registry(
            payload, 10, 11, v11_registry, runtime.default_allocator(),
        )
        defer fixture_migration_error_dispose(&migration_error)
        defer fixture_migration_result_dispose(&result)
        testing.expect(t, migrated && migration_error.kind == .None)
        if !migrated do return
        testing.expect(t, result.fixture.atmosphere.world_minutes == 723)
        testing.expect(t, result.fixture.atmosphere.front_seconds == 8400)
        testing.expect(t, result.fixture.atmosphere.weather == {.7, .4, .3, .5, {9, -2}})
        testing.expect(t, result.fixture.atmosphere.schedule.initialized)
        testing.expect(t, result.fixture.atmosphere.schedule.elapsed_seconds == 0)
        testing.expect(t, result.fixture.atmosphere.schedule.next_event_seconds >= 60 * 60)
        testing.expect(t, result.fixture.atmosphere.schedule.next_event_seconds <= 120 * 60)
        testing.expect(t, result.fixture.tweak.atmosphere.schedule.initialized)
        testing.expect(t, len(production.steps) == 12)
        testing.expect(t, production.steps[9].wrapper == fixture_migration_step_v0010_to_v0011)
        testing.expect(t, production.steps[10].wrapper == fixture_migration_step_v0011_to_v0012)
        testing.expect(t, production.steps[11].wrapper == fixture_migration_step_v0012_to_v0013)
    }
}
