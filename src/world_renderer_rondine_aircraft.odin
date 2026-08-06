package main
import "core:math"

import flight "../packages/flight"
import third_person "zelda_engine:third_person"
import vehicles "../packages/vehicles"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_rondine_tail_fin :: proc(editor: ^Editor, color, edge: canvas2d.Color) {
    // Keep directional stability without competing with the namesake fork:
    // this is a low, aft-swept dorsal feather rather than a conventional
    // upright airplane tail.
    base_front_l := world_rondine_local(editor, {-.11, .66, 3.46})
    base_front_r := world_rondine_local(editor, {.11, .66, 3.46})
    base_rear_l := world_rondine_local(editor, {-.11, .66, 4.92})
    base_rear_r := world_rondine_local(editor, {.11, .66, 4.92})
    peak_l := world_rondine_local(editor, {-.08, 1.76, 4.58})
    peak_r := world_rondine_local(editor, {.08, 1.76, 4.58})
    world_triangle(base_front_l, base_rear_l, peak_l, color)
    world_triangle(base_front_r, peak_r, base_rear_r, color)
    world_quad(base_front_l, peak_l, peak_r, base_front_r, edge)
    world_quad(base_rear_l, base_rear_r, peak_r, peak_l, edge)
}

world_rondine_nacelle :: proc(editor: ^Editor, center_x: f32, top, side, intake: canvas2d.Color) {
    front_z, rear_z := f32(-.62), f32(1.88)
    front_half_x, rear_half_x := f32(.39), f32(.25)
    front_low, front_high := f32(.28), f32(1.04)
    rear_low, rear_high := f32(.4), f32(.9)
    p := [8]third_person.Vec3 {
        world_rondine_local(editor, {center_x - front_half_x, front_low, front_z}),
        world_rondine_local(editor, {center_x + front_half_x, front_low, front_z}),
        world_rondine_local(editor, {center_x + front_half_x, front_high, front_z}),
        world_rondine_local(editor, {center_x - front_half_x, front_high, front_z}),
        world_rondine_local(editor, {center_x - rear_half_x, rear_low, rear_z}),
        world_rondine_local(editor, {center_x + rear_half_x, rear_low, rear_z}),
        world_rondine_local(editor, {center_x + rear_half_x, rear_high, rear_z}),
        world_rondine_local(editor, {center_x - rear_half_x, rear_high, rear_z}),
    }
    world_quad(p[0], p[3], p[2], p[1], intake)
    world_quad(p[4], p[5], p[6], p[7], side)
    world_quad(p[3], p[7], p[6], p[2], top)
    world_quad(p[0], p[4], p[7], p[3], side)
    world_quad(p[1], p[2], p[6], p[5], side)
    world_quad(p[0], p[1], p[5], p[4], {30, 35, 36, 255})
}

