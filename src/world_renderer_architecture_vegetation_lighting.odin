package main
import "core:math"

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import canvas2d "zelda_engine:canvas2d"

world_architecture_cypress_crown :: proc(x, z, base_y: f32, seed: u32) {
    // One continuous profile avoids the pinched necks of stacked cones. The
    // low shoulder stays dense, then small alternating swells carry the eye
    // into a narrow, slightly wind-bent tip.
    RINGS :: 13
    SEGMENTS :: 20
    height_noise := f32(seed % 997) / 996
    width_noise := f32((seed / 997) % 991) / 990
    fullness_noise := f32((seed / 7919) % 983) / 982
    height := 40.5 + height_noise * 5.5
    width := 9.3 + width_noise * 2.0
    fullness := .94 + fullness_noise * .12
    // Small reversals in the taper suggest overlapping upright sprays without
    // breaking the unmistakable columnar outline.
    ring_height := [RINGS]f32{0, .075, .15, .24, .33, .42, .51, .60, .69, .77, .85, .92, .975}
    ring_radius := [RINGS]f32{.72, .96, 1, .94, .96, .84, .86, .72, .70, .57, .45, .28, .105}
    ring_color := [RINGS]canvas2d.Color {
        {30, 68, 43, 255},
        {31, 72, 44, 255},
        {33, 76, 46, 255},
        {35, 81, 48, 255},
        {36, 84, 49, 255},
        {39, 91, 52, 255},
        {41, 95, 54, 255},
        {43, 98, 55, 255},
        {48, 105, 58, 255},
        {51, 109, 60, 255},
        {55, 112, 62, 255},
        {62, 119, 66, 255},
        {70, 126, 70, 255},
    }
    vertices: [RINGS][SEGMENTS]third_person.Vec3
    for ring in 0 ..< RINGS {
        progress := ring_height[ring]
        // Lean grows gradually with height, so the trunk and crown remain one
        // gesture instead of introducing another visibly offset tier.
        lean_x := f32(math.sin(f64(f32(seed) * .013))) * progress * progress * .72
        lean_z := f32(math.cos(f64(f32(seed) * .017))) * progress * progress * .56
        // Each spray band wanders by only a fraction of its radius. Correlated
        // phases keep the movement branch-like rather than noisy.
        branch_drift := math.sin(f32(ring) * 1.71 + f32(seed % 101) * .037)
        center_x := x + lean_x + branch_drift * width * ring_radius[ring] * .026
        center_z :=
            z +
            lean_z +
            f32(math.cos(f64(f32(ring) * 1.43 + f32(seed % 79) * .041))) * width * ring_radius[ring] * .021
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / SEGMENTS
            broad := f32(math.sin(f64(f32(seed) * .009 + angle * 3 + progress * 2.4)))
            fine := f32(math.sin(f64(f32(seed) * .017 + angle * 7 - progress * 3.1)))
            // A slow one-sided bulge creates occasional lateral sprays. Its
            // phase changes by band, preventing a continuous corkscrew seam.
            spray := f32(math.sin(f64(angle + f32(ring) * 1.19 + f32(seed % 127) * .023)))
            spray = max(spray, f32(0))
            irregularity := 1 + broad * .065 + fine * .022 + spray * spray * .055
            // Fullness affects the broad lower and middle sprays, then fades
            // toward the tip so even the stockier trees finish crisply.
            habit_scale := 1 + (fullness - 1) * (1 - progress * progress)
            radius := width * .5 * ring_radius[ring] * irregularity * habit_scale
            vertex_y := base_y + 1.2 + height * progress
            if ring == 0 {
                hanging_spray := f32(math.sin(f64(angle * 4.3 + f32(seed % 173) * .039)))
                hanging_spray = clamp(.48 + hanging_spray * .52, 0, 1)
                vertex_y -= .10 + hanging_spray * .48
            }
            vertices[ring][segment] = {
                center_x + math.cos(angle) * radius,
                vertex_y,
                center_z + math.sin(angle) * radius * .90,
            }
        }
    }
    // Close the low skirt around a shallow raised center. Eye-level views
    // otherwise look into an empty crown and expose the trunk as a square peg.
    skirt_center := third_person.Vec3{x, base_y + 1.55, z}
    skirt_center_color := canvas2d.Color{20, 50, 34, 255}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        angle_here := f32(segment) * math.PI * 2 / SEGMENTS
        angle_next := f32(next) * math.PI * 2 / SEGMENTS
        edge_here := world_architecture_cypress_surface_color(ring_color[0], angle_here, 0, 0, seed)
        edge_next := world_architecture_cypress_surface_color(ring_color[0], angle_next, 0, 0, seed)
        world_triangle_colored(
            vertices[0][next],
            skirt_center,
            vertices[0][segment],
            edge_next,
            skirt_center_color,
            edge_here,
        )
    }
    for ring in 0 ..< RINGS - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            angle_here := f32(segment) * math.PI * 2 / SEGMENTS
            angle_next := f32(next) * math.PI * 2 / SEGMENTS
            lower_here := world_architecture_cypress_surface_color(
                ring_color[ring],
                angle_here,
                ring_height[ring],
                ring,
                seed,
            )
            lower_next := world_architecture_cypress_surface_color(
                ring_color[ring],
                angle_next,
                ring_height[ring],
                ring,
                seed,
            )
            upper_here := world_architecture_cypress_surface_color(
                ring_color[ring + 1],
                angle_here,
                ring_height[ring + 1],
                ring + 1,
                seed,
            )
            upper_next := world_architecture_cypress_surface_color(
                ring_color[ring + 1],
                angle_next,
                ring_height[ring + 1],
                ring + 1,
                seed,
            )
            world_triangle_colored(
                vertices[ring][segment],
                vertices[ring + 1][segment],
                vertices[ring + 1][next],
                lower_here,
                upper_here,
                upper_next,
            )
            world_triangle_colored(
                vertices[ring][segment],
                vertices[ring + 1][next],
                vertices[ring][next],
                lower_here,
                upper_next,
                lower_next,
            )
        }
    }
    tip_x := x + f32(math.sin(f64(f32(seed) * .013))) * .78
    tip_z := z + f32(math.cos(f64(f32(seed) * .017))) * .62
    tip := third_person.Vec3{tip_x, base_y + 1.2 + height * 1.045, tip_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        angle := (f32(segment) + .5) * math.PI * 2 / SEGMENTS
        color := formation_face_color({75, 130, 72, 255}, angle, RINGS)
        world_triangle_colored(
            vertices[RINGS - 1][segment],
            tip,
            vertices[RINGS - 1][next],
            ring_color[RINGS - 1],
            color,
            ring_color[RINGS - 1],
        )
    }
}

