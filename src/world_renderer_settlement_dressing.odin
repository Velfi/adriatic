package main
import "core:math"

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import dio "zelda_engine:dio"
import third_person "zelda_engine:third_person"

world_settlement_town_building_skirts :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_settlement_town_building_skirts")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil || !editor.settlement_plan.valid do return
    if editor.settlement_plan.request.scale != .Town do return
    stone := canvas2d.Color{150, 146, 132, 255}
    strip := f32(.58)
    for site in editor.settlement_plan.sites[:editor.settlement_plan.site_count] {
        if !site.accepted || (site.kind != .Ordinary && site.kind != .Landmark) do continue
        footprint := architecture.architecture_footprint(site.structure)
        for mass in footprint.masses[:footprint.count] {
            center_x, center_z := architecture.architecture_mass_world(site.structure, mass)
            half_width := mass.width * .5
            half_depth := mass.depth * .5
            for side in -1 ..= 1 {
                if side == 0 do continue
                x, z := world_rotate_xz(
                    center_x,
                    center_z,
                    0,
                    f32(side) * (half_depth + strip * .5 - .06),
                    site.structure.rotation,
                )
                front_length := mass.width + strip * 2
                if world_settlement_town_skirt_supported(
                    editor,
                    x,
                    z,
                    front_length,
                    site.structure.rotation,
                    site.structure.base_y,
                ) {
                    world_land_surface_rotated(editor, x, z, front_length, strip, site.structure.rotation, .125, stone)
                }
                x, z = world_rotate_xz(
                    center_x,
                    center_z,
                    f32(side) * (half_width + strip * .5 - .06),
                    0,
                    site.structure.rotation,
                )
                side_rotation := site.structure.rotation + math.PI * .5
                if world_settlement_town_skirt_supported(
                    editor,
                    x,
                    z,
                    mass.depth,
                    side_rotation,
                    site.structure.base_y,
                ) {
                    world_land_surface_rotated(editor, x, z, mass.depth, strip, side_rotation, .125, stone)
                }
            }
        }
    }
}

world_settlement_town_civic_forecourts :: proc(editor: ^Editor, plan: ^architecture.City_Plan) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_settlement_town_civic_forecourts")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil || plan == nil || !editor.settlement_plan.valid do return
    if editor.settlement_plan.request.scale != .Town do return
    stone := canvas2d.Color{150, 146, 132, 255}
    for structure in plan.structures[:plan.count] {
        identity := architecture.architecture_resolve_legacy_identity(structure)
        if identity.archetype != .Post_Office && identity.archetype != .Clinic do continue
        outward := settlement_structure_entrance_outward(structure)
        tangent := [2]f32{outward[1], -outward[0]}
        threshold := settlement_structure_front_door_point(structure)
        depth := f32(3.4)
        width := clamp(
            (structure.entrance_side == .Front || structure.entrance_side == .Rear ? structure.width : structure.depth) *
            .64,
            f32(4.2),
            f32(7.2),
        )
        center: [2]f32
        supported := false
        // Start with a small public forecourt, then contract it into a door
        // landing when the hillside cannot support the full rectangle. This
        // preserves a civic threshold without draping paving down a bank.
        for attempt in 0 ..< 8 {
            center = threshold + outward * (depth * .5 - .10)
            corners := [4][2]f32 {
                center - tangent * width * .5 - outward * depth * .5,
                center + tangent * width * .5 - outward * depth * .5,
                center + tangent * width * .5 + outward * depth * .5,
                center - tangent * width * .5 + outward * depth * .5,
            }
            low, high := f32(1e30), f32(-1e30)
            for corner in corners {
                height := terrain.sample_surface_height(&editor.project, 0, corner[0], corner[1])
                low, high = min(low, height), max(high, height)
            }
            if high - low <= .38 {
                supported = true
                break
            }
            if attempt % 2 == 0 {
                depth = max(depth * .72, f32(1.25))
            } else {
                width = max(width * .82, f32(2.8))
            }
        }
        if !supported do continue
        yaw := f32(math.atan2(f64(tangent[1]), f64(tangent[0])))
        world_land_surface_rotated(editor, center[0], center[1], width, depth, yaw, .13, stone)
    }
}

