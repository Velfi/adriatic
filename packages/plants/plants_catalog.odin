package plants

import leaf_mesh "../leaf_mesh"
import plant_structure "../plant_structure"
import "core:math"

Species :: enum u8 {
    Olive,
    Italian_Cypress,
    Grapevine,
    Fig,
    Lemon,
    Pomegranate,
    Almond,
    Oleander,
    Bougainvillea,
    Rosemary,
    Stone_Pine,
    Bay_Laurel,
    Carob,
    Strawberry_Tree,
    Myrtle,
    Mastic,
    Lavender,
    Thyme,
    Sage,
    Prickly_Pear,
    Pelargonium,
    Wisteria,
    Climbing_Rose,
    Hydrangea_Bush,
    Hydrangea_Tree,
    Agapanthus,
    Star_Jasmine,
    Holm_Oak,
    Oriental_Plane,
    European_Hackberry,
    White_Poplar,
    Golden_Barrel,
    Agave,
    Aloe,
    Aeonium,
    Echeveria,
    Jade_Plant,
    Stonecrop,
    Blue_Chalk_Sticks,
    Golden_Torch_Cactus,
}

SPECIES_COUNT :: int(Species.Golden_Torch_Cactus) + 1

Detail_Level :: enum u8 {
    Near,
    Medium,
    Far,
}

Growth_Habit :: enum u8 {
    Free_Standing,
    Wall_Trained,
    Trellised,
}

Attachment_Kind :: enum u8 {
    Leaf,
    Flower,
    Fruit,
    Thorn,
    Tendril,
}

Attachment_Stage :: enum u8 {
    None,
    Bud,
    Opening,
    Half_Open,
    Bloom,
    Fruit_Set,
    Immature_Fruit,
    Ripening_Fruit,
    Ripe_Fruit,
}

Root_Kind :: enum u8 {
    Soil,
    Planter,
}

Rect :: struct {
    minimum_x, minimum_y: f32,
    maximum_x, maximum_y: f32,
}

Support_Axis :: struct {
    start:  plant_structure.Vec3,
    end:    plant_structure.Vec3,
    radius: f32,
}

Support_Surface :: struct {
    width:             f32,
    height:            f32,
    plane_z:           f32,
    root_x:            f32,
    left_corner_x:     f32,
    left_return_depth: f32,
    planter:           bool,
    exclusions:        []Rect,
    axes:              []Support_Axis,
    contact_radius:    f32,
    signature:         u64,
}

Generate_Config :: struct {
    species:  Species,
    seed:     u64,
    maturity: f32,
    detail:   Detail_Level,
    habit:    Growth_Habit,
    support:  ^Support_Surface,
    site:     Site_Context,
}

// Site_Context carries durable growing conditions rather than momentary
// weather. Consumers may use it for botanical structure, pigment, or both.
// All continuous values are normalized unless their names state otherwise.
Site_Substrate :: enum u8 {
    Unknown,
    Sand,
    Soil,
    Rock,
}

Site_Context :: struct {
    valid:            bool,
    aridity:          f32,
    exposure:         f32,
    slope:            f32,
    elevation_meters: f32,
    coast_distance_m: f32,
    substrate:        Site_Substrate,
}

site_context_signature :: proc(site: Site_Context) -> u64 {
    if !site.valid do return 0
    quantize := proc(value: f32, steps: int) -> u64 {
        return u64(clamp(int(math.round(f64(clamp(value, f32(0), f32(1)) * f32(steps)))), 0, steps))
    }
    elevation := quantize(site.elevation_meters / 1600, 15)
    coast := quantize(site.coast_distance_m / 1800, 15)
    return(
        1 |
        quantize(site.aridity, 7) << 1 |
        quantize(site.exposure, 7) << 4 |
        quantize(site.slope, 7) << 7 |
        elevation << 10 |
        coast << 14 |
        u64(site.substrate) << 18 \
    )
}

