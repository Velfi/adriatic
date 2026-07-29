package ruins

import "core:math"

BUILDING_CAPACITY :: 12
PROP_CAPACITY :: 320
PATH_CAPACITY :: 16
ROUTE_CAPACITY :: 48
FEATURE_CAPACITY :: 4
ENCLOSURE_CAPACITY :: 8
DRAINAGE_CAPACITY :: 2
PRECINCT_CAPACITY :: 2

Vec2 :: struct {
    x, z: f32,
}

Mode :: enum u8 {
    Ruin,
    Complex,
}

Culture :: enum u8 {
    Aegean,
    Roman,
    Minoan,
}

Terrain_Profile :: enum u8 {
    Flat,
    Incline,
    Terraced,
}

Preservation :: enum u8 {
    Preserved,
    Weathered,
    Collapsed,
}

Pottery_Density :: enum u8 {
    Typical,
    Sparse,
    Abundant,
}

Complex_Scale :: enum u8 {
    Standard,
    Compact,
    Extensive,
}

Precinct_Layout :: enum u8 {
    Irregular_Temenos,
    Formal_Axis,
    Offset_Terraces,
}

Enclosure_Layout :: enum u8 {
    Irregular_Temenos,
    Rectilinear_Pomerium,
    Terraced_Peribolos,
}

Gateway_Kind :: enum u8 {
    Aegean_Propylon,
    Roman_Gatehouse,
    Minoan_Guardrooms,
}

Site :: struct {
    profile:        Terrain_Profile,
    slope_x:        f32,
    slope_z:        f32,
    terrace_height: f32,
}

Building_Kind :: enum u8 {
    Temple,
    Stoa,
    Shrine,
    House,
    Tomb,
    Basilica,
    Baths,
    Villa,
    Palace,
    Magazine,
}

Interior_Layout :: enum u8 {
    None,
    Cella,
    Aisled_Hall,
    Chambers,
    Domestic_Rooms,
    Courtyard,
    Magazines,
}

Colonnade_Layout :: enum u8 {
    None,
    Peristyle,
    Frontage,
    Nave_Aisles,
    Court,
}

Wall_Finish_Style :: enum u8 {
    None,
    Roman_Painted_Plaster,
    Minoan_Painted_Plaster,
}

Floor_Finish_Style :: enum u8 {
    Packed_Clay,
    Roman_Mosaic,
    Minoan_Gypsum_Plaster,
}

Occupation_Phase :: enum u8 {
    Founding,
    Expansion,
    Reoccupation,
}

Column_State :: enum u8 {
    Standing,
    Stump,
    Fallen,
}

Signature_Remain :: enum u8 {
    None,
    Basilica_Tribunal,
    Bath_Hypocaust,
    Palace_Grand_Stair,
    Magazine_Pithos_Beds,
}

Prop_Kind :: enum u8 {
    Pot,
    Amphora,
    Pithos,
    Dolium,
    Pottery_Sherds,
    Rubble,
    Fallen_Column,
    Tumbled_Wall,
    Masonry_Pile,
    Roof_Tile_Pile,
    Fallen_Timber,
    Mudbrick_Fall,
    Grass_Tuft,
    Scrub,
}

Site_Feature_Kind :: enum u8 {
    Altar_Platform,
    Cistern,
    Lustral_Basin,
}

Building :: struct {
    culture:          Culture,
    kind:             Building_Kind,
    center:           Vec2,
    width, depth:     f32,
    yaw:              f32,
    wall_height:      f32,
    base_y:           f32,
    damage:           f32,
    entrance_side:    int,
    interior_layout:  Interior_Layout,
    room_count:       int,
    colonnade_layout: Colonnade_Layout,
    column_count:     int,
    wall_finish:      Wall_Finish_Style,
    floor_finish:     Floor_Finish_Style,
    occupation_phase: Occupation_Phase,
    route_hub:        int,
    signature_remain: Signature_Remain,
    collapse_yaw:     f32,
    collapsed_sides:  u8,
    collapse_centers: [4]f32,
    seed:             u32,
}

Prop :: struct {
    kind:        Prop_Kind,
    position:    Vec2,
    yaw:         f32,
    scale:       f32,
    building:    int,
    detail_seed: u32,
}

Route_Segment :: struct {
    a, b:     Vec2,
    a_y, b_y: f32,
    width:    f32,
    building: int,
}

Site_Feature :: struct {
    kind:     Site_Feature_Kind,
    position: Vec2,
    base_y:   f32,
    yaw:      f32,
    scale:    f32,
}

Central_Court :: struct {
    center:       Vec2,
    width, depth: f32,
    base_y:       f32,
    yaw:          f32,
}

Enclosure_Segment :: struct {
    a, b:     Vec2,
    a_y, b_y: f32,
    width:    f32,
    height:   f32,
    seed:     u32,
}

Drainage_Kind :: enum u8 {
    Runoff_Gutter,
    Capped_Drain,
    Plaster_Channel,
}

Drainage_Channel :: struct {
    kind:     Drainage_Kind,
    a, b:     Vec2,
    a_y, b_y: f32,
    width:    f32,
    seed:     u32,
}

Gateway_Remain :: struct {
    kind:        Gateway_Kind,
    position:    Vec2,
    base_y:      f32,
    yaw:         f32,
    clear_width: f32,
    depth:       f32,
    seed:        u32,
}

Plan :: struct {
    seed:                 u32,
    mode:                 Mode,
    culture:              Culture,
    terrain_profile:      Terrain_Profile,
    preservation:         Preservation,
    pottery_density:      Pottery_Density,
    complex_scale:        Complex_Scale,
    precinct_layout:      Precinct_Layout,
    enclosure_layout:     Enclosure_Layout,
    buildings:            [BUILDING_CAPACITY]Building,
    building_count:       int,
    props:                [PROP_CAPACITY]Prop,
    prop_count:           int,
    path:                 [PATH_CAPACITY]Vec2,
    path_count:           int,
    routes:               [ROUTE_CAPACITY]Route_Segment,
    route_count:          int,
    features:             [FEATURE_CAPACITY]Site_Feature,
    feature_count:        int,
    court:                Central_Court,
    precincts:            [PRECINCT_CAPACITY]Central_Court,
    precinct_count:       int,
    enclosure:            [ENCLOSURE_CAPACITY]Enclosure_Segment,
    enclosure_count:      int,
    gateway:               Gateway_Remain,
    has_gateway:           bool,
    drainage:             [DRAINAGE_CAPACITY]Drainage_Channel,
    drainage_count:       int,
    extent:               f32,
    elevation_range:      f32,
    route_overlap_count:  int,
    relocated_prop_count: int,
    collapse_yaw:         f32,
    valid:                bool,
}

hash :: proc(value: u32) -> u32 {
    x := value
    x = x ~ (x >> 16)
    x *= 0x7feb352d
    x = x ~ (x >> 15)
    x *= 0x846ca68b
    x = x ~ (x >> 16)
    return x
}

random01 :: proc(seed: u32) -> f32 {
    return f32(hash(seed) & 0x00ffffff) / f32(0x01000000)
}

random_range :: proc(seed: u32, low, high: f32) -> f32 {
    return low + (high - low) * random01(seed)
}

preservation_name :: proc(preservation: Preservation) -> cstring {
    switch preservation {
    case .Preserved:
        return "PRESERVED"
    case .Weathered:
        return "WEATHERED"
    case .Collapsed:
        return "COLLAPSED"
    }
    return "WEATHERED"
}

pottery_density_name :: proc(density: Pottery_Density) -> cstring {
    switch density {
    case .Sparse:
        return "SPARSE"
    case .Typical:
        return "TYPICAL"
    case .Abundant:
        return "ABUNDANT"
    }
    return "TYPICAL"
}

pottery_density_factor :: proc(density: Pottery_Density) -> f32 {
    switch density {
    case .Sparse:
        return .55
    case .Typical:
        return 1
    case .Abundant:
        return 1.45
    }
    return 1
}

complex_scale_name :: proc(scale: Complex_Scale) -> cstring {
    switch scale {
    case .Standard:
        return "STANDARD"
    case .Compact:
        return "COMPACT"
    case .Extensive:
        return "EXTENSIVE"
    }
    return "STANDARD"
}

precinct_layout_name :: proc(layout: Precinct_Layout) -> cstring {
    switch layout {
    case .Irregular_Temenos:
        return "IRREGULAR TEMENOS"
    case .Formal_Axis:
        return "FORMAL AXIS"
    case .Offset_Terraces:
        return "OFFSET TERRACES"
    }
    return "IRREGULAR TEMENOS"
}

enclosure_layout_name :: proc(layout: Enclosure_Layout) -> cstring {
    switch layout {
    case .Irregular_Temenos:
        return "IRREGULAR BOUNDARY"
    case .Rectilinear_Pomerium:
        return "RECTILINEAR POMERIUM"
    case .Terraced_Peribolos:
        return "TERRACED PERIBOLOS"
    }
    return "IRREGULAR BOUNDARY"
}

