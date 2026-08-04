package tests

import islands "../packages/islands"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "core:math"
import "core:os"
import "core:testing"

@(test)
default_town_sites_keep_the_full_settlement_envelope_on_land :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        town_x, town_z := terrain.default_town_center_for_project(project, sign)
        runway_x, runway_z := terrain.default_runway_center_for_project(project, sign)
        runway_half_length := f32(terrain.WORLD_SIZE_METERS * .5) * terrain.DEFAULT_RUNWAY_HALF_LENGTH
        runway_dx := max(math.abs(town_x - runway_x) - runway_half_length, f32(0))
        runway_dz := math.abs(town_z - runway_z)
        runway_distance := f32(math.sqrt(f64(runway_dx * runway_dx + runway_dz * runway_dz)))
        testing.expect(t, runway_distance >= terrain.DEFAULT_TOWN_SITE_RADIUS + terrain.DEFAULT_TOWN_RUNWAY_CLEARANCE)
        radii := [3]f32{0, terrain.DEFAULT_TOWN_SITE_RADIUS * .55, terrain.DEFAULT_TOWN_SITE_RADIUS}
        for radius in radii {
            sample_total := radius == 0 ? 1 : 32
            for sample_index in 0 ..< sample_total {
                angle := f32(sample_index) * math.TAU / f32(sample_total)
                x := town_x + math.cos(angle) * radius
                z := town_z + math.sin(angle) * radius
                testing.expect(t, terrain.sample_surface_height(project, 0, x, z) > project.sea_level + .8)
            }
        }
    }
}

@(test)
terrain_strokes_propagate_through_every_clipmap_level :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    revision := project.revision
    terrain.apply_stroke(project, .Raise, 0, 0, 8, 1, 1)
    testing.expect(t, project.revision == revision + 1)
    for level in 0 ..< terrain.CLIPMAP_LEVELS do testing.expect(t, terrain.sample_surface_height(project, level, 0, 0) > 0)
}

@(test)
terrain_sculpting_changes_building_level :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    building := terrain.structure_make(0, 0, 8, 8, terrain.sample_surface_height(project, 0, 0, 0), 12)
    building.kind = .Architecture
    index := terrain.add_structure(project, building)
    original_level := project.structures[index].base_y

    terrain.apply_stroke(project, .Raise, 0, 0, 8, 2, 1)

    testing.expect(t, project.structures[index].base_y > original_level)
    testing.expect(
        t,
        project.structures[index].base_y ==
        terrain.sample_surface_height(project, 0, building.center_x, building.center_z),
    )
}

@(test)
terrain_material_is_bounded :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    paint_x, paint_z := terrain.default_island_center(1)
    // Cover at least two samples on the coarsest 32 m level so the derived
    // material survives every LOD's staggered grid alignment.
    terrain.apply_stroke(project, .Paint, paint_x, paint_z, 72, 10, 1)
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        material := terrain.sample_material(project, level, paint_x, paint_z)
        testing.expect(t, material > 0)
        testing.expect(t, material <= 1)
    }
}

@(test)
terrain_render_material_interpolates_without_changing_cell_classification :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    level := &project.levels[0]
    sample_x, sample_z := 240, 240
    left_index := sample_z * terrain.TERRAIN_RESOLUTION + sample_x
    right_index := left_index + 1
    level.material[left_index] = -1
    level.material[right_index] = 0
    left_x := level.origin_x + f32(sample_x) * level.cell_size
    z := level.origin_z + f32(sample_z) * level.cell_size
    midpoint_x := left_x + level.cell_size * .5

    testing.expect(t, math.abs(terrain.sample_render_material(project, 0, midpoint_x, z) + .5) < .001)
    testing.expect(t, terrain.sample_material(project, 0, left_x, z) == -1)
    testing.expect(t, terrain.sample_material(project, 0, left_x + level.cell_size, z) == 0)
}

@(test)
terrain_brush_hardness_controls_edge_falloff :: proc(t: ^testing.T) {
    soft := terrain.new_project()
    hard := terrain.new_project()
    defer terrain.free_project(soft)
    defer terrain.free_project(hard)
    center_x := soft.levels[0].origin_x + f32(terrain.TERRAIN_RESOLUTION / 2) * soft.levels[0].cell_size
    center_z := soft.levels[0].origin_z + f32(terrain.TERRAIN_RESOLUTION / 2) * soft.levels[0].cell_size
    terrain.apply_stroke_with_hardness(soft, .Raise, center_x, center_z, 100, 1, 1, 0)
    terrain.apply_stroke_with_hardness(hard, .Raise, center_x, center_z, 100, 1, 1, 1)
    testing.expect(
        t,
        terrain.sample_surface_height(hard, 0, center_x + 50, center_z) >
        terrain.sample_surface_height(soft, 0, center_x + 50, center_z),
    )
    testing.expect(
        t,
        terrain.sample_surface_height(soft, 0, center_x, center_z) ==
        terrain.sample_surface_height(hard, 0, center_x, center_z),
    )
}

