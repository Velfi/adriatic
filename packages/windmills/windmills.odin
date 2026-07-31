package windmills

import "core:math"

MAX_SAILS :: 12

Region :: enum u8 {
    Adriatic,
    Aegean,
}

Config :: struct {
    region:           Region,
    tower_height:     f32,
    tower_radius:     f32,
    sail_count:       int,
    sail_length:      f32,
    rpm:              f32,
    heading:          f32,
    entrance_heading: f32,
}

Plan :: struct {
    seed:              u32,
    region:            Region,
    tower_height:      f32,
    base_radius:       f32,
    top_radius:        f32,
    wall_segments:     int,
    wall_irregularity: f32,
    cap_height:        f32,
    cap_overhang:      f32,
    hub_height:        f32,
    hub_radius:        f32,
    sail_count:        int,
    sail_length:       f32,
    sail_root:         f32,
    sail_tip_width:    f32,
    door_width:        f32,
    door_height:       f32,
    window_count:      int,
    site_radius:       f32,
    site_segments:     int,
    site_irregularity: f32,
    site_rotation:     f32,
    phase:             f32,
    rpm:               f32,
    heading:           f32,
    entrance_heading:  f32,
    valid:             bool,
}

mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

defaults :: proc(region: Region = .Adriatic) -> Config {
    if region == .Aegean {
        return {
            region = .Aegean,
            tower_height = 7.8,
            tower_radius = 2.35,
            sail_count = 12,
            sail_length = 5.1,
            rpm = 3.5,
        }
    }
    return {region = .Adriatic, tower_height = 6.4, tower_radius = 2.7, sail_count = 8, sail_length = 4.3, rpm = 3.5}
}

generate :: proc(seed: u32, requested: Config) -> Plan {
    config := requested
    if config.region == .Aegean {
        config.tower_height = clamp(config.tower_height, f32(6.5), f32(10))
        config.tower_radius = clamp(config.tower_radius, f32(1.9), f32(3.0))
        config.sail_count = config.sail_count <= 10 ? 10 : 12
        config.sail_length = clamp(config.sail_length, f32(4.4), f32(6.0))
    } else {
        config.tower_height = clamp(config.tower_height, f32(5.0), f32(8.0))
        config.tower_radius = clamp(config.tower_radius, f32(2.0), f32(4.0))
        config.sail_count = 8
        config.sail_length = clamp(config.sail_length, f32(3.4), f32(5.2))
    }
    config.rpm = clamp(config.rpm, f32(0), f32(12))
    config.heading = clamp(config.heading, f32(-3.141592654), f32(3.141592654))
    config.entrance_heading = clamp(config.entrance_heading, f32(-3.141592654), f32(3.141592654))

    shape := mix(seed ~ 0x57494e44)
    detail := mix(seed ~ 0x4d494c4c)
    span := mix(seed ~ 0x5341494c)
    shape_unit := f32(shape & 255) / 255
    detail_unit := f32(detail & 255) / 255
    span_unit := f32(span & 255) / 255
    aegean := config.region == .Aegean
    height_scale := f32(.94 + shape_unit * .12)
    radius_scale := f32(.95 + detail_unit * .10)
    sail_scale := f32(.94 + span_unit * .12)
    tower_height := config.tower_height * height_scale
    base_radius := config.tower_radius * radius_scale
    sail_length := config.sail_length * sail_scale
    if aegean {
        tower_height = clamp(tower_height, f32(6.5), f32(10))
        base_radius = clamp(base_radius, f32(1.9), f32(3))
        sail_length = clamp(sail_length, f32(4.4), f32(6))
    } else {
        tower_height = clamp(tower_height, f32(5), f32(8))
        base_radius = clamp(base_radius, f32(2), f32(4))
        sail_length = clamp(sail_length, f32(3.4), f32(5.2))
    }
    plan := Plan {
        seed              = seed,
        region            = config.region,
        tower_height      = tower_height,
        base_radius       = base_radius,
        top_radius        = base_radius * (aegean ? f32(.82 + shape_unit * .045) : f32(.88 + shape_unit * .04)),
        wall_segments     = aegean ? 24 : 20 + int((shape >> 8) & 1) * 4,
        wall_irregularity = aegean ? f32(.015) : f32(.07 + detail_unit * .025),
        cap_height        = base_radius * (aegean ? f32(.90 + detail_unit * .10) : f32(.43 + detail_unit * .08)),
        cap_overhang      = base_radius * (aegean ? f32(.16) : f32(.12)),
        hub_height        = tower_height * (aegean ? f32(.91) : f32(.88)),
        hub_radius        = base_radius * (aegean ? f32(.115) : f32(.14)),
        sail_count        = config.sail_count,
        sail_length       = sail_length,
        sail_root         = base_radius * (aegean ? f32(.20) : f32(.24)),
        sail_tip_width    = sail_length * (aegean ? f32(.17) : f32(.20)),
        door_width        = base_radius * (aegean ? f32(.34) : f32(.40)),
        door_height       = tower_height * (aegean ? f32(.27) : f32(.31)),
        window_count      = aegean ? 2 : 3,
        site_radius       = max(
            base_radius * (aegean ? f32(2.15) : f32(2.1)),
            sail_length * (aegean ? f32(.92) : f32(.96)),
        ),
        site_segments     = aegean ? 12 : 9,
        site_irregularity = aegean ? f32(0) : f32(.09 + detail_unit * .05),
        site_rotation     = aegean ? f32(0) : f32(.12 + shape_unit * .14),
        phase             = f32((detail >> 8) & 1023) / 1023 * 6.283185307,
        rpm               = config.rpm,
        heading           = config.heading,
        entrance_heading  = config.entrance_heading,
    }
    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil do return false
    if plan.region == .Aegean {
        if plan.tower_height < 6.5 || plan.tower_height > 10 do return false
        if plan.base_radius < 1.9 || plan.base_radius > 3 do return false
        if plan.sail_count != 10 && plan.sail_count != 12 do return false
        if plan.sail_length < 4.4 || plan.sail_length > 6 do return false
    } else {
        if plan.tower_height < 5 || plan.tower_height > 8 do return false
        if plan.base_radius < 2 || plan.base_radius > 4 do return false
        if plan.sail_count != 8 do return false
        if plan.sail_length < 3.4 || plan.sail_length > 5.2 do return false
    }
    if plan.top_radius <= 0 || plan.top_radius >= plan.base_radius do return false
    if plan.wall_segments < 12 || plan.wall_segments > 24 do return false
    if plan.sail_root <= plan.hub_radius || plan.sail_root >= plan.sail_length do return false
    if plan.hub_height <= plan.tower_height * .65 || plan.hub_height >= plan.tower_height do return false
    if plan.cap_height <= 0 || plan.cap_overhang <= 0 do return false
    if plan.site_radius <= plan.base_radius || plan.site_segments < 6 || plan.site_segments > 16 do return false
    if plan.site_irregularity < 0 || plan.site_irregularity > .2 do return false
    if plan.rpm < 0 || plan.rpm > 12 do return false
    if plan.heading < -3.141592654 || plan.heading > 3.141592654 do return false
    if plan.entrance_heading < -3.141592654 || plan.entrance_heading > 3.141592654 do return false
    return true
}

