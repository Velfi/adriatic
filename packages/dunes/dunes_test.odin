package dunes

import "core:math"
import "core:testing"

test_config :: proc(seed: u32 = 42, vegetation: f32 = .8) -> Config {
    return {
        seed = seed,
        anchor = {10, -4},
        tangent = {1, 0},
        inland = {0, 1},
        length = 240,
        width = 120,
        wind_direction = {.2, 1},
        wind_strength = .7,
        dune_height = 7,
        dune_spacing = 31,
        vegetation_strength = vegetation,
    }
}

@(test)
same_seed_is_deterministic_and_sampling_is_order_independent :: proc(t: ^testing.T) {
    a := generate(test_config())
    b := generate(test_config())
    points := [?]Vec2{{0, 18}, {60, 49}, {-72, 83}, {15, 111}}
    for index in 0 ..< len(points) {
        forward := sample(&a, points[index])
        reverse := sample(&a, points[len(points) - 1 - index])
        again := sample(&b, points[index])
        testing.expect_value(t, forward, again)
        testing.expect_value(t, reverse, sample(&b, points[len(points) - 1 - index]))
    }
}

@(test)
different_seeds_change_the_field :: proc(t: ^testing.T) {
    a := generate(test_config(42))
    b := generate(test_config(43))
    changed := false
    for z := f32(12); z < 110; z += 7 {
        if abs(sample(&a, {24, z}).height_delta - sample(&b, {24, z}).height_delta) > .001 {
            changed = true
            break
        }
    }
    testing.expect(t, changed)
}

@(test)
samples_fade_at_bounds_and_remain_finite_and_bounded :: proc(t: ^testing.T) {
    plan := generate(test_config())
    outside := [?]Vec2{{10, -5}, {10, 117}, {-111, 40}, {131, 40}}
    for point in outside do testing.expect_value(t, sample(&plan, point), Sample{})
    for z := f32(0); z <= plan.config.width; z += 2 {
        for x := f32(-120); x <= 120; x += 8 {
            value := sample(&plan, {x + 10, z - 4})
            testing.expect(t, !math.is_nan(value.height_delta) && !math.is_inf(value.height_delta))
            testing.expect(t, value.height_delta >= 0 && value.height_delta <= plan.maximum_height + .001)
            testing.expect(t, value.coverage >= 0 && value.coverage <= 1)
            testing.expect(t, value.grass_suitability >= 0 && value.grass_suitability <= 1)
        }
    }
    testing.expect(t, sample(&plan, {10, -3.9}).height_delta < .01)
    testing.expect(t, sample(&plan, {10, 115.9}).height_delta < .05)
}

@(test)
ecology_suppresses_shore_and_slip_faces_and_favors_stable_ground :: proc(t: ^testing.T) {
    plan := generate(test_config())
    testing.expect_value(t, sample(&plan, {10, -5}).grass_suitability, f32(0))
    best_grass, exposed_grass := f32(0), f32(1)
    found_exposed := false
    for z := f32(18); z < 105; z += .5 {
        value := sample(&plan, {10, z})
        best_grass = max(best_grass, value.grass_suitability)
        if value.exposure > .8 {
            exposed_grass = min(exposed_grass, value.grass_suitability)
            found_exposed = true
        }
    }
    testing.expect(t, best_grass > .35)
    testing.expect(t, found_exposed && exposed_grass < best_grass * .45)
}

@(test)
grass_candidates_are_deterministic_bounded_and_obey_strength :: proc(t: ^testing.T) {
    full := generate(test_config(91, 1))
    none := generate(test_config(91, 0))
    accepted := 0
    for index in 0 ..< full.candidate_count {
        a, ok_a := grass_candidate(&full, index)
        b, ok_b := grass_candidate(&full, index)
        testing.expect_value(t, ok_a, ok_b)
        testing.expect_value(t, a, b)
        _, ok_none := grass_candidate(&none, index)
        testing.expect(t, !ok_none)
        if ok_a {
            accepted += 1
            along, inland_distance := local_coordinates(&full, a.position)
            testing.expect(t, abs(along) < full.config.length * .5)
            testing.expect(t, inland_distance > 0 && inland_distance < full.config.width)
            testing.expect(t, a.density > 0 && a.density <= .78)
        }
    }
    testing.expect(t, accepted > 0 && accepted < full.candidate_count)
}

