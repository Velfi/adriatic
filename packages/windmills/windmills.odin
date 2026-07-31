package windmills

MAX_SAILS :: 8

Style :: enum u8 {
    Stone,
    Whitewashed,
    Ochre,
}

Config :: struct {
    style:        Style,
    tower_height: f32,
    tower_radius: f32,
    sail_count:   int,
    sail_length:  f32,
    rpm:          f32,
}

Plan :: struct {
    seed:            u32,
    style:           Style,
    tower_height:    f32,
    base_radius:     f32,
    top_radius:      f32,
    wall_segments:   int,
    cap_height:      f32,
    cap_overhang:    f32,
    hub_height:      f32,
    hub_radius:      f32,
    sail_count:      int,
    sail_length:     f32,
    sail_root:       f32,
    sail_tip_width:  f32,
    sail_root_width: f32,
    door_angle:      f32,
    window_angle:    f32,
    phase:           f32,
    rpm:             f32,
    valid:           bool,
}

mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

defaults :: proc() -> Config {
    return {
        style = .Whitewashed,
        tower_height = 6.8,
        tower_radius = 2.35,
        sail_count = 4,
        sail_length = 4.15,
        rpm = 3.5,
    }
}

generate :: proc(seed: u32, requested: Config) -> Plan {
    config := requested
    config.tower_height = clamp(config.tower_height, f32(4.5), f32(10))
    config.tower_radius = clamp(config.tower_radius, f32(1.6), f32(3.5))
    config.sail_count = clamp(config.sail_count, 4, MAX_SAILS)
    config.sail_length = clamp(config.sail_length, f32(2.8), f32(6))
    config.rpm = clamp(config.rpm, f32(0), f32(12))

    shape := mix(seed ~ 0x57494e44)
    detail := mix(seed ~ 0x4d494c4c)
    shape_unit := f32(shape & 255) / 255
    detail_unit := f32(detail & 255) / 255
    plan := Plan {
        seed            = seed,
        style           = config.style,
        tower_height    = config.tower_height,
        base_radius     = config.tower_radius,
        top_radius      = config.tower_radius * (.76 + shape_unit * .08),
        wall_segments   = 16 + int((shape >> 8) & 1) * 4,
        cap_height      = config.tower_radius * (.72 + detail_unit * .10),
        cap_overhang    = config.tower_radius * (.13 + shape_unit * .035),
        hub_height      = config.tower_height * (.80 + detail_unit * .025),
        hub_radius      = config.tower_radius * .14,
        sail_count      = config.sail_count,
        sail_length     = config.sail_length,
        sail_root       = config.tower_radius * .28,
        sail_tip_width  = config.sail_length * (.18 + detail_unit * .025),
        sail_root_width = config.sail_length * .055,
        door_angle      = f32(0),
        window_angle    = f32(2.28 + shape_unit * .38),
        phase           = f32((detail >> 8) & 1023) / 1023 * 6.283185307,
        rpm             = config.rpm,
    }
    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil do return false
    if plan.tower_height < 4.5 || plan.tower_height > 10 do return false
    if plan.base_radius < 1.6 || plan.base_radius > 3.5 do return false
    if plan.top_radius <= 0 || plan.top_radius >= plan.base_radius do return false
    if plan.wall_segments < 12 || plan.wall_segments > 24 do return false
    if plan.sail_count < 4 || plan.sail_count > MAX_SAILS do return false
    if plan.sail_length < 2.8 || plan.sail_length > 6 do return false
    if plan.sail_root <= plan.hub_radius || plan.sail_root >= plan.sail_length do return false
    if plan.hub_height <= plan.tower_height * .65 || plan.hub_height >= plan.tower_height do return false
    if plan.rpm < 0 || plan.rpm > 12 do return false
    return true
}
