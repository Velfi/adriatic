package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import dialogue "../packages/dialogue"
import dialogue_session "../packages/dialogue_session"
import game_input "zelda_engine:game_input"
import harbor "../packages/harbor"
import marina "../packages/marina"
import plants "../packages/plants"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import "core:fmt"
import "core:math"
import "core:strconv"
import sdl "vendor:sdl3"
import canvas2d "zelda_engine:canvas2d"
import physics "zelda_engine:physics"

MARKOV_MARINA_DEFAULT_SEED :: u32(0x4d415249)
MARINA_GEOMETRY_CACHE_DEFAULT_FIRST :: 0
MARINA_GEOMETRY_CACHE_AUTHORED :: MARINA_GEOMETRY_CACHE_DEFAULT_FIRST + len(terrain.DEFAULT_ISLAND_SIGNS)
MARINA_GEOMETRY_CACHE_PREVIEW :: MARINA_GEOMETRY_CACHE_AUTHORED + 1
MARINA_GEOMETRY_CACHE_LAB :: MARINA_GEOMETRY_CACHE_PREVIEW + 1
MARINA_GEOMETRY_CACHE_CAPACITY :: MARINA_GEOMETRY_CACHE_LAB + 1

Marina_Geometry_Cache_Entry :: struct {
    valid:          bool,
    plan:           marina.Plan,
    world_vertices: [dynamic]World_Vertex,
}

markov_marina_plan: marina.Plan
markov_marina_breakwater_focus_active: bool
markov_marina_world_site_score: f32
markov_marina_gallery_active: bool
markov_marina_gallery_plans: [marina.SHORELINE_FORM_COUNT]marina.Plan
markov_marina_gallery_count: int
shoreline_harbor_lab_active: bool
shoreline_harbor_lab_plan: harbor.Harbor_Plan
shoreline_harbor_lab_intervention: harbor.Harbor_Intervention

shoreline_harbor_lab_configure :: proc(editor: ^Editor, index: int) -> bool {
    if editor == nil || index < 0 || index >= 10 do return false
    sign := index < 5 ? f32(-1) : f32(1)
    center, _ := terrain.default_island_center(sign)
    radius := f32(terrain.WORLD_SIZE_METERS * .5) * terrain.DEFAULT_ISLAND_RADIUS
    local_index := index % 5
    // Five distinct aspects on each generated island: channel-facing,
    // crosswind shoulders, outer coast, and an oblique cove search.
    angle := (sign < 0 ? f32(.25) : f32(1.25)) * math.PI + (f32(local_index) - 2) * math.PI * .22
    direction := harbor.Vec2{math.cos(angle), math.sin(angle)}
    approximate := harbor.Vec2{center + direction.x * radius, center + direction.z * radius}
    preferred_scale := f32(170 + (index * 67) % 280)
    seed := u32(0x48415242 + index * 0x9e3779b9)
    role :=
        index % 4 == 0 ? harbor.Settlement_Role.Working_Port : index % 3 == 0 ? harbor.Settlement_Role.Village : harbor.Settlement_Role.Town
    survey := harbor.survey_coast(&editor.project, approximate, max(preferred_scale * 1.7, 420))
    program := harbor.derive_harbor_program(role, 420 + index * 135, seed)
    fallback_site := harbor.select_harbor_site(&editor.project, &survey, &program, seed)
    if !fallback_site.valid do return false
    shoreline_harbor_lab_intervention = harbor.generate_for_survey(&editor.project, &survey, &program, seed)
    accepted := shoreline_harbor_lab_intervention.valid
    site := accepted ? shoreline_harbor_lab_intervention.site : fallback_site
    if accepted {
        harbor.apply_harbor_terrain(&editor.project, &shoreline_harbor_lab_intervention)
        shoreline_harbor_lab_plan = harbor.finalize_intervention(&shoreline_harbor_lab_intervention)
    } else {
        // A rejected intervention is a deliberate untouched-coast result.
        // Keep the lab camera and terrain active without fabricating structures.
        shoreline_harbor_lab_plan = {}
        shoreline_harbor_lab_plan.origin = site.anchor
        shoreline_harbor_lab_plan.tangent = site.tangent
        shoreline_harbor_lab_plan.outward = site.outward
        shoreline_harbor_lab_plan.sea_level = site.sea_level
        shoreline_harbor_lab_plan.office = harbor.add(site.anchor, harbor.scale(site.outward, -18))
        shoreline_harbor_lab_plan.diagnostics.footprint_diameter = site.preferred_scale
        // This is a valid lab display plan with deliberately zero works; the
        // intervention itself remains invalid and cannot enter gameplay.
        shoreline_harbor_lab_plan.valid = true
    }
    shoreline_harbor_lab_active = true
    editor.default_marina_count = 0
    editor.marina_authored = false
    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.boat_traffic = {}
    atmosphere.set_world_minutes(&editor.atmosphere, 9 * 60 + 10)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true
    plan := &shoreline_harbor_lab_plan
    span := plan.diagnostics.footprint_diameter
    target := third_person.Vec3 {
        plan.origin.x + plan.outward.x * span * .22,
        editor.project.sea_level,
        plan.origin.z + plan.outward.z * span * .22,
    }
    eye := third_person.Vec3 {
        target.x - plan.outward.x * span * .62 + plan.tangent.x * span * .28,
        editor.project.sea_level + span * .52,
        target.z - plan.outward.z * span * .62 + plan.tangent.z * span * .28,
    }
    // High, steep backland can otherwise bury a sea-relative inspection
    // camera inside the island and produce an empty horizon-only capture.
    eye.y = max(eye.y, terrain.sample_surface_height(&editor.project, 0, eye.x, eye.z) + span * .14)
    editor.camera_pose = third_person.camera_look_at(eye, target)
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    // Keep terrain clipmap focus on the surveyed coast even when construction
    // is rejected, so the lab shows an untouched shoreline rather than empty
    // ocean around the previous player position.
    player_y := max(
        terrain.sample_surface_height(&editor.project, 0, plan.office.x, plan.office.z) + .7,
        editor.project.sea_level + .7,
    )
    player_place(editor, {plan.office.x, player_y, plan.office.z}, .Scene_Setup)
    return true
}

markov_marina_frontage_target :: proc(target: string) -> (marina.Shoreline_Form, bool) {
    switch target {
    case "natural":
        return .Natural_Shore, true
    case "straight":
        return .Straight_Quay, true
    case "west-apron":
        return .West_Apron, true
    case "east-apron":
        return .East_Apron, true
    case "split-aprons":
        return .Split_Aprons, true
    case "stepped-quays":
        return .Stepped_Quays, true
    }
    return .Natural_Shore, false
}

markov_marina_gallery_generate :: proc() -> bool {
    markov_marina_gallery_plans = {}
    markov_marina_gallery_count = 0
    found: [marina.SHORELINE_FORM_COUNT]bool
    for seed := u32(0); seed < 2048 && markov_marina_gallery_count < marina.SHORELINE_FORM_COUNT; seed += 1 {
        plan := marina.generate(seed, context.temp_allocator)
        if !plan.valid do continue
        form_index := int(plan.shoreline_form)
        if form_index < 0 || form_index >= len(found) || found[form_index] do continue
        column := form_index % 3
        row := form_index / 3
        plan.world_conditioned = true
        plan.world_origin = {(f32(column) - 1) * 125, (f32(row) - .5) * 135}
        plan.world_yaw = 0
        markov_marina_gallery_plans[form_index] = plan
        found[form_index] = true
        markov_marina_gallery_count += 1
    }
    if markov_marina_gallery_count != marina.SHORELINE_FORM_COUNT do return false
    markov_marina_plan = markov_marina_gallery_plans[int(marina.Shoreline_Form.Natural_Shore)]
    return true
}

@(no_instrumentation)
markov_marina_breakwater_random :: #force_inline proc(input: u32) -> f32 {
    value := input
    value = (value ~ (value >> 16)) * 0x7feb352d
    value = (value ~ (value >> 15)) * 0x846ca68b
    value = value ~ (value >> 16)
    return f32(value & 0x00ff_ffff) / f32(0x0100_0000)
}

