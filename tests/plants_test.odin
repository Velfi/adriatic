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
            testing.expect_value(t, result.error, plants.Generate_Error.None)
            testing.expect(t, len(result.plant.segments) > 0)
            segment_limit, attachment_limit := plants.limits(detail)
            testing.expect(t, len(result.plant.segments) <= segment_limit)
            testing.expect(t, len(result.plant.attachments) <= attachment_limit)
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
plant_leaf_density_scales_by_species_and_detail :: proc(t: ^testing.T) {
    testing.expect(t, plants.leaf_cluster_size(.Italian_Cypress, .Near, 1) > plants.leaf_cluster_size(.Fig, .Near, 1))
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
        for attachment in pine.plant.attachments {
            if attachment.kind != .Leaf || attachment.position[1] < height * .48 do continue
            crown_minimum_x = min(crown_minimum_x, attachment.position[0])
            crown_maximum_x = max(crown_maximum_x, attachment.position[0])
            crown_minimum_z = min(crown_minimum_z, attachment.position[2])
            crown_maximum_z = max(crown_maximum_z, attachment.position[2])
            crown_attachment_count += 1
        }
        crown_width := max(crown_maximum_x - crown_minimum_x, crown_maximum_z - crown_minimum_z)
        testing.expect(t, crown_attachment_count >= 48)
        testing.expect(t, crown_width >= plants.leaf_traits(.Stone_Pine, 0, 1).length * 1.5)
        plants.destroy(&pine)
    }
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

    first_wire := f32(.55)
    spacing := (support.height * .96 - first_wire) / 3
    trained_endpoint_count := 0
    occupied_tiers: [4]bool
    for segment in result.plant.segments {
        for endpoint_index in 0 ..< 2 {
            endpoint := endpoint_index == 0 ? segment.start : segment.end
            if endpoint[1] < first_wire - .001 do continue
            tier := clamp(int(math.round(f64((endpoint[1] - first_wire) / spacing))), 0, 3)
            expected_y := first_wire + f32(tier) * spacing
            testing.expect(t, math.abs(endpoint[1] - expected_y) < .001)
            occupied_tiers[tier] = true
            trained_endpoint_count += 1
        }
    }
    occupied_count := 0
    for occupied in occupied_tiers {
        if occupied do occupied_count += 1
    }
    testing.expect(t, trained_endpoint_count >= 24)
    testing.expect(t, occupied_count >= 3)
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
rosemary_needles_form_staggered_shoot_sprays :: proc(t: ^testing.T) {
    rosemary := plants.generate({species = .Rosemary, seed = 73, maturity = 1, detail = .Near, habit = .Free_Standing})
    defer plants.destroy(&rosemary)
    testing.expect_value(t, rosemary.error, plants.Generate_Error.None)
    testing.expect(t, len(rosemary.plant.attachments) >= plants.leaf_cluster_size(.Rosemary, .Near, 1))
    first := rosemary.plant.attachments[0].position
    maximum_offset := f32(0)
    for attachment in rosemary.plant.attachments[1:plants.leaf_cluster_size(.Rosemary, .Near, 1)] {
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
        for attachment in lavender.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Flower do flower_count += 1
        }
        testing.expect(t, leaf_count > 0)
        testing.expect(t, flower_count >= 8)
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
        maximum_stem_radius := f32(0)
        for segment in thyme.plant.segments {
            maximum_stem_radius = max(maximum_stem_radius, segment.radius_start)
        }
        for attachment in thyme.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Flower do flower_count += 1
        }
        testing.expect(t, flower_count >= 8)
        testing.expect(t, leaf_count > flower_count * 2)
        testing.expect(t, maximum_stem_radius < plants.leaf_traits(.Thyme, 0, 1).length * .35)
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
        for attachment in sage.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Flower do flower_count += 1
        }
        testing.expect(t, flower_count >= 8)
        testing.expect(t, leaf_count > flower_count)
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
        testing.expect(t, flower_count >= 12)
        testing.expect(t, leaf_count > flower_count)
        testing.expect(t, highest_flower > highest_leaf)
        testing.expect(t, maximum_stem_radius < .022)
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
        testing.expect(t, height > width * .52)
        testing.expect(t, height < width * 1.9)
        basal_stems := 0
        maximum_radius := f32(0)
        for segment in myrtle.plant.segments {
            maximum_radius = max(maximum_radius, segment.radius_start)
            if segment.start[1] < height * .08 do basal_stems += 1
        }
        testing.expect(t, basal_stems >= 5)
        testing.expect(t, maximum_radius < plants.leaf_traits(.Myrtle, 0, 1).length * .5)
        testing.expect(t, len(myrtle.plant.attachments) > len(myrtle.plant.segments))
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
        for segment in pomegranate.plant.segments {
            maximum_radius = max(maximum_radius, segment.radius_start)
            if segment.start[1] < height * .08 do basal_stems += 1
        }
        for attachment in pomegranate.plant.attachments {
            if attachment.kind == .Leaf do leaf_count += 1
            if attachment.kind == .Flower do flower_count += 1
            if attachment.kind == .Fruit do fruit_count += 1
        }
        testing.expect(t, basal_stems >= 5)
        testing.expect(t, maximum_radius < plants.leaf_traits(.Pomegranate, 0, 1).length * .5)
        testing.expect(t, flower_count > 0)
        testing.expect(t, fruit_count > 0)
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
        pad_count, basal_pad_count, fruit_count := 0, 0, 0
        maximum_joint_radius := f32(0)
        for segment in cactus.plant.segments {
            maximum_joint_radius = max(maximum_joint_radius, segment.radius_start)
        }
        for attachment in cactus.plant.attachments {
            if attachment.kind == .Leaf {
                pad_count += 1
                if attachment.position[1] < height * .08 do basal_pad_count += 1
            }
            if attachment.kind == .Fruit do fruit_count += 1
        }
        testing.expect(t, pad_count >= 12)
        testing.expect(t, basal_pad_count >= 1)
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
