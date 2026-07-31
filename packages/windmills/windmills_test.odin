package windmills

import "core:testing"

@(test)
both_regions_are_deterministic_and_valid :: proc(t: ^testing.T) {
    for region in Region {
        first := generate(1948, defaults(region))
        second := generate(1948, defaults(region))
        testing.expect(t, first.valid)
        testing.expect_value(t, first, second)
    }
}

@(test)
adriatic_plan_has_regional_silhouette_and_rig :: proc(t: ^testing.T) {
    plan := generate(7, defaults(.Adriatic))
    testing.expect(t, plan.valid)
    testing.expect_value(t, plan.sail_count, 8)
    testing.expect(t, plan.base_radius > generate(7, defaults(.Aegean)).base_radius)
    testing.expect(t, plan.wall_irregularity > .05)
    testing.expect(t, plan.site_irregularity > 0)
    testing.expect_value(t, plan.site_segments, 9)
    testing.expect(t, plan.cap_height / plan.base_radius < .52)
}

@(test)
aegean_plan_has_cycladic_cap_and_ten_or_twelve_antennae :: proc(t: ^testing.T) {
    ten := defaults(.Aegean)
    ten.sail_count = 10
    plan_ten := generate(9, ten)
    plan_twelve := generate(9, defaults(.Aegean))
    testing.expect(t, plan_ten.valid && plan_twelve.valid)
    testing.expect_value(t, plan_ten.sail_count, 10)
    testing.expect_value(t, plan_twelve.sail_count, 12)
    testing.expect(t, plan_twelve.cap_height > generate(9, defaults(.Adriatic)).cap_height)
    testing.expect(t, plan_twelve.cap_height / plan_twelve.base_radius > .89)
    testing.expect(t, plan_twelve.wall_segments >= generate(9, defaults(.Adriatic)).wall_segments)
    testing.expect_value(t, plan_twelve.site_irregularity, f32(0))
    testing.expect_value(t, plan_twelve.site_segments, 12)
}

@(test)
generation_clamps_each_regional_domain :: proc(t: ^testing.T) {
    adriatic := generate(
        1,
        {region = .Adriatic, tower_height = 99, tower_radius = -2, sail_count = 12, sail_length = 20, rpm = -3},
    )
    aegean := generate(
        1,
        {region = .Aegean, tower_height = -2, tower_radius = 9, sail_count = 4, sail_length = 1, rpm = 30},
    )
    testing.expect(t, adriatic.valid && aegean.valid)
    testing.expect_value(t, adriatic.sail_count, 8)
    testing.expect_value(t, aegean.sail_count, 10)
    testing.expect_value(t, adriatic.rpm, f32(0))
    testing.expect_value(t, aegean.rpm, f32(12))
}

@(test)
seeds_vary_detail_without_changing_regional_contract :: proc(t: ^testing.T) {
    first := generate(11, defaults(.Adriatic))
    second := generate(12, defaults(.Adriatic))
    testing.expect(t, first.tower_height != second.tower_height)
    testing.expect(t, first.base_radius != second.base_radius)
    testing.expect(t, first.sail_length != second.sail_length)
    testing.expect(t, first.top_radius != second.top_radius)
    testing.expect(t, first.cap_height != second.cap_height)
    testing.expect_value(t, first.sail_count, second.sail_count)
    testing.expect_value(t, first.region, second.region)
}

@(test)
regional_large_form_contract_holds_across_seeds :: proc(t: ^testing.T) {
    for seed in u32(0) ..< 256 {
        adriatic := generate(seed, defaults(.Adriatic))
        aegean := generate(seed, defaults(.Aegean))
        adriatic_slenderness := adriatic.tower_height / (adriatic.base_radius * 2)
        aegean_slenderness := aegean.tower_height / (aegean.base_radius * 2)
        testing.expect(t, adriatic.valid && aegean.valid)
        testing.expect(t, adriatic_slenderness < 1.35)
        testing.expect(t, aegean_slenderness > 1.45)
        testing.expect(t, aegean_slenderness - adriatic_slenderness > .12)
        testing.expect(t, adriatic.sail_length > adriatic.base_radius * 1.4)
        testing.expect(t, aegean.sail_length > aegean.base_radius * 1.85)
        testing.expect(t, adriatic.hub_height - adriatic.sail_length > .35)
        testing.expect(t, aegean.hub_height - aegean.sail_length > 1.1)
        testing.expect(t, aegean.cap_height / aegean.base_radius - adriatic.cap_height / adriatic.base_radius > .38)
        testing.expect(t, adriatic.site_radius > adriatic.base_radius * 2)
        testing.expect(t, aegean.site_radius > aegean.base_radius * 2)
    }
}

@(test)
heading_is_preserved_and_bounded :: proc(t: ^testing.T) {
    oriented := defaults(.Adriatic)
    oriented.heading = .72
    plan := generate(31, oriented)
    testing.expect_value(t, plan.heading, f32(.72))
    testing.expect(t, plan.valid)

    oriented.heading = 20
    plan = generate(31, oriented)
    testing.expect_value(t, plan.heading, f32(3.141592654))
    testing.expect(t, plan.valid)
}