gateway_kind_name :: proc(kind: Gateway_Kind) -> cstring {
    switch kind {
    case .Aegean_Propylon:
        return "AEGEAN PROPYLON"
    case .Roman_Gatehouse:
        return "ROMAN GATEHOUSE"
    case .Minoan_Guardrooms:
        return "MINOAN GUARDROOMS"
    }
    return "AEGEAN PROPYLON"
}

damage_for_preservation :: proc(seed: u32, preservation: Preservation) -> f32 {
    switch preservation {
    case .Preserved:
        return random_range(seed ~ 0xd4a6e, .12, .35)
    case .Weathered:
        return random_range(seed ~ 0xd4a6e, .28, .78)
    case .Collapsed:
        return random_range(seed ~ 0xd4a6e, .68, .92)
    }
    return .5
}

wall_finish_coverage :: proc(building: Building) -> f32 {
    if building.wall_finish == .None do return 0
    cultural_survival := building.wall_finish == .Minoan_Painted_Plaster ? f32(.78) : f32(.68)
    return clamp((1 - building.damage) * cultural_survival, f32(0), f32(1))
}

wall_finish_patch_survives :: proc(building: Building, side, segment: int) -> bool {
    if building.wall_finish == .None do return false
    salt := u32(side * 0x4f1 + segment * 0x91d) ~ 0xf17e5
    return random01(building.seed ~ salt) < wall_finish_coverage(building)
}

floor_finish_coverage :: proc(building: Building) -> f32 {
    resilience := f32(.58)
    if building.floor_finish == .Roman_Mosaic do resilience = .76
    if building.floor_finish == .Minoan_Gypsum_Plaster do resilience = .68
    return clamp(.14 + (1 - building.damage) * resilience, f32(.08), f32(.92))
}

floor_finish_panel_survives :: proc(building: Building, row, column: int) -> bool {
    salt := u32(row * 0x6d5 + column * 0xa91) ~ 0xf1002
    return random01(building.seed ~ salt) < floor_finish_coverage(building)
}

column_state :: proc(building: Building, index: int, painted: bool = false) -> Column_State {
    // Small colonnades still need legible collapse evidence. At severe damage,
    // reserve the first two positions as a fallen shaft and a rooted stump;
    // all remaining states retain their seeded distribution.
    if building.damage >= .78 && index == 0 do return .Fallen
    if building.damage >= .72 && index == 1 do return .Stump
    roll := random01(building.seed ~ u32(index) * 71)
    fallen_threshold := building.damage * (painted ? f32(.25) : f32(.31))
    stump_threshold := building.damage * (painted ? f32(.52) : f32(.60))
    if roll < fallen_threshold do return .Fallen
    if roll < stump_threshold do return .Stump
    return .Standing
}

kind_name :: proc(kind: Building_Kind) -> cstring {
    switch kind {
    case .Temple:
        return "TEMPLE"
    case .Stoa:
        return "STOA"
    case .Shrine:
        return "SHRINE"
    case .House:
        return "HOUSE"
    case .Tomb:
        return "TOMB"
    case .Basilica:
        return "BASILICA"
    case .Baths:
        return "BATHS"
    case .Villa:
        return "VILLA"
    case .Palace:
        return "PALACE"
    case .Magazine:
        return "MAGAZINE"
    }
    return "RUIN"
}

culture_name :: proc(culture: Culture) -> cstring {
    switch culture {
    case .Aegean:
        return "AEGEAN"
    case .Roman:
        return "ROMAN"
    case .Minoan:
        return "MINOAN"
    }
    return "ANCIENT"
}

terrain_name :: proc(profile: Terrain_Profile) -> cstring {
    switch profile {
    case .Flat:
        return "FLAT"
    case .Incline:
        return "INCLINE"
    case .Terraced:
        return "TERRACED"
    }
    return "SITE"
}

default_site :: proc(profile: Terrain_Profile) -> Site {
    site := Site {
        profile = profile,
    }
    switch profile {
    case .Flat:
    case .Incline:
        site.slope_x, site.slope_z = .055, .035
    case .Terraced:
        site.slope_x, site.slope_z = .07, .045
        site.terrace_height = 1.25
    }
    return site
}

site_height :: proc(site: Site, position: Vec2) -> f32 {
    raw := position.x * site.slope_x + position.z * site.slope_z
    if site.profile == .Terraced && site.terrace_height > 0 {
        return f32(math.round(raw / site.terrace_height)) * site.terrace_height
    }
    return raw
}

mode_name :: proc(mode: Mode) -> cstring {
    return mode == .Complex ? "COMPLEX" : "SINGLE RUIN"
}

local_to_world :: proc(building: Building, local: Vec2) -> Vec2 {
    cosine, sine := math.cos(building.yaw), math.sin(building.yaw)
    return {
        building.center.x + local.x * cosine - local.z * sine,
        building.center.z + local.x * sine + local.z * cosine,
    }
}

wall_outward_world :: proc(building: Building, wall: int) -> Vec2 {
    local := Vec2{}
    switch wall {
    case 0:
        local = {0, -1}
    case 1:
        local = {1, 0}
    case 2:
        local = {0, 1}
    case 3:
        local = {-1, 0}
    }
    cosine, sine := math.cos(building.yaw), math.sin(building.yaw)
    return {
        local.x * cosine - local.z * sine,
        local.x * sine + local.z * cosine,
    }
}

preferred_collapse_wall :: proc(building: Building) -> int {
    direction := Vec2{math.cos(building.collapse_yaw), math.sin(building.collapse_yaw)}
    preferred, best_dot := 0, f32(-2)
    for wall in 0 ..< 4 {
        outward := wall_outward_world(building, wall)
        dot := outward.x * direction.x + outward.z * direction.z
        if dot > best_dot do preferred, best_dot = wall, dot
    }
    return preferred
}

collapse_wall_for_index :: proc(building: Building, index: int) -> int {
    direction := Vec2{math.cos(building.collapse_yaw), math.sin(building.collapse_yaw)}
    used := [4]bool{}
    for rank in 0 ..< 3 {
        best_wall, best_dot := -1, f32(-2)
        for wall in 0 ..< 4 {
            if wall == building.entrance_side || used[wall] do continue
            outward := wall_outward_world(building, wall)
            dot := outward.x * direction.x + outward.z * direction.z
            if dot > best_dot do best_wall, best_dot = wall, dot
        }
        if best_wall < 0 do break
        used[best_wall] = true
        if rank == index % 3 do return best_wall
    }
    return (building.entrance_side + 2) % 4
}

world_to_local :: proc(building: Building, world: Vec2) -> Vec2 {
    cosine, sine := math.cos(building.yaw), math.sin(building.yaw)
    dx, dz := world.x - building.center.x, world.z - building.center.z
    return {dx * cosine + dz * sine, -dx * sine + dz * cosine}
}

entrance_clearance_contains :: proc(building: Building, world: Vec2, prop_radius: f32 = .4) -> bool {
    local := world_to_local(building, world)
    half_door := f32(1.35) + prop_radius
    depth := f32(1.8) + prop_radius
    switch building.entrance_side {
    case 0:
        return math.abs(local.x) < half_door && local.z < -building.depth * .5 + depth
    case 1:
        return math.abs(local.z) < half_door && local.x > building.width * .5 - depth
    case 2:
        return math.abs(local.x) < half_door && local.z > building.depth * .5 - depth
    case 3:
        return math.abs(local.z) < half_door && local.x < -building.width * .5 + depth
    }
    return false
}

inside_wall_position :: proc(building: Building, wall: int, along, inset: f32) -> Vec2 {
    switch wall {
    case 0:
        return {along, -building.depth * .5 + inset}
    case 1:
        return {building.width * .5 - inset, along}
    case 2:
        return {along, building.depth * .5 - inset}
    case 3:
        return {-building.width * .5 + inset, along}
    }
    return {}
}

opposite_entrance_corner :: proc(building: Building, side: f32, inset: f32) -> Vec2 {
    switch building.entrance_side {
    case 0:
        return {side * (building.width * .5 - inset), building.depth * .5 - inset}
    case 1:
        return {-building.width * .5 + inset, side * (building.depth * .5 - inset)}
    case 2:
        return {side * (building.width * .5 - inset), -building.depth * .5 + inset}
    case 3:
        return {building.width * .5 - inset, side * (building.depth * .5 - inset)}
    }
    return {}
}

entrance_position :: proc(building: Building, outside: f32 = .75) -> Vec2 {
    local := Vec2{}
    switch building.entrance_side {
    case 0:
        local.z = -building.depth * .5 - outside
    case 1:
        local.x = building.width * .5 + outside
    case 2:
        local.z = building.depth * .5 + outside
    case 3:
        local.x = -building.width * .5 - outside
    }
    return local_to_world(building, local)
}

add_route :: proc(plan: ^Plan, a, b: Vec2, a_y, b_y, width: f32, building: int = -1) {
    if plan == nil || plan.route_count >= ROUTE_CAPACITY do return
    plan.routes[plan.route_count] = {a, b, a_y, b_y, width, building}
    plan.route_count += 1
}

