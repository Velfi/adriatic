package plants

import "core:math"

Architecture_Family :: enum u8 {
    Reiterating_Tree,
    Excurrent_Tree,
    Renewing_Shrub,
    Subshrub,
    Tendril_Climber,
    Twining_Climber,
    Scrambling_Climber,
    Rosette,
    Stemmed_Succulent,
    Cushion,
    Cladode_Cactus,
    Barrel_Cactus,
    Columnar_Cactus,
}

Garden_Profile :: struct {
    family:               Architecture_Family,
    mature_height:        f32,
    mature_spread:        f32,
    basal_axis_count:     u8,
    apical_control:       f32,
    branch_angle:         f32,
    phyllotactic_angle:   f32,
    gravitropism:         f32,
    phototropism:         f32,
    continuous_foliage:   bool,
    reproductive_lateral: bool,
}

// garden_profile describes the horticultural archetype represented by each
// catalog entry. It is deliberately not a claim about a single cultivar.
garden_profile :: proc(species: Species) -> Garden_Profile {
    golden_angle := f32(2.399963)
    switch species {
    case .Olive:
        return {.Reiterating_Tree, 5.2, 6.0, 3, .34, .78, golden_angle, .18, .10, true, true}
    case .Italian_Cypress:
        return {.Excurrent_Tree, 10.0, 2.0, 1, .96, .34, golden_angle, .88, .06, true, true}
    case .Grapevine:
        return {.Tendril_Climber, 2.4, 7.0, 1, .58, .62, math.PI, .42, .18, true, true}
    case .Fig:
        return {.Reiterating_Tree, 5.0, 6.4, 3, .38, .82, golden_angle, .16, .12, true, true}
    case .Lemon:
        return {.Reiterating_Tree, 4.0, 4.2, 3, .48, .72, golden_angle, .30, .12, true, true}
    case .Pomegranate:
        return {.Renewing_Shrub, 3.6, 3.2, 6, .25, .62, golden_angle, .46, .10, true, true}
    case .Almond:
        return {.Reiterating_Tree, 5.5, 5.6, 4, .44, .68, golden_angle, .24, .12, true, true}
    case .Oleander:
        return {.Renewing_Shrub, 3.5, 3.0, 7, .34, .52, math.PI, .62, .08, true, true}
    case .Bougainvillea:
        return {.Scrambling_Climber, 5.5, 7.5, 5, .28, .72, golden_angle, .18, .16, true, true}
    case .Rosemary:
        return {.Subshrub, 1.5, 1.6, 10, .32, .48, math.PI, .72, .10, true, true}
    case .Stone_Pine:
        return {.Excurrent_Tree, 12.0, 10.0, 1, .72, .92, golden_angle, .54, .14, false, true}
    case .Bay_Laurel:
        return {.Renewing_Shrub, 4.5, 3.5, 5, .52, .48, golden_angle, .72, .08, true, true}
    case .Carob:
        return {.Reiterating_Tree, 6.5, 8.0, 3, .36, .86, golden_angle, .20, .10, true, true}
    case .Strawberry_Tree:
        return {.Reiterating_Tree, 5.0, 4.8, 4, .42, .68, golden_angle, .36, .10, true, true}
    case .Myrtle:
        return {.Renewing_Shrub, 2.6, 2.2, 7, .34, .50, math.PI, .68, .08, true, true}
    case .Mastic:
        return {.Renewing_Shrub, 2.2, 3.0, 7, .24, .74, golden_angle, .44, .08, true, true}
    case .Lavender:
        return {.Subshrub, .75, .95, 18, .20, .42, golden_angle, .84, .10, true, true}
    case .Thyme:
        return {.Subshrub, .30, .75, 16, .10, .92, math.PI, .18, .08, true, true}
    case .Sage:
        return {.Subshrub, .85, 1.0, 9, .24, .56, math.PI, .72, .10, true, true}
    case .Prickly_Pear:
        return {.Cladode_Cactus, 1.2, 1.8, 5, .22, .76, golden_angle, .38, .06, false, true}
    case .Pelargonium:
        return {.Subshrub, .55, .75, 10, .18, .58, golden_angle, .64, .10, true, true}
    case .Wisteria:
        return {.Twining_Climber, 6.0, 8.0, 3, .62, .52, golden_angle, .28, .14, true, true}
    case .Climbing_Rose:
        return {.Scrambling_Climber, 4.5, 5.5, 5, .34, .72, golden_angle, .24, .12, true, true}
    case .Hydrangea_Bush:
        return {.Renewing_Shrub, 1.7, 2.0, 9, .18, .62, math.PI, .58, .08, true, true}
    case .Hydrangea_Tree:
        return {.Reiterating_Tree, 2.8, 2.2, 4, .52, .58, math.PI, .62, .08, true, true}
    case .Agapanthus:
        return {.Rosette, 1.1, .9, 1, .92, .20, golden_angle, .96, .08, true, true}
    case .Star_Jasmine:
        return {.Twining_Climber, 4.0, 5.5, 4, .48, .46, math.PI, .34, .12, true, true}
    case .Holm_Oak:
        return {.Reiterating_Tree, 8.0, 9.0, 4, .38, .88, golden_angle, .18, .12, true, true}
    case .Oriental_Plane:
        return {.Reiterating_Tree, 13.0, 11.0, 4, .52, .78, golden_angle, .24, .14, true, true}
    case .European_Hackberry:
        return {.Reiterating_Tree, 10.0, 8.0, 4, .58, .64, golden_angle, .38, .12, true, true}
    case .White_Poplar:
        return {.Excurrent_Tree, 13.0, 6.0, 1, .86, .48, golden_angle, .74, .12, true, true}
    case .Golden_Barrel:
        return {.Barrel_Cactus, .8, .8, 1, 1, 0, golden_angle, 1, 0, false, true}
    case .Agave:
        return {.Rosette, 1.5, 2.4, 1, 1, .20, golden_angle, 1, 0, true, true}
    case .Aloe:
        return {.Rosette, .9, 1.1, 3, .82, .24, golden_angle, .96, .04, true, true}
    case .Aeonium:
        return {.Stemmed_Succulent, 1.2, 1.0, 5, .54, .72, golden_angle, .68, .06, true, true}
    case .Echeveria:
        return {.Rosette, .30, .45, 1, 1, .12, golden_angle, 1, 0, true, true}
    case .Jade_Plant:
        return {.Stemmed_Succulent, 1.4, 1.2, 6, .42, .54, math.PI / 2, .72, .06, true, true}
    case .Stonecrop:
        return {.Cushion, .22, .9, 18, .08, .94, golden_angle, .12, .04, true, true}
    case .Blue_Chalk_Sticks:
        return {.Cushion, .45, 1.0, 20, .16, .76, golden_angle, .32, .04, true, true}
    case .Golden_Torch_Cactus:
        return {.Columnar_Cactus, 1.8, .55, 4, .94, .12, golden_angle, 1, 0, false, true}
    }
    return {}
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
    values := []f32 {
        support.width,
        support.height,
        support.plane_z,
        support.root_x,
        support.left_corner_x,
        support.left_return_depth,
        support.contact_radius,
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
    for axis in support.axes {
        axis_values := []f32 {
            axis.start[0],
            axis.start[1],
            axis.start[2],
            axis.end[0],
            axis.end[1],
            axis.end[2],
            axis.radius,
        }
        for value in axis_values {
            bits := transmute(u32)value
            hash = (hash ~ u64(bits)) * 0x100000001b3
        }
    }
    return hash
}

Profile :: struct {
    base_iterations: int,
    width_scale:     f32,
    height_scale:    f32,
}

profile_for :: proc(species: Species) -> Profile {
    switch species {
    case .Italian_Cypress: return {3, 1.65, 2.10}
    case .Olive: return {4, 1.35, 1.00}
    case .Fig: return {3, 1.22, .76}
    case .Lemon: return {3, 1.00, 1.00}
    case .Pomegranate: return {3, 1.00, .94}
    case .Almond: return {3, 1.00, 1.00}
    case .Oleander: return {3, .96, .90}
    case .Rosemary: return {3, .96, .92}
    case .Grapevine: return {3, 1.35, .84}
    case .Bougainvillea: return {3, 1.18, 1.04}
    case .Stone_Pine: return {3, 2.00, 1.12}
    case .Bay_Laurel: return {3, 1.02, 1.10}
    case .Carob: return {3, 1.36, .96}
    case .Strawberry_Tree: return {3, 1.04, 1.05}
    case .Myrtle: return {3, .78, 1.15}
    case .Mastic: return {3, .75, 1.00}
    case .Lavender: return {3, .88, .98}
    case .Thyme: return {3, 1.22, .52}
    case .Sage: return {3, .95, 1.00}
    case .Prickly_Pear: return {2, 1.18, .95}
    case .Pelargonium: return {3, 1.06, .72}
    case .Wisteria: return {2, 1.32, 1.04}
    case .Climbing_Rose: return {2, 1.18, 1.00}
    case .Hydrangea_Bush: return {3, 1.18, .76}
    case .Hydrangea_Tree: return {3, 1.05, 1.28}
    case .Agapanthus: return {2, .82, 1.32}
    case .Star_Jasmine: return {2, 1.22, .94}
    case .Holm_Oak: return {3, 1.48, .86}
    case .Oriental_Plane: return {3, 1.42, 1.16}
    case .European_Hackberry: return {3, 1.24, 1.10}
    case .White_Poplar: return {3, .90, 1.48}
    case .Golden_Barrel, .Agave, .Aloe, .Aeonium, .Echeveria,
         .Jade_Plant, .Stonecrop, .Blue_Chalk_Sticks, .Golden_Torch_Cactus:
        return {1, 1, 1}
    }
    return {}
}