world_architecture_lamps :: proc(editor: ^Editor, plan: ^architecture.City_Plan) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_architecture_lamps")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil || plan == nil do return
    for lamp in plan.lamps[:plan.lamp_count] {
        base_y := terrain.sample_surface_height(&editor.project, 0, lamp.x, lamp.z)
        // Include the complete 6.1 m ground pool in the bound, not only the
        // post and lantern. Otherwise the soft edge can disappear while still
        // visibly inside the screen.
        if !world_sphere_in_view(editor, {lamp.x, base_y + 2, lamp.z}, 6.45, .5) do continue
        // Blue-green painted iron stays subdued without lunar fill, but has
        // enough authored value for full-moon ambient to describe the post
        // and lantern cage instead of leaving the same black silhouette.
        metal := canvas2d.Color{82, 91, 87, 255}
        glass := canvas2d.Color{246, 211, 146, 255}
        camera_position := editor.camera_pose.position
        camera_dx, camera_dz := lamp.x - camera_position.x, lamp.z - camera_position.z
        far_fixture := camera_dx * camera_dx + camera_dz * camera_dz > 55 * 55
        if far_fixture {
            // Beyond this distance the base, cage frame, and cap are all
            // sub-pixel, but their boxes still cost 108 submitted vertices.
            // Preserve the silhouette, warm source, halo, and complete pool;
            // the compact emissive box naturally collapses into the same point
            // read without a rectangular source billboard.
            world_box_rotated({lamp.x, base_y + 1.94, lamp.z}, {.14, 3.88, .14}, lamp.yaw, metal)
            world_box_rotated_material({lamp.x, base_y + 3.62, lamp.z}, {.30, .30, .30}, lamp.yaw, glass, .Emissive)
            world_billboard_material_uv(
                editor,
                {lamp.x, base_y + 3.62, lamp.z},
                .74,
                .74,
                {255, 220, 160, 36},
                .Emissive_Halo,
                true,
            )
            world_municipal_light_pool(
                lamp.x,
                base_y,
                lamp.z,
                &editor.project,
                .20,
                6.1,
                6.1,
                0,
                50,
                surface_editor = editor,
                late_submit = true,
            )
            continue
        }
        world_box_rotated({lamp.x, base_y + .10, lamp.z}, {.48, .20, .48}, lamp.yaw, metal)
        world_box_rotated({lamp.x, base_y + 1.70, lamp.z}, {.14, 3.20, .14}, lamp.yaw, metal)
        world_box_rotated({lamp.x, base_y + 3.36, lamp.z}, {.58, .14, .58}, lamp.yaw, metal)
        world_emissive_fixture_box({lamp.x, base_y + 3.62, lamp.z}, {.42, .42, .42}, lamp.yaw, glass, 1)
        world_billboard_material_uv(
            editor,
            {lamp.x, base_y + 3.62, lamp.z},
            .74,
            .74,
            {255, 220, 160, 36},
            .Emissive_Halo,
            true,
        )
        world_box_rotated({lamp.x, base_y + 3.87, lamp.z}, {.54, .10, .54}, lamp.yaw, metal)
        // Post-top luminaires spread a broad, low-contrast symmetric pool.
        // The wider footprint bridges route spacing without adding geometry;
        // reduced opacity prevents overlapping pools from flattening the road.
        world_municipal_light_pool(
            lamp.x,
            base_y,
            lamp.z,
            &editor.project,
            .20,
            6.1,
            6.1,
            0,
            50,
            surface_editor = editor,
            late_submit = true,
        )
    }
}

