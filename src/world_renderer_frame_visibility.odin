package main
import "core:fmt"
import "core:math"
import "core:testing"
import "core:time"

import dio "../packages/dio"
import particles "../packages/particles"
import third_person "../packages/third_person"
import "core:math/linalg"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"

world_frame_build_transient :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_frame_build_transient_dynamic")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    world_structure_storage_ensure(editor.project.structure_count)
    clear(&world_renderer.vertices)
    clear(&world_renderer.late_transparent_vertices)
    clear(&world_renderer.wing_trail_vertices)
    clear(&world_renderer.wing_trail_indices)
    clear(&world_renderer.wing_trail_optimized_indices)
    clear(&world_renderer.road_vertices)
    clear(&world_renderer.foliage_vertices)
    clear(&world_renderer.bougainvillea_vertices)
    clear(&world_renderer.bougainvillea_instances)
    if world_renderer.grass_stream_dirty {
        clear(&world_renderer.grass_instances)
        clear(&world_renderer.wildflower_instances)
        clear(&world_renderer.marsh_instances)
        for _, chunk in world_renderer.grass_chunk_cache do chunk.stream_emitted = false
        world_renderer.grass_stream_dirty = false
    }
    clear(&world_renderer.terrain_particle_vertices)
    world_renderer.structure_lod_counts = {}
    world_renderer.structure_lod_world_vertices = 0
    world_renderer.structure_lod_foliage_vertices = 0
    world_renderer.player_vertex_first = 0
    world_renderer.player_vertex_count = 0
    world_renderer.dynamic_caster_first = 0
    world_renderer.dynamic_caster_count = 0
    clear(&world_renderer.explicit_shadow_caster_ranges)
    clear(&world_renderer.static_shadow_caster_ranges)
    world_renderer.late_transparent_first = 0
    world_renderer.late_transparent_count = 0
    world_renderer.scene_daylight = atmosphere_sky(editor).daylight
    if menu_scene_current(editor) == .Customization {
        // The customization screen gets a purpose-built miniature world pass.
        // It uses the exact gameplay model and materials, rather than maintaining
        // a second approximation of the mouse in the UI layer.
        world_ellipsoid_rotated({0, -.08, 0}, .72, .08, .72, 0, {40, 58, 61, 255})
        world_ellipsoid_rotated({0, -.025, 0}, .60, .035, .60, 0, {77, 112, 111, 255})
        world_mouse_model(
            editor,
            {
                position = {0, 0, 0},
                rotation = editor.customization_preview_yaw + .65,
                accessory = editor.mouse_headgear,
                fur = editor.mouse_fur,
                pattern = editor.mouse_pattern,
                scarf_enabled = editor.mouse_scarf_enabled,
                scarf_color = editor.mouse_scarf_color,
                preview = true,
                player_controlled = true,
                grounded = false,
            },
        )
        return
    }
    if editor.vehicle_showcase_scene {
        world_vehicle_showcase(editor)
        return
    }
    if lab_scene_draw_world(editor) {
        // Replacement labs return before the ordinary world tail, but their
        // emissive halos, light pools, and beam sheets still need the same
        // late transparent submission used by gameplay worlds.
        if world_renderer.dynamic_caster_count <= 0 && len(world_renderer.explicit_shadow_caster_ranges) == 0 {
            world_register_shadow_caster(0)
        }
        world_renderer.late_transparent_first = len(world_renderer.vertices)
        append(&world_renderer.vertices, ..world_renderer.late_transparent_vertices[:])
        world_renderer.late_transparent_count = len(world_renderer.vertices) - world_renderer.late_transparent_first
        return
    }
    // Depth testing makes submission order independent. Put authored gameplay
    // meshes first so dense terrain can consume only the remaining capacity
    // instead of silently dropping vehicles at the end of the frame.
    profile_water := dio.flame_graph_begin(dio.flame_graph_current(), "world_transient_water")
    world_ocean(editor)
    world_bathymetry(editor)
    world_river_water(editor)
    dio.flame_graph_end(dio.flame_graph_current(), profile_water)
    profile_infrastructure := dio.flame_graph_begin(dio.flame_graph_current(), "world_transient_infrastructure")
    infrastructure_shadow_first := len(world_renderer.vertices)
    for index in 0 ..< editor.default_marina_count {
        world_shoreline_harbor_facility(editor, &editor.default_harbors[index])
    }
    if editor.marina_authored {
        world_shoreline_harbor_facility(editor, &editor.harbor_authored_plan)
    }
    if editor.marina_paint_mode && editor.marina_preview_valid {
        world_shoreline_harbor_facility(editor, &editor.harbor_preview_plan, true)
    }
    world_register_shadow_caster(infrastructure_shadow_first)
    dio.flame_graph_end(dio.flame_graph_current(), profile_infrastructure)
    profile_settlement := dio.flame_graph_begin(dio.flame_graph_current(), "world_transient_settlement")
    world_roads_transient(editor)
    world_boat_wakes(editor)
    world_ocean_ship_wake(editor)
    world_city_density_overlay(editor)
    world_climbing_leaf_density_overlay(editor)
    dio.flame_graph_end(dio.flame_graph_current(), profile_settlement)
    // The player and vehicles are gameplay-critical. Submit them before any
    // capacity-limited environment detail so a dense scene can never cull the
    // controlled character or the vehicle they occupy. Keeping all vehicles
    // in this protected group also prevents an enter/exit transition from
    // exposing a one-frame ordering gap.
    world_renderer.dynamic_caster_first = len(world_renderer.vertices)
    profile_npcs := dio.flame_graph_begin(dio.flame_graph_current(), "world_transient_npcs")
    world_npc_boats(editor)
    world_ocean_ship(editor)
    world_bird_flocks(editor)
    world_aircraft(editor)
    world_bomber_drops(editor)
    world_car(editor)
    world_car_pilot(editor)
    world_renderer.player_vertex_first = len(world_renderer.vertices)
    world_character(editor)
    world_renderer.player_vertex_count = len(world_renderer.vertices) - world_renderer.player_vertex_first
    world_postale_pilot(editor)
    world_rondine_pilot(editor)
    // Persistent characters and their interaction landmarks must be submitted
    // before the capacity-limited procedural town and vegetation passes.
    world_attendant_kiosk(editor)
    world_marta(editor)
    world_gerta(editor)
    world_marin(editor)
    world_lighthouse_keepers(editor)
    world_town_mice(editor)
    world_settlement_inhabitants(editor, true, false)
    dio.flame_graph_end(dio.flame_graph_current(), profile_npcs)
    profile_authored := dio.flame_graph_begin(dio.flame_graph_current(), "world_transient_authored_decorations")
    world_settlement_patios(editor)
    world_settlement_cemetery(editor, false)
    world_authored_farmland(editor, false)
    world_authored_wrecks(editor, false)
    dio.flame_graph_end(dio.flame_graph_current(), profile_authored)
    profile_overlays := dio.flame_graph_begin(dio.flame_graph_current(), "world_transient_overlays")
    lab_scene_draw_world_overlay(editor)
    dio.flame_graph_end(dio.flame_graph_current(), profile_overlays)
    world_renderer.dynamic_caster_count = len(world_renderer.vertices) - world_renderer.dynamic_caster_first
    world_structures(editor)
    profile_vegetation := dio.flame_graph_begin(dio.flame_graph_current(), "world_transient_vegetation")
    world_ground_grass(editor)
    dio.flame_graph_end(dio.flame_graph_current(), profile_vegetation)
    world_renderer.player_shadow_receiver = mouse_surface_height(
        editor,
        editor.player.position.x,
        editor.player.position.z,
    )
    // Road Planning owns its endpoint markers and route preview. The ordinary
    // terrain brush is unrelated here and otherwise reads as a third marker.
    if !lab_scene_is_active(editor, "road-planning") && !lab_scene_is_active(editor, "road-pathing") do world_brush(editor)
    profile_effects := dio.flame_graph_begin(dio.flame_graph_current(), "world_transient_effects")
    world_vehicle_particles(editor)
    world_player_terrain_particles(editor)
    world_petal_particles(editor)
    world_wing_trails(editor)
    world_rondine_wake_fans(editor)
    world_wind_streaks(editor)
    world_fog_shells(editor)
    dio.flame_graph_end(dio.flame_graph_current(), profile_effects)
    // Keep transparent municipal pools contiguous at the end of the existing
    // world buffer. The render graph submits this range only after roads and
    // foliage have established receiver depth.
    world_renderer.late_transparent_first = len(world_renderer.vertices)
    append(&world_renderer.vertices, ..world_renderer.late_transparent_vertices[:])
    world_renderer.late_transparent_count = len(world_renderer.vertices) - world_renderer.late_transparent_first
}

