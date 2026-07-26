package vehicles

import third_person "../third_person"
import wireframe "../wireframe"
import "core:math"

Car_Wireframe :: struct {
    vertices: [32]wireframe.Vertex,
    edges:    [48]wireframe.Edge,
}

CAR_WHEEL_TRACK_HALF :: f32(.675)
CAR_WHEELBASE_HALF :: f32(.96)
CAR_WHEEL_RADIUS :: f32(.235)
CAR_WHEEL_CENTER_Y :: CAR_WHEEL_RADIUS
CAR_WHEEL_WIDTH :: f32(.17)
CAR_WHEEL_HUB_RADIUS :: f32(.095)

// simple_car returns a compact, game-facing wireframe: a low body, raised
// cabin, and four square wheel silhouettes. The model faces negative Z.
simple_car :: proc() -> Car_Wireframe {
    body_color := wireframe.Color_Float {
        r = 0.18,
        g = 0.75,
        b = 1.0,
    }
    glass_color := wireframe.Color_Float {
        r = 0.82,
        g = 0.94,
        b = 1.0,
    }
    wheel_color := wireframe.Color_Float {
        r = 1.0,
        g = 0.68,
        b = 0.16,
    }

    return {
        vertices = {
            // Lower body.
            {position = {-1.35, -0.25, -1.05}, color = body_color},
            {position = {1.35, -0.25, -1.05}, color = body_color},
            {position = {1.35, -0.25, 1.05}, color = body_color},
            {position = {-1.35, -0.25, 1.05}, color = body_color},
            {position = {-1.35, 0.45, -1.05}, color = body_color},
            {position = {1.35, 0.45, -1.05}, color = body_color},
            {position = {1.35, 0.45, 1.05}, color = body_color},
            {position = {-1.35, 0.45, 1.05}, color = body_color},
            // Cabin.
            {position = {-0.78, 0.45, -0.65}, color = glass_color},
            {position = {0.78, 0.45, -0.65}, color = glass_color},
            {position = {0.78, 0.45, 0.62}, color = glass_color},
            {position = {-0.78, 0.45, 0.62}, color = glass_color},
            {position = {-0.58, 1.08, -0.43}, color = glass_color},
            {position = {0.58, 1.08, -0.43}, color = glass_color},
            {position = {0.58, 1.08, 0.42}, color = glass_color},
            {position = {-0.58, 1.08, 0.42}, color = glass_color},
            // Front wheel silhouettes: left, right.
            {position = {-1.38, -0.65, -0.76}, color = wheel_color},
            {position = {-1.38, 0.02, -0.76}, color = wheel_color},
            {position = {-1.38, 0.02, -0.16}, color = wheel_color},
            {position = {-1.38, -0.65, -0.16}, color = wheel_color},
            {position = {1.38, -0.65, -0.76}, color = wheel_color},
            {position = {1.38, 0.02, -0.76}, color = wheel_color},
            {position = {1.38, 0.02, -0.16}, color = wheel_color},
            {position = {1.38, -0.65, -0.16}, color = wheel_color},
            // Rear wheel silhouettes: left, right.
            {position = {-1.38, -0.65, 0.16}, color = wheel_color},
            {position = {-1.38, 0.02, 0.16}, color = wheel_color},
            {position = {-1.38, 0.02, 0.76}, color = wheel_color},
            {position = {-1.38, -0.65, 0.76}, color = wheel_color},
            {position = {1.38, -0.65, 0.16}, color = wheel_color},
            {position = {1.38, 0.02, 0.16}, color = wheel_color},
            {position = {1.38, 0.02, 0.76}, color = wheel_color},
            {position = {1.38, -0.65, 0.76}, color = wheel_color},
        },
        edges    = {
            // Lower body cuboid.
            {0, 1},
            {1, 2},
            {2, 3},
            {3, 0},
            {4, 5},
            {5, 6},
            {6, 7},
            {7, 4},
            {0, 4},
            {1, 5},
            {2, 6},
            {3, 7},
            // Cabin cuboid.
            {8, 9},
            {9, 10},
            {10, 11},
            {11, 8},
            {12, 13},
            {13, 14},
            {14, 15},
            {15, 12},
            {8, 12},
            {9, 13},
            {10, 14},
            {11, 15},
            // Front wheels.
            {16, 17},
            {17, 18},
            {18, 19},
            {19, 16},
            {20, 21},
            {21, 22},
            {22, 23},
            {23, 20},
            // Rear wheels.
            {24, 25},
            {25, 26},
            {26, 27},
            {27, 24},
            {28, 29},
            {29, 30},
            {30, 31},
            {31, 28},
            // Wheel arches visually connect the tires to the body.
            {16, 4},
            {17, 4},
            {20, 5},
            {21, 5},
            {27, 7},
            {26, 7},
            {31, 6},
            {30, 6},
        },
    }
}