world_architecture_cypress :: proc(x, z, base_y: f32, seed: u32) {
    trunk_rotation := f32(seed % 31) * .071
    world_vertical_prism({x, base_y + 3.8, z}, .62, .56, 7.6, trunk_rotation, {101, 73, 47, 255})
    // Short buttress roots visually seat the narrow trunk without competing
    // with the dense low crown.
    for root in 0 ..< 3 {
        angle := trunk_rotation + f32(root) * math.PI * 2 / 3
        root_x := x + math.cos(angle) * .46
        root_z := z + math.sin(angle) * .46
        world_tapered_box_rotated({root_x, base_y + .34, root_z}, .68, .48, .34, .18, .18, angle, {91, 65, 43, 255})
    }
    world_architecture_cypress_crown(x, z, base_y, seed)
}

world_architecture_olive :: proc(x, z, base_y: f32, seed: u32) {
    // Low, wind-shaped olive crowns soften the cypress punctuation and keep
    // the town's planted edges from reading as an empty green plane.
    trunk := terrain.structure_make(x, z, 1.0, 1.0, base_y, 2.8)
    world_box_rotated({x, base_y + 1.4, z}, {.62, 2.8, .62}, 0, {116, 83, 48, 255})
    crown := terrain.structure_make(x, z, 8.2, 6.8, base_y + 1.8, 7.2)
    crown.seed = seed + 71
    crown.color = {83, 108, 63, 255}
    // Architecture olives favor the two silvery families, distinguishing
    // orchard planting from the greener spontaneous canopy.
    olive_variation := seed % 2 == 0 ? 4 : 2
    world_foliage_lobe(crown, 0, 0, crown.width, crown.depth, crown.height, 0, false, olive_variation, -.18, true)
    _ = trunk
}

