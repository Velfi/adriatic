package vehicles

import third_person "../third_person"
import wireframe "../wireframe"
import "core:math"

Car_Wireframe :: struct {
    vertices: [32]wireframe.Vertex,
    edges:    [48]wireframe.Edge,
}

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
    tire := [2]Mesh_Ring{{-.12, .32, 0, .32}, {.12, .32, 0, .32}}
    first := mesh.vertex_count
    add_ring_mesh(mesh, tire[:], 12, .Wheel)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    translate_new_vertices(mesh, first, center)

    hub := [2]Mesh_Ring{{-.125, .13, 0, .13}, {.125, .13, 0, .13}}
    first = mesh.vertex_count
    add_ring_mesh(mesh, hub[:], 12, .Bumper)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    translate_new_vertices(mesh, first, center)
}

// simple_car_mesh is a tiny, open-top roadster: its proportions are sized for
// the mouse rather than a human, and the low beltline keeps the driver visible
// in the showcase and during play.
simple_car_mesh :: proc() -> Aircraft_Mesh {
    mesh: Aircraft_Mesh

    // Tiny chassis, hood, rear deck, and a low sill around the open cockpit.
    add_box(&mesh, {0, .22, 0}, {1.46, .38, 2.72}, .Body)
    add_box(&mesh, {0, .48, -.82}, {1.32, .22, .66}, .Body)
    add_box(&mesh, {0, .46, .84}, {1.28, .18, .48}, .Body)
    add_box(&mesh, {-.62, .53, .08}, {.16, .18, 1.25}, .Body)
    add_box(&mesh, {.62, .53, .08}, {.16, .18, 1.25}, .Body)

    // A short split windscreen makes the convertible read clearly without
    // hiding the mouse behind a roof or a tall glass cabin.
    add_box(&mesh, {-.43, .76, -.43}, {.08, .48, .08}, .Frame)
    add_box(&mesh, {.43, .76, -.43}, {.08, .48, .08}, .Frame)
    add_box(&mesh, {0, .98, -.43}, {.92, .08, .08}, .Glass)
    add_box(&mesh, {0, .78, -.43}, {.72, .24, .035}, .Glass)

    // Four broad tires; inset hubs keep the miniature silhouette legible.
    wheel_x := [2]f32{-.78, .78}
    wheel_z := [2]f32{-.82, .82}
    for x in wheel_x {
        for z in wheel_z {
            car_wheel(&mesh, {x, .30, z})
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

CAR_SPAWN_OFFSET :: f32(2)

car_spawn_near :: proc(player_spawn: third_person.Vec3) -> third_person.Vec3 {
    return {
        x = player_spawn.x,
        y = player_spawn.y,
        // Park beyond the player, across the runway from the aircraft, instead
        // of overlapping the Postale's longitudinal footprint.
        z = player_spawn.z + CAR_SPAWN_OFFSET,
    }
}
