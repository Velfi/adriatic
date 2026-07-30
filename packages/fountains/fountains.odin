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
    seed:              u32,
    radius:            f32,
    wall_height:       f32,
    water_level:       f32,
    rim_width:         f32,
    basin_segments:    int,
    pedestal_radius:   f32,
    pedestal_height:   f32,
    lower_tier_radius: f32,
    upper_tier_radius: f32,
    tier_count:        int,
    jet_pattern:       u8,
    style:             Style,
    jets:              [MAX_JETS]Jet,
    jet_count:         int,
    valid:             bool,
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

    architecture_hash := mix(seed ~ 0x51ed270b)
    architecture_variation := f32(architecture_hash & 255) / 255
    silhouette_variation := f32((architecture_hash >> 8) & 255) / 255
    plan := Plan {
        seed              = seed,
        radius            = config.radius,
        wall_height       = clamp(config.radius * (.16 + architecture_variation * .035), f32(.46), f32(.94)),
        rim_width         = clamp(config.radius * (.115 + silhouette_variation * .035), f32(.32), f32(.72)),
        basin_segments    = config.style == .Bowl ? 32 : (config.style == .Tiered ? 24 : 12),
        pedestal_radius   = config.style == .Courtyard ? f32(.58) : f32(.44 + architecture_variation * .10),
        pedestal_height   = config.style == .Tiered ? f32(2.18 + silhouette_variation * .34) : (config.style == .Bowl ? f32(1.02 + silhouette_variation * .26) : f32(1.28 + silhouette_variation * .30)),
        lower_tier_radius = f32(1.30 + architecture_variation * .24),
        upper_tier_radius = f32(.68 + silhouette_variation * .18),
        style             = config.style,
        tier_count        = config.style == .Tiered ? 2 : 1,
        jet_pattern       = u8((architecture_hash >> 16) % 3),
    }
    plan.water_level = plan.wall_height * .72
    plan.jet_count = config.jet_count

    // Build mirrored motifs rather than assigning unrelated noise to every
    // stream. Opposing jets share one motif sample, preserving the formal
    // symmetry of civic fountains while seeds select a restrained rhythm.
    phase := f32(mix(seed) & 1023) / 1023 * f32(math.PI * 2)
    even_ring := plan.jet_count & 1 == 0
    motif_count := max(even_ring ? plan.jet_count / 2 : plan.jet_count, 1)
    for index in 0 ..< plan.jet_count {
        motif_index := index % motif_count
        motif_angle := f32(motif_index) * f32(math.PI * 2) / f32(motif_count)
        wave := math.cos(motif_angle + f32((architecture_hash >> 24) & 255) / 255 * math.PI * 2)
        alternating := motif_index & 1 == 0 ? f32(-1) : f32(1)
        height_scale, landing_scale := f32(1), f32(1)
        switch plan.jet_pattern {
        case 0:
            height_scale = 1 + wave * .035
        case 1:
            if even_ring {
                height_scale = 1 + alternating * .10
                landing_scale = 1 + alternating * .055
            } else {
                // Odd rings cannot have diametric pairs or a seamless
                // alternating sequence. Use a circular wave so the motif
                // remains rotationally coherent without a doubled seam.
                height_scale = 1 + wave * .10
                landing_scale = 1 - wave * .055
            }
        case 2:
            height_scale = 1 + wave * .12
            landing_scale = 1 - wave * .045
        }
        style_radius := config.style == .Courtyard ? f32(.68) : f32(.55)
        if config.style == .Bowl {
            height_scale = 1 + (height_scale - 1) * .55
            landing_scale = 1 + (landing_scale - 1) * .45
        } else if config.style == .Courtyard {
            // The large civic basin benefits from clearly nested landing
            // rings; its alternating pattern remains architectural at scale.
            landing_scale = 1 + (landing_scale - 1) * 1.45
        }
        plan.jets[index] = {
            angle       = phase + f32(index) * f32(math.PI * 2) / f32(max(plan.jet_count, 1)),
            radius      = config.radius * style_radius * landing_scale,
            height      = config.jet_height * height_scale,
            inward_lean = config.style == .Bowl ? f32(.48) : (config.style == .Courtyard ? f32(.62) : f32(.56)),
        }
    }
    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil || plan.radius < 2.2 || plan.radius > 7 do return false
    if plan.wall_height <= 0 || plan.water_level <= 0 || plan.water_level >= plan.wall_height do return false
    if plan.rim_width <= 0 || plan.rim_width >= plan.radius * .5 do return false
    if plan.basin_segments < 8 || plan.basin_segments > 40 do return false
    if plan.jet_pattern > 2 do return false
    if plan.pedestal_radius <= 0 || plan.pedestal_radius >= plan.radius do return false
    if plan.pedestal_height <= plan.wall_height do return false
    if plan.tier_count > 1 &&
       (plan.upper_tier_radius <= plan.pedestal_radius ||
               plan.lower_tier_radius <= plan.upper_tier_radius ||
               plan.lower_tier_radius >= plan.radius) {
        return false
    }
    if plan.jet_count < 0 || plan.jet_count > MAX_JETS do return false
    usable_water_radius := plan.radius - plan.rim_width - .12
    if usable_water_radius <= 0 do return false
    for jet in plan.jets[:plan.jet_count] {
        if jet.radius <= 0 || jet.radius >= usable_water_radius do return false
        if jet.height <= 0 do return false
    }
    return true
}
