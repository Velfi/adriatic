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
}

SPECIES_COUNT :: int(Species.Pelargonium) + 1

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
    }
    return "UNKNOWN"
}

default_habit :: proc(species: Species) -> Growth_Habit {
    switch species {
    case .Bougainvillea:
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
         .Pelargonium:
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
         .Pelargonium:
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
    case .Rosemary, .Lavender, .Thyme:
        // Dense opposite needles overlap into continuous aromatic sprays.
        // Five near-detail directions keep a mature shrub from reading as a
        // bare woody fan while medium detail retains a triangular whorl.
        if detail == .Near do return 5
        if detail == .Medium do return 3
    case .Fig:
        return detail == .Near && maturity > .72 ? 2 : 1
    case .Stone_Pine:
        return detail == .Near ? 4 : 2
    case .Myrtle, .Mastic:
        return detail == .Near ? 3 : 2
    case .Grapevine,
         .Pomegranate,
         .Almond,
         .Oleander,
         .Bougainvillea,
         .Bay_Laurel,
         .Carob,
         .Strawberry_Tree,
         .Sage,
         .Prickly_Pear,
         .Pelargonium,
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

    desired := 1 + clamp((maturity - .18) / .52, f32(0), f32(1)) * 5
    whole := int(math.floor(desired))
    fraction := desired - f32(whole)
    hash := (seed * 0x9e3779b97f4a7c15 + u64(index + 1) * 0xbf58476d1ce4e5b9) ~ (u64(index + 17) * 0x94d049bb133111eb)
    if f32(hash % 10_000) < fraction * 10_000 do whole += 1
    return clamp(whole, 1, 6)
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
            "F[L]F[L]",
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
            .98,
            .82,
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
            1.00,
            .90,
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
            1.04,
            .68,
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
    case .Almond, .Oleander, .Lavender, .Thyme, .Sage:
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
    case .Italian_Cypress, .Rosemary, .Stone_Pine:
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
    return attachment_kind(species, index, maturity)
}

leaf_traits :: proc(species: Species, variant: u8, maturity: f32) -> Leaf_Traits {
    traits: Leaf_Traits
    switch species {
    case .Olive:
        traits = {.Lanceolate, .12, .032, 0, .008, .003}
    case .Italian_Cypress:
        // Represent overlapping scale-leaf sprays rather than individual
        // microscopic scales; the latter disappear at ordinary game-camera
        // distances and expose the procedural scaffold.
        // Cypress sprays are short, overlapping fans. A broader footprint
        // closes gaps around each shoot while the shorter axis prevents the
        // crown edge from reading as a ring of individual needles.
        traits = {.Cypress_Spray, .070, .034, 0, .012, .005}
    case .Grapevine:
        traits = {.Grapevine, .18, .16, .05, .016, .008}
    case .Fig:
        traits = {.Fig, .24, .22, 0, .018, .012}
    case .Lemon:
        traits = {.Elliptic, .16, .075, .04, .012, .006}
    case .Pomegranate:
        traits = {.Lanceolate, .115, .040, 0, .008, .004}
    case .Almond:
        traits = {.Lanceolate, .15, .048, .08, .010, .004}
    case .Oleander:
        traits = {.Lanceolate, .18, .035, 0, .012, .004}
    case .Bougainvillea:
        traits = {.Ovate, .13, .090, 0, .014, .006}
    case .Rosemary:
        traits = {.Lanceolate, .045, .008, 0, .006, .001}
    case .Stone_Pine:
        traits = {.Lanceolate, .18, .009, 0, .018, .001}
    case .Bay_Laurel:
        traits = {.Lanceolate, .16, .052, .04, .014, .006}
    case .Carob:
        traits = {.Elliptic, .105, .066, 0, .008, .006}
    case .Strawberry_Tree:
        traits = {.Elliptic, .13, .055, .11, .012, .005}
    case .Myrtle:
        traits = {.Lanceolate, .075, .025, 0, .008, .003}
    case .Mastic:
        traits = {.Elliptic, .072, .031, 0, .007, .003}
    case .Lavender:
        traits = {.Lanceolate, .055, .010, 0, .008, .002}
    case .Thyme:
        traits = {.Ovate, .020, .009, 0, .003, .001}
    case .Sage:
        traits = {.Ovate, .105, .055, .12, .018, .012}
    case .Prickly_Pear:
        traits = {.Ovate, .48, .25, 0, .018, .055}
    case .Pelargonium:
        // Broad, nearly round and shallowly scalloped: this silhouette is the
        // strongest distinction between pelargonium and a generic shrub.
        traits = {.Lobed, .145, .132, .045, .018, .010}
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
) -> lsystem.Vec3 {
    result := point
    height_fraction := clamp(point[1] / max(source_height, f32(.001)), f32(0), f32(1))
    rise := height_fraction * height_fraction * (3 - 2 * height_fraction)
    root_x := clamp(support.root_x, -support.width * .46, support.width * .46)
    opposite_x := root_x <= 0 ? support.width * .42 : -support.width * .42
    // Preserve both lateral axes of the free L-system when flattening it onto
    // a support. Using x alone projected branches that differed mainly in z
    // onto the same track and made a mature climber read as one serpentine
    // stem. The oblique basis keeps those branches as a broad wall fan.
    lateral_source := point[0] * .74 + point[2] * .67
    lateral_fraction := clamp(lateral_source / max(source_half_width, f32(.001)), f32(-1), f32(1))
    lateral_spread := lateral_fraction * support.width * .23 * (.30 + height_fraction * .70)
    // A climber retains its generated lateral branching, but its main mass
    // progressively traverses the support instead of being clamped into a
    // corner near the root.
    result[0] = root_x + (opposite_x - root_x) * rise * .92 + lateral_spread
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
            result[0] = root_x + (opposite_x - root_x) * training_progress * .96 + lateral_spread
            tier := clamp(int(math.round(f64((raw_y - first_wire) / max(tier_spacing, f32(.001))))), 0, 3)
            result[1] = first_wire + f32(tier) * tier_spacing
        }
        result[0] = clamp(result[0], -support.width * .48, support.width * .48)
    }
    for exclusion in support.exclusions {
        exclusion_center := (exclusion.minimum_x + exclusion.maximum_x) * .5
        lintel_start := clamp(exclusion.maximum_y / support.height, f32(0), f32(.94))
        if height_fraction > lintel_start {
            // Once a leader reaches the top of an opening, spend its remaining
            // generated rise traversing the lintel. The prior router held the
            // branch beside the door through a large clearance and then
            // jumped to the far upright, leaving no attachment sites across
            // the span between them.
            lintel_progress := clamp(
                (height_fraction - lintel_start) / max(1 - lintel_start, f32(.001)),
                f32(0),
                f32(1),
            )
            lintel_progress = lintel_progress * lintel_progress * (3 - 2 * lintel_progress)
            result[0] = root_x + (opposite_x - root_x) * lintel_progress * .96 + lateral_spread
            lintel_top := support.height * .96
            result[1] = exclusion.maximum_y + .02 + (lintel_top - exclusion.maximum_y - .02) * lintel_progress
            result[0] = clamp(result[0], -support.width * .48, support.width * .48)
            continue
        }
        // Hold the routed side for enough vertical distance that a tessellated
        // segment can turn above the opening without its chord cutting back
        // through the exclusion.
        clearance := max(f32(.18), support.height * .12)
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
    stem_count := 3 + int(math.floor(eased * 7.99))
    node_count := 2 + int(math.floor(eased * 2.99))
    random := seed ~ 0x70656c6172676f6e
    phase := olive_random_signed(&random) * math.PI

    for stem_index in 0 ..< stem_count {
        azimuth := phase + f32(stem_index) * 2.399963 + olive_random_signed(&random) * .16
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
        position := radial * (.018 + f32(stem_index % 3) * .008) * size
        stem_lean := .42 + f32(stem_index % 4) * .040
        direction := linalg.normalize0(
            radial * stem_lean + tangent * olive_random_signed(&random) * .08 + lsystem.Vec3{0, .86, 0},
        )
        // Pelargonium carries fleshy but comparatively slender green-brown
        // stems; tree-scale radii make a patio plant read as a bonsai.
        radius := (.012 + eased * .006) * (1 + olive_random_signed(&random) * .08)

        for node_index in 0 ..< node_count {
            node_progress := f32(node_index) / f32(max(node_count - 1, 1))
            length :=
                (.105 + eased * .095) * (1 - node_progress * .10) * (1 + olive_random_signed(&random) * .08) * size
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
            leaf_azimuth := azimuth + f32(node_index) * 2.399963
            append(
                &result.plant.leaves,
                lsystem.Leaf {
                    position = next,
                    forward  = linalg.normalize0(
                        lsystem.Vec3{math.cos(leaf_azimuth), .52, math.sin(leaf_azimuth)}, // Lift the blade toward the viewer instead of laying// every broad leaf into a nearly edge-on horizontal// shelf at ordinary patio camera height.
                    ),
                    up       = {0, 1, 0},
                    depth    = 0,
                },
            )
            position = next
            radius *= .78
        }

        if growth >= .30 && stem_index % 2 == 0 {
            flowering := clamp((growth - .30) / .70, f32(0), f32(1))
            peduncle_direction := linalg.normalize0(direction * .34 + radial * .08 + lsystem.Vec3{0, .94, 0})
            flower_tip := position + peduncle_direction * (.12 + flowering * .13) * size
            append(
                &result.plant.segments,
                lsystem.Segment {
                    start = position,
                    end = flower_tip,
                    radius_start = max(radius * .52, f32(.006)),
                    radius_end = .004,
                    depth = 2,
                },
            )
            bloom_count := 3 + int(math.floor(flowering * 3.99))
            for bloom_index in 0 ..< bloom_count {
                bloom_angle := azimuth + f32(bloom_index) * math.PI * 2 / f32(bloom_count)
                bloom_radial := lsystem.Vec3{math.cos(bloom_angle), 0, math.sin(bloom_angle)}
                bloom_height := bloom_index % 2 == 0 ? f32(.018) : f32(-.006)
                append(
                    &result.plant.leaves,
                    lsystem.Leaf {
                        position = flower_tip +
                        bloom_radial * (.018 + flowering * .018) * size +
                        lsystem.Vec3{0, bloom_height * size, 0},
                        forward = bloom_radial,
                        up = {0, 1, 0},
                        depth = -4,
                    },
                )
            }
        }
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
    roll := olive_random_signed(random) * .55
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

stone_pine_clothe_scaffold :: proc(plant: ^lsystem.Plant) {
    if plant == nil || len(plant.segments) == 0 do return
    // Stone-pine needles gather in persistent bundles along the outer half of
    // each umbrella scaffold, not only at grammar-terminal buds. Seed choices
    // that selected shorter X productions could otherwise leave a mature
    // crown as a bare whorl with a few terminal sprays.
    stations := [4]f32{.26, .47, .68, .87}
    for segment in plant.segments {
        if segment.depth <= 0 do continue
        direction := linalg.normalize0(segment.end - segment.start)
        forward, up := olive_leaf_frame(direction)
        for station in stations {
            append(
                &plant.leaves,
                lsystem.Leaf {
                    position = linalg.lerp(segment.start, segment.end, station),
                    forward = forward,
                    up = up,
                    depth = segment.depth,
                },
            )
        }
    }
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
            olive_emit_spray(plant, foliage_random, position - direction * segment_length * .58, direction, depth)
            olive_emit_spray(plant, foliage_random, position - direction * segment_length * .27, direction, depth)
            olive_emit_spray(plant, foliage_random, position, direction, depth)
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

    leader_count := maturity >= .78 ? 5 : maturity >= .40 ? 4 : 3
    generations := clamp(iterations - 1, 0, 3)
    drift_angle := f32(lsystem.random_next(&habit_random) % 10_000) / 10_000 * math.PI * 2
    prevailing_drift := lsystem.Vec3{math.cos(drift_angle) * .10, 0, math.sin(drift_angle) * .10}
    for leader_index in 0 ..< leader_count {
        // Stagger leader origins over the upper trunk instead of creating a
        // single swollen umbrella hub.
        origin_index := clamp(trunk_segments - 1 + leader_index % 2, 1, trunk_segments)
        origin := trunk_points[origin_index]
        azimuth := f32(leader_index) * math.PI * 2 / f32(leader_count) + olive_random_signed(&random) * .34
        radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
        spread := .55 + maturity * .17
        lift := .72 - maturity * .20
        direction := linalg.normalize0(
            radial * (spread + olive_random_signed(&random) * .10) +
            prevailing_drift +
            lsystem.Vec3{0, lift + olive_random_signed(&random) * .12, 0},
        )
        olive_grow_branch(
            &result.plant,
            &random,
            &foliage_random,
            origin,
            direction,
            .39 * scale * (1 + olive_random_signed(&random) * .20),
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
        tier_fullness := 1 + olive_random_signed(&random) * .08
        pair_lengths: [4]f32
        for &pair_length in pair_lengths {
            pair_length = 1 + olive_random_signed(&random) * .045
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
            // Distribute the four opposite pairs over the upper part of the
            // preceding leader segment. Each pair keeps one exact origin and
            // remains balanced, while the crown loses its stacked horizontal
            // shelves. Stratification guarantees useful separation; a small
            // jitter prevents a second perfectly regular four-step pattern.
            pair_retraction = .025 + f32(pair_index) * .040 + olive_random_signed(&random) * .007
        }
        for branch_index in 0 ..< 8 {
            azimuth := tier_phase + f32(branch_index) * math.PI * 2 / 8 + pair_angles[branch_index % 4]
            radial := lsystem.Vec3{math.cos(azimuth), 0, math.sin(azimuth)}
            local_spread := spread_angle + pair_spreads[branch_index % 4]
            direction := linalg.normalize0(
                radial * math.sin(local_spread) + lsystem.Vec3{0, math.cos(local_spread), 0},
            )
            local_branch_origin := branch_origin - (branch_origin - leader_start) * pair_retractions[branch_index % 4]
            // Half-rate decay produces the cypress's nearly columnar crown;
            // using the leader segment length directly pinched every seed
            // above a bulbous lower third. The explicit apex envelope still
            // closes the final tiers into a narrow tip.
            branch_envelope_length := math.sqrt(max(segment_length * step, f32(0)))
            basal_progress := clamp(progress / .28, f32(0), f32(1))
            basal_smooth := basal_progress * basal_progress * (3 - 2 * basal_progress)
            basal_envelope := .86 + basal_smooth * .14
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
            branch_tip := branch_mid + direction * branch_length * .78
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
                lsystem.Leaf{position = branch_tip, forward = direction, up = up, depth = 1},
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
    if habit == .Free_Standing && (config.species == .Bougainvillea || config.species == .Grapevine) {
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
        interpreted = almond_skeleton(config.seed, maturity, iterations)
    } else if config.species == .Italian_Cypress {
        // Grow toward fifteen mature whorls continuously after establishment.
        // Ceil exposes one emerging tier at a time, while the skeleton's
        // geometric-series normalization interpolates its height within that
        // interval instead of jumping five complete tiers per grammar step.
        reference_tier_count := clamp((maturity - .10) / .90, f32(0), f32(1)) * 15
        tier_count := int(math.ceil(reference_tier_count))
        if config.detail == .Medium && tier_count > 5 do tier_count -= 1
        // Far spends its fixed budget on eleven silhouette-critical whorls.
        // Its redundant secondary leader anchors are omitted below, leaving
        // this denser topology beneath both hard geometry ceilings.
        if config.detail == .Far do tier_count = min(tier_count, 11)
        interpreted = cypress_skeleton(config.seed, maturity, tier_count, reference_tier_count)
    } else if config.species == .Pelargonium {
        interpreted = pelargonium_skeleton(config.seed, maturity)
    } else {
        alternatives := [2]lsystem.Alternative {
            {text = profile.production_a, weight = profile.weight_a},
            {text = profile.production_b, weight = profile.weight_b},
        }
        rules := [1]lsystem.Rule{{symbol = 'F', alternatives = alternatives[:]}}
        axiom := profile.axiom
        cypress_alternatives: [2]lsystem.Alternative
        cypress_rules: [1]lsystem.Rule
        grammar_rules := rules[:]
        if config.species == .Stone_Pine {
            // Preserve the clear trunk and rewrite only crown markers. This
            // keeps branches high and lets successive tiers overlap into the
            // stone pine's characteristic flattened umbrella.
            axiom = "FFFFXX"
            cypress_alternatives = {
                {text = "F[+^F[L]F[L]][-^F[L]F[L]][/^F[L]F[L]][\\^F[L]F[L]]X", weight = 3},
                {text = "F[+^F[L]F[L]][-^F[L]F[L]][/^F[L]][\\^F[L]]X", weight = 2},
            }
            cypress_rules = {{symbol = 'X', alternatives = cypress_alternatives[:]}}
            grammar_rules = cypress_rules[:]
        }
        word := lsystem.expand(
            {axiom = axiom, rules = grammar_rules},
            {iterations = iterations, seed = config.seed, max_symbols = segment_limit * 8},
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
    if iterations > 0 {
        sprout_newest_generation(&interpreted.plant, generation_progress)
    }
    if config.species == .Rosemary do rosemary_clothe_scaffold(&interpreted.plant)
    if config.species == .Stone_Pine do stone_pine_clothe_scaffold(&interpreted.plant)
    if len(interpreted.plant.segments) > segment_limit {
        lsystem.destroy_plant(&interpreted.plant)
        result.error = .Segment_Limit
        return result
    }
    if config.species == .Italian_Cypress {
        // Cypress scale leaves sheath both leaders and lateral sprays rather
        // than occurring only at terminal buds. The skeleton already emits
        // end anchors, so place the additional density between nodes instead
        // of stacking duplicate cards into blunt pom-poms.
        for segment in interpreted.plant.segments {
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
    for leaf, index in interpreted.plant.leaves {
        kind := generated_attachment_kind(config.species, config.seed, index, maturity, config.detail, leaf.depth)
        leaf_cluster_size := cluster_size
        if config.species == .Italian_Cypress {
            leaf_cluster_size = cypress_generated_cluster_size(config.detail, maturity, config.seed, index, leaf.depth)
        }
        if config.species == .Italian_Cypress && kind == .Fruit {
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
    routed_segment_capacity := climbing ? len(interpreted.plant.segments) * 6 : len(interpreted.plant.segments)
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
            route_samples := 6
            previous := route_point(segment.start, config.support, climbing_height, climbing_half_width, habit)
            for sample in 1 ..= route_samples {
                t := f32(sample) / f32(route_samples)
                source_point := segment.start + (segment.end - segment.start) * t
                current := route_point(source_point, config.support, climbing_height, climbing_half_width, habit)
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
        if climbing do position = route_point(position, config.support, climbing_height, climbing_half_width, habit)
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
    lsystem.destroy_plant(&interpreted.plant)
    return result
}
