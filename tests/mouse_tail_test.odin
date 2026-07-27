package tests

import mouse_tail "../packages/mouse_tail"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import "core:testing"

tail_distance :: proc(a, b: third_person.Vec3) -> f32 {
    return linalg.length(b - a)
}

@(test)
mouse_tail_default_resolution_preserves_authored_length :: proc(t: ^testing.T) {
    config := mouse_tail.default_config()
    total_length := config.segment_length * f32(mouse_tail.POINT_COUNT - 1)
    testing.expect(t, math.abs(total_length - 2.04) < .0001)
    testing.expect(t, mouse_tail.POINT_COUNT >= 13)
}

@(test)
mouse_tail_bend_rigidity_tapers_toward_tip :: proc(t: ^testing.T) {
    base := mouse_tail.bend_rigidity_profile(0)
    middle := mouse_tail.bend_rigidity_profile(.5)
    tip := mouse_tail.bend_rigidity_profile(1)
    testing.expect(t, base > middle)
    testing.expect(t, middle > tip)
    testing.expect(t, tip >= .08)
}

@(test)
mouse_tail_bend_stiffness_is_iteration_independent :: proc(t: ^testing.T) {
    requested := f32(.8)
    for iteration_count in 1 ..= 12 {
        per_iteration := mouse_tail.bend_iteration_stiffness(requested, iteration_count)
        remaining := f32(1)
        for _ in 0 ..< iteration_count do remaining *= 1 - per_iteration
        testing.expect(t, math.abs((1 - remaining) - requested) < .0001)
    }
}

@(test)
mouse_tail_keeps_its_segments_connected :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    state: mouse_tail.State
    config := mouse_tail.default_config()
    root := third_person.Vec3{0, 8, 0}
    for _ in 0 ..< 90 {
        mouse_tail.step(&state, root, {0, 0, 1}, project, config, 1.0 / 60.0)
    }
    for index in 0 ..< mouse_tail.POINT_COUNT - 1 {
        distance := tail_distance(state.points[index].position, state.points[index + 1].position)
        testing.expect(t, math.abs(distance - config.segment_length) < .012)
    }
}

@(test)
mouse_tail_collides_with_terrain :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    config := mouse_tail.default_config()
    root := third_person.Vec3{0, .5, 0}
    state: mouse_tail.State
    mouse_tail.reset(&state, root, {0, 0, 1}, config)
    for index in 1 ..< mouse_tail.POINT_COUNT {
        state.points[index].position.y = -10
        state.points[index].previous.y = -10
    }
    mouse_tail.step(&state, root, {0, 0, 1}, project, config, 1.0 / 60.0)
    for index in 1 ..< mouse_tail.POINT_COUNT {
        point := state.points[index].position
        floor := terrain.sample_height(project, 0, point.x, point.z) + config.radius + mouse_tail.TERRAIN_CONTACT_SKIN
        testing.expect(t, point.y >= floor - .0001)
    }
}

@(test)
mouse_tail_rests_on_rendered_road_crown :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    from := roads.add_node(&project.road_graph, {-4, 0, 0})
    to := roads.add_node(&project.road_graph, {4, 0, 0})
    _ = roads.add_straight_edge(&project.road_graph, from, to, 2)
    config := mouse_tail.default_config()
    point := mouse_tail.Point {
        position = {0, -1, 0},
        previous = {0, -1, 0},
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
    structure := terrain.structure_make(0, 0, 2, 2, 0, 1)
    structure.kind = .Box
    config := mouse_tail.default_config()
    half_width := structure.width * .5 + config.radius
    point := mouse_tail.Point {
        position = {half_width - .05, .5, 0},
        previous = {half_width - .05, .5, 0},
    }
    mouse_tail.resolve_structure(
        &point,
        structure,
        config.radius,
        config.surface_friction,
        config.segment_length,
    )
    inside :=
        math.abs(point.position.x) < half_width &&
        math.abs(point.position.z) < structure.depth * .5 + config.radius &&
        point.position.y > structure.base_y - config.radius &&
        point.position.y < structure.base_y + structure.height + config.radius
    testing.expect(t, !inside)
}

@(test)
mouse_tail_deep_structure_overlap_cannot_launch_a_segment_to_the_roof :: proc(t: ^testing.T) {
    solid_kinds := [7]terrain.Formation_Kind {
        .Box,
        .Rock,
        .Spire,
        .Mountain,
        .Ridge,
        .Cliff,
        .Architecture,
    }
    for kind in solid_kinds {
        project := new(terrain.Project)
        append(
            &project.structures,
            terrain.Structure {
                center_x = 0,
                center_z = 0,
                width    = 1000,
                depth    = 1000,
                base_y   = 0,
                height   = 100,
                kind     = kind,
            },
        )
        project.structure_count = 1

        config := mouse_tail.default_config()
        config.substeps = 1
        config.constraint_iterations = 1
        state: mouse_tail.State
        root := third_person.Vec3{0, .3, 0}
        mouse_tail.reset(&state, root, {0, 0, 1}, config)
        mouse_tail.step(&state, root, {0, 0, 1}, project, config, 1.0 / 60.0)

        for index in 0 ..< mouse_tail.POINT_COUNT - 1 {
            link_length := linalg.length(state.points[index + 1].position - state.points[index].position)
            testing.expectf(
                t,
                link_length <= config.segment_length * 2.01,
                "%v collision stretched link %d to %.3f m",
                kind,
                index,
                link_length,
            )
        }
        delete(project.structures)
        free(project)
    }
}