// car_wheel adds a short, faceted cylinder along the axle, with a smaller
// circular hub on each face. Keeping this here makes the car's miniature
// wheels round without changing the shared aircraft mesh helpers.
car_wheel :: proc(mesh: ^Aircraft_Mesh, center: [3]f32) {
    half_width := CAR_WHEEL_WIDTH * .5
    tire := [2]Mesh_Ring {
        {-half_width, CAR_WHEEL_RADIUS, 0, CAR_WHEEL_RADIUS},
        {half_width, CAR_WHEEL_RADIUS, 0, CAR_WHEEL_RADIUS},
    }
    first := mesh.vertex_count
    add_ring_mesh(mesh, tire[:], 12, .Wheel)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    translate_new_vertices(mesh, first, center)

    hub_face := half_width + .005
    hub := [2]Mesh_Ring {
        {-hub_face, CAR_WHEEL_HUB_RADIUS, 0, CAR_WHEEL_HUB_RADIUS},
        {hub_face, CAR_WHEEL_HUB_RADIUS, 0, CAR_WHEEL_HUB_RADIUS},
    }
    first = mesh.vertex_count
    add_ring_mesh(mesh, hub[:], 12, .Bumper)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    translate_new_vertices(mesh, first, center)
}

trailer_wheel :: proc(mesh: ^Aircraft_Mesh, center: [3]f32) {
    tire := [2]Mesh_Ring{{-.11, .25, 0, .25}, {.11, .25, 0, .25}}
    first := mesh.vertex_count
    add_ring_mesh(mesh, tire[:], 12, .Wheel)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    translate_new_vertices(mesh, first, center)

    hub := [2]Mesh_Ring{{-.115, .10, 0, .10}, {.115, .10, 0, .10}}
    first = mesh.vertex_count
    add_ring_mesh(mesh, hub[:], 12, .Bumper)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    translate_new_vertices(mesh, first, center)
}

trailer_spare_wheel :: proc(mesh: ^Aircraft_Mesh, center: [3]f32) {
    tire := [2]Mesh_Ring{{-.10, .23, 0, .23}, {.10, .23, 0, .23}}
    first := mesh.vertex_count
    add_ring_mesh(mesh, tire[:], 12, .Wheel)
    translate_new_vertices(mesh, first, center)

    hub := [2]Mesh_Ring{{-.105, .09, 0, .09}, {.105, .09, 0, .09}}
    first = mesh.vertex_count
    add_ring_mesh(mesh, hub[:], 12, .Bumper)
    translate_new_vertices(mesh, first, center)
}

animate_trailer_wheels :: proc(mesh: ^Aircraft_Mesh, rotation: f32) {
    if mesh == nil do return
    wheel_centers := [2][3]f32{{-.64, .26, 2.48}, {.64, .26, 2.48}}
    c, s := math.cos(rotation), math.sin(rotation)
    for center in wheel_centers {
        for &vertex in mesh.vertices[:mesh.vertex_count] {
            if vertex.part != .Wheel && vertex.part != .Bumper do continue
            dx := vertex.position[0] - center[0]
            dy := vertex.position[1] - center[1]
            dz := vertex.position[2] - center[2]
            if dx * dx + dy * dy + dz * dz > .36 * .36 do continue
            vertex.position[1] = center[1] + dy * c - dz * s
            vertex.position[2] = center[2] + dy * s + dz * c
        }
    }
}

