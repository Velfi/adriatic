package main

import particle_systems "../packages/particles"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"

// Sparse, jittered patch centers make wildflowers locally abundant but keep
// most grass uninterrupted. A fine hash roughens each patch's circular edge.
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
        ground := terrain.sample_height(&editor.project, 0, body.position.x, body.position.z)
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
    ground_height := terrain.sample_height(&editor.project, 0, origin.x, origin.z)
    if terrain.ground_surface_at(&editor.project, 0, origin.x, origin.z) != .Grass ||
       ground_height < editor.project.sea_level {
        flower_density = 0
    }
    wind := editor.atmosphere.weather.wind
    particle_systems.step_petals(
        &editor.petal_effects,
        dt,
        {origin.x, ground_height, origin.z},
        {motion.x, motion.y, motion.z},
        {wind[0], 0, wind[1]},
        disturbance * flower_density,
    )
}

configure_wildflower_lab_capture :: proc(editor: ^Editor) {
    // Locate a naturally generated dense patch on grass so the lab exercises
    // the production distribution instead of a capture-only flower bed.
    start := runway_spawn_position(editor)
    best_x, best_z := start.x + 24, start.z + 60
    best_density := f32(-1)
    for gz in -48 ..= 48 {
        for gx in -48 ..= 48 {
            x := start.x + f32(gx) * 2
            z := start.z + 56 + f32(gz) * 2
            density := wildflower_density_at(x, z)
            if density <= best_density do continue
            height := terrain.sample_height(&editor.project, 0, x, z)
            if terrain.ground_surface_at(&editor.project, 0, x, z) != .Grass do continue
            pavement := roads.pavement_at(&editor.project.road_graph, {x = x, y = height, z = z})
            if pavement.on_surface do continue
            best_x, best_z, best_density = x, z, density
        }
    }

    ground := terrain.sample_height(&editor.project, 0, best_x, best_z)
    editor.capture_world_only = true
    editor.postale_visible = false
    editor.libellula_visible = false
    editor.car.position.x += 300
    editor.car.position.z += 300
    editor.player.position = {best_x, ground, best_z}
    editor.player.grounded = true
    editor.pilot.position = editor.player.position
    editor.camera_target_lock = false
    pose := third_person.Camera_Pose {
        position = {best_x - 8.4, ground + 2.55, best_z + 6.6},
        target   = {best_x + 1.4, ground + .55, best_z},
    }
    third_person.camera_set_pose(&editor.cameras, .Inspection, pose)
    third_person.camera_set_active(&editor.cameras, .Inspection)
    editor.camera_pose = pose
}
