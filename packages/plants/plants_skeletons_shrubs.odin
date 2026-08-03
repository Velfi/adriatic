package plants

import lsystem "../lsystem"
import "core:math"
import "core:math/linalg"

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
            lsystem.Leaf{position = radial * (.012 * f32(ring)), forward = forward, up = tangent, depth = 0},
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
                lsystem.Leaf{position = terminal, forward = direction, up = {-radial[2], 0, radial[0]}, depth = -6},
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
                        forward = linalg.normalize0(
                            lsystem.Vec3 {
                                math.cos(side_angle + math.PI * .5),
                                .10,
                                math.sin(side_angle + math.PI * .5),
                            },
                        ),
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
            append(&plant.leaves, lsystem.Leaf{position = position, forward = forward, up = up, depth = segment.depth})
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
    // Olive blades spread mostly sideways from a shoot. Choose either side
    // before applying the shallow roll; constraining every sample around the
    // positive side axis put every source leaf on the same side of its shoot
    // (most visible when Far detail collapses each opposite pair to one card).
    // A full 360-degree roll still creates implausible curtains of vertically
    // hanging leaves, so retain the narrow botanical fan on both sides.
    side_sign := lsystem.random_next(random) & 1 == 0 ? f32(-1) : f32(1)
    phase := olive_random_signed(random) * .45
    forward := linalg.normalize0(side * side_sign * math.cos(phase) + stem_up * math.sin(phase))
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
            side * olive_random_signed(random) * .24 +
            binormal * olive_random_signed(random) * .16 +
            lsystem.Vec3{0, .05, 0},
        )
        // Compact, crooked runs let neighboring twigs overlap into an olive
        // crown instead of exposing long straight scaffold rays.
        segment_length := length * (.80 - f32(segment_index) * .075) * (1 + olive_random_signed(random) * .12)
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
            if generations <= 1 {
                // Fill terminal shoots with one staggered station. Three
                // widely separated pairs exposed the branch as a ladder;
                // this keeps the opposite-pair habit while closing the crown.
                fill_fraction := .56 + olive_random_signed(foliage_random) * .06
                olive_emit_spray(
                    plant,
                    foliage_random,
                    position - direction * segment_length * (1 - fill_fraction),
                    direction,
                    depth,
                )
            }
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

    child_count := generations >= 2 ? 3 : 2
    parent_direction := direction
    parent_side := linalg.normalize0(linalg.cross(parent_direction, lsystem.Vec3{0, 1, 0}))
    if linalg.dot(parent_side, parent_side) < .2 do parent_side = {1, 0, 0}
    parent_up := linalg.normalize0(linalg.cross(parent_side, parent_direction))
    phase := olive_random_signed(random) * math.PI
    for child_index in 0 ..< child_count {
        azimuth := phase + f32(child_index) * math.PI * 2 / f32(child_count)
        radial := parent_side * math.cos(azimuth) + parent_up * math.sin(azimuth)
        child_direction := linalg.normalize0(
            parent_direction * (.50 + olive_random_signed(random) * .08) +
            radial * (.66 + olive_random_signed(random) * .10) +
            lsystem.Vec3{0, .12 + olive_random_signed(random) * .08, 0},
        )
        olive_grow_branch(
            plant,
            random,
            foliage_random,
            position,
            child_direction,
            length * (.62 + olive_random_signed(random) * .05),
            current_radius * .66,
            depth + 1,
            generations - 1,
        )
    }
}
