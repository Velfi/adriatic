// Package plants contains Adriatic's product-specific plant catalog. It builds
// on the renderer-independent lsystem package and keeps species, growth, and
// architectural support policy out of zelda-engine.
package plants

import leaf_mesh "../leaf_mesh"
import lsystem "../lsystem"
import "core:math"
import "core:math/linalg"

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

Support_Surface :: struct {
    width:      f32,
    height:     f32,
    plane_z:    f32,
    root_x:     f32,
    planter:    bool,
    exclusions: []Rect,
    signature:  u64,
}

Generate_Config :: struct {
    species:  Species,
    seed:     u64,
    maturity: f32,
    detail:   Detail_Level,
    habit:    Growth_Habit,
    support:  ^Support_Surface,
}

Attachment :: struct {
    kind:     Attachment_Kind,
    stage:    Attachment_Stage,
    position: lsystem.Vec3,
    forward:  lsystem.Vec3,
    up:       lsystem.Vec3,
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
    minimum: lsystem.Vec3,
    maximum: lsystem.Vec3,
}

Generated_Plant :: struct {
    species:           Species,
    habit:             Growth_Habit,
    segments:          [dynamic]lsystem.Segment,
    attachments:       [dynamic]Attachment,
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
    delete(result.plant.attachments)
    result^ = {}
}

main_leader_sample :: proc(plant: ^Generated_Plant, fraction: f32) -> lsystem.Vec3 {
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
        return 2
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

climbing_density_limits :: proc(
    detail: Detail_Level,
    support: ^Support_Surface,
) -> (segments, attachments: int) {
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
        return 2
    case .Lemon:
        // Citrus leaves alternate along young shoots. Two staggered blades
        // read as a short leafy run; the generic three-way cluster makes
        // every anchor a palmate star and overpacks the mature crown.
        return 2
    case .Pomegranate:
        // Narrow leaves sit in opposite pairs on young pomegranate shoots.
        // The generic three-card whorl turns the dense multi-stem vase into
        // an opaque mound and hides its fruit.
        return 2
    case .Hydrangea_Bush, .Hydrangea_Tree:
        // Broad hydrangea leaves occur in opposite pairs. A generic
        // three-card whorl makes every node an opaque palmate fan and buries
        // the terminal inflorescences inside foliage.
        return 2
    case .Carob:
        // Each card stands in for part of a compound evergreen leaf. A
        // four-way near cluster closes the mature crown without increasing
        // skeleton complexity or affecting the distance budgets.
        return detail == .Near ? 4 : 2
    case .Holm_Oak:
        // Small evergreen oak leaves overlap densely into a heavy crown.
        return detail == .Near ? 4 : 2
    case .Rosemary:
        // Dense opposite needles overlap into continuous aromatic sprays.
        // Five near-detail directions keep a mature shrub from reading as a
        // bare woody fan while medium detail retains a triangular whorl.
        return 2
    case .Lavender:
        // Lavender's narrow leaves form opposite pairs along fine shoots.
        // Five cards at every station made the plant an opaque bottlebrush.
        return 2
    case .Thyme:
        // Thyme's tiny leaves occur in close opposite pairs along creeping
        // runners; five-card stars overwhelm both its scale and mat habit.
        return 2
    case .Pelargonium:
        // Each authored node represents one alternate round leaf.
        return 1
    case .Agapanthus:
        // Its dedicated rosette emits every strap leaf explicitly.
        return 1
    case .Almond:
        // Almond leaves alternate along current shoots. Each skeleton marker
        // is already a distinct longitudinal station, so a three-card whorl
        // turns the airy flowering crown into repeated palmate stars.
        return 1
    case .Strawberry_Tree:
        // Arbutus leaves alternate along red-barked shoots; one authored
        // station represents a short evergreen run at game scale. Two
        // crossed blades retain crown mass without restoring three-card stars.
        return 2
    case .Sage:
        // Broad sage leaves occur in opposite pairs along soft shoots.
        return 2
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
        return 2
    case .White_Poplar:
        // Small alternate deltoid leaves need paired game-scale coverage, but
        // the generic three-card whorl creates opaque vertical clumps.
        return 2
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
        // Dedicated skeletons emit one complete fleshy rib or rosette blade
        // per marker; generic clusters would stack duplicate geometry.
        return 1
    case .Stone_Pine:
        return detail == .Near ? 6 : detail == .Medium ? 3 : 1
    case .Myrtle:
        // Myrtle carries small opposite leaves; three-way whorls read as
        // palmate stars on the now-legible fine cane scaffold.
        return 2
    case .Mastic:
        return 2
    case .Grapevine:
        // One marker represents one full palmate grape leaf. The generic
        // near-detail cluster stacks three broad cards at identical wire
        // stations, merging each cordon tier into a clipped green cylinder.
        return 1
    case .Oleander,
         .Bougainvillea,
         .Bay_Laurel,
         .Wisteria,
         .Climbing_Rose,
         .Star_Jasmine,
         .Italian_Cypress:
    }
    return base
}

cypress_generated_cluster_size :: proc(detail: Detail_Level, maturity: f32, seed: u64, index, depth: int) -> int {
    if depth == -2 {
        if detail == .Far do return 1
        // The leader cap establishes after the lateral crown. Giving a young
        // tree its full mature cap made the apex read as a round pom-pom.
        if detail == .Medium do return maturity < .58 ? 1 : 2
        if maturity < .42 do return 1
        if maturity < .70 do return 2
        return 3
    }
    if depth == -3 do return detail == .Near ? 6 : detail == .Medium ? 2 : 1
    if detail == .Far do return 1
    if detail == .Medium do return 2

    // Keep individual nodes from becoming dense rosettes. Near-detail
    // cypresses add a second anchor along each lateral segment below, so four
    // wrapped sprays per node produce better continuous coverage than six
    // sprays concentrated at fewer points while remaining inside the shared
    // attachment budget.
    desired := 1 + clamp((maturity - .18) / .52, f32(0), f32(1)) * 3
    whole := int(math.floor(desired))
    fraction := desired - f32(whole)
    hash := (seed * 0x9e3779b97f4a7c15 + u64(index + 1) * 0xbf58476d1ce4e5b9) ~ (u64(index + 17) * 0x94d049bb133111eb)
    if f32(hash % 10_000) < fraction * 10_000 do whole += 1
    return clamp(whole, 1, 4)
}

support_hash :: proc(support: Support_Surface) -> u64 {
    if support.signature != 0 do return support.signature
    hash := u64(0xcbf29ce484222325)
    values := []f32{support.width, support.height, support.plane_z, support.root_x}
    for value in values {
        bits := transmute(u32)value
        hash = (hash ~ u64(bits)) * 0x100000001b3
    }
    hash = (hash ~ u64(support.planter ? 1 : 0)) * 0x100000001b3
    for exclusion in support.exclusions {
        rect_values := []f32{exclusion.minimum_x, exclusion.minimum_y, exclusion.maximum_x, exclusion.maximum_y}
        for value in rect_values {
            bits := transmute(u32)value
            hash = (hash ~ u64(bits)) * 0x100000001b3
        }
    }
    return hash
}

Profile :: struct {
    axiom:           string,
    production_a:    string,
    production_b:    string,
    weight_a:        u32,
    weight_b:        u32,
    base_iterations: int,
    step:            f32,
    step_scale:      f32,
    angle:           f32,
    radius:          f32,
    radius_scale:    f32,
    width_scale:     f32,
    height_scale:    f32,
}

profile_for :: proc(species: Species) -> Profile {
    switch species {
    case .Italian_Cypress:
        return {
            "FF",
            "F[L][+&F[L]][-&F[L]][/&F[L]][\\&F[L]]F[L]",
            "F[L][+&F[L]][-&F[L]]F[L][/&L][\\&L]",
            3,
            2,
            3,
            .42,
            .94,
            .30,
            .11,
            .73,
            1.65,
            2.10,
        }
    case .Olive:
        // A broad, low crown carried by several crooked scaffold limbs.
        // Every advancing shoot emits foliage; leaving the final F bare made
        // mature trees end in conspicuous sawn-off branches.
        return {
            "FF[+&F[L]][-&F[L]][/^F[L]]",
            "F[L][+&F[L]F[L]][-&F[L]F[L]][/^F[L]]F[L]",
            "F[L][+^F[L]][-&F[L]][\\&F[L]]F[L]",
            3,
            2,
            4,
            .62,
            .85,
            .52,
            .17,
            .72,
            1.35,
            1.00,
        }
    case .Fig:
        return {"F[+F][-F]", "F[+&FL][-&FL][/FL]", "F[+FL][-FL][\\FL]", 2, 2, 3, .72, .88, .64, .19, .70, 1.22, .76}
    case .Lemon:
        // Citrus forms a compact, many-sided crown on several ascending
        // scaffold limbs. Carry leaves along every advancing shoot instead
        // of only at its tips; terminal-only foliage exposes the grammar as a
        // narrow fan and leaves the crown hollow from oblique views.
        return {
            "FF[+^F[L]][-^F[L]][/^F[L]][\\^F[L]]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/&F[L]][\\&F[L]]F[L]",
            3,
            2,
            3,
            .48,
            .86,
            .78,
            .13,
            .69,
            1.00,
            1.00,
        }
    case .Pomegranate:
        return {
            "[+^F][-^F][/^F][\\^F][F]",
            "F[+&FL][-&FL]F",
            "F[+FL][/FL][-FL]",
            3,
            2,
            3,
            .54,
            .88,
            .46,
            .045,
            .72,
            1.00,
            .94,
        }
    case .Almond:
        // Almonds develop an open, rounded vase above a short clear trunk.
        // Four rising scaffold limbs keep the crown volumetric, while leaves
        // along each continuing shoot avoid the old bare, planar leader with
        // a single tuft at its apex.
        return {
            "FFF[+^F[L]][-^F[L]][/^F[L]][\\^F[L]]",
            "F[L][+^F[L]][-^F[L]]F[L]",
            "F[L][/^F[L]][\\^F[L]]F[L]",
            3,
            2,
            3,
            .60,
            .86,
            .55,
            .14,
            .70,
            1.00,
            1.00,
        }
    case .Oleander:
        // Opposite whorls continue down each cane; terminal-only L markers
        // leave a mature hedge as a set of bare radial spokes. Carry foliage
        // sites on both the advancing cane and each newly forked shoot.
        return {
            "[+^F[L]][-^F[L]][/^F[L]][\\^F[L]][F[L]]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][+F[L]][-F[L]][/F[L]]",
            3,
            2,
            3,
            .50,
            .87,
            .42,
            .04,
            .70,
            .96,
            .90,
        }
    case .Rosemary:
        // Rosemary carries dense opposite leaf clusters along fine, repeatedly
        // forked, ascending shoots. Pitching every basal leader outward while
        // retaining a central leader produces the rounded, upright habit of a
        // mature shrub; the earlier mostly yawed fan collapsed into a flat
        // candelabra. Keeping L on advancing stems and branch tips avoids bare
        // radial spokes.
        return {
            "[+&F[L]][-^F[L]][/&F[L]][\\^F[L]][F[L]]",
            "F[L][+&F[L][/L]][-&F[L][\\L]]F[L][/L][\\L]",
            "F[L][/^F[L]][\\^F[L]]F[L][+L][-L]",
            3,
            2,
            3,
            .25,
            .84,
            .60,
            .011,
            .63,
            .96,
            .92,
        }
    case .Grapevine:
        return {"FF", "F[+FL][-FL]F[+FL]", "F[+FL]F[-FL]", 3, 2, 3, .62, .91, .48, .11, .74, 1.35, .84}
    case .Bougainvillea:
        // Bougainvillea clothes long advancing canes as well as their branch
        // tips. Keeping L sites on each rewritten leader section produces the
        // continuous bracted mass seen across lintels instead of two isolated
        // terminal pom-poms at opposite ends of a support.
        return {
            "[+&F[L]][-&F[L]]F[L]F[L]",
            "F[L][+&F[L]][-&F[L]]F[L][/&F[L]]",
            "F[L][+&F[L]]F[L][-&F[L]][\\F[L]]",
            3,
            2,
            3,
            .66,
            .91,
            .42,
            .10,
            .73,
            1.18,
            1.04,
        }
    case .Stone_Pine:
        // A clean trunk opens into long, rising scaffold limbs and a broad
        // umbrella crown carrying dense terminal needle bundles.
        return {
            "FFFF",
            "F[+^FFL][-^FFL][/^FL][\\^FL]",
            "F[+^FL][-^FL]F[/^FL]",
            3,
            2,
            3,
            .76,
            .88,
            .58,
            .18,
            .70,
            2.00,
            1.12,
        }
    case .Bay_Laurel:
        return {"FF", "F[L][+&FL][-&FL][/FL]", "F[L][+FL][-FL]F[L]", 3, 2, 3, .54, .86, .46, .12, .70, 1.02, 1.10}
    case .Carob:
        return {
            "FF[+F][-F]",
            "F[L][+&FFL][-&FFL][/FL]",
            "F[L][+FL][-FL][\\FL]",
            3,
            2,
            3,
            .68,
            .87,
            .56,
            .18,
            .71,
            1.36,
            .96,
        }
    case .Strawberry_Tree:
        return {
            "F[+F][-F][/F]",
            "F[L][+&FL][-&FL]F[L]",
            "F[L][+FL][-FL][/FL]",
            3,
            2,
            3,
            .57,
            .87,
            .48,
            .13,
            .71,
            1.04,
            1.05,
        }
    case .Myrtle:
        return {
            "[+&F][-^F][/&F][\\^F][F]",
            "F[L][+&FL][-&FL]F[L]",
            "F[L][+FL][-FL][/FL]",
            3,
            2,
            3,
            .40,
            .85,
            .43,
            .024,
            .68,
            .78,
            1.15,
        }
    case .Mastic:
        return {
            "[+^F][-^F][/^F][\\^F][^F][F]",
            "F[L][+&FL][-&FL]F[L]",
            "F[L][/FL][\\FL][-FL]",
            3,
            2,
            3,
            .32,
            .86,
            .52,
            .026,
            .69,
            .75,
            1.00,
        }
    case .Lavender:
        return {
            "[+&F[L]][-&F[L]][/&F[L]][\\&F[L]][F[L]]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/&F[L]][\\&F[L]]F[L]",
            3,
            2,
            3,
            .22,
            .83,
            .54,
            .010,
            .62,
            .88,
            .98,
        }
    case .Thyme:
        return {
            "[+&F[L]][-&F[L]][/&F[L]][\\&F[L]]",
            "F[L][+&F[L]][-&F[L]]",
            "F[L][/F[L]][\\F[L]]",
            3,
            2,
            3,
            .14,
            .82,
            .62,
            .0045,
            .61,
            1.22,
            .52,
        }
    case .Sage:
        // Sage carries opposite broad leaves down its soft basal and advancing
        // shoots. Terminal-only markers exaggerate bare gaps between plants
        // even when their botanical crown envelopes overlap.
        return {
            "[+F[L]][-F[L]][/F[L]][\\F[L]]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/F[L]][\\F[L]]F[L]",
            3,
            2,
            3,
            .27,
            .84,
            .52,
            .018,
            .65,
            .95,
            1.00,
        }
    case .Prickly_Pear:
        // Short woody links act as pad joints; the large, thick ovate leaf
        // traits below supply the recognizable flattened cladodes.
        return {
            "[L][+^F[L]][-^F[L]][/^F[L]][\\^F[L]][F[L]]",
            "F[L][+&F[L]][-&F[L]]",
            "F[L][/&F[L]][\\&F[L]]",
            3,
            2,
            2,
            .32,
            .88,
            .76,
            .025,
            .72,
            1.18,
            .95,
        }
    case .Pelargonium:
        // Courtyard pelargoniums form soft basal mounds with repeated,
        // slightly ascending shoots. Broad lobed leaves clothe each advance
        // while flower markers remain distributed throughout the crown.
        return {
            "[+&F[L]][-&F[L]][/&F[L]][\\&F[L]][F[L]]",
            "F[L][+&F[L]][-&F[L]]",
            "F[L][/&F[L]][\\&F[L]]",
            3,
            2,
            3,
            .18,
            .82,
            .60,
            .006,
            .61,
            1.06,
            .72,
        }
    case .Wisteria:
        return {
            "[+&F[L]][-&F[L]]FFF[L]",
            "F[L][+&FF[L]][-&FF[L]]F[L]",
            "F[L][/&FF[L]][\\&FF[L]]F[L]",
            3,
            2,
            2,
            .58,
            .91,
            .42,
            .085,
            .73,
            1.32,
            1.04,
        }
    case .Climbing_Rose:
        return {
            "[+&F[L]][-&F[L]]FF[L]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/&F[L]][\\&F[L]]F[L]",
            3,
            2,
            2,
            .48,
            .89,
            .52,
            .055,
            .71,
            1.18,
            1.00,
        }
    case .Hydrangea_Bush:
        // Repeated low leaders form a deliberately clipped, rounded mound.
        return {
            "[+&F[L]][-&F[L]][/&F[L]][\\&F[L]][F[L]]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/&F[L]][\\&F[L]]F[L]",
            3,
            2,
            3,
            .31,
            .84,
            .58,
            .026,
            .66,
            1.18,
            .76,
        }
    case .Hydrangea_Tree:
        // A clean standard trunk carries a looser elevated hydrangea crown.
        return {
            "FFFF[+^F[L]][-^F[L]][/^F[L]][\\^F[L]]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/&F[L]][\\&F[L]]F[L]",
            3,
            2,
            3,
            .42,
            .86,
            .54,
            .065,
            .69,
            1.05,
            1.28,
        }
    case .Agapanthus:
        return {
            "[+^FF[L]][-^FF[L]][/^FF[L]][\\^FF[L]][FF[L]]",
            "F[L][+^F[L]]",
            "F[L][/^F[L]]",
            3,
            2,
            2,
            .24,
            .88,
            .42,
            .009,
            .65,
            .82,
            1.32,
        }
    case .Star_Jasmine:
        return {
            // Several basal searching canes establish independently before
            // their laterals knit together. Keeping a central leader as well
            // preserves upward reach at young maturities without reducing a
            // mature jasmine to one trunk with decorations.
            "[+&F[L]][-&F[L]]FF[L]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/&F[L]][\\&F[L]]F[L]",
            3,
            2,
            2,
            .42,
            .90,
            .46,
            .035,
            .72,
            1.22,
            .94,
        }
    case .Holm_Oak:
        // A low, weighty evergreen crown with crooked, spreading scaffold limbs.
        return {
            "FFF[+^F[L]][-^F[L]][/^F[L]][\\^F[L]]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/^F[L]][\\^F[L]][-F[L]]F[L]",
            3,
            2,
            3,
            .62,
            .84,
            .62,
            .20,
            .72,
            1.48,
            .86,
        }
    case .Oriental_Plane:
        // Tall trunk and an open, monumental dome suited to streets and squares.
        return {
            "FFFF[+^FF[L]][-^FF[L]][/^FF[L]][\\^FF[L]]",
            "F[L][+^F[L]][-^F[L]]F[L]",
            "F[L][/^F[L]][\\^F[L]]F[L]",
            3,
            2,
            3,
            .72,
            .87,
            .57,
            .17,
            .71,
            1.42,
            1.16,
        }
    case .European_Hackberry:
        // Fine ascending forks build a loose rounded crown with a light edge.
        return {
            "FFF[+^F[L]][-^F[L]][/^F[L]][\\^F[L]]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/F[L]][\\F[L]][+F[L]]",
            3,
            2,
            3,
            .58,
            .86,
            .49,
            .12,
            .70,
            1.24,
            1.10,
        }
    case .White_Poplar:
        // A tall oval broadleaf crown, narrower and more vertical than plane or oak.
        return {
            "FFFF[+^F[L]][-^F[L]][/^F[L]][\\^F[L]]",
            "F[L][+&F[L]][-&F[L]]F[L]",
            "F[L][/&F[L]][\\&F[L]]F[L]",
            3,
            2,
            3,
            .56,
            .86,
            .46,
            .13,
            .70,
            .90,
            1.48,
        }
    case .Golden_Barrel,
         .Agave,
         .Aloe,
         .Aeonium,
         .Echeveria,
         .Jade_Plant,
         .Stonecrop,
         .Blue_Chalk_Sticks,
         .Golden_Torch_Cactus:
        // These species bypass the branching grammar, but retain a small
        // profile so shared maturity/detail bookkeeping stays well-defined.
        return {"F", "F", "F", 1, 1, 1, .1, 1, .5, .01, .8, 1, 1}
    }
    return {}
}

