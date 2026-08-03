package main
import "core:math"

import architecture "../packages/architecture"
import dio "../packages/dio"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_story_resident_home_pose_uncached :: proc(
    editor: ^Editor,
    resident: story.Resident,
) -> (
    position: third_person.Vec3,
    rotation: f32,
    ok: bool,
) {
    if editor == nil do return {}, 0, false
    if resident == .Zora {
        half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
        island_signs := terrain.DEFAULT_ISLAND_SIGNS
        island_center := island_signs[1] * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        island_radius := half_extent * terrain.DEFAULT_ISLAND_RADIUS
        best_structure_index := -1
        best_post_office_distance := -f32(1)
        structures := editor.project.structures[:editor.project.structure_count]
        for structure, structure_index in structures {
            identity := architecture.architecture_resolve_legacy_identity(structure)
            storefront := identity.archetype == .Shop_House || identity.archetype == .Mixed_Use_Dwelling
            if structure.kind != .Architecture || structure.height > 60 || !storefront do continue
            island_dx, island_dz := structure.center_x - island_center, structure.center_z - island_center
            if island_dx * island_dx + island_dz * island_dz > island_radius * island_radius do continue
            nearest_post_office_distance := f32(1e30)
            for office in structures {
                office_identity := architecture.architecture_resolve_legacy_identity(office)
                if office.kind != .Architecture || office_identity.archetype != .Post_Office do continue
                office_dx, office_dz := structure.center_x - office.center_x, structure.center_z - office.center_z
                nearest_post_office_distance = min(
                    nearest_post_office_distance,
                    office_dx * office_dx + office_dz * office_dz,
                )
            }
            if nearest_post_office_distance > best_post_office_distance {
                best_post_office_distance = nearest_post_office_distance
                best_structure_index = structure_index
            }
        }
        if best_structure_index < 0 do return {}, 0, false
        frontage := architecture.architecture_frontage_structure(structures[best_structure_index])
        x, z := world_rotate_xz(
            frontage.center_x,
            frontage.center_z,
            1.4,
            frontage.depth * .5 + 2.6,
            frontage.rotation,
        )
        ground_y := terrain.sample_surface_height(&editor.project, 0, x, z)
        if ground_y <= editor.project.sea_level + .35 do return {}, 0, false
        return {x, ground_y, z}, frontage.rotation, true
    }
    if resident == .Toma || resident == .Lena {
        target_island := resident == .Toma ? 0 : 1
        half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
        island_signs := terrain.DEFAULT_ISLAND_SIGNS
        island_center := island_signs[target_island] * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        island_radius := half_extent * terrain.DEFAULT_ISLAND_RADIUS
        for structure in editor.project.structures[:editor.project.structure_count] {
            identity := architecture.architecture_resolve_legacy_identity(structure)
            if structure.kind != .Architecture || identity.archetype != .Post_Office do continue
            dx, dz := structure.center_x - island_center, structure.center_z - island_center
            if dx * dx + dz * dz > island_radius * island_radius do continue
            frontage := architecture.architecture_frontage_structure(structure)
            lateral := resident == .Toma ? f32(-1.1) : f32(1.1)
            x, z := world_rotate_xz(
                frontage.center_x,
                frontage.center_z,
                lateral,
                frontage.depth * .5 + 2.3,
                frontage.rotation,
            )
            ground_y := terrain.sample_surface_height(&editor.project, 0, x, z)
            if ground_y <= editor.project.sea_level + .35 do continue
            return {x, ground_y, z}, frontage.rotation, true
        }
        return {}, 0, false
    }
    island_index, resident_index, mapped := story_resident_town_slot(resident)
    if !mapped do return {}, 0, false
    structures := editor.project.structures[:editor.project.structure_count]
    world_structure_storage_ensure(len(structures))
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    island_signs := terrain.DEFAULT_ISLAND_SIGNS
    island_center := island_signs[island_index] * half_extent * terrain.DEFAULT_ISLAND_OFFSET
    island_radius := half_extent * terrain.DEFAULT_ISLAND_RADIUS
    clear(&world_renderer.structure_candidates)
    for structure, structure_index in structures {
        if structure.kind != .Architecture || structure.height > 60 do continue
        dx, dz := structure.center_x - island_center, structure.center_z - island_center
        if dx * dx + dz * dz > island_radius * island_radius do continue
        append(&world_renderer.structure_candidates, structure_index)
    }
    candidates := world_renderer.structure_candidates[:]
    candidate_count := len(candidates)
    if candidate_count == 0 do return {}, 0, false

    lateral := [7]f32{-1.0, .8, -1.3, 1.1, -.7, 1.4, -.9}
    outward := [7]f32{2.5, 2.2, 2.7, 2.4, 2.2, 2.6, 2.3}
    for attempt in 0 ..< candidate_count {
        candidate_index := candidates[(resident_index + attempt) % candidate_count]
        frontage := architecture.architecture_frontage_structure(structures[candidate_index])
        doorway_row := resident_index / candidate_count
        x, z, _ := world_town_mouse_frontage_pose(
            frontage,
            &editor.project,
            lateral[resident_index],
            max(outward[resident_index] - 1.8, f32(.4)) + f32(doorway_row) * 1.25,
        )
        ground_y := terrain.sample_surface_height(&editor.project, 0, x, z)
        if ground_y <= editor.project.sea_level + .35 do continue
        return {x, ground_y, z}, frontage.rotation, true
    }
    return {}, 0, false
}

