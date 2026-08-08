package main

import plants "../packages/plants"
import terrain "../packages/terrain"
import "core:math"
import "core:strings"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

Foliage_Transition_Example :: enum u8 {
    Wheat_Field,
    Pine_Forest,
    Oak_Forest,
    Olive_Orchard,
    Residential_Hedges,
}

foliage_transition_example := Foliage_Transition_Example.Wheat_Field
foliage_transition_forest_sample_limit := 420
foliage_transition_forest_half_width := f32(24)
foliage_transition_forest_start := f32(12)
foliage_transition_forest_depth := f32(348)

foliage_transition_example_name :: proc(example: Foliage_Transition_Example) -> cstring {
    switch example {
    case .Wheat_Field:
        return "WHEAT FIELD"
    case .Pine_Forest:
        return "PINE FOREST"
    case .Oak_Forest:
        return "OAK FOREST"
    case .Olive_Orchard:
        return "OLIVE ORCHARD"
    case .Residential_Hedges:
        return "RESIDENTIAL HEDGES"
    }
    return "FOLIAGE"
}

foliage_transition_target :: proc(target: string) -> (Foliage_Transition_Example, bool) {
    foliage_transition_forest_sample_limit = 420
    foliage_transition_forest_half_width = 24
    foliage_transition_forest_start = 12
    foliage_transition_forest_depth = 348
    if strings.equal_fold(target, "pine-empty-smoke") {
        foliage_transition_forest_sample_limit = 0
        foliage_transition_forest_half_width = 8
        foliage_transition_forest_depth = 180
        return .Pine_Forest, true
    }
    if strings.equal_fold(target, "pine-middle-smoke") {
        foliage_transition_forest_sample_limit = 12
        foliage_transition_forest_half_width = 8
        foliage_transition_forest_depth = 180
        return .Pine_Forest, true
    }
    if strings.equal_fold(target, "pine-middle-only-smoke") {
        foliage_transition_forest_sample_limit = 12
        foliage_transition_forest_half_width = 8
        foliage_transition_forest_start = 110
        foliage_transition_forest_depth = 100
        return .Pine_Forest, true
    }
    if strings.equal_fold(target, "pine-middle-only-bounded") {
        foliage_transition_forest_sample_limit = 96
        foliage_transition_forest_half_width = 18
        foliage_transition_forest_start = 110
        foliage_transition_forest_depth = 220
        return .Pine_Forest, true
    }
    if strings.equal_fold(target, "oak-middle-only-bounded") {
        foliage_transition_forest_sample_limit = 96
        foliage_transition_forest_half_width = 18
        foliage_transition_forest_start = 110
        foliage_transition_forest_depth = 220
        return .Oak_Forest, true
    }
    if strings.equal_fold(target, "oak-middle-smoke") {
        foliage_transition_forest_sample_limit = 12
        foliage_transition_forest_half_width = 8
        foliage_transition_forest_depth = 180
        return .Oak_Forest, true
    }
    if strings.equal_fold(target, "pine-benchmark") {
        foliage_transition_forest_sample_limit = 36
        foliage_transition_forest_half_width = 18
        return .Pine_Forest, true
    }
    if strings.equal_fold(target, "oak-benchmark") {
        foliage_transition_forest_sample_limit = 36
        foliage_transition_forest_half_width = 18
        return .Oak_Forest, true
    }
    if strings.equal_fold(target, "pine-middle-bounded") {
        foliage_transition_forest_sample_limit = 96
        foliage_transition_forest_half_width = 18
        foliage_transition_forest_depth = 220
        return .Pine_Forest, true
    }
    if strings.equal_fold(target, "oak-middle-bounded") {
        foliage_transition_forest_sample_limit = 96
        foliage_transition_forest_half_width = 18
        foliage_transition_forest_depth = 220
        return .Oak_Forest, true
    }
    if target == "" || strings.equal_fold(target, "wheat") do return .Wheat_Field, true
    if strings.equal_fold(target, "pine") do return .Pine_Forest, true
    if strings.equal_fold(target, "oak") do return .Oak_Forest, true
    if strings.equal_fold(target, "olive") || strings.equal_fold(target, "orchard") do return .Olive_Orchard, true
    if strings.equal_fold(target, "hedges") || strings.equal_fold(target, "residential") do return .Residential_Hedges, true
    return {}, false
}