@(test)
shore_profile_builds_berm_nearshore_bar_and_shelf_descent :: proc(t: ^testing.T) {
    config := Shore_Config {
        sea_level       = 2,
        berm_height     = 1.2,
        dry_beach_width = 24,
        nearshore_width = 70,
        nearshore_depth = 3,
        shelf_width     = 140,
        shelf_depth     = 12,
        bar_strength    = .8,
    }
    toe := shore_sample(config, 0)
    berm := shore_sample(config, 30)
    swash := shore_sample(config, -2)
    trough := shore_sample(config, -17)
    bar := shore_sample(config, -41)
    shelf := shore_sample(config, -210)
    testing.expect_value(t, toe.height, config.sea_level)
    testing.expect(t, berm.height > toe.height)
    testing.expect(t, swash.height < config.sea_level && swash.depth > 0)
    testing.expect(t, trough.depth > bar.depth)
    testing.expect(t, shelf.depth > config.nearshore_depth)
    testing.expect(t, shelf.height < bar.height)
    testing.expect(t, swash.shallow_water > shelf.shallow_water)
    testing.expect(t, toe.wetness == 1)
    testing.expect(t, shore_sample(config, 12).wetness == 0)
}

@(test)
curved_coast_sampling_follows_distance_normal_wind_and_suitability :: proc(t: ^testing.T) {
    config := Curved_Coast_Config {
        seed                = 77,
        wind_direction      = {0, 1},
        wind_strength       = .7,
        dune_height         = 8,
        dune_spacing        = 31,
        dune_width          = 110,
        vegetation_strength = .8,
    }
    found := false
    for x := f32(-180); x <= 180; x += 4 {
        value := sample_curved_coast(config, {x, 40}, -40, {0, -1})
        if value.height_delta > .1 {
            found = true
            testing.expect(t, value.inside)
            testing.expect(t, value.coverage > 0 && value.coverage <= 1)
            testing.expect(t, value.grass_suitability >= 0 && value.grass_suitability <= 1)
        }
    }
    testing.expect(t, found)
    testing.expect(t, !sample_curved_coast(config, {0, 0}, 2, {0, -1}).inside)
    testing.expect(t, !sample_curved_coast(config, {0, 40}, -40, {0, 1}).inside)
    testing.expect(t, !sample_curved_coast(config, {0, 40}, -40, {0, -1}, 0).inside)
}

@(test)
curved_coast_coverage_forms_a_smooth_belt_independent_of_ridge_height :: proc(t: ^testing.T) {
    config := Curved_Coast_Config {
        seed                = 77,
        wind_direction      = {0, 1},
        wind_strength       = .7,
        dune_height         = 8,
        dune_spacing        = 31,
        dune_width          = 110,
        vegetation_strength = .8,
    }
    found_low_ridge_in_belt := false
    previous := sample_curved_coast(config, {24, 1}, -1, {0, -1})
    maximum_half_meter_step := f32(0)
    previous_fine := previous
    for inland := f32(1.5); inland < config.dune_width; inland += .5 {
        value := sample_curved_coast(config, {24, inland}, -inland, {0, -1})
        maximum_half_meter_step = max(maximum_half_meter_step, abs(value.height_delta - previous_fine.height_delta))
        previous_fine = value
    }
    for inland := f32(2); inland < config.dune_width; inland += 1 {
        value := sample_curved_coast(config, {24, inland}, -inland, {0, -1})
        testing.expect(t, abs(value.coverage - previous.coverage) < .2)
        if value.coverage > .2 && value.height_delta < .15 {
            found_low_ridge_in_belt = true
        }
        previous = value
    }
    testing.expect(t, found_low_ridge_in_belt)
    testing.expect(t, maximum_half_meter_step < 1.5)
    testing.expect(t, sample_curved_coast(config, {24, .1}, -.1, {0, -1}).coverage < .01)
    testing.expect(t, sample_curved_coast(config, {24, 109.9}, -109.9, {0, -1}).coverage < .01)
}

@(test)
curved_coast_keeps_a_readable_bounded_foredune_along_suitable_coast :: proc(t: ^testing.T) {
    config := Curved_Coast_Config {
        seed                = 77,
        wind_direction      = {0, 1},
        wind_strength       = .7,
        dune_height         = 8,
        dune_spacing        = 31,
        dune_width          = 110,
        vegetation_strength = .8,
    }
    weakest_peak := f32(1e6)
    strongest_peak := f32(0)
    for along := f32(-180); along <= 180; along += 12 {
        peak := f32(0)
        for inland := f32(4); inland < config.dune_width - 4; inland += 1 {
            value := sample_curved_coast(config, {along, inland}, -inland, {0, -1})
            peak = max(peak, value.height_delta)
        }
        weakest_peak = min(weakest_peak, peak)
        strongest_peak = max(strongest_peak, peak)
    }
    testing.expect(t, weakest_peak > config.dune_height * .08)
    testing.expect(t, strongest_peak <= config.dune_height * 1.08)
    testing.expect(t, strongest_peak > weakest_peak * 1.6)
}