world_story_resident_home_pose :: proc(
    editor: ^Editor,
    resident: story.Resident,
) -> (
    position: third_person.Vec3,
    rotation: f32,
    ok: bool,
) {
    if editor == nil do return {}, 0, false
    if !world_renderer.resident_home_cache_valid ||
       world_renderer.resident_home_project_revision != editor.project.revision ||
       world_renderer.resident_home_terrain_revision != editor.terrain_revision {
        world_renderer.resident_home_cache = {}
        world_renderer.resident_home_project_revision = editor.project.revision
        world_renderer.resident_home_terrain_revision = editor.terrain_revision
        world_renderer.resident_home_cache_valid = true
    }
    entry := &world_renderer.resident_home_cache[resident]
    if !entry.valid {
        entry.position, entry.rotation, entry.found = world_story_resident_home_pose_uncached(editor, resident)
        entry.valid = true
    }
    return entry.position, entry.rotation, entry.found
}

world_story_meeting_pose :: proc(editor: ^Editor) -> (niko, iva, center: third_person.Vec3, rotation: f32, ok: bool) {
    home, frontage_rotation, found := world_story_resident_home_pose(editor, .Niko)
    if !found do return {}, {}, {}, 0, false
    // The procedural resident point sits just beyond the doorway. Spread the
    // pair along the façade and lift the awning center slightly toward it.
    side_x, side_z := math.cos(frontage_rotation), math.sin(frontage_rotation)
    out_x, out_z := -math.sin(frontage_rotation), math.cos(frontage_rotation)
    center = {home.x - out_x * .28, 0, home.z - out_z * .28}
    center.y = terrain.sample_surface_height(&editor.project, 0, center.x, center.z)
    niko = {center.x - side_x * .62, 0, center.z - side_z * .62}
    iva = {center.x + side_x * .62, 0, center.z + side_z * .62}
    niko.y = terrain.sample_surface_height(&editor.project, 0, niko.x, niko.z)
    iva.y = terrain.sample_surface_height(&editor.project, 0, iva.x, iva.z)
    return niko, iva, center, frontage_rotation, true
}

