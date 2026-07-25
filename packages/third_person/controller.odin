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
    ground_normal:      Vec3,
}

Config :: struct {
    move_speed:          f32,
    ground_acceleration: f32,
    ground_deceleration: f32,
    reversal_braking:    f32,
    reversal_speed:      f32,
    facing_turn_speed:   f32,
    air_acceleration:    f32,
    jump_speed:          f32,
    gravity:             f32,
    slope_gravity_scale: f32,
    max_slope_acceleration: f32,
}

State :: struct {
    position, velocity: Vec3,
    facing_yaw_radians: f32,
    grounded:           bool,
    turn_amount:        f32,
    brake_amount:       f32,
    ground_normal:      Vec3,
}

Camera :: struct {
    yaw_radians, pitch_radians: f32,
    distance, height:           f32,
}

Camera_Pose :: struct {
    position, target: Vec3,
}

Camera_Slot :: enum u8 {
    Player,
    Inspection,
    Cutaway,
    Count,
}

Camera_System :: struct {
    poses:  [Camera_Slot.Count]Camera_Pose,
    active: Camera_Slot,
}

camera_system :: proc(player_pose: Camera_Pose) -> Camera_System {
    return {poses = {player_pose, player_pose, player_pose}, active = .Player}
}

camera_set_pose :: proc(system: ^Camera_System, slot: Camera_Slot, pose: Camera_Pose) {
    if system == nil || slot == .Count do return
    system.poses[slot] = pose
}

camera_set_active :: proc(system: ^Camera_System, slot: Camera_Slot) {
    if system == nil || slot == .Count do return
    system.active = slot
}

camera_active_pose :: proc(system: ^Camera_System) -> Camera_Pose {
    if system == nil do return {}
    return system.poses[system.active]
}

// camera_look_at creates a view from an explicit eye position and target.
// It is useful for authored viewpoints, inspection tools, and screenshots
// where an orbit camera's yaw/pitch are less expressive than world points.
camera_look_at :: proc(position, target: Vec3) -> Camera_Pose {
    return {position = position, target = target}
}

// camera_near places the camera at a caller-supplied offset from a thing and
// aims at that thing. The offset is world-space on purpose: callers can use
// authored positions for a runway, vehicle, NPC, or landmark without needing
// to know the camera's orbit conventions.
camera_near :: proc(target, offset: Vec3) -> Camera_Pose {
    return camera_look_at(add(target, offset), target)
}