@(test)
terrain_ground_classifier_mirrors_renderer_bands :: proc(t: ^testing.T) {
    // Ground at or below sea level is beach edge, never open water.
    testing.expect(t, terrain.classify_ground(0, 0, 0) == .Sand)
    testing.expect(t, terrain.classify_ground(0, -2, 0) == .Sand)
    // Painted material dominates regardless of elevation, matching the
    // renderer's `painted > .5` soil short-circuit.
    testing.expect(t, terrain.classify_ground(.8, 3.5, 0) == .Dirt)
    testing.expect(t, terrain.classify_ground(1, .3, 0) == .Dirt)
    // Unpainted low shelf reads as sand; its soil-dominated upper half as dirt.
    testing.expect(t, terrain.classify_ground(0, .3, 0) == .Sand)
    testing.expect(t, terrain.classify_ground(0, .8, 0) == .Dirt)
    // Unpainted upland reads as dirt near the transition, grass once it climbs.
    testing.expect(t, terrain.classify_ground(0, 1.4, 0) == .Dirt)
    testing.expect(t, terrain.classify_ground(0, 4, 0) == .Grass)
    // Sea level offsets shift the bands with the water plane.
    testing.expect(t, terrain.classify_ground(0, 10.3, 10) == .Sand)
    testing.expect(t, terrain.classify_ground(0, 14, 10) == .Grass)
    testing.expect(t, terrain.classify_ground(-1, 14, 10) == .Sand)
    testing.expect(t, terrain.classify_ground(-.1, 14, 10) == .Grass)
}

@(test)
terrain_ground_surface_at_tracks_painted_material :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    // A default island top is unpainted upland: it should read as grass.
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    offset := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    testing.expect(t, terrain.ground_surface_at(project, 0, -offset, -offset) == .Grass)
    // Painting the same spot flips it to bare soil.
    terrain.apply_stroke(project, .Paint, -offset, -offset, 100, 1, 1)
    testing.expect(t, terrain.ground_surface_at(project, 0, -offset, -offset) == .Dirt)
    // A nil project falls back to the neutral grass surface.
    testing.expect(t, terrain.ground_surface_at(nil, 0, 0, 0) == .Grass)
}

@(test)
terrain_ground_grip_distinguishes_sand_dirt_and_grass :: proc(t: ^testing.T) {
    sand := terrain.ground_grip(.Sand)
    dirt := terrain.ground_grip(.Dirt)
    grass := terrain.ground_grip(.Grass)
    testing.expect(t, dirt.lateral > grass.lateral)
    testing.expect(t, grass.lateral > sand.lateral)
    testing.expect(t, dirt.longitudinal > grass.longitudinal)
    testing.expect(t, grass.longitudinal > sand.longitudinal)
    testing.expect(t, sand.rolling_resistance > grass.rolling_resistance)
    testing.expect(t, grass.rolling_resistance > dirt.rolling_resistance)
}

@(test)
terrain_project_file_round_trips_height_material_and_structures :: proc(t: ^testing.T) {
    path := "build/terrain_project_test.bin"
    defer os.remove(path)
    source := terrain.new_project()
    loaded := terrain.new_project()
    defer terrain.free_project(source)
    defer terrain.free_project(loaded)
    terrain.apply_stroke_with_hardness(source, .Raise, 0, 0, 100, 1, 1, .8)
    terrain.apply_stroke_with_hardness(source, .Paint, 0, 0, 100, 1, 1, .8)
    foliage := terrain.structure_make(20, -30, 40, 50, 0, 60)
    foliage.kind = .Foliage
    terrain.add_structure(source, foliage)
    building := terrain.structure_make(-20, 30, 18, 16, 0, 12)
    building.kind = .Architecture
    building.building.archetype = .Shop_House
    building.building.purpose = .Inn_Shop
    terrain.add_structure(source, building)
    source.city_density[terrain.RING_RESOLUTION / 2 * terrain.RING_RESOLUTION + terrain.RING_RESOLUTION / 2] = 203
    road_a := roads.add_node(&source.road_graph, {0, 2, 0})
    road_b := roads.add_node(&source.road_graph, {40, 3, 20})
    road_edge := roads.add_straight_edge(&source.road_graph, road_a, road_b, 7, 1, .Cobblestone)
    testing.expect(t, terrain.save_project(source, path))
    testing.expect(t, terrain.load_project(loaded, path))
    testing.expect(t, terrain.sample_surface_height(loaded, 0, 0, 0) == terrain.sample_surface_height(source, 0, 0, 0))
    testing.expect(t, terrain.sample_material(loaded, 0, 0, 0) == terrain.sample_material(source, 0, 0, 0))
    testing.expect(t, loaded.structure_count == 2)
    testing.expect(t, loaded.structures[0].height == source.structures[0].height)
    testing.expect(t, loaded.structures[0].group_id == source.structures[0].group_id)
    testing.expect(t, loaded.structures[0].kind == .Foliage)
    testing.expect(t, loaded.structures[1].building == source.structures[1].building)
    testing.expect(
        t,
        loaded.city_density[terrain.RING_RESOLUTION / 2 * terrain.RING_RESOLUTION + terrain.RING_RESOLUTION / 2] ==
        203,
    )
    testing.expect(t, loaded.road_graph.node_count == source.road_graph.node_count)
    testing.expect(t, loaded.road_graph.edge_count == source.road_graph.edge_count)
    testing.expect(t, loaded.road_graph.nodes[road_b].position == source.road_graph.nodes[road_b].position)
    testing.expect(t, loaded.road_graph.edges[road_edge].pavement == .Cobblestone)
}

