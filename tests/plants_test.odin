package tests

import branch_mesh "../packages/branch_mesh"
import leaf_mesh "../packages/leaf_mesh"
import plants "../packages/plants"
import "core:math"
import "core:math/linalg"
import "core:testing"

plant_support :: proc(support: ^plants.Support_Surface, exclusions: ^[2]plants.Rect) {
    exclusions[0] = {-1.1, .6, 1.1, 2.8}
    exclusions[1] = {-2.8, 3.3, -.6, 5.2}
    support^ = {
        width      = 8,
        height     = 7,
        plane_z    = .12,
        root_x     = -2.7,
        planter    = true,
        exclusions = exclusions[:],
    }
}

@(test)
plant_catalog_generates_every_species_at_every_detail :: proc(t: ^testing.T) {
    support: plants.Support_Surface
    exclusions: [2]plants.Rect
    plant_support(&support, &exclusions)
    for species_index in 0 ..< plants.SPECIES_COUNT {
        species := plants.Species(species_index)
        for detail in plants.Detail_Level {
            habit := plants.default_habit(species)
            support_pointer: ^plants.Support_Surface
            if habit != .Free_Standing do support_pointer = &support
            result := plants.generate(
                {
                    species = species,
                    seed = 73,
                    maturity = 1,
                    detail = detail,
                    habit = habit,
                    support = support_pointer,
                },
            )
            testing.expectf(
                t,
                result.error == .None,
                "%s detail=%v generation error=%v",
                plants.species_name(species),
                detail,
                result.error,
            )
            testing.expectf(
                t,
                len(result.plant.segments) > 0,
                "%s detail=%v generated no segments",
                plants.species_name(species),
                detail,
            )
            segment_limit, attachment_limit := plants.limits(detail)
            if habit != .Free_Standing {
                segment_limit, attachment_limit = plants.climbing_density_limits(detail, &support)
            }
            testing.expectf(
                t,
                len(result.plant.segments) <= segment_limit,
                "%s detail=%v segments=%d limit=%d",
                plants.species_name(species),
                detail,
                len(result.plant.segments),
                segment_limit,
            )
            testing.expectf(
                t,
                len(result.plant.attachments) <= attachment_limit,
                "%s detail=%v attachments=%d limit=%d",
                plants.species_name(species),
                detail,
                len(result.plant.attachments),
                attachment_limit,
            )
            for segment in result.plant.segments {
                testing.expect(t, segment.radius_start > 0)
                testing.expect(t, segment.radius_end > 0)
                for value in segment.start do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
                for value in segment.end do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
            }
            for attachment in result.plant.attachments {
                if attachment.kind == .Leaf {
                    testing.expect(
                        t,
                        int(attachment.leaf.shape) >= 0 && int(attachment.leaf.shape) < leaf_mesh.SHAPE_COUNT,
                    )
                    testing.expect(t, attachment.leaf.length > 0)
                    testing.expect(t, attachment.leaf.width > 0)
                }
            }
            plants.destroy(&result)
        }
    }
}

