package terrain

import islands "../islands"
import spring_river "../spring_river"
import "core:math"
import "core:testing"

@(test)
default_islands_generate_connected_seeded_rivers_without_estuaries :: proc(t: ^testing.T) {
    plans: [len(DEFAULT_ISLAND_SIGNS)]islands.Plan
    hydrology: [len(DEFAULT_ISLAND_SIGNS)]Default_Island_Hydrology
    island_signs := DEFAULT_ISLAND_SIGNS
    for seed, index in DEFAULT_ISLAND_SEEDS {
        plans[index] = islands.generate(seed)
        hydrology[index] = default_island_hydrology_generate(&plans[index], seed, index, island_signs[index])
    }
    defer for &plan in plans do islands.destroy(&plan)
    defer for &water in hydrology do default_island_hydrology_destroy(&water)

    for &water in hydrology {
        mouth := spring_river.mouth(&water.river)
        testing.expect(t, math.abs(mouth.water_level) < .01)
    }

    for &water, index in hydrology {
        sign := island_signs[index]
        center_x, center_z := default_island_center(sign)
        testing.expect_value(t, water.river.points[0].position, water.mountain_center)
        testing.expect(t, water.mountain_height >= 24)
        testing.expect(t, water.mountain_radius >= 170)
        for point_index in 0 ..< water.river.point_count {
            point := water.river.points[point_index]
            local_x := (point.position[0] - center_x) / DEFAULT_GENERATED_ISLAND_HALF_X
            if sign < 0 do local_x = -local_x
            local_z := (point.position[1] - center_z) / DEFAULT_GENERATED_ISLAND_HALF_Z
            testing.expect(t, islands.sample_signed_distance(&plans[index], local_x, local_z) < 0)
            if point_index > 0 {
                testing.expect(t, point.water_level < water.river.points[point_index - 1].water_level)
            }
        }
    }

    duplicate := default_island_hydrology_generate(&plans[0], DEFAULT_ISLAND_SEEDS[0], 0, island_signs[0])
    defer default_island_hydrology_destroy(&duplicate)
    testing.expect_value(t, duplicate.river.points, hydrology[0].river.points)

    water_spline := river_water_spline_from_plan(&hydrology[0].river)
    testing.expect_value(t, water_spline.point_count, hydrology[0].river.point_count)
    testing.expect_value(t, water_spline.points[0].position, hydrology[0].mountain_center)
    testing.expect_value(
        t,
        water_spline.points[water_spline.point_count - 1].water_level,
        hydrology[0].river.points[hydrology[0].river.point_count - 1].water_level,
    )

    half_extent := f32(WORLD_SIZE_METERS * .5)
    river_sample := hydrology[0].river.points[hydrology[0].river.point_count / 2].position
    wet_height, _, wet_material := default_generated_height(
        &plans,
        river_sample[0],
        river_sample[1],
        half_extent,
        &hydrology,
    )
    midpoint := hydrology[0].river.points[hydrology[0].river.point_count / 2]
    testing.expect(t, wet_height <= midpoint.water_level)
    testing.expect(t, wet_material < -1)

    // Check the completed height function, including the infrastructure
    // constraints that are composed after hydrology.
    for &water in hydrology {
        for point_index in 0 ..< water.river.point_count {
            point := water.river.points[point_index]
            final_height, _, _ := default_generated_height(
                &plans,
                point.position[0],
                point.position[1],
                half_extent,
                &hydrology,
            )
            testing.expect(t, final_height <= point.water_level + .35)
        }
    }

    arbitrary_plan := islands.generate(0xa73195c2)
    defer islands.destroy(&arbitrary_plan)
    arbitrary := default_island_hydrology_generate(&arbitrary_plan, 0xa73195c2, 1, 1)
    defer default_island_hydrology_destroy(&arbitrary)
    center_x, center_z := default_island_center(1)
    for point_index in 0 ..< arbitrary.river.point_count {
        point := arbitrary.river.points[point_index]
        local_x := (point.position[0] - center_x) / DEFAULT_GENERATED_ISLAND_HALF_X
        local_z := (point.position[1] - center_z) / DEFAULT_GENERATED_ISLAND_HALF_Z
        testing.expect(t, islands.sample_signed_distance(&arbitrary_plan, local_x, local_z) < 0)
    }

    project := new_project()
    defer free_project(project)
    visible_water_points := 0
    east_water := &project.river_water_splines[1]
    for water_point in east_water.points[:east_water.point_count] {
        if !level_contains(&project.levels[0], water_point.position[0], water_point.position[1]) do continue
        ground := sample_surface_height(project, 0, water_point.position[0], water_point.position[1])
        testing.expect(t, ground <= water_point.water_level + .05)
        visible_water_points += 1
    }
    testing.expect(t, visible_water_points > 32)
    east_midpoint := hydrology[1].river.points[hydrology[1].river.point_count / 2]
    minimum_lod_height, maximum_lod_height := f32(1e6), f32(-1e6)
    sampled_levels := 0
    for level in 0 ..< CLIPMAP_LEVELS {
        data := &project.levels[level]
        if !level_contains(data, east_midpoint.position[0], east_midpoint.position[1]) do continue
        height := sample_surface_height(project, level, east_midpoint.position[0], east_midpoint.position[1])
        testing.expect(t, height == height && math.abs(height) < 1e6)
        minimum_lod_height = min(minimum_lod_height, height)
        maximum_lod_height = max(maximum_lod_height, height)
        sampled_levels += 1
    }
    testing.expect(t, sampled_levels >= 2)
    testing.expect(t, maximum_lod_height - minimum_lod_height < 3.5)
    testing.expect(t, minimum_lod_height <= east_midpoint.water_level + .5)
}