@(test)
terrain_project_grows_and_round_trips_beyond_legacy_structure_limit :: proc(t: ^testing.T) {
    path := "build/terrain_project_growable_test.bin"
    defer os.remove(path)
    source := terrain.new_project()
    loaded := terrain.new_project()
    defer terrain.free_project(source)
    defer terrain.free_project(loaded)
    count := terrain.LEGACY_STRUCTURE_CAPACITY + 144
    for index in 0 ..< count {
        structure := terrain.structure_make(f32(index), f32(-index), 4, 5, 1, 6)
        if index == count - 1 do structure.entrance_side = .Left
        testing.expect_value(t, terrain.add_structure(source, structure), index)
    }
    testing.expect_value(t, source.structure_count, count)
    testing.expect(t, len(source.structures) >= count)
    testing.expect(t, terrain.save_project(source, path))
    testing.expect(t, terrain.load_project(loaded, path))
    testing.expect_value(t, loaded.structure_count, count)
    testing.expect_value(t, loaded.structures[count - 1].center_x, f32(count - 1))
    testing.expect_value(t, loaded.structures[count - 1].center_z, f32(-(count - 1)))
    testing.expect_value(t, loaded.structures[count - 1].entrance_side, terrain.Entrance_Side.Left)
}

@(test)
terrain_v4_project_migration_copies_fixed_structures_into_growable_storage :: proc(t: ^testing.T) {
    legacy := new(terrain.Project_V4)
    defer free(legacy)
    legacy.structure_count = 2
    legacy.next_structure_id = 19
    legacy.structures[0] = {
        center_x = 4,
        center_z = 5,
        width    = 6,
        depth    = 7,
        base_y   = 8,
        height   = 9,
    }
    legacy.structures[1] = {
        center_x = 10,
        center_z = 11,
        width    = 12,
        depth    = 13,
        base_y   = 14,
        height   = 15,
    }
    migrated := new(terrain.Project)
    defer terrain.free_project(migrated)
    testing.expect(t, terrain.project_migrate_v4(migrated, legacy))
    testing.expect_value(t, migrated.structure_count, 2)
    testing.expect_value(t, len(migrated.structures), 2)
    testing.expect_value(t, migrated.next_structure_id, u64(19))
    testing.expect_value(t, migrated.structures[1].center_x, f32(10))
    testing.expect_value(t, migrated.structures[1].entrance_side, terrain.Entrance_Side.Front)
}

@(test)
terrain_v6_project_migration_upsamples_legacy_clipmap_levels :: proc(t: ^testing.T) {
    legacy := new(terrain.Project_File_Payload_V6)
    migrated := terrain.new_project()
    defer free(legacy)
    defer terrain.free_project(migrated)
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        data := &legacy.levels[level]
        data.cell_size = terrain.FINE_CELL_SIZE * f32(u32(1) << u32(level))
        extent := f32(terrain.LEGACY_TERRAIN_RESOLUTION - 1) * data.cell_size
        data.origin_x, data.origin_z = -extent * .5, -extent * .5
    }
    center := terrain.LEGACY_TERRAIN_RESOLUTION / 2
    for z in center - 1 ..= center {
        for x in center - 1 ..= center {
            legacy.levels[0].heights[z * terrain.LEGACY_TERRAIN_RESOLUTION + x] = 7
            legacy.levels[0].material[z * terrain.LEGACY_TERRAIN_RESOLUTION + x] = .6
        }
    }
    testing.expect(t, terrain.project_migrate_v6(migrated, legacy, nil))
    testing.expect_value(t, migrated.levels[0].cell_size, terrain.FINE_CELL_SIZE)
    testing.expect(t, math.abs(terrain.sample_surface_height(migrated, 0, 0, 0) - 7) < .001)
    testing.expect(t, math.abs(terrain.sample_material(migrated, 0, 0, 0) - .6) < .001)
}

@(test)
default_terrain_has_two_opposite_corner_islands :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    offset := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    testing.expect(t, terrain.sample_surface_height(project, 0, -offset, -offset) > project.sea_level)
    testing.expect(t, terrain.sample_surface_height(project, 0, offset, offset) > project.sea_level)
    testing.expect(t, terrain.sample_surface_height(project, 0, -offset, offset) <= project.sea_level)
    testing.expect(t, terrain.sample_surface_height(project, 0, offset, -offset) <= project.sea_level)
}

@(test)
default_generated_islands_have_dune_material_and_coastal_bathymetry :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    level := &project.levels[4]
    dry_dune_samples, submerged_samples := 0, 0
    for z in 0 ..< terrain.TERRAIN_RESOLUTION {
        for x in 0 ..< terrain.TERRAIN_RESOLUTION {
            index := z * terrain.TERRAIN_RESOLUTION + x
            height := level.heights[index]
            material := level.material[index]
            if height > project.sea_level && material < -.05 do dry_dune_samples += 1
            if height < project.sea_level - .1 do submerged_samples += 1
        }
    }
    testing.expect(t, dry_dune_samples > 12)
    testing.expect(t, submerged_samples > 100)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        center_x, center_z := terrain.default_island_center(sign)
        testing.expect(t, terrain.sample_material(project, 0, center_x, center_z) >= 0)
    }
}