world_rondine :: proc(editor: ^Editor) {
    if editor == nil ||
       !editor.rondine_visible ||
       (!editor.vehicle_showcase_scene && !world_aircraft_in_view(editor, editor.rondine.body.position, 16)) {
        return
    }
    cream := canvas2d.Color{231, 216, 171, 255}
    red := canvas2d.Color{174, 54, 42, 255}
    dark := canvas2d.Color{41, 48, 51, 255}
    cockpit := canvas2d.Color{24, 31, 34, 255}
    leather := canvas2d.Color{113, 61, 43, 255}
    glass := canvas2d.Color{116, 181, 194, 190}

    // Low planing hull, broad gull wing and twin pusher booms. The silhouette
    // is deliberately legible from the long, low chase camera used at speed.
    world_rondine_hull(editor, cream, {213, 194, 142, 255}, {161, 58, 44, 255})
    // A restrained red throat marking follows the sharpened bow without
    // turning the whole forebody into a separate colored block.
    nose := world_rondine_local(editor, {0, .42, -5.67})
    nose_l := world_rondine_local(editor, {-.72, -.14, -4.46})
    nose_r := world_rondine_local(editor, {.72, -.14, -4.46})
    nose_top := world_rondine_local(editor, {0, .58, -4.46})
    world_triangle(nose, nose_l, nose_top, red)
    world_triangle(nose, nose_top, nose_r, red)
    world_triangle(nose, nose_r, nose_l, cream)
    // A narrow waterline flash follows the monohull chines without breaking
    // the cream deck into unrelated color blocks.
    stripe_l_fore_top := world_rondine_local(editor, {-1.11, .53, -3.42})
    stripe_l_fore_low := world_rondine_local(editor, {-1.04, .3, -3.42})
    stripe_l_aft_low := world_rondine_local(editor, {-1.08, .22, 1.72})
    stripe_l_aft_top := world_rondine_local(editor, {-1.2, .5, 1.72})
    stripe_r_fore_top := world_rondine_local(editor, {1.11, .53, -3.42})
    stripe_r_fore_low := world_rondine_local(editor, {1.04, .3, -3.42})
    stripe_r_aft_low := world_rondine_local(editor, {1.08, .22, 1.72})
    stripe_r_aft_top := world_rondine_local(editor, {1.2, .5, 1.72})
    world_quad(stripe_l_fore_top, stripe_l_fore_low, stripe_l_aft_low, stripe_l_aft_top, red)
    world_quad(stripe_r_fore_top, stripe_r_aft_top, stripe_r_aft_low, stripe_r_fore_low, red)

    // An open launch-style cockpit keeps the little pilot exposed to the sea
    // air. A dark inset sells the missing deck, while the coaming and seat
    // remain chunky enough to read at gameplay distance.
    // Sink the floor below the coaming so the opening has real depth from the
    // chase camera instead of reading as a dark decal on the cream deck.
    world_rondine_box(editor, {0, .84, -.15}, {1.52, .08, 2.22}, cockpit)
    world_rondine_box(editor, {-.91, 1.08, -.15}, {.14, .25, 2.55}, cream)
    world_rondine_box(editor, {.91, 1.08, -.15}, {.14, .25, 2.55}, cream)
    world_rondine_box(editor, {0, 1.08, 1.1}, {1.82, .25, .16}, cream)
    world_rondine_box(editor, {-.83, 1.25, -.15}, {.12, .12, 2.55}, leather)
    world_rondine_box(editor, {.83, 1.25, -.15}, {.12, .12, 2.55}, leather)
    world_rondine_box(editor, {0, 1.25, 1.06}, {1.55, .12, .12}, leather)
    // Dark inner faces exaggerate the recess while leaving a slim, warm
    // coaming highlight around the exposed pilot.
    world_rondine_box(editor, {-.73, 1.03, -.15}, {.08, .36, 2.22}, cockpit)
    world_rondine_box(editor, {.73, 1.03, -.15}, {.08, .36, 2.22}, cockpit)
    world_rondine_box(editor, {0, 1.03, .94}, {1.48, .36, .08}, cockpit)
    world_rondine_box(editor, {0, 1.18, .5}, {1.16, .52, .18}, leather)
    world_rondine_box(editor, {0, 1.04, -.55}, {.9, .12, .72}, leather)
    world_rondine_box(editor, {0, 1.2, -1.02}, {1.34, .35, .12}, dark)
    windscreen_l := world_rondine_local(editor, {-.78, 1.1, -1.35})
    windscreen_r := world_rondine_local(editor, {.78, 1.1, -1.35})
    windscreen_rt := world_rondine_local(editor, {.64, 1.62, -1.08})
    windscreen_lt := world_rondine_local(editor, {-.64, 1.62, -1.08})
    world_quad(windscreen_l, windscreen_lt, windscreen_rt, windscreen_r, glass)
    world_quad(windscreen_r, windscreen_rt, windscreen_lt, windscreen_l, glass)
    // Keep the open cockpit mechanically legible: a framed screen, compact
    // yoke, and brass-faced instruments are visible around the seated mouse.
    world_rondine_box(editor, {-.72, 1.36, -1.2}, {.06, .58, .07}, dark)
    world_rondine_box(editor, {.72, 1.36, -1.2}, {.06, .58, .07}, dark)
    world_rondine_box(editor, {0, 1.33, -.56}, {.07, .48, .07}, dark)
    world_rondine_box(editor, {0, 1.55, -.56}, {.7, .07, .08}, dark)
    world_rondine_box(editor, {-.27, 1.31, -.96}, {.16, .13, .05}, {215, 184, 104, 255})
    world_rondine_box(editor, {0, 1.31, -.96}, {.16, .13, .05}, {215, 184, 104, 255})
    world_rondine_box(editor, {.27, 1.31, -.96}, {.16, .13, .05}, {215, 184, 104, 255})

    // Long swept panels and needle tips give Rondine the planform of its
    // namesake instead of a conventional rectangular light-aircraft wing.
    wing_l_tip := world_rondine_local(editor, {-8.9, .79, .92})
    wing_l_aft := world_rondine_local(editor, {-6.55, .66, 1.58})
    wing_l_root_aft := world_rondine_local(editor, {-1.18, .44, 1.18})
    wing_l_root := world_rondine_local(editor, {-1.03, .54, -.92})
    wing_r_root := world_rondine_local(editor, {1.03, .54, -.92})
    wing_r_root_aft := world_rondine_local(editor, {1.18, .44, 1.18})
    wing_r_aft := world_rondine_local(editor, {6.55, .66, 1.58})
    wing_r_tip := world_rondine_local(editor, {8.9, .79, .92})
    wing_l_tip_low := world_rondine_local(editor, {-8.9, .64, .92})
    wing_l_aft_low := world_rondine_local(editor, {-6.55, .51, 1.58})
    wing_l_root_aft_low := world_rondine_local(editor, {-1.18, .29, 1.18})
    wing_l_root_low := world_rondine_local(editor, {-1.03, .39, -.92})
    wing_r_root_low := world_rondine_local(editor, {1.03, .39, -.92})
    wing_r_root_aft_low := world_rondine_local(editor, {1.18, .29, 1.18})
    wing_r_aft_low := world_rondine_local(editor, {6.55, .51, 1.58})
    wing_r_tip_low := world_rondine_local(editor, {8.9, .64, .92})
    wing_under := canvas2d.Color{124, 42, 36, 255}
    world_quad(wing_l_tip, wing_l_aft, wing_l_root_aft, wing_l_root, red)
    world_quad(wing_r_root, wing_r_root_aft, wing_r_aft, wing_r_tip, red)
    wing_l_tip_inner := world_rondine_local(editor, {-7.55, .75, .7})
    wing_l_aft_inner := world_rondine_local(editor, {-5.55, .62, 1.5})
    wing_r_tip_inner := world_rondine_local(editor, {7.55, .75, .7})
    wing_r_aft_inner := world_rondine_local(editor, {5.55, .62, 1.5})
    world_quad(wing_l_tip, wing_l_aft, wing_l_aft_inner, wing_l_tip_inner, cream)
    world_quad(wing_r_tip_inner, wing_r_aft_inner, wing_r_aft, wing_r_tip, cream)
    world_quad(wing_l_tip_low, wing_l_root_low, wing_l_root_aft_low, wing_l_aft_low, wing_under)
    world_quad(wing_r_root_low, wing_r_tip_low, wing_r_aft_low, wing_r_root_aft_low, wing_under)
    world_quad(wing_l_tip, wing_l_root, wing_l_root_low, wing_l_tip_low, wing_under)
    world_quad(wing_l_aft, wing_l_tip, wing_l_tip_low, wing_l_aft_low, wing_under)
    world_quad(wing_l_root_aft, wing_l_aft, wing_l_aft_low, wing_l_root_aft_low, wing_under)
    world_quad(wing_r_root, wing_r_tip, wing_r_tip_low, wing_r_root_low, wing_under)
    world_quad(wing_r_tip, wing_r_aft, wing_r_aft_low, wing_r_tip_low, wing_under)
    world_quad(wing_r_aft, wing_r_root_aft, wing_r_root_aft_low, wing_r_aft_low, wing_under)
    tail_l_root := world_rondine_local(editor, {-.3, .62, 3.78})
    tail_l_outer := world_rondine_local(editor, {-3.05, .64, 4.18})
    tail_l_tip := world_rondine_local(editor, {-4.05, .6, 6.65})
    tail_l_inner := world_rondine_local(editor, {-.68, .58, 4.92})
    tail_r_root := world_rondine_local(editor, {.3, .62, 3.78})
    tail_r_inner := world_rondine_local(editor, {.68, .58, 4.92})
    tail_r_tip := world_rondine_local(editor, {4.05, .6, 6.65})
    tail_r_outer := world_rondine_local(editor, {3.05, .64, 4.18})
    world_quad(tail_l_root, tail_l_inner, tail_l_tip, tail_l_outer, red)
    world_quad(tail_r_root, tail_r_outer, tail_r_tip, tail_r_inner, red)
    world_quad(tail_l_outer, tail_l_tip, tail_l_inner, tail_l_root, red)
    world_quad(tail_r_inner, tail_r_tip, tail_r_outer, tail_r_root, red)
    tail_l_tip_inner := world_rondine_local(editor, {-3.05, .65, 5.62})
    tail_l_tip_outer := world_rondine_local(editor, {-3.62, .65, 5.5})
    tail_r_tip_inner := world_rondine_local(editor, {3.05, .65, 5.62})
    tail_r_tip_outer := world_rondine_local(editor, {3.62, .65, 5.5})
    world_triangle(tail_l_tip, tail_l_tip_inner, tail_l_tip_outer, cream)
    world_triangle(tail_r_tip, tail_r_tip_outer, tail_r_tip_inner, cream)
    // Red upper fairings preserve the continuous swept-wing read from above;
    // the dark flanks still make the pusher machinery legible in profile.
    world_rondine_nacelle(editor, -3.8, red, {34, 41, 43, 255}, cream)
    world_rondine_nacelle(editor, 3.8, red, {34, 41, 43, 255}, cream)
    world_rondine_propeller(editor, -3.8, 0, {67, 72, 70, 230})
    world_rondine_propeller(editor, 3.8, math.PI * .25, {67, 72, 70, 230})
    world_rondine_tail_fin(editor, red, {126, 42, 36, 255})
}

