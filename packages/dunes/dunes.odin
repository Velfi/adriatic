package dunes

import "core:math"

Vec2 :: [2]f32

Config :: struct {
    seed:                u32,
    anchor:              Vec2,
    tangent:             Vec2,
    inland:              Vec2,
    length:              f32,
    width:               f32,
    wind_direction:      Vec2,
    wind_strength:       f32,
    dune_height:         f32,
    dune_spacing:        f32,
    vegetation_strength: f32,
    shore_fade:          f32,
    inland_fade:         f32,
}

Plan :: struct {
    config:          Config,
    tangent:         Vec2,
    inland:          Vec2,
    wind_along:      f32,
    wind_inland:     f32,
    phase_offset:    f32,
    warp_phase:      f32,
    dune_count:      int,
    maximum_height:  f32,
    grass_grid_step: f32,
    grass_columns:   int,
    grass_rows:      int,
    candidate_count: int,
}

Sample :: struct {
    height_delta:      f32,
    coverage:          f32,
    sand_weight:       f32,
    grass_suitability: f32,
    exposure:          f32,
    stability:         f32,
    blowout:           f32,
    inside:            bool,
}

Grass_Candidate :: struct {
    position: Vec2,
    density:  f32,
    height:   f32,
    width:    f32,
    tile:     int,
    tint:     f32,
}

Shore_Config :: struct {
    sea_level:       f32,
    berm_height:     f32,
    dry_beach_width: f32,
    nearshore_width: f32,
    nearshore_depth: f32,
    shelf_width:     f32,
    shelf_depth:     f32,
    bar_strength:    f32,
}

Shore_Sample :: struct {
    height:        f32,
    depth:         f32,
    wetness:       f32,
    shallow_water: f32,
}

Curved_Coast_Config :: struct {
    seed:                u32,
    wind_direction:      Vec2,
    wind_strength:       f32,
    dune_height:         f32,
    dune_spacing:        f32,
    dune_width:          f32,
    vegetation_strength: f32,
}

clamp01 :: #force_inline proc(value: f32) -> f32 {
    return clamp(value, f32(0), f32(1))
}

smooth :: #force_inline proc(value: f32) -> f32 {
    t := clamp01(value)
    return t * t * (3 - 2 * t)
}

shore_sample :: proc(requested: Shore_Config, signed_shore_distance: f32) -> Shore_Sample {
    config := requested
    if config.berm_height <= 0 do config.berm_height = 1.1
    if config.dry_beach_width <= 0 do config.dry_beach_width = 28
    if config.nearshore_width <= 0 do config.nearshore_width = 72
    if config.nearshore_depth <= 0 do config.nearshore_depth = 3.2
    if config.shelf_width <= 0 do config.shelf_width = 150
    if config.shelf_depth <= config.nearshore_depth do config.shelf_depth = config.nearshore_depth + 9
    config.bar_strength = clamp(config.bar_strength, f32(0), config.nearshore_depth * .42)

    if signed_shore_distance >= 0 {
        berm_progress := smooth(signed_shore_distance / config.dry_beach_width)
        height := config.sea_level + config.berm_height * berm_progress
        return {height = height, wetness = 1 - smooth(signed_shore_distance / min(f32(8), config.dry_beach_width))}
    }

    offshore := -signed_shore_distance
    if offshore <= config.nearshore_width {
        progress := clamp01(offshore / config.nearshore_width)
        base_depth := config.nearshore_depth * f32(math.pow(f64(progress), .72))
        trough_delta := (progress - .24) / .12
        bar_delta := (progress - .58) / .16
        trough_origin := f32(math.exp(f64(-(.24 / .12) * (.24 / .12))))
        bar_origin := f32(math.exp(f64(-(.58 / .16) * (.58 / .16))))
        trough := config.bar_strength * .42 * (f32(math.exp(f64(-trough_delta * trough_delta))) - trough_origin)
        bar := config.bar_strength * (f32(math.exp(f64(-bar_delta * bar_delta))) - bar_origin)
        depth := max(f32(0), base_depth + trough - bar)
        return {
            height = config.sea_level - depth,
            depth = depth,
            wetness = smooth(offshore / 4),
            shallow_water = 1 - smooth(progress),
        }
    }

    shelf_progress := smooth((offshore - config.nearshore_width) / config.shelf_width)
    depth := config.nearshore_depth + (config.shelf_depth - config.nearshore_depth) * shelf_progress
    return {height = config.sea_level - depth, depth = depth, wetness = 1, shallow_water = (1 - shelf_progress) * .35}
}

