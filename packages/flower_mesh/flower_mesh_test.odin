package flower_mesh

import "core:math"
import "core:testing"

@(test)
generates_valid_meshes_for_every_petal_shape_and_arrangement :: proc(t: ^testing.T) {
    for shape in Petal_Shape {
        for arrangement in Arrangement {
            config := defaults()
            config.petal_shape = shape
            config.arrangement = arrangement
            config.petal_count = 7
            config.whorl_count = 2
            mesh := generate(config)
            expected_vertices := config.petal_count * config.whorl_count * (config.segments + 1) * 3
            expected_vertices += config.center_segments + 1
            expected_indices := config.petal_count * config.whorl_count * config.segments * 12
            expected_indices += config.center_segments * 3
            testing.expect_value(t, mesh.vertex_count, expected_vertices)
            testing.expect_value(t, mesh.index_count, expected_indices)
            for index in mesh.indices[:mesh.index_count] {
                testing.expect(t, int(index) < mesh.vertex_count)
            }
            for vertex in mesh.vertices[:mesh.vertex_count] {
                for value in vertex.position {
                    testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
                }
                normal_length := math.sqrt(
                    vertex.normal[0] * vertex.normal[0] +
                    vertex.normal[1] * vertex.normal[1] +
                    vertex.normal[2] * vertex.normal[2],
                )
                testing.expect(t, math.abs(normal_length - 1) < .001)
            }
        }
    }
}

@(test)
whorled_petals_have_rotationally_symmetric_roots :: proc(t: ^testing.T) {
    config := defaults()
    config.petal_count = 5
    config.whorl_count = 1
    mesh := generate(config)
    stride := (config.segments + 1) * 3
    for petal in 0 ..< config.petal_count {
        root := mesh.vertices[petal * stride + 1].position
        radius := math.sqrt(root[0] * root[0] + root[1] * root[1])
        testing.expect(t, math.abs(radius - config.base_radius) < .0001)
    }
}

@(test)
generator_clamps_extreme_counts_to_capacity :: proc(t: ^testing.T) {
    config := defaults()
    config.petal_count = 999
    config.whorl_count = 999
    config.segments = 999
    config.center_segments = 999
    mesh := generate(config)
    testing.expect(t, mesh.vertex_count <= MAX_VERTICES)
    testing.expect(t, mesh.index_count <= MAX_INDICES)
    testing.expect(t, mesh.vertex_count > 0)
    testing.expect(t, mesh.index_count > 0)
}

@(test)
bushy_clusters_are_bounded_deterministic_domes :: proc(t: ^testing.T) {
    config := cluster_defaults(.Dome)
    config.flower_count = 19
    config.radius = .11
    config.height = .06
    config.floret_scale = .024
    config.phase = .73
    first := generate_cluster(config)
    second := generate_cluster(config)
    testing.expect_value(t, first.count, 19)
    testing.expect_value(t, first, second)
    testing.expect(t, first.instances[0].position[2] > .059)
    edge_count := 0
    for instance in first.instances[:first.count] {
        radial := math.sqrt(instance.position[0] * instance.position[0] + instance.position[1] * instance.position[1])
        testing.expect(t, radial <= config.radius + .0001)
        testing.expect(t, instance.position[2] >= 0 && instance.position[2] <= config.height + .0001)
        testing.expect(t, instance.scale > 0)
        normal_length := math.sqrt(
            instance.normal[0] * instance.normal[0] +
            instance.normal[1] * instance.normal[1] +
            instance.normal[2] * instance.normal[2],
        )
        testing.expect(t, math.abs(normal_length - 1) < .001)
        if radial > config.radius * .85 do edge_count += 1
    }
    testing.expect(t, edge_count >= 4)
}

@(test)
cluster_counts_clamp_and_single_ignores_bushy_capacity :: proc(t: ^testing.T) {
    config := cluster_defaults(.Dome)
    config.flower_count = 999
    testing.expect_value(t, generate_cluster(config).count, MAX_CLUSTER_FLOWERS)
    config = cluster_defaults(.Single)
    config.flower_count = 17
    single := generate_cluster(config)
    testing.expect_value(t, single.count, 1)
    testing.expect_value(t, single.instances[0].position, [3]f32{})
}

