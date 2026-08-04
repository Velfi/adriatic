package main

import architecture "../packages/architecture"
import buildings "../packages/buildings"
import dio "../packages/dio"
import farmland "../packages/farmland"
import harbor "../packages/harbor"
import hero "../packages/hero_buildings"
import marina "../packages/marina"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import canvas2d "zelda_engine:canvas2d"

Building_Generator_Kind :: enum u8 {
    Ordinary,
    Post_Office,
    Clinic,
    Airport_Terminal,
    Marina_Office,
    Windmill,
    Patio,
    Garden,
    Cemetery,
    Plaza,
}

BUILDING_GENERATOR_AIRPORT_TERMINAL_GROUP :: u64(0x41505254524d4e4c)
BUILDING_GENERATOR_SITE_GROUP_TAG :: u64(0x4255494c00000000)
BUILDING_GENERATOR_SITE_GROUP_MASK :: u64(0xffffffff00000000)

building_generator_is_site_kind :: #force_inline proc(kind: Building_Generator_Kind) -> bool {
    return kind == .Patio || kind == .Garden || kind == .Cemetery || kind == .Plaza
}

building_generator_site_marker :: #force_inline proc(structure: terrain.Structure) -> bool {
    return structure.group_id & BUILDING_GENERATOR_SITE_GROUP_MASK == BUILDING_GENERATOR_SITE_GROUP_TAG
}

building_generator_select_kind :: proc(editor: ^Editor, kind: Building_Generator_Kind) {
    if editor == nil || editor.building_generator_kind == kind do return
    editor.building_generator_kind = kind
    if kind == .Ordinary {
        editor.building_generator_width = 12
        editor.building_generator_depth = 16
        editor.building_generator_height = 10
        return
    }
    if kind == .Marina_Office {
        editor.building_generator_width = 8.2
        editor.building_generator_depth = 6.4
        editor.building_generator_height = 4.8
        return
    }
    if kind == .Windmill {
        editor.building_generator_width = 10
        editor.building_generator_depth = 10
        editor.building_generator_height = 8
        return
    }
    if kind == .Patio {
        editor.building_generator_width = 8
        editor.building_generator_depth = 6
        editor.building_generator_height = .1
        return
    }
    if kind == .Garden {
        editor.building_generator_width = 12
        editor.building_generator_depth = 10
        editor.building_generator_height = .1
        return
    }
    if kind == .Cemetery {
        editor.building_generator_width = 30
        editor.building_generator_depth = 36
        editor.building_generator_height = .1
        return
    }
    if kind == .Plaza {
        editor.building_generator_width = 18
        editor.building_generator_depth = 16
        editor.building_generator_height = .1
        return
    }
    hero_kind := kind == .Clinic ? hero.Kind.Clinic : kind == .Airport_Terminal ? hero.Kind.Airport_Terminal : hero.Kind.Post_Office
    config := hero.defaults(hero_kind)
    editor.building_generator_width = config.frontage
    editor.building_generator_depth = config.depth
    plan := hero.generate(u32(max(editor.building_generator_variation, f32(1)) + .5), config)
    editor.building_generator_height = plan.arcade_height + plan.roof_height + plan.monitor_height
}

