package cemeteries

import "core:testing"

@(test)
generation_is_deterministic_and_valid :: proc(t: ^testing.T) {
    first := generate(0xC3E7E8, defaults())
    second := generate(0xC3E7E8, defaults())
    testing.expect(t, first.valid)
    testing.expect_value(t, first, second)
}

@(test)
configuration_is_clamped_to_supported_bounds :: proc(t: ^testing.T) {
    plan := generate(1, {width = -10, depth = 100, density = 4, style = .Churchyard})
    testing.expect(t, plan.valid)
    testing.expect_value(t, plan.width, f32(12))
    testing.expect_value(t, plan.depth, f32(50))
}

@(test)
graves_keep_the_processional_path_clear :: proc(t: ^testing.T) {
    for style in Style {
        for seed in u32(0) ..< 64 {
            plan := generate(seed, {width = 30, depth = 36, density = 1, style = style})
            testing.expect(t, plan.valid)
            for grave in plan.graves[:plan.grave_count] {
                testing.expect(t, abs(grave.x) > plan.path_width * .5)
            }
        }
    }
}

@(test)
styles_select_distinct_marker_populations :: proc(t: ^testing.T) {
    adriatic := generate(14, {width = 30, depth = 36, density = 1, style = .Adriatic_Medieval})
    aegean := generate(14, {width = 30, depth = 36, density = 1, style = .Classical_Aegean})
    garden := generate(14, {width = 30, depth = 36, density = 1, style = .Memorial_Garden})
    adriatic_common, adriatic_rare, aegean_stelai, garden_slabs := 0, 0, 0, 0
    for grave in adriatic.graves[:adriatic.grave_count] {
        if grave.marker == .Slab || grave.marker == .Chest do adriatic_common += 1
        if grave.marker == .Pillar || grave.marker == .Cross do adriatic_rare += 1
    }
    for grave in aegean.graves[:aegean.grave_count] do if grave.marker == .Stele do aegean_stelai += 1
    for grave in garden.graves[:garden.grave_count] do if grave.marker == .Slab do garden_slabs += 1
    testing.expect(t, adriatic_common > adriatic_rare)
    testing.expect(t, aegean_stelai > aegean.grave_count / 2)
    testing.expect(t, garden_slabs > 0)
}

@(test)
memorial_archetypes_can_be_selected_explicitly :: proc(t: ^testing.T) {
    for kind in Memorial_Kind {
        config := defaults()
        config.memorial_kind = kind
        config.memorial_explicit = true
        plan := generate(77, config)
        testing.expect(t, plan.valid)
        testing.expect_value(t, plan.memorial.kind, kind)
        testing.expect(t, plan.memorial.height > 2)
        testing.expect(t, plan.memorial.court_radius > plan.memorial.base_width * .5)
    }
}

@(test)
memorial_court_remains_clear_across_supported_domain :: proc(t: ^testing.T) {
    for style in Style {
        for kind in Memorial_Kind {
            for seed in u32(0) ..< 32 {
                plan := generate(
                    seed,
                    {
                        width = 24,
                        depth = 30,
                        density = 1,
                        style = style,
                        memorial_kind = kind,
                        memorial_explicit = true,
                    },
                )
                testing.expect(t, plan.valid)
                for grave in plan.graves[:plan.grave_count] {
                    dx := grave.x - plan.memorial.x
                    dz := grave.z - plan.memorial.z
                    testing.expect(t, dx * dx + dz * dz >= plan.memorial.court_radius * plan.memorial.court_radius)
                }
            }
        }
    }
}

@(test)
styles_generate_multiple_memorial_archetypes :: proc(t: ^testing.T) {
    seen: [4]bool
    for style in Style {
        for seed in u32(0) ..< 64 {
            plan := generate(seed, {width = 24, depth = 30, density = .7, style = style})
            testing.expect(t, plan.valid)
            seen[plan.memorial.kind] = true
        }
    }
    for value in seen do testing.expect(t, value)
}

@(test)
grave_marker_construction_is_bounded :: proc(t: ^testing.T) {
    for style in Style {
        for seed in u32(0) ..< 64 {
            plan := generate(seed, {width = 30, depth = 36, density = 1, style = style})
            testing.expect(t, plan.valid)
            for grave in plan.graves[:plan.grave_count] {
                testing.expect(t, grave.width > 0 && grave.height > 0 && grave.depth > 0)
                testing.expect(t, grave.base_width >= grave.width)
                testing.expect(t, grave.base_height >= .08 && grave.base_height <= .16)
                testing.expect(t, grave.profile <= 3)
                testing.expect(t, grave.inscription <= 3)
                testing.expect(t, grave.relief <= .Amphora)
                testing.expect(t, grave.stone_variant <= 3)
            }
        }
    }
}

@(test)
supported_styles_exercise_every_marker_family :: proc(t: ^testing.T) {
    seen: [7]bool
    for style in Style {
        for seed in u32(0) ..< 64 {
            plan := generate(seed, {width = 30, depth = 36, density = 1, style = style})
            for grave in plan.graves[:plan.grave_count] do seen[grave.marker] = true
        }
    }
    for value in seen do testing.expect(t, value)
}

@(test)
adriatic_markers_favor_relief_over_epigraphy :: proc(t: ^testing.T) {
    relief_count, inscription_count, marker_count := 0, 0, 0
    for seed in u32(0) ..< 64 {
        plan := generate(seed, {width = 30, depth = 36, density = 1, style = .Adriatic_Medieval})
        for grave in plan.graves[:plan.grave_count] {
            marker_count += 1
            if grave.has_relief do relief_count += 1
            if grave.has_inscription do inscription_count += 1
        }
    }
    testing.expect(t, relief_count > marker_count / 2)
    testing.expect(t, inscription_count < marker_count / 4)
    testing.expect(t, relief_count > inscription_count)
}

@(test)
historical_material_treatment_is_preset_specific :: proc(t: ^testing.T) {
    adriatic_bases, adriatic_count, aegean_pigment := 0, 0, 0
    for seed in u32(0) ..< 32 {
        adriatic := generate(seed, {width = 30, depth = 36, density = 1, style = .Adriatic_Medieval})
        aegean := generate(seed, {width = 30, depth = 36, density = 1, style = .Classical_Aegean})
        for grave in adriatic.graves[:adriatic.grave_count] {
            adriatic_count += 1
            if grave.has_base do adriatic_bases += 1
            testing.expect_value(t, grave.stone_variant, u8(2))
            testing.expect_value(t, grave.pigment_strength, f32(0))
        }
        for grave in aegean.graves[:aegean.grave_count] {
            if grave.pigment_strength > 0 do aegean_pigment += 1
            testing.expect(t, grave.has_base)
        }
    }
    testing.expect(t, adriatic_bases < adriatic_count / 2)
    testing.expect(t, aegean_pigment > 0)
}

@(test)
traditions_do_not_mix_unsupported_marker_forms :: proc(t: ^testing.T) {
    for style in Style {
        for seed in u32(0) ..< 64 {
            plan := generate(seed, {width = 30, depth = 36, density = 1, style = style})
            testing.expect(t, plan.valid)
            for grave in plan.graves[:plan.grave_count] {
                testing.expect(t, style_supports_marker(style, grave.marker))
            }
        }
    }
}
