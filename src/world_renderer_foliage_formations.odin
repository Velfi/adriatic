package main
import "core:math"

import terrain "../packages/terrain"
import canvas2d "zelda_engine:canvas2d"

world_foliage_formation :: proc(
    structure: terrain.Structure,
    minimum_footprint := terrain.BASE_CELL_SIZE,
    lod: Structure_LOD = .Near,
    aerial_view := false,
) {
    // Authored foliage retains the tool's one-cell minimum. Derived foliage,
    // such as scrub placed on a ridge or cliff, can opt into its exact
    // footprint while still using this same crown generator.
    width := max(structure.width, minimum_footprint)
    depth := max(structure.depth, minimum_footprint)
    if world_foliage_should_condense_to_field(width, depth, structure.height, lod) && world_renderer.editor != nil {
        condensed := structure
        condensed.width = width
        condensed.depth = depth
        world_crop_field(condensed, &world_renderer.editor.project, lod)
        return
    }
    shadow_first := len(world_renderer.vertices)
    defer world_register_shadow_caster(shadow_first)
    wide, narrow := max(width, depth), min(width, depth)
    aspect := wide / max(narrow, f32(.01))
    mature_forest, aerial_woodland := world_foliage_is_forest(width, depth, structure.height, lod, aerial_view)
    // Young groves and broad shrub patches should join the surrounding wood
    // when viewed from the air, even though their close treatment remains a
    // lower bush mass. A tiny aerial-only crown budget prevents these patches
    // from dissolving the forest edge into isolated dots.
    young_aerial_woodland := aerial_view && aerial_woodland && !mature_forest
    is_forest := mature_forest || aerial_woodland
    // Keep forest patches dense by filling their area with tree-scale trees,
    // rather than stretching a handful of crowns across the footprint.
    forest_tree_count := mature_forest ? clamp(int(width * depth / 460), 24, 36) : 0
    if mature_forest && lod == .Medium do forest_tree_count = min(forest_tree_count, 18)
    if mature_forest && lod == .Far do forest_tree_count = min(forest_tree_count, 7)
    if aerial_woodland && !mature_forest {
        forest_tree_count = lod == .Far ? 4 : lod == .Medium ? 6 : 12
    }
    // A nearby grove can fill much of the aerial frame, but its individual
    // contour facets remain too small to justify the 30x10 walking mesh.
    // Preserve the full mature tree count (or all twelve young crowns) and
    // only select the approved 16x6 crown topology. This avoids the sparse
    // canopy failure of reducing count and topology together. Ground views
    // never enter this path.
    crown_lod := lod
    if aerial_view && is_forest && lod == .Near {
        crown_lod = .Medium
    }
    crown_shape_lod := crown_lod
    if aerial_view && mature_forest && lod == .Near {
        // Mature aerial woods decimate topology only. Their Near coverage,
        // perimeter, and three-emergent composition remain identical.
        crown_shape_lod = lod
    }
    // A forest formation is a grove footprint, not one gigantic tree. Keep
    // the leaf ceiling around four character heights while individual crown
    // clusters supply the remaining tree height.
    canopy_lift := is_forest ? structure.height * .11 : f32(0)

    // Large authored groves can remain well above the generic 48-pixel Far
    // threshold even in a high aerial shot. Once a Medium grove is viewed
    // from above, its internal tree spacing is already perceived as one value
    // shape, so join neighboring footprints at that perceptual transition.
    if is_forest && world_foliage_uses_cluster_mass(lod, aerial_view) {
        world_foliage_far_forest_mass(structure, width, depth, canopy_lift)
        world_foliage_far_forest_bridges(structure)
    }

    if is_forest {
        walking_distance := lod == .Near && !aerial_view
        dapple_count := 7
        if !walking_distance do dapple_count = 0
        for dapple in 0 ..< dapple_count {
            angle := f32(dapple) * 2.399963 + f32(structure.seed % 149) * .026
            radial := .12 + f32((dapple * 5 + 2) % 9) / 8 * .30
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            dapple_x, dapple_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            dapple_width := 13.0 + f32(dapple % 3) * 5.5
            dapple_depth := 9.5 + f32((dapple + 1) % 3) * 4.0
            dapple_rotation := angle * .47 + structure.rotation
            world_foliage_ground_dapple(
                dapple_x,
                dapple_z,
                structure.base_y,
                dapple_width,
                dapple_depth,
                dapple_rotation,
                structure.seed + u32(dapple * 1699),
            )
            // A smaller overlapping echo breaks the radial fan into a loose
            // painted pool. Offset it across the main ellipse rather than
            // scattering another isolated dot, so their shared center gains
            // light while the combined outer edge stays irregular and soft.
            echo_angle := dapple_rotation + 1.17 + f32(dapple % 2) * .41
            echo_x := dapple_x + math.cos(echo_angle) * dapple_width * .22
            echo_z := dapple_z + math.sin(echo_angle) * dapple_depth * .22
            world_foliage_ground_dapple(
                echo_x,
                echo_z,
                structure.base_y + .006,
                dapple_width * (.61 + f32(dapple % 2) * .07),
                dapple_depth * (.66 - f32(dapple % 2) * .05),
                dapple_rotation - .58,
                structure.seed + u32(dapple * 1699 + 947),
            )
        }

        understory_count := walking_distance ? clamp(forest_tree_count, 24, 32) : 0
        for tuft in 0 ..< understory_count {
            angle := f32(tuft) * 2.399963 + f32(structure.seed % 127) * .029
            radial := .28 + f32((tuft * 7) % 9) / 8 * .25
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            tuft_x, tuft_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            // Human-scale fern colonies: broad enough to read from the editor
            // camera, but roughly knee-to-chest high in third person.
            // Each placement represents an overlapping fern colony, not one
            // enormous plant: widen the fan while retaining human-scale
            // frond height so ground cover reads as painted patches.
            tuft_width := 2.05 + f32(tuft % 4) * .38
            tuft_height := 1.05 + f32((tuft + 2) % 5) * .22
            tuft_gesture := tuft % 4
            if tuft_gesture == 0 || tuft_gesture == 1 {
                // Broad, low fern fans are the dominant ground gesture. This
                // avoids a floor full of narrow conifer-like spikes while
                // preserving layered silhouettes between the trunks.
                tuft_width *= 1.28
                tuft_height *= .76
            } else if tuft_gesture == 3 {
                // Occasional upright clumps punctuate the fan rhythm without
                // becoming the default understory silhouette.
                tuft_width *= .90
                tuft_height *= 1.10
            }
            world_foliage_understory_tuft(
                tuft_x,
                tuft_z,
                structure.base_y,
                tuft_width,
                tuft_height,
                structure.seed + u32(tuft * 1301),
            )
        }

        // A quieter layer of low broadleaf rosettes bridges the empty ground
        // between fern fans. Their separate spiral and smaller radial range
        // produce loose colonies rather than a uniformly stamped carpet.
        ground_cover_count := walking_distance ? clamp(forest_tree_count + 8, 30, 44) : 0
        for cover in 0 ..< ground_cover_count {
            angle := f32(cover) * 2.399963 + f32(structure.seed % 163) * .021 + .83
            radial := .09 + f32((cover * 5 + 3) % 11) / 10 * .41
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            cover_x, cover_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            cover_width := 1.25 + f32(cover % 4) * .28
            cover_height := .28 + f32((cover + 2) % 3) * .08
            world_foliage_ground_rosette(
                cover_x,
                cover_z,
                structure.base_y,
                cover_width,
                cover_height,
                structure.seed + u32(cover * 1877 + 431),
            )
        }

        // A low-discrepancy spiral makes a dense natural stand without rows.
        // Far woodland is viewed as a painted canopy mass. Its trunks occupy
        // less than a pixel and only add draw bandwidth and dark pinstripes.
        trunk_count := lod == .Far ? 0 : forest_tree_count
        if !mature_forest do trunk_count = 0
        for trunk in 0 ..< trunk_count {
            local_x, local_z := world_foliage_forest_tree_local(structure, trunk)
            trunk_x, trunk_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            trunk_ground_y := terrain.sample_surface_height(&world_renderer.editor.project, 0, trunk_x, trunk_z)
            height_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .013 + f32(trunk) * 1.73)))
            tree_canopy_lift := structure.height * (.075 + height_noise * .055)
            if !aerial_view {
                // Give players a readable woodland room beneath the boughs.
                // The aerial lift placed low-noise crowns barely above head
                // height, turning the near forest into a continuous ceiling.
                tree_canopy_lift = structure.height * (.105 + height_noise * .060)
            }
            trunk_height := tree_canopy_lift + structure.height * (.040 + height_noise * .012)
            trunk_radius := max(
                f32(.52),
                min(width, depth) *
                (.0055 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .031 + f32(trunk) * 2.53)))) * .0030),
            )
            crown_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .029 + f32(trunk) * 2.17)))
            crown_span := structure.height * (.17 + crown_noise * .075)
            if aerial_view {
                crown_span = structure.height * (.20 + crown_noise * .09)
            }
            if aerial_view && mature_forest && crown_shape_lod == .Near {
                coverage_span := f32(math.sqrt(f64(width * depth / f32(max(forest_tree_count, 1))))) * 1.08
                crown_span = max(crown_span, coverage_span)
            }
            world_foliage_trunk(
                trunk_x,
                trunk_z,
                trunk_ground_y,
                trunk_height,
                trunk_radius,
                crown_span,
                structure.seed + u32(trunk * 977),
            )
        }
    }

    if aspect >= 1.8 {
        // Long gestures become hedges. Shorter, more numerous crowns overlap
        // into a continuous mass while exposing a readable scalloped rhythm;
        // the earlier four very long lobes merged into smooth sausages.
        // Resolve long hedges into enough crown beats that their silhouette
        // reads as clipped vegetation rather than three or four inflated
        // capsules. The overlapping binder still guarantees continuity.
        lobe_count := clamp(int(wide / max(narrow * 1.15, f32(1))) + 3, 4, 8)
        // A low recessed binder closes the dark gaps between crown beats. Most
        // of it remains concealed by the scallops, preserving one continuous
        // hedge gesture without returning to a single exposed sausage.
        binder_width, binder_depth := wide * .88, narrow * .76
        if depth > width do binder_width, binder_depth = binder_depth, binder_width
        world_foliage_lobe(
            structure,
            0,
            0,
            binder_width,
            binder_depth,
            structure.height * .43,
            0,
            true,
            19,
            0,
            false,
            lod,
        )
        for lobe in 0 ..< lobe_count {
            fraction := (f32(lobe) + .5) / f32(lobe_count)
            along :=
                (fraction - .5) * wide * .82 +
                f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.77))) * wide / f32(lobe_count) * .08
            cross := f32(math.sin(f64(f32(structure.seed) * .009 + f32(lobe) * 2.41))) * narrow * .18
            local_x, local_z := along, cross
            crown_scale := .90 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .027 + f32(lobe) * 1.87)))) * .20
            if lobe == int(structure.seed % u32(lobe_count)) do crown_scale *= 1.06
            lobe_width := max(wide / f32(lobe_count) * 1.72, narrow * 1.04) * crown_scale
            lobe_depth :=
                narrow *
                (.92 + f32(math.sin(f64(f32(structure.seed) * .021 + f32(lobe) * 1.31))) * .065) *
                (.96 + (crown_scale - 1) * .38)
            if depth > width {
                local_x, local_z = cross, along
                lobe_width, lobe_depth = lobe_depth, lobe_width
            }
            lobe_height :=
                structure.height *
                (.54 + f32(math.sin(f64(f32(structure.seed) * .017 + f32(lobe) * 1.63))) * .090) *
                (.97 + (crown_scale - 1) * .20)
            outward := f32(math.PI * .5)
            if depth > width do outward = 0
            if lobe % 2 != 0 do outward += math.PI
            world_foliage_lobe(
                structure,
                local_x,
                local_z,
                lobe_width,
                lobe_depth,
                lobe_height,
                0,
                true,
                lobe,
                outward,
                true,
                lod,
            )
        }
        return
    }

    // Broad gestures become bushes or forest canopy patches. A deterministic
    // dominant crown and an opposing concave opening give each gesture a
    // composed silhouette instead of an evenly filled radial blob.
    lobe_count := clamp(int(wide / (terrain.BASE_CELL_SIZE * 1.5)) + 5, 5, 9)
    if is_forest do lobe_count = forest_tree_count
    outer_count := max(lobe_count - 1, 1)
    dominant_lobe := 1 + int(structure.seed % u32(outer_count))
    seed_phase := f32(structure.seed % 97) * .031
    dominant_angle := f32(dominant_lobe - 1) * 2.399963 + seed_phase
    opening_angle := dominant_angle + math.PI
    for lobe in 0 ..< lobe_count {
        local_x, local_z := f32(0), f32(0)
        radial := f32(0)
        angle := f32(0)
        opening_strength := f32(0)
        if lobe > 0 {
            angle = f32(lobe - 1) * 2.399963 + seed_phase
            radial = .18 + .27 * f32(math.sqrt(f64(f32(lobe) / f32(outer_count))))
            opening_delta := angle - opening_angle
            opening_distance := math.abs(math.atan2(math.sin(opening_delta), math.cos(opening_delta)))
            opening_strength = clamp(1 - opening_distance / .72, 0, 1)
            radial += opening_strength * .055
            if is_forest {
                // Forest positions are composed below from a shared tree
                // center plus one of three overlapping crown offsets. The
                // bush-specific concave opening must not shrink one crown in
                // every tree cluster.
                opening_strength = 0
            }
        }
        // The center only binds the patch together; it should not become one
        // dominant balloon. Mid-sized perimeter crowns now carry the canopy.
        scale := is_forest ? f32(.085) : f32(.59)
        if lobe > 0 {
            scale = .40 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .019 + f32(lobe) * 1.87)))) * .20
            if is_forest {
                scale = .075 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .019 + f32(lobe) * 1.87)))) * .035
            }
            scale *= 1 - opening_strength * .34
        }
        height_fraction := is_forest ? f32(.17) : f32(.80)
        if lobe > 0 {
            height_fraction = .62 + f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.71))) * .15
            if is_forest {
                height_fraction = .15 + f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.71))) * .028
            }
        }
        height_fraction *= 1 - opening_strength * .18
        if lobe == dominant_lobe {
            scale *= 1.16
            height_fraction *= 1.20
            radial *= .92
        }
        if lobe > 0 {
            if is_forest {
                // One irregular crown per trunk preserves density without
                // tripling the tessellation cost of every tree.
                tree_index := lobe
                local_x, local_z = world_foliage_forest_tree_local(structure, tree_index)
                angle = math.atan2(local_z / depth, local_x / width)
            } else {
                local_x = math.cos(angle) * width * radial
                local_z = math.sin(angle) * depth * radial
            }
        } else if is_forest {
            local_x, local_z = world_foliage_forest_tree_local(structure, 0)
            angle = math.atan2(local_z / depth, local_x / width)
            scale = .075 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .019)))) * .035
            height_fraction = .15 + f32(math.sin(f64(f32(structure.seed) * .013))) * .028
        }
        lobe_height := structure.height * height_fraction
        outward := f32(0)
        if lobe > 0 do outward = math.atan2(local_z / depth, local_x / width)
        lobe_base_lift := canopy_lift
        if is_forest {
            // Layer saplings, middle crowns, and mature trees into one dense
            // stand. The matching expression in the trunk pass keeps every
            // crown attached to its own trunk.
            height_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.73)))
            lobe_base_lift = structure.height * (.075 + height_noise * .055)
            if !aerial_view {
                lobe_base_lift = structure.height * (.105 + height_noise * .060)
            }
            lobe_height *= .82 + height_noise * .30
            if young_aerial_woodland {
                // Young aerial groves need a layered ceiling as well as area
                // coverage. A small lift and stronger deterministic height
                // range separate saplings, middle crowns, and emergents
                // without emitting another crown or increasing topology.
                lobe_base_lift += structure.height * (.012 + height_noise * .014)
                lobe_height *= 1.10 + height_noise * .18
            }
        }
        lobe_width, lobe_depth := width * scale, depth * scale
        lobe_structure := structure
        if is_forest {
            crown_x, crown_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            lobe_structure.base_y = terrain.sample_surface_height(&world_renderer.editor.project, 0, crown_x, crown_z)
            // A tree crown has its own dimensions; it must not inherit the
            // aspect ratio of the authored forest footprint. Per-tree seed
            // variation also mixes crown profiles and green families across
            // the stand instead of tinting the whole patch as one species.
            crown_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .029 + f32(lobe) * 2.17)))
            // Mature crowns must overlap into a continuous woodland ceiling.
            // The former span left visible grass channels between nearly
            // every tree in aerial views, turning forests into gumdrop fields.
            crown_span := structure.height * (.17 + crown_noise * .075)
            if aerial_view {
                crown_span = structure.height * (.20 + crown_noise * .09)
            }
            if aerial_view && mature_forest && crown_shape_lod == .Near {
                // Near topology is retained from the air, but its physical
                // footprint still needs to cover the grove. Derive a minimum
                // diameter from area per tree so neighboring shelves meet
                // instead of exposing a regular network of grass channels.
                coverage_span := f32(math.sqrt(f64(width * depth / f32(max(forest_tree_count, 1))))) * 1.08
                crown_span = max(crown_span, coverage_span)
            }
            if crown_shape_lod != .Near {
                // Once individual trees occupy only a few pixels, preserve
                // the authored forest's covered area rather than preserving
                // the near crown diameter. The LOD deliberately emits fewer
                // crowns; scaling those crowns from area-per-sample lets them
                // overlap into coherent copses instead of dissolving the
                // forest into isolated dots.
                coverage_scale := crown_shape_lod == .Far ? f32(1.05) : f32(.72)
                if !mature_forest {
                    coverage_scale = crown_shape_lod == .Far ? f32(1.10) : f32(.95)
                }
                coverage_span := f32(math.sqrt(f64(width * depth / f32(max(forest_tree_count, 1))))) * coverage_scale
                crown_span = max(crown_span, coverage_span)
            }
            crown_aspect := .64 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .041 + f32(lobe) * 1.31)))) * .74
            lobe_width = crown_span * crown_aspect
            lobe_depth = crown_span / crown_aspect
            lobe_structure.seed += u32(lobe * 977)
            if crown_shape_lod != .Near || aerial_view {
                // Feather the authored ellipse into an irregular woodland
                // silhouette. Interior crowns retain full coverage; only the
                // outer third steps down into smaller, lower scallops. Apply
                // this to aerial Near topology too: retaining its vertices
                // must not retain the clipped row of equal circles.
                normalized_x := local_x / max(width * .5, f32(.01))
                normalized_z := local_z / max(depth * .5, f32(.01))
                edge_radius := f32(math.sqrt(f64(normalized_x * normalized_x + normalized_z * normalized_z)))
                edge_taper := clamp((edge_radius - .62) / .40, 0, 1)
                edge_taper = edge_taper * edge_taper * (3 - 2 * edge_taper)
                perimeter_scale := 1 - edge_taper * .16
                lobe_width *= perimeter_scale
                lobe_depth *= perimeter_scale
                lobe_height *= 1 - edge_taper * .12

            }

            // Every forest tier needs one composed hierarchy, not a random
            // third of its crowns using the loud upright laurel profile.
            // Preserve three Near, two Medium, or one Far emergent accents;
            // all remaining trees become broad oak/broadleaf shelves. Near
            // keeps its full geometry and density, so walking detail survives.
            tree_count := max(forest_tree_count, 1)
            primary_emergent := int(structure.seed % u32(tree_count))
            secondary_emergent := (primary_emergent + max(tree_count / 2, 1)) % tree_count
            tertiary_emergent := (primary_emergent + max(tree_count / 3, 1)) % tree_count
            emergent :=
                lobe == primary_emergent ||
                (crown_shape_lod != .Far && lobe == secondary_emergent) ||
                (young_aerial_woodland && lobe == tertiary_emergent)
            if emergent {
                height_scale :=
                    crown_shape_lod == .Far ? f32(1.28) : crown_shape_lod == .Medium ? f32(1.16) : f32(1.10)
                lift_scale := crown_shape_lod == .Far ? f32(.025) : crown_shape_lod == .Medium ? f32(.012) : f32(.006)
                width_scale := crown_shape_lod == .Far ? f32(.78) : crown_shape_lod == .Medium ? f32(.87) : f32(.92)
                lobe_height *= height_scale
                lobe_base_lift += structure.height * lift_scale
                lobe_width *= width_scale
                lobe_depth *= width_scale
                species_remainder := lobe_structure.seed % 3
                lobe_structure.seed += (2 + 3 - species_remainder) % 3
            } else if lobe_structure.seed % 3 == 2 {
                lobe_structure.seed += 1
            }
        }
        crown_orientation := f32(0)
        if is_forest {
            // Each tree owns an independent grain direction. Rotating only
            // the crown profile (not its formation-local center) breaks the
            // stamped rows of parallel oval shelves while preserving stable
            // placement, terrain attachment, and the matching trunk.
            orientation_hash := world_foliage_tree_hash(structure.seed ~ u32(lobe + 1) * 0x9e3779b9)
            crown_orientation = f32(f64(orientation_hash) / f64(0x1_0000_0000)) * math.TAU
        }
        world_foliage_lobe(
            lobe_structure,
            local_x,
            local_z,
            lobe_width,
            lobe_depth,
            lobe_height,
            lobe_base_lift,
            false,
            lobe,
            outward,
            // The solid crowns already occupy several pixels in aerial woods.
            // Their translucent outline sprays become subpixel speckle and
            // spend an animated card budget without improving the woodland
            // silhouette. Retain those cards for walking views where
            // leaf-scale edge breakup is actually visible.
            lobe > 0 && !(aerial_view && is_forest),
            crown_lod,
            crown_orientation,
        )
    }
}