building_generator_structure :: proc(editor: ^Editor, x, z, rotation: f32) -> terrain.Structure {
    if editor == nil do return {}
    seed := u32(max(editor.building_generator_variation, f32(1)) + .5)
    height := terrain.sample_surface_height(&editor.project, 0, x, z)
    result := terrain.structure_make(
        x, z,
        editor.building_generator_width,
        editor.building_generator_depth,
        height,
        editor.building_generator_height,
    )
    result.kind = .Architecture
    // Generator footprints may be smaller than the generic terrain editing
    // minimum (notably the compact marina office).
    result.width = editor.building_generator_width
    result.depth = editor.building_generator_depth
    result.height = editor.building_generator_height
    result.rotation = rotation
    result.seed = seed
    if building_generator_is_site_kind(editor.building_generator_kind) {
        result.kind = .Foliage
        result.height = .01
        result.group_id = BUILDING_GENERATOR_SITE_GROUP_TAG | u64(editor.building_generator_kind)
    } else if editor.building_generator_kind == .Ordinary {
        result.building = architecture.architecture_identity(
            {
                density = editor.building_generator_density,
                frontage = editor.building_generator_width,
                depth = editor.building_generator_depth,
                purpose_explicit = false,
            },
            seed,
        )
    } else if editor.building_generator_kind == .Post_Office ||
              editor.building_generator_kind == .Clinic ||
              editor.building_generator_kind == .Airport_Terminal {
        hero_kind := editor.building_generator_kind == .Clinic ? hero.Kind.Clinic : editor.building_generator_kind == .Airport_Terminal ? hero.Kind.Airport_Terminal : hero.Kind.Post_Office
        landmark := editor.building_generator_kind == .Clinic ? buildings.Landmark_Kind.Clinic : buildings.Landmark_Kind.Post_Office
        config := hero.defaults(hero_kind)
        config.frontage = editor.building_generator_width
        config.depth = editor.building_generator_depth
        plan := hero.generate(seed, config)
        result.height = plan.arcade_height + plan.roof_height + plan.monitor_height
        result.building = architecture.architecture_identity(
            {
                landmark_kind = landmark,
                frontage = editor.building_generator_width,
                depth = editor.building_generator_depth,
                purpose_explicit = true,
            },
            seed,
        )
        if editor.building_generator_kind == .Airport_Terminal {
            result.group_id = BUILDING_GENERATOR_AIRPORT_TERMINAL_GROUP
            result.building = architecture.architecture_identity(
                {
                    density = .64,
                    frontage = editor.building_generator_width,
                    depth = editor.building_generator_depth,
                    purpose_explicit = true,
                },
                seed,
            )
        }
    } else if editor.building_generator_kind == .Marina_Office {
        result.height = 4.8
        result.building = architecture.architecture_identity(
            {
                region = .Adriatic,
                tissue = .Harbor,
                density = .42,
                frontage = editor.building_generator_width,
                depth = editor.building_generator_depth,
                route = .Waterfront,
                waterfront = true,
                landmark_kind = .Harbor_Office,
                purpose_explicit = true,
            },
            seed,
        )
    } else {
        result.building = {
            archetype = .Mill,
            purpose = .Mill,
            region = .Adriatic,
        }
    }
    if building_generator_is_site_kind(editor.building_generator_kind) {
        result.color = {0, 0, 0, 0}
        result.base_y = height
    } else {
        result.color = architecture.architecture_color(seed)
        _, foundation_high := architecture.architecture_foundation_height_range(&editor.project, result)
        result.base_y = foundation_high
    }
    return result
}

building_generator_site_valid :: proc(editor: ^Editor, candidate: terrain.Structure) -> bool {
    checked := candidate
    if editor == nil || !architecture.city_structure_site_valid(&editor.project, &checked) do return false
    for existing in editor.project.structures[:editor.project.structure_count] {
        if architecture.city_structure_overlaps(candidate, existing) do return false
    }
    return true
}

building_generator_refresh_preview :: proc(editor: ^Editor, x, z: f32) {
    if editor == nil do return
    candidate := building_generator_structure(editor, x, z, editor.architecture_brush_rotation)
    editor.building_generator_preview_valid = building_generator_site_valid(editor, candidate)
    architecture.city_plan_destroy(&editor.architecture_preview_plan)
    editor.architecture_preview_plan.structures = make([dynamic]terrain.Structure, 0, 1)
    append(&editor.architecture_preview_plan.structures, candidate)
    editor.architecture_preview_plan.count = 1
}