world_chunks_update_dirty :: proc(editor: ^Editor) {
    started := time.tick_now()
    was_dirty := world_renderer.retained_static_dirty
    world_spatial_sync_structures(editor)
    world_retained_static_repack()
    if was_dirty {
        world_renderer.rebuilt_static_objects += u64(len(world_renderer.retained_static_draws))
    }
    world_renderer.dirty_build_ms = time.duration_seconds(time.tick_since(started)) * 1000
}

world_retained_visibility_begin :: proc(editor: ^Editor) {
    profile := dio.flame_graph_begin(dio.flame_graph_current(), "world_retained_visibility_begin")
    defer dio.flame_graph_end(dio.flame_graph_current(), profile)
    clear(&world_renderer.retained_static_draws)
    clear(&world_renderer.road_draw_commands)
    if editor == nil ||
       menu_scene_current(editor) == .Customization ||
       editor.vehicle_showcase_scene ||
       lab_scene_replaces_world(editor) {
        return
    }
    world_retained_roads_prepare(editor)
}

world_visibility_build_cpu :: proc() {
    started := time.tick_now()
    world_static_indirect_commands_build()
    world_renderer.indexed_cells = u64(len(world_renderer.spatial_index.cells))
    world_renderer.visible_clusters = u64(
        len(world_renderer.static_draw_commands) + len(world_renderer.road_draw_commands),
    )
    world_renderer.indirect_command_count = world_renderer.visible_clusters
    world_renderer.visibility_build_cpu_ms = time.duration_seconds(time.tick_since(started)) * 1000
}

