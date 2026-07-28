package tests

import architecture "../packages/architecture"
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
mouse_tail_applies_physics_config_changes_without_resetting :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    weightless_state, gravity_state: mouse_tail.State
    weightless := mouse_tail.default_config()
    weightless.gravity = 0
    with_gravity := weightless
    with_gravity.gravity = 15
    root := third_person.Vec3{0, 8, 0}
    mouse_tail.reset(&weightless_state, root, {0, 0, 1}, weightless)
    gravity_state = weightless_state
    mouse_tail.step(&weightless_state, root, {0, 0, 1}, project, weightless, 1.0 / 30.0)
    mouse_tail.step(&gravity_state, root, {0, 0, 1}, project, with_gravity, 1.0 / 30.0)

    tip := mouse_tail.POINT_COUNT - 1
    testing.expect(t, weightless_state.initialized && gravity_state.initialized)
    testing.expect(t, gravity_state.points[tip].position.y < weightless_state.points[tip].position.y)
}

@(test)
mouse_tail_root_stiffness_controls_attachment_heading_response :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    root := third_person.Vec3{0, 8, 0}

    loose_state: mouse_tail.State
    loose := mouse_tail.default_config()
    loose.root_stiffness = 0
    mouse_tail.step(&loose_state, root, {0, 0, 1}, project, loose, 0)
    mouse_tail.step(&loose_state, root, {1, 0, 0}, project, loose, 1.0 / 60.0)
    loose_direction := loose_state.points[1].position - root
    testing.expect(t, loose_direction.z > 0)
    testing.expect(t, math.abs(loose_direction.z) > math.abs(loose_direction.x))

    stiff_state: mouse_tail.State
    stiff := mouse_tail.default_config()
    stiff.root_stiffness = 1
    mouse_tail.step(&stiff_state, root, {0, 0, 1}, project, stiff, 0)
    mouse_tail.step(&stiff_state, root, {1, 0, 0}, project, stiff, 1.0 / 60.0)
    stiff_direction := stiff_state.points[1].position - root
    testing.expect(t, stiff_direction.x > 0)
    testing.expect(t, math.abs(stiff_direction.x) > math.abs(stiff_direction.z))
}

@(test)
mouse_tail_player_motion_settles_into_one_trailing_curve :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    state: mouse_tail.State
    config := mouse_tail.default_config()
    root := third_person.Vec3{0, 8, 0}
    mouse_tail.reset(&state, root, {0, 0, 1}, config)

    // Sustained lateral player motion used to excite alternating bends down
    // the Verlet chain. A regular mouse tail may bow once as it trails, but
    // should not reverse curvature repeatedly into a visible S-wave.
    for _ in 0 ..< 45 {
        root.x += .07
        mouse_tail.step(&state, root, {0, 0, 1}, project, config, 1.0 / 60.0)
    }
    previous_sign := i32(0)
    reversals := 0
    for index in 1 ..< mouse_tail.POINT_COUNT - 1 {
        before := state.points[index].position.x - state.points[index - 1].position.x
        after := state.points[index + 1].position.x - state.points[index].position.x
        curvature := after - before
        sign := curvature > .0005 ? i32(1) : curvature < -.0005 ? i32(-1) : i32(0)
        if sign != 0 {
            if previous_sign != 0 && sign != previous_sign do reversals += 1
            previous_sign = sign
        }
    }
    testing.expectf(t, reversals <= 1, "tail formed an S-wave with %d curvature reversals", reversals)
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
mouse_tail_generated_town_surface_does_not_ratchet_upward :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    centers := [4]third_person.Vec3{{-12, 0, -12}, {12, 0, -12}, {-12, 0, 12}, {12, 0, 12}}
    for center in centers {
        structure := terrain.structure_make(center.x, center.z, 8, 8, 0, 8)
        structure.kind = .Architecture
        append(&project.structures, structure)
        project.structure_count += 1
    }

    config := mouse_tail.default_config()
    point := mouse_tail.Point {
        position = {0, 1, 0},
        previous = {0, 1, 0},
    }
    initial_y := point.position.y
    for _ in 0 ..< 64 {
        mouse_tail.resolve_terrain(&point, project, config.radius, config.surface_friction)
    }
    testing.expectf(
        t,
        math.abs(point.position.y - initial_y) < .0001,
        "generated surface ratcheted tail point from %.3f to %.3f",
        initial_y,
        point.position.y,
    )
}

