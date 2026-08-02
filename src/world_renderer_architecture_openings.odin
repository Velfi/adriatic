package main
import "core:math"

import architecture "../packages/architecture"
import flight "../packages/flight"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import canvas2d "zelda_engine:canvas2d"

world_architecture_face_openings :: proc(
    structure: terrain.Structure,
    layout: ^architecture.Opening_Layout,
    window, trim: canvas2d.Color,
) {
    if layout == nil do return
    identity := architecture.architecture_resolve_legacy_identity(structure)
    for opening in layout.openings[:layout.count] {
        // The existing primary façade pass owns its richer doors, shutters,
        // balconies, and storefront details. This pass supplies the other
        // independently generated mass faces.
        mixed_use_private_entry := identity.archetype == .Mixed_Use_Dwelling && opening.kind == .Service_Door
        if mixed_use_private_entry || (opening.face == .Front && opening.kind == .Window) || opening.kind == .Door {
            continue
        }
        horizontal := opening.horizontal
        opening_y := opening.y
        opening_width := opening.width
        opening_height := opening.height
        // Keep the shallow panel wholly beyond the wall plane.  At long
        // streetscape distances a half-embedded panel can lose the depth
        // test to the wall because both surfaces quantize to the same depth.
        // This is still ordinary surface geometry: no depth bias, sorting,
        // or cross-mass visibility query is involved.
        face_offset := f32(.28)
        local_x, local_z, yaw_offset := f32(0), f32(0), f32(0)
        switch opening.face {
        case .Front:
            local_x, local_z = horizontal, structure.depth * .5 + face_offset
        case .Rear:
            local_x, local_z, yaw_offset = -horizontal, -structure.depth * .5 - face_offset, math.PI
        case .Left:
            // world_glass_panel derives its outward normal from the pane yaw.
            // A positive quarter turn points toward local -X (the left face).
            local_x, local_z, yaw_offset = -structure.width * .5 - face_offset, horizontal, math.PI * .5
        case .Right:
            // Conversely, a negative quarter turn points toward local +X.
            local_x, local_z, yaw_offset = structure.width * .5 + face_offset, -horizontal, -math.PI * .5
        }
        wx, wz := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        color :=
            opening.kind == .Vent ? canvas2d.Color{62, 69, 66, 255} : (opening.kind == .Service_Door ? canvas2d.Color{83, 70, 60, 255} : (opening.kind == .Loggia ? canvas2d.Color{39, 45, 44, 255} : window))
        world_box_rotated(
            {wx, structure.base_y + opening_y, wz},
            {opening_width, opening_height, .22},
            structure.rotation + yaw_offset,
            color,
        )
        if opening.kind == .Window {
            glass_local_x, glass_local_z := local_x, local_z
            switch opening.face {
            case .Front:
                glass_local_z += .125
            case .Rear:
                glass_local_z -= .125
            case .Left:
                glass_local_x -= .125
            case .Right:
                glass_local_x += .125
            }
            glass_x, glass_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                glass_local_x,
                glass_local_z,
                structure.rotation,
            )
            glass_tone := int((structure.seed + u32(opening.row * 11) + u32(opening.face) * 7) % 3)
            glass := canvas2d.Color{53, 77, 81, 255}
            if glass_tone == 1 {
                glass = {59, 84, 87, 255}
            } else if glass_tone == 2 {
                glass = {48, 73, 79, 255}
            }
            storefront :=
                opening.face == .Front &&
                opening.row == 0 &&
                (identity.archetype == .Shop_House || identity.archetype == .Mixed_Use_Dwelling)
            interior, interior_light := world_architecture_window_interior(
                structure,
                opening.face,
                opening.row,
                opening.column,
                storefront,
            )
            if interior_light > 0 do glass = interior
            shutter :=
                identity.region == .Aegean ? canvas2d.Color{55, 92, 102, 255} : (structure.seed % 3 == 0 ? canvas2d.Color{132, 55, 49, 255} : canvas2d.Color{57, 88, 73, 255})
            world_architecture_generated_window(
                structure,
                {glass_x, structure.base_y + opening_y, glass_z},
                structure.rotation + yaw_offset,
                opening_width * .84,
                opening_height * .82,
                opening.face,
                opening.row,
                opening.column,
                glass,
                trim,
                shutter,
                {62, 60, 54, 255},
                interior_light,
                false,
            )
        }
        lintel_local_x, lintel_local_z := local_x, local_z
        switch opening.face {
        case .Front:
            lintel_local_z += .045
        case .Rear:
            lintel_local_z -= .045
        case .Left:
            lintel_local_x -= .045
        case .Right:
            lintel_local_x += .045
        }
        lintel_x, lintel_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            lintel_local_x,
            lintel_local_z,
            structure.rotation,
        )
        world_box_rotated(
            {lintel_x, structure.base_y + opening_y + opening_height * .5 + .12, lintel_z},
            {opening_width + .36, .075, .16},
            structure.rotation + yaw_offset,
            trim,
        )
    }
}