world_prepare :: proc(editor: ^Editor, cmd: vk.CommandBuffer, frame_index: int) {
    world_renderer.dirty_build_ms = 0
    world_renderer.frame_build_ms = 0
    world_renderer.visibility_build_cpu_ms = 0
    world_renderer.texture_upload_ms = 0
    world_renderer.indexed_cells = 0
    world_renderer.visible_clusters = 0
    world_renderer.indirect_command_count = 0
    world_renderer.dynamic_vertex_uploaded = false

    texture_started := time.tick_now()
    if world_renderer.material_lab_map_revision != material_lab.map_revision {
        if !material_lab_gpu_maps_reload(world_renderer.ctx) {
            fmt.eprintln("material lab GPU maps failed to reload")
        }
    }
    vehicle_paint_atlas_flush(editor, cmd, frame_index)
    world_renderer.texture_upload_ms = time.duration_seconds(time.tick_since(texture_started)) * 1000

    // Retained geometry owns its cache maintenance and visible draw list.
    // The transient build may reference retained structure entries, but no
    // longer rebuilds or gathers the retained road stream.
    if world_renderer.retained_static_dirty do world_renderer.retained_patio_dirty = true
    world_retained_patio_rebuild(editor)
    world_retained_visibility_begin(editor)

    dynamic_started := time.tick_now()
    world_frame_build_transient(editor)
    world_renderer.frame_build_ms = time.duration_seconds(time.tick_since(dynamic_started)) * 1000
    world_chunks_update_dirty(editor)
    world_visibility_build_cpu()
}

