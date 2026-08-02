package bridges

MAX_SPANS :: 12
MAX_PIERS :: MAX_SPANS - 1

Region :: enum u8 {Adriatic, Aegean, Later_Era}

Archetype :: enum u8 {
    Dalmatian_Multi_Arch,
    Herzegovinian_High_Arch,
    Venetian_Canal,
    Cycladic_Rural,
    Aegean_Fortress,
    Timber_Trestle,
    Iron_Truss,
}

Material :: enum u8 {Limestone, Travertine, Istrian_Stone, Slate, Fieldstone, Timber, Iron}
Construction :: enum u8 {Dry_Stone, Lime_Mortared, Dressed_Masonry, Framed}
Arch_Shape :: enum u8 {Semicircular, Segmental, Slightly_Pointed}
Deck_Profile :: enum u8 {Level, Crowned, Humpback, Stepped}
Parapet :: enum u8 {Solid, Low_Irregular, Balustrade, Rail}

Config :: struct {
    region:             Region,
    archetype:          Archetype,
    length:             f32,
    width:              f32,
    clearance:          f32,
    span_count:         int,
    material:           Material,
    construction:       Construction,
    arch_shape:         Arch_Shape,
    deck_profile:       Deck_Profile,
    parapet:            Parapet,
    pier_cutwaters:     bool,
    approach_steps:     bool,
    fortified_end:      bool,
    urban_shops:        bool,
}

Pier :: struct {station, width, batter: f32}

Plan :: struct {
    seed:               u32,
    region:             Region,
    archetype:          Archetype,
    material:           Material,
    construction:       Construction,
    arch_shape:         Arch_Shape,
    deck_profile:       Deck_Profile,
    parapet:            Parapet,
    length:             f32,
    width:              f32,
    clearance:          f32,
    deck_thickness:     f32,
    parapet_height:     f32,
    parapet_width:      f32,
    span_length:        f32,
    primary_span_ratio: f32,
    arch_rise:          f32,
    deck_rise:          f32,
    truss_height:       f32,
    cross_brace_count:  int,
    piers:              [MAX_PIERS]Pier,
    pier_count:         int,
    pier_cutwaters:     bool,
    approach_steps:     bool,
    fortified_end:      bool,
    urban_shops:        bool,
    dressed_arch_ring:  bool,
    masonry_variation:  f32,
    valid:              bool,
}

mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

defaults :: proc(archetype: Archetype = .Dalmatian_Multi_Arch) -> Config {
    switch archetype {
    case .Dalmatian_Multi_Arch:
        return {region=.Adriatic, archetype=archetype, length=42, width=3.8, clearance=4.2, span_count=8, material=.Travertine, construction=.Dry_Stone, arch_shape=.Segmental, deck_profile=.Crowned, parapet=.Solid, pier_cutwaters=true}
    case .Herzegovinian_High_Arch:
        return {region=.Adriatic, archetype=archetype, length=30, width=4.0, clearance=10.5, span_count=1, material=.Limestone, construction=.Lime_Mortared, arch_shape=.Slightly_Pointed, deck_profile=.Humpback, parapet=.Solid}
    case .Venetian_Canal:
        return {region=.Adriatic, archetype=archetype, length=24, width=5.4, clearance=5.2, span_count=1, material=.Istrian_Stone, construction=.Dressed_Masonry, arch_shape=.Segmental, deck_profile=.Stepped, parapet=.Balustrade, approach_steps=true}
    case .Cycladic_Rural:
        return {region=.Aegean, archetype=archetype, length=15, width=2.8, clearance=4.0, span_count=1, material=.Fieldstone, construction=.Dry_Stone, arch_shape=.Semicircular, deck_profile=.Humpback, parapet=.Low_Irregular}
    case .Aegean_Fortress:
        return {region=.Aegean, archetype=archetype, length=19, width=3.0, clearance=7.0, span_count=1, material=.Slate, construction=.Lime_Mortared, arch_shape=.Semicircular, deck_profile=.Stepped, parapet=.Solid, approach_steps=true, fortified_end=true}
    case .Timber_Trestle:
        return {region=.Later_Era, archetype=archetype, length=28, width=5.2, clearance=6, span_count=3, material=.Timber, construction=.Framed, arch_shape=.Segmental, deck_profile=.Level, parapet=.Rail}
    case .Iron_Truss:
        return {region=.Later_Era, archetype=archetype, length=34, width=5.2, clearance=6, span_count=2, material=.Iron, construction=.Framed, arch_shape=.Segmental, deck_profile=.Level, parapet=.Rail}
    }
    return {}
}

