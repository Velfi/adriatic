package plants

import lsystem "../lsystem"
import "core:math"
import "core:math/linalg"

generate :: proc(config: Generate_Config) -> Generate_Result {
    result: Generate_Result
    if int(config.species) < 0 || int(config.species) >= SPECIES_COUNT {
        result.error = .Invalid_Species
        return result
    }
    habit := config.habit
    if habit == .Free_Standing &&
       (config.species == .Bougainvillea ||
               config.species == .Grapevine ||
               config.species == .Wisteria ||
               config.species == .Climbing_Rose ||
               config.species == .Star_Jasmine) {
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
    growth_iterations := int(math.ceil(raw_iterations))
    iterations := clamp(growth_iterations - detail_reduction, 0, profile.base_iterations)
    generation_progress := raw_iterations - math.floor(raw_iterations)
    if raw_iterations > 0 && generation_progress < .0001 do generation_progress = 1
    segment_limit, attachment_limit := limits(config.detail)
    if climbing {
        segment_limit, attachment_limit = climbing_density_limits(config.detail, config.support)
    }
    expansion_segment_limit := segment_limit
    if climbing {
        catalog_segment_limit, _ := limits(config.detail)
        expansion_segment_limit = max(expansion_segment_limit, catalog_segment_limit)
    }
    interpreted, skeleton_error := generate_skeleton_stage(
        config,
        profile,
        maturity,
        iterations,
        detail_reduction,
        expansion_segment_limit,
    )
    if skeleton_error != .None {
        result.error = skeleton_error
        return result
    }
    if interpreted.error != .None {
        lsystem.destroy_plant(&interpreted.plant)
        result.error = .Interpretation_Failed
        return result
    }
    if iterations > 0 &&
       config.species != .Prickly_Pear &&
       config.species != .Golden_Barrel &&
       config.species != .Agave &&
       config.species != .Aloe &&
       config.species != .Aeonium &&
       config.species != .Echeveria &&
       config.species != .Jade_Plant &&
       config.species != .Stonecrop &&
       config.species != .Blue_Chalk_Sticks &&
       config.species != .Golden_Torch_Cactus &&
       config.species != .Agapanthus &&
       config.species != .Strawberry_Tree &&
       config.species != .Rosemary &&
       config.species != .Pelargonium &&
       config.species != .Hydrangea_Bush &&
       config.species != .Hydrangea_Tree &&
       config.species != .Star_Jasmine &&
       config.species != .Wisteria &&
       config.species != .Climbing_Rose &&
       config.species != .Lavender &&
       config.species != .Thyme &&
       config.species != .Sage {
        sprout_newest_generation(&interpreted.plant, generation_progress)
    }
    if config.species == .Myrtle || config.species == .Mastic || config.species == .Sage {
        myrtle_clothe_scaffold(&interpreted.plant)
    }
    if config.species == .Lavender do lavender_clothe_scaffold(&interpreted.plant)
    if config.species == .Stone_Pine do stone_pine_clothe_scaffold(&interpreted.plant, config.detail)
    source_segment_limit := climbing ? max(segment_limit / 6, 1) : segment_limit
    if climbing && len(interpreted.plant.segments) > source_segment_limit {
        source_segments := interpreted.plant.segments
        thinned_segments := make([dynamic]lsystem.Segment, 0, source_segment_limit)
        for retained_index in 0 ..< source_segment_limit {
            source_index := retained_index * len(source_segments) / source_segment_limit
            append(&thinned_segments, source_segments[source_index])
        }
        delete(source_segments)
        interpreted.plant.segments = thinned_segments
    } else if len(interpreted.plant.segments) > source_segment_limit {
        lsystem.destroy_plant(&interpreted.plant)
        result.error = .Segment_Limit
        return result
    }
    if config.species == .Italian_Cypress {
        for segment, segment_index in interpreted.plant.segments {
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
            if segment.depth == 1 && config.detail == .Near {
                append(
                    &interpreted.plant.leaves,
                    lsystem.Leaf {
                        position = segment.start + (segment.end - segment.start) * .78,
                        forward = direction,
                        up = {1, 0, 0},
                        depth = segment.depth,
                    },
                )
                branch_interval := segment_index / 17
                relative_interval := f32(branch_interval) / 18
                lower_density := clamp((.46 - relative_interval) / .40, f32(0), f32(1))
                density_hash := (config.seed + 1) * 0x9e3779b97f4a7c15 ~ u64(segment_index + 23) * 0xbf58476d1ce4e5b9
                density_hash = (density_hash ~ (density_hash >> 29)) * 0x94d049bb133111eb
                if f32(density_hash % 10_000) < lower_density * 10_000 {
                    append(
                        &interpreted.plant.leaves,
                        lsystem.Leaf {
                            position = segment.start + (segment.end - segment.start) * .28,
                            forward = direction,
                            up = {1, 0, 0},
                            depth = segment.depth,
                        },
                    )
                }
            }
            if segment.depth == 0 && config.detail != .Far {
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
    if climbing && len(interpreted.plant.leaves) * max(cluster_size, 1) > attachment_limit {
        source_leaves := interpreted.plant.leaves
        leaf_limit := max(attachment_limit / max(cluster_size, 1), 1)
        thinned_leaves := make([dynamic]lsystem.Leaf, 0, leaf_limit)
        for retained_index in 0 ..< leaf_limit {
            source_index := retained_index * len(source_leaves) / leaf_limit
            append(&thinned_leaves, source_leaves[source_index])
        }
        delete(source_leaves)
        interpreted.plant.leaves = thinned_leaves
    }
    for leaf, index in interpreted.plant.leaves {
        kind := generated_attachment_kind(config.species, config.seed, index, maturity, config.detail, leaf.depth)
        leaf_cluster_size := cluster_size
        if config.species == .Italian_Cypress {
            leaf_cluster_size = cypress_generated_cluster_size(config.detail, maturity, config.seed, index, leaf.depth)
        } else if config.species == .Lemon && leaf.depth >= 2 {
            leaf_cluster_size = 1
        }
        if config.species == .Grapevine && kind != .Leaf {
            attachment_count += 2
        } else if config.species == .Italian_Cypress && kind == .Fruit {
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
        result.plant.wood = {
            radial_irregularity = .075,
            twist               = .42,
        }
    } else if config.species == .Lemon {
        result.plant.wood = {
            radial_irregularity = .055,
            twist               = .28,
        }
    }
    result.plant.root_kind = climbing && config.support.planter ? .Planter : .Soil
    result.plant.wind_compliance = woody_wind_compliance(config.species, maturity)
    if climbing do result.plant.support_signature = support_hash(config.support^)
    climbing_route_samples := climbing ? 6 : 1
    if config.species == .Grapevine do climbing_route_samples = 1
    routed_segment_capacity := len(interpreted.plant.segments) * climbing_route_samples
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
    extra_route_demand := 0
    maximum_route_samples := config.detail == .Near ? 12 : config.detail == .Medium ? 9 : 6
    if config.species == .Grapevine do maximum_route_samples = 1
    if climbing && maximum_route_samples > climbing_route_samples {
        for source in interpreted.plant.segments {
            start := lsystem.Vec3 {
                source.start[0] * profile.width_scale,
                source.start[1] * profile.height_scale,
                source.start[2] * profile.width_scale,
            }
            end := lsystem.Vec3 {
                source.end[0] * profile.width_scale,
                source.end[1] * profile.height_scale,
                source.end[2] * profile.width_scale,
            }
            routed_start := route_point(
                start,
                config.support,
                climbing_height,
                climbing_half_width,
                habit,
                source.depth,
            )
            routed_end := route_point(end, config.support, climbing_height, climbing_half_width, habit, source.depth)
            delta := routed_end - routed_start
            projected_length := math.sqrt(linalg.dot(delta, delta))
            desired_samples := clamp(
                int(math.ceil(projected_length / .32)),
                climbing_route_samples,
                maximum_route_samples,
            )
            extra_route_demand += desired_samples - climbing_route_samples
        }
    }
    base_routed_count := len(interpreted.plant.segments) * climbing_route_samples
    extra_route_budget := min(extra_route_demand, max(segment_limit - base_routed_count, 0))
    extra_demand_seen, extra_samples_awarded := 0, 0
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
            route_samples := climbing_route_samples
            if extra_route_demand > 0 && extra_route_budget > 0 {
                routed_start := route_point(
                    segment.start,
                    config.support,
                    climbing_height,
                    climbing_half_width,
                    habit,
                    segment.depth,
                )
                routed_end := route_point(
                    segment.end,
                    config.support,
                    climbing_height,
                    climbing_half_width,
                    habit,
                    segment.depth,
                )
                delta := routed_end - routed_start
                projected_length := math.sqrt(linalg.dot(delta, delta))
                desired_samples := clamp(
                    int(math.ceil(projected_length / .32)),
                    climbing_route_samples,
                    maximum_route_samples,
                )
                extra_demand_seen += desired_samples - climbing_route_samples
                target_awarded := extra_demand_seen * extra_route_budget / extra_route_demand
                route_samples += target_awarded - extra_samples_awarded
                extra_samples_awarded = target_awarded
            }
            previous := route_point(
                segment.start,
                config.support,
                climbing_height,
                climbing_half_width,
                habit,
                segment.depth,
            )
            for sample in 1 ..= route_samples {
                t := f32(sample) / f32(route_samples)
                source_point := segment.start + (segment.end - segment.start) * t
                current := route_point(
                    source_point,
                    config.support,
                    climbing_height,
                    climbing_half_width,
                    habit,
                    segment.depth,
                )
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
        if climbing do position = route_point(position, config.support, climbing_height, climbing_half_width, habit, leaf.depth)
        if config.species == .Grapevine && habit == .Trellised {
            hash := (config.seed + 1) * 0x9e3779b97f4a7c15 ~ u64(index + 61) * 0xbf58476d1ce4e5b9
            hash = (hash ~ (hash >> 30)) * 0x94d049bb133111eb
            signed_offset := f32(hash % 10_001) / 5_000 - 1
            position[1] = clamp(position[1] + signed_offset * .11, f32(.03), config.support.height * .98)
        }
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
        } else if config.species == .Lemon && leaf.depth >= 2 {
            attachment_cluster_size = 1
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
        if config.species == .Grapevine && generated_kind != .Leaf {
            companion_traits := generated_leaf_traits(config.species, variant, maturity, config.detail)
            append(
                &result.plant.attachments,
                Attachment {
                    kind = .Leaf,
                    stage = .None,
                    position = position,
                    forward = forward,
                    up = up,
                    depth = leaf.depth,
                    variant = variant,
                    leaf = companion_traits,
                },
            )
            update_leaf_bounds(&result.plant.bounds, position, forward, up, companion_traits, &first)
        }
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
                    clustered_position -= forward * clustered_traits.length * (.72 + f32(cluster_index - 1) * .58)
                    clustered_position[1] = max(clustered_position[1], 0)
                } else if config.species == .Stone_Pine {
                    clustered_position -= forward * clustered_traits.length * (.16 + f32(cluster_index - 1) * .14)
                    clustered_position[1] = max(clustered_position[1], 0)
                }
                if climbing {
                    clustered_position[0] = clamp(
                        clustered_position[0],
                        -config.support.width * .48,
                        config.support.width * .48,
                    )
                    clustered_position[1] = clamp(clustered_position[1], f32(0), config.support.height * .96)
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
    if habit == .Wall_Trained && len(result.plant.segments) > 0 {
        cadence_density := config.detail == .Near ? f32(16) : config.detail == .Medium ? f32(8) : f32(4)
        cadence_ceiling := int(math.ceil(config.support.width * config.support.height * cadence_density))
        eligible_count := 0
        minimum_height := config.support.height * .10
        primary_canopy_height := config.support.height * .42
        for segment in result.plant.segments {
            midpoint := (segment.start + segment.end) * .5
            midpoint_y := midpoint[1]
            eligible := (segment.depth >= 1 && midpoint_y >= minimum_height) || midpoint_y >= primary_canopy_height
            for exclusion in config.support.exclusions {
                if midpoint[0] >= exclusion.minimum_x &&
                   midpoint[0] <= exclusion.maximum_x &&
                   midpoint[1] >= exclusion.minimum_y &&
                   midpoint[1] <= exclusion.maximum_y {
                    eligible = false
                    break
                }
            }
            if eligible do eligible_count += 1
        }
        needed := min(min(cadence_ceiling, (eligible_count + 1) / 2), attachment_limit - len(result.plant.attachments))
        if needed > 0 {
            accumulator := 0
            added := 0
            for segment, segment_index in result.plant.segments {
                position := (segment.start + segment.end) * .5
                midpoint_y := position[1]
                eligible := (segment.depth >= 1 && midpoint_y >= minimum_height) || midpoint_y >= primary_canopy_height
                for exclusion in config.support.exclusions {
                    if position[0] >= exclusion.minimum_x &&
                       position[0] <= exclusion.maximum_x &&
                       position[1] >= exclusion.minimum_y &&
                       position[1] <= exclusion.maximum_y {
                        eligible = false
                        break
                    }
                }
                if !eligible do continue
                accumulator += needed
                if accumulator < eligible_count do continue
                accumulator -= eligible_count
                direction := linalg.normalize0(segment.end - segment.start)
                if linalg.dot(direction, direction) < .001 do continue
                variant := u8((config.seed + u64(segment_index * 13 + added * 7)) % 4)
                traits := generated_leaf_traits(config.species, variant, maturity, config.detail)
                forward, up := attachment_frame(direction, {0, 0, 1}, profile, true)
                append(
                    &result.plant.attachments,
                    Attachment {
                        kind = .Leaf,
                        position = position,
                        forward = forward,
                        up = up,
                        depth = segment.depth,
                        variant = variant,
                        leaf = traits,
                    },
                )
                update_bounds(&result.plant.bounds, position, &first)
                update_leaf_bounds(&result.plant.bounds, position, forward, up, traits, &first)
                added += 1
                if added == needed do break
            }
        }
    }
    lsystem.destroy_plant(&interpreted.plant)
    return result
}