world_structure_frame :: proc(structure: terrain.Structure, y: f32, color: canvas2d.Color) {
    thickness := max(f32(.08), min(structure.width, structure.depth) * .035)
    left_x, left_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .5 + thickness * .5,
        0,
        structure.rotation,
    )
    right_x, right_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .5 - thickness * .5,
        0,
        structure.rotation,
    )
    back_x, back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        -structure.depth * .5 + thickness * .5,
        structure.rotation,
    )
    front_x, front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        structure.depth * .5 - thickness * .5,
        structure.rotation,
    )
    world_box_rotated(
        {left_x, y + thickness * .5, left_z},
        {thickness, thickness, structure.depth + thickness * 2},
        structure.rotation,
        color,
    )
    world_box_rotated(
        {right_x, y + thickness * .5, right_z},
        {thickness, thickness, structure.depth + thickness * 2},
        structure.rotation,
        color,
    )
    world_box_rotated(
        {back_x, y + thickness * .5, back_z},
        {structure.width, thickness, thickness},
        structure.rotation,
        color,
    )
    world_box_rotated(
        {front_x, y + thickness * .5, front_z},
        {structure.width, thickness, thickness},
        structure.rotation,
        color,
    )
}

world_radial_formation :: proc(
    structure: terrain.Structure,
    radii: [4]f32,
    heights: [4]f32,
    z_scale, cap_height: f32,
    lod: Structure_LOD = .Near,
) {
    // Twelve sides keep cypress crowns and other radial formations from
    // resolving as hard triangular prisms in eye-level architectural views.
    segments := lod == .Near ? 12 : lod == .Medium ? 8 : 5
    layer_count := lod == .Near ? 4 : lod == .Medium ? 3 : 2
    color := canvas2d.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    vertices: [4][12]third_person.Vec3
    normals: [4][12]third_person.Vec3
    colors: [4][12]canvas2d.Color
    sampled_radii: [4]f32
    sampled_heights: [4]f32
    for layer in 0 ..< layer_count {
        profile_position := f32(layer) * 3 / f32(max(layer_count - 1, 1))
        lower := clamp(int(profile_position), 0, 3)
        upper := min(lower + 1, 3)
        fraction := profile_position - f32(lower)
        sampled_radii[layer] = radii[lower] + (radii[upper] - radii[lower]) * fraction
        sampled_heights[layer] = heights[lower] + (heights[upper] - heights[lower]) * fraction
    }
    color_phase := f32(structure.seed & 0xffff) / 65535 * math.TAU
    for layer in 0 ..< layer_count {
        for segment in 0 ..< segments {
            angle := f32(segment) * math.PI * 2 / f32(segments)
            jitter := 1 + f32(math.sin(f64(f32(structure.seed) * .001 + f32(segment) * 2.17 + f32(layer) * .71))) * .11
            local_x := math.cos(angle) * structure.width * .5 * sampled_radii[layer] * jitter
            local_z := math.sin(angle) * structure.depth * .5 * sampled_radii[layer] * z_scale * jitter
            world_x, world_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            vertices[layer][segment] = {world_x, structure.base_y + structure.height * sampled_heights[layer], world_z}
            previous_layer := max(layer - 1, 0)
            next_layer := min(layer + 1, layer_count - 1)
            height_delta := max(sampled_heights[next_layer] - sampled_heights[previous_layer], f32(.001))
            radius_delta := sampled_radii[next_layer] - sampled_radii[previous_layer]
            average_radius := (structure.width + structure.depth * z_scale) * .25
            slope := radius_delta * average_radius / max(height_delta * structure.height, f32(.001))
            local_normal := linalg.normalize0(
                [3]f32{math.cos(angle), clamp(-slope, f32(.04), f32(2.5)), math.sin(angle) / max(z_scale, f32(.05))},
            )
            normal_x, normal_z := world_rotate_xz(0, 0, local_normal.x, local_normal.z, structure.rotation)
            normals[layer][segment] = {normal_x, local_normal.y, normal_z}
            // Low-frequency color waves wrap continuously around the shared
            // profile vertices. Warm mineral staining, cool grey variation,
            // and a slight sun-bleached crest remain smooth across triangles.
            warm := math.sin(angle + color_phase) * .5 + math.sin(angle * 2 - color_phase * .7) * .22
            cool := math.cos(angle * 1.0 - color_phase * 1.3) * .38
            height_lift := f32(layer) / f32(max(layer_count - 1, 1)) * 5
            brightness := math.sin(angle * 2 + color_phase * .4) * 4 + height_lift
            colors[layer][segment] = {
                r = u8(clamp(f32(color.r) + brightness + warm * 11, 0, 255)),
                g = u8(clamp(f32(color.g) + brightness + warm * 5 + cool * 2, 0, 255)),
                b = u8(clamp(f32(color.b) + brightness - warm * 5 + cool * 9, 0, 255)),
                a = color.a,
            }
        }
    }
    for layer in 0 ..< layer_count - 1 {
        for segment in 0 ..< segments {
            next := (segment + 1) % segments
            world_triangle_smooth_lit(
                vertices[layer][segment],
                vertices[layer + 1][segment],
                vertices[layer + 1][next],
                normals[layer][segment],
                normals[layer + 1][segment],
                normals[layer + 1][next],
                colors[layer][segment],
                colors[layer + 1][segment],
                colors[layer + 1][next],
                .94,
            )
            world_triangle_smooth_lit(
                vertices[layer][segment],
                vertices[layer + 1][next],
                vertices[layer][next],
                normals[layer][segment],
                normals[layer + 1][next],
                normals[layer][next],
                colors[layer][segment],
                colors[layer + 1][next],
                colors[layer][next],
                .94,
            )
        }
    }
    top := third_person.Vec3{structure.center_x, structure.base_y + structure.height * cap_height, structure.center_z}
    for segment in 0 ..< segments {
        next := (segment + 1) % segments
        world_triangle_smooth_lit(
            vertices[layer_count - 1][segment],
            top,
            vertices[layer_count - 1][next],
            normals[layer_count - 1][segment],
            {0, 1, 0},
            normals[layer_count - 1][next],
            colors[layer_count - 1][segment],
            {
                r = u8(clamp(f32(color.r) + 7, 0, 255)),
                g = u8(clamp(f32(color.g) + 6, 0, 255)),
                b = u8(clamp(f32(color.b) + 4, 0, 255)),
                a = color.a,
            },
            colors[layer_count - 1][next],
            .94,
        )
    }
}

