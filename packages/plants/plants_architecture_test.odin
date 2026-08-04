#+feature dynamic-literals
package plants

import plant_structure "../plant_structure"
import "core:math"
import "core:testing"

@(test)
garden_profiles_cover_the_catalog :: proc(t: ^testing.T) {
    for species_index in 0 ..< SPECIES_COUNT {
        species := Species(species_index)
        profile := garden_profile(species)
        testing.expectf(t, profile.mature_height > 0, "%s has no mature height", species_name(species))
        testing.expectf(t, profile.mature_spread > 0, "%s has no mature spread", species_name(species))
        testing.expectf(t, profile.basal_axis_count > 0, "%s has no basal axes", species_name(species))
        testing.expect(t, profile.phyllotactic_angle > 0 && profile.phyllotactic_angle <= math.PI * 2)
    }
}

@(test)
site_context_signature_is_stable_and_environment_sensitive :: proc(t: ^testing.T) {
    testing.expect_value(t, site_context_signature({}), u64(0))
    dry_rock := Site_Context {
        valid            = true,
        aridity          = .84,
        exposure         = .72,
        slope            = .44,
        elevation_meters = 380,
        coast_distance_m = 920,
        substrate        = .Rock,
    }
    nearby_sample := dry_rock
    nearby_sample.aridity += .001
    testing.expect_value(t, site_context_signature(dry_rock), site_context_signature(nearby_sample))

    humid_soil := dry_rock
    humid_soil.aridity = .18
    humid_soil.substrate = .Soil
    testing.expect(t, site_context_signature(dry_rock) != site_context_signature(humid_soil))
}

@(test)
architecture_compile_preserves_renderer_depths :: proc(t: ^testing.T) {
    graph: Plant_Graph
    axis := graph_add_axis(&graph, -1, -1, .Leader, .Orthotropic, 0, 1, 1)
    unit := graph_begin_growth_unit(&graph, axis, 0, 1)
    internode := graph_add_internode(&graph, axis, unit, -1, {0, 0, 0}, {0, 1, 0}, .1, .05, 1, -23)
    graph_add_organ(&graph, internode, 1, .Leaf, {0, 1, 0}, {0, 0, 1}, 0, -23)
    compiled := graph_compile(&graph)
    defer destroy_graph(&graph)
    defer plant_structure.destroy_plant(&compiled.plant)
    testing.expect_value(t, compiled.plant.segments[0].depth, -23)
    testing.expect_value(t, compiled.plant.leaves[0].depth, -23)
}

@(test)
reproductive_organs_use_explicit_species_sites :: proc(t: ^testing.T) {
    cases := []struct {
        species: Species,
        marker:  int,
        source:  plant_structure.Interpret_Result,
    } {
        {.Oleander, -9, oleander_architecture(73, 1, .Near)},
        {.Wisteria, -10, wisteria_architecture(73, 1, .Near)},
        {.Climbing_Rose, -11, climbing_rose_architecture(73, 1, .Near)},
        {.Strawberry_Tree, -12, strawberry_tree_architecture(73, 1, 3)},
        {.Carob, -13, carob_architecture(73, 1, 3)},
    }
    for &item in cases {
        found := false
        for leaf, index in item.source.plant.leaves {
            if leaf.depth != item.marker do continue
            kind := generated_attachment_kind(item.species, 73, index, 1, .Near, leaf.depth)
            testing.expectf(
                t,
                kind == .Flower || kind == .Fruit,
                "%s marker routed to %v",
                species_name(item.species),
                kind,
            )
            found = true
        }
        testing.expectf(t, found, "%s has no explicit reproductive site", species_name(item.species))
        plant_structure.destroy_plant(&item.source.plant)
    }
}

@(test)
twining_support_routes_are_helical_and_deterministic :: proc(t: ^testing.T) {
    axes := [1]Support_Axis{{{0, 0, .1}, {0, 4, .1}, .04}}
    support := Support_Surface {
        width          = 4,
        height         = 4,
        plane_z        = .1,
        axes           = axes[:],
        contact_radius = .05,
    }
    a := route_species_point({0, 1, 0}, &support, 4, 1, .Wall_Trained, 0, .Wisteria)
    b := route_species_point({0, 1, 0}, &support, 4, 1, .Wall_Trained, 0, .Wisteria)
    higher := route_species_point({0, 1.2, 0}, &support, 4, 1, .Wall_Trained, 0, .Wisteria)
    testing.expect_value(t, a, b)
    testing.expect(t, a != higher)
    radial_a := a - plant_structure.Vec3{0, a[1], .1}
    testing.expect(t, math.abs(math.sqrt(radial_a[0] * radial_a[0] + radial_a[2] * radial_a[2]) - .05) < .002)
}