// simple_car_mesh is a tiny, open-top roadster: its proportions are sized for
// the mouse rather than a human, and the low beltline keeps the driver visible
// in the showcase and during play.
simple_car_mesh :: proc() -> Aircraft_Mesh {
    mesh: Aircraft_Mesh

    // Three nested, tapered shells give the tiny roadster one continuous
    // shoulder line. Broad middle rings wrap the wheels while narrower end
    // rings soften the nose and tail without abandoning the faceted style.
    lower_body := [7]Mesh_Ring {
        {-1.40, .48, .26, .18},
        {-1.24, .66, .28, .24},
        {-.84, .74, .29, .27},
        {0, .76, .29, .27},
        {.84, .74, .29, .27},
        {1.24, .64, .28, .23},
        {1.40, .46, .26, .17},
    }
    add_ring_mesh(&mesh, lower_body[:], 10, .Body)

    hood := [4]Mesh_Ring{{-1.34, .44, .47, .08}, {-1.17, .60, .49, .12}, {-.78, .66, .50, .14}, {-.45, .58, .47, .10}}
    add_ring_mesh(&mesh, hood[:], 10, .Body)

    rear_deck := [4]Mesh_Ring{{.46, .57, .45, .08}, {.78, .65, .48, .12}, {1.16, .59, .47, .11}, {1.34, .43, .43, .07}}
    add_ring_mesh(&mesh, rear_deck[:], 10, .Body)

    // Low cockpit rails preserve a crisp opening against the rounded shells.
    add_box(&mesh, {-.62, .53, .08}, {.16, .18, 1.25}, .Body)
    add_box(&mesh, {.62, .53, .08}, {.16, .18, 1.25}, .Body)

    // A visible bucket seat grounds the driver inside the cockpit instead of
    // leaving the character suspended over the rear deck. The low cushion and
    // gently reclined two-piece back preserve the open roadster silhouette.
    add_box(&mesh, {0, .50, .27}, {.62, .12, .64}, .Strap)
    add_box(&mesh, {0, .61, .64}, {.62, .20, .10}, .Strap)

    // Move the short split windscreen toward the nose and rake its top back
    // over the cockpit. The lower pivot keeps the glass rooted in the scuttle.
    windscreen_pivot := [3]f32{0, .54, -.58}
    windscreen_rake := f32(.30)
    first := mesh.vertex_count
    add_box(&mesh, {-.43, .76, -.58}, {.08, .48, .08}, .Frame)
    rotate_new_vertices_x(&mesh, first, windscreen_pivot, windscreen_rake)
    first = mesh.vertex_count
    add_box(&mesh, {.43, .76, -.58}, {.08, .48, .08}, .Frame)
    rotate_new_vertices_x(&mesh, first, windscreen_pivot, windscreen_rake)
    first = mesh.vertex_count
    add_box(&mesh, {0, .98, -.58}, {.92, .08, .08}, .Glass)
    rotate_new_vertices_x(&mesh, first, windscreen_pivot, windscreen_rake)
    first = mesh.vertex_count
    add_box(&mesh, {0, .78, -.58}, {.72, .24, .035}, .Glass)
    rotate_new_vertices_x(&mesh, first, windscreen_pivot, windscreen_rake)

    // Keep the narrower tire faces flush with the shoulder. Realistic kei-car
    // tread is much slimmer relative to diameter than the former toy-like
    // wheels, while the compact wheelbase supplies the short overhangs.
    wheel_x := [2]f32{-CAR_WHEEL_TRACK_HALF, CAR_WHEEL_TRACK_HALF}
    wheel_z := [2]f32{-CAR_WHEELBASE_HALF, CAR_WHEELBASE_HALF}
    for x in wheel_x {
        for z in wheel_z {
            car_wheel(&mesh, {x, CAR_WHEEL_CENTER_Y, z})
        }
    }

    add_box(&mesh, {0, .25, -1.42}, {1.34, .14, .14}, .Bumper)
    add_box(&mesh, {0, .25, 1.42}, {1.30, .14, .14}, .Bumper)
    light_x := [2]f32{-.58, .58}
    for x in light_x {
        add_box(&mesh, {x, .56, -1.18}, {.22, .14, .06}, .Headlight)
        add_box(&mesh, {x, .54, 1.14}, {.22, .12, .06}, .Tail_Light)
    }
    return mesh
}

