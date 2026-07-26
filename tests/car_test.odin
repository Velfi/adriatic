package tests

import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:testing"

@(test)
simple_car_has_valid_wireframe_indices :: proc(t: ^testing.T) {
    car := vehicles.simple_car()
    for edge in car.edges {
        testing.expect(t, edge.a >= 0 && edge.a < len(car.vertices))
        testing.expect(t, edge.b >= 0 && edge.b < len(car.vertices))
    }
}

@(test)
simple_car_has_a_raised_cabin_and_wheels :: proc(t: ^testing.T) {
    car := vehicles.simple_car()
    testing.expect(t, car.vertices[12].position[1] > car.vertices[4].position[1])
    testing.expect(t, car.vertices[16].position[1] < car.vertices[0].position[1])
    testing.expect(t, car.vertices[24].position[2] > car.vertices[16].position[2])
}

@(test)
simple_car_solid_mesh_is_closed_and_grouped :: proc(t: ^testing.T) {
    mesh := vehicles.simple_car_mesh()
    testing.expect(t, mesh.vertex_count > 0)
    testing.expect(t, mesh.triangle_count >= 100)
    for triangle in vehicles.mesh_triangles(&mesh) {
        testing.expect(t, int(triangle.a) < mesh.vertex_count)
        testing.expect(t, int(triangle.b) < mesh.vertex_count)
        testing.expect(t, int(triangle.c) < mesh.vertex_count)
    }
}

@(test)
simple_car_solid_mesh_is_nondegenerate_with_kei_proportions :: proc(t: ^testing.T) {
    mesh := vehicles.simple_car_mesh()
    for triangle in vehicles.mesh_triangles(&mesh) {
        a := mesh.vertices[triangle.a].position
        b := mesh.vertices[triangle.b].position
        c := mesh.vertices[triangle.c].position
        ab := b - a
        ac := c - a
        normal := [3]f32{ab[1] * ac[2] - ab[2] * ac[1], ab[2] * ac[0] - ab[0] * ac[2], ab[0] * ac[1] - ab[1] * ac[0]}
        area_squared := normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]
        testing.expect(t, area_squared > .0000001)
    }
    testing.expect(t, vehicles.CAR_WHEEL_TRACK_HALF >= .67)
    testing.expect(t, vehicles.CAR_WHEEL_TRACK_HALF <= .68)
    testing.expect(t, vehicles.CAR_WHEELBASE_HALF >= .95)
    testing.expect(t, vehicles.CAR_WHEEL_RADIUS >= .23)
    testing.expect(t, vehicles.CAR_WHEEL_RADIUS <= .24)
    testing.expect(t, vehicles.CAR_WHEEL_WIDTH < vehicles.CAR_WHEEL_RADIUS)
    testing.expect(t, vehicles.CAR_WHEEL_CENTER_Y == vehicles.CAR_WHEEL_RADIUS)
}

@(test)
car_spawns_in_entry_range_and_is_selected_before_the_postale :: proc(t: ^testing.T) {
    player_spawn := third_person.Vec3 {
        x = 20,
        y = 4.5,
        z = 30,
    }
    car := vehicles.default_vehicle(vehicles.car_spawn_near(player_spawn))
    car.interaction_radius = 3
    testing.expect(t, car.position.x == player_spawn.x)
    testing.expect(t, car.position.z > player_spawn.z)
    postale := vehicles.default_vehicle({x = player_spawn.x, y = player_spawn.y, z = player_spawn.z - 2.2})
    character := vehicles.Character {
        position = player_spawn,
    }
    selected, entered := vehicles.try_enter_nearest(&character, []^vehicles.Vehicle{&car, &postale})
    testing.expect(t, entered)
    testing.expect(t, selected == &car)
    testing.expect(t, character.vehicle == &car && car.driver == &character)
}
