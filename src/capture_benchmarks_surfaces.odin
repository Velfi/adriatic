package main

import engine_sound "../packages/engine_sound"
import particle_systems "../packages/particles"
import roads "../packages/roads"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"


benchmark_seed_scene :: proc(editor: ^Editor, scenario: string) -> bool {
    if editor == nil do return false
    switch scenario {
    case "editor", "terrain_edit":
        return true
    case "formation_edit":
        for editor.project.structure_count < FORMATION_EDIT_BENCHMARK_STRUCTURES {
            index := editor.project.structure_count
            column := index % 16
            row := index / 16
            structure := terrain.structure_make(
                editor.editor_focus.x + (f32(column) - 7.5) * 12,
                editor.editor_focus.z + (f32(row) - 7.5) * 12,
                7,
                7,
                terrain.sample_surface_height(
                    &editor.project,
                    0,
                    editor.editor_focus.x + (f32(column) - 7.5) * 12,
                    editor.editor_focus.z + (f32(row) - 7.5) * 12,
                ),
                8,
            )
            if terrain.add_structure(&editor.project, structure) < 0 do break
        }
    case "foliage":
        seed_foliage_capture(editor)
    case "foliage_forest":
        seed_foliage_forest_capture(editor)
    case "foliage_understory":
        seed_foliage_forest_capture(editor)
        configure_foliage_understory_camera(editor)
    case "foliage_stress":
        seed_foliage_stress(editor)
    case "field_edit":
        seed_foliage_capture(editor, "field")
        structure_lod_force(i32(Structure_LOD.Near))
    case "formations":
        seed_default_island_towns(editor)
    case "structure_lod":
        seed_structure_lod_benchmark(editor)
    case "structure_lod_near":
        seed_structure_lod_benchmark(editor)
        structure_lod_force(i32(Structure_LOD.Near))
    case "roads":
        seed_road_capture(editor)
    case "road_dust":
        seed_road_capture(editor)
        seed_road_dust_capture(editor)
    case "road_grip":
        seed_road_grip_benchmark(editor)
    case "terrain_grip":
        seed_terrain_grip_benchmark(editor)
    case "player":
        seed_player_benchmark(editor)
        editor.tweak.player_outline.enabled = true
    case "player_outline_off":
        seed_player_benchmark(editor)
    case "grass":
        seed_player_benchmark(editor)
    case "grass_disabled":
        seed_player_benchmark(editor)
        editor.benchmark_ground_grass_disabled = true
    case "ocean_flight":
        seed_ocean_flight_benchmark(editor)
    case "fog_banks":
        seed_ocean_flight_benchmark(editor)
    case "land_flight":
        seed_land_flight_benchmark(editor)
    case "land_flight_cold":
        seed_land_flight_benchmark(editor)
        editor.benchmark_ground_grass_disabled = true
    case "zora":
        seed_zora_benchmark(editor)
    case "marta":
        seed_marta_benchmark(editor)
    case "architecture", "architecture_night":
        seed_city_capture(editor)
    case "municipal_route_night", "municipal_route_night_storm":
        seed_municipal_route_night_benchmark(editor)
    case "shadow_lab":
        _ = lab_scene_load(editor, {definition = lab_scene_find("shadow")})
    case "garden":
        _ = lab_scene_load(editor, {definition = lab_scene_find("garden"), target = "courtyard"})
    case "plant_gallery":
        _ = lab_scene_load(editor, {definition = lab_scene_find("plant-generator"), target = "gallery"})
    case "plant_transition":
        _ = lab_scene_load(editor, {definition = lab_scene_find("foliage-transition"), target = "pine-benchmark"})
    case "plant_transition_oak":
        _ = lab_scene_load(editor, {definition = lab_scene_find("foliage-transition"), target = "oak-benchmark"})
    case "olive_orchard":
        _ = lab_scene_load(editor, {definition = lab_scene_find("plant-generator"), target = "olive"})
    case "plant_climbers":
        _ = lab_scene_load(editor, {definition = lab_scene_find("plant-generator"), target = "climbing-garden"})
    case "plant_runtime_max":
        _ = lab_scene_load(editor, {definition = lab_scene_find("plant-generator"), target = "stone-pine"})
    case "boids_10k":
        _ = lab_scene_load(editor, {definition = lab_scene_find("boid"), target = "stress-10k"})
    case "boids_0":
        _ = lab_scene_load(editor, {definition = lab_scene_find("boid"), target = "stress-0"})
    case:
        return false
    }
    if scenario != "foliage_stress" &&
       scenario != "field_edit" &&
       scenario != "structure_lod" &&
       scenario != "structure_lod_near" &&
       scenario != "foliage_forest" &&
       scenario != "foliage_understory" &&
       scenario != "road_grip" &&
       scenario != "terrain_grip" &&
       scenario != "player" &&
       scenario != "player_outline_off" &&
       scenario != "grass" &&
       scenario != "grass_disabled" &&
       scenario != "ocean_flight" &&
       scenario != "fog_banks" &&
       scenario != "land_flight" &&
       scenario != "land_flight_cold" &&
       scenario != "zora" &&
       scenario != "marta" &&
       scenario != "municipal_route_night" &&
       scenario != "municipal_route_night_storm" &&
       scenario != "shadow_lab" &&
       scenario != "garden" &&
       scenario != "plant_gallery" &&
       scenario != "plant_transition" &&
       scenario != "plant_transition_oak" &&
       scenario != "olive_orchard" &&
       scenario != "plant_climbers" &&
       scenario != "plant_runtime_max" &&
       scenario != "boids_0" &&
       scenario != "boids_10k" {
        editor.editor_camera.distance = 260
        editor.camera_pose = third_person.camera_pose(editor.editor_focus, editor.editor_camera)
    }
    return true
}