generate :: proc(seed: u32, requested: Config) -> Plan {
    config := requested
    config.length = clamp(config.length, f32(10), f32(80))
    config.width = clamp(config.width, f32(2.2), f32(10))
    config.clearance = clamp(config.clearance, f32(2.5), f32(16))
    config.span_count = clamp(config.span_count, 1, MAX_SPANS)
    if config.archetype == .Herzegovinian_High_Arch || config.archetype == .Venetian_Canal ||
       config.archetype == .Cycladic_Rural || config.archetype == .Aegean_Fortress {
        config.span_count = 1
    }
    variation := f32(mix(seed) & 255) / 255
    span_length := config.length / f32(config.span_count)
    primary_ratio := f32(1)
    if config.archetype == .Dalmatian_Multi_Arch do primary_ratio = .92 + variation * .16
    deck_rise := f32(0)
    switch config.deck_profile {
    case .Crowned: deck_rise = .18 + variation * .12
    case .Humpback: deck_rise = clamp(config.length * .075, f32(.8), f32(2.8))
    case .Stepped: deck_rise = clamp(config.length * .055, f32(.65), f32(1.8))
    case .Level:
    }
    framed := config.construction == .Framed
    plan := Plan {
        seed = seed,
        region = config.region,
        archetype = config.archetype,
        material = config.material,
        construction = config.construction,
        arch_shape = config.arch_shape,
        deck_profile = config.deck_profile,
        parapet = config.parapet,
        length = config.length,
        width = config.width,
        clearance = config.clearance,
        deck_thickness = framed ? f32(.42) : f32(.58 + variation * .14),
        parapet_height = config.parapet == .Low_Irregular ? f32(.48 + variation*.12) : (config.parapet == .Rail ? f32(.18) : f32(.78)),
        parapet_width = config.parapet == .Balustrade ? f32(.22) : (config.parapet == .Rail ? f32(.16) : f32(.28)),
        span_length = span_length,
        primary_span_ratio = primary_ratio,
        arch_rise = min(config.clearance * f32(.88), span_length * (config.arch_shape == .Segmental ? f32(.34) : f32(.49))),
        deck_rise = deck_rise,
        truss_height = clamp(span_length * f32(.30), f32(2.2), f32(5.5)),
        cross_brace_count = clamp(int(span_length / 2.2), 3, 10),
        pier_count = config.span_count - 1,
        pier_cutwaters = config.pier_cutwaters,
        approach_steps = config.approach_steps,
        fortified_end = config.fortified_end,
        urban_shops = config.urban_shops,
        dressed_arch_ring = config.construction == .Dressed_Masonry || config.construction == .Lime_Mortared,
        masonry_variation = config.construction == .Dry_Stone ? f32(.16 + variation*.10) : f32(.035 + variation*.035),
    }
    for index in 0 ..< plan.pier_count {
        pier_variation := f32(mix(seed + u32(index) * 0x9e3779b9) & 255) / 255
        plan.piers[index] = {
            station = -config.length*.5 + span_length*f32(index+1),
            width = clamp(span_length*(.13 + pier_variation*.025), f32(.72), f32(2.0)),
            batter = .10 + pier_variation*.06,
        }
    }
    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil || plan.length < 10 || plan.length > 80 do return false
    if plan.width < 2.2 || plan.width > 10 || plan.clearance < 2.5 || plan.clearance > 16 do return false
    if plan.pier_count < 0 || plan.pier_count >= MAX_SPANS do return false
    if plan.span_length <= 0 || plan.deck_thickness <= 0 || plan.arch_rise <= 0 do return false
    if plan.region == .Aegean && plan.width > 4.5 do return false
    if plan.urban_shops && plan.archetype != .Venetian_Canal do return false
    previous := -plan.length*.5
    for pier in plan.piers[:plan.pier_count] {
        if pier.station <= previous || pier.station >= plan.length*.5 || pier.width <= 0 do return false
        previous = pier.station
    }
    return true
}