Attachment :: struct {
    kind:     Attachment_Kind,
    stage:    Attachment_Stage,
    position: plant_structure.Vec3,
    forward:  plant_structure.Vec3,
    up:       plant_structure.Vec3,
    depth:    int,
    variant:  u8,
    leaf:     Leaf_Traits,
}

attachment_stage :: proc(kind: Attachment_Kind, seed: u64, index: int, maturity: f32) -> Attachment_Stage {
    hash := (seed + 1) * 0x9e3779b97f4a7c15 ~ u64(index + 17) * 0xbf58476d1ce4e5b9
    hash = (hash ~ (hash >> 30)) * 0x94d049bb133111eb
    cohort := int(hash % 4)
    switch kind {
    case .Flower:
        latest := maturity < .30 ? 0 : maturity < .42 ? 1 : maturity < .56 ? 2 : 3
        stages := [4]Attachment_Stage{.Bud, .Opening, .Half_Open, .Bloom}
        return stages[min(cohort, latest)]
    case .Fruit:
        latest := maturity < .70 ? 0 : maturity < .80 ? 1 : maturity < .90 ? 2 : 3
        stages := [4]Attachment_Stage{.Fruit_Set, .Immature_Fruit, .Ripening_Fruit, .Ripe_Fruit}
        return stages[min(cohort, latest)]
    case .Leaf, .Thorn, .Tendril:
        return .None
    }
    return .None
}

// Leaf_Traits describes botanical intent independently of rendering. A
// consumer may generate geometry from it, substitute a billboard at distance,
// or use it to select authored foliage.
Leaf_Traits :: struct {
    shape:     leaf_mesh.Shape,
    length:    f32,
    width:     f32,
    serration: f32,
    curl:      f32,
    cup:       f32,
    thickness: f32,
}

Bounds :: struct {
    minimum: plant_structure.Vec3,
    maximum: plant_structure.Vec3,
}

Generated_Plant :: struct {
    species:           Species,
    habit:             Growth_Habit,
    maturity:          f32,
    graph:             Plant_Graph,
    segments:          [dynamic]plant_structure.Segment,
    segment_parents:   [dynamic]int,
    segment_axes:      [dynamic]int,
    segment_ids:       [dynamic]u64,
    axis_parents:      [dynamic]int,
    axis_roles:        [dynamic]Axis_Role,
    axis_orientations: [dynamic]Axis_Orientation,
    attachments:       [dynamic]Attachment,
    attachment_ids:    [dynamic]u64,
    bounds:            Bounds,
    wood:              Wood_Traits,
    root_kind:         Root_Kind,
    wind_compliance:   f32,
    support_signature: u64,
    generation_workspace: ^Generation_Workspace,
}

Wood_Traits :: struct {
    radial_irregularity: f32,
    twist:               f32,
}

Generate_Error :: enum {
    None,
    Invalid_Species,
    Invalid_Support,
    Expansion_Failed,
    Interpretation_Failed,
    Segment_Limit,
    Attachment_Limit,
}

Generate_Result :: struct {
    plant: Generated_Plant,
    error: Generate_Error,
}

destroy :: proc(result: ^Generate_Result) {
    if result == nil do return
    if generation_workspace_recycle_result(&result.plant) {
        result^ = {}
        return
    }
    delete(result.plant.segments)
    delete(result.plant.segment_parents)
    delete(result.plant.segment_axes)
    delete(result.plant.segment_ids)
    delete(result.plant.axis_parents)
    delete(result.plant.axis_roles)
    delete(result.plant.axis_orientations)
    delete(result.plant.attachments)
    delete(result.plant.attachment_ids)
    destroy_graph(&result.plant.graph)
    result^ = {}
}