markov_marina_sample_world_site :: proc(project: ^terrain.Project, origin: marina.Vec2, yaw: f32) -> marina.Site {
    site: marina.Site
    site.enabled = project != nil
    site.origin = origin
    site.yaw = yaw
    if project == nil do return site
    site.sea_level = project.sea_level
    land_threshold := project.sea_level + .15
    for z in 0 ..< marina.GRID_HEIGHT {
        for x in 0 ..< marina.GRID_WIDTH {
            local := marina.grid_position(x, z)
            world := marina.site_world_position(&site, local)
            height := terrain.sample_surface_height(project, 0, world.x, world.z)
            value := height > land_threshold ? marina.Site_Cell.Land : marina.Site_Cell.Water
            if terrain.structure_index_at(project, world.x, world.z) >= 0 {
                value = .Blocked
            } else {
                road := roads.pavement_at(&project.road_graph, {world.x, height, world.z})
                if road.on_surface do value = .Blocked
            }
            marina.set_site_cell(&site, x, z, value)
        }
    }
    for z in 0 ..< marina.GRID_HEIGHT - 1 {
        for x in 0 ..< marina.GRID_WIDTH {
            if marina.site_cell(&site, x, z) == .Land && marina.site_cell(&site, x, z + 1) == .Water {
                marina.set_site_cell(&site, x, z, .Shore)
            }
        }
    }
    return site
}

markov_marina_coarse_world_site_suitability :: proc(project: ^terrain.Project, origin: marina.Vec2, yaw: f32) -> f32 {
    if project == nil do return 0
    probe := marina.Site {
        enabled   = true,
        origin    = origin,
        yaw       = yaw,
        sea_level = project.sea_level,
    }
    threshold := project.sea_level + .15
    backland_good, backland_total := 0, 0
    shore_good, shore_total := 0, 0
    basin_good, basin_total := 0, 0
    entrance_good, entrance_total := 0, 0

    for z := 0; z <= 3; z += 3 {
        for x := 1; x < marina.GRID_WIDTH; x += 4 {
            world := marina.site_world_position(&probe, marina.grid_position(x, z))
            backland_total += 1
            if terrain.sample_surface_height(project, 0, world.x, world.z) > threshold do backland_good += 1
        }
    }
    for x := 1; x < marina.GRID_WIDTH; x += 3 {
        world := marina.site_world_position(&probe, marina.grid_position(x, 4))
        shore_total += 1
        if terrain.sample_surface_height(project, 0, world.x, world.z) <= threshold do shore_good += 1
    }
    for z := 7; z < marina.GRID_HEIGHT; z += 5 {
        for x := 1; x < marina.GRID_WIDTH; x += 4 {
            world := marina.site_world_position(&probe, marina.grid_position(x, z))
            basin_total += 1
            if terrain.sample_surface_height(project, 0, world.x, world.z) <= threshold do basin_good += 1
        }
    }
    for z := 6; z < marina.GRID_HEIGHT; z += 4 {
        world := marina.site_world_position(&probe, marina.grid_position(13, z))
        entrance_total += 1
        if terrain.sample_surface_height(project, 0, world.x, world.z) <= threshold do entrance_good += 1
    }

    backland := f32(backland_good) / f32(max(backland_total, 1))
    shoreline := f32(shore_good) / f32(max(shore_total, 1))
    basin := f32(basin_good) / f32(max(basin_total, 1))
    entrance := f32(entrance_good) / f32(max(entrance_total, 1))
    return clamp(backland * .22 + shoreline * .23 + basin * .35 + entrance * .20, 0, 1)
}

markov_marina_snap_shoreline :: proc(project: ^terrain.Project, anchor, outward: marina.Vec2) -> marina.Vec2 {
    if project == nil do return anchor
    threshold := project.sea_level + .15
    best := anchor
    best_distance := f32(1 << 30)
    previous_offset := f32(-80)
    previous := marina.Vec2{anchor.x + outward.x * previous_offset, anchor.z + outward.z * previous_offset}
    previous_land := terrain.sample_surface_height(project, 0, previous.x, previous.z) > threshold
    for offset := f32(-76); offset <= 80; offset += 4 {
        point := marina.Vec2{anchor.x + outward.x * offset, anchor.z + outward.z * offset}
        land := terrain.sample_surface_height(project, 0, point.x, point.z) > threshold
        if land != previous_land {
            transition_offset := (previous_offset + offset) * .5
            distance := abs(transition_offset)
            if distance < best_distance {
                best = {anchor.x + outward.x * transition_offset, anchor.z + outward.z * transition_offset}
                best_distance = distance
            }
        }
        previous_offset = offset
        previous_land = land
    }
    return best
}

markov_marina_find_world_site :: proc(project: ^terrain.Project, shoreline_anchor: marina.Vec2) -> (marina.Site, f32) {
    best: marina.Site
    best_score := f32(-1)
    shore_to_center := -marina.grid_position(0, 4).z
    for index in 0 ..< 16 {
        yaw := f32(index) * math.TAU / 16
        outward := marina.Vec2{math.sin(yaw), math.cos(yaw)}
        snapped_anchor := markov_marina_snap_shoreline(project, shoreline_anchor, outward)
        origin := marina.Vec2 {
            snapped_anchor.x + outward.x * shore_to_center,
            snapped_anchor.z + outward.z * shore_to_center,
        }
        candidate := markov_marina_sample_world_site(project, origin, yaw)
        score := marina.site_suitability(&candidate)
        if score > best_score {
            best = candidate
            best_score = score
        }
    }
    return best, max(best_score, f32(0))
}

markov_marina_find_shoreline_along_ray :: proc(
    project: ^terrain.Project,
    center, direction: marina.Vec2,
    maximum_distance: f32,
) -> marina.Vec2 {
    if project == nil do return center
    previous := center
    threshold := project.sea_level + .15
    for distance := f32(0); distance <= maximum_distance; distance += f32(4) {
        point := marina.Vec2{center.x + direction.x * distance, center.z + direction.z * distance}
        if terrain.sample_surface_height(project, 0, point.x, point.z) <= threshold do return previous
        previous = point
    }
    return previous
}

markov_marina_generate_valid_for_site :: proc(base_seed: u32, site: ^marina.Site) -> (marina.Plan, int) {
    best: marina.Plan
    for attempt in 0 ..< 32 {
        seed := base_seed + u32(attempt) * 0x9e3779b9
        candidate := marina.generate_for_site(seed, site, context.temp_allocator)
        if candidate.valid do return candidate, attempt + 1
        if attempt == 0 || candidate.site_conformance_badness < best.site_conformance_badness {
            best = candidate
        }
    }
    return best, 32
}

markov_marina_generate_world_plan :: proc(
    project: ^terrain.Project,
    shoreline_anchor: marina.Vec2,
    base_seed: u32,
) -> (
    marina.Plan,
    f32,
    int,
) {
    best: marina.Plan
    best_suitability := f32(-1)
    attempts := 0
    shore_to_center := -marina.grid_position(0, 4).z
    // Spend the same bounded 32-plan budget across the possible shoreline
    // orientations. Curved coasts often give the highest raw site score to an
    // orientation that no generated plan can exactly conform to.
    for variation in 0 ..< 2 {
        for index in 0 ..< 16 {
            yaw := f32(index) * math.TAU / 16
            outward := marina.Vec2{math.sin(yaw), math.cos(yaw)}
            snapped_anchor := markov_marina_snap_shoreline(project, shoreline_anchor, outward)
            origin := marina.Vec2 {
                snapped_anchor.x + outward.x * shore_to_center,
                snapped_anchor.z + outward.z * shore_to_center,
            }
            site := markov_marina_sample_world_site(project, origin, yaw)
            suitability := marina.site_suitability(&site)
            if suitability < MARINA_BRUSH_MINIMUM_SUITABILITY do continue
            seed := base_seed + u32(variation) * u32(0x9e3779b9) + u32(index) * u32(0x85ebca6b)
            candidate := marina.generate_for_site(seed, &site, context.temp_allocator)
            attempts += 1
            if candidate.valid && suitability > best_suitability {
                best = candidate
                best_suitability = suitability
            }
        }
    }
    return best, max(best_suitability, f32(0)), attempts
}

