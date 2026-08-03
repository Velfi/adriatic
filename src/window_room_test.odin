package main

import buildings "../packages/buildings"
import terrain "../packages/terrain"
import "core:math"
import "core:testing"

window_room_test_variant :: proc(archetype: buildings.Archetype, row: int) -> int {
    structure := terrain.Structure {
        seed = 1948,
        building = {archetype = archetype},
    }
    encoded := world_architecture_window_room(structure, .Front, row, 0)
    return int(math.floor(f64(encoded))) - 1
}

@(test)
window_rooms_follow_building_purpose :: proc(t: ^testing.T) {
    testing.expect_value(t, window_room_test_variant(.Dwelling, 0), 0)
    testing.expect_value(t, window_room_test_variant(.Shop_House, 0), 1)
    testing.expect_value(t, window_room_test_variant(.Workshop, 0), 2)
    testing.expect_value(t, window_room_test_variant(.Storehouse, 0), 3)
    testing.expect_value(t, window_room_test_variant(.Post_Office, 0), 4)
    testing.expect_value(t, window_room_test_variant(.Clinic, 0), 5)
}

@(test)
window_rooms_split_mixed_use_floors :: proc(t: ^testing.T) {
    testing.expect_value(t, window_room_test_variant(.Mixed_Use_Dwelling, 0), 1)
    testing.expect_value(t, window_room_test_variant(.Mixed_Use_Dwelling, 1), 0)
    testing.expect_value(t, window_room_test_variant(.Shop_House, 2), 0)
}
