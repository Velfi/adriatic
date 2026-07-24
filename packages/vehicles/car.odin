package vehicles

import third_person "../third_person"
import wireframe "../wireframe"

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

// simple_car_mesh is the solid counterpart to simple_car. It deliberately
// uses the shared product-local mesh container so all procedural vehicles can
// be submitted through the same depth-tested world pass.
simple_car_mesh :: proc() -> Aircraft_Mesh {
    mesh: Aircraft_Mesh

    // Chassis and lower body.
    add_box(&mesh, {0, .28, 0}, {1.82, .42, 3.62}, .Body)
    add_box(&mesh, {0, .60, -.08}, {1.72, .36, 3.12}, .Body)

    // A faceted cabin gives the windscreen and rear glass a readable rake.
    cabin_profile := [6]Mesh_Profile_Point {
        {z = -1.08, y = .72},
        {z = -.68, y = 1.35},
        {z = .48, y = 1.35},
        {z = .98, y = .72},
        {z = .72, y = .64},
        {z = -.88, y = .64},
    }
    add_profile_prism(&mesh, cabin_profile[:], .72, .Glass)

    // Four broad tires; slightly inset bright hubs keep the boxy low-poly
    // silhouette legible from the capture camera and during normal play.
    wheel_x := [2]f32{-1.0, 1.0}
    wheel_z := [2]f32{-1.12, 1.12}
    for x in wheel_x {
        for z in wheel_z {
            add_box(&mesh, {x, .31, z}, {.30, .62, .72}, .Wheel)
            add_box(&mesh, {x * 1.015, .31, z}, {.08, .26, .30}, .Bumper)
        }
    }

    add_box(&mesh, {0, .30, -1.88}, {1.68, .18, .18}, .Bumper)
    add_box(&mesh, {0, .30, 1.88}, {1.68, .18, .18}, .Bumper)
    light_x := [2]f32{-.58, .58}
    for x in light_x {
        add_box(&mesh, {x, .61, -1.66}, {.30, .18, .08}, .Headlight)
        add_box(&mesh, {x, .61, 1.66}, {.30, .18, .08}, .Tail_Light)
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