@(test)
generated_low_coast_transitions_from_wet_to_dry_beach_before_dunes :: proc(t: ^testing.T) {
    plans: [len(terrain.DEFAULT_ISLAND_SIGNS)]islands.Plan
    for seed, index in terrain.DEFAULT_ISLAND_SEEDS {
        plans[index] = islands.generate(seed)
    }
    defer for &plan in plans do islands.destroy(&plan)

    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    center_x, center_z := terrain.default_island_center(1)
    found := false
    for x := center_x - 800; x <= center_x + 800 && !found; x += 16 {
        shore_z := center_z
        found_shore := false
        for offset := f32(0); offset <= terrain.DEFAULT_GENERATED_ISLAND_HALF_Z * 1.2; offset += 4 {
            _, signed_distance, _ := terrain.default_generated_height(&plans, x, center_z - offset, half_extent)
            if signed_distance >= 0 {
                shore_z = center_z - offset + 4
                found_shore = true
                break
            }
        }
        if !found_shore do continue
        wet_height, _, wet := terrain.default_generated_height(&plans, x, shore_z + 2, half_extent)
        dry_height, _, dry := terrain.default_generated_height(&plans, x, shore_z + 14, half_extent)
        shoulder_height, _, shoulder := terrain.default_generated_height(&plans, x, shore_z + 34, half_extent)
        if wet < -1.02 &&
           dry < -.35 &&
           shoulder > wet &&
           dry_height > wet_height + .08 &&
           shoulder_height >= dry_height {
            found = true
        }
    }
    testing.expect(t, found)
}

@(test)
generated_beach_width_is_deterministic_bounded_and_changes_smoothly_alongshore :: proc(t: ^testing.T) {
    seed := terrain.DEFAULT_ISLAND_SEEDS[1]
    minimum, maximum := f32(100), f32(0)
    previous := terrain.default_generated_beach_width(seed, 1800, 2200)
    for x := f32(1801); x <= 3400; x += 1 {
        width := terrain.default_generated_beach_width(seed, x, 2200)
        testing.expect(t, width >= 20 && width <= 35)
        testing.expect(t, math.abs(width - previous) < .12)
        testing.expect_value(t, width, terrain.default_generated_beach_width(seed, x, 2200))
        minimum = min(minimum, width)
        maximum = max(maximum, width)
        previous = width
    }
    testing.expect(t, maximum - minimum > 5)
}

@(test)
generated_dune_character_is_deterministic_bounded_and_varies_by_island :: proc(t: ^testing.T) {
    west := terrain.default_generated_dune_character(terrain.DEFAULT_ISLAND_SEEDS[0])
    west_again := terrain.default_generated_dune_character(terrain.DEFAULT_ISLAND_SEEDS[0])
    east := terrain.default_generated_dune_character(terrain.DEFAULT_ISLAND_SEEDS[1])
    testing.expect_value(t, west, west_again)
    characters := [2]terrain.Generated_Dune_Character{west, east}
    for character in characters {
        testing.expect(t, character.height >= 4.6 && character.height <= 6.2)
        testing.expect(t, character.spacing >= 34 && character.spacing <= 45)
        testing.expect(t, character.width >= 60 && character.width <= terrain.DEFAULT_DUNE_MAX_WIDTH)
        testing.expect(t, character.wind_strength >= .58 && character.wind_strength <= .78)
        testing.expect(t, character.vegetation_strength >= .58 && character.vegetation_strength <= .82)
    }
    testing.expect(
        t,
        west.height != east.height ||
        west.spacing != east.spacing ||
        west.width != east.width ||
        west.vegetation_strength != east.vegetation_strength,
    )
}

@(test)
generated_coastal_morphology_distinguishes_sheltered_bays_and_exposed_headlands :: proc(t: ^testing.T) {
    seed := terrain.DEFAULT_ISLAND_SEEDS[0]
    sheltered := terrain.default_generated_coastal_morphology(seed, 120, -80, 1, 0)
    sheltered_again := terrain.default_generated_coastal_morphology(seed, 120, -80, 1, 0)
    exposed := terrain.default_generated_coastal_morphology(seed, 120, -80, -1, 1)
    testing.expect_value(t, sheltered, sheltered_again)
    testing.expect(t, sheltered.beach_width > exposed.beach_width)
    testing.expect(t, sheltered.dune_width_scale > exposed.dune_width_scale)
    testing.expect(t, sheltered.dune_height_scale < exposed.dune_height_scale)
    testing.expect(t, sheltered.vegetation_scale > exposed.vegetation_scale)
    contexts := [2]terrain.Generated_Coastal_Morphology{sheltered, exposed}
    for morphology in contexts {
        testing.expect(t, morphology.beach_width >= 18 && morphology.beach_width <= 39)
        testing.expect(t, morphology.dune_height_scale >= .76 && morphology.dune_height_scale <= 1.08)
        testing.expect(t, morphology.dune_width_scale >= .82 && morphology.dune_width_scale <= 1.05)
        testing.expect(t, morphology.vegetation_scale >= .92 && morphology.vegetation_scale <= 1.13)
    }
}

@(test)
generated_coast_context_uses_the_anisotropic_world_metric :: proc(t: ^testing.T) {
    plan := islands.generate(terrain.DEFAULT_ISLAND_SEEDS[0])
    defer islands.destroy(&plan)
    step_x := f32(2) / f32(islands.GRID_WIDTH - 1)
    step_z := f32(2) / f32(islands.GRID_HEIGHT - 1)
    cell_x := terrain.DEFAULT_GENERATED_ISLAND_HALF_X * step_x
    cell_z := terrain.DEFAULT_GENERATED_ISLAND_HALF_Z * step_z
    found := false
    for z := 2; z < islands.GRID_HEIGHT - 2 && !found; z += 1 {
        local_z := f32(z) / f32(islands.GRID_HEIGHT - 1) * 2 - 1
        for x in 2 ..< islands.GRID_WIDTH - 2 {
            local_x := f32(x) / f32(islands.GRID_WIDTH - 1) * 2 - 1
            left := islands.sample_signed_distance(&plan, local_x - step_x, local_z)
            right := islands.sample_signed_distance(&plan, local_x + step_x, local_z)
            back := islands.sample_signed_distance(&plan, local_x, local_z - step_z)
            front := islands.sample_signed_distance(&plan, local_x, local_z + step_z)
            grid_x, grid_z := right - left, front - back
            grid_length := f32(math.sqrt(f64(grid_x * grid_x + grid_z * grid_z)))
            if grid_length < .1 || abs(grid_x) < .1 || abs(grid_z) < .1 do continue
            world_x, world_z := grid_x / cell_x, grid_z / cell_z
            world_length := f32(math.sqrt(f64(world_x * world_x + world_z * world_z)))
            coast := terrain.default_generated_coast_context(&plan, local_x, local_z, 1)
            testing.expect(t, math.abs(coast.outward_normal[0] - world_x / world_length) < .0001)
            testing.expect(t, math.abs(coast.outward_normal[1] - world_z / world_length) < .0001)
            testing.expect(t, math.abs(coast.distance_scale - f32(math.sqrt(f64(cell_x * cell_z)))) < .001)
            found = true
            break
        }
    }
    testing.expect(t, found)
}