world_benchmark_static_counters_reset :: proc() {
    world_renderer.rebuilt_static_objects = 0
    world_renderer.rebuilt_static_pages = 0
    world_renderer.static_bytes_uploaded = 0
}

world_bomber_drops :: proc(editor: ^Editor) {
    if editor == nil do return
    for drop in editor.bomber_drops[:editor.bomber_drop_count] {
        // Airborne drops may be behind the downward-facing bomber camera while
        // simultaneously centered in the PiP chase camera. With only a few
        // bounded payloads, retaining them is cheaper and more reliable than
        // culling solely against the primary view.
        if drop.landed && !world_sphere_in_view(editor, drop.position, f32(2.5)) do continue
        payload_color := canvas2d.Color{218, 187, 124, 255}
        payload_size := third_person.Vec3{.55, .34, .44}
        switch drop.kind {
        case .Mail:
            payload_color = {194, 104, 82, 255}
            payload_size = {.48, .18, .34}
        case .Parcel:
            payload_color = {205, 166, 101, 255}
        case .Supplies:
            payload_color = {80, 130, 112, 255}
            payload_size = {.72, .48, .58}
        }
        world_box(drop.position, payload_size, payload_color)
        if drop.kind == .Mail {
            world_box(
                {drop.position.x, drop.position.y + .105, drop.position.z},
                {.36, .025, .25},
                {238, 224, 184, 255},
            )
        }
        if !drop.parachute_open || drop.landed do continue
        canopy_center := third_person.Vec3{drop.position.x, drop.position.y + 1.75, drop.position.z}
        canopy_color := canvas2d.Color{235, 218, 166, 255}
        if drop.kind == .Mail do canopy_color = {224, 108, 90, 255}
        if drop.kind == .Supplies do canopy_color = {102, 151, 125, 255}
        world_ellipsoid_rotated(canopy_center, 1.18, .28, 1.18, 0, canopy_color)
        cord_color := canvas2d.Color{222, 213, 183, 255}
        anchors := [4]third_person.Vec3 {
            {canopy_center.x - .82, canopy_center.y - .05, canopy_center.z},
            {canopy_center.x + .82, canopy_center.y - .05, canopy_center.z},
            {canopy_center.x, canopy_center.y - .05, canopy_center.z - .82},
            {canopy_center.x, canopy_center.y - .05, canopy_center.z + .82},
        }
        for anchor in anchors {
            world_box_between(anchor, drop.position, {0, 0, 1}, .018, .018, cord_color)
        }
    }
}

world_petal_particles :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    palette := [5]canvas2d.Color {
        {246, 201, 70, 235},
        {242, 121, 151, 235},
        {199, 151, 229, 225},
        {248, 238, 210, 230},
        {218, 78, 105, 230},
    }
    for particle in editor.petal_effects.particles[:editor.petal_effects.count] {
        if !world_sphere_in_view(
            editor,
            {particle.position.x, particle.position.y, particle.position.z},
            max(particle.size * 2, f32(.25)),
        ) {
            continue
        }
        display := particles.Vehicle_Particle {
            position = particle.position,
            velocity = particle.velocity,
            life     = particle.life,
            max_life = particle.max_life,
            size     = particle.size,
            seed     = particle.seed,
        }
        world_vehicle_particle(camera, display, palette[int(particle.seed % u32(len(palette)))], -1)
    }
}

customization_preview_camera_pose :: proc() -> third_person.Camera_Pose {
    return {position = {2.24, 1.10, 2.77}, target = {1.86, .38, 0}}
}