benchmark_terrain_edit_step :: proc(editor: ^Editor, edit_frame: int) {
    if editor == nil || edit_frame < 0 do return
    phase := f32(edit_frame)
    world_x := editor.editor_focus.x + math.sin(phase * .037) * 72
    world_z := editor.editor_focus.z + math.sin(phase * .023) * 56
    terrain.apply_stroke_with_hardness(
        &editor.project,
        editor.tool,
        world_x,
        world_z,
        editor.radius,
        editor.strength * (f32(1) / 60) * 4,
        1,
        editor.hardness,
    )
    world_terrain_changed(editor, world_x, world_z, editor.radius, true)
}

benchmark_formation_edit_step :: proc(editor: ^Editor, edit_frame: int) {
    if editor == nil || edit_frame < 0 || editor.project.structure_count <= 0 do return
    structure := &editor.project.structures[editor.project.structure_count - 1]
    structure.height = 8 + math.sin(f32(edit_frame) * .17) * .5
    editor.project.revision += 1
}

benchmark_field_edit_step :: proc(editor: ^Editor, edit_frame: int) {
    if editor == nil || edit_frame < 0 || editor.project.structure_count <= 0 do return
    structure := &editor.project.structures[editor.project.structure_count - 1]
    if structure.kind != .Field do return
    structure.rotation = -.14 + math.sin(f32(edit_frame) * .11) * .015
    editor.project.revision += 1
}

benchmark_land_flight_step :: proc(editor: ^Editor, benchmark_frame: int) {
    if editor == nil || benchmark_frame < 0 do return
    spawn := postale_spawn_position(editor)
    phase := f32(benchmark_frame) * .012
    x := spawn.x + math.sin(phase) * 72
    z := spawn.z + math.sin(phase * .61) * 28
    ground := terrain.sample_surface_height(&editor.project, 0, x, z)
    editor.postale.body.position = {x, ground + 9, z}
    editor.postale.body.velocity = {-24, 0, 0}
    editor.postale.grounded = false
    editor.postale.was_grounded = false
    editor.postale.vehicle.position = {x, ground + 9, z}
    editor.camera_pose = third_person.camera_look_at({x + 16, ground + 14, z + 9}, {x - 10, ground + 5, z})
}

benchmark_percentile :: proc(sorted_samples: []f64, fraction: f64) -> f64 {
    if len(sorted_samples) <= 0 do return 0
    index := int(math.ceil(fraction * f64(len(sorted_samples)))) - 1
    return sorted_samples[clamp(index, 0, len(sorted_samples) - 1)]
}

Benchmark_Timing :: struct {
    mean_ms, median_ms, p95_ms, p99_ms, max_ms, median_fps: f64,
}

