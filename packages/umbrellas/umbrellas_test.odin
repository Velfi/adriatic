package umbrellas

import "core:testing"

@(test)
generation_is_deterministic_and_valid :: proc(t: ^testing.T) {
    first := generate(42, defaults(.Beach))
    second := generate(42, defaults(.Beach))
    testing.expect(t, first.valid)
    testing.expect_value(t, first, second)
}

@(test)
unsafe_dimensions_and_panels_are_clamped :: proc(t: ^testing.T) {
    plan := generate(7, {kind = .Patio, radius = 99, height = -2, panel_count = 15})
    testing.expect(t, plan.valid)
    testing.expect_value(t, plan.radius, f32(4))
    testing.expect_value(t, plan.height, f32(1.8))
    testing.expect_value(t, plan.panel_count, 16)
}

@(test)
beach_and_patio_have_distinct_construction :: proc(t: ^testing.T) {
    beach := generate(11, defaults(.Beach))
    patio := generate(11, defaults(.Patio))
    testing.expect(t, beach.valid && patio.valid)
    testing.expect_value(t, beach.base, Base.Spike)
    testing.expect_value(t, patio.base, Base.Slab)
    testing.expect(t, beach.tilt > 0)
    testing.expect_value(t, patio.tilt, f32(0))
    testing.expect(t, beach.canopy_rise > patio.canopy_rise * .8)
}

@(test)
supported_domain_remains_valid :: proc(t: ^testing.T) {
    kinds := [2]Kind{.Beach, .Patio}
    for seed in u32(0) ..< 64 {
        for kind in kinds {
            for radius in ([3]f32{1.2, 2.5, 4}) {
                for height in ([3]f32{1.8, 3, 4.5}) {
                    for panels in ([4]int{6, 7, 12, 16}) {
                        testing.expect(
                            t,
                            generate(seed, {kind = kind, radius = radius, height = height, panel_count = panels}).valid,
                        )
                    }
                }
            }
        }
    }
}