attachment_kind :: proc(species: Species, index: int, maturity: f32) -> Attachment_Kind {
    switch species {
    case .Bougainvillea:
        if maturity > .16 && index % 3 != 0 do return .Flower
        if maturity > .38 && index % 11 == 0 do return .Thorn
    case .Grapevine:
        if maturity > .50 && index % 7 == 0 do return .Fruit
        if index % 5 == 0 do return .Tendril
    case .Lemon, .Pomegranate, .Strawberry_Tree:
        if maturity > .58 && index % 8 == 0 do return .Fruit
        if maturity > .22 && index % 9 == 1 do return .Flower
    case .Almond,
         .Oleander,
         .Lavender,
         .Thyme,
         .Sage,
         .Wisteria,
         .Climbing_Rose,
         .Hydrangea_Bush,
         .Hydrangea_Tree,
         .Agapanthus,
         .Star_Jasmine:
        if maturity > .22 && index % 4 == 0 do return .Flower
    case .Pelargonium:
        if maturity > .18 && index % 3 == 0 do return .Flower
    case .Fig, .Olive, .Carob, .Myrtle, .Mastic:
        if maturity > .68 && index % 12 == 0 do return .Fruit
    case .Prickly_Pear:
        // Keep the first, ground-level cladode as a pad; fruit belongs on
        // later joints near the outer edge of the clump.
        if maturity > .68 && index % 12 == 7 do return .Fruit
    case .Bay_Laurel:
        if maturity > .68 && index % 14 == 0 do return .Flower
    case .Italian_Cypress,
         .Rosemary,
         .Stone_Pine,
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
    }
    return .Leaf
}

generated_attachment_kind :: proc(
    species: Species,
    seed: u64,
    index: int,
    maturity: f32,
    detail: Detail_Level,
    depth: int,
) -> Attachment_Kind {
    if species == .Thyme {
        return depth == -8 && maturity > .32 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Lavender {
        return depth == -7 && maturity > .35 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Sage {
        return depth == -6 && maturity > .35 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Agapanthus {
        return depth == -5 && maturity > .42 && detail != .Far ? .Flower : .Leaf
    }
    if species == .Lemon {
        if detail == .Far {
            // At far detail every anchor is silhouette-critical. Fruit and
            // blossom geometry is sub-pixel here and must not replace the
            // broad leaf surrogates retained for that shoot.
            return .Leaf
        }
        // Citrus flowers and fruit belong on newer outer growth. Hashing the
        // stable seed/index pair avoids the regular modulo bands produced by
        // catalog attachment_kind while keeping captures deterministic.
        if depth >= 2 {
            hash := (seed + 1) * 0x9e3779b97f4a7c15 ~ u64(index + 11) * 0xbf58476d1ce4e5b9
            hash = (hash ~ (hash >> 29)) * 0x94d049bb133111eb
            if maturity > .58 && hash % 11 == 0 do return .Fruit
            if maturity > .22 && hash % 13 == 1 do return .Flower
        }
        return .Leaf
    }
    if species == .Pomegranate {
        if detail == .Far do return .Leaf
        // Pomegranate flowers and fruit hang from current outer shoots. The
        // catalog-wide modulo assignment put many replacements inside the
        // dense basal vase, making mature fruit disappear from normal views.
        if depth >= 1 {
            hash := (seed + 1) * 0xbf58476d1ce4e5b9 ~ u64(index + 19) * 0x94d049bb133111eb
            hash = (hash ~ (hash >> 31)) * 0x9e3779b97f4a7c15
            if maturity > .58 && hash % 9 == 0 do return .Fruit
            if maturity > .22 && hash % 11 == 1 do return .Flower
        }
        return .Leaf
    }
    if species == .Hydrangea_Bush || species == .Hydrangea_Tree {
        // Dedicated hydrangea skeletons reserve this depth exclusively for
        // terminal mopheads. Interior nodes always retain their paired leaves.
        return depth == -9 && maturity > .22 ? .Flower : .Leaf
    }
    if species == .Italian_Cypress && detail == .Near && maturity >= .78 && depth == 1 {
        // Mature Mediterranean cypresses carry sparse spherical woody cones
        // inside lateral sprays. Hashing seed and anchor index avoids regular
        // bands while keeping placement exact and deterministic. A second
        // hash gives every candidate a stable ripening threshold so cones set
        // progressively instead of all appearing at 78% maturity.
        hash := u64(index + 1) * 0x9e3779b97f4a7c15 + seed * 0xbf58476d1ce4e5b9
        if hash % 29 == 0 {
            cone_set := clamp((maturity - .78) / .18, f32(0), f32(1))
            ripening_hash := (hash ~ (hash >> 27) ~ (seed + 1) * 0x94d049bb133111eb) * 0xbf58476d1ce4e5b9
            if f32(ripening_hash % 10_000) < cone_set * 10_000 do return .Fruit
        }
    }
    if species == .Pelargonium {
        return depth == -4 ? .Flower : .Leaf
    }
    if species == .Star_Jasmine {
        if detail == .Far || maturity <= .22 do return .Leaf
        // White pinwheels need a richer, irregular distribution to remain
        // legible against the sunlit support wall. Avoid modulo rows shared
        // by matching stations on adjacent canes.
        hash := (seed + 1) * 0x9e3779b97f4a7c15 ~ u64(index + 47) * 0xbf58476d1ce4e5b9
        hash = (hash ~ (hash >> 29)) * 0x94d049bb133111eb
        return hash % 3 == 0 ? .Flower : .Leaf
    }
    return attachment_kind(species, index, maturity)
}

leaf_traits :: proc(species: Species, variant: u8, maturity: f32) -> Leaf_Traits {
    traits: Leaf_Traits
    switch species {
    case .Olive:
        traits = {.Lanceolate, .12, .032, 0, .008, .003, 0}
    case .Italian_Cypress:
        // Represent overlapping scale-leaf sprays rather than individual
        // microscopic scales; the latter disappear at ordinary game-camera
        // distances and expose the procedural scaffold.
        // Favor slim shoot-following fans over broad pads. The longer axis
        // bridges neighboring anchors, while the reduced width prevents the
        // crown from resolving into stacked rounded topiary lobes.
        traits = {.Cypress_Spray, .078, .032, 0, .013, .0045, 0}
    case .Grapevine:
        traits = {.Grapevine, .18, .16, .05, .016, .008, 0}
    case .Fig:
        traits = {.Fig, .21, .185, 0, .017, .010, 0}
    case .Lemon:
        // Citrus leaves are broad, but the old footprint let neighboring
        // alternate shoots overlap into a wall of flat cards at near detail.
        // Keep the elliptic silhouette while restoring visible twig and fruit
        // gaps through the crown.
        traits = {.Elliptic, .145, .062, .04, .011, .005, 0}
    case .Pomegranate:
        traits = {.Lanceolate, .115, .040, 0, .008, .004, 0}
    case .Almond:
        traits = {.Lanceolate, .15, .048, .08, .010, .004, 0}
    case .Oleander:
        traits = {.Lanceolate, .18, .035, 0, .012, .004, 0}
    case .Bougainvillea:
        traits = {.Ovate, .13, .090, 0, .014, .006, 0}
    case .Rosemary:
        traits = {.Lanceolate, .034, .004, 0, .005, .0008, 0}
    case .Stone_Pine:
        // Each rendered blade stands for a compact fascicle. Long individual
        // needles turn terminal pads into radial spikes at game scale; shorter
        // overlapping blades merge into the dense umbrella silhouette while
        // retaining a fine fringed edge.
        traits = {.Lanceolate, .13, .018, 0, .014, .0014, 0}
    case .Bay_Laurel:
        traits = {.Lanceolate, .16, .052, .04, .014, .006, 0}
    case .Carob:
        traits = {.Elliptic, .105, .066, 0, .008, .006, 0}
    case .Strawberry_Tree:
        traits = {.Elliptic, .13, .055, .11, .012, .005, 0}
    case .Myrtle:
        traits = {.Lanceolate, .075, .025, 0, .008, .003, 0}
    case .Mastic:
        traits = {.Elliptic, .072, .031, 0, .007, .003, 0}
    case .Lavender:
        traits = {.Lanceolate, .052, .014, 0, .008, .002, 0}
    case .Thyme:
        traits = {.Ovate, .020, .009, 0, .003, .001, 0}
    case .Sage:
        traits = {.Ovate, .105, .055, .12, .018, .012, 0}
    case .Prickly_Pear:
        // The grammar already builds a multi-generation clump. Metre-scale
        // presentation of the old .48 pad stacked those generations into a
        // hedge; a compact cladode keeps joints and stepped tiers readable.
        traits = {.Ovate, .36, .21, 0, .016, .045, .070}
    case .Pelargonium:
        // Broad, nearly round and shallowly scalloped: this silhouette is the
        // strongest distinction between pelargonium and a generic shrub.
        traits = {.Lobed, .090, .082, .032, .013, .007, 0}
    case .Wisteria:
        traits = {.Elliptic, .105, .052, 0, .010, .004, 0}
    case .Climbing_Rose:
        traits = {.Ovate, .105, .062, .08, .012, .006, 0}
    case .Hydrangea_Bush, .Hydrangea_Tree:
        // Hydrangea leaves are broad ovates rather than long lance-like
        // blades. A near-square footprint keeps isolated crown-edge leaves
        // from projecting as spears while retaining their coarse silhouette.
        traits = {.Ovate, .158, .136, .12, .022, .012, 0}
    case .Agapanthus:
        traits = {.Lanceolate, .31, .030, 0, .020, .006, 0}
    case .Star_Jasmine:
        traits = {.Elliptic, .080, .043, 0, .009, .004, 0}
    case .Holm_Oak:
        traits = {.Ovate, .125, .068, .10, .013, .007, 0}
    case .Oriental_Plane:
        traits = {.Lobed, .19, .17, .06, .018, .008, 0}
    case .European_Hackberry:
        traits = {.Ovate, .105, .052, .12, .012, .005, 0}
    case .White_Poplar:
        traits = {.Deltoid, .115, .105, .08, .014, .007, 0}
    case .Golden_Barrel:
        // One narrow, deeply cupped blade reads as a single vertical rib;
        // the radial skeleton closes those ribs into a squat barrel.
        traits = {.Lanceolate, .42, .075, 0, .010, .055, .060}
    case .Agave:
        traits = {.Lanceolate, .58, .115, .06, .040, .045, .038}
    case .Aloe:
        traits = {.Lanceolate, .38, .072, .08, .055, .032, .030}
    case .Aeonium:
        traits = {.Ovate, .22, .105, 0, .018, .020, .026}
    case .Echeveria:
        traits = {.Ovate, .20, .115, 0, .026, .028, .034}
    case .Jade_Plant:
        traits = {.Ovate, .105, .072, 0, .008, .022, .030}
    case .Stonecrop:
        traits = {.Ovate, .040, .020, 0, .004, .010, .016}
    case .Blue_Chalk_Sticks:
        traits = {.Lanceolate, .19, .034, 0, .012, .014, .030}
    case .Golden_Torch_Cactus:
        traits = {.Lanceolate, .78, .080, 0, .006, .040, .052}
    }
    variation := .92 + f32(variant) * .055
    maturity_scale := .72 + clamp(maturity, f32(0), f32(1)) * .28
    traits.length *= variation * maturity_scale
    traits.width *= (1.04 - f32(variant) * .025) * maturity_scale
    traits.curl *= variant % 2 == 0 ? f32(1) : f32(-1)
    return traits
}

generated_leaf_traits :: proc(species: Species, variant: u8, maturity: f32, detail: Detail_Level) -> Leaf_Traits {
    traits := leaf_traits(species, variant, maturity)
    if species == .Italian_Cypress {
        // Reduced tiers represent whole overlapping scale-leaf sprays. Their
        // footprint grows as geometry falls so the distant crown converges
        // toward a solid silhouette instead of exposing individual twigs.
        length_scale := detail == .Far ? f32(2.05) : detail == .Medium ? f32(1.10) : f32(1)
        width_scale := detail == .Far ? f32(3.5) : detail == .Medium ? f32(2.2) : f32(1)
        traits.length *= length_scale
        traits.width *= width_scale
        traits.curl *= length_scale
        traits.cup *= width_scale
    }
    if species == .Olive {
        // With opposite pairs collapsed from two leaves to one at far detail,
        // treat the survivor as a small spray surrogate. Width grows more
        // than length so distant foliage fills crown mass instead of becoming
        // a set of longer fern-like strokes.
        length_scale := detail == .Far ? f32(1.60) : detail == .Medium ? f32(1.14) : f32(1)
        width_scale := detail == .Far ? f32(3.00) : detail == .Medium ? f32(1.28) : f32(1)
        traits.length *= length_scale
        traits.width *= width_scale
        traits.curl *= length_scale
        traits.cup *= width_scale
    }
    if species == .Lemon {
        // Reduced tiers collapse whole glossy citrus sprays into a few
        // anchors. Broaden those survivors into canopy surrogates so the
        // radial scaffold does not reappear as a bare candelabra.
        length_scale := detail == .Far ? f32(1.90) : detail == .Medium ? f32(1.12) : f32(1)
        width_scale := detail == .Far ? f32(3.20) : detail == .Medium ? f32(1.35) : f32(1)
        traits.length *= length_scale
        traits.width *= width_scale
        traits.curl *= length_scale
        traits.cup *= width_scale
    }
    return traits
}

attachment_frame :: proc(
    forward, up: lsystem.Vec3,
    profile: Profile,
    climbing: bool,
) -> (
    result_forward, result_up: lsystem.Vec3,
) {
    result_forward = {
        forward[0] * profile.width_scale,
        forward[1] * profile.height_scale,
        forward[2] * profile.width_scale,
    }
    result_up = {up[0] * profile.width_scale, up[1] * profile.height_scale, up[2] * profile.width_scale}
    if climbing {
        result_forward[2] = 0
        if linalg.dot(result_forward, result_forward) < .001 do result_forward = {0, 1, 0}
        result_forward = linalg.normalize0(result_forward)
        result_up = {0, 0, 1}
        return
    }
    result_forward = linalg.normalize0(result_forward)
    if linalg.dot(result_forward, result_forward) < .001 do result_forward = {0, 1, 0}
    // Gram-Schmidt keeps up perpendicular after non-uniform species scaling.
    result_up -= result_forward * linalg.dot(result_up, result_forward)
    result_up = linalg.normalize0(result_up)
    if linalg.dot(result_up, result_up) < .001 {
        reference := math.abs(result_forward[1]) < .9 ? lsystem.Vec3{0, 1, 0} : lsystem.Vec3{1, 0, 0}
        right := linalg.normalize0(linalg.cross(result_forward, reference))
        result_up = linalg.normalize0(linalg.cross(right, result_forward))
    }
    return
}

update_leaf_bounds :: proc(bounds: ^Bounds, position, forward, up: lsystem.Vec3, traits: Leaf_Traits, first: ^bool) {
    right := linalg.normalize0(linalg.cross(forward, up))
    if linalg.dot(right, right) < .001 do right = {1, 0, 0}
    half_width := traits.width * .5
    lift := math.abs(traits.curl) + math.abs(traits.cup)
    stations := [2]lsystem.Vec3{position, position + forward * traits.length}
    sides := [2]f32{-1, 1}
    for station in stations {
        for side in sides {
            update_bounds(bounds, station + right * half_width * side + up * lift, first)
            update_bounds(bounds, station + right * half_width * side - up * lift, first)
        }
    }
}

route_point :: proc(
    point: lsystem.Vec3,
    support: ^Support_Surface,
    source_height, source_half_width: f32,
    habit: Growth_Habit,
    depth: int,
) -> lsystem.Vec3 {
    result := point
    height_fraction := clamp(point[1] / max(source_height, f32(.001)), f32(0), f32(1))
    root_x := clamp(support.root_x, -support.width * .46, support.width * .46)
    opposite_x := root_x <= 0 ? support.width * .42 : -support.width * .42
    if habit == .Trellised && depth <= -20 {
        normalized_x := clamp(point[0] / max(source_half_width, f32(.001)), f32(-1), f32(1))
        if math.abs(root_x) > support.width * .20 {
            // End-planted vines train one long cordon across the support.
            // Preserve the trunk at the authored centre while mapping cordon
            // and fruiting-shoot positions through the full root-to-end span.
            if depth == -23 {
                result[0] = root_x
            } else {
                fraction := (normalized_x + 1) * .5
                result[0] = root_x + (opposite_x - root_x) * fraction
            }
        } else {
            result[0] = root_x + normalized_x * support.width * .42
        }
        result[0] = clamp(result[0], -support.width * .48, support.width * .48)
        result[1] = height_fraction * support.height * .92
        // Ties and wire hold grape canes slightly proud of the wall. Keeping
        // them exactly coplanar causes alternating spans to lose the depth
        // test and appear as disconnected dashes in the lab.
        result[2] = support.plane_z + .16
        for exclusion in support.exclusions {
            if result[0] < exclusion.minimum_x || result[0] > exclusion.maximum_x ||
               result[1] < exclusion.minimum_y || result[1] > exclusion.maximum_y {
                continue
            }
            margin := f32(.12)
            // Preserve a continuous root-side route around openings. Stable
            // side choice prevents neighboring phytomer anchors from
            // alternating across a window and drawing canes through it.
            exclusion_center := (exclusion.minimum_x + exclusion.maximum_x) * .5
            if root_x <= exclusion_center {
                result[0] = exclusion.minimum_x - margin
            } else {
                result[0] = exclusion.maximum_x + margin
            }
            result[0] = clamp(result[0], -support.width * .48, support.width * .48)
        }
        return result
    }
    // Source x is the botanical left/right axis: opposing yaw branches must
    // remain opposing when flattened onto the wall. Depth contributes only a
    // small offset to separate shoots that would otherwise overlap. Giving
    // both axes equal weight made similarly pitched left and right canes
    // inherit the same z sign and collapse onto one side of the support.
    lateral_source := point[0] + point[2] * .18
    lateral_fraction := clamp(lateral_source / max(source_half_width, f32(.001)), f32(-1), f32(1))
    // Projection must be a function of source position alone. Parent ends and
    // child starts share a botanical point but have different depths; using
    // depth here pulled those identical junctions apart into floating tufts.
    branch_order := math.abs(lateral_fraction) * 3
    spread_envelope := .16 + height_fraction * .84
    lateral_spread := lateral_fraction * support.width * (.25 + branch_order * .055) * spread_envelope
    // Real wall climbers do not train every shoot along one shared diagonal.
    // Keep the leader near its root with a slow searching meander, then let
    // lateral and secondary shoots use the source plant's two horizontal
    // axes to fan across the available surface. A small directional drift
    // still prevents a ruler-straight central cane without overpowering the
    // generated forks.
    leader_meander :=
        f32(math.sin(f64(height_fraction * math.PI * 2.35 + lateral_fraction * .71))) *
        support.width *
        (.035 + branch_order * .010) *
        spread_envelope
    directional_drift := (opposite_x - root_x) * height_fraction * (.10 + min(branch_order, f32(1)) * .05)
    result[0] = root_x + directional_drift + lateral_spread + leader_meander
    result[1] = height_fraction * support.height * .96
    result[2] = support.plane_z
    result[0] = clamp(result[0], -support.width * .48, support.width * .48)
    if habit == .Trellised {
        // A trellised vine climbs freely to its first wire, then trains its
        // generated leader and branches along four horizontal tiers. Snapping
        // only the support projection—not the L-system—retains botanical
        // branching while removing the unsupported diagonal curtain.
        raw_y := height_fraction * support.height * .96
        first_wire := min(f32(.55), support.height * .22)
        top_wire := support.height * .96
        tier_spacing := (top_wire - first_wire) / 3
        if raw_y < first_wire {
            result[0] = root_x + lateral_spread * .20
            result[1] = raw_y
        } else {
            training_progress := clamp((raw_y - first_wire) / max(top_wire - first_wire, f32(.001)), f32(0), f32(1))
            training_progress = training_progress * training_progress * (3 - 2 * training_progress)
            // Train opposing shoots into bilateral cordons. Choosing one
            // `opposite_x` for a centered root sent the entire grapevine to
            // the right-hand side regardless of its generated branch axis.
            source_angle := f32(math.atan2(f64(point[2]), f64(point[0])))
            trellis_lateral := clamp(source_angle / math.PI, f32(-1), f32(1))
            cordon_reach: f32
            if math.abs(root_x) > support.width * .20 {
                // A vine planted at the end of a trellis trains primarily
                // across it; treating the root as the centre of a bilateral
                // cordon wastes half the support outside the frame.
                reach_fraction := .72 + math.abs(trellis_lateral) * .28
                cordon_reach = (opposite_x - root_x) * reach_fraction * training_progress
            } else {
                cordon_reach = trellis_lateral * support.width * .42 * training_progress
            }
            result[0] = root_x + cordon_reach + lateral_spread * .48
            tier := clamp(int(math.round(f64((raw_y - first_wire) / max(tier_spacing, f32(.001))))), 0, 3)
            wire_y := first_wire + f32(tier) * tier_spacing
            if depth == 0 {
                // Keep the structural leader and cordons trained on wires.
                result[1] = wire_y
            } else {
                // Fruiting shoots grow away from a cordon; snapping their
                // every node and leaf anchor to the same wire created four
                // topiary shelves. Retain most generated height while a mild
                // wire bias keeps the canopy visibly trained.
                result[1] = raw_y * .82 + wire_y * .18
            }
        }
        result[0] = clamp(result[0], -support.width * .48, support.width * .48)
    }
    for exclusion in support.exclusions {
        exclusion_center := (exclusion.minimum_x + exclusion.maximum_x) * .5
        clearance := max(f32(.18), support.height * .12)
        release_fraction := clamp(
            exclusion.maximum_y / max(support.height, f32(.001)),
            f32(0),
            f32(.98),
        )
        // Planters and low plinths can raise a doorway exclusion slightly;
        // distinguish those from upper windows by relative wall height.
        ground_opening := exclusion.minimum_y <= support.height * .18
        if habit == .Wall_Trained && ground_opening && height_fraction > release_fraction {
            // Train the connected canopy across the lintel while retaining
            // each shoot's authored lateral displacement. Remapping the rise
            // keeps attachment-bearing portions on the wall instead of
            // leaving long bare connectors to isolated roofline tufts.
            canopy_progress := clamp(
                (height_fraction - release_fraction) / max(1 - release_fraction, f32(.001)),
                f32(0),
                f32(1),
            )
            canopy_progress = canopy_progress * canopy_progress * (3 - 2 * canopy_progress)
            result[0] =
                root_x +
                (opposite_x - root_x) * canopy_progress * .94 +
                lateral_spread
            lintel_top := support.height * .96
            result[1] =
                exclusion.maximum_y + .02 +
                (lintel_top - exclusion.maximum_y - .02) * canopy_progress
            result[0] = clamp(result[0], -support.width * .48, support.width * .48)
            continue
        }
        // Hold the routed side for enough vertical distance that a tessellated
        // segment can turn above the opening without its chord cutting back
        // through the exclusion. Once clear, restore each shoot's generated
        // lateral position. Forcing every upper shoot to traverse the lintel
        // from root side to opposite side collapsed a branching canopy into
        // one conspicuous diagonal perimeter stroke.
        if result[1] < exclusion.minimum_y || result[1] > exclusion.maximum_y + clearance {
            continue
        }
        margin := f32(.12)
        // Keep the vine on the root side while it climbs past an opening.
        // Choosing the nearest edge independently allowed connected segment
        // endpoints to flip sides and draw a branch straight through a door.
        edge_spread := math.abs(lateral_fraction) * support.width * .10
        if root_x <= exclusion_center {
            result[0] = min(result[0], exclusion.minimum_x - margin - edge_spread)
        } else {
            result[0] = max(result[0], exclusion.maximum_x + margin + edge_spread)
        }
        result[0] = clamp(result[0], -support.width * .48, support.width * .48)
    }
    return result
}

update_bounds :: proc(bounds: ^Bounds, point: lsystem.Vec3, first: ^bool) {
    if first^ {
        bounds.minimum = point
        bounds.maximum = point
        first^ = false
        return
    }
    bounds.minimum = linalg.min(bounds.minimum, point)
    bounds.maximum = linalg.max(bounds.maximum, point)
}

olive_random_signed :: proc(random: ^u64) -> f32 {
    return f32(lsystem.random_next(random) >> 40) / f32(1 << 24) * 2 - 1
}

pelargonium_skeleton :: proc(seed: u64, maturity: f32) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    growth := clamp(maturity, f32(0), f32(1))
    eased := growth * growth * (3 - 2 * growth)
    size := .16 + eased * .84
    stem_count := 3 + int(math.floor(eased * 9.99))
    node_count := 2 + int(math.floor(eased * 2.99))
    random := seed ~ 0x70656c6172676f6e
    phase := olive_random_signed(&random) * math.PI

    for stem_index in 0 ..< stem_count {
        azimuth := phase + f32(stem_index) * 2.399963 + olive_random_signed(&random) * .16
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
        position := radial * (.018 + f32(stem_index % 3) * .008) * size
        stem_lean := .58 + f32(stem_index % 4) * .040
        direction := linalg.normalize0(
            radial * stem_lean + tangent * olive_random_signed(&random) * .08 + lsystem.Vec3{0, .72, 0},
        )
        // Pelargonium carries fleshy but comparatively slender green-brown
        // stems; tree-scale radii make a patio plant read as a bonsai.
        radius := (.002 + eased * .0012) * (1 + olive_random_signed(&random) * .08)

        for node_index in 0 ..< node_count {
            node_progress := f32(node_index) / f32(max(node_count - 1, 1))
            length :=
                (.050 + eased * .025) * (1 - node_progress * .10) * (1 + olive_random_signed(&random) * .08) * size
            direction = linalg.normalize0(
                direction + radial * (.035 + node_progress * .025) + tangent * olive_random_signed(&random) * .025,
            )
            next := position + direction * length
            append(
                &result.plant.segments,
                lsystem.Segment {
                    start = position,
                    end = next,
                    radius_start = radius,
                    radius_end = radius * .78,
                    depth = 0,
                },
            )
            append(
                &result.plant.leaves,
                lsystem.Leaf {
                    position = next,
                    forward  = direction,
                    up       = radial,
                    depth    = 0,
                },
            )
            position = next
            radius *= .78
        }

        if growth >= .30 && stem_index % 2 == 0 {
            flowering := clamp((growth - .30) / .70, f32(0), f32(1))
            peduncle_direction := linalg.normalize0(direction * .34 + radial * .08 + lsystem.Vec3{0, .94, 0})
            // Keep the head just above its subtending leaf. The previous
            // long bare peduncle made blossoms look disconnected from the
            // otherwise compact patio mound.
            flower_tip := position + peduncle_direction * (.055 + flowering * .028) * size
            append(
                &result.plant.segments,
                lsystem.Segment {
                    start = position,
                    end = flower_tip,
                    radius_start = max(radius * .48, f32(.0012)),
                    radius_end = .0007,
                    depth = 2,
                },
            )
            append(
                &result.plant.leaves,
                lsystem.Leaf {
                    position = flower_tip,
                    forward = {0, 1, 0},
                    up = radial,
                    depth = -4,
                },
            )
        }
    }
    return result
}

hydrangea_skeleton :: proc(
    species: Species,
    seed: u64,
    maturity: f32,
    detail: Detail_Level,
) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x68796472616e6765
    if random == 0 do random = 1
    growth := .22 + clamp(maturity, f32(0), f32(1)) * .78
    is_tree := species == .Hydrangea_Tree
    stem_count := is_tree ? (detail == .Near ? 11 : detail == .Medium ? 8 : 6) :
        (detail == .Near ? 24 : detail == .Medium ? 20 : 18)
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    crown_base := lsystem.Vec3{}
    crown_radius := f32(.010) * (.35 + maturity * .65)

    if is_tree {
        trunk_radius := f32(.045) * (.35 + maturity * .65)
        position := lsystem.Vec3{}
        for trunk_index in 0 ..< 4 {
            drift_angle := phase + f32(trunk_index) * 1.7
            next := position + lsystem.Vec3 {
                math.cos(drift_angle) * .012 * growth,
                .245 * growth,
                math.sin(drift_angle) * .012 * growth,
            }
            end_radius := trunk_radius * .84
            append(&result.plant.segments, lsystem.Segment{position, next, trunk_radius, end_radius, 0})
            position = next
            trunk_radius = end_radius
        }
        crown_base = position
        crown_radius = trunk_radius * .30
    }

    for stem_index in 0 ..< stem_count {
        inner_stem := !is_tree && stem_index % 3 == 0
        ring_count := inner_stem ? max(stem_count / 3, 1) : max(stem_count - stem_count / 3, 1)
        ring_index := inner_stem ? stem_index / 3 : stem_index - (stem_index + 2) / 3
        ring_phase := inner_stem ? phase + math.PI / f32(ring_count) : phase
        azimuth := ring_phase + f32(ring_index) * math.PI * 2 / f32(ring_count) + olive_random_signed(&random) * .10
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
        position := crown_base
        if !is_tree {
            base_spread := inner_stem ? f32(.018) : f32(.052 + f32(ring_index % 3) * .012)
            position = radial * base_spread * growth
        }
        stem_origin := position
        radius := (is_tree ? crown_radius : f32(.009) * (.35 + maturity * .65)) *
            (1 + olive_random_signed(&random) * .10)
        segment_count := 3
        crown_reach := inner_stem ? f32(.16) : f32(.50)
        reach := (is_tree ? f32(.52) : crown_reach) *
            (1 + olive_random_signed(&random) * .16) * growth
        crown_rise := inner_stem ? f32(.70) :
            f32(.56 + f32(ring_index % 5) * .018)
        rise := (is_tree ? f32(.56) : crown_rise) *
            (1 + olive_random_signed(&random) * .14) * growth
        bow := tangent * olive_random_signed(&random) * .075 * growth
        for segment_index in 0 ..< segment_count {
            progress := f32(segment_index + 1) / f32(segment_count)
            // Hydrangea shoots bow outward early, then turn upward into a
            // clipped crown envelope. Explicit targets avoid the repeated
            // rising direction that produced a bare V-shaped candelabrum.
            outward_progress := math.sin(progress * math.PI * .5)
            height_progress := progress * (.78 + progress * .22)
            next := stem_origin +
                radial * reach * outward_progress +
                bow * math.sin(progress * math.PI) +
                lsystem.Vec3{0, rise * height_progress, 0}
            direction := linalg.normalize0(next - position)
            end_radius := radius * .72
            append(
                &result.plant.segments,
                lsystem.Segment{position, next, radius, end_radius, segment_index + 1},
            )
            // Opposite leaf pairs clothe each shoot from its first node while
            // leaving enough gaps for the woody structure to remain readable.
            leaf_position := linalg.lerp(position, next, .58)
            // Hydrangea blades project across their shoots in broad opposite
            // pairs. Following the rising shoot made them render as thin,
            // edge-on spears and exposed the entire radial scaffold.
            leaf_forward := linalg.normalize0(tangent + radial * olive_random_signed(&random) * .10)
            leaf_normal := linalg.normalize0(
                lsystem.Vec3{0, .72, 0} + radial * (.62 + olive_random_signed(&random) * .10),
            )
            append(
                &result.plant.leaves,
                lsystem.Leaf{position = leaf_position, forward = leaf_forward, up = leaf_normal, depth = segment_index + 1},
                lsystem.Leaf{position = next, forward = leaf_forward, up = leaf_normal, depth = segment_index + 1},
            )
            position = next
            radius = end_radius
        }
        if maturity > .22 {
            // This marker becomes one terminal mophead and never displaces
            // the paired leaves at the final vegetative node above. Before
            // flowering, omit it entirely rather than converting this
            // reserved frame into an upright, non-botanical leaf card.
            append(
                &result.plant.leaves,
                lsystem.Leaf {
                    position = position + lsystem.Vec3{0, .042 * growth, 0},
                    // Terminal heads remain predominantly upright, with a
                    // small radial lean that breaks the nursery-perfect row.
                    forward = linalg.normalize0(radial * .12 + lsystem.Vec3{0, .99, 0}),
                    up = radial,
                    depth = -9,
                },
            )
        }
    }
    return result
}

rosemary_skeleton :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x726f73656d617279
    if random == 0 do random = 1
    growth := .24 + clamp(maturity, f32(0), f32(1)) * .76
    stem_count := detail == .Near ? 20 : detail == .Medium ? 14 : 9
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    leaf_fractions := [5]f32{.10, .30, .50, .70, .90}
    for stem_index in 0 ..< stem_count {
        azimuth := phase + f32(stem_index) * math.PI * 2 / f32(stem_count) + olive_random_signed(&random) * .11
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
        position := radial * (.018 + f32(stem_index % 3) * .008) * growth
        radius := .0018 * (.30 + maturity * .70)
        for segment_index in 0 ..< 4 {
            direction := linalg.normalize0(
                radial * (.30 + f32(segment_index) * .035) +
                tangent * olive_random_signed(&random) * .055 +
                lsystem.Vec3{0, .96, 0},
            )
            next := position + direction * (.068 * growth * (1 + olive_random_signed(&random) * .07))
            append(&result.plant.segments, lsystem.Segment{position, next, radius, radius * .74, segment_index})
            for fraction, fraction_index in leaf_fractions {
                leaf_position := linalg.lerp(position, next, fraction)
                leaf_azimuth := azimuth + f32(segment_index * len(leaf_fractions) + fraction_index) * 2.399963
                outward := lsystem.Vec3{math.cos(leaf_azimuth), .10, math.sin(leaf_azimuth)}
                append(
                    &result.plant.leaves,
                    lsystem.Leaf {
                        position = leaf_position,
                        forward = linalg.normalize0(outward),
                        up = {-outward[2], 0, outward[0]},
                        depth = segment_index,
                    },
                )
            }
            position = next
            radius *= .74
        }
    }
    return result
}