SMALL_ROCK_VARIATION_COUNT :: 8
SMALL_ROCK_CANDIDATE_COUNT :: 100
SMALL_ROCK_SIDE_CAPACITY :: 8

Small_Rock_Template :: struct {
    side_count:                       int,
    footprint_x, footprint_z:         f32,
    height_scale:                     f32,
    bottom_radius:                    [SMALL_ROCK_SIDE_CAPACITY]f32,
    shoulder_radius, shoulder_height: [SMALL_ROCK_SIDE_CAPACITY]f32,
    cap_mode:                         int,
    cap_scale, cap_height:            f32,
    cap_offset_x, cap_offset_z:       f32,
    ridge_angle, ridge_length:        f32,
    interest:                         f32,
}

small_rock_templates: [SMALL_ROCK_VARIATION_COUNT]Small_Rock_Template
small_rock_templates_ready: bool

small_rock_template_random :: proc(input: u32) -> f32 {
    value := input
    value = (value ~ (value >> 16)) * 0x7feb352d
    value = (value ~ (value >> 15)) * 0x846ca68b
    value = value ~ (value >> 16)
    return f32(value & 0x00ff_ffff) / f32(0x0100_0000)
}

small_rock_template_distance :: proc(a, b: ^Small_Rock_Template) -> f32 {
    if a == nil || b == nil do return 0
    distance := abs(a.footprint_x - b.footprint_x) + abs(a.footprint_z - b.footprint_z)
    distance += abs(a.height_scale - b.height_scale) * .8
    distance += a.cap_mode != b.cap_mode ? f32(.9) : f32(0)
    distance += f32(abs(a.side_count - b.side_count)) * .12
    sample_count := min(a.side_count, b.side_count)
    for side in 0 ..< sample_count {
        distance += abs(a.bottom_radius[side] - b.bottom_radius[side]) * .12
        distance += abs(a.shoulder_height[side] - b.shoulder_height[side]) * .10
    }
    return distance
}

