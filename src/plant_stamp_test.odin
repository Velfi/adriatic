package main

import terrain "../packages/terrain"
import "core:testing"
import third_person "zelda_engine:third_person"

@(test)
plant_stamp_target_distance_respects_rotated_footprint :: proc(t: ^testing.T) {
    structure := terrain.Structure {
        center_x = 4,
        center_z = 2,
        width    = 8,
        depth    = 6,
        height   = 7,
        kind     = .Architecture,
    }
    testing.expect(t, plant_stamp_structure_distance_squared(structure, 5, 3) == 0)
    testing.expect(t, plant_stamp_structure_distance_squared(structure, 14, 2) == 36)
    structure.rotation = 1.5707963
    testing.expect(t, plant_stamp_structure_distance_squared(structure, 14, 2) == 49)
}

@(test)
plant_stamp_target_ray_hits_rotated_support_surface :: proc(t: ^testing.T) {
    structure := terrain.Structure {
        center_x = 4,
        center_z = 2,
        width    = 8,
        depth    = 6,
        base_y   = 1,
        height   = 7,
        rotation = 1.5707963,
        kind     = .Architecture,
    }
    distance, hit := plant_stamp_ray_structure_distance(
        structure,
        third_person.Vec3{4, 4, 14},
        third_person.Vec3{0, 0, -1},
    )
    testing.expect(t, hit)
    testing.expect(t, distance > 5 && distance < 10)
    _, misses_above := plant_stamp_ray_structure_distance(
        structure,
        third_person.Vec3{4, 20, 14},
        third_person.Vec3{0, 0, -1},
    )
    testing.expect(t, !misses_above)
}

@(test)
plant_stamp_climbers_accept_natural_and_built_supports :: proc(t: ^testing.T) {
    testing.expect(t, plant_stamp_climbing_eligible(.Architecture))
    testing.expect(t, plant_stamp_climbing_eligible(.Rock))
    testing.expect(t, plant_stamp_climbing_eligible(.Cliff))
    testing.expect(t, !plant_stamp_climbing_eligible(.Foliage))
    testing.expect(t, !plant_stamp_climbing_eligible(.Box))
}
