package plants

import lsystem "../lsystem"
import "core:math"
import "core:math/linalg"

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
            reach := .27 + f32(lsystem.random_next(&root_random) % 7) * .008
            radial := lsystem.Vec3{math.cos(angle), 0, math.sin(angle)}
            tangent := lsystem.Vec3{-radial[2], 0, radial[0]}
            bow := olive_random_signed(&root_random) * reach * .16
            root_start := radial * .035 + lsystem.Vec3{0, .030, 0}
            root_mid := radial * reach * .58 + tangent * bow + lsystem.Vec3{0, -.006, 0}
            // Finish below grade with a useful radius. The old exposed,
            // near-zero tip read as a wooden spike laid on the ground.
            root_end := radial * reach + tangent * bow * .45 + lsystem.Vec3{0, -.030, 0}
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
                    radius_end = trunk_base_radius * .10,
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
        origin_index := clamp(trunk_segments - 2 + leader_index % 3, 1, trunk_segments)
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

generate_skeleton_stage :: proc(
    config: Generate_Config,
    profile: Profile,
    maturity: f32,
    iterations, detail_reduction, expansion_segment_limit: int,
) -> (
    lsystem.Interpret_Result,
    Generate_Error,
) {
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
    } else if config.species == .Bougainvillea {
        interpreted = bougainvillea_skeleton(config.seed, maturity, config.detail)
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
            return {}, .Expansion_Failed
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
    return interpreted, .None
}
