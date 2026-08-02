package bridges

import "core:testing"

@(test)
all_regional_archetypes_are_deterministic_and_valid :: proc(t: ^testing.T) {
    for archetype in Archetype {
        first := generate(0xB12D6E, defaults(archetype))
        second := generate(0xB12D6E, defaults(archetype))
        testing.expect(t, first.valid)
        testing.expect_value(t, first, second)
    }
}

@(test)
dalmatian_crossing_uses_many_dry_stone_spans :: proc(t: ^testing.T) {
    plan := generate(7, defaults(.Dalmatian_Multi_Arch))
    testing.expect_value(t, plan.region, Region.Adriatic)
    testing.expect_value(t, plan.construction, Construction.Dry_Stone)
    testing.expect(t, plan.pier_count >= 5)
    testing.expect(t, plan.pier_cutwaters)
}

@(test)
monumental_and_island_profiles_remain_distinct :: proc(t: ^testing.T) {
    mostar := generate(3, defaults(.Herzegovinian_High_Arch))
    cycladic := generate(3, defaults(.Cycladic_Rural))
    venetian := generate(3, defaults(.Venetian_Canal))
    testing.expect_value(t, mostar.arch_shape, Arch_Shape.Slightly_Pointed)
    testing.expect_value(t, mostar.deck_profile, Deck_Profile.Humpback)
    testing.expect(t, mostar.clearance > cycladic.clearance)
    testing.expect_value(t, cycladic.parapet, Parapet.Low_Irregular)
    testing.expect_value(t, venetian.material, Material.Istrian_Stone)
    testing.expect(t, venetian.approach_steps)
}

@(test)
archetype_rules_override_impossible_span_counts :: proc(t: ^testing.T) {
    config := defaults(.Aegean_Fortress)
    config.span_count = 12
    plan := generate(9, config)
    testing.expect(t, plan.valid)
    testing.expect_value(t, plan.pier_count, 0)
    testing.expect(t, plan.fortified_end)
}

@(test)
unsupported_cross_region_combinations_are_rejected :: proc(t: ^testing.T) {
    config := defaults(.Cycladic_Rural)
    config.width = 8
    testing.expect(t, !generate(5, config).valid)
    config = defaults(.Dalmatian_Multi_Arch)
    config.urban_shops = true
    testing.expect(t, !generate(5, config).valid)
}
