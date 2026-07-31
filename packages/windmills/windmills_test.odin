package windmills

import "core:testing"

@(test)
generation_is_deterministic_and_valid :: proc(t: ^testing.T) {
    first := generate(1948, defaults())
    second := generate(1948, defaults())
    testing.expect(t, first.valid)
    testing.expect_value(t, first, second)
}

@(test)
generation_clamps_unsafe_inputs :: proc(t: ^testing.T) {
    plan := generate(1, {tower_height = 99, tower_radius = -2, sail_count = 30, sail_length = 20, rpm = -3})
    testing.expect(t, plan.valid)
    testing.expect_value(t, plan.tower_height, f32(10))
    testing.expect_value(t, plan.base_radius, f32(1.6))
    testing.expect_value(t, plan.sail_count, MAX_SAILS)
    testing.expect_value(t, plan.rpm, f32(0))
}

@(test)
seeds_vary_proportions_without_changing_requested_constraints :: proc(t: ^testing.T) {
    first := generate(11, defaults())
    second := generate(12, defaults())
    testing.expect(t, first.top_radius != second.top_radius)
    testing.expect(t, first.cap_height != second.cap_height)
    testing.expect_value(t, first.tower_height, second.tower_height)
    testing.expect_value(t, first.sail_count, second.sail_count)
}