Benchmark_Geometry :: struct {
    world_vertices, world_unique_vertices, world_capacity: int,
    world_utilization:                                     f64,
    road_vertices, road_capacity:                          int,
    road_utilization:                                      f64,
    foliage_vertices, foliage_capacity:                    int,
    foliage_utilization:                                   f64,
    structure_lod_world_vertices:                          int,
    structure_lod_foliage_vertices:                        int,
    structure_lod_counts:                                  [3]int,
    structure_lod_cache_rebuilds:                          u64,
}

Benchmark_Caches :: struct {
    clipmap_generated, clipmap_copied:                 u64,
    clipmap_full_rebuilds, clipmap_incremental_shifts: u64,
    clipmap_cells_copied, clipmap_cells_generated:     u64,
    grass_hits, grass_misses, grass_emitted:           u64,
    climbing_leaf_builds, climbing_leaf_reuses:        u64,
    town_mouse_builds, town_mouse_reuses:              u64,
}

Benchmark_Renderer :: struct {
    dirty_build_ms, frame_build_ms:                        f64,
    visibility_build_cpu_ms, texture_upload_ms:            f64,
    rebuilt_objects, rebuilt_pages, static_bytes_uploaded: u64,
    indexed_cells, visible_clusters, indirect_commands:    u64,
    retired_bytes:                                         u64,
}

Benchmark_Result :: struct {
    scenario:      string,
    samples:       int,
    window, world: [2]int,
    timing:        Benchmark_Timing,
    geometry:      Benchmark_Geometry,
    visibility:    Static_Visibility_Stats,
    caches:        Benchmark_Caches,
    renderer:      Benchmark_Renderer,
}

benchmark_result_write_timing :: proc(builder: ^strings.Builder, result: ^Benchmark_Result) {
    t := result.timing
    fmt.sbprintf(
        builder,
        "{{\"scenario\":\"%s\",\"samples\":%d,\"window\":[%d,%d],\"world\":[%d,%d],\"mean_ms\":%.4f,\"median_ms\":%.4f,\"p95_ms\":%.4f,\"p99_ms\":%.4f,\"max_ms\":%.4f,\"median_fps\":%.2f,",
        result.scenario,
        result.samples,
        result.window[0],
        result.window[1],
        result.world[0],
        result.world[1],
        t.mean_ms,
        t.median_ms,
        t.p95_ms,
        t.p99_ms,
        t.max_ms,
        t.median_fps,
    )
}

benchmark_result_write_geometry :: proc(builder: ^strings.Builder, g: Benchmark_Geometry) {
    fmt.sbprintf(
        builder,
        "\"geometry\":{{\"world_vertices\":%d,\"world_unique_vertices\":%d,\"world_capacity\":%d,\"world_utilization\":%.6f,\"road_vertices\":%d,\"road_capacity\":%d,\"road_utilization\":%.6f,\"foliage_vertices\":%d,\"foliage_capacity\":%d,\"foliage_utilization\":%.6f,\"structure_lod_world_vertices\":%d,\"structure_lod_foliage_vertices\":%d,\"structure_lod_counts\":[%d,%d,%d],\"structure_lod_cache_rebuilds\":%d,",
        g.world_vertices,
        g.world_unique_vertices,
        g.world_capacity,
        g.world_utilization,
        g.road_vertices,
        g.road_capacity,
        g.road_utilization,
        g.foliage_vertices,
        g.foliage_capacity,
        g.foliage_utilization,
        g.structure_lod_world_vertices,
        g.structure_lod_foliage_vertices,
        g.structure_lod_counts[0],
        g.structure_lod_counts[1],
        g.structure_lod_counts[2],
        g.structure_lod_cache_rebuilds,
    )
}

benchmark_result_write_visibility :: proc(builder: ^strings.Builder, v: Static_Visibility_Stats) {
    fmt.sbprintf(
        builder,
        "\"static_visibility\":{{\"candidates\":%d,\"frustum_culled\":%d,\"occlusion_culled\":%d,\"force_visible\":%d,\"empty\":%d,\"emitted_draws\":%d,\"opaque_cost\":%d,\"foliage_cost\":%d,\"bougainvillea_cost\":%d,\"atlas_used\":[%d,%d,%d],\"atlas_fragmentation\":%.6f}},",
        v.candidates,
        v.frustum_culled,
        v.occlusion_culled,
        v.force_visible,
        v.empty,
        v.emitted_draws,
        v.opaque_cost,
        v.foliage_cost,
        v.bougainvillea_cost,
        v.atlas_opaque_used,
        v.atlas_foliage_used,
        v.atlas_bougainvillea_used,
        v.atlas_fragmentation,
    )
}

