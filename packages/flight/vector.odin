package flight

import "core:math"

Vec3 :: struct {
    x, y, z: f32,
}

vec3 :: proc(x, y, z: f32) -> Vec3 { return {x, y, z} }
add :: proc(a, b: Vec3) -> Vec3 { return {a.x + b.x, a.y + b.y, a.z + b.z} }
sub :: proc(a, b: Vec3) -> Vec3 { return {a.x - b.x, a.y - b.y, a.z - b.z} }
scale :: proc(v: Vec3, s: f32) -> Vec3 { return {v.x * s, v.y * s, v.z * s} }
dot :: proc(a, b: Vec3) -> f32 { return a.x * b.x + a.y * b.y + a.z * b.z }
cross :: proc(a, b: Vec3) -> Vec3 { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x} }
length :: proc(v: Vec3) -> f32 { return math.sqrt(dot(v, v)) }
normalize :: proc(v: Vec3) -> Vec3 { n := length(v); if n < 0.00001 do return {}; return scale(v, 1 / n) }
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
    f := normalize(b.forward)
    r := normalize(cross(f, b.up))
    return {forward = f, right = r, up = normalize(cross(r, f))}
}

local_to_world :: proc(b: Basis, local: Vec3) -> Vec3 {return add(
        add(scale(b.right, local.x), scale(b.up, local.y)),
        scale(b.forward, local.z),
    )}
world_to_local :: proc(b: Basis, world: Vec3) -> Vec3 {return{
        dot(world, b.right),
        dot(world, b.up),
        dot(world, b.forward),
    }}
