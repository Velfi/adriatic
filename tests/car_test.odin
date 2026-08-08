package tests

import vehicles "../packages/vehicles"
import "core:math"
import "core:math/linalg"
import "core:testing"
import third_person "zelda_engine:third_person"

@(test)
simple_car_solid_mesh_is_closed_and_grouped :: proc(t: ^testing.T) {
    mesh := vehicles.simple_car_mesh()
    defer free(mesh)
    testing.expect(t, mesh.vertex_count > 0)
    testing.expect(t, mesh.triangle_count >= 100)
    testing.expect(t, mesh.vertex_count < mesh.triangle_count * 3)
    for triangle in vehicles.mesh_triangles(mesh) {
        testing.expect(t, int(triangle.a) < mesh.vertex_count)
        testing.expect(t, int(triangle.b) < mesh.vertex_count)
        testing.expect(t, int(triangle.c) < mesh.vertex_count)
    }
}

@(test)
simple_car_mesh_has_a_real_cockpit_opening :: proc(t: ^testing.T) {
    mesh := vehicles.simple_car_mesh()
    defer free(mesh)
    for vertex in vehicles.mesh_vertices(mesh) {
        // The central crown used to seal the cockpit beneath its dark tub.
        // Side rails remain outside this envelope, so any body-paint vertex
        // here means the opening has accidentally been closed again.
        in_opening :=
            vertex.part == .Body &&
            math.abs(vertex.position[0]) < .5 &&
            math.abs(vertex.position[2]) < .3 &&
            vertex.position[1] > .48
        testing.expect(t, !in_opening)
    }
}

@(test)
simple_car_solid_mesh_retains_period_detail_parts :: proc(t: ^testing.T) {
    mesh := vehicles.simple_car_mesh()
    defer free(mesh)
    headlight_count, tail_light_count, ivory_count := 0, 0, 0
    rounded_chrome_count, rounded_ivory_count := 0, 0
    left_tail_light_count, right_tail_light_count := 0, 0
    for vertex in vehicles.mesh_vertices(mesh) {
        #partial switch vertex.part {
        case .Headlight:
            headlight_count += 1
        case .Tail_Light:
            tail_light_count += 1
            if vertex.position[0] < 0 {
                left_tail_light_count += 1
            } else if vertex.position[0] > 0 {
                right_tail_light_count += 1
            }
        case .Ivory:
            ivory_count += 1
        case .Rounded_Chrome:
            rounded_chrome_count += 1
        case .Rounded_Ivory:
            rounded_ivory_count += 1
        }
    }
    testing.expect(t, headlight_count > 0)
    testing.expect(t, tail_light_count > 0)
    testing.expect(t, left_tail_light_count > 0)
    testing.expect(t, right_tail_light_count > 0)
    testing.expect(t, left_tail_light_count == right_tail_light_count)
    testing.expect(t, ivory_count > 0)
    testing.expect(t, rounded_chrome_count > 0)
    testing.expect(t, rounded_ivory_count > 0)
    testing.expect(t, mesh.vertex_count < len(mesh.vertices))
    testing.expect(t, mesh.triangle_count < len(mesh.triangles))
}

@(test)
simple_car_trailer_variants_are_optimized_and_indexed :: proc(t: ^testing.T) {
    variants := [3][3]bool{{false, false, false}, {false, true, false}, {true, false, true}}
    triangle_counts: [3]int
    mesh: ^vehicles.Aircraft_Mesh
    for variant, index in variants {
        mesh = vehicles.simple_car_trailer_mesh(variant[0], variant[1], variant[2])
        defer free(mesh)
        triangle_counts[index] = mesh.triangle_count
        testing.expect(t, mesh.vertex_count > 0)
        testing.expect(t, mesh.vertex_count < mesh.triangle_count * 3)
        for triangle in vehicles.mesh_triangles(mesh) {
            testing.expect(t, int(triangle.a) < mesh.vertex_count)
            testing.expect(t, int(triangle.b) < mesh.vertex_count)
            testing.expect(t, int(triangle.c) < mesh.vertex_count)
        }
    }
    testing.expect(t, triangle_counts[1] > triangle_counts[0])
    testing.expect(t, triangle_counts[2] > triangle_counts[0])
}

@(test)
simple_car_solid_mesh_is_nondegenerate_with_kei_proportions :: proc(t: ^testing.T) {
    mesh := vehicles.simple_car_mesh()
    defer free(mesh)
    for triangle in vehicles.mesh_triangles(mesh) {
        a := mesh.vertices[triangle.a].position
        b := mesh.vertices[triangle.b].position
        c := mesh.vertices[triangle.c].position
        ab := b - a
        ac := c - a
        normal := linalg.cross(ab, ac)
        area_squared := linalg.dot(normal, normal)
        // Dashboard gauges and switches intentionally use millimetric faces;
        // keep the guard below their valid area while still rejecting
        // collapsed triangles.
        testing.expect(t, area_squared > 1e-12)
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
    player_spawn := third_person.Vec3{20, 4.5, 30}
    car := vehicles.default_vehicle(vehicles.car_spawn_near(player_spawn))
    car.interaction_radius = 3
    testing.expect(t, car.position.x == player_spawn.x)
    testing.expect(t, car.position.z > player_spawn.z)
    postale := vehicles.default_vehicle({player_spawn.x, player_spawn.y, player_spawn.z - 2.2})
    character := vehicles.Character {
        position = player_spawn,
    }
    selected, entered := vehicles.try_enter_nearest(&character, []^vehicles.Vehicle{&car, &postale})
    testing.expect(t, entered)
    testing.expect(t, selected == &car)
    testing.expect(t, character.vehicle == &car && car.driver == &character)
}
