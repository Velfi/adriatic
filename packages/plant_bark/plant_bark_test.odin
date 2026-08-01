package plant_bark

import plants "../plants"
import "core:testing"

@(test)
species_profiles_are_valid_and_deterministic :: proc(t: ^testing.T) {
    for species_index in 0 ..< plants.SPECIES_COUNT {
        bark := profile(plants.Species(species_index))
        testing.expect(t, bark.scale > 0)
        testing.expect(t, bark.roughness >= .55 && bark.roughness <= 1)
        a := sample(bark, {.2, 1.7, -.4}, {.45, .1, .89}, 73)
        b := sample(bark, {.2, 1.7, -.4}, {.45, .1, .89}, 73)
        testing.expect_value(t, a, b)
        testing.expect(t, a.roughness >= .55 && a.roughness <= 1)
    }
}

@(test)
signature_species_keep_distinct_bark_identities :: proc(t: ^testing.T) {
    olive := profile(.Olive)
    plane := profile(.Oriental_Plane)
    poplar := profile(.White_Poplar)
    pine := profile(.Stone_Pine)
    testing.expect_value(t, olive.pattern, Pattern.Furrowed)
    testing.expect_value(t, plane.pattern, Pattern.Mottled)
    testing.expect_value(t, poplar.pattern, Pattern.Lenticelled)
    testing.expect_value(t, pine.pattern, Pattern.Plated)
    testing.expect(t, poplar.base_color[0] > olive.base_color[0])
}

@(test)
sampling_changes_over_the_bark_surface :: proc(t: ^testing.T) {
    bark := profile(.Grapevine)
    a := sample(bark, {0, .2, 0}, {1, 0, 0}, 41)
    b := sample(bark, {0, 1.8, 0}, {0, 0, 1}, 41)
    testing.expect(t, a.color != b.color || a.relief != b.relief)
}
