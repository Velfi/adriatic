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
architecture_graph_recovers_connected_axes_and_organs :: proc(t: ^testing.T) {
    source := plant_structure.Plant {
        segments = {
            {{0, 0, 0}, {0, 1, 0}, .2, .15, 0},
            {{0, 1, 0}, {0, 2, 0}, .15, .1, 0},
            {{0, 1, 0}, {1, 1.5, 0}, .08, .03, 1},
        },
        leaves   = {{{1, 1.5, 0}, {1, 0, 0}, {0, 1, 0}, 1}},
    }
    defer plant_structure.destroy_plant(&source)
    graph := graph_from_interpreted(&source)
    defer destroy_graph(&graph)
    testing.expect_value(t, len(graph.axes), 2)
    testing.expect_value(t, len(graph.growth_units), 2)
    testing.expect_value(t, len(graph.internodes), 3)
    testing.expect_value(t, len(graph.organs), 1)
    testing.expect_value(t, graph.axes[0].role, Axis_Role.Leader)
    testing.expect_value(t, graph.axes[1].role, Axis_Role.Scaffold)
    testing.expect_value(t, graph.axes[1].parent_axis, 0)
    testing.expect_value(t, graph.internodes[2].parent, 0)
    testing.expect_value(t, graph.organs[0].internode, 2)
}

@(test)
architecture_compile_preserves_renderer_depths :: proc(t: ^testing.T) {
    source := plant_structure.Plant {
        segments = {{{0, 0, 0}, {0, 1, 0}, .1, .05, -23}},
        leaves   = {{{0, 1, 0}, {0, 1, 0}, {0, 0, 1}, -23}},
    }
    defer plant_structure.destroy_plant(&source)
    graph := graph_from_interpreted(&source)
    compiled := graph_compile(&graph)
    defer destroy_graph(&graph)
    defer plant_structure.destroy_plant(&compiled.plant)
    testing.expect_value(t, compiled.plant.segments[0].depth, -23)
    testing.expect_value(t, compiled.plant.leaves[0].depth, -23)
}

@(test)
canonicalization_preserves_attachment_routing_metadata :: proc(t: ^testing.T) {
    source := olive_architecture(73, 1, 2)
    before_count := len(source.plant.leaves)
    before_depths := make([]int, before_count)
    defer delete(before_depths)
    for leaf, index in source.plant.leaves do before_depths[index] = leaf.depth
    canonicalize_architecture(&source)
    defer plant_structure.destroy_plant(&source.plant)
    testing.expect_value(t, len(source.plant.leaves), before_count)
    for leaf, index in source.plant.leaves do testing.expect_value(t, leaf.depth, before_depths[index])
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
            testing.expectf(t, kind == .Flower || kind == .Fruit, "%s marker routed to %v", species_name(item.species), kind)
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
            generated := generate({species, 73, 1, detail, habit, support_pointer})
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
            for segment in generated.plant.segments {
                testing.expect(t, segment.radius_start > 0 && segment.radius_end > 0)
                for value in segment.start do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
                for value in segment.end do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
            }
            for parent, segment_index in generated.plant.segment_parents {
                testing.expect(t, parent < segment_index)
                testing.expect(t, parent >= -1)
                testing.expect(t, generated.plant.segment_axes[segment_index] >= 0)
            }
            destroy(&generated)
        }
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
                near := generate({species, seed, maturity, .Near, habit, support_pointer})
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
                    generated := generate({species, seed, maturity, detail, habit, support_pointer})
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
