package vehicles

import third_person "../third_person"
import "core:math"

CAR_WHEEL_TRACK_HALF :: f32(.675)
CAR_WHEELBASE_HALF :: f32(.96)
CAR_WHEEL_RADIUS :: f32(.235)
CAR_WHEEL_CENTER_Y :: CAR_WHEEL_RADIUS
CAR_WHEEL_WIDTH :: f32(.17)
CAR_WHEEL_HUB_RADIUS :: f32(.095)

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

    // Cream face discs sit between the black tire and metal hub. The hub is
    // submitted after them and covers each center, leaving a crisp whitewall
    // annulus without requiring a separate ring topology.
    whitewall_face := half_width + .004
    whitewall := [2]Mesh_Ring{{-whitewall_face, .165, 0, .165}, {whitewall_face, .165, 0, .165}}
    first = mesh.vertex_count
    add_ring_mesh(mesh, whitewall[:], 12, .Rounded_Ivory)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    translate_new_vertices(mesh, first, center)

    hub_face := half_width + .005
    hub := [2]Mesh_Ring {
        {-hub_face, CAR_WHEEL_HUB_RADIUS, 0, CAR_WHEEL_HUB_RADIUS},
        {hub_face, CAR_WHEEL_HUB_RADIUS, 0, CAR_WHEEL_HUB_RADIUS},
    }
    first = mesh.vertex_count
    add_ring_mesh(mesh, hub[:], 12, .Rounded_Chrome)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    translate_new_vertices(mesh, first, center)
}

car_ellipsoid :: proc(
    mesh: ^Aircraft_Mesh,
    center: [3]f32,
    radius_x, radius_y, radius_z: f32,
    part: Aircraft_Mesh_Part,
) {
    if mesh == nil do return
    profile_z := [5]f32{-1, -.50, 0, .50, 1}
    // Keep the terminal rings broad enough that the generated cap triangles
    // remain numerically healthy at tail-lamp scale.
    profile_radius := [5]f32{.40, .87, 1, .87, .40}
    rings: [5]Mesh_Ring
    for index in 0 ..< len(rings) {
        rings[index] = {
            z        = center[2] + profile_z[index] * radius_z,
            width    = radius_x * profile_radius[index],
            center_y = center[1],
            height   = radius_y * profile_radius[index],
        }
    }
    first := mesh.vertex_count
    add_ring_mesh(mesh, rings[:], 8, part)
    translate_new_vertices(mesh, first, {center[0], 0, 0})
}

// Build the main coachwork with a genuine opening above the cockpit tub.
// The ordinary ring builder closes every strip around the ellipse, which left
// a teal roof-like surface beneath the driver even though the car is open-top.
// Here the three upward-facing strips are omitted only between the scuttle and
// rear deck; the lower chassis and both side sills remain continuous.
add_car_open_body :: proc(mesh: ^Aircraft_Mesh, rings: []Mesh_Ring, sides: int, part: Aircraft_Mesh_Part) {
    if mesh == nil || len(rings) < 2 || sides < 5 do return
    COCKPIT_FRONT_RING :: 3
    COCKPIT_REAR_RING :: 4
    for ring_index in 0 ..< len(rings) - 1 {
        cockpit_span := ring_index == COCKPIT_FRONT_RING && ring_index + 1 == COCKPIT_REAR_RING
        for side in 0 ..< sides {
            // With ten sides, strips 1-3 form the crown of the elliptical
            // section. Removing them exposes a broad opening while retaining
            // the shoulder vertices as a clean rim on either side.
            if cockpit_span && side >= 1 && side <= 3 do continue
            next := (side + 1) % sides
            mesh_quad(
                mesh,
                ring_point(rings[ring_index], side, sides),
                ring_point(rings[ring_index + 1], side, sides),
                ring_point(rings[ring_index + 1], next, sides),
                ring_point(rings[ring_index], next, sides),
                part,
            )
        }
    }
    front := [3]f32{0, rings[0].center_y, rings[0].z}
    rear := [3]f32{0, rings[len(rings) - 1].center_y, rings[len(rings) - 1].z}
    for side in 0 ..< sides {
        next := (side + 1) % sides
        mesh_triangle(mesh, front, ring_point(rings[0], next, sides), ring_point(rings[0], side, sides), part)
        mesh_triangle(
            mesh,
            rear,
            ring_point(rings[len(rings) - 1], side, sides),
            ring_point(rings[len(rings) - 1], next, sides),
            part,
        )
    }
}

