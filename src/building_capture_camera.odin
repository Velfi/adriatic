package main

import architecture "../packages/architecture"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:strconv"

configure_building_capture_camera :: proc(editor: ^Editor, target_arg: string = "") -> bool {
    if editor == nil do return false
    if target_arg == "west-town-review" || target_arg == "east-town-review" {
        island_sign := target_arg == "west-town-review" ? f32(-1) : f32(1)
        town_x, town_z := terrain.default_town_center_for_project(&editor.project, island_sign)
        focus_y := terrain.sample_surface_height(&editor.project, 0, town_x, town_z) + 4
        editor.capture_world_only = true
        editor.architecture_node_mode = true
        editor.editor_camera.distance = 190
        editor.editor_focus = {town_x, focus_y, town_z}
        editor.camera_pose = third_person.camera_look_at(
            {town_x + 115, focus_y + 125, town_z + 115},
            editor.editor_focus,
        )
        return true
    }
    bougainvillea_seed_override := -1
    storefront_plant_seed_override := -1
    storefront_display_seed_override := -1
    storefront_angle_seed_override := -1
    storefront_plan_seed_override := -1
    stoop_seed_override := -1
    ground_level_capture := false
    roof_capture := false
    roof_landmark_capture := target_arg == "roof-landmark"
    roof_ceremonial_capture := target_arg == "roof-ceremonial"
    roof_aegean_parapet_capture := target_arg == "roof-style-parapet-aegean"
    roof_style_capture := false
    roof_style_target := architecture.Roof_Style.Gable
    switch target_arg {
    case "stoop-straight":
        stoop_seed_override, ground_level_capture = 3, true
    case "stoop-left":
        stoop_seed_override, ground_level_capture = 4, true
    case "stoop-right":
        stoop_seed_override, ground_level_capture = 5, true
    case "roof-style-gable":
        roof_style_capture, roof_style_target = true, .Gable
    case "roof-style-low-gable":
        roof_style_capture, roof_style_target = true, .Low_Gable
    case "roof-style-hip":
        roof_style_capture, roof_style_target = true, .Hip
    case "roof-style-parapet":
        roof_style_capture, roof_style_target = true, .Parapet
    }
    if roof_style_capture do structure_lod_force(0)
    if roof_aegean_parapet_capture do structure_lod_force(0)
    ordinal_arg := target_arg
    ground_prefix := "ground-"
    if len(target_arg) > len(ground_prefix) && target_arg[:len(ground_prefix)] == ground_prefix {
        ground_level_capture = true
        ordinal_arg = target_arg[len(ground_prefix):]
    }
    roof_prefix := "roof-"
    if len(target_arg) > len(roof_prefix) && target_arg[:len(roof_prefix)] == roof_prefix {
        roof_capture = true
        ordinal_arg = target_arg[len(roof_prefix):]
    }
    roof_medium_prefix := "roof-medium-"
    if len(target_arg) > len(roof_medium_prefix) && target_arg[:len(roof_medium_prefix)] == roof_medium_prefix {
        roof_capture = true
        ordinal_arg = target_arg[len(roof_medium_prefix):]
        structure_lod_force(1)
    }
    bougainvillea_prefix := "bougainvillea-"
    if len(target_arg) > len(bougainvillea_prefix) && target_arg[:len(bougainvillea_prefix)] == bougainvillea_prefix {
        parsed, ok := strconv.parse_int(target_arg[len(bougainvillea_prefix):])
        if ok && parsed >= 0 && parsed <= 0xffffffff {
            bougainvillea_seed_override = int(parsed)
        }
    }
    storefront_plant_prefix := "storefront-plant-"
    if len(target_arg) > len(storefront_plant_prefix) &&
       target_arg[:len(storefront_plant_prefix)] == storefront_plant_prefix {
        parsed, ok := strconv.parse_int(target_arg[len(storefront_plant_prefix):])
        if ok && parsed >= 0 && parsed <= 0xffffffff {
            storefront_plant_seed_override = int(parsed)
        }
    }
    storefront_display_prefix := "storefront-display-"
    if len(target_arg) > len(storefront_display_prefix) &&
       target_arg[:len(storefront_display_prefix)] == storefront_display_prefix {
        parsed, ok := strconv.parse_int(target_arg[len(storefront_display_prefix):])
        if ok && parsed >= 0 && parsed <= 0xffffffff {
            storefront_display_seed_override = int(parsed)
        }
    }
    storefront_night_display_prefix := "storefront-night-display-"
    if len(target_arg) > len(storefront_night_display_prefix) &&
       target_arg[:len(storefront_night_display_prefix)] == storefront_night_display_prefix {
        parsed, ok := strconv.parse_int(target_arg[len(storefront_night_display_prefix):])
        if ok && parsed >= 0 && parsed <= 0xffffffff {
            storefront_display_seed_override = int(parsed)
        }
    }
    storefront_angle_prefix := "storefront-angle-"
    if len(target_arg) > len(storefront_angle_prefix) &&
       target_arg[:len(storefront_angle_prefix)] == storefront_angle_prefix {
        parsed, ok := strconv.parse_int(target_arg[len(storefront_angle_prefix):])
        if ok && parsed >= 0 && parsed <= 0xffffffff {
            storefront_angle_seed_override = int(parsed)
        }
    }
    storefront_plan_prefix := "storefront-plan-"
    if len(target_arg) > len(storefront_plan_prefix) &&
       target_arg[:len(storefront_plan_prefix)] == storefront_plan_prefix {
        parsed, ok := strconv.parse_int(target_arg[len(storefront_plan_prefix):])
        if ok && parsed >= 0 && parsed <= 0xffffffff {
            storefront_plan_seed_override = int(parsed)
        }
    }
    if target_arg == "municipal-route-night" || target_arg == "municipal-route-night-storm" {
        seed_municipal_route_lamps(editor)
        if editor.architecture_city_plan.lamp_count > 0 {
            // Frame the middle lamp of an interior row so the capture shows
            // the complete three-fixture pedestrian cadence across the route.
            lamp_index := min(10, editor.architecture_city_plan.lamp_count - 1)
            lamp := editor.architecture_city_plan.lamps[lamp_index]
            ground := terrain.sample_surface_height(&editor.project, 0, lamp.x, lamp.z)
            focus := third_person.Vec3{lamp.x, ground + 1.8, lamp.z}
            eye := third_person.Vec3{lamp.x + 2.0, ground + 2.1, lamp.z + 23}
            editor.capture_world_only = true
            editor.architecture_node_mode = true
            editor.editor_focus = focus
            editor.camera_pose = third_person.camera_look_at(eye, focus)
            return true
        }
    }
    if target_arg == "mouse-wheel-plaza" {
        plan := editor_circulation_plan(editor)
        if plan != nil {
            best_area_index := -1
            best_area_score := -f32(1e30)
            for area, area_index in plan.areas[:plan.count] {
                if area.kind != .Plaza do continue
                score := area.width * area.length
                if score > best_area_score {
                    best_area_index, best_area_score = area_index, score
                }
            }
            if best_area_index >= 0 {
                area := plan.areas[best_area_index]
                wheel_x, wheel_z := world_town_mouse_wheel_position(area)
                eye_x, eye_z := world_rotate_xz(wheel_x, wheel_z, 4.2, 4.2, area.rotation)
                wheel_y := terrain.sample_surface_height(&editor.project, 0, wheel_x, wheel_z)
                eye_y := max(terrain.sample_surface_height(&editor.project, 0, eye_x, eye_z), wheel_y) + 7
                editor.capture_world_only = true
                editor.architecture_node_mode = true
                editor.editor_focus = {wheel_x, wheel_y + .35, wheel_z}
                editor.camera_pose = third_person.camera_look_at({eye_x, eye_y, eye_z}, editor.editor_focus)
                return true
            }
        }
    }
    if target_arg == "plaza" ||
       target_arg == "plaza-night" ||
       target_arg == "plaza-night-new-moon" ||
       target_arg == "plaza-night-full-moon" ||
       target_arg == "plaza-night-storm" {
        plan := editor_circulation_plan(editor)
        if plan != nil {
            best_area_index := -1
            best_area_score := -f32(1e30)
            for area, area_index in plan.areas[:plan.count] {
                if area.kind != .Plaza do continue
                score := area.width * area.length
                if score > best_area_score {
                    best_area_index, best_area_score = area_index, score
                }
            }
            if best_area_index >= 0 {
                area := plan.areas[best_area_index]
                best_eye_x, best_eye_z := area.center_x, area.center_z
                best_focus_x, best_focus_z := area.center_x, area.center_z
                best_view_clearance := -f32(1e30)
                for corner_x in -1 ..= 1 {
                    if corner_x == 0 do continue
                    for corner_z in -1 ..= 1 {
                        if corner_z == 0 do continue
                        local_x := f32(corner_x) * (area.width * .5 - 1.4)
                        local_z := f32(corner_z) * (area.length * .5 - 1.4)
                        candidate_x, candidate_z := world_rotate_xz(
                            area.center_x,
                            area.center_z,
                            local_x,
                            local_z,
                            area.rotation,
                        )
                        for view_index in 0 ..< 8 {
                            view_angle := f32(view_index) / 8 * 2 * f32(math.PI)
                            eye_candidate_x := candidate_x + math.cos(view_angle) * 8
                            eye_candidate_z := candidate_z + math.sin(view_angle) * 8
                            midpoint_x := (eye_candidate_x + candidate_x) * .5
                            midpoint_z := (eye_candidate_z + candidate_z) * .5
                            clearance := f32(1e30)
                            for structure in editor.project.structures[:editor.project.structure_count] {
                                if structure.kind != .Architecture || structure.height > 60 do continue
                                radius := max(structure.width, structure.depth) * .5
                                eye_dx, eye_dz :=
                                    eye_candidate_x - structure.center_x, eye_candidate_z - structure.center_z
                                eye_distance := f32(math.sqrt(f64(eye_dx * eye_dx + eye_dz * eye_dz))) - radius
                                mid_dx, mid_dz := midpoint_x - structure.center_x, midpoint_z - structure.center_z
                                mid_distance := f32(math.sqrt(f64(mid_dx * mid_dx + mid_dz * mid_dz))) - radius
                                clearance = min(clearance, min(eye_distance, mid_distance))
                            }
                            if clearance > best_view_clearance {
                                best_eye_x, best_eye_z = eye_candidate_x, eye_candidate_z
                                best_focus_x, best_focus_z = candidate_x, candidate_z
                                best_view_clearance = clearance
                            }
                        }
                    }
                }
                eye_y := terrain.sample_surface_height(&editor.project, 0, best_eye_x, best_eye_z) + 1.78
                focus_y := terrain.sample_surface_height(&editor.project, 0, best_focus_x, best_focus_z) + 2.15
                editor.capture_world_only = true
                editor.architecture_node_mode = true
                editor.editor_camera.distance = 8
                editor.editor_focus = {best_focus_x, focus_y, best_focus_z}
                // Judge public lighting from a pedestrian's eye line inside
                // the plaza. The former high diagonal view repeatedly landed
                // between tall façades and hid pool overlap behind rooftops.
                editor.camera_pose = third_person.camera_look_at({best_eye_x, eye_y, best_eye_z}, editor.editor_focus)
                return true
            }
        }
    }
    if target_arg == "cypress" {
        min_x, max_x := f32(1e9), f32(-1e9)
        min_z, max_z := f32(1e9), f32(-1e9)
        buildings := 0
        for structure in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture || structure.height > 60 do continue
            min_x = min(min_x, structure.center_x)
            max_x = max(max_x, structure.center_x)
            min_z = min(min_z, structure.center_z)
            max_z = max(max_z, structure.center_z)
            buildings += 1
        }
        if buildings >= 4 {
            center_x, center_z := (min_x + max_x) * .5, (min_z + max_z) * .5
            road_span := max(max_x - min_x + 36, 160)
            tree_x := center_x + road_span * .42
            tree_z := center_z + (max_z - min_z) * .5 + 7
            tree_y := terrain.sample_surface_height(&editor.project, 0, tree_x, tree_z)
            // The cypress is taller than a façade, so pull the verification
            // camera back and aim through its middle instead of clipping the
            // crown from an eye-level close-up.
            eye_x, eye_z := tree_x - 30, tree_z - 30
            eye_y := terrain.sample_surface_height(&editor.project, 0, eye_x, eye_z) + 4.0
            editor.capture_world_only = true
            editor.architecture_node_mode = true
            editor.editor_camera.distance = 36
            editor.editor_focus = {tree_x, tree_y + 20.0, tree_z}
            editor.camera_pose = third_person.camera_look_at({eye_x, eye_y, eye_z}, editor.editor_focus)
            return true
        }
    }
    target_index := -1
    // Seed-matrix captures use the same close façade as the long-running
    // architectural validation shot, changing only the plant seed. This keeps
    // palette and habit comparisons from being confounded by camera/building
    // selection.
    requested_ordinal := bougainvillea_seed_override >= 0 ? 4 : -1
    if ordinal_arg != "" && bougainvillea_seed_override < 0 {
        parsed, ok := strconv.parse_int(ordinal_arg)
        if ok && parsed >= 0 do requested_ordinal = int(parsed)
    }

    // Explicit targets use a stable zero-based ordinal over architecture
    // structures, independent of roads, foliage, and other authored items.
    if requested_ordinal >= 0 {
        ordinal := 0
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture do continue
            if ordinal == requested_ordinal {
                target_index = index
                break
            }
            ordinal += 1
        }
    }
    if stoop_seed_override >= 0 {
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind == .Architecture && structure.seed == u32(stoop_seed_override) {
                target_index = index
            }
        }
    }
    if roof_style_capture {
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture || settlement_structure_is_landmark(structure) {
                continue
            }
            if world_architecture_roof_style(structure) == roof_style_target {
                target_index = index
                break
            }
        }
        // Keep every style fixture available even if a deterministic town
        // happens not to contain that seed modulo. Mutations stay inside the
        // transient capture project.
        if target_index < 0 {
            for structure, index in editor.project.structures[:editor.project.structure_count] {
                if structure.kind != .Architecture || settlement_structure_is_landmark(structure) {
                    continue
                }
                target_index = index
                target := &editor.project.structures[index]
                target.building.archetype = .Dwelling
                target.building.landmark_kind = .None
                target.building.region = .Adriatic
                target.seed = target.seed / 4 * 4 + u32(roof_style_target)
                world_terrain_invalidate_all(editor)
                break
            }
        }
    }
    if roof_aegean_parapet_capture {
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture || settlement_structure_is_landmark(structure) {
                continue
            }
            identity := architecture.architecture_resolve_legacy_identity(structure)
            if identity.region == .Aegean {
                target_index = index
                break
            }
        }
        if target_index < 0 {
            for structure, index in editor.project.structures[:editor.project.structure_count] {
                if structure.kind != .Architecture || settlement_structure_is_landmark(structure) {
                    continue
                }
                target_index = index
                target := &editor.project.structures[index]
                target.building.archetype = .Dwelling
                target.building.landmark_kind = .None
                target.building.region = .Aegean
                world_terrain_invalidate_all(editor)
                break
            }
        }
    }
    if roof_landmark_capture {
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind == .Architecture && settlement_structure_is_landmark(structure) {
                target_index = index
                break
            }
        }
    }
    if roof_ceremonial_capture {
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture do continue
            identity := architecture.architecture_resolve_legacy_identity(structure)
            if identity.archetype == .Church ||
               identity.archetype == .Campanile ||
               identity.archetype == .Cycladic_Bell {
                target_index = index
                break
            }
        }
        // Some deterministic settlement seeds contain only civic landmarks.
        // This is a transient capture world, so promote a suitably sized
        // ordinary structure when necessary to keep the ceremonial roof
        // regression fixture available for every seed.
        if target_index < 0 {
            for structure, index in editor.project.structures[:editor.project.structure_count] {
                if structure.kind != .Architecture || structure.width < 9 || structure.depth < 12 {
                    continue
                }
                target_index = index
                editor.project.structures[index].building.archetype = .Church
                editor.project.structures[index].building.landmark_kind = .Church
                break
            }
        }
    }

    generated_storefront_capture := target_arg == "storefront-generated" || target_arg == "storefront-generated-night"
    storefront_capture :=
        target_arg == "storefront" ||
        target_arg == "storefront-front" ||
        generated_storefront_capture ||
        capture_target_is_storefront_night(target_arg) ||
        storefront_plant_seed_override >= 0 ||
        storefront_display_seed_override >= 0 ||
        storefront_angle_seed_override >= 0 ||
        storefront_plan_seed_override >= 0
    if storefront_capture {
        best_score := -f32(1e30)
        for &structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture {
                continue
            }
            if generated_storefront_capture {
                if structure.width < 12 || structure.height > 60 do continue
            } else if structure.width < 16 || structure.height > 36 {
                continue
            }
            identity := architecture.architecture_resolve_legacy_identity(structure)
            if generated_storefront_capture && identity.archetype != .Mixed_Use_Dwelling {
                continue
            }
            score := structure.width - math.abs(structure.height - 16) * .35
            if identity.archetype == .Mixed_Use_Dwelling do score += 100
            if identity.archetype == .Shop_House do score += 50
            if score > best_score {
                best_score = score
                target_index = index
            }
        }
        if generated_storefront_capture && target_index < 0 {
            // Never let this verification target silently fall through to an
            // unrelated ordinary building.
            return false
        }
        if target_index >= 0 {
            // This is a visual test fixture in the transient capture world:
            // always exercise the dedicated archetype even if the selected
            // deterministic settlement seed produced only ordinary dwellings.
            if !generated_storefront_capture {
                editor.project.structures[target_index].building.archetype = .Mixed_Use_Dwelling
                editor.project.structures[target_index].building.purpose = .Inn_Shop
                editor.project.structures[target_index].building.landmark_kind = .None
                editor.project.structures[target_index].seed &~= SETTLEMENT_LANDMARK_SEED_MASK
                if storefront_display_seed_override >= 0 {
                    editor.project.structures[target_index].seed = u32(storefront_display_seed_override)
                }
                if storefront_angle_seed_override >= 0 {
                    editor.project.structures[target_index].seed = u32(storefront_angle_seed_override)
                }
                if storefront_plan_seed_override >= 0 {
                    editor.project.structures[target_index].seed = u32(storefront_plan_seed_override)
                    editor.project.structures[target_index].width = max(
                        editor.project.structures[target_index].width,
                        f32(24),
                    )
                    editor.project.structures[target_index].depth = max(
                        editor.project.structures[target_index].depth,
                        f32(18),
                    )
                }
                // The capture world may have rendered one editor frame before
                // this fixture converts the selected building. Rebuild cached
                // architecture and presentation geometry so ordinary-dwelling
                // pots, openings, and foliage cannot survive the mixed-use
                // archetype/seed mutation.
                world_terrain_invalidate_all(editor)
            }
        }
        ground_level_capture = true
    }

    // Auto-target a normal building on the camera-facing edge of the town.
    // That keeps intervening rows out of the shot as generated layouts change.
    if target_index < 0 {
        center_x, building_count := f32(0), 0
        for structure in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture || structure.height > 60 do continue
            center_x += structure.center_x
            building_count += 1
        }
        if building_count > 0 do center_x /= f32(building_count)
        best_score := -f32(1e30)
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if structure.kind != .Architecture || structure.height > 60 do continue
            score := structure.center_z - abs(structure.center_x - center_x) * .16 + structure.width * .08
            if score > best_score {
                best_score = score
                target_index = index
            }
        }
    }
    if target_index < 0 do return false

    building := editor.project.structures[target_index]
    if storefront_plant_seed_override >= 0 {
        editor.capture_bougainvillea_seed_enabled = true
        editor.capture_bougainvillea_structure_id = building.id
        editor.capture_bougainvillea_seed = u32(storefront_plant_seed_override)
    }
    if bougainvillea_seed_override >= 0 {
        editor.capture_bougainvillea_seed_enabled = true
        editor.capture_bougainvillea_structure_id = building.id
        editor.capture_bougainvillea_seed = u32(bougainvillea_seed_override)
    }
    facade_x, facade_z := -math.sin(building.rotation), math.cos(building.rotation)
    if storefront_plan_seed_override >= 0 {
        facade_x, facade_z = -facade_x, -facade_z
    }
    // Move the architectural capture into the lane so balconies and laundry
    // read as the subject instead of small details in a town-wide shot.
    camera_distance := building.depth * .5 + max(f32(9), building.height * .54)
    if ground_level_capture {
        camera_distance = building.depth * .5 + max(f32(10), building.width * .48)
    }
    if roof_capture {
        camera_distance = building.depth * .5 + max(f32(14), building.width * .80)
    }
    if storefront_plan_seed_override >= 0 {
        camera_distance = building.depth * .5 + max(f32(28), building.width * 1.25)
    }
    minimum_distance := building.depth * .5 + 6
    for camera_distance > minimum_distance {
        dry_approach := true
        facade_distance := building.depth * .5 + .75
        for sample in 1 ..= 12 {
            sample_distance := facade_distance + (camera_distance - facade_distance) * f32(sample) / 12
            sample_x := building.center_x + facade_x * sample_distance
            sample_z := building.center_z + facade_z * sample_distance
            sample_ground := terrain.sample_surface_height(&editor.project, 0, sample_x, sample_z)
            if sample_ground <= editor.project.sea_level + .35 {
                dry_approach = false
                break
            }
        }
        if dry_approach do break
        camera_distance = max(minimum_distance, camera_distance - 4)
    }
    eye_x := building.center_x + facade_x * camera_distance
    eye_z := building.center_z + facade_z * camera_distance
    // A modest lateral offset reveals the balcony depth instead of flattening
    // every railing into a line across the window.
    side_offset :=
        target_arg == "storefront-front" || generated_storefront_capture || storefront_display_seed_override >= 0 ? f32(0) : storefront_plan_seed_override >= 0 ? min(f32(24), camera_distance * .45) : storefront_capture ? -min(f32(30), camera_distance * .90) : ground_level_capture ? min(f32(5), building.width * .16) : min(f32(8), building.width * .24)
    eye_x += facade_z * side_offset
    eye_z -= facade_x * side_offset
    eye_y :=
        terrain.sample_surface_height(&editor.project, 0, eye_x, eye_z) +
        (roof_capture ? building.height + max(f32(10), building.width * .55) : storefront_plan_seed_override >= 0 ? f32(6.2) : f32(3.2))
    target_y :=
        roof_capture ? building.base_y + building.height + building.width * .14 : storefront_plan_seed_override >= 0 ? building.base_y + building.height * .34 : ground_level_capture ? building.base_y + 2.4 : building.base_y + clamp(building.height * .50, f32(7), f32(18))
    editor.capture_world_only = true
    // Keep the procedural street dressing in the architectural capture so
    // façades read as a walkable Mediterranean neighborhood, not isolated
    // blocks floating on a blank field.
    editor.architecture_node_mode = true
    // The pose is explicit; keep the editor-orbit distance low only so its
    // near-clip heuristic does not cut away the street under this camera.
    editor.editor_camera.distance = min(camera_distance, f32(36))
    editor.editor_focus = {building.center_x, target_y, building.center_z}
    editor.camera_pose = third_person.camera_look_at({eye_x, eye_y, eye_z}, editor.editor_focus)
    return true
}
