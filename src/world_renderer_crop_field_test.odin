package main

import "core:math"
import "core:testing"

import terrain "../packages/terrain"

@(test)
world_crop_field_point_follows_terrain_height :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    project.levels[0].cell_size = 1
    project.levels[0].origin_x = 0
    project.levels[0].origin_z = 0
    project.levels[0].heights[0] = 2
    project.levels[0].heights[1] = 4
    project.levels[0].heights[terrain.TERRAIN_RESOLUTION] = 6
    project.levels[0].heights[terrain.TERRAIN_RESOLUTION + 1] = 8
    structure := terrain.Structure {
        center_x = .5,
        center_z = .5,
        width    = 1,
        depth    = 1,
        height   = 1.4,
        kind     = .Field,
    }

    point := world_crop_field_point(structure, project, 0, 0)
    wave := f32(math.sin(f64(point.x * .31 + point.z * .17))) * structure.height * .035

    testing.expect(t, math.abs(point.y - (5 + structure.height + wave)) < .0001)
}

@(test)
world_crop_field_inland_test_cuts_back_from_water :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    project.sea_level = 2
    project.levels[0].cell_size = 1
    project.levels[0].origin_x = 0
    project.levels[0].origin_z = 0
    for z in 0 ..< 32 {
        for x in 0 ..< 32 {
            project.levels[0].heights[z * terrain.TERRAIN_RESOLUTION + x] = 8
        }
    }

    testing.expect(t, world_crop_field_is_inland(project, 16, 16, CROP_FIELD_SHORE_CLEARANCE))

    // Water six metres east carves out this otherwise dry field cell.
    project.levels[0].heights[16 * terrain.TERRAIN_RESOLUTION + 22] = 1
    testing.expect(t, !world_crop_field_is_inland(project, 16, 16, CROP_FIELD_SHORE_CLEARANCE))
}

@(test)
world_crop_field_volume_has_an_organic_plant_footprint :: proc(t: ^testing.T) {
    structure := terrain.Structure {
        width  = 100,
        depth  = 60,
        height = 1.4,
        seed   = 73,
        kind   = .Field,
    }

    testing.expect(t, world_crop_field_volume_contains(structure, 0, 0, 1))
    // The authored volume is only a bounding envelope: its corners are not
    // planted, which prevents the old rectangular-sheet silhouette.
    testing.expect(t, !world_crop_field_volume_contains(structure, 47, 27, 1))
    // Seeded boundary undulation keeps the footprint from collapsing to a
    // perfect ellipse while leaving its stable interior filled.
    boundary_samples := 0
    for index in 0 ..< 16 {
        angle := f32(index) / 16 * f32(math.PI * 2)
        x := math.cos(angle) * structure.width * .43
        z := math.sin(angle) * structure.depth * .43
        if world_crop_field_volume_contains(structure, x, z, 1) do boundary_samples += 1
    }
    testing.expect(t, boundary_samples > 0 && boundary_samples < 16)
}

@(test)
world_crop_field_volume_edge_interpolates_to_the_contour :: proc(t: ^testing.T) {
    edge := world_crop_field_volume_edge({0, 2}, {10, 2}, 1, -3)
    testing.expect(t, math.abs(edge.x - 2.5) < .0001)
    testing.expect(t, edge.y == 2)
}

@(test)
world_foliage_lod_only_condenses_broad_low_plant_fields :: proc(t: ^testing.T) {
    testing.expect(t, !world_foliage_should_condense_to_field(90, 70, 1.5, .Near))
    testing.expect(t, world_foliage_should_condense_to_field(90, 70, 1.5, .Medium))
    testing.expect(t, world_foliage_should_condense_to_field(90, 70, 1.5, .Far))
    testing.expect(t, !world_foliage_should_condense_to_field(90, 70, 42, .Far))
    testing.expect(t, !world_foliage_should_condense_to_field(120, 14, 1.5, .Far))
}
