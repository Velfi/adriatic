package chase_camera

import flight "../flight"
import third_person "../third_person"
import "core:math"

FOLLOW_DISTANCE :: f32(6.5)
FOLLOW_HEIGHT :: f32(5.5)
LOOK_AHEAD :: f32(5)
FOCUS_HEIGHT :: f32(-5.5)

State :: struct {
    pose:                     third_person.Camera_Pose,
    base_pose:                third_person.Camera_Pose,
    orbit_yaw, orbit_pitch:   f32,
    focal_length:             f32,
    shake_phase:              f32,
    shake_intensity:          f32,
    previous_target_position: flight.Vec3,
    initialized:              bool,
}

Target :: struct {
    position:   flight.Vec3,
    basis:      flight.Basis,
    airspeed:   f32,
    roll_input: f32,
    grounded:   bool,
}

reset :: proc(state: ^State, target: Target) {
    if state == nil do return
    state.orbit_yaw = 0
    state.orbit_pitch = 0
    state.base_pose = desired_pose(target, 0, 0)
    state.pose = state.base_pose
    state.focal_length = focal_length_for_fov(desired_fov(target.airspeed))
    state.shake_phase = 0
    state.shake_intensity = 0
    state.previous_target_position = target.position
    state.initialized = true
}

look :: proc(state: ^State, mouse_x, mouse_y: f32) {
    if state == nil do return
    state.orbit_yaw = wrap_angle(state.orbit_yaw - mouse_x * .003)
    state.orbit_pitch = clamp(state.orbit_pitch - mouse_y * .0025, -.75, .75)
}

step :: proc(state: ^State, target: Target, delta_seconds: f32, flyby_shake: f32 = 0) {
    if state == nil do return
    desired := desired_pose(target, state.orbit_yaw, state.orbit_pitch)
    if !state.initialized || distance_squared(state.base_pose.position, desired.position) > 50 * 50 {
        state.base_pose = desired
        state.initialized = true
    } else {
        // Follow target translation exactly and smooth only the camera's local
        // offset. World-space smoothing makes a steadily moving aircraft drag
        // the camera through uneven frame deltas, which reads as judder.
        previous_target := to_third_person(state.previous_target_position)
        current_target := to_third_person(target.position)
        current_position_offset := vec_sub(state.base_pose.position, previous_target)
        desired_position_offset := vec_sub(desired.position, current_target)
        current_focus_offset := vec_sub(state.base_pose.target, previous_target)
        desired_focus_offset := vec_sub(desired.target, current_target)
        state.base_pose.position = third_person.add(
            current_target,
            lerp(current_position_offset, desired_position_offset, exp_response(8, delta_seconds)),
        )
        state.base_pose.target = third_person.add(
            current_target,
            lerp(current_focus_offset, desired_focus_offset, exp_response(10, delta_seconds)),
        )
    }
    state.previous_target_position = target.position
    state.focal_length = scalar_lerp(
        state.focal_length,
        focal_length_for_fov(desired_fov(target.airspeed)),
        exp_response(3.5, delta_seconds),
    )
    state.shake_intensity = scalar_lerp(
        state.shake_intensity,
        clamp(flyby_shake, 0, 1),
        exp_response(flyby_shake > state.shake_intensity ? f32(18) : f32(7), delta_seconds),
    )
    state.shake_phase = wrap_angle(state.shake_phase + delta_seconds * (16 + target.airspeed * .42))
    state.pose = shake_pose(state.base_pose, target, state.shake_phase, state.shake_intensity)
}

// Diagnostic/direct follow path: derive the rendered camera from exactly the
// same target pose as the aircraft, without retaining any temporal state.
snap :: proc(state: ^State, target: Target) {
    if state == nil do return
    state.base_pose = desired_pose(target, state.orbit_yaw, state.orbit_pitch)
    state.pose = state.base_pose
    state.focal_length = focal_length_for_fov(desired_fov(target.airspeed))
    state.shake_intensity = 0
    state.previous_target_position = target.position
    state.initialized = true
}

shake_pose :: proc(pose: third_person.Camera_Pose, target: Target, phase, intensity: f32) -> third_person.Camera_Pose {
    amount := clamp(intensity, 0, 1)
    if amount <= .001 do return pose
    amplitude := amount * amount * .34
    side := f32(math.sin(f64(phase * 1.73))) * amplitude
    lift := f32(math.sin(f64(phase * 2.41 + 1.2))) * amplitude * .62
    pulse := f32(math.sin(f64(phase * .79 + .4))) * amplitude * .18
    position_offset := flight.add(
        flight.add(flight.scale(target.basis.right, side), flight.scale(target.basis.up, lift)),
        flight.scale(target.basis.forward, pulse),
    )
    target_offset := flight.add(
        flight.scale(target.basis.right, side * .28),
        flight.scale(target.basis.up, lift * .22),
    )
    result := pose
    result.position = third_person.add(result.position, to_third_person(position_offset))
    result.target = third_person.add(result.target, to_third_person(target_offset))
    return result
}