world_laundry_web_segment :: proc(a, b: third_person.Vec3, color: canvas2d.Color) {
    dx := b.x - a.x
    dy := b.y - a.y
    dz := b.z - a.z
    length := f32(math.sqrt(f64(dx * dx + dy * dy + dz * dz)))
    if length <= .05 do return
    horizontal_length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if horizontal_length <= .001 do return
    half_width: f32 = .025
    side_x, side_z := -dz / horizontal_length * half_width, dx / horizontal_length * half_width
    a_left, a_right :=
        third_person.Vec3{a.x - side_x, a.y, a.z - side_z}, third_person.Vec3{a.x + side_x, a.y, a.z + side_z}
    b_left, b_right :=
        third_person.Vec3{b.x - side_x, b.y, b.z - side_z}, third_person.Vec3{b.x + side_x, b.y, b.z + side_z}
    world_quad(a_left, b_left, b_right, a_right, color)
    world_quad(a_right, b_right, b_left, a_left, color)
    a_low, a_high := third_person.Vec3{a.x, a.y - half_width, a.z}, third_person.Vec3{a.x, a.y + half_width, a.z}
    b_low, b_high := third_person.Vec3{b.x, b.y - half_width, b.z}, third_person.Vec3{b.x, b.y + half_width, b.z}
    world_quad(a_low, b_low, b_high, a_high, color)
    world_quad(a_high, b_high, b_low, a_low, color)
}

world_laundry_span_blocked :: proc(
    structures: []terrain.Structure,
    first_index, second_index: int,
    start_x, start_z, finish_x, finish_z: f32,
) -> bool {
    dx, dz := finish_x - start_x, finish_z - start_z
    distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
    samples := max(2, int(math.ceil(f64(distance / 1.5))))
    for sample in 1 ..< samples {
        t := f32(sample) / f32(samples)
        point_x, point_z := start_x + dx * t, start_z + dz * t
        for blocker, blocker_index in structures {
            if blocker_index == first_index || blocker_index == second_index || blocker.kind != .Architecture do continue
            footprint := architecture.architecture_footprint(blocker)
            cosine, sine := f32(math.cos(f64(blocker.rotation))), f32(math.sin(f64(blocker.rotation)))
            for mass in footprint.masses[:footprint.count] {
                mass_x, mass_z := architecture.architecture_mass_world(blocker, mass)
                offset_x, offset_z := point_x - mass_x, point_z - mass_z
                local_x := offset_x * cosine + offset_z * sine
                local_z := -offset_x * sine + offset_z * cosine
                if math.abs(local_x) <= mass.width * .5 + .45 && math.abs(local_z) <= mass.depth * .5 + .45 {
                    return true
                }
            }
        }
    }
    return false
}

world_laundry_catenary_drop :: proc(t, sag: f32) -> f32 {
    // A normalized cosh curve: zero drop at both anchors and exactly `sag`
    // at midspan. A modest shape factor keeps the line natural rather than
    // sharply pinched beneath the center.
    shape: f64 = 1.55
    centered := f64(t * 2 - 1)
    normalized := (math.cosh(shape) - math.cosh(shape * centered)) / (math.cosh(shape) - 1)
    return sag * f32(normalized)
}