world_story_resident_position :: proc(
    editor: ^Editor,
    resident: story.Resident,
) -> (
    position: third_person.Vec3,
    ok: bool,
) {
    if editor != nil && editor.story_state.romance == .Meeting && (resident == .Niko || resident == .Iva) {
        niko, iva, _, _, found := world_story_meeting_pose(editor)
        if !found do return {}, false
        return resident == .Niko ? niko : iva, true
    }
    home_position, _, found := world_story_resident_home_pose(editor, resident)
    return home_position, found
}

world_settlement_inhabitants :: proc(editor: ^Editor, include_animated := true, include_static := true) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "settlement_inhabitants")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil || editor.settlement_plan.inhabitant_count <= 0 do return
    animated := 0
    elapsed := f32(canvas2d.GetTime())
    camera := [2]f32{editor.camera_pose.position.x, editor.camera_pose.position.z}
    for inhabitant, inhabitant_index in editor.settlement_plan.inhabitants[:editor.settlement_plan.inhabitant_count] {
        if inhabitant.home_activity < 0 || inhabitant.home_activity >= editor.settlement_plan.activity_point_count {
            continue
        }
        home := editor.settlement_plan.activity_points[inhabitant.home_activity].position
        point := home
        tangent := [2]f32{0, 1}
        distance_to_camera := linalg.length(home - camera)
        if include_animated && distance_to_camera <= 135 && animated < 24 && editor.architecture_city_plan.alley_count > 0 {
            alley_index := int(inhabitant.seed % u32(editor.architecture_city_plan.alley_count))
            alley := editor.architecture_city_plan.alleys[alley_index]
            start := [2]f32{alley.start_x, alley.start_z}
            finish := [2]f32{alley.end_x, alley.end_z}
            phase := elapsed * (.055 + f32((inhabitant.seed >> 8) & 15) * .0025) + f32(inhabitant.seed & 255) / 255
            amount := .5 - .5 * f32(math.cos(f64(phase * 2 * math.PI)))
            point = start * (1 - amount) + finish * amount
            tangent = finish - start
            if f32(math.sin(f64(phase * 2 * math.PI))) < 0 do tangent = -tangent
            ground := terrain.sample_surface_height(&editor.project, 0, point[0], point[1])
            if ground <= editor.project.sea_level + .35 do continue
            if !world_sphere_in_view(editor, {point[0], ground + .8, point[1]}, 1.4, 2) do continue
            world_mouse_model_scaled(
                editor,
                {
                    position = {point[0], ground, point[1]},
                    rotation = math.PI - math.atan2(tangent[0], tangent[1]),
                    build = .82 + f32((inhabitant.seed >> 12) & 15) / 50,
                    snout_length = .9 + f32((inhabitant.seed >> 16) & 15) / 35,
                    fur = Mouse_Fur((inhabitant.seed >> 20) % 6),
                    pattern = Mouse_Fur_Pattern((inhabitant.seed >> 24) % 6),
                    grounded = true,
                },
                .82,
            )
            animated += 1
            continue
        }
        if !include_static do continue
        if !world_renderer.retained_patio_rebuilding && distance_to_camera > 420 do continue
        // Mid/far inhabitants use a tiny batched silhouette instead of a full
        // articulated mouse. It is deterministic and shares the world vertex
        // stream with other static settlement dressing.
        ground := terrain.sample_surface_height(&editor.project, 0, point[0], point[1])
        if ground <= editor.project.sea_level + .35 do continue
        if !world_sphere_in_view(editor, {point[0], ground + .6, point[1]}, 1, 2) do continue
        tint := inhabitant.worker ? canvas2d.Color{83, 103, 111, 210} : canvas2d.Color{104, 86, 70, 205}
        world_box_rotated({point[0], ground + .43, point[1]}, {.28, .66, .23}, 0, tint)
        world_box_rotated({point[0], ground + .85, point[1]}, {.32, .30, .30}, 0, tint)
    }
}