world_architecture_balcony :: proc(
    structure: terrain.Structure,
    local_x, local_z, sill_y, window_width: f32,
    warm_iron: bool,
) {
    balcony_width := window_width + (warm_iron ? f32(1.20) : f32(1.35))
    balcony_depth: f32 = .90
    slab_center_z := local_z + balcony_depth * .5 - .08
    slab_height: f32 = .20
    slab_center_y := sill_y - .14
    slab_top_y := slab_center_y + slab_height * .5
    slab_x, slab_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_x,
        slab_center_z,
        structure.rotation,
    )
    slab_color := canvas2d.Color{196, 151, 103, 255}
    iron := warm_iron ? canvas2d.Color{83, 68, 62, 255} : canvas2d.Color{102, 76, 63, 255}
    world_box_rotated(
        {slab_x, slab_center_y, slab_z},
        {balcony_width, slab_height, balcony_depth},
        structure.rotation,
        slab_color,
    )
    // A slightly deeper fascia gives the slab a finished stone edge instead
    // of exposing one featureless box at eye level.
    front_z := local_z + balcony_depth - .13
    fascia_x, fascia_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, front_z, structure.rotation)
    world_box_rotated(
        {fascia_x, sill_y - .17, fascia_z},
        {balcony_width + .06, .24, .10},
        structure.rotation,
        formation_face_color(slab_color, math.PI, 0),
    )

    rail_width := balcony_width - .22
    rail_base_y := slab_top_y
    rail_top_y := sill_y + .92
    rail_height := rail_top_y - rail_base_y
    rail_depth: f32 = .07
    top_rail_height: f32 = .10
    lower_rail_y := rail_base_y + .16

    // Front frame: continuous top and lower rails with closely spaced,
    // grounded balusters. This reads as a guard instead of a row of floating
    // sticks, especially against bright glass.
    world_metal_box_rotated(
        {fascia_x, rail_top_y, fascia_z},
        {rail_width + .12, top_rail_height, .09},
        structure.rotation,
        iron,
    )
    world_metal_box_rotated(
        {fascia_x, lower_rail_y, fascia_z},
        {rail_width, .055, rail_depth},
        structure.rotation,
        iron,
    )
    for baluster in -3 ..= 3 {
        baluster_x, baluster_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x + f32(baluster) * rail_width / 6,
            front_z,
            structure.rotation,
        )
        world_metal_box_rotated(
            {baluster_x, (rail_base_y + rail_top_y) * .5, baluster_z},
            {.05, rail_height, rail_depth},
            structure.rotation,
            iron,
        )
    }

    // Carry the guard back to the wall on both sides. The previous balcony
    // only had a top return, which left the slab visibly open at each end.
    back_z := local_z + .06
    return_depth := front_z - back_z
    return_center_z := (front_z + back_z) * .5
    rail_levels := [2]f32{rail_top_y, lower_rail_y}
    for side in -1 ..= 1 {
        if side == 0 do continue
        side_local_x := local_x + f32(side) * rail_width * .5
        for rail_y in rail_levels {
            return_x, return_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x,
                return_center_z,
                structure.rotation,
            )
            world_metal_box_rotated(
                {return_x, rail_y, return_z},
                {.075, rail_y == rail_top_y ? top_rail_height : f32(.055), return_depth},
                structure.rotation,
                iron,
            )
        }
        for depth_step in 0 ..= 2 {
            post_local_z := back_z + f32(depth_step) * return_depth * .5
            post_x, post_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                side_local_x,
                post_local_z,
                structure.rotation,
            )
            world_metal_box_rotated(
                {post_x, (rail_base_y + rail_top_y) * .5, post_z},
                {.06, rail_height, rail_depth},
                structure.rotation,
                iron,
            )
        }
    }

    // Two compact stone brackets make the projection feel supported without
    // turning the façade into a heavy arcade.
    for bracket in -1 ..= 1 {
        if bracket == 0 do continue
        bracket_x, bracket_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x + f32(bracket) * balcony_width * .30,
            local_z + balcony_depth * .22,
            structure.rotation,
        )
        world_box_rotated(
            {bracket_x, sill_y - .31, bracket_z},
            {.16, .36, .26},
            structure.rotation,
            formation_face_color(slab_color, math.PI, 0),
        )
    }
}

