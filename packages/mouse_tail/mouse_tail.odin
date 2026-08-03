package mouse_tail

import architecture "../architecture"
import circulation "../circulation"
import roads "../roads"
import terrain "../terrain"
import third_person "../third_person"
import "core:math"
import "core:math/linalg"

// Thirteen shorter links preserve the original 2.04 m authored length while
// giving the rendered centerline enough resolution to form a smooth curve.
POINT_COUNT :: 13
TERRAIN_CONTACT_SKIN :: f32(.006)

Point :: struct {
    position: third_person.Vec3,
    previous: third_person.Vec3,
}

State :: struct {
    points:               [POINT_COUNT]Point,
    last_root:            third_person.Vec3,
    evaluated_attachment: third_person.Vec3,
    attachment_valid:     bool,
    initialized:          bool,
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
        segment_length        = .17,
        radius                = .026,
        gravity               = 12,
        // A mouse tail trails as one supple rod rather than preserving a
        // traveling impulse in each vertebra. Bleed off inherited point
        // velocity before it can reflect through the chain as an S-wave.
        damping               = .84,
        constraint_iterations = 8,
        substeps              = 3,
        root_stiffness        = .30,
        root_damping          = .48,
        // This is the total bend correction for one solver pass. The actual
        // rigidity tapers with the fourth power of the rendered radius, like
        // a slender elastic rod, so the muscular base carries its shape while
        // the narrow tip remains lively.
        bend_stiffness        = .80,
        surface_friction      = .22,
    }
}

reset :: proc(state: ^State, root, backward: third_person.Vec3, config: Config) {
    if state == nil do return
    direction := linalg.normalize0(third_person.Vec3{backward.x, -.22, backward.z})
    if linalg.dot(direction, direction) <= .000001 do direction = {0, 0, 1}
    side := third_person.Vec3{direction.z, 0, -direction.x}
    segment_length := max(config.segment_length, f32(.02))
    for index in 0 ..< POINT_COUNT {
        distance := f32(index) * segment_length
        weight := f32(index) / f32(POINT_COUNT - 1)
        authored_length := segment_length * f32(POINT_COUNT - 1)
        curl := math.sin(weight * 3.36) * authored_length * .04 * weight
        position := root + direction * distance + side * curl
        state.points[index] = {
            position = position,
            previous = position,
        }
    }
    state.last_root = root
    state.initialized = true
}

@(no_instrumentation)
point_is_finite :: #force_inline proc(point: third_person.Vec3) -> bool {
    // NaN is the only floating-point value unequal to itself. The magnitude
    // guard also rejects infinities and coordinates that cannot plausibly
    // belong to this finite world before they reach the mesh builder.
    return(
        point.x == point.x &&
        point.y == point.y &&
        point.z == point.z &&
        math.abs(point.x) < 1e6 &&
        math.abs(point.y) < 1e6 &&
        math.abs(point.z) < 1e6 \
    )
}

state_is_stretched :: proc(state: ^State, root: third_person.Vec3, config: Config) -> bool {
    if state == nil || !state.initialized do return false
    segment_length := max(config.segment_length, f32(.02))
    maximum_link := segment_length * 4
    maximum_link_squared := maximum_link * maximum_link
    authored_length := segment_length * f32(POINT_COUNT - 1)
    maximum_root_distance := authored_length * 1.5
    maximum_root_distance_squared := maximum_root_distance * maximum_root_distance
    for point, index in state.points {
        if !point_is_finite(point.position) || !point_is_finite(point.previous) do return true
        root_delta := point.position - root
        if linalg.dot(root_delta, root_delta) > maximum_root_distance_squared do return true
        if index > 0 {
            link := point.position - state.points[index - 1].position
            if linalg.dot(link, link) > maximum_link_squared do return true
        }
    }
    return false
}