building_generator_commit :: proc(editor: ^Editor) {
    if editor == nil || !editor.building_generator_preview_valid || editor.architecture_preview_plan.count != 1 do return
    candidate := editor.architecture_preview_plan.structures[0]
    structure_history_push_undo(editor)
    added := terrain.add_structure(&editor.project, candidate)
    if added < 0 do return
    editor.project.structures[added].seed = candidate.seed
    switch editor.building_generator_kind {
    case .Patio:
        if editor.settlement_plan.patio_count < SETTLEMENT_PATIO_CAPACITY {
            editor.settlement_plan.patios[editor.settlement_plan.patio_count] = {
                center = {candidate.center_x, candidate.center_z},
                base_y = candidate.base_y,
                width = candidate.width,
                depth = candidate.depth,
                rotation = candidate.rotation,
                seed = candidate.seed,
                style = editor.settlement_plan.request.region == .Aegean ? .Aegean : .Adriatic,
            }
            editor.settlement_plan.patio_count += 1
            world_renderer.retained_patio_dirty = true
        }
    case .Garden:
        if editor.settlement_plan.site_count < len(editor.settlement_plan.sites) &&
           editor.settlement_plan.garden_count < len(editor.settlement_plan.gardens) {
            site_index := editor.settlement_plan.site_count
            editor.settlement_plan.sites[site_index] = {
                structure = editor.project.structures[added],
                kind = .Park,
                accepted = true,
            }
            editor.settlement_plan.site_count += 1
            editor.settlement_plan.gardens[editor.settlement_plan.garden_count] = {
                center = {candidate.center_x, candidate.center_z},
                width = candidate.width,
                depth = candidate.depth,
                rotation = candidate.rotation,
                seed = candidate.seed,
                site_index = site_index,
                style = .Courtyard,
            }
            editor.settlement_plan.garden_count += 1
            editor.settlement_plan.valid = true
        }
    case .Cemetery:
        editor.project.structures[added].group_id = SETTLEMENT_CEMETERY_GROUP_TAG | u64(candidate.seed)
        world_renderer.retained_patio_dirty = true
    case .Plaza:
        if editor.settlement_plan.terrain_edit_count < len(editor.settlement_plan.terrain_edits) {
            editor.settlement_plan.terrain_edits[editor.settlement_plan.terrain_edit_count] = {
                kind = .Plaza,
                center = {candidate.center_x, candidate.center_z},
                half_extent = {candidate.width * .5, candidate.depth * .5},
                target_height = candidate.base_y,
                feather = 1,
            }
            editor.settlement_plan.terrain_edit_count += 1
            editor.settlement_plan.valid = true
            editor.circulation_plan_valid = false
        }
    case .Ordinary, .Post_Office, .Clinic, .Airport_Terminal, .Marina_Office, .Windmill:
        append(&editor.architecture_city_plan.structures, candidate)
        editor.architecture_city_plan.count += 1
    }
    editor.project.revision += 1
    editor.building_generator_variation = min(editor.building_generator_variation + 1, f32(256))
}

architecture_paint_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.architecture_paint_mode || editor.airport_stamp_mode do return
    pressed := canvas2d.IsMouseButtonPressed(.LEFT)
    down := canvas2d.IsMouseButtonDown(.LEFT)
    released := canvas2d.IsMouseButtonReleased(.LEFT)
    if cursor_hit && !editor.architecture_painting {
        editor.architecture_last_x, editor.architecture_last_z = world_x, world_z
        building_generator_refresh_preview(editor, world_x, world_z)
    }
    if pressed && cursor_hit {
        editor.architecture_painting = true
        editor.architecture_last_x, editor.architecture_last_z = world_x, world_z
        editor.architecture_drag_x, editor.architecture_drag_z = world_x, world_z
        editor.architecture_brush_rotation = 0
        building_generator_refresh_preview(editor, world_x, world_z)
    }
    if editor.architecture_painting && down && cursor_hit && !pressed {
        editor.architecture_drag_x, editor.architecture_drag_z = world_x, world_z
        dx, dz := world_x - editor.architecture_last_x, world_z - editor.architecture_last_z
        if dx * dx + dz * dz > 1 {
            editor.architecture_brush_rotation = f32(math.atan2(f64(dz), f64(dx)))
        }
        building_generator_refresh_preview(editor, editor.architecture_last_x, editor.architecture_last_z)
    }
    if editor.architecture_painting && released {
        building_generator_commit(editor)
        editor.architecture_painting = false
        building_generator_refresh_preview(editor, world_x, world_z)
    }
}

