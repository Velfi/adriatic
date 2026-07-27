package tests

import marina "../packages/marina"
import "core:math"
import "core:testing"

marina_fingerprint :: proc(plan: ^marina.Plan) -> u64 {
    hash := u64(1469598103934665603)
    hash = (hash ~ u64(plan.style)) * 1099511628211
    hash = (hash ~ u64(plan.boundary_form)) * 1099511628211
    hash = (hash ~ u64(plan.shoreline_form)) * 1099511628211
    for value in plan.cells {
        hash = (hash ~ u64(value)) * 1099511628211
    }
    for slip in plan.slips[:plan.slip_count] {
        hash = (hash ~ u64(slip.class)) * 1099511628211
        hash = (hash ~ u64(slip.occupied)) * 1099511628211
        hash = (hash ~ u64(slip.kind)) * 1099511628211
    }
    for segment in plan.segments[:plan.segment_count] {
        hash = (hash ~ u64(segment.kind)) * 1099511628211
        hash = (hash ~ u64(int(segment.a.x * 10) + 10000)) * 1099511628211
        hash = (hash ~ u64(int(segment.a.z * 10) + 10000)) * 1099511628211
        hash = (hash ~ u64(int(segment.b.x * 10) + 10000)) * 1099511628211
        hash = (hash ~ u64(int(segment.b.z * 10) + 10000)) * 1099511628211
    }
    return hash
}

@(test)
markov_marina_mooring_field_reserves_swing_room :: proc(t: ^testing.T) {
    plan: marina.Plan
    for &value in plan.cells do value = .Water
    marina.add_mooring_field(&plan, nil, 6, 8)
    testing.expect(t, plan.section_form_counts[int(marina.Section_Form.Mooring_Field)] == 1)
    testing.expect(t, plan.slip_count == 4)
    for berth in plan.slips[:plan.slip_count] {
        testing.expect(t, berth.kind == .Swing_Mooring)
        testing.expect(
            t,
            marina.cell(
                &plan,
                int(berth.position.x / marina.CELL_METERS + f32(marina.GRID_WIDTH - 1) * .5),
                int(berth.position.z / marina.CELL_METERS + f32(marina.GRID_HEIGHT - 1) * .5),
            ) ==
            .Mooring,
        )
    }
    testing.expect(t, marina.slips_have_clearance(&plan))
    testing.expect(t, marina.slips_clear_structures(&plan))
    dx := plan.slips[1].position.x - plan.slips[0].position.x
    dz := plan.slips[2].position.z - plan.slips[0].position.z
    testing.expect(t, math.abs(dx) == marina.MOORING_FIELD_SPACING_METERS)
    testing.expect(t, math.abs(dz) == marina.MOORING_FIELD_SPACING_METERS)
}

@(test)
markov_marina_uses_full_length_finger_piers :: proc(t: ^testing.T) {
    plan: marina.Plan
    for &value in plan.cells do value = .Water
    marina.add_pier(&plan, nil, 8, 5, 13)
    found_finger := false
    for segment in plan.segments[:plan.segment_count] {
        if segment.kind != .Finger_Pier do continue
        found_finger = true
        dx, dz := segment.b.x - segment.a.x, segment.b.z - segment.a.z
        length := f32(math.sqrt(f64(dx * dx + dz * dz)))
        testing.expect(t, math.abs(length - marina.FINGER_PIER_LENGTH_METERS) < .001)
        testing.expect(t, segment.width == marina.FINGER_PIER_WIDTH_METERS)
    }
    testing.expect(t, found_finger)
}

@(test)
markov_marina_is_deterministic_and_seeded :: proc(t: ^testing.T) {
    a := marina.generate(7123)
    b := marina.generate(7123)
    c := marina.generate(99181)
    testing.expect(t, a.valid)
    testing.expect(t, b.valid)
    testing.expect(t, c.valid)
    testing.expect(t, marina_fingerprint(&a) == marina_fingerprint(&b))
    testing.expect(t, marina_fingerprint(&a) != marina_fingerprint(&c))
}

@(test)
markov_marina_default_world_site_preserves_generation :: proc(t: ^testing.T) {
    site := marina.default_site()
    site.origin = {140, -72}
    site.yaw = math.PI * .5
    plan := marina.generate_for_site(7123, &site)
    testing.expect(t, plan.valid)
    testing.expect(t, plan.site_conformance_badness == 0)
    testing.expect(t, marina.plan_conforms_to_site(&plan, &site))
    testing.expect(t, plan.world_origin == site.origin)
    testing.expect(t, plan.world_yaw == site.yaw)
    local := marina.Vec2{4, 8}
    world := marina.plan_world_position(&plan, local)
    testing.expect(t, math.abs(world.x - 148) < .001)
    testing.expect(t, math.abs(world.z - -76) < .001)
    testing.expect(t, marina.site_suitability(&site) > .999)
}

