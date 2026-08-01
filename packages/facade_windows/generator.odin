package facade_windows

Region :: enum u8 {
    Adriatic,
    Aegean,
}

Surround :: enum u8 {
    Dressed_Stone,
    Whitewashed_Reveal,
    Molded_Stone,
}

Shutter_Style :: enum u8 {
    Solid,
    Louvered,
    Persiana,
}

Shutter_State :: enum u8 {
    Closed,
    Ajar,
    Open,
}

Config :: struct {
    region:          Region,
    surround:        Surround,
    shutter_style:   Shutter_Style,
    shutter_state:   Shutter_State,
    width:           f32,
    height:          f32,
    reveal_depth:    f32,
    surround_width:  f32,
    sill_projection: f32,
    shutter_angle:   f32,
    pane_columns:    int,
    pane_rows:       int,
}

Plan :: struct {
    seed:              u32,
    region:            Region,
    surround:          Surround,
    shutter_style:     Shutter_Style,
    shutter_state:     Shutter_State,
    width:             f32,
    height:            f32,
    reveal_depth:      f32,
    surround_width:    f32,
    surround_depth:    f32,
    sill_height:       f32,
    sill_projection:   f32,
    shutter_width:     f32,
    shutter_thickness: f32,
    shutter_angle:     f32,
    pane_columns:      int,
    pane_rows:         int,
    louver_count:      int,
    lower_panel_ratio: f32,
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
            surround = .Whitewashed_Reveal,
            shutter_style = .Solid,
            shutter_state = .Open,
            width = 1.05,
            height = 1.35,
            reveal_depth = .42,
            surround_width = .18,
            sill_projection = .08,
            shutter_angle = 1.42,
            pane_columns = 2,
            pane_rows = 2,
        }
    }
    return {
        region = .Adriatic,
        surround = .Dressed_Stone,
        shutter_style = .Louvered,
        shutter_state = .Open,
        width = 1.20,
        height = 1.85,
        reveal_depth = .24,
        surround_width = .20,
        sill_projection = .16,
        shutter_angle = 1.48,
        pane_columns = 2,
        pane_rows = 3,
    }
}

generate :: proc(seed: u32, requested: Config) -> Plan {
    config := requested
    aegean := config.region == .Aegean
    config.width = clamp(config.width, aegean ? f32(.65) : f32(.80), aegean ? f32(1.55) : f32(1.85))
    config.height = clamp(config.height, aegean ? f32(.75) : f32(1.15), aegean ? f32(1.90) : f32(2.60))
    config.reveal_depth = clamp(config.reveal_depth, f32(.10), f32(.65))
    config.surround_width = clamp(config.surround_width, f32(.10), f32(.34))
    config.sill_projection = clamp(config.sill_projection, f32(.04), f32(.30))
    config.pane_columns = clamp(config.pane_columns, 1, 3)
    config.pane_rows = clamp(config.pane_rows, 1, 4)
    switch config.shutter_state {
    case .Closed:
        config.shutter_angle = 0
    case .Ajar:
        config.shutter_angle = clamp(config.shutter_angle, f32(.22), f32(.82))
    case .Open:
        config.shutter_angle = clamp(config.shutter_angle, f32(1.05), f32(1.57))
    }

    variation := f32(mix(seed ~ 0x57494e44) & 255) / 255
    louver_pitch := aegean ? f32(.145) : f32(.115)
    louver_count := int(config.height / louver_pitch)
    plan := Plan {
        seed              = seed,
        region            = config.region,
        surround          = config.surround,
        shutter_style     = config.shutter_style,
        shutter_state     = config.shutter_state,
        width             = config.width,
        height            = config.height,
        reveal_depth      = config.reveal_depth,
        surround_width    = config.surround_width,
        surround_depth    = aegean ? f32(.18) : f32(.12),
        sill_height       = aegean ? f32(.10) : f32(.13),
        sill_projection   = config.sill_projection,
        shutter_width     = config.width * .5 + .035,
        shutter_thickness = aegean ? f32(.075) : f32(.065),
        shutter_angle     = config.shutter_angle,
        pane_columns      = config.pane_columns,
        pane_rows         = config.pane_rows,
        louver_count      = clamp(louver_count, 5, 20),
        lower_panel_ratio = config.shutter_style == .Persiana ? f32(.25 + variation * .08) : f32(0),
    }
    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil do return false
    if plan.width <= 0 || plan.height <= 0 || plan.reveal_depth <= 0 do return false
    if plan.surround_width <= 0 || plan.sill_height <= 0 || plan.sill_projection <= 0 do return false
    if plan.shutter_width < plan.width * .49 || plan.shutter_thickness <= 0 do return false
    if plan.pane_columns < 1 || plan.pane_columns > 3 || plan.pane_rows < 1 || plan.pane_rows > 4 do return false
    if plan.louver_count < 5 || plan.louver_count > 20 do return false
    if plan.shutter_state == .Closed && plan.shutter_angle != 0 do return false
    if plan.shutter_state == .Ajar && (plan.shutter_angle < .22 || plan.shutter_angle > .82) do return false
    if plan.shutter_state == .Open && (plan.shutter_angle < 1.05 || plan.shutter_angle > 1.57) do return false
    if plan.shutter_style == .Persiana && (plan.lower_panel_ratio < .25 || plan.lower_panel_ratio > .33) do return false
    return true
}