world_architecture_mixed_use_side_clearance :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    side: int,
) -> f32 {
    if project == nil do return f32(1.0e20)
    side_f := f32(side)
    threshold_x, threshold_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        side_f * (structure.width * .5 + 1.15),
        structure.depth * .20,
        structure.rotation,
    )
    nearest := f32(1.0e20)
    for neighbor in project.structures[:project.structure_count] {
        if neighbor.kind != .Architecture || neighbor.id == structure.id do continue
        cosine, sine := math.cos(neighbor.rotation), math.sin(neighbor.rotation)
        neighbor_footprint := architecture.architecture_footprint(neighbor)
        for neighbor_mass in neighbor_footprint.masses[:neighbor_footprint.count] {
            mass_x, mass_z := architecture.architecture_mass_world(neighbor, neighbor_mass)
            dx, dz := threshold_x - mass_x, threshold_z - mass_z
            local_x := dx * cosine + dz * sine
            local_z := -dx * sine + dz * cosine
            outside_x := max(math.abs(local_x) - neighbor_mass.width * .5, f32(0))
            outside_z := max(math.abs(local_z) - neighbor_mass.depth * .5, f32(0))
            nearest = min(nearest, f32(math.sqrt(f64(outside_x * outside_x + outside_z * outside_z))))
        }
    }
    return nearest
}

world_architecture_opening_needs_stoop :: proc(opening: architecture.Opening) -> bool {
    return opening.primary && (opening.kind == .Door || opening.kind == .Service_Door)
}

