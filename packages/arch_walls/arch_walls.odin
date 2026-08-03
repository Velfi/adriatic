package arch_walls

import "core:math"

Vec2 :: [2]f32

MAX_PATH_POINTS :: 32

Terrain_Height_Proc :: proc(position: Vec2, data: rawptr) -> f32

Path :: struct {
    points:      [MAX_PATH_POINTS]Vec2,
    point_count: int,
    closed:      bool,
}

Config :: struct {
    height:              f32,
    thickness:           f32,
    target_span_length:  f32,
    minimum_ground_step: f32,
    arch_spacing:        f32,
    arch_width:          f32,
    arch_height:         f32,
    arch_ring_thickness: f32,
    arch_segments:       int,
}

Span :: struct {
    from, to:                 Vec2,
    left_from, right_from:    f32,
    left_to, right_to:        f32,
    station_from, station_to: f32,
}

Arch :: struct {
    position: Vec2,
    tangent:  Vec2,
    ground:   f32,
    station:  f32,
    width:    f32,
    height:   f32,
}

Plan :: struct {
    spans:  [dynamic]Span,
    arches: [dynamic]Arch,
    length: f32,
    valid:  bool,
}

defaults :: proc() -> Config {
    return {
        height = 3.2,
        thickness = .55,
        target_span_length = 1.25,
        minimum_ground_step = .20,
        arch_spacing = 8,
        arch_width = 2.8,
        arch_height = 2.6,
        arch_ring_thickness = .28,
        arch_segments = 12,
    }
}

dispose :: proc(plan: ^Plan) {
    if plan == nil do return
    delete(plan.spans)
    delete(plan.arches)
    plan^ = {}
}

catmull_rom :: proc(a, b, c, d: Vec2, t: f32) -> Vec2 {
    t2, t3 := t * t, t * t * t
    return .5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
}

path_index :: #force_inline proc(path: ^Path, i: int) -> int {
    if path.closed do return ((i % path.point_count) + path.point_count) % path.point_count
    return clamp(i, 0, path.point_count - 1)
}

vec2_length :: #force_inline proc(value: Vec2) -> f32 {
    return math.sqrt(value.x * value.x + value.y * value.y)
}

stepped_ground :: #force_inline proc(sample: Terrain_Height_Proc, data: rawptr, point: Vec2, step_height: f32) -> f32 {
    value := sample_ground(sample, data, point)
    return math.floor(value / step_height + f32(.5)) * step_height
}

path_point :: proc(path: ^Path, amount: f32) -> Vec2 {
    if path == nil || path.point_count <= 0 do return {}
    if path.point_count == 1 do return path.points[0]
    piece_count := path.closed ? path.point_count : path.point_count - 1
    scaled := clamp(amount, f32(0), f32(1)) * f32(piece_count)
    piece := min(int(math.floor(scaled)), piece_count - 1)
    t := scaled - f32(piece)
    return catmull_rom(
        path.points[path_index(path, piece - 1)],
        path.points[path_index(path, piece)],
        path.points[path_index(path, piece + 1)],
        path.points[path_index(path, piece + 2)],
        t,
    )
}

sample_ground :: #force_inline proc(sample: Terrain_Height_Proc, data: rawptr, point: Vec2) -> f32 {
    if sample == nil do return 0
    return sample(point, data)
}

generate :: proc(
    path: ^Path,
    config: Config,
    terrain_height: Terrain_Height_Proc,
    terrain_data: rawptr = nil,
) -> Plan {
    plan: Plan
    if path == nil || path.point_count < 2 || path.point_count > MAX_PATH_POINTS || config.height <= 0 || config.thickness <= 0 do return plan

    // First estimate arc length at a stable resolution. The final sampling is
    // distance-driven, so adding path length adds spans without stretching them.
    estimate_steps := max(32, (path.point_count - 1) * 24)
    if path.closed do estimate_steps = max(32, path.point_count * 24)
    previous := path_point(path, 0)
    estimated_length: f32
    for step in 1 ..= estimate_steps {
        point := path_point(path, f32(step) / f32(estimate_steps))
        estimated_length += vec2_length(point - previous)
        previous = point
    }
    if estimated_length <= .001 do return plan

    target := max(config.target_span_length, f32(.15))
    span_count := max(1, int(math.ceil(estimated_length / target)))
    plan.spans = make([dynamic]Span, 0, span_count)
    half_width := config.thickness * .5
    previous = path_point(path, 0)
    station: f32
    for step in 0 ..< span_count {
        amount_from := f32(step) / f32(span_count)
        amount_to := f32(step + 1) / f32(span_count)
        from := path_point(path, amount_from)
        to := path_point(path, amount_to)
        delta := to - from
        distance := vec2_length(delta)
        if distance <= .0001 do continue
        tangent := delta / distance
        normal := Vec2{-tangent.y, tangent.x} * half_width
        step_height := max(config.minimum_ground_step, f32(.01))
        append(
            &plan.spans,
            Span {
                from = from,
                to = to,
                left_from = stepped_ground(terrain_height, terrain_data, from + normal, step_height),
                right_from = stepped_ground(terrain_height, terrain_data, from - normal, step_height),
                left_to = stepped_ground(terrain_height, terrain_data, to + normal, step_height),
                right_to = stepped_ground(terrain_height, terrain_data, to - normal, step_height),
                station_from = station,
                station_to = station + distance,
            },
        )
        station += distance
        previous = to
    }
    plan.length = station

    if config.arch_spacing > 0 && config.arch_width > 0 && config.arch_height > 0 {
        arch_count := int(math.floor(plan.length / config.arch_spacing))
        plan.arches = make([dynamic]Arch, 0, arch_count)
        for arch_index in 0 ..< arch_count {
            station_target := (f32(arch_index) + .5) * plan.length / f32(arch_count)
            for span in plan.spans {
                if station_target < span.station_from || station_target > span.station_to do continue
                t := (station_target - span.station_from) / max(span.station_to - span.station_from, f32(.0001))
                position := span.from + (span.to - span.from) * t
                tangent := span.to - span.from
                tangent /= max(vec2_length(tangent), f32(.000001))
                append(
                    &plan.arches,
                    Arch {
                        position = position,
                        tangent = tangent,
                        ground = sample_ground(terrain_height, terrain_data, position),
                        station = station_target,
                        width = config.arch_width,
                        height = config.arch_height,
                    },
                )
                break
            }
        }
    }
    plan.valid = len(plan.spans) > 0
    return plan
}