@(test)
coastal_grass_cards_open_only_on_elevated_stabilized_sand :: proc(t: ^testing.T) {
    sea := f32(0)
    testing.expect(t, !terrain.supports_coastal_grass(-1.8, 1.8, sea))
    testing.expect(t, !terrain.supports_coastal_grass(-.70, 2.8, sea))
    testing.expect(t, !terrain.supports_coastal_grass(-.45, .7, sea))
    testing.expect(t, terrain.supports_coastal_grass(-.58, 2.8, sea))
    testing.expect(t, terrain.supports_coastal_grass(-.20, 3.2, sea))
    testing.expect(t, terrain.supports_coastal_grass(0, 4.2, sea))
}

@(test)
clipmap_levels_are_nested_without_scaled_world_features :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    authored_half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        testing.expect(t, project.levels[level].cell_size == terrain.FINE_CELL_SIZE * f32(u32(1) << u32(level)))
    }
    testing.expect(
        t,
        terrain.sample_surface_height(
            project,
            0,
            authored_half_extent * terrain.DEFAULT_ISLAND_OFFSET,
            authored_half_extent * terrain.DEFAULT_ISLAND_OFFSET,
        ) >
        project.sea_level,
    )
}

@(test)
default_islands_support_the_full_runway :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        center_x, center_z := terrain.default_runway_center_for_project(project, sign)
        runway_half_length := half_extent * terrain.DEFAULT_RUNWAY_HALF_LENGTH
        runway_half_width := half_extent * terrain.DEFAULT_RUNWAY_HALF_WIDTH
        runway_ends := [2]f32{center_x - runway_half_length, center_x + runway_half_length}
        runway_sides := [2]f32{center_z - runway_half_width, center_z + runway_half_width}
        for x in runway_ends {
            for z in runway_sides {
                testing.expect(t, terrain.sample_surface_height(project, 0, x, z) > project.sea_level)
            }
        }
    }
    testing.expect(t, project.road_graph.node_count == 4)
    testing.expect(t, project.road_graph.edge_count == 2)
    runway_edges := 0
    for edge in project.road_graph.edges[:project.road_graph.edge_count] {
        testing.expect(t, edge.pavement == .Asphalt)
        from := project.road_graph.nodes[edge.from].position
        to := project.road_graph.nodes[edge.to].position
        if edge.half_width == half_extent * terrain.DEFAULT_RUNWAY_HALF_WIDTH {
            runway_edges += 1
            testing.expect(t, from.z == to.z)
            testing.expect(t, math.abs(to.x - from.x - half_extent * terrain.DEFAULT_RUNWAY_HALF_LENGTH * 2) < .001)
            for sample_index in 0 ..= 8 {
                sample_x := from.x + (to.x - from.x) * f32(sample_index) / 8
                testing.expect(
                    t,
                    math.abs(terrain.sample_surface_height(project, 0, sample_x, from.z) - from.y) < .001,
                )
            }
        }
    }
    testing.expect_value(t, runway_edges, len(terrain.DEFAULT_ISLAND_SIGNS))
}

@(test)
default_runway_sites_are_terrain_selected_and_bounded_inside_islands :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        island_x, island_z := terrain.default_island_center(sign)
        runway_x, runway_z := terrain.default_runway_center_for_project(project, sign)
        offset_x := runway_x - island_x
        offset_z := runway_z - island_z
        testing.expect(t, math.abs(offset_x) + math.abs(offset_z) > 1)
        testing.expect(t, math.abs(offset_x) <= 640)
        testing.expect(t, math.abs(offset_z) <= 560)
    }
}

@(test)
regenerated_islands_place_runways_at_the_regenerated_terrain_selected_sites :: proc(t: ^testing.T) {
    seeds := terrain.next_default_island_seeds(terrain.DEFAULT_ISLAND_SEEDS)
    project := terrain.new_project_seeded(seeds)
    defer terrain.free_project(project)
    testing.expect_value(t, project.road_graph.node_count, 4)
    testing.expect_value(t, project.road_graph.edge_count, 2)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        airport_x, airport_z := terrain.default_airport_center_for_project(project, sign)
        testing.expect(t, terrain.sample_surface_height(project, 0, airport_x, airport_z) > project.sea_level)
    }
}