markov_marina_generate_world_preview :: proc(
    project: ^terrain.Project,
    shoreline_anchor: marina.Vec2,
    base_seed: u32,
) -> (
    marina.Plan,
    f32,
    int,
) {
    ORIENTATION_BUDGET :: 2
    CANDIDATE_BUDGET :: 2

    origins: [16]marina.Vec2
    yaws: [16]f32
    coarse_suitabilities: [16]f32
    selected: [16]bool
    shore_to_center := -marina.grid_position(0, 4).z
    for index in 0 ..< len(origins) {
        yaw := f32(index) * math.TAU / f32(len(origins))
        outward := marina.Vec2{math.sin(yaw), math.cos(yaw)}
        snapped_anchor := markov_marina_snap_shoreline(project, shoreline_anchor, outward)
        origin := marina.Vec2 {
            snapped_anchor.x + outward.x * shore_to_center,
            snapped_anchor.z + outward.z * shore_to_center,
        }
        origins[index] = origin
        yaws[index] = yaw
        coarse_suitabilities[index] = markov_marina_coarse_world_site_suitability(project, origin, yaw)
    }

    attempts := 0
    for _ in 0 ..< ORIENTATION_BUDGET {
        best_index := -1
        for index in 0 ..< len(origins) {
            if selected[index] do continue
            if best_index < 0 || coarse_suitabilities[index] > coarse_suitabilities[best_index] {
                best_index = index
            }
        }
        if best_index < 0 || coarse_suitabilities[best_index] < MARINA_BRUSH_MINIMUM_SUITABILITY do break
        selected[best_index] = true
        site := markov_marina_sample_world_site(project, origins[best_index], yaws[best_index])
        suitability := marina.site_suitability(&site)
        if suitability < MARINA_BRUSH_MINIMUM_SUITABILITY do continue
        seed := base_seed + u32(best_index) * u32(0x85ebca6b)
        candidate := marina.generate_for_site_budget(seed, &site, CANDIDATE_BUDGET, context.temp_allocator)
        attempts += 1
        if candidate.valid {
            // Orientations are visited in descending coarse suitability. The
            // first valid result is sufficient for an interactive preview;
            // continuing would add another full site scan to the same frame.
            return candidate, suitability, attempts
        }
    }
    return {}, 0, attempts
}

MARINA_BUOY_RADIUS :: f32(.34)
MARINA_BUOY_MASS :: f32(6)
MARINA_BUOY_WATERLINE_Y :: f32(.08)
MARINA_BUOY_FIXED_STEP :: f64(1.0 / 120.0)

Marina_Buoy_Body :: struct {
    body:        physics.Body_ID,
    berth_index: int,
    anchor:      physics.Vec3,
}

Marina_Buoy_Physics :: struct {
    world:       physics.World,
    bodies:      [marina.SLIP_CAPACITY]Marina_Buoy_Body,
    count:       int,
    accumulator: f64,
}

markov_marina_buoy_physics_destroy :: proc(editor: ^Editor) {
    if editor == nil || editor.marina_buoys.world == nil do return
    for buoy in editor.marina_buoys.bodies[:editor.marina_buoys.count] {
        if buoy.body != physics.INVALID_BODY {
            physics.remove_body(editor.marina_buoys.world, buoy.body)
        }
    }
    editor.marina_buoys = {}
}

markov_marina_buoy_physics_create :: proc(editor: ^Editor) {
    if editor == nil do return
    markov_marina_buoy_physics_destroy(editor)
    if editor.gameplay_physics.world == nil && !gameplay_physics_create(editor) do return
    editor.marina_buoys.world = editor.gameplay_physics.world
    if editor.marina_buoys.world == nil do return
    for berth, berth_index in markov_marina_plan.slips[:markov_marina_plan.slip_count] {
        if berth.kind != .Swing_Mooring do continue
        phase := f32((berth_index * 37 + int(markov_marina_plan.layout_seed & 255)) % 100) / 100
        forward_x, forward_z := math.sin(berth.yaw), math.cos(berth.yaw)
        pickup_offset := f32(0)
        if berth.occupied {
            pickup_offset = boats.specifications(berth.class).length * .5 + .45
        }
        nominal_local := marina.Vec2 {
            berth.position.x - forward_x * pickup_offset,
            berth.position.z - forward_z * pickup_offset,
        }
        nominal := marina.plan_world_position(&markov_marina_plan, nominal_local)
        position := physics.Vec3 {
            nominal.x + math.sin(phase * math.TAU) * .12,
            MARINA_BUOY_WATERLINE_Y + .04,
            nominal.z + math.cos(phase * math.TAU) * .12,
        }
        body := physics.add_sphere(
            editor.marina_buoys.world,
            MARINA_BUOY_RADIUS,
            position,
            .Dynamic,
            MARINA_BUOY_MASS,
            user_data = u64(berth_index + 1),
        )
        if body == physics.INVALID_BODY do continue
        index := editor.marina_buoys.count
        editor.marina_buoys.bodies[index] = {
            body        = body,
            berth_index = berth_index,
            anchor      = {nominal.x, -4.5, nominal.z},
        }
        editor.marina_buoys.count += 1
    }
}

markov_marina_buoy_physics_step :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil ||
       editor.marina_buoys.world == nil ||
       !lab_scene_is_active(editor, "markov-marina") ||
       delta_seconds <= 0 {
        return
    }
    wind_x, wind_z := editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]
    for buoy in editor.marina_buoys.bodies[:editor.marina_buoys.count] {
        position, _, ok := physics.get_transform(editor.marina_buoys.world, buoy.body)
        if !ok do continue
        velocity := physics.get_linear_velocity(editor.marina_buoys.world, buoy.body)
        displacement := MARINA_BUOY_WATERLINE_Y - position[1]
        vertical_force := MARINA_BUOY_MASS * 9.81 + displacement * 120 - velocity[1] * 18

        dx, dz := position[0] - buoy.anchor[0], position[2] - buoy.anchor[2]
        distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
        tether_x, tether_z := f32(0), f32(0)
        if distance > .65 {
            tension := (distance - .65) * 24
            tether_x = -dx / distance * tension
            tether_z = -dz / distance * tension
        }
        physics.add_force(
            editor.marina_buoys.world,
            buoy.body,
            {tether_x - velocity[0] * 5 + wind_x * .16, vertical_force, tether_z - velocity[2] * 5 + wind_z * .16},
        )
    }
}

markov_marina_dockmaster_position :: proc() -> third_person.Vec3 {
    office := markov_marina_plan.office
    world := marina.plan_world_position(&markov_marina_plan, {office.x + 4.6, office.z + 3.5})
    return {world.x, .62, world.z}
}

markov_marina_dinghy_position :: proc() -> third_person.Vec3 {
    office := markov_marina_plan.office
    local := marina.Vec2{office.x + 9.5, marina.grid_position(0, 5).z + 3}
    world := marina.plan_world_position(&markov_marina_plan, local)
    return {world.x, .03, world.z}
}

markov_marina_breakwater_camera :: proc() -> third_person.Camera_Pose {
    selected: marina.Segment
    selected_score := f32(-1)
    for segment in markov_marina_plan.segments[:markov_marina_plan.segment_count] {
        if segment.kind != .Breakwater do continue
        dx, dz := segment.b.x - segment.a.x, segment.b.z - segment.a.z
        length := f32(math.sqrt(f64(dx * dx + dz * dz)))
        diagonal_bonus := abs(dx) > .1 && abs(dz) > .1 ? f32(1000) : f32(0)
        score := diagonal_bonus + max(segment.a.z, segment.b.z) + length * .01
        if score > selected_score {
            selected = segment
            selected_score = score
        }
    }
    a := marina.plan_world_position(&markov_marina_plan, selected.a)
    b := marina.plan_world_position(&markov_marina_plan, selected.b)
    dx, dz := b.x - a.x, b.z - a.z
    length := max(f32(math.sqrt(f64(dx * dx + dz * dz))), f32(.01))
    direction_x, direction_z := dx / length, dz / length
    normal_x, normal_z := -direction_z, direction_x
    focus := third_person.Vec3 {
        b.x - direction_x * min(length * .25, f32(4)),
        .95,
        b.z - direction_z * min(length * .25, f32(4)),
    }
    eye := third_person.Vec3{focus.x + normal_x * 10 - direction_x * 3, 3.6, focus.z + normal_z * 10 - direction_z * 3}
    return third_person.camera_look_at(eye, focus)
}