@(test)
architecture_catalog_smoke_test :: proc(t: ^testing.T) {
    support := Support_Surface {
        width   = 8,
        height  = 7,
        plane_z = .1,
        root_x  = -2.7,
    }
    for species_index in 0 ..< SPECIES_COUNT {
        species := Species(species_index)
        for detail in Detail_Level {
            habit := default_habit(species)
            support_pointer: ^Support_Surface
            if habit != .Free_Standing do support_pointer = &support
            generated := generate({species, 73, 1, detail, habit, support_pointer, {}})
            testing.expectf(
                t,
                generated.error == .None,
                "%s %v failed: %v",
                species_name(species),
                detail,
                generated.error,
            )
            testing.expect(t, len(generated.plant.segments) > 0)
            testing.expect_value(t, len(generated.plant.segment_parents), len(generated.plant.segments))
            testing.expect_value(t, len(generated.plant.segment_axes), len(generated.plant.segments))
            testing.expect_value(t, len(generated.plant.segment_ids), len(generated.plant.segments))
            testing.expect_value(t, len(generated.plant.attachment_ids), len(generated.plant.attachments))
            testing.expect_value(t, len(generated.plant.axis_parents), len(generated.plant.axis_roles))
            testing.expect_value(t, len(generated.plant.axis_parents), len(generated.plant.axis_orientations))
            for segment in generated.plant.segments {
                testing.expect(t, segment.radius_start > 0 && segment.radius_end > 0)
                for value in segment.start do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
                for value in segment.end do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
            }
            for parent, segment_index in generated.plant.segment_parents {
                testing.expect(t, parent < segment_index)
                testing.expect(t, parent >= -1)
                testing.expect(t, generated.plant.segment_axes[segment_index] >= 0)
                testing.expect(t, generated.plant.segment_ids[segment_index] != 0)
            }
            for id in generated.plant.attachment_ids do testing.expect(t, id != 0)
            destroy(&generated)
        }
    }
}

@(test)
generated_plants_own_stable_botanical_graphs_across_maturity :: proc(t: ^testing.T) {
    juvenile := generate({species = .Olive, seed = 771, maturity = .45, detail = .Near})
    mature := generate({species = .Olive, seed = 771, maturity = .85, detail = .Near})
    defer destroy(&juvenile)
    defer destroy(&mature)
    testing.expect(t, juvenile.error == .None && mature.error == .None)
    testing.expect(t, len(juvenile.plant.graph.axes) > 0)
    testing.expect(t, len(juvenile.plant.graph.internodes) == len(juvenile.plant.segments))
    testing.expect(t, len(juvenile.plant.graph.organs) == len(juvenile.plant.attachments))
    testing.expect(t, juvenile.plant.graph.axes[0].stable_id == mature.plant.graph.axes[0].stable_id)
    testing.expect(t, juvenile.plant.graph.internodes[0].stable_id == mature.plant.graph.internodes[0].stable_id)
    testing.expect(t, juvenile.plant.graph.internodes[0].age < mature.plant.graph.internodes[0].age)
}

@(test)
generation_workspace_reuses_capacity_without_stale_topology :: proc(t: ^testing.T) {
    generation_workspace_destroy_thread()
    defer generation_workspace_destroy_thread()
    generation_workspace_enabled_for_test = true

    warm := generate({species = .Olive, seed = 551, maturity = 1, detail = .Near})
    testing.expect(t, warm.error == .None)
    warm_segments := len(warm.plant.segments)
    warm_organs := len(warm.plant.attachments)
    destroy(&warm)
    segment_capacity := cap(generation_thread_workspace.segments)
    leaf_capacity := cap(generation_thread_workspace.leaves)
    testing.expect(t, segment_capacity >= GENERATION_WORKSPACE_INITIAL_SEGMENTS)
    testing.expect(t, leaf_capacity >= GENERATION_WORKSPACE_INITIAL_LEAVES)

    repeated := generate({species = .Olive, seed = 551, maturity = 1, detail = .Near})
    testing.expect(t, repeated.error == .None)
    testing.expect_value(t, len(repeated.plant.segments), warm_segments)
    testing.expect_value(t, len(repeated.plant.attachments), warm_organs)
    destroy(&repeated)
    testing.expect_value(t, cap(generation_thread_workspace.segments), segment_capacity)
    testing.expect_value(t, cap(generation_thread_workspace.leaves), leaf_capacity)

    small := generate({species = .Echeveria, seed = 17, maturity = .35, detail = .Far})
    testing.expect(t, small.error == .None)
    testing.expect(t, len(small.plant.segments) < warm_segments)
    destroy(&small)
    testing.expect_value(t, cap(generation_thread_workspace.segments), segment_capacity)
    testing.expect_value(t, cap(generation_thread_workspace.leaves), leaf_capacity)
}