@(no_instrumentation)
constrain_distance :: #force_inline proc(a, b: ^Point, target, a_weight, b_weight: f32) {
    delta := b.position - a.position
    distance_squared := linalg.dot(delta, delta)
    if distance_squared <= .0000001 do return
    distance := linalg.length(delta)
    correction := delta * ((distance - target) / distance)
    weight_sum := a_weight + b_weight
    if weight_sum <= 0 do return
    a.position += correction * (a_weight / weight_sum)
    b.position -= correction * (b_weight / weight_sum)
}

@(no_instrumentation)
constrain_bend :: #force_inline proc(a, b: ^Point, target, stiffness: f32, a_fixed: bool) {
    delta := b.position - a.position
    distance_squared := linalg.dot(delta, delta)
    if distance_squared <= .0000001 do return
    distance := linalg.length(delta)
    correction := delta * ((distance - target) / distance * clamp(stiffness, 0, 1))
    if a_fixed {
        b.position -= correction
    } else {
        a.position += correction * .5
        b.position -= correction * .5
    }
}

// Flexural rigidity for a round section is proportional to radius^4. Match
// the tail's visible 48% radius taper, retaining a small floor so the last
// vertebrae cannot fold into a numerical hinge.
@(no_instrumentation)
bend_rigidity_profile :: #force_inline proc(chain_weight: f32) -> f32 {
    radius_ratio := 1 - clamp(chain_weight, 0, 1) * .48
    radius_squared := radius_ratio * radius_ratio
    return max(radius_squared * radius_squared, f32(.08))
}

// Convert a user-facing per-pass stiffness into a per-iteration correction.
// Without this conversion, increasing the collision solver's iteration count
// silently makes the tail more rigid.
@(no_instrumentation)
bend_iteration_stiffness :: #force_inline proc(stiffness: f32, iterations: int) -> f32 {
    clamped := clamp(stiffness, 0, 1)
    if clamped <= 0 || iterations <= 0 do return 0
    if clamped >= 1 do return 1
    return 1 - f32(math.pow(f64(1 - clamped), 1.0 / f64(iterations)))
}

resolve_terrain :: proc(
    point: ^Point,
    project: ^terrain.Project,
    radius, friction: f32,
    cached_plan: ^circulation.Plan = nil,
) {
    surface_height := terrain.sample_surface_height(project, 0, point.position.x, point.position.z)
    fallback_plan: circulation.Plan
    plan := cached_plan
    if plan == nil {
        fallback_plan = architecture.circulation_plan(project)
        plan = &fallback_plan
    }
    pavement := circulation.surface_at(
    &project.road_graph,
    plan,
    // Generated circulation areas are planar overlays and preserve the
    // query height in their hit result. Query from the terrain surface,
    // not from the tail point, or each collision pass treats the point's
    // previous correction as a taller pavement and ratchets it upward.
    {point.position.x, surface_height, point.position.z},
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

@(no_instrumentation)
formation_is_solid :: #force_inline proc(kind: terrain.Formation_Kind) -> bool {
    switch kind {
    case .Foliage:
        return false
    case .Box, .Rock, .Spire, .Mountain, .Ridge, .Cliff, .Architecture, .Ruins:
        return true
    }
    return false
}

@(no_instrumentation)
apply_bounded_structure_correction :: #force_inline proc(
    point: ^Point,
    target: third_person.Vec3,
    maximum_correction: f32,
) {
    correction := target - point.position
    distance_squared := linalg.dot(correction, correction)
    limit := max(maximum_correction, f32(.001))
    if distance_squared > limit * limit {
        correction *= limit / linalg.length(correction)
    }
    point.position += correction
}

@(no_instrumentation)
resolve_structure :: #force_inline proc(
    point: ^Point,
    structure: terrain.Structure,
    radius, friction, maximum_correction: f32,
) {
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
        apply_bounded_structure_correction(point, {point.position.x, top, point.position.z}, maximum_correction)
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
    apply_bounded_structure_correction(
        point,
        {
            structure.center_x + local_x * cosine - local_z * sine,
            point.position.y,
            structure.center_z + local_x * sine + local_z * cosine,
        },
        maximum_correction,
    )
}