markov_marina_lab_configure :: proc(editor: ^Editor, target: string) -> bool {
    if editor == nil do return false
    shoreline_harbor_lab_active = false
    shoreline_prefix := "shoreline-"
    if len(target) > len(shoreline_prefix) && target[:len(shoreline_prefix)] == shoreline_prefix {
        if index, ok := strconv.parse_int(target[len(shoreline_prefix):]); ok {
            return shoreline_harbor_lab_configure(editor, index)
        }
        return false
    }
    markov_marina_gallery_active = target == "gallery" || target == "complex"
    frontage_form, frontage_view := markov_marina_frontage_target(target)
    if (markov_marina_gallery_active || frontage_view) && !markov_marina_gallery_generate() do return false
    if frontage_view {
        markov_marina_plan = markov_marina_gallery_plans[int(frontage_form)]
        markov_marina_plan.world_origin = {}
        markov_marina_plan.world_yaw = 0
    }
    seed := MARKOV_MARINA_DEFAULT_SEED
    inner_coast := target == "inner"
    world_conditioned := target == "world" || inner_coast
    if inner_coast {
        seed = u32(0x4d415249 + (len(terrain.DEFAULT_ISLAND_SIGNS) - 1) * 0x9e3779b9)
    }
    if parsed, ok := strconv.parse_int(target); ok && parsed >= 0 && parsed <= 0xffffffff {
        seed = u32(parsed)
    }
    markov_marina_world_site_score = 0
    if markov_marina_gallery_active || frontage_view {
        markov_marina_world_site_score = 0
    } else if world_conditioned {
        half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
        island_center := half_extent * terrain.DEFAULT_ISLAND_OFFSET
        island_radius := half_extent * terrain.DEFAULT_ISLAND_RADIUS
        shoreline_anchor := marina.Vec2{island_center, island_center + island_radius}
        if inner_coast {
            diagonal := f32(.70710678)
            shoreline_anchor = markov_marina_find_shoreline_along_ray(
                &editor.project,
                {island_center, island_center},
                {-diagonal, -diagonal},
                island_radius * 1.8,
            )
        }
        site, score := markov_marina_find_world_site(&editor.project, shoreline_anchor)
        markov_marina_world_site_score = score
        attempts: int
        markov_marina_plan, attempts = markov_marina_generate_valid_for_site(seed, &site)
        fmt.println(
            "markov marina world site: suitability=",
            score,
            " valid=",
            markov_marina_plan.valid,
            " attempts=",
            attempts,
            " conformance_badness=",
            markov_marina_plan.site_conformance_badness,
        )
    } else {
        markov_marina_plan = marina.generate(seed, context.temp_allocator)
    }
    if !markov_marina_plan.valid do return false
    markov_marina_breakwater_focus_active = target == "breakwater"

    editor.in_map = true
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    if !world_conditioned do editor.project.sea_level = 0
    editor.boat_traffic = {}
    editor.marina_dinghy_borrowed = false
    if !markov_marina_gallery_active do markov_marina_buoy_physics_create(editor)

    for slip in markov_marina_plan.slips[:markov_marina_plan.slip_count] {
        if markov_marina_gallery_active do break
        if !slip.occupied do continue
        position := marina.plan_world_position(&markov_marina_plan, slip.position)
        _ = boats.add_moored_agent(
            &editor.boat_traffic,
            slip.class,
            {position.x, position.z},
            marina.plan_world_yaw(&markov_marina_plan, slip.yaw),
        )
    }
    route := markov_marina_plan.route
    if markov_marina_gallery_active do route.count = 0
    if route.count > 1 {
        moving: boats.Agent
        moving.class = .Fishing
        route_start := marina.plan_world_position(&markov_marina_plan, route.points[0])
        moving.position = {route_start.x, route_start.z}
        moving.yaw = markov_marina_plan.world_yaw
        moving.behavior = .Patrol
        moving.schedule[0] = {0, 1440, .Patrol, .52}
        moving.schedule_count = 1
        moving.route_count = min(route.count, boats.ROUTE_CAPACITY)
        for index in 0 ..< moving.route_count {
            point := marina.plan_world_position(&markov_marina_plan, route.points[index])
            moving.route[index] = {point.x, point.z}
        }
        moving.route_index = 1
        _ = boats.append_agent(&editor.boat_traffic, moving)
    }
    for _ in 0 ..< 90 do boats.step(&editor.boat_traffic, .05, 8 * 60 + 20)

    atmosphere.set_world_minutes(&editor.atmosphere, 8 * 60 + 20)
    atmosphere.set_weather_override(&editor.atmosphere, .Clear)
    editor.atmosphere.weather = atmosphere.weather_for(.Clear)
    editor.atmosphere.paused = true

    if markov_marina_gallery_active {
        editor.camera_pose = third_person.camera_look_at(
            {185, editor.project.sea_level + 260, 245},
            {0, editor.project.sea_level, 0},
        )
    } else if target == "mira" {
        dockmaster := markov_marina_dockmaster_position()
        editor.camera_pose = third_person.camera_near(
            {dockmaster.x, dockmaster.y + .48, dockmaster.z},
            {1.35, .62, 1.35},
        )
    } else if target == "breakwater" {
        editor.camera_pose = markov_marina_breakwater_camera()
    } else {
        camera_target_xz := marina.plan_world_position(&markov_marina_plan, {0, 4})
        camera_target := third_person.Vec3{camera_target_xz.x, editor.project.sea_level + .5, camera_target_xz.z}
        camera_local := marina.plan_world_position(&markov_marina_plan, {76, 78})
        editor.camera_pose = third_person.camera_look_at(
            {camera_local.x, editor.project.sea_level + 50, camera_local.z},
            camera_target,
        )
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, editor.camera_pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    dockmaster := markov_marina_dockmaster_position()
    player_place(editor, {dockmaster.x + 1.5, dockmaster.y, dockmaster.z + .4}, .Scene_Setup)
    return true
}

markov_marina_dockmaster_near :: proc(editor: ^Editor) -> bool {
    if editor == nil || !lab_scene_is_active(editor, "markov-marina") || editor.pilot.mode != .On_Foot {
        return false
    }
    delta := editor.player.position - markov_marina_dockmaster_position()
    return delta.x * delta.x + delta.z * delta.z <= 2.5 * 2.5
}

markov_marina_dockmaster_speaker :: proc(_: ^dialogue.Context) -> string {
    return "MIRA"
}

markov_marina_dockmaster_text :: proc(ctx: ^dialogue.Context) -> string {
    if ctx == nil || ctx.data == nil do return "Dobro jutro. Mind les lines und the gulls."
    editor := cast(^Editor)ctx.data
    if editor.marina_dinghy_borrowed {
        return "La little dinghy waits below the quay. Return her con more fuel than excuses."
    }
    return "La basin is calm, the bura is elsewhere, und my little dinghy does zero useful work."
}

markov_marina_borrow_dinghy :: proc(ctx: ^dialogue.Context) {
    if ctx == nil || ctx.data == nil do return
    editor := cast(^Editor)ctx.data
    _ = dialogue_session.set_marina(&editor.dialogue_session, .Borrow_Dinghy)
}

marina_stage_rondine_result :: proc(ctx: ^dialogue.Context) {
    if ctx == nil || ctx.data == nil do return
    editor := cast(^Editor)ctx.data
    _ = dialogue_session.set_marina(&editor.dialogue_session, .Stage_Rondine)
}

markov_marina_close_dialogue :: proc(ctx: ^dialogue.Context) {
    if ctx == nil || ctx.data == nil do return
    editor := cast(^Editor)ctx.data
    _ = dialogue_session.set_marina(&editor.dialogue_session, .Close)
}

open_markov_marina_dockmaster_dialogue :: proc(editor: ^Editor) -> bool {
    if editor == nil || !markov_marina_dockmaster_near(editor) do return false
    attendant_dialogue_definition_release(editor)
    choice_count := editor.marina_dinghy_borrowed ? 2 : 3
    choices := make([]dialogue.Choice, choice_count)
    if editor.marina_dinghy_borrowed {
        choices[0] = dialogue.choice(
            "Stage Rondine outside the breakwater.",
            dialogue.no_next_node,
            effect = marina_stage_rondine_result,
        )
        choices[1] = dialogue.choice(
            "I will bring her back.",
            dialogue.no_next_node,
            effect = markov_marina_close_dialogue,
        )
    } else {
        choices[0] = dialogue.choice(
            "May I borrow the dinghy?",
            dialogue.no_next_node,
            effect = markov_marina_borrow_dinghy,
        )
        choices[1] = dialogue.choice(
            "Stage Rondine outside the breakwater.",
            dialogue.no_next_node,
            effect = marina_stage_rondine_result,
        )
        choices[2] = dialogue.choice(
            "Not today, grazie.",
            dialogue.no_next_node,
            effect = markov_marina_close_dialogue,
        )
    }
    nodes := make([]dialogue.Node, 1)
    nodes[0] = dialogue.node("dockmaster", markov_marina_dockmaster_text, choices, markov_marina_dockmaster_speaker)
    definition := new(dialogue.Definition)
    definition^ = {
        id         = "mira_dockmaster",
        start_node = 0,
        nodes      = nodes,
    }
    conversation, opened := dialogue.open(definition, {data = rawptr(editor), location_id = "markov_marina"})
    if !opened do return false
    dialogue_session.begin(&editor.dialogue_session, .Marina_Dockmaster)
    editor.attendant_dialogue = conversation
    editor.attendant_dialogue_open = true
    editor.attendant_dialogue_focus = 0
    dialogue_view_reset(editor)
    game_input.reset_menu_repeat(&editor.runtime_input)
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
    return true
}

east_marina_plan :: proc(editor: ^Editor) -> ^marina.Plan {
    if editor == nil || editor.default_marina_count <= 0 do return nil
    for index in 0 ..< editor.default_marina_count {
        if editor.default_marina_islands[index] == .East {
            return &editor.default_marinas[index]
        }
    }
    return nil
}

east_harbor_plan :: proc(editor: ^Editor) -> ^harbor.Harbor_Plan {
    if editor == nil || editor.default_marina_count <= 0 do return nil
    for index in 0 ..< editor.default_marina_count {
        if editor.default_marina_islands[index] == .East {
            return &editor.default_harbors[index]
        }
    }
    return nil
}

marin_position :: proc(editor: ^Editor) -> third_person.Vec3 {
    plan := east_harbor_plan(editor)
    if plan == nil do return {}
    world := harbor.add(plan.office, harbor.add(harbor.scale(plan.tangent, 4.6), harbor.scale(plan.outward, 3.5)))
    ground := terrain.sample_surface_height(&editor.project, 0, world.x, world.z)
    return {world.x, max(ground, editor.project.sea_level + .62), world.z}
}

marin_near :: proc(editor: ^Editor) -> bool {
    if editor == nil ||
       !editor.in_map ||
       lab_scene_is_active(editor, "markov-marina") ||
       editor.pilot.mode != .On_Foot ||
       east_marina_plan(editor) == nil {
        return false
    }
    delta := editor.player.position - marin_position(editor)
    return delta.x * delta.x + delta.z * delta.z <= 2.5 * 2.5
}

marin_speaker :: proc(_: ^dialogue.Context) -> string { return "MARIN" }

marin_text :: proc(_: ^dialogue.Context) -> string {
    return "La Rondine is ready, wings clean und motors warm. Io keep her outside the breakwater, ready for il mare."
}

marin_handling_text :: proc(_: ^dialogue.Context) -> string {
    return(
        "Build speed straight, then turn smooth, da. Hold the bank und let the outside wake carry il drift; release before la coast." \
    )
}

open_marin_dialogue :: proc(editor: ^Editor) -> bool {
    if editor == nil || !marin_near(editor) do return false
    attendant_dialogue_definition_release(editor)
    choices := make([]dialogue.Choice, 2)
    choices[0] = dialogue.choice(
        "Stage Rondine in clear water.",
        dialogue.no_next_node,
        effect = marina_stage_rondine_result,
    )
    choices[1] = dialogue.choice("Explain the handling.", 1)
    handling_choices := make([]dialogue.Choice, 2)
    handling_choices[0] = dialogue.choice("Back.", 0)
    handling_choices[1] = dialogue.choice(
        "That is all, grazie.",
        dialogue.no_next_node,
        effect = markov_marina_close_dialogue,
    )
    nodes := make([]dialogue.Node, 2)
    nodes[0] = dialogue.node("rondine-service", marin_text, choices, marin_speaker)
    nodes[1] = dialogue.node("rondine-handling", marin_handling_text, handling_choices, marin_speaker)
    definition := new(dialogue.Definition)
    definition^ = {
        id         = "marin_rondine_service",
        start_node = 0,
        nodes      = nodes,
    }
    conversation, opened := dialogue.open(definition, {data = rawptr(editor), location_id = "east_marina"})
    if !opened do return false
    dialogue_session.begin(&editor.dialogue_session, .Marina_Dockmaster)
    editor.attendant_dialogue = conversation
    editor.attendant_dialogue_open = true
    editor.attendant_dialogue_focus = 0
    dialogue_view_reset(editor)
    game_input.reset_menu_repeat(&editor.runtime_input)
    set_pointer_locked(false)
    _ = sdl.ShowCursor()
    return true
}

markov_marina_process_input :: proc(_: ^Editor) {
    // General on-foot movement and dialogue input remain owned by the shared
    // gameplay loop; this hook reserves a home for marina-specific controls.
}

markov_marina_segment :: proc(source: marina.Segment, plan: ^marina.Plan) {
    segment := source
    segment.a = marina.plan_world_position(plan, segment.a)
    segment.b = marina.plan_world_position(plan, segment.b)
    dx, dz := segment.b.x - segment.a.x, segment.b.z - segment.a.z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= .01 do return
    center := third_person.Vec3{(segment.a.x + segment.b.x) * .5, .18, (segment.a.z + segment.b.z) * .5}
    // world_box_rotated's local +Z axis becomes {-sin(yaw), cos(yaw)}.
    // Negate dx so the rendered body follows the segment centerline instead
    // of mirroring diagonal jetties across the world Z axis.
    yaw := math.atan2(-dx, dz)
    side_x, side_z := dz / length, -dx / length
    color := canvas2d.Color{132, 105, 72, 255}
    height := f32(.42)
    switch segment.kind {
    case .Quay:
        color = {171, 164, 146, 255}
        height = .68
    case .Breakwater:
        color = {131, 132, 126, 255}
        height = 1.25
    case .Natural_Jetty:
        color = {119, 116, 102, 255}
        height = .82
    case .Main_Pier:
        color = {137, 91, 48, 255}
    case .Finger_Pier:
        color = {156, 108, 59, 255}
    }
    // Breakwater endpoints are already explicit centerline coordinates. A
    // width-sized length extension made each diagonal mole overshoot its tip,
    // leaving a bare grey slab beyond the inset crown stones. Keep protective
    // arms endpoint-accurate; timber and quay runs retain their overlap for
    // seamless T-junctions.
    diagonal_main_pier := segment.kind == .Main_Pier && abs(dx) > .01 && abs(dz) > .01
    endpoint_accurate := segment.kind == .Breakwater || segment.kind == .Quay || diagonal_main_pier
    body_length := endpoint_accurate ? length : length + segment.width
    if segment.kind == .Breakwater {
        // Rubble mounds spread below the waterline and narrow to a walkable
        // crown. The trapezoidal section reads as placed armour stone instead
        // of a concrete box floating on the sea.
        world_tapered_box_rotated(
            {center.x, -.05, center.z},
            1.55,
            segment.width,
            body_length,
            segment.width * .32,
            body_length,
            yaw,
            {117, 120, 117, 255},
        )
    } else {
        world_box_rotated(center, {segment.width, height, body_length}, yaw, color)
    }

    if segment.kind == .Main_Pier || segment.kind == .Finger_Pier {
        // A pale deck spine keeps long timber runs readable against dark water.
        deck_length := diagonal_main_pier ? length : length + segment.width * .45
        world_box_rotated(
            {center.x, center.y + height * .5 + .025, center.z},
            {max(segment.width - .34, .45), .05, deck_length},
            yaw,
            segment.kind == .Main_Pier ? canvas2d.Color{178, 125, 72, 255} : canvas2d.Color{190, 141, 84, 255},
        )
        steps := max(int(length / 5), 1)
        for index in 0 ..= steps {
            t := f32(index) / f32(steps)
            x := segment.a.x + dx * t
            z := segment.a.z + dz * t
            world_box({x, -.48, z}, {.28, 1.35, .28}, {78, 57, 40, 255})
        }
    } else if segment.kind == .Quay {
        steps := max(int(length / 8), 1)
        for index in 0 ..= steps {
            t := f32(index) / f32(steps)
            x := segment.a.x + dx * t
            z := segment.a.z + dz * t
            world_box({x, .92, z}, {.44, .52, .44}, {61, 67, 66, 255})
        }
    } else if segment.kind == .Natural_Jetty {
        // Overlapping, uneven stone crowns keep these kinked jetties distinct
        // from engineered breakwater walls and masonry quay blocks.
        steps := max(int(length / 2.6), 2)
        for index in 0 ..< steps {
            t := (f32(index) + .5) / f32(steps)
            x := segment.a.x + dx * t
            z := segment.a.z + dz * t
            offset := index & 1 == 0 ? f32(-.28) : f32(.24)
            crown_x := side_x * offset
            crown_z := side_z * offset
            shade := index % 3 == 0 ? canvas2d.Color{151, 145, 125, 255} : canvas2d.Color{132, 130, 116, 255}
            world_box_rotated(
                {x + crown_x, center.y + height * .5 + .10, z + crown_z},
                {segment.width * .72, .24 + f32(index & 1) * .10, max(length / f32(steps) + .35, .8)},
                yaw + (index & 1 == 0 ? f32(-.05) : f32(.04)),
                shade,
            )
        }
    } else if segment.kind == .Breakwater {
        // Stratified samples avoid accidental bare gaps, while independent
        // lateral, scale, height, and rotation jitter erase visible rows.
        // Large armour blocks should read as individual placed stones. The
        // tapered rubble core below them supplies continuous mass, so the
        // visible crown does not need carpet-like coverage.
        stone_count := max(int(length * segment.width / 4.15), 10)
        along_spacing := length / f32(stone_count)
        segment_seed := u32(abs(int((segment.a.x + 256) * 17 + (segment.a.z + 256) * 31)))
        for index in 0 ..< stone_count {
            seed := plan.layout_seed ~ segment_seed ~ u32(index + 1) * 0x9e3779b9
            along_jitter := (markov_marina_breakwater_random(seed) - .5) * along_spacing * .82
            along := clamp((f32(index) + .5) * along_spacing + along_jitter, .35, length - .35)
            t := along / length
            along_x := segment.a.x + dx * t
            along_z := segment.a.z + dz * t
            lateral_roll := markov_marina_breakwater_random(seed ~ 0x68bc21eb)
            lateral := (lateral_roll * 2 - 1) * segment.width * .48
            stone_x, stone_z := side_x * lateral, side_z * lateral
            toe_fraction := abs(lateral) / max(segment.width * .48, f32(.01))
            size_class_roll := markov_marina_breakwater_random(seed ~ 0x02e5be93)
            size_roll := markov_marina_breakwater_random(seed ~ 0x7f4a7c15)
            depth_roll := markov_marina_breakwater_random(seed ~ 0x967a889b)
            height_roll := markov_marina_breakwater_random(seed ~ 0x4f1bbcdc)
            aspect_roll := markov_marina_breakwater_random(seed ~ 0x846ca68b)
            rotation_roll := markov_marina_breakwater_random(seed ~ 0xb5297a4d)
            tone := u8(134 + int(markov_marina_breakwater_random(seed ~ 0x1b56c4e9) * 20))
            // Armour stone is graded, not uniform. Most pieces form a varied
            // middle course, with visibly smaller chinking stones and a few
            // large anchor blocks. Independent aspect and height rolls stop
            // every boulder from looking like the same model at a new scale.
            rock_scale :=
                size_class_roll < .18 ? .90 + size_roll * .62 : size_class_roll < .80 ? 1.65 + size_roll * 1.42 : 3.25 + size_roll * 1.85
            rock_width := rock_scale * (.78 + aspect_roll * .48)
            rock_depth := rock_scale * (1.18 - aspect_roll * .35) * (.88 + depth_roll * .30)
            rock_height := .38 + rock_scale * (.24 + height_roll * .22)
            world_formation(
                {
                    center_x = along_x + stone_x,
                    center_z = along_z + stone_z,
                    width = rock_width,
                    depth = rock_depth,
                    base_y = .18 + (1 - toe_fraction) * .25,
                    height = rock_height + toe_fraction * .08,
                    rotation = yaw + (rotation_roll * 2 - 1) * .42,
                    color = {tone, tone + 2, tone, 255},
                    kind = .Rock,
                    seed = seed,
                },
            )
        }
    }
}

markov_marina_prop :: proc(source: marina.Prop, plan: ^marina.Plan) {
    prop := source
    prop.position = marina.plan_world_position(plan, prop.position)
    prop.yaw = marina.plan_world_yaw(plan, prop.yaw)
    p := third_person.Vec3{prop.position.x, .7, prop.position.z}
    switch prop.kind {
    case .Lamp:
        world_box({p.x, 1.75, p.z}, {.16, 3.5, .16}, {53, 59, 58, 255})
        world_box({p.x, 3.55, p.z}, {.48, .42, .48}, {218, 178, 98, 255})
    case .Beacon:
        // Navigation beacon with an explicit footing, striped daymark, and
        // lantern housing. The plinth makes support on the mole unambiguous.
        world_box_rotated({p.x, .92, p.z}, {1.35, .42, 1.35}, prop.yaw, {157, 158, 149, 255})
        world_tapered_box_rotated({p.x, 1.72, p.z}, 1.45, .56, .56, .38, .38, prop.yaw, {218, 211, 181, 255})
        world_box({p.x, 2.05, p.z}, {.48, .34, .48}, {184, 61, 46, 255})
        world_box({p.x, 2.62, p.z}, {.34, .55, .34}, {60, 68, 66, 255})
        world_box({p.x, 2.65, p.z}, {.48, .30, .48}, {235, 184, 73, 255})
        world_box({p.x, 2.88, p.z}, {.64, .12, .64}, {55, 62, 61, 255})
    case .Bollard:
        world_box(p, {.48, 1.15, .48}, {66, 70, 69, 255})
    case .Crates:
        world_box_rotated(p, {1.5, 1.25, 1.2}, prop.yaw, {126, 83, 47, 255})
        world_box_rotated({p.x + .65, p.y - .2, p.z + .45}, {.9, .85, .9}, prop.yaw + .12, {151, 101, 56, 255})
    case .Nets:
        world_box_rotated(p, {2.2, .22, 1.4}, prop.yaw, {71, 113, 104, 255})
        world_box({p.x - .7, p.y + .35, p.z}, {.18, .9, .18}, {104, 76, 48, 255})
    }
}

markov_marina_buoy_model :: proc(center: third_person.Vec3, style: int, occupied: bool) {
    SEGMENTS :: 12
    RINGS :: 7
    heights := [RINGS]f32{-.29, -.22, -.08, .10, .25, .33, .38}
    round_radii := [RINGS]f32{.08, .25, .34, .35, .27, .13, .04}
    pear_radii := [RINGS]f32{.07, .22, .36, .32, .22, .10, .03}
    body := occupied ? canvas2d.Color{232, 126, 35, 255} : canvas2d.Color{226, 207, 137, 255}
    band := occupied ? canvas2d.Color{245, 226, 177, 255} : canvas2d.Color{211, 82, 49, 255}
    for ring in 0 ..< RINGS - 1 {
        radius_a := style & 1 == 0 ? round_radii[ring] : pear_radii[ring]
        radius_b := style & 1 == 0 ? round_radii[ring + 1] : pear_radii[ring + 1]
        color := ring == 3 ? band : body
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            angle_a := f32(segment) / f32(SEGMENTS) * math.TAU
            angle_b := f32(next) / f32(SEGMENTS) * math.TAU
            p00 := third_person.Vec3 {
                center.x + math.cos(angle_a) * radius_a,
                center.y + heights[ring],
                center.z + math.sin(angle_a) * radius_a,
            }
            p01 := third_person.Vec3 {
                center.x + math.cos(angle_b) * radius_a,
                center.y + heights[ring],
                center.z + math.sin(angle_b) * radius_a,
            }
            p11 := third_person.Vec3 {
                center.x + math.cos(angle_b) * radius_b,
                center.y + heights[ring + 1],
                center.z + math.sin(angle_b) * radius_b,
            }
            p10 := third_person.Vec3 {
                center.x + math.cos(angle_a) * radius_b,
                center.y + heights[ring + 1],
                center.z + math.sin(angle_a) * radius_b,
            }
            world_quad(p00, p10, p11, p01, color)
        }
    }
    // A galvanized pickup eye distinguishes the model from a generic float.
    metal := canvas2d.Color{106, 114, 109, 255}
    world_box({center.x, center.y + .47, center.z}, {.10, .20, .10}, metal)
    world_box({center.x, center.y + .58, center.z}, {.27, .07, .09}, metal)
    world_box({center.x - .10, center.y + .52, center.z}, {.07, .16, .09}, metal)
    world_box({center.x + .10, center.y + .52, center.z}, {.07, .16, .09}, metal)
}