benchmark_result_write_caches :: proc(builder: ^strings.Builder, c: Benchmark_Caches) {
    fmt.sbprintf(
        builder,
        "\"caches\":{{\"clipmap_generated\":%d,\"clipmap_copied\":%d,\"clipmap_full_rebuilds\":%d,\"clipmap_incremental_shifts\":%d,\"clipmap_cells_copied\":%d,\"clipmap_cells_generated\":%d,\"grass_hits\":%d,\"grass_misses\":%d,\"grass_emitted\":%d,\"climbing_leaf_builds\":%d,\"climbing_leaf_reuses\":%d,\"town_mouse_builds\":%d,\"town_mouse_reuses\":%d}},",
        c.clipmap_generated,
        c.clipmap_copied,
        c.clipmap_full_rebuilds,
        c.clipmap_incremental_shifts,
        c.clipmap_cells_copied,
        c.clipmap_cells_generated,
        c.grass_hits,
        c.grass_misses,
        c.grass_emitted,
        c.climbing_leaf_builds,
        c.climbing_leaf_reuses,
        c.town_mouse_builds,
        c.town_mouse_reuses,
    )
}

benchmark_result_write_renderer :: proc(builder: ^strings.Builder, r: Benchmark_Renderer) {
    fmt.sbprintf(
        builder,
        "\"renderer\":{{\"dirty_build_ms\":%.4f,\"frame_build_ms\":%.4f,\"visibility_build_cpu_ms\":%.4f,\"texture_upload_ms\":%.4f,\"rebuilt_objects\":%d,\"rebuilt_pages\":%d,\"static_bytes_uploaded\":%d,\"indexed_cells\":%d,\"visible_clusters\":%d,\"indirect_commands\":%d,\"retired_bytes\":%d}}}}}}",
        r.dirty_build_ms,
        r.frame_build_ms,
        r.visibility_build_cpu_ms,
        r.texture_upload_ms,
        r.rebuilt_objects,
        r.rebuilt_pages,
        r.static_bytes_uploaded,
        r.indexed_cells,
        r.visible_clusters,
        r.indirect_commands,
        r.retired_bytes,
    )
}