@(test)
default_islands_have_bluffs_away_from_arrival_districts :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        center_x, center_z := terrain.default_island_center(sign)
        west := sign < 0
        bluff_x := center_x + (west ? f32(-118) : f32(112))
        bluff_z := center_z + (west ? f32(104) : f32(92))
        bluff := terrain.sample_surface_height(project, 0, bluff_x, bluff_z)
        runway := terrain.sample_surface_height(project, 0, center_x, center_z)
        testing.expect(t, bluff > runway + 5)
    }
}

@(test)
default_islands_have_landforms_at_player_scale :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        center := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        minimum, maximum := f32(1e9), f32(-1e9)
        largest_step: f32
        // Sample an inland strip beyond the leveled runway shoulder. Twenty
        // meters is a few seconds of travel and should reveal changing ground.
        z := center + sign * 125
        previous := terrain.sample_surface_height(project, 0, center - 120, z)
        for offset := -100; offset <= 120; offset += 20 {
            height := terrain.sample_surface_height(project, 0, center + f32(offset), z)
            minimum = min(minimum, height)
            maximum = max(maximum, height)
            largest_step = max(largest_step, math.abs(height - previous))
            previous = height
        }
        testing.expect(t, maximum - minimum > 2)
        testing.expect(t, largest_step > .35)
    }
}

@(test)
terrain_constraints_compose_additive_landscape_before_level_surfaces :: proc(t: ^testing.T) {
    constraints := [2]terrain.Terrain_Constraint {
        {mode = .Add, shape = .Ellipse, curve = .Quadratic, priority = 0, half_x = 10, half_z = 10, target = 8},
        {
            mode = .Set,
            shape = .Rectangle,
            curve = .Smooth,
            priority = 10,
            half_x = 2,
            half_z = 2,
            feather = 4,
            target = 3,
        },
    }
    testing.expect(t, terrain.terrain_compose_constraints(1, constraints[:], 0, 0) == 3)
    transition := terrain.terrain_compose_constraints(1, constraints[:], 4, 0)
    testing.expect(t, transition > 3 && transition < 9)
    landscape := terrain.terrain_compose_constraints(1, constraints[:], 7, 0)
    testing.expect(t, landscape > 1)
}

@(test)
default_islands_are_aircraft_scale :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    diameter := half_extent * terrain.DEFAULT_ISLAND_RADIUS * 2
    runway_length := half_extent * terrain.DEFAULT_RUNWAY_HALF_LENGTH * 2
    testing.expect(t, diameter >= 550)
    testing.expect(t, runway_length >= 390)
    testing.expect(t, runway_length <= 410)
}

@(test)
terrain_levels_progress_from_one_meter_to_world_scale :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    testing.expect(t, project.levels[0].cell_size == 1)
    testing.expect(t, project.levels[4].cell_size == 16)
    span := f32(terrain.TERRAIN_RESOLUTION - 1) * project.levels[4].cell_size
    testing.expect(t, span >= terrain.WORLD_SIZE_METERS)
}

@(test)
terrain_edits_downsample_into_coarser_overlaps :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    fine := &project.levels[0]
    center_x := fine.origin_x + 128 * fine.cell_size
    center_z := fine.origin_z + 128 * fine.cell_size
    terrain.apply_stroke_with_hardness(project, .Raise, center_x, center_z, 24, 1, 1, .5)
    for level in 1 ..< terrain.CLIPMAP_LEVELS {
        coarse := &project.levels[level]
        previous := &project.levels[level - 1]
        for z in 0 ..< terrain.TERRAIN_RESOLUTION {
            world_z := coarse.origin_z + f32(z) * coarse.cell_size
            for x in 0 ..< terrain.TERRAIN_RESOLUTION {
                world_x := coarse.origin_x + f32(x) * coarse.cell_size
                if !terrain.level_contains(previous, world_x, world_z) do continue
                expected := terrain.sample_level_height(previous, world_x, world_z)
                testing.expect(t, coarse.heights[terrain.sample_index(x, z)] == expected)
            }
        }
    }
}

@(test)
clipmap_transition_converges_fine_edge_onto_coarse_surface :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    x, z := f32(1.5), f32(2.5)
    fine := terrain.sample_surface_height(project, 0, x, z)
    coarse := terrain.sample_surface_height(project, 1, x, z)
    testing.expect(t, terrain.sample_clipmap_transition_height(project, 0, x, z, 0) == fine)
    testing.expect(t, terrain.sample_clipmap_transition_height(project, 0, x, z, 1) == coarse)
    halfway := terrain.sample_clipmap_transition_height(project, 0, x, z, .5)
    testing.expect(t, math.abs(halfway - (fine + coarse) * .5) < .0001)
    last := terrain.CLIPMAP_LEVELS - 1
    testing.expect(
        t,
        terrain.sample_clipmap_transition_height(project, last, x, z, 1) ==
        terrain.sample_surface_height(project, last, x, z),
    )
}

@(test)
structure_placement_snaps_and_follows_terrain :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    cell := project.levels[0].cell_size
    structure := terrain.structure_make(13.2, -8.7, 1, 1, 999, 24)
    structure.center_x = terrain.snap_to_grid(structure.center_x, cell)
    structure.center_z = terrain.snap_to_grid(structure.center_z, cell)
    structure.base_y = terrain.sample_surface_height(project, 0, structure.center_x, structure.center_z)
    index := terrain.add_structure(project, structure)
    testing.expect(t, index == 0)
    testing.expect(t, project.structures[index].center_x == terrain.snap_to_grid(13.2, cell))
    testing.expect(
        t,
        project.structures[index].base_y ==
        terrain.sample_surface_height(project, 0, structure.center_x, structure.center_z),
    )
}