markov_marina_office_structure :: proc(plan: ^marina.Plan, project: ^terrain.Project = nil) -> terrain.Structure {
    if plan == nil do return {}
    office := marina.plan_world_position(plan, plan.office)
    seed := plan.layout_seed ~ 0x48415242
    base_y := project == nil ? f32(0) : terrain.sample_surface_height(project, 0, office.x, office.z)
    structure := terrain.structure_make(office.x, office.z, 8.2, 6.4, base_y, 4.8)
    // Marina footprints are intentionally more compact than settlement lots.
    // Preserve that footprint after structure_make applies the terrain grid's
    // minimum editing dimensions.
    structure.width = 8.2
    structure.depth = 6.4
    structure.height = 4.8
    structure.rotation = plan.world_yaw
    structure.kind = .Architecture
    structure.seed = seed
    structure.building = architecture.architecture_identity(
        {
            region = .Adriatic,
            tissue = .Harbor,
            density = .42,
            frontage = structure.width,
            depth = structure.depth,
            route = .Waterfront,
            waterfront = true,
            landmark_kind = .Harbor_Office,
        },
        seed,
    )
    structure.color = architecture.architecture_color(seed, true)
    return structure
}

shoreline_harbor_office_structure :: proc(
    plan: ^harbor.Harbor_Plan,
    project: ^terrain.Project = nil,
) -> terrain.Structure {
    if plan == nil do return {}
    seed := plan.seed ~ 0x48415242
    base_y := project == nil ? f32(0) : terrain.sample_surface_height(project, 0, plan.office.x, plan.office.z)
    structure := terrain.structure_make(plan.office.x, plan.office.z, 10, 8, base_y, 5.2)
    structure.width = 10
    structure.depth = 8
    structure.height = 5.2
    structure.rotation = math.atan2(-plan.tangent.x, plan.tangent.z)
    structure.kind = .Architecture
    structure.seed = seed
    structure.building = architecture.architecture_identity(
        {
            region = .Adriatic,
            tissue = .Harbor,
            density = .42,
            frontage = structure.width,
            depth = structure.depth,
            route = .Waterfront,
            waterfront = true,
            landmark_kind = .Harbor_Office,
        },
        seed,
    )
    structure.color = architecture.architecture_color(seed, true)
    return structure
}