@(no_instrumentation)
world_small_rock_templates_init :: proc() {
    if small_rock_templates_ready do return
    candidates: [SMALL_ROCK_CANDIDATE_COUNT]Small_Rock_Template
    for candidate_index in 0 ..< SMALL_ROCK_CANDIDATE_COUNT {
        candidate := &candidates[candidate_index]
        seed := u32(candidate_index + 1) * 0x9e3779b9
        candidate.side_count = 5 + int(seed % 4)
        candidate.footprint_x = .82 + small_rock_template_random(seed ~ 0x68bc21eb) * .34
        candidate.footprint_z = .72 + small_rock_template_random(seed ~ 0x02e5be93) * .48
        candidate.height_scale = .48 + small_rock_template_random(seed ~ 0x967a889b) * .46
        candidate.cap_mode = int((seed >> 7) % 4)
        candidate.cap_scale = .28 + small_rock_template_random(seed ~ 0x4f1bbcdc) * .44
        candidate.cap_height = .66 + small_rock_template_random(seed ~ 0xb5297a4d) * .28
        candidate.cap_offset_x = (small_rock_template_random(seed ~ 0x1b56c4e9) * 2 - 1) * .18
        candidate.cap_offset_z = (small_rock_template_random(seed ~ 0xc2b2ae35) * 2 - 1) * .18
        candidate.ridge_angle = small_rock_template_random(seed ~ 0x27d4eb2f) * math.TAU
        candidate.ridge_length = .20 + small_rock_template_random(seed ~ 0x165667b1) * .42
        radius_min, radius_max := f32(2), f32(-2)
        height_min, height_max := f32(2), f32(-2)
        for side in 0 ..< candidate.side_count {
            side_seed := seed ~ u32(side + 1) * 0x85ebca6b
            radius := .78 + small_rock_template_random(side_seed) * .43
            shoulder := .56 + small_rock_template_random(side_seed ~ 0x9e3779b9) * .35
            height := .50 + small_rock_template_random(side_seed ~ 0x7f4a7c15) * .31
            candidate.bottom_radius[side] = radius
            candidate.shoulder_radius[side] = shoulder
            candidate.shoulder_height[side] = height
            radius_min, radius_max = min(radius_min, radius), max(radius_max, radius)
            height_min, height_max = min(height_min, height), max(height_max, height)
        }
        asymmetry := radius_max - radius_min + height_max - height_min
        silhouette := abs(candidate.footprint_x - candidate.footprint_z)
        crown_interest :=
            candidate.cap_mode == 0 ? f32(.15) : candidate.cap_mode == 1 ? f32(.75) : candidate.cap_mode == 2 ? f32(.95) : f32(.60)
        squat_bonus := 1 - abs(candidate.height_scale - .68)
        candidate.interest = asymmetry * 1.8 + silhouette * .7 + crown_interest + squat_bonus * .35
    }

    selected: [SMALL_ROCK_CANDIDATE_COUNT]bool
    for variation in 0 ..< SMALL_ROCK_VARIATION_COUNT {
        best_index := -1
        best_score := f32(-1)
        for candidate_index in 0 ..< SMALL_ROCK_CANDIDATE_COUNT {
            if selected[candidate_index] do continue
            candidate := &candidates[candidate_index]
            diversity := f32(1)
            if variation > 0 {
                diversity = f32(100)
                for previous in 0 ..< variation {
                    diversity = min(
                        diversity,
                        small_rock_template_distance(candidate, &small_rock_templates[previous]),
                    )
                }
            }
            score := candidate.interest + min(diversity, f32(2)) * .72
            if score > best_score {
                best_score = score
                best_index = candidate_index
            }
        }
        if best_index >= 0 {
            selected[best_index] = true
            small_rock_templates[variation] = candidates[best_index]
        }
    }
    small_rock_templates_ready = true
}