hash :: #force_inline proc(value: u32) -> u32 {
    result := value
    result = (result ~ (result >> 16)) * 0x7feb352d
    result = (result ~ (result >> 15)) * 0x846ca68b
    return result ~ (result >> 16)
}

random01 :: #force_inline proc(seed, index, salt: u32) -> f32 {
    return f32(hash(seed ~ (index * 0x9e3779b9) ~ salt) & 0x00ffffff) / f32(0x01000000)
}

normalize_or :: proc(value, fallback: Vec2) -> Vec2 {
    length_squared := value[0] * value[0] + value[1] * value[1]
    if length_squared <= .000001 do return fallback
    inverse := f32(1 / math.sqrt(f64(length_squared)))
    return value * inverse
}

sample_curved_coast :: proc(
    requested: Curved_Coast_Config,
    position: Vec2,
    signed_shore_distance: f32,
    outward_normal: Vec2,
    site_suitability: f32 = 1,
) -> Sample {
    config := requested
    config.wind_strength = clamp01(config.wind_strength)
    config.vegetation_strength = clamp01(config.vegetation_strength)
    config.dune_height = max(config.dune_height, f32(0))
    config.dune_spacing = max(config.dune_spacing, f32(4))
    config.dune_width = max(config.dune_width, f32(1))
    suitability := clamp01(site_suitability)
    inland_distance := -signed_shore_distance
    if inland_distance <= 0 || inland_distance >= config.dune_width || suitability <= 0 do return {}

    outward := normalize_or(outward_normal, {0, -1})
    inward := -outward
    wind := normalize_or(config.wind_direction, inward)
    wind_inland := wind[0] * inward[0] + wind[1] * inward[1]
    wind_facing := smooth((wind_inland + .12) / .72)
    if wind_facing <= .001 do return {}

    // Use a fixed crosswind coordinate for phase continuity. Projecting the
    // world position onto the per-sample coast tangent makes tiny normal
    // changes jump the coordinate by hundreds of metres on large islands.
    crosswind := Vec2{-wind[1], wind[0]}
    along := position[0] * crosswind[0] + position[1] * crosswind[1]
    seed_phase := random01(config.seed, 0, 0x43555256) * math.PI * 2
    reach_field :=
        math.sin(along * .0073 + seed_phase) * .58 +
        math.sin(along * .019 - seed_phase * .71) * .29 +
        math.sin(along * .041 + seed_phase * 1.37) * .13
    // Keep a low, continuous foredune matrix along eligible coast while the
    // seeded field controls stronger lobes and gaps. Allowing reach to fall
    // all the way to zero made island dunes read as unrelated inland mounds.
    // Even exposed gaps retain a low foredune ridge; the alongshore field
    // modulates its maturity rather than switching geomorphology almost off.
    // The previous .14 floor reduced otherwise suitable island ridges to
    // shallow color bands that were hard to distinguish from the beach berm.
    reach_weight := smooth((reach_field + .32) / .72)
    reach := .28 + reach_weight * .72
    site := suitability * wind_facing * reach
    if site <= .001 do return {}

    shore_fade := smooth(inland_distance / min(f32(14), config.dune_width * .24))
    inland_fade := smooth((config.dune_width - inland_distance) / min(f32(30), config.dune_width * .35))
    envelope := shore_fade * inland_fade * site
    // Low-coast suitability controls how continuous the belt is more strongly
    // than how tall each surviving ridge can become. A square-root height
    // response keeps patchy coasts from collapsing into an unreadable ramp
    // while still fading unsuitable sites to zero.
    height_envelope := shore_fade * inland_fade * f32(math.sqrt(f64(site))) * (.62 + reach_weight * .38)
    warp :=
        math.sin(along * .025 + seed_phase) * config.dune_spacing * .15 +
        math.sin(along * .061 - seed_phase * .63) * config.dune_spacing * .05
    ridge_coordinate := inland_distance + warp + random01(config.seed, 1, 0x50484153) * config.dune_spacing
    cycle := ridge_coordinate / config.dune_spacing
    phase := cycle - f32(math.floor(f64(cycle)))
    crest := .70 + config.wind_strength * .08
    profile: f32
    if phase < crest {
        profile = f32(math.pow(f64(phase / crest), 1.55))
    } else {
        // Keep the short lee face steep at the crest but ease it smoothly into
        // the trough. Exponents below one have an unbounded derivative at zero,
        // which rasterizes as punctures and razor-thin cliff seams.
        profile = f32(math.pow(f64(1 - (phase - crest) / (1 - crest)), 1.15))
    }
    ridge_index := u32(max(0, int(math.floor(f64(cycle)))))
    variation := .8 + random01(config.seed, ridge_index, 0x52494447) * .28
    surface_texture :=
        1 +
        math.sin(along * .11 + inland_distance * .067 + seed_phase * 1.3) * .055 +
        math.sin(along * -.047 + inland_distance * .17 - seed_phase * .72) * .025
    ridge_scale := min(variation * surface_texture, f32(1.045))
    pocket_field :=
        math.sin(along * .032 + inland_distance * .021 + seed_phase) *
        math.sin(along * .014 - inland_distance * .049 - seed_phase * .8)
    pocket_blowout := smooth((pocket_field - .43) / .36) * (.12 + config.wind_strength * .20)

    // Sparse wind-aligned corridors connect upper beach sand to the interior
    // dune belt. Each channel meanders gently alongshore but remains coherent
    // across multiple ridges, unlike the isolated two-dimensional pockets.
    channel_spacing := 96 + random01(config.seed, 3, 0x42535043) * 42
    channel_offset := random01(config.seed, 4, 0x424f4646) * channel_spacing
    channel_meander :=
        math.sin(inland_distance * .046 + seed_phase * .53) * 7 +
        math.sin(inland_distance * .113 - seed_phase * .29) * 2.5
    channel_cycle := (along + channel_offset + channel_meander) / channel_spacing
    channel_index_signed := int(math.floor(f64(channel_cycle)))
    channel_phase := channel_cycle - f32(channel_index_signed)
    channel_index := u32(abs(channel_index_signed))
    channel_half_width := 4.5 + random01(config.seed, channel_index, 0x42574944) * 4
    channel_distance := abs(channel_phase - .5) * channel_spacing
    channel_shape := 1 - smooth((channel_distance - channel_half_width) / (channel_half_width * .85))
    channel_presence := smooth((random01(config.seed, channel_index, 0x424f5554) - .40) / .24)
    channel_inland_gate :=
        smooth(inland_distance / 11) *
        (1 - smooth((inland_distance - config.dune_width * .82) / (config.dune_width * .16)))
    channel_blowout := channel_shape * channel_presence * channel_inland_gate * (.34 + config.wind_strength * .42)
    blowout := max(pocket_blowout, channel_blowout)
    ridge_depth := smooth((inland_distance - 18) / (config.dune_width * .60))
    ridge_sequence := 1.03 - ridge_depth * .12
    height := max(
        f32(0),
        profile * config.dune_height * ridge_scale * ridge_sequence * (1 - blowout) * height_envelope,
    )

    lee_progress := phase >= crest ? (phase - crest) / max(f32(.04), 1 - crest) : 0
    slip_face := smooth(lee_progress / .34) * (1 - smooth((lee_progress - .72) / .28))
    crest_band := 1 - smooth(abs(phase - crest) / .21)
    maturity := smooth((inland_distance - 12) / (config.dune_width * .55))
    patch_cross :=
        math.sin(along * .019 + inland_distance * .043 + seed_phase * .37) *
        math.sin(along * -.051 + inland_distance * .017 - seed_phase * .61)
    patch :=
        .64 +
        math.sin(along * .073 + seed_phase) * .14 +
        math.sin(along * .031 - inland_distance * .057) * .10 +
        patch_cross * .20
    blowout_stability := 1 - blowout
    stability := clamp01(
        (.3 + crest_band * .56 + maturity * .35) * (1 - slip_face * .88) * blowout_stability * blowout_stability,
    )
    exposure := clamp01(.24 + slip_face * .73 + (1 - maturity) * .24 + blowout * .5)
    grass := clamp01(config.vegetation_strength * stability * clamp01(patch) * shore_fade * site)
    return {
        height_delta = height,
        coverage = envelope,
        sand_weight = clamp01(1 - grass * .74),
        grass_suitability = grass,
        exposure = exposure,
        stability = stability,
        blowout = blowout,
        inside = envelope > .0001,
    }
}