foliage_transition_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    example, ok := foliage_transition_target(target)
    if !ok do return false
    foliage_transition_example = example
    if !lab_flat_terrain_load(editor, 0, 0, {104, 126, 86, 255}) {
        return false
    }
    camera := third_person.default_camera()
    camera.yaw_radians = math.PI
    camera.pitch_radians = .08
    camera.distance = 138
    lab_scene_configure_camera(editor, {0, 3, 176}, camera)
    return true
}

foliage_transition_hash :: #force_inline proc(value: u32) -> u32 {
    return world_foliage_tree_hash(value ~ u32(0x5d588b65))
}

foliage_transition_distance :: #force_inline proc(editor: ^Editor, x, z: f32) -> f32 {
    dx, dz := x - editor.camera_pose.position.x, z - editor.camera_pose.position.z
    return f32(math.sqrt(f64(dx * dx + dz * dz)))
}

foliage_transition_species :: proc(example: Foliage_Transition_Example) -> plants.Species {
    switch example {
    case .Pine_Forest:
        return .Stone_Pine
    case .Oak_Forest:
        return .Holm_Oak
    case .Olive_Orchard:
        return .Olive
    case .Residential_Hedges:
        return .Myrtle
    case .Wheat_Field:
        return .Rosemary
    }
    return .Rosemary
}

foliage_transition_site :: proc() -> plants.Site_Context {
    return {valid = true, aridity = .42, exposure = .36, slope = 0, elevation_meters = 0, coast_distance_m = 900}
}

foliage_transition_mass :: proc(
    x, z, width, depth, height, lift, fade: f32,
    seed: u32,
    hedge: bool = false,
    color: canvas2d.Color = {},
    rotation: f32 = 0,
) {
    // Geometry grows out of the final sparse planting band instead of simply
    // appearing at the LOD threshold. A material dither can later replace
    // this silhouette blend, but the lab already exposes whether the two
    // representations share a convincing footprint and crown height.
    blend := clamp(fade, f32(0), f32(1))
    // Preserve a quiet sparse leading edge. Square-root coverage made the
    // first proxy crowns read as a solid wall while their source trees were
    // still plainly visible.
    coverage := blend * blend * (3 - 2 * blend)
    footprint_blend := .82 + blend * .18
    height_blend := .72 + blend * .28
    volume_width := width * footprint_blend
    volume_depth := depth * footprint_blend
    volume_height := height * height_blend
    structure := terrain.Structure {
        center_x = x,
        center_z = z,
        width    = volume_width,
        depth    = volume_depth,
        height   = volume_height,
        base_y   = 0,
        kind     = .Foliage,
        seed     = seed,
        rotation = rotation,
    }
    // The volume deliberately overlaps the final sparse plant rows. This is
    // the seam under test: its clumps should inherit the planted footprint,
    // rather than arriving as a separate distant object.
    world_foliage_lobe(
        structure,
        0,
        0,
        volume_width,
        volume_depth,
        volume_height,
        lift,
        hedge,
        0,
        0,
        true,
        .Far,
        0,
        coverage,
        color,
    )
    world_foliage_lobe(
        structure,
        volume_width * .12,
        volume_depth * -.08,
        volume_width * .72,
        volume_depth * .78,
        volume_height * .82,
        lift + volume_height * .08,
        hedge,
        1,
        .8,
        true,
        .Far,
        .31,
        coverage,
        color,
    )
}