default_config :: proc() -> Config {
    return {
        move_speed = 6,
        ground_acceleration = 20,
        ground_deceleration = 14,
        reversal_braking = 36,
        reversal_speed = 1.25,
        facing_turn_speed = 12,
        air_acceleration = 10,
        jump_speed = 7,
        gravity = 20,
        slope_gravity_scale = .35,
        max_slope_acceleration = 8,
    }
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
    move_amount := math.sqrt(length_squared)
    if length_squared > 1 {
        inverse_length := 1 / math.sqrt(length_squared)
        move_x *= inverse_length
        move_y *= inverse_length
        move_amount = 1
    }

    // Rotate local stick/WASD input by the orbit camera's yaw.
    forward := Vec3{-math.sin(input.camera_yaw_radians), 0, -math.cos(input.camera_yaw_radians)}
    right := Vec3{math.cos(input.camera_yaw_radians), 0, -math.sin(input.camera_yaw_radians)}
    direction := Vec3{forward.x * move_y + right.x * move_x, 0, forward.z * move_y + right.z * move_x}
    desired_direction := horizontal_normalize(direction)
    old_velocity := Vec3{x = state.velocity.x, z = state.velocity.z}
    old_speed := horizontal_length(old_velocity)
    old_direction := horizontal_normalize(old_velocity)
    state.ground_normal = valid_ground_normal(input.ground_normal)

    braking_target: f32
    if input.grounded {
        has_input := move_amount > .0001
        reversing := false
        if has_input && old_speed > max_f32(config.reversal_speed, .01) {
            reversing = horizontal_dot(old_direction, desired_direction) < -.5
        }

        if reversing {
            state.velocity = horizontal_move_towards(
                state.velocity,
                {},
                max_f32(config.reversal_braking, 0) * delta_seconds,
            )
            braking_target = 1
        } else if has_input {
            target_velocity := scale(desired_direction, max_f32(config.move_speed, 0) * move_amount)
            state.velocity = horizontal_move_towards(
                state.velocity,
                target_velocity,
                max_f32(config.ground_acceleration, 0) * delta_seconds,
            )
        } else {
            state.velocity = horizontal_move_towards(
                state.velocity,
                {},
                max_f32(config.ground_deceleration, 0) * delta_seconds,
            )
            if old_speed > .01 {
                braking_target = clamp(old_speed / max_f32(config.move_speed, f32(.1)), 0, 1)
            }
        }

        slope_acceleration := grounded_slope_acceleration(state.ground_normal, config)
        state.velocity.x += slope_acceleration.x * delta_seconds
        state.velocity.z += slope_acceleration.z * delta_seconds
        state.velocity = horizontal_limit(state.velocity, max_f32(config.move_speed, 0))
    } else {
        target_velocity := scale(desired_direction, max_f32(config.move_speed, 0) * move_amount)
        state.velocity = horizontal_move_towards(
            state.velocity,
            target_velocity,
            max_f32(config.air_acceleration, 0) * delta_seconds,
        )
    }

    new_horizontal_velocity := Vec3{x = state.velocity.x, z = state.velocity.z}
    new_speed := horizontal_length(new_horizontal_velocity)
    acceleration_delta := scale(
        Vec3{x = new_horizontal_velocity.x - old_velocity.x, z = new_horizontal_velocity.z - old_velocity.z},
        1 / delta_seconds,
    )
    turn_target: f32
    if input.grounded && old_speed > .1 {
        motion_right := Vec3{x = -old_direction.z, z = old_direction.x}
        turn_target = clamp(
            horizontal_dot(acceleration_delta, motion_right) /
                max_f32(config.ground_acceleration, f32(.1)),
            -1,
            1,
        )
    }
    signal_rate := f32(10) * delta_seconds
    state.turn_amount = approach(state.turn_amount, turn_target, signal_rate)
    state.brake_amount = approach(state.brake_amount, braking_target, signal_rate)

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

    facing_direction: Vec3
    if new_speed > max_f32(config.reversal_speed, .01) {
        facing_direction = horizontal_normalize(new_horizontal_velocity)
    } else if move_amount > .0001 {
        facing_direction = desired_direction
    }
    if horizontal_length(facing_direction) > .0001 {
        target_yaw := math.atan2(-facing_direction.x, -facing_direction.z)
        state.facing_yaw_radians = angle_move_towards(
            state.facing_yaw_radians,
            target_yaw,
            max_f32(config.facing_turn_speed, 0) * delta_seconds,
        )
    }
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

clamp :: proc(value, lower, upper: f32) -> f32 {if value < lower do return lower; if value > upper do return upper
    return value}
approach :: proc(current, target, maximum_delta: f32) -> f32 {if current < target do return min_f32(current + maximum_delta, target)
    return max_f32(current - maximum_delta, target)}
horizontal_length :: proc(value: Vec3) -> f32 {
    return math.sqrt(value.x * value.x + value.z * value.z)
}
horizontal_dot :: proc(a, b: Vec3) -> f32 { return a.x * b.x + a.z * b.z }
horizontal_normalize :: proc(value: Vec3) -> Vec3 {
    length := horizontal_length(value)
    if length <= .0001 do return {}
    return {x = value.x / length, z = value.z / length}
}
horizontal_move_towards :: proc(current, target: Vec3, maximum_delta: f32) -> Vec3 {
    delta := Vec3{x = target.x - current.x, z = target.z - current.z}
    distance := horizontal_length(delta)
    if distance <= maximum_delta || distance <= .0001 {
        return {x = target.x, y = current.y, z = target.z}
    }
    amount := maximum_delta / distance
    return {
        x = current.x + delta.x * amount,
        y = current.y,
        z = current.z + delta.z * amount,
    }
}
horizontal_limit :: proc(value: Vec3, maximum: f32) -> Vec3 {
    speed := horizontal_length(value)
    if speed <= maximum || speed <= .0001 do return value
    amount := maximum / speed
    return {x = value.x * amount, y = value.y, z = value.z * amount}
}
valid_ground_normal :: proc(value: Vec3) -> Vec3 {
    length_squared := value.x * value.x + value.y * value.y + value.z * value.z
    if length_squared <= .0001 || value.y <= .1 do return {y = 1}
    inverse_length := 1 / math.sqrt(length_squared)
    result := scale(value, inverse_length)
    if result.y <= .1 do return {y = 1}
    return result
}
grounded_slope_acceleration :: proc(normal: Vec3, config: Config) -> Vec3 {
    amount := max_f32(config.gravity, 0) * max_f32(config.slope_gravity_scale, 0) * normal.y
    result := Vec3{x = normal.x * amount, z = normal.z * amount}
    return horizontal_limit(result, max_f32(config.max_slope_acceleration, 0))
}
angle_move_towards :: proc(current, target, maximum_delta: f32) -> f32 {
    difference := target - current
    for difference > math.PI do difference -= math.PI * 2
    for difference < -math.PI do difference += math.PI * 2
    if math.abs(difference) <= maximum_delta do return target
    if difference > 0 do return current + maximum_delta
    return current - maximum_delta
}
min_f32 :: proc(a, b: f32) -> f32 { if a < b do return a; return b }
max_f32 :: proc(a, b: f32) -> f32 { if a > b do return a; return b }
add :: proc(a, b: Vec3) -> Vec3 { return {a.x + b.x, a.y + b.y, a.z + b.z} }
scale :: proc(value: Vec3, amount: f32) -> Vec3 { return {value.x * amount, value.y * amount, value.z * amount} }
lerp :: proc(a, b: Vec3, t: f32) -> Vec3 { return add(a, scale(Vec3{b.x - a.x, b.y - a.y, b.z - a.z}, t)) }