world_story_meeting :: proc(editor: ^Editor) {
    if editor == nil || editor.story_state.romance != .Meeting do return
    niko, iva, center, rotation, found := world_story_meeting_pose(editor)
    if !found do return
    if !world_sphere_in_view(editor, center + third_person.Vec3{0, 1.2, 0}, 3.5, 4) do return

    // A temporary quay awning gives the meeting a readable landmark without
    // requiring a hand-authored coordinate or a new asset.
    blue := canvas2d.Color{53, 103, 151, 255}
    pale := canvas2d.Color{219, 230, 220, 255}
    timber := canvas2d.Color{91, 63, 41, 255}
    canopy_y := max(niko.y, iva.y) + 1.72
    world_box_rotated({center.x, canopy_y, center.z}, {2.55, .12, 1.38}, rotation, blue)
    for stripe in -2 ..= 2 {
        if stripe & 1 != 0 do continue
        stripe_x, stripe_z := world_rotate_xz(center.x, center.z, f32(stripe) * .45, 0, rotation)
        world_box_rotated({stripe_x, canopy_y + .065, stripe_z}, {.34, .025, 1.40}, rotation, pale)
    }
    post_sides := [2]f32{-1, 1}
    for side in post_sides {
        post_x, post_z := world_rotate_xz(center.x, center.z, side * 1.13, -.54, rotation)
        ground := terrain.sample_surface_height(&editor.project, 0, post_x, post_z)
        world_box_rotated(
            {post_x, ground + (canopy_y - ground) * .5, post_z},
            {.075, canopy_y - ground, .075},
            rotation,
            timber,
        )
    }

    niko_draw, iva_draw := niko, iva
    iva_portrait_scale := f32(.96)
    if editor.attendant_dialogue_open && dialogue_current_resident(editor) == .Iva {
        niko_draw, iva_draw = iva, niko
        // Iva's long snout and flower silhouette fill considerably more of
        // Niko's nearer portrait position. Scale the promoted speaker so her
        // ears and accessory remain inside the dialogue card.
        iva_portrait_scale = .72
    }
    facing_niko := math.atan2(iva_draw.x - niko_draw.x, iva_draw.z - niko_draw.z)
    facing_iva := math.atan2(niko_draw.x - iva_draw.x, niko_draw.z - iva_draw.z)
    world_town_mouse_model_scaled_cached(
        editor,
        {
            position = niko_draw,
            rotation = math.PI - facing_niko,
            build = 1.12,
            snout_length = .94,
            accessory = .Acorn_Cap,
            fur = .Chestnut,
            pattern = .Pale_Belly,
            grounded = true,
        },
        1.02,
        TOWN_MOUSE_CACHE_COUNT - 2,
    )
    world_town_mouse_model_scaled_cached(
        editor,
        {
            position = iva_draw,
            rotation = math.PI - facing_iva,
            build = .86,
            snout_length = 1.16,
            accessory = .Flower,
            fur = .Cream,
            pattern = .Piebald,
            scarf_enabled = true,
            scarf_color = {177, 65, 73, 255},
            grounded = true,
        },
        iva_portrait_scale,
        TOWN_MOUSE_CACHE_COUNT - 1,
    )
    if story.resident_has_unseen_action(&editor.story_state, .Niko) {
        world_mouse_interaction_indicator(editor, niko)
    }
}

