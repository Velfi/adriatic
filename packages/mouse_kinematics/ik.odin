package mouse_kinematics

import "core:math"
import "core:math/linalg"

Vec3 :: [3]f32

fore_elbow_pole :: proc(forward: Vec3) -> Vec3 {
    return -forward
}

hind_knee_pole :: proc(forward: Vec3) -> Vec3 {
    return forward
}

hind_hock_pole :: proc(forward: Vec3) -> Vec3 {
    return -forward
}

stable_distal_span :: proc(
    root_target_distance, proximal_length, middle_length, distal_length: f32,
) -> f32 {
    distal_minimum := math.abs(middle_length - distal_length) + .0001
    distal_maximum := middle_length + distal_length - .0001
    triangle_minimum := math.abs(root_target_distance - proximal_length)
    triangle_maximum := root_target_distance + proximal_length
    lower := max(distal_minimum, triangle_minimum)
    upper := min(distal_maximum, triangle_maximum)
    // Keep the knee-to-paw span stable through ordinary stance and swing.
    // It only changes near the chain's reach limits where triangle geometry
    // requires it, avoiding a frame-dependent knee/hock accordion.
    preferred := (middle_length + distal_length) * .78
    return clamp(preferred, lower, max(lower, upper))
}

stable_pole :: proc(axis, anatomical_hint: Vec3) -> Vec3 {
    projection := linalg.dot(anatomical_hint, axis)
    pole := Vec3 {
        anatomical_hint.x - axis.x * projection,
        anatomical_hint.y - axis.y * projection,
        anatomical_hint.z - axis.z * projection,
    }
    if linalg.dot(pole, pole) <= .0001 {
        pole = linalg.cross(axis, Vec3{0, 1, 0})
        if linalg.dot(pole, pole) <= .0001 do pole = linalg.cross(axis, Vec3{1, 0, 0})
    }
    return linalg.normalize0(pole)
}

solve_two_bone :: proc(
    root, target, anatomical_pole: Vec3,
    root_length, tip_length: f32,
) -> Vec3 {
    delta := Vec3{target.x - root.x, target.y - root.y, target.z - root.z}
    distance := linalg.length(delta)
    axis: Vec3
    if distance <= .0001 {
        axis = {0, -1, 0}
        distance = math.abs(root_length - tip_length) + .0001
    } else {
        axis = delta / distance
    }
    solved_distance := clamp(
        distance,
        math.abs(root_length - tip_length) + .0001,
        root_length + tip_length - .0001,
    )
    along :=
        (solved_distance * solved_distance + root_length * root_length - tip_length * tip_length) /
        (2 * solved_distance)
    height := f32(math.sqrt(f64(max(root_length * root_length - along * along, f32(0)))))
    pole := stable_pole(axis, anatomical_pole)
    return root + axis * along + pole * height
}
