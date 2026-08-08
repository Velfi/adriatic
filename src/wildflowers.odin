package main

import architecture "../packages/architecture"
import circulation "../packages/circulation"
import particle_systems "../packages/particles"
import terrain "../packages/terrain"
import "core:math"
import third_person "zelda_engine:third_person"

// Sparse, jittered patch centers make wildflowers locally abundant but keep
// most grass uninterrupted. A fine hash roughens each patch's circular edge.
@(no_instrumentation)
wildflower_density_at :: proc(x, z: f32) -> f32 {
    // Broad cells preserve uninterrupted grass between patches while letting
    // each flower field span a meaningful stretch of terrain.
    CELL :: f32(48)
    cell_x := int(math.floor(f64(x / CELL)))
    cell_z := int(math.floor(f64(z / CELL)))
    density := f32(0)
    for dz in -1 ..= 1 {
        for dx in -1 ..= 1 {
            gx, gz := cell_x + dx, cell_z + dz
            seed := gx * 73856093 + gz * 19349663
            if wind_streak_hash(seed, 40) > .18 do continue
            center_x := (f32(gx) + .16 + wind_streak_hash(seed, 41) * .68) * CELL
            center_z := (f32(gz) + .16 + wind_streak_hash(seed, 42) * .68) * CELL
            radius := 10 + wind_streak_hash(seed, 43) * 10
            px, pz := x - center_x, z - center_z
            distance := f32(math.sqrt(f64(px * px + pz * pz)))
            edge_noise :=
                (wind_streak_hash(
                        int(math.floor(f64(x * .72))) * 83492791 + int(math.floor(f64(z * .72))) * 2971215073,
                        seed,
                    ) -
                    .5) *
                5.2
            density = max(density, clamp((radius + edge_noise - distance) / 4.5, 0, 1))
        }
    }
    return density
}

@(no_instrumentation)
wildflowers_renderable_at :: proc(editor: ^Editor, x, z: f32, prepared_plan: ^circulation.Plan = nil) -> bool {
    if editor == nil do return false
    if settlement_access_point_on_alley_surface(&editor.architecture_city_plan, {x, z}) do return false
    ground_height := terrain.sample_surface_height(&editor.project, 0, x, z)
    if terrain.ground_surface_at(&editor.project, 0, x, z) != .Grass do return false
    local_plan: circulation.Plan
    plan := prepared_plan
    if plan == nil {
        local_plan = architecture.circulation_plan(&editor.project)
        plan = &local_plan
    }
    surface := circulation.surface_at(&editor.project.road_graph, plan, {x, ground_height, z})
    return !surface.on_surface
}

@(no_instrumentation)
coastal_grass_renderable_at :: proc(editor: ^Editor, x, z: f32, prepared_plan: ^circulation.Plan = nil) -> bool {
    if editor == nil do return false
    if settlement_access_point_on_alley_surface(&editor.architecture_city_plan, {x, z}) do return false
    ground_height := terrain.sample_surface_height(&editor.project, 0, x, z)
    material := terrain.sample_material(&editor.project, 0, x, z)
    // Marram colonizes partly stabilized sand before the substrate reads as
    // ordinary inland grass. The later deterministic density gate remains
    // responsible for keeping these transitional areas sparse.
    if !terrain.supports_coastal_grass(material, ground_height, editor.project.sea_level) do return false
    local_plan: circulation.Plan
    plan := prepared_plan
    if plan == nil {
        local_plan = architecture.circulation_plan(&editor.project)
        plan = &local_plan
    }
    surface := circulation.surface_at(&editor.project.road_graph, plan, {x, ground_height, z})
    return !surface.on_surface
}

// Standalone foliage masses use the sixth palette family for their flowering
// crown. Keep the same deterministic choice here so blossom shedding always
// agrees with the tree the renderer presents, without adding mutable per-tree
// state to authored terrain structures.
flowering_tree :: proc(structure: terrain.Structure) -> bool {
    if structure.kind != .Foliage || structure.seed % 6 != 5 do return false
    wide, narrow := max(structure.width, structure.depth), min(structure.width, structure.depth)
    is_forest := wide >= 105 && narrow > 0 && wide / narrow < 1.8 && structure.height >= 58
    is_hedge := narrow > 0 && wide / narrow >= 2.35
    return !is_forest && !is_hedge && structure.height >= terrain.BASE_CELL_SIZE
}