world_vehicle_particle :: proc(
    camera: Perspective_Camera,
    particle: particles.Vehicle_Particle,
    color: canvas2d.Color,
    opacity_override: f32 = -1,
) {
    fade := clamp(particle.life / particle.max_life, 0, 1)
    age := 1 - fade
    rotation := particle.seed & 3
    cosine, sine := f32(1), f32(0)
    switch rotation {
    case 1:
        cosine, sine = .92388, .38268
    case 2:
        cosine, sine = .70711, .70711
    case 3:
        cosine, sine = .38268, .92388
    }
    width := particle.size * (.82 + f32((particle.seed >> 3) & 3) * .07) * (.78 + age * .46)
    height := particle.size * (.62 + f32((particle.seed >> 5) & 3) * .08) * (.78 + age * .46)
    right := third_person.Vec3 {
        (camera.right.x * cosine + camera.up.x * sine) * width,
        (camera.right.y * cosine + camera.up.y * sine) * width,
        (camera.right.z * cosine + camera.up.z * sine) * width,
    }
    up := third_person.Vec3 {
        (-camera.right.x * sine + camera.up.x * cosine) * height,
        (-camera.right.y * sine + camera.up.y * cosine) * height,
        (-camera.right.z * sine + camera.up.z * cosine) * height,
    }
    p := third_person.Vec3{particle.position.x, particle.position.y, particle.position.z}
    opacity := opacity_override < 0 ? fade : clamp(opacity_override, 0, 1)
    alpha := u8(f32(color.a) * opacity)
    shade := canvas2d.Color{color.r, color.g, color.b, alpha}
    world_quad(
        {p.x - right.x - up.x, p.y - right.y - up.y, p.z - right.z - up.z},
        {p.x + right.x - up.x, p.y + right.y - up.y, p.z + right.z - up.z},
        {p.x + right.x + up.x, p.y + right.y + up.y, p.z + right.z + up.z},
        {p.x - right.x + up.x, p.y - right.y + up.y, p.z - right.z + up.z},
        shade,
    )
}

world_terrain_particle :: proc(camera: Perspective_Camera, particle: particles.Vehicle_Particle) {
    fade := clamp(particle.life / max(particle.max_life, f32(.001)), 0, 1)
    age := 1 - fade
    angle := f32(particle.seed & 7) * math.PI / 16
    cosine, sine := math.cos(angle), math.sin(angle)
    half_size := particle.size * (1.05 + age * .30)
    right := third_person.Vec3 {
        (camera.right.x * cosine + camera.up.x * sine) * half_size,
        (camera.right.y * cosine + camera.up.y * sine) * half_size,
        (camera.right.z * cosine + camera.up.z * sine) * half_size,
    }
    up := third_person.Vec3 {
        (-camera.right.x * sine + camera.up.x * cosine) * half_size,
        (-camera.right.y * sine + camera.up.y * cosine) * half_size,
        (-camera.right.z * sine + camera.up.z * cosine) * half_size,
    }
    p := third_person.Vec3{particle.position.x, particle.position.y, particle.position.z}
    p0 := third_person.Vec3{p.x - right.x - up.x, p.y - right.y - up.y, p.z - right.z - up.z}
    p1 := third_person.Vec3{p.x + right.x - up.x, p.y + right.y - up.y, p.z + right.z - up.z}
    p2 := third_person.Vec3{p.x + right.x + up.x, p.y + right.y + up.y, p.z + right.z + up.z}
    p3 := third_person.Vec3{p.x - right.x + up.x, p.y - right.y + up.y, p.z - right.z + up.z}

    column := int(particle.seed % 8)
    row := clamp(int(particle.surface), 0, 5)
    // The generated atlas is 1448 x 1086: exactly 8 x 6 cells of 181 px.
    // A two-pixel inset keeps bilinear sampling away from adjacent variants.
    inset_u, inset_v := f32(2.0 / 1448.0), f32(2.0 / 1086.0)
    u0 := f32(column) / 8 + inset_u
    u1 := f32(column + 1) / 8 - inset_u
    v0 := f32(row) / 6 + inset_v
    v1 := f32(row + 1) / 6 - inset_v
    tint := [4]f32{1, 1, 1, fade * fade}
    append(
        &world_renderer.terrain_particle_vertices,
        Foliage_Vertex{{p0.x, p0.y, p0.z}, {u0, v1}, tint, 3},
        Foliage_Vertex{{p1.x, p1.y, p1.z}, {u1, v1}, tint, 3},
        Foliage_Vertex{{p2.x, p2.y, p2.z}, {u1, v0}, tint, 3},
        Foliage_Vertex{{p0.x, p0.y, p0.z}, {u0, v1}, tint, 3},
        Foliage_Vertex{{p2.x, p2.y, p2.z}, {u1, v0}, tint, 3},
        Foliage_Vertex{{p3.x, p3.y, p3.z}, {u0, v0}, tint, 3},
    )
}