AIRPORT_STAMP_SEED :: u32(0x41525054)
AIRPORT_STAMP_GROUP :: u64(0x414952504f5254)

airport_structure_is_stamp :: #force_inline proc(structure: terrain.Structure) -> bool {
    return structure.seed == AIRPORT_STAMP_SEED && structure.group_id == AIRPORT_STAMP_GROUP
}

airport_stamp_site_valid :: proc(editor: ^Editor, x, z, yaw: f32) -> bool {
    if editor == nil do return false
    cosine, sine := math.cos(yaw), math.sin(yaw)
    for local_z in ([3]f32{-15, 0, 15}) {
        for local_x in ([3]f32{-21, 0, 21}) {
            sample_x := x + local_x * cosine - local_z * sine
            sample_z := z + local_x * sine + local_z * cosine
            if terrain.sample_surface_height(&editor.project, 0, sample_x, sample_z) <=
               editor.project.sea_level + .35 {
                return false
            }
        }
    }
    return true
}

airport_stamp_add :: proc(editor: ^Editor, x, z, yaw: f32) -> int {
    if editor == nil || !airport_stamp_site_valid(editor, x, z, yaw) do return -1
    marker := terrain.structure_make(x, z, 1, 1, terrain.sample_surface_height(&editor.project, 0, x, z) - 2, 1)
    marker.group_id = AIRPORT_STAMP_GROUP
    marker.rotation = yaw
    index := terrain.add_structure(&editor.project, marker)
    if index >= 0 {
        // add_structure assigns an identity-derived seed; restore the marker tag
        // after insertion so airport stamps remain recognizable when persisted.
        editor.project.structures[index].seed = AIRPORT_STAMP_SEED
    }
    return index
}

airport_stamp_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.airport_stamp_mode {
        if editor != nil do editor.airport_preview_valid = false
        return
    }
    if !cursor_hit {
        editor.airport_preview_valid = false
        return
    }
    snap := f32(4)
    x := f32(math.round(f64(world_x / snap))) * snap
    z := f32(math.round(f64(world_z / snap))) * snap
    editor.airport_preview_x, editor.airport_preview_z = x, z
    editor.airport_preview_valid = airport_stamp_site_valid(editor, x, z, editor.airport_stamp_yaw)
    wheel := canvas2d.GetMouseWheelMove()
    if wheel != 0 {
        editor.airport_stamp_yaw += wheel * math.PI / 12
        editor.airport_preview_valid = airport_stamp_site_valid(editor, x, z, editor.airport_stamp_yaw)
    }
    if canvas2d.IsMouseButtonPressed(.RIGHT) {
        nearest, nearest_distance := -1, f32(48 * 48)
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            if !airport_structure_is_stamp(structure) do continue
            dx, dz := structure.center_x - x, structure.center_z - z
            distance := dx * dx + dz * dz
            if distance < nearest_distance {
                nearest, nearest_distance = index, distance
            }
        }
        if nearest >= 0 {
            structure_history_push_undo(editor)
            _ = terrain.remove_structure(&editor.project, nearest)
            editor.project.revision += 1
        }
        return
    }
    if !canvas2d.IsMouseButtonPressed(.LEFT) || !editor.airport_preview_valid do return
    structure_history_push_undo(editor)
    _ = airport_stamp_add(editor, x, z, editor.airport_stamp_yaw)
    editor.project.revision += 1
}

