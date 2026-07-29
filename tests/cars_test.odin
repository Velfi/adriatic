package tests

import cars "../packages/cars"
import "core:math/linalg"
import "core:testing"

CAR_TEST_KINDS := [5]cars.Kind{.Sedan, .Coupe, .Pickup, .Delivery, .Woody}

@(test)
compact_car_generator_is_deterministic_and_seeded :: proc(t: ^testing.T) {
    for kind in CAR_TEST_KINDS {
        first := cars.generate(kind, 1947)
        repeat := cars.generate(kind, 1947)
        alternate := cars.generate(kind, 1984)
        testing.expect_value(t, first, repeat)
        testing.expect(t, first.palette != alternate.palette || first.length != alternate.length)
    }
}

@(test)
compact_car_variants_keep_plausible_1940s_proportions :: proc(t: ^testing.T) {
    for kind in CAR_TEST_KINDS {
        for seed in 0 ..< 128 {
            plan := cars.generate(kind, u32(seed))
            testing.expect(t, plan.length >= 3.2 && plan.length <= 4.0)
            testing.expect(t, plan.width >= 1.35 && plan.width <= 1.52)
            testing.expect(t, plan.wheelbase > plan.length * .54)
            testing.expect(t, plan.wheelbase < plan.length * .68)
            testing.expect(t, plan.wheel_radius >= .29 && plan.wheel_radius <= .34)
            testing.expect(t, plan.cabin_height >= .60 && plan.cabin_height <= .95)
            testing.expect(t, plan.cabin_length < plan.length * .65)
            testing.expect(t, plan.hood_length < plan.length * .34)
        }
    }
}

@(test)
compact_car_seeds_vary_multiple_topology_channels :: proc(t: ^testing.T) {
    for kind in CAR_TEST_KINDS {
        min_wheel, max_wheel := f32(100), f32(0)
        min_cabin, max_cabin := f32(100), f32(0)
        min_wheelbase, max_wheelbase := f32(100), f32(0)
        for seed in 0 ..< 128 {
            plan := cars.generate(kind, u32(seed))
            min_wheel, max_wheel = min(min_wheel, plan.wheel_radius), max(max_wheel, plan.wheel_radius)
            min_cabin, max_cabin = min(min_cabin, plan.cabin_height), max(max_cabin, plan.cabin_height)
            min_wheelbase, max_wheelbase =
                min(min_wheelbase, plan.wheelbase), max(max_wheelbase, plan.wheelbase)
        }
        testing.expect(t, max_wheel - min_wheel >= .025)
        testing.expect(t, max_cabin - min_cabin >= .035)
        testing.expect(t, max_wheelbase - min_wheelbase >= .08)
    }
}

@(test)
compact_car_families_preserve_distinct_silhouettes :: proc(t: ^testing.T) {
    sedan := cars.generate(.Sedan, 1947)
    coupe := cars.generate(.Coupe, 1947)
    pickup := cars.generate(.Pickup, 1947)
    delivery := cars.generate(.Delivery, 1947)
    woody := cars.generate(.Woody, 1947)

    testing.expect(t, coupe.cabin_height < sedan.cabin_height)
    testing.expect(t, coupe.hood_length > sedan.hood_length)
    testing.expect(t, coupe.cabin_offset < sedan.cabin_offset)
    testing.expect(t, pickup.cabin_length < sedan.cabin_length)
    testing.expect(t, delivery.cabin_height > sedan.cabin_height)
    testing.expect(t, delivery.cabin_length > sedan.cabin_length)
    testing.expect(t, woody.cabin_length > sedan.cabin_length)
}

@(test)
compact_coupe_uses_two_door_fastback_topology :: proc(t: ^testing.T) {
    coupe_plan := cars.generate(.Coupe, 1947)
    sedan_plan := cars.generate(.Sedan, 1947)
    coupe := cars.mesh(coupe_plan)
    sedan := cars.mesh(sedan_plan)
    coupe_rear_roof, sedan_rear_roof := f32(0), f32(0)
    for vertex in coupe.vertices[:coupe.vertex_count] {
        if vertex.part == .Glass &&
           vertex.position[2] > coupe_plan.cabin_offset + coupe_plan.cabin_length * .40 {
            coupe_rear_roof = max(coupe_rear_roof, vertex.position[1])
        }
    }
    for vertex in sedan.vertices[:sedan.vertex_count] {
        if vertex.part == .Glass &&
           vertex.position[2] > sedan_plan.cabin_offset + sedan_plan.cabin_length * .40 {
            sedan_rear_roof = max(sedan_rear_roof, vertex.position[1])
        }
    }
    testing.expect(t, coupe_rear_roof > 0)
    testing.expect(t, sedan_rear_roof > 0)
    testing.expect(t, coupe_rear_roof < sedan_rear_roof)
}

