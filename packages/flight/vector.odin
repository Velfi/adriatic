package flight

import "core:math"
import "core:math/linalg"

Vec3 :: [3]f32

clamp :: proc(value, low, high: f32) -> f32 {if value < low do return low; if value > high do return high
    return value}
lerp :: proc(a, b, t: f32) -> f32 { return a + (b - a) * clamp(t, 0, 1) }
sign :: proc(value: f32) -> f32 { if value < 0 do return -1; if value > 0 do return 1; return 0 }
degrees :: proc(radians: f32) -> f32 { return radians * 57.2957795 }

Basis :: struct {
    forward, up, right: Vec3,
}

identity_basis :: proc() -> Basis { return {forward = {0, 0, -1}, up = {0, 1, 0}, right = {1, 0, 0}} }
identity_orientation :: proc() -> quaternion128 { return linalg.QUATERNIONF32_IDENTITY }

normalize_orientation :: proc(orientation: quaternion128) -> quaternion128 {
    if !(linalg.dot(orientation, orientation) > 1e-8) do return identity_orientation()
    return linalg.normalize(orientation)
}

basis_from_orientation :: proc(orientation: quaternion128) -> Basis {
    normalized := normalize_orientation(orientation)
    return {
        forward = linalg.mul(normalized, Vec3{0, 0, -1}),
        up = linalg.mul(normalized, Vec3{0, 1, 0}),
        right = linalg.mul(normalized, Vec3{1, 0, 0}),
    }
}

orientation_from_basis :: proc(basis: Basis) -> quaternion128 {
    if !(linalg.dot(basis.forward, basis.forward) > 1e-8) do return identity_orientation()
    side := linalg.cross(basis.forward, basis.up)
    if !(linalg.dot(side, side) > 1e-8) do return identity_orientation()
    normalized := orthonormalize(basis)
    return linalg.quaternion_from_forward_and_up(normalized.forward, normalized.up)
}

orientation_from_forward_and_up :: proc(forward, up: Vec3) -> quaternion128 {
    return orientation_from_basis({forward = forward, up = up})
}

level_preserving_heading :: proc(orientation: quaternion128) -> quaternion128 {
    basis := basis_from_orientation(orientation)
    world_up := Vec3{0, 1, 0}
    forward := Vec3{basis.forward.x, 0, basis.forward.z}
    if !(linalg.dot(forward, forward) > 1e-8) {
        right := Vec3{basis.right.x, 0, basis.right.z}
        if !(linalg.dot(right, right) > 1e-8) do return identity_orientation()
        forward = linalg.cross(world_up, right)
    }
    return orientation_from_forward_and_up(forward, world_up)
}

rotate_level_heading :: proc(orientation: quaternion128, radians: f32) -> quaternion128 {
    leveled := level_preserving_heading(orientation)
    if radians == 0 do return leveled
    delta := linalg.quaternion_angle_axis(radians, Vec3{0, 1, 0})
    return normalize_orientation(delta * leveled)
}

integrate_orientation :: proc(
    orientation: quaternion128,
    angular_velocity_world: Vec3,
    delta_seconds: f32,
) -> quaternion128 {
    if delta_seconds <= 0 do return normalize_orientation(orientation)
    speed := linalg.length(angular_velocity_world)
    if !(speed > 1e-8) do return normalize_orientation(orientation)
    delta := linalg.quaternion_angle_axis(speed * delta_seconds, angular_velocity_world / speed)
    return normalize_orientation(delta * orientation)
}

interpolate_orientation :: proc(a, b: quaternion128, alpha: f32) -> quaternion128 {
    return normalize_orientation(
        linalg.quaternion_slerp(normalize_orientation(a), normalize_orientation(b), clamp(alpha, 0, 1)),
    )
}

orthonormalize :: proc(b: Basis) -> Basis {
    f := linalg.normalize0(b.forward)
    r := linalg.normalize0(linalg.cross(f, b.up))
    return {forward = f, right = r, up = linalg.normalize0(linalg.cross(r, f))}
}

local_to_world :: proc(b: Basis, local: Vec3) -> Vec3 {
    return b.right * local.x + b.up * local.y + b.forward * local.z
}

world_to_local :: proc(b: Basis, world: Vec3) -> Vec3 {
    return {linalg.dot(world, b.right), linalg.dot(world, b.up), linalg.dot(world, b.forward)}
}