world_vehicle_particles :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for particle in editor.vehicle_effects.dust[:editor.vehicle_effects.dust_count] {
        if !world_sphere_in_view(
            editor,
            {particle.position.x, particle.position.y, particle.position.z},
            max(particle.size * 2, f32(.25)),
        ) {
            continue
        }
        world_terrain_particle(camera, particle)
    }
}

world_player_terrain_particles :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for particle in editor.player_terrain_effects.dust[:editor.player_terrain_effects.dust_count] {
        if !world_sphere_in_view(
            editor,
            {particle.position.x, particle.position.y, particle.position.z},
            max(particle.size * 2, f32(.25)),
        ) {
            continue
        }
        world_terrain_particle(camera, particle)
    }
}

world_wing_trails :: proc(editor: ^Editor) {
    if editor.wing_trails.count <= 0 do return
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for side in 0 ..< 2 {
        first_ring := len(world_renderer.wing_trail_vertices)
        ring_count := 0
        for particle in editor.wing_trails.particles[:editor.wing_trails.count] {
            if int(particle.side) != side do continue
            // Sparse deterministic breaks keep long, fast trails from
            // becoming rigid continuous rails. Preserve the bright new root
            // briefly so vapor still appears attached to each wingtip.
            age_fraction := 1 - clamp(particle.life / particle.max_life, 0, 1)
            breakup_band := int(age_fraction * 32)
            broken := age_fraction > .12 && breakup_band % 6 == 4 + side
            if broken {
                first_ring = len(world_renderer.wing_trail_vertices)
                ring_count = 0
                continue
            }
            if !world_sphere_in_view(
                editor,
                {particle.position.x, particle.position.y, particle.position.z},
                max(particle.size * 2, f32(.5)),
            ) {
                // Restart topology after an offscreen gap; otherwise two
                // retained rings could be joined across the culled interval.
                first_ring = len(world_renderer.wing_trail_vertices)
                ring_count = 0
                continue
            }
            fade := clamp(particle.life / particle.max_life, 0, 1)
            age := 1 - fade
            // Tip vapor begins as a tight bright filament, then diffuses into
            // a wider translucent wake. Broadening downstream is essential to
            // keep the trail from reading as a rigid glowing cable.
            radius := particle.size * (.68 + age * 1.05)
            opacity := fade * f32(math.sqrt(f64(fade)))
            color := canvas2d.Color{205, 239, 236, u8(clamp(opacity * 112, 0, 112))}
            for ring_side in 0 ..< 8 {
                angle := f32(ring_side) * math.PI * 2 / 8
                radial := third_person.Vec3 {
                    (camera.right.x * math.cos(angle) + camera.up.x * math.sin(angle)) * radius,
                    (camera.right.y * math.cos(angle) + camera.up.y * math.sin(angle)) * radius,
                    (camera.right.z * math.cos(angle) + camera.up.z * math.sin(angle)) * radius,
                }
                append(
                    &world_renderer.wing_trail_vertices,
                    world_vertex(
                        {
                            particle.position.x + radial.x,
                            particle.position.y + radial.y,
                            particle.position.z + radial.z,
                        },
                        color,
                    ),
                )
            }
            if ring_count > 0 {
                previous_ring := first_ring + (ring_count - 1) * 8
                current_ring := first_ring + ring_count * 8
                for ring_side in 0 ..< 8 {
                    next := (ring_side + 1) % 8
                    append(
                        &world_renderer.wing_trail_indices,
                        u16(previous_ring + ring_side),
                        u16(current_ring + ring_side),
                        u16(current_ring + next),
                        u16(previous_ring + ring_side),
                        u16(current_ring + next),
                        u16(previous_ring + next),
                    )
                }
            }
            ring_count += 1
        }
    }
    if len(world_renderer.wing_trail_indices) > 0 {
        resize(&world_renderer.wing_trail_optimized_indices, len(world_renderer.wing_trail_indices))
        adriatic_optimize_index_buffer(
            raw_data(world_renderer.wing_trail_optimized_indices),
            raw_data(world_renderer.wing_trail_indices),
            u32(len(world_renderer.wing_trail_indices)),
            u32(len(world_renderer.wing_trail_vertices)),
        )
    }
}