world_town_mouse_placements_ensure :: proc(editor: ^Editor) {
    if editor == nil do return
    if world_renderer.town_mouse_placement_valid &&
       world_renderer.town_mouse_placement_project_revision == editor.project.revision &&
       world_renderer.town_mouse_placement_terrain_revision == editor.terrain_revision {
        return
    }
    world_renderer.town_mouse_placements = {}
    structures := editor.project.structures[:editor.project.structure_count]
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    island_radius := half_extent * terrain.DEFAULT_ISLAND_RADIUS
    lateral := [8]f32{-1.0, .8, -1.3, 1.1, -.7, 1.4, -.9, 1.2}
    outward := [8]f32{2.5, 2.2, 2.7, 2.4, 2.2, 2.6, 2.3, 2.4}
    for sign, island_index in terrain.DEFAULT_ISLAND_SIGNS {
        island_center := sign * half_extent * terrain.DEFAULT_ISLAND_OFFSET
        clear(&world_renderer.structure_candidates)
        for structure, structure_index in structures {
            if structure.kind != .Architecture || structure.height > 60 do continue
            dx, dz := structure.center_x - island_center, structure.center_z - island_center
            if dx * dx + dz * dz > island_radius * island_radius do continue
            append(&world_renderer.structure_candidates, structure_index)
        }
        candidates := world_renderer.structure_candidates[:]
        candidate_count := len(candidates)
        if candidate_count == 0 do continue
        for resident_index in 0 ..< 8 {
            for attempt in 0 ..< candidate_count {
                candidate_index := candidates[(resident_index + attempt) % candidate_count]
                frontage := architecture.architecture_frontage_structure(structures[candidate_index])
                doorway_row := resident_index / candidate_count
                x, z, rotation := world_town_mouse_frontage_pose(
                    frontage,
                    &editor.project,
                    lateral[resident_index],
                    max(outward[resident_index] - 1.8, f32(.4)) + f32(doorway_row) * 1.25,
                )
                ground_y := terrain.sample_surface_height(&editor.project, 0, x, z)
                if ground_y <= editor.project.sea_level + .35 do continue
                world_renderer.town_mouse_placements[island_index][resident_index] = {
                    position = {x, ground_y, z},
                    rotation = rotation,
                    valid = true,
                }
                break
            }
        }
    }
    world_renderer.town_mouse_placement_project_revision = editor.project.revision
    world_renderer.town_mouse_placement_terrain_revision = editor.terrain_revision
    world_renderer.town_mouse_placement_valid = true
}