main_leader_sample :: proc(plant: ^Generated_Plant, fraction: f32) -> plant_structure.Vec3 {
    if plant == nil || len(plant.segments) == 0 do return {}
    leader_count := 0
    for segment in plant.segments {
        if segment.depth == 0 do leader_count += 1
    }
    if leader_count == 0 do return plant.segments[len(plant.segments) - 1].end
    desired := clamp(int(clamp(fraction, 0, 1) * f32(leader_count - 1)), 0, leader_count - 1)
    found := 0
    for segment in plant.segments {
        if segment.depth != 0 do continue
        if found == desired do return segment.end
        found += 1
    }
    return plant.segments[len(plant.segments) - 1].end
}

species_name :: proc(species: Species) -> string {
    switch species {
    case .Olive:
        return "OLIVE"
    case .Italian_Cypress:
        return "ITALIAN CYPRESS"
    case .Grapevine:
        return "GRAPEVINE"
    case .Fig:
        return "COMMON FIG"
    case .Lemon:
        return "LEMON"
    case .Pomegranate:
        return "POMEGRANATE"
    case .Almond:
        return "ALMOND"
    case .Oleander:
        return "OLEANDER"
    case .Bougainvillea:
        return "BOUGAINVILLEA"
    case .Rosemary:
        return "ROSEMARY"
    case .Stone_Pine:
        return "STONE PINE"
    case .Bay_Laurel:
        return "BAY LAUREL"
    case .Carob:
        return "CAROB"
    case .Strawberry_Tree:
        return "STRAWBERRY TREE"
    case .Myrtle:
        return "MYRTLE"
    case .Mastic:
        return "MASTIC"
    case .Lavender:
        return "LAVENDER"
    case .Thyme:
        return "THYME"
    case .Sage:
        return "SAGE"
    case .Prickly_Pear:
        return "PRICKLY PEAR"
    case .Pelargonium:
        return "PELARGONIUM"
    case .Wisteria:
        return "WISTERIA"
    case .Climbing_Rose:
        return "CLIMBING ROSE"
    case .Hydrangea_Bush:
        return "PRUNED HYDRANGEA"
    case .Hydrangea_Tree:
        return "TREE HYDRANGEA"
    case .Agapanthus:
        return "AGAPANTHUS"
    case .Star_Jasmine:
        return "STAR JASMINE"
    case .Holm_Oak:
        return "HOLM OAK"
    case .Oriental_Plane:
        return "ORIENTAL PLANE"
    case .European_Hackberry:
        return "EUROPEAN HACKBERRY"
    case .White_Poplar:
        return "WHITE POPLAR"
    case .Golden_Barrel:
        return "GOLDEN BARREL CACTUS"
    case .Agave:
        return "AGAVE"
    case .Aloe:
        return "ALOE"
    case .Aeonium:
        return "TREE AEONIUM"
    case .Echeveria:
        return "ECHEVERIA"
    case .Jade_Plant:
        return "JADE PLANT"
    case .Stonecrop:
        return "STONECROP"
    case .Blue_Chalk_Sticks:
        return "BLUE CHALK STICKS"
    case .Golden_Torch_Cactus:
        return "GOLDEN TORCH CACTUS"
    }
    return "UNKNOWN"
}

default_habit :: proc(species: Species) -> Growth_Habit {
    switch species {
    case .Bougainvillea, .Wisteria, .Climbing_Rose, .Star_Jasmine:
        return .Wall_Trained
    case .Grapevine:
        return .Trellised
    case .Olive,
         .Italian_Cypress,
         .Fig,
         .Lemon,
         .Pomegranate,
         .Almond,
         .Oleander,
         .Rosemary,
         .Stone_Pine,
         .Bay_Laurel,
         .Carob,
         .Strawberry_Tree,
         .Myrtle,
         .Mastic,
         .Lavender,
         .Thyme,
         .Sage,
         .Prickly_Pear,
         .Pelargonium,
         .Hydrangea_Bush,
         .Hydrangea_Tree,
         .Agapanthus,
         .Holm_Oak,
         .Oriental_Plane,
         .European_Hackberry,
         .White_Poplar,
         .Golden_Barrel,
         .Agave,
         .Aloe,
         .Aeonium,
         .Echeveria,
         .Jade_Plant,
         .Stonecrop,
         .Blue_Chalk_Sticks,
         .Golden_Torch_Cactus:
        return .Free_Standing
    }
    return .Free_Standing
}