postale_bank_grid :: proc(editor: ^Editor, mesh: ^vehicles.Aircraft_Mesh) {
    base := editor.postale.body
    base_basis := flight.basis_from_orientation(base.orientation)
    paint_layer := f32(vehicle_paint_layer_index(.Postale))
    rolls := [5]f32{-1.0471976, -.5235988, 0, .5235988, 1.0471976}
    pitches := [5]f32{-.3490659, -.1745329, 0, .1745329, .3490659}
    for row in 0 ..< 5 {
        for column in 0 ..< 5 {
            body := base
            body.position += base_basis.right * (f32(column) - 2) * 13
            body.position += base_basis.up * (f32(2 - row) * 9)
            pitch_delta := linalg.quaternion_angle_axis(pitches[row], base_basis.right)
            // Flight roll is defined around local +Z; Basis.forward is local
            // -Z, so use the opposite axis to keep the grid labels truthful.
            roll_delta := linalg.quaternion_angle_axis(rolls[column], -base_basis.forward)
            body.orientation = flight.normalize_orientation(roll_delta * pitch_delta * base.orientation)
            transform := world_aircraft_transform(body, POSTALE_PRESENTATION_SCALE)
            for triangle in vehicles.mesh_triangles(mesh) {
                a := mesh.vertices[triangle.a]
                b := mesh.vertices[triangle.b]
                c := mesh.vertices[triangle.c]
                color := aircraft_postale_part_color_with_paint(editor, a.part, editor.postale.throttle)
                if vehicles.aircraft_mesh_part_uses_smooth_normals(a.part) {
                    world_aircraft_triangle_smooth(
                        world_aircraft_vertex_world(transform, a.position),
                        world_aircraft_vertex_world(transform, b.position),
                        world_aircraft_vertex_world(transform, c.position),
                        world_aircraft_normal_world(transform, a.normal),
                        world_aircraft_normal_world(transform, b.normal),
                        world_aircraft_normal_world(transform, c.normal),
                        color,
                        a.uv,
                        b.uv,
                        c.uv,
                        paint_layer,
                        vehicle_paint_part_is_paintable(a.part),
                    )
                } else {
                    world_aircraft_triangle(
                        world_aircraft_vertex_world(transform, a.position),
                        world_aircraft_vertex_world(transform, b.position),
                        world_aircraft_vertex_world(transform, c.position),
                        color,
                        a.uv,
                        b.uv,
                        c.uv,
                        paint_layer,
                        vehicle_paint_part_is_paintable(a.part),
                    )
                }
            }
        }
    }
}