world_laundry_catenary_slope :: proc(t, sag, span_length: f32) -> f32 {
    if span_length <= .001 do return 0
    shape: f64 = 1.55
    centered := f64(t * 2 - 1)
    // y = anchor_y - drop(t), converted from dy/dt to dy per horizontal metre.
    derivative := 2 * shape * math.sinh(shape * centered) / (math.cosh(shape) - 1)
    return sag * f32(derivative) / span_length
}

world_laundry_cloth :: proc(
    top: third_person.Vec3,
    tangent_x, tangent_y, tangent_z, width, height, drift: f32,
    color: canvas2d.Color,
) {
    // Hang each item as a thin, slightly skewed panel instead of a solid box.
    // The skew and uneven hem keep the span from reading as a row of signs.
    wind_x, wind_z := -tangent_z, tangent_x
    top_left := third_person.Vec3 {
        top.x - tangent_x * width * .5,
        top.y - tangent_y * width * .5,
        top.z - tangent_z * width * .5,
    }
    top_right := third_person.Vec3 {
        top.x + tangent_x * width * .5,
        top.y + tangent_y * width * .5,
        top.z + tangent_z * width * .5,
    }
    bottom_left := third_person.Vec3 {
        top_left.x + tangent_x * width * .10 + wind_x * drift,
        top_left.y - height,
        top_left.z + tangent_z * width * .10 + wind_z * drift,
    }
    bottom_right := third_person.Vec3 {
        top_right.x - tangent_x * width * .10 + wind_x * drift * .55,
        top_right.y - height - .07,
        top_right.z - tangent_z * width * .10 + wind_z * drift * .55,
    }
    world_quad(top_left, bottom_left, bottom_right, top_right, color)
    world_quad(top_right, bottom_right, bottom_left, top_left, color)
}

