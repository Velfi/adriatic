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