world_aircraft :: proc(editor: ^Editor) {
    world_rondine(editor)
    if editor.capture_postale_bank_grid {
        if world_renderer.postale_pose_mesh == nil do world_renderer.postale_pose_mesh = new(vehicles.Aircraft_Mesh)
        mesh := world_renderer.postale_pose_mesh
        mesh^ = editor.postale_base_mesh^
        postale_bank_grid(editor, mesh)
        return
    }
    if editor.postale_visible && world_aircraft_in_view(editor, editor.postale.body.position, 18) {
        postale_paint_layer := f32(vehicle_paint_layer_index(.Postale))
        postale_propeller_blur := aircraft_propeller_blur_amount(editor.postale.throttle)
        postale_transform := world_aircraft_transform(aircraft_render_body(editor), POSTALE_PRESENTATION_SCALE)
        if world_renderer.postale_pose_mesh == nil {
            world_renderer.postale_pose_mesh = new(vehicles.Aircraft_Mesh)
        }
        mesh := world_renderer.postale_pose_mesh
        mesh^ = editor.postale_base_mesh^
        vehicles.animate_postale_mesh(
            mesh,
            editor.postale.flap_fraction,
            editor.flight_control.pitch,
            editor.flight_control.roll,
            editor.flight_control.yaw,
            editor.postale.propeller_turns,
            editor.postale.gear_compression / POSTALE_PRESENTATION_SCALE,
        )
        for triangle in vehicles.mesh_triangles(mesh) {
            a := mesh.vertices[triangle.a]
            b := mesh.vertices[triangle.b]
            c := mesh.vertices[triangle.c]
            if a.part == .Propeller_Blur && postale_propeller_blur <= .01 do continue
            if vehicles.aircraft_mesh_part_uses_smooth_normals(a.part) {
                world_aircraft_triangle_smooth(
                    world_aircraft_vertex_world(postale_transform, a.position),
                    world_aircraft_vertex_world(postale_transform, b.position),
                    world_aircraft_vertex_world(postale_transform, c.position),
                    world_aircraft_normal_world(postale_transform, a.normal),
                    world_aircraft_normal_world(postale_transform, b.normal),
                    world_aircraft_normal_world(postale_transform, c.normal),
                    aircraft_postale_part_color_with_paint(editor, a.part, editor.postale.throttle),
                    a.uv,
                    b.uv,
                    c.uv,
                    postale_paint_layer,
                    vehicle_paint_part_is_paintable(a.part),
                )
            } else {
                world_aircraft_triangle(
                    world_aircraft_vertex_world(postale_transform, a.position),
                    world_aircraft_vertex_world(postale_transform, b.position),
                    world_aircraft_vertex_world(postale_transform, c.position),
                    aircraft_postale_part_color_with_paint(editor, a.part, editor.postale.throttle),
                    a.uv,
                    b.uv,
                    c.uv,
                    postale_paint_layer,
                    vehicle_paint_part_is_paintable(a.part),
                )
            }
        }
        if editor.capture_postale_transform_parity || editor.tweak.postale_transform_tester_gizmo {
            body := aircraft_render_body(editor)
            physical := flight.basis_from_orientation(body.orientation)
            origin := third_person.Vec3{body.position.x, body.position.y, body.position.z}
            transform := world_aircraft_transform(body, POSTALE_PRESENTATION_SCALE)
            propeller := world_aircraft_vertex_world(transform, {0, .12, -3.42})
            rendered_nose := linalg.normalize(propeller - origin)
            world_tube_between(origin, origin + physical.forward * 9, {0, 1, 0}, .18, .18, {0, 210, 80, 255})
            world_tube_between(origin, origin + rendered_nose * 9, {0, 1, 0}, .18, .18, {230, 50, 40, 255})
            world_tube_between(origin, origin + physical.up * 7, {0, 1, 0}, .18, .18, {50, 120, 240, 255})
        }
    }
    if editor.libellula_visible && world_aircraft_in_view(editor, editor.libellula.body.position, 14) {
        cache := &world_renderer.libellula_geometry_cache
        rotor_turns := [3]f32 {
            editor.libellula.rotor_turns.x,
            editor.libellula.rotor_turns.y,
            editor.libellula.rotor_turns.z,
        }
        if cache.valid &&
           cache.body == editor.libellula.body &&
           cache.kind == editor.aircraft.active &&
           cache.rotor_turns == rotor_turns &&
           cache.pitch == editor.libellula.pitch &&
           cache.roll == editor.libellula.roll {
            append(&world_renderer.vertices, ..cache.vertices[:])
            return
        }
        first := len(world_renderer.vertices)
        libellula := &editor.libellula_visual_mesh
        if editor.aircraft.active == .Libellula_Mk2 {
            vehicles.libellula_mesh_copy(&editor.libellula_mk2_visual_mesh, &editor.libellula_mk2_base_mesh)
            libellula = &editor.libellula_mk2_visual_mesh
            vehicles.animate_libellula_mk2_mesh(
                libellula,
                editor.libellula.rotor_turns.x,
                editor.libellula.rotor_turns.y,
                editor.libellula.rotor_turns.z,
                editor.libellula.rotor_turns.z,
            )
        } else {
            vehicles.libellula_mesh_copy(libellula, &editor.libellula_base_mesh)
            vehicles.animate_libellula_mesh_pose(
                libellula,
                editor.libellula.rotor_turns.x,
                editor.libellula.rotor_turns.y,
                editor.libellula.rotor_turns.z,
                editor.libellula.pitch,
                editor.libellula.roll,
                0,
            )
        }
        libellula_paint_layer := f32(vehicle_paint_layer_index(editor.aircraft.active))
        libellula_transform := world_aircraft_transform(editor.libellula.body, LIBELLULA_PRESENTATION_SCALE)
        for triangle in vehicles.mesh_triangles(libellula) {
            a := libellula.vertices[triangle.a]
            b := libellula.vertices[triangle.b]
            c := libellula.vertices[triangle.c]
            world_aircraft_triangle(
                world_aircraft_vertex_world(libellula_transform, a.position),
                world_aircraft_vertex_world(libellula_transform, b.position),
                world_aircraft_vertex_world(libellula_transform, c.position),
                aircraft_part_color(a.part),
                a.uv,
                b.uv,
                c.uv,
                libellula_paint_layer,
                vehicle_paint_part_is_paintable(a.part),
            )
        }
        clear(&cache.vertices)
        if first < len(world_renderer.vertices) {
            append(&cache.vertices, ..world_renderer.vertices[first:])
        }
        cache.valid = true
        cache.body = editor.libellula.body
        cache.kind = editor.aircraft.active
        cache.rotor_turns = rotor_turns
        cache.pitch = editor.libellula.pitch
        cache.roll = editor.libellula.roll
    }
}