generate :: proc(requested: Config) -> Plan {
    config := requested
    config.length = max(config.length, f32(1))
    config.width = max(config.width, f32(1))
    config.dune_height = max(config.dune_height, f32(0))
    config.dune_spacing = max(config.dune_spacing, f32(4))
    config.wind_strength = clamp01(config.wind_strength)
    config.vegetation_strength = clamp01(config.vegetation_strength)
    if config.shore_fade <= 0 do config.shore_fade = 12
    if config.inland_fade <= 0 do config.inland_fade = 28
    config.shore_fade = clamp(config.shore_fade, f32(1), config.width * .4)
    config.inland_fade = clamp(config.inland_fade, f32(1), config.width * .5)

    tangent := normalize_or(config.tangent, {1, 0})
    inland := normalize_or(config.inland, {-tangent[1], tangent[0]})
    // Re-orthogonalize the shoreline frame so callers can pass surveyed,
    // slightly noisy coast vectors without stretching the generated field.
    inland = normalize_or(
        inland - tangent * (inland[0] * tangent[0] + inland[1] * tangent[1]),
        {-tangent[1], tangent[0]},
    )
    wind := normalize_or(config.wind_direction, inland)
    step := f32(3.2)
    columns := max(1, int(math.ceil(f64(config.length / step))))
    rows := max(1, int(math.ceil(f64(config.width / step))))
    return {
        config = config,
        tangent = tangent,
        inland = inland,
        wind_along = wind[0] * tangent[0] + wind[1] * tangent[1],
        wind_inland = wind[0] * inland[0] + wind[1] * inland[1],
        phase_offset = random01(config.seed, 0, 0x50484153) * config.dune_spacing,
        warp_phase = random01(config.seed, 1, 0x57415250) * math.PI * 2,
        dune_count = int(math.ceil(f64(config.width / config.dune_spacing))) + 1,
        maximum_height = config.dune_height * 1.27,
        grass_grid_step = step,
        grass_columns = columns,
        grass_rows = rows,
        candidate_count = columns * rows,
    }
}