add_enclosure_segment :: proc(plan: ^Plan, a, b: Vec2, a_y, b_y, width, height: f32, seed: u32) {
    if plan == nil || plan.enclosure_count >= ENCLOSURE_CAPACITY do return
    plan.enclosure[plan.enclosure_count] = {a, b, a_y, b_y, width, height, seed}
    plan.enclosure_count += 1
}

add_drainage_channel :: proc(plan: ^Plan, kind: Drainage_Kind, a, b: Vec2, a_y, b_y, width: f32, seed: u32) {
    if plan == nil || plan.drainage_count >= DRAINAGE_CAPACITY do return
    plan.drainage[plan.drainage_count] = {kind, a, b, a_y, b_y, width, seed}
    plan.drainage_count += 1
}

overlaps :: proc(a, b: Building, margin: f32 = 2) -> bool {
    // Conservative circles make generation stable even when buildings rotate.
    ar := math.sqrt(a.width * a.width + a.depth * a.depth) * .5
    br := math.sqrt(b.width * b.width + b.depth * b.depth) * .5
    dx, dz := a.center.x - b.center.x, a.center.z - b.center.z
    limit := ar + br + margin
    return dx * dx + dz * dz < limit * limit
}

segment_point_distance_squared :: proc(a, b, point: Vec2) -> f32 {
    dx, dz := b.x - a.x, b.z - a.z
    length_squared := dx * dx + dz * dz
    if length_squared <= .0001 {
        px, pz := point.x - a.x, point.z - a.z
        return px * px + pz * pz
    }
    t := clamp(((point.x - a.x) * dx + (point.z - a.z) * dz) / length_squared, f32(0), f32(1))
    nearest := Vec2{a.x + dx * t, a.z + dz * t}
    px, pz := point.x - nearest.x, point.z - nearest.z
    return px * px + pz * pz
}

route_intersects_building :: proc(a, b: Vec2, width: f32, building: Building) -> bool {
    local_a := world_to_local(building, a)
    local_b := world_to_local(building, b)
    clearance := width * .5 + .35
    half_width := building.width * .5 + clearance
    half_depth := building.depth * .5 + clearance
    delta := Vec2{local_b.x - local_a.x, local_b.z - local_a.z}
    entry, exit := f32(0), f32(1)
    origins := [2]f32{local_a.x, local_a.z}
    directions := [2]f32{delta.x, delta.z}
    extents := [2]f32{half_width, half_depth}
    for axis in 0 ..< 2 {
        origin, direction, extent := origins[axis], directions[axis], extents[axis]
        if math.abs(direction) < .0001 {
            if origin < -extent || origin > extent do return false
            continue
        }
        near := (-extent - origin) / direction
        far := (extent - origin) / direction
        if near > far do near, far = far, near
        entry = max(entry, near)
        exit = min(exit, far)
        if entry > exit do return false
    }
    return true
}

prop_traversal_radius :: proc(prop: Prop) -> f32 {
    switch prop.kind {
    case .Pot:
        return .31 * prop.scale
    case .Amphora:
        return .25 * prop.scale
    case .Pithos:
        return .46 * prop.scale
    case .Dolium:
        return .52 * prop.scale
    case .Pottery_Sherds:
        return .50 * prop.scale
    case .Rubble:
        return .48 * prop.scale
    case .Fallen_Column:
        return 1.95 * prop.scale
    case .Tumbled_Wall:
        return 2.35 * prop.scale
    case .Masonry_Pile, .Roof_Tile_Pile, .Mudbrick_Fall:
        return 1.25 * prop.scale
    case .Fallen_Timber:
        return 2.05 * prop.scale
    case .Grass_Tuft:
        return .22 * prop.scale
    case .Scrub:
        return .48 * prop.scale
    }
    return .5 * prop.scale
}

route_intersects_prop :: proc(a, b: Vec2, width: f32, prop: Prop) -> bool {
    if prop.kind == .Fallen_Column ||
       prop.kind == .Tumbled_Wall ||
       prop.kind == .Roof_Tile_Pile ||
       prop.kind == .Fallen_Timber {
        obstacle := Building {
            center = prop.position,
            width  = 3.5 * prop.scale,
            depth  = .68 * prop.scale,
            yaw    = prop.yaw,
        }
        if prop.kind == .Tumbled_Wall do obstacle.width, obstacle.depth = 3.8 * prop.scale, 1.55 * prop.scale
        if prop.kind == .Roof_Tile_Pile do obstacle.width, obstacle.depth = 1.9 * prop.scale, 1.25 * prop.scale
        if prop.kind == .Fallen_Timber do obstacle.width, obstacle.depth = 4.1 * prop.scale, .48 * prop.scale
        return route_intersects_building(a, b, width, obstacle)
    }
    clearance := width * .5 + prop_traversal_radius(prop) + .20
    return segment_point_distance_squared(a, b, prop.position) < clearance * clearance
}

route_is_clear_of_buildings :: proc(plan: ^Plan, a, b: Vec2, width: f32, owner: int = -1) -> bool {
    if plan == nil do return false
    for building, index in plan.buildings[:plan.building_count] {
        if index == owner do continue
        if route_intersects_building(a, b, width, building) do return false
    }
    return true
}

route_is_clear :: proc(plan: ^Plan, a, b: Vec2, width: f32, owner: int = -1) -> bool {
    if !route_is_clear_of_buildings(plan, a, b, width, owner) do return false
    for prop in plan.props[:plan.prop_count] {
        if prop.building == owner do continue
        if route_intersects_prop(a, b, width, prop) do return false
    }
    return true
}

relocate_props_clear_of_route :: proc(plan: ^Plan, a, b: Vec2, width: f32, owner: int = -1) -> bool {
    if plan == nil do return false
    for prop_index in 0 ..< plan.prop_count {
        prop := &plan.props[prop_index]
        if prop.building == owner || !route_intersects_prop(a, b, width, prop^) do continue
        original := prop.position
        relocated := false
        angle_offset := random_range(prop.detail_seed ~ 0xc1ea, 0, math.PI * 2)
        // Extensive complexes can have many converging approaches. Search far
        // enough to move collapse debris beyond the whole circulation fan,
        // rather than giving up after only a few metres around its origin.
        for attempt in 0 ..< 384 {
            ring := f32(attempt / 16 + 1) * .85
            angle := angle_offset + f32(attempt % 16) / 16 * math.PI * 2
            candidate := Vec2{original.x + math.cos(angle) * ring, original.z + math.sin(angle) * ring}
            trial := prop^
            trial.position = candidate
            if route_intersects_prop(a, b, width, trial) do continue
            owner_building := plan.buildings[prop.building]
            if entrance_clearance_contains(owner_building, candidate, prop_traversal_radius(trial)) do continue
            blocked := false
            for route in plan.routes[:plan.route_count] {
                if route_intersects_prop(route.a, route.b, route.width, trial) {
                    blocked = true
                    break
                }
            }
            if blocked do continue
            prop.position = candidate
            plan.relocated_prop_count += 1
            relocated = true
            break
        }
        if !relocated do return false
    }
    return true
}

route_requires_stairs :: proc(plan: ^Plan, route: Route_Segment) -> bool {
    return plan != nil && plan.terrain_profile == .Terraced && math.abs(route.b_y - route.a_y) >= .18
}

site_feature_radius :: proc(kind: Site_Feature_Kind, scale: f32 = 1) -> f32 {
    switch kind {
    case .Altar_Platform:
        return 1.55 * scale
    case .Cistern:
        return 1.85 * scale
    case .Lustral_Basin:
        return 1.75 * scale
    }
    return 1.5 * scale
}

site_feature_is_clear :: proc(plan: ^Plan, kind: Site_Feature_Kind, position: Vec2, scale: f32 = 1) -> bool {
    if plan == nil do return false
    radius := site_feature_radius(kind, scale)
    // Reuse the rotated footprint test with a zero-length segment. Its width
    // expands the building by the court feature's required breathing room.
    for building in plan.buildings[:plan.building_count] {
        if route_intersects_building(position, position, radius * 2, building) do return false
    }
    for route in plan.routes[:plan.route_count] {
        clearance := radius + route.width * .5 + .35
        if segment_point_distance_squared(route.a, route.b, position) < clearance * clearance do return false
    }
    for channel in plan.drainage[:plan.drainage_count] {
        clearance := radius + channel.width * .5 + .25
        if segment_point_distance_squared(channel.a, channel.b, position) < clearance * clearance do return false
    }
    return true
}