@(test)
curved_coast_patchy_sites_retain_relief_without_becoming_full_belts :: proc(t: ^testing.T) {
    config := Curved_Coast_Config {
        seed                = 77,
        wind_direction      = {0, 1},
        wind_strength       = .7,
        dune_height         = 8,
        dune_spacing        = 31,
        dune_width          = 110,
        vegetation_strength = .8,
    }
    full_peak, patchy_peak := f32(0), f32(0)
    full_coverage, patchy_coverage := f32(0), f32(0)
    for inland := f32(4); inland < config.dune_width - 4; inland += 1 {
        full := sample_curved_coast(config, {24, inland}, -inland, {0, -1}, 1)
        patchy := sample_curved_coast(config, {24, inland}, -inland, {0, -1}, .25)
        full_peak = max(full_peak, full.height_delta)
        patchy_peak = max(patchy_peak, patchy.height_delta)
        full_coverage = max(full_coverage, full.coverage)
        patchy_coverage = max(patchy_coverage, patchy.coverage)
    }
    testing.expect(t, patchy_peak > full_peak * .35)
    testing.expect(t, patchy_peak < full_peak * .65)
    testing.expect(t, patchy_coverage < full_coverage * .35)
}

@(test)
curved_coast_ecology_is_patchy_without_abrupt_alongshore_steps :: proc(t: ^testing.T) {
    config := Curved_Coast_Config {
        seed                = 77,
        wind_direction      = {0, 1},
        wind_strength       = .7,
        dune_height         = 8,
        dune_spacing        = 31,
        dune_width          = 110,
        vegetation_strength = .9,
    }
    minimum, maximum := f32(1), f32(0)
    previous := sample_curved_coast(config, {-180, 54}, -54, {0, -1}).grass_suitability
    largest_step := f32(0)
    for along := f32(-179); along <= 180; along += 1 {
        current := sample_curved_coast(config, {along, 54}, -54, {0, -1}).grass_suitability
        minimum = min(minimum, current)
        maximum = max(maximum, current)
        largest_step = max(largest_step, abs(current - previous))
        previous = current
    }
    testing.expect(t, maximum - minimum > .12)
    testing.expect(t, largest_step < .12)
}

@(test)
curved_coast_blowouts_form_sparse_connected_bare_corridors :: proc(t: ^testing.T) {
    config := Curved_Coast_Config {
        seed                = 77,
        wind_direction      = {0, 1},
        wind_strength       = .85,
        dune_height         = 8,
        dune_spacing        = 31,
        dune_width          = 110,
        vegetation_strength = 1,
    }
    inland_samples := [4]f32{18, 36, 54, 72}
    best_connected_strength := f32(0)
    best_grass := f32(1)
    for start_x := f32(-360); start_x <= 360; start_x += 2 {
        path_x := start_x
        connected_strength := f32(1)
        path_grass := f32(1)
        for inland in inland_samples {
            local_best := f32(0)
            local_grass := f32(1)
            local_x := path_x
            for offset := f32(-14); offset <= 14; offset += 1 {
                candidate_x := path_x + offset
                value := sample_curved_coast(config, {candidate_x, inland}, -inland, {0, -1})
                if value.blowout > local_best {
                    local_best = value.blowout
                    local_grass = value.grass_suitability
                    local_x = candidate_x
                }
            }
            connected_strength = min(connected_strength, local_best)
            path_grass = min(path_grass, local_grass)
            path_x = local_x
        }
        if connected_strength > best_connected_strength {
            best_connected_strength = connected_strength
            best_grass = path_grass
        }
    }
    testing.expect(t, best_connected_strength > .24)
    testing.expect(t, best_grass < .28)

    blowout_samples := 0
    total_samples := 0
    for along := f32(-400); along <= 400; along += 2 {
        value := sample_curved_coast(config, {along, 42}, -42, {0, -1})
        testing.expect(t, value.blowout >= 0 && value.blowout <= 1)
        if value.blowout > .24 do blowout_samples += 1
        total_samples += 1
    }
    testing.expect(t, blowout_samples > 0)
    testing.expect(t, f32(blowout_samples) / f32(total_samples) < .32)
}