@(test)
graph_builder_keeps_existing_ids_while_revealing_later_organs :: proc(t: ^testing.T) {
    build := proc(maturity: f32) -> Plant_Graph {
        builder := graph_builder_make(.Olive, 707, maturity)
        points := [3]plant_structure.Vec3{{0, 0, 0}, {0, 1, 0}, {.08, 2, 0}}
        _ = graph_builder_leader(&builder, points[:], .18, .06, 1)
        parent := len(builder.graph.internodes) - 1
        graph_builder_whorl(&builder, parent, 3, .18, .8, .04, 20, .25)
        _ = graph_builder_bifurcation(&builder, parent, {0, 1, 0}, {1, 0, 0}, .5, .7, .035, 30, .38)
        _ = graph_builder_renewal_cane(&builder, parent, {-1, .7, 0}, .6, .03, 40, .48)
        _ = graph_builder_runner(&builder, parent, {1, .05, 0}, .5, .02, 50, .58)
        _ = graph_builder_climber(&builder, parent, {0, 1, .3}, .6, .02, 60, .68, true)
        graph_builder_rosette(&builder, parent, 6, .18, 70, .42)
        _ = graph_builder_reproductive(&builder, parent, .8, .Flower, 80, .72)
        return graph_builder_take(&builder)
    }
    early := build(.45)
    late := build(.9)
    defer destroy_graph(&early)
    defer destroy_graph(&late)
    testing.expect(t, len(early.axes) > 1)
    testing.expect(t, len(late.axes) > len(early.axes))
    testing.expect(t, len(late.organs) > len(early.organs))
    testing.expect_value(t, early.axes[0].stable_id, late.axes[0].stable_id)
    testing.expect_value(t, early.internodes[0].stable_id, late.internodes[0].stable_id)
}

@(test)
generated_topology_ids_are_deterministic :: proc(t: ^testing.T) {
    config := Generate_Config {
        species  = .Olive,
        seed     = 73,
        maturity = 1,
        detail   = .Near,
    }
    first := generate(config)
    second := generate(config)
    defer destroy(&first)
    defer destroy(&second)
    testing.expect_value(t, first.error, Generate_Error.None)
    testing.expect_value(t, second.error, Generate_Error.None)
    testing.expect_value(t, len(first.plant.segment_ids), len(second.plant.segment_ids))
    for id, index in first.plant.segment_ids do testing.expect_value(t, id, second.plant.segment_ids[index])
    testing.expect_value(t, len(first.plant.attachment_ids), len(second.plant.attachment_ids))
    for id, index in first.plant.attachment_ids do testing.expect_value(t, id, second.plant.attachment_ids[index])
    testing.expect_value(t, len(first.plant.axis_parents), len(second.plant.axis_parents))
    for parent, index in first.plant.axis_parents do testing.expect_value(t, parent, second.plant.axis_parents[index])
    for role, index in first.plant.axis_roles do testing.expect_value(t, role, second.plant.axis_roles[index])
}

@(test)
succulent_catalog_builds_native_stable_graphs :: proc(t: ^testing.T) {
    species_set := [6]Species{.Aeonium, .Echeveria, .Jade_Plant, .Stonecrop, .Blue_Chalk_Sticks, .Golden_Torch_Cactus}
    for species in species_set {
        juvenile := succulent_catalog_graph(species, 73, .55, .Near)
        mature := succulent_catalog_graph(species, 73, 1, .Near)
        defer destroy_graph(&juvenile)
        defer destroy_graph(&mature)
        testing.expectf(t, len(juvenile.axes) > 0, "%s has no juvenile axes", species_name(species))
        testing.expectf(t, len(juvenile.internodes) > 0, "%s has no juvenile internodes", species_name(species))
        testing.expectf(t, len(mature.organs) > 0, "%s has no mature organs", species_name(species))
        testing.expect(t, len(mature.axes) >= len(juvenile.axes))
        testing.expect(t, len(mature.internodes) >= len(juvenile.internodes))
        testing.expect(t, len(mature.organs) >= len(juvenile.organs))
        for axis, index in juvenile.axes {
            testing.expect(t, axis.stable_id != 0)
            testing.expect_value(t, axis.stable_id, mature.axes[index].stable_id)
        }
        for internode, index in juvenile.internodes {
            testing.expect(t, internode.stable_id != 0)
            testing.expect_value(t, internode.stable_id, mature.internodes[index].stable_id)
            testing.expect(t, internode.parent < index)
            testing.expect(t, internode.radius_start > 0 && internode.radius_end > 0)
        }
        for organ, index in juvenile.organs {
            testing.expect(t, organ.stable_id != 0)
            testing.expect_value(t, organ.stable_id, mature.organs[index].stable_id)
        }
    }
}

