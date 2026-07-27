package architecture

import terrain "../terrain"
import "core:math"

// resolve_structure_circle keeps a world-space circle outside the rendered
// masses of an architecture structure.
resolve_structure_circle :: proc(structure: terrain.Structure, position: [2]f32, radius: f32) -> ([2]f32, bool) {
    if structure.kind != .Architecture || radius < 0 do return position, false

    result := position
    collided := false
    cosine := f32(math.cos(f64(structure.rotation)))
    sine := f32(math.sin(f64(structure.rotation)))
    footprint := architecture_footprint(structure)

    // Compound footprints can have overlapping masses. A few passes settle
    // the circle outside every mass while preserving open courts.
    for _ in 0 ..< 3 {
        changed := false
        for mass in footprint.masses[:footprint.count] {
            center_x, center_z := architecture_mass_world(structure, mass)
            delta_x, delta_z := result.x - center_x, result.y - center_z
            local_x := delta_x * cosine + delta_z * sine
            local_z := -delta_x * sine + delta_z * cosine
            half_x := mass.width * .5 + radius
            half_z := mass.depth * .5 + radius
            if math.abs(local_x) >= half_x || math.abs(local_z) >= half_z do continue

            distance_x := half_x - math.abs(local_x)
            distance_z := half_z - math.abs(local_z)
            if distance_x < distance_z {
                local_x = local_x < 0 ? -half_x : half_x
            } else {
                local_z = local_z < 0 ? -half_z : half_z
            }
            result = {center_x + local_x * cosine - local_z * sine, center_z + local_x * sine + local_z * cosine}
            changed, collided = true, true
        }
        if !changed do break
    }
    return result, collided
}

resolve_city_circle :: proc(plan: ^City_Plan, position: [2]f32, radius: f32) -> ([2]f32, bool) {
    if plan == nil || radius < 0 do return position, false
    result := position
    collided := false
    for structure in plan.structures[:plan.count] {
        corrected, hit := resolve_structure_circle(structure, result, radius)
        if hit {
            result = corrected
            collided = true
        }
    }
    return result, collided
}