world_markov_marina_static_geometry :: proc(plan: ^marina.Plan, project: ^terrain.Project = nil) {
    if plan == nil || !plan.valid do return
    if !plan.world_conditioned {
        extent_x := f32(marina.GRID_WIDTH) * marina.CELL_METERS * .5 + 24
        extent_z := f32(marina.GRID_HEIGHT) * marina.CELL_METERS * .5 + 28
        water_color := canvas2d.Color{38, 111, 139, 255}
        water_cell := f32(8)
        for z := -extent_z; z < extent_z; z += water_cell {
            for x := -extent_x; x < extent_x; x += water_cell {
                world_water_quad(
                    {x, 0, z},
                    {x, 0, z + water_cell},
                    {x + water_cell, 0, z + water_cell},
                    {x + water_cell, 0, z},
                    water_color,
                )
            }
        }

        shore_z := marina.grid_position(0, 3).z
        world_box(
            {0, .20, shore_z - 14},
            {f32(marina.GRID_WIDTH) * marina.CELL_METERS + 12, .8, 32},
            {190, 177, 145, 255},
        )
        world_box(
            {0, .66, marina.grid_position(0, 4).z},
            {f32(marina.GRID_WIDTH) * marina.CELL_METERS, .42, 5.2},
            {170, 164, 149, 255},
        )
    }

    // Shoreline aprons are area geometry, not just their perimeter segments.
    // Render the filled quay cells that project beyond the fixed waterfront so
    // stepped and split frontages match the generator's collision footprint.
    for z in 5 ..= marina.OUTER_SECTION_LIMIT_Z {
        for x in 0 ..< marina.GRID_WIDTH {
            if marina.cell(plan, x, z) != .Quay do continue
            p := marina.plan_world_position(plan, marina.grid_position(x, z))
            shade := (x + z) & 1 == 0 ? canvas2d.Color{174, 168, 151, 255} : canvas2d.Color{164, 160, 147, 255}
            world_box({p.x, .52, p.z}, {marina.CELL_METERS + .08, 1.04, marina.CELL_METERS + .08}, shade)
        }
    }

    for segment in plan.segments[:plan.segment_count] {
        markov_marina_segment(segment, plan)
    }

    office := markov_marina_office_structure(plan, project)
    world_architecture(office, project)

    // Salt-tolerant, generated planting softens the landward office edge
    // without occupying navigable quay cells. Keeping this in presentation
    // code leaves the marina plan and its collision rules product-neutral.
    office_local := plan.office
    for offset, plant_index in ([3]f32{-3.1, 0, 3.1}) {
        local := marina.Vec2{office_local.x + offset, office_local.z - 4.05}
        position := marina.plan_world_position(plan, local)
        world_vertical_prism(
            {position.x, .47, position.z},
            .48,
            .48,
            .68,
            plan.world_yaw + math.PI / 8,
            {151, 91, 58, 255},
        )
        species := plant_index == 1 ? plants.Species.Myrtle : plants.Species.Oleander
        _ = world_generated_plant(
            species,
            u64(plan.layout_seed) + u64(plant_index + 1) * 0x9e3779b97f4a7c15,
            {position.x, .82, position.z},
            plant_index == 1 ? .86 : .78,
            plan.world_yaw + f32(plant_index) * .41,
        )
    }

    for prop in plan.props[:plan.prop_count] {
        markov_marina_prop(prop, plan)
    }
}