world_formation_top_fraction :: proc(structure: terrain.Structure, local_x, local_z: f32) -> f32 {
    if structure.kind == .Cliff {
        // Cliff tops follow the same segmented, lightly broken profile as the
        // rendered cliff mesh.
        segment := (local_x / max(structure.width, f32(.01)) + .5) * 6
        return .84 + f32(math.sin(f64(f32(structure.seed) * .001 + segment * 1.73))) * .055
    }
    // Ridge foliage sits on the radial ridge profile, not on a flat height
    // fraction. This keeps bushes on the shoulder from hovering in the air.
    radius_x := local_x / max(structure.width * .5, f32(.01))
    radius_z := local_z / max(structure.depth * .5 * .42, f32(.01))
    radius := f32(math.sqrt(f64(radius_x * radius_x + radius_z * radius_z)))
    if radius >= .92 do return clamp((1 - radius) / .08 * .22, 0, .22)
    if radius >= .60 do return .22 + (.92 - radius) / .32 * .28
    if radius >= .14 do return .50 + (.60 - radius) / .46 * .28
    return .78 + (.14 - radius) / .14 * .12
}

world_formation_foliage :: proc(structure: terrain.Structure, lod: Structure_LOD = .Near) {
    if lod == .Far do return
    tuft_count := clamp(int(structure.width / 14), 4, 20)
    if lod == .Medium do tuft_count = max(2, tuft_count / 2)
    for tuft in 0 ..< tuft_count {
        fraction := (f32(tuft) + .5) / f32(tuft_count)
        jitter := f32(math.sin(f64(f32(structure.seed) * .013 + f32(tuft) * 2.41)))
        local_x := (fraction - .5) * structure.width + jitter * min(structure.width * .08, 3)
        local_z := f32(math.sin(f64(f32(structure.seed) * .007 + f32(tuft) * 1.73))) * structure.depth * .24
        base_y := structure.base_y + structure.height * world_formation_top_fraction(structure, local_x, local_z)
        bush_width := clamp(structure.depth * .50, 1.8, 10.0)
        bush_depth := clamp(structure.depth * .38, 1.3, 7.0)
        bush_height := clamp(structure.height * (.22 + f32(tuft % 3) * .035), 2.5, 10.0)
        bush_x, bush_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        foliage := structure
        foliage.kind = .Foliage
        foliage.center_x = bush_x
        foliage.center_z = bush_z
        foliage.base_y = base_y
        // The former tuft dimensions were radii. These compact footprints keep
        // roughly the same occupied area after the shared generator adds its
        // overlapping perimeter crowns.
        foliage.width = bush_width * 1.55
        foliage.depth = bush_depth * 1.55
        foliage.height = bush_height
        foliage.rotation += jitter * .18
        foliage.seed += u32(tuft * 977 + 431)
        world_foliage_formation(foliage, 0, lod)
    }
}

@(no_instrumentation)
world_architecture_cypress_surface_color :: #force_inline proc(
    base: canvas2d.Color,
    angle, progress: f32,
    ring: int,
    seed: u32,
) -> canvas2d.Color {
    color := formation_face_color(base, angle, ring)
    // Long correlated waves imply upright sprays and the cool recesses between
    // them. A quieter cross-wave keeps those strokes from becoming stripes.
    long_wave := f32(math.sin(f64(angle * 3.1 + progress * 2.4 + f32(seed % 211) * .031)))
    cross_wave := f32(math.sin(f64(angle * 6.7 - progress * 5.2 + f32(seed % 157) * .047)))
    spray_field := long_wave * .72 + cross_wave * .28
    if spray_field < -.12 {
        recess := clamp((-spray_field - .12) / .88, 0, 1)
        color = color_lerp(color, {18, 49, 34, 255}, recess * .42)
    } else if spray_field > .24 {
        crest := clamp((spray_field - .24) / .76, 0, 1)
        color = color_lerp(color, {82, 137, 73, 255}, crest * .16)
    }
    return color
}
