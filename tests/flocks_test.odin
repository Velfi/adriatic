package tests

import flocks "../packages/flocks"
import "core:math/linalg"
import "core:testing"

@(test)
flocks_spawn_for_each_anchor_and_stay_near_their_food_source :: proc(t: ^testing.T) {
    system: flocks.System
    anchors := [2]flocks.Anchor {
        {position = {0, 0, 0}, kind = .Harbor, seed = 7},
        {position = {100, 0, 40}, kind = .Fishing, seed = 11},
    }
    flocks.sync_anchors(&system, anchors[:])
    testing.expect_value(t, system.boid_count, 2 * flocks.BOIDS_PER_FLOCK)
    for _ in 0 ..< 240 do flocks.step(&system, 1.0 / 60.0, {2, -1})
    for boid in system.boids[:system.boid_count] {
        anchor := system.anchors[boid.flock]
        delta := boid.position - anchor.position
        testing.expect(t, linalg.dot(delta, delta) < 55 * 55)
        testing.expect(t, linalg.dot(boid.velocity, boid.velocity) > 1)
    }
}

@(test)
flocks_reseed_when_an_anchor_moves_to_a_different_site :: proc(t: ^testing.T) {
    system: flocks.System
    first := [1]flocks.Anchor{{position = {0, 0, 0}, kind = .Harbor, seed = 5}}
    flocks.sync_anchors(&system, first[:])
    original := system.boids[0].position
    moved := [1]flocks.Anchor{{position = {200, 0, 0}, kind = .Harbor, seed = 5}}
    flocks.sync_anchors(&system, moved[:])
    testing.expect(t, system.boids[0].position != original)
    testing.expect(t, system.boids[0].position.x > 180)
}

@(test)
ground_flocks_launch_for_an_active_nearby_threat :: proc(t: ^testing.T) {
    system := new(flocks.System)
    defer free(system)
    anchors := [1]flocks.Anchor{{position = {0, 2, 0}, kind = .Harbor, seed = 23}}
    flocks.sync_ground_anchors(system, anchors[:])
    testing.expect_value(t, system.boid_count, flocks.BOIDS_PER_FLOCK)

    for _ in 0 ..< 60 do flocks.step_grounded(system, 1.0 / 60.0, {}, {2, 2, 0}, false)
    for boid in system.boids[:system.boid_count] {
        testing.expect_value(t, boid.mode, flocks.Boid_Mode.Grounded)
        testing.expect(t, boid.position.y == boid.ground_y)
    }

    for _ in 0 ..< 90 do flocks.step_grounded(system, 1.0 / 60.0, {}, {2, 2, 0}, true)
    flying := 0
    for boid in system.boids[:system.boid_count] {
        if boid.mode == .Flying {
            flying += 1
            testing.expect(t, boid.position.y > boid.ground_y)
        }
    }
    testing.expect_value(t, flying, flocks.BOIDS_PER_FLOCK)
}

@(test)
ground_flocks_notice_threats_at_the_more_generous_scare_radius :: proc(t: ^testing.T) {
    system := new(flocks.System)
    defer free(system)
    anchors := [1]flocks.Anchor{{position = {0, 2, 0}, kind = .Harbor, seed = 29}}
    flocks.sync_ground_anchors(system, anchors[:])

    flocks.step_grounded(system, 1.0 / 60.0, {}, {15, 2, 0}, true)

    launching := 0
    for boid in system.boids[:system.boid_count] {
        if boid.mode == .Launching do launching += 1
    }
    testing.expect_value(t, launching, flocks.BOIDS_PER_FLOCK)
}

@(test)
patrol_marker_moves_and_the_flock_follows_it :: proc(t: ^testing.T) {
    system := new(flocks.System)
    defer free(system)
    anchors := [1]flocks.Anchor {
        {position = {0, 0, 0}, kind = .Harbor, movement = .Patrol, seed = 71, patrol_radius = 20, patrol_speed = 4},
    }
    flocks.sync_anchors(system, anchors[:])
    initial_marker := system.anchors[0].position
    initial_center: flocks.Vec3
    for boid in system.boids[:system.boid_count] do initial_center += boid.position
    initial_center /= f32(system.boid_count)

    for _ in 0 ..< 600 {
        flocks.step_markers(system, 1.0 / 60.0)
        flocks.step(system, 1.0 / 60.0, {})
    }

    marker_delta := system.anchors[0].position - initial_marker
    testing.expect(t, linalg.dot(marker_delta, marker_delta) > 5 * 5)
    center: flocks.Vec3
    for boid in system.boids[:system.boid_count] do center += boid.position
    center /= f32(system.boid_count)
    flock_delta := center - initial_center
    testing.expect(t, linalg.dot(flock_delta, flock_delta) > 2 * 2)
    marker_separation := center - system.anchors[0].position
    testing.expect(t, linalg.dot(marker_separation, marker_separation) < 35 * 35)
}