marina_brush_refresh_preview :: proc(editor: ^Editor, world_x, world_z: f32, reroll: bool) {
    if editor == nil do return
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "marina_brush_refresh_preview")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    if reroll {
        editor.marina_preview_variation += 1
    } else {
        editor.marina_preview_variation = 0
    }
    shoreline := marina.Vec2{world_x, world_z}
    editor.marina_brush_suitability = 0
    editor.marina_brush_attempts = 0
    editor.marina_preview_x, editor.marina_preview_z = world_x, world_z
    editor.marina_preview_valid = false
    editor.marina_preview_plan = {}
    editor.harbor_preview_plan = {}
    editor.harbor_preview_intervention = {}
    seed := u32(abs(int(world_x * 17))) ~ u32(abs(int(world_z * 31))) ~ editor.marina_preview_variation * 0x85ebca6b
    survey_profile := dio.flame_graph_begin(dio.flame_graph_current(), "marina_harbor_survey")
    survey := harbor.survey_coast(&editor.project, {world_x, world_z}, max(editor.marina_brush_radius * 5, f32(420)))
    dio.flame_graph_end(dio.flame_graph_current(), survey_profile)
    program := harbor.derive_harbor_program(.Town, int(editor.marina_brush_radius * 12), seed)
    if survey.site_count == 0 {
        editor.marina_brush_status = .Unsuitable
        return
    }
    harbor_profile := dio.flame_graph_begin(dio.flame_graph_current(), "marina_harbor_generate")
    intervention := harbor.generate_for_survey(&editor.project, &survey, &program, seed)
    harbor_candidate := harbor.finalize_intervention(&intervention)
    dio.flame_graph_end(dio.flame_graph_current(), harbor_profile)
    // The interactive preview ranks every orientation cheaply, then generates
    // only a small set of the best candidates. Full world seeding retains the
    // exhaustive generator.
    plan_profile := dio.flame_graph_begin(dio.flame_graph_current(), "marina_plan_generate")
    candidate, suitability, attempts := markov_marina_generate_world_preview(&editor.project, shoreline, seed)
    dio.flame_graph_end(dio.flame_graph_current(), plan_profile)
    editor.marina_brush_attempts = attempts
    editor.marina_brush_suitability = suitability
    if !candidate.valid || !harbor_candidate.valid {
        editor.marina_brush_status = .No_Valid_Layout
        return
    }
    editor.marina_preview_plan = candidate
    editor.harbor_preview_plan = harbor_candidate
    editor.harbor_preview_intervention = intervention
    editor.marina_preview_valid = true
    editor.marina_brush_status = .Preview
}

marina_brush_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.marina_paint_mode || !cursor_hit do return
    dx, dz := world_x - editor.marina_preview_x, world_z - editor.marina_preview_z
    refresh_distance := editor.marina_brush_radius * .22
    moved := dx * dx + dz * dz > refresh_distance * refresh_distance
    if !editor.marina_preview_valid && editor.marina_brush_status == .Idle || moved {
        marina_brush_refresh_preview(editor, world_x, world_z, false)
    }
    if canvas2d.IsMouseButtonPressed(.RIGHT) {
        marina_brush_refresh_preview(editor, editor.marina_preview_x, editor.marina_preview_z, true)
        return
    }
    if !canvas2d.IsMouseButtonPressed(.LEFT) || !editor.marina_preview_valid do return
    structure_history_push_undo(editor)
    editor.marina_authored_plan = editor.marina_preview_plan
    editor.harbor_authored_plan = editor.harbor_preview_plan
    editor.harbor_authored_intervention = editor.harbor_preview_intervention
    harbor.apply_harbor_terrain(&editor.project, &editor.harbor_authored_intervention)
    editor.marina_authored = true
    editor.marina_preview_valid = false
    editor.project.revision += 1
    editor.marina_brush_status = .Placed
}

farm_generation_score :: proc(plan: ^farmland.Plan) -> f32 {
    if plan == nil || !plan.valid || plan.parcel_count <= 0 do return 0
    crops: [5]bool
    smallest_area, largest_area := 1 << 30, 0
    elongated := 0
    for parcel in plan.parcels[:plan.parcel_count] {
        crops[int(parcel.crop)] = true
        width, depth := parcel.max_x - parcel.min_x, parcel.max_z - parcel.min_z
        area := width * depth
        smallest_area = min(smallest_area, area)
        largest_area = max(largest_area, area)
        if max(width, depth) >= min(width, depth) * 2 do elongated += 1
    }
    crop_count := 0
    for present in crops do if present do crop_count += 1
    diversity := f32(crop_count) / f32(len(crops))
    balance := f32(smallest_area) / f32(max(largest_area, 1))
    shape_mix := 1 - math.abs(f32(elongated) / f32(plan.parcel_count) - .35)
    return clamp(diversity * .46 + balance * .24 + shape_mix * .30, 0, 1)
}

