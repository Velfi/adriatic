package umbrellas

import "core:math"

MAX_PANELS :: 16

Kind :: enum u8 {
    Beach,
    Patio,
}

Base :: enum u8 {
    Spike,
    Slab,
}

Config :: struct {
    kind:        Kind,
    radius:      f32,
    height:      f32,
    panel_count: int,
}

Plan :: struct {
    seed:         u32,
    kind:         Kind,
    base:         Base,
    radius:       f32,
    height:       f32,
    canopy_rise:  f32,
    canopy_drop:  f32,
    pole_radius:  f32,
    tilt:         f32,
    tilt_heading: f32,
    rotation:     f32,
    palette:      u8,
    scalloped:    bool,
    panel_count:  int,
    valid:        bool,
}

mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

defaults :: proc(kind: Kind) -> Config {
    if kind == .Beach do return {kind = .Beach, radius = 1.85, height = 2.35, panel_count = 10}
    return {kind = .Patio, radius = 2.65, height = 3.25, panel_count = 12}
}

generate :: proc(seed: u32, requested: Config) -> Plan {
    config := requested
    config.radius = clamp(config.radius, f32(1.2), f32(4.0))
    config.height = clamp(config.height, f32(1.8), f32(4.5))
    config.panel_count = clamp(config.panel_count, 6, MAX_PANELS)
    // An even panel ring preserves alternating canvas stripes without a seam.
    if config.panel_count & 1 != 0 do config.panel_count += 1

    variation := mix(seed ~ 0x554d4252)
    shape := f32(variation & 255) / 255
    plan := Plan {
        seed         = seed,
        kind         = config.kind,
        base         = config.kind == .Beach ? .Spike : .Slab,
        radius       = config.radius,
        height       = config.height,
        canopy_rise  = config.radius * (config.kind == .Beach ? f32(.28 + shape * .06) : f32(.18 + shape * .035)),
        canopy_drop  = config.radius * (config.kind == .Beach ? f32(.07) : f32(.045)),
        pole_radius  = config.kind == .Beach ? f32(.035) : f32(.055),
        tilt         = config.kind == .Beach ? f32(.08 + f32((variation >> 8) & 255) / 255 * .13) : 0,
        tilt_heading = f32((variation >> 16) & 255) / 255 * f32(math.PI * 2),
        rotation     = f32((variation >> 24) & 255) / 255 * f32(math.PI * 2),
        palette      = u8((variation >> 12) % 4),
        scalloped    = config.kind == .Patio && ((variation >> 7) & 1) != 0,
        panel_count  = config.panel_count,
    }
    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil do return false
    if plan.radius < 1.2 || plan.radius > 4 do return false
    if plan.height < 1.8 || plan.height > 4.5 do return false
    if plan.panel_count < 6 || plan.panel_count > MAX_PANELS || plan.panel_count & 1 != 0 do return false
    if plan.canopy_rise <= 0 || plan.canopy_rise >= plan.radius do return false
    if plan.canopy_drop < 0 || plan.canopy_drop >= plan.canopy_rise do return false
    if plan.pole_radius <= 0 || plan.pole_radius >= plan.radius * .1 do return false
    if plan.kind == .Patio && (plan.base != .Slab || plan.tilt != 0) do return false
    if plan.kind == .Beach && (plan.base != .Spike || plan.tilt <= 0 || plan.tilt > .25) do return false
    return true
}
