package estuaries

import spring_river "../spring_river"
import "core:math"
import "core:testing"

fingerprint :: proc(plan: ^Plan) -> u64 {
    result := u64(1469598103934665603)
    for value in plan.elevation do result = (result ~ u64(transmute(u32)value)) * 1099511628211
    for value in plan.channel_order do result = (result ~ u64(value)) * 1099511628211
    return result
}

@(test)
generation_is_deterministic_and_seeded :: proc(t: ^testing.T) {
    config := default_config()
    a, b := generate(config), generate(config)
    defer destroy(&a); defer destroy(&b)
    testing.expect_value(t, fingerprint(&a), fingerprint(&b))
    testing.expect_value(t, a.diagnostics, b.diagnostics)
    config.seed += 1
    c := generate(config)
    defer destroy(&c)
    testing.expect(t, fingerprint(&a) != fingerprint(&c))
}

@(test)
archetypes_have_valid_distinct_topology :: proc(t: ^testing.T) {
    config := default_config()
    estuary := generate(config)
    defer destroy(&estuary)
    config.archetype = .Distributary_Delta
    delta := generate(config)
    defer destroy(&delta)
    testing.expect(t, estuary.valid && delta.valid)
    testing.expect_value(t, estuary.diagnostics.outlet_count, 1)
    testing.expect(t, estuary.diagnostics.dominant_outlet_share > .65)
    testing.expect(t, delta.diagnostics.outlet_count >= 2)
    testing.expect(t, len(delta.graph_edges) > len(estuary.graph_edges))
    testing.expect(t, estuary.diagnostics.island_count >= 14)
    testing.expect(t, delta.diagnostics.island_count >= 14)
}

@(test)
fields_are_finite_bounded_and_connected :: proc(t: ^testing.T) {
    plan := generate(default_config())
    defer destroy(&plan)
    testing.expect(t, plan.attempts >= 1 && plan.attempts <= MAX_CANDIDATE_ATTEMPTS)
    testing.expect(t, plan.diagnostics.connected_to_sea)
    testing.expect_value(t, plan.diagnostics.unintended_outlets, 0)
    testing.expect(t, plan.diagnostics.sediment_balance_error <= .02)
    for value in plan.elevation do testing.expect(t, !math.is_nan(value) && !math.is_inf(value, 0))
    for value in plan.water_depth do testing.expect(t, value >= 0 && !math.is_nan(value))
    for value in plan.erosion_deposition do testing.expect(t, math.abs(value) <= MAX_EROSION_PER_STEP * SIMULATION_STEPS + .001)
}

@(test)
bathymetry_has_a_shallow_thalweg_and_deepening_offshore_shelf :: proc(t: ^testing.T) {
    plan := generate(default_config())
    defer destroy(&plan)
    channel_depth := sample_water_depth(&plan, 0, -.35)
    nearshore_depth := sample_water_depth(&plan, .55, -.62)
    offshore_depth := sample_water_depth(&plan, .55, -.96)
    testing.expect(t, channel_depth > .35 && channel_depth < 3.8)
    testing.expect(t, offshore_depth > nearshore_depth + 1)
    for value, index in plan.water_depth {
        expected := max(plan.config.mean_sea_level - plan.elevation[index], f32(0))
        testing.expect(t, math.abs(value - expected) < .001)
    }
}

@(test)
config_clamps_and_sampling_rotates :: proc(t: ^testing.T) {
    config := default_config()
    config.branching, config.mouth_width, config.relief = 9, 0, 100
    plan := generate(config)
    defer destroy(&plan)
    testing.expect_value(t, plan.config.branching, f32(1))
    testing.expect_value(t, plan.config.mouth_width, f32(.08))
    testing.expect_value(t, plan.config.relief, f32(30))
    north := sample_elevation(&plan, .3, .6)
    plan.config.orientation = .East
    east := sample_elevation(&plan, .6, -.3)
    testing.expect(t, math.abs(north - east) < .001)
    testing.expect(t, !math.is_nan(sample_elevation(&plan, 4, -4)))
}

@(test)
river_mouth_drives_estuary_inputs_and_opens_the_inland_channel :: proc(t: ^testing.T) {
    mouth := spring_river.Mouth {
        position      = {12, 90},
        direction     = {0, 1},
        water_level   = 3.5,
        width         = 12,
        depth         = 1.4,
        discharge     = 1.1,
        sediment_load = .78,
    }
    config := config_from_river_mouth(mouth, .Distributary_Delta, 160)
    testing.expect_value(t, config.mean_sea_level, mouth.water_level)
    testing.expect_value(t, config.sediment_load, mouth.sediment_load)
    testing.expect(t, config.branching > .7)
    plan := generate(config)
    defer destroy(&plan)
    testing.expect(t, sample_wetland(&plan, 0, .975) == .Channel)
    inlet := index_of(GRID_WIDTH / 2, GRID_HEIGHT - 1)
    testing.expect_value(t, plan.channel_order[inlet], u8(3))
    testing.expect(t, plan.elevation[inlet] < config.mean_sea_level)
}

@(test)
inland_reach_meanders_at_world_scale :: proc(t: ^testing.T) {
    plan := generate(default_config())
    defer destroy(&plan)
    centers: [3]f32
    reaches := [3]f32{.30, .58, .82}
    for source_z, reach_index in reaches {
        best_height := f32(1e9)
        for x_index in 1 ..< GRID_WIDTH - 1 {
            source_x := f32(x_index) / f32(GRID_WIDTH - 1) * 2 - 1
            height := sample_elevation_source(&plan, source_x, source_z)
            if height < best_height {
                best_height = height
                centers[reach_index] = source_x
            }
        }
    }
    span := max(max(centers[0], centers[1]), centers[2]) - min(min(centers[0], centers[1]), centers[2])
    // 0.04 of the normalized width is about 25 m in the realized lab.
    testing.expect(t, span >= .04)
}