farm_site_score :: proc(editor: ^Editor, origin_x, origin_z, yaw: f32, grid_width, grid_height: int) -> (f32, bool) {
    if editor == nil do return 0, false
    cosine, sine := math.cos(yaw), math.sin(yaw)
    land, clear, samples := 0, 0, 0
    slope_total := f32(0)
    for z_index in -3 ..= 3 {
        for x_index in -4 ..= 4 {
            local_x := f32(x_index) / 4 * f32(grid_width) * farmland.CELL_METERS * .48
            local_z := f32(z_index) / 3 * f32(grid_height) * farmland.CELL_METERS * .48
            x := origin_x + local_x * cosine - local_z * sine
            z := origin_z + local_x * sine + local_z * cosine
            height := terrain.sample_surface_height(&editor.project, 0, x, z)
            if height > editor.project.sea_level + .35 do land += 1
            blocked := terrain.structure_index_at(&editor.project, x, z) >= 0
            for farm in editor.farms[:editor.farm_count] {
                farm_dx, farm_dz := x - farm.origin_x, z - farm.origin_z
                if farm_dx * farm_dx + farm_dz * farm_dz < 68 * 68 {
                    blocked = true
                    break
                }
            }
            pavement := roads.pavement_at(&editor.project.road_graph, {x, height, z})
            if !blocked && !pavement.on_surface do clear += 1
            sample := f32(4)
            rise_x :=
                terrain.sample_surface_height(&editor.project, 0, x + sample, z) -
                terrain.sample_surface_height(&editor.project, 0, x - sample, z)
            rise_z :=
                terrain.sample_surface_height(&editor.project, 0, x, z + sample) -
                terrain.sample_surface_height(&editor.project, 0, x, z - sample)
            slope_total += f32(math.sqrt(f64(rise_x * rise_x + rise_z * rise_z))) / (sample * 2)
            samples += 1
        }
    }
    land_ratio := f32(land) / f32(samples)
    clear_ratio := f32(clear) / f32(samples)
    average_slope := slope_total / f32(samples)
    slope_score := 1 - clamp((average_slope - .04) / .34, 0, 1)
    score := land_ratio * .48 + clear_ratio * .27 + slope_score * .25
    valid := land_ratio >= .94 && clear_ratio >= .88 && average_slope <= .34
    return clamp(score, 0, 1), valid
}

farm_stamp_update_preview :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || !editor.farm_paint_mode || editor.in_map || !cursor_hit {
        if editor != nil do editor.farm_preview_valid = false
        return
    }
    snap := f32(8)
    preview_x := f32(math.round(f64(world_x / snap))) * snap
    preview_z := f32(math.round(f64(world_z / snap))) * snap
    if preview_x != editor.farm_preview_x || preview_z != editor.farm_preview_z {
        dx, dz := preview_x - editor.farm_preview_x, preview_z - editor.farm_preview_z
        if editor.farm_preview_revision != 0 && dx * dx + dz * dz > 1 {
            editor.farm_brush_yaw = math.atan2(dz, dx)
        }
    }
    if preview_x == editor.farm_preview_x &&
       preview_z == editor.farm_preview_z &&
       editor.farm_preview_revision == editor.project.revision {
        return
    }
    editor.farm_preview_x = preview_x
    editor.farm_preview_z = preview_z
    editor.farm_preview_revision = editor.project.revision
    editor.farm_preview_valid = false
    editor.farm_preview_score = 0
    best_score := f32(-1)
    // Keep the chosen procedural variation stable while positioning it.
    // Right-click is the only interaction that advances this seed.
    base_seed := u32(0x4641524d) ~ editor.farm_preview_seed_offset * u32(0x27d4eb2d)
    // Radius controls the major footprint. Preserve the traditional 25:19
    // proportion while generating a genuinely different grid at each size.
    grid_width := clamp(
        int(math.round(f64(editor.farm_brush_radius * 2 / farmland.CELL_METERS))),
        farmland.MIN_GRID_SPAN,
        farmland.MAX_GRID_SPAN,
    )
    grid_height := clamp(
        int(math.round(f64(f32(grid_width) * f32(farmland.GRID_HEIGHT) / f32(farmland.GRID_WIDTH)))),
        farmland.MIN_GRID_SPAN,
        farmland.MAX_GRID_SPAN,
    )
    for orientation in 0 ..< 1 {
        yaw := editor.farm_brush_yaw
        site_score, site_valid := farm_site_score(editor, preview_x, preview_z, yaw, grid_width, grid_height)
        if !site_valid do continue
        for variant in 0 ..< 2 {
            seed := base_seed ~ u32(orientation + 1) * u32(0x85ebca6b) ~ u32(variant + 1) * u32(0xc2b2ae35)
            candidate := farmland.generate_sized(seed, grid_width, grid_height, context.temp_allocator)
            generation_score := farm_generation_score(&candidate)
            combined := site_score * .72 + generation_score * .28
            if combined <= best_score do continue
            best_score = combined
            editor.farm_preview = {
                plan     = candidate,
                origin_x = preview_x,
                origin_z = preview_z,
                yaw      = yaw,
                scale_x  = 1,
                scale_z  = 1,
            }
            editor.farm_preview_valid = true
            editor.farm_preview_score = combined
            editor.farm_preview_site_score = site_score
            editor.farm_preview_generation_score = generation_score
        }
    }
}