grapevine_skeleton :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x677261706576696e
    if random == 0 do random = 1
    growth := .28 + clamp(maturity, f32(0), f32(1)) * .72
    cordon_y := .34 * growth

    // Permanent wood: a subtly irregular trunk reaches a bilateral Royat
    // cordon. The trunk has a distinct depth so an end-planted support can
    // keep it at the root while mapping the cordon across the available span.
    trunk_mid_a := lsystem.Vec3{.010 * olive_random_signed(&random), cordon_y * .34, .008}
    trunk_mid_b := lsystem.Vec3{-.008 * olive_random_signed(&random), cordon_y * .70, -.006}
    append(
        &result.plant.segments,
        lsystem.Segment{{0, 0, 0}, trunk_mid_a, .050, .040, -23},
        lsystem.Segment{trunk_mid_a, trunk_mid_b, .040, .031, -23},
        lsystem.Segment{trunk_mid_b, {0, cordon_y, 0}, .031, .024, -23},
    )
    cordon_links := 12
    for link_index in 0 ..< cordon_links {
        x0 := -1 + f32(link_index) * 2 / f32(cordon_links)
        x1 := -1 + f32(link_index + 1) * 2 / f32(cordon_links)
        y0 := cordon_y + f32(math.sin(f64(x0 * math.PI))) * .018 * growth
        y1 := cordon_y + f32(math.sin(f64(x1 * math.PI))) * .018 * growth
        radial_position := max(math.abs(x0), math.abs(x1))
        radius := .025 - radial_position * .011
        append(
            &result.plant.segments,
            lsystem.Segment{{x0, y0, 0}, {x1, y1, 0}, radius, max(radius * .94, f32(.010)), -20},
        )
    }

    // Spur heads are approximately hand-width apart, with small spacing
    // irregularity and occasional dormant positions. Each retained spur is
    // short old wood bearing one, occasionally two, flexible annual shoots.
    spur_count := detail == .Near ? 10 : detail == .Medium ? 8 : 6
    for spur_index in 0 ..< spur_count {
        fraction := (f32(spur_index) + .5) / f32(spur_count)
        x := -1 + fraction * 2 + olive_random_signed(&random) * .025
        x = clamp(x, f32(-.94), f32(.94))
        local_cordon_y := cordon_y + f32(math.sin(f64(x * math.PI))) * .018 * growth
        cordon_point := lsystem.Vec3{x, local_cordon_y, 0}
        spur_side := spur_index % 2 == 0 ? f32(-1) : f32(1)
        spur_tip := cordon_point + lsystem.Vec3{spur_side * .012, .040 * growth, .010 * spur_side}
        append(
            &result.plant.segments,
            lsystem.Segment{cordon_point, spur_tip, .011, .008, -22},
        )

        active_threshold := .38 + clamp(maturity, f32(0), f32(1)) * .57
        if f32(lsystem.random_next(&random) % 10_000) / 10_000 > active_threshold do continue
        annual_count := detail == .Near && lsystem.random_next(&random) % 5 == 0 ? 2 : 1
        for annual_index in 0 ..< annual_count {
            phytomer_count := detail == .Near ? 6 + int(lsystem.random_next(&random) % 4) :
                              detail == .Medium ? 5 + int(lsystem.random_next(&random) % 3) :
                              4 + int(lsystem.random_next(&random) % 2)
            position := spur_tip
            lateral_velocity := olive_random_signed(&random) * .050 + f32(annual_index) * .035 * spur_side
            depth_velocity := olive_random_signed(&random) * .018
            radius := f32(.0072)
            for phytomer_index in 0 ..< phytomer_count {
                // Negative gravitropism gradually damps lateral drift, while
                // node-scale perturbations keep successive internodes from
                // forming one ruler-straight rod.
                lateral_velocity = lateral_velocity * .82 + olive_random_signed(&random) * .018
                depth_velocity = depth_velocity * .72 + olive_random_signed(&random) * .008
                internode_length := (.060 + f32(phytomer_index) * .004) * growth *
                    (1 + olive_random_signed(&random) * .10)
                direction := linalg.normalize0(lsystem.Vec3{lateral_velocity, 1, depth_velocity})
                next := position + direction * internode_length
                append(
                    &result.plant.segments,
                    lsystem.Segment{position, next, radius, radius * .86, -21},
                )
                leaf_side := phytomer_index % 2 == 0 ? f32(-1) : f32(1)
                append(
                    &result.plant.leaves,
                    lsystem.Leaf {
                        position = next,
                        forward = linalg.normalize0(lsystem.Vec3{leaf_side * .78, .28, .18}),
                        up = {0, 0, 1},
                        depth = -21,
                    },
                )
                position = next
                radius *= .86
            }
        }
    }
    return result
}

star_jasmine_skeleton :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x737461726a61736d
    if random == 0 do random = 1
    growth := .24 + clamp(maturity, f32(0), f32(1)) * .76
    cane_count := detail == .Near ? 9 : detail == .Medium ? 7 : 5
    level_count := 5
    leaf_fractions := [4]f32{.18, .40, .62, .84}
    cane_points: [9][6]lsystem.Vec3
    for cane_index in 0 ..< cane_count {
        lateral_target := cane_count <= 1 ? f32(0) : -1 + f32(cane_index) * 2 / f32(cane_count - 1)
        position: lsystem.Vec3
        cane_points[cane_index][0] = position
        height_variation := 1 + olive_random_signed(&random) * .085
        radius := .010 * (.30 + maturity * .70)
        for level_index in 0 ..< level_count {
            progress := f32(level_index + 1) / f32(level_count)
            meander := olive_random_signed(&random) * .085 + f32(math.sin(f64(progress * 5.1 + lateral_target * 2.3))) * .035
            // Trained climbers begin searching sideways low on the support.
            // Linear lateral growth gave every cane the same perfect V edge.
            lateral_progress := f32(math.pow(f64(progress), .72))
            cane_bias := olive_random_signed(&random) * .035 * progress
            next := lsystem.Vec3 {
                (lateral_target * lateral_progress + meander + cane_bias) * growth,
                progress * growth * height_variation,
                f32(math.sin(f64(progress * math.PI * 2 + lateral_target * 1.7))) * .12 * growth,
            }
            append(&result.plant.segments, lsystem.Segment{position, next, radius, radius * .78, level_index})
            direction := linalg.normalize0(next - position)
            for fraction in leaf_fractions {
                append(
                    &result.plant.leaves,
                    lsystem.Leaf {
                        position = linalg.lerp(position, next, fraction),
                        forward = direction,
                        up = {0, 0, 1},
                        depth = level_index,
                    },
                )
            }
            position = next
            cane_points[cane_index][level_index + 1] = position
            radius *= .78
        }
    }
    if detail != .Far {
        // Alternating side links knit the searching leaders into a climber
        // rather than a set of independent trained rods. Stagger their levels
        // so the wall does not acquire horizontal ladder bands.
        for level_index in 2 ..= 4 {
            pair_offset := level_index % 2
            for cane_index := pair_offset; cane_index + 1 < cane_count; cane_index += 2 {
                start := cane_points[cane_index][level_index]
                end := cane_points[cane_index + 1][level_index]
                append(&result.plant.segments, lsystem.Segment{start, end, .0035, .0024, level_index + 1})
                direction := linalg.normalize0(end - start)
                append(
                    &result.plant.leaves,
                    lsystem.Leaf {
                        position = linalg.lerp(start, end, .52),
                        forward = direction,
                        up = {0, 0, 1},
                        depth = level_index + 1,
                    },
                )
            }
        }
    }
    return result
}

