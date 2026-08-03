package terrain

import estuaries "../estuaries"
import islands "../islands"
import spring_river "../spring_river"
import "core:math"
import "core:testing"

@(test)
default_islands_connect_seeded_rivers_to_distinct_coastal_morphologies :: proc(t: ^testing.T) {
    plans: [len(DEFAULT_ISLAND_SIGNS)]islands.Plan
    hydrology: [len(DEFAULT_ISLAND_SIGNS)]Default_Island_Hydrology
    island_signs := DEFAULT_ISLAND_SIGNS
    for seed, index in DEFAULT_ISLAND_SEEDS {
        plans[index] = islands.generate(seed)
        hydrology[index] = default_island_hydrology_generate(&plans[index], seed, index, island_signs[index])
    }
    defer for &plan in plans do islands.destroy(&plan)
    defer for &water in hydrology do default_island_hydrology_destroy(&water)

    testing.expect(t, hydrology[0].archetype == .Tidal_Estuary)
    testing.expect(t, hydrology[1].archetype == .Distributary_Delta)
    testing.expect(t, hydrology[0].estuary.valid)
    testing.expect(t, hydrology[1].estuary.valid)
    testing.expect_value(t, hydrology[0].estuary.diagnostics.outlet_count, 1)
    testing.expect(t, hydrology[0].estuary.diagnostics.dominant_outlet_share > .65)
    testing.expect(t, hydrology[1].estuary.diagnostics.outlet_count >= 2)

    for &water in hydrology {
        mouth := spring_river.mouth(&water.river)
        testing.expect(t, math.abs(mouth.position[0] - water.estuary_center[0]) < .5)
        testing.expect(t, math.abs(mouth.position[1] - (water.estuary_center[1] + water.estuary_half_extent)) < .01)
        testing.expect(t, math.abs(mouth.water_level) < .01)

        // Probe beyond the river's terminal bank kernel, inside the estuary.
        // The inlet must remain carved across the finite simulation boundary.
        inlet_height, inlet_material := default_apply_island_hydrology(
            &water,
            mouth.position[0],
            mouth.position[1] - 8,
            10,
            0,
        )
        testing.expect(t, inlet_height < 2)
        testing.expect(t, inlet_material < -1)
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
    testing.expect_value(t, duplicate.estuary.selected_seed, hydrology[0].estuary.selected_seed)
    testing.expect_value(t, duplicate.estuary.score, hydrology[0].estuary.score)
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

    dry_marsh_islands := 0
    dry_non_marsh_deposits := 0
    delta := &hydrology[1]
    for z in 0 ..< estuaries.GRID_HEIGHT {
        for x in 0 ..< estuaries.GRID_WIDTH {
            index := z * estuaries.GRID_WIDTH + x
            class := delta.estuary.wetland[index]
            if class != .Marsh && class != .Mudflat && class != .Shoal do continue
            nx := f32(x) / f32(estuaries.GRID_WIDTH - 1) * 2 - 1
            nz := f32(z) / f32(estuaries.GRID_HEIGHT - 1) * 2 - 1
            world_x := delta.estuary_center[0] + nx * delta.estuary_half_extent
            world_z := delta.estuary_center[1] + nz * delta.estuary_half_extent
            original_height, _, _ := default_generated_height(&plans, world_x, world_z, half_extent)
            marsh_height, _, marsh_material := default_generated_height(
                &plans,
                world_x,
                world_z,
                half_extent,
                &hydrology,
            )
            if class == .Marsh {
                if marsh_height > .1 && marsh_material > 0 do dry_marsh_islands += 1
            } else if original_height <= 0 && marsh_height > 0 {
                dry_non_marsh_deposits += 1
            }
        }
    }
    testing.expect(t, dry_marsh_islands > 8)
    testing.expect_value(t, dry_non_marsh_deposits, 0)

    // The square simulation boundary must converge exactly to the original
    // island terrain on all four sides.
    for side_sample in 0 ..= 16 {
        along := -1 + f32(side_sample) / 16 * 2
        boundary_points := [3][2]f32{{-1, along}, {1, along}, {along, -1}}
        for boundary in boundary_points {
            world_x := delta.estuary_center[0] + boundary[0] * delta.estuary_half_extent
            world_z := delta.estuary_center[1] + boundary[1] * delta.estuary_half_extent
            original, _, _ := default_generated_height(&plans, world_x, world_z, half_extent)
            integrated, _, _ := default_generated_height(&plans, world_x, world_z, half_extent, &hydrology)
            testing.expect(t, math.abs(original - integrated) < .01)
        }
    }

    // The finite estuary simulation must not emboss its square domain into
    // deep offshore bathymetry when it is baked into the island terrain.
    deep_height, _ := default_apply_island_hydrology(
        &hydrology[1],
        hydrology[1].estuary_center[0],
        hydrology[1].estuary_center[1],
        -20,
        0,
    )
    testing.expect(t, math.abs(deep_height + 20) < .01)

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

    rejected := arbitrary
    rejected.estuary.valid = false
    probe_x := rejected.estuary_center[0] + rejected.estuary_half_extent * .45
    probe_z := rejected.estuary_center[1]
    rejected_height, rejected_material := default_apply_island_hydrology(&rejected, probe_x, probe_z, -3, .25)
    testing.expect_value(t, rejected_height, f32(-3))
    testing.expect_value(t, rejected_material, f32(.25))

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