// Measures clearance to an oriented structure volume. Product code decides
// which authored objects are large enough to produce a camera response.
box_flyby_strength :: proc(position, center, half_extent: flight.Vec3, rotation, response_range: f32) -> f32 {
    if response_range <= 0 do return 0
    dx, dz := position.x - center.x, position.z - center.z
    sine, cosine := f32(math.sin(f64(rotation))), f32(math.cos(f64(rotation)))
    local_x := dx * cosine + dz * sine
    local_z := -dx * sine + dz * cosine
    outside_x := max(math.abs(local_x) - max(half_extent.x, f32(0)), f32(0))
    outside_y := max(math.abs(position.y - center.y) - max(half_extent.y, f32(0)), f32(0))
    outside_z := max(math.abs(local_z) - max(half_extent.z, f32(0)), f32(0))
    clearance := f32(math.sqrt(f64(outside_x * outside_x + outside_y * outside_y + outside_z * outside_z)))
    normalized := clamp(1 - clearance / response_range, 0, 1)
    return smooth_step(normalized)
}

desired_pose :: proc(target: Target, orbit_yaw, orbit_pitch: f32) -> third_person.Camera_Pose {
    forward := horizontal_forward(target.basis)
    behind := rotate_y(flight.scale(forward, -1), orbit_yaw)
    framing_camera, framing_focus := vertical_framing(target.basis.forward.y)
    position := flight.add(
        flight.add(target.position, flight.scale(behind, FOLLOW_DISTANCE)),
        {y = FOLLOW_HEIGHT + framing_camera + orbit_pitch * 8},
    )
    right := target.basis.right
    right.y = 0
    right = flight.normalize(right)
    look_ahead := LOOK_AHEAD + clamp(target.airspeed / 18, 0, 4)
    focus := flight.add(
        flight.add(target.position, flight.scale(forward, look_ahead)),
        flight.add(
            flight.scale(right, clamp(-target.roll_input * 3.2, -3.2, 3.2)),
            {y = FOCUS_HEIGHT + framing_focus + (target.grounded ? -.35 : 0)},
        ),
    )
    return {position = to_third_person(position), target = to_third_person(focus)}
}

vertical_framing :: proc(forward_up: f32) -> (f32, f32) {
    pitch := clamp(forward_up, -1, 1)
    engagement := smooth_step(clamp((math.abs(pitch) - .2) / .65, 0, 1))
    signed := engagement * math.sign(pitch)
    return -signed * 8, signed * 4
}

desired_fov :: proc(airspeed: f32) -> f32 {
    return scalar_lerp(70, 80, clamp((airspeed - 8) / 62, 0, 1))
}

focal_length_for_fov :: proc(fov_degrees: f32) -> f32 {
    return 1 / f32(math.tan(f64(fov_degrees * math.PI / 360)))
}

horizontal_forward :: proc(basis: flight.Basis) -> flight.Vec3 {
    forward := basis.forward
    forward.y = 0
    if flight.length(forward) > .001 do return flight.normalize(forward)
    right := basis.right
    right.y = 0
    if flight.length(right) <= .001 do return {z = -1}
    right = flight.normalize(right)
    return {-right.z, 0, right.x}
}

rotate_y :: proc(value: flight.Vec3, radians: f32) -> flight.Vec3 {
    sine, cosine := f32(math.sin(radians)), f32(math.cos(radians))
    return {value.x * cosine + value.z * sine, value.y, -value.x * sine + value.z * cosine}
}

to_third_person :: proc(value: flight.Vec3) -> third_person.Vec3 {
    return {value.x, value.y, value.z}
}

distance_squared :: proc(a, b: third_person.Vec3) -> f32 {
    x, y, z := b.x - a.x, b.y - a.y, b.z - a.z
    return x * x + y * y + z * z
}

vec_sub :: proc(a, b: third_person.Vec3) -> third_person.Vec3 {
    return {a.x - b.x, a.y - b.y, a.z - b.z}
}

lerp :: proc(a, b: third_person.Vec3, amount: f32) -> third_person.Vec3 {
    return {scalar_lerp(a.x, b.x, amount), scalar_lerp(a.y, b.y, amount), scalar_lerp(a.z, b.z, amount)}
}

exp_response :: proc(response, delta_seconds: f32) -> f32 {
    return 1 - f32(math.exp(f64(-response * max(delta_seconds, 0))))
}

smooth_step :: proc(value: f32) -> f32 { return value * value * (3 - 2 * value) }
scalar_lerp :: proc(a, b, amount: f32) -> f32 { return a + (b - a) * amount }
clamp :: proc(value, lower, upper: f32) -> f32 { return min(max(value, lower), upper) }
wrap_angle :: proc(value: f32) -> f32 {
    two_pi := f32(2 * math.PI)
    result := value
    for result > math.PI do result -= two_pi
    for result < -math.PI do result += two_pi
    return result
}