@(test)
ball_clusters_support_flattened_mophead_proportions :: proc(t: ^testing.T) {
    config := cluster_defaults(.Ball)
    config.flower_count = MAX_CLUSTER_FLOWERS
    config.radius = .078
    config.height = .052
    cluster := generate_cluster(config)
    minimum_z, maximum_z := f32(1000), f32(-1000)
    maximum_radial := f32(0)
    for instance in cluster.instances[:cluster.count] {
        radial := math.sqrt(instance.position[0] * instance.position[0] + instance.position[1] * instance.position[1])
        maximum_radial = max(maximum_radial, radial)
        minimum_z = min(minimum_z, instance.position[2])
        maximum_z = max(maximum_z, instance.position[2])
        gradient := [3]f32 {
            instance.position[0] / (config.radius * config.radius),
            instance.position[1] / (config.radius * config.radius),
            instance.position[2] / (config.height * config.height),
        }
        gradient_length := math.sqrt(gradient[0] * gradient[0] + gradient[1] * gradient[1] + gradient[2] * gradient[2])
        gradient /= gradient_length
        alignment :=
            gradient[0] * instance.normal[0] +
            gradient[1] * instance.normal[1] +
            gradient[2] * instance.normal[2]
        testing.expect(t, alignment > .999)
    }
    testing.expect(t, minimum_z < 0 && maximum_z > 0)
    testing.expect(t, maximum_radial > .07)
    testing.expect(t, maximum_z - minimum_z < maximum_radial * 1.6)
}

@(test)
fruit_profiles_generate_closed_finite_meshes :: proc(t: ^testing.T) {
    for shape in Fruit_Shape {
        config := fruit_defaults(shape)
        mesh := generate_fruit(config)
        expected_vertices := (config.rings + 1) * (config.segments + 1)
        expected_indices := config.rings * config.segments * 6
        testing.expect_value(t, mesh.vertex_count, expected_vertices)
        testing.expect_value(t, mesh.index_count, expected_indices)
        for index in mesh.indices[:mesh.index_count] do testing.expect(t, int(index) < mesh.vertex_count)
        for vertex in mesh.vertices[:mesh.vertex_count] {
            for value in vertex.position do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
            for value in vertex.normal do testing.expect(t, !math.is_nan(value) && !math.is_inf(value))
        }
    }
}

@(test)
lifecycle_reuses_origin_and_grows_from_set_to_ripe_fruit :: proc(t: ^testing.T) {
    config := Lifecycle_Config {
        stage  = .Fruit_Set,
        flower = defaults(),
        fruit  = fruit_defaults(.Citrus),
    }
    set_mesh := generate_lifecycle(config)
    config.stage = .Ripe_Fruit
    ripe_mesh := generate_lifecycle(config)
    testing.expect_value(t, set_mesh.vertex_count, ripe_mesh.vertex_count)
    equator := (config.fruit.rings / 2) * (config.fruit.segments + 1)
    set_radius := math.abs(set_mesh.vertices[equator].position[0])
    ripe_radius := math.abs(ripe_mesh.vertices[equator].position[0])
    testing.expect(t, ripe_radius > set_radius)
}

@(test)
fruit_stages_grow_outward_in_order :: proc(t: ^testing.T) {
    config := Lifecycle_Config {
        flower = defaults(),
        fruit  = fruit_defaults(.Citrus),
    }
    stages := [4]Lifecycle_Stage{.Fruit_Set, .Immature_Fruit, .Ripening_Fruit, .Ripe_Fruit}
    previous_radius: f32
    for stage, index in stages {
        config.stage = stage
        mesh := generate_lifecycle(config)
        equator := (config.fruit.rings / 2) * (config.fruit.segments + 1)
        radius := math.abs(mesh.vertices[equator].position[0])
        if index > 0 do testing.expect(t, radius > previous_radius)
        previous_radius = radius
    }
}

@(test)
opening_stages_expand_outward_in_order :: proc(t: ^testing.T) {
    config := Lifecycle_Config {
        flower = defaults(),
        fruit  = fruit_defaults(),
    }
    stages := [4]Lifecycle_Stage{.Bud, .Opening, .Half_Open, .Bloom}
    previous_radius: f32
    for stage, index in stages {
        config.stage = stage
        mesh := generate_lifecycle(config)
        tip := mesh.vertices[config.flower.segments * 3 + 1].position
        radius := math.sqrt(tip[0] * tip[0] + tip[1] * tip[1])
        if index > 0 do testing.expect(t, radius > previous_radius)
        previous_radius = radius
    }
}

@(test)
botanical_profiles_have_distinct_simple_silhouettes :: proc(t: ^testing.T) {
    // Ovate petals carry their broadest mass beyond the midpoint.
    testing.expect(t, half_width(.Ovate, .62) > half_width(.Ovate, .28))
    // Spatulate petals keep a narrow claw before opening into the blade.
    testing.expect(t, half_width(.Spatulate, .22) < half_width(.Spatulate, .68) * .5)
    // Lanceolate petals taper more strongly than rounded petals near the apex.
    testing.expect(t, half_width(.Lanceolate, .88) < half_width(.Rounded, .88))
}
