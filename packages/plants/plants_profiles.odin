package plants

import "core:math"

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
    values := []f32 {
        support.width,
        support.height,
        support.plane_z,
        support.root_x,
        support.left_corner_x,
        support.left_return_depth,
    }
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