foliage_transition_canopy_mass :: proc(example: Foliage_Transition_Example, z, fade: f32, seed: u32) {
    switch example {
    case .Wheat_Field:
        if fade <= .02 do return
        footprint_blend := .78 + clamp(fade, f32(0), f32(1)) * .22
        field := terrain.Structure {
            center_x = 0,
            center_z = z,
            width    = 46 * footprint_blend,
            depth    = 18 * footprint_blend,
            height   = 1.35,
            base_y   = 0,
            kind     = .Foliage,
            seed     = seed,
        }
        // Exercise the production foliage LOD handoff in the lab instead of
        // maintaining a wheat-only proxy that can drift from it.
        world_foliage_formation(field, 0, .Far)
    case .Pine_Forest:
        // Three narrow, high crowns preserve conifer rhythm even after their
        // trunks and individual needle clusters have gone below a pixel.
        for crown in -3 ..= 3 {
            foliage_transition_mass(
                f32(crown) * 6.4,
                z + f32(crown & 1) * 1.4,
                9.2,
                18.5,
                3.8,
                6.4,
                fade,
                seed + u32(crown + 4) * 131,
            )
        }
    case .Oak_Forest:
        // Oak resolves into overlapping low shelves, never a line of cones.
        for crown in -2 ..= 2 {
            offset := f32(crown)
            foliage_transition_mass(
                offset * 8.2,
                z + f32(crown & 1) * 2.4 - 1.2,
                16.5,
                15.5,
                4.4 + f32((crown + 2) & 1) * .45,
                2.9,
                fade,
                seed + u32(crown + 3) * 971,
            )
        }
    case .Olive_Orchard:
        // Keep the aerial row cadence by retaining four separated, flattened
        // crowns rather than blending the whole parcel into one shrub.
        for row in -3 ..= 3 {
            foliage_transition_mass(f32(row) * 6.7, z - 2.9, 7.4, 7.2, 2.8, 2.0, fade, seed + u32(row + 4) * 313)
            foliage_transition_mass(
                f32(row) * 6.7 + .45,
                z + 4.1,
                7.1,
                6.8,
                2.65,
                1.95,
                fade,
                seed + u32(row + 4) * 313 + 1,
            )
        }
    case .Residential_Hedges:
        // Two hedge ribbons preserve the residential lane between them.
        foliage_transition_mass(-9.5, z, 4.2, 20, 2.4, .25, fade, seed, true)
        foliage_transition_mass(9.5, z, 4.2, 20, 2.4, .25, fade, seed + 997, true)
    }
}

foliage_transition_plant :: proc(
    editor: ^Editor,
    example: Foliage_Transition_Example,
    x, z, scale, yaw: f32,
    seed: u32,
    cutoff_distance: f32 = 148,
) {
    distance := foliage_transition_distance(editor, x, z)
    if distance > cutoff_distance do return
    if example == .Wheat_Field {
        color := canvas2d.Color{184, 159, 74, 255}
        world_grass_card({x, .68, z}, .36 * scale, 1.36 * scale, int(seed % 16), color)
        return
    }
    foliage_mode := distance < 40 ? Generated_Plant_Foliage_Mode.Leaves : .Density_Clumps
    // The middle representation keeps a botanically faithful low-detail
    // branch scaffold, but replaces its individual leaf cards with clump
    // volumes carrying the same projected leaf density.
    detail :=
        foliage_mode == .Density_Clumps ? plants.Detail_Level.Far : (distance < 54 ? plants.Detail_Level.Near : .Medium)
    _ = world_generated_plant(
        foliage_transition_species(example),
        u64(seed) | u64(0x46544c00) << 32,
        {x, 0, z},
        scale,
        yaw,
        .Free_Standing,
        nil,
        detail,
        0,
        .88,
        false,
        foliage_transition_site(),
        foliage_mode,
    )
}

Foliage_Transition_Forest_Sample :: struct {
    x, z:              f32,
    scale:             f32,
    spacing_scale:     f32,
    yaw:               f32,
    seed:              u32,
    transition_offset: f32,
}