world_town_mice :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "town_mice")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if editor == nil do return
    world_business_sign_for_resident(editor, .Niko, .Pane)
    world_business_sign_for_resident(editor, .Zora, .Fortuna)
    world_business_sign_for_resident(editor, .Vesna, .Clinica)
    world_business_sign_for_resident(editor, .Anica, .Clinica)
    world_business_sign_for_resident(editor, .Toma, .Post)
    world_business_sign_for_resident(editor, .Lena, .Post)

    focal_length := editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : f32(1.35)
    view_camera := perspective_camera(editor.camera_pose, focal_length)
    screen_width := max(canvas2d.GetScreenWidth(), 1)
    screen_height := max(canvas2d.GetScreenHeight(), 1)
    aspect := f32(screen_width) / f32(screen_height)
    near_plane := world_camera_near_clip(editor)
    residents := [8]Town_Mouse {
        {-1.0, 2.5, .18, 1.08, 1.12, .94, .Acorn_Cap, .Chestnut, .Pale_Belly, false, {}},
        {.8, 2.2, -.22, .91, .86, 1.16, .Flower, .Cream, .Piebald, true, {177, 65, 73, 255}},
        {-1.3, 2.7, .12, 1.14, 1.22, .88, .Bottle_Cap, .Soot, .Solid, true, {61, 112, 139, 255}},
        {1.1, 2.4, -.16, 1.00, .94, 1.22, .Paper_Boat, .Silver, .Hooded, false, {}},
        {-.7, 2.2, .24, .86, 1.08, 1.02, .Chef_Hat, .White, .Pale_Belly, false, {}},
        {1.4, 2.6, -.10, 1.05, 1.18, 1.10, .None, .Russet, .Piebald, true, {205, 151, 52, 255}},
        {-.9, 2.3, .20, .96, .82, .90, .Goggles, .Chestnut, .Hooded, false, {}},
        {1.2, 2.4, -.12, .98, .90, 1.04, .Goggles, .Soot, .Piebald, true, {77, 168, 151, 255}},
    }
    world_town_mouse_placements_ensure(editor)
    for island_index in 0 ..< 2 {
        for resident, resident_index in residents {
            placement := world_renderer.town_mouse_placements[island_index][resident_index]
            if !placement.valid do continue
            x, ground_y, z := placement.position.x, placement.position.y, placement.position.z
            frontage_rotation := placement.rotation
            named_resident: story.Resident
            named := false
                if island_index == 0 && resident_index == 0 {
                    named_resident, named = .Niko, true
                } else if island_index == 0 && resident_index == 2 {
                    named_resident, named = .Bojan, true
                } else if island_index == 1 && resident_index == 1 {
                    named_resident, named = .Iva, true
                } else if island_index == 1 && resident_index == 5 {
                    named_resident, named = .Zora, true
                } else if island_index == 0 && resident_index == 4 {
                    named_resident, named = .Vesna, true
                } else if island_index == 0 && resident_index == 6 {
                    named_resident, named = .Petar, true
                } else if island_index == 1 && resident_index == 6 {
                    named_resident, named = .Anica, true
                } else if island_index == 1 && resident_index == 3 {
                    named_resident, named = .Mirna, true
                }
                if named &&
                   editor.story_state.romance == .Meeting &&
                   (named_resident == .Niko || named_resident == .Iva) {
                    continue
                }
                if named && named_resident == .Zora do continue
                rotation := frontage_rotation + resident.facing
                mouse_center := third_person.Vec3{x, ground_y + .75 * resident.scale, z}
                if !static_sphere_in_frustum(
                    view_camera,
                    mouse_center,
                    1.8 * resident.scale,
                    aspect,
                    near_plane,
                    WORLD_FAR_CLIP,
                ) {
                    continue
                }
            world_town_mouse_model_scaled_cached(
                    editor,
                    {
                        position = {x, ground_y, z},
                        rotation = rotation,
                        build = resident.build,
                        snout_length = resident.snout_length,
                        accessory = resident.accessory,
                        fur = resident.fur,
                        pattern = resident.pattern,
                        scarf_enabled = resident.scarf,
                        scarf_color = resident.scarf_color,
                        grounded = true,
                    },
                    resident.scale,
                    island_index * len(residents) + resident_index,
                )
            if named && story.resident_has_unseen_action(&editor.story_state, named_resident) {
                world_mouse_interaction_indicator(editor, {x, ground_y, z})
            }
        }
    }
    zora_position, zora_rotation, zora_found := world_story_resident_home_pose(editor, .Zora)
    if zora_found && world_sphere_in_view(editor, zora_position + third_person.Vec3{0, 1.1, 0}, 2, 4) {
        world_town_mouse_model_scaled_cached(
            editor,
            {
                position = zora_position,
                rotation = zora_rotation + math.PI * .5 - .10,
                build = 1.18,
                snout_length = 1.10,
                fur = .Russet,
                pattern = .Piebald,
                scarf_enabled = true,
                scarf_color = {205, 151, 52, 255},
                grounded = true,
            },
            1.05,
            len(residents) + 5,
        )
        if story.resident_has_unseen_action(&editor.story_state, .Zora) {
            world_mouse_interaction_indicator(editor, zora_position)
        }
    }
    postal_residents := [2]story.Resident{.Toma, .Lena}
    for postal_resident, postal_index in postal_residents {
        position, frontage_rotation, found := world_story_resident_home_pose(editor, postal_resident)
        if !found || !world_sphere_in_view(editor, position + third_person.Vec3{0, 1.1, 0}, 2, 4) do continue
        is_toma := postal_resident == .Toma
        world_town_mouse_model_scaled_cached(
            editor,
            {
                position = position,
                rotation = frontage_rotation + math.PI * .5,
                build = is_toma ? f32(1.06) : f32(.92),
                snout_length = is_toma ? f32(.96) : f32(1.10),
                accessory = .Paper_Boat,
                fur = is_toma ? Mouse_Fur.Chestnut : Mouse_Fur.Cream,
                pattern = is_toma ? Mouse_Fur_Pattern.Hooded : Mouse_Fur_Pattern.Piebald,
                scarf_enabled = true,
                scarf_color = is_toma ? canvas2d.Color{45, 73, 104, 255} : canvas2d.Color{154, 54, 52, 255},
                grounded = true,
            },
            1,
            TOWN_MOUSE_CACHE_COUNT - 4 + postal_index,
        )
        if story.resident_has_unseen_action(&editor.story_state, postal_resident) ||
           player_mail_available_count(editor) > 0 {
            world_mouse_interaction_indicator(editor, position)
        }
    }
    world_story_meeting(editor)
}