world_rondine_spray_streak :: proc(
    camera: Perspective_Camera,
    position, direction: third_person.Vec3,
    size: f32,
    color: canvas2d.Color,
) {
    direction_length := f32(
        math.sqrt(f64(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)),
    )
    if direction_length <= .001 do return
    unit_direction := direction / direction_length
    // Build the ribbon width perpendicular to both its trajectory and the
    // view direction. A fixed `camera.right` width collapses when a streak
    // travels laterally across the screen and shears steep droplets into
    // broad wedges. This cross product keeps every procedural needle thin,
    // trajectory-aligned, and camera-facing without a sprite billboard.
    width_axis := third_person.Vec3 {
        camera.forward.y * unit_direction.z - camera.forward.z * unit_direction.y,
        camera.forward.z * unit_direction.x - camera.forward.x * unit_direction.z,
        camera.forward.x * unit_direction.y - camera.forward.y * unit_direction.x,
    }
    width_length := f32(
        math.sqrt(f64(width_axis.x * width_axis.x + width_axis.y * width_axis.y + width_axis.z * width_axis.z)),
    )
    if width_length > .001 {
        width_axis /= width_length
    } else {
        width_axis = camera.right
    }
    half_width := width_axis * (size * .34)
    tail := position - unit_direction * (size * .55)
    tip := position + unit_direction * (size * 2.4)
    clear := canvas2d.Color{color.r, color.g, color.b, 0}
    world_triangle_colored(tail - half_width, tail + half_width, tip, clear, clear, color)
}

