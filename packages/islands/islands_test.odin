package islands

import "core:math"
import "core:testing"

fingerprint :: proc(plan: ^Plan) -> u64 {
    value := u64(1469598103934665603)
    for cell in plan.cleaned {
        value = (value ~ u64(cell)) * 1099511628211
    }
    for contour in plan.contours {
        value = (value ~ u64(contour.kind)) * 1099511628211
        value = (value ~ u64(len(contour.points))) * 1099511628211
    }
    return value
}

@(test)
island_generation_is_seeded_and_deterministic :: proc(t: ^testing.T) {
    a := generate(0x49534c45)
    b := generate(0x49534c45)
    c := generate(0x49534c46)
    defer destroy(&a)
    defer destroy(&b)
    defer destroy(&c)
    testing.expect_value(t, a.selected_seed, b.selected_seed)
    testing.expect_value(t, a.attempts, b.attempts)
    testing.expect_value(t, a.score, b.score)
    testing.expect_value(t, fingerprint(&a), fingerprint(&b))
    testing.expect(t, fingerprint(&a) != fingerprint(&c))
    testing.expect_value(t, len(a.foliage), len(b.foliage))
    for patch, index in a.foliage do testing.expect_value(t, patch, b.foliage[index])
}

@(test)
island_foliage_is_inland_and_avoids_bluffs :: proc(t: ^testing.T) {
    plan := generate(0x49534c45)
    defer destroy(&plan)
    testing.expect(t, len(plan.foliage) >= 8)
    for patch in plan.foliage {
        testing.expect(t, sample_signed_distance(&plan, patch.x, patch.z) < -3)
        testing.expect(t, sample_bluff(&plan, patch.x, patch.z) < .5)
        testing.expect(t, sample_elevation(&plan, patch.x, patch.z) > 2)
        testing.expect(t, patch.width > 0 && patch.depth > 0 && patch.height > 0)
    }
}

@(test)
island_contours_are_closed_classified_and_consistently_wound :: proc(t: ^testing.T) {
    plan := generate(0x49534c45)
    defer destroy(&plan)
    testing.expect(t, len(plan.contours) > 0)
    main_coasts, lakes, skerries := 0, 0, 0
    for contour in plan.contours {
        testing.expect(t, len(contour.points) >= 4)
        switch contour.kind {
        case .Main_Coast:
            main_coasts += 1
            testing.expect(t, contour.area > 0)
        case .Lake:
            lakes += 1
            testing.expect(t, contour.area < 0)
        case .Skerry:
            skerries += 1
            testing.expect(t, contour.area > 0)
        }
        for point in contour.points {
            testing.expect(t, point.x >= 0 && point.x <= GRID_WIDTH)
            testing.expect(t, point.z >= 0 && point.z <= GRID_HEIGHT)
        }
    }
    testing.expect_value(t, main_coasts, 1)
    testing.expect_value(t, lakes, plan.diagnostics.lake_count)
    testing.expect_value(t, skerries, plan.diagnostics.skerry_count)
}

@(test)
island_signed_distance_agrees_with_cleaned_mask :: proc(t: ^testing.T) {
    plan := generate(8128)
    defer destroy(&plan)
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            index := index_of(x, z)
            if plan.cleaned[index] == .Land {
                testing.expect(t, plan.signed_distance[index] < 0)
            } else {
                testing.expect(t, plan.signed_distance[index] > 0)
            }
            testing.expect(t, !math.is_nan(plan.signed_distance[index]))
            if x + 1 < GRID_WIDTH {
                difference := math.abs(plan.signed_distance[index] - plan.signed_distance[index + 1])
                testing.expect(t, difference <= 2)
            }
        }
    }
    land_index := -1
    for cell, index in plan.cleaned {
        if cell == .Land {
            land_index = index
            break
        }
    }
    testing.expect(t, land_index >= 0)
    land_x, land_z := land_index % GRID_WIDTH, land_index / GRID_WIDTH
    normalized_x := f32(land_x) / f32(GRID_WIDTH - 1) * 2 - 1
    normalized_z := f32(land_z) / f32(GRID_HEIGHT - 1) * 2 - 1
    testing.expect(t, sample_signed_distance(&plan, normalized_x, normalized_z) < 0)
    testing.expect(t, sample_signed_distance(&plan, -.99, -.99) > 0)
    testing.expect(t, sample_signed_distance(&plan, -1.4, -1.4) > sample_signed_distance(&plan, -.99, -.99))
}

