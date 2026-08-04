package main

import "core:testing"

@(test)
plant_site_lab_runs_from_ocean_corner_to_mountain_corner :: proc(t: ^testing.T) {
    ocean := plant_site_lab_terrain_sample(nil, -110, -110)
    middle := plant_site_lab_terrain_sample(nil, 0, 0)
    mountain := plant_site_lab_terrain_sample(nil, 88, 88)
    testing.expect(t, ocean.height < 0)
    testing.expect(t, middle.height > 0)
    testing.expect(t, mountain.height > middle.height + 45)
    testing.expect(t, ocean.material < middle.material)
    testing.expect(t, mountain.material > middle.material)
}

@(test)
plant_site_lab_poisson_samples_respect_minimum_distance :: proc(t: ^testing.T) {
    previous_seed := plant_site_lab_seed
    defer plant_site_lab_seed = previous_seed
    plant_site_lab_seed = 73
    plant_site_lab_regenerate_samples()
    testing.expect(t, plant_site_lab_sample_count > 350)
    minimum_distance_squared := PLANT_SITE_LAB_MIN_DISTANCE * PLANT_SITE_LAB_MIN_DISTANCE
    for first_index in 0 ..< plant_site_lab_sample_count {
        for second_index in first_index + 1 ..< plant_site_lab_sample_count {
            first := plant_site_lab_samples[first_index]
            second := plant_site_lab_samples[second_index]
            dx, dz := first.x - second.x, first.z - second.z
            testing.expect(t, dx * dx + dz * dz >= minimum_distance_squared)
        }
    }
}
