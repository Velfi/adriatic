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
architecture_graph_preserves_renderer_depths :: proc(t: ^testing.T) {
    graph: Plant_Graph
    axis := graph_add_axis(&graph, -1, -1, .Leader, .Orthotropic, 0, 1, 1)
    unit := graph_begin_growth_unit(&graph, axis, 0, 1)
    internode := graph_add_internode(&graph, axis, unit, -1, {0, 0, 0}, {0, 1, 0}, .1, .05, 1, -23)
    graph_add_organ(&graph, internode, 1, .Leaf, {0, 1, 0}, {0, 0, 1}, 0, -23)
    defer destroy_graph(&graph)
    testing.expect_value(t, graph.internodes[0].render_depth, -23)
    testing.expect_value(t, graph.organs[0].render_depth, -23)
}

@(test)
reproductive_organs_use_explicit_species_sites :: proc(t: ^testing.T) {
    cases := []struct {
        species: Species,
        kind:    Architecture_Organ,
    } {
        {.Oleander, .Flower},
        {.Wisteria, .Flower},
        {.Climbing_Rose, .Flower},
        {.Strawberry_Tree, .Flower},
        {.Carob, .Fruit},
    }
    support := Support_Surface {
        width   = 8,
        height  = 7,
        plane_z = .1,
    }
    for item in cases {
        habit := default_habit(item.species)
        support_pointer: ^Support_Surface
        if habit != .Free_Standing do support_pointer = &support
        generated := generate({item.species, 73, 1, .Near, habit, support_pointer, {}})
        testing.expect_value(t, generated.error, Generate_Error.None)
        found := false
        for organ in generated.plant.graph.organs do found = found || organ.kind == item.kind
        testing.expectf(t, found, "%s has no explicit reproductive site", species_name(item.species))
        destroy(&generated)
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
generation_emits_authored_organs_without_flat_policy_reclassification :: proc(t: ^testing.T) {
    support := Support_Surface{width = 3, height = 2}
    generated := generate({species = .Grapevine, seed = 551, maturity = 1, detail = .Near, habit = .Trellised, support = &support})
    defer destroy(&generated)
    testing.expect(t, generated.error == .None)
    testing.expect_value(t, len(generated.plant.graph.organs), len(generated.plant.attachments))
    for organ, index in generated.plant.graph.organs {
        testing.expect_value(t, generated_graph_organ_kind(generated.plant.attachments[index].kind), organ.kind)
        testing.expect_value(t, generated.plant.attachment_ids[index], organ.stable_id)
    }
}

@(test)
generation_workspace_reuses_graph_and_compiled_output_capacity :: proc(t: ^testing.T) {
    workspace: Generation_Workspace
    defer generation_workspace_destroy(&workspace)
    config := Generate_Config{species = .Olive, seed = 808, maturity = 1, detail = .Near}
    testing.expect(t, generation_workspace_begin(&workspace))
    first := generate(config)
    generation_workspace_end(&workspace)
    testing.expect(t, first.error == .None)
    segment_count, organ_count := len(first.plant.segments), len(first.plant.attachments)
    testing.expect(t, workspace.borrowed)
    destroy(&first)
    testing.expect(t, !workspace.borrowed)
    capacities := [4]int {
        cap(workspace.graph.internodes),
        cap(workspace.graph.organs),
        cap(workspace.segments),
        cap(workspace.attachments),
    }
    testing.expect(t, capacities[0] >= segment_count && capacities[1] >= organ_count)
    testing.expect(t, capacities[2] >= segment_count && capacities[3] >= organ_count)

    testing.expect(t, generation_workspace_begin(&workspace))
    second := generate(config)
    generation_workspace_end(&workspace)
    testing.expect(t, second.error == .None)
    testing.expect_value(t, len(second.plant.segments), segment_count)
    testing.expect_value(t, len(second.plant.attachments), organ_count)
    destroy(&second)
    testing.expect_value(t, cap(workspace.graph.internodes), capacities[0])
    testing.expect_value(t, cap(workspace.graph.organs), capacities[1])
    testing.expect_value(t, cap(workspace.segments), capacities[2])
    testing.expect_value(t, cap(workspace.attachments), capacities[3])
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
catalog_generation_retains_authored_graph_identity :: proc(t: ^testing.T) {
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
        younger := generate({species, 73, .55, .Near, habit, support_pointer, {}})
        older := generate({species, 73, 1, .Near, habit, support_pointer, {}})
        testing.expectf(
            t,
            younger.error == .None && older.error == .None,
            "%s graph generation failed",
            species_name(species),
        )
        if younger.error == .None && older.error == .None {
            testing.expect_value(t, len(younger.plant.graph.internodes), len(younger.plant.segments))
            testing.expect_value(t, len(younger.plant.graph.organs), len(younger.plant.attachments))
            testing.expect(t, len(younger.plant.graph.axes) > 0)
            testing.expect(t, len(older.plant.graph.axes) >= len(younger.plant.graph.axes))
            if len(younger.plant.graph.axes) > 0 {
                testing.expect(t, younger.plant.graph.axes[0].stable_id != 0)
                testing.expect_value(t, younger.plant.graph.axes[0].stable_id, older.plant.graph.axes[0].stable_id)
            }
            if habit != .Free_Standing {
                for axis in younger.plant.graph.axes {
                    testing.expectf(t, axis.role == .Climber, "%s emitted non-climber axis", species_name(species))
                }
            }
        }
        destroy(&younger)
        destroy(&older)
    }
}

@(test)
reduced_lods_retain_only_near_graph_identities :: proc(t: ^testing.T) {
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
        near := generate({species, 73, 1, .Near, habit, support_pointer, {}})
        medium := generate({species, 73, 1, .Medium, habit, support_pointer, {}})
        far := generate({species, 73, 1, .Far, habit, support_pointer, {}})
        testing.expect(t, near.error == .None && medium.error == .None && far.error == .None)
        reduced_results: [2]^Generate_Result
        reduced_results[0] = &medium
        reduced_results[1] = &far
        for reduced in reduced_results {
            for stable_id in reduced.plant.segment_ids {
                retained := false
                for near_id in near.plant.segment_ids do retained = retained || near_id == stable_id
                testing.expectf(t, retained, "%s LOD invented segment id %d", species_name(species), stable_id)
            }
            for stable_id in reduced.plant.attachment_ids {
                retained := false
                for near_id in near.plant.attachment_ids do retained = retained || near_id == stable_id
                testing.expectf(t, retained, "%s LOD invented organ id %d", species_name(species), stable_id)
            }
        }
        destroy(&near)
        destroy(&medium)
        destroy(&far)
    }
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