world_rondine_triangle_colored :: proc(
    a, b, c: third_person.Vec3,
    color_a, color_b, color_c: canvas2d.Color,
    mirrored: bool,
) {
    if mirrored {
        world_triangle_colored(a, c, b, color_a, color_c, color_b)
    } else {
        world_triangle_colored(a, b, c, color_a, color_b, color_c)
    }
}

world_rondine_triangle_double_sided :: proc(a, b, c: third_person.Vec3, color_a, color_b, color_c: canvas2d.Color) {
    world_triangle_colored(a, b, c, color_a, color_b, color_c)
    world_triangle_colored(a, c, b, color_a, color_c, color_b)
}

world_rondine_spray_bead :: proc(
    camera: Perspective_Camera,
    position: third_person.Vec3,
    size: f32,
    color: canvas2d.Color,
) {
    if color.a <= 1 || size <= .001 do return
    // Four fading triangles make a tiny camera-facing droplet head. Keeping
    // the center opaque and every outer point transparent preserves the
    // faceted procedural language while avoiding a hard diamond silhouette.
    horizontal := camera.right * size
    vertical := camera.up * (size * 1.18)
    clear := canvas2d.Color{color.r, color.g, color.b, 0}
    top := position + vertical
    right := position + horizontal
    bottom := position - vertical
    left := position - horizontal
    world_rondine_triangle_double_sided(position, top, right, color, clear, clear)
    world_rondine_triangle_double_sided(position, right, bottom, color, clear, clear)
    world_rondine_triangle_double_sided(position, bottom, left, color, clear, clear)
    world_rondine_triangle_double_sided(position, left, top, color, clear, clear)
}

