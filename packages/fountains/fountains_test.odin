package fountains

import "core:testing"

@(test)
generation_is_deterministic_and_valid :: proc(t: ^testing.T) {
    config := defaults()
    first := generate(0xF017A17, config)
    second := generate(0xF017A17, config)
    testing.expect(t, first.valid)
    testing.expect_value(t, first, second)
}

@(test)
generation_clamps_unsafe_inputs :: proc(t: ^testing.T) {
    plan := generate(7, {radius = -4, style = .Courtyard, jet_count = 99, jet_height = 40})
    testing.expect(t, plan.valid)
    testing.expect_value(t, plan.radius, f32(2.2))
    testing.expect_value(t, plan.jet_count, MAX_JETS)
}

@(test)
seeds_create_bounded_architectural_variation :: proc(t: ^testing.T) {
    first := generate(1, defaults())
    second := generate(2, defaults())
    testing.expect(t, first.valid && second.valid)
    testing.expect(t, first.wall_height != second.wall_height)
    testing.expect(t, first.pedestal_height != second.pedestal_height)
    testing.expect(t, first.rim_width != second.rim_width)
}

@(test)
styles_have_distinct_basin_silhouettes :: proc(t: ^testing.T) {
    bowl := generate(9, {radius = 3.8, style = .Bowl, jet_count = 8, jet_height = 2})
    tiered := generate(9, defaults())
    courtyard := generate(9, {radius = 3.8, style = .Courtyard, jet_count = 8, jet_height = 2})
    testing.expect(t, bowl.valid && tiered.valid && courtyard.valid)
    testing.expect(t, bowl.basin_segments > tiered.basin_segments)
    testing.expect(t, tiered.basin_segments > courtyard.basin_segments)
}

@(test)
jet_choreography_preserves_opposing_symmetry :: proc(t: ^testing.T) {
    for seed in u32(0) ..< 32 {
        for jet_count in 2 ..= MAX_JETS {
            if jet_count & 1 != 0 do continue
            plan := generate(seed, {radius = 3.8, style = .Tiered, jet_count = jet_count, jet_height = 2.8})
            testing.expect(t, plan.valid)
            for index in 0 ..< plan.jet_count / 2 {
                opposite := index + plan.jet_count / 2
                testing.expect_value(t, plan.jets[index].height, plan.jets[opposite].height)
                testing.expect_value(t, plan.jets[index].radius, plan.jets[opposite].radius)
            }
        }
    }
}

@(test)
odd_alternating_rings_use_a_seamless_circular_motif :: proc(t: ^testing.T) {
    for seed in u32(0) ..< 128 {
        plan := generate(seed, {radius = 3.8, style = .Tiered, jet_count = 9, jet_height = 2.8})
        if plan.jet_pattern != 1 do continue
        unique_heights := 1
        for index in 1 ..< plan.jet_count {
            seen := false
            for earlier in 0 ..< index {
                if plan.jets[index].height == plan.jets[earlier].height {
                    seen = true
                    break
                }
            }
            if !seen do unique_heights += 1
        }
        testing.expect(t, unique_heights >= 3)
        return
    }
    testing.expect(t, false)
}

@(test)
seeds_select_multiple_jet_patterns :: proc(t: ^testing.T) {
    seen: [3]bool
    for seed in u32(0) ..< 64 {
        plan := generate(seed, defaults())
        seen[plan.jet_pattern] = true
    }
    testing.expect(t, seen[0] && seen[1] && seen[2])
}

@(test)
supported_domain_stays_valid_and_lands_in_water :: proc(t: ^testing.T) {
    styles := [3]Style{.Bowl, .Tiered, .Courtyard}
    radii := [3]f32{2.2, 3.8, 7.0}
    jet_counts := [4]int{0, 1, 10, MAX_JETS}
    jet_heights := [3]f32{.4, 2.8, 6.0}
    for seed in u32(0) ..< 64 {
        for style in styles {
            for radius in radii {
                for jet_count in jet_counts {
                    for jet_height in jet_heights {
                        plan := generate(
                            seed,
                            {radius = radius, style = style, jet_count = jet_count, jet_height = jet_height},
                        )
                        testing.expect(t, plan.valid)
                        usable_water_radius := plan.radius - plan.rim_width - .12
                        for jet in plan.jets[:plan.jet_count] {
                            testing.expect(t, jet.radius < usable_water_radius)
                        }
                    }
                }
            }
        }
    }
}