@(test)
structure_hit_testing_prefers_the_topmost_structure :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    first := terrain.add_structure(project, terrain.structure_make(0, 0, 20, 20, 0, 10))
    second := terrain.add_structure(project, terrain.structure_make(0, 0, 8, 8, 0, 10))
    testing.expect(t, first == 0)
    testing.expect(t, second == 1)
    testing.expect(t, terrain.structure_index_at(project, 0, 0) == second)
    testing.expect(t, terrain.structure_index_at(project, 9, 0) == first)
    testing.expect(t, terrain.structure_index_at(project, 20, 20) == -1)
}

@(test)
structure_duplicate_and_remove_preserve_ids :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    original := terrain.add_structure(project, terrain.structure_make(0, 0, 10, 10, 0, 10))
    duplicate := terrain.duplicate_structure(project, original, 20, 0)
    original_id := project.structures[original].id
    duplicate_id := project.structures[duplicate].id
    testing.expect(t, original_id != duplicate_id)
    testing.expect(t, project.structures[duplicate].center_x == 20)
    testing.expect(t, terrain.remove_structure(project, original))
    testing.expect(t, project.structure_count == 1)
    testing.expect(t, project.structures[0].id == duplicate_id)
}

@(test)
overlapping_foliage_nodes_merge_without_spending_structure_budget :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    cell := terrain.BASE_CELL_SIZE
    first := terrain.structure_make(0, 0, cell * 2, cell, 3, cell)
    first.kind = .Foliage
    first_index := terrain.add_or_merge_foliage(project, first)
    first_id := project.structures[first_index].id

    overlapping := terrain.structure_make(cell * 1.5, 0, cell * 2, cell, 2, cell * 2)
    overlapping.kind = .Foliage
    merged_index := terrain.add_or_merge_foliage(project, overlapping)

    testing.expect(t, merged_index == first_index)
    testing.expect(t, project.structure_count == 1)
    testing.expect(t, project.structures[merged_index].id == first_id)
    testing.expect(t, project.structures[merged_index].center_x == cell * .75)
    testing.expect(t, project.structures[merged_index].width == cell * 3.5)
    testing.expect(t, project.structures[merged_index].depth == cell)
    testing.expect(t, project.structures[merged_index].base_y == 2)
    testing.expect(t, math.abs(project.structures[merged_index].height - cell * 2) < .001)

    separate := terrain.structure_make(100, 0, cell, cell, 0, cell)
    separate.kind = .Foliage
    terrain.add_or_merge_foliage(project, separate)
    testing.expect(t, project.structure_count == 2)
}

@(test)
formation_density_stroke_merges_into_a_range :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    cell := terrain.BASE_CELL_SIZE
    group_id := project.next_structure_id
    for index in 0 ..< 5 {
        formation := terrain.structure_make(f32(index) * cell, 0, cell * 1.5, cell, 0, cell * 1.5)
        formation.kind = .Rock
        formation.group_id = group_id
        _ = terrain.add_or_merge_formation(project, formation, cell * .5)
    }

    testing.expect(t, project.structure_count == 1)
    testing.expect(t, project.structures[0].kind == .Ridge)
    testing.expect(t, project.structures[0].width >= cell * 5)
}

@(test)
formation_density_strokes_do_not_merge_across_edit_groups :: proc(t: ^testing.T) {
    project := terrain.new_project()
    defer terrain.free_project(project)
    cell := terrain.BASE_CELL_SIZE
    first := terrain.structure_make(0, 0, cell * 2, cell, 0, cell)
    first.kind = .Rock
    first.group_id = 17
    _ = terrain.add_or_merge_formation(project, first, cell)
    second := first
    second.center_x = cell
    second.group_id = 18
    _ = terrain.add_or_merge_formation(project, second, cell)

    testing.expect(t, project.structure_count == 2)
}

@(test)
formation_kinds_cycle_without_skipping :: proc(t: ^testing.T) {
    kind := terrain.Formation_Kind.Box
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Rock)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Spire)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Mountain)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Ridge)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Foliage)
    kind = terrain.formation_kind_next(kind)
    testing.expect(t, kind == .Box)
}

@(test)
cliff_stroke_raises_the_left_side_and_reverse_flips_it :: proc(t: ^testing.T) {
    forward := terrain.new_project()
    reverse := terrain.new_project()
    defer terrain.free_project(forward)
    defer terrain.free_project(reverse)
    points := [2]terrain.Cliff_Point{{-40, 0}, {40, 0}}
    reversed := [2]terrain.Cliff_Point{{40, 0}, {-40, 0}}
    forward_high_before := terrain.sample_surface_height(forward, 0, 0, 4)
    forward_low_before := terrain.sample_surface_height(forward, 0, 0, -4)
    reverse_north_before := terrain.sample_surface_height(reverse, 0, 0, 4)
    testing.expect(t, terrain.apply_cliff_stroke(forward, points[:], 20, 8, .Raise))
    testing.expect(t, terrain.apply_cliff_stroke(reverse, reversed[:], 20, 8, .Raise))
    testing.expect(t, terrain.sample_surface_height(forward, 0, 0, 4) > forward_high_before + 4)
    testing.expect(t, math.abs(terrain.sample_surface_height(forward, 0, 0, -4) - forward_low_before) < .01)
    testing.expect(t, math.abs(terrain.sample_surface_height(reverse, 0, 0, 4) - reverse_north_before) < .01)
}