wisteria_skeleton :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> lsystem.Interpret_Result {
    result := star_jasmine_skeleton(seed ~ 0x9e3779b97f4a7c15, maturity, detail)
    // Wisteria retains the broad connected wall search but carries older,
    // visibly woody twining canes beneath its compound foliage and racemes.
    for &segment in result.plant.segments {
        segment.radius_start *= 2.15
        segment.radius_end *= 2.15
    }
    return result
}

climbing_rose_skeleton :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> lsystem.Interpret_Result {
    result := star_jasmine_skeleton(seed ~ 0xbf58476d1ce4e5b9, maturity, detail)
    for &segment in result.plant.segments {
        segment.radius_start *= 1.55
        segment.radius_end *= 1.55
    }
    return result
}

olive_growth_iterations :: proc(maturity: f32) -> int {
    // Olive crowns establish scaffold leaders before filling them with
    // successive ramification. Explicit biological stages avoid the uneven
    // floor(maturity * 4) schedule, whose last quarter added nearly 90% of
    // the final wood in one abrupt jump.
    if maturity < .18 do return 0
    if maturity < .48 do return 1
    if maturity < .68 do return 2
    if maturity < .88 do return 3
    return 4
}

// A grammar iteration describes the topology of the next flush of growth,
// but it must not make that entire flush appear in one frame.  Extend the
// newest branch generation out of its joints while the interval matures.
// Segments at one depth form connected shoots, so carrying each transformed
// endpoint into the following segment keeps the shoot continuous.
sprout_newest_generation :: proc(plant: ^lsystem.Plant, progress: f32) {
    if plant == nil || len(plant.segments) == 0 || progress >= 1 do return
    newest_depth := 0
    for segment in plant.segments {
        if segment.depth > newest_depth do newest_depth = segment.depth
    }
    if newest_depth <= 0 do return

    amount := clamp(progress, f32(0), f32(1))
    amount = amount * amount * (3 - 2 * amount)
    old_segments := make([]lsystem.Segment, len(plant.segments))
    copy(old_segments, plant.segments[:])
    defer delete(old_segments)

    for &segment, index in plant.segments {
        if segment.depth != newest_depth do continue
        old := old_segments[index]
        // Find an earlier segment in this shoot. L-system interpretation is
        // parent-before-child, so its already-grown endpoint is authoritative.
        for previous_index := index - 1; previous_index >= 0; previous_index -= 1 {
            previous_old := old_segments[previous_index]
            if previous_old.depth != newest_depth do continue
            delta := previous_old.end - old.start
            if linalg.dot(delta, delta) < .0000001 {
                segment.start = plant.segments[previous_index].end
                break
            }
        }
        segment.end = segment.start + (old.end - old.start) * amount
        thickness := math.sqrt(amount)
        segment.radius_start *= thickness
        segment.radius_end *= thickness
    }

    // Keep foliage on the extending shoot instead of leaving mature leaves
    // floating at its eventual endpoints.
    for &leaf in plant.leaves {
        if leaf.depth != newest_depth do continue
        best_distance := f32(3.402823e38)
        best_position := leaf.position
        for old, index in old_segments {
            if old.depth != newest_depth do continue
            direction := old.end - old.start
            length_squared := linalg.dot(direction, direction)
            t := f32(0)
            if length_squared > .0000001 {
                t = clamp(linalg.dot(leaf.position - old.start, direction) / length_squared, f32(0), f32(1))
            }
            source_position := old.start + direction * t
            distance := linalg.dot(leaf.position - source_position, leaf.position - source_position)
            if distance < best_distance {
                best_distance = distance
                grown := plant.segments[index]
                best_position = grown.start + (grown.end - grown.start) * t
            }
        }
        leaf.position = best_position
    }
}

olive_leaf_frame :: proc(direction: lsystem.Vec3) -> (forward, up: lsystem.Vec3) {
    forward = linalg.normalize0(direction)
    reference := math.abs(forward[1]) > .88 ? lsystem.Vec3{1, 0, 0} : lsystem.Vec3{0, 1, 0}
    right := linalg.normalize0(linalg.cross(forward, reference))
    up = linalg.normalize0(linalg.cross(right, forward))
    return
}

lemon_emit_leaf :: proc(plant: ^lsystem.Plant, random: ^u64, position, shoot_direction: lsystem.Vec3, depth: int) {
    shoot := linalg.normalize0(shoot_direction)
    side := linalg.normalize0(linalg.cross(shoot, lsystem.Vec3{0, 1, 0}))
    if linalg.dot(side, side) < .2 do side = {1, 0, 0}
    shoot_up := linalg.normalize0(linalg.cross(side, shoot))
    // Successive citrus leaves spiral around the shoot. Restricting every
    // anchor to a narrow side-facing arc made neighboring cards share nearly
    // the same plane, producing dark slabs in the crown. Sample the full
    // circumference; the small shoot component still gives each blade its
    // characteristic outward/upward reach.
    roll := olive_random_signed(random) * math.PI
    forward := linalg.normalize0(side * math.cos(roll) + shoot_up * math.sin(roll) + shoot * .18)
    up := linalg.normalize0(linalg.cross(forward, shoot))
    append(&plant.leaves, lsystem.Leaf{position = position, forward = forward, up = up, depth = depth})
}

lemon_grow_branch :: proc(
    plant: ^lsystem.Plant,
    random, foliage_random: ^u64,
    start, initial_direction: lsystem.Vec3,
    length, radius: f32,
    depth, generations: int,
) {
    direction := linalg.normalize0(initial_direction)
    position := start
    current_radius := radius
    for segment_index in 0 ..< 3 {
        side := linalg.normalize0(linalg.cross(direction, lsystem.Vec3{0, 1, 0}))
        if linalg.dot(side, side) < .2 do side = {1, 0, 0}
        binormal := linalg.normalize0(linalg.cross(side, direction))
        direction = linalg.normalize0(
            direction +
            side * olive_random_signed(random) * .10 +
            binormal * olive_random_signed(random) * .07 +
            lsystem.Vec3{0, .035, 0},
        )
        segment_length := length * (.96 - f32(segment_index) * .07) * (1 + olive_random_signed(random) * .07)
        next := position + direction * segment_length
        end_radius := current_radius * .76
        append(
            &plant.segments,
            lsystem.Segment {
                start = position,
                end = next,
                radius_start = current_radius,
                radius_end = end_radius,
                depth = depth,
            },
        )
        // Citrus leaves clothe current-season shoots rather than gathering
        // only into terminal rosettes.
        lemon_emit_leaf(plant, foliage_random, linalg.lerp(position, next, .42), direction, depth)
        lemon_emit_leaf(plant, foliage_random, next, direction, depth)
        position = next
        current_radius = end_radius
    }
    if generations <= 0 do return

    side := linalg.normalize0(linalg.cross(direction, lsystem.Vec3{0, 1, 0}))
    if linalg.dot(side, side) < .2 do side = {1, 0, 0}
    binormal := linalg.normalize0(linalg.cross(side, direction))
    phase := f32(lsystem.random_next(random) % 10_000) / 10_000 * math.PI * 2
    for child_index in 0 ..< 3 {
        azimuth := phase + f32(child_index) * math.PI * 2 / 3
        radial := side * math.cos(azimuth) + binormal * math.sin(azimuth)
        child_direction := linalg.normalize0(
            direction * (.54 + olive_random_signed(random) * .05) +
            radial * (.62 + olive_random_signed(random) * .07) +
            lsystem.Vec3{0, .10, 0},
        )
        lemon_grow_branch(
            plant,
            random,
            foliage_random,
            position,
            child_direction,
            length * (.61 + olive_random_signed(random) * .04),
            current_radius * .62,
            depth + 1,
            generations - 1,
        )
    }
}

lemon_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0xd1b54a32d192ed03
    if random == 0 do random = 1
    foliage_random := seed ~ 0x94d049bb133111eb
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76

    trunk_segments := clamp(2 + int(maturity * 2), 2, 4)
    trunk_position: lsystem.Vec3
    trunk_radius := .13 * (.30 + maturity * .70)
    crown_origins: [5]lsystem.Vec3
    for index in 0 ..< trunk_segments {
        crown_origins[index] = trunk_position
        drift := lsystem.Vec3{olive_random_signed(&random) * .025, .34, olive_random_signed(&random) * .025} * scale
        next := trunk_position + drift
        end_radius := trunk_radius * .84
        append(
            &result.plant.segments,
            lsystem.Segment {
                start = trunk_position,
                end = next,
                radius_start = trunk_radius,
                radius_end = end_radius,
                depth = 0,
            },
        )
        trunk_position = next
        trunk_radius = end_radius
    }
    crown_origins[trunk_segments] = trunk_position

    // Opposed radial scaffold pairs prevent every recursive generation from
    // inheriting the same two turtle planes without leaving an incomplete
    // spiral biased toward one side. Staggered origins and slight angular
    // jitter keep the crown from becoming a mechanical wagon wheel.
    branch_generations := generations <= 1 ? 0 : generations == 2 ? 1 : 2
    scaffold_count := generations == 0 ? 4 : generations == 1 ? 6 : 8
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for scaffold_index in 0 ..< scaffold_count {
        azimuth :=
            phase + f32(scaffold_index) * math.PI * 2 / f32(scaffold_count) + olive_random_signed(&random) * .055
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        origin_index := clamp(trunk_segments - 2 + scaffold_index % 3, 1, trunk_segments)
        origin := crown_origins[origin_index]
        rise := .48 + f32(scaffold_index % 3) * .08
        direction := linalg.normalize0(radial * (.72 + olive_random_signed(&random) * .08) + lsystem.Vec3{0, rise, 0})
        pair_index := scaffold_index % max(scaffold_count / 2, 1)
        length_random := seed ~ (u64(pair_index + 1) * 0x94d049bb133111eb)
        if length_random == 0 do length_random = 1
        scaffold_length := .30 * scale * (1 + olive_random_signed(&length_random) * .14)
        lemon_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            origin,
            direction,
            scaffold_length,
            trunk_radius * .78,
            1,
            branch_generations,
        )
    }
    // A restrained center leader closes the crown without dominating its
    // radial scaffolds.
    lemon_grow_branch(
        &result.plant,
        &random,
        &foliage_random,
        trunk_position,
        {olive_random_signed(&random) * .08, 1, olive_random_signed(&random) * .08},
        .25 * scale,
        trunk_radius * .72,
        1,
        min(branch_generations, 1),
    )
    return result
}

prickly_pear_emit_pad :: proc(plant: ^lsystem.Plant, position: lsystem.Vec3, normal_azimuth: f32, depth: int) {
    if plant == nil do return
    normal := lsystem.Vec3{math.cos(normal_azimuth), 0, math.sin(normal_azimuth)}
    append(&plant.leaves, lsystem.Leaf{position = position, forward = {0, 1, 0}, up = normal, depth = depth})
}

prickly_pear_skeleton :: proc(seed: u64, maturity: f32) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x8cb92baa3f3d8dd7
    if random == 0 do random = 1
    scale := .34 + maturity * .66
    basal_count := maturity < .34 ? 1 : maturity < .64 ? 2 : 3
    child_count := maturity < .42 ? 0 : maturity < .74 ? 1 : 2
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2

    for basal_index in 0 ..< basal_count {
        centered := f32(basal_index) - f32(basal_count - 1) * .5
        base := lsystem.Vec3{centered * .20 * scale, 0, olive_random_signed(&random) * .055 * scale}
        base_normal := phase + f32(basal_index) * .86 + olive_random_signed(&random) * .18
        prickly_pear_emit_pad(&result.plant, base, base_normal, 0)
        // Keep one tiny structural segment inside each basal pad so the
        // generated plant retains valid woody topology without exposing the
        // brown connector sticks that made the cactus look like saplings.
        append(
            &result.plant.segments,
            lsystem.Segment{base, base + lsystem.Vec3{0, .10 * scale, 0}, .012 * scale, .008 * scale, 0},
        )

        for child_index in 0 ..< child_count {
            side := child_index == 0 ? f32(-1) : f32(1)
            outward := centered == 0 ? side : (centered < 0 ? f32(-1) : f32(1))
            child_base :=
                base +
                lsystem.Vec3 {
                        outward * (.055 + .015 * f32(child_index)) * scale,
                        (.255 + .025 * f32((basal_index + child_index) % 2)) * scale,
                        side * (.055 + olive_random_signed(&random) * .018) * scale,
                    }
            child_normal := base_normal + side * (.48 + olive_random_signed(&random) * .14)
            prickly_pear_emit_pad(&result.plant, child_base, child_normal, 1)

            if maturity < .82 do continue
            top_side := (basal_index + child_index) % 2 == 0 ? f32(-1) : f32(1)
            top_base :=
                child_base +
                lsystem.Vec3 {
                        top_side * (.040 + math.abs(olive_random_signed(&random)) * .018) * scale,
                        (.215 + olive_random_signed(&random) * .015) * scale,
                        -side * .022 * scale,
                    }
            prickly_pear_emit_pad(
                &result.plant,
                top_base,
                child_normal + top_side * (.36 + olive_random_signed(&random) * .10),
                2,
            )
        }
    }
    return result
}

succulent_emit_rosette :: proc(
    plant: ^lsystem.Plant,
    center: lsystem.Vec3,
    count: int,
    phase, rise, spread: f32,
    depth: int,
) {
    if plant == nil || count <= 0 do return
    for index in 0 ..< count {
        angle := phase + f32(index) * math.PI * 2 / f32(count)
        radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
        forward := linalg.normalize0(radial * spread + lsystem.Vec3{0, rise, 0})
        tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
        append(&plant.leaves, lsystem.Leaf{position = center, forward = forward, up = tangent, depth = depth})
    }
}

fleshy_plant_skeleton :: proc(
    species: Species,
    seed: u64,
    maturity: f32,
    detail: Detail_Level,
) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0xa0761d6478bd642f
    if random == 0 do random = 1
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    growth := .28 + maturity * .72

    // A tiny hidden segment preserves the generator's topology contract. The
    // persistent visible structure is carried entirely by fleshy attachments.
    append(&result.plant.segments, lsystem.Segment{{}, {0, .06 * growth, 0}, .009, .006, 0})
    if species == .Golden_Barrel {
        rib_count := detail == .Near ? 20 : detail == .Medium ? 14 : 9
        radius := (.13 + maturity * .16)
        for index in 0 ..< rib_count {
            angle := phase + f32(index) * math.PI * 2 / f32(rib_count)
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            position := radial * radius
            append(
                &result.plant.leaves,
                lsystem.Leaf{position = position, forward = {0, 1, 0}, up = radial, depth = 0},
            )
        }
        return result
    }

    outer_count := detail == .Near ? 18 : detail == .Medium ? 12 : 8
    inner_count := detail == .Near ? 11 : detail == .Medium ? 7 : 5
    if species == .Agave {
        succulent_emit_rosette(&result.plant, {}, outer_count, phase, .30, 1.0, 0)
        if maturity >= .42 {
            succulent_emit_rosette(&result.plant, {0, .025 * growth, 0}, inner_count, phase + .31, .70, .72, 1)
        }
    } else {
        // Aloe is a narrower, more upright clumping rosette. Mature plants
        // add two small deterministic offsets instead of becoming one agave.
        succulent_emit_rosette(&result.plant, {}, outer_count, phase, .62, .78, 0)
        succulent_emit_rosette(&result.plant, {0, .025 * growth, 0}, inner_count, phase + .37, .88, .48, 1)
        if maturity >= .72 && detail != .Far {
            offset_count := detail == .Near ? 7 : 5
            succulent_emit_rosette(
                &result.plant,
                {.18 * growth, 0, -.10 * growth},
                offset_count,
                phase + 1.1,
                .72,
                .66,
                2,
            )
            succulent_emit_rosette(
                &result.plant,
                {-.16 * growth, 0, .12 * growth},
                offset_count,
                phase - .8,
                .75,
                .62,
                2,
            )
        }
    }
    return result
}

succulent_catalog_skeleton :: proc(species: Species, seed: u64, maturity: f32, detail: Detail_Level) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    phase := f32((seed ~ 0xe7037ed1a0b428db) % 10_000) / 10_000 * math.PI * 2
    growth := .25 + maturity * .75
    if species == .Echeveria {
        append(&result.plant.segments, lsystem.Segment{{}, {0, .025, 0}, .008, .005, 0})
        succulent_emit_rosette(&result.plant, {}, detail == .Near ? 18 : detail == .Medium ? 12 : 8, phase, .32, 1, 0)
        succulent_emit_rosette(&result.plant, {0, .018, 0}, detail == .Near ? 11 : detail == .Medium ? 7 : 5, phase + .29, .68, .70, 1)
        if maturity > .68 && detail != .Far do succulent_emit_rosette(&result.plant, {.21 * growth, 0, -.13 * growth}, 7, phase + .8, .48, .78, 2)
        return result
    }
    if species == .Aeonium {
        height := .24 + maturity * .62
        tip := lsystem.Vec3{0, height, 0}
        append(&result.plant.segments, lsystem.Segment{{}, tip, .045 * growth, .026 * growth, 0})
        rosette_count := detail == .Near ? 16 : detail == .Medium ? 11 : 7
        succulent_emit_rosette(&result.plant, tip, rosette_count, phase, .12, 1, 1)
        if maturity > .48 {
            branch_count := detail == .Far ? 2 : 4
            for branch in 0 ..< branch_count {
                angle := phase + f32(branch) * math.PI * 2 / f32(branch_count)
                radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
                start := lsystem.Vec3{0, height * (.48 + f32(branch & 1) * .10), 0}
                end := start + radial * .23 * growth + lsystem.Vec3{0, .18 * growth, 0}
                append(&result.plant.segments, lsystem.Segment{start, end, .025 * growth, .014 * growth, 1})
                succulent_emit_rosette(&result.plant, end, max(rosette_count - 4, 5), angle + .2, .18, 1, 2)
            }
        }
        return result
    }
    if species == .Jade_Plant {
        stem_count := detail == .Far ? 3 : 5
        node_count := detail == .Near ? 4 : detail == .Medium ? 3 : 2
        for stem in 0 ..< stem_count {
            angle := phase + f32(stem) * math.PI * 2 / f32(stem_count)
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            position := radial * .035
            for node in 0 ..< node_count {
                next := position + radial * (.030 + f32(node) * .008) * growth + lsystem.Vec3{0, .13 * growth, 0}
                append(&result.plant.segments, lsystem.Segment{position, next, (.024 - f32(node) * .003) * growth, (.021 - f32(node) * .003) * growth, node})
                tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
                axis := node & 1 == 0 ? tangent : radial
                append(&result.plant.leaves,
                    lsystem.Leaf{position = next, forward = linalg.normalize0(axis + lsystem.Vec3{0, .28, 0}), up = radial, depth = node},
                    lsystem.Leaf{position = next, forward = linalg.normalize0(-axis + lsystem.Vec3{0, .28, 0}), up = -radial, depth = node})
                position = next
            }
        }
        return result
    }
    if species == .Stonecrop {
        runner_count := detail == .Near ? 12 : detail == .Medium ? 8 : 5
        nodes := detail == .Near ? 5 : detail == .Medium ? 4 : 3
        for runner in 0 ..< runner_count {
            angle := phase + f32(runner) * math.PI * 2 / f32(runner_count)
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            position: lsystem.Vec3
            for node in 0 ..< nodes {
                next := position + radial * .075 * growth + lsystem.Vec3{0, .010 + f32(node) * .004, 0}
                append(&result.plant.segments, lsystem.Segment{position, next, .006, .004, 0})
                append(&result.plant.leaves, lsystem.Leaf{position = next, forward = {-radial[2], .18, radial[0]}, up = {0, 1, 0}, depth = node})
                position = next
            }
        }
        return result
    }
    if species == .Blue_Chalk_Sticks {
        append(&result.plant.segments, lsystem.Segment{{}, {0, .03, 0}, .008, .005, 0})
        count := detail == .Near ? 22 : detail == .Medium ? 14 : 8
        for index in 0 ..< count {
            angle := phase + f32(index) * 2.399963
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            append(&result.plant.leaves, lsystem.Leaf{position = radial * (.035 + f32(index % 4) * .022), forward = linalg.normalize0(radial * .26 + lsystem.Vec3{0, 1, 0}), up = {-radial[2], 0, radial[0]}, depth = index % 3})
        }
        return result
    }
    rib_count := detail == .Near ? 18 : detail == .Medium ? 12 : 8
    append(&result.plant.segments, lsystem.Segment{{}, {0, .12 * growth, 0}, .012, .008, 0})
    for rib in 0 ..< rib_count {
        angle := phase + f32(rib) * math.PI * 2 / f32(rib_count)
        radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
        append(&result.plant.leaves, lsystem.Leaf{position = radial * .13 * growth, forward = {0, 1, 0}, up = radial, depth = 0})
    }
    return result
}

