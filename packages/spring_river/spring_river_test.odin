package spring_river

import "core:math"
import "core:testing"

test_config :: proc(seed: u32 = 42) -> Config {
    return {
        seed = seed,
        source = {-12, -80},
        direction = {.1, 1},
        source_height = 18,
        length = 180,
        segment_length = 6,
        gradient = .055,
        discharge = .7,
        meander = .65,
        spring_radius = 4,
    }
}

@(test)
generation_is_deterministic_seeded_and_downhill :: proc(t: ^testing.T) {
    a, b := generate(test_config()), generate(test_config())
    testing.expect_value(t, a, b)
    changed := generate(test_config(43))
    testing.expect(t, changed.points[8].position != a.points[8].position)
    for index in 1 ..< a.point_count {
        testing.expect(t, a.points[index].water_level < a.points[index - 1].water_level)
        testing.expect(t, a.points[index].flow >= a.points[index - 1].flow)
    }
    testing.expect(t, math.abs(a.total_drop - a.config.length * a.config.gradient) < .0001)
}

@(test)
sampling_finds_water_bed_banks_and_flow :: proc(t: ^testing.T) {
    plan := generate(test_config())
    for index in 0 ..< plan.point_count - 1 {
        point := plan.points[index]
        value := sample(&plan, point.position)
        testing.expect(t, value.inside_water)
        testing.expect(t, value.bed_height < value.water_level)
        testing.expect(t, value.bank_influence > .99)
        length := f32(
            math.sqrt(
                f64(
                    value.flow_direction[0] * value.flow_direction[0] +
                    value.flow_direction[1] * value.flow_direction[1],
                ),
            ),
        )
        testing.expect(t, math.abs(length - 1) < .001)
    }
    far := sample(&plan, {500, 500})
    testing.expect(t, !far.inside_water)
    testing.expect_value(t, far.bank_influence, f32(0))
    testing.expect_value(t, far.wetness, f32(0))
}

@(test)
configuration_is_clamped_and_capacity_bounded :: proc(t: ^testing.T) {
    config := test_config()
    config.length = 10000
    config.segment_length = 0
    config.gradient = -1
    config.discharge = 8
    config.meander = 7
    config.spring_radius = 0
    plan := generate(config)
    testing.expect_value(t, plan.point_count, MAX_POINTS)
    testing.expect_value(t, plan.config.length, f32(900))
    testing.expect_value(t, plan.config.segment_length, f32(2))
    testing.expect_value(t, plan.config.gradient, f32(.002))
    testing.expect_value(t, plan.config.discharge, f32(2))
    testing.expect_value(t, plan.config.meander, f32(1))
    testing.expect_value(t, plan.config.spring_radius, f32(1))
}

@(test)
mouth_exports_the_downstream_estuary_contract :: proc(t: ^testing.T) {
    plan := generate(test_config())
    handoff := mouth(&plan)
    last := plan.points[plan.point_count - 1]
    testing.expect_value(t, handoff.position, last.position)
    testing.expect_value(t, handoff.water_level, last.water_level)
    testing.expect_value(t, handoff.width, last.width)
    testing.expect_value(t, handoff.discharge, last.flow)
    testing.expect(t, handoff.sediment_load > 0 && handoff.sediment_load <= 1)
}