@(no_instrumentation)
wind_streak_hash :: proc(index, salt: int) -> f32 {
    value := math.sin(f64(index * 127 + salt * 311) * 12.9898) * 43758.5453
    return f32(value - math.floor(value))
}

@(no_instrumentation)
wind_streak_cycle :: proc(time, wind_speed, speed_variation, phase_seed, gust_seed: f32) -> f32 {
    gust_phase := time * .72 + gust_seed * math.PI * 2
    // The gust derivative must stay below the slowest base phase derivative
    // (wind_speed 1, speed_variation .72). Otherwise a visible streak can
    // travel backward briefly and produce a wagon-wheel effect.
    gust_offset := f32(math.sin(f64(gust_phase * .61))) * .04
    return time * wind_speed * .035 * speed_variation + phase_seed + gust_offset
}

@(no_instrumentation)
wind_streak_camera_distance :: proc(camera, start, finish: third_person.Vec3) -> f32 {
    segment := finish - start
    length_squared := linalg.dot(segment, segment)
    if length_squared <= .000001 do return linalg.length(camera - start)
    amount := clamp(linalg.dot(camera - start, segment) / length_squared, 0, 1)
    closest := start + segment * amount
    return linalg.length(camera - closest)
}

@(no_instrumentation)
wind_streak_perspective_length :: proc(authored_length, camera_distance: f32) -> f32 {
    // Roughly cap a ribbon to an eight-degree angular span. This preserves
    // distant authored lengths while preventing nearby streams from becoming
    // screen-crossing rails under perspective projection.
    return min(max(authored_length, f32(0)), max(camera_distance * .14, f32(.9)))
}

@(test)
wind_streak_camera_distance_uses_whole_segment :: proc(t: ^testing.T) {
    camera := third_person.Vec3{0, 0, 0}
    testing.expect(t, wind_streak_camera_distance(camera, {-5, 0, 0}, {5, 0, 0}) == 0)
    testing.expect(t, wind_streak_camera_distance(camera, {3, 0, 0}, {7, 0, 0}) == 3)
    testing.expect(t, wind_streak_camera_distance(camera, {0, 4, 0}, {0, 4, 0}) == 4)
    testing.expect(t, math.abs(wind_streak_perspective_length(8, 10) - 1.4) < .0001)
    testing.expect(t, wind_streak_perspective_length(4, 100) == 4)
}

@(test)
wind_streak_cycle_remains_forward_at_minimum_speed :: proc(t: ^testing.T) {
    previous := wind_streak_cycle(0, 1, .72, .37, .83)
    for sample in 1 ..= 2000 {
        current := wind_streak_cycle(f32(sample) * .01, 1, .72, .37, .83)
        testing.expect(t, current >= previous)
        previous = current
    }
}
