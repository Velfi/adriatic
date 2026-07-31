package cemeteries

MAX_GRAVES :: 128
MAX_TREES :: 20

Style :: enum u8 {
    Adriatic_Medieval,
    Classical_Aegean,
    Churchyard,
    Memorial_Garden,
}

Marker_Kind :: enum u8 {
    Stele,
    Cross,
    Slab,
    Pillar,
    Plaque,
    Chest,
    Gabled,
}

Relief_Kind :: enum u8 {
    Geometric_Border,
    Cross,
    Solar_Rosette,
    Arcade,
    Sword,
    Round_Dance,
    Palmette,
    Wreath,
    Farewell_Panel,
    Amphora,
}

Memorial_Kind :: enum u8 {
    Obelisk,
    Cross,
    Stele,
    Shrine,
}

Grave :: struct {
    x, z:             f32,
    ground_y:         f32,
    rotation:         f32,
    width:            f32,
    height:           f32,
    depth:            f32,
    base_width:       f32,
    base_height:      f32,
    marker:           Marker_Kind,
    profile:          u8,
    inscription:      u8,
    relief:           Relief_Kind,
    stone_variant:    u8,
    has_inscription:  bool,
    has_relief:       bool,
    has_base:         bool,
    pigment:          u8,
    pigment_strength: f32,
    weathering:       f32,
}

Tree :: struct {
    x, z:   f32,
    height: f32,
    radius: f32,
}

Memorial :: struct {
    kind:          Memorial_Kind,
    x, z:          f32,
    rotation:      f32,
    scale:         f32,
    height:        f32,
    base_width:    f32,
    court_radius:  f32,
    step_count:    int,
    inscription:   u8,
    weathering:    f32,
    flanking_urns: bool,
}

Config :: struct {
    width:             f32,
    depth:             f32,
    density:           f32,
    style:             Style,
    memorial_kind:     Memorial_Kind,
    memorial_explicit: bool,
}

Plan :: struct {
    seed:        u32,
    width:       f32,
    depth:       f32,
    wall_height: f32,
    path_width:  f32,
    gate_width:  f32,
    style:       Style,
    graves:      [MAX_GRAVES]Grave,
    grave_count: int,
    trees:       [MAX_TREES]Tree,
    tree_count:  int,
    memorial:    Memorial,
    valid:       bool,
}

mix :: proc(value: u32) -> u32 {
    result := (value ~ (value >> 16)) * u32(0x7feb352d)
    result = (result ~ (result >> 15)) * u32(0x846ca68b)
    return result ~ (result >> 16)
}

unit :: proc(value: u32) -> f32 {
    return f32(mix(value) & 0xffff) / f32(0xffff)
}

defaults :: proc() -> Config {
    return {width = 24, depth = 30, density = .72, style = .Adriatic_Medieval}
}

style_supports_marker :: proc(style: Style, marker: Marker_Kind) -> bool {
    switch style {
    case .Adriatic_Medieval:
        return marker == .Slab || marker == .Chest || marker == .Gabled || marker == .Pillar || marker == .Cross
    case .Classical_Aegean:
        return marker == .Stele || marker == .Pillar || marker == .Slab
    case .Churchyard:
        return marker == .Stele || marker == .Cross || marker == .Pillar || marker == .Slab
    case .Memorial_Garden:
        return marker == .Stele || marker == .Cross || marker == .Slab || marker == .Pillar || marker == .Plaque
    }
    return false
}

style_supports_relief :: proc(style: Style, relief: Relief_Kind) -> bool {
    switch style {
    case .Adriatic_Medieval:
        return relief <= .Round_Dance
    case .Classical_Aegean:
        return relief >= .Palmette
    case .Churchyard, .Memorial_Garden:
        return false
    }
    return false
}

