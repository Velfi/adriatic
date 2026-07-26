package mouse_tail

import roads "../roads"
import terrain "../terrain"
import third_person "../third_person"
import "core:math"

// Thirteen shorter links preserve the original 2.04 m authored length while
// giving the rendered centerline enough resolution to form a smooth curve.
POINT_COUNT :: 13
TERRAIN_CONTACT_SKIN :: f32(.006)

Point :: struct {
    position: third_person.Vec3,
    previous: third_person.Vec3,
}

State :: struct {
    points:      [POINT_COUNT]Point,
    last_root:   third_person.Vec3,
    initialized: bool,
}

Config :: struct {
    segment_length:        f32,
    radius:                f32,
    gravity:               f32,
    damping:               f32,
    constraint_iterations: int,
    substeps:              int,
    root_stiffness:        f32,
    root_damping:          f32,
    bend_stiffness:        f32,
    surface_friction:      f32,
}

default_config :: proc() -> Config {
    return {
        segment_length = .17,
        radius = .026,
        gravity = 12,
        damping = .965,
        constraint_iterations = 8,
        substeps = 3,
        root_stiffness = .42,
        root_damping = .72,
        bend_stiffness = .18,
        surface_friction = .22,
    }
}

add :: proc(a, b: third_person.Vec3) -> third_person.Vec3 {
    return {a.x + b.x, a.y + b.y, a.z + b.z}
}

subtract :: proc(a, b: third_person.Vec3) -> third_person.Vec3 {
    return {a.x - b.x, a.y - b.y, a.z - b.z}
}

scale :: proc(value: third_person.Vec3, amount: f32) -> third_person.Vec3 {
    return {value.x * amount, value.y * amount, value.z * amount}
}

length_squared :: proc(value: third_person.Vec3) -> f32 {
    return value.x * value.x + value.y * value.y + value.z * value.z
}

normalize_or :: proc(value, fallback: third_person.Vec3) -> third_person.Vec3 {
    squared := length_squared(value)
    if squared <= .000001 do return fallback
    inverse := 1 / f32(math.sqrt(f64(squared)))
    return scale(value, inverse)
}

reset :: proc(state: ^State, root, backward: third_person.Vec3, config: Config) {
    if state == nil do return
    direction := normalize_or({backward.x, -.22, backward.z}, {z = 1})
    side := third_person.Vec3 {
        x = direction.z,
        z = -direction.x,
    }
    segment_length := max(config.segment_length, f32(.02))
    for index in 0 ..< POINT_COUNT {
        distance := f32(index) * segment_length
        weight := f32(index) / f32(POINT_COUNT - 1)
        authored_length := segment_length * f32(POINT_COUNT - 1)
        curl := math.sin(weight * 3.36) * authored_length * .04 * weight
        position := add(add(root, scale(direction, distance)), scale(side, curl))
        state.points[index] = {
            position = position,
            previous = position,
        }
    }
    state.last_root = root
    state.initialized = true
}

constrain_distance :: proc(a, b: ^Point, target, a_weight, b_weight: f32) {
    delta := subtract(b.position, a.position)
    distance_squared := length_squared(delta)
    if distance_squared <= .0000001 do return
    distance := f32(math.sqrt(f64(distance_squared)))
    correction := scale(delta, (distance - target) / distance)
    weight_sum := a_weight + b_weight
    if weight_sum <= 0 do return
    a.position = add(a.position, scale(correction, a_weight / weight_sum))
    b.position = subtract(b.position, scale(correction, b_weight / weight_sum))
}

constrain_bend :: proc(a, b: ^Point, target, stiffness: f32, a_fixed: bool) {
    delta := subtract(b.position, a.position)
    distance_squared := length_squared(delta)
    if distance_squared <= .0000001 do return
    distance := f32(math.sqrt(f64(distance_squared)))
    correction := scale(delta, (distance - target) / distance * clamp(stiffness, 0, 1))
    if a_fixed {
        b.position = subtract(b.position, correction)
    } else {
        a.position = add(a.position, scale(correction, .5))
        b.position = subtract(b.position, scale(correction, .5))
    }
}

resolve_terrain :: proc(point: ^Point, project: ^terrain.Project, radius, friction: f32) {
    surface_height := terrain.sample_height(project, 0, point.position.x, point.position.z)
    pavement := roads.pavement_at(
        &project.road_graph,
        {x = point.position.x, y = point.position.y, z = point.position.z},
    )
    // Rendered road crowns sit 12 cm above the terrain heightfield. Treat that
    // presentation lift as physical support so a grounded tail rests on the
    // pavement instead of disappearing beneath it.
    if pavement.on_surface do surface_height = max(surface_height + .12, pavement.height + .12)
    // Keep a small separation beyond the rendered radius. Exact tangency is
    // vulnerable to raster/depth precision and makes the underside of the
    // tail intermittently disappear into the terrain or road crown.
    floor := surface_height + radius + TERRAIN_CONTACT_SKIN
    if point.position.y >= floor do return
    point.position.y = floor
    friction_amount := clamp(friction, 0, 1)
    point.previous.x += (point.position.x - point.previous.x) * friction_amount
    point.previous.z += (point.position.z - point.previous.z) * friction_amount
    if point.previous.y < point.position.y do point.previous.y = point.position.y
}