world_markov_marina_static_geometry_cached :: proc(plan: ^marina.Plan, project: ^terrain.Project, cache_slot: int) {
    if cache_slot < 0 || cache_slot >= MARINA_GEOMETRY_CACHE_CAPACITY {
        world_markov_marina_static_geometry(plan, project)
        return
    }

    entry := &world_renderer.marina_geometry_cache[cache_slot]
    if entry.valid && entry.plan == plan^ {
        append(&world_renderer.vertices, ..entry.world_vertices[:])
        return
    }

    first := len(world_renderer.vertices)
    world_markov_marina_static_geometry(plan, project)
    clear(&entry.world_vertices)
    if first < len(world_renderer.vertices) {
        append(&entry.world_vertices, ..world_renderer.vertices[first:])
    }
    entry.plan = plan^
    entry.valid = true
}

world_markov_marina_preview_tint :: proc(first: int) {
    preview_color := world_color(canvas2d.Color{128, 211, 166, 255})
    for index in first ..< len(world_renderer.vertices) {
        for channel in 0 ..< 3 {
            world_renderer.vertices[index].color[channel] =
                world_renderer.vertices[index].color[channel] * .58 + preview_color[channel] * .42
        }
    }
}

world_markov_marina_facility :: proc(
    editor: ^Editor,
    plan: ^marina.Plan,
    include_actors: bool,
    cache_slot: int = -1,
    preview: bool = false,
) {
    if editor == nil || plan == nil || !plan.valid do return
    first := len(world_renderer.vertices)
    world_markov_marina_static_geometry_cached(plan, &editor.project, cache_slot)
    if !include_actors {
        for slip, slip_index in plan.slips[:plan.slip_count] {
            position := marina.plan_world_position(plan, slip.position)
            if slip.kind == .Swing_Mooring {
                markov_marina_buoy_model({position.x, .48, position.z}, slip_index, slip.occupied)
            }
            if slip.occupied {
                world_npc_boat(slip.class, {position.x, .18, position.z}, marina.plan_world_yaw(plan, slip.yaw))
            }
        }
        if preview do world_markov_marina_preview_tint(first)
        return
    }

    for buoy, buoy_index in editor.marina_buoys.bodies[:editor.marina_buoys.count] {
        position, _, ok := physics.get_transform(editor.marina_buoys.world, buoy.body)
        if !ok do continue
        berth := markov_marina_plan.slips[buoy.berth_index]
        markov_marina_buoy_model({position[0], position[1], position[2]}, buoy_index, berth.occupied)
    }

    dockmaster := markov_marina_dockmaster_position()
    delta := third_person.Vec3{editor.player.position.x - dockmaster.x, 0, editor.player.position.z - dockmaster.z}
    facing := math.atan2(-delta.x, -delta.z)
    world_mouse_model(
        editor,
        {position = dockmaster, rotation = math.PI - facing, accessory = .Paper_Boat, grounded = false},
    )
    world_mouse_interaction_indicator(editor, dockmaster)

    if editor.marina_dinghy_borrowed {
        dinghy := markov_marina_dinghy_position()
        world_npc_boat(.Dinghy, dinghy, math.PI * .5)
    }

    world_boat_wakes(editor)
    world_renderer.dynamic_caster_first = len(world_renderer.vertices)
    world_npc_boats(editor)
    world_renderer.dynamic_caster_count = len(world_renderer.vertices) - world_renderer.dynamic_caster_first
}