almond_grow_branch :: proc(
    plant: ^lsystem.Plant,
    random, foliage_random: ^u64,
    start, initial_direction: lsystem.Vec3,
    length, radius: f32,
    depth, generations: int,
) {
    direction := linalg.normalize0(initial_direction)
    position := start
    current_radius := radius
    roll_phase := f32(lsystem.random_next(random) % 10_000) / 10_000 * math.PI * 2
    for segment_index in 0 ..< 3 {
        side := linalg.normalize0(linalg.cross(direction, lsystem.Vec3{0, 1, 0}))
        if linalg.dot(side, side) < .2 do side = {1, 0, 0}
        binormal := linalg.normalize0(linalg.cross(side, direction))
        direction = linalg.normalize0(
            direction +
            side * olive_random_signed(random) * .065 +
            binormal * olive_random_signed(random) * .045 +
            lsystem.Vec3{0, .035, 0},
        )
        segment_length := length * (.98 - f32(segment_index) * .10) * (1 + olive_random_signed(random) * .055)
        next := position + direction * segment_length
        end_radius := current_radius * .74
        append(&plant.segments, lsystem.Segment{position, next, current_radius, end_radius, depth})
        lemon_emit_leaf(plant, foliage_random, linalg.lerp(position, next, .42), direction, depth)
        lemon_emit_leaf(plant, foliage_random, next, direction, depth)
        position = next
        current_radius = end_radius

        if generations <= 0 do continue
        // Almond shoots ramify with alternating laterals along their length,
        // not citrus-like three-way whorls collected at the terminal bud.
        // Golden-angle spacing gives three sequential branch sites full
        // radial coverage without placing them in a terminal whorl.
        azimuth := roll_phase + f32(segment_index) * 2.399963 + olive_random_signed(random) * .16
        radial := side * math.cos(azimuth) + binormal * math.sin(azimuth)
        child_direction := linalg.normalize0(
            direction * (.56 + olive_random_signed(random) * .045) +
            radial * (.65 + olive_random_signed(random) * .055) +
            lsystem.Vec3{0, .045, 0},
        )
        almond_grow_branch(
            plant,
            random,
            foliage_random,
            position,
            child_direction,
            length * (.64 + olive_random_signed(random) * .035),
            current_radius * .61,
            depth + 1,
            generations - 1,
        )
    }
}

almond_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x8cb92baa7f3d8dd7
    if random == 0 do random = 1
    foliage_random := seed ~ 0x9e3779b97f4a7c15
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76

    // Keep a short, uninterrupted trunk below the vase. Primary scaffolds
    // emerge from two adjacent heights so their bases remain legible instead
    // of collapsing into one procedural hub.
    trunk_segments := clamp(2 + int(maturity * 1.4), 2, 3)
    trunk_position: lsystem.Vec3
    trunk_radius := .14 * (.30 + maturity * .70)
    crown_origins: [4]lsystem.Vec3
    for index in 0 ..< trunk_segments {
        crown_origins[index] = trunk_position
        next :=
            trunk_position +
            lsystem.Vec3{olive_random_signed(&random) * .020, .38, olive_random_signed(&random) * .020} * scale
        end_radius := trunk_radius * .82
        append(&result.plant.segments, lsystem.Segment{trunk_position, next, trunk_radius, end_radius, 0})
        trunk_position = next
        trunk_radius = end_radius
    }
    crown_origins[trunk_segments] = trunk_position

    scaffold_count := maturity < .42 ? 3 : 5
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for scaffold_index in 0 ..< scaffold_count {
        // Even radial sectors guarantee coverage around the trunk. Restrained
        // jitter preserves seed identity without allowing one empty half.
        azimuth := phase + f32(scaffold_index) * math.PI * 2 / f32(scaffold_count) + olive_random_signed(&random) * .10
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        origin_index := clamp(trunk_segments - 1 + scaffold_index % 2, 1, trunk_segments)
        direction := linalg.normalize0(
            radial * (.66 + olive_random_signed(&random) * .045) +
            lsystem.Vec3{0, .78 + olive_random_signed(&random) * .045, 0},
        )
        almond_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            crown_origins[origin_index],
            direction,
            .37 * scale * (1 + olive_random_signed(&random) * .05),
            trunk_radius * (.70 + olive_random_signed(&random) * .035),
            1,
            clamp(generations, 0, 2),
        )
    }
    return result
}

almond_orchard_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result := almond_skeleton(seed, maturity, generations)
    // The shared radial topology also underpins substantially heavier trees.
    // Almond keeps the same complete vase but carries a lighter orchard trunk
    // and fine flowering scaffold, particularly visible below its open crown.
    for &segment in result.plant.segments {
        radius_scale := segment.depth == 0 ? f32(.72) : f32(.84)
        segment.radius_start *= radius_scale
        segment.radius_end *= radius_scale
    }
    return result
}

broadleaf_tree_skeleton :: proc(
    species: Species,
    seed: u64,
    maturity: f32,
    generations: int,
) -> lsystem.Interpret_Result {
    // These full-sized trees need radial scaffold authority. The generic
    // turtle grammar advances a single leader between branch whorls, which
    // produced disconnected foliage shelves and hourglass silhouettes.
    result := almond_skeleton(seed ~ 0xd1b54a32d192ed03, maturity, generations)
    horizontal_scale, vertical_scale, radius_scale := f32(1), f32(1), f32(1)
    #partial switch species {
    case .Holm_Oak:
        // Holm oak retains a broad evergreen crown, but it is a rounded mass
        // rather than the flat umbrella reserved for stone pine. Give the
        // existing radial scaffold enough vertical authority to stack its
        // foliage pads into a deep crown across seed variants.
        horizontal_scale, vertical_scale, radius_scale = 1.22, 1.90, 1.30
    case .Oriental_Plane:
        horizontal_scale, vertical_scale, radius_scale = 1.48, 1.46, 1.18
    case .European_Hackberry:
        horizontal_scale, vertical_scale, radius_scale = 1.30, 1.28, 1.05
    case .White_Poplar:
        // White poplar forms a broad irregular oval crown. The previous
        // Lombardy-like transform compressed the radial scaffold so severely
        // that the mature tree read as a bare pole with a narrow foliage
        // sleeve. Retain an ascending habit without losing lateral authority.
        horizontal_scale, vertical_scale, radius_scale = 1.80, 1.40, 1.08
    case .Olive,
         .Italian_Cypress,
         .Grapevine,
         .Fig,
         .Lemon,
         .Pomegranate,
         .Almond,
         .Oleander,
         .Bougainvillea,
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
         .Golden_Barrel,
         .Agave,
         .Aloe,
         .Aeonium,
         .Echeveria,
         .Jade_Plant,
         .Stonecrop,
         .Blue_Chalk_Sticks,
         .Golden_Torch_Cactus:
    }
    for &segment in result.plant.segments {
        segment.start[0] *= horizontal_scale
        segment.start[1] *= vertical_scale
        segment.start[2] *= horizontal_scale
        segment.end[0] *= horizontal_scale
        segment.end[1] *= vertical_scale
        segment.end[2] *= horizontal_scale
        segment.radius_start *= radius_scale
        segment.radius_end *= radius_scale
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= horizontal_scale
        leaf.position[1] *= vertical_scale
        leaf.position[2] *= horizontal_scale
    }
    return result
}

fig_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    // Figs and almonds share an orchard-tree vase, but figs are lower,
    // broader, and heavier-limbed. Reusing the balanced radial topology keeps
    // the species from falling back to the old one-sided turtle fan while
    // this deterministic transform supplies the distinct fig proportions.
    result := almond_skeleton(seed ~ 0x6a09e667f3bcc909, maturity, generations)
    for &segment in result.plant.segments {
        segment.start[0] *= 1.20
        segment.start[1] *= 1.15
        segment.start[2] *= 1.20
        segment.end[0] *= 1.20
        segment.end[1] *= 1.15
        segment.end[2] *= 1.20
        segment.radius_start *= 1.08
        segment.radius_end *= 1.08
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= 1.20
        leaf.position[1] *= 1.15
        leaf.position[2] *= 1.20
    }
    return result
}

carob_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result := fig_skeleton(seed ~ 0xa54ff53a5f1d36f1, maturity, generations)
    // Carobs mature into substantial, deep-crowned evergreens. Preserve the
    // balanced vase topology but give its persistent limbs more height and
    // weight than the lower, lighter fig.
    for &segment in result.plant.segments {
        segment.start[1] *= 1.08
        segment.end[1] *= 1.08
        segment.radius_start *= 1.16
        segment.radius_end *= 1.16
    }
    for &leaf in result.plant.leaves do leaf.position[1] *= 1.08
    return result
}

pomegranate_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0xbb67ae8584caa73b
    if random == 0 do random = 1
    foliage_random := seed ~ 0x3c6ef372fe94f82b
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76
    stem_count := maturity < .42 ? 3 : generations < 2 ? 4 : 5
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    // One lateral generation is enough to clothe five renewing canes. A
    // second recursive almond-style generation explodes into a low tangled
    // mound and hides both the vase and its fruit.
    branch_generations := clamp(generations - 1, 0, 1)
    for stem_index in 0 ..< stem_count {
        // Pomegranates characteristically renew from several basal canes.
        // Even sectors guarantee a complete vase, while different lift and
        // reach keep those canes from becoming a mechanical radial whorl.
        azimuth := phase + f32(stem_index) * math.PI * 2 / f32(stem_count) + olive_random_signed(&random) * .12
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        direction := linalg.normalize0(
            radial * (.30 + olive_random_signed(&random) * .045) +
            lsystem.Vec3{0, 1.06 + olive_random_signed(&random) * .07, 0},
        )
        almond_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            radial * .025,
            direction,
            .38 * scale * (1 + olive_random_signed(&random) * .07),
            .050 * (.30 + maturity * .70),
            0,
            branch_generations,
        )
    }
    return result
}

strawberry_tree_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result := pomegranate_skeleton(seed ~ 0xcbbb9d5dc1059ed8, maturity, generations)
    // Strawberry trees commonly form several red-barked leaders beneath a
    // taller rounded crown. Stretch the complete radial vase while retaining
    // enough width and fine ramification to avoid a detached top tuft.
    for &segment in result.plant.segments {
        segment.start[0] *= 1.22
        segment.start[1] *= 1.62
        segment.start[2] *= 1.22
        segment.end[0] *= 1.22
        segment.end[1] *= 1.62
        segment.end[2] *= 1.22
        segment.radius_start *= 1.08
        segment.radius_end *= 1.08
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= 1.22
        leaf.position[1] *= 1.62
        leaf.position[2] *= 1.22
    }
    return result
}

myrtle_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    // Myrtle and pomegranate are both renewing multi-cane shrubs, but Myrtle
    // is finer, narrower, and more continuously leafy. Reusing the balanced
    // radial cane topology removes the generic grammar's hollow V-shaped fan
    // while this transform keeps the two species visibly distinct.
    result := pomegranate_skeleton(seed ~ 0xa54ff53a5f1d36f1, maturity, generations)
    for &segment in result.plant.segments {
        segment.start[0] *= 1.05
        segment.start[1] *= .98
        segment.start[2] *= 1.05
        segment.end[0] *= 1.05
        segment.end[1] *= .98
        segment.end[2] *= 1.05
        segment.radius_start *= .55
        segment.radius_end *= .55
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= 1.05
        leaf.position[1] *= .98
        leaf.position[2] *= 1.05
    }
    return result
}

mastic_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x3c6ef372fe94f82b
    if random == 0 do random = 1
    foliage_random := seed ~ 0xa54ff53a5f1d36f1
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76
    stem_count := maturity < .42 ? 4 : 6
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    branch_generations := clamp(generations - 1, 0, 2)
    for stem_index in 0 ..< stem_count {
        azimuth := phase + f32(stem_index) * math.PI * 2 / f32(stem_count) + olive_random_signed(&random) * .10
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        // Mastic stays broader and lower than Myrtle, but all six basal canes
        // still occupy distinct radial sectors rather than one planar fan.
        direction := linalg.normalize0(
            radial * (.43 + olive_random_signed(&random) * .04) +
            lsystem.Vec3{0, .98 + olive_random_signed(&random) * .06, 0},
        )
        almond_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            radial * .025,
            direction,
            .34 * scale * (1 + olive_random_signed(&random) * .06),
            .026 * (.30 + maturity * .70),
            0,
            branch_generations,
        )
    }
    return result
}

agapanthus_skeleton :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x510e527fade682d1
    if random == 0 do random = 1
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    growth := .25 + maturity * .75

    // One hidden basal link preserves the non-empty topology contract. The
    // persistent vegetative mass is the explicit strap-leaf rosette below.
    append(&result.plant.segments, lsystem.Segment{{}, {0, .025, 0}, .006, .004, 0})
    leaf_count := detail == .Near ? 22 : detail == .Medium ? 14 : 9
    for leaf_index in 0 ..< leaf_count {
        angle := phase + f32(leaf_index) * 2.399963 + olive_random_signed(&random) * .10
        radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
        ring := leaf_index % 3
        rise := f32(.32 + .12 * f32(ring))
        forward := linalg.normalize0(radial + lsystem.Vec3{0, rise, 0})
        tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
        append(
            &result.plant.leaves,
            lsystem.Leaf {
                position = radial * (.012 * f32(ring)),
                forward = forward,
                up = tangent,
                depth = 0,
            },
        )
    }

    if maturity > .42 && detail != .Far {
        scape_count := detail == .Near ? 3 : 2
        for scape_index in 0 ..< scape_count {
            angle := phase + f32(scape_index) * math.PI * 2 / f32(scape_count) + olive_random_signed(&random) * .12
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            start := radial * (.035 + f32(scape_index % 2) * .018)
            height := (.60 + f32(scape_index) * .055 + olive_random_signed(&random) * .020) * growth
            end := start + radial * .120 + lsystem.Vec3{0, height, 0}
            append(&result.plant.segments, lsystem.Segment{start, end, .009, .0045, 0})
            append(
                &result.plant.leaves,
                lsystem.Leaf {
                    position = end,
                    forward = linalg.normalize0(radial + lsystem.Vec3{0, .15, 0}),
                    up = {-radial[2], 0, radial[0]},
                    depth = -5,
                },
            )
        }
    }
    return result
}

sage_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x9b05688c2b3e6c1f
    if random == 0 do random = 1
    foliage_random := seed ~ 0x1f83d9abfb41bd6b
    if foliage_random == 0 do foliage_random = 1
    scale := .24 + maturity * .76
    stem_count := maturity < .42 ? 5 : 8
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    branch_generations := clamp(generations - 1, 0, 1)
    for stem_index in 0 ..< stem_count {
        azimuth := phase + f32(stem_index) * math.PI * 2 / f32(stem_count) + olive_random_signed(&random) * .12
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        direction := linalg.normalize0(
            radial * (.38 + olive_random_signed(&random) * .04) +
            lsystem.Vec3{0, .98 + olive_random_signed(&random) * .06, 0},
        )
        before := len(result.plant.segments)
        almond_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            radial * .018,
            direction,
            .23 * scale * (1 + olive_random_signed(&random) * .06),
            .008 * (.30 + maturity * .70),
            0,
            branch_generations,
        )
        if len(result.plant.segments) > before {
            terminal: lsystem.Vec3
            for segment in result.plant.segments[before:] {
                if segment.depth == 0 && segment.end[1] > terminal[1] do terminal = segment.end
            }
            append(
                &result.plant.leaves,
                lsystem.Leaf {
                    position = terminal,
                    forward = direction,
                    up = {-radial[2], 0, radial[0]},
                    depth = -6,
                },
            )
        }
    }
    return result
}

lavender_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0xa54ff53a5f1d36f1
    if random == 0 do random = 1
    scale := .24 + maturity * .76
    stem_count := maturity < .42 ? 10 : 22
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for stem_index in 0 ..< stem_count {
        azimuth := phase + f32(stem_index) * math.PI * 2 / f32(stem_count) + olive_random_signed(&random) * .11
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        height_variation := 1 + olive_random_signed(&random) * .10
        start := radial * (.025 + f32(stem_index % 4) * .008) * scale
        shoulder := start + radial * (.060 * scale) + lsystem.Vec3{0, .100 * scale * height_variation, 0}
        terminal := shoulder + radial * (.015 * scale) + lsystem.Vec3{0, .105 * scale * height_variation, 0}
        radius := .0018 * (.30 + maturity * .70)
        append(&result.plant.segments, lsystem.Segment{start, shoulder, radius, radius * .72, 0})
        append(&result.plant.segments, lsystem.Segment{shoulder, terminal, radius * .72, radius * .38, 1})
        append(
            &result.plant.leaves,
            lsystem.Leaf {
                position = terminal,
                forward = linalg.normalize0(radial * .18 + lsystem.Vec3{0, 1, 0}),
                up = {-radial[2], 0, radial[0]},
                depth = -7,
            },
        )
    }
    return result
}

thyme_skeleton :: proc(seed: u64, maturity: f32, detail: Detail_Level) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0x5be0cd19137e2179
    if random == 0 do random = 1
    scale := .24 + maturity * .76
    runner_count := detail == .Near ? 16 : detail == .Medium ? 11 : 7
    leaf_fractions := [2]f32{.28, .72}
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for runner_index in 0 ..< runner_count {
        azimuth := phase + f32(runner_index) * math.PI * 2 / f32(runner_count) + olive_random_signed(&random) * .10
        tangent_angle := azimuth + olive_random_signed(&random) * .12
        position := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)} * .018 * scale
        direction := lsystem.Vec3{math.cos(tangent_angle), .62, math.sin(tangent_angle)}
        radius := .0015 * (.30 + maturity * .70)
        for segment_index in 0 ..< 3 {
            side_angle := tangent_angle + olive_random_signed(&random) * .18
            direction = linalg.normalize0(
                lsystem.Vec3{math.cos(side_angle), .58 + f32(segment_index) * .060, math.sin(side_angle)},
            )
            next := position + direction * (.055 * scale * (1 + olive_random_signed(&random) * .07))
            append(&result.plant.segments, lsystem.Segment{position, next, radius, radius * .76, segment_index})
            for fraction in leaf_fractions {
                leaf_position := linalg.lerp(position, next, fraction)
                append(
                    &result.plant.leaves,
                    lsystem.Leaf {
                        position = leaf_position,
                        forward = linalg.normalize0(lsystem.Vec3{math.cos(side_angle + math.PI * .5), .10, math.sin(side_angle + math.PI * .5)}),
                        up = {0, 1, 0},
                        depth = segment_index,
                    },
                )
            }
            position = next
            radius *= .76
        }
        append(
            &result.plant.leaves,
            lsystem.Leaf {
                position = position,
                forward = linalg.normalize0(direction + lsystem.Vec3{0, .35, 0}),
                up = {0, 1, 0},
                depth = -8,
            },
        )
    }
    return result
}