foliage_transition_leaf_color :: proc(species: plants.Species) -> canvas2d.Color {
    _, fallback, _ := plant_generator_colors(species)
    total_r, total_g, total_b := 0, 0, 0
    for variant in 0 ..< 4 {
        color := plant_generator_leaf_color(species, u8(variant), fallback)
        total_r += int(color.r)
        total_g += int(color.g)
        total_b += int(color.b)
    }
    return {u8(total_r / 4), u8(total_g / 4), u8(total_b / 4), 255}
}

foliage_transition_generated_crown :: proc(
    example: Foliage_Transition_Example,
    x, z, scale, yaw, fade: f32,
    seed: u32,
) {
    species := foliage_transition_species(example)
    generated_seed := u64(seed) | u64(0x46544c00) << 32
    entry := generated_plant_cached(species, generated_seed, .Far, .Free_Standing, nil, 1, foliage_transition_site())
    if entry == nil do return

    minimum := third_person.Vec3{1e30, 1e30, 1e30}
    maximum := third_person.Vec3{-1e30, -1e30, -1e30}
    leaf_count := 0
    leaf_reach := f32(0)
    _, fallback_leaf_color, _ := plant_generator_colors(species)
    leaf_red, leaf_green, leaf_blue := 0, 0, 0
    for attachment in entry.result.plant.attachments {
        if attachment.kind != .Leaf do continue
        point := third_person.Vec3{attachment.position[0], attachment.position[1], attachment.position[2]}
        minimum.x = min(minimum.x, point.x)
        minimum.y = min(minimum.y, point.y)
        minimum.z = min(minimum.z, point.z)
        maximum.x = max(maximum.x, point.x)
        maximum.y = max(maximum.y, point.y)
        maximum.z = max(maximum.z, point.z)
        leaf_reach = max(leaf_reach, attachment.leaf.length * .5)
        attachment_color := plant_generator_leaf_color(species, attachment.variant, fallback_leaf_color)
        leaf_red += int(attachment_color.r)
        leaf_green += int(attachment_color.g)
        leaf_blue += int(attachment_color.b)
        leaf_count += 1
    }
    if leaf_count == 0 {
        bounds := entry.result.plant.bounds
        minimum = {bounds.minimum[0], bounds.minimum[1], bounds.minimum[2]}
        maximum = {bounds.maximum[0], bounds.maximum[1], bounds.maximum[2]}
    }
    profile := plants.garden_profile(species)
    // Keep a species-derived lower bound for sparse Far-detail specimens, but
    // leave enough negative space for the Poisson pattern to remain legible.
    // A .72 span exceeded the distant exclusion radius and collapsed the
    // forest into the sphere-packed carpet this lab is meant to avoid.
    coverage_span := profile.mature_spread * scale * .52
    width := max((maximum.x - minimum.x + leaf_reach * 2) * scale, coverage_span)
    depth := max((maximum.z - minimum.z + leaf_reach * 2) * scale, coverage_span)
    height := max((maximum.y - minimum.y + leaf_reach) * scale, f32(.24))
    lift := max((minimum.y - leaf_reach * .25) * scale, f32(.08))
    proxy_color := foliage_transition_leaf_color(species)
    if leaf_count > 0 {
        // The proxy uses the specimen's actual leaf-variant distribution.
        // Compact canopy geometry reflects more light than the perforated leaf
        // cards, so calibrate its albedo while preserving the derived hue.
        material_match := f32(.68)
        proxy_color = {
            u8(clamp(f32(leaf_red / leaf_count) * material_match, f32(0), f32(255))),
            u8(clamp(f32(leaf_green / leaf_count) * material_match, f32(0), f32(255))),
            u8(clamp(f32(leaf_blue / leaf_count) * material_match, f32(0), f32(255))),
            255,
        }
    }
    foliage_transition_mass(x, z, width, depth, height, lift, fade, seed, false, proxy_color, yaw)
}