world_architecture_laundry_webbing_uncached :: proc(editor: ^Editor) {
    if editor == nil do return
    webbing_count := 0
    webbing_limit := 8
    structures := editor.project.structures[:editor.project.structure_count]
    building_spans := world_renderer.structure_building_spans[:len(structures)]
    for &span in building_spans do span = 0
    cloth_colors := [4]canvas2d.Color {
        {235, 224, 188, 255},
        {112, 157, 171, 255},
        {191, 94, 72, 255},
        {205, 157, 177, 255},
    }
    for first, first_index in structures {
        if first.kind != .Architecture || first.height > 52 do continue
        if building_spans[first_index] >= 2 do continue
        first_facade := architecture.architecture_frontage_structure(first)
        first_front := [2]f32{-math.sin(first_facade.rotation), math.cos(first_facade.rotation)}
        for second_index in first_index + 1 ..< len(structures) {
            second := structures[second_index]
            if second.kind != .Architecture || second.height > 52 do continue
            if building_spans[first_index] >= 2 do break
            if building_spans[second_index] >= 2 do continue
            second_facade := architecture.architecture_frontage_structure(second)
            if webbing_count >= webbing_limit do return
            dx := second_facade.center_x - first_facade.center_x
            dz := second_facade.center_z - first_facade.center_z
            distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if distance < 14 || distance > 76 do continue
            direction_x, direction_z := dx / distance, dz / distance
            second_front := [2]f32{-math.sin(second_facade.rotation), math.cos(second_facade.rotation)}
            // Only span a line when the two selected façades face each other;
            // this keeps the webbing in alleys instead of through back walls.
            first_facing := first_front.x * direction_x + first_front.y * direction_z
            second_facing := second_front.x * -direction_x + second_front.y * -direction_z
            if first_facing < .05 || second_facing < .05 do continue
            first_side := direction_x * math.cos(first_facade.rotation) + direction_z * math.sin(first_facade.rotation)
            if math.abs(first_side) < .08 do first_side = first_facade.seed & 1 == 0 ? f32(-1) : f32(1)
            second_side :=
                -direction_x * math.cos(second_facade.rotation) - direction_z * math.sin(second_facade.rotation)
            if math.abs(second_side) < .08 do second_side = second_facade.seed & 1 == 0 ? f32(-1) : f32(1)
            first_x, first_z := world_rotate_xz(
                first_facade.center_x,
                first_facade.center_z,
                clamp(first_side, f32(-1), f32(1)) * first_facade.width * .30,
                first_facade.depth * .5 + .55,
                first_facade.rotation,
            )
            second_x, second_z := world_rotate_xz(
                second_facade.center_x,
                second_facade.center_z,
                clamp(second_side, f32(-1), f32(1)) * second_facade.width * .30,
                second_facade.depth * .5 + .55,
                second_facade.rotation,
            )
            if world_laundry_span_blocked(
                structures,
                first_index,
                second_index,
                first_x,
                first_z,
                second_x,
                second_z,
            ) {
                continue
            }
            line_y := min(
                first_facade.base_y +
                clamp(first_facade.height * (.34 + f32(first_facade.seed % 3) * .025), f32(7.5), f32(14)),
                second_facade.base_y +
                clamp(second_facade.height * (.34 + f32(second_facade.seed % 3) * .025), f32(7.5), f32(14)),
            )
            if line_y < editor.project.sea_level + 3 do continue
            crown_conflict := false
            for planted in structures {
                if planted.kind != .Architecture do continue
                growth := architecture.bougainvillea_density_at_structure(
                    &editor.project.climbing_leaf_density,
                    planted,
                    &editor.project,
                )
                if architecture.bougainvillea_laundry_span_conflict(
                    planted,
                    growth,
                    line_y,
                    first_x,
                    first_z,
                    second_x,
                    second_z,
                ) {
                    crown_conflict = true
                    break
                }
            }
            if crown_conflict do continue
            start := third_person.Vec3{first_x, line_y, first_z}
            finish := third_person.Vec3{second_x, line_y, second_z}
            catenary_sag := min(f32(1.35), distance * .040)
            catenary_segments := clamp(int(math.ceil(f64(distance / 3.0))), 8, 20)
            previous := start
            for segment in 1 ..= catenary_segments {
                t := f32(segment) / f32(catenary_segments)
                next := third_person.Vec3 {
                    start.x + (finish.x - start.x) * t,
                    line_y - world_laundry_catenary_drop(t, catenary_sag),
                    start.z + (finish.z - start.z) * t,
                }
                world_laundry_web_segment(previous, next, {66, 61, 56, 255})
                previous = next
            }
            span_dx, span_dz := finish.x - start.x, finish.z - start.z
            span_length := f32(math.sqrt(f64(span_dx * span_dx + span_dz * span_dz)))
            tangent_x, tangent_z := span_dx / span_length, span_dz / span_length
            cloth_count := 5 + int((first.seed + second.seed) % 3)
            for cloth in 0 ..< cloth_count {
                t := f32(cloth + 1) / f32(cloth_count + 1)
                cloth_x := start.x + (finish.x - start.x) * t
                cloth_z := start.z + (finish.z - start.z) * t
                cloth_y := line_y - world_laundry_catenary_drop(t, catenary_sag) - .05
                world_laundry_cloth(
                    {cloth_x, cloth_y, cloth_z},
                    tangent_x,
                    world_laundry_catenary_slope(t, catenary_sag, span_length),
                    tangent_z,
                    .82 + f32((cloth + int(second.seed)) % 3) * .15,
                    .62 + f32((cloth + int(first.seed)) % 3) * .14,
                    (f32(cloth % 2) - .5) * .12,
                    cloth_colors[(cloth + int(first.seed % 3)) % len(cloth_colors)],
                )
            }
            building_spans[first_index] += 1
            building_spans[second_index] += 1
            if (first.seed + second.seed) % 3 == 0 {
                // Abstract, low-detail resident silhouette: body, head, and
                // outstretched arms reaching the line. One endpoint per few
                // spans keeps the town inhabited without making mannequins a
                // repeated façade motif.
                worker_body := canvas2d.Color{74, 67, 61, 255}
                worker_shirt :=
                    (first.seed + second.seed) % 2 == 0 ? canvas2d.Color{132, 104, 79, 255} : canvas2d.Color{77, 109, 119, 255}
                world_box_rotated({start.x, line_y - .72, start.z}, {.32, .92, .24}, 0, worker_shirt)
                world_box_rotated({start.x, line_y - 1.25, start.z}, {.36, .36, .36}, 0, {91, 69, 53, 255})
                world_box_rotated(
                    {start.x, line_y - .68, start.z},
                    {.98, .11, .10},
                    math.atan2(finish.x - start.x, finish.z - start.z),
                    worker_body,
                )
            }
            webbing_count += 1
        }
    }
}