generate :: proc(seed: u32, requested: Config) -> Plan {
    config := requested
    config.width = clamp(config.width, f32(12), f32(42))
    config.depth = clamp(config.depth, f32(14), f32(50))
    config.density = clamp(config.density, f32(.2), f32(1))

    memorial_hash := mix(seed ~ 0x91e10da5)
    memorial_kind := config.memorial_kind
    if !config.memorial_explicit {
        roll := int(memorial_hash % 8)
        switch config.style {
        case .Adriatic_Medieval:
            memorial_kind = roll < 3 ? .Obelisk : (roll < 6 ? .Shrine : .Cross)
        case .Classical_Aegean:
            memorial_kind = roll < 5 ? .Stele : .Obelisk
        case .Churchyard:
            memorial_kind = roll < 4 ? .Cross : (roll < 7 ? .Shrine : .Obelisk)
        case .Memorial_Garden:
            memorial_kind = roll < 4 ? .Stele : (roll < 7 ? .Obelisk : .Cross)
        }
    }
    memorial_scale := .9 + unit(memorial_hash ~ 0x68bc21eb) * .3
    memorial_height := f32(3.2)
    #partial switch memorial_kind {
    case .Obelisk:
        memorial_height = 3.8
    case .Cross:
        memorial_height = 3.35
    case .Stele:
        memorial_height = 2.45
    case .Shrine:
        memorial_height = 3.15
    }
    memorial_base_width := (memorial_kind == .Shrine ? f32(2.7) : f32(2.15)) * memorial_scale
    memorial_court_radius := (memorial_kind == .Shrine ? f32(3.25) : f32(2.75)) * memorial_scale
    plan := Plan {
        seed = seed,
        width = config.width,
        depth = config.depth,
        style = config.style,
        path_width = config.style == .Memorial_Garden ? 2.6 : 2.1,
        gate_width = config.style == .Churchyard ? 3.2 : 2.8,
        wall_height = config.style == .Adriatic_Medieval ? 1.05 : .72,
        memorial = {
            kind = memorial_kind,
            x = 0,
            z = config.depth * .5 - memorial_court_radius - .65,
            rotation = 0,
            scale = memorial_scale,
            height = memorial_height * memorial_scale,
            base_width = memorial_base_width,
            court_radius = memorial_court_radius,
            step_count = 1 + int((memorial_hash >> 8) % 3),
            inscription = u8((memorial_hash >> 16) % 4),
            weathering = unit(memorial_hash ~ 0xc2b2ae35),
            flanking_urns = memorial_kind != .Cross && (memorial_hash >> 24) & 1 == 1,
        },
    }

    grave_spacing_x := config.style == .Memorial_Garden ? f32(2.45) : f32(2.15)
    grave_spacing_z := config.style == .Churchyard ? f32(2.55) : f32(2.35)
    columns := max(2, int((config.width * .5 - plan.path_width * .5 - 1.2) / grave_spacing_x))
    rows := max(2, int((config.depth - 5.5) / grave_spacing_z))
    candidate := 0
    for row in 0 ..< rows {
        z := -config.depth * .5 + 3.0 + f32(row) * grave_spacing_z
        for side in -1 ..= 1 {
            if side == 0 do continue
            for column in 0 ..< columns {
                hash := mix(seed + u32(candidate) * 0x9e3779b9)
                candidate += 1
                if unit(hash) > config.density do continue
                if plan.grave_count >= MAX_GRAVES do break
                jitter_x := (unit(hash ~ 0x68bc21eb) - .5) * .28
                jitter_z := (unit(hash ~ 0x02e5be93) - .5) * .32
                x := f32(side) * (plan.path_width * .5 + 1.05 + f32(column) * grave_spacing_x) + jitter_x
                grave_z := z + jitter_z
                memorial_dx := x - plan.memorial.x
                memorial_dz := grave_z - plan.memorial.z
                if memorial_dx * memorial_dx + memorial_dz * memorial_dz <
                   plan.memorial.court_radius * plan.memorial.court_radius {
                    continue
                }
                marker_roll := int((hash >> 16) % 16)
                marker := Marker_Kind.Stele
                switch config.style {
                case .Adriatic_Medieval:
                    if marker_roll < 6 {
                        marker = .Slab
                    } else if marker_roll < 12 {
                        marker = .Chest
                    } else if marker_roll < 14 {
                        marker = .Gabled
                    } else if marker_roll == 14 {
                        marker = .Pillar
                    } else {
                        marker = .Cross
                    }
                case .Classical_Aegean:
                    if marker_roll < 10 {
                        marker = .Stele
                    } else if marker_roll < 14 {
                        marker = .Pillar
                    } else {
                        marker = .Slab
                    }
                case .Churchyard:
                    if marker_roll < 2 {
                        marker = .Cross
                    } else if marker_roll == 2 {
                        marker = .Pillar
                    } else if marker_roll == 3 {
                        marker = .Slab
                    }
                case .Memorial_Garden:
                    if marker_roll < 5 {
                        marker = .Slab
                    } else if marker_roll < 9 {
                        marker = .Plaque
                    } else if marker_roll == 9 {
                        marker = .Pillar
                    } else if marker_roll == 10 {
                        marker = .Cross
                    }
                }
                width := .58 + unit(hash ~ 0x63d83595) * .22
                height := .72 + unit(hash ~ 0xc2b2ae35) * .48
                depth := .18 + unit(hash ~ 0x165667b1) * .08
                if marker == .Pillar {
                    width = .38 + unit(hash ~ 0x63d83595) * .16
                    height = 1.18 + unit(hash ~ 0xc2b2ae35) * .55
                    depth = width
                } else if marker == .Plaque {
                    width = .72 + unit(hash ~ 0x63d83595) * .26
                    height = .34 + unit(hash ~ 0xc2b2ae35) * .22
                    depth = .18 + unit(hash ~ 0x165667b1) * .08
                } else if marker == .Slab {
                    width = .68 + unit(hash ~ 0x63d83595) * .24
                    height = .22 + unit(hash ~ 0xc2b2ae35) * .15
                    depth = 1.25 + unit(hash ~ 0x165667b1) * .55
                } else if marker == .Chest || marker == .Gabled {
                    width = .82 + unit(hash ~ 0x63d83595) * .34
                    height =
                        marker == .Gabled ? f32(.72) + unit(hash ~ 0xc2b2ae35) * .34 : f32(.48) + unit(hash ~ 0xc2b2ae35) * .30
                    depth = 1.45 + unit(hash ~ 0x165667b1) * .62
                }
                base_width := width * (1.14 + unit(hash ~ 0x85ebca6b) * .18)
                plan.graves[plan.grave_count] = {
                    x                = x,
                    z                = grave_z,
                    rotation         = (unit(hash ~ 0xa511e9b3) -
                        .5) * (config.style == .Churchyard ? f32(.10) : f32(.035)),
                    width            = width,
                    height           = height,
                    depth            = depth,
                    base_width       = base_width,
                    base_height      = .08 + unit(hash ~ 0xd3a2646c) * .08,
                    marker           = marker,
                    profile          = u8((hash >> 20) % 4),
                    inscription      = u8((hash >> 22) % 4),
                    relief           = config.style == .Classical_Aegean ? Relief_Kind(int(Relief_Kind.Palmette) + int((hash >> 18) % 4)) : Relief_Kind((hash >> 18) % 6),
                    stone_variant    = config.style == .Adriatic_Medieval ? 2 : u8((hash >> 25) % 4),
                    has_inscription  = config.style == .Classical_Aegean ? (hash >> 28) & 3 != 0 : (config.style == .Adriatic_Medieval ? (hash >> 28) & 7 == 0 : (hash >> 28) & 1 == 0),
                    has_relief       = config.style == .Adriatic_Medieval ? (hash >> 27) & 3 != 0 : (config.style == .Classical_Aegean ? (hash >> 27) & 1 == 0 : false),
                    has_base         = config.style == .Adriatic_Medieval ? (hash >> 26) & 3 == 0 : true,
                    pigment          = u8((hash >> 24) % 4),
                    pigment_strength = config.style == .Classical_Aegean ? .10 + unit(hash ~ 0x94d049bb) * .24 : 0,
                    weathering       = unit(hash ~ 0x27d4eb2f),
                }
                plan.grave_count += 1
            }
        }
    }

    desired_trees := clamp(int((config.width + config.depth) / 8), 4, MAX_TREES)
    for index in 0 ..< desired_trees {
        hash := mix(seed ~ (u32(index) * 0x85ebca6b + 0x165667b1))
        along_side := index & 1 == 0
        if along_side {
            side := index & 2 == 0 ? f32(-1) : f32(1)
            plan.trees[index].x = side * (config.width * .5 - .9)
            plan.trees[index].z = (unit(hash) - .5) * (config.depth - 5)
        } else {
            plan.trees[index].x = (unit(hash) - .5) * (config.width - 4)
            plan.trees[index].z = config.depth * .5 - 1.1
        }
        plan.trees[index].height = 3.8 + unit(hash ~ 0x9e3779b9) * 2.8
        plan.trees[index].radius = .48 + unit(hash ~ 0x7f4a7c15) * .35
    }
    plan.tree_count = desired_trees
    plan.valid = validate(&plan)
    return plan
}