world_rondine_surface_chip :: proc(
    position, tangent, radial: third_person.Vec3,
    half_length, half_width: f32,
    color: canvas2d.Color,
    double_sided := false,
) {
    tangent_axis := tangent
    tangent_length := f32(
        math.sqrt(
            f64(tangent_axis.x * tangent_axis.x + tangent_axis.y * tangent_axis.y + tangent_axis.z * tangent_axis.z),
        ),
    )
    if tangent_length > .0001 do tangent_axis /= tangent_length
    radial_axis := radial
    radial_length := f32(
        math.sqrt(f64(radial_axis.x * radial_axis.x + radial_axis.y * radial_axis.y + radial_axis.z * radial_axis.z)),
    )
    if radial_length > .0001 do radial_axis /= radial_length
    // Remove any component parallel to the length axis. Most callers provide
    // an approximate perpendicular assembled from forward/right weights; a
    // small shared component otherwise shears the two triangles into a kite
    // and changes apparent width with maneuver direction.
    radial_axis -= tangent_axis * linalg.dot(radial_axis, tangent_axis)
    radial_length = f32(
        math.sqrt(f64(radial_axis.x * radial_axis.x + radial_axis.y * radial_axis.y + radial_axis.z * radial_axis.z)),
    )
    if radial_length > .0001 {
        radial_axis /= radial_length
    } else {
        // Surface details are horizontal, so a 90-degree turn in XZ is a
        // stable fallback for degenerate or accidentally parallel inputs.
        radial_axis = {-tangent_axis.z, 0, tangent_axis.x}
    }
    clear := canvas2d.Color{color.r, color.g, color.b, 0}
    leading := position + tangent_axis * half_length
    trailing := position - tangent_axis * half_length
    outer := position + radial_axis * half_width
    inner := position - radial_axis * half_width
    if double_sided {
        world_rondine_triangle_double_sided(leading, outer, trailing, clear, color, clear)
        world_rondine_triangle_double_sided(leading, trailing, inner, clear, clear, color)
    } else {
        world_triangle_colored(leading, outer, trailing, clear, color, clear)
        world_triangle_colored(leading, trailing, inner, clear, clear, color)
    }
}