@(test)
island_candidate_search_is_bounded_and_reports_topology :: proc(t: ^testing.T) {
    plan := generate(73)
    defer destroy(&plan)
    testing.expect(t, plan.attempts >= 1 && plan.attempts <= MAX_CANDIDATE_ATTEMPTS)
    testing.expect(t, plan.diagnostics.main_land_cells > 0)
    testing.expect(t, plan.diagnostics.land_cells >= plan.diagnostics.main_land_cells)
    testing.expect(t, plan.bounds.min_x > 0 && plan.bounds.max_x < GRID_WIDTH - 1)
    testing.expect(t, plan.bounds.min_z > 0 && plan.bounds.max_z < GRID_HEIGHT - 1)
}

@(test)
island_secondary_topology_varies_naturally_across_seeds :: proc(t: ^testing.T) {
    first_lakes, first_skerries := -1, -1
    distinct_topologies := 0
    has_no_lake, has_no_skerry := false, false
    for seed in u32(0) ..< 16 {
        plan := generate(seed)
        lakes, skerries := plan.diagnostics.lake_count, plan.diagnostics.skerry_count
        if seed == 0 {
            first_lakes, first_skerries = lakes, skerries
            distinct_topologies = 1
        } else if lakes != first_lakes || skerries != first_skerries {
            distinct_topologies = 2
        }
        has_no_lake = has_no_lake || lakes == 0
        has_no_skerry = has_no_skerry || skerries == 0
        destroy(&plan)
    }
    testing.expect(t, distinct_topologies >= 2)
    testing.expect(t, has_no_lake)
    testing.expect(t, has_no_skerry)
}

@(test)
island_vertical_form_has_seeded_relief_and_coastal_bluffs :: proc(t: ^testing.T) {
    a := generate(0x424c5546)
    b := generate(0x424c5547)
    defer destroy(&a)
    defer destroy(&b)
    testing.expect(t, a.diagnostics.maximum_elevation > 12)
    testing.expect(t, a.diagnostics.bluff_cells > 0)
    testing.expect(t, b.diagnostics.maximum_elevation > 12)
    different := false
    for index in 0 ..< CELL_COUNT {
        if a.cleaned[index] == .Water {
            testing.expect_value(t, a.elevation[index], f32(0))
            testing.expect_value(t, a.bluff[index], f32(0))
        } else {
            testing.expect(t, a.elevation[index] > 0)
        }
        if math.abs(a.elevation[index] - b.elevation[index]) > .01 do different = true
    }
    testing.expect(t, different)
    testing.expect(t, sample_elevation(&a, -.99, -.99) == 0)
}

@(test)
island_vertical_form_separates_lowland_and_mountain_halves :: proc(t: ^testing.T) {
    seed := u32(0x4b7d19e3)
    plan := generate(seed)
    defer destroy(&plan)
    lowland_sum, highland_sum := f32(0), f32(0)
    lowland_count, highland_count := 0, 0
    for z in 0 ..< GRID_HEIGHT {
        for x in 0 ..< GRID_WIDTH {
            index := index_of(x, z)
            if plan.cleaned[index] == .Water || plan.signed_distance[index] > -5 do continue
            nx := f32(x) / f32(GRID_WIDTH - 1) * 2 - 1
            nz := f32(z) / f32(GRID_HEIGHT - 1) * 2 - 1
            highland := macro_highland_weight(seed, nx, nz)
            if highland < .2 {
                lowland_sum += plan.elevation[index]
                lowland_count += 1
            } else if highland > .8 {
                highland_sum += plan.elevation[index]
                highland_count += 1
            }
        }
    }
    testing.expect(t, lowland_count > 0 && highland_count > 0)
    testing.expect(t, highland_sum / f32(highland_count) > lowland_sum / f32(lowland_count) + 3)
}

@(test)
island_macro_archetypes_are_all_reachable_and_geometrically_distinct :: proc(t: ^testing.T) {
    found: [5]bool
    for seed in u32(0) ..< 256 {
        found[int(shape_archetype(seed))] = true
    }
    for present in found do testing.expect(t, present)

    fingerprints: [5]u64
    for shape_index in 0 ..< len(fingerprints) {
        shape := Shape_Archetype(shape_index)
        value := u64(1469598103934665603)
        land := 0
        for z in 0 ..< GRID_HEIGHT {
            for x in 0 ..< GRID_WIDTH {
                nx := (f32(x) - f32(GRID_WIDTH - 1) * .5) / 43
                nz := (f32(z) - f32(GRID_HEIGHT - 1) * .5) / 27
                occupied := shape_macro_contains(shape, nx, nz, .73)
                value = (value ~ u64(occupied)) * 1099511628211
                if occupied do land += 1
            }
        }
        testing.expect(t, land > 400)
        fingerprints[shape_index] = value
    }
    for first in 0 ..< len(fingerprints) {
        for second in first + 1 ..< len(fingerprints) {
            testing.expect(t, fingerprints[first] != fingerprints[second])
        }
    }
}
