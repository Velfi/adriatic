package main
import "core:math"

import flight "../packages/flight"
import mouse_gait "../packages/mouse_gait"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

player_animation_approach :: proc(current, target, rate, delta_seconds: f32) -> f32 {
    maximum_delta := max(rate, f32(.1)) * delta_seconds
    if current < target do return min(current + maximum_delta, target)
    return max(current - maximum_delta, target)
}

// A semi-implicit damped spring gives the sprint pose mass: acceleration tips
// the body forward and each bound loads the spine, then both settle without
// being tied directly to a canned animation curve.
player_animation_spring :: proc(value, velocity: ^f32, target, stiffness, damping, delta_seconds: f32) {
    if value == nil || velocity == nil || delta_seconds <= 0 do return
    acceleration := (target - value^) * max(stiffness, f32(1)) - velocity^ * max(damping, f32(0))
    velocity^ += acceleration * delta_seconds
    value^ += velocity^ * delta_seconds
}

mouse_gait_weights :: proc(
    animation: ^Player_Animation_Tweak,
    horizontal_speed, airborne_weight: f32,
) -> mouse_gait.Weights {
    if animation == nil do return {walk = 1}
    return mouse_gait.weights(
        horizontal_speed,
        animation.walk_full_speed,
        animation.trot_full_speed,
        animation.bound_start_speed,
        animation.bound_full_speed,
        airborne_weight,
    )
}

Mouse_Bone :: enum u8 {
    Pelvis,
    Spine,
    Chest,
    Neck,
    Head,
}

Mouse_Bone_Pose :: struct {
    parent:        i8,
    bind_position: third_person.Vec3,
    position:      third_person.Vec3,
    pitch:         f32,
    yaw:           f32,
    roll:          f32,
}