validate :: proc(plan: ^Plan) -> bool {
    if plan == nil || plan.width < 12 || plan.width > 42 || plan.depth < 14 || plan.depth > 50 do return false
    if plan.path_width <= 0 || plan.path_width >= plan.width * .4 do return false
    if plan.gate_width <= plan.path_width || plan.gate_width >= plan.width * .5 do return false
    if plan.memorial.scale <= 0 || plan.memorial.height <= 0 || plan.memorial.base_width <= 0 do return false
    if plan.memorial.court_radius <= plan.memorial.base_width * .5 do return false
    if abs(plan.memorial.x) + plan.memorial.court_radius >= plan.width * .5 do return false
    if abs(plan.memorial.z) + plan.memorial.court_radius >= plan.depth * .5 + .01 do return false
    if plan.memorial.step_count < 1 || plan.memorial.step_count > 3 do return false
    if plan.grave_count < 0 || plan.grave_count > MAX_GRAVES do return false
    if plan.tree_count < 0 || plan.tree_count > MAX_TREES do return false
    for grave in plan.graves[:plan.grave_count] {
        if abs(grave.x) <= plan.path_width * .5 do return false
        if abs(grave.x) >= plan.width * .5 || abs(grave.z) >= plan.depth * .5 do return false
        if grave.width <= 0 || grave.height <= 0 || grave.depth <= 0 do return false
        if grave.base_width < grave.width || grave.base_height <= 0 do return false
        if grave.profile > 3 || grave.inscription > 3 || grave.relief > .Amphora || grave.stone_variant > 3 do return false
        if grave.pigment > 3 || grave.pigment_strength < 0 || grave.pigment_strength > .35 do return false
        if !style_supports_marker(plan.style, grave.marker) do return false
        if grave.has_relief && !style_supports_relief(plan.style, grave.relief) do return false
        dx := grave.x - plan.memorial.x
        dz := grave.z - plan.memorial.z
        if dx * dx + dz * dz < plan.memorial.court_radius * plan.memorial.court_radius do return false
    }
    for tree in plan.trees[:plan.tree_count] {
        if abs(tree.x) >= plan.width * .5 || abs(tree.z) >= plan.depth * .5 do return false
        if tree.height <= 0 || tree.radius <= 0 do return false
    }
    return true
}