@(test)
mouse_tail_step_accepts_one_prebuilt_town_circulation_plan :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    for z in -1 ..= 1 {
        for x in -1 ..= 1 {
            structure := terrain.structure_make(f32(x * 14), f32(z * 14), 8, 8, 0, 8)
            structure.kind = .Architecture
            append(&project.structures, structure)
            project.structure_count += 1
        }
    }
    plan := architecture.circulation_plan(project)
    config := mouse_tail.default_config()
    state: mouse_tail.State
    root := third_person.Vec3{0, 1, 0}
    for _ in 0 ..< 8 {
        mouse_tail.step(&state, root, {0, 0, 1}, project, config, 1.0 / 60.0, &plan)
    }
    for point in state.points {
        testing.expect(t, math.abs(point.position.x) < 1e6)
        testing.expect(t, math.abs(point.position.y) < 1e6)
        testing.expect(t, math.abs(point.position.z) < 1e6)
    }
}

@(test)
mouse_tail_recovers_from_a_previously_launched_chain :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    config := mouse_tail.default_config()
    root := third_person.Vec3{0, 1, 0}
    state: mouse_tail.State
    mouse_tail.reset(&state, root, {0, 0, 1}, config)

    // Match the visible failure: an earlier collision frame left one part of
    // the simulated chain many metres above the player.
    state.points[6].position.y = 100
    state.points[6].previous.y = 100
    mouse_tail.step(&state, root, {0, 0, 1}, project, config, 1.0 / 60.0)

    testing.expect(t, !mouse_tail.state_is_stretched(&state, root, config))
    for index in 0 ..< mouse_tail.POINT_COUNT - 1 {
        distance := tail_distance(state.points[index].position, state.points[index + 1].position)
        testing.expectf(
            t,
            distance <= config.segment_length * 1.1,
            "recovered link %d remains stretched to %.3f m",
            index,
            distance,
        )
    }
}

@(test)
mouse_tail_rejects_a_non_finite_root_without_poisoning_the_chain :: proc(t: ^testing.T) {
    project := new(terrain.Project)
    defer terrain.free_project(project)
    terrain.init_project(project)
    config := mouse_tail.default_config()
    state: mouse_tail.State
    valid_root := third_person.Vec3{0, 1, 0}
    mouse_tail.reset(&state, valid_root, {0, 0, 1}, config)
    original := state.points

    invalid_root := valid_root
    negative := f64(-1)
    invalid_root.y = f32(math.sqrt(negative))
    mouse_tail.step(&state, invalid_root, {0, 0, 1}, project, config, 1.0 / 60.0)

    testing.expect(t, !state.initialized)
    for point, index in state.points {
        testing.expect(t, point.position == original[index].position)
        testing.expect(t, point.previous == original[index].previous)
    }
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
    mouse_tail.resolve_structure(&point, structure, config.radius, config.surface_friction, config.segment_length)
    inside :=
        math.abs(point.position.x) < half_width &&
        math.abs(point.position.z) < structure.depth * .5 + config.radius &&
        point.position.y > structure.base_y - config.radius &&
        point.position.y < structure.base_y + structure.height + config.radius
    testing.expect(t, !inside)
}

@(test)
mouse_tail_deep_structure_overlap_cannot_launch_a_segment_to_the_roof :: proc(t: ^testing.T) {
    solid_kinds := [7]terrain.Formation_Kind{.Box, .Rock, .Spire, .Mountain, .Ridge, .Cliff, .Architecture}
    for kind in solid_kinds {
        project := new(terrain.Project)
        append(
            &project.structures,
            terrain.Structure {
                center_x = 0,
                center_z = 0,
                width = 1000,
                depth = 1000,
                base_y = 0,
                height = 100,
                kind = kind,
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
