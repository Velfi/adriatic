package main

import umbrellas "../packages/umbrellas"
import "core:math"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

umbrella_palette :: proc(index: u8) -> (canvas2d.Color, canvas2d.Color) {
    switch index % 4 {
    case 0:
        return {205, 63, 48, 255}, {244, 222, 169, 255}
    case 1:
        return {48, 126, 153, 255}, {235, 225, 190, 255}
    case 2:
        return {74, 133, 91, 255}, {246, 210, 126, 255}
    case:
        return {220, 116, 57, 255}, {242, 226, 191, 255}
    }
}

world_umbrella :: proc(plan: ^umbrellas.Plan, origin: third_person.Vec3) {
    if plan == nil || !plan.valid do return
    metal := canvas2d.Color{67, 73, 68, 255}
    base_color := canvas2d.Color{126, 119, 101, 255}
    color_a, color_b := umbrella_palette(plan.palette)
    heading := plan.tilt_heading
    lean_x := math.cos(heading) * math.sin(plan.tilt)
    lean_z := math.sin(heading) * math.sin(plan.tilt)
    up_y := math.cos(plan.tilt)
    hub := third_person.Vec3 {
        origin.x + lean_x * plan.height,
        origin.y + up_y * plan.height,
        origin.z + lean_z * plan.height,
    }
    world_box_between(
        origin,
        hub,
        {math.cos(heading + math.PI / 2), 0, math.sin(heading + math.PI / 2)},
        plan.pole_radius * 2,
        plan.pole_radius * 2,
        metal,
    )

    for segment in 0 ..< plan.panel_count {
        angle_a := plan.rotation + f32(segment) * f32(math.PI * 2) / f32(plan.panel_count)
        angle_b := plan.rotation + f32(segment + 1) * f32(math.PI * 2) / f32(plan.panel_count)
        edge_a := third_person.Vec3 {
            hub.x + math.cos(angle_a) * plan.radius,
            hub.y - plan.canopy_rise,
            hub.z + math.sin(angle_a) * plan.radius,
        }
        edge_b := third_person.Vec3 {
            hub.x + math.cos(angle_b) * plan.radius,
            hub.y - plan.canopy_rise,
            hub.z + math.sin(angle_b) * plan.radius,
        }
        color := segment & 1 == 0 ? color_a : color_b
        world_triangle(hub, edge_a, edge_b, color)
        world_triangle(hub, edge_b, edge_a, color)
        world_box_between(hub, edge_a, {0, 1, 0}, .025, .025, metal)
        if plan.scalloped {
            middle_angle := (angle_a + angle_b) * .5
            middle := third_person.Vec3 {
                hub.x + math.cos(middle_angle) * plan.radius * .965,
                edge_a.y - plan.canopy_drop,
                hub.z + math.sin(middle_angle) * plan.radius * .965,
            }
            world_triangle(edge_a, middle, edge_b, color)
            world_triangle(edge_b, middle, edge_a, color)
        }
    }
    world_vertical_prism(hub, plan.pole_radius * 3, plan.pole_radius * 3, plan.canopy_rise * .35, 0, metal)
    if plan.base == .Slab {
        world_vertical_prism({origin.x, origin.y + .055, origin.z}, .62, .62, .11, math.PI / 8, base_color)
    } else {
        world_vertical_prism({origin.x, origin.y + .09, origin.z}, .12, .12, .18, 0, metal)
    }
}