bay_laurel_skeleton :: proc(seed: u64, maturity: f32, generations: int) -> lsystem.Interpret_Result {
    result := pomegranate_skeleton(seed ~ 0x510e527fade682d1, maturity, generations)
    // Laurel forms a dense upright oval rather than pomegranate's open,
    // fruit-bearing vase. Compress the same complete radial coverage and
    // extend its cane height, preserving seed variation in three dimensions.
    for &segment in result.plant.segments {
        segment.start[0] *= .95
        segment.start[1] *= 1.08
        segment.start[2] *= .95
        segment.end[0] *= .95
        segment.end[1] *= 1.08
        segment.end[2] *= .95
        segment.radius_start *= .92
        segment.radius_end *= .92
    }
    for &leaf in result.plant.leaves {
        leaf.position[0] *= .95
        leaf.position[1] *= 1.08
        leaf.position[2] *= .95
    }
    return result
}

rosemary_clothe_scaffold :: proc(plant: ^lsystem.Plant) {
    if plant == nil || len(plant.leaves) == 0 do return
    original_segment_count := len(plant.segments)
    fractions := [2]f32{.38, .70}
    replacement_count := 0
    for segment in plant.segments[:original_segment_count] {
        if segment.depth <= 1 do replacement_count += len(fractions)
    }
    replacement_ordinal := 0
    for segment in plant.segments[:original_segment_count] {
        // Only clothe the persistent basal leaders. Fine recursive shoots
        // already carry grammar-authored needles; duplicating those would
        // spend the attachment budget without improving the silhouette.
        if segment.depth > 1 do continue
        direction := linalg.normalize0(segment.end - segment.start)
        forward, up := olive_leaf_frame(direction)
        for fraction in fractions {
            // Spread replacement sites through the grammar output. Replacing
            // one contiguous tail block strips the terminal crown bare.
            replacement_index := (replacement_ordinal + 1) * len(plant.leaves) / (replacement_count + 1)
            plant.leaves[replacement_index] = {
                position = linalg.lerp(segment.start, segment.end, fraction),
                forward  = forward,
                up       = up,
                depth    = segment.depth,
            }
            replacement_ordinal += 1
        }
    }
}

myrtle_clothe_scaffold :: proc(plant: ^lsystem.Plant) {
    if plant == nil || len(plant.segments) == 0 do return
    // Opposite pairs need several longitudinal stations to form Myrtle's
    // dense evergreen sprays. Add stations along the cane instead of
    // restoring the old three-way palmate cluster at a single node.
    fractions := [2]f32{.18, .70}
    for segment in plant.segments {
        direction := linalg.normalize0(segment.end - segment.start)
        forward, up := olive_leaf_frame(direction)
        for fraction in fractions {
            append(
                &plant.leaves,
                lsystem.Leaf {
                    position = linalg.lerp(segment.start, segment.end, fraction),
                    forward = forward,
                    up = up,
                    depth = segment.depth,
                },
            )
        }
    }
}

lavender_clothe_scaffold :: proc(plant: ^lsystem.Plant) {
    if plant == nil || len(plant.segments) == 0 do return
    // Lavender hides its fine basal framework beneath many close opposite
    // leaf pairs. Four stations per short link create that soft grey mound
    // while the separately authored terminal markers remain flower-only.
    fractions := [4]f32{.12, .38, .64, .86}
    for segment, segment_index in plant.segments {
        for fraction, fraction_index in fractions {
            position := linalg.lerp(segment.start, segment.end, fraction)
            azimuth := f32(segment_index) * 2.399963 + f32(fraction_index) * math.PI * .43
            outward := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
            forward := linalg.normalize0(outward * .96 + lsystem.Vec3{0, .18, 0})
            up := lsystem.Vec3{-outward[2], 0, outward[0]}
            append(
                &plant.leaves,
                lsystem.Leaf {
                    position = position,
                    forward = forward,
                    up = up,
                    depth = segment.depth,
                },
            )
        }
    }
}

stone_pine_clothe_scaffold :: proc(plant: ^lsystem.Plant, detail: Detail_Level) {
    if plant == nil || len(plant.segments) == 0 do return
    for segment in plant.segments {
        if segment.depth <= 0 do continue
        direction := linalg.normalize0(segment.end - segment.start)
        forward, up := olive_leaf_frame(direction)
        // The old uniform six-station run painted thin needles along every
        // scaffold and exposed the radial construction. Italian stone pines
        // retain visible inner arms but concentrate foliage into overlapping
        // pads on their terminal forks.
        primary_stations := [2]f32{.70, .91}
        terminal_stations := [8]f32{.18, .31, .44, .56, .67, .77, .86, .94}
        station_count := segment.depth == 1 ? len(primary_stations) : len(terminal_stations)
        for station_index in 0 ..< station_count {
            station := segment.depth == 1 ? primary_stations[station_index] : terminal_stations[station_index]
            row_count := segment.depth == 1 ? 1 : detail == .Near ? 3 : detail == .Medium ? 2 : 1
            right := linalg.normalize0(linalg.cross(forward, up))
            for row_index in 0 ..< row_count {
                row_side := row_index == 0 ? f32(0) : row_index == 1 ? f32(1) : f32(-1)
                row_position :=
                    linalg.lerp(segment.start, segment.end, station) +
                    right * row_side * .040 +
                    up * math.abs(row_side) * .012
                append(
                    &plant.leaves,
                    lsystem.Leaf{position = row_position, forward = forward, up = up, depth = segment.depth},
                )
            }
        }
    }
}

stone_pine_skeleton :: proc(seed: u64, maturity: f32, iterations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0xd6e8feb86659fd93
    if random == 0 do random = 1
    scale := .22 + maturity * .78
    trunk_segments := clamp(3 + int(maturity * 3.2), 3, 6)
    trunk_step := .43 * scale
    trunk_radius := .18 * (.28 + maturity * .72)
    position := lsystem.Vec3{}
    trunk_points: [7]lsystem.Vec3
    trunk_points[0] = position
    for index in 0 ..< trunk_segments {
        // A long, slightly wandering clear bole is the visual anchor of a
        // mature stone pine; the umbrella begins only in its upper quarter.
        next :=
            position +
            lsystem.Vec3 {
                    olive_random_signed(&random) * .022 * scale,
                    trunk_step,
                    olive_random_signed(&random) * .022 * scale,
                }
        end_radius := trunk_radius * (.91 - f32(index) * .018)
        append(&result.plant.segments, lsystem.Segment{position, next, trunk_radius, end_radius, 0})
        position = next
        trunk_points[index + 1] = position
        trunk_radius = end_radius
    }

    leader_count := iterations >= 3 ? 8 : iterations == 2 ? 6 : 4
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    for leader_index in 0 ..< leader_count {
        azimuth := phase + f32(leader_index) * math.PI * 2 / f32(leader_count) + olive_random_signed(&random) * .12
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        origin_index := max(trunk_segments - leader_index % 2, 1)
        origin := trunk_points[origin_index]
        reach := (.78 + olive_random_signed(&random) * .10) * scale
        first_direction := linalg.normalize0(
            radial * .88 + lsystem.Vec3{0, .47 + olive_random_signed(&random) * .08, 0},
        )
        elbow := origin + first_direction * reach * .48
        outer_direction := linalg.normalize0(radial + lsystem.Vec3{0, .18 + olive_random_signed(&random) * .09, 0})
        tip := elbow + outer_direction * reach * .52
        branch_radius := max(trunk_radius * (.46 + olive_random_signed(&random) * .04), f32(.012))
        append(
            &result.plant.segments,
            lsystem.Segment{origin, elbow, branch_radius, branch_radius * .72, 1},
            lsystem.Segment{elbow, tip, branch_radius * .72, branch_radius * .42, 1},
        )

        // Two short, rising terminal forks broaden and flatten the crown
        // without collapsing all needles into one spherical tuft.
        tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
        for side in -1 ..= 1 {
            if side == 0 do continue
            fork_direction := linalg.normalize0(
                radial * .58 +
                tangent * f32(side) * .46 +
                lsystem.Vec3{0, .42 + olive_random_signed(&random) * .10, 0},
            )
            fork_end := tip + fork_direction * reach * (.34 + olive_random_signed(&random) * .04)
            append(&result.plant.segments, lsystem.Segment{tip, fork_end, branch_radius * .42, branch_radius * .12, 2})
        }
    }
    return result
}

olive_emit_spray :: proc(plant: ^lsystem.Plant, random: ^u64, position, direction: lsystem.Vec3, depth: int) {
    stem := linalg.normalize0(direction)
    side := linalg.normalize0(linalg.cross(stem, lsystem.Vec3{0, 1, 0}))
    if linalg.dot(side, side) < .2 do side = {1, 0, 0}
    stem_up := linalg.normalize0(linalg.cross(side, stem))
    // Olive blades spread mostly sideways from a shoot. A full 360-degree
    // roll creates implausible curtains of vertically hanging leaf pairs.
    phase := olive_random_signed(random) * .45
    forward := linalg.normalize0(side * math.cos(phase) + stem_up * math.sin(phase))
    up := linalg.normalize0(linalg.cross(forward, stem))
    append(&plant.leaves, lsystem.Leaf{position = position, forward = forward, up = up, depth = depth})
}

olive_grow_branch :: proc(
    plant: ^lsystem.Plant,
    random, foliage_random: ^u64,
    start, initial_direction: lsystem.Vec3,
    length, radius: f32,
    depth, generations: int,
) {
    if plant == nil || generations < 0 do return
    direction := linalg.normalize0(initial_direction)
    position := start
    current_radius := radius
    segment_count := generations > 0 ? 3 : 2
    for segment_index in 0 ..< segment_count {
        // Olive wood keeps the momentum of its parent while wandering and
        // turning upward. Small independent yaw and roll changes avoid the
        // radial spokes and planar fans produced by fixed turtle rotations.
        side := linalg.normalize0(linalg.cross(direction, lsystem.Vec3{0, 1, 0}))
        if linalg.dot(side, side) < .2 do side = {1, 0, 0}
        binormal := linalg.normalize0(linalg.cross(side, direction))
        direction = linalg.normalize0(
            direction +
            side * olive_random_signed(random) * .16 +
            binormal * olive_random_signed(random) * .10 +
            lsystem.Vec3{0, .05, 0},
        )
        segment_length := length * (.92 - f32(segment_index) * .09) * (1 + olive_random_signed(random) * .10)
        next := position + direction * segment_length
        end_radius := current_radius * (.80 - f32(segment_index) * .035)
        append(
            &plant.segments,
            lsystem.Segment {
                start = position,
                end = next,
                radius_start = current_radius,
                radius_end = end_radius,
                depth = depth,
            },
        )
        position = next
        current_radius = end_radius
        if generations <= 2 || segment_index == segment_count - 1 {
            // Do not repeat identical stations on every recursive shoot. In
            // projection those shared .42/.73 fractions line up into obvious
            // horizontal foliage shelves. Small deterministic offsets retain
            // the olive's paired rhythm while breaking the procedural bands.
            inner_fraction := .40 + olive_random_signed(foliage_random) * .09
            outer_fraction := .72 + olive_random_signed(foliage_random) * .08
            olive_emit_spray(
                plant,
                foliage_random,
                position - direction * segment_length * (1 - inner_fraction),
                direction,
                depth,
            )
            olive_emit_spray(
                plant,
                foliage_random,
                position - direction * segment_length * (1 - outer_fraction),
                direction,
                depth,
            )
            olive_emit_spray(plant, foliage_random, position, direction, depth)
        } else if generations >= 3 && segment_index == 1 {
            // One sparse interior pair visually carries foliage from the old
            // scaffold into the terminal crown. Leaving the whole primary
            // run bare produces long isolated arms with detached tip clumps.
            bridge_fraction := .68 + olive_random_signed(foliage_random) * .10
            bridge_position := position - direction * segment_length * (1 - bridge_fraction)
            olive_emit_spray(plant, foliage_random, bridge_position, direction, depth)
            olive_emit_spray(
                plant,
                foliage_random,
                bridge_position - direction * segment_length * .20,
                direction,
                depth,
            )
        }
    }
    if generations == 0 do return

    child_count := generations >= 2 && lsystem.random_next(random) % 3 == 0 ? 3 : 2
    parent_direction := direction
    parent_side := linalg.normalize0(linalg.cross(parent_direction, lsystem.Vec3{0, 1, 0}))
    if linalg.dot(parent_side, parent_side) < .2 do parent_side = {1, 0, 0}
    parent_up := linalg.normalize0(linalg.cross(parent_side, parent_direction))
    phase := olive_random_signed(random) * math.PI
    for child_index in 0 ..< child_count {
        azimuth := phase + f32(child_index) * math.PI * 2 / f32(child_count)
        radial := parent_side * math.cos(azimuth) + parent_up * math.sin(azimuth)
        child_direction := linalg.normalize0(
            parent_direction * (.58 + olive_random_signed(random) * .08) +
            radial * (.52 + olive_random_signed(random) * .10) +
            lsystem.Vec3{0, .12 + olive_random_signed(random) * .08, 0},
        )
        olive_grow_branch(
            plant,
            random,
            foliage_random,
            position,
            child_direction,
            length * (.70 + olive_random_signed(random) * .05),
            current_radius * .66,
            depth + 1,
            generations - 1,
        )
    }
}

olive_skeleton :: proc(seed: u64, maturity: f32, iterations: int) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed ~ 0xa0761d6478bd642f
    if random == 0 do random = 1
    foliage_random := seed ~ 0xe7037ed1a0b428db
    if foliage_random == 0 do foliage_random = 1
    root_random := seed ~ 0x8ebc6af09c88c6e3
    if root_random == 0 do root_random = 1
    habit_random := seed ~ 0x589965cc75374cc3
    if habit_random == 0 do habit_random = 1
    scale := .22 + maturity * .78
    trunk_segments := clamp(2 + int(maturity * 2.2), 2, 4)
    trunk_points: [5]lsystem.Vec3
    trunk_points[0] = {}
    // Olive height and primary scaffolds establish well before the trunk
    // acquires its old, massive character. A slightly steeper age curve keeps
    // adolescents from reading as miniature ancient bonsai while preserving
    // the full mature girth.
    trunk_base_radius := .25 * (.10 + math.pow(maturity, 2.2) * .90)
    trunk_radius := trunk_base_radius
    for index in 0 ..< trunk_segments {
        t := f32(index + 1) / f32(trunk_segments)
        wander :=
            lsystem.Vec3 {
                olive_random_signed(&random) * .16,
                .50 + olive_random_signed(&random) * .035,
                olive_random_signed(&random) * .16,
            } *
            scale
        // Buttress flare is carried by the first two radii rather than by a
        // separate stump primitive, so the spline remains continuous.
        end_radius := trunk_base_radius * (.92 - t * .35)
        append(
            &result.plant.segments,
            lsystem.Segment {
                start = trunk_points[index],
                end = trunk_points[index] + wander,
                radius_start = trunk_radius,
                radius_end = end_radius,
                depth = 0,
            },
        )
        trunk_points[index + 1] = trunk_points[index] + wander
        trunk_radius = end_radius
    }
    if maturity > .55 {
        root_phase := olive_random_signed(&root_random) * math.PI
        for root_index in 0 ..< 3 {
            angle := root_phase + f32(root_index) * math.PI * 2 / 3
            reach := .34 + f32(lsystem.random_next(&root_random) % 9) * .010
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
            bow := olive_random_signed(&root_random) * reach * .16
            root_start := radial * .035 + lsystem.Vec3{0, .045, 0}
            root_mid := radial * reach * .56 + tangent * bow + lsystem.Vec3{0, .025, 0}
            root_end := radial * reach + tangent * bow * .45 + lsystem.Vec3{0, .010, 0}
            root_depth := -1 - root_index
            append(
                &result.plant.segments,
                lsystem.Segment {
                    start = root_start,
                    end = root_mid,
                    radius_start = trunk_base_radius * .42,
                    radius_end = trunk_base_radius * .22,
                    depth = root_depth,
                },
                lsystem.Segment {
                    start = root_mid,
                    end = root_end,
                    radius_start = trunk_base_radius * .22,
                    radius_end = trunk_base_radius * .06,
                    depth = root_depth,
                },
            )
        }
    }

    // Mature olives carry several persistent scaffold axes around the short
    // trunk. Three loosely opposed pairs close the conspicuous five-spoke
    // gaps, but small complementary differences in bearing, reach, and lift
    // keep the result from reading as a manufactured radial candelabrum.
    leader_count := maturity >= .78 ? (iterations >= 4 ? 6 : 5) : maturity >= .40 ? 5 : 3
    generations := clamp(iterations - 1, 0, 3)
    drift_angle := f32(lsystem.random_next(&habit_random) % 10_000) / 10_000 * math.PI * 2
    prevailing_drift := lsystem.Vec3{math.cos(drift_angle) * .10, 0, math.sin(drift_angle) * .10}
    for leader_index in 0 ..< leader_count {
        // Stagger leader origins over the upper trunk instead of creating a
        // single swollen umbrella hub.
        origin_index := clamp(trunk_segments - 1 + leader_index % 2, 1, trunk_segments)
        origin := trunk_points[origin_index]
        pair_count := max(leader_count / 2, 1)
        pair_index := leader_index % pair_count
        pair_random := seed ~ (u64(pair_index + 1) * 0x94d049bb133111eb)
        if pair_random == 0 do pair_random = 1
        pair_jitter := olive_random_signed(&pair_random) * .22
        pair_reach := 1 + olive_random_signed(&pair_random) * .14
        pair_skew := olive_random_signed(&pair_random) * .13
        pair_asymmetry := olive_random_signed(&pair_random) * .09
        pair_lift := olive_random_signed(&pair_random) * .08
        pair_side := leader_index < pair_count ? f32(-1) : f32(1)
        azimuth := f32(leader_index) * math.PI * 2 / f32(leader_count) + pair_jitter + pair_side * pair_skew
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        spread := .55 + maturity * .17
        lift := .72 - maturity * .20
        direction := linalg.normalize0(
            radial * (spread + olive_random_signed(&random) * .10) +
            prevailing_drift +
            lsystem.Vec3{0, lift + pair_side * pair_lift + olive_random_signed(&random) * .12, 0},
        )
        olive_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            origin,
            direction,
            .38 * scale * pair_reach * (1 + pair_side * pair_asymmetry),
            trunk_radius * (.52 + olive_random_signed(&random) * .06),
            1,
            generations,
        )
    }
    if maturity > .78 {
        // A short capped stub suggests past pruning and keeps the inner crown
        // from reading as a flawless procedural fork. It remains leafless.
        stub_origin := trunk_points[max(trunk_segments - 1, 1)]
        stub_azimuth := olive_random_signed(&random) * math.PI
        stub_direction := linalg.normalize0(lsystem.Vec3{math.cos(stub_azimuth), .34, math.sin(stub_azimuth)})
        stub_mid := stub_origin + stub_direction * .17
        stub_end := stub_mid + linalg.normalize0(stub_direction + lsystem.Vec3{0, .12, 0}) * .10
        append(
            &result.plant.segments,
            lsystem.Segment{stub_origin, stub_mid, trunk_radius * .30, trunk_radius * .20, 1},
            lsystem.Segment{stub_mid, stub_end, trunk_radius * .20, trunk_radius * .08, 1},
        )
    }
    return result
}