resolve_world :: proc(
    point: ^Point,
    project: ^terrain.Project,
    config: Config,
    circulation_plan: ^circulation.Plan = nil,
) {
    radius := max(config.radius, f32(0))
    resolve_terrain(point, project, radius, config.surface_friction, circulation_plan)
    for index in 0 ..< project.structure_count {
        structure := project.structures[index]
        // Any authored solid can have a large enclosing volume. Never let a
        // single collision projection stretch a tail link by metres in the
        // final solver iteration; repeated iterations still move genuinely
        // embedded points out of the obstacle. Small props cannot produce
        // the failure-sized correction and retain exact same-frame escape.
        maximum_correction := max(config.segment_length, f32(.02))
        resolve_structure(point, structure, radius, config.surface_friction, maximum_correction)
    }
    // A side projection can put a point over a different patch of terrain.
    resolve_terrain(point, project, radius, config.surface_friction, circulation_plan)
}

step :: proc(
    state: ^State,
    root, backward: third_person.Vec3,
    project: ^terrain.Project,
    config: Config,
    delta_seconds: f32,
    cached_plan: ^circulation.Plan = nil,
) {
    if state == nil || project == nil do return
    if !point_is_finite(root) {
        state.initialized = false
        return
    }
    if !state.initialized ||
       linalg.dot(root - state.last_root, root - state.last_root) > 4 ||
       state_is_stretched(state, root, config) {
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
    backward_direction := linalg.normalize0(third_person.Vec3{backward.x, 0, backward.z})
    if linalg.dot(backward_direction, backward_direction) <= .000001 do backward_direction = {0, 0, 1}
    bend_iteration_weights: [POINT_COUNT - 2]f32
    for index in 0 ..< POINT_COUNT - 2 {
        chain_weight := f32(index + 1) / f32(POINT_COUNT - 1)
        pass_stiffness := clamp(config.bend_stiffness, 0, 1) * bend_rigidity_profile(chain_weight)
        bend_iteration_weights[index] = bend_iteration_stiffness(pass_stiffness, iterations)
    }
    fallback_plan: circulation.Plan
    circulation_plan := cached_plan
    if circulation_plan == nil {
        fallback_plan = architecture.circulation_plan(project)
        circulation_plan = &fallback_plan
    }

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
            velocity := (point.position - point.previous) * point_damping
            point.previous = point.position
            point.position += velocity + {0, -max(config.gravity, f32(0)) * dt_squared, 0}
        }

        // Apply the rump's heading once per substep. Reapplying this inside
        // every solver iteration makes the first link snap toward the target
        // repeatedly and shows up as a shake while running.
        desired_first := root + backward_direction * segment_length
        root_stiffness := clamp(config.root_stiffness, 0, 1)
        state.points[1].position += (desired_first - state.points[1].position) * root_stiffness

        for _ in 0 ..< iterations {
            state.points[0].position = root
            bend_target := segment_length * 1.94
            for index in 0 ..< POINT_COUNT - 2 {
                // Use the middle vertebra's position along the chain. The
                // radius-derived profile produces a firm, load-bearing base
                // and progressively more compliant tip instead of a chain
                // with the same artificial hinge strength everywhere.
                constrain_bend(
                    &state.points[index],
                    &state.points[index + 2],
                    bend_target,
                    bend_iteration_weights[index],
                    index == 0,
                )
            }
            for index in 0 ..< POINT_COUNT - 1 {
                a_weight := index == 0 ? f32(0) : f32(1)
                constrain_distance(&state.points[index], &state.points[index + 1], segment_length, a_weight, 1)
            }
            for index in 1 ..< POINT_COUNT {
                resolve_world(&state.points[index], project, config, circulation_plan)
            }
        }
    }
    state.points[0] = {
        position = root,
        previous = root,
    }
    state.last_root = root
}
