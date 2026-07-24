package third_person

import "core:math"

// Vec3 uses a conventional right-handed game-space: Y is up and a yaw of zero
// faces down -Z. Collision remains the caller's responsibility; feed the
// collision result into Input.grounded each frame before calling step.
Vec3 :: struct {
    x, y, z: f32,
}

Input :: struct {
    move_x, move_y:     f32,
    jump_pressed:       bool,
    grounded:           bool,
    camera_yaw_radians: f32,
}

Config :: struct {
    move_speed:          f32,
    ground_acceleration: f32,
    air_acceleration:    f32,
    jump_speed:          f32,
    gravity:             f32,
}

State :: struct {
    position, velocity: Vec3,
    facing_yaw_radians: f32,
    grounded:           bool,
}

Camera :: struct {
    yaw_radians, pitch_radians: f32,
    distance, height:           f32,
}

Camera_Pose :: struct {
    position, target: Vec3,
}

default_config :: proc() -> Config {
    return {move_speed = 6, ground_acceleration = 36, air_acceleration = 10, jump_speed = 7, gravity = 20}
}

default_camera :: proc() -> Camera { return {pitch_radians = .35, distance = 5, height = 1.5} }

// look applies raw mouse/stick deltas to the orbit camera. Keeping the clamp
// here makes the controller safe to use from any presentation layer.
look :: proc(camera: ^Camera, yaw_delta, pitch_delta, sensitivity: f32) {
    if camera == nil do return
    camera.yaw_radians += yaw_delta * sensitivity
    camera.pitch_radians = clamp(camera.pitch_radians + pitch_delta * sensitivity, -.85, 1.2)
}

// step updates the controller's desired motion. Apply State.position and
// State.velocity to the product's kinematic or dynamic physics body afterward.
step :: proc(state: ^State, input: Input, config: Config, delta_seconds: f32) {
    if state == nil || delta_seconds <= 0 do return

    move_x := clamp(input.move_x, -1, 1)
    move_y := clamp(input.move_y, -1, 1)
    length_squared := move_x * move_x + move_y * move_y
    if length_squared > 1 {
        inverse_length := 1 / math.sqrt(length_squared)
        move_x *= inverse_length
        move_y *= inverse_length
    }

    // Rotate local stick/WASD input by the orbit camera's yaw.
    forward := Vec3{-math.sin(input.camera_yaw_radians), 0, -math.cos(input.camera_yaw_radians)}
    right := Vec3{math.cos(input.camera_yaw_radians), 0, -math.sin(input.camera_yaw_radians)}
    direction := Vec3{forward.x * move_y + right.x * move_x, 0, forward.z * move_y + right.z * move_x}
    state.velocity.x = approach(
        state.velocity.x,
        direction.x * config.move_speed,
        acceleration(input.grounded, config) * delta_seconds,
    )
    state.velocity.z = approach(
        state.velocity.z,
        direction.z * config.move_speed,
        acceleration(input.grounded, config) * delta_seconds,
    )

    if input.grounded {
        state.grounded = true
        if state.velocity.y < 0 do state.velocity.y = 0
        if input.jump_pressed {
            state.velocity.y = config.jump_speed
            state.grounded = false
        }
    } else {
        state.grounded = false
        state.velocity.y -= config.gravity * delta_seconds
    }

    if length_squared > .0001 do state.facing_yaw_radians = math.atan2(-direction.x, -direction.z)
    state.position = add(state.position, scale(state.velocity, delta_seconds))
}

// camera_pose returns an orbit-camera placement looking at the character's
// upper body. Clamp pitch while collecting look input to avoid a pole flip.
camera_pose :: proc(character_position: Vec3, camera: Camera) -> Camera_Pose {
    pitch := clamp(camera.pitch_radians, -.85, 1.2)
    horizontal_distance := camera.distance * math.cos(pitch)
    target := add(character_position, Vec3{y = camera.height})
    return {
        position = Vec3 {
            x = target.x + math.sin(camera.yaw_radians) * horizontal_distance,
            y = target.y + math.sin(pitch) * camera.distance,
            z = target.z + math.cos(camera.yaw_radians) * horizontal_distance,
        },
        target = target,
    }
}

// follow_camera eases an orbit camera toward the character without changing
// its look angles. It gives the familiar third-person follow feel while the
// caller remains free to run collision avoidance on the returned pose.
follow_camera :: proc(current: Camera_Pose, desired: Camera_Pose, sharpness, delta_seconds: f32) -> Camera_Pose {
    if delta_seconds <= 0 do return current
    t := clamp(sharpness * delta_seconds, 0, 1)
    return {position = lerp(current.position, desired.position, t), target = lerp(current.target, desired.target, t)}
}

acceleration :: proc(grounded: bool, config: Config) -> f32 {if grounded do return config.ground_acceleration
    return config.air_acceleration}
clamp :: proc(value, lower, upper: f32) -> f32 {if value < lower do return lower; if value > upper do return upper
    return value}
approach :: proc(current, target, maximum_delta: f32) -> f32 {if current < target do return min_f32(current + maximum_delta, target)
    return max_f32(current - maximum_delta, target)}
min_f32 :: proc(a, b: f32) -> f32 { if a < b do return a; return b }
max_f32 :: proc(a, b: f32) -> f32 { if a > b do return a; return b }
add :: proc(a, b: Vec3) -> Vec3 { return {a.x + b.x, a.y + b.y, a.z + b.z} }
scale :: proc(value: Vec3, amount: f32) -> Vec3 { return {value.x * amount, value.y * amount, value.z * amount} }
lerp :: proc(a, b: Vec3, t: f32) -> Vec3 { return add(a, scale(Vec3{b.x - a.x, b.y - a.y, b.z - a.z}, t)) }