world_architecture_door_stoop :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    opening: architecture.Opening,
    color: canvas2d.Color,
) {
    // Settlement access guarantees the primary entrance only. Secondary
    // service doors may face any exposed mass; giving each one a full flight
    // on a slope creates unsupported stairs that terminate in private lawn.
    if project == nil || !world_architecture_opening_needs_stoop(opening) do return

    threshold_y := structure.base_y + opening.y - opening.height * .5
    outward_x, outward_z, yaw_offset := f32(0), f32(0), f32(0)
    wall_x, wall_z := f32(0), f32(0)
    switch opening.face {
    case .Front:
        wall_x, wall_z, outward_z = opening.horizontal, structure.depth * .5, 1
    case .Rear:
        wall_x, wall_z, outward_z, yaw_offset = -opening.horizontal, -structure.depth * .5, -1, math.PI
    case .Left:
        wall_x, wall_z, outward_x, yaw_offset = -structure.width * .5, opening.horizontal, -1, math.PI * .5
    case .Right:
        wall_x, wall_z, outward_x, yaw_offset = structure.width * .5, -opening.horizontal, 1, -math.PI * .5
    }

    tangent_x, tangent_z := outward_z, -outward_x
    // Keep the seeded choice stable unless a straight flight would intrude
    // into a committed road. In that case the shared access policy selects
    // whichever facade-parallel flight has more road clearance.
    wall_world_x, wall_world_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        wall_x,
        wall_z,
        structure.rotation,
    )
    outward_world_x, outward_world_z := world_rotate_xz(0, 0, outward_x, outward_z, structure.rotation)
    tangent_world_x, tangent_world_z := world_rotate_xz(0, 0, tangent_x, tangent_z, structure.rotation)
    base_choice := int(
        (structure.seed + u32(opening.face) * 17 + u32(max(opening.row, 0)) * 7 + u32(max(opening.column, 0)) * 3) % 3,
    )
    layout_choice := settlement_stoop_layout_choice(
        project,
        structure,
        {wall_world_x, wall_world_z},
        {outward_world_x, outward_world_z},
        {tangent_world_x, tangent_world_z},
        opening.width,
        threshold_y,
        base_choice,
    )
    turn_sign := layout_choice == 1 ? f32(-1) : f32(1)
    turned := layout_choice != 0

    // Buildings are seated at the highest point beneath their footprint.
    // Sample at the foot of the selected run so a doorway on the downhill
    // side receives an actual approach instead of retaining the fixed,
    // floating doorstep used on level sites.
    sample_outward: f32 = .72
    sample_tangent: f32 = 0
    if turned {
        sample_outward = .90
        sample_tangent = turn_sign * (opening.width * .5 + 2.4)
    }
    sample_x, sample_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        wall_x + outward_x * sample_outward + tangent_x * sample_tangent,
        wall_z + outward_z * sample_outward + tangent_z * sample_tangent,
        structure.rotation,
    )
    ground_y := terrain.sample_height(project, 0, sample_x, sample_z)
    rise := threshold_y - ground_y
    if rise <= .30 do return

    step_count := clamp(int(math.ceil(f64(rise / .20))), 2, 14)
    step_rise := rise / f32(step_count)
    tread_depth: f32 = .42
    step_width := turned ? f32(1.22) : opening.width + .82

    if turned {
        // A full-width landing bridges the doorway to the parallel flight.
        // Its solid skirt also conceals the exposed foundation immediately
        // below an entrance on sloping terrain.
        landing_x, landing_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            wall_x + outward_x * .90,
            wall_z + outward_z * .90,
            structure.rotation,
        )
        landing_ground_y := terrain.sample_height(project, 0, landing_x, landing_z)
        landing_height := threshold_y - landing_ground_y
        if landing_height > .025 {
            world_box_rotated(
                {landing_x, landing_ground_y + landing_height * .5, landing_z},
                {opening.width + .82, landing_height, 1.80},
                structure.rotation + yaw_offset,
                color,
            )
        }
    }

    for step in 0 ..< step_count {
        outward_distance := turned ? f32(.90) : .20 + f32(step) * tread_depth
        tangent_distance := f32(0)
        if turned {
            tangent_distance = turn_sign * (opening.width * .5 + tread_depth * (.5 + f32(step)))
        }
        local_x := wall_x + outward_x * outward_distance + tangent_x * tangent_distance
        local_z := wall_z + outward_z * outward_distance + tangent_z * tangent_distance
        step_x, step_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        local_ground_y := terrain.sample_height(project, 0, step_x, step_z)
        top_y := threshold_y - f32(step) * step_rise
        height := top_y - local_ground_y
        if height <= .025 do continue
        actual_step_width := step_width + (turned ? min(f32(step) * .025, f32(.20)) : f32(step) * .10)
        world_box_rotated(
            {step_x, local_ground_y + height * .5, step_z},
            {actual_step_width, height, tread_depth + .04},
            structure.rotation + yaw_offset + (turned ? math.PI * .5 : 0),
            color,
        )
    }

    // Complete the downhill handoff with a small level stone landing. The
    // access network can approach from several angles, but the architectural
    // flight should never deposit its last tread directly into turf. A short
    // slab also gives the rendered vicolo a stable surface to overlap.
    foot_outward := f32(.20) + f32(step_count) * tread_depth + .18
    foot_tangent := f32(0)
    foot_yaw := structure.rotation + yaw_offset
    if turned {
        foot_outward = .90
        foot_tangent = turn_sign * (opening.width * .5 + f32(step_count) * tread_depth + .20)
        foot_yaw += math.PI * .5
    }
    foot_local_x := wall_x + outward_x * foot_outward + tangent_x * foot_tangent
    foot_local_z := wall_z + outward_z * foot_outward + tangent_z * foot_tangent
    foot_x, foot_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        foot_local_x,
        foot_local_z,
        structure.rotation,
    )
    foot_y := terrain.sample_height(project, 0, foot_x, foot_z)
    world_box_rotated({foot_x, foot_y + .06, foot_z}, {step_width + .30, .12, .76}, foot_yaw, color)
    // Give the approach a complete, climbable-looking guard rather than
    // leaving the generated masonry flight bare.  The same local basis works
    // for every facade: straight flights advance along `outward`, while
    // turned flights advance along the signed facade tangent.
    iron := canvas2d.Color{76, 69, 64, 255}
    guard_height: f32 = .86
    rail_radius: f32 = .045
    for side in -1 ..= 1 {
        if side == 0 do continue
        previous_rail: third_person.Vec3
        has_previous := false
        for step in 0 ..< step_count {
            actual_step_width := step_width + (turned ? min(f32(step) * .025, f32(.20)) : f32(step) * .10)
            outward_distance := f32(.20) + f32(step) * tread_depth
            tangent_distance := f32(side) * (actual_step_width * .5 - .10)
            if turned {
                outward_distance = .90 + f32(side) * (actual_step_width * .5 - .10)
                tangent_distance = turn_sign * (opening.width * .5 + tread_depth * (.5 + f32(step)))
            }
            local_x := wall_x + outward_x * outward_distance + tangent_x * tangent_distance
            local_z := wall_z + outward_z * outward_distance + tangent_z * tangent_distance
            rail_x, rail_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            tread_y := threshold_y - f32(step) * step_rise
            rail := third_person.Vec3{rail_x, tread_y + guard_height, rail_z}
            if has_previous {
                world_tube_between(previous_rail, rail, {0, 1, 0}, rail_radius, rail_radius, iron)
            }
            previous_rail, has_previous = rail, true

            // Posts at every other tread keep the silhouette open; shorter
            // intermediate balusters make the assembly read as a balustrade
            // at pedestrian distance without becoming a dark solid fence.
            post_radius := step % 2 == 0 || step == step_count - 1 ? f32(.050) : f32(.032)
            post_top := rail
            post_bottom := third_person.Vec3{rail_x, tread_y + .05, rail_z}
            world_tube_between(post_bottom, post_top, {0, 0, 1}, post_radius, post_radius, iron)
        }
    }

    if turned {
        // Close the exposed face of the landing up to the corner where the
        // parallel flight begins.  The opposite half remains clear for the
        // doorway and prevents the guard from crossing the walking line.
        landing_half := (opening.width + .82) * .5 - .10
        landing_start_tangent := -turn_sign * landing_half
        landing_end_tangent := turn_sign * (opening.width * .5 - .04)
        landing_outward := f32(1.70)
        landing_rail: [3]third_person.Vec3
        for post in 0 ..< len(landing_rail) {
            amount := f32(post) / f32(len(landing_rail) - 1)
            tangent_distance := landing_start_tangent + (landing_end_tangent - landing_start_tangent) * amount
            local_x := wall_x + outward_x * landing_outward + tangent_x * tangent_distance
            local_z := wall_z + outward_z * landing_outward + tangent_z * tangent_distance
            post_x, post_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            landing_rail[post] = {post_x, threshold_y + guard_height, post_z}
            world_tube_between(
                {post_x, threshold_y + .05, post_z},
                landing_rail[post],
                {0, 0, 1},
                post == 0 || post == len(landing_rail) - 1 ? f32(.050) : f32(.032),
                post == 0 || post == len(landing_rail) - 1 ? f32(.050) : f32(.032),
                iron,
            )
            if post > 0 {
                world_tube_between(
                    landing_rail[post - 1],
                    landing_rail[post],
                    {0, 1, 0},
                    rail_radius,
                    rail_radius,
                    iron,
                )
            }
        }

        // Return the guard from the outer corner back toward the wall on the
        // closed side of the landing. The flight-side edge remains open so a
        // person can turn naturally from the mat onto the first tread.
        closed_tangent := landing_start_tangent
        landing_return: [3]third_person.Vec3
        for post in 0 ..< len(landing_return) {
            amount := f32(post) / f32(len(landing_return) - 1)
            outward_distance := .10 + (landing_outward - .10) * amount
            local_x := wall_x + outward_x * outward_distance + tangent_x * closed_tangent
            local_z := wall_z + outward_z * outward_distance + tangent_z * closed_tangent
            post_x, post_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            landing_return[post] = {post_x, threshold_y + guard_height, post_z}
            world_tube_between(
                {post_x, threshold_y + .05, post_z},
                landing_return[post],
                {0, 0, 1},
                post == 0 || post == len(landing_return) - 1 ? f32(.050) : f32(.032),
                post == 0 || post == len(landing_return) - 1 ? f32(.050) : f32(.032),
                iron,
            )
            if post > 0 {
                world_tube_between(
                    landing_return[post - 1],
                    landing_return[post],
                    {0, 1, 0},
                    rail_radius,
                    rail_radius,
                    iron,
                )
            }
        }

        // Bridge the outer landing guard to the outside stair rail around
        // the open corner, instead of drawing a diagonal through the landing.
        flight_tangent := turn_sign * (opening.width * .5 + tread_depth * .5)
        flight_outward := .90 + (step_width * .5 - .10)
        flight_x, flight_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            wall_x + outward_x * flight_outward + tangent_x * flight_tangent,
            wall_z + outward_z * flight_outward + tangent_z * flight_tangent,
            structure.rotation,
        )
        world_tube_between(
            landing_rail[len(landing_rail) - 1],
            {flight_x, threshold_y + guard_height, flight_z},
            {0, 1, 0},
            rail_radius,
            rail_radius,
            iron,
        )
    }
}
