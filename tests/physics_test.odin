package tests

import "core:math"
import "core:testing"
import physics "zelda_engine:physics"

@(test)
physics_world_recreates_layered_bodies_and_queries :: proc(t: ^testing.T) {
    for _ in 0 ..< 3 {
        world := physics.create_world(128, 1)
        testing.expect(t, world != nil)
        if world == nil do return
        ground := physics.add_box_layered(world, {8, .5, 8}, {0, -.5, 0}, user_data = 0x55aa)
        testing.expect(t, ground != physics.INVALID_BODY)
        if ground == physics.INVALID_BODY do return
        testing.expect(t, physics.get_user_data(world, ground) == 0x55aa)
        hit, ok := physics.cast_ray(world, {0, 2, 0}, {0, -1, 0}, 4)
        testing.expect(t, ok)
        testing.expect(t, hit.body == ground)
        testing.expect(t, hit.normal.y > .999)
        physics.destroy_world(world)
    }
}

@(test)
physics_filtered_ray_returns_normals_and_excludes_layers :: proc(t: ^testing.T) {
    world := physics.create_world(128, 1)
    defer physics.destroy_world(world)
    ground := physics.add_box_layered(world, {4, .5, 4}, {0, -.5, 0}, layer = .Static_World)
    blocker := physics.add_box_layered(world, {.5, .25, .5}, {0, .25, 0}, layer = .Character)
    testing.expect(t, ground != physics.INVALID_BODY && blocker != physics.INVALID_BODY)
    static_mask := u16(1 << u16(physics.Object_Layer.Static_World))
    hit, ok := physics.cast_ray_filtered(world, {0, 2, 0}, {0, -1, 0}, 4, static_mask)
    testing.expect(t, ok && hit.body == ground)
    testing.expect(t, hit.normal.y > .999)
    _, miss := physics.cast_ray_filtered(world, {8, 2, 0}, {0, -1, 0}, 1, static_mask)
    testing.expect(t, !miss)
}

@(test)
physics_character_virtual_lands_and_reports_ground :: proc(t: ^testing.T) {
    world := physics.create_world(128, 1)
    defer physics.destroy_world(world)
    ground := physics.add_box_layered(world, {8, .5, 8}, {0, -.5, 0})
    testing.expect(t, ground != physics.INVALID_BODY)
    if ground == physics.INVALID_BODY do return
    character := physics.create_character(world, .18, .24, {0, 2, 0}, math.PI * .3)
    testing.expect(t, character != nil)
    if character == nil do return
    defer physics.destroy_character(world, character)
    velocity := physics.Vec3{0, 0, 0}
    state: physics.Character_State
    ok := false
    for _ in 0 ..< 240 {
        velocity.y -= 20.0 / 120.0
        state, ok = physics.step_character(world, character, velocity, 1.0 / 120.0, {0, -20, 0})
        testing.expect(t, ok)
        if !ok do return
        velocity = state.velocity
    }
    testing.expect(t, state.ground_state == .On_Ground)
    testing.expect(t, state.ground_body == ground)
    testing.expect(t, state.ground_normal.y > .9)
}

@(test)
physics_soft_strand_pins_root_and_keeps_finite_vertices :: proc(t: ^testing.T) {
    world := physics.create_world(128, 1)
    defer physics.destroy_world(world)
    points := [5]physics.Vec3{{0, 2, 0}, {0, 2, .2}, {0, 2, .4}, {0, 2, .6}, {0, 2, .8}}
    inverse_masses := [5]f32{0, 0, 1, 1, 1}
    strand := physics.add_soft_strand(world, points[:], inverse_masses[:], 0, .00002, 8, .15, 1, .02, .3)
    testing.expect(t, strand != physics.INVALID_BODY)
    if strand == physics.INVALID_BODY do return
    for _ in 0 ..< 60 {
        testing.expect(t, physics.set_soft_strand_attachment(world, strand, {0, 2, 0}, {0, 2, .2}, 1.0 / 120.0))
        physics.step(world, 1.0 / 120.0, 2)
    }
    output: [5]physics.Vec3
    testing.expect(t, physics.get_soft_strand_points(world, strand, output[:]))
    testing.expect(t, math.abs(output[0].x) < .001)
    testing.expect(t, math.abs(output[0].y - 2) < .01)
    testing.expect(t, math.abs(output[1].x) < .001)
    testing.expect(t, math.abs(output[1].z - .2) < .01)
    tail_offset := output[len(output) - 1] - output[0]
    testing.expect(t, math.abs(tail_offset.z) > math.abs(tail_offset.x) * 2)
    for point in output {
        testing.expect(t, point.x == point.x && point.y == point.y && point.z == point.z)
    }
}