local_coordinates :: #force_inline proc(plan: ^Plan, position: Vec2) -> (along, inland: f32) {
    offset := position - plan.config.anchor
    return offset[0] * plan.tangent[0] + offset[1] * plan.tangent[1],
        offset[0] * plan.inland[0] + offset[1] * plan.inland[1]
}

sample :: proc(plan: ^Plan, position: Vec2) -> Sample {
    if plan == nil do return {}
    along, inland_distance := local_coordinates(plan, position)
    half_length := plan.config.length * .5
    if abs(along) >= half_length || inland_distance <= 0 || inland_distance >= plan.config.width do return {}

    lateral_fade := smooth((half_length - abs(along)) / min(f32(26), half_length))
    shore_fade := smooth(inland_distance / plan.config.shore_fade)
    inland_fade := smooth((plan.config.width - inland_distance) / plan.config.inland_fade)
    envelope := lateral_fade * shore_fade * inland_fade

    warp :=
        math.sin(along * .024 + plan.warp_phase) * plan.config.dune_spacing * .16 +
        math.sin(along * .061 - plan.warp_phase * .73) * plan.config.dune_spacing * .055
    oblique := along * plan.wind_along * (.12 + plan.config.wind_strength * .13)
    ridge_coordinate := inland_distance + warp + oblique + plan.phase_offset
    cycle := ridge_coordinate / plan.config.dune_spacing
    phase := cycle - f32(math.floor(f64(cycle)))

    // Most of the cycle is a long windward climb; the short remainder is the
    // sharper lee slip face. Stronger onshore wind increases that asymmetry.
    crest := .70 + plan.config.wind_strength * .08
    profile: f32
    if phase < crest {
        profile = f32(math.pow(f64(phase / crest), 1.55))
    } else {
        profile = f32(math.pow(f64(1 - (phase - crest) / (1 - crest)), 1.15))
    }
    ridge_index := u32(max(0, int(math.floor(f64(cycle)))))
    ridge_variation := .78 + random01(plan.config.seed, ridge_index, 0x52494447) * .34
    secondary := .88 + math.sin(along * .043 + f32(ridge_index) * 1.71) * .12

    blowout_field :=
        math.sin(along * .031 + inland_distance * .019 + plan.warp_phase * 1.7) *
        math.sin(along * .013 - inland_distance * .047 - plan.warp_phase)
    blowout := smooth((blowout_field - .42) / .38) * (.18 + plan.config.wind_strength * .34)
    height := max(f32(0), profile * plan.config.dune_height * ridge_variation * secondary * (1 - blowout) * envelope)

    lee_progress := phase >= crest ? (phase - crest) / max(f32(.04), 1 - crest) : 0
    slip_face := smooth(lee_progress / .34) * (1 - smooth((lee_progress - .72) / .28))
    crest_distance := abs(phase - crest)
    crest_band := 1 - smooth(crest_distance / .20)
    inland_maturity := smooth((inland_distance - plan.config.shore_fade * .7) / (plan.config.width * .48))
    patch :=
        .64 + math.sin(along * .071 + plan.warp_phase) * .19 + math.sin(along * .029 - inland_distance * .053) * .17
    stability := clamp01(
        (.34 + crest_band * .54 + inland_maturity * .32) * (1 - slip_face * .88) * (1 - blowout * .92),
    )
    exposure := clamp01(.26 + slip_face * .72 + (1 - inland_maturity) * .24 + blowout * .55)
    grass := clamp01(plan.config.vegetation_strength * stability * clamp01(patch) * shore_fade * lateral_fade)

    return {
        height_delta = height,
        coverage = envelope,
        sand_weight = clamp01(1 - grass * .74),
        grass_suitability = grass,
        exposure = exposure,
        stability = stability,
        inside = envelope > .0001,
    }
}