detail_for_distance :: proc(distance: f32) -> Detail_Level {
    if distance < 48 do return .Near
    if distance < 112 do return .Medium
    return .Far
}

detail_tier :: proc(distance: f32) -> int {
    switch detail_for_distance(distance) {
    case .Near:
        return 1
    case .Medium:
        return 1
    case .Far:
        return 0
    }
    return 0
}

maturity_for_species :: proc(species: Species, growth: f32) -> f32 {
    if species == .Bougainvillea {
        maturity := clamp((growth - .035) / (.72 - .035), 0, 1)
        return maturity * maturity * (3 - 2 * maturity)
    }
    return clamp(growth, 0, 1)
}

woody_wind_compliance :: proc(species: Species, maturity: f32) -> f32 {
    switch species {
    case .Bougainvillea:
        return 1 - clamp(maturity, 0, 1) * .86
    case .Grapevine:
        return .72 - clamp(maturity, 0, 1) * .46
    case .Olive:
        return .48 - clamp(maturity, 0, 1) * .30
    case .Italian_Cypress,
         .Fig,
         .Lemon,
         .Pomegranate,
         .Almond,
         .Oleander,
         .Rosemary,
         .Stone_Pine,
         .Bay_Laurel,
         .Carob,
         .Strawberry_Tree,
         .Myrtle,
         .Mastic,
         .Lavender,
         .Thyme,
         .Sage,
         .Prickly_Pear,
         .Pelargonium,
         .Wisteria,
         .Climbing_Rose,
         .Hydrangea_Bush,
         .Hydrangea_Tree,
         .Agapanthus,
         .Star_Jasmine,
         .Holm_Oak,
         .Oriental_Plane,
         .European_Hackberry,
         .White_Poplar,
         .Golden_Barrel,
         .Agave,
         .Aloe,
         .Aeonium,
         .Echeveria,
         .Jade_Plant,
         .Stonecrop,
         .Blue_Chalk_Sticks,
         .Golden_Torch_Cactus:
        return .18
    }
    return .18
}

limits :: proc(detail: Detail_Level) -> (segments, attachments: int) {
    switch detail {
    case .Near:
        return 2_048, 4_096
    case .Medium:
        return 768, 1_536
    case .Far:
        return 192, 384
    }
    return 192, 384
}

climbing_density_limits :: proc(detail: Detail_Level, support: ^Support_Surface) -> (segments, attachments: int) {
    if support == nil do return limits(detail)
    // Climbers consume a surface, not a self-contained crown volume. Their
    // useful topology therefore scales with wall/trellis area; a global cap
    // either undersamples a large facade or permits excessive density on a
    // tiny panel. Values are routed segments and attachments per square metre.
    segment_density, attachment_density := f32(16), f32(24)
    switch detail {
    case .Near:
        segment_density, attachment_density = 64, 96
    case .Medium:
        segment_density, attachment_density = 32, 48
    case .Far:
        segment_density, attachment_density = 16, 24
    }
    area := max(support.width * support.height, f32(.25))
    return max(int(math.ceil(area * segment_density)), 6), max(int(math.ceil(area * attachment_density)), 1)
}

leaf_cluster_size :: proc(species: Species, detail: Detail_Level, maturity: f32) -> int {
    // Native graphs author every organ site explicitly. Expanding an authored
    // site into a renderer-side cluster would destroy the one-to-one stable-ID
    // contract between graph organs and attachment instances.
    _ = species
    _ = detail
    _ = maturity
    return 1
}