// The roof heading points along the rotor shaft. Only airflow through the
// rotor plane drives it; a crosswind contributes no torque. The configured
// RPM is the rated mechanical speed reached at eight world wind units.
rotor_rpm_for_wind :: proc(plan: ^Plan, wind: [2]f32) -> f32 {
    if plan == nil || plan.rpm <= 0 do return 0
    forward_x := f32(math.sin(f64(plan.heading)))
    forward_z := f32(math.cos(f64(plan.heading)))
    through_rotor := wind[0] * forward_x + wind[1] * forward_z
    if abs(through_rotor) < .35 do return 0
    response := clamp(abs(through_rotor) / 8, f32(0), f32(1))
    direction := through_rotor < 0 ? f32(-1) : f32(1)
    return plan.rpm * response * direction
}

wrap_heading :: proc(heading: f32) -> f32 {
    return f32(math.atan2(math.sin(heading), math.cos(heading)))
}

// A towermill's cap can face either normal of the same rotor plane. Choose
// the wind-aligned equivalent requiring the least rotation of the heavy cap.
rotor_heading_for_wind :: proc(current: f32, wind: [2]f32) -> f32 {
    if wind[0] * wind[0] + wind[1] * wind[1] < .35 * .35 do return wrap_heading(current)
    target := math.atan2(wind[0], wind[1])
    delta := wrap_heading(target - current)
    if delta > math.PI * .5 {
        delta -= math.PI
    } else if delta < -math.PI * .5 {
        delta += math.PI
    }
    return wrap_heading(current + delta)
}

approach_heading :: proc(current, target, max_delta: f32) -> f32 {
    delta := wrap_heading(target - current)
    return wrap_heading(current + clamp(delta, -max_delta, max_delta))
}