benchmark_report :: proc(
    scenario: string,
    samples: []f64,
    window_width, window_height, world_width, world_height: int,
) {
    if len(samples) <= 0 do return
    sorted := make([]f64, len(samples))
    defer delete(sorted)
    copy(sorted, samples)
    slice.sort(sorted)
    total := f64(0)
    for sample in sorted do total += sample
    median := benchmark_percentile(sorted, .50)
    p95 := benchmark_percentile(sorted, .95)
    p99 := benchmark_percentile(sorted, .99)
    maximum := sorted[len(sorted) - 1]
    instance_index_count := 0
    for mesh in world_renderer.instance_meshes {
        instance_index_count += int(mesh.index_count) * len(mesh.instances)
    }
    for mesh in world_renderer.plant_meshes {
        instance_index_count += int(mesh.index_count) * len(mesh.instances)
    }
    world_vertex_count := len(world_renderer.vertices) + len(world_renderer.static_indices) + instance_index_count
    world_unique_vertex_count :=
        len(world_renderer.vertices) +
        len(world_renderer.static_vertices) +
        len(world_renderer.instance_vertices) +
        len(world_renderer.plant_vertices)
    road_vertex_count := len(world_renderer.road_geometry_cache)
    foliage_vertex_count :=
        len(world_renderer.foliage_vertices) +
        len(world_renderer.bougainvillea_vertices) +
        (len(world_renderer.grass_instances) + len(world_renderer.wildflower_instances)) * 6
    world_vertex_capacity :=
        int(world_buffer_min_size(world_renderer.vertex[:]) / size_of(World_Vertex)) +
        int(world_buffer_min_size(world_renderer.static_index[:]) / size_of(u32))
    world_vertex_utilization := f64(world_vertex_count) / f64(max(world_vertex_capacity, 1))
    foliage_vertex_capacity :=
        int(world_buffer_min_size(world_renderer.foliage_vertex[:]) / size_of(Foliage_Vertex)) +
        int(world_buffer_min_size(world_renderer.grass_instance[:]) / size_of(Grass_Instance)) * 6
    foliage_vertex_utilization := f64(foliage_vertex_count) / f64(max(foliage_vertex_capacity, 1))
    road_vertex_capacity := int(world_buffer_min_size(world_renderer.road_vertex[:]) / size_of(World_Vertex))
    road_vertex_utilization := f64(road_vertex_count) / f64(max(road_vertex_capacity, 1))
    result := Benchmark_Result {
        scenario = scenario,
        samples = len(sorted),
        window = {window_width, window_height},
        world = {world_width, world_height},
        timing = {
            mean_ms = total / f64(len(sorted)) * 1000,
            median_ms = median * 1000,
            p95_ms = p95 * 1000,
            p99_ms = p99 * 1000,
            max_ms = maximum * 1000,
            median_fps = 1 / max(median, f64(.000001)),
        },
        geometry = {
            world_vertices = world_vertex_count,
            world_unique_vertices = world_unique_vertex_count,
            world_capacity = world_vertex_capacity,
            world_utilization = world_vertex_utilization,
            road_vertices = road_vertex_count,
            road_capacity = road_vertex_capacity,
            road_utilization = road_vertex_utilization,
            foliage_vertices = foliage_vertex_count,
            foliage_capacity = foliage_vertex_capacity,
            foliage_utilization = foliage_vertex_utilization,
            structure_lod_world_vertices = world_renderer.structure_lod_world_vertices,
            structure_lod_foliage_vertices = world_renderer.structure_lod_foliage_vertices,
            structure_lod_counts = world_renderer.structure_lod_counts,
            structure_lod_cache_rebuilds = world_renderer.structure_lod_cache_rebuilds,
        },
        visibility = world_renderer.static_visibility,
        caches = {
            clipmap_generated = world_renderer.clipmap_levels_generated,
            clipmap_copied = world_renderer.clipmap_levels_copied,
            clipmap_full_rebuilds = world_renderer.clipmap_full_rebuilds,
            clipmap_incremental_shifts = world_renderer.clipmap_incremental_shifts,
            clipmap_cells_copied = world_renderer.clipmap_cells_copied,
            clipmap_cells_generated = world_renderer.clipmap_cells_generated,
            grass_hits = world_renderer.grass_candidate_hits,
            grass_misses = world_renderer.grass_candidate_misses,
            grass_emitted = world_renderer.grass_instances_emitted,
            climbing_leaf_builds = world_renderer.climbing_leaf_cache_builds,
            climbing_leaf_reuses = world_renderer.climbing_leaf_cache_reuses,
            town_mouse_builds = world_renderer.town_mouse_cache_builds,
            town_mouse_reuses = world_renderer.town_mouse_cache_reuses,
        },
        renderer = {
            dirty_build_ms = world_renderer.dirty_build_ms,
            frame_build_ms = world_renderer.frame_build_ms,
            visibility_build_cpu_ms = world_renderer.visibility_build_cpu_ms,
            texture_upload_ms = world_renderer.texture_upload_ms,
            rebuilt_objects = world_renderer.rebuilt_static_objects,
            rebuilt_pages = world_renderer.rebuilt_static_pages,
            static_bytes_uploaded = world_renderer.static_bytes_uploaded,
            indexed_cells = world_renderer.indexed_cells,
            visible_clusters = world_renderer.visible_clusters,
            indirect_commands = world_renderer.indirect_command_count,
            retired_bytes = world_renderer.retired_bytes,
        },
    }
    output := strings.builder_make_len_cap(0, 4096)
    defer delete(output.buf)
    benchmark_result_write_timing(&output, &result)
    benchmark_result_write_geometry(&output, result.geometry)
    benchmark_result_write_visibility(&output, result.visibility)
    benchmark_result_write_caches(&output, result.caches)
    benchmark_result_write_renderer(&output, result.renderer)
    fmt.printf("BENCHMARK_RESULT %s\n", strings.to_string(output))
}