foliage_transition_forest_world :: proc(editor: ^Editor, example: Foliage_Transition_Example) {
    MAX_SAMPLES :: 420
    CANDIDATES :: 2200
    samples: [MAX_SAMPLES]Foliage_Transition_Forest_Sample
    sample_count := 0
    species := foliage_transition_species(example)
    profile := plants.garden_profile(species)
    base_spacing := profile.mature_spread * .56
    for candidate in 0 ..< CANDIDATES {
        if sample_count >= min(MAX_SAMPLES, foliage_transition_forest_sample_limit) do break
        hash_x := foliage_transition_hash(u32(candidate) * 0x9e3779b9 + u32(example) * 0x85ebca6b)
        hash_z := foliage_transition_hash(hash_x ~ u32(0x68bc21eb))
        hash_scale := foliage_transition_hash(hash_z ~ u32(0x517cc1b7))
        x :=
            -foliage_transition_forest_half_width +
            f32(hash_x & 0x00ffffff) / f32(0x01000000) * foliage_transition_forest_half_width * 2
        z :=
            foliage_transition_forest_start +
            f32(hash_z & 0x00ffffff) / f32(0x01000000) * foliage_transition_forest_depth
        // A broad but plausible age/size distribution creates understory and
        // emergent crowns; a narrow ±25% range produced a level proxy skyline.
        scale := .62 + f32(hash_scale & 0xffff) / f32(0x10000) * .80
        depth_fraction := clamp(
            (z - foliage_transition_forest_start) / foliage_transition_forest_depth,
            f32(0),
            f32(1),
        )
        depth_curve := depth_fraction * depth_fraction * (3 - 2 * depth_fraction)
        // Perspective already compresses distant samples. Give the walkable
        // foreground more canopy coverage and let the horizon breathe.
        spacing_scale := .72 + depth_curve * .46
        accepted := true
        for existing in samples[:sample_count] {
            dx, dz := x - existing.x, z - existing.z
            exclusion := base_spacing * (scale * spacing_scale + existing.scale * existing.spacing_scale) * .5
            if dx * dx + dz * dz < exclusion * exclusion {
                accepted = false
                break
            }
        }
        if !accepted do continue
        placement_hash := foliage_transition_hash(hash_scale ~ u32(candidate * 977))
        // A small specimen palette keeps capture startup bounded while scale and
        // rotation still give each Poisson sample a distinct silhouette.
        specimen := u32(candidate % 12)
        seed := foliage_transition_hash(specimen + u32(example) * 0x85ebca6b)
        samples[sample_count] = {
            x                 = x,
            z                 = z,
            scale             = scale,
            spacing_scale     = spacing_scale,
            yaw               = f32(placement_hash & 0xffff) / f32(0x10000) * math.TAU,
            seed              = seed,
            // Break the LOD boundary into overlapping pockets so the forest
            // recedes as a mass instead of crossing one camera-facing line.
            transition_offset = (f32((placement_hash >> 16) & 0xffff) / f32(0x10000) - .5) * 28,
        }
        sample_count += 1
    }
    for sample in samples[:sample_count] {
        distance := foliage_transition_distance(editor, sample.x, sample.z)
        proxy_start := 96 + sample.transition_offset
        transition_span := f32(64)
        if distance >= proxy_start {
            fade := clamp((distance - proxy_start) / transition_span, f32(0), f32(1))
            foliage_transition_generated_crown(
                example,
                sample.x,
                sample.z,
                sample.scale,
                sample.yaw,
                fade,
                sample.seed,
            )
        }
        foliage_transition_plant(
            editor,
            example,
            sample.x,
            sample.z,
            sample.scale,
            sample.yaw,
            sample.seed,
            proxy_start + transition_span,
        )
    }
}