cypress_skeleton :: proc(
    seed: u64,
    maturity: f32,
    tier_count: int,
    reference_tier_count: f32,
) -> lsystem.Interpret_Result {
    result: lsystem.Interpret_Result
    random := seed
    if random == 0 do random = 1
    step := f32(.37) * (.22 + maturity * .78)
    // LOD may remove a few whorls, but it must not visibly shorten the tree.
    // Renormalize the decaying leader-step series against the full-detail
    // tier count so every detail level retains the authored mature height.
    decay := f32(.94)
    actual_step_sum := (1 - math.pow(decay, f32(tier_count + 1))) / (1 - decay)
    reference_step_sum := (1 - math.pow(decay, reference_tier_count + 1)) / (1 - decay)
    step *= reference_step_sum / max(actual_step_sum, f32(.001))
    base_radius := f32(.11) * (.28 + maturity * .72)
    position := lsystem.Vec3{}
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    height_scale := 1 + olive_random_signed(&random) * .07
    spread_angle := .38 + olive_random_signed(&random) * .035
    taper_drop := .20 + olive_random_signed(&random) * .08
    drift_angle := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    drift_strength := .012 + math.abs(olive_random_signed(&random)) * .010
    drift_curve := olive_random_signed(&random) * .65
    step *= height_scale

    // One short basal leader remains at zero iterations so very young plants
    // still have valid woody geometry. Successive tiers are generated in
    // true radial whorls instead of relying on coupled turtle yaw/roll state,
    // which made the crown more than twice as wide from one azimuth.
    total_leader_segments := tier_count + 1
    for tier in 0 ..< total_leader_segments {
        progress := f32(tier) / f32(max(total_leader_segments - 1, 1))
        segment_length := step * math.pow(f32(.94), f32(tier))
        segment_length *= 1 + olive_random_signed(&random) * .025
        leader_start := position
        tier_drift_angle := drift_angle + drift_curve * (progress - .5)
        tier_drift_direction := lsystem.Vec3{math.cos(tier_drift_angle), 0, math.sin(tier_drift_angle)}
        drift := tier_drift_direction * segment_length * drift_strength * (.35 + progress)
        next := position + lsystem.Vec3{drift[0], segment_length, drift[2]}
        radius_start := max(base_radius * (1 - progress * .72), f32(.014))
        next_progress := f32(tier + 1) / f32(max(total_leader_segments - 1, 1))
        radius_end := max(base_radius * (1 - next_progress * .72), f32(.010))
        if tier == 0 {
            // A modest root flare grounds the narrow column without turning
            // the lower trunk into the broad buttress of an old hardwood.
            radius_start *= 1.25
        }
        append(
            &result.plant.segments,
            lsystem.Segment {
                start = position,
                end = next,
                radius_start = radius_start,
                radius_end = radius_end,
                depth = 0,
            },
        )
        if tier == 0 {
            // Vertical scale sprays bridge the root flare into the first
            // woody whorl without introducing a detached low branch tuft.
            basal_anchor_fractions := [2]f32{.32, .72}
            for fraction in basal_anchor_fractions {
                append(
                    &result.plant.leaves,
                    lsystem.Leaf {
                        position = position + (next - position) * fraction,
                        forward = {0, 1, 0},
                        up = {1, 0, 0},
                        depth = -3,
                    },
                )
            }
        }
        leader_leaf_depth := tier == total_leader_segments - 1 ? -2 : 0
        append(
            &result.plant.leaves,
            lsystem.Leaf{position = next, forward = {0, 1, 0}, up = {1, 0, 0}, depth = leader_leaf_depth},
        )
        position = next
        if tier >= tier_count do continue
        branch_origin := position

        // A golden-angle phase shift prevents vertically stacked radial seams
        // while every individual tier remains balanced in opposite pairs.
        tier_phase := phase + f32(tier) * 2.399963
        // Step decay already shortens successive whorls by roughly half.
        // Only a mild additional envelope taper is needed; multiplying both
        // effects strongly made the upper two-thirds read as a bare pole.
        taper := 1 - progress * taper_drop
        // Young trees have only a few widely separated whorls, so begin
        // closing their crown earlier. As tiers fill in, move the taper back
        // toward the mature upper quarter to retain the tall column.
        apex_start := .34 + clamp((maturity - .28) / .42, f32(0), f32(1)) * .38
        apex_progress := clamp((progress - apex_start) / (1 - apex_start), f32(0), f32(1))
        taper *= 1 - apex_progress * apex_progress * .58
        // Whole intervals breathe in and out slightly, producing the subtle
        // uneven outline of a living crown rather than a lathed green pole.
        tier_fullness := 1 + olive_random_signed(&random) * .12
        pair_lengths: [4]f32
        for &pair_length in pair_lengths {
            pair_length = 1 + olive_random_signed(&random) * .08
        }
        pair_angles: [4]f32
        for &pair_angle in pair_angles {
            // Opposite branches share the same offset, retaining exact radial
            // balance while breaking the mechanical 45-degree whorl lattice.
            pair_angle = olive_random_signed(&random) * .055
        }
        pair_spreads: [4]f32
        for &pair_spread in pair_spreads {
            // Matching elevation within each opposite pair cancels lateral
            // bias but avoids a perfectly level ring of identical shoots.
            pair_spread = olive_random_signed(&random) * .028
        }
        pair_retractions: [4]f32
        for &pair_retraction, pair_index in pair_retractions {
            // Italian cypress does not carry eight branches from one visible
            // collar. Distribute the four opposite pairs through most of the
            // preceding leader interval so adjacent tiers interleave into one
            // continuous column. Each pair still shares an exact origin and
            // remains radially balanced; the small jitter avoids replacing a
            // whorl lattice with four equally spaced horizontal ranks.
            pair_retraction = .06 + f32(pair_index) * .12 + olive_random_signed(&random) * .014
        }
        for branch_index in 0 ..< 8 {
            azimuth := tier_phase + f32(branch_index) * math.PI * 2 / 8 + pair_angles[branch_index % 4]
            radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
            lower_crown_weight := 1 - clamp(progress / .32, f32(0), f32(1))
            // Lower limbs open a little farther from the leader, giving the
            // tree a grounded shoulder before it settles into the familiar
            // narrow column. Upper shoots retain their strongly ascending
            // habit rather than turning the whole crown conical.
            local_spread := spread_angle + pair_spreads[branch_index % 4] + lower_crown_weight * .06
            direction := linalg.normalize0(
                radial * math.sin(local_spread) + lsystem.Vec3{0, math.cos(local_spread), 0},
            )
            local_branch_origin := branch_origin - (branch_origin - leader_start) * pair_retractions[branch_index % 4]
            // Half-rate decay produces the cypress's nearly columnar crown;
            // using the leader segment length directly pinched every seed
            // above a bulbous lower third. The explicit apex envelope still
            // closes the final tiers into a narrow tip.
            branch_envelope_length := math.sqrt(max(segment_length * step, f32(0)))
            basal_progress := clamp(progress / .48, f32(0), f32(1))
            basal_smooth := basal_progress * basal_progress * (3 - 2 * basal_progress)
            // A real mature cypress carries its heaviest body in the lower
            // third. Earlier values suppressed exactly those first whorls,
            // leaving a bottle-brush trunk beneath a top-heavy column.
            basal_envelope := 1.28 - basal_smooth * .10
            branch_length :=
                branch_envelope_length * basal_envelope * taper * tier_fullness * pair_lengths[branch_index % 4]
            // Keep every upper whorl beneath the remaining leader. The
            // penultimate whorl can otherwise overtake a short random final
            // step even when the last whorl itself is tightly constrained.
            remaining_leader_length := f32(0)
            for remaining_tier in tier + 1 ..= tier_count {
                remaining_leader_length += step * math.pow(decay, f32(remaining_tier)) * .975
            }
            branch_length = min(branch_length, remaining_leader_length * .40)
            branch_mid := local_branch_origin + direction * branch_length
            // Cypress scaffold limbs open away from the trunk, then their
            // outer sprays turn sharply upward. Keeping both segments on one
            // diagonal made every nominal tier taper back to the leader and
            // expand again, producing the stacked-bead silhouette visible in
            // captures. The upright second segment holds foliage at the
            // crown envelope and lets neighboring tiers overlap vertically.
            tip_spread := local_spread * .42
            tip_direction := linalg.normalize0(
                radial * math.sin(tip_spread) + lsystem.Vec3{0, math.cos(tip_spread), 0},
            )
            branch_tip := branch_mid + tip_direction * branch_length * .78
            branch_radius := max(radius_end * .42, f32(.008))
            append(
                &result.plant.segments,
                lsystem.Segment {
                    start = local_branch_origin,
                    end = branch_mid,
                    radius_start = branch_radius,
                    radius_end = max(branch_radius * .72, f32(.005)),
                    depth = 1,
                },
                lsystem.Segment {
                    start = branch_mid,
                    end = branch_tip,
                    radius_start = max(branch_radius * .72, f32(.005)),
                    radius_end = max(branch_radius * .46, f32(.003)),
                    depth = 1,
                },
            )
            up := linalg.normalize0(linalg.cross(direction, radial))
            if linalg.dot(up, up) < .1 do up = {1, 0, 0}
            append(
                &result.plant.leaves,
                lsystem.Leaf{position = branch_mid, forward = direction, up = up, depth = 1},
                lsystem.Leaf{position = branch_tip, forward = tip_direction, up = up, depth = 1},
            )
        }
    }
    return result
}

