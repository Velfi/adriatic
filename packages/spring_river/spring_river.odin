package spring_river

import "core:math"

// Long generated rivers use 2 m centerline spacing to stay near the terrain's
// 1 m authored grid. Leave enough capacity for the maximum supported length.
MAX_POINTS :: 512

Vec2 :: [2]f32

Config :: struct {
    seed:           u32,
    source:         Vec2,
    direction:      Vec2,
    source_height:  f32,
    length:         f32,
    segment_length: f32,
    gradient:       f32,
    discharge:      f32,
    meander:        f32,
    spring_radius:  f32,
}

Point :: struct {
    position:    Vec2,
    water_level: f32,
    width:       f32,
    depth:       f32,
    flow:        f32,
}

Plan :: struct {
    config:      Config,
    points:      [MAX_POINTS]Point,
    point_count: int,
    total_drop:  f32,
}

Sample :: struct {
    distance:       f32,
    water_level:    f32,
    bed_height:     f32,
    width:          f32,
    depth:          f32,
    bank_influence: f32,
    wetness:        f32,
    flow_direction: Vec2,
    inside_water:   bool,
}

Mouth :: struct {
    position:      Vec2,
    direction:     Vec2,
    water_level:   f32,
    width:         f32,
    depth:         f32,
    discharge:     f32,
    sediment_load: f32,
}

hash :: #force_inline proc(value: u32) -> u32 {
    result := value
    result = (result ~ (result >> 16)) * 0x7feb352d
    result = (result ~ (result >> 15)) * 0x846ca68b
    return result ~ (result >> 16)
}

random_signed :: #force_inline proc(seed, index, salt: u32) -> f32 {
    value := hash(seed ~ index * 0x9e3779b9 ~ salt)
    return f32(value & 0x00ffffff) / f32(0x00800000) - 1
}

normalize_or :: proc(value, fallback: Vec2) -> Vec2 {
    length_squared := value[0] * value[0] + value[1] * value[1]
    if length_squared <= .000001 do return fallback
    inverse := f32(1 / math.sqrt(f64(length_squared)))
    return value * inverse
}

smooth01 :: #force_inline proc(value: f32) -> f32 {
    t := clamp(value, f32(0), f32(1))
    return t * t * (3 - 2 * t)
}

generate :: proc(requested: Config) -> Plan {
    config := requested
    config.direction = normalize_or(config.direction, {0, 1})
    config.length = clamp(config.length, f32(12), f32(900))
    config.segment_length = clamp(config.segment_length, f32(2), f32(20))
    config.gradient = clamp(config.gradient, f32(.002), f32(.3))
    config.discharge = clamp(config.discharge, f32(.05), f32(2))
    config.meander = clamp(config.meander, f32(0), f32(1))
    config.spring_radius = clamp(config.spring_radius, f32(1), f32(18))

    plan := Plan {
        config = config,
    }
    plan.point_count = clamp(int(math.ceil(f64(config.length / config.segment_length))) + 1, 2, MAX_POINTS)
    step := config.length / f32(plan.point_count - 1)
    side := Vec2{-config.direction[1], config.direction[0]}
    phase := random_signed(config.seed, 0, 0x53505247) * math.PI
    previous_lateral := f32(0)
    for index in 0 ..< plan.point_count {
        progress := f32(index) / f32(plan.point_count - 1)
        distance := progress * config.length
        broad := math.sin(progress * math.PI * (2.1 + config.meander * 2.2) + phase)
        detail := math.sin(progress * math.PI * 8.3 - phase * .61) * .28
        noise := random_signed(config.seed, u32(index), 0x4d45414e) * .16
        envelope := smooth01(progress / .09) * smooth01((1 - progress) / .06)
        lateral := (broad + detail + noise) * config.meander * config.length * .055 * envelope
        // Limit local bends so downstream segments never fold back on themselves.
        lateral = clamp(lateral, previous_lateral - step * .7, previous_lateral + step * .7)
        // Both ends are contract points: the source stays on its requested
        // position and the mouth must meet the estuary inlet exactly. With a
        // fine centerline the per-segment bend clamp otherwise prevents the
        // last point from returning all the way to zero lateral offset.
        if index == 0 || index == plan.point_count - 1 do lateral = 0
        previous_lateral = lateral
        flow := config.discharge * (.72 + progress * .46)
        width :=
            config.spring_radius * (1 - smooth01(progress / .08)) * 2 + (1.15 + flow * 2.25) * smooth01(progress / .06)
        depth := .18 + flow * .52 + smooth01(progress / .18) * .16
        water_level := config.source_height - distance * config.gradient
        plan.points[index] = {
            position    = config.source + config.direction * distance + side * lateral,
            water_level = water_level,
            width       = width,
            depth       = depth,
            flow        = flow,
        }
    }
    plan.total_drop = config.length * config.gradient
    return plan
}

mouth :: proc(plan: ^Plan) -> Mouth {
    if plan == nil || plan.point_count < 2 do return {}
    last := plan.points[plan.point_count - 1]
    previous := plan.points[plan.point_count - 2]
    direction := normalize_or(last.position - previous.position, plan.config.direction)
    // Steeper, more sinuous rivers arrive with more suspended material. Keep
    // discharge in the response so a small spring cannot seed a mature delta.
    sediment := clamp(.12 + plan.config.gradient * 4.2 + plan.config.meander * .22 + last.flow * .16, f32(0), f32(1))
    return {
        position = last.position,
        direction = direction,
        water_level = last.water_level,
        width = last.width,
        depth = last.depth,
        discharge = last.flow,
        sediment_load = sediment,
    }
}

sample :: proc(plan: ^Plan, position: Vec2) -> Sample {
    if plan == nil || plan.point_count < 2 do return {}
    best_distance_squared := f32(1e30)
    result: Sample
    for index in 0 ..< plan.point_count - 1 {
        a, b := plan.points[index], plan.points[index + 1]
        segment := b.position - a.position
        length_squared := segment[0] * segment[0] + segment[1] * segment[1]
        if length_squared <= .000001 do continue
        relative := position - a.position
        t := clamp((relative[0] * segment[0] + relative[1] * segment[1]) / length_squared, f32(0), f32(1))
        closest := a.position + segment * t
        delta := position - closest
        distance_squared := delta[0] * delta[0] + delta[1] * delta[1]
        if distance_squared >= best_distance_squared do continue
        best_distance_squared = distance_squared
        distance := f32(math.sqrt(f64(distance_squared)))
        width := a.width + (b.width - a.width) * t
        depth := a.depth + (b.depth - a.depth) * t
        water_level := a.water_level + (b.water_level - a.water_level) * t
        half_width := width * .5
        bank_width := max(f32(2.2), width * .85)
        bank := 1 - smooth01((distance - half_width) / bank_width)
        wetness := 1 - smooth01((distance - half_width) / max(f32(1.2), width * .45))
        result = {
            distance       = distance,
            water_level    = water_level,
            bed_height     = water_level - depth * (1 - smooth01(distance / max(half_width, f32(.01))) * .28),
            width          = width,
            depth          = depth,
            bank_influence = bank,
            wetness        = wetness,
            flow_direction = normalize_or(segment, plan.config.direction),
            inside_water   = distance <= half_width,
        }
    }
    return result
}