@(test)
markov_marina_world_site_rejects_blocked_entrance :: proc(t: ^testing.T) {
    site := marina.default_site()
    marina.set_site_cell(&site, 13, 18, .Blocked)
    plan := marina.generate_for_site(41, &site)
    testing.expect(t, !plan.valid)
    testing.expect(t, plan.site_conformance_badness > 0)
    testing.expect(t, !marina.plan_conforms_to_site(&plan, &site))
}

@(test)
markov_marina_seed_matrix_preserves_navigation_and_berths :: proc(t: ^testing.T) {
    seeds := [8]u32{0, 1, 7, 41, 7123, 99181, 0x4d415249, 0xffffffff}
    for seed in seeds {
        plan := marina.generate(seed)
        testing.expect(t, marina.validate(&plan))
        testing.expect(t, plan.route.count >= 4)
        testing.expect(t, marina.route_has_clearance(&plan))
        testing.expect(t, plan.segment_count >= 5)
        testing.expect(t, plan.slip_count >= 6)
        for z in 5 ..< marina.GRID_HEIGHT {
            for x in 12 ..= 14 {
                value := marina.cell(&plan, x, z)
                testing.expect(t, value == .Channel || value == .Main_Pier)
            }
        }
    }
}

@(test)
markov_marina_styles_have_distinct_waterfronts :: proc(t: ^testing.T) {
    fingerprints: [4]u64
    for seed in 0 ..< 4 {
        plan := marina.generate(u32(seed))
        testing.expect(t, plan.valid)
        testing.expect(t, int(plan.style) == seed)
        testing.expect(t, plan.segment_count >= 5)
        testing.expect(t, plan.slip_count >= 6)
        fingerprints[seed] = marina_fingerprint(&plan)
    }
    for a in 0 ..< len(fingerprints) {
        for b in a + 1 ..< len(fingerprints) {
            testing.expect(t, fingerprints[a] != fingerprints[b])
        }
    }
}

@(test)
markov_marina_spacing_badness_is_bounded_across_seed_matrix :: proc(t: ^testing.T) {
    for seed in 0 ..< 256 {
        plan := marina.generate(u32(seed))
        density, badness := marina.measure_spacing(&plan)
        testing.expect(t, density == plan.spacing_density)
        testing.expect(t, badness == plan.spacing_badness_density)
        testing.expect(t, density > 0 && density < 1)
        testing.expect(t, badness >= 0 && badness <= 1)
        testing.expect(t, badness <= .35)
        testing.expect(t, plan.berth_spacing_badness == 0)
        testing.expect(t, plan.structure_overlap_badness == 0)
        testing.expect(t, marina.slips_have_clearance(&plan))
        testing.expect(t, marina.slips_clear_structures(&plan))
        testing.expect(t, marina.route_has_clearance(&plan))
        for z in 5 ..< marina.GRID_HEIGHT {
            for x in 0 ..< marina.GRID_WIDTH {
                value := marina.cell(&plan, x, z)
                if value != .Slip &&
                   value != .Mooring &&
                   value != .Quay &&
                   value != .Natural_Jetty &&
                   value != .Main_Pier &&
                   value != .Finger_Pier {
                    continue
                }
                for bz in 0 ..< marina.GRID_HEIGHT {
                    for bx in 0 ..< marina.GRID_WIDTH {
                        if marina.cell(&plan, bx, bz) != .Breakwater do continue
                        dx, dz := x - bx, z - bz
                        required := marina.MIN_EDGE_CLEARANCE_CELLS
                        if bz >= 17 {
                            required = marina.MIN_OUTER_CLEARANCE_CELLS
                        }
                        testing.expect(t, dx * dx + dz * dz >= required * required)
                    }
                }
            }
        }
    }
}

@(test)
markov_marina_selects_least_bad_valid_candidate :: proc(t: ^testing.T) {
    for seed in 0 ..< 64 {
        selected := marina.generate(u32(seed))
        testing.expect(t, selected.valid)
        testing.expect(t, selected.candidates_evaluated == marina.GENERATION_CANDIDATES)
        for candidate_index in 0 ..< marina.GENERATION_CANDIDATES {
            layout_seed := u32(seed) ~ (u32(candidate_index) * u32(0x9e3779b9))
            candidate := marina.generate_candidate(u32(seed), layout_seed, candidate_index)
            if candidate.valid {
                testing.expect(t, selected.generation_quality <= candidate.generation_quality)
            }
        }
    }
}