generate :: proc(config: Generate_Config) -> Generate_Result {
    result: Generate_Result
    if int(config.species) < 0 || int(config.species) >= SPECIES_COUNT {
        result.error = .Invalid_Species
        return result
    }
    habit := config.habit
    if habit == .Free_Standing &&
       (config.species == .Bougainvillea ||
               config.species == .Grapevine ||
               config.species == .Wisteria ||
               config.species == .Climbing_Rose ||
               config.species == .Star_Jasmine) {
        habit = default_habit(config.species)
    }
    climbing := habit != .Free_Standing
    if climbing && (config.support == nil || config.support.width <= 0 || config.support.height <= 0) {
        result.error = .Invalid_Support
        return result
    }

    maturity := clamp(config.maturity, 0, 1)
    profile := profile_for(config.species)
    detail_reduction := config.detail == .Near ? 0 : config.detail == .Medium ? 1 : 2
    raw_iterations := maturity * f32(profile.base_iterations)
    // Generate the topology of the incoming flush, then let
    // sprout_newest_generation extend it continuously below.
    growth_iterations := int(math.ceil(raw_iterations))
    iterations := clamp(growth_iterations - detail_reduction, 0, profile.base_iterations)
    generation_progress := raw_iterations - math.floor(raw_iterations)
    if raw_iterations > 0 && generation_progress < .0001 do generation_progress = 1
    segment_limit, attachment_limit := limits(config.detail)
    if climbing {
        segment_limit, attachment_limit = climbing_density_limits(config.detail, config.support)
    }
    expansion_segment_limit := segment_limit
    if climbing {
        // A small support still needs the complete authored vine as the
        // sampling domain. Surface density is applied after interpretation;
        // constraining expansion here would fail before that sampler runs.
        catalog_segment_limit, _ := limits(config.detail)
        expansion_segment_limit = max(expansion_segment_limit, catalog_segment_limit)
    }
    interpreted: lsystem.Interpret_Result
    if config.species == .Olive {
        // Far LOD keeps the medium woody silhouette and spends its savings on
        // leaf clustering and mesh tessellation. Removing another entire
        // branch generation makes olives read as bare candelabras.
        olive_iterations := max(olive_growth_iterations(maturity) - detail_reduction, 0)
        if config.detail == .Far && maturity >= .68 do olive_iterations = max(olive_iterations, 3)
        interpreted = olive_skeleton(config.seed, maturity, olive_iterations)
    } else if config.species == .Lemon {
        interpreted = lemon_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Almond {
        interpreted = almond_orchard_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Fig {
        interpreted = fig_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Pomegranate {
        interpreted = pomegranate_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Strawberry_Tree {
        interpreted = strawberry_tree_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Myrtle {
        interpreted = myrtle_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Mastic {
        interpreted = mastic_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Agapanthus {
        interpreted = agapanthus_skeleton(config.seed, maturity, config.detail)
    } else if config.species == .Lavender {
        interpreted = lavender_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Thyme {
        interpreted = thyme_skeleton(config.seed, maturity, config.detail)
    } else if config.species == .Sage {
        interpreted = sage_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Carob {
        interpreted = carob_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Bay_Laurel {
        interpreted = bay_laurel_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Holm_Oak ||
       config.species == .Oriental_Plane ||
       config.species == .European_Hackberry ||
       config.species == .White_Poplar {
        interpreted = broadleaf_tree_skeleton(config.species, config.seed, maturity, iterations)
    } else if config.species == .Italian_Cypress {
        // Grow toward eighteen mature branch intervals continuously after establishment.
        // Ceil exposes one emerging tier at a time, while the skeleton's
        // geometric-series normalization interpolates its height within that
        // interval instead of jumping five complete tiers per grammar step.
        reference_tier_count := clamp((maturity - .10) / .90, f32(0), f32(1)) * 18
        tier_count := int(math.ceil(reference_tier_count))
        if config.detail == .Medium && tier_count > 5 do tier_count -= 1
        // Far spends its fixed budget on eleven silhouette-critical whorls.
        // Its redundant secondary leader anchors are omitted below, leaving
        // this denser topology beneath both hard geometry ceilings.
        if config.detail == .Far do tier_count = min(tier_count, 11)
        interpreted = cypress_skeleton(config.seed, maturity, tier_count, reference_tier_count)
    } else if config.species == .Pelargonium {
        interpreted = pelargonium_skeleton(config.seed, maturity)
    } else if config.species == .Rosemary {
        interpreted = rosemary_skeleton(config.seed, maturity, config.detail)
    } else if config.species == .Hydrangea_Bush || config.species == .Hydrangea_Tree {
        interpreted = hydrangea_skeleton(config.species, config.seed, maturity, config.detail)
    } else if config.species == .Grapevine {
        interpreted = grapevine_skeleton(config.seed, maturity, config.detail)
    } else if config.species == .Star_Jasmine {
        interpreted = star_jasmine_skeleton(config.seed, maturity, config.detail)
    } else if config.species == .Wisteria {
        interpreted = wisteria_skeleton(config.seed, maturity, config.detail)
    } else if config.species == .Climbing_Rose {
        interpreted = climbing_rose_skeleton(config.seed, maturity, config.detail)
    } else if config.species == .Prickly_Pear {
        interpreted = prickly_pear_skeleton(config.seed, maturity)
    } else if config.species == .Golden_Barrel || config.species == .Agave || config.species == .Aloe {
        interpreted = fleshy_plant_skeleton(config.species, config.seed, maturity, config.detail)
    } else if config.species == .Aeonium ||
              config.species == .Echeveria ||
              config.species == .Jade_Plant ||
              config.species == .Stonecrop ||
              config.species == .Blue_Chalk_Sticks ||
              config.species == .Golden_Torch_Cactus {
        interpreted = succulent_catalog_skeleton(config.species, config.seed, maturity, config.detail)
    } else if config.species == .Stone_Pine {
        interpreted = stone_pine_skeleton(config.seed, maturity, iterations)
    } else {
        alternatives := [2]lsystem.Alternative {
            {text = profile.production_a, weight = profile.weight_a},
            {text = profile.production_b, weight = profile.weight_b},
        }
        rules := [1]lsystem.Rule{{symbol = 'F', alternatives = alternatives[:]}}
        axiom := profile.axiom
        grammar_rules := rules[:]
        word := lsystem.expand(
            {axiom = axiom, rules = grammar_rules},
            {iterations = iterations, seed = config.seed, max_symbols = expansion_segment_limit * 8},
        )
        if word.error != .None {
            lsystem.destroy_word(&word)
            result.error = .Expansion_Failed
            return result
        }
        interpreted = lsystem.interpret(
            word.word[:],
            {
                step = profile.step * (.22 + maturity * .78),
                step_scale = profile.step_scale,
                step_jitter = .08,
                angle = profile.angle,
                angle_jitter = .14,
                radius = profile.radius * (.28 + maturity * .72),
                radius_scale = profile.radius_scale,
                seed = config.seed,
            },
        )
        lsystem.destroy_word(&word)
    }
    if interpreted.error != .None {
        lsystem.destroy_plant(&interpreted.plant)
        result.error = .Interpretation_Failed
        return result
    }
    if iterations > 0 &&
       config.species != .Prickly_Pear &&
       config.species != .Golden_Barrel &&
       config.species != .Agave &&
       config.species != .Aloe &&
       config.species != .Aeonium &&
       config.species != .Echeveria &&
       config.species != .Jade_Plant &&
       config.species != .Stonecrop &&
       config.species != .Blue_Chalk_Sticks &&
       config.species != .Golden_Torch_Cactus &&
       // Dedicated herbaceous rosettes author their lifecycle continuously;
       // grammar sprouting would add woody-looking links through the clump.
       config.species != .Agapanthus &&
       config.species != .Strawberry_Tree &&
       config.species != .Rosemary &&
       config.species != .Pelargonium &&
       config.species != .Hydrangea_Bush &&
       config.species != .Hydrangea_Tree &&
       config.species != .Star_Jasmine &&
       config.species != .Wisteria &&
       config.species != .Climbing_Rose &&
       config.species != .Lavender &&
       config.species != .Thyme &&
       config.species != .Sage {
        sprout_newest_generation(&interpreted.plant, generation_progress)
    }
    if config.species == .Myrtle || config.species == .Mastic || config.species == .Sage {
        myrtle_clothe_scaffold(&interpreted.plant)
    }
    if config.species == .Lavender do lavender_clothe_scaffold(&interpreted.plant)
    if config.species == .Stone_Pine do stone_pine_clothe_scaffold(&interpreted.plant, config.detail)
    // Reserve six samples for every climbing source link. Additional samples
    // are allocated to long projected canes below without discarding authored
    // parent/child links to make room for them.
    source_segment_limit := climbing ? max(segment_limit / 6, 1) : segment_limit
    if climbing && len(interpreted.plant.segments) > source_segment_limit {
        // Sample across the complete authored word so a small support keeps
        // the vine's full spatial coverage instead of truncating its final
        // branches. Each retained link still receives its full route samples.
        source_segments := interpreted.plant.segments
        thinned_segments := make([dynamic]lsystem.Segment, 0, source_segment_limit)
        for retained_index in 0 ..< source_segment_limit {
            source_index := retained_index * len(source_segments) / source_segment_limit
            append(&thinned_segments, source_segments[source_index])
        }
        delete(source_segments)
        interpreted.plant.segments = thinned_segments
    } else if len(interpreted.plant.segments) > source_segment_limit {
        lsystem.destroy_plant(&interpreted.plant)
        result.error = .Segment_Limit
        return result
    }
    if config.species == .Italian_Cypress {
        // Cypress scale leaves sheath both leaders and lateral sprays rather
        // than occurring only at terminal buds. The skeleton already emits
        // end anchors, so place the additional density between nodes instead
        // of stacking duplicate cards into blunt pom-poms.
        for segment, segment_index in interpreted.plant.segments {
            direction := linalg.normalize0(segment.end - segment.start)
            append(
                &interpreted.plant.leaves,
                lsystem.Leaf {
                    position = (segment.start + segment.end) * .5,
                    forward = direction,
                    up = {1, 0, 0},
                    depth = segment.depth,
                },
            )
            if segment.depth == 1 && config.detail == .Near {
                // One midpoint alone leaves long lateral shoots as separated
                // tufts. A second staggered anchor distributes scale-leaf
                // sprays along the shoot, closing the woody gaps without
                // widening the cypress's deliberately narrow silhouette.
                append(
                    &interpreted.plant.leaves,
                    lsystem.Leaf {
                        position = segment.start + (segment.end - segment.start) * .78,
                        forward = direction,
                        up = {1, 0, 0},
                        depth = segment.depth,
                    },
                )
                // Cypress skeleton order is one leader followed by sixteen
                // lateral segments per branch interval. Derive the stable
                // interval rather than normalizing against current height;
                // the latter changes during growth and can make established
                // foliage disappear when a new top interval is added.
                branch_interval := segment_index / 17
                relative_interval := f32(branch_interval) / 18
                lower_density := clamp((.46 - relative_interval) / .40, f32(0), f32(1))
                density_hash := (config.seed + 1) * 0x9e3779b97f4a7c15 ~ u64(segment_index + 23) * 0xbf58476d1ce4e5b9
                density_hash = (density_hash ~ (density_hash >> 29)) * 0x94d049bb133111eb
                if f32(density_hash % 10_000) < lower_density * 10_000 {
                    // The lower crown carries more overlapping secondary
                    // spray than the upper spire. Fade these anchors out
                    // independently through mid-crown: a hard shared height
                    // cutoff creates a conspicuous horizontal foliage shelf.
                    append(
                        &interpreted.plant.leaves,
                        lsystem.Leaf {
                            position = segment.start + (segment.end - segment.start) * .28,
                            forward = direction,
                            up = {1, 0, 0},
                            depth = segment.depth,
                        },
                    )
                }
            }
            if segment.depth == 0 && config.detail != .Far {
                // Two staggered leader anchors keep the inner column clothed
                // without doubling the terminal tuft at each tier.
                append(
                    &interpreted.plant.leaves,
                    lsystem.Leaf {
                        position = segment.start + (segment.end - segment.start) * .20,
                        forward = direction,
                        up = {1, 0, 0},
                        depth = segment.depth,
                    },
                )
            }
        }
    }
    attachment_count := 0
    cluster_size := leaf_cluster_size(config.species, config.detail, maturity)
    if climbing && len(interpreted.plant.leaves) * max(cluster_size, 1) > attachment_limit {
        // As with cane links, distribute retained anchors across the complete
        // plant rather than keeping a dense prefix on only one side.
        source_leaves := interpreted.plant.leaves
        leaf_limit := max(attachment_limit / max(cluster_size, 1), 1)
        thinned_leaves := make([dynamic]lsystem.Leaf, 0, leaf_limit)
        for retained_index in 0 ..< leaf_limit {
            source_index := retained_index * len(source_leaves) / leaf_limit
            append(&thinned_leaves, source_leaves[source_index])
        }
        delete(source_leaves)
        interpreted.plant.leaves = thinned_leaves
    }
    for leaf, index in interpreted.plant.leaves {
        kind := generated_attachment_kind(config.species, config.seed, index, maturity, config.detail, leaf.depth)
        leaf_cluster_size := cluster_size
        if config.species == .Italian_Cypress {
            leaf_cluster_size = cypress_generated_cluster_size(config.detail, maturity, config.seed, index, leaf.depth)
        } else if config.species == .Lemon && leaf.depth >= 2 {
            // Fine citrus shoots already carry two staggered anchors per
            // segment. Expanding both into paired cards makes the terminal
            // crown opaque and buries fruit and branch structure. Keep the
            // paired treatment on the primary scaffold, then let secondary
            // and terminal anchors each represent one alternating leaf.
            leaf_cluster_size = 1
        }
        if config.species == .Grapevine && kind != .Leaf {
            // A grape cluster or tendril arises opposite a persistent leaf at
            // the same phytomer; it does not replace that leaf.
            attachment_count += 2
        } else if config.species == .Italian_Cypress && kind == .Fruit {
            // Cypress cones are carried within a live scale-leaf spray; they
            // supplement that foliage rather than replacing the whole pad.
            attachment_count += leaf_cluster_size + 1
        } else {
            attachment_count += kind == .Leaf ? leaf_cluster_size : 1
        }
    }
    if attachment_count > attachment_limit {
        lsystem.destroy_plant(&interpreted.plant)
        result.error = .Attachment_Limit
        return result
    }

    result.plant.species = config.species
    result.plant.habit = habit
    if config.species == .Olive {
        result.plant.wood = {
            radial_irregularity = .20,
            twist               = 1.50,
        }
    } else if config.species == .Italian_Cypress {
        // Restrained longitudinal fluting keeps exposed leader sections from
        // reading as smooth cylinders without giving the narrow conifer the
        // deeply twisted, gnarled surface of an old olive.
        result.plant.wood = {
            radial_irregularity = .075,
            twist               = .42,
        }
    } else if config.species == .Lemon {
        // Young citrus bark is comparatively restrained but not lathed
        // smooth. A little longitudinal irregularity keeps the short exposed
        // trunk and scaffold forks organic without borrowing olive's deeply
        // twisted, ancient character.
        result.plant.wood = {
            radial_irregularity = .055,
            twist               = .28,
        }
    }
    result.plant.root_kind = climbing && config.support.planter ? .Planter : .Soil
    result.plant.wind_compliance = woody_wind_compliance(config.species, maturity)
    if climbing do result.plant.support_signature = support_hash(config.support^)
    climbing_route_samples := climbing ? 6 : 1
    if config.species == .Grapevine do climbing_route_samples = 1
    routed_segment_capacity := len(interpreted.plant.segments) * climbing_route_samples
    result.plant.segments = make([dynamic]lsystem.Segment, 0, routed_segment_capacity)
    result.plant.attachments = make([dynamic]Attachment, 0, attachment_count)

    climbing_height, climbing_half_width := f32(1), f32(.001)
    if climbing {
        climbing_height = .001
        for segment in interpreted.plant.segments {
            start := lsystem.Vec3 {
                segment.start[0] * profile.width_scale,
                segment.start[1] * profile.height_scale,
                segment.start[2] * profile.width_scale,
            }
            end := lsystem.Vec3 {
                segment.end[0] * profile.width_scale,
                segment.end[1] * profile.height_scale,
                segment.end[2] * profile.width_scale,
            }
            climbing_height = max(climbing_height, max(start[1], end[1]))
            climbing_half_width = max(
                climbing_half_width,
                max(max(math.abs(start[0]), math.abs(end[0])), max(math.abs(start[2]), math.abs(end[2]))),
            )
        }
    }

    extra_route_demand := 0
    maximum_route_samples := config.detail == .Near ? 12 : config.detail == .Medium ? 9 : 6
    if config.species == .Grapevine do maximum_route_samples = 1
    if climbing && maximum_route_samples > climbing_route_samples {
        for source in interpreted.plant.segments {
            start := lsystem.Vec3 {
                source.start[0] * profile.width_scale,
                source.start[1] * profile.height_scale,
                source.start[2] * profile.width_scale,
            }
            end := lsystem.Vec3 {
                source.end[0] * profile.width_scale,
                source.end[1] * profile.height_scale,
                source.end[2] * profile.width_scale,
            }
            routed_start := route_point(start, config.support, climbing_height, climbing_half_width, habit, source.depth)
            routed_end := route_point(end, config.support, climbing_height, climbing_half_width, habit, source.depth)
            delta := routed_end - routed_start
            projected_length := math.sqrt(linalg.dot(delta, delta))
            desired_samples := clamp(int(math.ceil(projected_length / .32)), climbing_route_samples, maximum_route_samples)
            extra_route_demand += desired_samples - climbing_route_samples
        }
    }
    base_routed_count := len(interpreted.plant.segments) * climbing_route_samples
    extra_route_budget := min(extra_route_demand, max(segment_limit - base_routed_count, 0))
    extra_demand_seen, extra_samples_awarded := 0, 0

    first := true
    for source in interpreted.plant.segments {
        segment := source
        segment.start[0] *= profile.width_scale
        segment.start[1] *= profile.height_scale
        segment.start[2] *= profile.width_scale
        segment.end[0] *= profile.width_scale
        segment.end[1] *= profile.height_scale
        segment.end[2] *= profile.width_scale
        if climbing {
            route_samples := climbing_route_samples
            if extra_route_demand > 0 && extra_route_budget > 0 {
                routed_start := route_point(
                    segment.start,
                    config.support,
                    climbing_height,
                    climbing_half_width,
                    habit,
                    segment.depth,
                )
                routed_end := route_point(
                    segment.end,
                    config.support,
                    climbing_height,
                    climbing_half_width,
                    habit,
                    segment.depth,
                )
                delta := routed_end - routed_start
                projected_length := math.sqrt(linalg.dot(delta, delta))
                desired_samples := clamp(
                    int(math.ceil(projected_length / .32)),
                    climbing_route_samples,
                    maximum_route_samples,
                )
                extra_demand_seen += desired_samples - climbing_route_samples
                target_awarded := extra_demand_seen * extra_route_budget / extra_route_demand
                route_samples += target_awarded - extra_samples_awarded
                extra_samples_awarded = target_awarded
            }
            previous := route_point(
                segment.start,
                config.support,
                climbing_height,
                climbing_half_width,
                habit,
                segment.depth,
            )
            for sample in 1 ..= route_samples {
                t := f32(sample) / f32(route_samples)
                source_point := segment.start + (segment.end - segment.start) * t
                current := route_point(
                    source_point,
                    config.support,
                    climbing_height,
                    climbing_half_width,
                    habit,
                    segment.depth,
                )
                routed := segment
                routed.start = previous
                routed.end = current
                previous_t := f32(sample - 1) / f32(route_samples)
                routed.radius_start = segment.radius_start + (segment.radius_end - segment.radius_start) * previous_t
                routed.radius_end = segment.radius_start + (segment.radius_end - segment.radius_start) * t
                append(&result.plant.segments, routed)
                update_bounds(&result.plant.bounds, routed.start, &first)
                update_bounds(&result.plant.bounds, routed.end, &first)
                previous = current
            }
            continue
        }
        append(&result.plant.segments, segment)
        update_bounds(&result.plant.bounds, segment.start, &first)
        update_bounds(&result.plant.bounds, segment.end, &first)
    }
    for leaf, index in interpreted.plant.leaves {
        position := leaf.position
        position[0] *= profile.width_scale
        position[1] *= profile.height_scale
        position[2] *= profile.width_scale
        if climbing do position = route_point(position, config.support, climbing_height, climbing_half_width, habit, leaf.depth)
        if config.species == .Grapevine && habit == .Trellised {
            // Leaves and fruiting sites occupy short shoots above and below a
            // trained cordon, not one mathematically exact horizontal rank.
            // The grammar supplies several anchors at matching source
            // heights, so give each a small stable offset around its wire.
            // Keep the displacement within a petiole/shoot length so the
            // attachment still reads as part of the visible cane network.
            hash := (config.seed + 1) * 0x9e3779b97f4a7c15 ~ u64(index + 61) * 0xbf58476d1ce4e5b9
            hash = (hash ~ (hash >> 30)) * 0x94d049bb133111eb
            signed_offset := f32(hash % 10_001) / 5_000 - 1
            position[1] = clamp(position[1] + signed_offset * .11, f32(.03), config.support.height * .98)
        }
        variant := u8((u64(index) + config.seed) % 4)
        generated_kind := generated_attachment_kind(
            config.species,
            config.seed,
            index,
            maturity,
            config.detail,
            leaf.depth,
        )
        cypress_cone := config.species == .Italian_Cypress && generated_kind == .Fruit
        kind := cypress_cone ? Attachment_Kind.Leaf : generated_kind
        attachment_cluster_size := cluster_size
        if config.species == .Italian_Cypress {
            attachment_cluster_size = cypress_generated_cluster_size(
                config.detail,
                maturity,
                config.seed,
                index,
                leaf.depth,
            )
        } else if config.species == .Lemon && leaf.depth >= 2 {
            attachment_cluster_size = 1
        }
        forward, up := attachment_frame(leaf.forward, leaf.up, profile, climbing)
        traits :=
            kind == .Leaf ? generated_leaf_traits(config.species, variant, maturity, config.detail) : Leaf_Traits{}
        append(
            &result.plant.attachments,
            Attachment {
                kind = kind,
                stage = attachment_stage(kind, config.seed, index, maturity),
                position = position,
                forward = forward,
                up = up,
                depth = leaf.depth,
                variant = variant,
                leaf = traits,
            },
        )
        update_bounds(&result.plant.bounds, position, &first)
        if kind == .Leaf do update_leaf_bounds(&result.plant.bounds, position, forward, up, traits, &first)
        if config.species == .Grapevine && generated_kind != .Leaf {
            companion_traits := generated_leaf_traits(config.species, variant, maturity, config.detail)
            append(
                &result.plant.attachments,
                Attachment {
                    kind = .Leaf,
                    stage = .None,
                    position = position,
                    forward = forward,
                    up = up,
                    depth = leaf.depth,
                    variant = variant,
                    leaf = companion_traits,
                },
            )
            update_leaf_bounds(&result.plant.bounds, position, forward, up, companion_traits, &first)
        }
        if kind == .Leaf {
            right := linalg.normalize0(linalg.cross(forward, up))
            for cluster_index in 1 ..< attachment_cluster_size {
                angle :=
                    f32(cluster_index) * math.PI * 2 / f32(attachment_cluster_size) +
                    f32((config.seed + u64(index * 17)) % 29) / 29 * .38
                clustered_variant := u8((int(variant) + cluster_index) % 4)
                clustered_traits := generated_leaf_traits(config.species, clustered_variant, maturity, config.detail)
                clustered_forward: lsystem.Vec3
                clustered_up: lsystem.Vec3
                clustered_position: lsystem.Vec3
                if config.species == .Italian_Cypress {
                    // Scale leaves form layered, shoot-following pads rather
                    // than a terminal rosette. Rotate each card's plane around
                    // the shoot and stagger it toward the branch base so the
                    // foliage wraps and conceals the woody axis.
                    plane_up := linalg.normalize0(up * math.cos(angle) + right * math.sin(angle))
                    plane_right := linalg.normalize0(linalg.cross(forward, plane_up))
                    divergence := f32(.055 + .018 * f32(cluster_index % 2))
                    clustered_forward = linalg.normalize0(
                        forward + plane_right * divergence + plane_up * divergence * .35,
                    )
                    clustered_up = linalg.normalize0(
                        plane_up - clustered_forward * linalg.dot(plane_up, clustered_forward),
                    )
                    clustered_position =
                        position -
                        forward * clustered_traits.length * (.55 + f32(cluster_index - 1) * .62) +
                        plane_up * clustered_traits.width * .10
                    clustered_position[1] = max(clustered_position[1], 0)
                } else if config.species == .Lemon {
                    // Citrus leaves alternate around the shoot near the
                    // golden angle rather than forming mirrored pairs at one
                    // node. Recover the shoot axis from the authored leaf
                    // frame, rotate the second blade in its transverse plane,
                    // and stagger it slightly toward the branch base.
                    shoot := -right
                    alternate_random := config.seed ~ (u64(index + 1) * 0xbf58476d1ce4e5b9)
                    if alternate_random == 0 do alternate_random = 1
                    alternate_angle := f32(cluster_index) * 2.39996323 + olive_random_signed(&alternate_random) * .08
                    clustered_forward = linalg.normalize0(
                        forward * math.cos(alternate_angle) + up * math.sin(alternate_angle),
                    )
                    clustered_up = linalg.normalize0(linalg.cross(clustered_forward, shoot))
                    clustered_position =
                        position - shoot * clustered_traits.length * (.24 + f32(cluster_index - 1) * .22)
                    clustered_position[1] = max(clustered_position[1], 0)
                } else {
                    clustered_forward = linalg.normalize0(
                        forward * math.cos(angle) + right * math.sin(angle) + up * f32(cluster_index % 2) * .08,
                    )
                    clustered_up = linalg.normalize0(up - clustered_forward * linalg.dot(up, clustered_forward))
                    clustered_position = position + clustered_forward * clustered_traits.length * .08
                }
                if config.species == .Rosemary {
                    // Rosemary needles emerge in close opposite runs along a
                    // shoot, not as a palmate star at one terminal node.
                    // Staggering the generated whorl backward along its parent
                    // direction fills the woody gaps while preserving the
                    // same botanical needle size and attachment budget.
                    clustered_position -= forward * clustered_traits.length * (.72 + f32(cluster_index - 1) * .58)
                    clustered_position[1] = max(clustered_position[1], 0)
                } else if config.species == .Stone_Pine {
                    // Spread the radial fascicle along its shoot. Keeping all
                    // four blades at one exact point exposes a repeated star
                    // glyph; this short stagger merges neighboring anchors
                    // into the flat, tufted pads of an umbrella crown.
                    clustered_position -= forward * clustered_traits.length * (.16 + f32(cluster_index - 1) * .14)
                    clustered_position[1] = max(clustered_position[1], 0)
                }
                if climbing {
                    clustered_position[0] = clamp(
                        clustered_position[0],
                        -config.support.width * .48,
                        config.support.width * .48,
                    )
                    clustered_position[1] = clamp(
                        clustered_position[1],
                        f32(0),
                        config.support.height * .96,
                    )
                }
                append(
                    &result.plant.attachments,
                    Attachment {
                        kind = .Leaf,
                        position = clustered_position,
                        forward = clustered_forward,
                        up = clustered_up,
                        depth = leaf.depth,
                        variant = clustered_variant,
                        leaf = clustered_traits,
                    },
                )
                update_bounds(&result.plant.bounds, clustered_position, &first)
                update_leaf_bounds(
                    &result.plant.bounds,
                    clustered_position,
                    clustered_forward,
                    clustered_up,
                    clustered_traits,
                    &first,
                )
            }
        }
        if cypress_cone {
            // Nest the woody cone just outside its supporting spray so it is
            // visible without floating beyond the narrow crown silhouette.
            cone_position := position + forward * .010 + up * .006
            append(
                &result.plant.attachments,
                Attachment {
                    kind = .Fruit,
                    stage = attachment_stage(.Fruit, config.seed, index, maturity),
                    position = cone_position,
                    forward = forward,
                    up = up,
                    depth = leaf.depth,
                    variant = variant,
                },
            )
            update_bounds(&result.plant.bounds, cone_position, &first)
        }
    }
    if habit == .Wall_Trained && len(result.plant.segments) > 0 {
        // L-system markers tend to accumulate at shoot terminals. On a wall
        // that leaves the long, visually important routed canes bare even
        // when the overall attachment count is healthy. Establish a modest
        // cane-foliage cadence per square metre, safely below the attachment
        // density ceiling, and distribute it over already-routed young wood. This is
        // intentionally independent of terminal-marker count: many clustered
        // leaves at two tips do not fill a bare three-metre cane.
        cadence_density := config.detail == .Near ? f32(16) : config.detail == .Medium ? f32(8) : f32(4)
        cadence_ceiling := int(math.ceil(config.support.width * config.support.height * cadence_density))
        eligible_count := 0
        minimum_height := config.support.height * .10
        primary_canopy_height := config.support.height * .42
        for segment in result.plant.segments {
            midpoint := (segment.start + segment.end) * .5
            midpoint_y := midpoint[1]
            eligible :=
                (segment.depth >= 1 && midpoint_y >= minimum_height) ||
                midpoint_y >= primary_canopy_height
            for exclusion in config.support.exclusions {
                if midpoint[0] >= exclusion.minimum_x && midpoint[0] <= exclusion.maximum_x &&
                   midpoint[1] >= exclusion.minimum_y && midpoint[1] <= exclusion.maximum_y {
                    eligible = false
                    break
                }
            }
            if eligible do eligible_count += 1
        }
        needed := min(
            min(cadence_ceiling, (eligible_count + 1) / 2),
            attachment_limit - len(result.plant.attachments),
        )
        if needed > 0 {
            accumulator := 0
            added := 0
            for segment, segment_index in result.plant.segments {
                position := (segment.start + segment.end) * .5
                midpoint_y := position[1]
                eligible :=
                    (segment.depth >= 1 && midpoint_y >= minimum_height) ||
                    midpoint_y >= primary_canopy_height
                for exclusion in config.support.exclusions {
                    if position[0] >= exclusion.minimum_x && position[0] <= exclusion.maximum_x &&
                       position[1] >= exclusion.minimum_y && position[1] <= exclusion.maximum_y {
                        eligible = false
                        break
                    }
                }
                if !eligible do continue
                accumulator += needed
                if accumulator < eligible_count do continue
                accumulator -= eligible_count
                direction := linalg.normalize0(segment.end - segment.start)
                if linalg.dot(direction, direction) < .001 do continue
                variant := u8((config.seed + u64(segment_index * 13 + added * 7)) % 4)
                traits := generated_leaf_traits(config.species, variant, maturity, config.detail)
                forward, up := attachment_frame(direction, {0, 0, 1}, profile, true)
                append(
                    &result.plant.attachments,
                    Attachment {
                        kind = .Leaf,
                        position = position,
                        forward = forward,
                        up = up,
                        depth = segment.depth,
                        variant = variant,
                        leaf = traits,
                    },
                )
                update_bounds(&result.plant.bounds, position, &first)
                update_leaf_bounds(&result.plant.bounds, position, forward, up, traits, &first)
                added += 1
                if added == needed do break
            }
        }
    }
    lsystem.destroy_plant(&interpreted.plant)
    return result
}
