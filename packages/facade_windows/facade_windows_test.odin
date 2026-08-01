package facade_windows

import "core:testing"

@(test)
regional_defaults_are_distinct_and_valid :: proc(t: ^testing.T) {
    adriatic := generate(1948, defaults(.Adriatic))
    aegean := generate(1948, defaults(.Aegean))
    testing.expect(t, adriatic.valid && aegean.valid)
    testing.expect(t, adriatic.height / adriatic.width > aegean.height / aegean.width)
    testing.expect(t, aegean.reveal_depth > adriatic.reveal_depth)
    testing.expect_value(t, adriatic.surround, Surround.Dressed_Stone)
    testing.expect_value(t, aegean.surround, Surround.Whitewashed_Reveal)
}

@(test)
generation_is_deterministic :: proc(t: ^testing.T) {
    config := defaults(.Adriatic)
    config.shutter_style = .Persiana
    testing.expect_value(t, generate(77, config), generate(77, config))
}

@(test)
state_controls_angle_domain :: proc(t: ^testing.T) {
    config := defaults(.Adriatic)
    config.shutter_state = .Closed
    closed := generate(1, config)
    config.shutter_state = .Ajar
    config.shutter_angle = 8
    ajar := generate(1, config)
    config.shutter_state = .Open
    config.shutter_angle = 0
    open := generate(1, config)
    testing.expect_value(t, closed.shutter_angle, f32(0))
    testing.expect_value(t, ajar.shutter_angle, f32(.82))
    testing.expect_value(t, open.shutter_angle, f32(1.05))
    testing.expect(t, closed.valid && ajar.valid && open.valid)
}

@(test)
persiana_has_seeded_lower_panel :: proc(t: ^testing.T) {
    config := defaults(.Adriatic)
    config.shutter_style = .Persiana
    first := generate(10, config)
    second := generate(11, config)
    testing.expect(t, first.lower_panel_ratio >= .25 && first.lower_panel_ratio <= .33)
    testing.expect(t, first.lower_panel_ratio != second.lower_panel_ratio)
}

@(test)
hostile_configuration_is_clamped :: proc(t: ^testing.T) {
    plan := generate(
        0,
        {region = .Aegean, width = -4, height = 99, reveal_depth = 0, pane_columns = -9, pane_rows = 99},
    )
    testing.expect(t, plan.valid)
    testing.expect_value(t, plan.width, f32(.65))
    testing.expect_value(t, plan.height, f32(1.90))
    testing.expect_value(t, plan.pane_columns, 1)
    testing.expect_value(t, plan.pane_rows, 4)
}
