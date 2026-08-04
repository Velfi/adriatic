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
    if species == .Italian_Cypress {
        if detail == .Far do return 1
        if detail == .Medium do return 2
        // Establish scale-leaf density gradually. Switching directly from
        // one spray to six at juvenile maturity caused a sevenfold geometry
        // pop even after tier growth itself had been made continuous.
        return 6
    }
    if species == .Lemon && detail == .Far {
        // Three crossed broad spray surrogates preserve a rounded citrus mass
        // from oblique views without restoring reproductive or fine twig
        // geometry at this tier.
        return 3
    }
    if (species == .Hydrangea_Bush || species == .Hydrangea_Tree) && detail == .Far {
        // Broad opposite pairs are the hydrangea canopy silhouette. Dropping
        // them to the generic single-card Far surrogate halves projected leaf
        // area and turns the shrub back into a visible radial scaffold.
        return maturity < .28 ? 1 : 2
    }
    if detail == .Far {
        // Far cypress keeps many more silhouette-critical whorls than the
        // generic LOD path, so one broad spray per anchor spends the fixed
        // budget on vertical continuity rather than duplicate cards.
        return 1
    }
    if maturity < .28 do return 1
    base := detail == .Medium ? 2 : 3
    switch species {
    case .Olive:
        // Olive leaves occur in opposite pairs along the newest shoots.
        // Three-way radial clusters read as palmate leaf stars.
        return 1
    case .Lemon:
        // Citrus leaves alternate along young shoots. Two staggered blades
        // read as a short leafy run; the generic three-way cluster makes
        // every anchor a palmate star and overpacks the mature crown.
        return 1
    case .Pomegranate:
        // Narrow leaves sit in opposite pairs on young pomegranate shoots.
        // The generic three-card whorl turns the dense multi-stem vase into
        // an opaque mound and hides its fruit.
        return 1
    case .Hydrangea_Bush, .Hydrangea_Tree:
        // Broad hydrangea leaves occur in opposite pairs. A generic
        // three-card whorl makes every node an opaque palmate fan and buries
        // the terminal inflorescences inside foliage.
        return 1
    case .Oleander:
        // The native graph authors opposite and three-leaf whorls explicitly.
        return 1
    case .Carob:
        // Each card stands in for part of a compound evergreen leaf. A
        // four-way near cluster closes the mature crown without increasing
        // architecture complexity or affecting the distance budgets.
        return 1
    case .Holm_Oak:
        // Small evergreen oak leaves overlap densely into a heavy crown.
        return 1
    case .Rosemary:
        // Dense opposite needles overlap into continuous aromatic sprays.
        // Five near-detail directions keep a mature shrub from reading as a
        // bare woody fan while medium detail retains a triangular whorl.
        return 2
    case .Lavender:
        // Lavender's narrow leaves form opposite pairs along fine shoots.
        // Five cards at every station made the plant an opaque bottlebrush.
        return 1
    case .Thyme:
        // The dedicated thyme architecture emits both members of every opposite
        // pair explicitly. Expanding each authored blade again displaces
        // synthetic copies from the node and forces budget thinning that
        // removes otherwise valid pairs and terminal flower shoots.
        return 1
    case .Pelargonium:
        // Each authored node represents one alternate round leaf.
        return 1
    case .Agapanthus:
        // Its dedicated rosette emits every strap leaf explicitly.
        return 1
    case .Almond:
        // Almond leaves alternate along current shoots. Each architecture marker
        // is already a distinct longitudinal station, so a three-card whorl
        // turns the airy flowering crown into repeated palmate stars.
        return 1
    case .Strawberry_Tree:
        // Arbutus leaves alternate along red-barked shoots; one authored
        // station represents a short evergreen run at game scale. Two
        // crossed blades retain crown mass without restoring three-card stars.
        return 1
    case .Sage:
        // Broad sage leaves occur in opposite pairs along soft shoots.
        return 1
    case .Fig:
        // One broad lobed blade already supplies a strong silhouette. Paired
        // copies turn each shoot into an opaque paddle and hide the vase.
        return 1
    case .Oriental_Plane:
        // Plane leaves alternate along current shoots. One large lobed blade
        // is already silhouette-dominant; three copies make the crown opaque.
        return 1
    case .European_Hackberry:
        // Hackberry leaves also alternate; repeated three-card stars conceal
        // the species' light irregular branching. Two crossed surrogates keep
        // its smaller foliage continuous without restoring dense starbursts.
        return 1
    case .White_Poplar:
        // Small alternate deltoid leaves need paired game-scale coverage, but
        // the generic three-card whorl creates opaque vertical clumps.
        return 1
    case .Prickly_Pear:
        // Each grammar marker is already one complete cladode. Expanding it
        // through the generic three-leaf cluster stacks multiple metre-scale
        // pads at every joint and collapses the plant into an upright wall.
        return 1
    case .Golden_Barrel,
         .Agave,
         .Aloe,
         .Aeonium,
         .Echeveria,
         .Jade_Plant,
         .Stonecrop,
         .Blue_Chalk_Sticks,
         .Golden_Torch_Cactus:
        // Dedicated architectures emit one complete fleshy rib or rosette blade
        // per marker; generic clusters would stack duplicate geometry.
        return 1
    case .Stone_Pine:
        return 1
    case .Myrtle:
        // Myrtle carries small opposite leaves; three-way whorls read as
        // palmate stars on the now-legible fine cane scaffold.
        return 1
    case .Mastic:
        return 1
    case .Bay_Laurel:
        return 1
    case .Grapevine:
        // One marker represents one full palmate grape leaf. The generic
        // near-detail cluster stacks three broad cards at identical wire
        // stations, merging each cordon tier into a clipped green cylinder.
        return 1
    case .Italian_Cypress:
        return 1
    case .Bougainvillea, .Wisteria, .Climbing_Rose, .Star_Jasmine:
    }
    return base
}