@(test)
cliff_elevation_modes_and_width_preserve_unaffected_terrain :: proc(t: ^testing.T) {
    lower := terrain.new_project()
    split := terrain.new_project()
    defer terrain.free_project(lower)
    defer terrain.free_project(split)
    points := [2]terrain.Cliff_Point{{-40, 0}, {40, 0}}
    lower_high := terrain.sample_surface_height(lower, 0, 0, 4)
    lower_low := terrain.sample_surface_height(lower, 0, 0, -4)
    outside := terrain.sample_surface_height(lower, 0, 0, 30)
    split_high := terrain.sample_surface_height(split, 0, 0, 4)
    split_low := terrain.sample_surface_height(split, 0, 0, -4)
    testing.expect(t, terrain.apply_cliff_stroke(lower, points[:], 20, 8, .Lower))
    testing.expect(t, terrain.apply_cliff_stroke(split, points[:], 20, 8, .Split))
    testing.expect(t, math.abs(terrain.sample_surface_height(lower, 0, 0, 4) - lower_high) < .01)
    testing.expect(t, terrain.sample_surface_height(lower, 0, 0, -4) < lower_low - 4)
    testing.expect(t, math.abs(terrain.sample_surface_height(lower, 0, 0, 30) - outside) < .01)
    testing.expect(t, terrain.sample_surface_height(split, 0, 0, 4) > split_high + 2)
    testing.expect(t, terrain.sample_surface_height(split, 0, 0, -4) < split_low - 2)
}

@(test)
legacy_cliff_cleanup_is_stable :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    defer delete(project.structures)
    project.next_structure_id = 1
    first := terrain.structure_make(0, 0, 1, 1, 0, 1)
    first.kind = .Rock
    cliff := terrain.structure_make(1, 0, 1, 1, 0, 1)
    cliff.kind = .Cliff
    last := terrain.structure_make(2, 0, 1, 1, 0, 1)
    last.kind = .Foliage
    _ = terrain.add_structure(project, first)
    _ = terrain.add_structure(project, cliff)
    _ = terrain.add_structure(project, last)
    testing.expect_value(t, terrain.remove_legacy_cliffs(project), 1)
    testing.expect_value(t, project.structure_count, 2)
    testing.expect(t, project.structures[0].kind == .Rock)
    testing.expect(t, project.structures[1].kind == .Foliage)
}

@(test)
formation_gesture_selects_useful_profiles :: proc(t: ^testing.T) {
    cell := terrain.BASE_CELL_SIZE
    testing.expect(t, terrain.formation_kind_for_gesture(cell * 8, cell * 2, cell * 3) == .Ridge)
    testing.expect(t, terrain.formation_kind_for_gesture(cell * 2, cell * 2, cell * 5) == .Spire)
    testing.expect(t, terrain.formation_kind_for_gesture(cell * 4, cell * 4, cell * 5) == .Mountain)
    testing.expect(t, terrain.formation_kind_for_gesture(cell * 4, cell * 4, cell * 2) == .Rock)
}

@(test)
formation_segments_merge_only_across_similar_angles :: proc(t: ^testing.T) {
    minimum_cosine := f32(0.9961947)
    testing.expect(t, terrain.formation_segments_can_merge(0, 0, 10, 0, 20, 0, minimum_cosine))
    testing.expect(t, terrain.formation_segments_can_merge(0, 0, 10, 0, 20, .5, minimum_cosine))
    testing.expect(t, !terrain.formation_segments_can_merge(0, 0, 10, 0, 20, 2, minimum_cosine))
    testing.expect(t, !terrain.formation_segments_can_merge(0, 0, 10, 0, 10, 10, minimum_cosine))
    testing.expect(t, !terrain.formation_segments_can_merge(0, 0, 0, 0, 10, 0, minimum_cosine))
}

@(test)
rotated_structure_hit_testing_uses_local_bounds :: proc(t: ^testing.T) {
    structure := terrain.structure_make(0, 0, 20, 4, 0, 10)
    structure.rotation = math.PI * .25
    testing.expect(t, terrain.structure_contains_point(structure, 0, 6))
    testing.expect(t, !terrain.structure_contains_point(structure, 0, 16))
}

@(test)
formations_are_opaque_and_raise_the_collision_surface :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    defer delete(project.structures)
    project.next_structure_id = 1
    structure := terrain.structure_make(0, 0, 20, 4, 3, 20)
    structure.kind = .Rock
    structure.rotation = math.PI * .25
    structure_index := terrain.add_structure(project, structure)

    testing.expect_value(t, project.structures[structure_index].color[3], u8(255))
    testing.expect_value(t, terrain.structure_collision_surface_height(project, 0, 6, 1), f32(23))
    testing.expect_value(t, terrain.structure_collision_surface_height(project, 0, 16, 1), f32(1))

    project.structures[structure_index].kind = .Foliage
    testing.expect_value(t, terrain.structure_collision_surface_height(project, 0, 6, 1), f32(1))

    project.structures[structure_index].kind = .Field
    testing.expect_value(t, terrain.structure_collision_surface_height(project, 0, 6, 1), f32(1))
}

@(test)
fields_are_bounded_to_the_supported_heightfield_extent :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    defer delete(project.structures)
    structure := terrain.structure_make(0, 0, 1000, 800, 0, 1.4)
    structure.kind = .Field

    index := terrain.add_structure(project, structure)

    testing.expect_value(t, project.structures[index].width, terrain.FIELD_MAXIMUM_EXTENT)
    testing.expect_value(t, project.structures[index].depth, terrain.FIELD_MAXIMUM_EXTENT)
}