dimensions :: proc(culture: Culture, kind: Building_Kind, seed: u32) -> (width, depth, height: f32) {
    switch kind {
    case .Temple:
        return random_range(seed ~ 11, 9, 13), random_range(seed ~ 12, 14, 20), random_range(seed ~ 13, 2.8, 5.2)
    case .Stoa:
        return random_range(seed ~ 21, 16, 24), random_range(seed ~ 22, 5, 7), random_range(seed ~ 23, 2.4, 4.3)
    case .Shrine:
        return random_range(seed ~ 31, 4.5, 7), random_range(seed ~ 32, 5, 8), random_range(seed ~ 33, 2.0, 3.7)
    case .House:
        return random_range(seed ~ 41, 7, 11), random_range(seed ~ 42, 7, 12), random_range(seed ~ 43, 1.8, 3.4)
    case .Tomb:
        size := random_range(seed ~ 51, 5.5, 8.5)
        return size, size, random_range(seed ~ 52, 2.2, 4)
    case .Basilica:
        return random_range(seed ~ 61, 11, 16), random_range(seed ~ 62, 20, 28), random_range(seed ~ 63, 4, 6.5)
    case .Baths:
        return random_range(seed ~ 71, 13, 19), random_range(seed ~ 72, 12, 18), random_range(seed ~ 73, 2.8, 5)
    case .Villa:
        return random_range(seed ~ 81, 11, 17), random_range(seed ~ 82, 10, 16), random_range(seed ~ 83, 2.4, 4.2)
    case .Palace:
        return random_range(seed ~ 91, 15, 22), random_range(seed ~ 92, 14, 21), random_range(seed ~ 93, 3, 5.4)
    case .Magazine:
        return random_range(seed ~ 101, 5, 8), random_range(seed ~ 102, 13, 21), random_range(seed ~ 103, 2.2, 3.8)
    }
    _ = culture
    return 8, 8, 3
}

add_prop :: proc(plan: ^Plan, kind: Prop_Kind, position: Vec2, yaw, scale: f32, building: int, detail_seed: u32 = 0) {
    if plan == nil || plan.prop_count >= PROP_CAPACITY do return
    plan.props[plan.prop_count] = {
        kind        = kind,
        position    = position,
        yaw         = yaw,
        scale       = scale,
        building    = building,
        detail_seed = detail_seed,
    }
    plan.prop_count += 1
}

court_contains :: proc(court: Central_Court, position: Vec2, padding: f32 = 0) -> bool {
    local := Vec2{position.x - court.center.x, position.z - court.center.z}
    c, s := math.cos(-court.yaw), math.sin(-court.yaw)
    x := local.x * c - local.z * s
    z := local.x * s + local.z * c
    return math.abs(x) < court.width * .5 + padding &&
        math.abs(z) < court.depth * .5 + padding
}

vegetation_position_is_clear :: proc(
    plan: ^Plan,
    building_index: int,
    position: Vec2,
    radius: f32,
    ignore_prop_index: int = -1,
) -> bool {
    if plan == nil || building_index < 0 || building_index >= plan.building_count do return false
    owner := plan.buildings[building_index]
    if entrance_clearance_contains(owner, position, radius + .18) do return false
    for route in plan.routes[:plan.route_count] {
        clearance := radius + route.width * .5 + .28
        if segment_point_distance_squared(route.a, route.b, position) < clearance * clearance do return false
    }
    for channel in plan.drainage[:plan.drainage_count] {
        clearance := radius + channel.width * .5 + .24
        if segment_point_distance_squared(channel.a, channel.b, position) < clearance * clearance do return false
    }
    for feature in plan.features[:plan.feature_count] {
        clearance := radius + site_feature_radius(feature.kind, feature.scale) + .35
        dx, dz := position.x - feature.position.x, position.z - feature.position.z
        if dx * dx + dz * dz < clearance * clearance do return false
    }
    if plan.mode == .Complex {
        if court_contains(plan.court, position, radius + .25) do return false
        for precinct in plan.precincts[:plan.precinct_count] {
            if court_contains(precinct, position, radius + .25) do return false
        }
    }
    for building, index in plan.buildings[:plan.building_count] {
        if index == building_index do continue
        if route_intersects_building(position, position, radius * 2, building) do return false
    }
    for prop, prop_index in plan.props[:plan.prop_count] {
        if prop_index == ignore_prop_index do continue
        dx, dz := position.x - prop.position.x, position.z - prop.position.z
        // Let grass knit into rubble margins, but keep individual generated
        // deposits from collapsing into one unreadable clump.
        clearance := radius + min(prop_traversal_radius(prop), f32(.46)) * .52
        if dx * dx + dz * dz < clearance * clearance do return false
    }
    return true
}

add_vegetation_encroachment :: proc(plan: ^Plan, building_index: int) {
    if plan == nil || building_index < 0 || building_index >= plan.building_count do return
    building := plan.buildings[building_index]
    base := building.seed ~ 0x6a4555
    grass_count := 2 + int(building.damage * 6)
    scrub_count := int(max(building.damage - .24, f32(0)) * 3.2)
    total := grass_count + scrub_count
    for index in 0 ..< total {
        kind := index < grass_count ? Prop_Kind.Grass_Tuft : Prop_Kind.Scrub
        salt := u32(index) * 0x9e3779b9
        placed := false
        for attempt in 0 ..< 24 {
            attempt_salt := salt ~ u32(attempt) * 0x85ebca6b
            wall := int(hash(base ~ attempt_salt ~ 1) % 4)
            if wall == building.entrance_side && attempt < 8 do continue
            horizontal := wall == 0 || wall == 2
            extent := horizontal ? building.width : building.depth
            along := random_range(base ~ attempt_salt ~ 2, -extent * .46, extent * .46)
            // Most growth hugs the outside foot of a wall; occasional inner
            // tufts occupy sheltered rooms without filling their center.
            outside := random01(base ~ attempt_salt ~ 3) < .72
            offset := -random_range(base ~ attempt_salt ~ 4, .42, .78)
            if outside do offset = random_range(base ~ attempt_salt ~ 4, .38, .92)
            local := Vec2{}
            switch wall {
            case 0:
                local = {along, -building.depth * .5 - offset}
            case 1:
                local = {building.width * .5 + offset, along}
            case 2:
                local = {along, building.depth * .5 + offset}
            case 3:
                local = {-building.width * .5 - offset, along}
            }
            candidate := local_to_world(building, local)
            scale := random_range(base ~ salt ~ 5, .62, 1.18)
            if kind == .Scrub do scale = random_range(base ~ salt ~ 5, .72, 1.22)
            radius := kind == .Scrub ? f32(.48) * scale : f32(.22) * scale
            if !vegetation_position_is_clear(plan, building_index, candidate, radius) do continue
            add_prop(
                plan,
                kind,
                candidate,
                random_range(base ~ salt ~ 6, -math.PI, math.PI),
                scale,
                building_index,
                base ~ salt ~ 0x7e6,
            )
            placed = true
            break
        }
        _ = placed
    }
}