farm_brush_process_input :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.farm_paint_mode || !cursor_hit do return
    if canvas2d.IsMouseButtonPressed(.RIGHT) {
        editor.farm_preview_seed_offset += 1
        editor.farm_preview_revision = 0
        editor.farm_preview_valid = false
        return
    }
    if !canvas2d.IsMouseButtonPressed(.LEFT) ||
       editor.farm_count >= FARM_INSTANCE_CAPACITY ||
       !editor.farm_preview_valid {
        return
    }
    structure_history_push_undo(editor)
    editor.farms[editor.farm_count] = editor.farm_preview
    editor.farm_count += 1
    editor.project.revision += 1
    editor.farm_preview_valid = false
}

wreck_site_suitable :: proc(editor: ^Editor, origin_x, origin_z: f32) -> bool {
    if editor == nil do return false
    // Terrain picking returns the surface used by the heightfield, not whether
    // the pointer visually lies on ocean water. Do not reject a wreck based on
    // that sample; wrecks may also be deliberately stranded on a beach.
    for wreck in editor.wrecks[:editor.wreck_count] {
        dx, dz := origin_x - wreck.origin_x, origin_z - wreck.origin_z
        if dx * dx + dz * dz < 380 * 380 do return false
    }
    return true
}

wreck_stamp_update_preview :: proc(editor: ^Editor, world_x, world_z: f32, cursor_hit: bool) {
    if editor == nil || !editor.wreck_paint_mode || editor.in_map || !cursor_hit {
        if editor != nil do editor.wreck_preview_valid = false
        return
    }
    snap := f32(8)
    preview_x := f32(math.round(f64(world_x / snap))) * snap
    preview_z := f32(math.round(f64(world_z / snap))) * snap
    if preview_x != editor.wreck_preview_x || preview_z != editor.wreck_preview_z {
        dx, dz := preview_x - editor.wreck_preview_x, preview_z - editor.wreck_preview_z
        if editor.wreck_preview_revision != 0 && dx * dx + dz * dz > 1 {
            editor.wreck_brush_yaw = math.atan2(dz, dx)
        }
    }
    if preview_x == editor.wreck_preview_x &&
       preview_z == editor.wreck_preview_z &&
       editor.wreck_preview_revision == editor.project.revision {
        return
    }
    editor.wreck_preview_x = preview_x
    editor.wreck_preview_z = preview_z
    editor.wreck_preview_revision = editor.project.revision
    editor.wreck_preview_valid = false
    if !wreck_site_suitable(editor, preview_x, preview_z) do return
    // Position and project edits must not reroll the preview. Only right-click
    // advances the selected procedural variation.
    seed := u32(0x57524543) ~ editor.wreck_preview_seed_offset * u32(0x27d4eb2d)
    editor.wreck_preview, editor.wreck_preview_valid = markov_wreck_generate_instance(
        seed,
        preview_x,
        preview_z,
        editor.wreck_brush_yaw,
        editor.wreck_brush_size / 330,
    )
    if !editor.wreck_preview_valid {
        editor.wreck_preview, editor.wreck_preview_valid = markov_wreck_generate_instance(
            MARKOV_WRECK_DEFAULT_SEED,
            preview_x,
            preview_z,
            editor.wreck_brush_yaw,
            editor.wreck_brush_size / 330,
        )
    }
}