world_architecture_laundry_webbing :: proc(editor: ^Editor) {
    if editor == nil do return
    cache_valid :=
        world_renderer.laundry_geometry_valid &&
        world_renderer.laundry_geometry_revision == editor.project.revision &&
        world_renderer.laundry_geometry_terrain_revision == editor.terrain_revision
    if cache_valid {
        append(&world_renderer.vertices, ..world_renderer.laundry_geometry_cache[:])
        return
    }

    first := len(world_renderer.vertices)
    world_architecture_laundry_webbing_uncached(editor)
    clear(&world_renderer.laundry_geometry_cache)
    if first < len(world_renderer.vertices) {
        append(&world_renderer.laundry_geometry_cache, ..world_renderer.vertices[first:])
    }
    world_renderer.laundry_geometry_revision = editor.project.revision
    world_renderer.laundry_geometry_terrain_revision = editor.terrain_revision
    world_renderer.laundry_geometry_valid = true
}

world_architecture_grass_footprints :: proc(
    editor: ^Editor,
    allocator := context.temp_allocator,
) -> [dynamic]Architecture_Grass_Footprint {
    footprints := make([dynamic]Architecture_Grass_Footprint, allocator)
    if editor == nil do return footprints
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.height > 60 do continue
        footprint := architecture.architecture_footprint(structure)
        for mass in footprint.masses[:footprint.count] {
            center_x, center_z := architecture.architecture_mass_world(structure, mass)
            append(
                &footprints,
                Architecture_Grass_Footprint {
                    center_x = center_x,
                    center_z = center_z,
                    half_width = mass.width * .5,
                    half_depth = mass.depth * .5,
                    rotation = structure.rotation,
                },
            )
        }
    }
    // The airport terminals are procedural landmarks rather than authored
    // Architecture structures, so register their halls and forecourts.
    airport_positions := [2]third_person.Vec3{editor.attendant_position, editor.gerta_position}
    for airport in airport_positions {
        append(
            &footprints,
            Architecture_Grass_Footprint{center_x = airport.x, center_z = airport.z, half_width = 20, half_depth = 15},
            Architecture_Grass_Footprint{center_x = airport.x, center_z = airport.z, half_width = 8, half_depth = 22},
        )
    }
    for structure in editor.project.structures[:editor.project.structure_count] {
        if !airport_structure_is_stamp(structure) do continue
        append(
            &footprints,
            Architecture_Grass_Footprint {
                center_x = structure.center_x,
                center_z = structure.center_z,
                half_width = 20,
                half_depth = 15,
                rotation = structure.rotation,
            },
            Architecture_Grass_Footprint {
                center_x = structure.center_x,
                center_z = structure.center_z,
                half_width = 8,
                half_depth = 22,
                rotation = structure.rotation,
            },
        )
    }
    return footprints
}

world_architecture_grass_height_scale :: proc(footprints: []Architecture_Grass_Footprint, x, z: f32) -> f32 {
    scale := f32(1)
    for footprint in footprints {
        dx, dz := x - footprint.center_x, z - footprint.center_z
        cosine, sine := math.cos(footprint.rotation), math.sin(footprint.rotation)
        local_x := math.abs(dx * cosine + dz * sine)
        local_z := math.abs(-dx * sine + dz * cosine)
        outside_x := max(local_x - footprint.half_width, f32(0))
        outside_z := max(local_z - footprint.half_depth, f32(0))
        if outside_x == 0 && outside_z == 0 do return 0
        distance := f32(math.sqrt(f64(outside_x * outside_x + outside_z * outside_z)))
        // Read as intentionally maintained grass beside homes, blending back
        // to the wild field beyond the immediate building edge.
        proximity := clamp(distance / 12, f32(0), f32(1))
        proximity = proximity * proximity * (3 - 2 * proximity)
        scale = min(scale, .25 + proximity * .75)
    }
    return scale
}