furnish :: proc(plan: ^Plan, building_index: int) {
    building := plan.buildings[building_index]
    base := building.seed ~ 0x50524f50
    // Pottery belongs at thresholds, sheltered inner corners, and domestic
    // walls—not uniformly sprinkled over archaeological ground.
    pot_count := 0
    switch building.kind {
    case .House:
        pot_count = 3 + int(hash(base) % 4)
    case .Shrine:
        pot_count = 2 + int(hash(base) % 3)
    case .Stoa:
        pot_count = 1 + int(hash(base) % 3)
    case .Temple:
        pot_count = 1 + int(hash(base) % 2)
    case .Tomb:
        pot_count = int(hash(base) % 2)
    case .Basilica:
        pot_count = 1 + int(hash(base) % 2)
    case .Baths:
        pot_count = 1 + int(hash(base) % 3)
    case .Villa:
        pot_count = 4 + int(hash(base) % 4)
    case .Palace:
        pot_count = 4 + int(hash(base) % 4)
    case .Magazine:
        pot_count = 6 + int(hash(base) % 5)
    }
    pot_count = int(math.round(f32(pot_count) * pottery_density_factor(plan.pottery_density)))
    for index in 0 ..< pot_count {
        salt := u32(index) * 0x9e3779b9
        // Cycle through the other three walls. Door thresholds remain clear
        // for traversal even when pottery density is high in magazines.
        wall := (building.entrance_side + 1 + index % 3) % 4
        along_extent := wall == 0 || wall == 2 ? building.width : building.depth
        side := index / 3 % 2 == 0 ? f32(-1) : f32(1)
        along := side * random_range(base ~ salt ~ 1, along_extent * .18, along_extent * .38)
        inset := random_range(base ~ salt ~ 2, .65, 1.15)
        local := inside_wall_position(building, wall, along, inset)
        world := local_to_world(building, local)
        if entrance_clearance_contains(building, world, .45) {
            local = opposite_entrance_corner(building, side, inset)
            world = local_to_world(building, local)
        }
        amphora_threshold := plan.culture == .Minoan ? u32(2) : u32(1)
        kind := hash(base ~ salt ~ 4) % 3 < amphora_threshold ? Prop_Kind.Amphora : Prop_Kind.Pot
        if building.culture == .Minoan &&
           (building.kind == .Magazine || building.kind == .Palace) &&
           index < max(pot_count / 2, 2) {
            kind = .Pithos
        } else if building.culture == .Roman &&
                  building.kind == .Villa &&
                  index == 0 {
            kind = .Dolium
        }
        shatter_chance := clamp(building.damage * .55 - .05, f32(0), f32(.48))
        if random01(base ~ salt ~ 0x5aed) < shatter_chance do kind = .Pottery_Sherds
        pottery_scale := random_range(base ~ salt ~ 6, .78, 1.22)
        pottery_clearance := f32(.35)
        if kind == .Pottery_Sherds do pottery_clearance = .50 * pottery_scale
        if kind == .Pithos do pottery_clearance = .46 * pottery_scale
        if kind == .Dolium do pottery_clearance = .52 * pottery_scale
        if entrance_clearance_contains(building, world, pottery_clearance) {
            local = opposite_entrance_corner(building, side, max(inset, f32(.9)))
            world = local_to_world(building, local)
        }
        add_prop(
            plan,
            kind,
            world,
            random_range(base ~ salt ~ 5, -math.PI, math.PI),
            pottery_scale,
            building_index,
            base ~ salt ~ 0x5aed5,
        )
    }

    rubble_count := 1 + int(building.damage * 5) + int(hash(base ~ 7) % 2)
    for index in 0 ..< rubble_count {
        salt := u32(index) * 0x85ebca6b
        edge := int(hash(base ~ salt) % 4)
        if edge == building.entrance_side do edge = (edge + 1) % 4
        x := random_range(base ~ salt ~ 8, -building.width * .55, building.width * .55)
        z := random_range(base ~ salt ~ 9, -building.depth * .55, building.depth * .55)
        if edge == 0 do x = -building.width * .55
        if edge == 1 do x = building.width * .55
        if edge == 2 do z = -building.depth * .55
        if edge == 3 do z = building.depth * .55
        rubble_local := Vec2{x, z}
        rubble_world := local_to_world(building, rubble_local)
        if entrance_clearance_contains(building, rubble_world, .55) {
            side := index % 2 == 0 ? f32(-1) : f32(1)
            rubble_local = opposite_entrance_corner(building, side, .7)
            rubble_world = local_to_world(building, rubble_local)
        }
        add_prop(
            plan,
            .Rubble,
            rubble_world,
            random_range(base ~ salt ~ 10, -math.PI, math.PI),
            random_range(base ~ salt ~ 11, .55, 1.35),
            building_index,
            base ~ salt ~ 0x711,
        )
    }
    if building.kind == .Temple || building.kind == .Stoa || building.kind == .Basilica {
        side := hash(base ~ 12) & 1 == 0 ? f32(-1) : f32(1)
        local := Vec2 {
            side * building.width * .34,
            random_range(base ~ 13, -building.depth * .32, building.depth * .32),
        }
        fallen_world := local_to_world(building, local)
        if entrance_clearance_contains(building, fallen_world, .5) {
            local = opposite_entrance_corner(building, side, 1)
            fallen_world = local_to_world(building, local)
        }
        add_prop(
            plan,
            .Fallen_Column,
            fallen_world,
            building.collapse_yaw + random_range(base ~ 14, -.20, .20),
            random_range(base ~ 15, .8, 1.18),
            building_index,
            base ~ 0xf411,
        )
    }

    // High damage produces one or more coherent wall-collapse deposits. Each
    // lies just outside a non-entrance wall, parallel to the wall it came from.
    collapse_count := 1 + int(building.damage * 2.4)
    for index in 0 ..< collapse_count {
        salt := u32(index) * 0x27d4eb2d
        wall := collapse_wall_for_index(building, index)
        horizontal := wall == 0 || wall == 2
        along_extent := horizontal ? building.width : building.depth
        along := random_range(base ~ salt ~ 0xc1, -along_extent * .26, along_extent * .26)
        plan.buildings[building_index].collapsed_sides |= u8(1 << u32(wall))
        plan.buildings[building_index].collapse_centers[wall] = along
        outside := random_range(base ~ salt ~ 0xc2, .55, 1.05)
        local := Vec2{}
        yaw := building.yaw
        switch wall {
        case 0:
            local = {along, -building.depth * .5 - outside}
        case 1:
            local = {building.width * .5 + outside, along}
            yaw += math.PI * .5
        case 2:
            local = {along, building.depth * .5 + outside}
        case 3:
            local = {-building.width * .5 - outside, along}
            yaw += math.PI * .5
        }
        collapse_world := local_to_world(building, local)
        if entrance_clearance_contains(building, collapse_world, .55) {
            side := index % 2 == 0 ? f32(-1) : f32(1)
            local = opposite_entrance_corner(building, side, -.7)
            collapse_world = local_to_world(building, local)
        }
        add_prop(
            plan,
            .Tumbled_Wall,
            collapse_world,
            yaw,
            random_range(base ~ salt ~ 0xc3, .8, 1.35),
            building_index,
            base ~ salt ~ 0xc4,
        )
    }

    pile_count := 1 + int(building.damage * 2)
    for index in 0 ..< pile_count {
        salt := u32(index) * 0x165667b1
        wall := (building.entrance_side + 1 + index % 3) % 4
        along_extent := wall == 0 || wall == 2 ? building.width : building.depth
        along := random_range(base ~ salt ~ 0x91, -along_extent * .34, along_extent * .34)
        local := inside_wall_position(building, wall, along, -.65)
        pile_world := local_to_world(building, local)
        if entrance_clearance_contains(building, pile_world, .55) {
            side := index % 2 == 0 ? f32(-1) : f32(1)
            local = opposite_entrance_corner(building, side, -.65)
            pile_world = local_to_world(building, local)
        }
        kind := Prop_Kind.Masonry_Pile
        if building.culture == .Roman {
            if index == 0 && building_index % 2 == 0 do kind = .Roof_Tile_Pile
        } else if building.culture == .Minoan {
            if index == 0 {
                kind = building_index % 2 == 0 ? .Mudbrick_Fall : .Fallen_Timber
            } else {
                kind = hash(base ~ salt ~ 0x92) & 1 == 0 ? .Mudbrick_Fall : .Fallen_Timber
            }
        } else if index == 0 &&
                  (building.kind == .Temple || building.kind == .Stoa) {
            kind = .Roof_Tile_Pile
        }
        pile_scale := random_range(base ~ salt ~ 0x94, .72, 1.28)
        pile_clearance := prop_traversal_radius({kind = kind, scale = pile_scale})
        if entrance_clearance_contains(building, pile_world, pile_clearance) {
            side := index % 2 == 0 ? f32(-1) : f32(1)
            local = opposite_entrance_corner(building, side, -max(pile_clearance, f32(.75)))
            pile_world = local_to_world(building, local)
        }
        pile_yaw := building.yaw + random_range(base ~ salt ~ 0x93, -.35, .35)
        if kind == .Fallen_Timber {
            pile_yaw = building.collapse_yaw + random_range(base ~ salt ~ 0x93, -.18, .18)
        }
        add_prop(
            plan,
            kind,
            pile_world,
            pile_yaw,
            pile_scale,
            building_index,
            base ~ salt ~ 0x95,
        )
    }
}

make_building_for_culture :: proc(
    culture: Culture,
    kind: Building_Kind,
    center: Vec2,
    yaw: f32,
    seed: u32,
) -> Building {
    width, depth, height := dimensions(culture, kind, seed)
    layout := Interior_Layout.None
    room_count := 1
    colonnade := Colonnade_Layout.None
    column_count := 0
    wall_finish := Wall_Finish_Style.None
    floor_finish := Floor_Finish_Style.Packed_Clay
    signature_remain := Signature_Remain.None
    if culture == .Roman do wall_finish = .Roman_Painted_Plaster
    if culture == .Minoan do wall_finish = .Minoan_Painted_Plaster
    if culture == .Roman do floor_finish = .Roman_Mosaic
    if culture == .Minoan do floor_finish = .Minoan_Gypsum_Plaster
    switch kind {
    case .Temple:
        layout, room_count = .Cella, 2
        colonnade = .Peristyle
        along_depth := max(int(math.ceil(depth / 3)), 4)
        along_width := max(int(math.ceil(width / 3)), 3)
        column_count = along_depth * 2 + max(along_width - 2, 1) * 2
    case .Stoa:
        layout, room_count = .Aisled_Hall, 2
        colonnade = .Frontage
        column_count = max(int(math.ceil(width / 2.6)), 5)
    case .Shrine, .Tomb:
        layout, room_count = .None, 1
    case .House:
        layout, room_count = .Domestic_Rooms, 3 + int(hash(seed ~ 0x600d) % 3)
    case .Basilica:
        layout, room_count = .Aisled_Hall, 3
        colonnade = .Nave_Aisles
        column_count = max(int(math.ceil(depth / 3)), 5) * 2
        signature_remain = .Basilica_Tribunal
    case .Baths:
        layout, room_count = .Chambers, 4 + int(hash(seed ~ 0xba75) % 3)
        signature_remain = .Bath_Hypocaust
    case .Villa:
        layout, room_count = .Courtyard, 5 + int(hash(seed ~ 0x711a) % 4)
    case .Palace:
        layout, room_count = .Courtyard, 7 + int(hash(seed ~ 0xfa1a) % 5)
        colonnade = .Court
        column_count = 5
        signature_remain = .Palace_Grand_Stair
    case .Magazine:
        layout, room_count = .Magazines, 3
        signature_remain = .Magazine_Pithos_Beds
    }
    return {
        culture = culture,
        kind = kind,
        center = center,
        width = width,
        depth = depth,
        yaw = yaw,
        wall_height = height,
        damage = random_range(seed ~ 0xd4a6e, .28, .78),
        entrance_side = int(hash(seed ~ 0xe17) % 4),
        interior_layout = layout,
        room_count = room_count,
        colonnade_layout = colonnade,
        column_count = column_count,
        wall_finish = wall_finish,
        floor_finish = floor_finish,
        signature_remain = signature_remain,
        collapse_yaw = random_range(seed ~ 0xc011a95e, -math.PI, math.PI),
        seed = seed,
    }
}