world_lighthouse_keeper_pose :: proc(
    editor: ^Editor,
    structure: terrain.Structure,
) -> (
    position: third_person.Vec3,
    rotation: f32,
    ok: bool,
) {
    if editor == nil || structure.kind != .Architecture do return {}, 0, false
    identity := architecture.architecture_resolve_legacy_identity(structure)
    if identity.archetype != .Lighthouse do return {}, 0, false
    x, z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .23,
        structure.depth * .5 + 1.8,
        structure.rotation,
    )
    ground_y := terrain.sample_surface_height(&editor.project, 0, x, z)
    if ground_y <= editor.project.sea_level + .35 do return {}, 0, false
    return {x, ground_y, z}, structure.rotation + math.PI * .5, true
}

world_lighthouse_keepers :: proc(editor: ^Editor) {
    if editor == nil do return
    keeper_index := 0
    for structure in editor.project.structures[:editor.project.structure_count] {
        position, rotation, found := world_lighthouse_keeper_pose(editor, structure)
        if !found do continue
        if !world_sphere_in_view(editor, position + third_person.Vec3{0, 1.1, 0}, 2.2, 4) {
            keeper_index += 1
            continue
        }
        world_lighthouse_keeper_model(editor, position, rotation, keeper_index == 0)
        keeper_index += 1
    }
}

world_lighthouse_keeper_model :: proc(
    editor: ^Editor,
    position: third_person.Vec3,
    rotation: f32,
    west_keeper: bool,
    grounded: bool = true,
    scale: f32 = 1,
) {
    if editor == nil do return
    world_mouse_model_scaled(
        editor,
        {
            position = position,
            rotation = rotation,
            build = west_keeper ? f32(1.08) : f32(.94),
            snout_length = west_keeper ? f32(.94) : f32(1.08),
            accessory = .Bottle_Cap,
            fur = west_keeper ? Mouse_Fur.Soot : Mouse_Fur.Silver,
            pattern = .Pale_Belly,
            scarf_enabled = true,
            scarf_color = west_keeper ? canvas2d.Color{218, 151, 43, 255} : canvas2d.Color{184, 62, 48, 255},
            grounded = grounded,
        },
        scale,
    )
}

world_brush_disc :: proc(editor: ^Editor, x, z, radius, height_offset: f32, color: canvas2d.Color) {
    if editor == nil do return
    segments := 48
    center := third_person.Vec3{x, terrain.sample_surface_height(&editor.project, 0, x, z) + height_offset, z}
    for i in 0 ..< segments {
        a0 := f32(i) * 2 * math.PI / f32(segments)
        a1 := f32(i + 1) * 2 * math.PI / f32(segments)
        p0 := third_person.Vec3{x + math.cos(a0) * radius, 0, z + math.sin(a0) * radius}
        p1 := third_person.Vec3{x + math.cos(a1) * radius, 0, z + math.sin(a1) * radius}
        p0.y = terrain.sample_surface_height(&editor.project, 0, p0.x, p0.z) + height_offset
        p1.y = terrain.sample_surface_height(&editor.project, 0, p1.x, p1.z) + height_offset
        // Ground decal fan: upward face front (CCW) so it survives culling.
        world_triangle(center, p1, p0, color)
    }
}

