package main
import "core:math"
import "core:time"

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

world_architecture_roof :: proc(
    source_structure: terrain.Structure,
    landmark: bool,
    lod: Structure_LOD = .Near,
    primary_mass: bool = true,
) {
    structure := source_structure
    eave_y := structure.base_y + structure.height
    roof_style := world_architecture_roof_style(structure)
    identity := architecture.architecture_resolve_legacy_identity(structure)
    tower_landmark := identity.archetype == .Campanile || identity.archetype == .Cycladic_Bell
    ceremonial_roof := tower_landmark || identity.archetype == .Church
    gable_roof := !ceremonial_roof && (roof_style == .Gable || roof_style == .Low_Gable)
    hip_roof := ceremonial_roof || roof_style == .Hip
    if !ceremonial_roof && roof_style == .Parapet {
        is_aegean := identity.region == .Aegean
        roof_color := canvas2d.Color{229, 226, 211, 255}
        deck_color := canvas2d.Color{207, 210, 199, 255}
        coping_color := canvas2d.Color{242, 240, 226, 255}
        chimney_color := canvas2d.Color{221, 218, 203, 255}
        chimney_width := clamp(structure.width * .06, f32(.82), f32(1.15))
        chimney_height := f32(1.25)
        if !is_aegean {
            roof_bytes := architecture.architecture_roof_color(structure.seed)
            roof_color = {roof_bytes[0], roof_bytes[1], roof_bytes[2], roof_bytes[3]}
            deck_bytes := architecture.architecture_roof_tile_color(structure.seed, 1)
            coping_bytes := architecture.architecture_roof_tile_color(structure.seed, 4)
            deck_color = {deck_bytes[0], deck_bytes[1], deck_bytes[2], deck_bytes[3]}
            coping_color = {coping_bytes[0], coping_bytes[1], coping_bytes[2], coping_bytes[3]}
            chimney_color = {157, 112, 86, 255}
            chimney_width = clamp(structure.width * .08, f32(1.10), f32(1.65))
            chimney_height = 1.65
        }
        world_box_rotated(
            {structure.center_x, eave_y + .25, structure.center_z},
            {structure.width + .8, .50, structure.depth + .8},
            structure.rotation,
            roof_color,
        )
        // A parapet roof needs a raised perimeter, not just a thick flat
        // slab. Four narrow bands preserve the usable roof terrace while
        // producing the stepped white skyline characteristic of Aegean
        // buildings (and a masonry coping on rarer Adriatic flat roofs).
        parapet_height := is_aegean ? f32(.72) : f32(.58)
        parapet_thickness := is_aegean ? f32(.28) : f32(.34)
        parapet_center_y := eave_y + .50 + parapet_height * .5
        parapet_offset_x := structure.width * .5 + .40 - parapet_thickness * .5
        parapet_offset_z := structure.depth * .5 + .40 - parapet_thickness * .5
        for side in -1 ..= 1 {
            if side == 0 do continue
            side_x, side_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(side) * parapet_offset_x,
                0,
                structure.rotation,
            )
            world_box_rotated(
                {side_x, parapet_center_y, side_z},
                {parapet_thickness, parapet_height, structure.depth + .8},
                structure.rotation,
                roof_color,
            )
            end_x, end_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                f32(side) * parapet_offset_z,
                structure.rotation,
            )
            world_box_rotated(
                {end_x, parapet_center_y, end_z},
                {structure.width + .8, parapet_height, parapet_thickness},
                structure.rotation,
                roof_color,
            )
        }
        if lod != .Far {
            // Expose a distinct terrace floor inside the perimeter instead of
            // letting the structural slab and parapet merge into one tray.
            deck_width := max(f32(.5), structure.width + .8 - parapet_thickness * 2)
            deck_depth := max(f32(.5), structure.depth + .8 - parapet_thickness * 2)
            world_box_rotated(
                {structure.center_x, eave_y + .525, structure.center_z},
                {deck_width, .05, deck_depth},
                structure.rotation,
                deck_color,
            )

            // A narrow coping course protects the wall tops and catches a
            // highlight that keeps pale Aegean parapets readable at distance.
            coping_thickness := parapet_thickness + .12
            coping_y := eave_y + .50 + parapet_height + .055
            for side in -1 ..= 1 {
                if side == 0 do continue
                side_x, side_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    f32(side) * parapet_offset_x,
                    0,
                    structure.rotation,
                )
                world_box_rotated(
                    {side_x, coping_y, side_z},
                    {coping_thickness, .11, structure.depth + .92},
                    structure.rotation,
                    coping_color,
                )
                end_x, end_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    0,
                    f32(side) * parapet_offset_z,
                    structure.rotation,
                )
                world_box_rotated(
                    {end_x, coping_y, end_z},
                    {structure.width + .92, .11, coping_thickness},
                    structure.rotation,
                    coping_color,
                )
            }
        }
        if lod != .Far && architecture.architecture_has_chimney(structure.seed) {
            chimney_side := structure.seed % 2 == 0 ? f32(1) : f32(-1)
            chimney_end := (structure.seed / 2) % 2 == 0 ? f32(-1) : f32(1)
            chimney_x, chimney_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                chimney_side * structure.width * .22,
                chimney_end * structure.depth * .16,
                structure.rotation,
            )
            world_box_rotated(
                {chimney_x, eave_y + .50 + chimney_height * .5, chimney_z},
                {chimney_width, chimney_height, chimney_width},
                structure.rotation,
                chimney_color,
            )
            world_box_rotated(
                {chimney_x, eave_y + .50 + chimney_height + .07, chimney_z},
                {chimney_width + .22, .14, chimney_width + .22},
                structure.rotation,
                coping_color,
            )
        }
        if lod == .Near {
            // A single seeded scupper gives the enclosed terrace a believable
            // drainage outlet without ringing every wall with hardware.
            scupper_side := structure.seed % 2 == 0 ? f32(-1) : f32(1)
            scupper_z_local := ((structure.seed / 2) % 2 == 0 ? f32(-1) : f32(1)) * structure.depth * .20
            scupper_inner_x, scupper_inner_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                scupper_side * (structure.width * .5 + .16),
                scupper_z_local,
                structure.rotation,
            )
            scupper_outer_x, scupper_outer_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                scupper_side * (structure.width * .5 + .72),
                scupper_z_local,
                structure.rotation,
            )
            scupper_y := eave_y + .50 + parapet_height * .34
            world_tube_between(
                {scupper_inner_x, scupper_y, scupper_inner_z},
                {scupper_outer_x, scupper_y - .06, scupper_outer_z},
                {0, 1, 0},
                .055,
                .055,
                {79, 78, 69, 255},
            )
        }
        return
    }
    // Pitched roofs are authored with their ridge along local depth. Normalize
    // the local roof frame so that depth is always the footprint's longest
    // axis; this keeps broad buildings from receiving a short-axis ridge.
    structure.width, structure.depth, structure.rotation = world_roof_long_axis_frame(
        structure.width,
        structure.depth,
        structure.rotation,
    )
    rise := ceremonial_roof ? structure.width * .72 : structure.width * .34
    if !ceremonial_roof && roof_style == .Low_Gable do rise = structure.width * .24
    depth := structure.depth * .58
    left_front_x, left_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .54,
        -depth,
        structure.rotation,
    )
    right_front_x, right_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .54,
        -depth,
        structure.rotation,
    )
    left_back_x, left_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .54,
        depth,
        structure.rotation,
    )
    right_back_x, right_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .54,
        depth,
        structure.rotation,
    )
    left_front := third_person.Vec3{left_front_x, eave_y, left_front_z}
    right_front := third_person.Vec3{right_front_x, eave_y, right_front_z}
    left_back := third_person.Vec3{left_back_x, eave_y, left_back_z}
    right_back := third_person.Vec3{right_back_x, eave_y, right_back_z}
    ridge_half_depth := depth
    if hip_roof do ridge_half_depth = depth * .50
    ridge_front_x, ridge_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        -ridge_half_depth,
        structure.rotation,
    )
    ridge_back_x, ridge_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        ridge_half_depth,
        structure.rotation,
    )
    ridge_front := third_person.Vec3{ridge_front_x, eave_y + rise, ridge_front_z}
    ridge_back := third_person.Vec3{ridge_back_x, eave_y + rise, ridge_back_z}
    left_apex_x, left_apex_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .54,
        0,
        structure.rotation,
    )
    right_apex_x, right_apex_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .54,
        0,
        structure.rotation,
    )
    left_apex := third_person.Vec3{left_apex_x, eave_y + rise, left_apex_z}
    right_apex := third_person.Vec3{right_apex_x, eave_y + rise, right_apex_z}
    wall_left_front_x, wall_left_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .5,
        -structure.depth * .5,
        structure.rotation,
    )
    wall_left_back_x, wall_left_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .5,
        structure.depth * .5,
        structure.rotation,
    )
    wall_right_front_x, wall_right_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .5,
        -structure.depth * .5,
        structure.rotation,
    )
    wall_right_back_x, wall_right_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .5,
        structure.depth * .5,
        structure.rotation,
    )
    wall_left_front := third_person.Vec3{wall_left_front_x, eave_y, wall_left_front_z}
    wall_left_back := third_person.Vec3{wall_left_back_x, eave_y, wall_left_back_z}
    wall_right_front := third_person.Vec3{wall_right_front_x, eave_y, wall_right_front_z}
    wall_right_back := third_person.Vec3{wall_right_back_x, eave_y, wall_right_back_z}
    wall_front_left := third_person.Vec3{wall_left_front_x, eave_y, wall_left_front_z}
    wall_front_right := third_person.Vec3{wall_right_front_x, eave_y, wall_right_front_z}
    wall_back_left := third_person.Vec3{wall_left_back_x, eave_y, wall_left_back_z}
    wall_back_right := third_person.Vec3{wall_right_back_x, eave_y, wall_right_back_z}
    wall_front_apex := third_person.Vec3 {
        wall_left_front_x + (wall_right_front_x - wall_left_front_x) * .5,
        eave_y + rise,
        wall_left_front_z + (wall_right_front_z - wall_left_front_z) * .5,
    }
    wall_back_apex := third_person.Vec3 {
        wall_left_back_x + (wall_right_back_x - wall_left_back_x) * .5,
        eave_y + rise,
        wall_left_back_z + (wall_right_back_z - wall_left_back_z) * .5,
    }
    roof_bytes := architecture.architecture_roof_color(structure.seed, landmark)
    terracotta := canvas2d.Color{roof_bytes[0], roof_bytes[1], roof_bytes[2], roof_bytes[3]}
    agricultural_stone_roof :=
        identity.region == .Adriatic &&
        (identity.archetype == .Farmstead || identity.archetype == .Barn_Granary) &&
        structure.seed % 4 != 0
    if agricultural_stone_roof {
        stone_roof_palette := [3]canvas2d.Color{{142, 139, 125, 255}, {156, 151, 134, 255}, {129, 132, 123, 255}}
        terracotta = stone_roof_palette[int((structure.seed >> 3) % 3)]
    }
    // The ridge follows the building depth. Gable roofs continue the left and
    // right walls to their ridge apexes; hip roofs close the front and rear
    // ends against the shortened ridge.
    wall := canvas2d.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    if gable_roof {
        // Wind each end cap toward the outside of the building. The previous
        // inward-facing order let back-face culling erase the gable viewed
        // from its corresponding end. Keep the caps on the same stucco atlas
        // material and directional face tint as the upper wall below them.
        cosine, sine := f32(math.cos(f64(structure.rotation))), f32(math.sin(f64(structure.rotation)))
        front_wall := world_architecture_face_color(wall, sine, -cosine)
        back_wall := world_architecture_face_color(wall, -sine, cosine)
        world_architecture_triangle(wall_front_left, wall_front_apex, wall_front_right, front_wall)
        world_architecture_triangle(wall_back_right, wall_back_apex, wall_back_left, back_wall)
    } else if hip_roof {
        world_triangle(left_front, ridge_front, right_front, terracotta)
        world_triangle(right_back, ridge_back, left_back, formation_face_color(terracotta, 1.4, 0))
    }
    world_architecture_quad(left_front, left_back, ridge_back, ridge_front, terracotta, 2)
    world_architecture_quad(
        right_back,
        right_front,
        ridge_front,
        ridge_back,
        formation_face_color(terracotta, 1.4, 0),
        2,
    )
    fascia := formation_face_color(terracotta, math.PI, 0)
    soffit := formation_face_color(terracotta, math.PI * .72, 0)
    front_fascia_x, front_fascia_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        -depth,
        structure.rotation,
    )
    back_fascia_x, back_fascia_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        depth,
        structure.rotation,
    )
    if gable_roof {
        // A gable's end fascia follows both rakes up to the ridge. A single
        // horizontal strip across the eave floated in front of the triangular
        // wall at street level and made the roof read as a detached plank.
        // Follow the overhanging roof edge, not the recessed masonry apex.
        fascia_radius := f32(.12)
        world_tube_between(left_front, ridge_front, {0, 0, 1}, fascia_radius, fascia_radius, fascia)
        world_tube_between(ridge_front, right_front, {0, 0, 1}, fascia_radius, fascia_radius, fascia)
        world_tube_between(right_back, ridge_back, {0, 0, 1}, fascia_radius, fascia_radius, fascia)
        world_tube_between(ridge_back, left_back, {0, 0, 1}, fascia_radius, fascia_radius, fascia)

        // Close the shallow gap between the recessed triangular wall and the
        // overhanging roof edge. These downward-wound strips are the visible
        // underside of the front and rear rake overhangs.
        world_quad(left_front, ridge_front, wall_front_apex, wall_front_left, soffit)
        world_quad(ridge_front, right_front, wall_front_right, wall_front_apex, soffit)
        world_quad(right_back, ridge_back, wall_back_apex, wall_back_right, soffit)
        world_quad(ridge_back, left_back, wall_back_left, wall_back_apex, soffit)
    } else {
        world_box_rotated(
            {front_fascia_x, eave_y + .05, front_fascia_z},
            {structure.width * 1.10, .24, .18},
            structure.rotation,
            fascia,
        )
        world_box_rotated(
            {back_fascia_x, eave_y + .05, back_fascia_z},
            {structure.width * 1.10, .24, .18},
            structure.rotation,
            fascia,
        )
    }
    // Give the long eaves a visible edge. Without this small fascia the roof
    // quad is literally paper-thin and reads as a floating dark strip when
    // the camera is near wall height.
    left_eave_x, left_eave_z := (left_front.x + left_back.x) * .5, (left_front.z + left_back.z) * .5
    right_eave_x, right_eave_z := (right_front.x + right_back.x) * .5, (right_front.z + right_back.z) * .5
    eave_length := depth * 2
    world_box_rotated({left_eave_x, eave_y + .03, left_eave_z}, {.20, .24, eave_length}, structure.rotation, fascia)
    world_box_rotated({right_eave_x, eave_y + .03, right_eave_z}, {.20, .24, eave_length}, structure.rotation, fascia)
    if lod == .Near && !ceremonial_roof {
        // Shallow metal gutters ground the long eaves and give rain a
        // plausible route off the roof. They stay near-only because their
        // narrow silhouette aliases before the rest of the roof reaches
        // medium LOD.
        gutter_color := canvas2d.Color{91, 88, 76, 255}
        gutter_radius := f32(.075)
        for side in -1 ..= 1 {
            if side == 0 do continue
            gutter_front_x, gutter_front_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(side) * structure.width * .545,
                -depth,
                structure.rotation,
            )
            gutter_back_x, gutter_back_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(side) * structure.width * .545,
                depth,
                structure.rotation,
            )
            world_tube_between(
                {gutter_front_x, eave_y - .055, gutter_front_z},
                {gutter_back_x, eave_y - .055, gutter_back_z},
                {0, 1, 0},
                gutter_radius,
                gutter_radius,
                gutter_color,
            )
        }

        // One seeded downspout is enough to explain the drainage without
        // tracing every corner with dark vertical lines. A short kick brings
        // it from the overhanging gutter back to the masonry face.
        drain_side := structure.seed % 2 == 0 ? f32(-1) : f32(1)
        drain_end := (structure.seed / 2) % 2 == 0 ? f32(-1) : f32(1)
        drain_z := drain_end * (depth - .28)
        drain_top_x, drain_top_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            drain_side * structure.width * .545,
            drain_z,
            structure.rotation,
        )
        drain_wall_x, drain_wall_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            drain_side * (structure.width * .5 + .08),
            drain_z,
            structure.rotation,
        )
        drain_elbow_y := eave_y - .48
        world_tube_between(
            {drain_top_x, eave_y - .055, drain_top_z},
            {drain_wall_x, drain_elbow_y, drain_wall_z},
            {0, 0, 1},
            gutter_radius * .82,
            gutter_radius * .82,
            gutter_color,
        )
        world_tube_between(
            {drain_wall_x, drain_elbow_y, drain_wall_z},
            {drain_wall_x, structure.base_y + .32, drain_wall_z},
            {0, 0, 1},
            gutter_radius * .82,
            gutter_radius * .82,
            gutter_color,
        )
    }
    // Close only the narrow long-eave overhangs. A full-width flat plate under
    // the entire roof intersects the triangular gable and reads as a ceiling.
    soffit_width := structure.width * .04
    for side in -1 ..= 1 {
        if side == 0 do continue
        soffit_x, soffit_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            f32(side) * structure.width * .52,
            0,
            structure.rotation,
        )
        world_box_rotated(
            {soffit_x, eave_y + .02, soffit_z},
            {soffit_width, .10, depth * 2},
            structure.rotation,
            soffit,
        )
    }
    if hip_roof {
        end_soffit_depth := structure.depth * .08
        for end in -1 ..= 1 {
            if end == 0 do continue
            soffit_x, soffit_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                f32(end) * structure.depth * .54,
                structure.rotation,
            )
            world_box_rotated(
                {soffit_x, eave_y + .02, soffit_z},
                {structure.width, .10, end_soffit_depth},
                structure.rotation,
                soffit,
            )
        }
    }

    if lod == .Near && !agricultural_stone_roof {
        // These are stylized groups of barrel tiles rather than literal
        // one-tile meshes, but their module must remain small enough that a
        // residential roof reads as courses instead of four giant panels.
        courses := clamp(int(structure.width / 2.6), 6, 11)
        segments := clamp(int(structure.depth / 3.2), 5, 10)
        world_architecture_tile_slope(
            left_front,
            left_back,
            ridge_front,
            ridge_back,
            courses,
            segments,
            structure.seed,
            structure.seed + 3,
        )
        world_architecture_tile_slope(
            right_back,
            right_front,
            ridge_back,
            ridge_front,
            courses,
            segments,
            structure.seed,
            structure.seed + 17,
        )
        if hip_roof {
            end_courses := clamp(int(structure.width / 2.8), 5, 9)
            end_segments := clamp(int(structure.width / 3.2), 4, 8)
            world_architecture_tile_slope(
                left_front,
                right_front,
                ridge_front,
                ridge_front,
                end_courses,
                end_segments,
                structure.seed,
                structure.seed + 29,
                true,
            )
            world_architecture_tile_slope(
                right_back,
                left_back,
                ridge_back,
                ridge_back,
                end_courses,
                end_segments,
                structure.seed,
                structure.seed + 41,
                true,
            )
        }
    }
    if lod != .Far && !agricultural_stone_roof {
        // Mediterranean roofs finish their exposed seams with convex cap
        // tiles. Besides giving the ridge a readable silhouette, these cover
        // the tiny gaps where independently tessellated roof faces meet.
        cap_radius := clamp(structure.width * .016, f32(.16), f32(.28))
        ridge_lift := third_person.Vec3{0, cap_radius * .42, 0}
        world_architecture_roof_cap_run(
            ridge_front + ridge_lift,
            ridge_back + ridge_lift,
            cap_radius,
            structure.seed,
            structure.seed + 53,
            lod == .Near,
        )
        if hip_roof {
            hip_radius := cap_radius * .82
            hip_lift := third_person.Vec3{0, hip_radius * .30, 0}
            world_architecture_roof_cap_run(
                left_front + hip_lift,
                ridge_front + hip_lift,
                hip_radius,
                structure.seed,
                structure.seed + 59,
                lod == .Near,
            )
            world_architecture_roof_cap_run(
                right_front + hip_lift,
                ridge_front + hip_lift,
                hip_radius,
                structure.seed,
                structure.seed + 61,
                lod == .Near,
            )
            world_architecture_roof_cap_run(
                left_back + hip_lift,
                ridge_back + hip_lift,
                hip_radius,
                structure.seed,
                structure.seed + 67,
                lod == .Near,
            )
            world_architecture_roof_cap_run(
                right_back + hip_lift,
                ridge_back + hip_lift,
                hip_radius,
                structure.seed,
                structure.seed + 71,
                lod == .Near,
            )
        }
    }
    if lod != .Far && !landmark && roof_style != .Parapet && architecture.architecture_has_chimney(structure.seed) {
        chimney_side := structure.seed % 2 == 0 ? f32(1) : f32(-1)
        chimney_end := (structure.seed / 2) % 2 == 0 ? f32(-1) : f32(1)
        chimney_local_x := chimney_side * (hip_roof ? structure.width * .12 : structure.width * .18)
        chimney_local_z := chimney_end * structure.depth * .12
        chimney_x, chimney_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            chimney_local_x,
            chimney_local_z,
            structure.rotation,
        )
        half_roof_width := structure.width * .54
        chimney_roof_y := world_roof_surface_y(eave_y, rise, half_roof_width, chimney_local_x)
        chimney_base := chimney_roof_y - .20
        // The stack must clear the ridge even on broad, steep roofs. Sizing
        // from both the local slope and ridge elevation prevents short stacks
        // from disappearing behind the roof while avoiding a fixed giant
        // chimney on compact houses.
        chimney_height := max(f32(2.5), eave_y + rise + .75 - chimney_base)
        chimney_width := clamp(structure.width * .075, f32(1.15), f32(1.75))
        if lod == .Near {
            world_architecture_chimney_flashing(
                structure,
                eave_y,
                rise,
                half_roof_width,
                chimney_local_x,
                chimney_local_z,
                chimney_width,
            )
        }
        world_box_rotated(
            {chimney_x, chimney_base + chimney_height * .5, chimney_z},
            {chimney_width, chimney_height, chimney_width},
            structure.rotation,
            {157, 112, 86, 255},
        )
        chimney_top := chimney_base + chimney_height
        world_box_rotated(
            {chimney_x, chimney_top + .11, chimney_z},
            {chimney_width + .30, .22, chimney_width + .30},
            structure.rotation,
            {184, 93, 61, 255},
        )
        // A pale cap lip and a dark inset keep the stack from reading as a
        // single solid cube at eye level, while preserving the hand-built
        // terracotta character of the roofline.
        world_box_rotated(
            {chimney_x, chimney_top + .27, chimney_z},
            {chimney_width + .50, .10, chimney_width + .50},
            structure.rotation,
            {214, 178, 139, 255},
        )
        world_box_rotated(
            {chimney_x, chimney_top + .34, chimney_z},
            {chimney_width * .72, .035, chimney_width * .72},
            structure.rotation,
            {65, 55, 49, 255},
        )
    }
    world_architecture_roof_crown(
        structure,
        identity,
        landmark,
        primary_mass,
        tower_landmark,
        eave_y,
        rise,
        terracotta,
    )
}