wreck_brush_process_input :: proc(editor: ^Editor, _: f32, _: f32, cursor_hit: bool) {
    if editor == nil || editor.in_map || !editor.wreck_paint_mode || !cursor_hit do return
    if canvas2d.IsMouseButtonPressed(.RIGHT) {
        editor.wreck_preview_seed_offset += 1
        editor.wreck_preview_revision = 0
        editor.wreck_preview_valid = false
        return
    }
    if !canvas2d.IsMouseButtonPressed(.LEFT) ||
       editor.wreck_count >= WRECK_INSTANCE_CAPACITY ||
       !editor.wreck_preview_valid {
        return
    }
    structure_history_push_undo(editor)
    editor.wrecks[editor.wreck_count] = editor.wreck_preview
    editor.wreck_count += 1
    editor.project.revision += 1
    editor.wreck_preview_valid = false
}

plant_stamp_climbing_eligible :: #force_inline proc(kind: terrain.Formation_Kind) -> bool {
    return(
        kind == .Architecture ||
        kind == .Rock ||
        kind == .Spire ||
        kind == .Mountain ||
        kind == .Ridge ||
        kind == .Cliff \
    )
}

plant_stamp_structure_distance_squared :: proc(structure: terrain.Structure, world_x, world_z: f32) -> f32 {
    dx, dz := world_x - structure.center_x, world_z - structure.center_z
    cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
    local_x := dx * cosine + dz * sine
    local_z := -dx * sine + dz * cosine
    outside_x := max(math.abs(local_x) - structure.width * .5, f32(0))
    outside_z := max(math.abs(local_z) - structure.depth * .5, f32(0))
    return outside_x * outside_x + outside_z * outside_z
}

plant_stamp_ray_axis :: #force_inline proc(origin, direction, minimum, maximum: f32, near, far: ^f32) -> bool {
    if math.abs(direction) < 1.0e-6 {
        return origin >= minimum && origin <= maximum
    }
    first, second := (minimum - origin) / direction, (maximum - origin) / direction
    if first > second do first, second = second, first
    near^ = max(near^, first)
    far^ = min(far^, second)
    return near^ <= far^
}

plant_stamp_ray_structure_distance :: proc(
    structure: terrain.Structure,
    origin, direction: third_person.Vec3,
    padding: f32 = 0,
) -> (
    f32,
    bool,
) {
    cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
    dx, dz := origin.x - structure.center_x, origin.z - structure.center_z
    local_origin := third_person.Vec3{dx * cosine + dz * sine, origin.y, -dx * sine + dz * cosine}
    local_direction := third_person.Vec3 {
        direction.x * cosine + direction.z * sine,
        direction.y,
        -direction.x * sine + direction.z * cosine,
    }
    near, far := f32(0), f32(1.0e30)
    if !plant_stamp_ray_axis(
           local_origin.x,
           local_direction.x,
           -structure.width * .5 - padding,
           structure.width * .5 + padding,
           &near,
           &far,
       ) ||
       !plant_stamp_ray_axis(
               local_origin.y,
               local_direction.y,
               structure.base_y,
               structure.base_y + structure.height,
               &near,
               &far,
           ) ||
       !plant_stamp_ray_axis(
               local_origin.z,
               local_direction.z,
               -structure.depth * .5 - padding,
               structure.depth * .5 + padding,
               &near,
               &far,
           ) {
        return 0, false
    }
    return near, far >= 0
}