seed_road_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    graph := &editor.project.road_graph
    graph^ = {}
    center := f32(terrain.WORLD_SIZE_METERS * .5 * terrain.DEFAULT_ISLAND_OFFSET)
    node_positions := [5]roads.Vec3 {
        {center - 145, 0, center + 80},
        {center - 45, 0, center + 20},
        {center + 105, 0, center - 45},
        {center - 15, 0, center - 125},
        {center - 15, 0, center + 135},
    }
    for &position in node_positions {
        position.y = terrain.sample_surface_height(&editor.project, 0, position.x, position.z)
    }
    west := roads.add_node(graph, node_positions[0], 7)
    junction := roads.add_node(graph, node_positions[1], 10)
    east := roads.add_node(graph, node_positions[2], 7)
    south := roads.add_node(graph, node_positions[3], 7)
    north := roads.add_node(graph, node_positions[4], 7)
    _ = roads.add_edge(
        graph,
        west,
        junction,
        {center - 115, node_positions[0].y, center + 40},
        {center - 78, node_positions[1].y, center + 62},
        12,
        2.2,
        .Asphalt,
    )
    _ = roads.add_edge(
        graph,
        junction,
        east,
        {center + 5, node_positions[1].y, center - 15},
        {center + 58, node_positions[2].y, center + 2},
        11,
        2.1,
        .Cobblestone,
    )
    _ = roads.add_edge(
        graph,
        junction,
        south,
        {center - 70, node_positions[1].y, center - 35},
        {center - 55, node_positions[3].y, center - 92},
        9,
        1.9,
        .Dirt,
    )
    _ = roads.add_edge(
        graph,
        junction,
        north,
        {center - 70, node_positions[1].y, center + 65},
        {center - 45, node_positions[4].y, center + 100},
        10,
        2,
        .Gravel,
    )
    editor.authoring_tool = .Roads
    editor.tool = .Structure
    editor.road_mode = true
    editor.architecture_node_mode = false
    editor.road_selected_node = junction
    editor.project.revision += 1
}

seed_road_dust_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    for edge in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
        point := roads.edge_point(&editor.project.road_graph, edge, .58)
        surface := particle_systems.Dust_Surface.Grass
        switch edge.pavement {
        case .Asphalt:
            surface = .Asphalt
        case .Gravel:
            surface = .Gravel
        case .Cobblestone:
            surface = .Cobblestone
        case .Dirt:
            surface = .Dirt
        case .Steps:
            surface = .Cobblestone
        }
        contact := particle_systems.Vehicle_Contact {
            position = {point.x, point.y + .12, point.z},
            grounded = true,
            surface  = surface,
        }
        first_particle := editor.vehicle_effects.dust_count
        for preview_index in 0 ..< 48 {
            angle := f32(preview_index) * math.PI * 2 / 48
            radius := f32(preview_index % 9) * .28
            preview_contact := contact
            preview_contact.position.x += math.cos(angle) * radius
            preview_contact.position.z += math.sin(angle) * radius
            particle_systems.spawn_dust(&editor.vehicle_effects, preview_contact, 1.15)
        }
        // The overview camera sees all four materials at once, so magnify only
        // its diagnostic billboards while preserving each runtime profile.
        for index in first_particle ..< editor.vehicle_effects.dust_count {
            editor.vehicle_effects.dust[index].size *= 5.5
        }
    }
    empty_contacts: [4]particle_systems.Vehicle_Contact
    particle_systems.step_vehicle_effects(&editor.vehicle_effects, .05, 0, 0, false, 0, empty_contacts)
    particle_systems.step_vehicle_effects(&editor.vehicle_effects, .05, 0, 0, false, 0, empty_contacts)
}

