package hero_buildings

import "core:math"

Kind :: enum u8 {
    Post_Office,
    Airport_Terminal,
    Clinic,
}

Roof_Form :: enum u8 {
    Centered_Lantern,
    Offset_Lantern,
    Twin_Lantern,
}

Room_Arrangement :: enum u8 {
    Split_Corners,
    Grouped_Left,
    Grouped_Right,
}

Counter_Form :: enum u8 {
    Linear,
    L_Shaped,
    Circular,
}

Waiting_Layout :: enum u8 {
    End_Bays,
    Side_Rows,
}

Config :: struct {
    kind:          Kind,
    frontage:      f32,
    depth:         f32,
    arcade_depth:  f32,
    bay_count:     int,
    arcade_height: f32,
}

Plan :: struct {
    seed:                 u32,
    kind:                 Kind,
    frontage:             f32,
    depth:                f32,
    arcade_depth:         f32,
    arcade_height:        f32,
    enclosed_depth:       f32,
    bay_count:            int,
    bay_width:            f32,
    pier_width:           f32,
    pier_depth:           f32,
    roof_height:          f32,
    roof_overhang:        f32,
    monitor_width:        f32,
    monitor_depth:        f32,
    monitor_height:       f32,
    counter_width:        f32,
    counter_depth:        f32,
    counter_z:            f32,
    entrance_width:       f32,
    mailbox_count:        int,
    clock:                bool,
    side_mailboxes:       bool,
    open_office:          bool,
    secure_width:         f32,
    secure_depth:         f32,
    has_secure_room:      bool,
    circular_counter:     bool,
    counter_radius:       f32,
    private_room_count:   int,
    roof_form:            Roof_Form,
    monitor_count:        int,
    monitor_offset_x:     f32,
    room_arrangement:     Room_Arrangement,
    counter_form:         Counter_Form,
    counter_return_depth: f32,
    counter_return_side:  f32,
    waiting_layout:       Waiting_Layout,
    valid:                bool,
}

mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

defaults :: proc(kind: Kind = .Post_Office) -> Config {
    if kind == .Airport_Terminal {
        return {kind = kind, frontage = 30, depth = 18, arcade_depth = 7.4, bay_count = 6, arcade_height = 5.0}
    }
    if kind == .Clinic {
        return {kind = kind, frontage = 26, depth = 16, arcade_depth = 6.6, bay_count = 5, arcade_height = 4.8}
    }
    return {kind = kind, frontage = 24, depth = 15, arcade_depth = 6.2, bay_count = 5, arcade_height = 4.8}
}