formation_is_solid :: proc(kind: terrain.Formation_Kind) -> bool {
    switch kind {
    case .Foliage:
        return false
    case .Box, .Rock, .Spire, .Mountain, .Ridge, .Cliff, .Architecture:
        return true
    }
    return false
}

resolve_structure :: proc(point: ^Point, structure: terrain.Structure, radius, friction: f32) {
    if !formation_is_solid(structure.kind) do return
    cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
    dx, dz := point.position.x - structure.center_x, point.position.z - structure.center_z
    local_x := dx * cosine + dz * sine
    local_z := -dx * sine + dz * cosine
    half_width := max(structure.width * .5, f32(0)) + radius
    half_depth := max(structure.depth * .5, f32(0)) + radius
    bottom := structure.base_y - radius
    top := structure.base_y + max(structure.height, f32(0)) + radius
    if math.abs(local_x) >= half_width ||
       math.abs(local_z) >= half_depth ||
       point.position.y <= bottom ||
       point.position.y >= top {
        return
    }

    penetration_x := half_width - math.abs(local_x)
    penetration_z := half_depth - math.abs(local_z)
    penetration_top := top - point.position.y
    if penetration_top <= penetration_x && penetration_top <= penetration_z {
        point.position.y = top
        if point.previous.y < point.position.y do point.previous.y = point.position.y
        point.previous.x += (point.position.x - point.previous.x) * clamp(friction, 0, 1)
        point.previous.z += (point.position.z - point.previous.z) * clamp(friction, 0, 1)
        return
    }
    if penetration_x <= penetration_z {
        local_x = local_x < 0 ? -half_width : half_width
    } else {
        local_z = local_z < 0 ? -half_depth : half_depth
    }
    point.position.x = structure.center_x + local_x * cosine - local_z * sine
    point.position.z = structure.center_z + local_x * sine + local_z * cosine
}

resolve_world :: proc(point: ^Point, project: ^terrain.Project, config: Config) {
    radius := max(config.radius, f32(0))
    resolve_terrain(point, project, radius, config.surface_friction)
    for index in 0 ..< project.structure_count {
        resolve_structure(point, project.structures[index], radius, config.surface_friction)
    }
    // A side projection can put a point over a different patch of terrain.
    resolve_terrain(point, project, radius, config.surface_friction)
}

step :: proc(
    state: ^State,
    root, backward: third_person.Vec3,
    project: ^terrain.Project,
    config: Config,
    delta_seconds: f32,
) {
    if state == nil || project == nil do return
    if !state.initialized || length_squared(subtract(root, state.last_root)) > 4 {
        reset(state, root, backward, config)
    }
    if delta_seconds <= 0 {
        state.points[0] = {
            position = root,
            previous = root,
        }
        state.last_root = root
        return
    }

    substeps := clamp(config.substeps, 1, 8)
    iterations := clamp(config.constraint_iterations, 1, 16)
    dt := min(delta_seconds, f32(.05)) / f32(substeps)
    dt_squared := dt * dt
    damping := clamp(config.damping, 0, 1)
    segment_length := max(config.segment_length, f32(.02))
    backward_direction := normalize_or({backward.x, 0, backward.z}, {z = 1})

    for _ in 0 ..< substeps {
        state.points[0] = {
            position = root,
            previous = root,
        }
        for index in 1 ..< POINT_COUNT {
            point := &state.points[index]
            // The first link is driven by the rump's changing heading. Give
            // it a separate damper so running does not excite a visible
            // high-frequency shake through the rest of the chain.
            point_damping := index == 1 ? clamp(config.root_damping, 0, 1) : damping
            velocity := scale(subtract(point.position, point.previous), point_damping)
            point.previous = point.position
            point.position = add(add(point.position, velocity), {y = -max(config.gravity, f32(0)) * dt_squared})
        }

        // Apply the rump's heading once per substep. Reapplying this inside
        // every solver iteration makes the first link snap toward the target
        // repeatedly and shows up as a shake while running.
        desired_first := add(root, scale(backward_direction, segment_length))
        root_stiffness := clamp(config.root_stiffness, 0, 1)
        state.points[1].position = add(
            state.points[1].position,
            scale(subtract(desired_first, state.points[1].position), root_stiffness),
        )

        for _ in 0 ..< iterations {
            state.points[0].position = root
            bend_target := segment_length * 1.94
            bend_weight := clamp(config.bend_stiffness, 0, 1)
            for index in 0 ..< POINT_COUNT - 2 {
                constrain_bend(&state.points[index], &state.points[index + 2], bend_target, bend_weight, index == 0)
            }
            for index in 0 ..< POINT_COUNT - 1 {
                a_weight := index == 0 ? f32(0) : f32(1)
                constrain_distance(&state.points[index], &state.points[index + 1], segment_length, a_weight, 1)
            }
            for index in 1 ..< POINT_COUNT {
                resolve_world(&state.points[index], project, config)
            }
        }
    }
    state.points[0] = {
        position = root,
        previous = root,
    }
    state.last_root = root
}