seed_road_grip_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    seed_road_capture(editor)
    dirt_edge := -1
    for edge, index in editor.project.road_graph.edges[:editor.project.road_graph.edge_count] {
        if edge.pavement == .Dirt {
            dirt_edge = index
            break
        }
    }
    if dirt_edge < 0 do return
    edge := editor.project.road_graph.edges[dirt_edge]
    point := roads.edge_point(&editor.project.road_graph, edge, .18)
    tangent := roads.edge_tangent(&editor.project.road_graph, edge, .18)
    editor.car.position = {point.x, point.y, point.z}
    editor.car.yaw_radians = math.atan2(tangent.z, tangent.x)
    dirt_grip := roads.pavement_grip(.Dirt)
    drive_surface := vehicles.Car_Drive_Surface {
        longitudinal_grip  = dirt_grip.longitudinal,
        lateral_grip       = dirt_grip.lateral,
        rolling_resistance = dirt_grip.rolling_resistance,
    }
    contacts: [4]particle_systems.Vehicle_Contact
    for _ in 0 ..< 105 {
        ground := terrain.sample_surface_height(&editor.project, 0, editor.car.position.x, editor.car.position.z)
        vehicles.car_drive_step(
            &editor.car_drive,
            &editor.car,
            {throttle = 1, steering = .78},
            ground,
            1.0 / 60,
            drive_surface,
        )
        for index in 0 ..< 4 {
            contacts[index] = {
                position = {editor.car.position.x, editor.car.position.y + .08, editor.car.position.z},
                grounded = true,
                surface  = .Dirt,
            }
        }
        particle_systems.step_vehicle_effects(
            &editor.vehicle_effects,
            1.0 / 60,
            vehicles.car_drive_speed(editor.car_drive),
            editor.car_drive.steering,
            false,
            editor.car_drive.slip_amount,
            contacts,
        )
    }
    for index in 0 ..< editor.vehicle_effects.dust_count {
        editor.vehicle_effects.dust[index].size *= 2.8
    }
    car_physics_teleport(editor)
}

seed_terrain_grip_capture :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.project.road_graph = {}
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    center := half_extent * terrain.DEFAULT_ISLAND_OFFSET
    shore_x := center + half_extent * terrain.DEFAULT_ISLAND_RADIUS
    shore_z := center
    ground := terrain.sample_surface_height(&editor.project, 0, shore_x, shore_z)
    editor.car.position = {shore_x, ground, shore_z}
    editor.car.yaw_radians = math.PI * .5
    sand_grip := terrain.ground_grip(.Sand)
    drive_surface := vehicles.Car_Drive_Surface {
        longitudinal_grip  = sand_grip.longitudinal,
        lateral_grip       = sand_grip.lateral,
        rolling_resistance = sand_grip.rolling_resistance,
    }
    contacts: [4]particle_systems.Vehicle_Contact
    for _ in 0 ..< 105 {
        ground = terrain.sample_surface_height(&editor.project, 0, editor.car.position.x, editor.car.position.z)
        vehicles.car_drive_step(
            &editor.car_drive,
            &editor.car,
            {throttle = 1, steering = .72},
            ground,
            1.0 / 60,
            drive_surface,
        )
        for index in 0 ..< 4 {
            contacts[index] = {
                position = {editor.car.position.x, editor.car.position.y + .08, editor.car.position.z},
                grounded = true,
                surface  = .Sand,
            }
        }
        particle_systems.step_vehicle_effects(
            &editor.vehicle_effects,
            1.0 / 60,
            vehicles.car_drive_speed(editor.car_drive),
            editor.car_drive.steering,
            false,
            editor.car_drive.slip_amount,
            contacts,
        )
    }
    for index in 0 ..< editor.vehicle_effects.dust_count {
        editor.vehicle_effects.dust[index].size *= 2.8
    }
    car_physics_teleport(editor)
}

// terrain_dust_surface maps the terrain classifier's discrete ground band onto
// the particle system's surface vocabulary. Terrain has no dedicated asphalt or
// gravel, so it reuses the existing Dirt/Grass profiles and the new Sand one.
terrain_dust_surface :: proc(surface: terrain.Ground_Surface) -> particle_systems.Dust_Surface {
    switch surface {
    case .Sand:
        return .Sand
    case .Dirt:
        return .Dirt
    case .Grass:
        return .Grass
    }
    return .Grass
}

footstep_surface_from_dust :: proc(surface: particle_systems.Dust_Surface) -> engine_sound.Footstep_Surface {
    switch surface {
    case .Asphalt:
        return .Asphalt
    case .Cobblestone:
        return .Cobblestone
    case .Gravel:
        return .Gravel
    case .Dirt:
        return .Dirt
    case .Sand:
        return .Sand
    case .Grass:
        return .Grass
    }
    return .Grass
}