world_architecture_municipal_lamp_fixture :: proc(editor: ^Editor, center_x, center_z, rotation: f32) {
    base_y := terrain.sample_surface_height(&editor.project, 0, center_x, center_z)
    metal := canvas2d.Color{82, 91, 87, 255}
    world_box_rotated({center_x, base_y + .14, center_z}, {.46, .28, .46}, rotation, {91, 91, 79, 255})
    world_metal_box_rotated({center_x, base_y + 2.25, center_z}, {.13, 4.35, .13}, rotation, metal)

    arm_x, arm_z := world_rotate_xz(center_x, center_z, 0, .34, rotation)
    world_metal_box_rotated({arm_x, base_y + 4.33, arm_z}, {.13, .13, .78}, rotation, metal)
    fixture_x, fixture_z := world_rotate_xz(center_x, center_z, 0, .72, rotation)
    world_metal_box_rotated({fixture_x, base_y + 4.16, fixture_z}, {.40, .14, .34}, rotation, metal)
    world_emissive_fixture_box(
        {fixture_x, base_y + 4.065, fixture_z},
        {.30, .06, .26},
        rotation,
        {255, 210, 140, 255},
        2,
    )
}

world_architecture_municipal_lamp_effects :: proc(
    editor: ^Editor,
    center_x, center_z, rotation: f32,
    roadway: bool = true,
) {
    base_y := terrain.sample_surface_height(&editor.project, 0, center_x, center_z)
    if !world_sphere_in_view(editor, {center_x, base_y + 2.2, center_z}, 8.75, .5) do return
    fixture_x, fixture_z := world_rotate_xz(center_x, center_z, 0, .72, rotation)
    world_billboard_material_uv(
        editor,
        {fixture_x, base_y + 4.04, fixture_z},
        .70,
        .70,
        {255, 220, 160, 34},
        .Emissive_Halo,
        true,
    )

    // Cantilever roadway optics distribute light along the street, while
    // plaza arms face inward and throw their long axis toward the square.
    // A broader, lower-alpha footprint bridges municipal coverage without
    // turning each pool into a bright isolated spot. Geometry and draw-call
    // cost remain unchanged.
    pool_radius_x := roadway ? f32(6.40) : f32(3.35)
    pool_radius_z := roadway ? f32(3.35) : f32(5.20)
    // The post sits at the circulation edge and its cantilever points along
    // local +Z. Place the optical footprint farther along that aimed throw,
    // rather than centering most of it beneath and behind the curbside head.
    pool_throw := roadway ? f32(2.0) : f32(1.65)
    pool_x, pool_z := world_rotate_xz(center_x, center_z, 0, pool_throw, rotation)
    world_municipal_light_pool(
        pool_x,
        base_y,
        pool_z,
        &editor.project,
        .20,
        pool_radius_x,
        pool_radius_z,
        rotation,
        56,
        1,
        surface_editor = editor,
        late_submit = true,
    )
}

world_architecture_municipal_lamp :: proc(editor: ^Editor, center_x, center_z, rotation: f32, roadway: bool = true) {
    base_y := terrain.sample_surface_height(&editor.project, 0, center_x, center_z)
    if !world_sphere_in_view(editor, {center_x, base_y + 2.2, center_z}, 8.75, .5) do return
    world_architecture_municipal_lamp_fixture(editor, center_x, center_z, rotation)
    world_architecture_municipal_lamp_effects(editor, center_x, center_z, rotation, roadway)
}