world_settlement_brush_segment :: proc(editor: ^Editor, a, b: [2]f32, color: canvas2d.Color) {
    delta := b - a
    length := linalg.length(delta)
    if editor == nil || length <= .001 do return
    normal := [2]f32{-delta[1] / length, delta[0] / length} * .32
    ah := terrain.sample_surface_height(&editor.project, 0, a[0], a[1]) + .13
    bh := terrain.sample_surface_height(&editor.project, 0, b[0], b[1]) + .13
    points := [4]third_person.Vec3 {
        {a[0] - normal[0], ah, a[1] - normal[1]},
        {a[0] + normal[0], ah, a[1] + normal[1]},
        {b[0] + normal[0], bh, b[1] + normal[1]},
        {b[0] - normal[0], bh, b[1] - normal[1]},
    }
    world_quad(points[0], points[1], points[2], points[3], color)
    world_quad(points[3], points[2], points[1], points[0], color)
}

world_settlement_brush_outline :: proc(editor: ^Editor) {
    if editor == nil do return
    center := [2]f32{editor.cursor_world_x, editor.cursor_world_z}
    if editor.architecture_painting do center = {editor.architecture_last_x, editor.architecture_last_z}
    piece := Settlement_Brush_Piece {
        shape    = editor.architecture_brush_shape,
        preset   = editor.architecture_brush_preset,
        center   = center,
        rotation = editor.architecture_brush_rotation,
        density  = editor.architecture_brush_strength,
        hardness = editor.architecture_brush_hardness,
    }
    span := settlement_brush_preset_span(piece.preset)
    local_points: [98][2]f32
    point_count := 0
    switch piece.shape {
    case .Circle:
        point_count = 48
        for index in 0 ..< point_count {
            angle := f32(index) / f32(point_count) * 2 * math.PI
            local_points[index] = {math.cos(angle) * span * .5, math.sin(angle) * span * .5}
        }
    case .Square:
        point_count = 4
        local_points[0], local_points[1] = {-span * .5, -span * .5}, {span * .5, -span * .5}
        local_points[2], local_points[3] = {span * .5, span * .5}, {-span * .5, span * .5}
    case .Rectangle:
        point_count = 4
        local_points[0], local_points[1] = {-span * .5, -span * .275}, {span * .5, -span * .275}
        local_points[2], local_points[3] = {span * .5, span * .275}, {-span * .5, span * .275}
    case .Macaroni:
        intervals := 32
        thickness := span * .28
        centerline := span * .5 - thickness * .5
        outer, inner := centerline + thickness * .5, centerline - thickness * .5
        for index in 0 ..= intervals {
            angle := -math.PI / 3 + f32(index) / f32(intervals) * 2 * math.PI / 3
            local_points[point_count] = {math.cos(angle) * outer, math.sin(angle) * outer}
            point_count += 1
        }
        for index := intervals; index >= 0; index -= 1 {
            angle := -math.PI / 3 + f32(index) / f32(intervals) * 2 * math.PI / 3
            local_points[point_count] = {math.cos(angle) * inner, math.sin(angle) * inner}
            point_count += 1
        }
    }
    cosine, sine := math.cos(piece.rotation), math.sin(piece.rotation)
    for index in 0 ..< point_count {
        next := (index + 1) % point_count
        a_local, b_local := local_points[index], local_points[next]
        a := piece.center + [2]f32{a_local[0] * cosine - a_local[1] * sine, a_local[0] * sine + a_local[1] * cosine}
        b := piece.center + [2]f32{b_local[0] * cosine - b_local[1] * sine, b_local[0] * sine + b_local[1] * cosine}
        color := canvas2d.Color{116, 226, 191, 190}
        if !settlement_brush_point_developable(&editor.project, (a + b) * .5, SETTLEMENT_TOWN.max_slope) {
            color = {229, 105, 90, 205}
        }
        world_settlement_brush_segment(editor, a, b, color)
    }
}
