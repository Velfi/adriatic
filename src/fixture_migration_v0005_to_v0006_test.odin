package main

import fixture_v0005 "../packages/fixture_history/v0005"
import hs "../packages/hs"
import terrain "../packages/terrain"
import "base:runtime"
import "core:testing"

when ODIN_TEST {
    fixture_migration_v0005_payload :: proc(t: ^testing.T) -> ([]byte, bool) {
        historical := new(fixture_v0005.Fixture)
        testing.expect(t, historical != nil)
        if historical == nil do return nil, false
        defer free(historical)

        for &level, level_index in historical.project.levels {
            level.cell_size = f32(u32(1) << u32(level_index))
            extent := f32(terrain.LEGACY_TERRAIN_RESOLUTION - 1) * level.cell_size
            level.origin_x = -extent * .5
            level.origin_z = -extent * .5
            level.heights[0] = f32(level_index + 1)
            level.heights[len(level.heights) - 1] = f32(level_index + 11)
            level.material[0] = f32(.1)
            level.material[len(level.material) - 1] = f32(.9)
        }
        historical.project.city_density[17] = 201
        historical.project.climbing_leaf_density[29] = 177
        historical.project.road_graph.edge_count = 1
        historical.project.road_graph.edges[0].from = 0
        historical.project.road_graph.edges[0].to = 1
        historical.project.road_graph.edges[0].pavement = .Cobblestone

        historical.farm_count = 1
        historical.farms[0].plan.seed = 0x4641524d
        historical.farms[0].plan.width = 25
        historical.farms[0].plan.height = 19
        historical.farms[0].plan.valid = true

        historical.settlement_plan.site_count = 1
        historical.settlement_plan.sites[0].kind = .Rejected
        historical.settlement_plan.rejected_site_count = 1
        historical.settlement_plan.rejected_sites[0].kind = .Rejected
        historical.settlement_plan.acceptance_failure = .Building_Access

        payload, portable_error, ok := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0005.Fixture)},
            fixture_codec_portable_config(),
            context.allocator,
        )
        testing.expect(t, ok && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        return payload, ok
    }

    @(test)
    fixture_migration_v0005_to_v0006_direct_defaults_and_registry :: proc(t: ^testing.T) {
        payload, payload_ok := fixture_migration_v0005_payload(t)
        if !payload_ok do return
        defer delete(payload)

        result, migration_error, migrated := fixture_migration_run_with_registry(
            payload,
            5,
            FIXTURE_SCHEMA_VERSION,
            fixture_migration_production_registry(),
            runtime.default_allocator(),
        )
        defer fixture_migration_error_dispose(&migration_error)
        defer fixture_migration_result_dispose(&result)
        testing.expect(t, migrated && migration_error.kind == .None)
        if !migrated do return

        fixture := result.fixture
        testing.expect(t, fixture.project.road_graph.edges[0].use_intensity == 1)
        testing.expect(t, fixture.project.city_density[17] == 201)
        testing.expect(t, fixture.project.climbing_leaf_density[29] == 177)
        testing.expect(t, fixture.project.city_density[terrain.LEGACY_TERRAIN_SAMPLES] == 0)
        testing.expect(t, fixture.farms[0].plan.garden_span == 3)
        testing.expect(t, fixture.farms[0].plan.garden_x >= 1)
        testing.expect(t, fixture.farms[0].plan.garden_z >= 1)
        testing.expect(t, fixture.settlement_plan.sites[0].kind == .Rejected)
        testing.expect(t, fixture.settlement_plan.rejected_sites[0].kind == .Rejected)
        testing.expect(t, fixture.settlement_plan.acceptance_failure == .Building_Access)
        testing.expect(t, fixture.settlement_plan.growth_event_count == 0)
        testing.expect(t, fixture.settlement_plan.garden_count == 0)
        testing.expect(t, fixture.settlement_plan.patio_count == 0)
        testing.expect(t, fixture.story_state.delivery.care == .Unchosen)
        defaults := tweak_default_state().player_animation
        testing.expect(
            t,
            fixture.tweak.player_animation.body_softness_strength == defaults.body_softness_strength &&
            fixture.tweak.player_animation.body_softness_stiffness == defaults.body_softness_stiffness &&
            fixture.tweak.player_animation.body_softness_max_displacement == defaults.body_softness_max_displacement,
        )

        registry := fixture_migration_production_registry()
        testing.expect(t, len(registry.steps) == FIXTURE_SCHEMA_VERSION - 1)
        testing.expect(t, registry.steps[4].from_version == 5)
        testing.expect(t, registry.steps[4].to_version == 6)
        testing.expect(t, registry.steps[4].wrapper == fixture_migration_step_v0005_to_v0006)
    }
}