generate :: proc(seed: u32, requested: Config) -> Plan {
    config := requested
    config.frontage = clamp(config.frontage, f32(16), f32(34))
    config.depth = clamp(config.depth, f32(11), f32(23))
    config.arcade_depth = clamp(config.arcade_depth, f32(4.5), config.depth * .58)
    config.arcade_height = clamp(config.arcade_height, f32(3.8), f32(6.5))
    config.bay_count = clamp(config.bay_count, 3, 8)
    if config.kind != .Airport_Terminal && config.bay_count & 1 == 0 {
        config.bay_count += config.bay_count < 7 ? 1 : -1
    }

    shape := mix(seed ~ 0x4845524f)
    detail_salt := u32(0x504f5354)
    if config.kind == .Airport_Terminal do detail_salt = 0x41495254
    if config.kind == .Clinic do detail_salt = 0x434c494e
    detail := mix(seed ~ detail_salt)
    frontage := config.frontage * (.96 + f32(shape & 255) / 255 * .08)
    depth := config.depth * (.96 + f32((shape >> 8) & 255) / 255 * .08)
    arcade_depth := min(config.arcade_depth * (.95 + f32((detail >> 8) & 255) / 255 * .10), depth * .58)
    bay_width := frontage / f32(config.bay_count)
    pier_width := clamp(bay_width * (.14 + f32(detail & 31) / 31 * .035), f32(.62), f32(1.05))
    roof_form := Roof_Form(int((shape >> 20) % u32(len(Roof_Form))))
    monitor_count := roof_form == .Twin_Lantern ? 2 : 1
    monitor_width_scale := monitor_count == 2 ? f32(.24) : f32(.38 + f32((shape >> 4) & 15) / 15 * .12)
    counter_form := config.kind == .Airport_Terminal ? Counter_Form.Circular : Counter_Form(int((detail >> 18) & 1))
    plan := Plan {
        seed                 = seed,
        kind                 = config.kind,
        frontage             = frontage,
        depth                = depth,
        arcade_depth         = arcade_depth,
        arcade_height        = config.arcade_height * (.97 + f32((shape >> 16) & 255) / 255 * .06),
        enclosed_depth       = depth - arcade_depth,
        bay_count            = config.bay_count,
        bay_width            = bay_width,
        pier_width           = pier_width,
        pier_depth           = .78 + f32((detail >> 16) & 31) / 31 * .22,
        roof_height          = .36 + f32((shape >> 24) & 31) / 31 * .16,
        roof_overhang        = .65 + f32((detail >> 24) & 31) / 31 * .30,
        monitor_width        = frontage * monitor_width_scale,
        monitor_depth        = arcade_depth * (.36 + f32((detail >> 4) & 15) / 15 * .12),
        monitor_height       = .68 + f32((detail >> 12) & 15) / 15 * .34,
        counter_width        = config.kind == .Airport_Terminal ? f32(4.2) : min(frontage * (config.kind == .Clinic ? f32(.34) : f32(.48)), bay_width * 2.7),
        counter_depth        = config.kind == .Airport_Terminal ? f32(4.2) : (config.kind == .Clinic ? f32(1.10) : f32(1.25)),
        counter_z            = arcade_depth * .08,
        entrance_width       = min(bay_width * .68, f32(2.5)),
        mailbox_count        = 4 + int((detail >> 20) & 3),
        clock                = config.kind == .Post_Office && shape & 1 == 0,
        side_mailboxes       = config.kind == .Post_Office && detail & 1 == 0,
        open_office          = true,
        secure_width         = config.kind == .Airport_Terminal ? 0 : min(bay_width * (config.kind == .Clinic ? f32(1.05) : f32(1.18)), frontage * .27),
        secure_depth         = config.kind == .Airport_Terminal ? 0 : min(f32(3.8), depth * .29),
        has_secure_room      = config.kind != .Airport_Terminal,
        circular_counter     = config.kind == .Airport_Terminal,
        counter_radius       = config.kind == .Airport_Terminal ? f32(1.65) : 0,
        private_room_count   = config.kind == .Clinic ? 2 : (config.kind == .Post_Office ? 1 : 0),
        roof_form            = roof_form,
        monitor_count        = monitor_count,
        monitor_offset_x     = roof_form == .Offset_Lantern ? frontage * (detail & 1 == 0 ? f32(-.16) : f32(.16)) : 0,
        room_arrangement     = Room_Arrangement(int((detail >> 21) % u32(len(Room_Arrangement)))),
        counter_form         = counter_form,
        counter_return_depth = counter_form == .L_Shaped ? min(depth * .22, f32(3.2)) : 0,
        counter_return_side  = detail & 2 == 0 ? f32(-1) : f32(1),
        waiting_layout       = Waiting_Layout(int((detail >> 25) & 1)),
    }
    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil do return false
    if plan.frontage < 16 || plan.frontage > 36 do return false
    if plan.depth < 11 || plan.depth > 24 do return false
    if plan.arcade_depth < 4.25 || plan.arcade_depth > plan.depth * .60 do return false
    if plan.enclosed_depth < 4.5 do return false
    if plan.arcade_height < 3.65 || plan.arcade_height > 6.7 do return false
    if plan.bay_count < 3 || plan.bay_count > 8 do return false
    if plan.kind != .Airport_Terminal && plan.bay_count & 1 == 0 do return false
    if plan.bay_width <= plan.pier_width * 2.5 do return false
    if plan.kind != .Airport_Terminal &&
       (plan.counter_width <= plan.bay_width || plan.counter_width >= plan.frontage * .65) {
        return false
    }
    if plan.monitor_width <= 0 || plan.monitor_width >= plan.frontage * .65 do return false
    if plan.monitor_count < 1 || plan.monitor_count > 2 do return false
    if plan.roof_form == .Twin_Lantern && plan.monitor_count != 2 do return false
    if plan.roof_form != .Twin_Lantern && plan.monitor_count != 1 do return false
    if math.abs(plan.monitor_offset_x) > plan.frontage * .18 do return false
    if plan.mailbox_count < 4 || plan.mailbox_count > 7 do return false
    if !plan.open_office do return false
    if plan.has_secure_room {
        if plan.secure_width <= 0 || plan.secure_width > plan.frontage * .28 do return false
        if plan.secure_depth <= 0 || plan.secure_depth > plan.depth * .30 do return false
        if plan.secure_width * plan.secure_depth > plan.frontage * plan.depth * .10 do return false
    } else if plan.secure_width != 0 || plan.secure_depth != 0 {
        return false
    }
    if plan.circular_counter != (plan.kind == .Airport_Terminal) do return false
    if plan.circular_counter != (plan.counter_form == .Circular) do return false
    if plan.circular_counter && (plan.counter_radius < 1.4 || plan.counter_radius > 2.1) do return false
    if plan.counter_form == .L_Shaped && plan.counter_return_depth <= plan.counter_depth do return false
    if plan.counter_form != .L_Shaped && plan.counter_return_depth != 0 do return false
    if plan.counter_return_side != -1 && plan.counter_return_side != 1 do return false
    expected_rooms := plan.kind == .Clinic ? 2 : (plan.kind == .Post_Office ? 1 : 0)
    if plan.private_room_count != expected_rooms do return false
    return true
}