// simple_car_trailer_mesh is authored in the same local space as the car. The
// trailer sits behind the convertible (+Z), with a short tongue and coupler so
// it still reads as detachable when it is parked separately. Detached trailers
// also lower a small jockey wheel/support foot under the tongue.
simple_car_trailer_mesh :: proc(
    detached: bool = false,
    attached: bool = false,
    jockey_deployed: bool = false,
) -> Aircraft_Mesh {
    mesh: Aircraft_Mesh

    // Low floor, open bed, and four raised rails give the trailer a readable
    // utility silhouette instead of making it look like a second car body.
    add_box(&mesh, {0, .18, 2.48}, {1.18, .22, 1.42}, .Body)
    add_box(&mesh, {-.60, .28, 2.48}, {.035, .08, 1.04}, .Red_Paint)
    add_box(&mesh, {.60, .28, 2.48}, {.035, .08, 1.04}, .Red_Paint)
    add_box(&mesh, {0, .32, 2.48}, {1.04, .12, 1.20}, .Frame)
    add_box(&mesh, {-.53, .58, 2.48}, {.10, .48, 1.20}, .Frame)
    add_box(&mesh, {.53, .58, 2.48}, {.10, .48, 1.20}, .Frame)
    add_box(&mesh, {0, .58, 1.91}, {1.04, .48, .10}, .Frame)
    add_box(&mesh, {0, .52, 3.05}, {1.04, .34, .10}, .Frame)
    // A compact cargo box makes the open bed legible at gameplay distance.
    add_box(&mesh, {0, .49, 2.48}, {.70, .28, .72}, .Bumper)
    add_box(&mesh, {0, .66, 2.48}, {.72, .05, .72}, .Ivory)
    add_box(&mesh, {-.25, .69, 2.48}, {.06, .06, .76}, .Strap)
    add_box(&mesh, {.25, .69, 2.48}, {.06, .06, .76}, .Strap)
    add_box(&mesh, {0, .25, 1.62}, {.14, .14, .48}, .Frame)
    if attached {
        add_horizontal_beam(&mesh, {-.30, .28, 1.50}, {-.14, .25, 1.36}, .045, .Strap)
        add_horizontal_beam(&mesh, {.30, .28, 1.50}, {.14, .25, 1.36}, .045, .Strap)
    }
    if detached && jockey_deployed {
        add_box(&mesh, {0, .13, 1.42}, {.08, .24, .08}, .Dark_Metal)
        add_box(&mesh, {0, .025, 1.42}, {.26, .05, .18}, .Bumper)
    }
    add_box(&mesh, {-.64, .50, 2.48}, {.18, .16, .86}, .Body)
    add_box(&mesh, {.64, .50, 2.48}, {.18, .16, .86}, .Body)
    add_box(&mesh, {-.75, .55, 2.82}, {.04, .08, .14}, .Headlight)
    add_box(&mesh, {.75, .55, 2.82}, {.04, .08, .14}, .Headlight)
    add_box(&mesh, {0, .28, 1.36}, {.28, .18, .18}, .Dark_Metal)
    add_box(&mesh, {-.48, .18, 3.16}, {.16, .16, .16}, .Tail_Light)
    add_box(&mesh, {.48, .18, 3.16}, {.16, .16, .16}, .Tail_Light)
    trailer_spare_wheel(&mesh, {0, .52, 3.14})
    add_box(&mesh, {.32, .34, 3.12}, {.22, .12, .04}, .Ivory)

    wheel_x := [2]f32{-.64, .64}
    for x in wheel_x {
        trailer_wheel(&mesh, {x, .26, 2.48})
    }
    return mesh
}

CAR_SPAWN_OFFSET :: f32(2)

car_spawn_near :: proc(player_spawn: third_person.Vec3) -> third_person.Vec3 {
    return {
        player_spawn.x,
        player_spawn.y,
        // Park beyond the player, across the runway from the aircraft, instead
        // of overlapping the Postale's longitudinal footprint.
        player_spawn.z + CAR_SPAWN_OFFSET,
    }
}
