// Package plant_bark provides small, deterministic procedural bark profiles
// for Adriatic's plant catalog. It describes visual identity rather than
// geometry: renderers may sample it per vertex, per texel, or per instance.
package plant_bark

import plants "../plants"
import "core:math"

Pattern :: enum u8 {
    Smooth,
    Furrowed,
    Flaky,
    Plated,
    Mottled,
    Fibrous,
    Lenticelled,
    Green_Stem,
}

Profile :: struct {
    base_color:      [3]u8,
    pattern:         Pattern,
    scale:           f32,
    contrast:        f32,
    groove_strength: f32,
    patch_strength:  f32,
    roughness:       f32,
}

Sample :: struct {
    color:     [3]u8,
    roughness: f32,
    relief:    f32,
}

relief_depth :: proc(value: Profile) -> f32 {
    switch value.pattern {
    case .Plated:
        return .16
    case .Furrowed:
        return .12
    case .Flaky:
        return .09
    case .Fibrous:
        return .07
    case .Lenticelled:
        return .035
    case .Mottled:
        return .025
    case .Smooth:
        return .018
    case .Green_Stem:
        return .008
    }
    return 0
}

profile :: proc(species: plants.Species) -> Profile {
    // Values intentionally capture the first-read identity of each bark at
    // game distance, rather than attempting photographic micro-detail.
    #partial switch species {
    case .Olive:
        return {{122, 110, 88}, .Furrowed, 1.25, .22, .85, .18, .91}
    case .Italian_Cypress:
        return {{92, 66, 43}, .Fibrous, 2.20, .18, .72, .10, .94}
    case .Grapevine:
        return {{101, 70, 48}, .Flaky, 1.75, .25, .50, .62, .95}
    case .Fig:
        return {{132, 112, 83}, .Smooth, 1.10, .09, .12, .20, .78}
    case .Lemon:
        return {{104, 82, 52}, .Smooth, 1.55, .11, .18, .20, .76}
    case .Pomegranate:
        return {{116, 76, 47}, .Flaky, 1.45, .21, .32, .66, .87}
    case .Almond:
        return {{111, 79, 52}, .Furrowed, 1.55, .18, .62, .20, .90}
    case .Oleander:
        return {{86, 74, 49}, .Smooth, 1.30, .11, .18, .25, .82}
    case .Bougainvillea:
        return {{116, 80, 53}, .Fibrous, 1.75, .20, .58, .24, .91}
    case .Rosemary, .Lavender, .Thyme, .Sage:
        return {{86, 73, 53}, .Fibrous, 2.80, .16, .58, .12, .94}
    case .Stone_Pine:
        return {{110, 75, 48}, .Plated, .82, .27, .50, .82, .96}
    case .Bay_Laurel:
        return {{91, 70, 48}, .Smooth, 1.20, .10, .16, .22, .80}
    case .Carob:
        return {{83, 62, 43}, .Furrowed, 1.10, .22, .78, .16, .94}
    case .Strawberry_Tree:
        return {{146, 78, 54}, .Flaky, 1.18, .26, .28, .82, .80}
    case .Myrtle, .Mastic:
        return {{89, 69, 49}, .Smooth, 1.50, .12, .20, .28, .83}
    case .Wisteria:
        return {{104, 76, 54}, .Fibrous, 1.62, .20, .66, .20, .92}
    case .Climbing_Rose:
        return {{105, 75, 52}, .Lenticelled, 1.65, .17, .25, .50, .87}
    case .Hydrangea_Bush, .Hydrangea_Tree:
        return {{98, 78, 57}, .Flaky, 1.65, .17, .30, .58, .90}
    case .Star_Jasmine:
        return {{91, 72, 51}, .Fibrous, 1.90, .15, .48, .18, .89}
    case .Holm_Oak:
        return {{82, 79, 70}, .Plated, 1.08, .40, .82, .96, .97}
    case .Oriental_Plane:
        return {{139, 125, 96}, .Mottled, .72, .25, .10, .92, .78}
    case .European_Hackberry:
        return {{105, 87, 65}, .Lenticelled, 1.05, .18, .36, .60, .88}
    case .White_Poplar:
        return {{151, 144, 132}, .Lenticelled, 1.30, .20, .20, .74, .82}
    case .Pelargonium,
         .Agapanthus,
         .Prickly_Pear,
         .Golden_Barrel,
         .Agave,
         .Aloe,
         .Aeonium,
         .Echeveria,
         .Jade_Plant,
         .Stonecrop,
         .Blue_Chalk_Sticks,
         .Golden_Torch_Cactus:
        return {{91, 108, 67}, .Green_Stem, 1.30, .08, .12, .16, .72}
    }
    return {{100, 75, 50}, .Smooth, 1.25, .10, .18, .20, .84}
}

hash01 :: proc(seed: u64, x, y: i32) -> f32 {
    value := seed ~ u64(u32(x)) * 0x9e3779b185ebca87 ~ u64(u32(y)) * 0xc2b2ae3d27d4eb4f
    value = (value ~ (value >> 30)) * 0xbf58476d1ce4e5b9
    value = (value ~ (value >> 27)) * 0x94d049bb133111eb
    value = value ~ (value >> 31)
    return f32(value & 0xffff) / 65535
}

sample :: proc(value: Profile, position, normal: [3]f32, seed: u64) -> Sample {
    angle := math.atan2(normal[2], normal[0])
    u := angle / (2 * f32(math.PI)) + .5
    v := position[1]
    scale := max(value.scale, .01)
    column := i32(math.floor(u * 12 * scale))
    row := i32(math.floor(v * 5 * scale))
    cell := hash01(seed, column, row) * 2 - 1
    fine := f32(math.sin(f64(angle * (7 + scale * 2) + v * scale * 3.7)))
    vertical := f32(math.sin(f64(angle * (4 + scale) + v * .32)))
    patch := cell
    relief := fine * .12

    switch value.pattern {
    case .Smooth:
        relief = fine * .08 + cell * .05
    case .Furrowed:
        relief = -math.abs(vertical) * value.groove_strength + fine * .18
    case .Flaky:
        relief = cell * .62 + fine * .12
    case .Plated:
        relief = cell * .54 - math.abs(fine) * .24
    case .Mottled:
        relief = cell * .34 + vertical * .16
    case .Fibrous:
        relief = vertical * .45 + fine * .18
    case .Lenticelled:
        lenticel := hash01(seed + 19, i32(math.floor(u * 22)), i32(math.floor(v * 9)))
        relief = fine * .08 - (lenticel > .86 ? f32(.55) : f32(0))
    case .Green_Stem:
        relief = fine * .05 + cell * .025
    }

    tone := 1 + clamp(relief * value.contrast + patch * value.patch_strength * .12, -.34, .28)
    result: Sample
    for channel in 0 ..< 3 {
        result.color[channel] = u8(clamp(f32(value.base_color[channel]) * tone, 0, 255))
    }
    result.roughness = clamp(value.roughness - relief * .08, .55, 1)
    result.relief = clamp(relief, -1, 1)
    return result
}