make_building :: proc(kind: Building_Kind, center: Vec2, yaw: f32, seed: u32) -> Building {
    return make_building_for_culture(.Aegean, kind, center, yaw, seed)
}

single_kind :: proc(culture: Culture, seed: u32) -> Building_Kind {
    roll := hash(seed) % 5
    switch culture {
    case .Aegean:
        return Building_Kind(roll)
    case .Roman:
        kinds := [5]Building_Kind{.Temple, .Basilica, .Baths, .Villa, .Tomb}
        return kinds[roll]
    case .Minoan:
        kinds := [5]Building_Kind{.Palace, .Magazine, .Shrine, .House, .Tomb}
        return kinds[roll]
    }
    return .House
}

generate_for_site :: proc(
    culture: Culture,
    mode: Mode,
    seed: u32,
    site: Site,
    preservation: Preservation = .Weathered,
    pottery_density: Pottery_Density = .Typical,
    complex_scale: Complex_Scale = .Standard,
) -> Plan {
    plan := Plan {
        seed            = seed,
        mode            = mode,
        culture         = culture,
        terrain_profile = site.profile,
        preservation    = preservation,
        pottery_density = pottery_density,
        complex_scale   = complex_scale,
        extent          = 24,
        collapse_yaw    = random_range(seed ~ 0xc011a95e, -math.PI, math.PI),
    }
    if culture == .Roman {
        plan.precinct_layout = .Formal_Axis
        plan.enclosure_layout = .Rectilinear_Pomerium
    } else if culture == .Minoan {
        plan.precinct_layout = .Offset_Terraces
        plan.enclosure_layout = .Terraced_Peribolos
    } else {
        plan.precinct_layout = .Irregular_Temenos
        plan.enclosure_layout = .Irregular_Temenos
    }
    if mode == .Ruin {
        kind := single_kind(culture, seed)
        plan.buildings[0] = make_building_for_culture(culture, kind, {}, random_range(seed ~ 1, -.22, .22), seed)
        plan.buildings[0].collapse_yaw = plan.collapse_yaw
        plan.buildings[0].damage = damage_for_preservation(plan.buildings[0].seed, preservation)
        plan.buildings[0].base_y = 0
        plan.building_count = 1
        furnish(&plan, 0)
        add_vegetation_encroachment(&plan, 0)
        plan.valid = true
        return plan
    }

    plan.extent = culture == .Aegean ? f32(54) : f32(64)
    wanted := 5 + int(hash(seed ~ 0xc011ec7) % 5)
    if complex_scale == .Compact {
        plan.extent *= .82
        wanted = 4 + int(hash(seed ~ 0xc011ec7) % 2)
    } else if complex_scale == .Extensive {
        plan.extent *= 1.25
        wanted = 9 + int(hash(seed ~ 0xc011ec7) % 4)
    }
    // The first structure is the visual anchor. Later structures orbit a
    // shared court and face approximately inward, forming a legible complex.
    anchor_kind := Building_Kind.Temple
    if culture == .Aegean do anchor_kind = hash(seed ~ 2) & 1 == 0 ? .Temple : .Stoa
    if culture == .Roman do anchor_kind = hash(seed ~ 2) & 1 == 0 ? .Basilica : .Baths
    if culture == .Minoan do anchor_kind = .Palace
    plan.buildings[0] = make_building_for_culture(culture, anchor_kind, {0, -8}, 0, seed ~ 0xa11)
    plan.buildings[0].collapse_yaw = plan.collapse_yaw
    plan.buildings[0].damage = damage_for_preservation(plan.buildings[0].seed, preservation)
    plan.buildings[0].entrance_side = 2
    plan.building_count = 1
    hub := Vec2{0, 8}
    approach_start := Vec2{0, plan.extent * .90}
    plan.court = {
        center = hub,
        width  = 14,
        depth  = 12,
    }
    if culture == .Roman do plan.court.width, plan.court.depth = 18, 15
    if culture == .Minoan do plan.court.width, plan.court.depth = 14, 20
    if complex_scale == .Extensive {
        switch plan.precinct_layout {
        case .Formal_Axis:
            // Roman subsidiary fora remain locked to a legible civic axis.
            plan.precincts[0] = {center = {hub.x - 21, hub.z}, width = 9, depth = 8}
            plan.precincts[1] = {center = {hub.x + 21, hub.z}, width = 9, depth = 8}
        case .Offset_Terraces:
            // Minoan courts step around the palace rather than mirroring it.
            plan.precincts[0] = {
                center = {hub.x - 18, hub.z + 4.5},
                width  = 8,
                depth  = 11,
                yaw    = -.09,
            }
            plan.precincts[1] = {
                center = {hub.x + 16, hub.z - 4},
                width  = 8,
                depth  = 10,
                yaw    = .12,
            }
        case .Irregular_Temenos:
            // Aegean precincts share a loose axis whose angle and reach vary
            // by seed, avoiding repeated modern-looking bilateral plans.
            axis_yaw := random_range(seed ~ 0x7e6e, -.32, .32)
            axis := Vec2{math.cos(axis_yaw), math.sin(axis_yaw)}
            left_reach := random_range(seed ~ 0x7e6f, 16.5, 19.5)
            right_reach := random_range(seed ~ 0x7e70, 17, 20)
            plan.precincts[0] = {
                center = {hub.x - axis.x * left_reach, hub.z - axis.z * left_reach + 1.5},
                width  = 8,
                depth  = 8,
                yaw    = axis_yaw,
            }
            plan.precincts[1] = {
                center = {hub.x + axis.x * right_reach, hub.z + axis.z * right_reach - 1},
                width  = 7.5,
                depth  = 8.5,
                yaw    = axis_yaw + .08,
            }
        }
        plan.precinct_count = PRECINCT_CAPACITY
    }
    placement_attempts := complex_scale == .Extensive ? 768 : 384
    for attempt in 0 ..< placement_attempts {
        if plan.building_count >= wanted do break
        salt := u32(attempt + 1) * 0x9e3779b9
        angle := random_range(seed ~ salt ~ 3, 0, math.PI * 2)
        radius_low, radius_high := f32(15), f32(25)
        if culture == .Roman {
            radius_low, radius_high = 20, 32
        } else if culture == .Minoan {
            radius_low, radius_high = 18, 30
        }
        if complex_scale == .Extensive && attempt >= 384 {
            radius_low *= 1.28
            radius_high *= 1.62
        }
        radius := random_range(seed ~ salt ~ 4, radius_low, radius_high)
        center := Vec2{math.cos(angle) * radius, math.sin(angle) * radius + 2}
        roll := hash(seed ~ salt ~ 5) % 100
        kind := Building_Kind.House
        switch culture {
        case .Aegean:
            if roll < 18 do kind = .Shrine
            if roll >= 18 && roll < 31 do kind = .Tomb
            if roll >= 31 && roll < 45 do kind = .Stoa
        case .Roman:
            kind = .Villa
            if roll < 20 do kind = .Shrine
            if roll >= 20 && roll < 38 do kind = .Baths
            if roll >= 38 && roll < 50 do kind = .Tomb
        case .Minoan:
            kind = .Magazine
            if roll < 22 do kind = .Shrine
            if roll >= 22 && roll < 42 do kind = .House
            if roll >= 42 && roll < 52 do kind = .Tomb
        }
        route_hub := 0
        target_hub := hub
        best_hub_distance := (center.x - hub.x) * (center.x - hub.x) +
            (center.z - hub.z) * (center.z - hub.z)
        for precinct, precinct_index in plan.precincts[:plan.precinct_count] {
            dx, dz := center.x - precinct.center.x, center.z - precinct.center.z
            distance_squared := dx * dx + dz * dz
            if distance_squared < best_hub_distance {
                best_hub_distance = distance_squared
                target_hub = precinct.center
                route_hub = precinct_index + 1
            }
        }
        // Side zero is the generated doorway. Aim its outward normal toward
        // the assigned court so the circulation route reaches the threshold
        // without visually cutting through the building it serves.
        toward_hub := math.atan2(target_hub.z - center.z, target_hub.x - center.x)
        candidate := make_building_for_culture(
            culture,
            kind,
            center,
            toward_hub + math.PI * .5,
            seed ~ salt,
        )
        candidate.collapse_yaw =
            plan.collapse_yaw + random_range(candidate.seed ~ 0xc011a95e, -.18, .18)
        candidate.damage = damage_for_preservation(candidate.seed, preservation)
        candidate.entrance_side = 0
        candidate.route_hub = route_hub
        candidate.occupation_phase = Occupation_Phase(plan.building_count % len(Occupation_Phase))
        court_footprint := Building {
            center = plan.court.center,
            width  = plan.court.width,
            depth  = plan.court.depth,
            yaw    = plan.court.yaw,
        }
        candidate_diameter := math.sqrt(candidate.width * candidate.width + candidate.depth * candidate.depth)
        // Preserve the ceremonial approach from the site edge to the anchor.
        blocked :=
            route_intersects_building(approach_start, hub, 3.2, candidate) ||
            route_intersects_building(candidate.center, candidate.center, candidate_diameter + 2, court_footprint)
        for precinct in plan.precincts[:plan.precinct_count] {
            precinct_footprint := Building {
                center = precinct.center,
                width  = precinct.width,
                depth  = precinct.depth,
                yaw    = precinct.yaw,
            }
            if route_intersects_building(
                   candidate.center,
                   candidate.center,
                   candidate_diameter + 1.5,
                   precinct_footprint,
               ) ||
               route_intersects_building(hub, precinct.center, 2.0, candidate) {
                blocked = true
                break
            }
        }
        for other in plan.buildings[:plan.building_count] {
            if overlaps(candidate, other) {
                blocked = true
                break
            }
        }
        // Access is part of the site plan rather than an afterthought. Reject a
        // structure if its approach crosses an existing ruin, or if it would
        // close an approach already reserved by an accepted structure.
        candidate_entrance := entrance_position(candidate)
        if !blocked && !route_is_clear(&plan, candidate_entrance, target_hub, 1.65) {
            blocked = true
        }
        if !blocked {
            for other, other_index in plan.buildings[:plan.building_count] {
                other_entrance := entrance_position(other)
                if other_index == 0 {
                    // The anchor also owns the broad ceremonial approach.
                    if route_intersects_building(other_entrance, hub, 1.65, candidate) {
                        blocked = true
                        break
                    }
                } else {
                    other_hub := hub
                    if other.route_hub > 0 &&
                       other.route_hub <= plan.precinct_count {
                        other_hub = plan.precincts[other.route_hub - 1].center
                    }
                    if !route_intersects_building(other_entrance, other_hub, 1.65, candidate) do continue
                    blocked = true
                    break
                }
            }
        }
        if blocked do continue
        plan.buildings[plan.building_count] = candidate
        plan.building_count += 1
    }

    minimum_y, maximum_y := f32(100000), f32(-100000)
    for index in 0 ..< plan.building_count {
        y := site_height(site, plan.buildings[index].center)
        plan.buildings[index].base_y = y
        minimum_y, maximum_y = min(minimum_y, y), max(maximum_y, y)
    }
    enclosure_half_x := plan.court.width * .5 + 6
    enclosure_half_z := plan.court.depth * .5 + 6
    for building in plan.buildings[:plan.building_count] {
        radius := math.sqrt(building.width * building.width + building.depth * building.depth) * .5
        enclosure_half_x = max(enclosure_half_x, math.abs(building.center.x) + radius + 3)
        enclosure_half_z = max(enclosure_half_z, math.abs(building.center.z) + radius + 3)
    }
    enclosure_half_x = min(enclosure_half_x, plan.extent * .84)
    enclosure_half_z = min(enclosure_half_z, approach_start.z - 4)
    enclosure_width, enclosure_height := f32(.82), f32(1.45)
    if culture == .Roman do enclosure_width, enclosure_height = .62, 1.75
    if culture == .Minoan do enclosure_width, enclosure_height = 1.05, 1.55
    gate_half_width := culture == .Roman ? f32(3.8) : f32(3.2)
    southwest := Vec2{-enclosure_half_x, -enclosure_half_z}
    southeast := Vec2{enclosure_half_x, -enclosure_half_z}
    northeast := Vec2{enclosure_half_x, enclosure_half_z}
    northwest := Vec2{-enclosure_half_x, enclosure_half_z}
    gate_z := enclosure_half_z
    switch plan.enclosure_layout {
    case .Irregular_Temenos:
        southwest = {-enclosure_half_x, -enclosure_half_z * 1.05}
        southeast = {enclosure_half_x * 1.06, -enclosure_half_z}
        northeast = {enclosure_half_x, enclosure_half_z * 1.04}
        northwest = {-enclosure_half_x * 1.05, enclosure_half_z}
        gate_z = enclosure_half_z * 1.02
    case .Rectilinear_Pomerium:
        // Deliberately orthogonal: Roman boundary legibility comes from the
        // contrast with the looser Aegean and Minoan perimeter systems.
    case .Terraced_Peribolos:
        southwest = {-enclosure_half_x * 1.04, -enclosure_half_z}
        southeast = {enclosure_half_x, -enclosure_half_z * 1.06}
        northeast = {enclosure_half_x * 1.06, enclosure_half_z}
        northwest = {-enclosure_half_x, enclosure_half_z * 1.07}
        gate_z = enclosure_half_z * 1.035
    }
    enclosure_points := [7][2]Vec2 {
        {southwest, southeast},
        {southeast, northeast},
        {northeast, {gate_half_width, gate_z}},
        {{-gate_half_width, gate_z}, northwest},
        {northwest, southwest},
        // A short return beside the gate makes the opening read intentionally.
        {{gate_half_width, gate_z}, {gate_half_width, gate_z - 2.4}},
        {{-gate_half_width, gate_z - 2.4}, {-gate_half_width, gate_z}},
    }
    gateway_kind := Gateway_Kind.Aegean_Propylon
    if culture == .Roman do gateway_kind = .Roman_Gatehouse
    if culture == .Minoan do gateway_kind = .Minoan_Guardrooms
    plan.gateway = {
        kind        = gateway_kind,
        position    = {0, gate_z},
        clear_width = gate_half_width * 2,
        depth       = culture == .Roman ? 3.6 : 3.0,
        seed        = seed ~ 0x6a7e,
    }
    plan.has_gateway = true
    for endpoints in enclosure_points {
        for point in endpoints {
            y := site_height(site, point)
            minimum_y, maximum_y = min(minimum_y, y), max(maximum_y, y)
        }
    }
    circulation_points := [2]Vec2{approach_start, hub}
    for point in circulation_points {
        y := site_height(site, point)
        minimum_y, maximum_y = min(minimum_y, y), max(maximum_y, y)
    }
    gateway_y := site_height(site, plan.gateway.position)
    minimum_y, maximum_y = min(minimum_y, gateway_y), max(maximum_y, gateway_y)
    for precinct in plan.precincts[:plan.precinct_count] {
        y := site_height(site, precinct.center)
        minimum_y, maximum_y = min(minimum_y, y), max(maximum_y, y)
    }
    for index in 0 ..< plan.building_count {
        plan.buildings[index].base_y -= minimum_y
    }
    plan.elevation_range = maximum_y - minimum_y
    plan.court.base_y = site_height(site, plan.court.center) - minimum_y
    plan.gateway.base_y = site_height(site, plan.gateway.position) - minimum_y
    for index in 0 ..< plan.precinct_count {
        plan.precincts[index].base_y =
            site_height(site, plan.precincts[index].center) - minimum_y
    }
    for endpoints, index in enclosure_points {
        a, b := endpoints[0], endpoints[1]
        add_enclosure_segment(
            &plan,
            a,
            b,
            site_height(site, a) - minimum_y,
            site_height(site, b) - minimum_y,
            enclosure_width,
            enclosure_height,
            seed ~ u32(index * 0x1f123bb5) ~ 0xeac1,
        )
    }
    drainage_kind := Drainage_Kind.Runoff_Gutter
    drainage_width := f32(.42)
    if culture == .Roman do drainage_kind, drainage_width = .Capped_Drain, .68
    if culture == .Minoan do drainage_kind, drainage_width = .Plaster_Channel, .54
    downhill_x, downhill_z := -site.slope_x, -site.slope_z
    downhill_length := math.sqrt(downhill_x * downhill_x + downhill_z * downhill_z)
    drainage_angle := random_range(seed ~ 0xd2a1, 0, math.PI * 2)
    if downhill_length > .0001 do drainage_angle = math.atan2(downhill_z, downhill_x)
    best_score := f32(-100000)
    best_a, best_b := Vec2{}, Vec2{}
    drainage_found := false
    // Dense, doorway-facing plans leave narrower gaps between structures than
    // the old 22.5-degree sweep could detect. Sample the full circle at 5.625
    // degrees so drainage can still find a genuinely building-clear fall line.
    for attempt in 0 ..< 64 {
        offset_index := (attempt + 1) / 2
        offset_sign := attempt % 2 == 0 ? f32(1) : f32(-1)
        angle := drainage_angle + offset_sign * f32(offset_index) * math.PI / 32
        direction := Vec2{math.cos(angle), math.sin(angle)}
        abs_x, abs_z := max(math.abs(direction.x), f32(.0001)), max(math.abs(direction.z), f32(.0001))
        court_radius := min(plan.court.width * .5 / abs_x, plan.court.depth * .5 / abs_z) - 1.15
        enclosure_radius := min(enclosure_half_x / abs_x, enclosure_half_z / abs_z) - 1.35
        start := Vec2 {
            plan.court.center.x + direction.x * court_radius,
            plan.court.center.z + direction.z * court_radius,
        }
        finish := Vec2 {
            plan.court.center.x + direction.x * enclosure_radius,
            plan.court.center.z + direction.z * enclosure_radius,
        }
        if !route_is_clear_of_buildings(&plan, start, finish, drainage_width, -1) do continue
        crosses_precinct := false
        for precinct in plan.precincts[:plan.precinct_count] {
            footprint := Building {
                center = precinct.center,
                width  = precinct.width,
                depth  = precinct.depth,
                yaw    = precinct.yaw,
            }
            if route_intersects_building(start, finish, drainage_width, footprint) {
                crosses_precinct = true
                break
            }
        }
        if crosses_precinct do continue
        start_y, finish_y := site_height(site, start), site_height(site, finish)
        score := start_y - finish_y - f32(offset_index) * .002
        if score <= best_score do continue
        best_score, best_a, best_b = score, start, finish
        drainage_found = true
    }
    if drainage_found {
        a_y, b_y := site_height(site, best_a) - minimum_y, site_height(site, best_b) - minimum_y
        if b_y > a_y do best_a, best_b, a_y, b_y = best_b, best_a, b_y, a_y
        add_drainage_channel(&plan, drainage_kind, best_a, best_b, a_y, b_y, drainage_width, seed ~ 0xd2a1a6e)
    }
    // Furnish before solving final circulation. Paths can then avoid the full
    // footprints of wall falls, columns, masonry, pottery, and sherd fields.
    for index in 0 ..< plan.building_count {
        furnish(&plan, index)
    }

    plan.path[0] = approach_start
    plan.path[1] = {0, 8}
    plan.path[2] = {0, 0}
    plan.path_count = 3
    approach_y := site_height(site, approach_start) - minimum_y
    _ = relocate_props_clear_of_route(&plan, approach_start, hub, 3.2, 0)
    add_route(&plan, approach_start, hub, approach_y, site_height(site, hub) - minimum_y, 3.2, 0)
    for precinct in plan.precincts[:plan.precinct_count] {
        precinct_y := site_height(site, precinct.center) - minimum_y
        _ = relocate_props_clear_of_route(&plan, precinct.center, hub, 2.0)
        add_route(
            &plan,
            precinct.center,
            hub,
            precinct_y,
            site_height(site, hub) - minimum_y,
            2.0,
        )
    }
    for building, building_index in plan.buildings[:plan.building_count] {
        entrance := entrance_position(building)
        building_hub := hub
        if building.route_hub > 0 && building.route_hub <= plan.precinct_count {
            building_hub = plan.precincts[building.route_hub - 1].center
        }
        hub_y := site_height(site, building_hub) - minimum_y
        dx, dz := building_hub.x - entrance.x, building_hub.z - entrance.z
        distance_to_hub := math.sqrt(dx * dx + dz * dz)
        routed := false
        if distance_to_hub > .01 {
            perpendicular := Vec2{-dz / distance_to_hub, dx / distance_to_hub}
            midpoint := Vec2{(entrance.x + building_hub.x) * .5, (entrance.z + building_hub.z) * .5}
            // A slight deterministic bend prevents every approach from reading
            // as a modern radial site plan. Keep it only when both legs retain
            // the same archaeological footprint clearance as a direct route.
            bend_side := hash(building.seed ~ 0xb37d) & 1 == 0 ? f32(-1) : f32(1)
            bend := bend_side * random_range(building.seed ~ 0xb37e, 2.4, 5.2)
            preferred := Vec2{midpoint.x + perpendicular.x * bend, midpoint.z + perpendicular.z * bend}
            if route_is_clear(&plan, entrance, preferred, 1.65, building_index) &&
               route_is_clear(&plan, preferred, building_hub, 1.65, building_index) {
                preferred_y := site_height(site, preferred) - minimum_y
                add_route(&plan, entrance, preferred, building.base_y, preferred_y, 1.65, building_index)
                add_route(&plan, preferred, building_hub, preferred_y, hub_y, 1.65, building_index)
                routed = true
            }
        }
        if routed do continue
        if route_is_clear(&plan, entrance, building_hub, 1.65, building_index) {
            add_route(&plan, entrance, building_hub, building.base_y, hub_y, 1.65, building_index)
            continue
        }
        if distance_to_hub > .01 {
            perpendicular := Vec2{-dz / distance_to_hub, dx / distance_to_hub}
            midpoint := Vec2{(entrance.x + building_hub.x) * .5, (entrance.z + building_hub.z) * .5}
            offsets := [8]f32{5, -5, 8, -8, 11, -11, 14, -14}
            for offset in offsets {
                waypoint := Vec2{midpoint.x + perpendicular.x * offset, midpoint.z + perpendicular.z * offset}
                if !route_is_clear(&plan, entrance, waypoint, 1.65, building_index) ||
                   !route_is_clear(&plan, waypoint, building_hub, 1.65, building_index) {
                    continue
                }
                waypoint_y := site_height(site, waypoint) - minimum_y
                add_route(&plan, entrance, waypoint, building.base_y, waypoint_y, 1.65, building_index)
                add_route(&plan, waypoint, building_hub, waypoint_y, hub_y, 1.65, building_index)
                routed = true
                break
            }
        }
        if !routed && distance_to_hub > .01 {
            perpendicular := Vec2{-dz / distance_to_hub, dx / distance_to_hub}
            offsets := [8]f32{4, -4, 7, -7, 10, -10, 13, -13}
            for first_offset in offsets {
                if routed do break
                first := Vec2 {
                    entrance.x + dx * .33 + perpendicular.x * first_offset,
                    entrance.z + dz * .33 + perpendicular.z * first_offset,
                }
                if !route_is_clear(&plan, entrance, first, 1.65, building_index) do continue
                for second_offset in offsets {
                    second := Vec2 {
                        entrance.x + dx * .67 + perpendicular.x * second_offset,
                        entrance.z + dz * .67 + perpendicular.z * second_offset,
                    }
                    if !route_is_clear(&plan, first, second, 1.65, building_index) ||
                       !route_is_clear(&plan, second, building_hub, 1.65, building_index) {
                        continue
                    }
                    first_y := site_height(site, first) - minimum_y
                    second_y := site_height(site, second) - minimum_y
                    add_route(&plan, entrance, first, building.base_y, first_y, 1.65, building_index)
                    add_route(&plan, first, second, first_y, second_y, 1.65, building_index)
                    add_route(&plan, second, building_hub, second_y, hub_y, 1.65, building_index)
                    routed = true
                    break
                }
            }
        }
        if !routed &&
           route_is_clear_of_buildings(&plan, entrance, building_hub, 1.65, building_index) &&
           relocate_props_clear_of_route(&plan, entrance, building_hub, 1.65, building_index) &&
           route_is_clear(&plan, entrance, building_hub, 1.65, building_index) {
            add_route(&plan, entrance, building_hub, building.base_y, hub_y, 1.65, building_index)
            routed = true
        }
        if !routed {
            plan.route_overlap_count += 1
            add_route(&plan, entrance, building_hub, building.base_y, hub_y, 1.65, building_index)
        }
    }
    feature_kind := Site_Feature_Kind.Altar_Platform
    if culture == .Roman do feature_kind = .Cistern
    if culture == .Minoan do feature_kind = .Lustral_Basin
    feature_scale := random_range(seed ~ 0xfea7, .88, 1.12)
    angle_offset := random_range(seed ~ 0xfea8, 0, math.PI * 2)
    // Search beyond the immediate ceremonial ring on crowded plans; larger
    // precincts can host their fixture in a quieter court-edge pocket.
    for attempt in 0 ..< 144 {
        ring := f32(5.5) + f32(attempt / 12) * 2
        angle := angle_offset + f32(attempt % 12) / 12 * math.PI * 2
        candidate := Vec2{hub.x + math.cos(angle) * ring, hub.z + math.sin(angle) * ring}
        if !site_feature_is_clear(&plan, feature_kind, candidate, feature_scale) do continue
        plan.features[0] = {
            kind     = feature_kind,
            position = candidate,
            base_y   = site_height(site, candidate) - minimum_y,
            yaw      = angle + math.PI * .5,
            scale    = feature_scale,
        }
        plan.feature_count = 1
        break
    }
    for index in 0 ..< plan.building_count {
        add_vegetation_encroachment(&plan, index)
    }
    plan.valid = plan.building_count >= 4 && plan.route_overlap_count == 0
    return plan
}

generate_for_culture :: proc(
    culture: Culture,
    mode: Mode,
    seed: u32,
    preservation: Preservation = .Weathered,
    pottery_density: Pottery_Density = .Typical,
    complex_scale: Complex_Scale = .Standard,
) -> Plan {
    return generate_for_site(culture, mode, seed, default_site(.Flat), preservation, pottery_density, complex_scale)
}

generate :: proc(mode: Mode, seed: u32) -> Plan {
    return generate_for_culture(.Aegean, mode, seed)
}
