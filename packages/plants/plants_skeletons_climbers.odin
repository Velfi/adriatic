package plants

import lsystem "../lsystem"
import "core:math"
import "core:math/linalg"

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
            append(&result.plant.leaves, lsystem.Leaf{position = next, forward = direction, up = radial, depth = 0})
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
                lsystem.Leaf{position = flower_tip, forward = {0, 1, 0}, up = radial, depth = -4},
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
    stem_count :=
        is_tree ? (detail == .Near ? 11 : detail == .Medium ? 8 : 6) : (detail == .Near ? 24 : detail == .Medium ? 20 : 18)
    phase := f32(lsystem.random_next(&random) % 10_000) / 10_000 * math.PI * 2
    crown_base := lsystem.Vec3{}
    crown_radius := f32(.010) * (.35 + maturity * .65)

    if is_tree {
        trunk_radius := f32(.045) * (.35 + maturity * .65)
        position := lsystem.Vec3{}
        for trunk_index in 0 ..< 4 {
            drift_angle := phase + f32(trunk_index) * 1.7
            next :=
                position +
                lsystem.Vec3 {
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
        radius :=
            (is_tree ? crown_radius : f32(.009) * (.35 + maturity * .65)) * (1 + olive_random_signed(&random) * .10)
        segment_count := 3
        crown_reach := inner_stem ? f32(.16) : f32(.50)
        reach := (is_tree ? f32(.52) : crown_reach) * (1 + olive_random_signed(&random) * .16) * growth
        crown_rise := inner_stem ? f32(.70) : f32(.56 + f32(ring_index % 5) * .018)
        rise := (is_tree ? f32(.56) : crown_rise) * (1 + olive_random_signed(&random) * .14) * growth
        bow := tangent * olive_random_signed(&random) * .075 * growth
        for segment_index in 0 ..< segment_count {
            progress := f32(segment_index + 1) / f32(segment_count)
            // Hydrangea shoots bow outward early, then turn upward into a
            // clipped crown envelope. Explicit targets avoid the repeated
            // rising direction that produced a bare V-shaped candelabrum.
            outward_progress := math.sin(progress * math.PI * .5)
            height_progress := progress * (.78 + progress * .22)
            next :=
                stem_origin +
                radial * reach * outward_progress +
                bow * math.sin(progress * math.PI) +
                lsystem.Vec3{0, rise * height_progress, 0}
            direction := linalg.normalize0(next - position)
            end_radius := radius * .72
            append(&result.plant.segments, lsystem.Segment{position, next, radius, end_radius, segment_index + 1})
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
                lsystem.Leaf {
                    position = leaf_position,
                    forward = leaf_forward,
                    up = leaf_normal,
                    depth = segment_index + 1,
                },
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
                    forward  = linalg.normalize0(radial * .12 + lsystem.Vec3{0, .99, 0}),
                    up       = radial,
                    depth    = -9,
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
        append(&result.plant.segments, lsystem.Segment{cordon_point, spur_tip, .011, .008, -22})

        active_threshold := .38 + clamp(maturity, f32(0), f32(1)) * .57
        if f32(lsystem.random_next(&random) % 10_000) / 10_000 > active_threshold do continue
        annual_count := detail == .Near && lsystem.random_next(&random) % 5 == 0 ? 2 : 1
        for annual_index in 0 ..< annual_count {
            phytomer_count :=
                detail == .Near ? 6 + int(lsystem.random_next(&random) % 4) : detail == .Medium ? 5 + int(lsystem.random_next(&random) % 3) : 4 + int(lsystem.random_next(&random) % 2)
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
                internode_length :=
                    (.060 + f32(phytomer_index) * .004) * growth * (1 + olive_random_signed(&random) * .10)
                direction := linalg.normalize0(lsystem.Vec3{lateral_velocity, 1, depth_velocity})
                next := position + direction * internode_length
                append(&result.plant.segments, lsystem.Segment{position, next, radius, radius * .86, -21})
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
            meander :=
                olive_random_signed(&random) * .085 + f32(math.sin(f64(progress * 5.1 + lateral_target * 2.3))) * .035
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