@(test)
markov_marina_rejects_overlapping_berth_rows :: proc(t: ^testing.T) {
    plan: marina.Plan
    plan.slips[0].position = marina.grid_position(8, 7)
    plan.slips[1].position = marina.grid_position(8, 7)
    plan.slips[2].position = marina.grid_position(9, 7)
    plan.slip_count = 3
    _, badness := marina.measure_spacing(&plan)
    testing.expect(t, plan.berth_spacing_badness > 0)
    testing.expect(t, badness > 0)
    testing.expect(t, !marina.slips_have_clearance(&plan))
}

@(test)
markov_marina_rejects_hulls_intersecting_wide_structures :: proc(t: ^testing.T) {
    plan: marina.Plan
    marina.add_segment(&plan, .Natural_Jetty, 8, 4, 8, 12, 4.2)
    plan.slips[0] = {
        position = marina.grid_position(9, 8),
        yaw      = 0,
        class    = .Fishing,
        occupied = true,
    }
    plan.slip_count = 1
    testing.expect(t, marina.measure_structure_overlaps(&plan) > 0)
    testing.expect(t, !marina.slips_clear_structures(&plan))
}

@(test)
markov_marina_island_quay_reserves_clear_opposing_berths :: proc(t: ^testing.T) {
    plan: marina.Plan
    for &value in plan.cells do value = .Water
    marina.add_island_quay(&plan, nil, 7, 10, 9)
    testing.expect(t, plan.section_form_counts[int(marina.Section_Form.Island_Quay)] == 1)
    testing.expect(t, plan.slip_count == 4)
    testing.expect(t, marina.slips_have_clearance(&plan))
    testing.expect(t, marina.slips_clear_structures(&plan))
}

@(test)
markov_marina_forked_pier_places_clear_branch_berths :: proc(t: ^testing.T) {
    plan: marina.Plan
    for &value in plan.cells do value = .Water
    marina.add_forked_pier(&plan, nil, 8)
    testing.expect(t, plan.section_form_counts[int(marina.Section_Form.Forked_Pier)] == 1)
    testing.expect(t, plan.slip_count == 4)
    testing.expect(t, marina.slips_have_clearance(&plan))
    testing.expect(t, marina.slips_clear_structures(&plan))
}

@(test)
markov_marina_archetypes_use_distinct_section_forms :: proc(t: ^testing.T) {
    observed: [marina.SECTION_FORM_COUNT]bool
    styles: [8]bool
    for seed in 0 ..< 128 {
        plan := marina.generate(u32(seed))
        testing.expect(t, plan.valid)
        testing.expect(t, plan.fill_density >= plan.target_fill_density * .75)
        styles[int(plan.style)] = true
        for form in 0 ..< len(observed) {
            if plan.section_form_counts[form] > 0 do observed[form] = true
        }
    }
    testing.expect_value(
        t,
        observed,
        [marina.SECTION_FORM_COUNT]bool{true, true, true, true, true, true, true, true, true},
    )
    for found in styles do testing.expect(t, found)
}

@(test)
markov_marina_uses_varied_basin_boundaries :: proc(t: ^testing.T) {
    observed: [marina.BOUNDARY_FORM_COUNT]bool
    for seed in 0 ..< 256 {
        plan := marina.generate(u32(seed))
        testing.expect(t, plan.valid)
        observed[int(plan.boundary_form)] = true
        for prop in plan.props[:plan.prop_count] {
            if prop.kind != .Beacon do continue
            supported := false
            for segment in plan.segments[:plan.segment_count] {
                if segment.kind != .Breakwater do continue
                vx, vz := segment.b.x - segment.a.x, segment.b.z - segment.a.z
                length_squared := vx * vx + vz * vz
                if length_squared <= .001 do continue
                wx, wz := prop.position.x - segment.a.x, prop.position.z - segment.a.z
                projection := clamp((wx * vx + wz * vz) / length_squared, 0, 1)
                dx := prop.position.x - (segment.a.x + vx * projection)
                dz := prop.position.z - (segment.a.z + vz * projection)
                if f32(math.sqrt(f64(dx * dx + dz * dz))) <= segment.width * .25 {
                    supported = true
                    break
                }
            }
            testing.expect(t, supported)
        }
    }
    testing.expect_value(t, observed, [marina.BOUNDARY_FORM_COUNT]bool{true, true, true, true, true})
}

@(test)
markov_marina_uses_varied_quay_frontages :: proc(t: ^testing.T) {
    observed: [marina.SHORELINE_FORM_COUNT]bool
    for seed in 0 ..< 256 {
        plan := marina.generate(u32(seed))
        testing.expect(t, plan.valid)
        observed[int(plan.shoreline_form)] = true
    }
    testing.expect_value(t, observed, [marina.SHORELINE_FORM_COUNT]bool{true, true, true, true, true})
}
