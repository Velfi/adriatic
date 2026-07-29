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
