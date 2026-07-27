package main

import markov "../packages/markov"
import terrain "../packages/terrain"
import "core:math"
import "core:math/linalg"

Settlement_Scale :: enum {
    City,
    Town,
    Village,
}

Settlement_Profile :: struct {
    scale:                Settlement_Scale,
    world_cell:           f32,
    neighborhood_steps:   int,
    density_growth_steps: int,
    medium_steps:         int,
    high_steps:           int,
    core_steps:           int,
    landmark_steps:       int,
    foliage_steps:        int,
    density_floor:        f32,
    density_ceiling:      f32,
    max_slope:            f32,
}

SETTLEMENT_CITY :: Settlement_Profile {
    scale                = .City,
    world_cell           = 20,
    neighborhood_steps   = 138,
    density_growth_steps = 176,
    medium_steps         = 58,
    high_steps           = 12,
    core_steps           = 3,
    landmark_steps       = 4,
    foliage_steps        = 22,
    density_floor        = .30,
    density_ceiling      = .82,
    max_slope            = .34,
}

SETTLEMENT_TOWN :: Settlement_Profile {
    scale                = .Town,
    world_cell           = 14,
    neighborhood_steps   = 84,
    density_growth_steps = 108,
    medium_steps         = 26,
    high_steps           = 3,
    core_steps           = 0,
    landmark_steps       = 3,
    foliage_steps        = 18,
    density_floor        = .18,
    density_ceiling      = .62,
    max_slope            = .42,
}

SETTLEMENT_VILLAGE :: Settlement_Profile {
    scale                = .Village,
    world_cell           = 9,
    neighborhood_steps   = 45,
    density_growth_steps = 58,
    medium_steps         = 12,
    high_steps           = 0,
    core_steps           = 0,
    landmark_steps       = 1,
    foliage_steps        = 14,
    density_floor        = .10,
    density_ceiling      = .48,
    max_slope            = .52,
}

Settlement_Density_Cell :: enum u8 {
    Empty,
    Low,
    Medium,
    High,
    Core,
}

settlement_density_model :: proc(profile: Settlement_Profile) -> markov.Proc_Node {
    empty := int(Settlement_Density_Cell.Empty)
    low := int(Settlement_Density_Cell.Low)
    medium := int(Settlement_Density_Cell.Medium)
    high := int(Settlement_Density_Cell.High)
    core := int(Settlement_Density_Cell.Core)
    children := make([dynamic]markov.Proc_Node, 0, 4, context.temp_allocator)
    append(
        &children,
        markov.node(
            markov.Proc_Tag.one,
            []markov.Proc_Attr {
                markov.kattr(
                    .in_,
                    markov.match_layer(
                        markov.match_row(markov.one_of(markov.sym(low)), markov.one_of(markov.sym(empty))),
                    ),
                ),
                markov.kattr(.out, markov.write_layer(markov.write_row(markov.keep(), markov.sym(low)))),
                markov.kattr(.steps, profile.density_growth_steps),
            },
        ),
    )
    promotions := [3]struct {
        from, to, steps: int,
    }{{low, medium, profile.medium_steps}, {medium, high, profile.high_steps}, {high, core, profile.core_steps}}
    for promotion in promotions {
        if promotion.steps <= 0 do continue
        append(
            &children,
            markov.node(
                markov.Proc_Tag.one,
                []markov.Proc_Attr {
                    markov.kattr(
                        .in_,
                        markov.match_layer(markov.match_row(markov.one_of(markov.sym(promotion.from)))),
                    ),
                    markov.kattr(.out, markov.write_layer(markov.write_row(markov.sym(promotion.to)))),
                    markov.kattr(.steps, promotion.steps),
                },
            ),
        )
    }
    return markov.node(
        markov.Proc_Tag.sequence,
        []markov.Proc_Attr{markov.kattr(.values, markov.values_count(5)), markov.kattr(.origin, true)},
        children[:],
    )
}

settlement_density_value :: proc(cell: Settlement_Density_Cell, profile: Settlement_Profile) -> f32 {
    normalized: f32
    switch cell {
    case .Empty:
        return 0
    case .Low:
        normalized = .18
    case .Medium:
        normalized = .46
    case .High:
        normalized = .76
    case .Core:
        normalized = 1
    }
    return profile.density_floor + (profile.density_ceiling - profile.density_floor) * normalized
}

settlement_density_smoothed :: proc(frame: ^markov.Frame, grid_size, gx, gz: int, profile: Settlement_Profile) -> f32 {
    if frame == nil do return 0
    weighted_sum, weight_sum := f32(0), f32(0)
    for dz in -1 ..= 1 {
        for dx in -1 ..= 1 {
            x, z := gx + dx, gz + dz
            if x < 0 || z < 0 || x >= grid_size || z >= grid_size do continue
            weight := dx == 0 && dz == 0 ? f32(4) : (dx == 0 || dz == 0 ? f32(2) : f32(1))
            cell := Settlement_Density_Cell(frame.state[z * grid_size + x])
            weighted_sum += settlement_density_value(cell, profile) * weight
            weight_sum += weight
        }
    }
    if weight_sum <= 0 do return 0
    return weighted_sum / weight_sum
}

settlement_terrain_slope :: proc(project: ^terrain.Project, x, z: f32) -> f32 {
    SAMPLE :: f32(8)
    dx := terrain.sample_height(project, 0, x + SAMPLE, z) - terrain.sample_height(project, 0, x - SAMPLE, z)
    dz := terrain.sample_height(project, 0, x, z + SAMPLE) - terrain.sample_height(project, 0, x, z - SAMPLE)
    return linalg.length([2]f32{dx, dz}) / (SAMPLE * 2)
}

settlement_site_suitability :: proc(project: ^terrain.Project, x, z: f32, profile: Settlement_Profile) -> f32 {
    height := terrain.sample_height(project, 0, x, z)
    if height <= project.sea_level + .6 do return 0
    slope := settlement_terrain_slope(project, x, z)
    return clamp(1 - slope / max(profile.max_slope, f32(.01)), 0, 1)
}

settlement_fit_landscape_point :: proc(project: ^terrain.Project, x, z: f32, search_radius: f32) -> (f32, f32) {
    best_x, best_z := x, z
    best_score := f32(-1e9)
    origin_height := terrain.sample_height(project, 0, x, z)
    for iz in -2 ..= 2 {
        for ix in -2 ..= 2 {
            candidate_x := x + f32(ix) * search_radius * .5
            candidate_z := z + f32(iz) * search_radius * .5
            height := terrain.sample_height(project, 0, candidate_x, candidate_z)
            if height <= project.sea_level + .6 do continue
            slope := settlement_terrain_slope(project, candidate_x, candidate_z)
            distance := f32(ix * ix + iz * iz)
            elevation_change := math.abs(height - origin_height)
            score := 1 - slope * 3.2 - distance * .035 - elevation_change * .012
            if score > best_score {
                best_score = score
                best_x, best_z = candidate_x, candidate_z
            }
        }
    }
    return best_x, best_z
}