flowering_tree_wind_shedding :: proc(
    editor: ^Editor,
    observer: third_person.Vec3,
) -> (
    origin: third_person.Vec3,
    intensity: f32,
    found: bool,
) {
    if editor == nil do return
    local := atmosphere_local_weather(editor, observer)
    wind := [2]f32{local.wind[0], local.wind[2]}
    wind_speed := f32(math.sqrt(f64(wind[0] * wind[0] + wind[1] * wind[1])))
    // Clear weather remains quiet. The windy preset just crosses the onset,
    // while storms drive a sustained shower rather than an abrupt burst.
    intensity = clamp((wind_speed - 7.5) / 8.5, 0, 1)
    if intensity <= 0 do return

    best_distance_squared := f32(60 * 60)
    for structure in editor.project.structures[:editor.project.structure_count] {
        if !flowering_tree(structure) do continue
        dx, dz := structure.center_x - observer.x, structure.center_z - observer.z
        distance_squared := dx * dx + dz * dz
        if distance_squared >= best_distance_squared do continue
        best_distance_squared = distance_squared
        origin = {structure.center_x, structure.base_y + structure.height * .72, structure.center_z}
        found = true
    }
    if found {
        proximity := 1 - f32(math.sqrt(f64(best_distance_squared))) / 60
        intensity *= clamp(.35 + proximity * .65, 0, 1)
    }
    return
}

wildflower_effects_step :: proc(editor: ^Editor, dt: f32) {
    if editor == nil do return
    if !editor.in_map || dt <= 0 {
        particle_systems.step_petals(&editor.petal_effects, dt, {}, {}, {}, 0)
        return
    }
    origin := editor.player.position
    motion := editor.player.velocity
    disturbance := f32(0)
    if driving_aircraft(editor) {
        body := active_aircraft_body(editor)
        ground := terrain.sample_surface_height(&editor.project, 0, body.position.x, body.position.z)
        height := body.position.y - ground
        origin = {body.position.x, ground, body.position.z}
        motion = {body.velocity.x, body.velocity.y, body.velocity.z}
        speed := f32(math.sqrt(f64(body.velocity.x * body.velocity.x + body.velocity.z * body.velocity.z)))
        disturbance = clamp((9 - height) / 7, 0, 1) * clamp((speed - 8) / 28, 0, 1)
    } else if editor.pilot.mode == .On_Foot && editor.player.grounded {
        speed := f32(math.sqrt(f64(motion.x * motion.x + motion.z * motion.z)))
        disturbance = clamp((speed - 4.5) / 5, 0, 1)
    }
    flower_density := wildflower_density_at(origin.x, origin.z)
    ground_height := terrain.sample_surface_height(&editor.project, 0, origin.x, origin.z)
    circulation_plan := editor_circulation_plan(editor)
    if !wildflowers_renderable_at(editor, origin.x, origin.z, circulation_plan) {
        flower_density = 0
    }
    local := atmosphere_local_weather(editor, origin)
    wind := [2]f32{local.wind[0], local.wind[2]}
    petal_origin := third_person.Vec3{origin.x, ground_height, origin.z}
    petal_motion := motion
    petal_intensity := disturbance * flower_density
    tree_origin, tree_intensity, tree_found := flowering_tree_wind_shedding(editor, origin)
    if tree_found && tree_intensity > petal_intensity {
        petal_origin = tree_origin
        // A detached blossom inherits a little downwind crown velocity before
        // the particle integrator's continuous wind advection takes over.
        petal_motion = {wind[0] * .18, .15, wind[1] * .18}
        petal_intensity = tree_intensity
    }
    particle_systems.step_petals(
        &editor.petal_effects,
        dt,
        {petal_origin.x, petal_origin.y, petal_origin.z},
        {petal_motion.x, petal_motion.y, petal_motion.z},
        {wind[0], 0, wind[1]},
        petal_intensity,
    )
}

configure_wildflower_lab_capture :: proc(editor: ^Editor) {
    // This is an isolated renderer fixture, independent of gameplay-world
    // terrain, circulation, structures, vehicles, and procedural placement.
    editor.capture_world_only = true
    editor.wildflower_lab_scene = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.camera_target_lock = false
    pose := third_person.Camera_Pose {
        position = {-8.4, 2.55, 6.6},
        target   = {1.4, .55, 0},
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    editor.camera_pose = pose
}
