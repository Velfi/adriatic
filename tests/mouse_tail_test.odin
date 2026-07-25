package tests

import mouse_tail "../packages/mouse_tail"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:testing"

tail_distance :: proc(a, b: third_person.Vec3) -> f32 {
    dx, dy, dz := b.x - a.x, b.y - a.y, b.z - a.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
}

@(test)
mouse_tail_default_resolution_preserves_authored_length :: proc(t: ^testing.T) {
    config := mouse_tail.default_config()
    total_length := config.segment_length * f32(mouse_tail.POINT_COUNT - 1)
    testing.expect(t, math.abs(total_length - 2.04) < .0001)
    testing.expect(t, mouse_tail.POINT_COUNT >= 13)
}

@(test)
mouse_tail_keeps_its_segments_connected :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    state: mouse_tail.State
    config := mouse_tail.default_config()
    root := third_person.Vec3 {
        x = 0,
        y = 8,
        z = 0,
    }
    for _ in 0 ..< 90 {
        mouse_tail.step(&state, root, {z = 1}, project, config, 1.0 / 60.0)
    }
    for index in 0 ..< mouse_tail.POINT_COUNT - 1 {
        distance := tail_distance(state.points[index].position, state.points[index + 1].position)
        testing.expect(t, math.abs(distance - config.segment_length) < .012)
    }
}

@(test)
mouse_tail_collides_with_terrain :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    config := mouse_tail.default_config()
    root := third_person.Vec3 {
        x = 0,
        y = .5,
        z = 0,
    }
    state: mouse_tail.State
    mouse_tail.reset(&state, root, {z = 1}, config)
    for index in 1 ..< mouse_tail.POINT_COUNT {
        state.points[index].position.y = -10
        state.points[index].previous.y = -10
    }
    mouse_tail.step(&state, root, {z = 1}, project, config, 1.0 / 60.0)
    for index in 1 ..< mouse_tail.POINT_COUNT {
        point := state.points[index].position
        floor := terrain.sample_height(project, 0, point.x, point.z) + config.radius + mouse_tail.TERRAIN_CONTACT_SKIN
        testing.expect(t, point.y >= floor - .0001)
    }
}

@(test)
mouse_tail_rests_on_rendered_road_crown :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    from := roads.add_node(&project.road_graph, {-4, 0, 0})
    to := roads.add_node(&project.road_graph, {4, 0, 0})
    _ = roads.add_straight_edge(&project.road_graph, from, to, 2)
    config := mouse_tail.default_config()
    point := mouse_tail.Point {
        position = {x = 0, y = -1, z = 0},
        previous = {x = 0, y = -1, z = 0},
    }
    mouse_tail.resolve_terrain(&point, project, config.radius, config.surface_friction)
    terrain_height := terrain.sample_height(project, 0, 0, 0)
    testing.expect(
        t,
        point.position.y >= terrain_height + .12 + config.radius + mouse_tail.TERRAIN_CONTACT_SKIN - .0001,
    )
}

@(test)
mouse_tail_collides_with_solid_formations :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer free(project)
    terrain.init_project(project)
    structure := terrain.structure_make(0, 0, 2, 2, 0, 1)
    structure.kind = .Box
    _ = terrain.add_structure(project, structure)
    config := mouse_tail.default_config()
    root := third_person.Vec3 {
        x = 0,
        y = 1.5,
        z = -1.2,
    }
    state: mouse_tail.State
    mouse_tail.reset(&state, root, {z = 1}, config)
    for index in 1 ..< mouse_tail.POINT_COUNT {
        state.points[index].position = {
            x = 0,
            y = .5,
            z = 0,
        }
        state.points[index].previous = state.points[index].position
    }
    mouse_tail.step(&state, root, {z = 1}, project, config, 1.0 / 60.0)
    for index in 1 ..< mouse_tail.POINT_COUNT {
        point := state.points[index].position
        inside :=
            math.abs(point.x) < structure.width * .5 + config.radius &&
            math.abs(point.z) < structure.depth * .5 + config.radius &&
            point.y > structure.base_y - config.radius &&
            point.y < structure.base_y + structure.height + config.radius
        testing.expect(t, !inside)
    }
}