world_rondine_wake_hash :: proc(serial, pressure_role, salt: u32) -> u32 {
    value := serial * u32(1664525) + u32(1013904223)
    value += pressure_role * u32(374761393) + salt * u32(668265263)
    value = (value ~ (value >> 13)) * u32(1274126177)
    return value ~ (value >> 16)
}

world_rondine_live_variation :: proc(epoch: u32, blend: f32, pressure_role, salt: u32) -> f32 {
    first := f32(world_rondine_wake_hash(epoch, pressure_role, salt) % 1024) / 1023
    second := f32(world_rondine_wake_hash(epoch + 1, pressure_role, salt) % 1024) / 1023
    t := clamp(blend, 0, 1)
    smooth := t * t * (3 - 2 * t)
    return first + (second - first) * smooth
}

world_rondine_surface_heading :: proc(editor: ^Editor) -> third_person.Vec3 {
    if editor == nil do return {0, 0, -1}
    basis := flight.basis_from_orientation(editor.rondine.body.orientation)
    body_forward := third_person.Vec3{basis.forward.x, 0, basis.forward.z}
    horizontal_velocity := third_person.Vec3{editor.rondine.body.velocity.x, 0, editor.rondine.body.velocity.z}
    horizontal_speed := f32(
        math.sqrt(f64(horizontal_velocity.x * horizontal_velocity.x + horizontal_velocity.z * horizontal_velocity.z)),
    )
    if horizontal_speed <= .01 do return body_forward
    travel_forward := horizontal_velocity / horizontal_speed
    travel_blend := clamp(math.abs(editor.rondine.telemetry.slip) * 1.8, 0, .72)
    heading := body_forward * (1 - travel_blend) + travel_forward * travel_blend
    heading_length := f32(math.sqrt(f64(heading.x * heading.x + heading.z * heading.z)))
    if heading_length <= .01 do return body_forward
    return heading / heading_length
}