world_shoreline_harbor_facility :: proc(editor: ^Editor, plan: ^harbor.Harbor_Plan, preview: bool = false) {
    if editor == nil || plan == nil || !plan.valid do return
    center_x := (plan.bounds.minimum.x + plan.bounds.maximum.x) * .5
    center_z := (plan.bounds.minimum.z + plan.bounds.maximum.z) * .5
    half_x := (plan.bounds.maximum.x - plan.bounds.minimum.x) * .5
    half_z := (plan.bounds.maximum.z - plan.bounds.minimum.z) * .5
    radius := f32(math.sqrt(f64(half_x * half_x + half_z * half_z))) + 12
    if radius <= 12.01 {
        // Deliberately untouched-coast lab plans carry an origin and diagnostic
        // footprint but no generated bounds.
        center_x, center_z = plan.origin.x, plan.origin.z
        radius = max(plan.diagnostics.footprint_diameter * .5, f32(24))
    }
    if !world_sphere_in_view(editor, {center_x, plan.sea_level + 2, center_z}, radius, 8) do return
    first := len(world_renderer.vertices)
    for path in plan.structures[:plan.structure_count] {
        for point_index in 0 ..< path.count - 1 {
            a, b := path.points[point_index], path.points[point_index + 1]
            dx, dz := b.x - a.x, b.z - a.z
            segment_length := f32(math.sqrt(f64(dx * dx + dz * dz)))
            if segment_length <= .01 do continue
            yaw := math.atan2(-dx, dz)
            center := third_person.Vec3{(a.x + b.x) * .5, editor.project.sea_level + .18, (a.z + b.z) * .5}
            color := canvas2d.Color{142, 101, 57, 255}
            height := f32(.44)
            switch path.kind {
            case .Quay:
                color, height = {171, 164, 146, 255}, .68
            case .Breakwater:
                color, height = {120, 123, 120, 255}, 1.2
            case .Pier:
            case .Natural_Jetty:
                color, height = {119, 116, 102, 255}, .82
            }
            world_box_rotated(center, {path.width, height, segment_length}, yaw, color)
        }
    }
    office := shoreline_harbor_office_structure(plan, &editor.project)
    world_architecture(office, &editor.project)
    for berth, berth_index in plan.berths[:plan.berth_count] {
        if berth.kind == .Swing_Mooring {
            markov_marina_buoy_model(
                {berth.position.x, editor.project.sea_level + .48, berth.position.z},
                berth_index,
                berth.occupied,
            )
        }
        if berth.occupied {
            world_npc_boat(
                berth.class,
                {berth.position.x, editor.project.sea_level + .18, berth.position.z},
                berth.yaw,
            )
        }
    }
    if preview do world_markov_marina_preview_tint(first)
}

world_markov_marina :: proc(editor: ^Editor) {
    if shoreline_harbor_lab_active {
        world_shoreline_harbor_facility(editor, &shoreline_harbor_lab_plan)
        return
    }
    if markov_marina_gallery_active {
        for &plan in markov_marina_gallery_plans {
            world_markov_marina_facility(editor, &plan, false)
        }
        return
    }
    world_markov_marina_facility(editor, &markov_marina_plan, true, MARINA_GEOMETRY_CACHE_LAB)
}

markov_marina_draw_ui :: proc(_: ^Editor, width, height: i32) {
    if shoreline_harbor_lab_active do return
    if markov_marina_breakwater_focus_active do return
    panel := canvas2d.Rectangle {
        x      = 22,
        y      = 22,
        width  = 420,
        height = markov_marina_gallery_active ? 220 : 182,
    }
    canvas2d.DrawRectangleRounded(panel, .12, 8, {10, 27, 37, 226})
    canvas2d.DrawRectangleRoundedLinesEx(panel, .12, 8, 1, {104, 168, 184, 255})
    title: cstring = markov_marina_gallery_active ? "MARINA SHORELINE GALLERY" : "MARKOV MARINA"
    canvas2d.DrawTextEx(canvas2d.Font{}, title, {38, 38}, 20, 1, {245, 238, 197, 255})
    occupied, moorings := 0, 0
    for slip in markov_marina_plan.slips[:markov_marina_plan.slip_count] {
        if slip.occupied do occupied += 1
        if slip.kind == .Swing_Mooring do moorings += 1
    }
    style_name := "FISHING QUAY"
    switch markov_marina_plan.style {
    case .Fishing_Quay:
        style_name = "FISHING QUAY"
    case .Civic_Marina:
        style_name = "CIVIC MARINA"
    case .Island_Harbour:
        style_name = "ISLAND HARBOUR"
    case .Working_Port:
        style_name = "WORKING PORT"
    case .Stone_Cove:
        style_name = "STONE COVE"
    case .Ferry_Quay:
        style_name = "FERRY QUAY"
    case .Boat_Yard:
        style_name = "BOAT YARD"
    case .Lagoon_Marina:
        style_name = "LAGOON MARINA"
    }
    boundary_name := "ENCLOSED BASIN"
    switch markov_marina_plan.boundary_form {
    case .Enclosed_Basin:
        boundary_name = "ENCLOSED BASIN"
    case .Wide_Twin_Moles:
        boundary_name = "WIDE TWIN MOLES"
    case .Offset_West:
        boundary_name = "WEST OFFSET"
    case .Offset_East:
        boundary_name = "EAST OFFSET"
    case .Open_Cove:
        boundary_name = "OPEN COVE"
    }
    frontage_name := "STRAIGHT QUAY"
    switch markov_marina_plan.shoreline_form {
    case .Natural_Shore:
        frontage_name = "NATURAL SHORE"
    case .Straight_Quay:
        frontage_name = "STRAIGHT QUAY"
    case .West_Apron:
        frontage_name = "WEST WORKING APRON"
    case .East_Apron:
        frontage_name = "EAST WORKING APRON"
    case .Split_Aprons:
        frontage_name = "SPLIT WORKING APRONS"
    case .Stepped_Quays:
        frontage_name = "STEPPED QUAYS"
    }
    label := fmt.ctprintf(
        "%s / %s   SEED %d.%d/%d   %d/%d BERTHS (%d MOORINGS)",
        style_name,
        boundary_name,
        int(markov_marina_plan.seed),
        markov_marina_plan.candidate_index + 1,
        markov_marina_plan.candidates_evaluated,
        occupied,
        markov_marina_plan.slip_count,
        moorings,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, label, {38, 68}, 13, 1, {208, 239, 240, 255})
    frontage_label := fmt.ctprintf("QUAY FRONTAGE %s", frontage_name)
    canvas2d.DrawTextEx(canvas2d.Font{}, frontage_label, {38, 86}, 13, 1, {196, 215, 208, 255})
    spacing_label := fmt.ctprintf(
        "STRUCTURE %.0f%%   SPACING BADNESS %.3f",
        markov_marina_plan.spacing_density * 100,
        markov_marina_plan.spacing_badness_density,
    )
    spacing_color := canvas2d.Color{174, 220, 185, 255}
    if markov_marina_plan.spacing_badness_density > .35 {
        spacing_color = {245, 132, 104, 255}
    }
    canvas2d.DrawTextEx(canvas2d.Font{}, spacing_label, {38, 104}, 13, 1, spacing_color)
    berth_label := fmt.ctprintf("BERTH SPACING BADNESS %.3f", markov_marina_plan.berth_spacing_badness)
    berth_color := canvas2d.Color{174, 220, 185, 255}
    if markov_marina_plan.berth_spacing_badness > 0 {
        berth_color = {245, 132, 104, 255}
    }
    canvas2d.DrawTextEx(canvas2d.Font{}, berth_label, {38, 122}, 13, 1, berth_color)
    fill_label := fmt.ctprintf(
        "LANE-FIRST FILL %.0f%% / %.0f%% TARGET",
        markov_marina_plan.fill_density * 100,
        markov_marina_plan.target_fill_density * 100,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, fill_label, {38, 140}, 13, 1, {180, 207, 225, 255})
    quality_label := fmt.ctprintf(
        "GENERATION QUALITY %.3f   TARGET ERROR %.1f%%",
        markov_marina_plan.generation_quality,
        markov_marina_plan.fill_density_error * 100,
    )
    canvas2d.DrawTextEx(canvas2d.Font{}, quality_label, {38, 158}, 13, 1, {215, 194, 151, 255})
    overlap_label := fmt.ctprintf("HULL / STRUCTURE OVERLAP %.3f", markov_marina_plan.structure_overlap_badness)
    overlap_color := canvas2d.Color{174, 220, 185, 255}
    if markov_marina_plan.structure_overlap_badness > 0 {
        overlap_color = {245, 132, 104, 255}
    }
    canvas2d.DrawTextEx(canvas2d.Font{}, overlap_label, {38, 176}, 13, 1, overlap_color)
    if markov_marina_gallery_active {
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            "NATURAL  /  STRAIGHT  /  WEST APRON",
            {38, 196},
            12,
            1,
            {208, 239, 240, 255},
        )
        canvas2d.DrawTextEx(
            canvas2d.Font{},
            "EAST APRON  /  SPLIT APRONS  /  STEPPED QUAYS",
            {38, 214},
            12,
            1,
            {208, 239, 240, 255},
        )
    }
    _ = width
    _ = height
}
