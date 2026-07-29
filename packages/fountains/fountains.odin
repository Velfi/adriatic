package fountains

import "core:math"

MAX_JETS :: 24

Style :: enum u8 {
    Bowl,
    Tiered,
    Courtyard,
}

Jet :: struct {
    angle:       f32,
    radius:      f32,
    height:      f32,
    inward_lean: f32,
}

Config :: struct {
    radius:     f32,
    style:      Style,
    jet_count:  int,
    jet_height: f32,
}

Plan :: struct {
    seed:        u32,
    radius:      f32,
    wall_height: f32,
    water_level: f32,
    tier_count:  int,
    style:       Style,
    jets:        [MAX_JETS]Jet,
    jet_count:   int,
    valid:       bool,
}

mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

defaults :: proc() -> Config {
    return {radius = 3.8, style = .Tiered, jet_count = 10, jet_height = 2.8}
}

generate :: proc(seed: u32, requested: Config) -> Plan {
    config := requested
    config.radius = clamp(config.radius, f32(2.2), f32(7.0))
    config.jet_count = clamp(config.jet_count, 0, MAX_JETS)
    config.jet_height = clamp(config.jet_height, f32(.4), f32(6.0))

    plan := Plan {
        seed        = seed,
        radius      = config.radius,
        wall_height = clamp(config.radius * .18, f32(.48), f32(.9)),
        style       = config.style,
        tier_count  = config.style == .Tiered ? 2 : 1,
    }
    plan.water_level = plan.wall_height * .72
    plan.jet_count = config.jet_count

    // Keep the ring regular enough to read as civic architecture, but vary
    // height and lean coherently so generated fountains do not look cloned.
    phase := f32(mix(seed) & 1023) / 1023 * f32(math.PI * 2)
    ring_radius := config.radius * (config.style == .Courtyard ? f32(.68) : f32(.55))
    for index in 0 ..< plan.jet_count {
        hash := mix(seed ~ u32(index + 1) * u32(0x9e3779b9))
        variation := f32(hash & 255) / 255
        plan.jets[index] = {
            angle       = phase + f32(index) * f32(math.PI * 2) / f32(max(plan.jet_count, 1)),
            radius      = ring_radius * (.94 + variation * .12),
            height      = config.jet_height * (.88 + variation * .22),
            inward_lean = config.style == .Bowl ? f32(.48) : (config.style == .Courtyard ? f32(.62) : f32(.56)),
        }
    }
    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil || plan.radius < 2.2 || plan.radius > 7 do return false
    if plan.wall_height <= 0 || plan.water_level <= 0 || plan.water_level >= plan.wall_height do return false
    if plan.jet_count < 0 || plan.jet_count > MAX_JETS do return false
    for jet in plan.jets[:plan.jet_count] {
        if jet.radius <= 0 || jet.radius >= plan.radius do return false
        if jet.height <= 0 do return false
    }
    return true
}
