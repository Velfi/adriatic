package tests

import flight "../packages/flight"
import "core:math"
import "core:math/linalg"
import "core:testing"

orientation_expect_vec3_near :: proc(t: ^testing.T, actual, expected: flight.Vec3) {
    testing.expect(t, linalg.length(actual - expected) < 1e-5)
}

orientation_expect_basis_orthonormal :: proc(t: ^testing.T, basis: flight.Basis) {
    testing.expect(t, math.abs(linalg.length(basis.forward) - 1) < 1e-5)
    testing.expect(t, math.abs(linalg.length(basis.up) - 1) < 1e-5)
    testing.expect(t, math.abs(linalg.length(basis.right) - 1) < 1e-5)
    testing.expect(t, math.abs(linalg.dot(basis.forward, basis.up)) < 1e-5)
    testing.expect(t, math.abs(linalg.dot(basis.forward, basis.right)) < 1e-5)
    testing.expect(t, math.abs(linalg.dot(basis.up, basis.right)) < 1e-5)
    orientation_expect_vec3_near(t, linalg.cross(basis.forward, basis.up), basis.right)
}

@(test)
flight_orientation_identity_uses_canonical_axes :: proc(t: ^testing.T) {
    basis := flight.basis_from_orientation(flight.identity_orientation())
    orientation_expect_vec3_near(t, basis.forward, {0, 0, -1})
    orientation_expect_vec3_near(t, basis.up, {0, 1, 0})
    orientation_expect_vec3_near(t, basis.right, {1, 0, 0})
}

@(test)
flight_orientation_forward_up_round_trip :: proc(t: ^testing.T) {
    expected := flight.orthonormalize({forward = {-.8, .3, -.4}, up = {.2, .9, .1}})
    actual := flight.basis_from_orientation(flight.orientation_from_basis(expected))
    orientation_expect_vec3_near(t, actual.forward, expected.forward)
    orientation_expect_vec3_near(t, actual.up, expected.up)
    orientation_expect_vec3_near(t, actual.right, expected.right)
}

@(test)
flight_orientation_integrates_world_angular_velocity :: proc(t: ^testing.T) {
    orientation := flight.integrate_orientation(flight.identity_orientation(), {0, f32(math.PI / 2), 0}, 1)
    basis := flight.basis_from_orientation(orientation)
    orientation_expect_vec3_near(t, basis.forward, {-1, 0, 0})
    orientation_expect_vec3_near(t, basis.up, {0, 1, 0})
}

@(test)
flight_orientation_interpolation_stays_normalized :: proc(t: ^testing.T) {
    target := flight.orientation_from_forward_and_up({-1, 0, 0}, {0, 1, 0})
    halfway := flight.interpolate_orientation(flight.identity_orientation(), target, .5)
    testing.expect(t, math.abs(linalg.length(halfway) - 1) < 1e-5)
    basis := flight.basis_from_orientation(halfway)
    orientation_expect_vec3_near(t, basis.forward, linalg.normalize(flight.Vec3{-1, 0, -1}))
}

@(test)
flight_orientation_basis_stays_orthonormal_during_high_rate_rotation :: proc(t: ^testing.T) {
    orientation := flight.identity_orientation()
    for _ in 0 ..< 2000 {
        orientation = flight.integrate_orientation(orientation, {4, -7, 11}, 1.0 / 240)
    }
    orientation_expect_basis_orthonormal(t, flight.basis_from_orientation(orientation))
}

@(test)
flight_orientation_levels_without_changing_heading :: proc(t: ^testing.T) {
    orientation := flight.orientation_from_forward_and_up({-1, .75, -1}, {0, 1, 0})
    before := flight.basis_from_orientation(orientation)
    expected_forward := linalg.normalize(flight.Vec3{before.forward.x, 0, before.forward.z})
    leveled := flight.basis_from_orientation(flight.level_preserving_heading(orientation))
    orientation_expect_vec3_near(t, leveled.forward, expected_forward)
    orientation_expect_vec3_near(t, leveled.up, {0, 1, 0})
    orientation_expect_basis_orthonormal(t, leveled)
}

@(test)
flight_orientation_rotates_level_heading_about_world_up :: proc(t: ^testing.T) {
    rotated := flight.basis_from_orientation(
        flight.rotate_level_heading(flight.identity_orientation(), f32(math.PI / 2)),
    )
    orientation_expect_vec3_near(t, rotated.forward, {-1, 0, 0})
    orientation_expect_vec3_near(t, rotated.up, {0, 1, 0})
    orientation_expect_basis_orthonormal(t, rotated)
}