@(test)
olive_source_leaves_use_both_sides_of_their_shoots :: proc(t: ^testing.T) {
    // Juvenile plants retain one card per source station, exposing any bias
    // that mature Near and Medium plants conceal with opposite pairs.
    for seed in u64(1) ..= 8 {
        result := plants.generate(
            {species = .Olive, seed = seed, maturity = .20, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)

        positive, negative := 0, 0
        for attachment in result.plant.attachments {
            if attachment.kind != .Leaf do continue
            nearest_distance := f32(1e30)
            nearest_side: [3]f32
            for segment in result.plant.segments {
                direction := segment.end - segment.start
                length_squared := linalg.dot(direction, direction)
                if length_squared < .000001 do continue
                fraction := clamp(
                    linalg.dot(attachment.position - segment.start, direction) / length_squared,
                    f32(0),
                    f32(1),
                )
                nearest := segment.start + direction * fraction
                offset := attachment.position - nearest
                distance := linalg.dot(offset, offset)
                if distance >= nearest_distance do continue
                side := linalg.normalize0(linalg.cross(linalg.normalize0(direction), [3]f32{0, 1, 0}))
                if linalg.dot(side, side) < .2 do side = {1, 0, 0}
                nearest_distance = distance
                nearest_side = side
            }
            facing := linalg.dot(attachment.forward, nearest_side)
            if facing > .25 do positive += 1
            if facing < -.25 do negative += 1
        }
        testing.expectf(t, positive > 0, "olive seed=%d has no leaves on the positive shoot side", seed)
        testing.expectf(t, negative > 0, "olive seed=%d has no leaves on the negative shoot side", seed)
    }
}

@(test)
climbing_limits_scale_with_support_area_not_a_global_count :: proc(t: ^testing.T) {
    small := plants.Support_Surface {
        width  = 2,
        height = 3,
    }
    large := plants.Support_Surface {
        width  = 4,
        height = 6,
    }
    for detail in plants.Detail_Level {
        small_segments, small_attachments := plants.climbing_density_limits(detail, &small)
        large_segments, large_attachments := plants.climbing_density_limits(detail, &large)
        testing.expect_value(t, large_segments, small_segments * 4)
        testing.expect_value(t, large_attachments, small_attachments * 4)
    }
}

@(test)
climbing_generation_fills_supports_within_area_density :: proc(t: ^testing.T) {
    supports := [2]plants.Support_Surface {
        {width = 2, height = 3, plane_z = .1, root_x = 0},
        {width = 8, height = 7, plane_z = .1, root_x = 0},
    }
    segment_counts: [2]int
    for &support, index in supports {
        result := plants.generate(
            {
                species = .Bougainvillea,
                seed = 73,
                maturity = 1,
                detail = .Near,
                habit = .Wall_Trained,
                support = &support,
            },
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        segment_limit, attachment_limit := plants.climbing_density_limits(.Near, &support)
        testing.expect(t, len(result.plant.segments) <= segment_limit)
        testing.expect(t, len(result.plant.attachments) <= attachment_limit)
        testing.expect_value(t, len(result.plant.segments) % 6, 0)
        segment_counts[index] = len(result.plant.segments)
    }
    testing.expect(t, segment_counts[1] > segment_counts[0])
}

@(test)
star_jasmine_spreads_a_connected_flowering_fan_across_its_wall :: proc(t: ^testing.T) {
    support := plants.Support_Surface {
        width   = 8,
        height  = 7,
        plane_z = .1,
        root_x  = 0,
    }
    result := plants.generate(
        {species = .Star_Jasmine, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    width := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
    height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
    testing.expect(t, width > support.width * .62)
    testing.expect(t, height > support.height * .88)
    testing.expect(t, result.plant.bounds.minimum[0] < -support.width * .24)
    testing.expect(t, result.plant.bounds.maximum[0] > support.width * .24)
    segment_limit, _ := plants.climbing_density_limits(.Near, &support)
    testing.expect(t, len(result.plant.segments) >= 270)
    testing.expect(t, len(result.plant.segments) <= segment_limit)
    leaf_count, flower_count := 0, 0
    for attachment in result.plant.attachments {
        if attachment.kind == .Leaf do leaf_count += 1
        if attachment.kind == .Flower do flower_count += 1
    }
    testing.expect(t, leaf_count > 0)
    testing.expect(t, flower_count > 0)
}

@(test)
wisteria_spreads_woody_flowering_canes_across_its_wall :: proc(t: ^testing.T) {
    support := plants.Support_Surface {
        width   = 8,
        height  = 7,
        plane_z = .1,
        root_x  = 0,
    }
    result := plants.generate(
        {species = .Wisteria, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    width := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
    height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
    testing.expect(t, width > support.width * .62)
    testing.expect(t, height > support.height * .88)
    flower_count := 0
    maximum_radius := f32(0)
    for attachment in result.plant.attachments {
        if attachment.kind == .Flower do flower_count += 1
    }
    for segment in result.plant.segments do maximum_radius = max(maximum_radius, segment.radius_start)
    testing.expect(t, flower_count > 0)
    testing.expect(t, maximum_radius > .018)
}

@(test)
climbing_rose_spreads_flowering_canes_across_its_wall :: proc(t: ^testing.T) {
    support := plants.Support_Surface {
        width   = 8,
        height  = 7,
        plane_z = .1,
        root_x  = 0,
    }
    result := plants.generate(
        {species = .Climbing_Rose, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    width := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
    height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
    testing.expect(t, width > support.width * .62)
    testing.expect(t, height > support.height * .88)
    flower_count := 0
    for attachment in result.plant.attachments {
        if attachment.kind == .Flower do flower_count += 1
    }
    testing.expect(t, flower_count > 0)
}

@(test)
bougainvillea_main_leader_samples_one_continuous_root_to_tip_cane :: proc(t: ^testing.T) {
    support := plants.Support_Surface {
        width   = 8,
        height  = 7,
        plane_z = .1,
        root_x  = 0,
    }
    result := plants.generate(
        {species = .Bougainvillea, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)

    previous := plants.main_leader_sample(&result.plant, 0)
    for sample in 1 ..= 20 {
        current := plants.main_leader_sample(&result.plant, f32(sample) / 20)
        testing.expectf(
            t,
            current[1] + .0001 >= previous[1],
            "leader moved downward from %.3f to %.3f at sample %d",
            previous[1],
            current[1],
            sample,
        )
        previous = current
    }
    testing.expect(t, previous[1] >= support.height * .90)
}

@(test)
mature_bougainvillea_clothes_its_canes_with_dense_short_laterals :: proc(t: ^testing.T) {
    support := plants.Support_Surface {
        width   = 8,
        height  = 7,
        plane_z = .1,
        root_x  = 0,
    }
    result := plants.generate(
        {species = .Bougainvillea, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)

    lateral_segment_count := 0
    for segment in result.plant.segments {
        if segment.depth >= 8 do lateral_segment_count += 1
    }
    testing.expectf(t, lateral_segment_count >= 450, "routed flowering lateral segments: %d", lateral_segment_count)
    testing.expectf(
        t,
        len(result.plant.attachments) >= 900,
        "mature bougainvillea attachments: %d",
        len(result.plant.attachments),
    )
    unaccompanied_count := 0
    for attachment in result.plant.attachments {
        if attachment.kind == .Leaf do continue
        accompanied := false
        for candidate in result.plant.attachments {
            if candidate.kind != .Leaf do continue
            delta := candidate.position - attachment.position
            if linalg.dot(delta, delta) <= 1e-8 {
                accompanied = true
                break
            }
        }
        if !accompanied do unaccompanied_count += 1
    }
    testing.expectf(t, unaccompanied_count == 0, "flowering or thorn sites without foliage: %d", unaccompanied_count)
}

@(test)
plant_species_assign_distinct_leaf_semantics :: proc(t: ^testing.T) {
    grape := plants.leaf_traits(.Grapevine, 0, 1)
    fig := plants.leaf_traits(.Fig, 0, 1)
    rosemary := plants.leaf_traits(.Rosemary, 0, 1)
    testing.expect_value(t, grape.shape, leaf_mesh.Shape.Grapevine)
    testing.expect_value(t, fig.shape, leaf_mesh.Shape.Fig)
    testing.expect_value(t, rosemary.shape, leaf_mesh.Shape.Lanceolate)
    testing.expect(t, fig.width > grape.width)
    testing.expect(t, rosemary.length < grape.length)
}

@(test)
cacti_and_succulents_use_distinct_fleshy_architectures :: proc(t: ^testing.T) {
    species := [4]plants.Species{.Prickly_Pear, .Golden_Barrel, .Agave, .Aloe}
    for plant_species in species {
        near := plants.generate(
            {species = plant_species, seed = 0xcac71, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        far := plants.generate(
            {species = plant_species, seed = 0xcac71, maturity = 1, detail = .Far, habit = .Free_Standing},
        )
        defer plants.destroy(&near)
        defer plants.destroy(&far)
        testing.expectf(t, near.error == .None, "%s failed near generation", plants.species_name(plant_species))
        testing.expectf(t, far.error == .None, "%s failed far generation", plants.species_name(plant_species))
        testing.expect(t, len(near.plant.segments) > 0)
        testing.expect(t, len(near.plant.attachments) >= len(far.plant.attachments))
        testing.expect(t, len(far.plant.attachments) > 0)
    }

    barrel := plants.generate(
        {species = .Golden_Barrel, seed = 0xcac71, maturity = 1, detail = .Near, habit = .Free_Standing},
    )
    agave := plants.generate({species = .Agave, seed = 0xcac71, maturity = 1, detail = .Near, habit = .Free_Standing})
    aloe := plants.generate({species = .Aloe, seed = 0xcac71, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&barrel)
    defer plants.destroy(&agave)
    defer plants.destroy(&aloe)
    testing.expect_value(t, len(barrel.plant.attachments), 20)
    testing.expect(t, len(aloe.plant.attachments) > len(agave.plant.attachments))
    testing.expect(t, plants.leaf_traits(.Agave, 0, 1).length > plants.leaf_traits(.Aloe, 0, 1).length)
    testing.expect(t, plants.leaf_traits(.Golden_Barrel, 0, 1).cup > plants.leaf_traits(.Agave, 0, 1).cup)
}

@(test)
expanded_succulent_catalog_preserves_six_distinct_architectures :: proc(t: ^testing.T) {
    species := [6]plants.Species {
        .Aeonium,
        .Echeveria,
        .Jade_Plant,
        .Stonecrop,
        .Blue_Chalk_Sticks,
        .Golden_Torch_Cactus,
    }
    near: [6]plants.Generate_Result
    defer for &result in near do plants.destroy(&result)
    for plant_species, index in species {
        near[index] = plants.generate(
            {species = plant_species, seed = 0x5acc, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        far := plants.generate(
            {species = plant_species, seed = 0x5acc, maturity = 1, detail = .Far, habit = .Free_Standing},
        )
        defer plants.destroy(&far)
        testing.expectf(t, near[index].error == .None, "%s failed near generation", plants.species_name(plant_species))
        testing.expectf(t, far.error == .None, "%s failed far generation", plants.species_name(plant_species))
        testing.expect(t, len(near[index].plant.segments) > 0)
        testing.expect(t, len(near[index].plant.attachments) > 0)
        testing.expect(t, len(near[index].plant.attachments) >= len(far.plant.attachments))
        testing.expect(t, plants.leaf_traits(plant_species, 0, 1).thickness > 0)
    }

    aeonium := &near[0].plant
    echeveria := &near[1].plant
    jade := &near[2].plant
    stonecrop := &near[3].plant
    chalk := &near[4].plant
    torch := &near[5].plant
    testing.expect(t, len(aeonium.segments) >= 5)
    testing.expect(t, len(echeveria.attachments) > len(echeveria.segments) * 20)
    testing.expect_value(t, len(jade.attachments), len(jade.segments) * 2)
    stonecrop_width := stonecrop.bounds.maximum[0] - stonecrop.bounds.minimum[0]
    stonecrop_height := stonecrop.bounds.maximum[1] - stonecrop.bounds.minimum[1]
    testing.expect(t, stonecrop_width > stonecrop_height * 2)
    testing.expect(t, len(chalk.attachments) >= 20)
    torch_width := torch.bounds.maximum[0] - torch.bounds.minimum[0]
    torch_height := torch.bounds.maximum[1] - torch.bounds.minimum[1]
    testing.expect(t, torch_height > torch_width * 2)
}

@(test)
mediterranean_broadleaf_catalog_has_distinct_silhouettes_and_leaves :: proc(t: ^testing.T) {
    species := [4]plants.Species{.Holm_Oak, .Oriental_Plane, .European_Hackberry, .White_Poplar}
    expected_shapes := [4]leaf_mesh.Shape{.Ovate, .Lobed, .Ovate, .Deltoid}
    for tree, index in species {
        result := plants.generate({species = tree, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
        defer plants.destroy(&result)
        testing.expectf(t, result.error == .None, "%s failed to generate", plants.species_name(tree))
        testing.expect(t, len(result.plant.segments) > 20)
        testing.expect(t, len(result.plant.attachments) > 20)
        testing.expect_value(t, plants.leaf_traits(tree, 0, 1).shape, expected_shapes[index])
    }

    oak := plants.profile_for(.Holm_Oak)
    plane := plants.profile_for(.Oriental_Plane)
    hackberry := plants.profile_for(.European_Hackberry)
    poplar := plants.profile_for(.White_Poplar)
    testing.expect(t, oak.width_scale > plane.width_scale)
    testing.expect(t, plane.width_scale > hackberry.width_scale)
    testing.expect(t, poplar.height_scale > plane.height_scale)
    testing.expect_value(t, plants.leaf_cluster_size(.Oriental_Plane, .Near, 1), 1)
    testing.expect_value(t, plants.leaf_cluster_size(.European_Hackberry, .Near, 1), 2)
    testing.expect_value(t, plants.leaf_cluster_size(.White_Poplar, .Near, 1), 2)
}

@(test)
mature_white_poplar_keeps_an_ascending_but_substantial_crown_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(60) ..= 80 {
        result := plants.generate(
            {species = .White_Poplar, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        width_x := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
        width_z := result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2]
        width := max(width_x, width_z)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        testing.expect(t, width > height * .58)
        testing.expect(t, width < height * 1.10)
        testing.expect(t, min(width_x, width_z) > width * .58)
    }
}

@(test)
mature_holm_oak_keeps_a_dense_rounded_crown_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(60) ..= 80 {
        result := plants.generate(
            {species = .Holm_Oak, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        width_x := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
        width_z := result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2]
        width := max(width_x, width_z)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        crown_minimum_x, crown_minimum_y, crown_minimum_z: f32
        crown_maximum_x, crown_maximum_y, crown_maximum_z: f32
        crown_first := true
        for attachment in result.plant.attachments {
            if attachment.kind != .Leaf do continue
            if crown_first {
                crown_minimum_x, crown_minimum_y, crown_minimum_z =
                    attachment.position[0], attachment.position[1], attachment.position[2]
                crown_maximum_x, crown_maximum_y, crown_maximum_z =
                    attachment.position[0], attachment.position[1], attachment.position[2]
                crown_first = false
            } else {
                crown_minimum_x = min(crown_minimum_x, attachment.position[0])
                crown_minimum_y = min(crown_minimum_y, attachment.position[1])
                crown_minimum_z = min(crown_minimum_z, attachment.position[2])
                crown_maximum_x = max(crown_maximum_x, attachment.position[0])
                crown_maximum_y = max(crown_maximum_y, attachment.position[1])
                crown_maximum_z = max(crown_maximum_z, attachment.position[2])
            }
        }
        crown_width := max(crown_maximum_x - crown_minimum_x, crown_maximum_z - crown_minimum_z)
        crown_height := crown_maximum_y - crown_minimum_y
        testing.expect(t, width > height * .90)
        testing.expect(t, width < height * 1.80)
        testing.expect(t, min(width_x, width_z) > width * .60)
        testing.expect(t, crown_height > 0)
        testing.expect(t, crown_width < crown_height * 2.20)
        testing.expect(t, len(result.plant.attachments) > len(result.plant.segments) * 2)
    }
}

@(test)
plant_leaf_density_scales_by_species_and_detail :: proc(t: ^testing.T) {
    testing.expect(t, plants.leaf_cluster_size(.Italian_Cypress, .Near, 1) > plants.leaf_cluster_size(.Fig, .Near, 1))
    testing.expect_value(t, plants.leaf_cluster_size(.Olive, .Near, 1), 2)
    testing.expect_value(t, plants.leaf_cluster_size(.Olive, .Medium, 1), 2)
    testing.expect_value(t, plants.leaf_cluster_size(.Olive, .Far, 1), 1)
    near := plants.generate({species = .Olive, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
    far := plants.generate({species = .Olive, seed = 73, maturity = 1, detail = .Far, habit = .Free_Standing})
    defer plants.destroy(&near)
    defer plants.destroy(&far)
    testing.expect_value(t, near.error, plants.Generate_Error.None)
    testing.expect_value(t, far.error, plants.Generate_Error.None)
    near_leaves, far_leaves := 0, 0
    for attachment in near.plant.attachments {
        if attachment.kind == .Leaf do near_leaves += 1
    }
    for attachment in far.plant.attachments {
        if attachment.kind == .Leaf do far_leaves += 1
    }
    testing.expect(t, near_leaves > far_leaves)
}

@(test)
mature_olive_keeps_a_broad_leafy_crown_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(60) ..= 80 {
        result := plants.generate(
            {species = .Olive, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        width := max(
            result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0],
            result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2],
        )
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        testing.expect(t, width > height * 1.1)
        testing.expect(t, len(result.plant.attachments) > len(result.plant.segments) * 2)
    }
}

@(test)
mature_lemon_keeps_a_compact_leafy_crown_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(60) ..= 80 {
        result := plants.generate(
            {species = .Lemon, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        width_x := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
        width_z := result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2]
        width := max(width_x, width_z)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        testing.expect(t, width > height * .72)
        testing.expect(t, min(width_x, width_z) > height * .56)
        testing.expect(t, len(result.plant.attachments) > len(result.plant.segments) * 2)
        crown_center_x := (result.plant.bounds.minimum[0] + result.plant.bounds.maximum[0]) * .5
        crown_center_z := (result.plant.bounds.minimum[2] + result.plant.bounds.maximum[2]) * .5
        testing.expect(t, math.abs(crown_center_x) < width * .14)
        testing.expect(t, math.abs(crown_center_z) < width * .14)
        testing.expect(t, result.plant.wood.radial_irregularity > 0)
        testing.expect(t, result.plant.wood.twist > 0)
        fruit_count := 0
        for attachment in result.plant.attachments {
            if attachment.kind != .Fruit do continue
            fruit_count += 1
            testing.expect(t, attachment.depth >= 2)
        }
        testing.expect(t, fruit_count >= 4)
    }
}

@(test)
mature_fig_keeps_a_balanced_spreading_vase_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(60) ..= 80 {
        result := plants.generate({species = .Fig, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing})
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        width_x := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
        width_z := result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2]
        width := max(width_x, width_z)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        center_x := (result.plant.bounds.minimum[0] + result.plant.bounds.maximum[0]) * .5
        center_z := (result.plant.bounds.minimum[2] + result.plant.bounds.maximum[2]) * .5
        testing.expect(t, width > height * 1.08)
        testing.expect(t, min(width_x, width_z) > width * .60)
        testing.expect(t, math.abs(center_x) < width * .18)
        testing.expect(t, math.abs(center_z) < width * .18)
    }
}

@(test)
mature_pomegranate_keeps_a_balanced_multistem_vase_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(60) ..= 80 {
        result := plants.generate(
            {species = .Pomegranate, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        width_x := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
        width_z := result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2]
        width := max(width_x, width_z)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        center_x := (result.plant.bounds.minimum[0] + result.plant.bounds.maximum[0]) * .5
        center_z := (result.plant.bounds.minimum[2] + result.plant.bounds.maximum[2]) * .5
        testing.expect(t, width > height * .82)
        testing.expect(t, min(width_x, width_z) > width * .62)
        testing.expect(t, math.abs(center_x) < width * .16)
        testing.expect(t, math.abs(center_z) < width * .16)
    }
}

@(test)
mature_carob_keeps_a_balanced_heavy_crown_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(60) ..= 80 {
        result := plants.generate(
            {species = .Carob, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        width_x := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
        width_z := result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2]
        width := max(width_x, width_z)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        center_x := (result.plant.bounds.minimum[0] + result.plant.bounds.maximum[0]) * .5
        center_z := (result.plant.bounds.minimum[2] + result.plant.bounds.maximum[2]) * .5
        testing.expect(t, width > height * 1.02)
        testing.expect(t, min(width_x, width_z) > width * .60)
        testing.expect(t, math.abs(center_x) < width * .18)
        testing.expect(t, math.abs(center_z) < width * .18)
    }
}

@(test)
mature_bay_laurel_keeps_a_balanced_upright_oval_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(60) ..= 80 {
        result := plants.generate(
            {species = .Bay_Laurel, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        width_x := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
        width_z := result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2]
        width := max(width_x, width_z)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        center_x := (result.plant.bounds.minimum[0] + result.plant.bounds.maximum[0]) * .5
        center_z := (result.plant.bounds.minimum[2] + result.plant.bounds.maximum[2]) * .5
        testing.expect(t, width > height * .58)
        testing.expect(t, width < height * 1.12)
        testing.expect(t, min(width_x, width_z) > width * .62)
        testing.expect(t, math.abs(center_x) < width * .16)
        testing.expect(t, math.abs(center_z) < width * .16)
    }
}

@(test)
lemon_lifecycle_adds_radial_ramification_without_a_topology_cliff :: proc(t: ^testing.T) {
    maturities := [4]f32{.28, .42, .72, 1}
    previous_segments := 0
    previous_attachments := 0
    for maturity in maturities {
        result := plants.generate(
            {species = .Lemon, seed = 73, maturity = maturity, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        if previous_segments > 0 {
            testing.expect(t, len(result.plant.segments) > previous_segments)
            testing.expect(t, len(result.plant.segments) < previous_segments * 5)
            testing.expect(t, len(result.plant.attachments) > previous_attachments)
            testing.expect(t, len(result.plant.attachments) < previous_attachments * 5)
        }
        previous_segments = len(result.plant.segments)
        previous_attachments = len(result.plant.attachments)
        plants.destroy(&result)
    }

    near := plants.generate({species = .Lemon, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&near)
    medium := plants.generate({species = .Lemon, seed = 73, maturity = 1, detail = .Medium, habit = .Free_Standing})
    defer plants.destroy(&medium)
    far := plants.generate({species = .Lemon, seed = 73, maturity = 1, detail = .Far, habit = .Free_Standing})
    defer plants.destroy(&far)
    testing.expect_value(t, near.error, plants.Generate_Error.None)
    testing.expect_value(t, medium.error, plants.Generate_Error.None)
    testing.expect_value(t, far.error, plants.Generate_Error.None)
    testing.expect(t, len(near.plant.segments) > len(medium.plant.segments))
    testing.expect(t, len(medium.plant.segments) > len(far.plant.segments))
    near_maximum_leaf_width, far_maximum_leaf_width := f32(0), f32(0)
    far_reproductive_attachments := 0
    for attachment in near.plant.attachments {
        if attachment.kind == .Leaf {
            near_maximum_leaf_width = max(near_maximum_leaf_width, attachment.leaf.width)
        }
    }
    for attachment in far.plant.attachments {
        if attachment.kind == .Leaf {
            far_maximum_leaf_width = max(far_maximum_leaf_width, attachment.leaf.width)
        } else {
            far_reproductive_attachments += 1
        }
    }
    testing.expect(t, far_maximum_leaf_width > near_maximum_leaf_width * 2.5)
    testing.expect_value(t, far_reproductive_attachments, 0)
}

@(test)
olive_uses_a_crooked_trunk_and_staggered_primary_leaders :: proc(t: ^testing.T) {
    result := plants.generate({species = .Olive, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)

    trunk_segments, primary_roots := 0, 0
    trunk_top: plants.Bounds
    first_trunk_point := true
    primary_root_heights: [8]f32
    for segment in result.plant.segments {
        if segment.depth == 0 {
            trunk_segments += 1
            plants.update_bounds(&trunk_top, segment.end, &first_trunk_point)
        }
        if segment.depth != 1 do continue
        rooted_on_trunk := false
        for trunk in result.plant.segments {
            if trunk.depth != 0 do continue
            delta := segment.start - trunk.end
            if linalg.dot(delta, delta) < 1e-7 {
                rooted_on_trunk = true
                break
            }
        }
        if !rooted_on_trunk do continue
        if primary_roots < len(primary_root_heights) {
            primary_root_heights[primary_roots] = segment.start[1]
        }
        primary_roots += 1
    }
    testing.expect(t, trunk_segments >= 3)
    testing.expect(t, primary_roots >= 3)
    testing.expect(t, math.abs(trunk_top.maximum[0]) + math.abs(trunk_top.maximum[2]) > .01)

    staggered := false
    for a in 0 ..< min(primary_roots, len(primary_root_heights)) {
        for b in a + 1 ..< min(primary_roots, len(primary_root_heights)) {
            if math.abs(primary_root_heights[a] - primary_root_heights[b]) > .01 {
                staggered = true
            }
        }
    }
    testing.expect(t, staggered)
}

@(test)
olive_mature_roots_finish_below_grade_without_needle_tips :: proc(t: ^testing.T) {
    result := plants.generate({species = .Olive, seed = 41, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)

    buried_tips := 0
    for segment in result.plant.segments {
        if segment.depth >= 0 || segment.end[1] >= 0 do continue
        buried_tips += 1
        testing.expect(t, segment.radius_end >= result.plant.segments[0].radius_start * .09)
    }
    testing.expect_value(t, buried_tips, 3)
}

@(test)
olive_juvenile_wood_stays_slender_and_upright :: proc(t: ^testing.T) {
    young := plants.generate({species = .Olive, seed = 73, maturity = .28, detail = .Near, habit = .Free_Standing})
    mature := plants.generate({species = .Olive, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&young)
    defer plants.destroy(&mature)
    testing.expect_value(t, young.error, plants.Generate_Error.None)
    testing.expect_value(t, mature.error, plants.Generate_Error.None)
    testing.expect(t, young.plant.segments[0].radius_start < mature.plant.segments[0].radius_start * .25)
    testing.expect(t, young.plant.wind_compliance > mature.plant.wind_compliance)
    young_roots, mature_roots := 0, 0
    for segment in young.plant.segments {
        if segment.depth < 0 do young_roots += 1
    }
    for segment in mature.plant.segments {
        if segment.depth < 0 do mature_roots += 1
    }
    testing.expect_value(t, young_roots, 0)
    testing.expect_value(t, mature_roots, 6)
    for segment in young.plant.segments {
        if segment.depth != 1 do continue
        direction := linalg.normalize0(segment.end - segment.start)
        testing.expect(t, direction[1] > .45)
    }
}

@(test)
olive_far_leaves_become_broad_spray_surrogates :: proc(t: ^testing.T) {
    near := plants.generate({species = .Olive, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
    far := plants.generate({species = .Olive, seed = 73, maturity = 1, detail = .Far, habit = .Free_Standing})
    defer plants.destroy(&near)
    defer plants.destroy(&far)
    testing.expect_value(t, near.error, plants.Generate_Error.None)
    testing.expect_value(t, far.error, plants.Generate_Error.None)
    near_maximum_width, far_maximum_width := f32(0), f32(0)
    for attachment in near.plant.attachments {
        if attachment.kind == .Leaf do near_maximum_width = max(near_maximum_width, attachment.leaf.width)
    }
    for attachment in far.plant.attachments {
        if attachment.kind == .Leaf do far_maximum_width = max(far_maximum_width, attachment.leaf.width)
    }
    testing.expect(t, far_maximum_width > near_maximum_width * 2.5)
}

@(test)
olive_lifecycle_adds_ramification_without_a_late_architecture_cliff :: proc(t: ^testing.T) {
    maturities := [5]f32{.28, .42, .55, .72, 1.0}
    previous_segments := 0
    previous_attachments := 0
    for maturity in maturities {
        result := plants.generate(
            {species = .Olive, seed = 73, maturity = maturity, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        if previous_segments > 0 {
            testing.expect(t, len(result.plant.segments) > previous_segments)
            testing.expect(t, len(result.plant.segments) < previous_segments * 4)
            testing.expect(t, len(result.plant.attachments) > previous_attachments)
            testing.expect(t, len(result.plant.attachments) < previous_attachments * 4)
        }
        previous_segments = len(result.plant.segments)
        previous_attachments = len(result.plant.attachments)
        plants.destroy(&result)
    }

    young_near := plants.generate(
        {species = .Olive, seed = 73, maturity = .28, detail = .Near, habit = .Free_Standing},
    )
    defer plants.destroy(&young_near)
    young_far := plants.generate({species = .Olive, seed = 73, maturity = .28, detail = .Far, habit = .Free_Standing})
    defer plants.destroy(&young_far)
    testing.expect_value(t, young_near.error, plants.Generate_Error.None)
    testing.expect_value(t, young_far.error, plants.Generate_Error.None)
    testing.expect(t, len(young_far.plant.segments) <= len(young_near.plant.segments))
}

@(test)
plant_leaf_frames_and_bounds_include_generated_geometry :: proc(t: ^testing.T) {
    result := plants.generate({species = .Fig, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    found_leaf := false
    for attachment in result.plant.attachments {
        if attachment.kind != .Leaf do continue
        found_leaf = true
        testing.expect(t, math.abs(linalg.dot(attachment.forward, attachment.up)) < .001)
        tip := attachment.position + attachment.forward * attachment.leaf.length
        for axis in 0 ..< 3 {
            testing.expect(t, tip[axis] >= result.plant.bounds.minimum[axis] - .001)
            testing.expect(t, tip[axis] <= result.plant.bounds.maximum[axis] + .001)
        }
    }
    testing.expect(t, found_leaf)
}

@(test)
plant_generated_geometry_preserves_winding :: proc(t: ^testing.T) {
    support: plants.Support_Surface
    exclusions: [2]plants.Rect
    plant_support(&support, &exclusions)
    for species_index in 0 ..< plants.SPECIES_COUNT {
        species := plants.Species(species_index)
        habit := plants.default_habit(species)
        support_pointer: ^plants.Support_Surface
        if habit != .Free_Standing do support_pointer = &support
        found_species_leaf := false
        for detail in plants.Detail_Level {
            result := plants.generate(
                {
                    species = species,
                    seed = 73,
                    maturity = 1,
                    detail = detail,
                    habit = habit,
                    support = support_pointer,
                },
            )
            testing.expect_value(t, result.error, plants.Generate_Error.None)

            branch_config := branch_mesh.Config {
                minimum_radius = .012,
                axis_ids       = result.plant.segment_axes[:],
            }
            switch detail {
            case .Near:
                branch_config.radial_segments = 8
                branch_config.samples_per_segment = 3
            case .Medium:
                branch_config.radial_segments = 6
                branch_config.samples_per_segment = 2
            case .Far:
                branch_config.radial_segments = 4
                branch_config.samples_per_segment = 1
            }
            branch_hull := branch_mesh.generate(result.plant.segments[:], branch_config)
            testing.expect(t, len(branch_hull.indices) > 0 && len(branch_hull.indices) % 3 == 0)
            found_branch_face := false
            outward_branch_faces := 0
            reversed_branch_faces := 0
            for first := 0; first + 2 < len(branch_hull.indices); first += 3 {
                a := branch_hull.vertices[branch_hull.indices[first + 0]]
                b := branch_hull.vertices[branch_hull.indices[first + 1]]
                c := branch_hull.vertices[branch_hull.indices[first + 2]]
                face := linalg.cross(b.position - a.position, c.position - a.position)
                if linalg.dot(face, face) < 1e-12 do continue
                found_branch_face = true
                // Side and cap triangles must face the same direction as the
                // normals consumed by plant_generator_draw_branch_hull. At a
                // sharp cap the radial ring normals can cancel the axial
                // center normal, so compare the face with each contributor.
                alignment := max(linalg.dot(face, a.normal), linalg.dot(face, b.normal), linalg.dot(face, c.normal))
                if alignment > 0 {
                    outward_branch_faces += 1
                } else {
                    // Very tight procedural bends can fold a spline quad
                    // through its smooth normals. Track those separately so
                    // an index-order inversion of the whole hull still fails.
                    reversed_branch_faces += 1
                }
            }
            testing.expect(t, found_branch_face)
            testing.expect(t, outward_branch_faces > reversed_branch_faces)
            branch_mesh.destroy(&branch_hull)

            for attachment in result.plant.attachments {
                if attachment.kind != .Leaf do continue
                found_species_leaf = true

                // The renderer uses {right, forward, up} to take leaf mesh
                // coordinates into plant space. This basis must stay
                // right-handed or it reverses the mesh's triangle winding.
                forward := linalg.normalize0(attachment.forward)
                up := linalg.normalize0(attachment.up)
                right := linalg.normalize0(linalg.cross(forward, up))
                testing.expect(t, linalg.dot(linalg.cross(right, forward), up) > .999)

                config := leaf_mesh.defaults(attachment.leaf.shape)
                config.length = attachment.leaf.length
                config.width = attachment.leaf.width
                config.serration = attachment.leaf.serration
                config.curl = attachment.leaf.curl
                config.cup = attachment.leaf.cup
                config.segments = detail == .Near ? 12 : detail == .Medium ? 6 : 3
                mesh := leaf_mesh.generate(config)
                testing.expect(t, mesh.index_count > 0 && mesh.index_count % 3 == 0)
                found_wound_triangle := false
                for first := 0; first + 2 < mesh.index_count; first += 3 {
                    a := mesh.vertices[mesh.indices[first + 0]].position
                    b := mesh.vertices[mesh.indices[first + 1]].position
                    c := mesh.vertices[mesh.indices[first + 2]].position
                    face := linalg.cross(b - a, c - a)
                    // Tip and base triangles may collapse in XY, but no
                    // non-degenerate face may reverse the -Z convention.
                    testing.expect(t, face[2] <= .0000001)
                    if face[2] < -.0000001 do found_wound_triangle = true
                }
                testing.expect(t, found_wound_triangle)
            }
            plants.destroy(&result)
        }
        testing.expect(t, found_species_leaf)
    }
}

@(test)
plant_catalog_is_deterministic :: proc(t: ^testing.T) {
    config := plants.Generate_Config {
        species  = .Olive,
        seed     = 991,
        maturity = .78,
        detail   = .Near,
        habit    = .Free_Standing,
    }
    a := plants.generate(config)
    b := plants.generate(config)
    defer plants.destroy(&a)
    defer plants.destroy(&b)
    testing.expect_value(t, a.error, plants.Generate_Error.None)
    testing.expect_value(t, b.error, plants.Generate_Error.None)
    testing.expect_value(t, len(a.plant.segments), len(b.plant.segments))
    testing.expect_value(t, len(a.plant.attachments), len(b.plant.attachments))
    for segment, index in a.plant.segments {
        testing.expect_value(t, segment, b.plant.segments[index])
    }
    for attachment, index in a.plant.attachments {
        testing.expect_value(t, attachment, b.plant.attachments[index])
    }
}

@(test)
plant_maturity_increases_reach_and_hierarchy :: proc(t: ^testing.T) {
    for species_index in 0 ..< plants.SPECIES_COUNT {
        species := plants.Species(species_index)
        support: plants.Support_Surface
        exclusions: [2]plants.Rect
        plant_support(&support, &exclusions)
        habit := plants.default_habit(species)
        support_pointer: ^plants.Support_Surface
        if habit != .Free_Standing do support_pointer = &support
        young := plants.generate(
            {species = species, seed = 41, maturity = .2, detail = .Near, habit = habit, support = support_pointer},
        )
        mature := plants.generate(
            {species = species, seed = 41, maturity = 1, detail = .Near, habit = habit, support = support_pointer},
        )
        testing.expect_value(t, young.error, plants.Generate_Error.None)
        testing.expect_value(t, mature.error, plants.Generate_Error.None)
        testing.expect(t, len(mature.plant.segments) >= len(young.plant.segments))
        young_height := young.plant.bounds.maximum[1] - young.plant.bounds.minimum[1]
        mature_height := mature.plant.bounds.maximum[1] - mature.plant.bounds.minimum[1]
        testing.expect(t, mature_height >= young_height)
        plants.destroy(&young)
        plants.destroy(&mature)
    }
}

@(test)
dense_evergreens_generate_continuous_foliage_architecture :: proc(t: ^testing.T) {
    evergreen_species := [2]plants.Species{.Italian_Cypress, .Rosemary}
    for species in evergreen_species {
        result := plants.generate({species = species, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        leaf_count := 0
        for attachment in result.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
        }
        // These species carry foliage continuously along shoots; a terminal-
        // bud-only grammar produces conspicuous bare radial fans.
        testing.expect(t, leaf_count >= len(result.plant.segments))
        testing.expect(t, leaf_count >= 64)
    }

    cypress := plants.generate(
        {species = .Italian_Cypress, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing},
    )
    defer plants.destroy(&cypress)
    width := cypress.plant.bounds.maximum[0] - cypress.plant.bounds.minimum[0]
    depth := cypress.plant.bounds.maximum[2] - cypress.plant.bounds.minimum[2]
    height := cypress.plant.bounds.maximum[1] - cypress.plant.bounds.minimum[1]
    crown_width := max(width, depth)
    testing.expect(t, crown_width / height > .06)
    testing.expect(t, crown_width / height < .42)
    leaf_count := 0
    for attachment in cypress.plant.attachments {
        if attachment.kind == .Leaf do leaf_count += 1
    }
    // Scale-leaf sprays should sheath the lateral shoots rather than collect
    // into sparse terminal tufts. This ratio includes the leader, so it stays
    // conservative while guarding the mature crown's foliage coverage.
    testing.expect(t, leaf_count >= len(cypress.plant.segments) * 11)
}

@(test)
stone_pine_preserves_a_clothed_umbrella_crown_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        pine := plants.generate(
            {species = .Stone_Pine, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, pine.error, plants.Generate_Error.None)
        height := pine.plant.bounds.maximum[1] - pine.plant.bounds.minimum[1]
        crown_minimum_x, crown_maximum_x := f32(1e9), f32(-1e9)
        crown_minimum_z, crown_maximum_z := f32(1e9), f32(-1e9)
        crown_attachment_count := 0
        primary_attachment_count, terminal_attachment_count := 0, 0
        pad_minimum := [3]f32{1e9, 1e9, 1e9}
        pad_maximum := [3]f32{-1e9, -1e9, -1e9}
        pad_attachment_count := 0
        for attachment in pine.plant.attachments {
            if attachment.kind != .Leaf || attachment.position[1] < height * .48 do continue
            crown_minimum_x = min(crown_minimum_x, attachment.position[0])
            crown_maximum_x = max(crown_maximum_x, attachment.position[0])
            crown_minimum_z = min(crown_minimum_z, attachment.position[2])
            crown_maximum_z = max(crown_maximum_z, attachment.position[2])
            crown_attachment_count += 1
            if attachment.depth == 1 do primary_attachment_count += 1
            if attachment.depth >= 2 do terminal_attachment_count += 1
            if attachment.depth >= 3 {
                pad_minimum = linalg.min(pad_minimum, attachment.position)
                pad_maximum = linalg.max(pad_maximum, attachment.position)
                pad_attachment_count += 1
            }
        }
        crown_width := max(crown_maximum_x - crown_minimum_x, crown_maximum_z - crown_minimum_z)
        pad_width := max(pad_maximum[0] - pad_minimum[0], pad_maximum[2] - pad_minimum[2])
        pad_height := pad_maximum[1] - pad_minimum[1]
        // Mature specimens should read as one bushy, interlocking umbrella,
        // not as a ring of individually legible terminal sprays.
        testing.expect(t, crown_attachment_count >= 120)
        // The global near-detail attachment budget stratifies this population
        // with the branch-bound fascicles, so require a substantial surviving
        // pad rather than its pre-budget source count.
        testing.expect(t, pad_attachment_count >= 700)
        testing.expect(t, pad_width / max(pad_height, f32(.001)) > 2.4)
        testing.expect(t, crown_width >= plants.leaf_traits(.Stone_Pine, 0, 1).length * 1.5)
        // Needle mass belongs to the terminal umbrella pads, leaving the old
        // inner scaffold legible instead of clothing every arm uniformly.
        testing.expect(t, terminal_attachment_count > primary_attachment_count * 4)
        plants.destroy(&pine)
    }
}

@(test)
stone_pine_preserves_umbrella_pad_through_lods :: proc(t: ^testing.T) {
    details := [2]plants.Detail_Level{.Medium, .Far}
    minimum_pad_counts := [2]int{240, 28}
    for detail, detail_index in details {
        for seed in u64(70) ..= 76 {
            pine := plants.generate(
                {species = .Stone_Pine, seed = seed, maturity = 1, detail = detail, habit = .Free_Standing},
            )
            testing.expect_value(t, pine.error, plants.Generate_Error.None)
            pad_minimum := [3]f32{1e9, 1e9, 1e9}
            pad_maximum := [3]f32{-1e9, -1e9, -1e9}
            pad_count := 0
            for attachment in pine.plant.attachments {
                if attachment.kind != .Leaf || attachment.depth < 3 do continue
                pad_minimum = linalg.min(pad_minimum, attachment.position)
                pad_maximum = linalg.max(pad_maximum, attachment.position)
                pad_count += 1
            }
            pad_width := max(pad_maximum[0] - pad_minimum[0], pad_maximum[2] - pad_minimum[2])
            pad_height := pad_maximum[1] - pad_minimum[1]
            testing.expect(t, pad_count >= minimum_pad_counts[detail_index])
            testing.expect(t, pad_width / max(pad_height, f32(.001)) > 2.2)
            plants.destroy(&pine)
        }
    }
}

@(test)
stone_pine_umbrella_pad_forms_late_in_lifecycle :: proc(t: ^testing.T) {
    maturities := [3]f32{.30, .55, 1}
    pad_counts: [3]int
    for maturity, maturity_index in maturities {
        pine := plants.generate(
            {species = .Stone_Pine, seed = 73, maturity = maturity, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, pine.error, plants.Generate_Error.None)
        for attachment in pine.plant.attachments {
            if attachment.kind == .Leaf && attachment.depth >= 3 do pad_counts[maturity_index] += 1
        }
        plants.destroy(&pine)
    }
    testing.expect_value(t, pad_counts[0], 0)
    testing.expect(t, pad_counts[1] > 0)
    testing.expect(t, pad_counts[1] < pad_counts[2])
    testing.expect(t, pad_counts[2] >= 700)
}

@(test)
mature_cypress_carries_foliage_through_its_full_crown :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Italian_Cypress, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        crown_width := max(
            result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0],
            result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2],
        )
        crown_depth := result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2]
        crown_span_x := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
        testing.expect(t, crown_width / height > .06)
        testing.expect(t, crown_width / height < .30)
        testing.expect(t, crown_span_x / crown_depth > .85)
        testing.expect(t, crown_span_x / crown_depth < 1.18)
        foliage_by_band: [10]int
        for attachment in result.plant.attachments {
            if attachment.kind != .Leaf do continue
            relative_height := (attachment.position[1] - result.plant.bounds.minimum[1]) / height
            band := clamp(int(relative_height * f32(len(foliage_by_band))), 0, len(foliage_by_band) - 1)
            foliage_by_band[band] += 1
        }
        // A small visible trunk is healthy, but every tenth above it should
        // contribute to the narrow evergreen crown.
        for band in 1 ..< len(foliage_by_band) {
            testing.expect(t, foliage_by_band[band] > 0)
        }
    }
}

@(test)
mature_almond_forms_a_broad_volumetric_leafy_crown :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Almond, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        width := result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0]
        depth := result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2]
        testing.expect(t, max(width, depth) / height > .45)
        testing.expect(t, min(width, depth) / max(width, depth) > .58)

        primary_scaffolds := 0
        positive_x, negative_x := false, false
        positive_z, negative_z := false, false
        minimum_origin_height, maximum_origin_height := f32(1e9), f32(-1e9)
        for segment in result.plant.segments {
            if segment.depth != 1 do continue
            starts_on_trunk := false
            for trunk in result.plant.segments {
                if trunk.depth == 0 && segment.start == trunk.end {
                    starts_on_trunk = true
                    break
                }
            }
            if !starts_on_trunk do continue
            primary_scaffolds += 1
            direction := segment.end - segment.start
            positive_x = positive_x || direction[0] > 0
            negative_x = negative_x || direction[0] < 0
            positive_z = positive_z || direction[2] > 0
            negative_z = negative_z || direction[2] < 0
            minimum_origin_height = min(minimum_origin_height, segment.start[1])
            maximum_origin_height = max(maximum_origin_height, segment.start[1])
        }
        testing.expect_value(t, primary_scaffolds, 5)
        testing.expect(t, positive_x && negative_x && positive_z && negative_z)
        testing.expect(t, maximum_origin_height - minimum_origin_height > height * .10)

        foliage_by_band: [4]int
        for attachment in result.plant.attachments {
            if attachment.kind != .Leaf && attachment.kind != .Flower do continue
            relative_height := (attachment.position[1] - result.plant.bounds.minimum[1]) / height
            band := clamp(int(relative_height * f32(len(foliage_by_band))), 0, len(foliage_by_band) - 1)
            foliage_by_band[band] += 1
        }
        testing.expect(t, foliage_by_band[1] > 0)
        testing.expect(t, foliage_by_band[2] > 0)
        testing.expect(t, foliage_by_band[3] > 0)
        testing.expect_value(t, plants.leaf_cluster_size(.Almond, .Near, 1), 1)
        testing.expect(t, result.plant.segments[0].radius_start < .11)
    }
}

@(test)
strawberry_tree_forms_a_radial_multistem_fruiting_crown_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Strawberry_Tree, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        width := max(
            result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0],
            result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2],
        )
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        testing.expect(t, height > width * .82)
        testing.expect(t, height < width * 2.35)
        positive_x, negative_x, positive_z, negative_z := false, false, false, false
        leaf_count, fruit_count := 0, 0
        for segment in result.plant.segments {
            positive_x = positive_x || segment.end[0] > 0
            negative_x = negative_x || segment.end[0] < 0
            positive_z = positive_z || segment.end[2] > 0
            negative_z = negative_z || segment.end[2] < 0
        }
        for attachment in result.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Fruit do fruit_count += 1
        }
        testing.expect(t, positive_x && negative_x && positive_z && negative_z)
        testing.expect(t, leaf_count > 0)
        testing.expect(t, fruit_count > 0)
        testing.expect_value(t, plants.leaf_cluster_size(.Strawberry_Tree, .Near, 1), 2)
        plants.destroy(&result)
    }
}

@(test)
cypress_seeds_vary_habit_coherently_and_repeat_exactly :: proc(t: ^testing.T) {
    minimum_height, maximum_height := f32(1e9), f32(0)
    minimum_width, maximum_width := f32(1e9), f32(0)
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Italian_Cypress, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        width := max(
            result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0],
            result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2],
        )
        minimum_height, maximum_height = min(minimum_height, height), max(maximum_height, height)
        minimum_width, maximum_width = min(minimum_width, width), max(maximum_width, width)
        leader_tip: plants.Bounds
        found_tip := false
        for segment in result.plant.segments {
            if segment.depth != 0 do continue
            leader_tip.maximum = segment.end
            found_tip = true
        }
        testing.expect(t, found_tip)
        lean := math.sqrt(
            leader_tip.maximum[0] * leader_tip.maximum[0] + leader_tip.maximum[2] * leader_tip.maximum[2],
        )
        testing.expect(t, lean < height * .04)
    }
    testing.expect(t, maximum_height / minimum_height > 1.08)
    testing.expect(t, maximum_width / minimum_width > 1.10)

    first := plants.generate(
        {species = .Italian_Cypress, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing},
    )
    second := plants.generate(
        {species = .Italian_Cypress, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing},
    )
    defer plants.destroy(&first)
    defer plants.destroy(&second)
    testing.expect_value(t, first.error, plants.Generate_Error.None)
    testing.expect_value(t, second.error, plants.Generate_Error.None)
    testing.expect(t, first.plant.bounds == second.plant.bounds)
    testing.expect_value(t, len(first.plant.segments), len(second.plant.segments))
    testing.expect_value(t, len(first.plant.attachments), len(second.plant.attachments))
    for segment, index in first.plant.segments {
        testing.expect(t, segment == second.plant.segments[index])
    }
}

@(test)
mature_cypress_carries_sparse_woody_cones_only_at_near_detail :: proc(t: ^testing.T) {
    mature_near := plants.generate(
        {species = .Italian_Cypress, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing},
    )
    young_near := plants.generate(
        {species = .Italian_Cypress, seed = 73, maturity = .72, detail = .Near, habit = .Free_Standing},
    )
    mature_medium := plants.generate(
        {species = .Italian_Cypress, seed = 73, maturity = 1, detail = .Medium, habit = .Free_Standing},
    )
    defer plants.destroy(&mature_near)
    defer plants.destroy(&young_near)
    defer plants.destroy(&mature_medium)
    testing.expect_value(t, mature_near.error, plants.Generate_Error.None)
    testing.expect_value(t, young_near.error, plants.Generate_Error.None)
    testing.expect_value(t, mature_medium.error, plants.Generate_Error.None)

    mature_cones, young_cones, medium_cones := 0, 0, 0
    for attachment in mature_near.plant.attachments {
        if attachment.kind != .Fruit do continue
        mature_cones += 1
        testing.expect(t, attachment.depth == 1)
        // A cone must remain embedded in its supporting scale-leaf spray,
        // rather than replacing that spray and punching a hole in the crown.
        carried_by_foliage := false
        for support in mature_near.plant.attachments {
            if support.kind != .Leaf || support.depth != attachment.depth do continue
            offset := support.position - attachment.position
            if linalg.dot(offset, offset) < .0005 {
                carried_by_foliage = true
                break
            }
        }
        testing.expect(t, carried_by_foliage)
    }
    for attachment in young_near.plant.attachments {
        if attachment.kind == .Fruit do young_cones += 1
    }
    for attachment in mature_medium.plant.attachments {
        if attachment.kind == .Fruit do medium_cones += 1
    }
    testing.expect(t, mature_cones >= 6)
    testing.expect(t, mature_cones <= 24)
    testing.expect_value(t, young_cones, 0)
    testing.expect_value(t, medium_cones, 0)
}

@(test)
mature_cypress_cones_remain_sparse_and_vertically_distributed_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Italian_Cypress, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)

        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        occupied_bands: [3]bool
        cone_count := 0
        for attachment in result.plant.attachments {
            if attachment.kind != .Fruit do continue
            cone_count += 1
            normalized_height := (attachment.position[1] - result.plant.bounds.minimum[1]) / max(height, f32(.001))
            testing.expect(t, normalized_height > .12)
            band := clamp(int(normalized_height * 3), 0, 2)
            occupied_bands[band] = true
        }
        band_count := 0
        for occupied in occupied_bands {
            if occupied do band_count += 1
        }
        testing.expect(t, cone_count >= 6)
        testing.expect(t, cone_count <= 24)
        testing.expect(t, band_count >= 2)
    }
}

@(test)
cypress_cones_set_progressively_without_disappearing_during_maturation :: proc(t: ^testing.T) {
    maturities := [6]f32{.78, .82, .86, .90, .96, 1}
    previous_count := -1
    for maturity in maturities {
        result := plants.generate(
            {species = .Italian_Cypress, seed = 73, maturity = maturity, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        cone_count := 0
        for attachment in result.plant.attachments {
            if attachment.kind == .Fruit do cone_count += 1
        }
        testing.expect(t, cone_count >= previous_count)
        if maturity == .78 do testing.expect_value(t, cone_count, 0)
        previous_count = cone_count
    }
    testing.expect(t, previous_count >= 6)
    testing.expect(t, previous_count <= 24)
}

@(test)
cypress_detail_levels_preserve_the_column_while_reducing_geometry :: proc(t: ^testing.T) {
    results: [3]plants.Generate_Result
    details := [3]plants.Detail_Level{.Near, .Medium, .Far}
    for detail, index in details {
        results[index] = plants.generate(
            {species = .Italian_Cypress, seed = 73, maturity = 1, detail = detail, habit = .Free_Standing},
        )
        testing.expect_value(t, results[index].error, plants.Generate_Error.None)
        height := results[index].plant.bounds.maximum[1] - results[index].plant.bounds.minimum[1]
        width := max(
            results[index].plant.bounds.maximum[0] - results[index].plant.bounds.minimum[0],
            results[index].plant.bounds.maximum[2] - results[index].plant.bounds.minimum[2],
        )
        testing.expect(t, height > width * 3)
    }
    defer for &result in results do plants.destroy(&result)
    testing.expect(t, len(results[0].plant.segments) > len(results[1].plant.segments))
    testing.expect(t, len(results[1].plant.segments) > len(results[2].plant.segments))
    testing.expect(t, len(results[0].plant.attachments) > len(results[1].plant.attachments))
    testing.expect(t, len(results[1].plant.attachments) > len(results[2].plant.attachments))
    // Far cypress deliberately spends most of its fixed budget on eleven
    // vertically overlapping whorls; dropping back to a generic sparse LOD
    // reintroduces a visibly striped, skeletal crown.
    testing.expect(t, len(results[2].plant.segments) >= 184)
    testing.expect(t, len(results[2].plant.segments) <= 192)
    testing.expect(t, len(results[2].plant.attachments) >= 370)
    testing.expect(t, len(results[2].plant.attachments) <= 384)
    near_height := results[0].plant.bounds.maximum[1] - results[0].plant.bounds.minimum[1]
    for index in 1 ..< len(results) {
        lod_height := results[index].plant.bounds.maximum[1] - results[index].plant.bounds.minimum[1]
        testing.expect(t, lod_height >= near_height * .95)
        testing.expect(t, lod_height <= near_height * 1.08)
    }
}

@(test)
mature_cypress_crown_width_changes_smoothly_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Italian_Cypress, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        band_radii: [10]f32
        for segment in result.plant.segments {
            if segment.depth != 1 do continue
            band := clamp(int((segment.end[1] - result.plant.bounds.minimum[1]) / height * 10), 0, len(band_radii) - 1)
            radius := f32(math.sqrt(segment.end[0] * segment.end[0] + segment.end[2] * segment.end[2]))
            band_radii[band] = max(band_radii[band], radius)
        }
        minimum_radius, maximum_radius := f32(1e9), f32(0)
        for band in 2 ..< len(band_radii) {
            testing.expect(t, band_radii[band] > 0)
            minimum_radius = min(minimum_radius, band_radii[band])
            maximum_radius = max(maximum_radius, band_radii[band])
            if band > 2 {
                ratio := band_radii[band] / band_radii[band - 1]
                testing.expect(t, ratio >= .70)
                testing.expect(t, ratio <= 1.42)
            }
        }
        // The deliberately fuller lower third may be appreciably broader
        // than the upper column, but should remain recognizably fastigiate.
        testing.expect(t, maximum_radius / minimum_radius < 2.60)
        testing.expect(t, band_radii[1] >= band_radii[2] * .55)
    }
}

@(test)
cypress_whorls_vary_their_gaps_while_opposite_pairs_remain_balanced :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Italian_Cypress, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        directions: [8][3]f32
        for branch in 0 ..< 8 {
            // Segment zero is the first leader; each first-order branch then
            // contributes a trunk-to-mid and mid-to-tip segment.
            segment := result.plant.segments[1 + branch * 2]
            x := segment.end[0] - segment.start[0]
            y := segment.end[1] - segment.start[1]
            z := segment.end[2] - segment.start[2]
            horizontal_length := f32(math.sqrt(x * x + z * z))
            length := f32(math.sqrt(x * x + y * y + z * z))
            directions[branch] = {x / horizontal_length, z / horizontal_length, y / length}
        }
        minimum_adjacent_dot, maximum_adjacent_dot := f32(1), f32(-1)
        minimum_elevation, maximum_elevation := f32(1), f32(-1)
        minimum_origin_height, maximum_origin_height := f32(1e9), f32(-1e9)
        for branch in 0 ..< 4 {
            next := branch + 1
            adjacent_dot := directions[branch][0] * directions[next][0] + directions[branch][1] * directions[next][1]
            minimum_adjacent_dot = min(minimum_adjacent_dot, adjacent_dot)
            maximum_adjacent_dot = max(maximum_adjacent_dot, adjacent_dot)
            opposite_dot :=
                directions[branch][0] * directions[branch + 4][0] + directions[branch][1] * directions[branch + 4][1]
            testing.expect(t, opposite_dot < -.9999)
            testing.expect(t, math.abs(directions[branch][2] - directions[branch + 4][2]) < .00001)
            origin := result.plant.segments[1 + branch * 2].start
            opposite_origin := result.plant.segments[1 + (branch + 4) * 2].start
            testing.expect(t, linalg.length(origin - opposite_origin) < .00001)
            minimum_origin_height = min(minimum_origin_height, origin[1])
            maximum_origin_height = max(maximum_origin_height, origin[1])
            minimum_elevation = min(minimum_elevation, directions[branch][2])
            maximum_elevation = max(maximum_elevation, directions[branch][2])
        }
        testing.expect(t, maximum_adjacent_dot - minimum_adjacent_dot > .015)
        testing.expect(t, maximum_elevation - minimum_elevation > .004)
        // A realistic cypress interleaves each nominal whorl through most of
        // a leader interval. A shallow spread recreates visible stacked
        // collars even when azimuths vary.
        testing.expect(t, maximum_origin_height - minimum_origin_height > .12)
        plants.destroy(&result)
    }
}

@(test)
cypress_terminal_leader_remains_above_the_last_whorl :: proc(t: ^testing.T) {
    maturities := [3]f32{.28, .55, 1}
    for maturity in maturities {
        for seed in u64(70) ..= 76 {
            result := plants.generate(
                {species = .Italian_Cypress, seed = seed, maturity = maturity, detail = .Near, habit = .Free_Standing},
            )
            testing.expect_value(t, result.error, plants.Generate_Error.None)
            leader_height, branch_height := f32(0), f32(0)
            for segment in result.plant.segments {
                if segment.depth == 0 do leader_height = max(leader_height, segment.end[1])
                if segment.depth == 1 do branch_height = max(branch_height, segment.end[1])
            }
            testing.expect(t, leader_height > branch_height)
            plants.destroy(&result)
        }
    }
}

@(test)
cypress_wood_uses_restrained_longitudinal_fluting :: proc(t: ^testing.T) {
    result := plants.generate(
        {species = .Italian_Cypress, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    testing.expect(t, result.plant.wood.radial_irregularity > 0)
    testing.expect(t, result.plant.wood.radial_irregularity < .10)
    testing.expect(t, result.plant.wood.twist > .20)
    testing.expect(t, result.plant.wood.twist < .80)
}

@(test)
cypress_first_leader_segment_forms_a_restrained_root_flare :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Italian_Cypress, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        testing.expect(t, len(result.plant.segments) > 1)
        root := result.plant.segments[0]
        next_leader := result.plant.segments[17]
        testing.expect_value(t, root.depth, 0)
        testing.expect_value(t, next_leader.depth, 0)
        flare_ratio := root.radius_start / root.radius_end
        testing.expect(t, flare_ratio > 1.25)
        testing.expect(t, flare_ratio < 1.40)
        testing.expect(t, math.abs(root.radius_end - next_leader.radius_start) < .00001)
        plants.destroy(&result)
    }
}

@(test)
cypress_leader_curves_gently_without_excessive_lean :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Italian_Cypress, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        first_direction, last_direction := [2]f32{}, [2]f32{}
        leader_x, leader_z := f32(0), f32(0)
        first := true
        for segment in result.plant.segments {
            if segment.depth != 0 do continue
            x := segment.end[0] - segment.start[0]
            z := segment.end[2] - segment.start[2]
            length := f32(math.sqrt(x * x + z * z))
            direction := [2]f32{x / length, z / length}
            if first {
                first_direction = direction
                first = false
            }
            last_direction = direction
            leader_x = segment.end[0]
            leader_z = segment.end[2]
        }
        heading_dot := clamp(
            first_direction[0] * last_direction[0] + first_direction[1] * last_direction[1],
            f32(-1),
            f32(1),
        )
        heading_change := f32(math.acos(heading_dot))
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        lean := f32(math.sqrt(leader_x * leader_x + leader_z * leader_z)) / height
        testing.expect(t, heading_change > .04)
        testing.expect(t, heading_change < .70)
        testing.expect(t, lean < .02)
        plants.destroy(&result)
    }
}

@(test)
cypress_basal_sprays_bridge_the_root_flare_across_growth_stages :: proc(t: ^testing.T) {
    maturities := [3]f32{.28, .55, 1}
    for maturity in maturities {
        for seed in u64(70) ..= 76 {
            result := plants.generate(
                {species = .Italian_Cypress, seed = seed, maturity = maturity, detail = .Near, habit = .Free_Standing},
            )
            testing.expect_value(t, result.error, plants.Generate_Error.None)
            height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
            low_count, very_low_count := 0, 0
            minimum_leaf_y := f32(1e9)
            for attachment in result.plant.attachments {
                if attachment.kind != .Leaf do continue
                local_y := attachment.position[1] - result.plant.bounds.minimum[1]
                minimum_leaf_y = min(minimum_leaf_y, local_y)
                if local_y <= height * .10 do low_count += 1
                if local_y <= height * .05 do very_low_count += 1
            }
            expected_low := maturity < .4 ? 10 : maturity < .8 ? 19 : 32
            expected_very_low := maturity < .4 ? 8 : maturity < .8 ? 13 : 19
            testing.expect(t, low_count >= expected_low)
            testing.expect(t, very_low_count >= expected_very_low)
            testing.expect(t, minimum_leaf_y <= height * .01)
            plants.destroy(&result)
        }
    }
}

@(test)
cypress_growth_adds_at_most_two_branch_intervals_per_maturity_step :: proc(t: ^testing.T) {
    previous_height, previous_attachments := f32(0), 0
    previous_segments := 0
    for sample in 4 ..= 20 {
        maturity := f32(sample) * .05
        result := plants.generate(
            {species = .Italian_Cypress, seed = 73, maturity = maturity, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        segment_count := len(result.plant.segments)
        attachment_count := len(result.plant.attachments)
        if previous_height > 0 {
            testing.expect(t, height >= previous_height)
            testing.expect(t, height / previous_height <= 1.40)
            testing.expect(t, segment_count >= previous_segments)
            testing.expect(t, segment_count - previous_segments <= 34)
            testing.expect(t, attachment_count >= previous_attachments)
            testing.expect(t, f32(attachment_count) / f32(previous_attachments) <= 2.10)
        }
        previous_height = height
        previous_segments = segment_count
        previous_attachments = attachment_count
        plants.destroy(&result)
    }
}

@(test)
juvenile_cypress_has_a_compact_crown_not_a_single_branch_star :: proc(t: ^testing.T) {
    result := plants.generate(
        {species = .Italian_Cypress, seed = 73, maturity = .28, detail = .Near, habit = .Free_Standing},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    testing.expect(t, len(result.plant.segments) >= 32)
    testing.expect(t, len(result.plant.attachments) >= 128)
    height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
    width := max(
        result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0],
        result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2],
    )
    testing.expect(t, height > width * 2)

    // The immature leader cap should taper into the crown instead of forming
    // a fully mature terminal pom-pom above a narrow juvenile column.
    top_start := result.plant.bounds.maximum[1] - height * .16
    top_minimum_x, top_maximum_x := f32(1e9), f32(-1e9)
    top_minimum_z, top_maximum_z := f32(1e9), f32(-1e9)
    for attachment in result.plant.attachments {
        if attachment.position[1] < top_start do continue
        top_minimum_x = min(top_minimum_x, attachment.position[0])
        top_maximum_x = max(top_maximum_x, attachment.position[0])
        top_minimum_z = min(top_minimum_z, attachment.position[2])
        top_maximum_z = max(top_maximum_z, attachment.position[2])
    }
    top_width := max(top_maximum_x - top_minimum_x, top_maximum_z - top_minimum_z)
    testing.expect(t, top_width < width * .72)
}

@(test)
climbing_plants_route_attachments_away_from_openings :: proc(t: ^testing.T) {
    support: plants.Support_Surface
    exclusions: [2]plants.Rect
    plant_support(&support, &exclusions)
    climbing_species := [2]plants.Species{plants.Species.Bougainvillea, plants.Species.Grapevine}
    for species in climbing_species {
        result := plants.generate(
            {
                species = species,
                seed = 15,
                maturity = 1,
                detail = .Near,
                habit = plants.default_habit(species),
                support = &support,
            },
        )
        defer plants.destroy(&result)
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        testing.expect(t, result.plant.root_kind == .Planter)
        testing.expect(t, result.plant.support_signature != 0)
        minimum_x, maximum_x := f32(1e9), f32(-1e9)
        maximum_y := f32(0)
        for segment in result.plant.segments {
            minimum_x = min(minimum_x, min(segment.start[0], segment.end[0]))
            maximum_x = max(maximum_x, max(segment.start[0], segment.end[0]))
            maximum_y = max(maximum_y, max(segment.start[1], segment.end[1]))
        }
        // Mature climbing form must use the support rather than collapse into
        // the root corner after coordinate projection.
        testing.expect(t, minimum_x <= support.root_x + .35)
        testing.expect(t, maximum_x >= support.width * .20)
        testing.expect(t, maximum_x - minimum_x >= support.width * .55)
        testing.expect(t, maximum_y >= support.height * .90)
        for attachment in result.plant.attachments {
            for exclusion in support.exclusions {
                inside :=
                    attachment.position[0] >= exclusion.minimum_x &&
                    attachment.position[0] <= exclusion.maximum_x &&
                    attachment.position[1] >= exclusion.minimum_y &&
                    attachment.position[1] <= exclusion.maximum_y
                testing.expect(t, !inside)
            }
        }
    }
}

@(test)
climbing_branches_route_around_a_doorway :: proc(t: ^testing.T) {
    opening := [1]plants.Rect{{-1.18, 0, 1.18, 2.78}}
    support := plants.Support_Surface {
        width      = 3.25,
        height     = 3.55,
        root_x     = -1.48,
        exclusions = opening[:],
    }
    result := plants.generate(
        {species = .Bougainvillea, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    for segment in result.plant.segments {
        midpoint := (segment.start + segment.end) * .5
        midpoint_inside :=
            midpoint[0] >= opening[0].minimum_x &&
            midpoint[0] <= opening[0].maximum_x &&
            midpoint[1] >= opening[0].minimum_y &&
            midpoint[1] <= opening[0].maximum_y
        testing.expect(t, !midpoint_inside)
    }
}

@(test)
bougainvillea_routes_from_an_interior_corner_beneath_stacked_windows :: proc(t: ^testing.T) {
    windows := [2]plants.Rect{{-3.45, 1.05, -1.35, 2.35}, {-3.45, 3.65, -1.35, 4.95}}
    support := plants.Support_Surface {
        width             = 8,
        height            = 7,
        plane_z           = .18,
        root_x            = -2.45,
        left_corner_x     = -4.16,
        left_return_depth = 3.9,
        planter           = true,
        exclusions        = windows[:],
    }
    result := plants.generate(
        {species = .Bougainvillea, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)

    corner_strip_count, return_wall_count, right_jamb_count, between_windows_count, above_windows_count :=
        0, 0, 0, 0, 0
    maximum_return_z := support.plane_z
    for attachment in result.plant.attachments {
        for window in windows {
            inside :=
                attachment.position[0] >= window.minimum_x &&
                attachment.position[0] <= window.maximum_x &&
                attachment.position[1] >= window.minimum_y &&
                attachment.position[1] <= window.maximum_y
            testing.expectf(
                t,
                !inside,
                "inside window position: %.3f %.3f",
                attachment.position[0],
                attachment.position[1],
            )
        }
        if attachment.position[0] <= windows[0].minimum_x - .08 do corner_strip_count += 1
        if attachment.position[2] >= support.plane_z + .35 {
            return_wall_count += 1
            maximum_return_z = max(maximum_return_z, attachment.position[2])
        }
        if attachment.position[0] >= windows[0].maximum_x + .08 &&
           attachment.position[1] >= windows[0].minimum_y &&
           attachment.position[1] <= windows[1].maximum_y + support.height * .12 {
            right_jamb_count += 1
        }
        if attachment.position[1] > windows[0].maximum_y && attachment.position[1] < windows[1].minimum_y {
            between_windows_count += 1
        }
        if attachment.position[1] > windows[1].maximum_y do above_windows_count += 1
    }
    testing.expectf(t, corner_strip_count >= 12, "attachments using the interior-corner strip: %d", corner_strip_count)
    testing.expectf(t, return_wall_count >= 200, "attachments wrapping onto the return wall: %d", return_wall_count)
    testing.expectf(t, maximum_return_z >= support.plane_z + 2.5, "maximum return-wall depth: %.3f", maximum_return_z)
    testing.expectf(t, right_jamb_count >= 12, "attachments using the right window jamb: %d", right_jamb_count)
    testing.expectf(t, between_windows_count >= 8, "attachments between stacked windows: %d", between_windows_count)
    testing.expectf(t, above_windows_count >= 12, "attachments above stacked windows: %d", above_windows_count)
}

@(test)
bougainvillea_seeds_choose_distinct_window_routes :: proc(t: ^testing.T) {
    windows := [2]plants.Rect{{-3.45, 1.05, -1.35, 2.35}, {-3.45, 3.65, -1.35, 4.95}}
    support := plants.Support_Surface {
        width             = 8,
        height            = 7,
        plane_z           = .18,
        root_x            = -2.45,
        left_corner_x     = -4.16,
        left_return_depth = 3.9,
        planter           = true,
        exclusions        = windows[:],
    }
    route_signatures: [16]u64
    distinct_signatures := 0
    for seed in 0 ..< len(route_signatures) {
        result := plants.generate(
            {
                species = .Bougainvillea,
                seed = u64(seed),
                maturity = 1,
                detail = .Near,
                habit = .Wall_Trained,
                support = &support,
            },
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        signature: u64
        for attachment in result.plant.attachments {
            x_band := clamp(int((attachment.position[0] / support.width + .5) * 8), 0, 7)
            y_band := clamp(int(attachment.position[1] / support.height * 8), 0, 7)
            signature |= u64(1) << u64(y_band * 8 + x_band)
        }
        route_signatures[seed] = signature
        unique := true
        for previous in 0 ..< seed {
            if route_signatures[previous] == signature {
                unique = false
                break
            }
        }
        if unique do distinct_signatures += 1
        plants.destroy(&result)
    }
    testing.expectf(
        t,
        distinct_signatures >= 8,
        "distinct 8x8 route signatures across 16 seeds: %d",
        distinct_signatures,
    )
}

@(test)
bougainvillea_preserves_a_broad_generated_fan_above_an_opening :: proc(t: ^testing.T) {
    opening := [1]plants.Rect{{-1.18, 0, 1.18, 2.78}}
    support := plants.Support_Surface {
        width      = 3.25,
        height     = 3.55,
        root_x     = -1.48,
        exclusions = opening[:],
    }
    result := plants.generate(
        {species = .Bougainvillea, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)

    minimum_x, maximum_x := f32(1e9), f32(-1e9)
    upper_attachment_count := 0
    occupied_lintel_bands: [4]bool
    for attachment in result.plant.attachments {
        if attachment.position[1] < opening[0].maximum_y do continue
        minimum_x = min(minimum_x, attachment.position[0])
        maximum_x = max(maximum_x, attachment.position[0])
        normalized_x := clamp(attachment.position[0] / support.width + .5, f32(0), f32(.999))
        occupied_lintel_bands[clamp(int(normalized_x * 4), 0, 3)] = true
        upper_attachment_count += 1
    }
    occupied_count := 0
    for occupied in occupied_lintel_bands {
        if occupied do occupied_count += 1
    }
    testing.expect(t, upper_attachment_count >= 8)
    testing.expect(t, maximum_x - minimum_x >= support.width * .48)
    testing.expect(t, occupied_count >= 3)
}

@(test)
bougainvillea_distributes_foliage_along_routed_canes :: proc(t: ^testing.T) {
    support: plants.Support_Surface
    exclusions: [2]plants.Rect
    plant_support(&support, &exclusions)
    result := plants.generate(
        {species = .Bougainvillea, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)

    maximum_nearest_distance_squared := f32(0)
    inspected_segment_count := 0
    for segment in result.plant.segments {
        midpoint := (segment.start + segment.end) * .5
        eligible := (segment.depth >= 1 && midpoint[1] >= support.height * .20) || midpoint[1] >= support.height * .42
        for exclusion in support.exclusions {
            if midpoint[0] >= exclusion.minimum_x &&
               midpoint[0] <= exclusion.maximum_x &&
               midpoint[1] >= exclusion.minimum_y &&
               midpoint[1] <= exclusion.maximum_y {
                eligible = false
                break
            }
        }
        if !eligible do continue
        nearest_distance_squared := f32(1e9)
        for attachment in result.plant.attachments {
            if attachment.kind != .Leaf do continue
            delta := attachment.position - midpoint
            nearest_distance_squared = min(nearest_distance_squared, linalg.dot(delta, delta))
        }
        maximum_nearest_distance_squared = max(maximum_nearest_distance_squared, nearest_distance_squared)
        inspected_segment_count += 1
    }
    testing.expect(t, inspected_segment_count >= 24)
    upper_bands: [8]int
    minimum_upper_x, maximum_upper_x := f32(1e9), f32(-1e9)
    for attachment in result.plant.attachments {
        if attachment.kind != .Leaf || attachment.position[1] < 2.8 do continue
        normalized_x := clamp(attachment.position[0] / support.width + .5, f32(0), f32(.999))
        upper_bands[clamp(int(normalized_x * 8), 0, 7)] += 1
        minimum_upper_x = min(minimum_upper_x, attachment.position[0])
        maximum_upper_x = max(maximum_upper_x, attachment.position[0])
    }
    occupied_upper_bands := 0
    for count in upper_bands {
        if count > 0 do occupied_upper_bands += 1
    }
    testing.expectf(
        t,
        occupied_upper_bands >= 6,
        "upper foliage bands: %v; total attachments: %d",
        upper_bands,
        len(result.plant.attachments),
    )
    testing.expectf(
        t,
        maximum_upper_x - minimum_upper_x >= support.width * .70,
        "upper foliage spread %.3f across %.3f-wide support",
        maximum_upper_x - minimum_upper_x,
        support.width,
    )
    testing.expectf(
        t,
        maximum_nearest_distance_squared <= .36,
        "maximum routed-cane foliage gap squared: %.3f",
        maximum_nearest_distance_squared,
    )
}

@(test)
climbing_projection_keeps_branch_junctions_connected :: proc(t: ^testing.T) {
    support: plants.Support_Surface
    exclusions: [2]plants.Rect
    plant_support(&support, &exclusions)
    result := plants.generate(
        {species = .Bougainvillea, seed = 73, maturity = 1, detail = .Near, habit = .Wall_Trained, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)

    disconnected_count := 0
    for segment, segment_index in result.plant.segments {
        if segment_index == 0 || segment.start[1] <= .01 do continue
        connected := false
        for candidate in result.plant.segments {
            delta := candidate.end - segment.start
            if linalg.dot(delta, delta) <= 1e-8 {
                connected = true
                break
            }
        }
        if !connected do disconnected_count += 1
    }
    testing.expectf(t, disconnected_count == 0, "disconnected routed branch starts: %d", disconnected_count)
}

@(test)
grapevine_routes_generated_growth_onto_trellis_wire_tiers :: proc(t: ^testing.T) {
    support := plants.Support_Surface {
        width   = 5.8,
        height  = 2.65,
        root_x  = -2.62,
        planter = false,
    }
    result := plants.generate(
        {species = .Grapevine, seed = 73, maturity = 1, detail = .Near, habit = .Trellised, support = &support},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)

    minimum_x, maximum_x := f32(1000), f32(-1000)
    maximum_y := f32(0)
    trunk_segment_count, cordon_segment_count := 0, 0
    spur_segment_count, shoot_segment_count := 0, 0
    for segment in result.plant.segments {
        minimum_x = min(minimum_x, min(segment.start[0], segment.end[0]))
        maximum_x = max(maximum_x, max(segment.start[0], segment.end[0]))
        maximum_y = max(maximum_y, max(segment.start[1], segment.end[1]))
        if segment.depth == -23 do trunk_segment_count += 1
        if segment.depth == -20 do cordon_segment_count += 1
        if segment.depth == -22 do spur_segment_count += 1
        if segment.depth == -21 do shoot_segment_count += 1
        testing.expect(t, segment.start[0] >= -support.width * .48 - .001)
        testing.expect(t, segment.start[0] <= support.width * .48 + .001)
        testing.expect(t, segment.end[0] >= -support.width * .48 - .001)
        testing.expect(t, segment.end[0] <= support.width * .48 + .001)
        testing.expect(t, segment.start[1] >= 0 && segment.start[1] <= support.height)
        testing.expect(t, segment.end[1] >= 0 && segment.end[1] <= support.height)
    }
    testing.expect(t, maximum_x - minimum_x > support.width * .75)
    testing.expect(t, maximum_y > support.height * .86)
    testing.expect_value(t, trunk_segment_count, 3)
    testing.expect_value(t, cordon_segment_count, 12)
    testing.expect_value(t, spur_segment_count, 10)
    testing.expect(t, shoot_segment_count >= 40)
    testing.expect(t, shoot_segment_count <= 110)
}

@(test)
grapevine_vsp_network_preserves_permanent_wood_and_variable_shoots_across_seeds :: proc(t: ^testing.T) {
    support := plants.Support_Surface {
        width  = 8,
        height = 7,
        root_x = 0,
    }
    minimum_shoot_segments, maximum_shoot_segments := 1_000, 0
    for seed in u64(70) ..= 76 {
        result := plants.generate(
            {species = .Grapevine, seed = seed, maturity = 1, detail = .Near, habit = .Trellised, support = &support},
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        trunk_count, cordon_count, spur_count, shoot_count := 0, 0, 0, 0
        maximum_y := f32(0)
        for segment in result.plant.segments {
            maximum_y = max(maximum_y, max(segment.start[1], segment.end[1]))
            switch segment.depth {
            case -23:
                trunk_count += 1
            case -20:
                cordon_count += 1
            case -22:
                spur_count += 1
            case -21:
                shoot_count += 1
            }
        }
        testing.expect_value(t, trunk_count, 3)
        testing.expect_value(t, cordon_count, 12)
        testing.expect_value(t, spur_count, 10)
        testing.expect(t, maximum_y > support.height * .86)
        testing.expect(t, shoot_count >= 35 && shoot_count <= 110)
        leaf_count := 0
        for attachment in result.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
        }
        // Fruit and tendrils accompany rather than replace the leaf at each
        // grapevine phytomer.
        testing.expect_value(t, leaf_count, shoot_count)
        minimum_shoot_segments = min(minimum_shoot_segments, shoot_count)
        maximum_shoot_segments = max(maximum_shoot_segments, shoot_count)
        plants.destroy(&result)
    }
    testing.expect(t, maximum_shoot_segments > minimum_shoot_segments)
}

@(test)
plant_species_preserve_characteristic_silhouettes :: proc(t: ^testing.T) {
    cypress := plants.generate(
        {species = .Italian_Cypress, seed = 8, maturity = 1, detail = .Near, habit = .Free_Standing},
    )
    rosemary := plants.generate({species = .Rosemary, seed = 8, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&cypress)
    defer plants.destroy(&rosemary)
    cypress_width := cypress.plant.bounds.maximum[0] - cypress.plant.bounds.minimum[0]
    cypress_height := cypress.plant.bounds.maximum[1] - cypress.plant.bounds.minimum[1]
    rosemary_height := rosemary.plant.bounds.maximum[1] - rosemary.plant.bounds.minimum[1]
    rosemary_width := max(
        rosemary.plant.bounds.maximum[0] - rosemary.plant.bounds.minimum[0],
        rosemary.plant.bounds.maximum[2] - rosemary.plant.bounds.minimum[2],
    )
    testing.expect(t, cypress_height > cypress_width * 2)
    testing.expect(t, rosemary_height < cypress_height * .5)
    // A mature rosemary is a broad but upright mound. This guards against
    // grammars that collapse its leaders into a low radial candelabra.
    testing.expect(t, rosemary_height > rosemary_width * .55)
    testing.expect(t, rosemary_height < rosemary_width * 1.8)
}

@(test)
hydrangea_catalog_separates_pruned_bush_and_tree_forms :: proc(t: ^testing.T) {
    bush := plants.generate(
        {species = .Hydrangea_Bush, seed = 91, maturity = 1, detail = .Near, habit = .Free_Standing},
    )
    tree := plants.generate(
        {species = .Hydrangea_Tree, seed = 91, maturity = 1, detail = .Near, habit = .Free_Standing},
    )
    defer plants.destroy(&bush)
    defer plants.destroy(&tree)
    testing.expect_value(t, bush.error, plants.Generate_Error.None)
    testing.expect_value(t, tree.error, plants.Generate_Error.None)

    bush_height := bush.plant.bounds.maximum[1] - bush.plant.bounds.minimum[1]
    tree_height := tree.plant.bounds.maximum[1] - tree.plant.bounds.minimum[1]
    bush_width := max(
        bush.plant.bounds.maximum[0] - bush.plant.bounds.minimum[0],
        bush.plant.bounds.maximum[2] - bush.plant.bounds.minimum[2],
    )
    tree_width := max(
        tree.plant.bounds.maximum[0] - tree.plant.bounds.minimum[0],
        tree.plant.bounds.maximum[2] - tree.plant.bounds.minimum[2],
    )
    testing.expectf(
        t,
        bush_height >= .65 && bush_height <= 1.8,
        "bush hydrangea height %.2fm is out of scale",
        bush_height,
    )
    testing.expectf(
        t,
        bush_width >= .75 && bush_width <= 2.4,
        "bush hydrangea width %.2fm is out of scale",
        bush_width,
    )
    testing.expectf(
        t,
        tree_height >= 1.5 && tree_height <= 4.5,
        "tree hydrangea height %.2fm is out of scale",
        tree_height,
    )
    testing.expectf(
        t,
        tree_width >= .75 && tree_width <= 2.8,
        "tree hydrangea width %.2fm is out of scale",
        tree_width,
    )
    testing.expectf(
        t,
        tree_height > bush_height * 1.25,
        "tree hydrangea %.2fm does not clear bush form %.2fm",
        tree_height,
        bush_height,
    )
    bush_flowers, tree_flowers := 0, 0
    interior_flowers := 0
    for attachment in bush.plant.attachments {
        if attachment.kind == .Flower {
            bush_flowers += 1
            if attachment.depth != -9 do interior_flowers += 1
        }
    }
    for attachment in tree.plant.attachments {
        if attachment.kind == .Flower {
            tree_flowers += 1
            if attachment.depth != -9 do interior_flowers += 1
        }
    }
    testing.expect(t, bush_flowers >= 4)
    testing.expect(t, tree_flowers >= 4)
    testing.expect_value(t, interior_flowers, 0)
    testing.expect_value(t, plants.leaf_cluster_size(.Hydrangea_Bush, .Near, 1), 2)
    testing.expect_value(t, plants.leaf_cluster_size(.Hydrangea_Tree, .Near, 1), 2)
}

@(test)
hydrangea_far_detail_preserves_terminal_mopheads :: proc(t: ^testing.T) {
    result := plants.generate(
        {species = .Hydrangea_Bush, seed = 91, maturity = 1, detail = .Far, habit = .Free_Standing},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    flower_count := 0
    for attachment in result.plant.attachments {
        if attachment.kind == .Flower {
            flower_count += 1
            testing.expect_value(t, attachment.depth, -9)
        }
    }
    testing.expectf(t, flower_count >= 16, "far hydrangea lost its bushy terminal mophead mass (%d)", flower_count)
    testing.expect_value(t, plants.leaf_cluster_size(.Hydrangea_Bush, .Far, 1), 2)
}

@(test)
juvenile_hydrangea_omits_dormant_flower_frames :: proc(t: ^testing.T) {
    result := plants.generate(
        {species = .Hydrangea_Bush, seed = 91, maturity = .20, detail = .Near, habit = .Free_Standing},
    )
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    for attachment in result.plant.attachments {
        testing.expect(t, attachment.depth != -9)
        testing.expect(t, attachment.kind != .Flower)
    }
}

@(test)
mature_hydrangea_stays_bushy_and_floriferous_across_seeds :: proc(t: ^testing.T) {
    seeds := [5]u64{0, 1, 73, 91, 999}
    for seed in seeds {
        result := plants.generate(
            {species = .Hydrangea_Bush, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, result.error, plants.Generate_Error.None)
        if result.error != .None {
            plants.destroy(&result)
            continue
        }
        width := max(
            result.plant.bounds.maximum[0] - result.plant.bounds.minimum[0],
            result.plant.bounds.maximum[2] - result.plant.bounds.minimum[2],
        )
        height := result.plant.bounds.maximum[1] - result.plant.bounds.minimum[1]
        flower_count := 0
        for attachment in result.plant.attachments {
            if attachment.kind == .Flower {
                flower_count += 1
                testing.expect_value(t, attachment.depth, -9)
            }
        }
        testing.expectf(t, flower_count == 24, "seed %d emitted %d terminal heads", seed, flower_count)
        testing.expectf(t, width >= .75, "seed %d collapsed to %.2fm width", seed, width)
        testing.expectf(
            t,
            height >= width * .35 && height <= width * 1.4,
            "seed %d lost bush proportions (%.2fm wide x %.2fm tall)",
            seed,
            width,
            height,
        )
        plants.destroy(&result)
    }
}

@(test)
agapanthus_separates_a_basal_strap_rosette_from_elevated_umbels :: proc(t: ^testing.T) {
    result := plants.generate({species = .Agapanthus, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&result)
    testing.expect_value(t, result.error, plants.Generate_Error.None)
    testing.expect_value(t, len(result.plant.segments), 4)
    testing.expect_value(t, plants.leaf_cluster_size(.Agapanthus, .Near, 1), 1)
    leaf_count, flower_count := 0, 0
    lowest_flower := f32(1000)
    highest_leaf_anchor := f32(0)
    for attachment in result.plant.attachments {
        if attachment.kind == .Leaf {
            leaf_count += 1
            highest_leaf_anchor = max(highest_leaf_anchor, attachment.position[1])
        }
        if attachment.kind == .Flower {
            flower_count += 1
            lowest_flower = min(lowest_flower, attachment.position[1])
            testing.expect_value(t, attachment.depth, -5)
        }
    }
    testing.expect_value(t, leaf_count, 22)
    testing.expect_value(t, flower_count, 3)
    testing.expect(t, lowest_flower > .50)
    testing.expect(t, lowest_flower > highest_leaf_anchor + .45)
}

@(test)
new_ornamental_catalog_species_generate_deterministically :: proc(t: ^testing.T) {
    support: plants.Support_Surface
    exclusions: [2]plants.Rect
    plant_support(&support, &exclusions)
    ornamentals := [6]plants.Species {
        .Wisteria,
        .Climbing_Rose,
        .Hydrangea_Bush,
        .Hydrangea_Tree,
        .Agapanthus,
        .Star_Jasmine,
    }
    for species in ornamentals {
        habit := plants.default_habit(species)
        support_pointer: ^plants.Support_Surface
        if habit != .Free_Standing do support_pointer = &support
        first := plants.generate(
            {
                species = species,
                seed = 0x0a71d3,
                maturity = 1,
                detail = .Near,
                habit = habit,
                support = support_pointer,
            },
        )
        second := plants.generate(
            {
                species = species,
                seed = 0x0a71d3,
                maturity = 1,
                detail = .Near,
                habit = habit,
                support = support_pointer,
            },
        )
        defer plants.destroy(&first)
        defer plants.destroy(&second)
        testing.expectf(t, first.error == .None, "%s failed generation: %v", plants.species_name(species), first.error)
        testing.expect(t, len(first.plant.segments) > 0)
        testing.expect_value(t, len(first.plant.segments), len(second.plant.segments))
        testing.expect_value(t, len(first.plant.attachments), len(second.plant.attachments))
        testing.expect_value(t, first.plant.bounds, second.plant.bounds)
    }
}

@(test)
rosemary_needles_form_staggered_shoot_sprays :: proc(t: ^testing.T) {
    rosemary := plants.generate({species = .Rosemary, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&rosemary)
    testing.expect_value(t, rosemary.error, plants.Generate_Error.None)
    testing.expect(t, len(rosemary.plant.attachments) >= plants.leaf_cluster_size(.Rosemary, .Near, 1))
    first := rosemary.plant.attachments[0].position
    maximum_offset := f32(0)
    station_sample_count := min(len(rosemary.plant.attachments), plants.leaf_cluster_size(.Rosemary, .Near, 1) * 4)
    for attachment in rosemary.plant.attachments[1:station_sample_count] {
        delta := attachment.position - first
        maximum_offset = max(maximum_offset, f32(math.sqrt(f64(linalg.dot(delta, delta)))))
    }
    testing.expect(t, maximum_offset > rosemary.plant.attachments[0].leaf.length)

    crown_height := rosemary.plant.bounds.maximum[1] - rosemary.plant.bounds.minimum[1]
    lowest_needle := rosemary.plant.bounds.maximum[1]
    for attachment in rosemary.plant.attachments {
        if attachment.kind != .Leaf do continue
        lowest_needle = min(lowest_needle, attachment.position[1])
        testing.expect(t, attachment.position[1] >= 0)
    }
    // Foliage should clothe the basal shoots instead of leaving a miniature
    // tree trunk beneath a terminal crown.
    testing.expect(t, lowest_needle < crown_height * .22)
    testing.expect_value(t, plants.leaf_cluster_size(.Rosemary, .Near, 1), 2)
    testing.expect_value(t, len(rosemary.plant.segments), 80)
    maximum_stem_radius := f32(0)
    for segment in rosemary.plant.segments do maximum_stem_radius = max(maximum_stem_radius, segment.radius_start)
    testing.expect(t, maximum_stem_radius < .003)
}

@(test)
lavender_preserves_a_rounded_flowering_habit_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        lavender := plants.generate(
            {species = .Lavender, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, lavender.error, plants.Generate_Error.None)
        width := max(
            lavender.plant.bounds.maximum[0] - lavender.plant.bounds.minimum[0],
            lavender.plant.bounds.maximum[2] - lavender.plant.bounds.minimum[2],
        )
        height := lavender.plant.bounds.maximum[1] - lavender.plant.bounds.minimum[1]
        testing.expect(t, height > width * .58)
        testing.expect(t, height < width * 1.65)
        leaf_count, flower_count := 0, 0
        interior_flower_count := 0
        for attachment in lavender.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Flower {
                flower_count += 1
                if attachment.depth != -7 do interior_flower_count += 1
            }
        }
        testing.expect(t, leaf_count > 0)
        testing.expect(t, flower_count >= 8)
        testing.expect_value(t, interior_flower_count, 0)
        testing.expect_value(t, plants.leaf_cluster_size(.Lavender, .Near, 1), 2)
        plants.destroy(&lavender)
    }
}

@(test)
thyme_remains_a_low_flowering_mat_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        thyme := plants.generate({species = .Thyme, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing})
        testing.expect_value(t, thyme.error, plants.Generate_Error.None)
        width := max(
            thyme.plant.bounds.maximum[0] - thyme.plant.bounds.minimum[0],
            thyme.plant.bounds.maximum[2] - thyme.plant.bounds.minimum[2],
        )
        height := thyme.plant.bounds.maximum[1] - thyme.plant.bounds.minimum[1]
        testing.expect(t, width > 0)
        testing.expect(t, height > width * .12)
        testing.expect(t, height < width * .72)
        leaf_count, flower_count := 0, 0
        interior_flower_count := 0
        maximum_stem_radius := f32(0)
        for segment in thyme.plant.segments {
            maximum_stem_radius = max(maximum_stem_radius, segment.radius_start)
        }
        for attachment in thyme.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Flower {
                flower_count += 1
                if attachment.depth != -8 do interior_flower_count += 1
            }
        }
        testing.expect(t, flower_count >= 8)
        testing.expect(t, leaf_count > flower_count * 2)
        testing.expect(t, maximum_stem_radius < plants.leaf_traits(.Thyme, 0, 1).length * .35)
        testing.expect_value(t, interior_flower_count, 0)
        testing.expect_value(t, plants.leaf_cluster_size(.Thyme, .Near, 1), 2)
        testing.expect_value(t, len(thyme.plant.segments), 48)
        plants.destroy(&thyme)
    }
}

@(test)
sage_preserves_a_broad_leafy_mound_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        sage := plants.generate({species = .Sage, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing})
        testing.expect_value(t, sage.error, plants.Generate_Error.None)
        width := max(
            sage.plant.bounds.maximum[0] - sage.plant.bounds.minimum[0],
            sage.plant.bounds.maximum[2] - sage.plant.bounds.minimum[2],
        )
        height := sage.plant.bounds.maximum[1] - sage.plant.bounds.minimum[1]
        testing.expect(t, height > width * .32)
        testing.expect(t, height < width * 1.35)
        leaf_count, flower_count := 0, 0
        interior_flower_count := 0
        for attachment in sage.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Flower {
                flower_count += 1
                if attachment.depth != -6 do interior_flower_count += 1
            }
        }
        testing.expect(t, flower_count >= 8)
        testing.expect(t, leaf_count > flower_count)
        testing.expect_value(t, interior_flower_count, 0)
        testing.expect_value(t, plants.leaf_cluster_size(.Sage, .Near, 1), 2)
        plants.destroy(&sage)
    }
}

@(test)
pelargonium_preserves_a_low_leafy_flowering_mound_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        pelargonium := plants.generate(
            {species = .Pelargonium, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, pelargonium.error, plants.Generate_Error.None)
        width := max(
            pelargonium.plant.bounds.maximum[0] - pelargonium.plant.bounds.minimum[0],
            pelargonium.plant.bounds.maximum[2] - pelargonium.plant.bounds.minimum[2],
        )
        height := pelargonium.plant.bounds.maximum[1] - pelargonium.plant.bounds.minimum[1]
        leaf_count, flower_count := 0, 0
        highest_leaf, highest_flower := f32(0), f32(0)
        for attachment in pelargonium.plant.attachments {
            if attachment.kind == .Leaf {
                leaf_count += 1
                highest_leaf = max(highest_leaf, attachment.position[1])
            }
            if attachment.kind == .Flower {
                flower_count += 1
                highest_flower = max(highest_flower, attachment.position[1])
            }
        }
        maximum_stem_radius := f32(0)
        for segment in pelargonium.plant.segments {
            maximum_stem_radius = max(maximum_stem_radius, segment.radius_start)
        }
        testing.expect(t, width > 0)
        testing.expect(t, height > width * .30)
        testing.expect(t, height < width * 1.35)
        testing.expect(t, flower_count >= 6)
        testing.expect(t, leaf_count > flower_count)
        testing.expect(t, highest_flower > highest_leaf)
        testing.expect(t, maximum_stem_radius < .022)
        testing.expect_value(t, plants.leaf_cluster_size(.Pelargonium, .Near, 1), 1)
        testing.expect_value(t, len(pelargonium.plant.segments), 54)
        testing.expect(t, maximum_stem_radius < .004)
        plants.destroy(&pelargonium)
    }
}

@(test)
myrtle_preserves_a_fine_multistem_shrub_habit_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        myrtle := plants.generate(
            {species = .Myrtle, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, myrtle.error, plants.Generate_Error.None)
        width := max(
            myrtle.plant.bounds.maximum[0] - myrtle.plant.bounds.minimum[0],
            myrtle.plant.bounds.maximum[2] - myrtle.plant.bounds.minimum[2],
        )
        height := myrtle.plant.bounds.maximum[1] - myrtle.plant.bounds.minimum[1]
        testing.expect(t, height > width * .78)
        testing.expectf(
            t,
            height < width * 1.60,
            "myrtle seed %d is too narrow: %.2fm high x %.2fm wide",
            seed,
            height,
            width,
        )
        basal_stems := 0
        maximum_radius := f32(0)
        for segment in myrtle.plant.segments {
            maximum_radius = max(maximum_radius, segment.radius_start)
            if segment.start[1] < height * .08 do basal_stems += 1
        }
        testing.expect(t, basal_stems >= 5)
        testing.expect(t, maximum_radius < plants.leaf_traits(.Myrtle, 0, 1).length * .5)
        testing.expect(t, len(myrtle.plant.attachments) > len(myrtle.plant.segments))
        testing.expect_value(t, plants.leaf_cluster_size(.Myrtle, .Near, 1), 2)
        plants.destroy(&myrtle)
    }
}

@(test)
mastic_preserves_a_dense_rounded_multistem_habit_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        mastic := plants.generate(
            {species = .Mastic, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, mastic.error, plants.Generate_Error.None)
        width := max(
            mastic.plant.bounds.maximum[0] - mastic.plant.bounds.minimum[0],
            mastic.plant.bounds.maximum[2] - mastic.plant.bounds.minimum[2],
        )
        height := mastic.plant.bounds.maximum[1] - mastic.plant.bounds.minimum[1]
        testing.expect(t, width > 0)
        testing.expect(t, height > width * .38)
        testing.expect(t, height < width * 1.35)
        basal_stems := 0
        maximum_radius := f32(0)
        leaf_count := 0
        for segment in mastic.plant.segments {
            maximum_radius = max(maximum_radius, segment.radius_start)
            if segment.start[1] < height * .08 do basal_stems += 1
        }
        for attachment in mastic.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
        }
        testing.expect(t, basal_stems >= 6)
        testing.expect(t, maximum_radius < plants.leaf_traits(.Mastic, 0, 1).length * .5)
        testing.expect(t, leaf_count > len(mastic.plant.segments))
        testing.expect_value(t, plants.leaf_cluster_size(.Mastic, .Near, 1), 2)
        plants.destroy(&mastic)
    }
}

@(test)
oleander_preserves_a_fine_caned_flowering_shrub_habit_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        oleander := plants.generate(
            {species = .Oleander, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, oleander.error, plants.Generate_Error.None)
        width := max(
            oleander.plant.bounds.maximum[0] - oleander.plant.bounds.minimum[0],
            oleander.plant.bounds.maximum[2] - oleander.plant.bounds.minimum[2],
        )
        height := oleander.plant.bounds.maximum[1] - oleander.plant.bounds.minimum[1]
        testing.expect(t, width > 0)
        testing.expect(t, height > width * .58)
        testing.expect(t, height < width * 1.8)
        basal_stems := 0
        maximum_radius := f32(0)
        leaf_count, flower_count := 0, 0
        for segment in oleander.plant.segments {
            maximum_radius = max(maximum_radius, segment.radius_start)
            if segment.start[1] < height * .08 do basal_stems += 1
        }
        for attachment in oleander.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Flower do flower_count += 1
        }
        testing.expect(t, basal_stems >= 5)
        testing.expect(t, maximum_radius < plants.leaf_traits(.Oleander, 0, 1).length * .3)
        testing.expect(t, flower_count >= 8)
        testing.expect(t, leaf_count > flower_count)
        plants.destroy(&oleander)
    }
}

@(test)
pomegranate_preserves_a_leafy_suckering_shrub_habit_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        pomegranate := plants.generate(
            {species = .Pomegranate, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, pomegranate.error, plants.Generate_Error.None)
        width := max(
            pomegranate.plant.bounds.maximum[0] - pomegranate.plant.bounds.minimum[0],
            pomegranate.plant.bounds.maximum[2] - pomegranate.plant.bounds.minimum[2],
        )
        height := pomegranate.plant.bounds.maximum[1] - pomegranate.plant.bounds.minimum[1]
        testing.expect(t, width > 0)
        testing.expect(t, height > width * .50)
        testing.expect(t, height < width * 1.75)
        basal_stems := 0
        maximum_radius := f32(0)
        leaf_count, flower_count, fruit_count := 0, 0, 0
        interior_reproductive_count := 0
        for segment in pomegranate.plant.segments {
            maximum_radius = max(maximum_radius, segment.radius_start)
            if segment.start[1] < height * .08 do basal_stems += 1
        }
        for attachment in pomegranate.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Flower {
                flower_count += 1
                if attachment.depth < 1 do interior_reproductive_count += 1
            }
            if attachment.kind == .Fruit {
                fruit_count += 1
                if attachment.depth < 1 do interior_reproductive_count += 1
            }
        }
        testing.expect(t, basal_stems >= 5)
        testing.expect(t, maximum_radius < plants.leaf_traits(.Pomegranate, 0, 1).length * .5)
        testing.expect(t, flower_count > 0)
        testing.expect(t, fruit_count > 0)
        testing.expect_value(t, interior_reproductive_count, 0)
        testing.expect(t, leaf_count > (flower_count + fruit_count) * 3)
        plants.destroy(&pomegranate)
    }
}

@(test)
prickly_pear_preserves_a_grounded_layered_pad_clump_across_seeds :: proc(t: ^testing.T) {
    for seed in u64(70) ..= 76 {
        cactus := plants.generate(
            {species = .Prickly_Pear, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, cactus.error, plants.Generate_Error.None)
        width := max(
            cactus.plant.bounds.maximum[0] - cactus.plant.bounds.minimum[0],
            cactus.plant.bounds.maximum[2] - cactus.plant.bounds.minimum[2],
        )
        height := cactus.plant.bounds.maximum[1] - cactus.plant.bounds.minimum[1]
        testing.expect(t, width > 0)
        testing.expect(t, height > width * .30)
        testing.expect(t, height < width * 1.55)
        pad_count, basal_pad_count, middle_pad_count, upper_pad_count, fruit_count := 0, 0, 0, 0, 0
        maximum_joint_radius := f32(0)
        for segment in cactus.plant.segments {
            maximum_joint_radius = max(maximum_joint_radius, segment.radius_start)
        }
        for attachment in cactus.plant.attachments {
            if attachment.kind == .Leaf {
                pad_count += 1
                if attachment.position[1] < height * .08 do basal_pad_count += 1
                if attachment.depth == 1 do middle_pad_count += 1
                if attachment.depth >= 2 do upper_pad_count += 1
            }
            if attachment.kind == .Fruit do fruit_count += 1
        }
        testing.expect(t, pad_count >= 12)
        testing.expect(t, basal_pad_count >= 3)
        testing.expect(t, middle_pad_count >= 6)
        testing.expect(t, upper_pad_count >= 4)
        testing.expect(t, fruit_count > 0)
        testing.expect(t, maximum_joint_radius < plants.leaf_traits(.Prickly_Pear, 0, 1).width * .18)
        plants.destroy(&cactus)
    }
}

@(test)
generated_reproductive_attachments_span_all_lifecycle_stages :: proc(t: ^testing.T) {
    flower_stages: [4]bool
    fruit_stages: [4]bool
    for seed in u64(70) ..= 90 {
        plant := plants.generate(
            {species = .Pomegranate, seed = seed, maturity = 1, detail = .Near, habit = .Free_Standing},
        )
        testing.expect_value(t, plant.error, plants.Generate_Error.None)
        for attachment in plant.plant.attachments {
            switch attachment.stage {
            case .Bud:
                flower_stages[0] = true
            case .Opening:
                flower_stages[1] = true
            case .Half_Open:
                flower_stages[2] = true
            case .Bloom:
                flower_stages[3] = true
            case .Fruit_Set:
                fruit_stages[0] = true
            case .Immature_Fruit:
                fruit_stages[1] = true
            case .Ripening_Fruit:
                fruit_stages[2] = true
            case .Ripe_Fruit:
                fruit_stages[3] = true
            case .None:
            }
            if attachment.kind == .Leaf || attachment.kind == .Thorn || attachment.kind == .Tendril {
                testing.expect_value(t, attachment.stage, plants.Attachment_Stage.None)
            }
        }
        plants.destroy(&plant)
    }
    for present in flower_stages do testing.expect(t, present)
    for present in fruit_stages do testing.expect(t, present)
}

@(test)
young_reproductive_attachments_begin_at_the_earliest_stage :: proc(t: ^testing.T) {
    support: plants.Support_Surface
    exclusions: [2]plants.Rect
    plant_support(&support, &exclusions)
    flower_count := 0
    for seed in u64(70) ..= 90 {
        plant := plants.generate(
            {
                species = .Bougainvillea,
                seed = seed,
                maturity = .20,
                detail = .Near,
                habit = .Wall_Trained,
                support = &support,
            },
        )
        testing.expect_value(t, plant.error, plants.Generate_Error.None)
        for attachment in plant.plant.attachments {
            if attachment.kind != .Flower do continue
            flower_count += 1
            testing.expect_value(t, attachment.stage, plants.Attachment_Stage.Bud)
        }
        plants.destroy(&plant)
    }
    testing.expect(t, flower_count > 0)
}