trailer_wheel :: proc(mesh: ^Aircraft_Mesh, center: [3]f32) {
    tire := [2]Mesh_Ring{{-.11, .25, 0, .25}, {.11, .25, 0, .25}}
    first := mesh.vertex_count
    add_ring_mesh(mesh, tire[:], 12, .Wheel)
    rotate_new_vertices_y(mesh, first, {0, 0, 0}, math.PI * .5)
    translate_new_vertices(mesh, first, center)

    whitewall := [2]Mesh_Ring{{-.113, .175, 0, .175}, {.113, .175, 0, .175}}
    first = mesh.vertex_count
    add_ring_mesh(mesh, whitewall[:], 12, .Ivory)
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

    whitewall := [2]Mesh_Ring{{-.103, .16, 0, .16}, {.103, .16, 0, .16}}
    first = mesh.vertex_count
    add_ring_mesh(mesh, whitewall[:], 12, .Ivory)
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
    lower_body := [8]Mesh_Ring {
        {-1.40, .48, .26, .18},
        {-1.24, .66, .28, .24},
        {-.84, .74, .29, .27},
        {-.52, .76, .29, .27},
        {.60, .76, .29, .27},
        {.84, .74, .29, .27},
        {1.24, .64, .28, .23},
        {1.40, .46, .26, .17},
    }
    add_car_open_body(&mesh, lower_body[:], 10, .Body)

    hood := [4]Mesh_Ring{{-1.34, .44, .47, .08}, {-1.17, .60, .49, .12}, {-.78, .66, .50, .14}, {-.45, .58, .47, .10}}
    add_ring_mesh(&mesh, hood[:], 10, .Body)

    rear_deck := [4]Mesh_Ring{{.46, .57, .45, .08}, {.78, .65, .48, .12}, {1.16, .59, .47, .11}, {1.34, .43, .43, .07}}
    add_ring_mesh(&mesh, rear_deck[:], 10, .Body)

    // Soft wheel shoulders interrupt the long slab side and make each tire
    // feel nested into the coachwork. The wheel mesh is submitted later, so
    // its dark face remains cleanly readable inside these shallow body pods.
    wheel_z := [2]f32{-CAR_WHEELBASE_HALF, CAR_WHEELBASE_HALF}
    for z in wheel_z {
        shoulder := [3]Mesh_Ring{{z - .31, .60, .40, .08}, {z, .76, .40, .28}, {z + .31, .60, .40, .08}}
        add_ring_mesh(&mesh, shoulder[:], 12, .Body)
    }

    // Low cockpit rails preserve a crisp opening against the rounded shells.
    add_box(&mesh, {-.62, .53, .08}, {.16, .18, 1.25}, .Body)
    add_box(&mesh, {.62, .53, .08}, {.16, .18, 1.25}, .Body)

    // Recess the mouse into a complete cockpit tub rather than perching it on
    // a rectangular cushion. The dark floor and inner door cards remain below
    // the body rails, while a low bucket supports the rump without cutting
    // through the driver's torso.
    add_box(&mesh, {0, .305, .02}, {1.16, .07, 1.06}, .Frame)
    add_box(&mesh, {-.57, .405, .04}, {.055, .22, 1.02}, .Strap)
    add_box(&mesh, {.57, .405, .04}, {.055, .22, 1.02}, .Strap)
    add_box(&mesh, {0, .335, .25}, {.60, .09, .58}, .Strap)
    add_box(&mesh, {0, .49, .55}, {.62, .34, .09}, .Strap)
    // Raised side bolsters keep the seat readable around the mouse instead of
    // turning it back into one broad slab beneath the character.
    add_box(&mesh, {-.30, .39, .29}, {.07, .16, .48}, .Strap)
    add_box(&mesh, {.30, .39, .29}, {.07, .16, .48}, .Strap)

    // Push the dashboard beneath the windscreen and give it a hood, inset
    // fascia, gauges, and lower knee panel. The steering column emerges from
    // its driver-facing surface, leaving open air between the mouse and dash.
    add_box(&mesh, {0, .525, -.535}, {1.00, .13, .13}, .Strap)
    add_box(&mesh, {0, .605, -.545}, {1.08, .045, .16}, .Frame)
    add_box(&mesh, {0, .445, -.54}, {.74, .05, .12}, .Frame)
    gauge_x := [2]f32{-.19, .19}
    for x in gauge_x {
        car_ellipsoid(&mesh, {x, .55, -.466}, .09, .09, .018, .Rounded_Chrome)
        car_ellipsoid(&mesh, {x, .55, -.445}, .058, .058, .012, .Rounded_Ivory)
        add_box(&mesh, {x, .55, -.429}, {.012, .050, .009}, .Strap)
    }
    // A small brass-toned center switch breaks up the fascia at mouse scale.
    car_ellipsoid(&mesh, {0, .505, -.444}, .027, .027, .012, .Headlight)

    // Fine inset door lines give the broad side panel a human-readable scale.
    // Duplicate them on both sides so the detail survives either chase-camera
    // shoulder; shallow boxes avoid z-fighting with the curved body shell.
    door_side_x := [2]f32{-.706, .706}
    for x in door_side_x {
        add_box(&mesh, {x, .43, -.38}, {.018, .30, .018}, .Frame)
        add_box(&mesh, {x, .43, .55}, {.018, .30, .018}, .Frame)
        add_box(&mesh, {x, .29, .085}, {.018, .018, .95}, .Frame)
        add_box(&mesh, {x, .54, .34}, {.026, .035, .14}, .Bumper)
    }

    // Move the short split windscreen toward the nose and rake its top back
    // over the cockpit. The lower pivot keeps the glass rooted in the scuttle.
    windscreen_pivot := [3]f32{0, .54, -.58}
    windscreen_rake := f32(.30)
    first := mesh.vertex_count
    add_box(&mesh, {-.39, .735, -.58}, {.07, .40, .07}, .Bumper)
    rotate_new_vertices_x(&mesh, first, windscreen_pivot, windscreen_rake)
    first = mesh.vertex_count
    add_box(&mesh, {.39, .735, -.58}, {.07, .40, .07}, .Bumper)
    rotate_new_vertices_x(&mesh, first, windscreen_pivot, windscreen_rake)
    first = mesh.vertex_count
    add_box(&mesh, {0, .925, -.58}, {.84, .07, .07}, .Bumper)
    rotate_new_vertices_x(&mesh, first, windscreen_pivot, windscreen_rake)
    first = mesh.vertex_count
    add_box(&mesh, {0, .75, -.58}, {.66, .20, .030}, .Glass)
    rotate_new_vertices_x(&mesh, first, windscreen_pivot, windscreen_rake)

    // Keep the narrower tire faces flush with the shoulder. Realistic kei-car
    // tread is much slimmer relative to diameter than the former toy-like
    // wheels, while the compact wheelbase supplies the short overhangs.
    // A dark, narrow step visually joins the two arches without making the
    // lower body heavy. It also gives the mouse-sized roadster a useful scale
    // cue and a believable place to climb into the open cockpit.
    running_board_x := [2]f32{-.755, .755}
    for x in running_board_x {
        add_box(&mesh, {x, .245, 0}, {.13, .055, 1.18}, .Bumper)
    }

    wheel_x := [2]f32{-CAR_WHEEL_TRACK_HALF, CAR_WHEEL_TRACK_HALF}
    for x in wheel_x {
        for z in wheel_z {
            car_wheel(&mesh, {x, CAR_WHEEL_CENTER_Y, z})
        }
    }

    // Slim overriders punctuate the ends without turning into large grey
    // blocks in profile.
    car_ellipsoid(&mesh, {0, .25, -1.43}, .58, .07, .06, .Rounded_Chrome)
    car_ellipsoid(&mesh, {0, .25, 1.43}, .56, .07, .06, .Rounded_Chrome)
    light_x := [2]f32{-.58, .58}
    for x in light_x {
        car_ellipsoid(&mesh, {x, .57, -1.17}, .14, .12, .09, .Rounded_Chrome)
        car_ellipsoid(&mesh, {x, .57, -1.245}, .11, .09, .065, .Headlight)
        car_ellipsoid(&mesh, {x, .54, 1.16}, .115, .10, .075, .Rounded_Chrome)
        car_ellipsoid(&mesh, {x, .54, 1.215}, .09, .075, .06, .Tail_Light)
    }
    add_box(&mesh, {0, .37, 1.445}, {.34, .13, .035}, .Ivory)
    for mark in -1 ..= 1 {
        add_box(&mesh, {f32(mark) * .075, .37, 1.468}, {.038, .040, .012}, .Strap)
    }
    mesh_finalize(&mesh, &car_mesh_cache, car_uvs[:], car_sources[:], car_indices[:], car_scratch[:])
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
    variant := 0
    if attached {
        variant = 1
    } else if detached && jockey_deployed {
        variant = 2
    }
    mesh_finalize(
        &mesh,
        &trailer_mesh_caches[variant],
        trailer_uvs[variant][:],
        trailer_sources[variant][:],
        trailer_indices[variant][:],
        trailer_scratch[variant][:],
    )
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
