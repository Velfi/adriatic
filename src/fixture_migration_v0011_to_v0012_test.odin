package main

import fixture_v0011 "../packages/fixture_history/v0011"
import hs "zelda_engine:hs"
import "base:runtime"
import "core:testing"

when ODIN_TEST {
    @(test)
    fixture_migration_v0011_to_v0012_initializes_climate_without_losing_front :: proc(t: ^testing.T) {
        historical := new(fixture_v0011.Fixture)
        testing.expect(t, historical != nil)
        if historical == nil do return
        defer free(historical)
        historical.atmosphere.seed = 0x434c494d
        historical.atmosphere.world_days = 140
        historical.atmosphere.world_minutes = 910
        historical.atmosphere.schedule.initialized = true
        historical.atmosphere.schedule.elapsed_seconds = 412
        historical.atmosphere.schedule.front.active = true
        historical.atmosphere.schedule.front.event_id = 7
        payload, portable_error, encoded := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0011.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        testing.expect(t, encoded && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        if !encoded do return
        defer delete(payload)

        result, migration_error, migrated := fixture_migration_run(
            payload,
            11,
            FIXTURE_SCHEMA_VERSION,
            runtime.default_allocator(),
        )
        defer fixture_migration_error_dispose(&migration_error)
        defer fixture_migration_result_dispose(&result)
        testing.expect(t, migrated && migration_error.kind == .None)
        if !migrated do return
        testing.expect(t, result.fixture.atmosphere.climate.initialized)
        testing.expect(t, result.fixture.atmosphere.climate.transition_start_seconds > 0)
        testing.expect(t, result.fixture.atmosphere.world_days == 140)
        testing.expect(t, result.fixture.atmosphere.world_minutes == 910)
        testing.expect(t, result.fixture.atmosphere.schedule.elapsed_seconds == 412)
        testing.expect(t, result.fixture.atmosphere.schedule.front.active)
        testing.expect(t, result.fixture.atmosphere.schedule.front.event_id == 7)
        testing.expect(t, result.fixture.tweak.atmosphere.climate.initialized)
    }
}