grass_candidate :: proc(plan: ^Plan, index: int) -> (Grass_Candidate, bool) {
    if plan == nil || index < 0 || index >= plan.candidate_count do return {}, false
    column := index % plan.grass_columns
    row := index / plan.grass_columns
    jitter_x := (random01(plan.config.seed, u32(index), 0x475258) - .5) * plan.grass_grid_step * .82
    jitter_z := (random01(plan.config.seed, u32(index), 0x47525a) - .5) * plan.grass_grid_step * .82
    along := -plan.config.length * .5 + (f32(column) + .5) * plan.grass_grid_step + jitter_x
    inland_distance := (f32(row) + .5) * plan.grass_grid_step + jitter_z
    position := plan.config.anchor + plan.tangent * along + plan.inland * inland_distance
    surface := sample(plan, position)
    acceptance := random01(plan.config.seed, u32(index), 0x47524153)
    density := surface.grass_suitability * .78
    if !surface.inside || density <= 0 || acceptance > density do return {}, false
    scale := random01(plan.config.seed, u32(index), 0x48454947)
    height := .28 + scale * .48
    return {
            position = position,
            density = density,
            height = height,
            width = height * (.48 + random01(plan.config.seed, u32(index), 0x57494454) * .18),
            tile = int(hash(plan.config.seed + u32(index) * 17) % 16),
            tint = random01(plan.config.seed, u32(index), 0x54494e54),
        },
        true
}