@(test)
compact_car_meshes_have_complete_non_degenerate_topology :: proc(t: ^testing.T) {
    for kind in CAR_TEST_KINDS {
        plan := cars.generate(kind, 1947)
        generated := cars.mesh(plan)
        testing.expect(t, generated.vertex_count > 100)
        testing.expect(t, generated.vertex_count <= cars.MESH_VERTEX_CAPACITY)
        testing.expect(t, generated.index_count > 500)
        testing.expect(t, generated.index_count % 3 == 0)
        testing.expect(t, generated.index_count <= cars.MESH_INDEX_CAPACITY)
        testing.expect(t, generated.vertex_count < generated.index_count / 2)
        saw_body, saw_glass, saw_trim := false, false, false
        saw_tire, saw_whitewall, saw_chrome := false, false, false
        for first := 0; first + 2 < generated.index_count; first += 3 {
            a_index := int(generated.indices[first + 0])
            b_index := int(generated.indices[first + 1])
            c_index := int(generated.indices[first + 2])
            testing.expect(t, a_index < generated.vertex_count)
            testing.expect(t, b_index < generated.vertex_count)
            testing.expect(t, c_index < generated.vertex_count)
            a := generated.vertices[a_index]
            b := generated.vertices[b_index]
            c := generated.vertices[c_index]
            saw_body = saw_body || a.part == .Body
            saw_glass = saw_glass || a.part == .Glass
            saw_trim = saw_trim || a.part == .Trim
            saw_tire = saw_tire || a.part == .Tire
            saw_whitewall = saw_whitewall || a.part == .Whitewall
            saw_chrome = saw_chrome || a.part == .Chrome
            ab := b.position - a.position
            ac := c.position - a.position
            normal := linalg.cross(ab, ac)
            normal_length_squared := normal[0] * normal[0] + normal[1] * normal[1] + normal[2] * normal[2]
            testing.expect(t, normal_length_squared > .0000001)
            face_vertices := [3]cars.Vertex{a, b, c}
            for vertex in face_vertices {
                testing.expect(t, abs(vertex.position[0]) <= plan.width * .60)
                if vertex.part == .Tire ||
                   vertex.part == .Whitewall ||
                   vertex.part == .Chrome {
                    testing.expect(t, vertex.position[1] >= -.001)
                } else {
                    testing.expect(t, vertex.position[1] >= .15)
                }
                testing.expect(t, vertex.position[1] <= plan.belt_height + plan.cabin_height + .01)
                testing.expect(t, abs(vertex.position[2]) <= plan.length * .51)
            }
        }
        testing.expect(t, saw_body)
        testing.expect(t, saw_glass)
        testing.expect(t, saw_trim)
        testing.expect(t, saw_tire)
        testing.expect(t, saw_whitewall)
        testing.expect(t, saw_chrome)
    }
}

@(test)
compact_utility_car_topology_has_family_specific_material_regions :: proc(t: ^testing.T) {
    pickup := cars.mesh(cars.generate(.Pickup, 1947))
    sedan := cars.mesh(cars.generate(.Sedan, 1947))
    delivery := cars.mesh(cars.generate(.Delivery, 1947))

    // The open tray adds closed indexed regions, while the delivery body's
    // panelled cargo quarters require fewer glass seam duplicates.
    testing.expect(t, pickup.index_count > sedan.index_count)
    pickup_trim := 0
    delivery_glass := 0
    sedan_glass := 0
    for vertex in pickup.vertices[:pickup.vertex_count] {
        if vertex.part == .Trim do pickup_trim += 1
    }
    for vertex in delivery.vertices[:delivery.vertex_count] {
        if vertex.part == .Glass do delivery_glass += 1
    }
    for vertex in sedan.vertices[:sedan.vertex_count] {
        if vertex.part == .Glass do sedan_glass += 1
    }
    testing.expect(t, pickup_trim > 0)
    testing.expect(t, delivery_glass < sedan_glass)
    testing.expect(t, delivery.index_count > sedan.index_count)
    delivery_trim, sedan_trim := 0, 0
    for vertex in delivery.vertices[:delivery.vertex_count] {
        if vertex.part == .Trim do delivery_trim += 1
    }
    for vertex in sedan.vertices[:sedan.vertex_count] {
        if vertex.part == .Trim do sedan_trim += 1
    }
    testing.expect(t, delivery_trim > sedan_trim)
}

@(test)
compact_woody_has_topology_native_timber_frame :: proc(t: ^testing.T) {
    woody := cars.mesh(cars.generate(.Woody, 1947))
    sedan := cars.mesh(cars.generate(.Sedan, 1947))
    woody_timber, sedan_timber := 0, 0
    for vertex in woody.vertices[:woody.vertex_count] {
        if vertex.part == .Timber do woody_timber += 1
    }
    for vertex in sedan.vertices[:sedan.vertex_count] {
        if vertex.part == .Timber do sedan_timber += 1
    }
    testing.expect(t, woody_timber >= 40)
    testing.expect_value(t, sedan_timber, 0)
    testing.expect(t, woody.index_count > sedan.index_count)
}