foliage_transition_lab_world :: proc(editor: ^Editor) {
    if editor == nil do return
    example := foliage_transition_example
    if example == .Pine_Forest || example == .Oak_Forest {
        foliage_transition_forest_world(editor, example)
        return
    }
    // Twenty-four contiguous cells give the camera one unbroken corridor:
    // individual plants are retained through 148 m, mass starts at 92 m, and
    // their 56 m overlap is the intended cross-fade design range.
    for cell in 0 ..< 24 {
        z := 12 + f32(cell) * 15
        seed := foliage_transition_hash(u32(cell) * 0x9e3779b9 + u32(example) * 0x85ebca6b)
        distance := foliage_transition_distance(editor, 0, z)
        if distance >= 104 {
            mass_fade := clamp((distance - 104) / 44, f32(0), f32(1))
            foliage_transition_canopy_mass(example, z, mass_fade, seed)
        }

        switch example {
        case .Wheat_Field:
            for row in -15 ..= 15 {
                for stalk in 0 ..< 7 {
                    x := f32(row) * 1.35 + f32(stalk & 1) * .24
                    foliage_transition_plant(
                        editor,
                        example,
                        x,
                        z - 6 + f32(stalk) * 1.85,
                        .92,
                        0,
                        seed + u32(row + 16) * 37 + u32(stalk),
                    )
                }
            }
        case .Olive_Orchard:
            for row in -3 ..= 3 {
                foliage_transition_plant(editor, example, f32(row) * 6.7, z - 3.5, 1.04, .08, seed + u32(row + 4) * 41)
                foliage_transition_plant(
                    editor,
                    example,
                    f32(row) * 6.7 + .5,
                    z + 4.2,
                    .96,
                    -.06,
                    seed + u32(row + 4) * 41 + 1,
                )
            }
        case .Residential_Hedges:
            sides := [2]int{-1, 1}
            for side in sides {
                for plant in 0 ..< 4 {
                    foliage_transition_plant(
                        editor,
                        example,
                        f32(side) * 9.5,
                        z - 5 + f32(plant) * 3.4,
                        .96,
                        0,
                        seed + u32(side + 2) * 31 + u32(plant),
                    )
                }
            }
        case .Pine_Forest, .Oak_Forest:
            for row in -3 ..= 3 {
                for plant in 0 ..< 3 {
                    mixed := foliage_transition_hash(seed + u32(row + 2) * 61 + u32(plant))
                    x := f32(row) * 6.2 + (f32(mixed & 255) / 255 - .5) * 1.8
                    foliage_transition_plant(
                        editor,
                        example,
                        x,
                        z - 4 + f32(plant) * 4.1,
                        1.0 + f32((mixed >> 8) & 31) / 180,
                        f32(mixed & 255) / 255 * math.TAU,
                        mixed,
                    )
                }
            }
        }
    }
}

foliage_transition_lab_process_input :: proc(editor: ^Editor) {
    if editor == nil do return
    selected := foliage_transition_example
    if canvas2d.IsKeyPressed(.ONE) do selected = .Wheat_Field
    if canvas2d.IsKeyPressed(.TWO) do selected = .Pine_Forest
    if canvas2d.IsKeyPressed(.THREE) do selected = .Oak_Forest
    if canvas2d.IsKeyPressed(.FOUR) do selected = .Olive_Orchard
    if canvas2d.IsKeyPressed(.F) do selected = .Residential_Hedges
    if selected == foliage_transition_example do return
    foliage_transition_example = selected
}

foliage_transition_lab_draw_ui :: proc(_: ^Editor, _: i32, _: i32) {
    panel := canvas2d.Rectangle{24, 24, 560, 112}
    canvas2d.DrawRectangleRounded(panel, .10, 8, {10, 27, 37, 226})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .10, 8, 1, {104, 168, 184, 255})
    canvas2d.DrawTextEx(canvas2d.Font{}, "FOLIAGE TRANSITION LAB", {40, 40}, 20, 1, {245, 238, 197, 255})
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        foliage_transition_example_name(foliage_transition_example),
        {40, 70},
        17,
        1,
        {105, 215, 198, 255},
    )
    canvas2d.DrawTextEx(
        canvas2d.Font{},
        "1 WHEAT   2 PINE   3 OAK   4 OLIVE   F HEDGES",
        {40, 102},
        14,
        1,
        {190, 207, 211, 255},
    )
}