@(test)
generated_native_graph_keeps_authored_roles_and_organs :: proc(t: ^testing.T) {
    generated := generate({species = .Prickly_Pear, seed = 73, maturity = 1, detail = .Near})
    defer destroy(&generated)
    testing.expect_value(t, generated.error, Generate_Error.None)
    testing.expect_value(t, len(generated.plant.graph.internodes), len(generated.plant.segments))
    testing.expect_value(t, len(generated.plant.graph.organs), len(generated.plant.attachments))
    testing.expect_value(t, generated.plant.graph.organs[0].kind, Architecture_Organ.Cladode)
    testing.expect_value(t, generated.plant.graph.axes[0].role, Axis_Role.Leader)
    has_lateral := false
    for axis in generated.plant.graph.axes {
        if axis.role == .Lateral {
            has_lateral = true
            testing.expect(t, axis.parent_axis >= 0)
            testing.expect(t, axis.parent_internode >= 0)
        }
    }
    testing.expect(t, has_lateral)
    for internode, index in generated.plant.graph.internodes {
        testing.expect_value(t, internode.stable_id, generated.plant.segment_ids[index])
        testing.expect_value(t, internode.axis, generated.plant.segment_axes[index])
        testing.expect_value(t, internode.parent, generated.plant.segment_parents[index])
    }
}

@(test)
native_shrub_graph_keeps_renewal_and_flowering_axes :: proc(t: ^testing.T) {
    generated := generate({species = .Oleander, seed = 73, maturity = 1, detail = .Near})
    defer destroy(&generated)
    testing.expect_value(t, generated.error, Generate_Error.None)
    has_renewal, has_flowering, has_flower := false, false, false
    for axis in generated.plant.graph.axes {
        has_renewal = has_renewal || axis.role == .Renewal_Cane
        has_flowering = has_flowering || axis.role == .Flowering_Shoot
    }
    for organ in generated.plant.graph.organs do has_flower = has_flower || organ.kind == .Flower
    testing.expect(t, has_renewal)
    testing.expect(t, has_flowering)
    testing.expect(t, has_flower)
    testing.expect_value(t, len(generated.plant.graph.organs), len(generated.plant.attachments))
}

@(test)
architecture_catalog_growth_lod_seed_matrix :: proc(t: ^testing.T) {
    seeds := [3]u64{7, 73, 991}
    maturities := [6]f32{0, .2, .4, .6, .8, 1}
    reduced_details := [2]Detail_Level{.Medium, .Far}
    support := Support_Surface {
        width   = 8,
        height  = 7,
        plane_z = .1,
        root_x  = -2.7,
    }
    for species_index in 0 ..< SPECIES_COUNT {
        species := Species(species_index)
        habit := default_habit(species)
        support_pointer: ^Support_Surface
        if habit != .Free_Standing do support_pointer = &support
        for seed in seeds {
            previous_height := f32(0)
            for maturity in maturities {
                near := generate({species, seed, maturity, .Near, habit, support_pointer, {}})
                testing.expectf(
                    t,
                    near.error == .None,
                    "%s seed=%d maturity=%f Near failed",
                    species_name(species),
                    seed,
                    maturity,
                )
                if near.error == .None {
                    height := near.plant.bounds.maximum[1] - near.plant.bounds.minimum[1]
                    tolerance := max(f32(.08), previous_height * .05)
                    testing.expectf(
                        t,
                        height + tolerance >= previous_height,
                        "%s shrank from %f to %f",
                        species_name(species),
                        previous_height,
                        height,
                    )
                    previous_height = max(previous_height, height)
                }
                destroy(&near)
                for detail in reduced_details {
                    generated := generate({species, seed, maturity, detail, habit, support_pointer, {}})
                    testing.expectf(
                        t,
                        generated.error == .None,
                        "%s seed=%d maturity=%f %v failed",
                        species_name(species),
                        seed,
                        maturity,
                        detail,
                    )
                    destroy(&generated)
                }
            }
        }
    }
}
