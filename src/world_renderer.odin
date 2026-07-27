package main

import architecture "../packages/architecture"
import atmosphere "../packages/atmosphere"
import boats "../packages/boats"
import buildings "../packages/buildings"
import circulation "../packages/circulation"
import flight "../packages/flight"
import mouse_gait "../packages/mouse_gait"
import mouse_kinematics "../packages/mouse_kinematics"
import mouse_paws "../packages/mouse_paws"
import mouse_tail "../packages/mouse_tail"
import particles "../packages/particles"
import render_graph "../packages/render_graph"
import roads "../packages/roads"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:testing"
import vk "vendor:vulkan"
import rl "zelda_engine:canvas2d"
import engine "zelda_engine:engine"
import render3d "zelda_engine:render3d"
import resources "zelda_engine:render_resources"

// Initial host-buffer and CPU-array reserves. Frame-slot buffers grow when a
// larger authored world needs them.
WORLD_VERTEX_INITIAL_CAPACITY :: 600_000
ROAD_VERTEX_INITIAL_CAPACITY :: 320_000
FOLIAGE_VERTEX_INITIAL_CAPACITY :: 24_000
// Bougainvillea cards use four anchor-centered sub-quads (24 vertices) so
// their painted roots remain fixed under wind. Preserve the former effective
// budget of 2,000 cards after that fourfold tessellation.
BOUGAINVILLEA_VERTEX_INITIAL_CAPACITY :: 48_000
GRASS_INSTANCE_INITIAL_CAPACITY :: 18_000
WILDFLOWER_INSTANCE_INITIAL_CAPACITY :: 4_000
WING_TRAIL_VERTEX_CAPACITY :: particles.MAX_WING_TRAIL_PARTICLES * 8
WING_TRAIL_INDEX_CAPACITY :: (particles.MAX_WING_TRAIL_PARTICLES - 2) * 8 * 6 + 8 * 6
SHADOW_VERTEX_INITIAL_CAPACITY :: 180_000
CLIPMAP_GRID_RESOLUTION :: (terrain.RING_RESOLUTION - 1) / 2 + 2
CLIPMAP_VERTEX_COUNT :: CLIPMAP_GRID_RESOLUTION * CLIPMAP_GRID_RESOLUTION
CLIPMAP_FULL_INDEX_COUNT :: (CLIPMAP_GRID_RESOLUTION - 1) * (CLIPMAP_GRID_RESOLUTION - 1) * 6

// Keep the world pass useful beyond the immediate flight envelope. The
// clipmap already provides this coverage; these values prevent the camera
// projection, fog, and ocean fallback from hiding it prematurely.
WORLD_FAR_CLIP :: f32(12000)
// Eight centimeters lets a nearby posted mouse's broad torso triangles cross
// almost through the camera before homogeneous clipping. Their intersections
// are then perspective-divided into screen-spanning wedges. A conventional
// gameplay near plane clips those occluders before the projection becomes
// numerically and visually extreme while remaining well inside the player's
// chase-camera distance.
WORLD_PLAY_NEAR_CLIP :: f32(.20)
WORLD_FLIGHT_NEAR_CLIP :: f32(.5)
WORLD_EDITOR_NEAR_CLIP :: f32(100)
WORLD_FOG_START :: f32(4500)
WORLD_FOG_END :: f32(11000)

Structure_LOD :: enum u8 {
    Near,
    Medium,
    Far,
}

STRUCTURE_LOD_NEAR_PIXELS :: f32(160)
STRUCTURE_LOD_MEDIUM_PIXELS :: f32(48)
STRUCTURE_LOD_HYSTERESIS :: f32(.15)

Structure_LOD_Result :: struct {
    tier:               Structure_LOD,
    projected_diameter: f32,
    transition:         f32,
}

Static_Visibility_Classification :: enum u8 {
    Visible,
    Frustum_Culled,
    Occlusion_Culled,
    Empty,
    Force_Visible,
}

Static_Visibility_Stats :: struct {
    candidates:          u32,
    frustum_culled:      u32,
    occlusion_culled:    u32,
    force_visible:       u32,
    empty:               u32,
    emitted_draws:       u32,
    opaque_cost:         u32,
    foliage_cost:        u32,
    bougainvillea_cost:  u32,
    atlas_opaque_used:   u32,
    atlas_foliage_used:  u32,
    atlas_bougainvillea_used: u32,
    atlas_fragmentation: f32,
}

Structure_Visibility_Order :: struct {
    index:            int,
    distance_squared: f32,
}

@(no_instrumentation)
structure_visibility_order_less :: #force_inline proc(a, b: Structure_Visibility_Order) -> bool {
    if a.distance_squared != b.distance_squared do return a.distance_squared < b.distance_squared
    return a.index < b.index
}

@(no_instrumentation)
structure_visibility_order_repair :: proc(order: []Structure_Visibility_Order) -> bool {
    move_limit := len(order) * 8
    moves := 0
    for index in 1 ..< len(order) {
        entry := order[index]
        insertion := index
        for insertion > 0 && structure_visibility_order_less(entry, order[insertion - 1]) {
            order[insertion] = order[insertion - 1]
            insertion -= 1
            moves += 1
            if moves >= move_limit {
                order[insertion] = entry
                return false
            }
        }
        order[insertion] = entry
    }
    return true
}

structure_lod_forced: i32 = -1

window_flower_box_roll :: proc(structure_seed: u32, row, column: int) -> u32 {
    hash := structure_seed ~ u32(row + 1) * 0x9e3779b9 ~ u32(column + 1) * 0x85ebca6b
    hash ~= hash >> 16
    hash *= 0x7feb352d
    hash ~= hash >> 15
    hash *= 0x846ca68b
    hash ~= hash >> 16
    return hash % 100
}

window_has_flower_box :: proc(structure_seed: u32, row, column: int) -> bool {
    return window_flower_box_roll(structure_seed, row, column) < 35
}

structure_lod_force :: proc(tier: i32) {
    structure_lod_forced = clamp(tier, i32(-1), i32(2))
}

structure_lod_projected_diameter :: proc(
    camera: Perspective_Camera,
    center: third_person.Vec3,
    radius: f32,
    viewport_height: f32,
    near_plane: f32,
) -> f32 {
    depth := linalg.dot(center - camera.position, camera.forward)
    if depth <= near_plane + radius do return f32(1e9)
    return max(radius, f32(0)) * 2 * max(camera.focal_length, f32(.01)) *
           max(viewport_height, f32(1)) * .5 / depth
}

// Conservative sphere/frustum test in the same camera basis and projection
// convention used by the world shaders. A sphere intersecting any plane stays
// visible; this deliberately prefers extra work over a visible false reject.
static_sphere_in_frustum :: proc(
    camera: Perspective_Camera,
    center: third_person.Vec3,
    radius, aspect, near_plane, far_plane: f32,
) -> bool {
    safe_radius := max(radius, f32(0))
    safe_focal := max(camera.focal_length, f32(.01))
    safe_aspect := max(aspect, f32(.01))
    view := center - camera.position
    depth := linalg.dot(view, camera.forward)
    if depth + safe_radius < near_plane || depth - safe_radius > far_plane do return false

    horizontal_scale := safe_focal / safe_aspect
    horizontal := abs(linalg.dot(view, camera.right)) * horizontal_scale
    horizontal_radius := safe_radius * f32(math.sqrt(f64(1 + horizontal_scale * horizontal_scale)))
    if horizontal > depth + horizontal_radius do return false

    vertical := abs(linalg.dot(view, camera.up)) * safe_focal
    vertical_radius := safe_radius * f32(math.sqrt(f64(1 + safe_focal * safe_focal)))
    return vertical <= depth + vertical_radius
}

structure_visibility_sphere :: proc(structure: terrain.Structure) -> (third_person.Vec3, f32) {
    center := third_person.Vec3 {
        structure.center_x,
        structure.base_y + structure.height * .5,
        structure.center_z,
    }
    radius := f32(math.sqrt(f64(
        structure.width * structure.width +
        structure.depth * structure.depth +
        structure.height * structure.height,
    ))) * .5
    return center, radius
}

structure_lod_select :: proc(
    projected_diameter: f32,
    previous: Structure_LOD,
    force_near := false,
) -> Structure_LOD_Result {
    if structure_lod_forced >= 0 {
        return {
            tier = Structure_LOD(structure_lod_forced),
            projected_diameter = projected_diameter,
            transition = 1,
        }
    }
    if force_near || projected_diameter >= f32(1e8) {
        return {tier = .Near, projected_diameter = projected_diameter, transition = 1}
    }
    tier := previous
    near_enter := STRUCTURE_LOD_NEAR_PIXELS * (1 + STRUCTURE_LOD_HYSTERESIS)
    near_exit := STRUCTURE_LOD_NEAR_PIXELS * (1 - STRUCTURE_LOD_HYSTERESIS)
    medium_enter := STRUCTURE_LOD_MEDIUM_PIXELS * (1 + STRUCTURE_LOD_HYSTERESIS)
    medium_exit := STRUCTURE_LOD_MEDIUM_PIXELS * (1 - STRUCTURE_LOD_HYSTERESIS)
    switch previous {
    case .Near:
        if projected_diameter < near_exit do tier = projected_diameter < medium_exit ? .Far : .Medium
    case .Medium:
        if projected_diameter >= near_enter {
            tier = .Near
        } else if projected_diameter < medium_exit {
            tier = .Far
        }
    case .Far:
        if projected_diameter >= near_enter {
            tier = .Near
        } else if projected_diameter >= medium_enter {
            tier = .Medium
        }
    }
    lower, upper := STRUCTURE_LOD_MEDIUM_PIXELS, STRUCTURE_LOD_NEAR_PIXELS
    if tier == .Far do lower, upper = 0, STRUCTURE_LOD_MEDIUM_PIXELS
    transition := clamp((projected_diameter - lower) / max(upper - lower, f32(1)), 0, 1)
    return {tier = tier, projected_diameter = projected_diameter, transition = transition}
}

structure_lod_for :: proc(
    structure: terrain.Structure,
    previous: Structure_LOD,
    force_near := false,
) -> Structure_LOD_Result {
    editor := world_renderer.editor
    if editor == nil do return {tier = .Near, projected_diameter = 1e9, transition = 1}
    focal_length := editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : f32(1.35)
    camera := perspective_camera(editor.camera_pose, focal_length)
    center := third_person.Vec3 {
        structure.center_x,
        structure.base_y + structure.height * .5,
        structure.center_z,
    }
    radius := f32(math.sqrt(f64(
        structure.width * structure.width +
        structure.depth * structure.depth +
        structure.height * structure.height,
    ))) * .5
    near_plane := editor.in_map && driving_aircraft(editor) ? WORLD_FLIGHT_NEAR_CLIP : WORLD_PLAY_NEAR_CLIP
    diameter := structure_lod_projected_diameter(camera, center, radius, f32(rl.GetScreenHeight()), near_plane)
    return structure_lod_select(diameter, previous, force_near)
}

when ODIN_TEST {
    @(test)
    window_flower_boxes_are_deterministic_varied_and_near_target_density :: proc(t: ^testing.T) {
        testing.expect_value(t, window_has_flower_box(1234, 2, 3), window_has_flower_box(1234, 2, 3))

        placements: int
        samples: int
        saw_box, saw_empty := false, false
        for seed in 0 ..< 256 {
            for row in 0 ..< 4 {
                for column in 0 ..< 5 {
                    placed := window_has_flower_box(u32(seed), row, column)
                    placements += placed ? 1 : 0
                    samples += 1
                    saw_box = saw_box || placed
                    saw_empty = saw_empty || !placed
                }
            }
        }

        density := f32(placements) / f32(samples)
        testing.expect(t, saw_box && saw_empty)
        testing.expect(t, density >= .33 && density <= .37)
    }

    @(test)
    structure_lod_selector_uses_balanced_thresholds_and_hysteresis :: proc(t: ^testing.T) {
        structure_lod_force(-1)
        testing.expect_value(t, structure_lod_select(200, .Medium).tier, Structure_LOD.Near)
        testing.expect_value(t, structure_lod_select(100, .Near).tier, Structure_LOD.Medium)
        testing.expect_value(t, structure_lod_select(30, .Medium).tier, Structure_LOD.Far)
        testing.expect_value(t, structure_lod_select(50, .Far).tier, Structure_LOD.Far)
        testing.expect_value(t, structure_lod_select(60, .Far).tier, Structure_LOD.Medium)
        testing.expect_value(t, structure_lod_select(150, .Near).tier, Structure_LOD.Near)
        testing.expect_value(t, structure_lod_select(170, .Medium).tier, Structure_LOD.Medium)
        testing.expect_value(t, structure_lod_select(1, .Far, true).tier, Structure_LOD.Near)
    }

    @(test)
    structure_lod_projection_accounts_for_focal_length_and_near_plane :: proc(t: ^testing.T) {
        camera := Perspective_Camera {
            position = {0, 0, 0},
            forward = {0, 0, -1},
            right = {1, 0, 0},
            up = {0, 1, 0},
            focal_length = 1,
        }
        diameter := structure_lod_projected_diameter(camera, {0, 0, -10}, 1, 1000, .2)
        testing.expect(t, math.abs(diameter - 100) < .001)
        camera.focal_length = 2
        testing.expect(t, math.abs(structure_lod_projected_diameter(camera, {0, 0, -10}, 1, 1000, .2) - 200) < .001)
        testing.expect(t, structure_lod_projected_diameter(camera, {0, 0, -.5}, 1, 1000, .2) >= 1e8)
    }

    @(test)
    static_frustum_is_conservative_at_planes_and_rejects_clear_misses :: proc(t: ^testing.T) {
        camera := Perspective_Camera {
            position = {},
            forward = {0, 0, -1},
            right = {1, 0, 0},
            up = {0, 1, 0},
            focal_length = 1,
        }
        testing.expect(t, static_sphere_in_frustum(camera, {0, 0, -10}, 1, 16.0 / 9.0, .2, 100))
        testing.expect(t, static_sphere_in_frustum(camera, {18.7, 0, -10}, 1, 16.0 / 9.0, .2, 100))
        testing.expect(t, !static_sphere_in_frustum(camera, {30, 0, -10}, 1, 16.0 / 9.0, .2, 100))
        testing.expect(t, !static_sphere_in_frustum(camera, {0, 0, 4}, 1, 16.0 / 9.0, .2, 100))
        testing.expect(t, static_sphere_in_frustum(camera, {0, 0, -.1}, 1, 16.0 / 9.0, .2, 100))
    }

    @(test)
    world_host_buffer_growth_covers_required_bytes :: proc(t: ^testing.T) {
        testing.expect_value(t, world_host_buffer_growth_size(0, 64), vk.DeviceSize(64))
        testing.expect_value(t, world_host_buffer_growth_size(64, 32), vk.DeviceSize(64))
        testing.expect_value(t, world_host_buffer_growth_size(64, 65), vk.DeviceSize(128))
        testing.expect_value(t, world_host_buffer_growth_size(64, 256), vk.DeviceSize(256))
    }
}

World_Material_Kind :: enum u32 {
    Plain,
    Water,
    Terrain,
    Foliage,
    Road,
    Lit,
    Eye,
    Vehicle,
    Acorn,
    Bottle_Cap,
}

World_Vertex :: struct {
    position: [3]f32,
    color:    [4]f32,
    kind:     World_Material_Kind,
    normal:   [3]f32,
    // Lit: metallic, roughness. Vehicle: paintable, atlas layer.
    material: [2]f32,
    uv:       [2]f32,
}

World_Land_Surface_Sample :: struct {
    x, z, height: f32,
}

Foliage_Vertex :: struct {
    position: [3]f32,
    uv:       [2]f32,
    color:    [4]f32,
    kind:     u32,
}

Grass_Instance :: struct {
    center: [3]f32,
    size:   [2]f32,
    tile:   u32,
    color:  [4]f32,
}

Architecture_Grass_Footprint :: struct {
    center_x, center_z:     f32,
    half_width, half_depth: f32,
    rotation:               f32,
}

Foliage_Geometry_Cache_Entry :: struct {
    valid:            bool,
    structure:        terrain.Structure,
    distance_bucket:  i32,
    direction_bucket: i32,
    lod:              Structure_LOD,
    lod_transition:   f32,
    world_vertices:   [dynamic]World_Vertex,
    foliage_vertices: [dynamic]Foliage_Vertex,
}

Static_Geometry_Cache_Entry :: struct {
    valid:                  bool,
    structure:              terrain.Structure,
    lod:                    Structure_LOD,
    lod_transition:         f32,
    world_vertices:         [dynamic]World_Vertex,
    world_indices:          [dynamic]u32,
    foliage_vertices:       [dynamic]Foliage_Vertex,
    bougainvillea_vertices: [dynamic]Foliage_Vertex,
}

Climbing_Leaf_Geometry_Cache_Entry :: struct {
    valid:                  bool,
    structure:              terrain.Structure,
    density:                f32,
    detail_tier:            int,
    capture_seed_enabled:   bool,
    capture_seed:           u32,
    world_vertices:         [dynamic]World_Vertex,
    bougainvillea_vertices: [dynamic]Foliage_Vertex,
}

TOWN_MOUSE_CACHE_COUNT :: len(terrain.DEFAULT_ISLAND_SIGNS) * 7 + 2
TOWN_MOUSE_ANIMATION_HZ :: f32(30)
TOWN_MOUSE_TERRAIN_RADIUS :: f32(2.5)

Town_Mouse_Geometry_Cache_Entry :: struct {
    valid:            bool,
    model:            Mouse_Model,
    scale:            f32,
    animation_bucket: i64,
    wind:             [2]f32,
    vertices:         [dynamic]World_Vertex,
}

Terrain_Dirty_Bounds :: struct {
    valid:        bool,
    full_rebuild: bool,
    revision:     u64,
    min_x, min_z: f32,
    max_x, max_z: f32,
}

World_Push :: struct {
    camera_position: [4]f32,
    camera_right:    [4]f32,
    camera_up:       [4]f32,
    camera_forward:  [4]f32,
    projection:      [4]f32,
    fog_color:       [4]f32,
    water:           [4]f32,
    sun:             [4]f32,
}

Sky_Push :: struct {
    camera_right:   [4]f32,
    camera_up:      [4]f32,
    camera_forward: [4]f32,
    sun_direction:  [4]f32,
    moon_direction: [4]f32,
    time_light:     [4]f32,
    wind_cloud:     [4]f32,
    haze_severity:  [4]f32,
}

World_Renderer :: struct {
    editor:                          ^Editor,
    ctx:                             ^engine.Vk_Context,
    pipelines:                       [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    shadow_pipelines:                [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    dynamic_shadow:                  Dynamic_Shadow_State,
    shadow_vertex:                   [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    shadow_vertices:                 [dynamic]World_Vertex,
    dynamic_caster_first:            int,
    dynamic_caster_count:            int,
    road_pipelines:                  [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    sky_pipelines:                   [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    particle_pipelines:              [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    foliage_pipelines:               [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    grass_pipelines:                 [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    layout:                          vk.PipelineLayout,
    sky_layout:                      vk.PipelineLayout,
    foliage_layout:                  vk.PipelineLayout,
    foliage_descriptor_layout:       vk.DescriptorSetLayout,
    foliage_descriptor_pool:         vk.DescriptorPool,
    foliage_descriptor:              vk.DescriptorSet,
    bougainvillea_descriptor:        vk.DescriptorSet,
    grass_descriptor:                vk.DescriptorSet,
    wildflower_descriptor:           vk.DescriptorSet,
    foliage_atlas:                   resources.Image,
    bougainvillea_atlas:             resources.Image,
    grass_atlas:                     resources.Image,
    wildflower_atlas:                resources.Image,
    vehicle_paint_atlas:             resources.Image,
    soda_cap_logo:                   resources.Image,
    vehicle_paint_staging:           [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    vehicle_paint_descriptor_layout: vk.DescriptorSetLayout,
    vehicle_paint_descriptor_pool:   vk.DescriptorPool,
    vehicle_paint_descriptor:        vk.DescriptorSet,
    vertex:                          [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    static_vertex:                   [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    static_index:                    [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    road_vertex:                     [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    foliage_vertex:                  [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    grass_instance:                  [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    wing_trail_vertex:               [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    wing_trail_index:                [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    vertices:                        [dynamic]World_Vertex,
    static_vertices:                 [dynamic]World_Vertex,
    static_indices:                  [dynamic]u32,
    road_vertices:                   [dynamic]World_Vertex,
    foliage_vertices:                [dynamic]Foliage_Vertex,
    bougainvillea_vertices:          [dynamic]Foliage_Vertex,
    grass_instances:                 [dynamic]Grass_Instance,
    wildflower_instances:            [dynamic]Grass_Instance,
    wing_trail_vertices:             [dynamic]World_Vertex,
    wing_trail_indices:              [dynamic]u16,
    wing_trail_optimized_indices:    [dynamic]u16,
    land_surface_samples:            [dynamic]World_Land_Surface_Sample,
    player_vertex_first:             int,
    player_vertex_count:             int,
    player_shadow_receiver:          f32,
    clipmap_vertex:                  [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]engine.Vk_Buffer,
    clipmap_index:                   engine.Vk_Buffer,
    clipmap_full_indices:            u32,
    clipmap_ring_first:              u32,
    clipmap_ring_indices:            u32,
    clipmap_revision:                [engine.MAX_FRAMES_IN_FLIGHT]u64,
    clipmap_center:                  [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS][2]f32,
    clipmap_valid:                   [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]bool,
    clipmap_dirty:                   [engine.MAX_FRAMES_IN_FLIGHT]Terrain_Dirty_Bounds,
    road_mesh:                       roads.Mesh,
    road_graph:                      roads.Graph,
    road_graph_valid:                bool,
    road_revision:                   u64,
    pavement_query:                  roads.Pavement_Query,
    pavement_query_graph:            roads.Graph,
    pavement_query_graph_valid:      bool,
    pavement_query_revision:         u64,
    foliage_geometry_cache:          [dynamic]Foliage_Geometry_Cache_Entry,
    static_geometry_cache:           [dynamic]Static_Geometry_Cache_Entry,
    climbing_leaf_geometry_cache:    [dynamic]Climbing_Leaf_Geometry_Cache_Entry,
    town_mouse_geometry_cache:        [TOWN_MOUSE_CACHE_COUNT]Town_Mouse_Geometry_Cache_Entry,
    marina_geometry_cache:           [MARINA_GEOMETRY_CACHE_CAPACITY]Marina_Geometry_Cache_Entry,
    structure_lod_counts:             [3]int,
    structure_lod_cache_rebuilds:     u64,
    structure_lod_world_vertices:     int,
    structure_lod_foliage_vertices:   int,
    static_visibility:                Static_Visibility_Stats,
    static_visibility_classification: [dynamic]Static_Visibility_Classification,
    structure_visibility_order:       [dynamic]Structure_Visibility_Order,
    structure_visibility_centers:     [dynamic][2]f32,
    structure_visibility_camera:      [2]f32,
    structure_visibility_selected:    int,
    structure_visibility_hovered:     int,
    structure_visibility_order_valid: bool,
    structure_building_spans:         [dynamic]u8,
    structure_candidates:             [dynamic]int,
    initialized:                     bool,
}

world_renderer: World_Renderer

when ODIN_OS == .Windows {
    foreign import adriatic_mesh "system:adriatic_mesh.lib"
} else {
    foreign import adriatic_mesh "system:adriatic_mesh"
}
foreign adriatic_mesh {
    adriatic_optimize_index_buffer :: proc(destination, indices: ^u16, index_count, vertex_count: u32) ---
    adriatic_optimize_unindexed_mesh :: proc(destination_vertices: rawptr, destination_indices: ^u32, source_vertices: rawptr, vertex_count, vertex_stride: u32) -> u32 ---
}

#assert(size_of(World_Push) == 128)
#assert(size_of(Sky_Push) == 128)
#assert(offset_of(Sky_Push, sun_direction) == 48)
#assert(offset_of(Sky_Push, moon_direction) == 64)
#assert(offset_of(Sky_Push, time_light) == 80)
#assert(offset_of(Sky_Push, wind_cloud) == 96)
#assert(offset_of(Sky_Push, haze_severity) == 112)

world_host_buffer_growth_size :: proc(current, required: vk.DeviceSize) -> vk.DeviceSize {
    if required <= current do return current
    if current == 0 do return required
    return max(current * 2, required)
}

world_host_buffer_create :: proc(
    ctx: ^engine.Vk_Context,
    size: vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    buffer: ^engine.Vk_Buffer,
    name: string,
) -> bool {
    if !engine.vk_create_host_buffer(ctx, size, usage, buffer) do return false
    engine.vk_set_debug_name(ctx, .BUFFER, auto_cast buffer.handle, name)
    engine.vk_set_debug_name(ctx, .DEVICE_MEMORY, auto_cast buffer.memory, name)
    return true
}

world_host_buffer_ensure :: proc(
    ctx: ^engine.Vk_Context,
    buffer: ^engine.Vk_Buffer,
    required: vk.DeviceSize,
    usage: vk.BufferUsageFlags,
    name: string,
) -> bool {
    if ctx == nil || buffer == nil do return false
    if required <= buffer.size do return true
    replacement: engine.Vk_Buffer
    size := world_host_buffer_growth_size(buffer.size, required)
    if !world_host_buffer_create(ctx, size, usage, &replacement, name) do return false
    engine.vk_destroy_buffer(ctx, buffer)
    buffer^ = replacement
    return true
}

world_frame_geometry_buffers_ensure :: proc(frame: int) -> bool {
    if frame < 0 || frame >= engine.MAX_FRAMES_IN_FLIGHT do return false
    ctx := world_renderer.ctx
    if ctx == nil do return false
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.vertex[frame],
        vk.DeviceSize(len(world_renderer.vertices) * size_of(World_Vertex)),
        {.VERTEX_BUFFER},
        "world dynamic vertex buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.static_vertex[frame],
        vk.DeviceSize(len(world_renderer.static_vertices) * size_of(World_Vertex)),
        {.VERTEX_BUFFER},
        "world static vertex buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.static_index[frame],
        vk.DeviceSize(len(world_renderer.static_indices) * size_of(u32)),
        {.INDEX_BUFFER},
        "world static index buffer",
    ) {
        return false
    }
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.road_vertex[frame],
        vk.DeviceSize(len(world_renderer.road_vertices) * size_of(World_Vertex)),
        {.VERTEX_BUFFER},
        "world road vertex buffer",
    ) {
        return false
    }
    foliage_count := len(world_renderer.foliage_vertices) + len(world_renderer.bougainvillea_vertices)
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.foliage_vertex[frame],
        vk.DeviceSize(foliage_count * size_of(Foliage_Vertex)),
        {.VERTEX_BUFFER},
        "world foliage vertex buffer",
    ) {
        return false
    }
    grass_count := len(world_renderer.grass_instances) + len(world_renderer.wildflower_instances)
    if !world_host_buffer_ensure(
        ctx,
        &world_renderer.grass_instance[frame],
        vk.DeviceSize(grass_count * size_of(Grass_Instance)),
        {.VERTEX_BUFFER},
        "world grass instance buffer",
    ) {
        return false
    }
    return true
}

world_buffer_total_size :: proc(buffers: []engine.Vk_Buffer) -> u64 {
    total: u64
    for buffer in buffers do total += u64(buffer.size)
    return total
}

world_buffer_min_size :: proc(buffers: []engine.Vk_Buffer) -> u64 {
    if len(buffers) == 0 do return 0
    minimum := u64(buffers[0].size)
    for buffer in buffers[1:] do minimum = min(minimum, u64(buffer.size))
    return minimum
}

@(no_instrumentation)
world_color :: #force_inline proc(color: rl.Color) -> [4]f32 {
    return {f32(color.r) / 255, f32(color.g) / 255, f32(color.b) / 255, f32(color.a) / 255}
}

world_srgb_to_linear_channel :: proc(value: f32) -> f32 {
    clamped := clamp(value, 0, 1)
    if clamped <= .04045 do return clamped / 12.92
    return f32(math.pow(f64((clamped + .055) / 1.055), 2.4))
}

world_linear_to_srgb_channel :: proc(value: f32) -> f32 {
    clamped := clamp(value, 0, 1)
    if clamped <= .0031308 do return clamped * 12.92
    return 1.055 * f32(math.pow(f64(clamped), 1.0 / 2.4)) - .055
}

world_gltf_material_color :: proc(tint: rl.Color, factor: [4]f32, alpha: u8) -> [4]f32 {
    // glTF factors are linear while palette tints are authored as sRGB. Return
    // sRGB here because world.slang performs the shared vertex-color decode.
    return {
        world_linear_to_srgb_channel(world_srgb_to_linear_channel(f32(tint.r) / 255) * clamp(factor[0], 0, 1)),
        world_linear_to_srgb_channel(world_srgb_to_linear_channel(f32(tint.g) / 255) * clamp(factor[1], 0, 1)),
        world_linear_to_srgb_channel(world_srgb_to_linear_channel(f32(tint.b) / 255) * clamp(factor[2], 0, 1)),
        f32(tint.a) / 255 * clamp(factor[3], 0, 1) * f32(alpha) / 255,
    }
}

world_sky_horizon_color :: proc(sky: atmosphere.Sky_State) -> rl.Color {
    horizon := rl.Color{184, 209, 209, 255}
    storm := clamp(sky.weather.severity * .68 + sky.weather.precipitation * .52, 0, 1)
    storm_horizon := color_lerp({92, 110, 117, 255}, {112, 125, 128, 255}, sky.weather.haze * .55)
    horizon = color_lerp(horizon, storm_horizon, storm * .82)
    horizon = color_lerp({24, 40, 59, 255}, horizon, sky.daylight)
    return {
        u8(clamp(f32(horizon.r) + 255 * .34 * sky.twilight, 0, 255)),
        u8(clamp(f32(horizon.g) + 255 * .16 * sky.twilight, 0, 255)),
        u8(clamp(f32(horizon.b) + 255 * .08 * sky.twilight, 0, 255)),
        255,
    }
}

world_camera_near_clip :: proc(editor: ^Editor) -> f32 {
    if editor == nil do return WORLD_EDITOR_NEAR_CLIP
    if editor.in_map {
        return driving_aircraft(editor) ? WORLD_FLIGHT_NEAR_CLIP : WORLD_PLAY_NEAR_CLIP
    }
    // A fixed 100 m editor near plane is appropriate for island overviews but
    // clips the selected tree, roots, and understory when the author zooms in.
    // Scale with orbit distance while retaining the old cap for distant views.
    distance := editor.editor_camera.distance
    return clamp(distance * distance / 720, f32(2), WORLD_EDITOR_NEAR_CLIP)
}

world_scene_sun :: proc(editor: ^Editor, sky: atmosphere.Sky_State) -> [4]f32 {
    if editor != nil && editor.vehicle_paint_scene {
        // The paint hangar uses a brighter studio key so colors and surface
        // coverage remain easy to judge around the full aircraft.
        return {.28, .88, .38, 1.6}
    }
    return {sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2], sky.daylight}
}

@(no_instrumentation)
world_vertex :: #force_inline proc(point: third_person.Vec3, color: rl.Color) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), .Plain, {0, 1, 0}, {}, {}}
}

@(no_instrumentation)
world_water_vertex :: #force_inline proc(point: third_person.Vec3, color: rl.Color) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), .Water, {0, 1, 0}, {}, {}}
}

@(no_instrumentation)
world_foliage_vertex :: #force_inline proc(
    point: third_person.Vec3,
    color: rl.Color,
    normal: third_person.Vec3,
) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), .Foliage, {normal.x, normal.y, normal.z}, {}, {}}
}

@(no_instrumentation)
world_eye_vertex :: #force_inline proc(
    point: third_person.Vec3,
    color: rl.Color,
    normal: third_person.Vec3,
) -> World_Vertex {
    return {{point.x, point.y, point.z}, world_color(color), .Eye, {normal.x, normal.y, normal.z}, {}, {}}
}

@(no_instrumentation)
world_triangle :: #force_inline proc(a, b, c: third_person.Vec3, color: rl.Color) {
    append(&world_renderer.vertices, world_vertex(a, color), world_vertex(b, color), world_vertex(c, color))
}

@(no_instrumentation)
world_triangle_smooth_lit :: #force_inline proc(
    a, b, c: third_person.Vec3,
    normal_a, normal_b, normal_c: third_person.Vec3,
    color_a, color_b, color_c: rl.Color,
    roughness: f32 = .9,
) {
    points := [3]third_person.Vec3{a, b, c}
    normals := [3]third_person.Vec3{normal_a, normal_b, normal_c}
    colors := [3]rl.Color{color_a, color_b, color_c}
    vertices: [3]World_Vertex
    for index in 0 ..< 3 {
        vertices[index] = world_vertex(points[index], colors[index])
        vertices[index].kind = .Lit
        normal := linalg.normalize0(normals[index])
        vertices[index].normal = {normal.x, normal.y, normal.z}
        vertices[index].material = {0, clamp(roughness, .04, 1)}
    }
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_aircraft_triangle :: #force_inline proc(
    a, b, c: third_person.Vec3,
    color: rl.Color,
    uv_a, uv_b, uv_c: [2]f32,
    paint_layer: f32,
    paintable := true,
) {
    vertices := [3]World_Vertex{world_vertex(a, color), world_vertex(b, color), world_vertex(c, color)}
    normal := linalg.normalize0(linalg.cross((b - a), (c - a)))
    for &vertex in vertices {
        vertex.kind = .Vehicle
        vertex.material[0] = paintable ? 1 : 0
        vertex.material[1] = paint_layer
        vertex.normal = {normal.x, normal.y, normal.z}
    }
    vertices[0].uv = uv_a
    vertices[1].uv = uv_b
    vertices[2].uv = uv_c
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_aircraft_triangle_smooth :: #force_inline proc(
    a, b, c: third_person.Vec3,
    normal_a, normal_b, normal_c: third_person.Vec3,
    color: rl.Color,
    uv_a, uv_b, uv_c: [2]f32,
    paint_layer: f32,
    paintable := true,
) {
    vertices := [3]World_Vertex{world_vertex(a, color), world_vertex(b, color), world_vertex(c, color)}
    normals := [3]third_person.Vec3{normal_a, normal_b, normal_c}
    uvs := [3][2]f32{uv_a, uv_b, uv_c}
    for index in 0 ..< 3 {
        vertices[index].kind = .Vehicle
        vertices[index].material[0] = paintable ? 1 : 0
        vertices[index].material[1] = paint_layer
        normal := linalg.normalize0(normals[index])
        vertices[index].normal = {normal.x, normal.y, normal.z}
        vertices[index].uv = uvs[index]
    }
    append(&world_renderer.vertices, ..vertices[:])
}

@(no_instrumentation)
world_triangle_colored :: #force_inline proc(a, b, c: third_person.Vec3, color_a, color_b, color_c: rl.Color) {
    append(&world_renderer.vertices, world_vertex(a, color_a), world_vertex(b, color_b), world_vertex(c, color_c))
}

world_greek_asset_vertex :: proc(
    point: third_person.Vec3,
    color: [4]f32,
    normal: third_person.Vec3,
    metallic, roughness: f32,
) -> World_Vertex {
    return {
        {point.x, point.y, point.z},
        color,
        .Lit,
        {normal.x, normal.y, normal.z},
        {clamp(metallic, 0, 1), clamp(roughness, .04, 1)},
        {},
    }
}

world_greek_asset_primitive :: proc(
    asset: Greek_Asset,
    placement: Greek_Placement,
    first, count: int,
    color: [4]f32,
    metallic, roughness: f32,
) {
    end := min(first + count, len(asset.mesh.indices))
    for index := max(first, 0); index + 2 < end; index += 3 {
        ia, ib, ic := asset.mesh.indices[index], asset.mesh.indices[index + 1], asset.mesh.indices[index + 2]
        if ia >= u32(len(asset.mesh.vertices)) || ib >= u32(len(asset.mesh.vertices)) || ic >= u32(len(asset.mesh.vertices)) do continue
        a := greek_asset_local_to_world(asset, placement, asset.mesh.vertices[ia])
        b := greek_asset_local_to_world(asset, placement, asset.mesh.vertices[ib])
        c := greek_asset_local_to_world(asset, placement, asset.mesh.vertices[ic])
        normal := linalg.normalize0(
            linalg.cross(
                third_person.Vec3{b.x - a.x, b.y - a.y, b.z - a.z},
                third_person.Vec3{c.x - a.x, c.y - a.y, c.z - a.z},
            ),
        )
        append(
            &world_renderer.vertices,
            world_greek_asset_vertex(a, color, normal, metallic, roughness),
            world_greek_asset_vertex(b, color, normal, metallic, roughness),
            world_greek_asset_vertex(c, color, normal, metallic, roughness),
        )
    }
}

world_greek_asset_mesh :: proc(asset: Greek_Asset, placement: Greek_Placement, alpha: u8) {
    if !asset.ready do return
    if len(asset.mesh.primitives) == 0 {
        world_greek_asset_primitive(
            asset,
            placement,
            0,
            len(asset.mesh.indices),
            world_gltf_material_color(asset.color, {1, 1, 1, 1}, alpha),
            0,
            1,
        )
        return
    }
    for primitive, primitive_index in asset.mesh.primitives {
        metallic: f32 = 1
        roughness: f32 = 1
        if primitive_index < len(asset.mesh.metallic_factors) do metallic = asset.mesh.metallic_factors[primitive_index]
        if primitive_index < len(asset.mesh.roughness_factors) do roughness = asset.mesh.roughness_factors[primitive_index]
        world_greek_asset_primitive(
            asset,
            placement,
            primitive.first,
            primitive.count,
            world_gltf_material_color(asset.color, primitive.base_color, alpha),
            metallic,
            roughness,
        )
    }
}

world_greek_assets :: proc(editor: ^Editor) {
    if editor == nil do return
    for placement in editor.greek_placements[:editor.greek_placement_count] {
        if placement.asset_index < 0 || placement.asset_index >= GREEK_ASSET_CAPACITY do continue
        world_greek_asset_mesh(editor.greek_assets[placement.asset_index], placement, 255)
    }
    if editor.greek_placement_mode && editor.cursor_hit && greek_asset_selected_ready(editor) {
        preview := Greek_Placement {
            asset_index = editor.greek_asset_selected,
            x           = editor.cursor_world_x,
            z           = editor.cursor_world_z,
            base_y      = terrain.sample_height(&editor.project, 0, editor.cursor_world_x, editor.cursor_world_z),
            rotation    = editor.greek_asset_rotation,
            scale       = editor.greek_asset_scale,
        }
        world_greek_asset_mesh(editor.greek_assets[editor.greek_asset_selected], preview, 128)
    }
}

@(no_instrumentation)
world_triangle_foliage :: #force_inline proc(
    a, b, c: third_person.Vec3,
    color_a, color_b, color_c: rl.Color,
    normal_a, normal_b, normal_c: third_person.Vec3,
) {
    append(
        &world_renderer.vertices,
        world_foliage_vertex(a, color_a, normal_a),
        world_foliage_vertex(b, color_b, normal_b),
        world_foliage_vertex(c, color_c, normal_c),
    )
}

@(no_instrumentation)
world_quad :: #force_inline proc(a, b, c, d: third_person.Vec3, color: rl.Color) {
    world_triangle(a, b, c, color)
    world_triangle(a, c, d, color)
}

world_quad_colored :: proc(a, b, c, d: third_person.Vec3, color_a, color_b, color_c, color_d: rl.Color) {
    world_triangle_colored(a, b, c, color_a, color_b, color_c)
    world_triangle_colored(a, c, d, color_a, color_c, color_d)
}

@(no_instrumentation)
world_water_quad :: #force_inline proc(a, b, c, d: third_person.Vec3, color: rl.Color) {
    append(
        &world_renderer.vertices,
        world_water_vertex(a, color),
        world_water_vertex(b, color),
        world_water_vertex(c, color),
        world_water_vertex(a, color),
        world_water_vertex(c, color),
        world_water_vertex(d, color),
    )
}

@(no_instrumentation)
world_boat_part_color :: proc(class: boats.Class, part: boats.Part) -> rl.Color {
    switch part {
    case .Hull:
        switch class {
        case .Dinghy:
            return {211, 204, 169, 255}
        case .Motor:
            return {226, 231, 220, 255}
        case .Sail:
            return {215, 224, 217, 255}
        case .Fishing:
            return {56, 115, 129, 255}
        case .Tug:
            return {151, 48, 37, 255}
        }
    case .Deck:
        return {214, 199, 166, 255}
    case .Cabin:
        return class == .Tug ? rl.Color{235, 205, 119, 255} : rl.Color{225, 224, 205, 255}
    case .Glass:
        return {67, 115, 133, 255}
    case .Metal:
        return {68, 73, 71, 255}
    case .Sail:
        return {241, 233, 205, 255}
    case .Accent:
        return class == .Sail ? rl.Color{189, 74, 51, 255} : rl.Color{204, 119, 50, 255}
    case .Tire:
        return {35, 39, 38, 255}
    }
    return {220, 220, 210, 255}
}

@(no_instrumentation)
world_boat_point :: #force_inline proc(
    local: [3]f32,
    position: third_person.Vec3,
    yaw_cos, yaw_sin: f32,
) -> third_person.Vec3 {
    c, s := yaw_cos, yaw_sin
    return {position.x + local.x * c - local.z * s, position.y + local.y, position.z + local.x * s + local.z * c}
}

@(no_instrumentation)
world_boat_triangle :: proc(a, b, c: third_person.Vec3, color: rl.Color, part: boats.Part) {
    normal := linalg.normalize0(linalg.cross(b - a, c - a))
    metallic := part == .Metal ? f32(.62) : f32(0)
    roughness := part == .Glass ? f32(.24) : f32(.78)
    vertex_a := world_vertex(a, color)
    vertex_b := world_vertex(b, color)
    vertex_c := world_vertex(c, color)
    vertices := [3]^World_Vertex{&vertex_a, &vertex_b, &vertex_c}
    for vertex in vertices {
        vertex.kind = .Lit
        vertex.normal = {normal.x, normal.y, normal.z}
        vertex.material = {metallic, roughness}
    }
    append(&world_renderer.vertices, vertex_a, vertex_b, vertex_c)
}

world_npc_boat :: proc(class: boats.Class, position: third_person.Vec3, yaw: f32, sails_raised: bool = true) {
    mesh := boats.cached_mesh(class)
    if mesh == nil do return
    yaw_cos, yaw_sin := math.cos(yaw), math.sin(yaw)
    for face in boats.triangles(mesh) {
        a, b, c := mesh.vertices[face.a], mesh.vertices[face.b], mesh.vertices[face.c]
        if class == .Sail && !sails_raised && (a.part == .Sail || a.part == .Accent) {
            continue
        }
        world_boat_triangle(
            world_boat_point(a.position, position, yaw_cos, yaw_sin),
            world_boat_point(b.position, position, yaw_cos, yaw_sin),
            world_boat_point(c.position, position, yaw_cos, yaw_sin),
            world_boat_part_color(class, a.part),
            a.part,
        )
    }
}

world_npc_boats :: proc(editor: ^Editor) {
    if editor == nil do return
    for agent in editor.boat_traffic.agents[:editor.boat_traffic.count] {
        position := third_person.Vec3{agent.position.x, editor.project.sea_level + .03, agent.position.y}
        bob := math.sin(editor.map_time * .72 + f32(agent.class) * 1.31) * (.025 + agent.speed * .004)
        position.y += bob
        world_npc_boat(agent.class, position, agent.yaw, agent.behavior != .Moored)
    }
}

world_boat_wake_quad :: proc(
    center: boats.Vec2,
    direction: boats.Vec2,
    half_width, half_length: f32,
    color: rl.Color,
    y: f32,
) {
    right := boats.Vec2{-direction.y, direction.x}
    p0 := center - right * half_width - direction * half_length
    p1 := center - right * half_width + direction * half_length
    p2 := center + right * half_width + direction * half_length
    p3 := center + right * half_width - direction * half_length
    // Reverse the planar order so the foam faces upward under CCW culling.
    world_quad({p0.x, y, p0.y}, {p3.x, y, p3.y}, {p2.x, y, p2.y}, {p1.x, y, p1.y}, color)
}

world_boat_wakes :: proc(editor: ^Editor) {
    if editor == nil do return
    y := editor.project.sea_level + .055
    for agent in editor.boat_traffic.agents[:editor.boat_traffic.count] {
        spec := boats.specifications(agent.class)
        for sample_index in 0 ..< agent.wake_count {
            sample := agent.wake[sample_index]
            fade := clamp(1 - sample.age / sample.lifetime, 0, 1)
            if fade <= .01 do continue
            age_spread := sample.age * (.18 + sample.strength * .32)
            right := boats.Vec2{-sample.direction.y, sample.direction.x}
            arm_offset := sample.width * .48 + age_spread
            arm_width := clamp(sample.width * (.045 + fade * .045), f32(.055), f32(.46))
            arm_length := clamp(spec.beam * (.10 + sample.strength * .12), f32(.22), f32(1.75))
            alpha := u8(clamp(92 * sample.strength * fade * fade, 0, 92))
            foam := rl.Color{210, 237, 232, alpha}
            port := sample.position + right * arm_offset
            starboard := sample.position - right * arm_offset
            world_boat_wake_quad(port, sample.direction, arm_width, arm_length, foam, y)
            world_boat_wake_quad(starboard, sample.direction, arm_width, arm_length, foam, y)
            // Heavy displacement leaves a softer centerline boil; high-power
            // planing craft emphasize the divergent arms instead.
            displacement_mix := clamp(spec.displacement_kg / 350000, 0, 1)
            center_alpha := u8(f32(alpha) * (.12 + displacement_mix * .24))
            world_boat_wake_quad(
                sample.position,
                sample.direction,
                min(arm_width * (1.1 + displacement_mix * .45), f32(.62)),
                min(arm_length * .62, f32(1.05)),
                {220, 240, 235, center_alpha},
                y + .002,
            )
        }
    }
}

@(no_instrumentation)
road_world_point :: #force_inline proc(editor: ^Editor, vertex: roads.Vertex) -> third_person.Vec3 {
    clearance := f32(.12)
    if vertex.surface == .Shoulder {
        clearance = .05
    } else if vertex.surface == .Verge {
        clearance = .018
    }
    terrain_y := terrain.sample_height(&editor.project, 0, vertex.position.x, vertex.position.z)
    return {vertex.position.x, max(vertex.position.y, terrain_y + clearance), vertex.position.z}
}

@(no_instrumentation)
road_surface_color :: #force_inline proc(surface: roads.Surface, pavement: roads.Pavement) -> rl.Color {
    if surface == .Verge {
        // Outer verge vertices are transparent and interpolate into the opaque
        // shoulder, revealing terrain through a soft, pavement-aware tint.
        switch pavement {
        case .Asphalt:
            return {82, 111, 67, 0}
        case .Gravel:
            return {105, 119, 70, 0}
        case .Cobblestone:
            return {92, 112, 69, 0}
        case .Dirt:
            return {118, 101, 58, 0}
        }
    }
    if surface == .Shoulder {
        switch pavement {
        case .Asphalt:
            return {164, 148, 116, 255}
        case .Gravel:
            return {183, 163, 126, 255}
        case .Cobblestone:
            return {151, 146, 126, 255}
        case .Dirt:
            return {139, 96, 61, 255}
        }
    }
    switch pavement {
    case .Asphalt:
        return surface == .Junction ? rl.Color{86, 92, 86, 255} : rl.Color{91, 97, 90, 255}
    case .Gravel:
        return {158, 143, 111, 255}
    case .Cobblestone:
        return {119, 130, 124, 255}
    case .Dirt:
        return {158, 104, 61, 255}
    }
    return {91, 97, 90, 255}
}

world_road_editor_link :: proc(a, b: roads.Vec3, width: f32, color: rl.Color) {
    dx, dz := b.x - a.x, b.z - a.z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= .001 do return
    side_x, side_z := -dz / length * width * .5, dx / length * width * .5
    lift := f32(.12)
    world_quad(
        {a.x - side_x, a.y + lift, a.z - side_z},
        {b.x - side_x, b.y + lift, b.z - side_z},
        {b.x + side_x, b.y + lift, b.z + side_z},
        {a.x + side_x, a.y + lift, a.z + side_z},
        color,
    )
}

@(no_instrumentation)
world_road_vertex :: #force_inline proc(editor: ^Editor, vertex: roads.Vertex, color: rl.Color) -> World_Vertex {
    point := road_world_point(editor, vertex)
    // Road UV and pavement live in the normal channel because the dedicated
    // road pass does not need the generic mesh normal. This keeps the existing
    // compact vertex format and draw call while giving the fragment shader
    // stable material-space coordinates.
    return {
        {point.x, point.y, point.z},
        world_color(color),
        .Road,
        {vertex.uv[0], vertex.uv[1], f32(vertex.pavement)},
        {},
        {},
    }
}

@(no_instrumentation)
world_road_triangle_colored :: #force_inline proc(
    editor: ^Editor,
    a, b, c: roads.Vertex,
    color_a, color_b, color_c: rl.Color,
) {
    land_threshold := editor.project.sea_level + .04
    if terrain.sample_height(&editor.project, 0, a.position.x, a.position.z) <= land_threshold ||
       terrain.sample_height(&editor.project, 0, b.position.x, b.position.z) <= land_threshold ||
       terrain.sample_height(&editor.project, 0, c.position.x, c.position.z) <= land_threshold {
        return
    }
    append(
        &world_renderer.road_vertices,
        world_road_vertex(editor, a, color_a),
        world_road_vertex(editor, b, color_b),
        world_road_vertex(editor, c, color_c),
    )
}

world_roads :: proc(editor: ^Editor) {
    if editor == nil do return
    graph := &editor.project.road_graph
    if !world_renderer.road_graph_valid || world_renderer.road_revision != editor.project.revision {
        if !world_renderer.road_graph_valid || world_renderer.road_graph != graph^ {
            roads.mesh_destroy(&world_renderer.road_mesh)
            if graph.edge_count > 0 do world_renderer.road_mesh = roads.bake(graph)
            world_renderer.road_graph = graph^
            world_renderer.road_graph_valid = true
        }
        world_renderer.road_revision = editor.project.revision
    }
    mesh := &world_renderer.road_mesh
    if len(mesh.indices) > 0 {
        for triangle in 0 ..< len(mesh.indices) / 3 {
            a := mesh.vertices[mesh.indices[triangle * 3]]
            b := mesh.vertices[mesh.indices[triangle * 3 + 1]]
            c := mesh.vertices[mesh.indices[triangle * 3 + 2]]
            world_road_triangle_colored(
                editor,
                a,
                b,
                c,
                road_surface_color(a.surface, a.pavement),
                road_surface_color(b.surface, b.pavement),
                road_surface_color(c.surface, c.pavement),
            )
        }
    }
    if editor.in_map || !editor.road_mode || editor.capture_world_only do return
    for node, index in graph.nodes[:graph.node_count] {
        selected := index == editor.road_selected_node
        color: rl.Color = selected ? {244, 216, 103, 255} : {101, 226, 203, 255}
        size := selected ? f32(4.5) : f32(3.2)
        world_box({node.position.x, node.position.y + 1.3, node.position.z}, {size, 2.6, size}, color)
    }
    if editor.road_selected_node < 0 || editor.road_selected_node >= graph.node_count do return
    for edge in graph.edges[:graph.edge_count] {
        if edge.from != editor.road_selected_node && edge.to != editor.road_selected_node do continue
        start := graph.nodes[edge.from].position
        end := graph.nodes[edge.to].position
        world_road_editor_link(start, edge.control_from, .75, {76, 196, 191, 230})
        world_road_editor_link(end, edge.control_to, .75, {76, 196, 191, 230})
        world_box(
            {edge.control_from.x, edge.control_from.y + 1.1, edge.control_from.z},
            {3, 2.2, 3},
            {83, 232, 225, 255},
        )
        world_box({edge.control_to.x, edge.control_to.y + 1.1, edge.control_to.z}, {3, 2.2, 3}, {83, 232, 225, 255})
    }
}

world_ocean :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    extent := editor.in_map ? f32(12000) : f32(15000)
    divisions := editor.in_map ? 48 : 32
    cell := extent * 2 / f32(divisions)
    // A snapped tiled field surrounds the camera in every direction. Unlike the
    // former forward slab, it has no near edge for a high, downward-looking
    // camera to expose at the bottom of the viewport.
    center_x := f32(math.floor(f64(camera.position.x / cell))) * cell
    center_z := f32(math.floor(f64(camera.position.z / cell))) * cell
    ocean_y := editor.project.sea_level - (editor.in_map ? f32(.08) : f32(2))
    color := rl.Color{48, 112, 142, 255}
    for z_index in 0 ..< divisions {
        z0 := center_z - extent + f32(z_index) * cell
        z1 := z0 + cell
        for x_index in 0 ..< divisions {
            x0 := center_x - extent + f32(x_index) * cell
            x1 := x0 + cell
            // Reverse winding so the ocean's upward face is the front (CCW) face
            // and survives back-face culling from a downward-looking camera.
            world_water_quad({x0, ocean_y, z0}, {x0, ocean_y, z1}, {x1, ocean_y, z1}, {x1, ocean_y, z0}, color)
        }
    }
}

world_box :: proc(center, size: third_person.Vec3, color: rl.Color) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p := [8]third_person.Vec3 {
        {center.x - x, center.y - y, center.z - z},
        {center.x + x, center.y - y, center.z - z},
        {center.x + x, center.y + y, center.z - z},
        {center.x - x, center.y + y, center.z - z},
        {center.x - x, center.y - y, center.z + z},
        {center.x + x, center.y - y, center.z + z},
        {center.x + x, center.y + y, center.z + z},
        {center.x - x, center.y + y, center.z + z},
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

@(no_instrumentation)
clipmap_vertex_color :: #force_inline proc(editor: ^Editor, level: int, x, z, height: f32) -> rl.Color {
    cell := editor.project.levels[level].cell_size
    left := terrain.sample_height(&editor.project, level, x - cell, z)
    right := terrain.sample_height(&editor.project, level, x + cell, z)
    back := terrain.sample_height(&editor.project, level, x, z - cell)
    front := terrain.sample_height(&editor.project, level, x, z + cell)
    normal := linalg.normalize0(
        linalg.cross(third_person.Vec3{0, front - back, cell * 2}, third_person.Vec3{cell * 2, right - left, 0}),
    )
    light := linalg.normalize0(third_person.Vec3{-.45, .85, -.3})
    shade := clamp(.48 + max(linalg.dot(normal, light), 0) * .52, .42, 1.05)
    base := terrain_color(
        max(height, editor.project.sea_level + .12),
        terrain.sample_material(&editor.project, level, x, z),
        editor.project.sea_level,
        x,
        z,
    )
    return {
        u8(clamp(f32(base.r) * shade, 0, 255)),
        u8(clamp(f32(base.g) * shade, 0, 255)),
        u8(clamp(f32(base.b) * shade, 0, 255)),
        255,
    }
}

clipmap_update_level :: proc(
    editor: ^Editor,
    frame_index, level: int,
    center: [2]f32,
    dirty: ^Terrain_Dirty_Bounds = nil,
) {
    buffer := &world_renderer.clipmap_vertex[frame_index][level]
    vertices := cast([^]World_Vertex)buffer.mapped
    data := &editor.project.levels[level]
    grid_cell := data.cell_size * 2
    half_grid := f32(CLIPMAP_GRID_RESOLUTION - 1) * .5
    min_x, min_z := 0, 0
    max_x, max_z := CLIPMAP_GRID_RESOLUTION - 1, CLIPMAP_GRID_RESOLUTION - 1
    if dirty != nil {
        padding := data.cell_size * 2
        grid_min_x := center[0] - half_grid * grid_cell
        grid_min_z := center[1] - half_grid * grid_cell
        grid_max_x := center[0] + half_grid * grid_cell
        grid_max_z := center[1] + half_grid * grid_cell
        if dirty.max_x + padding < grid_min_x ||
           dirty.max_z + padding < grid_min_z ||
           dirty.min_x - padding > grid_max_x ||
           dirty.min_z - padding > grid_max_z {
            return
        }
        min_x = clamp(
            int(math.floor(f64((dirty.min_x - padding - grid_min_x) / grid_cell))),
            0,
            CLIPMAP_GRID_RESOLUTION - 1,
        )
        min_z = clamp(
            int(math.floor(f64((dirty.min_z - padding - grid_min_z) / grid_cell))),
            0,
            CLIPMAP_GRID_RESOLUTION - 1,
        )
        max_x = clamp(
            int(math.ceil(f64((dirty.max_x + padding - grid_min_x) / grid_cell))),
            0,
            CLIPMAP_GRID_RESOLUTION - 1,
        )
        max_z = clamp(
            int(math.ceil(f64((dirty.max_z + padding - grid_min_z) / grid_cell))),
            0,
            CLIPMAP_GRID_RESOLUTION - 1,
        )
    }
    for z in min_z ..= max_z {
        world_z := center[1] + (f32(z) - half_grid) * grid_cell
        for x in min_x ..= max_x {
            world_x := center[0] + (f32(x) - half_grid) * grid_cell
            height := terrain.sample_height(&editor.project, level, world_x, world_z)
            vertex := world_vertex(
                {world_x, height, world_z},
                clipmap_vertex_color(editor, level, world_x, world_z, height),
            )
            vertex.kind = .Terrain
            vertices[z * CLIPMAP_GRID_RESOLUTION + x] = vertex
        }
    }
}

@(no_instrumentation)
world_terrain_structure_intersects :: #force_inline proc(
    structure: terrain.Structure,
    dirty: Terrain_Dirty_Bounds,
) -> bool {
    closest_x := clamp(structure.center_x, dirty.min_x, dirty.max_x)
    closest_z := clamp(structure.center_z, dirty.min_z, dirty.max_z)
    dx, dz := structure.center_x - closest_x, structure.center_z - closest_z
    radius_squared := (structure.width * structure.width + structure.depth * structure.depth) * .25
    return dx * dx + dz * dz <= radius_squared
}

world_terrain_changed :: proc(editor: ^Editor, x, z, radius: f32) {
    if editor == nil do return
    editor.terrain_revision += 1
    revision := editor.terrain_revision
    changed := Terrain_Dirty_Bounds {
        valid    = true,
        revision = revision,
        min_x    = x - radius,
        min_z    = z - radius,
        max_x    = x + radius,
        max_z    = z + radius,
    }
    for &dirty in world_renderer.clipmap_dirty {
        if dirty.valid {
            if dirty.revision + 1 != revision do dirty.full_rebuild = true
            dirty.min_x = min(dirty.min_x, changed.min_x)
            dirty.min_z = min(dirty.min_z, changed.min_z)
            dirty.max_x = max(dirty.max_x, changed.max_x)
            dirty.max_z = max(dirty.max_z, changed.max_z)
            dirty.revision = revision
        } else {
            dirty = changed
        }
    }
    if world_renderer.road_revision != 0 do world_renderer.road_revision = editor.project.revision
    if world_renderer.pavement_query_revision != 0 {
        world_renderer.pavement_query_revision = editor.project.revision
    }
    for &entry in world_renderer.static_geometry_cache {
        if !entry.valid do continue
        if world_terrain_structure_intersects(entry.structure, changed) {
            entry.valid = false
        }
    }
    for &entry in world_renderer.town_mouse_geometry_cache {
        if !entry.valid do continue
        closest_x := clamp(entry.model.position.x, changed.min_x, changed.max_x)
        closest_z := clamp(entry.model.position.z, changed.min_z, changed.max_z)
        dx, dz := entry.model.position.x - closest_x, entry.model.position.z - closest_z
        influence_radius := TOWN_MOUSE_TERRAIN_RADIUS * entry.scale
        if dx * dx + dz * dz <= influence_radius * influence_radius {
            entry.valid = false
        }
    }
}

world_terrain_invalidate_all :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.terrain_revision += 1
    for &dirty in world_renderer.clipmap_dirty {
        dirty = {
            valid        = true,
            full_rebuild = true,
            revision     = editor.terrain_revision,
        }
    }
    for &entry in world_renderer.static_geometry_cache do entry.valid = false
    for &entry in world_renderer.climbing_leaf_geometry_cache do entry.valid = false
    for &entry in world_renderer.town_mouse_geometry_cache do entry.valid = false
}

world_structure_storage_ensure :: proc(count: int) {
    if count <= len(world_renderer.static_geometry_cache) do return
    MINIMUM_CAPACITY :: 64
    capacity := max(count, max(MINIMUM_CAPACITY, len(world_renderer.static_geometry_cache) * 2))
    resize(&world_renderer.foliage_geometry_cache, capacity)
    resize(&world_renderer.static_geometry_cache, capacity)
    resize(&world_renderer.climbing_leaf_geometry_cache, capacity)
    resize(&world_renderer.static_visibility_classification, capacity)
    resize(&world_renderer.structure_visibility_centers, capacity)
    reserve(&world_renderer.structure_visibility_order, capacity)
    resize(&world_renderer.structure_building_spans, capacity)
    reserve(&world_renderer.structure_candidates, capacity)
}

clipmap_update :: proc(editor: ^Editor, frame_index: int) {
    revision_changed := world_renderer.clipmap_revision[frame_index] != editor.terrain_revision
    dirty := &world_renderer.clipmap_dirty[frame_index]
    localized_revision :=
        revision_changed &&
        dirty.valid &&
        !dirty.full_rebuild &&
        dirty.revision == editor.terrain_revision
    snap := editor.project.levels[0].cell_size * 2
    center := [2]f32 {
        f32(math.round(f64(editor.camera_pose.target.x / snap))) * snap,
        f32(math.round(f64(editor.camera_pose.target.z / snap))) * snap,
    }
    for level in 0 ..< terrain.CLIPMAP_LEVELS {
        if revision_changed ||
           !world_renderer.clipmap_valid[frame_index][level] ||
           world_renderer.clipmap_center[frame_index][level] != center {
            center_changed :=
                !world_renderer.clipmap_valid[frame_index][level] ||
                world_renderer.clipmap_center[frame_index][level] != center
            clipmap_update_level(
                editor,
                frame_index,
                level,
                center,
                localized_revision && !center_changed ? dirty : nil,
            )
            world_renderer.clipmap_center[frame_index][level] = center
            world_renderer.clipmap_valid[frame_index][level] = true
        }
    }
    world_renderer.clipmap_revision[frame_index] = editor.terrain_revision
    dirty^ = {}
}

@(no_instrumentation)
clipmap_append_cell :: #force_inline proc(indices: ^[dynamic]u32, x, z: int) {
    row := CLIPMAP_GRID_RESOLUTION
    a := u32(z * row + x)
    b := u32(z * row + x + 1)
    c := u32((z + 1) * row + x + 1)
    d := u32((z + 1) * row + x)
    // Wound so the upward-facing terrain surface is the front (CCW) face, so it
    // survives back-face culling when viewed from above.
    append(indices, a, c, b, a, d, c)
}

clipmap_create_indices :: proc(ctx: ^engine.Vk_Context) -> bool {
    indices := make([dynamic]u32, 0, CLIPMAP_FULL_INDEX_COUNT * 2)
    defer delete(indices)
    for z in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
        for x in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
            clipmap_append_cell(&indices, x, z)
        }
    }
    world_renderer.clipmap_full_indices = u32(len(indices))
    world_renderer.clipmap_ring_first = u32(len(indices))
    hole_min := CLIPMAP_GRID_RESOLUTION / 4
    hole_max := CLIPMAP_GRID_RESOLUTION - hole_min - 1
    for z in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
        for x in 0 ..< CLIPMAP_GRID_RESOLUTION - 1 {
            if x >= hole_min && x < hole_max && z >= hole_min && z < hole_max do continue
            clipmap_append_cell(&indices, x, z)
        }
    }
    world_renderer.clipmap_ring_indices = u32(len(indices)) - world_renderer.clipmap_ring_first
    if !engine.vk_create_host_buffer(
        ctx,
        vk.DeviceSize(len(indices) * size_of(u32)),
        {.INDEX_BUFFER},
        &world_renderer.clipmap_index,
    ) {
        return false
    }
    mem.copy_non_overlapping(world_renderer.clipmap_index.mapped, raw_data(indices[:]), len(indices) * size_of(u32))
    return true
}

world_infrastructure :: proc(editor: ^Editor) {
    half := f32(terrain.WORLD_SIZE_METERS * .5)
    for sign in terrain.DEFAULT_ISLAND_SIGNS {
        x, z := sign * half * terrain.DEFAULT_ISLAND_OFFSET, sign * half * terrain.DEFAULT_ISLAND_OFFSET
        run_l, run_w := half * terrain.DEFAULT_RUNWAY_HALF_LENGTH, half * terrain.DEFAULT_RUNWAY_HALF_WIDTH
        y := terrain.sample_height(&editor.project, 0, x, z) + .05
        world_box({x, y, z}, {run_l * 2, .08, run_w * 2}, {60, 66, 67, 255})
        for marker in -3 ..= 3 {
            mx := x + f32(marker) * run_l * .22
            world_box({mx, y + .06, z}, {run_l * .11, .025, .12}, {238, 232, 186, 255})
        }
        // Run straight out from the island's outer shoreline. The former
        // diagonal endpoints crossed the coast at different Z coordinates,
        // which made the deck read as a detached triangular wedge.
        ix := x + sign * half * terrain.DEFAULT_ISLAND_RADIUS * .62
        ox := x + sign * half * terrain.DEFAULT_ISLAND_RADIUS * 1.18
        iz, oz := z, z
        // Keep the deck level from land to water. Sloping it down to sea level
        // buried most of the mesh inside the island and left only its far tip.
        deck_height := f32(terrain.DEFAULT_ISLAND_HEIGHT + .24)
        iy, oy := deck_height, deck_height
        w := half * .018
        world_quad({ix, iy, iz - w}, {ox, oy, oz - w}, {ox, oy, oz + w}, {ix, iy, iz + w}, {137, 89, 48, 255})
    }
}

@(no_instrumentation)
formation_face_color :: #force_inline proc(base: rl.Color, angle: f32, layer: int) -> rl.Color {
    light := math.cos(angle) * -.45 + math.sin(angle) * -.30
    if base.r > 175 && base.g > 165 && base.b > 135 {
        // Adriatic limestone is pale and cool, with stronger facet separation
        // than the generic formation palette.
        shade := clamp(.78 + light * .38 + f32(layer) * .055, .52, 1.18)
        return {
            r = u8(clamp(f32(base.r) * shade, 0, 255)),
            g = u8(clamp(f32(base.g) * shade * 1.01, 0, 255)),
            b = u8(clamp(f32(base.b) * shade * 1.03, 0, 255)),
            a = base.a,
        }
    }
    shade := clamp(.67 + light * .28 + f32(layer) * .035, .42, 1.05)
    return {
        r = u8(clamp(f32(base.r) * shade, 0, 255)),
        g = u8(clamp(f32(base.g) * shade, 0, 255)),
        b = u8(clamp(f32(base.b) * shade, 0, 255)),
        a = base.a,
    }
}

@(no_instrumentation)
world_rotate_xz :: #force_inline proc(center_x, center_z, x, z, rotation: f32) -> (f32, f32) {
    cosine, sine := math.cos(rotation), math.sin(rotation)
    return center_x + x * cosine - z * sine, center_z + x * sine + z * cosine
}

@(no_instrumentation)
world_land_surface_sample :: #force_inline proc(
    editor: ^Editor,
    center_x, center_z, local_x, local_z, cosine, sine: f32,
) -> World_Land_Surface_Sample {
    x := center_x + local_x * cosine - local_z * sine
    z := center_z + local_x * sine + local_z * cosine
    return {x, z, terrain.sample_height(&editor.project, 0, x, z)}
}

world_box_rotated :: proc(center: third_person.Vec3, size: third_person.Vec3, rotation: f32, color: rl.Color) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p: [8]third_person.Vec3
    local := [8][3]f32 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

// Draw a terrain-following rectangular surface, discarding shoreline cells
// instead of letting a single rigid road or path slab continue over the ocean.
world_land_surface_rotated :: proc(
    editor: ^Editor,
    center_x, center_z, width, length, rotation, lift: f32,
    color: rl.Color,
) {
    if editor == nil || width <= 0 || length <= 0 do return
    columns := max(1, int(math.ceil(f64(width / 2))))
    rows := max(1, int(math.ceil(f64(length / 2))))
    land_threshold := editor.project.sea_level + .04
    cosine, sine := math.cos(rotation), math.sin(rotation)
    samples_per_row := columns + 1
    resize(&world_renderer.land_surface_samples, samples_per_row * 2)
    previous := world_renderer.land_surface_samples[:samples_per_row]
    current := world_renderer.land_surface_samples[samples_per_row:]

    local_z0 := -length * .5
    for column in 0 ..= columns {
        local_x := -width * .5 + width * f32(column) / f32(columns)
        previous[column] = world_land_surface_sample(editor, center_x, center_z, local_x, local_z0, cosine, sine)
    }
    for row in 0 ..< rows {
        local_z1 := -length * .5 + length * f32(row + 1) / f32(rows)
        for column in 0 ..= columns {
            local_x := -width * .5 + width * f32(column) / f32(columns)
            current[column] = world_land_surface_sample(editor, center_x, center_z, local_x, local_z1, cosine, sine)
        }
        for column in 0 ..< columns {
            p00 := previous[column]
            p10 := previous[column + 1]
            p11 := current[column + 1]
            p01 := current[column]
            if p00.height <= land_threshold ||
               p10.height <= land_threshold ||
               p11.height <= land_threshold ||
               p01.height <= land_threshold {
                continue
            }
            world_quad(
                {p00.x, p00.height + lift, p00.z},
                {p01.x, p01.height + lift, p01.z},
                {p11.x, p11.height + lift, p11.z},
                {p10.x, p10.height + lift, p10.z},
                color,
            )
        }
        previous, current = current, previous
    }
}

world_architecture_face_color :: proc(base: rl.Color, normal_x, normal_z: f32, top: bool = false) -> rl.Color {
    // A restrained baked key keeps the plain-color architecture readable
    // without fighting the authored stucco palette or the dynamic sky.
    shade := top ? f32(1.015) : clamp(.955 + normal_x * -.035 + normal_z * -.025, f32(.90), f32(1.01))
    return {
        r = u8(clamp(f32(base.r) * shade, 0, 255)),
        g = u8(clamp(f32(base.g) * shade, 0, 255)),
        b = u8(clamp(f32(base.b) * shade, 0, 255)),
        a = base.a,
    }
}

world_architecture_box_rotated :: proc(
    center: third_person.Vec3,
    size: third_person.Vec3,
    rotation: f32,
    color: rl.Color,
) {
    x, y, z := size.x * .5, size.y * .5, size.z * .5
    p: [8]third_person.Vec3
    local := [8][3]f32 {
        {-x, -y, -z},
        {x, -y, -z},
        {x, y, -z},
        {-x, y, -z},
        {-x, -y, z},
        {x, -y, z},
        {x, y, z},
        {-x, y, z},
    }
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    cosine, sine := f32(math.cos(f64(rotation))), f32(math.sin(f64(rotation)))
    back := world_architecture_face_color(color, sine, -cosine)
    front := world_architecture_face_color(color, -sine, cosine)
    left := world_architecture_face_color(color, -cosine, -sine)
    right := world_architecture_face_color(color, cosine, sine)
    top := world_architecture_face_color(color, 0, 0, true)
    bottom := world_architecture_face_color(color, 0, 0)
    // Preserve the same outward CCW winding as world_box_rotated.
    world_quad(p[0], p[3], p[2], p[1], back)
    world_quad(p[4], p[5], p[6], p[7], front)
    world_quad(p[0], p[4], p[7], p[3], left)
    world_quad(p[1], p[2], p[6], p[5], right)
    world_quad(p[3], p[7], p[6], p[2], top)
    world_quad(p[0], p[1], p[5], p[4], bottom)
}

world_tapered_box_rotated :: proc(
    center: third_person.Vec3,
    height, bottom_width, bottom_depth, top_width, top_depth, rotation: f32,
    color: rl.Color,
) {
    half_height := height * .5
    local := [8][3]f32 {
        {-bottom_width * .5, -half_height, -bottom_depth * .5},
        {bottom_width * .5, -half_height, -bottom_depth * .5},
        {top_width * .5, half_height, -top_depth * .5},
        {-top_width * .5, half_height, -top_depth * .5},
        {-bottom_width * .5, -half_height, bottom_depth * .5},
        {bottom_width * .5, -half_height, bottom_depth * .5},
        {top_width * .5, half_height, top_depth * .5},
        {-top_width * .5, half_height, top_depth * .5},
    }
    p: [8]third_person.Vec3
    for index in 0 ..< 8 {
        world_x, world_z := world_rotate_xz(center.x, center.z, local[index][0], local[index][2], rotation)
        p[index] = {world_x, center.y + local[index][1], world_z}
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

world_vertical_prism :: proc(center: third_person.Vec3, radius_x, radius_z, height, rotation: f32, color: rl.Color) {
    SEGMENTS :: 8
    bottom, top: [SEGMENTS]third_person.Vec3
    half_height := height * .5
    for segment in 0 ..< SEGMENTS {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
        local_x := math.cos(angle) * radius_x
        local_z := math.sin(angle) * radius_z
        world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
        bottom[segment] = {world_x, center.y - half_height, world_z}
        top[segment] = {world_x, center.y + half_height, world_z}
    }
    bottom_center := third_person.Vec3{center.x, center.y - half_height, center.z}
    top_center := third_person.Vec3{center.x, center.y + half_height, center.z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_quad(bottom[segment], top[segment], top[next], bottom[next], color)
        world_triangle(bottom_center, bottom[segment], bottom[next], color)
        world_triangle(top_center, top[next], top[segment], color)
    }
}

world_vertical_disc_rotated :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, depth, rotation: f32,
    color: rl.Color,
) {
    SEGMENTS :: 12
    back, front: [SEGMENTS]third_person.Vec3
    half_depth := depth * .5
    back_x, back_z := world_rotate_xz(center.x, center.z, 0, -half_depth, rotation)
    front_x, front_z := world_rotate_xz(center.x, center.z, 0, half_depth, rotation)
    back_center := third_person.Vec3{back_x, center.y, back_z}
    front_center := third_person.Vec3{front_x, center.y, front_z}
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        local_x := math.cos(angle) * radius_x
        local_y := math.sin(angle) * radius_y
        back_world_x, back_world_z := world_rotate_xz(center.x, center.z, local_x, -half_depth, rotation)
        front_world_x, front_world_z := world_rotate_xz(center.x, center.z, local_x, half_depth, rotation)
        back[segment] = {back_world_x, center.y + local_y, back_world_z}
        front[segment] = {front_world_x, center.y + local_y, front_world_z}
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(back_center, back[next], back[segment], color)
        world_triangle(front_center, front[segment], front[next], color)
        world_quad(back[segment], back[next], front[next], front[segment], color)
    }
}

world_ellipsoid_rotated :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, radius_z, rotation: f32,
    color: rl.Color,
    material_kind: World_Material_Kind = .Eye,
) {
    LATITUDE_SEGMENTS :: 6
    LONGITUDE_SEGMENTS :: 10
    points: [LATITUDE_SEGMENTS + 1][LONGITUDE_SEGMENTS]third_person.Vec3
    normals: [LATITUDE_SEGMENTS + 1][LONGITUDE_SEGMENTS]third_person.Vec3
    for latitude in 0 ..= LATITUDE_SEGMENTS {
        latitude_angle := -math.PI * .5 + f32(latitude) * math.PI / f32(LATITUDE_SEGMENTS)
        latitude_radius := math.cos(latitude_angle)
        local_y := math.sin(latitude_angle) * radius_y
        for longitude in 0 ..< LONGITUDE_SEGMENTS {
            longitude_angle := f32(longitude) * math.PI * 2 / f32(LONGITUDE_SEGMENTS)
            local_x := math.cos(longitude_angle) * latitude_radius * radius_x
            local_z := math.sin(longitude_angle) * latitude_radius * radius_z
            world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
            points[latitude][longitude] = {world_x, center.y + local_y, world_z}
            local_normal := linalg.normalize0(
                third_person.Vec3 {
                    local_x / max(radius_x * radius_x, f32(.000001)),
                    local_y / max(radius_y * radius_y, f32(.000001)),
                    local_z / max(radius_z * radius_z, f32(.000001)),
                },
            )
            normal_x, normal_z := world_rotate_xz(0, 0, local_normal.x, local_normal.z, rotation)
            normals[latitude][longitude] = {normal_x, local_normal.y, normal_z}
        }
    }
    for latitude in 0 ..< LATITUDE_SEGMENTS {
        for longitude in 0 ..< LONGITUDE_SEGMENTS {
            next := (longitude + 1) % LONGITUDE_SEGMENTS
            vertex_coordinates := [6][2]int {
                {latitude, longitude},
                {latitude + 1, longitude},
                {latitude + 1, next},
                {latitude, longitude},
                {latitude + 1, next},
                {latitude, next},
            }
            for coordinate in vertex_coordinates {
                point_latitude, point_longitude := coordinate[0], coordinate[1]
                vertex := world_eye_vertex(
                    points[point_latitude][point_longitude],
                    color,
                    normals[point_latitude][point_longitude],
                )
                vertex.kind = material_kind
                if material_kind == .Acorn {
                    vertex.uv = {
                        f32(point_longitude) / f32(LONGITUDE_SEGMENTS),
                        f32(point_latitude) / f32(LATITUDE_SEGMENTS),
                    }
                    // Unwrap triangles that cross the longitude seam instead
                    // of interpolating through the entire texture domain.
                    if longitude == LONGITUDE_SEGMENTS - 1 && point_longitude == 0 {
                        vertex.uv[0] = 1
                    }
                }
                append(&world_renderer.vertices, vertex)
            }
        }
    }
}

// A softly faceted ellipsoid for cloth and other matte props. Unlike the eye
// ellipsoid it deliberately uses the plain material, avoiding hard wet-looking
// highlights on pale fabric.
world_ellipsoid_plain_oriented :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, radius_z, rotation, roll: f32,
    color: rl.Color,
) {
    LATITUDE_SEGMENTS :: 6
    LONGITUDE_SEGMENTS :: 10
    points: [LATITUDE_SEGMENTS + 1][LONGITUDE_SEGMENTS]third_person.Vec3
    roll_cos, roll_sin := math.cos(roll), math.sin(roll)
    for latitude in 0 ..= LATITUDE_SEGMENTS {
        latitude_angle := -math.PI * .5 + f32(latitude) * math.PI / f32(LATITUDE_SEGMENTS)
        latitude_radius := math.cos(latitude_angle)
        local_y := math.sin(latitude_angle) * radius_y
        for longitude in 0 ..< LONGITUDE_SEGMENTS {
            longitude_angle := f32(longitude) * math.PI * 2 / f32(LONGITUDE_SEGMENTS)
            local_x := math.cos(longitude_angle) * latitude_radius * radius_x
            local_z := math.sin(longitude_angle) * latitude_radius * radius_z
            rolled_x := local_x * roll_cos - local_y * roll_sin
            rolled_y := local_x * roll_sin + local_y * roll_cos
            world_x, world_z := world_rotate_xz(center.x, center.z, rolled_x, local_z, rotation)
            points[latitude][longitude] = {world_x, center.y + rolled_y, world_z}
        }
    }
    for latitude in 0 ..< LATITUDE_SEGMENTS {
        for longitude in 0 ..< LONGITUDE_SEGMENTS {
            next := (longitude + 1) % LONGITUDE_SEGMENTS
            world_triangle(
                points[latitude][longitude],
                points[latitude + 1][longitude],
                points[latitude + 1][next],
                color,
            )
            world_triangle(points[latitude][longitude], points[latitude + 1][next], points[latitude][next], color)
        }
    }
}

world_ellipsoid_plain_rotated :: proc(
    center: third_person.Vec3,
    radius_x, radius_y, radius_z, rotation: f32,
    color: rl.Color,
) {
    world_ellipsoid_plain_oriented(center, radius_x, radius_y, radius_z, rotation, 0, color)
}

// One closed, connected shell for the bottle-cap hat. The alternating outer
// radius is part of the hull itself, so the crimped edge no longer depends on
// detached blocks. UVs drive the pressed-metal finish in the world shader.
world_bottle_cap_hull :: proc(center: third_person.Vec3, rotation: f32, color: rl.Color) {
    // Forty-two vertices give the perimeter twenty-one crown-cap teeth.
    SEGMENTS :: 42
    RING_COUNT :: 7
    // Keep the top broad and almost planar. The former domed transition made
    // the cap read as a soft beret despite its ribbed edge.
    heights := [RING_COUNT]f32{-.060, -.045, .010, .045, .061, .066, .068}
    radii_x := [RING_COUNT]f32{.205, .265, .258, .232, .204, .115, 0}
    radii_z := [RING_COUNT]f32{.185, .242, .235, .210, .184, .104, 0}
    rings: [RING_COUNT][SEGMENTS]third_person.Vec3
    normals: [RING_COUNT][SEGMENTS]third_person.Vec3
    uvs: [RING_COUNT][SEGMENTS][2]f32
    for ring_index in 0 ..< RING_COUNT {
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            // Twenty-one sharp flutes around the rolled skirt, carried by the
            // first three rings so each crimp remains joined to the crown.
            crimp := ring_index <= 2 ? (1 + math.cos(angle * 21)) * .5 : f32(0)
            crimp_scale := 1 + crimp * (ring_index == 1 ? f32(.075) : f32(.032))
            local_x := math.cos(angle) * radii_x[ring_index] * crimp_scale
            local_z := math.sin(angle) * radii_z[ring_index] * crimp_scale
            world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
            rings[ring_index][segment] = {world_x, center.y + heights[ring_index], world_z}
            uvs[ring_index][segment] = {.5 + local_x / (.265 * 2), .5 + local_z / (.242 * 2)}
            local_normal := linalg.normalize0(
                [3]f32 {
                    local_x / max(radii_x[ring_index] * radii_x[ring_index], f32(.000001)),
                    ring_index >= 4 ? f32(1) : f32(.18),
                    local_z / max(radii_z[ring_index] * radii_z[ring_index], f32(.000001)),
                },
            )
            normal_x, normal_z := world_rotate_xz(0, 0, local_normal.x, local_normal.z, rotation)
            normals[ring_index][segment] = {normal_x, local_normal.y, normal_z}
        }
    }
    for ring_index in 0 ..< RING_COUNT - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            coordinates := [6][2]int {
                {ring_index, segment},
                {ring_index + 1, segment},
                {ring_index + 1, next},
                {ring_index, segment},
                {ring_index + 1, next},
                {ring_index, next},
            }
            for coordinate in coordinates {
                ring, point := coordinate[0], coordinate[1]
                vertex := world_eye_vertex(rings[ring][point], color, normals[ring][point])
                vertex.kind = .Bottle_Cap
                vertex.uv = uvs[ring][point]
                vertex.material[0] = f32(ring) / f32(RING_COUNT - 1)
                append(&world_renderer.vertices, vertex)
            }
        }
    }
    bottom := third_person.Vec3{center.x, center.y + heights[0], center.z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        bottom_coordinates := [3]int{segment, next, -1}
        for coordinate in bottom_coordinates {
            point := coordinate < 0 ? bottom : rings[0][coordinate]
            vertex := world_eye_vertex(point, color, {0, -1, 0})
            vertex.kind = .Bottle_Cap
            vertex.uv =
                coordinate < 0 ? [2]f32{.5, 0} : [2]f32{.5 + math.cos(f32(coordinate) * math.PI * 2 / f32(SEGMENTS)) * .5, .5 + math.sin(f32(coordinate) * math.PI * 2 / f32(SEGMENTS)) * .5}
            vertex.material[0] = 0
            append(&world_renderer.vertices, vertex)
        }
    }
}

// A single connected felt shell for the Tyrolean hat. Its radial profile
// travels from the closed underside, around the brim, and continuously up the
// tapered crown; every visible felt contour therefore belongs to one hull.
world_alpine_hat_hull :: proc(center: third_person.Vec3, rotation: f32, felt_dark, felt, felt_light: rl.Color) {
    SEGMENTS :: 14
    RING_COUNT :: 7
    heights := [RING_COUNT]f32{-.045, -.020, .010, .045, .135, .205, .225}
    radii_x := [RING_COUNT]f32{.305, .325, .238, .225, .195, .148, .112}
    radii_z := [RING_COUNT]f32{.215, .235, .190, .180, .150, .112, .080}
    offsets_x := [RING_COUNT]f32{0, 0, 0, 0, -.010, -.030, -.040}
    offsets_z := [RING_COUNT]f32{0, .010, 0, -.005, -.010, 0, .012}
    colors := [RING_COUNT]rl.Color{felt_dark, felt_dark, felt, felt, felt, felt_light, felt_light}
    rings: [RING_COUNT][SEGMENTS]third_person.Vec3
    for ring_index in 0 ..< RING_COUNT {
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            local_x := offsets_x[ring_index] + math.cos(angle) * radii_x[ring_index]
            local_z := offsets_z[ring_index] + math.sin(angle) * radii_z[ring_index]
            ring_height := heights[ring_index]
            if ring_index <= 1 {
                // Lift only the feather side of both brim surfaces. Keeping
                // the underside and upper edge together preserves hull
                // thickness while breaking the perfectly level bowler line.
                ring_height += max(math.cos(angle), f32(0)) * .030
            }
            world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
            rings[ring_index][segment] = {world_x, center.y + ring_height, world_z}
        }
    }
    for ring_index in 0 ..< RING_COUNT - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            world_triangle_colored(
                rings[ring_index][segment],
                rings[ring_index + 1][segment],
                rings[ring_index + 1][next],
                colors[ring_index],
                colors[ring_index + 1],
                colors[ring_index + 1],
            )
            world_triangle_colored(
                rings[ring_index][segment],
                rings[ring_index + 1][next],
                rings[ring_index][next],
                colors[ring_index],
                colors[ring_index + 1],
                colors[ring_index],
            )
        }
    }
    bottom_x, bottom_z := world_rotate_xz(center.x, center.z, 0, 0, rotation)
    top_x, top_z := world_rotate_xz(
        center.x,
        center.z,
        offsets_x[RING_COUNT - 1] - .015,
        offsets_z[RING_COUNT - 1],
        rotation,
    )
    bottom_center := third_person.Vec3{bottom_x, center.y + heights[0], bottom_z}
    // Sink the cap center below its final ring to press a shallow crease into
    // the crown while retaining one continuous watertight shell.
    top_center := third_person.Vec3{top_x, center.y + heights[RING_COUNT - 1] - .018, top_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(bottom_center, rings[0][next], rings[0][segment], felt_dark)
        world_triangle(top_center, rings[RING_COUNT - 1][segment], rings[RING_COUNT - 1][next], felt_light)
    }
}

// One closed cloth shell for the flat cap. The first rings travel from the
// fitted underside out around the asymmetric forward peak; successive rings
// pull back over the skull into the low crown. Crown and brim therefore share
// vertices instead of intersecting as separate primitives.
world_flat_cap_hull :: proc(
    center: third_person.Vec3,
    rotation: f32,
    tweed_dark, tweed, tweed_front, tweed_light: rl.Color,
) {
    SEGMENTS :: 18
    RING_COUNT :: 7
    heights := [RING_COUNT]f32{-.045, -.030, -.012, 0, .055, .100, .122}
    radii_x := [RING_COUNT]f32{.190, .205, .205, .235, .238, .205, .120}
    radii_z := [RING_COUNT]f32{.150, .205, .205, .205, .200, .160, .090}
    offsets_z := [RING_COUNT]f32{-.020, .090, .090, -.025, -.045, -.055, -.060}
    front_drop := [RING_COUNT]f32{0, .002, .004, .010, .024, .034, .025}
    colors := [RING_COUNT]rl.Color{tweed_dark, tweed_dark, tweed_front, tweed_front, tweed, tweed, tweed_light}

    rings: [RING_COUNT][SEGMENTS]third_person.Vec3
    vertex_colors: [RING_COUNT][SEGMENTS]rl.Color
    for ring_index in 0 ..< RING_COUNT {
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            local_x := math.cos(angle) * radii_x[ring_index]
            local_z := offsets_z[ring_index] + math.sin(angle) * radii_z[ring_index]
            local_y := heights[ring_index] - max(math.sin(angle), 0) * front_drop[ring_index]
            world_x, world_z := world_rotate_xz(center.x, center.z, local_x, local_z, rotation)
            rings[ring_index][segment] = {world_x, center.y + local_y, world_z}
            vertex_colors[ring_index][segment] = colors[ring_index]
            if ring_index >= 3 {
                // Eighteen radial samples form six broad cloth panels. The
                // restrained alternating value is visible at gameplay scale
                // without turning the tweed into a striped helmet.
                panel := (segment / 3) % 2
                panel_tint := panel == 0 ? tweed_light : tweed_dark
                vertex_colors[ring_index][segment] = color_lerp(colors[ring_index], panel_tint, .10)
            }
        }
    }

    for ring_index in 0 ..< RING_COUNT - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            world_triangle_colored(
                rings[ring_index][segment],
                rings[ring_index + 1][segment],
                rings[ring_index + 1][next],
                vertex_colors[ring_index][segment],
                vertex_colors[ring_index + 1][segment],
                vertex_colors[ring_index + 1][next],
            )
            world_triangle_colored(
                rings[ring_index][segment],
                rings[ring_index + 1][next],
                rings[ring_index][next],
                vertex_colors[ring_index][segment],
                vertex_colors[ring_index + 1][next],
                vertex_colors[ring_index][next],
            )
        }
    }

    bottom_x, bottom_z := world_rotate_xz(center.x, center.z, 0, offsets_z[0], rotation)
    top_x, top_z := world_rotate_xz(center.x, center.z, 0, offsets_z[RING_COUNT - 1], rotation)
    bottom_center := third_person.Vec3{bottom_x, center.y + heights[0], bottom_z}
    // A shallow center depression keeps the non-planar crown fan outward
    // facing after the forward drape and gives the cloth a tailored set.
    top_center := third_person.Vec3{top_x, center.y + heights[RING_COUNT - 1] - .035, top_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(bottom_center, rings[0][next], rings[0][segment], tweed_dark)
        world_triangle_colored(
            top_center,
            rings[RING_COUNT - 1][segment],
            rings[RING_COUNT - 1][next],
            tweed,
            vertex_colors[RING_COUNT - 1][segment],
            vertex_colors[RING_COUNT - 1][next],
        )
    }
}

// A closed, pointed feather vane. The outline supplies the taper and swept
// tip; shallow extrusion keeps it readable from both front and profile views.
world_alpine_feather_hull :: proc(center: third_person.Vec3, rotation: f32, feather, feather_light: rl.Color) {
    POINT_COUNT :: 8
    outline := [POINT_COUNT][2]f32 {
        {-.060, -.160},
        {-.075, -.075},
        {-.055, .035},
        {-.020, .125},
        {.030, .155},
        {.042, .080},
        {.032, -.025},
        {-.015, -.125},
    }
    depths := [POINT_COUNT]f32{.008, .026, .040, .030, .004, .024, .040, .028}
    back, front: [POINT_COUNT]third_person.Vec3
    back_center := center
    front_center := center
    for index in 0 ..< POINT_COUNT {
        back_world_x, back_world_z := world_rotate_xz(center.x, center.z, outline[index][0], -depths[index], rotation)
        front_world_x, front_world_z := world_rotate_xz(center.x, center.z, outline[index][0], depths[index], rotation)
        back[index] = {back_world_x, center.y + outline[index][1], back_world_z}
        front[index] = {front_world_x, center.y + outline[index][1], front_world_z}
    }
    for index in 0 ..< POINT_COUNT {
        next := (index + 1) % POINT_COUNT
        world_triangle(back_center, back[next], back[index], feather)
        world_triangle(front_center, front[index], front[next], feather_light)
        world_quad(back[index], back[next], front[next], front[index], feather)
    }
}

world_tapered_disc_depth_rotated :: proc(
    center: third_person.Vec3,
    back_radius_x, back_radius_y, front_radius_x, front_radius_y, depth, rotation: f32,
    color: rl.Color,
) {
    SEGMENTS :: 12
    back, front: [SEGMENTS]third_person.Vec3
    half_depth := depth * .5
    back_x, back_z := world_rotate_xz(center.x, center.z, 0, -half_depth, rotation)
    front_x, front_z := world_rotate_xz(center.x, center.z, 0, half_depth, rotation)
    back_center := third_person.Vec3{back_x, center.y, back_z}
    front_center := third_person.Vec3{front_x, center.y, front_z}
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        cosine, sine := math.cos(angle), math.sin(angle)
        back_world_x, back_world_z := world_rotate_xz(
            center.x,
            center.z,
            cosine * back_radius_x,
            -half_depth,
            rotation,
        )
        front_world_x, front_world_z := world_rotate_xz(
            center.x,
            center.z,
            cosine * front_radius_x,
            half_depth,
            rotation,
        )
        back[segment] = {back_world_x, center.y + sine * back_radius_y, back_world_z}
        front[segment] = {front_world_x, center.y + sine * front_radius_y, front_world_z}
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(back_center, back[next], back[segment], color)
        world_triangle(front_center, front[segment], front[next], color)
        world_quad(back[segment], back[next], front[next], front[segment], color)
    }
}

world_tube_between :: proc(a, b, forward: third_person.Vec3, radius_x, radius_z: f32, color: rl.Color) {
    SEGMENTS :: 8
    delta := third_person.Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
    length := linalg.length(delta)
    if length <= .0001 do return
    axis_y := third_person.Vec3{delta.x / length, delta.y / length, delta.z / length}
    reference := linalg.normalize0(forward)
    projection := linalg.dot(reference, axis_y)
    axis_z_candidate := third_person.Vec3 {
        reference.x - axis_y.x * projection,
        reference.y - axis_y.y * projection,
        reference.z - axis_y.z * projection,
    }
    // Tail links often point exactly opposite model-forward. In that case
    // Gram-Schmidt with `forward` produces a zero radial axis and collapses
    // the tube into invisible, zero-area triangles. Choose a stable fallback
    // reference for any collinear segment.
    if linalg.dot(axis_z_candidate, axis_z_candidate) < .0001 {
        fallback := third_person.Vec3{0, 1, 0}
        if math.abs(axis_y.y) > .90 do fallback = third_person.Vec3{1, 0, 0}
        fallback_projection := linalg.dot(fallback, axis_y)
        axis_z_candidate = {
            fallback.x - axis_y.x * fallback_projection,
            fallback.y - axis_y.y * fallback_projection,
            fallback.z - axis_y.z * fallback_projection,
        }
    }
    axis_z := linalg.normalize0(axis_z_candidate)
    axis_x := linalg.normalize0(linalg.cross(axis_y, axis_z))
    ring_a, ring_b: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
        x, z := math.cos(angle) * radius_x, math.sin(angle) * radius_z
        offset := third_person.Vec3 {
            axis_x.x * x + axis_z.x * z,
            axis_x.y * x + axis_z.y * z,
            axis_x.z * x + axis_z.z * z,
        }
        ring_a[segment] = {a.x + offset.x, a.y + offset.y, a.z + offset.z}
        ring_b[segment] = {b.x + offset.x, b.y + offset.y, b.z + offset.z}
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(a, ring_a[segment], ring_a[next], color)
        world_triangle(b, ring_b[next], ring_b[segment], color)
        world_quad(ring_a[segment], ring_b[segment], ring_b[next], ring_a[next], color)
    }
}

world_mouse_limb_hull :: proc(
    points: []third_person.Vec3,
    radii: []f32,
    colors: []rl.Color,
    forward: third_person.Vec3,
    cap_root := true,
) {
    MAX_RINGS :: 16
    SEGMENTS :: 12
    if len(points) < 2 || len(points) > MAX_RINGS || len(radii) != len(points) || len(colors) != len(points) {
        return
    }

    rings: [MAX_RINGS][SEGMENTS]third_person.Vec3
    reference := linalg.normalize0(forward)
    previous_axis_x, previous_axis_z: third_person.Vec3
    for ring_index in 0 ..< len(points) {
        previous := max(ring_index - 1, 0)
        next := min(ring_index + 1, len(points) - 1)
        tangent := third_person.Vec3 {
            points[next].x - points[previous].x,
            points[next].y - points[previous].y,
            points[next].z - points[previous].z,
        }
        axis_y := linalg.normalize0(tangent)
        frame_reference := reference
        if ring_index > 0 do frame_reference = previous_axis_z
        projection := linalg.dot(frame_reference, axis_y)
        axis_z_candidate := third_person.Vec3 {
            frame_reference.x - axis_y.x * projection,
            frame_reference.y - axis_y.y * projection,
            frame_reference.z - axis_y.z * projection,
        }
        if linalg.dot(axis_z_candidate, axis_z_candidate) < .0001 {
            fallback := ring_index > 0 ? previous_axis_x : third_person.Vec3{0, 1, 0}
            if ring_index == 0 && math.abs(axis_y.y) > .90 do fallback = third_person.Vec3{1, 0, 0}
            fallback_projection := linalg.dot(fallback, axis_y)
            axis_z_candidate = {
                fallback.x - axis_y.x * fallback_projection,
                fallback.y - axis_y.y * fallback_projection,
                fallback.z - axis_y.z * fallback_projection,
            }
        }
        axis_z := linalg.normalize0(axis_z_candidate)
        axis_x := linalg.normalize0(linalg.cross(axis_y, axis_z))
        // Projecting the previous radial axis onto the new tangent plane is a
        // discrete parallel transport: ring indices retain their orientation
        // through bends instead of independently choosing a frame/sign.
        previous_axis_x, previous_axis_z = axis_x, axis_z
        for segment in 0 ..< SEGMENTS {
            angle := (f32(segment) + .5) * math.PI * 2 / f32(SEGMENTS)
            cosine, sine := math.cos(angle), math.sin(angle)
            radius := radii[ring_index]
            offset := third_person.Vec3 {
                axis_x.x * cosine * radius + axis_z.x * sine * radius,
                axis_x.y * cosine * radius + axis_z.y * sine * radius,
                axis_x.z * cosine * radius + axis_z.z * sine * radius,
            }
            rings[ring_index][segment] = {
                points[ring_index].x + offset.x,
                points[ring_index].y + offset.y,
                points[ring_index].z + offset.z,
            }
        }
    }

    for ring_index in 0 ..< len(points) - 1 {
        for segment in 0 ..< SEGMENTS {
            next_segment := (segment + 1) % SEGMENTS
            a, b := rings[ring_index][segment], rings[ring_index][next_segment]
            c, d := rings[ring_index + 1][next_segment], rings[ring_index + 1][segment]
            world_triangle_colored(a, d, c, colors[ring_index], colors[ring_index + 1], colors[ring_index + 1])
            world_triangle_colored(a, c, b, colors[ring_index], colors[ring_index + 1], colors[ring_index])
        }
    }
    last := len(points) - 1
    for segment in 0 ..< SEGMENTS {
        next_segment := (segment + 1) % SEGMENTS
        if cap_root {
            world_triangle(points[0], rings[0][segment], rings[0][next_segment], colors[0])
        }
        world_triangle(points[last], rings[last][next_segment], rings[last][segment], colors[last])
    }
}

world_box_between :: proc(a, b, forward: third_person.Vec3, width, depth: f32, color: rl.Color) {
    delta := third_person.Vec3{b.x - a.x, b.y - a.y, b.z - a.z}
    length := linalg.length(delta)
    if length <= .0001 do return
    axis_y := third_person.Vec3{delta.x / length, delta.y / length, delta.z / length}
    axis_z := linalg.normalize0(forward)
    axis_x := linalg.cross(axis_y, axis_z)
    axis_x_length := linalg.length(axis_x)
    if axis_x_length <= .0001 {
        axis_x = linalg.cross(axis_y, third_person.Vec3{0, 1, 0})
        axis_x_length = linalg.length(axis_x)
    }
    if axis_x_length > .0001 {
        axis_x = {axis_x.x / axis_x_length, axis_x.y / axis_x_length, axis_x.z / axis_x_length}
    } else {
        axis_x = third_person.Vec3{1, 0, 0}
    }
    center := third_person.Vec3{(a.x + b.x) * .5, (a.y + b.y) * .5, (a.z + b.z) * .5}
    signs := [8][3]f32 {
        {-1, -1, -1},
        {1, -1, -1},
        {1, 1, -1},
        {-1, 1, -1},
        {-1, -1, 1},
        {1, -1, 1},
        {1, 1, 1},
        {-1, 1, 1},
    }
    p: [8]third_person.Vec3
    for index in 0 ..< 8 {
        x := signs[index][0] * width * .5
        y := signs[index][1] * length * .5
        z := signs[index][2] * depth * .5
        p[index] = {
            center.x + axis_x.x * x + axis_y.x * y + axis_z.x * z,
            center.y + axis_x.y * x + axis_y.y * y + axis_z.y * z,
            center.z + axis_x.z * x + axis_y.z * y + axis_z.z * z,
        }
    }
    world_quad(p[0], p[3], p[2], p[1], color)
    world_quad(p[4], p[5], p[6], p[7], color)
    world_quad(p[0], p[4], p[7], p[3], color)
    world_quad(p[1], p[2], p[6], p[5], color)
    world_quad(p[3], p[7], p[6], p[2], color)
    world_quad(p[0], p[1], p[5], p[4], color)
}

world_roof_raise :: proc(point: third_person.Vec3, amount: f32) -> third_person.Vec3 {
    return {point.x, point.y + amount, point.z}
}

// A Greek tile roof reads through its repeated courses: each course runs from
// the lower edge toward the ridge, with small gaps that catch the light.
world_architecture_tile_slope :: proc(
    edge_a, edge_b, ridge_a, ridge_b: third_person.Vec3,
    courses, segments: int,
    seed: u32,
) {
    for course in 0 ..< courses {
        course_start := f32(course) / f32(courses)
        course_end := min(course_start + .78 / f32(courses), 1)
        // Keep the decorative courses decisively in front of the continuous
        // weatherproof roof plane.  The old 3.5 cm offset became effectively
        // coplanar at town-scale camera distances and the depth buffer
        // alternated between the tile and base surfaces.
        relief := .12 + f32(course % 2) * .012
        for segment in 0 ..< segments {
            segment_start := f32(segment) / f32(segments)
            segment_end := f32(segment + 1) / f32(segments)
            // Offset alternate courses so the vertical joins do not line up.
            offset := course % 2 == 0 ? 0 : .035 / f32(segments)
            segment_start = clamp(segment_start + offset, 0, 1)
            segment_end = clamp(segment_end + offset, 0, 1)

            outer_a := linalg.lerp(edge_a, edge_b, segment_start)
            outer_b := linalg.lerp(edge_a, edge_b, segment_end)
            inner_a := linalg.lerp(outer_a, ridge_a, course_start)
            inner_b := linalg.lerp(outer_b, ridge_b, course_start)
            next_a := linalg.lerp(outer_a, ridge_a, course_end)
            next_b := linalg.lerp(outer_b, ridge_b, course_end)
            inner_a = world_roof_raise(inner_a, relief)
            inner_b = world_roof_raise(inner_b, relief)
            next_a = world_roof_raise(next_a, relief)
            next_b = world_roof_raise(next_b, relief)

            tone := int((seed + u32(course * 11 + segment * 3)) % 5)
            tile_bytes := architecture.architecture_roof_tile_color(seed, tone)
            tile := rl.Color{tile_bytes[0], tile_bytes[1], tile_bytes[2], tile_bytes[3]}
            world_quad(inner_a, inner_b, next_b, next_a, tile)
        }
    }
}

world_architecture_tile_face :: proc(edge_a, edge_b, ridge: third_person.Vec3, courses, segments: int, seed: u32) {
    world_architecture_tile_slope(edge_a, edge_b, ridge, ridge, courses, segments, seed)
}

world_architecture_roof_style :: proc(structure: terrain.Structure) -> architecture.Roof_Style {
    identity := architecture.architecture_resolve_legacy_identity(structure)
    if identity.region == .Aegean && !buildings.is_landmark(identity) {
        return .Parapet
    }
    return architecture.roof_style_for_seed(structure.seed)
}

world_architecture_roof :: proc(
    structure: terrain.Structure,
    landmark: bool,
    lod: Structure_LOD = .Near,
) {
    eave_y := structure.base_y + structure.height
    roof_style := world_architecture_roof_style(structure)
    identity := architecture.architecture_resolve_legacy_identity(structure)
    tower_landmark := identity.archetype == .Campanile || identity.archetype == .Cycladic_Bell
    ceremonial_roof := tower_landmark || identity.archetype == .Church
    if !ceremonial_roof && roof_style == .Parapet {
        roof_color := rl.Color{229, 226, 211, 255}
        chimney_color := rl.Color{221, 218, 203, 255}
        chimney_width, chimney_height := f32(1.1), f32(1.3)
        if identity.region != .Aegean {
            roof_bytes := architecture.architecture_roof_color(structure.seed)
            roof_color = {roof_bytes[0], roof_bytes[1], roof_bytes[2], roof_bytes[3]}
            chimney_color = {157, 112, 86, 255}
            chimney_width, chimney_height = 2.4, 2.0
        }
        world_box_rotated(
            {structure.center_x, eave_y + .25, structure.center_z},
            {structure.width + .8, .50, structure.depth + .8},
            structure.rotation,
            roof_color,
        )
        chimney_x, chimney_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            structure.width * .22,
            -structure.depth * .16,
            structure.rotation,
        )
        world_box_rotated(
            {chimney_x, eave_y + .50 + chimney_height * .5, chimney_z},
            {chimney_width, chimney_height, chimney_width},
            structure.rotation,
            chimney_color,
        )
        return
    }
    rise := ceremonial_roof ? structure.width * .72 : structure.width * .34
    if !ceremonial_roof && roof_style == .Low_Gable do rise = structure.width * .24
    depth := structure.depth * .58
    left_front_x, left_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .54,
        -depth,
        structure.rotation,
    )
    right_front_x, right_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .54,
        -depth,
        structure.rotation,
    )
    left_back_x, left_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .54,
        depth,
        structure.rotation,
    )
    right_back_x, right_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .54,
        depth,
        structure.rotation,
    )
    left_front := third_person.Vec3{left_front_x, eave_y, left_front_z}
    right_front := third_person.Vec3{right_front_x, eave_y, right_front_z}
    left_back := third_person.Vec3{left_back_x, eave_y, left_back_z}
    right_back := third_person.Vec3{right_back_x, eave_y, right_back_z}
    ridge_half_depth := depth
    if roof_style == .Hip do ridge_half_depth = depth * .50
    ridge_front_x, ridge_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        -ridge_half_depth,
        structure.rotation,
    )
    ridge_back_x, ridge_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        ridge_half_depth,
        structure.rotation,
    )
    ridge_front := third_person.Vec3{ridge_front_x, eave_y + rise, ridge_front_z}
    ridge_back := third_person.Vec3{ridge_back_x, eave_y + rise, ridge_back_z}
    left_apex_x, left_apex_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .54,
        0,
        structure.rotation,
    )
    right_apex_x, right_apex_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .54,
        0,
        structure.rotation,
    )
    left_apex := third_person.Vec3{left_apex_x, eave_y + rise, left_apex_z}
    right_apex := third_person.Vec3{right_apex_x, eave_y + rise, right_apex_z}
    wall_left_front_x, wall_left_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .5,
        -structure.depth * .5,
        structure.rotation,
    )
    wall_left_back_x, wall_left_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        -structure.width * .5,
        structure.depth * .5,
        structure.rotation,
    )
    wall_right_front_x, wall_right_front_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .5,
        -structure.depth * .5,
        structure.rotation,
    )
    wall_right_back_x, wall_right_back_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        structure.width * .5,
        structure.depth * .5,
        structure.rotation,
    )
    wall_left_front := third_person.Vec3{wall_left_front_x, eave_y, wall_left_front_z}
    wall_left_back := third_person.Vec3{wall_left_back_x, eave_y, wall_left_back_z}
    wall_right_front := third_person.Vec3{wall_right_front_x, eave_y, wall_right_front_z}
    wall_right_back := third_person.Vec3{wall_right_back_x, eave_y, wall_right_back_z}
    wall_front_left := third_person.Vec3{wall_left_front_x, eave_y, wall_left_front_z}
    wall_front_right := third_person.Vec3{wall_right_front_x, eave_y, wall_right_front_z}
    wall_back_left := third_person.Vec3{wall_left_back_x, eave_y, wall_left_back_z}
    wall_back_right := third_person.Vec3{wall_right_back_x, eave_y, wall_right_back_z}
    wall_front_apex := third_person.Vec3 {
        wall_left_front_x + (wall_right_front_x - wall_left_front_x) * .5,
        eave_y + rise,
        wall_left_front_z + (wall_right_front_z - wall_left_front_z) * .5,
    }
    wall_back_apex := third_person.Vec3 {
        wall_left_back_x + (wall_right_back_x - wall_left_back_x) * .5,
        eave_y + rise,
        wall_left_back_z + (wall_right_back_z - wall_left_back_z) * .5,
    }
    roof_bytes := architecture.architecture_roof_color(structure.seed, landmark)
    terracotta := rl.Color{roof_bytes[0], roof_bytes[1], roof_bytes[2], roof_bytes[3]}
    // The ridge follows the building depth. Gable roofs continue the left and
    // right walls to their ridge apexes; hip roofs close the front and rear
    // ends against the shortened ridge.
    wall := rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    if roof_style == .Gable || roof_style == .Low_Gable {
        // Wind each end cap toward the outside of the building. The previous
        // inward-facing order let back-face culling erase the gable viewed
        // from its corresponding end.
        world_triangle(wall_front_left, wall_front_apex, wall_front_right, wall)
        world_triangle(wall_back_right, wall_back_apex, wall_back_left, wall)
    } else if roof_style == .Hip || ceremonial_roof {
        world_triangle(left_front, ridge_front, right_front, terracotta)
        world_triangle(right_back, ridge_back, left_back, formation_face_color(terracotta, 1.4, 0))
    }
    world_quad(left_front, left_back, ridge_back, ridge_front, terracotta)
    world_quad(right_back, right_front, ridge_front, ridge_back, formation_face_color(terracotta, 1.4, 0))
    fascia := formation_face_color(terracotta, math.PI, 0)
    soffit := formation_face_color(terracotta, math.PI * .72, 0)
    front_fascia_x, front_fascia_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        -depth,
        structure.rotation,
    )
    back_fascia_x, back_fascia_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        0,
        depth,
        structure.rotation,
    )
    if roof_style == .Gable || roof_style == .Low_Gable {
        // A gable's end fascia follows both rakes up to the ridge. A single
        // horizontal strip across the eave floated in front of the triangular
        // wall at street level and made the roof read as a detached plank.
        // Follow the overhanging roof edge, not the recessed masonry apex.
        fascia_radius := f32(.12)
        world_tube_between(left_front, ridge_front, {0, 0, 1}, fascia_radius, fascia_radius, fascia)
        world_tube_between(ridge_front, right_front, {0, 0, 1}, fascia_radius, fascia_radius, fascia)
        world_tube_between(right_back, ridge_back, {0, 0, 1}, fascia_radius, fascia_radius, fascia)
        world_tube_between(ridge_back, left_back, {0, 0, 1}, fascia_radius, fascia_radius, fascia)

        // Close the shallow gap between the recessed triangular wall and the
        // overhanging roof edge. These downward-wound strips are the visible
        // underside of the front and rear rake overhangs.
        world_quad(left_front, ridge_front, wall_front_apex, wall_front_left, soffit)
        world_quad(ridge_front, right_front, wall_front_right, wall_front_apex, soffit)
        world_quad(right_back, ridge_back, wall_back_apex, wall_back_right, soffit)
        world_quad(ridge_back, left_back, wall_back_left, wall_back_apex, soffit)
    } else {
        world_box_rotated(
            {front_fascia_x, eave_y + .05, front_fascia_z},
            {structure.width * 1.10, .24, .18},
            structure.rotation,
            fascia,
        )
        world_box_rotated(
            {back_fascia_x, eave_y + .05, back_fascia_z},
            {structure.width * 1.10, .24, .18},
            structure.rotation,
            fascia,
        )
    }
    // Give the long eaves a visible edge. Without this small fascia the roof
    // quad is literally paper-thin and reads as a floating dark strip when
    // the camera is near wall height.
    left_eave_x, left_eave_z := (left_front.x + left_back.x) * .5, (left_front.z + left_back.z) * .5
    right_eave_x, right_eave_z := (right_front.x + right_back.x) * .5, (right_front.z + right_back.z) * .5
    eave_length := depth * 2
    world_box_rotated({left_eave_x, eave_y + .03, left_eave_z}, {.20, .24, eave_length}, structure.rotation, fascia)
    world_box_rotated({right_eave_x, eave_y + .03, right_eave_z}, {.20, .24, eave_length}, structure.rotation, fascia)
    // Close only the narrow long-eave overhangs. A full-width flat plate under
    // the entire roof intersects the triangular gable and reads as a ceiling.
    soffit_width := structure.width * .04
    for side in -1 ..= 1 {
        if side == 0 do continue
        soffit_x, soffit_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            f32(side) * structure.width * .52,
            0,
            structure.rotation,
        )
        world_box_rotated(
            {soffit_x, eave_y + .02, soffit_z},
            {soffit_width, .10, depth * 2},
            structure.rotation,
            soffit,
        )
    }
    if roof_style == .Hip {
        end_soffit_depth := structure.depth * .08
        for end in -1 ..= 1 {
            if end == 0 do continue
            soffit_x, soffit_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                f32(end) * structure.depth * .54,
                structure.rotation,
            )
            world_box_rotated(
                {soffit_x, eave_y + .02, soffit_z},
                {structure.width, .10, end_soffit_depth},
                structure.rotation,
                soffit,
            )
        }
    }

    if lod == .Near {
        courses := clamp(int(structure.width / 5.5), 4, 7)
        segments := clamp(int(structure.depth / 7), 3, 6)
        world_architecture_tile_slope(
            left_front,
            left_back,
            ridge_front,
            ridge_back,
            courses,
            segments,
            structure.seed + 3,
        )
        world_architecture_tile_slope(
            right_back,
            right_front,
            ridge_back,
            ridge_front,
            courses,
            segments,
            structure.seed + 17,
        )
        if roof_style == .Hip {
            side_courses := clamp(int(structure.depth / 5), 3, 5)
            world_architecture_tile_slope(
                left_front,
                right_front,
                ridge_front,
                ridge_front,
                side_courses,
                2,
                structure.seed + 29,
            )
            world_architecture_tile_slope(
                right_back,
                left_back,
                ridge_back,
                ridge_back,
                side_courses,
                2,
                structure.seed + 41,
            )
        }
    }
    if lod != .Far && !landmark && roof_style != .Parapet && architecture.architecture_has_chimney(structure.seed) {
        chimney_local_x := roof_style == .Hip ? structure.width * .12 : structure.width * .22
        chimney_local_z := -structure.depth * .12
        chimney_x, chimney_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            chimney_local_x,
            chimney_local_z,
            structure.rotation,
        )
        chimney_base := eave_y + rise * .74
        world_box_rotated(
            {chimney_x, chimney_base + 1.45, chimney_z},
            {1.8, 2.9, 1.8},
            structure.rotation,
            {157, 112, 86, 255},
        )
        world_box_rotated(
            {chimney_x, chimney_base + 3.0, chimney_z},
            {2.1, .22, 2.1},
            structure.rotation,
            {184, 93, 61, 255},
        )
        // A pale cap lip and a dark inset keep the stack from reading as a
        // single solid cube at eye level, while preserving the hand-built
        // terracotta character of the roofline.
        world_box_rotated(
            {chimney_x, chimney_base + 3.16, chimney_z},
            {2.30, .10, 2.30},
            structure.rotation,
            {214, 178, 139, 255},
        )
        world_box_rotated(
            {chimney_x, chimney_base + 3.23, chimney_z},
            {1.42, .035, 1.42},
            structure.rotation,
            {65, 55, 49, 255},
        )
    }
    if tower_landmark {
        world_box_rotated(
            {structure.center_x, eave_y + rise + 3.5, structure.center_z},
            {3.5, 7, 3.5},
            structure.rotation,
            {224, 219, 196, 255},
        )
    } else if identity.archetype == .Church {
        world_box_rotated(
            {structure.center_x, eave_y + rise + 1.9, structure.center_z},
            {2.6, 3.8, 2.2},
            structure.rotation,
            {224, 219, 196, 255},
        )
    }
}

world_architecture_face_openings :: proc(
    structure: terrain.Structure,
    layout: ^architecture.Opening_Layout,
    window, trim: rl.Color,
) {
    if layout == nil do return
    for opening in layout.openings[:layout.count] {
        // The existing primary façade pass owns its richer doors, shutters,
        // balconies, and storefront details. This pass supplies the other
        // independently generated mass faces.
        if (opening.face == .Front && opening.kind == .Window) || opening.kind == .Door {
            continue
        }
        face_span := opening.face == .Front || opening.face == .Rear ? structure.width : structure.depth
        horizontal := opening.horizontal
        opening_y := architecture.facade_window_row_y(structure.height, opening.row)
        opening_width := architecture.facade_window_width(face_span)
        opening_height := architecture.facade_window_height(structure.height)
        if opening.kind == .Service_Door {
            horizontal = 0
            opening_width = clamp(face_span * .13, f32(1.8), f32(2.8))
            opening_height = clamp(structure.height * .075, f32(3.0), f32(4.0))
            opening_y = .20 + opening_height * .5
        } else if opening.kind == .Vent {
            opening_height = clamp(opening_height * .55, f32(.65), f32(1.4))
            opening_y = max(opening_height * .5 + .55, f32(1.1))
        }
        // Keep the shallow panel wholly beyond the wall plane.  At long
        // streetscape distances a half-embedded panel can lose the depth
        // test to the wall because both surfaces quantize to the same depth.
        // This is still ordinary surface geometry: no depth bias, sorting,
        // or cross-mass visibility query is involved.
        face_offset := f32(.28)
        local_x, local_z, yaw_offset := f32(0), f32(0), f32(0)
        switch opening.face {
        case .Front:
            local_x, local_z = horizontal, structure.depth * .5 + face_offset
        case .Rear:
            local_x, local_z, yaw_offset = -horizontal, -structure.depth * .5 - face_offset, math.PI
        case .Left:
            local_x, local_z, yaw_offset = -structure.width * .5 - face_offset, horizontal, -math.PI * .5
        case .Right:
            local_x, local_z, yaw_offset = structure.width * .5 + face_offset, -horizontal, math.PI * .5
        }
        wx, wz := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        color :=
            opening.kind == .Vent ? rl.Color{62, 69, 66, 255} : (opening.kind == .Service_Door ? rl.Color{83, 70, 60, 255} : window)
        world_box_rotated(
            {wx, structure.base_y + opening_y, wz},
            {opening_width, opening_height, .22},
            structure.rotation + yaw_offset,
            color,
        )
        if opening.kind == .Window {
            glass_local_x, glass_local_z := local_x, local_z
            switch opening.face {
            case .Front:
                glass_local_z += .125
            case .Rear:
                glass_local_z -= .125
            case .Left:
                glass_local_x -= .125
            case .Right:
                glass_local_x += .125
            }
            glass_x, glass_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                glass_local_x,
                glass_local_z,
                structure.rotation,
            )
            glass_tone := int((structure.seed + u32(opening.row * 11) + u32(opening.face) * 7) % 3)
            glass := rl.Color{53, 77, 81, 255}
            if glass_tone == 1 {
                glass = {59, 84, 87, 255}
            } else if glass_tone == 2 {
                glass = {48, 73, 79, 255}
            }
            world_box_rotated(
                {glass_x, structure.base_y + opening_y, glass_z},
                {opening_width * .84, opening_height * .82, .035},
                structure.rotation + yaw_offset,
                glass,
            )
            world_box_rotated(
                {glass_x, structure.base_y + opening_y, glass_z},
                {.06, opening_height * .82, .05},
                structure.rotation + yaw_offset,
                trim,
            )
            world_box_rotated(
                {glass_x, structure.base_y + opening_y + opening_height * .08, glass_z},
                {opening_width * .84, .05, .05},
                structure.rotation + yaw_offset,
                trim,
            )
        }
        lintel_local_x, lintel_local_z := local_x, local_z
        switch opening.face {
        case .Front:
            lintel_local_z += .045
        case .Rear:
            lintel_local_z -= .045
        case .Left:
            lintel_local_x -= .045
        case .Right:
            lintel_local_x += .045
        }
        lintel_x, lintel_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            lintel_local_x,
            lintel_local_z,
            structure.rotation,
        )
        world_box_rotated(
            {lintel_x, structure.base_y + opening_y + opening_height * .5 + .12, lintel_z},
            {opening_width + .36, .075, .16},
            structure.rotation + yaw_offset,
            trim,
        )
    }
}

world_architecture_mass :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    has_entrance: bool = true,
    opening_layout: ^architecture.Opening_Layout = nil,
    lod: Structure_LOD = .Near,
) {
    identity := architecture.architecture_resolve_legacy_identity(structure)
    habitable := buildings.is_habitable(identity.archetype)
    landmark := structure.height > 60 || settlement_structure_is_landmark(structure) || buildings.is_landmark(identity)
    facade_style := architecture.facade_style_for_seed(structure.seed)
    roof_style := world_architecture_roof_style(structure)
    stone := rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    world_architecture_box_rotated(
        {structure.center_x, structure.base_y + structure.height * .5, structure.center_z},
        {structure.width, structure.height, structure.depth},
        structure.rotation,
        stone,
    )
    ground_stone := formation_face_color(stone, f32((structure.seed >> 10) & 3) * .10 - .15, 0)
    world_architecture_box_rotated(
        {structure.center_x, structure.base_y + 1.45, structure.center_z},
        {structure.width + .025, 2.90, structure.depth + .025},
        structure.rotation,
        ground_stone,
    )
    // A shallow overhanging limestone plinth separates each façade from the
    // terrain and gives the compact blocks a believable masonry foundation.
    plinth := formation_face_color(stone, math.PI, 0)
    plinth_height := .52 + f32((structure.seed >> 7) % 4) * .05
    foundation_low, _ := architecture.architecture_mass_height_range(project, structure)
    foundation_depth := max(structure.base_y - foundation_low + .18, f32(0))
    if foundation_depth > .01 {
        foundation_color := formation_face_color(plinth, math.PI * .45, 0)
        world_architecture_box_rotated(
            {structure.center_x, structure.base_y - foundation_depth * .5 + .02, structure.center_z},
            {structure.width + .30, foundation_depth + .04, structure.depth + .30},
            structure.rotation,
            foundation_color,
        )
    }
    world_architecture_box_rotated(
        {structure.center_x, structure.base_y + plinth_height * .5, structure.center_z},
        {structure.width + .46, plinth_height, structure.depth + .46},
        structure.rotation,
        plinth,
    )
    damp_course :=
        facade_style == 2 ? rl.Color{92, 113, 110, 255} : facade_style == 3 ? rl.Color{139, 107, 83, 255} : formation_face_color(plinth, math.PI, 0)
    world_architecture_box_rotated(
        {structure.center_x, structure.base_y + plinth_height + .06, structure.center_z},
        {structure.width + .22, .12, structure.depth + .22},
        structure.rotation,
        damp_course,
    )
    if lod == .Far {
        world_architecture_roof(structure, landmark, lod)
        panel := formation_face_color(stone, math.PI, 0)
        panel_width := clamp(structure.width * .42, f32(2.4), structure.width * .72)
        panel_height := clamp(structure.height * .26, f32(2.4), f32(6.0))
        panel_x, panel_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .07,
            structure.rotation,
        )
        world_box_rotated(
            {panel_x, structure.base_y + structure.height * .48, panel_z},
            {panel_width, panel_height, .12},
            structure.rotation,
            panel,
        )
        return
    }
    if !landmark {
        for corner_side in -1 ..= 1 {
            if corner_side == 0 do continue
            corner_x, corner_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(corner_side) * (structure.width * .5 - .28),
                structure.depth * .5 + .20,
                structure.rotation,
            )
            world_box_rotated(
                {corner_x, structure.base_y + .43, corner_z},
                {.56, .86, .20},
                structure.rotation,
                formation_face_color(plinth, f32(corner_side) * .25, 0),
            )
        }
        if structure.width >= 18 && structure.seed % 3 == 0 {
            for vent_side in -1 ..= 1 {
                if vent_side == 0 do continue
                vent_x, vent_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    f32(vent_side) * structure.width * .30,
                    structure.depth * .5 + .25,
                    structure.rotation,
                )
                world_box_rotated(
                    {vent_x, structure.base_y + .32, vent_z},
                    {.52, .20, .08},
                    structure.rotation,
                    {62, 69, 66, 255},
                )
            }
        }
        utility_side := (structure.seed & 2) == 0 ? f32(-1) : f32(1)
        utility_offset := max(structure.width * .5 - .82, f32(2.4))
        utility_local_x := utility_side * utility_offset
        pipe_x, pipe_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            utility_local_x,
            structure.depth * .5 + .24,
            structure.rotation,
        )
        // Carry the downspout all the way to the eave. Capping this detail at
        // 10.4 m left it visibly stranded midway up taller façades.
        world_box_rotated(
            {pipe_x, structure.base_y + structure.height * .5, pipe_z},
            {.13, structure.height, .13},
            structure.rotation,
            {82, 83, 76, 255},
        )
        shoe_x, shoe_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            utility_local_x - utility_side * .16,
            structure.depth * .5 + .36,
            structure.rotation,
        )
        world_box_rotated(
            {shoe_x, structure.base_y + .20, shoe_z},
            {.42, .16, .30},
            structure.rotation,
            {72, 73, 67, 255},
        )
        box_x, box_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            -utility_local_x,
            structure.depth * .5 + .27,
            structure.rotation,
        )
        box_y := structure.base_y + 1.05
        world_box_rotated({box_x, box_y, box_z}, {.62, .72, .16}, structure.rotation, {113, 119, 111, 255})
        world_box_rotated({box_x, box_y + 1.25, box_z - .02}, {.08, 1.80, .10}, structure.rotation, {96, 101, 94, 255})
        if structure.seed % 4 == 0 {
            patch_side := utility_side
            patch_x, patch_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                patch_side * structure.width * .24,
                structure.depth * .5 + .145,
                structure.rotation,
            )
            patch_color := formation_face_color(stone, patch_side * .18, 0)
            world_box_rotated(
                {patch_x, structure.base_y + 1.45, patch_z},
                {1.25, .72, .035},
                structure.rotation,
                patch_color,
            )
        }
        gravel := rl.Color{136, 126, 108, 255}
        gravel_x, gravel_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .43,
            structure.rotation,
        )
        world_box_rotated(
            {gravel_x, structure.base_y + .025, gravel_z},
            {structure.width + .70, .05, .34},
            structure.rotation,
            gravel,
        )
        for side in -1 ..= 1 {
            if side == 0 do continue
            side_gravel_x, side_gravel_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(side) * (structure.width * .5 + .39),
                0,
                structure.rotation,
            )
            world_box_rotated(
                {side_gravel_x, structure.base_y + .025, side_gravel_z},
                {structure.depth + .70, .05, .28},
                structure.rotation + math.PI * .5,
                gravel,
            )
        }
    }
    if !landmark && facade_style == 3 {
        wing_x, wing_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            structure.width * .28,
            -structure.depth * .05,
            structure.rotation,
        )
        wing_height := structure.height * .44
        world_architecture_box_rotated(
            {wing_x, structure.base_y + wing_height * .5, wing_z},
            {structure.width * .38, wing_height, structure.depth * .72},
            structure.rotation,
            stone,
        )
        world_box_rotated(
            {wing_x, structure.base_y + wing_height + .18, wing_z},
            {structure.width * .42, .36, structure.depth * .78},
            structure.rotation,
            {184, 93, 61, 255},
        )
    }
    world_architecture_roof(structure, landmark, lod)
    if lod == .Medium {
        window := facade_style == 2 ? rl.Color{42, 74, 82, 255} : rl.Color{48, 62, 64, 255}
        rows := architecture.facade_floor_count(structure.height)
        columns := architecture.facade_column_count(structure.width)
        window_width := architecture.facade_window_width(structure.width)
        window_height := architecture.facade_window_height(structure.height)
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                local_x := architecture.facade_window_column_x(structure.width, column)
                window_y := structure.base_y + architecture.facade_window_row_y(structure.height, row)
                window_x, window_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    local_x,
                    structure.depth * .5 + .08,
                    structure.rotation,
                )
                world_box_rotated(
                    {window_x, window_y, window_z},
                    {window_width, window_height, .14},
                    structure.rotation,
                    window,
                )
                // Even at medium LOD, split the opening into glazed panes so
                // it reads as a window rather than a black square.
                glass := facade_style == 2 ? rl.Color{55, 94, 104, 255} : rl.Color{57, 80, 83, 255}
                frame := facade_style == 2 ? rl.Color{170, 181, 166, 255} : rl.Color{174, 158, 134, 255}
                glass_x, glass_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    local_x,
                    structure.depth * .5 + .16,
                    structure.rotation,
                )
                world_box_rotated(
                    {glass_x, window_y, glass_z},
                    {window_width * .84, window_height * .82, .025},
                    structure.rotation,
                    glass,
                )
                world_box_rotated(
                    {glass_x, window_y, glass_z},
                    {.055, window_height * .82, .035},
                    structure.rotation,
                    frame,
                )
                world_box_rotated(
                    {glass_x, window_y + window_height * .08, glass_z},
                    {window_width * .84, .05, .035},
                    structure.rotation,
                    frame,
                )
            }
        }
        if has_entrance && habitable {
            door_x, door_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .10,
                structure.rotation,
            )
            door_width := clamp(structure.width * .13, f32(1.8), f32(2.8))
            door_height := clamp(structure.height * .075, f32(3.0), f32(4.0))
            world_box_rotated(
                {door_x, structure.base_y + door_height * .5, door_z},
                {door_width, door_height, .16},
                structure.rotation,
                {92, 66, 57, 255},
            )
        }
        if !landmark && rows > 1 && structure.seed % 3 == 0 {
            balcony_x, balcony_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .42,
                structure.rotation,
            )
            balcony_y := structure.base_y + architecture.facade_window_row_y(structure.height, rows - 1) -
                          window_height * .5
            world_box_rotated(
                {balcony_x, balcony_y, balcony_z},
                {min(structure.width * .56, f32(7.5)), .14, .72},
                structure.rotation,
                {111, 94, 76, 255},
            )
        }
        return
    }
    // Dark inset windows and red shutters give the generated blocks a readable
    // Adriatic façade even at the editor's wide camera distance.
    window := facade_style == 2 ? rl.Color{42, 74, 82, 255} : rl.Color{48, 62, 64, 255}
    shutter :=
        facade_style == 2 ? rl.Color{43, 102, 126, 255} : facade_style == 3 ? rl.Color{236, 218, 179, 255} : rl.Color{167, 61, 53, 255}
    rows := architecture.facade_floor_count(structure.height)
    columns := architecture.facade_column_count(structure.width)
    if has_entrance && habitable {
        door_x, door_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .18,
            structure.rotation,
        )
        door :=
            facade_style == 2 ? rl.Color{54, 91, 99, 255} : facade_style == 3 ? rl.Color{109, 75, 57, 255} : rl.Color{92, 66, 57, 255}
        if (structure.seed >> 11) & 3 == 1 {
            door = {72, 104, 101, 255}
        } else if (structure.seed >> 11) & 3 == 2 {
            door = {119, 71, 55, 255}
        }
        door_width := clamp(structure.width * .13, f32(1.8), f32(2.8))
        door_height := clamp(structure.height * .075, f32(3.0), f32(4.0))
        step_height: f32 = .20
        door_center_y := structure.base_y + step_height + door_height * .5
        world_box_rotated({door_x, door_center_y, door_z}, {door_width, door_height, .24}, structure.rotation, door)
        panel_color := formation_face_color(door, math.PI, 0)
        for panel in 0 ..< 2 {
            panel_y := structure.base_y + step_height + (panel == 0 ? door_height * .28 : door_height * .70)
            panel_height := panel == 0 ? door_height * .34 : door_height * .26
            panel_x, panel_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .315,
                structure.rotation,
            )
            world_box_rotated(
                {panel_x, panel_y, panel_z},
                {door_width * .70, panel_height, .055},
                structure.rotation,
                panel_color,
            )
        }
        if structure.height < 15 && structure.seed % 5 == 1 {
            divider_x, divider_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .355,
                structure.rotation,
            )
            world_box_rotated(
                {divider_x, door_center_y, divider_z},
                {.08, door_height * .88, .07},
                structure.rotation,
                {183, 157, 119, 255},
            )
        }
        if structure.height < 14 && structure.seed % 5 == 2 {
            for loading_slat in 0 ..< 3 {
                slat_x, slat_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    0,
                    structure.depth * .5 + .355,
                    structure.rotation,
                )
                world_box_rotated(
                    {slat_x, structure.base_y + step_height + door_height * (.25 + f32(loading_slat) * .25), slat_z},
                    {door_width * .82, .07, .07},
                    structure.rotation,
                    {70, 63, 55, 255},
                )
            }
        }
        handle_x, handle_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            door_width * .28,
            structure.depth * .5 + .365,
            structure.rotation,
        )
        world_box_rotated(
            {handle_x, structure.base_y + step_height + door_height * .50, handle_z},
            {.11, .11, .10},
            structure.rotation,
            {196, 157, 79, 255},
        )
        kick_x, kick_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .37,
            structure.rotation,
        )
        world_box_rotated(
            {kick_x, structure.base_y + step_height + .24, kick_z},
            {door_width * .62, .18, .06},
            structure.rotation,
            {157, 124, 69, 255},
        )
        escutcheon_x, escutcheon_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            door_width * .28,
            structure.depth * .5 + .425,
            structure.rotation,
        )
        world_box_rotated(
            {escutcheon_x, structure.base_y + step_height + door_height * .40, escutcheon_z},
            {.07, .14, .035},
            structure.rotation,
            {174, 139, 76, 255},
        )
        if structure.seed % 3 == 0 {
            transom_x, transom_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .37,
                structure.rotation,
            )
            transom_y := structure.base_y + step_height + door_height - .28
            world_box_rotated(
                {transom_x, transom_y, transom_z},
                {door_width * .66, .38, .06},
                structure.rotation,
                {60, 87, 91, 255},
            )
            world_box_rotated(
                {transom_x, transom_y, transom_z},
                {.055, .38, .075},
                structure.rotation,
                {190, 171, 139, 255},
            )
        }
        surround := facade_style == 2 ? rl.Color{166, 171, 151, 255} : rl.Color{190, 166, 128, 255}
        if (structure.seed >> 19) & 1 != 0 {
            surround = facade_style == 2 ? rl.Color{178, 181, 158, 255} : rl.Color{205, 181, 143, 255}
        }
        frame_width: f32 = .12
        frame_height := door_height + .30
        frame_offset := door_width * .5 + frame_width * .5
        left_frame_x, left_frame_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            -frame_offset,
            structure.depth * .5 + .34,
            structure.rotation,
        )
        right_frame_x, right_frame_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            frame_offset,
            structure.depth * .5 + .34,
            structure.rotation,
        )
        world_box_rotated(
            {left_frame_x, door_center_y + .08, left_frame_z},
            {frame_width, frame_height, .12},
            structure.rotation,
            surround,
        )
        world_box_rotated(
            {right_frame_x, door_center_y + .08, right_frame_z},
            {frame_width, frame_height, .12},
            structure.rotation,
            surround,
        )
        lintel_x, lintel_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .34,
            structure.rotation,
        )
        world_box_rotated(
            {lintel_x, structure.base_y + step_height + door_height + .22, lintel_z},
            {door_width + .34, .14, .14},
            structure.rotation,
            surround,
        )
        if structure.seed % 5 == 3 {
            portal_x, portal_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .46,
                structure.rotation,
            )
            world_box_rotated(
                {portal_x, structure.base_y + step_height + door_height + .42, portal_z},
                {door_width + .88, .24, .42},
                structure.rotation,
                surround,
            )
            world_box_rotated(
                {portal_x, structure.base_y + step_height + door_height + .57, portal_z},
                {.34, .22, .46},
                structure.rotation,
                formation_face_color(surround, math.PI, 0),
            )
        }
        step_x, step_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .28,
            structure.rotation,
        )
        step_color :=
            facade_style == 2 ? rl.Color{103, 130, 125, 255} : facade_style == 3 ? rl.Color{178, 127, 88, 255} : rl.Color{178, 127, 88, 255}
        if (structure.seed >> 13) & 1 != 0 {
            step_color = facade_style == 2 ? rl.Color{121, 137, 126, 255} : rl.Color{157, 137, 108, 255}
        }
        world_box_rotated(
            {step_x, structure.base_y + step_height * .5, step_z},
            {door_width + .72, step_height, .42},
            structure.rotation,
            step_color,
        )
        lower_step_x, lower_step_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + .52,
            structure.rotation,
        )
        world_box_rotated(
            {lower_step_x, structure.base_y + .06, lower_step_z},
            {door_width + 1.05, .12, .72},
            structure.rotation,
            formation_face_color(step_color, math.PI, 0),
        )
        for paver in 0 ..< 3 {
            paver_x, paver_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .72 + f32(paver) * .36,
                structure.rotation,
            )
            paver_tone := paver % 2 == 0 ? step_color : formation_face_color(step_color, math.PI, 0)
            if (structure.seed >> 14) & 1 != 0 && paver == 1 {
                paver_tone = facade_style == 2 ? rl.Color{116, 126, 116, 255} : rl.Color{149, 119, 91, 255}
            }
            world_box_rotated(
                {paver_x, structure.base_y + .035, paver_z},
                {door_width + .42 - f32(paver) * .08, .07, .42},
                structure.rotation,
                paver_tone,
            )
        }
        wear_color := formation_face_color(stone, math.PI, 0)
        for wear_side in -1 ..= 1 {
            if wear_side == 0 do continue
            wear_x, wear_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(wear_side) * (door_width * .5 + .30),
                structure.depth * .5 + .145,
                structure.rotation,
            )
            world_box_rotated(
                {wear_x, structure.base_y + .42, wear_z},
                {.34, .46 + f32((structure.seed >> 5) & 1) * .12, .035},
                structure.rotation,
                wear_color,
            )
        }
        if structure.seed % 2 == 0 {
            for pot_side in -1 ..= 1 {
                if pot_side == 0 do continue
                if (structure.seed >> 15) & 3 == 1 && pot_side > 0 do continue
                if (structure.seed >> 15) & 3 == 2 && pot_side < 0 do continue
                pot_height := .40 + f32((structure.seed >> u32(4 + pot_side + 1)) & 3) * .07
                pot_local_x := f32(pot_side) * (door_width * .5 + .72)
                pot_x, pot_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    pot_local_x,
                    structure.depth * .5 + .70,
                    structure.rotation,
                )
                world_box_rotated(
                    {pot_x, structure.base_y + pot_height * .5, pot_z},
                    {.42, pot_height, .42},
                    structure.rotation,
                    {167, 91, 56, 255},
                )
                world_box_rotated(
                    {pot_x, structure.base_y + pot_height + .18, pot_z},
                    {.48, .34, .48},
                    structure.rotation,
                    pot_side < 0 ? rl.Color{79, 124, 73, 255} : rl.Color{97, 139, 77, 255},
                )
            }
        }
        if structure.seed % 5 == 2 {
            crate_side := (structure.seed & 8) == 0 ? f32(-1) : f32(1)
            crate_local_x := crate_side * min(structure.width * .34, door_width * .5 + 2.0)
            crate_x, crate_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                crate_local_x,
                structure.depth * .5 + .62,
                structure.rotation,
            )
            world_box_rotated(
                {crate_x, structure.base_y + .30, crate_z},
                {.82, .60, .64},
                structure.rotation,
                {139, 94, 57, 255},
            )
            for slat in -1 ..= 1 {
                slat_x, slat_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    crate_local_x,
                    structure.depth * .5 + .96,
                    structure.rotation,
                )
                world_box_rotated(
                    {slat_x, structure.base_y + .30 + f32(slat) * .18, slat_z},
                    {.74, .055, .04},
                    structure.rotation,
                    {102, 71, 48, 255},
                )
            }
        }
        if structure.width >= 18 && structure.seed % 7 == 3 {
            bench_side := (structure.seed & 16) == 0 ? f32(-1) : f32(1)
            bench_local_x := bench_side * min(structure.width * .32, door_width * .5 + 2.7)
            bench_x, bench_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                bench_local_x,
                structure.depth * .5 + .78,
                structure.rotation,
            )
            world_box_rotated(
                {bench_x, structure.base_y + .52, bench_z},
                {2.1, .16, .58},
                structure.rotation,
                {123, 83, 55, 255},
            )
            for leg_side in -1 ..= 1 {
                if leg_side == 0 do continue
                leg_x, leg_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    bench_local_x + f32(leg_side) * .72,
                    structure.depth * .5 + .78,
                    structure.rotation,
                )
                world_box_rotated(
                    {leg_x, structure.base_y + .25, leg_z},
                    {.14, .50, .42},
                    structure.rotation,
                    {91, 68, 51, 255},
                )
            }
            back_x, back_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                bench_local_x,
                structure.depth * .5 + .55,
                structure.rotation,
            )
            world_box_rotated(
                {back_x, structure.base_y + .92, back_z},
                {2.1, .52, .12},
                structure.rotation,
                {112, 77, 53, 255},
            )
        }
        mat_x, mat_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            0,
            structure.depth * .5 + 1.02,
            structure.rotation,
        )
        world_box_rotated(
            {mat_x, structure.base_y + .075, mat_z},
            {door_width * .78, .04, .48},
            structure.rotation,
            facade_style == 2 ? rl.Color{72, 103, 105, 255} : rl.Color{116, 73, 54, 255},
        )
        for curb_side in -1 ..= 1 {
            if curb_side == 0 do continue
            curb_x, curb_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                f32(curb_side) * (door_width * .5 + .38),
                structure.depth * .5 + 1.10,
                structure.rotation,
            )
            world_box_rotated(
                {curb_x, structure.base_y + .09, curb_z},
                {.16, .18, 1.10},
                structure.rotation,
                formation_face_color(step_color, math.PI, 0),
            )
        }
        if structure.height < 16 && structure.seed % 5 == 0 {
            bollard_side := (structure.seed & 128) == 0 ? f32(-1) : f32(1)
            bollard_local_x := bollard_side * min(structure.width * .34, door_width * .5 + 1.65)
            bollard_x, bollard_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                bollard_local_x,
                structure.depth * .5 + 1.02,
                structure.rotation,
            )
            world_box_rotated(
                {bollard_x, structure.base_y + .46, bollard_z},
                {.28, .92, .28},
                structure.rotation,
                {85, 80, 70, 255},
            )
            world_box_rotated(
                {bollard_x, structure.base_y + .96, bollard_z},
                {.38, .10, .38},
                structure.rotation,
                {104, 94, 76, 255},
            )
        }
        if structure.seed % 6 == 1 {
            broom_side := (structure.seed & 32) == 0 ? f32(-1) : f32(1)
            broom_local_x := broom_side * (door_width * .5 + .52)
            broom_x, broom_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                broom_local_x,
                structure.depth * .5 + .48,
                structure.rotation,
            )
            world_box_rotated(
                {broom_x, structure.base_y + .88, broom_z},
                {.07, 1.62, .07},
                structure.rotation,
                {126, 91, 59, 255},
            )
            world_box_rotated(
                {broom_x, structure.base_y + .15, broom_z},
                {.52, .22, .18},
                structure.rotation,
                {160, 125, 72, 255},
            )
        }
        lantern_side := (structure.seed & 1) == 0 ? f32(-1) : f32(1)
        lantern_local_x := lantern_side * (door_width * .5 + .48)
        lantern_y := structure.base_y + step_height + door_height * (.68 + f32((structure.seed >> 17) & 3) * .035)
        bracket_x, bracket_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            lantern_local_x,
            structure.depth * .5 + .29,
            structure.rotation,
        )
        world_box_rotated(
            {bracket_x, lantern_y + .18, bracket_z},
            {.08, .40, .10},
            structure.rotation,
            {65, 59, 52, 255},
        )
        lamp_x, lamp_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            lantern_local_x,
            structure.depth * .5 + .40,
            structure.rotation,
        )
        world_box_rotated({lamp_x, lantern_y, lamp_z}, {.34, .44, .22}, structure.rotation, {65, 59, 52, 255})
        glass_x, glass_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            lantern_local_x,
            structure.depth * .5 + .525,
            structure.rotation,
        )
        world_box_rotated({glass_x, lantern_y, glass_z}, {.20, .26, .045}, structure.rotation, {224, 184, 105, 255})
        world_box_rotated({glass_x, lantern_y + .25, glass_z}, {.38, .07, .075}, structure.rotation, {65, 59, 52, 255})
        plaque_local_x := -lantern_side * (door_width * .5 + .40)
        plaque_x, plaque_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            plaque_local_x,
            structure.depth * .5 + .355,
            structure.rotation,
        )
        plaque_y := structure.base_y + step_height + door_height * .62
        world_box_rotated({plaque_x, plaque_y, plaque_z}, {.34, .22, .055}, structure.rotation, {202, 184, 145, 255})
        plaque_marks := 1 + int((structure.seed >> 4) % 3)
        for mark in 0 ..< plaque_marks {
            mark_offset := (f32(mark) - f32(plaque_marks - 1) * .5) * .09
            mark_x, mark_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                plaque_local_x + mark_offset,
                structure.depth * .5 + .39,
                structure.rotation,
            )
            world_box_rotated({mark_x, plaque_y, mark_z}, {.035, .11, .025}, structure.rotation, {75, 68, 58, 255})
        }
        if structure.seed % 4 == 1 {
            mailbox_x, mailbox_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                plaque_local_x,
                structure.depth * .5 + .40,
                structure.rotation,
            )
            world_box_rotated(
                {mailbox_x, structure.base_y + step_height + door_height * .38, mailbox_z},
                {.48, .34, .18},
                structure.rotation,
                {76, 91, 91, 255},
            )
            world_box_rotated(
                {mailbox_x, structure.base_y + step_height + door_height * .44, mailbox_z},
                {.34, .035, .20},
                structure.rotation,
                {189, 174, 143, 255},
            )
        }
        if structure.seed % 8 == 5 {
            urn_side := -lantern_side
            urn_local_x := urn_side * min(structure.width * .30, door_width * .5 + 1.55)
            urn_x, urn_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                urn_local_x,
                structure.depth * .5 + .67,
                structure.rotation,
            )
            world_box_rotated(
                {urn_x, structure.base_y + .28, urn_z},
                {.46, .56, .46},
                structure.rotation,
                {151, 105, 66, 255},
            )
            world_box_rotated(
                {urn_x, structure.base_y + .60, urn_z},
                {.58, .10, .58},
                structure.rotation,
                {176, 122, 74, 255},
            )
        }
        // A handful of low-rise blocks read as village shops: a shallow
        // canvas canopy over the entrance adds the lived-in 1940s street
        // rhythm without turning every façade into a storefront.
        if structure.height < 52 && structure.seed % 2 == 0 {
            awning_x, awning_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .46,
                structure.rotation,
            )
            awning_color :=
                structure.seed % 4 == 0 ? rl.Color{196, 105, 71, 255} : structure.seed % 4 == 1 ? rl.Color{215, 198, 151, 255} : rl.Color{105, 143, 151, 255}
            awning_width := door_width + 1.4
            world_box_rotated(
                {awning_x, structure.base_y + step_height + door_height + .82, awning_z},
                {awning_width, .14, .52},
                structure.rotation,
                awning_color,
            )
            stripe_color :=
                structure.seed % 4 == 0 ? rl.Color{226, 198, 157, 255} : structure.seed % 4 == 1 ? rl.Color{183, 91, 70, 255} : rl.Color{214, 199, 163, 255}
            for stripe in -1 ..= 1 {
                stripe_x, stripe_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    f32(stripe) * awning_width * .30,
                    structure.depth * .5 + .49,
                    structure.rotation,
                )
                world_box_rotated(
                    {stripe_x, structure.base_y + step_height + door_height + .832, stripe_z},
                    {awning_width * .28, .035, .54},
                    structure.rotation,
                    stripe % 2 == 0 ? stripe_color : awning_color,
                )
            }
            fascia_x, fascia_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                0,
                structure.depth * .5 + .73,
                structure.rotation,
            )
            world_box_rotated(
                {fascia_x, structure.base_y + step_height + door_height + .74, fascia_z},
                {awning_width, .12, .07},
                structure.rotation,
                formation_face_color(awning_color, math.PI, 0),
            )
            for support_side in -1 ..= 1 {
                if support_side == 0 do continue
                support_x, support_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    f32(support_side) * awning_width * .42,
                    structure.depth * .5 + .39,
                    structure.rotation,
                )
                world_box_rotated(
                    {support_x, structure.base_y + step_height + door_height + .40, support_z},
                    {.07, .74, .08},
                    structure.rotation,
                    {77, 69, 60, 255},
                )
            }
            commercial :=
                identity.archetype == .Shop_House ||
                identity.archetype == .Workshop ||
                identity.archetype == .Harbor_Office ||
                identity.archetype == .Market_Hall
            if commercial && structure.height < 18 && structure.seed % 4 == 0 {
                sign_side := (structure.seed & 64) == 0 ? f32(-1) : f32(1)
                sign_local_x := sign_side * (door_width * .5 + .72)
                sign_y := structure.base_y + step_height + door_height + 1.18
                sign_x, sign_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    sign_local_x,
                    structure.depth * .5 + .49,
                    structure.rotation,
                )
                world_box_rotated({sign_x, sign_y, sign_z}, {1.15, .54, .10}, structure.rotation, {91, 119, 117, 255})
                sign_bracket_x, sign_bracket_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    sign_local_x,
                    structure.depth * .5 + .29,
                    structure.rotation,
                )
                world_box_rotated(
                    {sign_bracket_x, sign_y + .36, sign_bracket_z},
                    {1.32, .07, .09},
                    structure.rotation,
                    {67, 61, 55, 255},
                )
            }
        }
    }
    window_width := architecture.facade_window_width(structure.width)
    window_height := architecture.facade_window_height(structure.height)
    rich_front := habitable
    for row in 0 ..< rows {
        if !rich_front do break
        for column in 0 ..< columns {
            if opening_layout != nil &&
               !architecture.opening_layout_contains(opening_layout, .Front, .Window, row, column) {
                continue
            }
            x := architecture.facade_window_column_x(structure.width, column)
            y := structure.base_y + architecture.facade_window_row_y(structure.height, row)
            local_z := structure.depth * .5 + .16
            wx, wz := world_rotate_xz(structure.center_x, structure.center_z, x, local_z, structure.rotation)
            world_box_rotated({wx, y, wz}, {window_width, window_height, .22}, structure.rotation, window)
            if !landmark {
                glass_x, glass_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x,
                    local_z + .125,
                    structure.rotation,
                )
                glass_tone := int((structure.seed + u32(column * 17)) % 3)
                glass := rl.Color{48, 72, 78, 255}
                if facade_style == 2 {
                    if glass_tone == 0 {
                        glass = {54, 94, 105, 255}
                    } else if glass_tone == 1 {
                        glass = {58, 99, 109, 255}
                    } else {
                        glass = {49, 87, 99, 255}
                    }
                } else if glass_tone == 0 {
                    glass = {54, 78, 82, 255}
                } else if glass_tone == 1 {
                    glass = {60, 84, 86, 255}
                }
                reveal := formation_face_color(window, math.PI, 0)
                world_box_rotated(
                    {glass_x, y, glass_z},
                    {window_width * .94, window_height * .92, .045},
                    structure.rotation,
                    reveal,
                )
                world_box_rotated(
                    {glass_x, y, glass_z},
                    {window_width * .84, window_height * .82, .035},
                    structure.rotation,
                    glass,
                )
                if (structure.seed + u32(row * 11 + column)) % 4 == 0 {
                    curtain := facade_style == 2 ? rl.Color{205, 197, 170, 255} : rl.Color{190, 169, 145, 255}
                    for curtain_side in -1 ..= 1 {
                        if curtain_side == 0 do continue
                        curtain_x, curtain_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x + f32(curtain_side) * window_width * .31,
                            local_z + .095,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {curtain_x, y, curtain_z},
                            {window_width * .10, window_height * .68, .025},
                            structure.rotation,
                            curtain,
                        )
                    }
                }
                mullion := facade_style == 2 ? rl.Color{183, 192, 174, 255} : rl.Color{177, 163, 137, 255}
                world_box_rotated(
                    {glass_x, y, glass_z},
                    {.065, window_height * .82, .055},
                    structure.rotation,
                    mullion,
                )
                if row == 0 && structure.height < 15 && structure.seed % 3 == 1 {
                    for shop_division in -1 ..= 1 {
                        if shop_division == 0 do continue
                        division_x, division_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x + f32(shop_division) * window_width * .25,
                            local_z + .145,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {division_x, y, division_z},
                            {.045, window_height * .82, .045},
                            structure.rotation,
                            mullion,
                        )
                    }
                }
                sill_x, sill_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x,
                    local_z + .18,
                    structure.rotation,
                )
                sill := facade_style == 2 ? rl.Color{166, 171, 151, 255} : rl.Color{190, 166, 128, 255}
                world_box_rotated(
                    {sill_x, y - window_height * .5 - .11, sill_z},
                    {window_width + .38, .10, .30},
                    structure.rotation,
                    sill,
                )
                if structure.height < 15 && structure.seed % 5 == 4 {
                    apron_x, apron_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        x,
                        local_z + .17,
                        structure.rotation,
                    )
                    world_box_rotated(
                        {apron_x, y - window_height * .34, apron_z},
                        {window_width * .88, window_height * .24, .08},
                        structure.rotation,
                        facade_style == 2 ? rl.Color{92, 119, 118, 255} : rl.Color{142, 103, 75, 255},
                    )
                }
                world_box_rotated(
                    {glass_x, y + window_height * .08, glass_z},
                    {window_width * .84, .055, .055},
                    structure.rotation,
                    mullion,
                )
            }
            if !landmark && (facade_style == 0 || facade_style == 1) {
                trim := facade_style == 1 ? rl.Color{205, 190, 157, 255} : rl.Color{190, 166, 128, 255}
                trim_width := window_width + .40
                trim_z := local_z + .045
                trim_x, trim_world_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x,
                    trim_z,
                    structure.rotation,
                )
                world_box_rotated(
                    {trim_x, y + window_height * .5 + .12, trim_world_z},
                    {trim_width, .075, .16},
                    structure.rotation,
                    trim,
                )
                world_box_rotated(
                    {trim_x, y - window_height * .5 - .10, trim_world_z},
                    {trim_width * .92, .065, .18},
                    structure.rotation,
                    formation_face_color(trim, math.PI, 0),
                )
            }
            if !landmark && window_has_flower_box(structure.seed, row, column) {
                flower_x, flower_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x,
                    local_z + .30,
                    structure.rotation,
                )
                world_box_rotated(
                    {flower_x, y - window_height * .5 - .18, flower_z},
                    {window_width + .56, .12, .22},
                    structure.rotation,
                    {178, 111, 73, 255},
                )
                world_window_flower_bunch_billboard(
                    structure,
                    x,
                    y - window_height * .5 - .10,
                    local_z + .35,
                    window_width,
                    row,
                    column,
                )
                // Flower-box openings still need a small Juliet guard. Without
                // it the planter lip reads as an unsupported balcony with its
                // upper railing missing.
                guard_width := window_width + .48
                guard_z := local_z + .40
                guard_color := facade_style == 2 ? rl.Color{64, 82, 83, 255} : rl.Color{83, 68, 62, 255}
                guard_height: f32 = .09
                guard_center_above_sill: f32 = 1.04
                post_width: f32 = .055
                post_base_above_sill: f32 = .04
                post_top_above_sill := guard_center_above_sill - guard_height * .5
                post_height := post_top_above_sill - post_base_above_sill
                post_center_above_sill := (post_base_above_sill + post_top_above_sill) * .5
                post_center_span := guard_width - post_width
                guard_x, guard_world_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    x,
                    guard_z,
                    structure.rotation,
                )
                if row > 0 {
                    world_box_rotated(
                        {guard_x, y - window_height * .5 + guard_center_above_sill, guard_world_z},
                        {guard_width, guard_height, .08},
                        structure.rotation,
                        guard_color,
                    )
                    for post in -2 ..= 2 {
                        post_x, post_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x + f32(post) * post_center_span * .25,
                            guard_z,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {post_x, y - window_height * .5 + post_center_above_sill, post_z},
                            {post_width, post_height, .07},
                            structure.rotation,
                            guard_color,
                        )
                    }
                }
            }
            if !landmark {
                if facade_style == 1 && row > 0 {
                    // A shallow balcony is a small silhouette break that reads
                    // clearly from the wide editor camera without needing a
                    // separate mesh asset.
                    balcony_width := window_width + 1.35
                    balcony_depth: f32 = .90
                    balcony_center_z := local_z + balcony_depth * .5 - .08
                    balcony_x, balcony_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        x,
                        balcony_center_z,
                        structure.rotation,
                    )
                    rail_width := window_width + .85
                    rail_front_z := local_z + balcony_depth - .13
                    railing_x, railing_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        x,
                        rail_front_z,
                        structure.rotation,
                    )
                    world_box_rotated(
                        {balcony_x, y - window_height * .5 - .14, balcony_z},
                        {balcony_width, .20, balcony_depth},
                        structure.rotation,
                        {196, 151, 103, 255},
                    )
                    world_box_rotated(
                        {railing_x, y - window_height * .5 + .58, railing_z},
                        {window_width + .85, .11, .08},
                        structure.rotation,
                        {102, 76, 63, 255},
                    )
                    for post in -2 ..= 2 {
                        post_x, post_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x + f32(post) * rail_width * .25,
                            rail_front_z,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {post_x, y - window_height * .5 + .20, post_z},
                            {.065, .72, .08},
                            structure.rotation,
                            {102, 76, 63, 255},
                        )
                    }
                    for side in -1 ..= 1 {
                        if side == 0 do continue
                        return_x, return_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x + f32(side) * rail_width * .5,
                            (local_z + rail_front_z) * .5,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {return_x, y - window_height * .5 + .58, return_z},
                            {.08, .11, rail_front_z - local_z},
                            structure.rotation,
                            {102, 76, 63, 255},
                        )
                    }
                } else if facade_style == 2 {
                    // Blue façades use small fabric awnings rather than
                    // balconies, giving this seed variant a distinct profile.
                    awning_x, awning_z := world_rotate_xz(
                        structure.center_x,
                        structure.center_z,
                        x,
                        local_z + .12,
                        structure.rotation,
                    )
                    world_box_rotated(
                        {awning_x, y + window_height * .5 + .30, awning_z},
                        {window_width + .65, .12, .34},
                        structure.rotation,
                        shutter,
                    )
                } else {
                    if facade_style == 0 && row > 0 && row % 2 == 0 {
                        // Alternating wrought-iron balconies give the warmer
                        // stucco façades a lived-in 1940s Mediterranean rhythm.
                        balcony_width := window_width + 1.20
                        balcony_depth: f32 = .90
                        balcony_center_z := local_z + balcony_depth * .5 - .08
                        balcony_x, balcony_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x,
                            balcony_center_z,
                            structure.rotation,
                        )
                        rail_width := window_width + .75
                        rail_front_z := local_z + balcony_depth - .13
                        railing_x, railing_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x,
                            rail_front_z,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {balcony_x, y - window_height * .5 - .14, balcony_z},
                            {balcony_width, .20, balcony_depth},
                            structure.rotation,
                            {196, 151, 103, 255},
                        )
                        world_box_rotated(
                            {railing_x, y - window_height * .5 + .58, railing_z},
                            {window_width + .75, .11, .08},
                            structure.rotation,
                            {83, 68, 62, 255},
                        )
                        for post in -2 ..= 2 {
                            post_x, post_z := world_rotate_xz(
                                structure.center_x,
                                structure.center_z,
                                x + f32(post) * rail_width * .25,
                                rail_front_z,
                                structure.rotation,
                            )
                            world_box_rotated(
                                {post_x, y - window_height * .5 + .20, post_z},
                                {.06, .68, .08},
                                structure.rotation,
                                {83, 68, 62, 255},
                            )
                        }
                        for side in -1 ..= 1 {
                            if side == 0 do continue
                            return_x, return_z := world_rotate_xz(
                                structure.center_x,
                                structure.center_z,
                                x + f32(side) * rail_width * .5,
                                (local_z + rail_front_z) * .5,
                                structure.rotation,
                            )
                            world_box_rotated(
                                {return_x, y - window_height * .5 + .58, return_z},
                                {.08, .11, rail_front_z - local_z},
                                structure.rotation,
                                {83, 68, 62, 255},
                            )
                        }
                        planter_x, planter_z := world_rotate_xz(
                            structure.center_x,
                            structure.center_z,
                            x,
                            local_z + .34,
                            structure.rotation,
                        )
                        world_box_rotated(
                            {planter_x, y - window_height * .5 + .10, planter_z},
                            {window_width + .25, .12, .12},
                            structure.rotation,
                            {107, 132, 92, 255},
                        )
                    } else {
                        shutter_width := clamp(window_width * .30, f32(.42), f32(.62))
                        for side in -1 ..= 1 {
                            if side == 0 do continue
                            sx, sz := world_rotate_xz(
                                wx,
                                wz,
                                f32(side) * (window_width * .5 + shutter_width * .5 + .08),
                                0,
                                structure.rotation,
                            )
                            world_box_rotated(
                                {sx, y, sz},
                                {shutter_width, window_height + .24, .28},
                                structure.rotation,
                                shutter,
                            )
                            hinge_x, hinge_z := world_rotate_xz(sx, sz, 0, .17, structure.rotation)
                            for hinge in -1 ..= 1 {
                                if hinge == 0 do continue
                                world_box_rotated(
                                    {hinge_x, y + f32(hinge) * window_height * .28, hinge_z},
                                    {shutter_width * .72, .055, .06},
                                    structure.rotation,
                                    {70, 65, 59, 255},
                                )
                            }
                            holdback_x, holdback_z := world_rotate_xz(
                                sx,
                                sz,
                                f32(side) * shutter_width * .34,
                                .19,
                                structure.rotation,
                            )
                            world_box_rotated(
                                {holdback_x, y - window_height * .58, holdback_z},
                                {.10, .18, .07},
                                structure.rotation,
                                {70, 65, 59, 255},
                            )
                            if row == 0 && structure.seed % 5 == 0 {
                                world_box_rotated(
                                    {hinge_x, y, hinge_z},
                                    {shutter_width + .04, .12, .07},
                                    structure.rotation,
                                    {203, 174, 119, 255},
                                )
                            }
                        }
                    }
                }
            }
        }
    }
    face_trim :=
        facade_style == 2 ? rl.Color{166, 171, 151, 255} : (facade_style == 1 ? rl.Color{205, 190, 157, 255} : rl.Color{190, 166, 128, 255})
    world_architecture_face_openings(structure, opening_layout, window, face_trim)
    // Climbing foliage is authored exclusively through the density brush;
    // keep the legacy always-on planter vine disabled so it cannot overlap
    // the simulated growth with a second, unrelated stem.
    if false {
        // A small bougainvillea climbs from one planter. Keep the stem close
        // to the wall and use individual leaf pairs so it reads as a vine,
        // not as floating topiary attached to the façade.
        vine_side := structure.seed % 2 == 0 ? -1 : 1
        vine_z_local := structure.depth * .5 + .39
        vine_x_base := f32(vine_side) * structure.width * .36
        vine_bottom := structure.base_y + structure.height * .14
        vine_top := structure.base_y + structure.height * .72
        planter_x, planter_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            vine_x_base,
            vine_z_local + .04,
            structure.rotation,
        )
        world_box_rotated(
            {planter_x, vine_bottom - .06, planter_z},
            {.62, .28, .42},
            structure.rotation,
            {164, 91, 62, 255},
        )
        stem_x, stem_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            vine_x_base,
            vine_z_local,
            structure.rotation,
        )
        world_box_rotated(
            {stem_x, (vine_bottom + vine_top) * .5, stem_z},
            {.07, vine_top - vine_bottom, .06},
            structure.rotation,
            {72, 119, 62, 255},
        )
        for segment in 0 ..< 7 {
            start_t := f32(segment) / 7
            end_t := f32(segment + 1) / 7
            start_x :=
                vine_x_base + f32(math.sin(f64(f32(structure.seed + u32(segment)) * .47))) * structure.width * .035
            end_x :=
                vine_x_base + f32(math.sin(f64(f32(structure.seed + u32(segment + 1)) * .47))) * structure.width * .035
            start_y := vine_bottom + (vine_top - vine_bottom) * start_t
            end_y := vine_bottom + (vine_top - vine_bottom) * end_t
            if segment % 2 == 1 {
                branch_x, branch_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    end_x + f32(vine_side) * structure.width * .035,
                    vine_z_local + .035,
                    structure.rotation,
                )
                world_box_rotated(
                    {branch_x, end_y, branch_z},
                    {.30, .045, .045},
                    structure.rotation,
                    {72, 119, 62, 255},
                )
                leaf_x, leaf_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    end_x + f32(vine_side) * structure.width * .07,
                    vine_z_local + .02,
                    structure.rotation,
                )
                world_ellipsoid_rotated({leaf_x, end_y, leaf_z}, .38, .13, .22, structure.rotation, {63, 117, 62, 255})
                second_leaf_x, second_leaf_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    end_x - f32(vine_side) * structure.width * .055,
                    vine_z_local + .04,
                    structure.rotation,
                )
                world_ellipsoid_rotated(
                    {second_leaf_x, end_y - .06, second_leaf_z},
                    .30,
                    .11,
                    .18,
                    structure.rotation,
                    {78, 133, 70, 255},
                )
            }
            if segment == 2 || segment == 5 {
                bloom_x, bloom_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    end_x + f32(vine_side) * structure.width * .085,
                    vine_z_local + .05,
                    structure.rotation,
                )
                world_ellipsoid_rotated(
                    {bloom_x, end_y + .02, bloom_z},
                    .18,
                    .14,
                    .16,
                    structure.rotation,
                    {214, 82, 112, 255},
                )
            }
        }
    }
    if !landmark && (roof_style == .Gable || roof_style == .Low_Gable) {
        // Put each opening on one consistent plane just beyond the barge
        // overhang. Size it from the roof rise and leave off shutters: the
        // triangular end has room for one clear opening, not three competing
        // vertical marks beneath its slopes.
        rise := roof_style == .Low_Gable ? structure.width * .24 : structure.width * .34
        center_fraction := roof_style == .Low_Gable ? f32(.36) : f32(.40)
        attic_height := min(clamp(rise * .25, f32(.75), f32(2.4)), rise * .38)
        attic_top_fraction := center_fraction + attic_height * .5 / rise
        // The gable narrows linearly toward the ridge. Cap the opening from
        // the width available at its upper corners so low roofs cannot clip
        // or completely surround a minimum-sized window.
        available_width := structure.width * (1 - attic_top_fraction) * .72
        attic_width := min(clamp(structure.width * .12, f32(1.0), f32(2.2)), available_width)
        if attic_height >= .65 && attic_width >= .80 {
            attic_y := structure.base_y + structure.height + rise * center_fraction
            for gable_end in -1 ..= 1 {
                if gable_end == 0 do continue
                local_z := f32(gable_end) * (structure.depth * .58 + .12)
                attic_x, attic_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    0,
                    local_z,
                    structure.rotation,
                )
                world_box_rotated(
                    {attic_x, attic_y, attic_z},
                    {attic_width, attic_height, .20},
                    structure.rotation,
                    window,
                )
            }
        }
    }
}

world_architecture :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    lod: Structure_LOD = .Near,
) {
    footprint := architecture.architecture_footprint(structure)
    if footprint.count <= 1 {
        layout := architecture.architecture_opening_layout(structure, 0, 0)
        world_architecture_mass(structure, project, true, &layout, lod)
        return
    }
    frontage_index := architecture.architecture_frontage_mass_index(structure)
    for mass, mass_index in footprint.masses[:footprint.count] {
        child := structure
        child.center_x, child.center_z = architecture.architecture_mass_world(structure, mass)
        child.width = mass.width
        child.depth = mass.depth
        child.height = max(terrain.BASE_CELL_SIZE, structure.height * mass.height_scale)
        // Keep palette identity while decoupling repeated openings and tiles.
        child.seed = structure.seed + u32(mass_index * 747796405)
        layout := architecture.architecture_opening_layout(structure, mass_index, frontage_index)
        world_architecture_mass(child, project, mass_index == frontage_index, &layout, lod)
    }
}

world_architecture_alleys :: proc(editor: ^Editor, plan: ^architecture.City_Plan, preview: bool = false) {
    if editor == nil || plan == nil do return
    for alley in plan.alleys[:plan.alley_count] {
        dx, dz := alley.end_x - alley.start_x, alley.end_z - alley.start_z
        length := f32(math.sqrt(f64(dx * dx + dz * dz)))
        if length <= .01 do continue
        center_x, center_z := (alley.start_x + alley.end_x) * .5, (alley.start_z + alley.end_z) * .5
        world_land_surface_rotated(
            editor,
            center_x,
            center_z,
            length,
            alley.half_width * 2,
            f32(math.atan2(f64(dz), f64(dx))),
            .13,
            preview ? rl.Color{176, 161, 128, 150} : rl.Color{151, 137, 110, 255},
        )
    }
}

world_architecture_lamps :: proc(editor: ^Editor, plan: ^architecture.City_Plan) {
    if editor == nil || plan == nil do return
    for lamp in plan.lamps[:plan.lamp_count] {
        base_y := terrain.sample_height(&editor.project, 0, lamp.x, lamp.z)
        metal := rl.Color{48, 54, 53, 255}
        glass := rl.Color{235, 190, 102, 255}
        world_box_rotated({lamp.x, base_y + .10, lamp.z}, {.48, .20, .48}, lamp.yaw, metal)
        world_box_rotated({lamp.x, base_y + 1.70, lamp.z}, {.14, 3.20, .14}, lamp.yaw, metal)
        world_box_rotated({lamp.x, base_y + 3.36, lamp.z}, {.58, .14, .58}, lamp.yaw, metal)
        world_box_rotated({lamp.x, base_y + 3.62, lamp.z}, {.42, .42, .42}, lamp.yaw, glass)
        world_box_rotated({lamp.x, base_y + 3.87, lamp.z}, {.54, .10, .54}, lamp.yaw, metal)
    }
}

world_structure_frame :: proc(structure: terrain.Structure, y: f32, color: rl.Color) {
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
    color := rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    vertices: [4][12]third_person.Vec3
    normals: [4][12]third_person.Vec3
    colors: [4][12]rl.Color
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

world_small_faceted_rock :: proc(structure: terrain.Structure) {
    world_small_rock_templates_init()
    template := &small_rock_templates[int(structure.seed % SMALL_ROCK_VARIATION_COUNT)]
    base_color := rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    radius_x := structure.width * .5 * template.footprint_x
    radius_z := structure.depth * .5 * template.footprint_z
    rock_height := structure.height * template.height_scale
    bottom: [SMALL_ROCK_SIDE_CAPACITY]third_person.Vec3
    shoulder: [SMALL_ROCK_SIDE_CAPACITY]third_person.Vec3
    crest: [SMALL_ROCK_SIDE_CAPACITY]third_person.Vec3
    side_normal: [SMALL_ROCK_SIDE_CAPACITY]third_person.Vec3
    ridge_x, ridge_z := math.cos(template.ridge_angle), math.sin(template.ridge_angle)
    for side in 0 ..< template.side_count {
        angle := f32(side) * math.TAU / f32(template.side_count)
        local_x := math.cos(angle) * radius_x * template.bottom_radius[side]
        local_z := math.sin(angle) * radius_z * template.bottom_radius[side]
        bottom_x, bottom_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            local_z,
            structure.rotation,
        )
        shoulder_x, shoulder_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x * template.shoulder_radius[side],
            local_z * template.shoulder_radius[side],
            structure.rotation,
        )
        bottom[side] = {bottom_x, structure.base_y, bottom_z}
        shoulder[side] = {shoulder_x, structure.base_y + rock_height * template.shoulder_height[side], shoulder_z}
        if template.cap_mode == 1 || template.cap_mode == 2 {
            projection := math.cos(angle - template.ridge_angle)
            ridge_local_x := ridge_x * projection * radius_x * template.ridge_length
            ridge_local_z := ridge_z * projection * radius_z * template.ridge_length
            crest_x, crest_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                ridge_local_x + template.cap_offset_x * radius_x,
                ridge_local_z + template.cap_offset_z * radius_z,
                structure.rotation,
            )
            saddle := template.cap_mode == 2 ? abs(projection) * .12 - .05 : f32(0)
            crest[side] = {crest_x, structure.base_y + rock_height * (template.cap_height + saddle), crest_z}
        } else {
            crest_x, crest_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x * template.cap_scale + template.cap_offset_x * radius_x,
                local_z * template.cap_scale + template.cap_offset_z * radius_z,
                structure.rotation,
            )
            step := template.cap_mode == 3 && side & 1 == 0 ? f32(.09) : f32(0)
            crest[side] = {crest_x, structure.base_y + rock_height * (template.cap_height + step), crest_z}
        }
        normal_x, normal_z := world_rotate_xz(
            0,
            0,
            math.cos(angle) / max(radius_x, f32(.01)),
            math.sin(angle) / max(radius_z, f32(.01)),
            structure.rotation,
        )
        side_normal[side] = linalg.normalize0([3]f32{normal_x, .22, normal_z})
    }
    tone := f32(int(structure.seed & 7) - 3) * 1.7
    rock_color := rl.Color {
        r = u8(clamp(f32(base_color.r) + tone, 0, 255)),
        g = u8(clamp(f32(base_color.g) + tone * .65, 0, 255)),
        b = u8(clamp(f32(base_color.b) - tone * .30, 0, 255)),
        a = base_color.a,
    }
    for side in 0 ..< template.side_count {
        next := (side + 1) % template.side_count
        world_triangle_smooth_lit(
            bottom[side],
            shoulder[side],
            shoulder[next],
            side_normal[side],
            side_normal[side],
            side_normal[next],
            rock_color,
            rock_color,
            rock_color,
            .96,
        )
        world_triangle_smooth_lit(
            bottom[side],
            shoulder[next],
            bottom[next],
            side_normal[side],
            side_normal[next],
            side_normal[next],
            rock_color,
            rock_color,
            rock_color,
            .96,
        )
        world_triangle_smooth_lit(
            shoulder[side],
            crest[side],
            crest[next],
            {0, 1, 0},
            {0, 1, 0},
            {0, 1, 0},
            rock_color,
            rock_color,
            rock_color,
            .98,
        )
        world_triangle_smooth_lit(
            shoulder[side],
            crest[next],
            shoulder[next],
            {0, 1, 0},
            {0, 1, 0},
            {0, 1, 0},
            rock_color,
            rock_color,
            rock_color,
            .98,
        )
    }
    if template.cap_mode == 0 || template.cap_mode == 3 {
        cap_x, cap_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            template.cap_offset_x * radius_x,
            template.cap_offset_z * radius_z,
            structure.rotation,
        )
        cap := third_person.Vec3 {
            cap_x,
            structure.base_y + rock_height * (template.cap_height + (template.cap_mode == 3 ? f32(.04) : f32(0))),
            cap_z,
        }
        for side in 0 ..< template.side_count {
            next := (side + 1) % template.side_count
            world_triangle_smooth_lit(
                crest[side],
                cap,
                crest[next],
                {0, 1, 0},
                {0, 1, 0},
                {0, 1, 0},
                rock_color,
                rock_color,
                rock_color,
                .98,
            )
        }
    }
}

@(no_instrumentation)
world_formation_sea_vegetation_band :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project,
    lod: Structure_LOD = .Near,
) {
    if project == nil || structure.base_y > project.sea_level + .04 do return

    footprint := max(structure.width, structure.depth)
    band_height := clamp(footprint * .09, f32(.18), structure.height * .22)
    if band_height <= .04 do return

    // Larger sea stacks support a broader fringe, while the height cap keeps
    // small, tall spires from turning green all the way up their faces.
    color := rl.Color{76, 105, 73, 255}
    if structure.kind == .Cliff {
        band := structure
        band.width += .035
        band.depth += .035
        band.height = band_height
        band.color = {color.r, color.g, color.b, color.a}
        world_cliff_formation(band, lod)
        return
    }

    segments := lod == .Near ? 16 : lod == .Medium ? 10 : 6
    lower: [16]third_person.Vec3
    upper: [16]third_person.Vec3
    fraction := clamp(band_height / max(structure.height, f32(.001)), 0, 1)
    top_radius := f32(1)
    switch structure.kind {
    case .Rock:
        top_radius = 1 - fraction * .25
    case .Spire:
        top_radius = 1 - fraction * .72
    case .Mountain:
        top_radius = 1 - fraction * .25
    case .Ridge:
        top_radius = 1 - fraction * .30
    case .Box, .Cliff, .Foliage, .Architecture:
        return
    }
    top_radius = max(top_radius, f32(.2))
    for segment in 0 ..< segments {
        angle := f32(segment) * math.PI * 2 / f32(segments)
        lower_x, lower_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            math.cos(angle) * structure.width * .505,
            math.sin(angle) * structure.depth * .505,
            structure.rotation,
        )
        upper_x, upper_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            math.cos(angle) * structure.width * .5 * (top_radius + .01),
            math.sin(angle) * structure.depth * .5 * (top_radius + .01),
            structure.rotation,
        )
        lower[segment] = {lower_x, structure.base_y, lower_z}
        upper[segment] = {upper_x, structure.base_y + band_height, upper_z}
    }
    for segment in 0 ..< segments {
        next := (segment + 1) % segments
        world_quad(lower[segment], upper[segment], upper[next], lower[next], color)
    }
}

world_formation :: proc(
    structure: terrain.Structure,
    project: ^terrain.Project = nil,
    lod: Structure_LOD = .Near,
) {
    switch structure.kind {
    case .Box:
        world_box_rotated(
            {structure.center_x, structure.base_y + structure.height * .5, structure.center_z},
            {structure.width, structure.height, structure.depth},
            structure.rotation,
            rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]},
        )
    case .Rock:
        if max(structure.width, structure.depth, structure.height) <= 5 && lod != .Far {
            world_small_faceted_rock(structure)
        } else {
            world_radial_formation(structure, {1, .94, .62, .20}, {0, .24, .58, .88}, 1, .96, lod)
        }
    case .Spire:
        world_radial_formation(structure, {1, .62, .30, .07}, {0, .20, .46, .94}, 1, 1, lod)
    case .Mountain:
        world_radial_formation(structure, {1, .94, .68, .24}, {0, .22, .54, .86}, 1, .99, lod)
    case .Ridge:
        stone := structure
        stone.color = world_limestone_color(.Ridge)
        world_radial_formation(stone, {1, .92, .60, .14}, {0, .22, .50, .78}, .42, .90, lod)
        world_formation_foliage(stone, lod)
    case .Cliff:
        stone := structure
        stone.color = world_limestone_color(.Cliff)
        world_cliff_formation(stone, lod)
        world_formation_foliage(stone, lod)
    case .Foliage:
        world_foliage_formation(structure, terrain.BASE_CELL_SIZE, lod)
    case .Architecture:
        world_architecture(structure, project, lod)
    }
    world_formation_sea_vegetation_band(structure, project, lod)
}

world_foliage_formation_cached :: proc(
    structure: terrain.Structure,
    structure_index: int,
    force_near := false,
) {
    if structure_index < 0 || structure_index >= len(world_renderer.foliage_geometry_cache) {
        world_foliage_formation(structure)
        return
    }
    entry := &world_renderer.foliage_geometry_cache[structure_index]
    lod_result := structure_lod_for(structure, entry.lod, force_near)
    camera := world_renderer.editor.camera_pose.position
    dx := camera.x - structure.center_x
    dz := camera.z - structure.center_z
    distance := f32(math.sqrt(f64(dx * dx + dz * dz)))
    // Foliage topology and surface detail vary with camera distance, while a
    // few accent cards choose the camera-facing side of a crown. Quantizing
    // both values keeps those authored LOD decisions responsive without
    // rebuilding thousands of deterministic static vertices every frame.
    // Structure-relative buckets also stagger rebuilds naturally as the
    // player moves through a forest instead of invalidating the whole scene.
    distance_bucket := lod_result.tier == .Far ? i32(0) : i32(math.floor(distance / 16))
    direction := math.atan2(dz, dx)
    direction_bucket := lod_result.tier == .Far ? i32(0) :
        i32(math.floor((direction + math.PI) * 16 / (math.PI * 2)))
    if entry.valid &&
       entry.structure == structure &&
       entry.lod == lod_result.tier &&
       entry.distance_bucket == distance_bucket &&
       entry.direction_bucket == direction_bucket {
        append(&world_renderer.vertices, ..entry.world_vertices[:])
        append(&world_renderer.foliage_vertices, ..entry.foliage_vertices[:])
        return
    }

    world_first := len(world_renderer.vertices)
    foliage_first := len(world_renderer.foliage_vertices)
    world_foliage_formation(structure, terrain.BASE_CELL_SIZE, lod_result.tier)
    world_renderer.structure_lod_cache_rebuilds += 1
    clear(&entry.world_vertices)
    clear(&entry.foliage_vertices)
    if world_first < len(world_renderer.vertices) {
        append(&entry.world_vertices, ..world_renderer.vertices[world_first:])
    }
    if foliage_first < len(world_renderer.foliage_vertices) {
        append(&entry.foliage_vertices, ..world_renderer.foliage_vertices[foliage_first:])
    }
    entry.valid = true
    entry.structure = structure
    entry.lod = lod_result.tier
    entry.lod_transition = lod_result.transition
    entry.distance_bucket = distance_bucket
    entry.direction_bucket = direction_bucket
}

world_static_mesh_append :: proc(entry: ^Static_Geometry_Cache_Entry) {
    if entry == nil || len(entry.world_vertices) == 0 || len(entry.world_indices) == 0 do return
    vertex_base := u32(len(world_renderer.static_vertices))
    append(&world_renderer.static_vertices, ..entry.world_vertices[:])
    reserve(&world_renderer.static_indices, len(world_renderer.static_indices) + len(entry.world_indices))
    for index in entry.world_indices {
        append(&world_renderer.static_indices, vertex_base + index)
    }
}

world_static_formation_cached :: proc(
    structure: terrain.Structure,
    structure_index: int,
    project: ^terrain.Project,
    force_near := false,
) {
    if project == nil ||
       structure_index < 0 ||
       structure_index >= len(world_renderer.static_geometry_cache) {
        world_formation(structure, project)
        return
    }
    entry := &world_renderer.static_geometry_cache[structure_index]
    lod_result := structure_lod_for(structure, entry.lod, force_near)
    if entry.valid &&
       entry.structure == structure &&
       entry.lod == lod_result.tier {
        world_static_mesh_append(entry)
        append(&world_renderer.foliage_vertices, ..entry.foliage_vertices[:])
        append(&world_renderer.bougainvillea_vertices, ..entry.bougainvillea_vertices[:])
        return
    }

    world_first := len(world_renderer.vertices)
    foliage_first := len(world_renderer.foliage_vertices)
    bougainvillea_first := len(world_renderer.bougainvillea_vertices)
    world_formation(structure, project, lod_result.tier)
    world_renderer.structure_lod_cache_rebuilds += 1
    clear(&entry.world_vertices)
    clear(&entry.world_indices)
    clear(&entry.foliage_vertices)
    clear(&entry.bougainvillea_vertices)
    if world_first < len(world_renderer.vertices) {
        source := world_renderer.vertices[world_first:]
        resize(&entry.world_vertices, len(source))
        resize(&entry.world_indices, len(source))
        optimized_count := adriatic_optimize_unindexed_mesh(
            raw_data(entry.world_vertices),
            raw_data(entry.world_indices),
            raw_data(source),
            u32(len(source)),
            u32(size_of(World_Vertex)),
        )
        if optimized_count > 0 {
            resize(&entry.world_vertices, int(optimized_count))
            resize(&world_renderer.vertices, world_first)
            world_static_mesh_append(entry)
        } else {
            clear(&entry.world_vertices)
            clear(&entry.world_indices)
        }
    }
    if foliage_first < len(world_renderer.foliage_vertices) {
        append(&entry.foliage_vertices, ..world_renderer.foliage_vertices[foliage_first:])
    }
    if bougainvillea_first < len(world_renderer.bougainvillea_vertices) {
        append(&entry.bougainvillea_vertices, ..world_renderer.bougainvillea_vertices[bougainvillea_first:])
    }
    entry.valid = true
    entry.structure = structure
    entry.lod = lod_result.tier
    entry.lod_transition = lod_result.transition
}

world_structure_preview_cluster :: proc(editor: ^Editor) {
    if editor == nil do return
    preview := editor.structure_preview
    preview.color = {168, 239, 220, 255}
    world_formation(preview)
    world_structure_frame(preview, preview.base_y + .04, {190, 255, 229, 255})
    if !editor.structure_scatter_mode do return
    dx := editor.structure_preview_end_x - editor.structure_anchor_x
    dz := editor.structure_preview_end_z - editor.structure_anchor_z
    length := f32(math.sqrt(f64(dx * dx + dz * dz)))
    if length <= 0 do return
    direction_x, direction_z := dx / length, dz / length
    perpendicular_x, perpendicular_z := -direction_z, direction_x
    cell := editor.project.levels[0].cell_size
    for cluster_index in 0 ..< editor.structure_scatter_count - 1 {
        offset := f32(cluster_index) - f32(editor.structure_scatter_count - 2) * .5
        copy := preview
        copy.center_x += direction_x * offset * length * .22
        copy.center_z += direction_z * offset * length * .22
        jitter := f32(
            math.sin(
                f64(f32(cluster_index) * 2.31 + f32(editor.project.next_structure_id + u64(cluster_index + 1)) * .17),
            ),
        )
        copy.center_x += perpendicular_x * jitter * length * .10
        copy.center_z += perpendicular_z * jitter * length * .10
        copy.width = max(cell, copy.width * (.58 + f32(cluster_index % 2) * .12))
        copy.depth = max(cell, copy.depth * (.58 + f32((cluster_index + 1) % 2) * .12))
        copy.height = max(cell, copy.height * (.72 + f32(cluster_index) * .06))
        copy.base_y = terrain.sample_height(&editor.project, 0, copy.center_x, copy.center_z)
        copy.seed = u32(editor.project.next_structure_id + u64(cluster_index + 1)) * 747796405
        if editor.authoring_tool == .Foliage {
            copy.kind = .Foliage
        } else if !editor.structure_force_box && !editor.structure_cliff_mode {
            copy.kind = terrain.formation_kind_for_gesture(copy.width, copy.depth, copy.height)
        }
        copy.color = {168, 239, 220, 255}
        world_formation(copy)
        world_structure_frame(copy, copy.base_y + .04, {190, 255, 229, 255})
    }
}

world_curve_preview :: proc(editor: ^Editor) {
    if editor == nil || !editor.curve_drawing || editor.curve_point_count < 2 do return
    for index in 0 ..< editor.curve_point_count - 1 {
        preview := curve_segment_structure(editor, editor.curve_points[index], editor.curve_points[index + 1])
        preview.color = {168, 239, 220, 255}
        world_formation(preview)
        world_structure_frame(preview, preview.base_y + .04, {190, 255, 229, 255})
    }
}

world_cliff_formation :: proc(structure: terrain.Structure, lod: Structure_LOD = .Near) {
    segments := lod == .Near ? 6 : lod == .Medium ? 4 : 2
    color := rl.Color{structure.color[0], structure.color[1], structure.color[2], structure.color[3]}
    front_bottom: [7]third_person.Vec3
    front_top: [7]third_person.Vec3
    back_top: [7]third_person.Vec3
    back_bottom: [7]third_person.Vec3
    for segment in 0 ..= segments {
        fraction := f32(segment) / f32(segments)
        local_x := (fraction - .5) * structure.width
        top_jitter := f32(math.sin(f64(f32(structure.seed) * .001 + f32(segment) * 1.73))) * .055
        top_y := structure.base_y + structure.height * (.84 + top_jitter)
        front_x, front_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            -structure.depth * .5,
            structure.rotation,
        )
        back_x, back_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            structure.depth * .08,
            structure.rotation,
        )
        foot_x, foot_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            local_x,
            structure.depth * .5,
            structure.rotation,
        )
        front_bottom[segment] = {front_x, structure.base_y, front_z}
        front_top[segment] = {front_x, top_y, front_z}
        back_top[segment] = {back_x, top_y, back_z}
        back_bottom[segment] = {foot_x, structure.base_y + structure.height * .14, foot_z}
    }
    for segment in 0 ..< segments {
        front_face := formation_face_color(color, -math.PI * .5, 0)
        top_face := formation_face_color(color, 0, 1)
        back_face := formation_face_color(color, math.PI * .5, 0)
        world_quad(
            front_bottom[segment],
            front_bottom[segment + 1],
            front_top[segment + 1],
            front_top[segment],
            front_face,
        )
        world_quad(front_top[segment], front_top[segment + 1], back_top[segment + 1], back_top[segment], top_face)
        world_quad(back_top[segment], back_top[segment + 1], back_bottom[segment + 1], back_bottom[segment], back_face)
    }
    world_quad(front_bottom[0], back_bottom[0], back_top[0], front_top[0], formation_face_color(color, -math.PI, 0))
    world_quad(
        front_bottom[segments],
        front_top[segments],
        back_top[segments],
        back_bottom[segments],
        formation_face_color(color, 0, 0),
    )
}

world_limestone_color :: proc(kind: terrain.Formation_Kind) -> [4]u8 {
    if kind == .Cliff do return {193, 191, 178, 255}
    return {215, 211, 193, 255}
}

world_foliage_card :: proc(
    center: third_person.Vec3,
    width, height: f32,
    tile: int,
    color: rl.Color,
    mirror: bool,
    flip_vertical := false,
) {
    editor := world_renderer.editor
    if editor == nil do return
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    right := third_person.Vec3{camera.right.x * width * .5, camera.right.y * width * .5, camera.right.z * width * .5}
    up := third_person.Vec3{camera.up.x * height * .5, camera.up.y * height * .5, camera.up.z * height * .5}
    p0 := third_person.Vec3{center.x - right.x - up.x, center.y - right.y - up.y, center.z - right.z - up.z}
    p1 := third_person.Vec3{center.x + right.x - up.x, center.y + right.y - up.y, center.z + right.z - up.z}
    p2 := third_person.Vec3{center.x + right.x + up.x, center.y + right.y + up.y, center.z + right.z + up.z}
    p3 := third_person.Vec3{center.x - right.x + up.x, center.y - right.y + up.y, center.z - right.z + up.z}

    atlas_tile := ((tile % 16) + 16) % 16
    column, row := atlas_tile % 4, atlas_tile / 4
    // A two-pixel inset prevents linear filtering from borrowing color from
    // the neighboring cell in the 1254px atlas.
    inset := f32(2.0 / 1254.0)
    u0 := f32(column) * .25 + inset
    v0 := f32(row) * .25 + inset
    u1 := f32(column + 1) * .25 - inset
    v1 := f32(row + 1) * .25 - inset
    if mirror {
        u0, u1 = u1, u0
    }
    if flip_vertical {
        v0, v1 = v1, v0
    }
    tint := world_color(color)
    append(
        &world_renderer.foliage_vertices,
        Foliage_Vertex{{p0.x, p0.y, p0.z}, {u0, v1}, tint, 0},
        Foliage_Vertex{{p1.x, p1.y, p1.z}, {u1, v1}, tint, 0},
        Foliage_Vertex{{p2.x, p2.y, p2.z}, {u1, v0}, tint, 0},
        Foliage_Vertex{{p0.x, p0.y, p0.z}, {u0, v1}, tint, 0},
        Foliage_Vertex{{p2.x, p2.y, p2.z}, {u1, v0}, tint, 0},
        Foliage_Vertex{{p3.x, p3.y, p3.z}, {u0, v0}, tint, 0},
    )
}

world_bougainvillea_card :: proc(
    center: third_person.Vec3,
    width, height: f32,
    tile: int,
    mirror: bool,
    roll: f32 = 0,
    value: f32 = 1,
    young_growth: bool = false,
    yaw_bias: f32 = 0,
) {
    editor := world_renderer.editor
    if editor == nil do return
    atlas_tile := ((tile % 16) + 16) % 16
    // Normalized painted branch origins within each atlas cell. Upright
    // clumps root near bottom-center; lateral sprays root at the appropriate
    // lower corner. Aligning these rather than each card's geometric center
    // keeps the generated foliage visibly attached to its procedural branch.
    anchors := [16][2]f32 {
        {.50, .90},
        {.12, .88},
        {.50, .91},
        {.08, .88},
        {.50, .90},
        {.12, .88},
        {.50, .91},
        {.08, .88},
        {.50, .90},
        {.10, .87},
        {.50, .91},
        {.08, .88},
        {.50, .90},
        {.10, .88},
        {.50, .92},
        {.08, .88},
    }
    anchor_x, anchor_y := anchors[atlas_tile][0], anchors[atlas_tile][1]
    texture_anchor_x := anchor_x
    if mirror do anchor_x = 1 - anchor_x
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    // Constrained cylindrical billboarding keeps the painted stem origin
    // mostly vertical as the camera pitches. A small camera-up contribution
    // prevents severe foreshortening in low-angle architectural views without
    // letting the clump lean freely like a HUD sprite.
    horizontal_right_length := f32(math.sqrt(f64(camera.right.x * camera.right.x + camera.right.z * camera.right.z)))
    if horizontal_right_length < .001 do horizontal_right_length = 1
    right_scale := width * .5 / horizontal_right_length
    right := third_person.Vec3{camera.right.x * right_scale, 0, camera.right.z * right_scale}
    if math.abs(yaw_bias) > .0001 {
        // Secondary crown layers can sit on a slightly different vertical
        // plane while remaining upright. This restrained yaw produces real
        // parallax instead of a stack of parallel camera-facing cutouts.
        yaw_cosine, yaw_sine := f32(math.cos(f64(yaw_bias))), f32(math.sin(f64(yaw_bias)))
        right = {right.x * yaw_cosine + right.z * yaw_sine, 0, -right.x * yaw_sine + right.z * yaw_cosine}
    }
    constrained_up := linalg.normalize0(
        third_person.Vec3{camera.up.x * .28, .72 + camera.up.y * .28, camera.up.z * .28},
    )
    up := third_person.Vec3 {
        constrained_up.x * height * .5,
        constrained_up.y * height * .5,
        constrained_up.z * height * .5,
    }
    if math.abs(roll) > .0001 {
        roll_cosine, roll_sine := f32(math.cos(f64(roll))), f32(math.sin(f64(roll)))
        unit_right := third_person.Vec3{right.x / (width * .5), right.y / (width * .5), right.z / (width * .5)}
        unit_up := third_person.Vec3{up.x / (height * .5), up.y / (height * .5), up.z / (height * .5)}
        right = {
            (unit_right.x * roll_cosine + unit_up.x * roll_sine) * width * .5,
            (unit_right.y * roll_cosine + unit_up.y * roll_sine) * width * .5,
            (unit_right.z * roll_cosine + unit_up.z * roll_sine) * width * .5,
        }
        up = {
            (-unit_right.x * roll_sine + unit_up.x * roll_cosine) * height * .5,
            (-unit_right.y * roll_sine + unit_up.y * roll_cosine) * height * .5,
            (-unit_right.z * roll_sine + unit_up.z * roll_cosine) * height * .5,
        }
    }
    anchored_center := third_person.Vec3 {
        center.x + right.x * (1 - anchor_x * 2) + up.x * (anchor_y * 2 - 1),
        center.y + right.y * (1 - anchor_x * 2) + up.y * (anchor_y * 2 - 1),
        center.z + right.z * (1 - anchor_x * 2) + up.z * (anchor_y * 2 - 1),
    }
    p0 := third_person.Vec3 {
        anchored_center.x - right.x - up.x,
        anchored_center.y - right.y - up.y,
        anchored_center.z - right.z - up.z,
    }
    p1 := third_person.Vec3 {
        anchored_center.x + right.x - up.x,
        anchored_center.y + right.y - up.y,
        anchored_center.z + right.z - up.z,
    }
    p2 := third_person.Vec3 {
        anchored_center.x + right.x + up.x,
        anchored_center.y + right.y + up.y,
        anchored_center.z + right.z + up.z,
    }
    p3 := third_person.Vec3 {
        anchored_center.x - right.x + up.x,
        anchored_center.y - right.y + up.y,
        anchored_center.z - right.z + up.z,
    }

    column, row := atlas_tile % 4, atlas_tile / 4
    inset := f32(2.0 / 1254.0)
    u0 := f32(column) * .25 + inset
    v0 := f32(row) * .25 + inset
    u1 := f32(column + 1) * .25 - inset
    v1 := f32(row + 1) * .25 - inset
    if mirror do u0, u1 = u1, u0
    anchor_u := u0 + (u1 - u0) * anchor_x
    anchor_v := v0 + (v1 - v0) * anchor_y
    // Alpha above one is an internal shader marker: use the native atlas
    // colors instead of treating this texture as a luminance tint mask.
    // Native cards use RGB as compact metadata: layer value, texture-space
    // anchor X, and texture-space anchor Y. This keeps shader wind weighting
    // synchronized with the single authoritative atlas anchor table above.
    // Alpha is an internal native-card marker rather than visible opacity.
    // Three marks bronze-flushed new growth; two marks established foliage.
    native_color := [4]f32{value, texture_anchor_x, anchor_y, young_growth ? f32(3) : f32(2)}
    positions: [3][3]third_person.Vec3
    positions[0] = {p3, linalg.lerp(p3, p2, anchor_x), p2}
    positions[1] = {linalg.lerp(p3, p0, anchor_y), center, linalg.lerp(p2, p1, anchor_y)}
    positions[2] = {p0, linalg.lerp(p0, p1, anchor_x), p1}
    card_u := [3]f32{u0, anchor_u, u1}
    card_v := [3]f32{v0, anchor_v, v1}
    for card_row in 0 ..< 2 {
        for card_column in 0 ..< 2 {
            top_left := positions[card_row][card_column]
            top_right := positions[card_row][card_column + 1]
            bottom_left := positions[card_row + 1][card_column]
            bottom_right := positions[card_row + 1][card_column + 1]
            left_u, right_u := card_u[card_column], card_u[card_column + 1]
            top_v, bottom_v := card_v[card_row], card_v[card_row + 1]
            append(
                &world_renderer.bougainvillea_vertices,
                Foliage_Vertex{{bottom_left.x, bottom_left.y, bottom_left.z}, {left_u, bottom_v}, native_color, 0},
                Foliage_Vertex{{bottom_right.x, bottom_right.y, bottom_right.z}, {right_u, bottom_v}, native_color, 0},
                Foliage_Vertex{{top_right.x, top_right.y, top_right.z}, {right_u, top_v}, native_color, 0},
                Foliage_Vertex{{bottom_left.x, bottom_left.y, bottom_left.z}, {left_u, bottom_v}, native_color, 0},
                Foliage_Vertex{{top_right.x, top_right.y, top_right.z}, {right_u, top_v}, native_color, 0},
                Foliage_Vertex{{top_left.x, top_left.y, top_left.z}, {left_u, top_v}, native_color, 0},
            )
        }
    }
}

world_window_flower_bunch_billboard :: proc(
    structure: terrain.Structure,
    local_x, root_y, local_z, window_width: f32,
    row, column: int,
) {
    seed := structure.seed ~ u32(row + 1) * 0x9e3779b9 ~ u32(column + 1) * 0x85ebca6b
    root_x, root_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_x,
        local_z,
        structure.rotation,
    )
    palette := architecture.bougainvillea_palette(seed)
    flower_tile := architecture.bougainvillea_flower_tile_base(palette)
    // Even atlas columns are upright, bottom-anchored clumps: a natural fit
    // for a window box where the stems must visibly emerge from the planter.
    variation := int((seed >> 8) & 1) * 2
    width := window_width + .32
    height := row == 0 ? f32(.58) : f32(.92)
    roll := (f32(int((seed >> 12) % 7)) - 3) * .025
    world_bougainvillea_card(
        {root_x, root_y, root_z},
        width,
        height,
        flower_tile + variation,
        seed & 1 != 0,
        roll,
        .96,
    )
}

world_grass_card :: proc(center: third_person.Vec3, width, height: f32, tile: int, color: rl.Color) {
    append(
        &world_renderer.grass_instances,
        Grass_Instance {
            center = {center.x, center.y, center.z},
            size = {width, height},
            tile = u32(((tile % 16) + 16) % 16),
            color = world_color(color),
        },
    )
}

world_wildflower_card :: proc(center: third_person.Vec3, width, height: f32, tile: int) {
    append(
        &world_renderer.wildflower_instances,
        Grass_Instance {
            center = {center.x, center.y, center.z},
            size   = {width, height},
            tile   = u32(((tile % 16) + 16) % 16),
            // Alpha above one marks a native-color wildflower atlas card.
            color  = {1, 1, 1, 2},
        },
    )
}

world_wildflower_lab :: proc() {
    // A self-contained meadow makes atlas, scale, density, and wind regressions
    // visible without inheriting any gameplay-world state.
    world_box({0, -.12, 0}, {32, .24, 24}, {62, 113, 72, 255})
    SPACING :: f32(.52)
    for grid_z in -20 ..= 20 {
        for grid_x in -26 ..= 26 {
            seed := grid_x * 73856093 + grid_z * 19349663
            x := f32(grid_x) * SPACING + (wind_streak_hash(seed, 1) - .5) * SPACING * .72
            z := f32(grid_z) * SPACING + (wind_streak_hash(seed, 2) - .5) * SPACING * .72
            distance := f32(math.sqrt(f64(x * x + z * z)))
            edge := clamp((11.5 - distance) / 2.5, 0, 1)
            if wind_streak_hash(seed, 3) > edge do continue
            height := .48 + wind_streak_hash(seed, 4) * .55
            grass_color := color_lerp(
                rl.Color{48, 113, 72, 255},
                rl.Color{91, 137, 69, 255},
                wind_streak_hash(seed, 5),
            )
            world_grass_card(
                {x, height * .5, z},
                height * (.58 + wind_streak_hash(seed, 6) * .34),
                height,
                abs(seed) % 16,
                grass_color,
            )
            flower_chance := .16 + .34 * clamp(1 - distance / 12, 0, 1)
            if wind_streak_hash(seed, 7) < flower_chance {
                flower_height := .34 + wind_streak_hash(seed, 8) * .34
                world_wildflower_card(
                    {x, flower_height * .5 + .12, z},
                    .22 + wind_streak_hash(seed, 9) * .18,
                    flower_height,
                    abs(seed / 11) % 16,
                )
            }
        }
    }
}

@(no_instrumentation)
world_foliage_vertex_color :: #force_inline proc(ring, variation: int) -> rl.Color {
    // Six broad Adriatic vegetation families: cypress, laurel, sunlit olive,
    // myrtle, silver olive, and warm Mediterranean scrub. Keeping each family
    // coherent from root pocket to crown gives the world postcard-scale color
    // regions without turning individual trees into multicolored noise.
    FOLIAGE_PALETTE_COUNT :: 6
    palette := ((variation % FOLIAGE_PALETTE_COUNT) + FOLIAGE_PALETTE_COUNT) % FOLIAGE_PALETTE_COUNT
    switch ring {
    case 0:
        colors := [6]rl.Color {
            {31, 65, 55, 255},
            {47, 76, 42, 255},
            {62, 76, 39, 255},
            {40, 70, 55, 255},
            {61, 75, 57, 255},
            {52, 74, 42, 255},
        }
        return colors[palette]
    case 1:
        // A deliberately cool, low-value shoulder remains visible in the
        // narrow gaps between overlapping lobes, acting as painted contact
        // shadow without another texture lookup or render pass.
        colors := [6]rl.Color {
            {43, 84, 68, 255},
            {62, 96, 48, 255},
            {81, 99, 48, 255},
            {52, 91, 69, 255},
            {78, 94, 69, 255},
            {70, 94, 49, 255},
        }
        return colors[palette]
    case 2:
        // Upper crown rings stay within one restrained body-color family.
        // Broad value grouping belongs to the continuous foliage shader;
        // large per-ring jumps expose the triangulated construction as bright
        // ribbons when a tree is viewed near eye level.
        colors := [6]rl.Color {
            {61, 111, 88, 255},
            {94, 130, 61, 255},
            {129, 145, 65, 255},
            {75, 119, 88, 255},
            {116, 128, 91, 255},
            {111, 132, 64, 255},
        }
        return colors[palette]
    case 3:
        colors := [6]rl.Color {
            {66, 119, 94, 255},
            {103, 140, 67, 255},
            {143, 158, 71, 255},
            {82, 128, 96, 255},
            {126, 138, 99, 255},
            {121, 143, 69, 255},
        }
        return colors[palette]
    case 4:
        colors := [6]rl.Color {
            {70, 124, 98, 255},
            {108, 145, 70, 255},
            {149, 164, 75, 255},
            {87, 133, 101, 255},
            {132, 143, 104, 255},
            {127, 148, 73, 255},
        }
        return colors[palette]
    case 5:
        colors := [6]rl.Color {
            {73, 128, 101, 255},
            {112, 149, 72, 255},
            {154, 169, 79, 255},
            {91, 137, 105, 255},
            {137, 148, 109, 255},
            {132, 153, 76, 255},
        }
        return colors[palette]
    case 6:
        colors := [6]rl.Color {
            {76, 132, 104, 255},
            {116, 152, 75, 255},
            {159, 173, 83, 255},
            {95, 141, 109, 255},
            {142, 153, 114, 255},
            {137, 158, 80, 255},
        }
        return colors[palette]
    }
    return {78, 112, 53, 255}
}

@(no_instrumentation)
world_foliage_clump_color :: #force_inline proc(ring, variation: int, clump: f32) -> rl.Color {
    // Extend the ring palette with a clump-aligned temperature and value shift.
    // Troughs between the rounded bunches sink into a cooler, lower-value
    // pocket -- soft painted ambient occlusion in the crevices -- while the
    // crests lift toward a warmer sunlit accent. Both are derived from the
    // ring's own body color so every species and palette family stays
    // harmonized, and the shift stays gentle so the grouped painted planes
    // never resolve into bright ribbons that expose the triangulation.
    base := world_foliage_vertex_color(ring, variation)
    if clump < 0 {
        // Deeper occlusion on the lower shoulders, where overlapping boughs
        // trap shade; the upper crown plane keeps only a faint recess.
        pocket_amount := clamp(-clump, 0, 1) * (.42 - f32(ring) * .035)
        pocket := rl.Color{u8(f32(base.r) * .70), u8(f32(base.g) * .81), u8(f32(base.b) * .90), base.a}
        return color_lerp(base, pocket, clamp(pocket_amount, 0, 1))
    }
    crest_amount := clamp(clump, 0, 1) * .22
    crest := rl.Color {
        u8(min(f32(base.r) * 1.15, 255.0)),
        u8(min(f32(base.g) * 1.08, 255.0)),
        u8(f32(base.b) * .93),
        base.a,
    }
    return color_lerp(base, crest, crest_amount)
}

world_foliage_trunk :: proc(x, z, base_y, height, radius: f32, seed: u32) {
    // Eight sides are enough to remove the conspicuous hexagonal shaft at
    // walking distance while keeping mature forests inexpensive.
    SEGMENTS :: 8
    TRUNK_RINGS :: 4
    base: [SEGMENTS]third_person.Vec3
    top: [SEGMENTS]third_person.Vec3
    rings: [TRUNK_RINGS][SEGMENTS]third_person.Vec3
    lean_angle := f32(seed % 628) * .01
    lean_x := math.cos(lean_angle) * height * .045
    lean_z := math.sin(lean_angle) * height * .045
    bend_angle := lean_angle + math.PI * .5 + f32(seed % 17) * .037
    bend_x, bend_z := math.cos(bend_angle), math.sin(bend_angle)
    ring_fraction := [TRUNK_RINGS]f32{0, .34, .69, 1}
    ring_radius := [TRUNK_RINGS]f32{1, .91, .78, .66}
    for ring in 0 ..< TRUNK_RINGS {
        fraction := ring_fraction[ring]
        curve := f32(math.sin(f64(fraction * math.PI)))
        center_x := x + lean_x * fraction + bend_x * height * .027 * curve
        center_z := z + lean_z * fraction + bend_z * height * .027 * curve
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / SEGMENTS + f32(ring) * .025
            rings[ring][segment] = {
                center_x + math.cos(angle) * radius * ring_radius[ring],
                base_y + height * fraction,
                center_z + math.sin(angle) * radius * ring_radius[ring],
            }
        }
    }
    for segment in 0 ..< SEGMENTS {
        base[segment] = rings[0][segment]
        top[segment] = rings[TRUNK_RINGS - 1][segment]
    }
    bark_light := [TRUNK_RINGS - 1]rl.Color{{91, 72, 52, 255}, {97, 76, 54, 255}, {103, 80, 55, 255}}
    bark_shadow := [TRUNK_RINGS - 1]rl.Color{{62, 55, 46, 255}, {66, 58, 47, 255}, {71, 61, 48, 255}}
    // Neighboring patches should not all expose the same orange-brown posts.
    // Three restrained bark families give the woodland warm oak, cool
    // gray-bark, and muted umber notes while keeping every trunk subordinate
    // to the canopy. Moss is applied afterward and ties the families together.
    bark_family := seed % 3
    if bark_family == 1 {
        bark_light = {{91, 79, 62, 255}, {98, 84, 64, 255}, {105, 89, 66, 255}}
        bark_shadow = {{62, 58, 50, 255}, {66, 61, 51, 255}, {71, 65, 53, 255}}
    } else if bark_family == 2 {
        bark_light = {{102, 69, 49, 255}, {109, 73, 51, 255}, {116, 78, 53, 255}}
        bark_shadow = {{68, 52, 43, 255}, {73, 55, 44, 255}, {78, 58, 45, 255}}
    }
    moss_light := [TRUNK_RINGS - 1]rl.Color{{91, 94, 53, 255}, {94, 96, 55, 255}, {96, 98, 57, 255}}
    moss_shadow := [TRUNK_RINGS - 1]rl.Color{{59, 67, 45, 255}, {62, 69, 46, 255}, {65, 71, 47, 255}}
    for ring in 0 ..< TRUNK_RINGS - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            // Let bark value travel continuously around the trunk instead of
            // assigning every third face a dark stripe. A seed phase keeps
            // neighboring trunks from repeating the identical highlight.
            face_angle := (f32(segment) + .5) * math.PI * 2 / SEGMENTS + f32(seed % 37) * .017
            bark_rhythm := f32(math.sin(f64(f32(segment) * 1.73 + f32(ring) * 2.11 + f32(seed % 29) * .19))) * .045
            face_light := clamp(.18 + (.5 + .5 * math.cos(face_angle - .72)) * .72 + bark_rhythm, .12, .94)
            lower_color := color_lerp(bark_shadow[ring], bark_light[ring], face_light)
            upper_index := min(ring + 1, TRUNK_RINGS - 2)
            upper_color := color_lerp(bark_shadow[upper_index], bark_light[upper_index], face_light)
            // Moss shares one broad, cool-facing side across the woodland,
            // with a small per-tree drift. Blending it into the existing
            // vertices keeps the shaft inexpensive and avoids pasted stripes.
            moss_angle := math.PI * 1.38 + f32(seed % 13) * .018
            moss_facing := .5 + .5 * math.cos(face_angle - moss_angle)
            moss_amount := clamp((moss_facing - .38) * .48, 0, .28) * (1 - f32(ring) * .19)
            lower_moss := color_lerp(moss_shadow[ring], moss_light[ring], face_light)
            upper_moss := color_lerp(moss_shadow[upper_index], moss_light[upper_index], face_light)
            lower_color = color_lerp(lower_color, lower_moss, moss_amount)
            upper_color = color_lerp(upper_color, upper_moss, moss_amount * .82)
            world_quad_colored(
                rings[ring][segment],
                rings[ring + 1][segment],
                rings[ring + 1][next],
                rings[ring][next],
                lower_color,
                upper_color,
                upper_color,
                lower_color,
            )
        }
    }

    // Sparse vertical brush strips keep the broad front faces from reading as
    // untextured orange posts. They sit just above the lower shaft and rotate
    // per tree; one dark bark split and one shorter moss stroke are enough to
    // imply surface rhythm without introducing another material or texture.
    for stroke in 0 ..< 2 {
        stroke_angle := f32(seed % 211) * .029 + f32(stroke) * 2.17
        outward_x, outward_z := math.cos(stroke_angle), math.sin(stroke_angle)
        tangent_x, tangent_z := -outward_z, outward_x
        stroke_width := radius * (stroke == 0 ? f32(.20) : f32(.27))
        stroke_bottom := base_y + height * (stroke == 0 ? f32(.12) : f32(.07))
        stroke_top := base_y + height * (stroke == 0 ? f32(.43) : f32(.28))
        lower_outset := radius * 1.018
        upper_radius :=
            radius *
            (ring_radius[1] +
                    (ring_radius[2] - ring_radius[1]) *
                        clamp(
                            ((stroke_top - base_y) / height - ring_fraction[1]) /
                            (ring_fraction[2] - ring_fraction[1]),
                            0,
                            1,
                        ))
        upper_outset := upper_radius * 1.018
        stroke_color := rl.Color{52, 49, 42, 220}
        if stroke == 1 do stroke_color = {64, 76, 49, 205}
        world_quad(
            {
                x + outward_x * lower_outset - tangent_x * stroke_width,
                stroke_bottom,
                z + outward_z * lower_outset - tangent_z * stroke_width,
            },
            {
                x +
                lean_x * (stroke_top - base_y) / height +
                outward_x * upper_outset -
                tangent_x * stroke_width * .68,
                stroke_top - height * .012,
                z +
                lean_z * (stroke_top - base_y) / height +
                outward_z * upper_outset -
                tangent_z * stroke_width * .68,
            },
            {
                x +
                lean_x * (stroke_top - base_y) / height +
                outward_x * upper_outset +
                tangent_x * stroke_width * .68,
                stroke_top,
                z +
                lean_z * (stroke_top - base_y) / height +
                outward_z * upper_outset +
                tangent_z * stroke_width * .68,
            },
            {
                x + outward_x * lower_outset + tangent_x * stroke_width,
                stroke_bottom + height * .018,
                z + outward_z * lower_outset + tangent_z * stroke_width,
            },
            stroke_color,
        )
    }

    // Three low buttress roots anchor the stylized trunk to the terrain.
    // Their uneven reach avoids a decorative star, and the wedges disappear
    // naturally beneath understory when viewed from above.
    ROOTS :: 3
    for root in 0 ..< ROOTS {
        angle :=
            lean_angle +
            f32(root) * math.PI * 2 / ROOTS +
            f32(math.sin(f64(f32(seed) * .023 + f32(root) * 1.71))) * .29
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        root_reach := radius * (2.35 + f32(root % 2) * .62)
        root_half_width := radius * (.54 + f32((root + 1) % 2) * .12)
        shoulder := third_person.Vec3 {
            x + direction_x * radius * .72,
            base_y + radius * (1.75 + f32(root) * .16),
            z + direction_z * radius * .72,
        }
        left := third_person.Vec3 {
            x + direction_x * radius - side_x * root_half_width,
            base_y + .035,
            z + direction_z * radius - side_z * root_half_width,
        }
        right := third_person.Vec3 {
            x + direction_x * radius + side_x * root_half_width,
            base_y + .035,
            z + direction_z * radius + side_z * root_half_width,
        }
        tip := third_person.Vec3{x + direction_x * root_reach, base_y + .025, z + direction_z * root_reach}
        root_light := rl.Color{91, 71, 52, 255}
        root_shadow := rl.Color{62, 54, 46, 255}
        if bark_family == 1 {
            root_light = {87, 76, 61, 255}
            root_shadow = {59, 57, 51, 255}
        } else if bark_family == 2 {
            root_light = {96, 66, 50, 255}
            root_shadow = {65, 50, 43, 255}
        }
        if root % 2 == 1 {
            root_light = color_lerp(root_light, {67, 63, 52, 255}, .34)
            root_shadow = color_lerp(root_shadow, {49, 50, 45, 255}, .22)
        }
        world_triangle_colored(left, tip, shoulder, root_shadow, root_shadow, root_light)
        world_triangle_colored(tip, right, shoulder, root_shadow, root_light, root_light)
    }

    crown := third_person.Vec3{x + lean_x, base_y + height, z + lean_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(top[segment], crown, top[next], {65, 54, 39, 255})
    }

    // A few broad forked limbs turn the supporting pole into a tree. They
    // disappear into the crown from above but become an important readable
    // layer at walking height and across glade openings.
    LIMBS :: 3
    for limb in 0 ..< LIMBS {
        angle :=
            lean_angle +
            f32(limb) * math.PI * 2 / LIMBS +
            f32(math.sin(f64(f32(seed) * .017 + f32(limb) * 1.91))) * .34
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        start_height := height * (.54 + f32(limb) * .055)
        start_fraction := start_height / height
        start_curve := f32(math.sin(f64(start_fraction * math.PI)))
        reach := radius * (2.75 + f32(limb % 2) * .58)
        start := third_person.Vec3 {
            x + lean_x * start_fraction + bend_x * height * .027 * start_curve,
            base_y + start_height,
            z + lean_z * start_fraction + bend_z * height * .027 * start_curve,
        }
        finish := third_person.Vec3 {
            x + lean_x * .92 + direction_x * reach,
            base_y + height * (.76 + f32(limb) * .035),
            z + lean_z * .92 + direction_z * reach,
        }
        start_half_width := radius * .58
        finish_half_width := radius * .28
        limb_color := rl.Color{80, 64, 49, 255}
        if bark_family == 1 do limb_color = {76, 69, 57, 255}
        if bark_family == 2 do limb_color = {88, 60, 46, 255}
        if limb % 2 == 1 {
            limb_color = color_lerp(limb_color, {55, 53, 47, 255}, .42)
        }
        world_quad(
            {start.x - side_x * start_half_width, start.y, start.z - side_z * start_half_width},
            {start.x + side_x * start_half_width, start.y, start.z + side_z * start_half_width},
            {finish.x + side_x * finish_half_width, finish.y, finish.z + side_z * finish_half_width},
            {finish.x - side_x * finish_half_width, finish.y, finish.z - side_z * finish_half_width},
            limb_color,
        )
    }
}

world_foliage_understory_tuft :: proc(x, z, base_y, width, height: f32, seed: u32) {
    FRONDS :: 6
    camera_position := world_renderer.editor.camera_pose.position
    camera_delta_x := camera_position.x - x
    camera_delta_z := camera_position.z - z
    leaflet_distance := f32(math.sqrt(f64(camera_delta_x * camera_delta_x + camera_delta_z * camera_delta_z)))
    // Leaflet tiers are a walking-distance silhouette feature. Beyond this
    // range they occupy sub-pixel space and would only consume world-mesh
    // capacity needed by the dense forest canopy.
    emit_leaflets := leaflet_distance < 220
    emit_lush_leaflets := leaflet_distance < 140
    for frond in 0 ..< FRONDS {
        angle := f32(frond) * math.PI * 2 / FRONDS + f32(seed % 113) * .037
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        spread := width * (.24 + f32(frond % 2) * .055)
        if emit_lush_leaflets {
            // At walking distance the central triangle is only a narrow stem;
            // the tiered leaflets, not a giant spearhead, carry the fern.
            spread = width * (.065 + f32(frond % 2) * .018)
        }
        lean := width * (.18 + f32((frond + 1) % 3) * .045)
        blade_height := height * (.72 + f32(math.sin(f64(f32(seed) * .011 + f32(frond) * 1.83))) * .18)
        left := third_person.Vec3{x - side_x * spread, base_y + .08, z - side_z * spread}
        right := third_person.Vec3{x + side_x * spread, base_y + .08, z + side_z * spread}
        tip := third_person.Vec3{x + direction_x * lean, base_y + blade_height, z + direction_z * lean}
        color := rl.Color{46, 91, 60, 255}
        if frond % 3 == 1 do color = {58, 108, 64, 255}
        if frond % 3 == 2 do color = {39, 80, 59, 255}
        tip_color := color
        tip_color.r = u8(min(int(tip_color.r) + 12, 255))
        tip_color.g = u8(min(int(tip_color.g) + 16, 255))
        tip_color.b = u8(min(int(tip_color.b) + 5, 255))
        // Ground vertices carry a downward normal so the canopy wind weight is
        // zero; the upright tip carries the full weight. The same triangle
        // therefore bends like a rooted fern instead of sliding as one rigid
        // piece across the forest floor.
        base_normal := third_person.Vec3{0, -1, 0}
        tip_normal := linalg.normalize0(third_person.Vec3{direction_x * .34, .94, direction_z * .34})
        world_triangle_foliage(left, tip, right, color, tip_color, color, base_normal, tip_normal, base_normal)

        // Walking-distance ferns carry three tapered leaflet tiers on every
        // frond. The middle LOD keeps one tier on alternating fronds, and the
        // distant LOD retains only the broad blade. This turns nearby cones
        // into layered woodland silhouettes without multiplying the stress
        // scene's sub-pixel geometry.
        tier_count := 0
        if emit_lush_leaflets {
            tier_count = 3
        } else if emit_leaflets && frond % 2 == 0 {
            tier_count = 1
        }
        lush_fractions := [3]f32{.29, .49, .68}
        lush_reaches := [3]f32{.32, .27, .20}
        for tier in 0 ..< tier_count {
            leaflet_fraction := f32(.56)
            if emit_lush_leaflets {
                leaflet_fraction = lush_fractions[tier]
            }
            stem_half_span := emit_lush_leaflets ? f32(.075) : f32(.08)
            stem_back_fraction := leaflet_fraction - stem_half_span
            stem_front_fraction := leaflet_fraction + stem_half_span
            stem_back := third_person.Vec3 {
                x + direction_x * lean * stem_back_fraction,
                base_y + blade_height * stem_back_fraction,
                z + direction_z * lean * stem_back_fraction,
            }
            stem_front := third_person.Vec3 {
                x + direction_x * lean * stem_front_fraction,
                base_y + blade_height * stem_front_fraction,
                z + direction_z * lean * stem_front_fraction,
            }
            leaflet_center_x := x + direction_x * lean * leaflet_fraction
            leaflet_center_z := z + direction_z * lean * leaflet_fraction
            leaflet_reach := width * (.23 + f32(frond % 2) * .035)
            if emit_lush_leaflets {
                leaflet_reach = width * lush_reaches[tier]
            }
            leaflet_lift := height * (.030 + f32((frond + tier + 1) % 2) * .012)
            left_leaflet := third_person.Vec3 {
                leaflet_center_x - side_x * leaflet_reach,
                base_y + blade_height * leaflet_fraction + leaflet_lift,
                leaflet_center_z - side_z * leaflet_reach,
            }
            right_leaflet := third_person.Vec3 {
                leaflet_center_x + side_x * leaflet_reach,
                base_y + blade_height * leaflet_fraction + leaflet_lift,
                leaflet_center_z + side_z * leaflet_reach,
            }
            leaflet_color := tip_color
            if tier == 0 {
                leaflet_color.r = u8(max(int(leaflet_color.r) - 6, 0))
                leaflet_color.g = u8(max(int(leaflet_color.g) - 7, 0))
            }
            stem_normal := linalg.normalize0(third_person.Vec3{direction_x * .18, .44, direction_z * .18})
            leaflet_normal := linalg.normalize0(third_person.Vec3{direction_x * .24, .68, direction_z * .24})
            world_triangle_foliage(
                stem_back,
                left_leaflet,
                stem_front,
                color,
                leaflet_color,
                leaflet_color,
                stem_normal,
                leaflet_normal,
                leaflet_normal,
            )
            world_triangle_foliage(
                stem_front,
                right_leaflet,
                stem_back,
                leaflet_color,
                leaflet_color,
                color,
                leaflet_normal,
                leaflet_normal,
                stem_normal,
            )
        }
    }
}

world_foliage_ground_rosette :: proc(x, z, base_y, width, height: f32, seed: u32) {
    camera_position := world_renderer.editor.camera_pose.position
    camera_delta_x := camera_position.x - x
    camera_delta_z := camera_position.z - z
    camera_distance := f32(math.sqrt(f64(camera_delta_x * camera_delta_x + camera_delta_z * camera_delta_z)))
    leaf_count := 4
    if camera_distance < 180 do leaf_count = 7
    for leaf in 0 ..< leaf_count {
        angle := f32(leaf) * math.PI * 2 / f32(leaf_count) + f32(seed % 137) * .031
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        reach := width * (.34 + f32(math.sin(f64(f32(seed) * .013 + f32(leaf) * 1.79))) * .08)
        lift := height * (.56 + f32(math.sin(f64(f32(seed) * .019 + f32(leaf) * 2.17))) * .18)
        half_width := width * (.105 + f32(leaf % 2) * .018)
        root := third_person.Vec3{x, base_y + .07, z}
        left := third_person.Vec3 {
            x + direction_x * reach * .50 - side_x * half_width,
            base_y + lift * .72,
            z + direction_z * reach * .50 - side_z * half_width,
        }
        right := third_person.Vec3 {
            x + direction_x * reach * .50 + side_x * half_width,
            base_y + lift * .72,
            z + direction_z * reach * .50 + side_z * half_width,
        }
        tip := third_person.Vec3{x + direction_x * reach, base_y + lift * .38, z + direction_z * reach}
        root_color := rl.Color{38, 77, 53, 255}
        leaf_color := rl.Color{61, 111, 66, 255}
        tip_color := rl.Color{70, 118, 68, 255}
        if leaf % 3 == 1 {
            root_color = {43, 81, 48, 255}
            leaf_color = {72, 119, 62, 255}
            tip_color = {82, 128, 66, 255}
        } else if leaf % 3 == 2 {
            root_color = {35, 72, 56, 255}
            leaf_color = {53, 101, 71, 255}
            tip_color = {63, 111, 74, 255}
        }
        root_normal := third_person.Vec3{0, -1, 0}
        leaf_normal := linalg.normalize0(third_person.Vec3{direction_x * .32, .88, direction_z * .32})
        tip_normal := linalg.normalize0(third_person.Vec3{direction_x * .46, .76, direction_z * .46})
        world_triangle_foliage(
            root,
            left,
            tip,
            root_color,
            leaf_color,
            tip_color,
            root_normal,
            leaf_normal,
            tip_normal,
        )
        world_triangle_foliage(
            root,
            tip,
            right,
            root_color,
            tip_color,
            leaf_color,
            root_normal,
            tip_normal,
            leaf_normal,
        )
    }
}

world_foliage_ground_dapple :: proc(x, z, base_y, width, depth, rotation: f32, seed: u32) {
    SEGMENTS :: 7
    // Painted woodland floors need readable pools of bounced canopy light.
    // Keep the irregular edge fully transparent, but lift the center enough
    // to separate fern and trunk silhouettes from one uniform green plane.
    center_color := rl.Color{184, 166, 86, 101}
    if seed % 3 == 1 do center_color = {143, 154, 83, 92}
    if seed % 3 == 2 do center_color = {197, 172, 91, 98}
    edge_color := center_color
    edge_color.a = 0
    center := third_person.Vec3{x, base_y + .115, z}
    points: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := rotation + f32(segment) * math.PI * 2 / SEGMENTS
        irregularity := .82 + f32(math.sin(f64(f32(seed) * .019 + f32(segment) * 2.37))) * .18
        points[segment] = {
            x + math.cos(angle) * width * .5 * irregularity,
            base_y + .11,
            z + math.sin(angle) * depth * .5 * irregularity,
        }
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle_colored(points[segment], points[next], center, edge_color, edge_color, center_color)
    }
}

world_foliage_lobe :: proc(
    structure: terrain.Structure,
    local_center_x, local_center_z, width, depth, height: f32,
    base_lift: f32,
    is_hedge: bool,
    variation: int,
    outline_angle: f32,
    emit_outline: bool,
    lod: Structure_LOD = .Near,
) {
    // Smooth normals cannot repair a faceted outer contour. Eighteen sides
    // keep the long crown ridge and hanging skirt from resolving into obvious
    // straight runs at eye level. The deterministic radius and height rhythm
    // still does the silhouette design; the extra sides only let that rhythm
    // describe a soft painted edge.
    // Nearby crowns receive a finer silhouette while distant forest masses
    // retain the cheaper contour. This spends vertices where scallops occupy
    // multiple pixels instead of increasing every canopy in overview scenes.
    MAX_SEGMENTS :: 30
    segment_count := lod == .Near ? 30 : lod == .Medium ? 18 : 8
    lobe_world_x, lobe_world_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_center_x,
        local_center_z,
        structure.rotation,
    )
    PROFILE_RINGS :: 7
    MAX_RINGS :: 10
    ring_count := lod == .Near ? MAX_RINGS : lod == .Medium ? PROFILE_RINGS : 4
    if is_hedge {
        // Hedgerows can span an entire property edge. Keep their continuous
        // silhouette cheap: the overlapping crown beats hide the coarser
        // radial profile, so tree-quality tessellation buys little on screen.
        segment_count = lod == .Near ? 14 : lod == .Medium ? 10 : 8
        ring_count = lod == .Near ? 6 : lod == .Medium ? 5 : 4
    }
    is_forest_lobe := !is_hedge && max(structure.width, structure.depth) >= 105 && structure.height >= 58
    if is_forest_lobe && lod == .Far {
        // Dense stands contain dozens of tree-scale crowns. Eight sides and
        // four sampled profile rings are enough once those crowns merge into
        // a distant forest silhouette, while keeping the aggregate affordable.
        segment_count = 8
        ring_count = 4
    }
    // Near crowns keep the full medium and fine clump breakup; distant masses
    // shed it so their silhouette stays a calm, inexpensive composition of the
    // bold dominant bunches. The fade is continuous, so a crown morphs its
    // surface detail smoothly rather than popping at an LOD band boundary.
    clump_detail_fade := lod == .Near ? f32(1) : lod == .Medium ? f32(.45) : f32(0)
    // Canopy lobes are broad layered shelves, not inflated spheres. The
    // widest contour sits low, the upper shoulder stays full, and the shallow
    // cap produces a painted crown plane instead of a pointed balloon.
    ring_height := [PROFILE_RINGS]f32{.06, .15, .28, .43, .58, .71, .81}
    ring_radius := [PROFILE_RINGS]f32{.70, .86, .98, 1.0, .92, .69, .44}
    profile_width, profile_depth, profile_height := width, depth, height
    irregularity_strength := f32(.14)
    crown_base := f32(.90)
    species := int(structure.seed % 3)
    switch species {
    case 1:
        // Oak-like: a low, broad, rugged shelf with a full upper shoulder.
        ring_height = {.05, .14, .26, .39, .52, .64, .75}
        ring_radius = {.74, .88, .98, 1.0, .94, .74, .54}
        profile_width *= 1.09
        profile_depth *= 1.05
        profile_height *= .90
        irregularity_strength = .20
        crown_base = .85
    case 2:
        // Laurel-like: tighter upright bunches with a steeper shoulder and
        // smaller crown plane, useful as vertical accents in a mixed forest.
        ring_height = {.07, .18, .32, .47, .63, .77, .86}
        ring_radius = {.62, .82, .97, 1.0, .79, .52, .30}
        profile_width *= .84
        profile_depth *= .87
        profile_height *= 1.12
        irregularity_strength = .105
        crown_base = .96
    case:
    // Rounded broadleaf is the balanced default.
    }
    if base_lift > 0 {
        // Forest crowns join into broad, overlapping bough shelves. Keeping
        // their widest contour high and flattening the crown prevents a grove
        // from becoming a collection of upright gumdrops, while the stronger
        // irregularity preserves distinct hand-painted crown gestures.
        ring_height = {.04, .11, .21, .33, .46, .58, .69}
        ring_radius = {.78, .90, .98, 1.0, .94, .78, .58}
        profile_width *= 1.17
        profile_depth *= 1.10
        profile_height *= .79
        irregularity_strength = max(irregularity_strength, f32(.18))
        crown_base = .80
        switch species {
        case 1:
            // Mature oak shelves stay especially broad and low, with a full
            // shoulder and a gently recessed crown plane.
            ring_height = {.03, .09, .17, .28, .40, .52, .64}
            ring_radius = {.82, .93, .99, 1.0, .95, .79, .57}
            crown_base = .75
        case 2:
            // Laurel-like forest crowns keep a narrower, rising outer gesture
            // so mixed woods do not collapse into one repeated flat cushion.
            ring_height = {.05, .14, .25, .39, .54, .68, .79}
            ring_radius = {.70, .87, .98, 1.0, .87, .64, .40}
            crown_base = .89
        case:
        // Balanced broadleaf keeps the shared forest shelf.
        }
    } else if is_hedge {
        // A maintained hedge is one shallow rolling volume rather than a row
        // of miniature trees. Preserve soft crown undulation while keeping
        // the shoulders broad enough for neighboring lobes to disappear into.
        ring_height = {.04, .10, .19, .31, .43, .55, .66}
        ring_radius = {.80, .91, .98, 1.0, .94, .79, .58}
        profile_width *= 1.08
        profile_depth *= 1.04
        profile_height *= .78
        irregularity_strength = max(irregularity_strength, f32(.15))
        crown_base = .76
    }
    // The seven authored profile points remain the shape authority. Nearby
    // crowns interpolate two additional contours from that same curve instead
    // of changing species proportions or procedural phases with LOD.
    sampled_ring_height: [MAX_RINGS]f32
    sampled_ring_radius: [MAX_RINGS]f32
    for ring in 0 ..< ring_count {
        profile_position := f32(ring) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1))
        lower := clamp(int(profile_position), 0, PROFILE_RINGS - 1)
        upper := min(lower + 1, PROFILE_RINGS - 1)
        fraction := profile_position - f32(lower)
        sampled_ring_height[ring] = ring_height[lower] + (ring_height[upper] - ring_height[lower]) * fraction
        sampled_ring_radius[ring] = ring_radius[lower] + (ring_radius[upper] - ring_radius[lower]) * fraction
    }
    vertices: [MAX_RINGS][MAX_SEGMENTS]third_person.Vec3
    normals: [MAX_RINGS][MAX_SEGMENTS]third_person.Vec3
    // The signed clump field, sampled once per contour vertex, drives both the
    // rounded three-dimensional bulges and the crevice ambient occlusion baked
    // into the vertex colors, so the painted shade tracks the real mesh volume.
    clump_field: [MAX_RINGS][MAX_SEGMENTS]f32
    // One authored mass keeps a coherent species hue. Earlier per-lobe palette
    // cycling made close trees read as a patchwork of unrelated teal, olive,
    // and yellow polygons; lighting and brush marks already provide the
    // necessary internal variation.
    color_variation := int(structure.seed % 6)
    if is_hedge {
        // Clipped hedges alternate between deep cypress/myrtle and laurel.
        // They remain saturated enough to frame pale roads and stucco, while
        // avoiding the silver and hot olive families used by open scrub.
        hedge_palettes := [3]int{0, 3, 1}
        color_variation = hedge_palettes[int(structure.seed % 3)]
    }
    if base_lift > 0 {
        // Mature woods need broad color regions, not a checkerboard of random
        // lime and teal crowns. A slow world-space field lets neighboring
        // authored patches share a palette family while still drifting from
        // cool recesses through green into warm olive crowns. The hottest
        // yellow-green family remains available to standalone flowering
        // bushes; across a mature canopy it overexposes broad eye-level faces
        // and makes the underlying mesh transitions unnecessarily visible.
        palette_field :=
            f32(math.sin(f64(structure.center_x * .0092 + structure.center_z * .0049))) +
            f32(math.sin(f64(structure.center_x * -.0037 + structure.center_z * .0081 + 1.7))) * .62
        if palette_field < -.76 {
            color_variation = 0
        } else if palette_field < -.24 {
            color_variation = 3
        } else if palette_field < .28 {
            color_variation = 4
        } else if palette_field < .78 {
            color_variation = 1
        } else {
            color_variation = 2
        }
    }

    for ring in 0 ..< ring_count {
        profile_ring := f32(ring) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1))
        for segment in 0 ..< segment_count {
            // Slightly twist each contour so the facets do not stack into
            // continuous vertical seams. A deterministic phase keeps adjacent
            // lobes from sharing the same outline.
            contour_angle := f32(segment) * math.PI * 2 / f32(segment_count)
            angle :=
                contour_angle +
                profile_ring * .075 +
                f32(math.sin(f64(f32(variation) * 1.37 + profile_ring * 2.11))) * .045
            // Three correlated octaves compose the crown as bold, rounded
            // cumulus clumps with a clear big/medium/small nesting -- the
            // Ghibli canopy read -- rather than one uniform scallop frequency.
            // The dominant octave carves a few large bunches; the medium and
            // fine octaves only break their edges, and both quieter octaves
            // fade with distance so far masses stay calm while near crowns gain
            // hand-painted volume without changing topology or vertex cost.
            clump_dominant := f32(
                math.sin(
                    f64(f32(structure.seed) * .008 + f32(variation) * 1.63 + contour_angle * 1.8 + profile_ring * .42),
                ),
            )
            clump_medium := f32(
                math.sin(
                    f64(f32(structure.seed) * .013 + f32(variation) * 2.11 + contour_angle * 3.9 - profile_ring * .63),
                ),
            )
            clump_fine := f32(
                math.sin(
                    f64(f32(structure.seed) * .021 + f32(variation) * 2.67 + contour_angle * 7.1 + profile_ring * .94),
                ),
            )
            clump :=
                clump_dominant * .60 +
                clump_medium * .28 * (.5 + .5 * clump_detail_fade) +
                clump_fine * .14 * clump_detail_fade
            clump_field[ring][segment] = clump
            irregularity := 1 + clump * irregularity_strength
            local_x := local_center_x + math.cos(angle) * profile_width * .5 * sampled_ring_radius[ring] * irregularity
            local_z := local_center_z + math.sin(angle) * profile_depth * .5 * sampled_ring_radius[ring] * irregularity
            world_x, world_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            contour_lift :=
                f32(math.sin(f64(f32(structure.seed) * .007 + f32(variation) * 1.43 + contour_angle * 4.899))) *
                profile_height *
                (ring == 0 ? f32(.008) : f32(.026))
            // Bulge crests dome outward and upward while troughs carve soft
            // crevices, turning the wavy outline into rounded three-dimensional
            // bunches. The dome weight peaks on the mid and upper shoulder and
            // vanishes at the skirt so the hanging underside stays a clean
            // shelf rather than a rippled ceiling.
            dome_weight := sampled_ring_height[ring] * (1 - sampled_ring_height[ring]) * 4
            contour_lift += clump * profile_height * dome_weight * .055
            if base_lift > 0 && ring == 0 {
                // The lowest forest contour carries uneven hanging bough
                // pockets. A broad rhythm chooses the limbs while a smaller
                // ripple keeps their tips leafy, breaking the tabletop
                // underside without adding cards hidden inside the mesh.
                broad_droop := f32(
                    math.sin(f64(f32(structure.seed) * .017 + f32(variation) * 1.23 + contour_angle * 3.841)),
                )
                tip_droop := f32(
                    math.sin(f64(f32(structure.seed) * .029 + f32(variation) * 2.07 + contour_angle * 7.369 + .8)),
                )
                droop_wave := clamp(.5 + broad_droop * .34 + tip_droop * .16, 0, 1)
                contour_lift -= profile_height * (.010 + droop_wave * .068)
            }
            vertices[ring][segment] = {
                world_x,
                structure.base_y + base_lift + profile_height * sampled_ring_height[ring] + contour_lift,
                world_z,
            }
            local_normal_x := math.cos(angle) * profile_height / max(profile_width, f32(.01))
            local_normal_y := (sampled_ring_height[ring] - .30) * 1.68
            local_normal_z := math.sin(angle) * profile_height / max(profile_depth, f32(.01))
            if base_lift > 0 {
                // Nearby forest lobes should share the lighting flow of their
                // parent crown. Blend each small ellipsoid normal toward a
                // broad formation normal so overlaps read as leafy bunches,
                // not colliding independently lit balls.
                mass_normal_x := local_x * structure.height * 2 / max(structure.width * structure.width, f32(.01))
                mass_normal_z := local_z * structure.height * 2 / max(structure.depth * structure.depth, f32(.01))
                local_normal_x += (mass_normal_x - local_normal_x) * .46
                local_normal_z += (mass_normal_z - local_normal_z) * .46
            }
            cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
            normals[ring][segment] = linalg.normalize0(
                third_person.Vec3 {
                    local_normal_x * cosine - local_normal_z * sine,
                    local_normal_y,
                    local_normal_x * sine + local_normal_z * cosine,
                },
            )
        }
    }

    base_x, base_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_center_x,
        local_center_z,
        structure.rotation,
    )
    base_fraction := f32(.065)
    if base_lift > 0 {
        // Lift the middle of an elevated crown's underside into a shallow
        // bowl. A flat center at the perimeter height created broad black
        // shelves when trees were viewed from below; this curved closure
        // keeps the deep pocket while allowing a soft value roll toward it.
        base_fraction = .115
    }
    base := third_person.Vec3{base_x, structure.base_y + base_lift + profile_height * base_fraction, base_z}
    for segment in 0 ..< segment_count {
        next := (segment + 1) % segment_count
        if base_lift > 0 {
            world_triangle_foliage(
                vertices[0][next],
                base,
                vertices[0][segment],
                world_foliage_clump_color(0, color_variation, clump_field[0][next]),
                {39, 66, 48, 255},
                world_foliage_clump_color(0, color_variation, clump_field[0][segment]),
                normals[0][next],
                {0, -1, 0},
                normals[0][segment],
            )
        } else {
            world_triangle(vertices[0][next], base, vertices[0][segment], {34, 61, 45, 255})
        }
    }

    for ring in 0 ..< ring_count - 1 {
        lower_palette_ring := clamp(
            int(f32(ring) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1)) + .5),
            0,
            PROFILE_RINGS - 1,
        )
        upper_palette_ring := clamp(
            int(f32(ring + 1) * f32(PROFILE_RINGS - 1) / f32(max(ring_count - 1, 1)) + .5),
            0,
            PROFILE_RINGS - 1,
        )
        for segment in 0 ..< segment_count {
            next := (segment + 1) % segment_count
            // Paint soft ambient occlusion into the troughs between clumps and
            // a restrained warm lift onto their crests, per contour vertex, so
            // the grouped shade is anchored to the real mesh bulges instead of
            // a detached noise field. This is the crevice read that gives the
            // near canopy its rounded, hand-painted volume.
            lower_here := world_foliage_clump_color(lower_palette_ring, color_variation, clump_field[ring][segment])
            lower_next := world_foliage_clump_color(lower_palette_ring, color_variation, clump_field[ring][next])
            upper_here := world_foliage_clump_color(
                upper_palette_ring,
                color_variation,
                clump_field[ring + 1][segment],
            )
            upper_next := world_foliage_clump_color(upper_palette_ring, color_variation, clump_field[ring + 1][next])
            world_triangle_foliage(
                vertices[ring][segment],
                vertices[ring + 1][segment],
                vertices[ring + 1][next],
                lower_here,
                upper_here,
                upper_next,
                normals[ring][segment],
                normals[ring + 1][segment],
                normals[ring + 1][next],
            )
            world_triangle_foliage(
                vertices[ring][segment],
                vertices[ring + 1][next],
                vertices[ring][next],
                lower_here,
                upper_next,
                lower_next,
                normals[ring][segment],
                normals[ring + 1][next],
                normals[ring][next],
            )
        }
    }

    crown_x, crown_z := world_rotate_xz(
        structure.center_x,
        structure.center_z,
        local_center_x + profile_width * f32(math.sin(f64(f32(variation) * 2.3))) * .035,
        local_center_z + profile_depth * f32(math.cos(f64(f32(variation) * 1.7))) * .035,
        structure.rotation,
    )
    crown_fraction := crown_base + f32(math.sin(f64(f32(structure.seed) * .005 + f32(variation) * 1.61))) * .035
    crown := third_person.Vec3{crown_x, structure.base_y + base_lift + profile_height * crown_fraction, crown_z}
    for segment in 0 ..< segment_count {
        next := (segment + 1) % segment_count
        world_triangle_foliage(
            vertices[ring_count - 1][segment],
            crown,
            vertices[ring_count - 1][next],
            world_foliage_clump_color(PROFILE_RINGS - 1, color_variation, clump_field[ring_count - 1][segment]),
            world_foliage_vertex_color(PROFILE_RINGS - 1, color_variation),
            world_foliage_clump_color(PROFILE_RINGS - 1, color_variation, clump_field[ring_count - 1][next]),
            normals[ring_count - 1][segment],
            {0, 1, 0},
            normals[ring_count - 1][next],
        )
    }

    // The atlas is primarily a silhouette accent. Perimeter boughs carry the
    // large sprays; clipped hedges also receive a few much smaller translucent
    // face clusters below so their long front plane does not stay textureless.
    if emit_outline && lod != .Far {
        local_x := local_center_x + math.cos(outline_angle) * profile_width * .64
        local_z := local_center_z + math.sin(outline_angle) * profile_depth * .64
        card_x, card_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        focal_length := f32(1.35)
        if world_renderer.editor.in_map && driving_aircraft(world_renderer.editor) {
            focal_length = world_renderer.editor.flight_camera.focal_length
        }
        camera := perspective_camera(world_renderer.editor.camera_pose, focal_length)
        to_camera_x := camera.position.x - card_x
        to_camera_z := camera.position.z - card_z
        to_camera_length := max(f32(.001), f32(math.sqrt(f64(to_camera_x * to_camera_x + to_camera_z * to_camera_z))))
        outward_angle := outline_angle + structure.rotation
        view_alignment := math.abs(
            math.cos(outward_angle) * to_camera_x / to_camera_length +
            math.sin(outward_angle) * to_camera_z / to_camera_length,
        )

        // Only side-on perimeter boughs break the screen-space silhouette.
        // Front-facing billboards would lie across the crown and read as giant
        // flat polygons when the camera approaches tree height. The near band
        // is now admitted -- down to a few crown radii away -- so walking-height
        // and understory views gain a soft leafy contour instead of the bare
        // triangulated mesh edge. It stays side-on and is eased in very small,
        // so the sprig sits on the silhouette rather than sheeting across it,
        // and because only nearby lobes qualify the card budget stays bounded
        // (overview forest and stress scenes keep the existing far-only path).
        if view_alignment < .68 && to_camera_length > 34 {
            card_scale_factor := f32(.255 + f32(variation % 3) * .018)
            if is_hedge do card_scale_factor = .225 + f32(variation % 3) * .016
            if !is_hedge && base_lift <= 0 {
                card_scale_factor = .292 + f32(variation % 3) * .018
            }
            // Cards ease in small near the camera as leafy contour nicks, reach
            // full silhouette-breaking size by mid distance, and hold there.
            near_mix := clamp((to_camera_length - 34) / 78, 0, 1)
            far_mix := clamp((to_camera_length - 112) / 82, 0, 1)
            distance_scale := .52 + near_mix * .24 + far_mix * .24
            card_scale := card_scale_factor * max(profile_width, profile_depth)
            card_scale *= distance_scale
            card_y := structure.base_y + base_lift + profile_height * (.51 + f32(variation % 3) * .032)
            world_foliage_card(
                {card_x, card_y, card_z},
                card_scale,
                card_scale * .82,
                variation * 5 + 7,
                world_foliage_vertex_color(3, color_variation),
                (variation + int(structure.seed)) % 2 == 0,
            )

            // A smaller offset spray turns the single cutout into an uneven
            // leafy bunch. Offset both outward and along the contour so the
            // pair overlaps near its branch bases but separates at the tips,
            // breaking the parent mesh silhouette at two different scales.
            tangent_x, tangent_z := -math.sin(outward_angle), math.cos(outward_angle)
            echo_side := (variation + int(structure.seed)) % 2 == 0 ? f32(1) : f32(-1)
            echo_x := card_x + math.cos(outward_angle) * card_scale * .10 + tangent_x * card_scale * .17 * echo_side
            echo_z := card_z + math.sin(outward_angle) * card_scale * .10 + tangent_z * card_scale * .17 * echo_side
            echo_scale := card_scale * (.63 + f32(variation % 2) * .055)
            world_foliage_card(
                {echo_x, card_y + card_scale * (.09 + f32(variation % 3) * .018), echo_z},
                echo_scale,
                echo_scale * .88,
                variation * 7 + 3,
                world_foliage_vertex_color(2, color_variation + 1),
                (variation + int(structure.seed)) % 2 != 0,
            )

            // Alternating mature-forest boughs receive one inverted lower
            // spray. Its branch base stays buried in the dark shelf while the
            // painted tips trail below, breaking the long canopy-ceiling edge
            // without filling the open understory with billboard cards.
            hanging_selected := base_lift > 0 && to_camera_length > 76
            if hanging_selected {
                hanging_scale := card_scale * (.57 + f32(variation % 3) * .028)
                hanging_side := variation % 2 == 0 ? f32(1) : f32(-1)
                hanging_x :=
                    card_x + math.cos(outward_angle) * card_scale * .055 + tangent_x * card_scale * .11 * hanging_side
                hanging_z :=
                    card_z + math.sin(outward_angle) * card_scale * .055 + tangent_z * card_scale * .11 * hanging_side
                world_foliage_card(
                    {
                        hanging_x,
                        structure.base_y + base_lift + profile_height * (.175 + f32(variation % 2) * .026),
                        hanging_z,
                    },
                    hanging_scale,
                    hanging_scale * 1.18,
                    variation * 11 + 5,
                    world_foliage_vertex_color(2, color_variation),
                    hanging_side < 0,
                    true,
                )
            }
        }

        hedge_face_selected :=
            is_hedge && to_camera_length > 72 && to_camera_length < 430 && (variation + int(structure.seed)) % 2 == 0
        if hedge_face_selected {
            // Push the accent onto the camera-facing shoulder so depth testing
            // attaches it to the solid crown instead of hiding it inside the
            // lobe. Partial opacity and alternating placement keep these as
            // broken leaf suggestions rather than a repeated decal strip.
            face_offset := min(profile_width, profile_depth) * .47
            face_x := lobe_world_x + to_camera_x / to_camera_length * face_offset
            face_z := lobe_world_z + to_camera_z / to_camera_length * face_offset
            face_scale := min(profile_width, profile_depth) * (.235 + f32(variation % 3) * .016)
            face_tint := world_foliage_vertex_color(3, color_variation)
            face_tint.a = 198
            world_foliage_card(
                {face_x, structure.base_y + profile_height * (.49 + f32(variation % 3) * .045), face_z},
                face_scale,
                face_scale * .78,
                variation * 13 + 9,
                face_tint,
                (variation + int(structure.seed)) % 4 == 0,
            )
        }

        bush_face_selected :=
            !is_hedge &&
            base_lift <= 0 &&
            to_camera_length > 78 &&
            to_camera_length < 430 &&
            (variation + int(structure.seed)) % 3 != 0
        if bush_face_selected {
            // Standalone bushes can carry a little more leaf-scale surface
            // rhythm than distant forest masses. Keep the accents small and
            // translucent so several read as one painted bunch, not stickers.
            face_offset := min(profile_width, profile_depth) * .46
            face_x := lobe_world_x + to_camera_x / to_camera_length * face_offset
            face_z := lobe_world_z + to_camera_z / to_camera_length * face_offset
            face_scale := min(profile_width, profile_depth) * (.19 + f32(variation % 3) * .014)
            face_tint := world_foliage_vertex_color(3, color_variation)
            face_tint.a = 186
            world_foliage_card(
                {face_x, structure.base_y + profile_height * (.50 + f32(variation % 3) * .042), face_z},
                face_scale,
                face_scale * .84,
                variation * 17 + 1,
                face_tint,
                (variation + int(structure.seed)) % 2 == 0,
            )
        }
    }
}

world_foliage_formation :: proc(
    structure: terrain.Structure,
    minimum_footprint := terrain.BASE_CELL_SIZE,
    lod: Structure_LOD = .Near,
) {
    // Authored foliage retains the tool's one-cell minimum. Derived foliage,
    // such as scrub placed on a ridge or cliff, can opt into its exact
    // footprint while still using this same crown generator.
    width := max(structure.width, minimum_footprint)
    depth := max(structure.depth, minimum_footprint)
    wide, narrow := max(width, depth), min(width, depth)
    aspect := wide / max(narrow, f32(.01))
    is_forest := aspect < 1.8 && wide >= 105 && structure.height >= 58
    // Keep forest patches dense by filling their area with tree-scale trees,
    // rather than stretching a handful of crowns across the footprint.
    forest_tree_count := is_forest ? clamp(int(width * depth / 460), 24, 36) : 0
    if is_forest && lod == .Medium do forest_tree_count = min(forest_tree_count, 24)
    if is_forest && lod == .Far do forest_tree_count = min(forest_tree_count, 12)
    // A forest formation is a grove footprint, not one gigantic tree. Keep
    // the leaf ceiling around four character heights while individual crown
    // clusters supply the remaining tree height.
    canopy_lift := is_forest ? structure.height * .11 : f32(0)

    if is_forest {
        walking_distance := lod == .Near
        dapple_count := 7
        if lod != .Near do dapple_count = 0
        for dapple in 0 ..< dapple_count {
            angle := f32(dapple) * 2.399963 + f32(structure.seed % 149) * .026
            radial := .12 + f32((dapple * 5 + 2) % 9) / 8 * .30
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            dapple_x, dapple_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            dapple_width := 13.0 + f32(dapple % 3) * 5.5
            dapple_depth := 9.5 + f32((dapple + 1) % 3) * 4.0
            dapple_rotation := angle * .47 + structure.rotation
            world_foliage_ground_dapple(
                dapple_x,
                dapple_z,
                structure.base_y,
                dapple_width,
                dapple_depth,
                dapple_rotation,
                structure.seed + u32(dapple * 1699),
            )
            // A smaller overlapping echo breaks the radial fan into a loose
            // painted pool. Offset it across the main ellipse rather than
            // scattering another isolated dot, so their shared center gains
            // light while the combined outer edge stays irregular and soft.
            echo_angle := dapple_rotation + 1.17 + f32(dapple % 2) * .41
            echo_x := dapple_x + math.cos(echo_angle) * dapple_width * .22
            echo_z := dapple_z + math.sin(echo_angle) * dapple_depth * .22
            world_foliage_ground_dapple(
                echo_x,
                echo_z,
                structure.base_y + .006,
                dapple_width * (.61 + f32(dapple % 2) * .07),
                dapple_depth * (.66 - f32(dapple % 2) * .05),
                dapple_rotation - .58,
                structure.seed + u32(dapple * 1699 + 947),
            )
        }

        understory_count := lod == .Near ? clamp(forest_tree_count * 2 / 3, 16, 24) : 0
        if walking_distance {
            understory_count = clamp(forest_tree_count, 24, 32)
        }
        for tuft in 0 ..< understory_count {
            angle := f32(tuft) * 2.399963 + f32(structure.seed % 127) * .029
            radial := .28 + f32((tuft * 7) % 9) / 8 * .25
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            tuft_x, tuft_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            // Human-scale fern colonies: broad enough to read from the editor
            // camera, but roughly knee-to-chest high in third person.
            // Each placement represents an overlapping fern colony, not one
            // enormous plant: widen the fan while retaining human-scale
            // frond height so ground cover reads as painted patches.
            tuft_width := 2.05 + f32(tuft % 4) * .38
            tuft_height := 1.05 + f32((tuft + 2) % 5) * .22
            tuft_gesture := tuft % 4
            if tuft_gesture == 0 || tuft_gesture == 1 {
                // Broad, low fern fans are the dominant ground gesture. This
                // avoids a floor full of narrow conifer-like spikes while
                // preserving layered silhouettes between the trunks.
                tuft_width *= 1.28
                tuft_height *= .76
            } else if tuft_gesture == 3 {
                // Occasional upright clumps punctuate the fan rhythm without
                // becoming the default understory silhouette.
                tuft_width *= .90
                tuft_height *= 1.10
            }
            world_foliage_understory_tuft(
                tuft_x,
                tuft_z,
                structure.base_y,
                tuft_width,
                tuft_height,
                structure.seed + u32(tuft * 1301),
            )
        }

        // A quieter layer of low broadleaf rosettes bridges the empty ground
        // between fern fans. Their separate spiral and smaller radial range
        // produce loose colonies rather than a uniformly stamped carpet.
        ground_cover_count := lod == .Near ? clamp(forest_tree_count * 3 / 4, 18, 27) : 0
        if walking_distance {
            ground_cover_count = clamp(forest_tree_count + 8, 30, 44)
        }
        for cover in 0 ..< ground_cover_count {
            angle := f32(cover) * 2.399963 + f32(structure.seed % 163) * .021 + .83
            radial := .09 + f32((cover * 5 + 3) % 11) / 10 * .41
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            cover_x, cover_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            cover_width := 1.25 + f32(cover % 4) * .28
            cover_height := .28 + f32((cover + 2) % 3) * .08
            world_foliage_ground_rosette(
                cover_x,
                cover_z,
                structure.base_y,
                cover_width,
                cover_height,
                structure.seed + u32(cover * 1877 + 431),
            )
        }

        // A low-discrepancy spiral makes a dense natural stand without rows.
        trunk_count := lod == .Far ? max(4, forest_tree_count / 2) : forest_tree_count
        for trunk in 0 ..< trunk_count {
            angle := f32(trunk) * 2.399963 + f32(structure.seed % 91) * .041
            radial := .06 + .43 * f32(math.sqrt(f64((f32(trunk) + .5) / f32(max(trunk_count, 1)))))
            local_x := math.cos(angle) * width * radial
            local_z := math.sin(angle) * depth * radial
            trunk_x, trunk_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                local_x,
                local_z,
                structure.rotation,
            )
            height_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .013 + f32(trunk) * 1.73)))
            tree_canopy_lift := structure.height * (.075 + height_noise * .055)
            trunk_height := tree_canopy_lift + structure.height * (.040 + height_noise * .012)
            trunk_radius := max(
                f32(.42),
                min(width, depth) *
                (.0045 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .031 + f32(trunk) * 2.53)))) * .0025),
            )
            world_foliage_trunk(
                trunk_x,
                trunk_z,
                structure.base_y,
                trunk_height,
                trunk_radius,
                structure.seed + u32(trunk * 977),
            )
        }
    }

    if aspect >= 1.8 {
        // Long gestures become hedges. Shorter, more numerous crowns overlap
        // into a continuous mass while exposing a readable scalloped rhythm;
        // the earlier four very long lobes merged into smooth sausages.
        lobe_count := clamp(int(wide / max(narrow * 1.6, f32(1))) + 2, 3, 6)
        // A low recessed binder closes the dark gaps between crown beats. Most
        // of it remains concealed by the scallops, preserving one continuous
        // hedge gesture without returning to a single exposed sausage.
        binder_width, binder_depth := wide * .88, narrow * .76
        if depth > width do binder_width, binder_depth = binder_depth, binder_width
        world_foliage_lobe(
            structure,
            0,
            0,
            binder_width,
            binder_depth,
            structure.height * .44,
            0,
            true,
            19,
            0,
            false,
            lod,
        )
        for lobe in 0 ..< lobe_count {
            fraction := (f32(lobe) + .5) / f32(lobe_count)
            along :=
                (fraction - .5) * wide * .82 +
                f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.77))) * wide / f32(lobe_count) * .08
            cross := f32(math.sin(f64(f32(structure.seed) * .009 + f32(lobe) * 2.41))) * narrow * .12
            local_x, local_z := along, cross
            crown_scale := .90 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .027 + f32(lobe) * 1.87)))) * .20
            if lobe == int(structure.seed % u32(lobe_count)) do crown_scale *= 1.14
            lobe_width := max(wide / f32(lobe_count) * 1.72, narrow * 1.04) * crown_scale
            lobe_depth :=
                narrow *
                (.92 + f32(math.sin(f64(f32(structure.seed) * .021 + f32(lobe) * 1.31))) * .065) *
                (.96 + (crown_scale - 1) * .38)
            if depth > width {
                local_x, local_z = cross, along
                lobe_width, lobe_depth = lobe_depth, lobe_width
            }
            lobe_height :=
                structure.height *
                (.68 + f32(math.sin(f64(f32(structure.seed) * .017 + f32(lobe) * 1.63))) * .085) *
                (.95 + (crown_scale - 1) * .32)
            outward := f32(math.PI * .5)
            if depth > width do outward = 0
            if lobe % 2 != 0 do outward += math.PI
            world_foliage_lobe(
                structure,
                local_x,
                local_z,
                lobe_width,
                lobe_depth,
                lobe_height,
                0,
                true,
                lobe,
                outward,
                true,
                lod,
            )
        }
        return
    }

    // Broad gestures become bushes or forest canopy patches. A deterministic
    // dominant crown and an opposing concave opening give each gesture a
    // composed silhouette instead of an evenly filled radial blob.
    lobe_count := clamp(int(wide / (terrain.BASE_CELL_SIZE * 1.5)) + 5, 5, 9)
    if is_forest do lobe_count = forest_tree_count
    outer_count := max(lobe_count - 1, 1)
    dominant_lobe := 1 + int(structure.seed % u32(outer_count))
    seed_phase := f32(structure.seed % 97) * .031
    dominant_angle := f32(dominant_lobe - 1) * 2.399963 + seed_phase
    opening_angle := dominant_angle + math.PI
    for lobe in 0 ..< lobe_count {
        local_x, local_z := f32(0), f32(0)
        radial := f32(0)
        angle := f32(0)
        opening_strength := f32(0)
        if lobe > 0 {
            angle = f32(lobe - 1) * 2.399963 + seed_phase
            radial = .18 + .27 * f32(math.sqrt(f64(f32(lobe) / f32(outer_count))))
            opening_delta := angle - opening_angle
            opening_distance := math.abs(math.atan2(math.sin(opening_delta), math.cos(opening_delta)))
            opening_strength = clamp(1 - opening_distance / .72, 0, 1)
            radial += opening_strength * .055
            if is_forest {
                // Forest positions are composed below from a shared tree
                // center plus one of three overlapping crown offsets. The
                // bush-specific concave opening must not shrink one crown in
                // every tree cluster.
                opening_strength = 0
            }
        }
        // The center only binds the patch together; it should not become one
        // dominant balloon. Mid-sized perimeter crowns now carry the canopy.
        scale := is_forest ? f32(.085) : f32(.59)
        if lobe > 0 {
            scale = .40 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .019 + f32(lobe) * 1.87)))) * .20
            if is_forest {
                scale = .075 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .019 + f32(lobe) * 1.87)))) * .035
            }
            scale *= 1 - opening_strength * .34
        }
        height_fraction := is_forest ? f32(.17) : f32(.80)
        if lobe > 0 {
            height_fraction = .62 + f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.71))) * .15
            if is_forest {
                height_fraction = .15 + f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.71))) * .028
            }
        }
        height_fraction *= 1 - opening_strength * .18
        if lobe == dominant_lobe {
            scale *= 1.16
            height_fraction *= 1.20
            radial *= .92
        }
        if lobe > 0 {
            if is_forest {
                // One irregular crown per trunk preserves density without
                // tripling the tessellation cost of every tree.
                tree_index := lobe
                tree_angle := f32(tree_index) * 2.399963 + f32(structure.seed % 91) * .041
                tree_radial := .06 + .43 * f32(math.sqrt(f64((f32(tree_index) + .5) / f32(max(forest_tree_count, 1)))))
                local_x = math.cos(tree_angle) * width * tree_radial
                local_z = math.sin(tree_angle) * depth * tree_radial
                angle = math.atan2(local_z / depth, local_x / width)
            } else {
                local_x = math.cos(angle) * width * radial
                local_z = math.sin(angle) * depth * radial
            }
        } else if is_forest {
            tree_angle := f32(structure.seed % 91) * .041
            tree_radial := .06 + .43 * f32(math.sqrt(f64(.5 / f32(max(forest_tree_count, 1)))))
            local_x = math.cos(tree_angle) * width * tree_radial
            local_z = math.sin(tree_angle) * depth * tree_radial
            angle = math.atan2(local_z / depth, local_x / width)
            scale = .075 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .019)))) * .035
            height_fraction = .15 + f32(math.sin(f64(f32(structure.seed) * .013))) * .028
        }
        lobe_height := structure.height * height_fraction
        outward := f32(0)
        if lobe > 0 do outward = math.atan2(local_z / depth, local_x / width)
        lobe_base_lift := canopy_lift
        if is_forest {
            // Layer saplings, middle crowns, and mature trees into one dense
            // stand. The matching expression in the trunk pass keeps every
            // crown attached to its own trunk.
            height_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .013 + f32(lobe) * 1.73)))
            lobe_base_lift = structure.height * (.075 + height_noise * .055)
            lobe_height *= .82 + height_noise * .30
        }
        lobe_width, lobe_depth := width * scale, depth * scale
        lobe_structure := structure
        if is_forest {
            // A tree crown has its own dimensions; it must not inherit the
            // aspect ratio of the authored forest footprint. Per-tree seed
            // variation also mixes crown profiles and green families across
            // the stand instead of tinting the whole patch as one species.
            crown_noise := .5 + .5 * f32(math.sin(f64(f32(structure.seed) * .029 + f32(lobe) * 2.17)))
            crown_span := structure.height * (.17 + crown_noise * .075)
            crown_aspect := .84 + (.5 + .5 * f32(math.sin(f64(f32(structure.seed) * .041 + f32(lobe) * 1.31)))) * .34
            lobe_width = crown_span * crown_aspect
            lobe_depth = crown_span / crown_aspect
            lobe_structure.seed += u32(lobe * 977)
        }
        world_foliage_lobe(
            lobe_structure,
            local_x,
            local_z,
            lobe_width,
            lobe_depth,
            lobe_height,
            lobe_base_lift,
            false,
            lobe,
            outward,
            lobe > 0,
            lod,
        )
    }
}

world_formation_top_fraction :: proc(structure: terrain.Structure, local_x, local_z: f32) -> f32 {
    if structure.kind == .Cliff {
        // Cliff tops follow the same segmented, lightly broken profile as the
        // rendered cliff mesh.
        segment := (local_x / max(structure.width, f32(.01)) + .5) * 6
        return .84 + f32(math.sin(f64(f32(structure.seed) * .001 + segment * 1.73))) * .055
    }
    // Ridge foliage sits on the radial ridge profile, not on a flat height
    // fraction. This keeps bushes on the shoulder from hovering in the air.
    radius_x := local_x / max(structure.width * .5, f32(.01))
    radius_z := local_z / max(structure.depth * .5 * .42, f32(.01))
    radius := f32(math.sqrt(f64(radius_x * radius_x + radius_z * radius_z)))
    if radius >= .92 do return clamp((1 - radius) / .08 * .22, 0, .22)
    if radius >= .60 do return .22 + (.92 - radius) / .32 * .28
    if radius >= .14 do return .50 + (.60 - radius) / .46 * .28
    return .78 + (.14 - radius) / .14 * .12
}

world_formation_foliage :: proc(structure: terrain.Structure, lod: Structure_LOD = .Near) {
    if lod == .Far do return
    tuft_count := clamp(int(structure.width / 14), 4, 20)
    if lod == .Medium do tuft_count = max(2, tuft_count / 2)
    for tuft in 0 ..< tuft_count {
        fraction := (f32(tuft) + .5) / f32(tuft_count)
        jitter := f32(math.sin(f64(f32(structure.seed) * .013 + f32(tuft) * 2.41)))
        local_x := (fraction - .5) * structure.width + jitter * min(structure.width * .08, 3)
        local_z := f32(math.sin(f64(f32(structure.seed) * .007 + f32(tuft) * 1.73))) * structure.depth * .24
        base_y := structure.base_y + structure.height * world_formation_top_fraction(structure, local_x, local_z)
        bush_width := clamp(structure.depth * .50, 1.8, 10.0)
        bush_depth := clamp(structure.depth * .38, 1.3, 7.0)
        bush_height := clamp(structure.height * (.22 + f32(tuft % 3) * .035), 2.5, 10.0)
        bush_x, bush_z := world_rotate_xz(structure.center_x, structure.center_z, local_x, local_z, structure.rotation)
        foliage := structure
        foliage.kind = .Foliage
        foliage.center_x = bush_x
        foliage.center_z = bush_z
        foliage.base_y = base_y
        // The former tuft dimensions were radii. These compact footprints keep
        // roughly the same occupied area after the shared generator adds its
        // overlapping perimeter crowns.
        foliage.width = bush_width * 1.55
        foliage.depth = bush_depth * 1.55
        foliage.height = bush_height
        foliage.rotation += jitter * .18
        foliage.seed += u32(tuft * 977 + 431)
        world_foliage_formation(foliage, 0, lod)
    }
}

@(no_instrumentation)
world_architecture_cypress_surface_color :: #force_inline proc(
    base: rl.Color,
    angle, progress: f32,
    ring: int,
    seed: u32,
) -> rl.Color {
    color := formation_face_color(base, angle, ring)
    // Long correlated waves imply upright sprays and the cool recesses between
    // them. A quieter cross-wave keeps those strokes from becoming stripes.
    long_wave := f32(math.sin(f64(angle * 3.1 + progress * 2.4 + f32(seed % 211) * .031)))
    cross_wave := f32(math.sin(f64(angle * 6.7 - progress * 5.2 + f32(seed % 157) * .047)))
    spray_field := long_wave * .72 + cross_wave * .28
    if spray_field < -.12 {
        recess := clamp((-spray_field - .12) / .88, 0, 1)
        color = color_lerp(color, {18, 49, 34, 255}, recess * .42)
    } else if spray_field > .24 {
        crest := clamp((spray_field - .24) / .76, 0, 1)
        color = color_lerp(color, {82, 137, 73, 255}, crest * .16)
    }
    return color
}

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
    ring_color := [RINGS]rl.Color {
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
    skirt_center_color := rl.Color{20, 50, 34, 255}
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

world_laundry_web_segment :: proc(a, b: third_person.Vec3, color: rl.Color) {
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
    color: rl.Color,
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

world_architecture_laundry_webbing :: proc(editor: ^Editor) {
    if editor == nil do return
    webbing_count := 0
    webbing_limit := 8
    structures := editor.project.structures[:editor.project.structure_count]
    building_spans := world_renderer.structure_building_spans[:len(structures)]
    for &span in building_spans do span = 0
    cloth_colors := [4]rl.Color{{235, 224, 188, 255}, {112, 157, 171, 255}, {191, 94, 72, 255}, {205, 157, 177, 255}}
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
                worker_body := rl.Color{74, 67, 61, 255}
                worker_shirt :=
                    (first.seed + second.seed) % 2 == 0 ? rl.Color{132, 104, 79, 255} : rl.Color{77, 109, 119, 255}
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
            append(&footprints, Architecture_Grass_Footprint {
                center_x   = center_x,
                center_z   = center_z,
                half_width = mass.width * .5,
                half_depth = mass.depth * .5,
                rotation   = structure.rotation,
            })
        }
    }
    // The kiosks are procedural landmarks rather than authored Architecture
    // structures, so register their pads and approaches explicitly.
    kiosk_positions := [2]third_person.Vec3{editor.attendant_position, editor.gerta_position}
    for kiosk in kiosk_positions {
        append(&footprints, Architecture_Grass_Footprint {
            center_x   = kiosk.x,
            center_z   = kiosk.z + .35,
            half_width = 2.1,
            half_depth = 1.9,
        }, Architecture_Grass_Footprint {
            center_x   = kiosk.x,
            center_z   = kiosk.z - 2.65,
            half_width = .825,
            half_depth = 1.5,
        })
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

world_architecture_streets :: proc(editor: ^Editor, sun_direction: [3]f32, cloud_cover: f32) {
    if editor == nil || lab_scene_suppresses_procedural_circulation(editor) do return
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
    if buildings < 4 || max_z <= min_z do return
    center_x := (min_x + max_x) * .5
    center_z := (min_z + max_z) * .5
    road_span := max(max_x - min_x + 36, 160)
    plan := editor_circulation_plan(editor)
    road := rl.Color{117, 119, 110, 255}
    shoulder := rl.Color{177, 164, 135, 255}
    path_color := rl.Color{194, 184, 157, 255}
    for area in plan.areas[:plan.count] {
        switch area.kind {
        case .Street:
            world_land_surface_rotated(editor, area.center_x, area.center_z, area.width, 5.5, area.rotation, .12, road)
            for side in -1 ..= 1 {
                if side == 0 do continue
                offset_x := -math.sin(area.rotation) * f32(side) * 3.05
                offset_z := math.cos(area.rotation) * f32(side) * 3.05
                world_land_surface_rotated(
                    editor,
                    area.center_x + offset_x,
                    area.center_z + offset_z,
                    area.width,
                    .35,
                    area.rotation,
                    .15,
                    shoulder,
                )
            }
        case .Plaza:
            world_land_surface_rotated(
                editor,
                area.center_x,
                area.center_z,
                area.width,
                area.length,
                area.rotation,
                .16,
                {151, 144, 126, 255},
            )
        case .Path, .Forecourt:
            world_land_surface_rotated(
                editor,
                area.center_x,
                area.center_z,
                area.width,
                area.length,
                area.rotation,
                .20,
                path_color,
            )
        }
    }

    // Entrance decoration remains presentation-only, while the path beneath
    // it now comes from the shared circulation plan above.
    for structure in editor.project.structures[:editor.project.structure_count] {
        if structure.kind != .Architecture || structure.height > 60 do continue
        if structure.seed % 3 != 0 do continue
        frontage := architecture.architecture_frontage_structure(structure)
        door_x, door_z := world_rotate_xz(
            frontage.center_x,
            frontage.center_z,
            0,
            frontage.depth * .5 + .22,
            frontage.rotation,
        )
        for pot_side in -1 ..= 1 {
            if pot_side == 0 do continue
            pot_x, pot_z := world_rotate_xz(
                door_x,
                door_z,
                f32(pot_side) * frontage.width * .27,
                .88,
                frontage.rotation,
            )
            pot_y := terrain.sample_height(&editor.project, 0, pot_x, pot_z)
            world_box_rotated({pot_x, pot_y + .22, pot_z}, {.32, .44, .32}, frontage.rotation, {169, 96, 61, 255})
            world_box_rotated({pot_x, pot_y + .53, pot_z}, {.44, .18, .44}, frontage.rotation, {77, 111, 63, 255})
        }
    }
    world_architecture_laundry_webbing(editor)
    // Cypress accents mark the two lane intersections and give the graph town
    // a readable Mediterranean scale cue without changing terrain data.
    for x_side in -1 ..= 1 {
        if x_side == 0 do continue
        for z_side in -1 ..= 1 {
            if z_side == 0 do continue
            tree_x := center_x + f32(x_side) * road_span * .42
            tree_z := center_z + f32(z_side) * ((max_z - min_z) * .5 + 7)
            if !architecture.city_accent_site_clear(&editor.project, tree_x, tree_z, 5) do continue
            tree_base := terrain.sample_height(&editor.project, 0, tree_x, tree_z)
            tree_seed := u32((x_side + 2) * 37 + (z_side + 2) * 11 + buildings * 5)
            world_architecture_cypress(tree_x, tree_z, tree_base, tree_seed)
            if (x_side == -1 && z_side == 1) || (x_side == 1 && z_side == -1) {
                olive_x := tree_x - f32(x_side) * 8
                olive_z := tree_z - f32(z_side) * 5
                olive_base := terrain.sample_height(&editor.project, 0, olive_x, olive_z)
                world_architecture_olive(
                    olive_x,
                    olive_z,
                    olive_base,
                    u32((x_side + 3) * 53 + (z_side + 3) * 17 + buildings * 9),
                )
            }
        }
    }
}

world_structures :: proc(editor: ^Editor) {
    if editor == nil do return
    sky := atmosphere.sample(&editor.atmosphere)
    world_architecture_streets(editor, sky.sun_direction, sky.weather.cloud_cover)
    hovered_index := -1
    if editor.tool == .Structure &&
       !editor.road_mode &&
       editor.cursor_hit &&
       !editor.structure_placing &&
       !editor.structure_moving {
        hovered_index = terrain.structure_index_at(&editor.project, editor.cursor_world_x, editor.cursor_world_z)
    }
    // Traverse structures from the camera outward so LOD and cache work stay
    // stable while each structure contributes its mass and climbing growth.
    focal_length := editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : f32(1.35)
    view_camera := perspective_camera(editor.camera_pose, focal_length)
    screen_width := max(rl.GetScreenWidth(), 1)
    screen_height := max(rl.GetScreenHeight(), 1)
    aspect := f32(screen_width) / f32(screen_height)
    near_plane := world_camera_near_clip(editor)
    stats := &world_renderer.static_visibility
    stats^ = {}
    selected_index := !editor.in_map ? editor.structure_selected : -1
    camera_position := [2]f32{view_camera.position.x, view_camera.position.z}
    order_rebuild :=
        !world_renderer.structure_visibility_order_valid ||
        len(world_renderer.structure_visibility_order) != editor.project.structure_count
    order_dirty :=
        order_rebuild ||
        world_renderer.structure_visibility_camera != camera_position ||
        world_renderer.structure_visibility_selected != selected_index ||
        world_renderer.structure_visibility_hovered != hovered_index
    if !order_dirty {
        for structure, index in editor.project.structures[:editor.project.structure_count] {
            center := [2]f32{structure.center_x, structure.center_z}
            if world_renderer.structure_visibility_centers[index] != center {
                order_dirty = true
                break
            }
        }
    }
    if order_dirty {
        if order_rebuild {
            clear(&world_renderer.structure_visibility_order)
            for index in 0 ..< editor.project.structure_count {
                append(&world_renderer.structure_visibility_order, Structure_Visibility_Order{index = index})
            }
        }
        for &ordered in world_renderer.structure_visibility_order {
            structure := editor.project.structures[ordered.index]
            world_renderer.structure_visibility_centers[ordered.index] = {
                structure.center_x,
                structure.center_z,
            }
            dx, dz := structure.center_x - view_camera.position.x, structure.center_z - view_camera.position.z
            ordered.distance_squared = dx * dx + dz * dz
            if ordered.index == selected_index || ordered.index == hovered_index {
                ordered.distance_squared = -1
            }
        }
        if !structure_visibility_order_repair(world_renderer.structure_visibility_order[:]) {
            slice.sort_by(world_renderer.structure_visibility_order[:], structure_visibility_order_less)
        }
        world_renderer.structure_visibility_camera = camera_position
        world_renderer.structure_visibility_selected = selected_index
        world_renderer.structure_visibility_hovered = hovered_index
        world_renderer.structure_visibility_order_valid = true
    }
    for ordered in world_renderer.structure_visibility_order {
        index := ordered.index
        structure := editor.project.structures[index]
        stats.candidates += 1
        force_visible := index == selected_index || index == hovered_index
        center, radius := structure_visibility_sphere(structure)
        if !force_visible &&
           !static_sphere_in_frustum(view_camera, center, radius, aspect, near_plane, WORLD_FAR_CLIP) {
            world_renderer.static_visibility_classification[index] = .Frustum_Culled
            stats.frustum_culled += 1
            continue
        }
        if force_visible {
            world_renderer.static_visibility_classification[index] = .Force_Visible
            stats.force_visible += 1
        } else {
            world_renderer.static_visibility_classification[index] = .Visible
        }
        if editor.architecture_painting &&
           structure.kind == .Architecture &&
           architecture.city_bounds_contains(
               architecture.city_bounds_expand(editor.architecture_dirty_bounds, 48),
               structure.center_x,
               structure.center_z,
           ) {
            continue
        }
        force_near := index == editor.structure_selected && !editor.in_map
        world_before := len(world_renderer.vertices) + len(world_renderer.static_indices)
        foliage_vertices_before := len(world_renderer.foliage_vertices)
        bougainvillea_vertices_before := len(world_renderer.bougainvillea_vertices)
        if structure.kind == .Foliage {
            world_foliage_formation_cached(structure, index, force_near)
            world_renderer.structure_lod_counts[int(world_renderer.foliage_geometry_cache[index].lod)] += 1
        } else {
            world_static_formation_cached(structure, index, &editor.project, force_near)
            world_renderer.structure_lod_counts[int(world_renderer.static_geometry_cache[index].lod)] += 1
        }
        world_climbing_leaves_for_structure(editor, structure, index)
        world_renderer.structure_lod_world_vertices +=
            len(world_renderer.vertices) + len(world_renderer.static_indices) - world_before
        world_renderer.structure_lod_foliage_vertices +=
            len(world_renderer.foliage_vertices) - foliage_vertices_before +
            len(world_renderer.bougainvillea_vertices) - bougainvillea_vertices_before
        world_added := len(world_renderer.vertices) + len(world_renderer.static_indices) - world_before
        foliage_added := len(world_renderer.foliage_vertices) - foliage_vertices_before
        bougainvillea_added := len(world_renderer.bougainvillea_vertices) - bougainvillea_vertices_before
        if world_added > 0 || foliage_added > 0 || bougainvillea_added > 0 {
            stats.opaque_cost += u32(max(world_added, 0))
            stats.foliage_cost += u32(max(foliage_added, 0))
            stats.bougainvillea_cost += u32(max(bougainvillea_added, 0))
        } else {
            world_renderer.static_visibility_classification[index] = .Empty
            stats.empty += 1
        }
        if index == editor.structure_selected && !editor.in_map && !editor.road_mode {
            world_structure_frame(structure, structure.base_y + structure.height, {244, 226, 122, 255})
        } else if index == hovered_index && !editor.in_map {
            world_structure_frame(structure, structure.base_y + structure.height + .02, {168, 239, 220, 255})
        }
    }
    if stats.opaque_cost > 0 do stats.emitted_draws += 1
    if stats.foliage_cost > 0 do stats.emitted_draws += 1
    if stats.bougainvillea_cost > 0 do stats.emitted_draws += 1
    if editor.structure_placing {
        world_structure_preview_cluster(editor)
    }
    world_curve_preview(editor)
    world_architecture_alleys(editor, &editor.architecture_city_plan)
    world_architecture_lamps(editor, &editor.architecture_city_plan)
    if editor.architecture_painting {
        world_architecture_alleys(editor, &editor.architecture_preview_plan, true)
        for candidate in editor.architecture_preview_plan.structures[:editor.architecture_preview_plan.count] {
            preview := candidate
            preview.color = {168, 239, 220, 210}
            world_formation(preview, &editor.project)
            world_structure_frame(preview, preview.base_y + .05, {190, 255, 229, 210})
        }
    }
    world_greek_assets(editor)
}

world_city_density_overlay :: proc(editor: ^Editor) {
    if editor == nil || editor.in_map || !editor.architecture_paint_mode do return
    field := &editor.project.city_density
    if editor.architecture_painting do field = &editor.architecture_density_preview
    cell := terrain.BASE_CELL_SIZE
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    for z in 0 ..< terrain.RING_RESOLUTION - 1 {
        for x in 0 ..< terrain.RING_RESOLUTION - 1 {
            density := f32(field[z * terrain.RING_RESOLUTION + x]) / 255
            if density <= .01 do continue
            x0, z0 := (f32(x) - half) * cell, (f32(z) - half) * cell
            x1, z1 := x0 + cell, z0 + cell
            lift := f32(.115)
            a := third_person.Vec3{x0, terrain.sample_height(&editor.project, 0, x0, z0) + lift, z0}
            b := third_person.Vec3{x1, terrain.sample_height(&editor.project, 0, x1, z0) + lift, z0}
            c := third_person.Vec3{x1, terrain.sample_height(&editor.project, 0, x1, z1) + lift, z1}
            d := third_person.Vec3{x0, terrain.sample_height(&editor.project, 0, x0, z1) + lift, z1}
            alpha := u8(28 + density * 112)
            world_quad(a, b, c, d, {22, 27, 31, alpha})
        }
    }
}

world_climbing_leaf_opening_badness :: proc(structure: terrain.Structure, local_x, local_y: f32) -> f32 {
    if structure.kind != .Architecture do return 0

    badness := f32(0)
    landmark := structure.height > 60
    if !landmark {
        // Include the lobe footprint in the exclusion margin, not just its
        // center, so a broad cluster cannot clip an opening from the side.
        door_x_score := clamp(1 - math.abs(local_x) / (structure.width * .24), 0, 1)
        door_y_score := clamp(1 - math.abs(local_y - structure.height * .14) / (structure.height * .25), 0, 1)
        badness = max(badness, door_x_score * door_y_score)
    }

    rows := architecture.facade_floor_count(structure.height)
    columns := architecture.facade_column_count(structure.width)
    window_height := architecture.facade_window_height(structure.height)
    window_width := architecture.facade_window_width(structure.width)
    for row in 0 ..< rows {
        window_y := architecture.facade_window_row_y(structure.height, row)
        window_y_score := clamp(1 - math.abs(local_y - window_y) / (window_height * .75 + .55), 0, 1)
        // Protect the full visual window band, not only the dark rectangle.
        // At façade distance a lobe beside a frame still reads as covering
        // the opening, so growth is routed into the masonry between floors.
        badness = max(badness, window_y_score * .74)
        for column in 0 ..< columns {
            window_x := architecture.facade_window_column_x(structure.width, column)
            window_x_score := clamp(1 - math.abs(local_x - window_x) / (window_width * .5 + .75), 0, 1)
            badness = max(badness, window_x_score * window_y_score)
        }
    }
    return clamp(badness, 0, 1)
}

world_climbing_leaf_stem_opening_badness :: proc(structure: terrain.Structure, local_x, local_y: f32) -> f32 {
    if structure.kind != .Architecture do return 0

    // Woody leaders only need to avoid the actual opening rectangles. The
    // broader floor-band exclusion used by foliage masses would make every
    // stem disappear between floors even when there is clear masonry beside
    // the windows.
    badness := f32(0)
    landmark := structure.height > 60
    if !landmark {
        door_x_score := clamp(1 - math.abs(local_x) / (structure.width * .20), 0, 1)
        door_y_score := clamp(1 - math.abs(local_y - structure.height * .14) / (structure.height * .23), 0, 1)
        badness = max(badness, door_x_score * door_y_score)
    }

    rows := architecture.facade_floor_count(structure.height)
    columns := architecture.facade_column_count(structure.width)
    window_height := architecture.facade_window_height(structure.height)
    window_width := architecture.facade_window_width(structure.width)
    for row in 0 ..< rows {
        window_y := architecture.facade_window_row_y(structure.height, row)
        window_y_score := clamp(1 - math.abs(local_y - window_y) / (window_height * .5 + .30), 0, 1)
        for column in 0 ..< columns {
            window_x := architecture.facade_window_column_x(structure.width, column)
            window_x_score := clamp(1 - math.abs(local_x - window_x) / (window_width * .5 + .35), 0, 1)
            badness = max(badness, window_x_score * window_y_score)
        }
    }
    return clamp(badness, 0, 1)
}

world_climbing_leaf_route_x :: proc(
    structure: terrain.Structure,
    preferred_x, previous_x, previous_y, previous_delta, local_y: f32,
) -> f32 {
    if structure.kind != .Architecture do return preferred_x
    offsets := [13]f32{0, -.055, .055, -.11, .11, -.17, .17, -.23, .23, -.30, .30, -.37, .37}
    best_x := preferred_x
    best_score := f32(1.0e20)
    for offset in offsets {
        candidate := clamp(preferred_x + offset * structure.width, -structure.width * .45, structure.width * .45)
        opening := f32(0)
        // Score the entire proposed segment, not just its destination. A
        // horizontal leader can have clear endpoints yet pass directly
        // through a window between them.
        for route_sample in 0 ..= 4 {
            sample_t := f32(route_sample) / 4
            sample_x := previous_x + (candidate - previous_x) * sample_t
            sample_y := previous_y + (local_y - previous_y) * sample_t
            opening = max(opening, world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y))
        }
        continuity := math.abs(candidate - previous_x) / max(structure.width, f32(1))
        curvature := math.abs((candidate - previous_x) - previous_delta) / max(structure.width, f32(1))
        departure := math.abs(candidate - preferred_x) / max(structure.width, f32(1))
        score := opening * 4.5 + continuity * 1.40 + curvature * .82 + departure * .18
        if score < best_score {
            best_x, best_score = candidate, score
        }
    }
    return best_x
}

world_climbing_leaf_segment_detour_x :: proc(
    structure: terrain.Structure,
    start_x, start_y, end_x, end_y: f32,
) -> f32 {
    if structure.kind != .Architecture do return (start_x + end_x) * .5
    middle_y := (start_y + end_y) * .5
    preferred_x := (start_x + end_x) * .5
    best_x := preferred_x
    best_score := f32(1.0e20)
    // Search the full usable façade width. The ordinary point router favors
    // smooth local motion; this fallback instead prioritizes a clear masonry
    // corridor so a difficult opening can never sever the woody leader.
    for candidate_index in 0 ..= 20 {
        candidate_x := (-.45 + f32(candidate_index) / 20 * .90) * structure.width
        opening := f32(0)
        for route_sample in 0 ..= 5 {
            sample_t := f32(route_sample) / 5
            first_x := start_x + (candidate_x - start_x) * sample_t
            first_y := start_y + (middle_y - start_y) * sample_t
            second_x := candidate_x + (end_x - candidate_x) * sample_t
            second_y := middle_y + (end_y - middle_y) * sample_t
            opening = max(
                opening,
                max(
                    world_climbing_leaf_stem_opening_badness(structure, first_x, first_y),
                    world_climbing_leaf_stem_opening_badness(structure, second_x, second_y),
                ),
            )
        }
        departure := math.abs(candidate_x - preferred_x) / max(structure.width, f32(1))
        score := opening * 8 + departure * .18
        if score < best_score {
            best_x, best_score = candidate_x, score
        }
    }
    return best_x
}

world_climbing_leaf_vine :: proc(
    structure: terrain.Structure,
    local_x, root_local_x, surface_z, vine_height: f32,
    growth_density: f32,
    seed, plant_seed: u32,
    render_root: bool,
) {
    vine_maturity := f32(1)
    if structure.kind == .Architecture {
        vine_maturity = architecture.bougainvillea_maturity(growth_density)
    }
    detail_tier := 2
    crown_detail_fade := f32(1)
    if structure.kind == .Architecture && world_renderer.editor != nil {
        camera_position := world_renderer.editor.camera_pose.position
        camera_dx := camera_position.x - structure.center_x
        camera_dz := camera_position.z - structure.center_z
        camera_distance := f32(math.sqrt(f64(camera_dx * camera_dx + camera_dz * camera_dz)))
        detail_tier = architecture.bougainvillea_detail_tier(camera_distance)
        crown_detail_fade = architecture.bougainvillea_crown_detail_fade(camera_distance)
    }
    root_scale := .78 + vine_maturity * .42
    stem_start := structure.base_y + .12 + f32(seed % 5) * .28
    planter_rooted := false
    if structure.kind == .Architecture {
        // Architectural bougainvillea starts from a legible growing medium,
        // never from an arbitrary point partway up the wall.
        planter_rooted = architecture.bougainvillea_planter_rooted(plant_seed)
        stem_start = structure.base_y + (planter_rooted ? .50 * root_scale : .12)
    }
    stem_end := min(structure.base_y + vine_height, structure.base_y + structure.height * .86)
    if stem_end <= stem_start + .2 do return
    // Sixteen samples keep detours around openings curved and connected.
    // Ten allowed a safe point above and below a window to be joined by one
    // long diagonal that visibly crossed the opening between them.
    vine_points: [16]third_person.Vec3
    vine_local_x: [16]f32
    previous_x := local_x
    previous_y := stem_start - structure.base_y
    previous_delta := f32(0)
    for point_index in 0 ..< len(vine_points) {
        t := f32(point_index) / f32(len(vine_points) - 1)
        sway := f32(math.sin(f64(f32(seed) * .013 + t * 5.7))) * structure.width * (.025 + t * .055)
        drift := f32(math.cos(f64(f32(seed) * .021 + t * 4.1))) * (.16 + t * .08)
        if structure.kind == .Architecture {
            divergence := t * t * (3 - 2 * t)
            trained_x := root_local_x + (local_x - root_local_x) * divergence
            // Multiple leaders share an exact basal origin, then acquire
            // independent shape only as their woody paths diverge.
            sway = trained_x - local_x + sway * divergence
        }
        // The woody path is structural geometry and must remain attached to
        // its wall. Leaf cards and papery bracts receive wind deformation in
        // the foliage shader without moving this attachment skeleton.
        local_y := stem_start + (stem_end - stem_start) * t - structure.base_y
        routed_x := world_climbing_leaf_route_x(
            structure,
            local_x + sway,
            previous_x,
            previous_y,
            previous_delta,
            local_y,
        )
        vine_local_x[point_index] = routed_x
        previous_delta = routed_x - previous_x
        previous_x = routed_x
        previous_y = local_y
        point_x, point_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            routed_x,
            surface_z + drift,
            structure.rotation,
        )
        vine_points[point_index] = {point_x, structure.base_y + local_y, point_z}
    }
    if structure.kind == .Architecture {
        for _ in 0 ..< 2 {
            smoothed_points := vine_points
            smoothed_local_x := vine_local_x
            for point_index in 1 ..< len(vine_points) - 1 {
                candidate_x :=
                    vine_local_x[point_index - 1] * .25 +
                    vine_local_x[point_index] * .50 +
                    vine_local_x[point_index + 1] * .25
                candidate_y := vine_points[point_index].y - structure.base_y
                left_mid_x := (vine_local_x[point_index - 1] + candidate_x) * .5
                left_mid_y := (vine_points[point_index - 1].y + vine_points[point_index].y) * .5 - structure.base_y
                right_mid_x := (candidate_x + vine_local_x[point_index + 1]) * .5
                right_mid_y := (vine_points[point_index].y + vine_points[point_index + 1].y) * .5 - structure.base_y
                candidate_badness := world_climbing_leaf_stem_opening_badness(structure, candidate_x, candidate_y)
                segment_badness := max(
                    world_climbing_leaf_stem_opening_badness(structure, left_mid_x, left_mid_y),
                    world_climbing_leaf_stem_opening_badness(structure, right_mid_x, right_mid_y),
                )
                if max(candidate_badness, segment_badness) < .42 {
                    smoothed_local_x[point_index] = candidate_x
                    smoothed_points[point_index].x =
                        vine_points[point_index - 1].x * .25 +
                        vine_points[point_index].x * .50 +
                        vine_points[point_index + 1].x * .25
                    smoothed_points[point_index].z =
                        vine_points[point_index - 1].z * .25 +
                        vine_points[point_index].z * .50 +
                        vine_points[point_index + 1].z * .25
                }
            }
            vine_points = smoothed_points
            vine_local_x = smoothed_local_x
        }
    }
    if structure.kind == .Architecture && render_root {
        root := vine_points[0]
        if planter_rooted {
            pottery := plant_seed % 2 == 0 ? rl.Color{177, 92, 57, 255} : rl.Color{156, 79, 53, 255}
            pottery_lip := formation_face_color(pottery, .35, 0)
            // A tapered body, proud rim, and visible soil plane read as an
            // actual terracotta planter rather than the former generic cube.
            world_box_rotated(
                {root.x, structure.base_y + .025 * root_scale, root.z},
                {.76 * root_scale, .05 * root_scale, .62 * root_scale},
                structure.rotation,
                plant_seed % 2 == 0 ? rl.Color{139, 70, 47, 255} : rl.Color{124, 62, 44, 255},
            )
            world_tapered_box_rotated(
                {root.x, structure.base_y + .22 * root_scale, root.z},
                .40 * root_scale,
                .48 * root_scale,
                .38 * root_scale,
                .64 * root_scale,
                .50 * root_scale,
                structure.rotation,
                pottery,
            )
            world_box_rotated(
                {root.x, structure.base_y + .43 * root_scale, root.z},
                {.70 * root_scale, .12 * root_scale, .56 * root_scale},
                structure.rotation,
                pottery_lip,
            )
            world_box_rotated(
                {root.x, structure.base_y + .495 * root_scale, root.z},
                {.56 * root_scale, .025 * root_scale, .42 * root_scale},
                structure.rotation,
                {72, 55, 37, 255},
            )
            // Mature bougainvillea develops a conspicuous woody crown rather
            // than emerging from the compost as one pencil-thin line. Seat a
            // low swelling and a few surface roots just above the soil plane;
            // all remain inside the rim, so entrance clearance is unchanged.
            // Small geometry receives stronger face shading than the main
            // tubes, so start lighter here to retain warm bark detail instead
            // of collapsing into a near-black knot at architectural distance.
            root_wood := color_lerp({151, 111, 72, 255}, {132, 91, 58, 255}, vine_maturity)
            root_crown := third_person.Vec3{root.x, structure.base_y + .502 * root_scale, root.z}
            world_ellipsoid_rotated(
                root_crown,
                (.070 + vine_maturity * .032) * root_scale,
                (.052 + vine_maturity * .024) * root_scale,
                (.060 + vine_maturity * .020) * root_scale,
                structure.rotation,
                root_wood,
            )
            if detail_tier >= 2 {
                for root_index in 0 ..< 3 {
                    root_angle := structure.rotation + (f32(root_index) - 1) * .82 + f32(plant_seed % 5) * .06
                    root_reach := (.12 + f32(root_index % 2) * .035) * root_scale
                    root_tip := third_person.Vec3 {
                        root.x + f32(math.cos(f64(root_angle))) * root_reach,
                        structure.base_y + .508 * root_scale,
                        root.z + f32(math.sin(f64(root_angle))) * root_reach,
                    }
                    world_tube_between(
                        root_crown,
                        root_tip,
                        {0, 1, 0},
                        (.040 + vine_maturity * .012) * root_scale,
                        .018 * root_scale,
                        root_wood,
                    )
                }
            }
        } else {
            // Some façades grow directly from a narrow soil pocket at the
            // masonry edge. Keep it low so it reads as ground contact rather
            // than another planter variant.
            world_tapered_box_rotated(
                {root.x, structure.base_y + .035, root.z},
                .07,
                .72 * root_scale,
                .46 * root_scale,
                .58 * root_scale,
                .36 * root_scale,
                structure.rotation,
                {76, 60, 40, 255},
            )
            for root_index in 0 ..< 3 {
                angle := structure.rotation + (f32(root_index) - 1) * .72
                root_tip := third_person.Vec3 {
                    root.x + math.cos(angle) * (.22 + f32(root_index) * .035) * root_scale,
                    structure.base_y + .075,
                    root.z + math.sin(angle) * (.22 + f32(root_index) * .035) * root_scale,
                }
                world_tube_between(
                    {root.x, structure.base_y + .13, root.z},
                    root_tip,
                    {0, 1, 0},
                    .045 * root_scale,
                    .025 * root_scale,
                    {112, 78, 50, 255},
                )
            }
        }
        fallen_count := architecture.bougainvillea_fallen_bract_count(vine_maturity)
        if fallen_count > 0 && detail_tier >= 2 {
            // Mature bougainvillea sheds papery bracts continuously. A small
            // palette-matched scatter ties the distant flower crown back to
            // its planter or soil pocket without becoming a litter decal.
            palette_color := architecture.bougainvillea_bract_color(architecture.bougainvillea_palette(plant_seed))
            bract_color := rl.Color{palette_color[0], palette_color[1], palette_color[2], palette_color[3]}
            base_radius := planter_rooted ? .46 * root_scale : .20 * root_scale
            for fallen in 0 ..< fallen_count {
                angle := f32(plant_seed % 29) * .31 + f32(fallen) * 2.399963
                radius := base_radius + f32(fallen % 3) * .10 * root_scale
                direction_x, direction_z := f32(math.cos(f64(angle))), f32(math.sin(f64(angle)))
                tangent_x, tangent_z := -direction_z, direction_x
                center := third_person.Vec3 {
                    root.x + direction_x * radius,
                    structure.base_y + .018 + f32(fallen % 2) * .003,
                    root.z + direction_z * radius,
                }
                bract_length := (.055 + f32(fallen % 2) * .014) * root_scale
                bract_width := bract_length * .58
                tip := third_person.Vec3 {
                    center.x + direction_x * bract_length,
                    center.y,
                    center.z + direction_z * bract_length,
                }
                left := third_person.Vec3 {
                    center.x - direction_x * bract_length * .52 - tangent_x * bract_width,
                    center.y,
                    center.z - direction_z * bract_length * .52 - tangent_z * bract_width,
                }
                right := third_person.Vec3 {
                    center.x - direction_x * bract_length * .52 + tangent_x * bract_width,
                    center.y,
                    center.z - direction_z * bract_length * .52 + tangent_z * bract_width,
                }
                tone := f32(fallen % 3) * .06
                fallen_color := color_lerp(bract_color, {239, 188, 157, 255}, tone)
                world_triangle(tip, left, right, fallen_color)
                world_triangle(tip, right, left, fallen_color)
            }
        }
    }
    woody_color := rl.Color{62, 108, 55, 255}
    woody_base_radius := f32(.055)
    woody_tip_radius := f32(.040)
    if structure.kind == .Architecture {
        wood_age := clamp((vine_maturity - .06) / .50, 0, 1)
        wood_age = wood_age * wood_age * (3 - 2 * wood_age)
        woody_color = color_lerp({78, 105, 63, 255}, {126, 91, 59, 255}, wood_age)
        woody_base_radius = .044 + vine_maturity * .030
        woody_tip_radius = .030 + vine_maturity * .012
    }
    secondary_strength := f32(0)
    facade_right_x, facade_right_z := f32(0), f32(0)
    facade_out_x, facade_out_z := f32(0), f32(0)
    if structure.kind == .Architecture {
        facade_right_x, facade_right_z = world_rotate_xz(0, 0, 1, 0, structure.rotation)
        facade_out_x, facade_out_z = world_rotate_xz(0, 0, 0, 1, structure.rotation)
        if render_root {
            secondary_strength = architecture.bougainvillea_secondary_leader_strength(vine_maturity)
        }
    }
    for point_index in 0 ..< len(vine_points) - 1 {
        segment_t := f32(point_index) / f32(len(vine_points) - 1)
        start_x := vine_local_x[point_index]
        end_x := vine_local_x[point_index + 1]
        middle_x := (start_x + end_x) * .5
        start_badness := world_climbing_leaf_stem_opening_badness(
            structure,
            start_x,
            vine_points[point_index].y - structure.base_y,
        )
        end_badness := world_climbing_leaf_stem_opening_badness(
            structure,
            end_x,
            vine_points[point_index + 1].y - structure.base_y,
        )
        middle_badness := world_climbing_leaf_stem_opening_badness(
            structure,
            middle_x,
            (vine_points[point_index].y + vine_points[point_index + 1].y) * .5 - structure.base_y,
        )
        needs_detour := max(start_badness, max(end_badness, middle_badness)) > .68
        segment_radius := woody_base_radius + (woody_tip_radius - woody_base_radius) * segment_t
        bark_value := .035 + f32((point_index + int(seed)) % 3) * .035
        segment_color :=
            point_index % 2 == 0 ? color_lerp(woody_color, {171, 128, 84, 255}, bark_value) : color_lerp(woody_color, {77, 55, 42, 255}, bark_value)
        if needs_detour {
            start_local_y := vine_points[point_index].y - structure.base_y
            end_local_y := vine_points[point_index + 1].y - structure.base_y
            detour_x := world_climbing_leaf_segment_detour_x(structure, start_x, start_local_y, end_x, end_local_y)
            detour := third_person.Vec3 {
                (vine_points[point_index].x + vine_points[point_index + 1].x) * .5,
                (vine_points[point_index].y + vine_points[point_index + 1].y) * .5,
                (vine_points[point_index].z + vine_points[point_index + 1].z) * .5,
            }
            detour.x += facade_right_x * (detour_x - middle_x) + facade_out_x * .08
            detour.z += facade_right_z * (detour_x - middle_x) + facade_out_z * .08
            middle_radius := segment_radius * .955
            world_tube_between(
                vine_points[point_index],
                detour,
                {0, 1, 0},
                segment_radius,
                middle_radius,
                segment_color,
            )
            world_tube_between(
                detour,
                vine_points[point_index + 1],
                {0, 1, 0},
                middle_radius,
                segment_radius * .91,
                segment_color,
            )
        } else {
            world_tube_between(
                vine_points[point_index],
                vine_points[point_index + 1],
                {0, 1, 0},
                segment_radius,
                segment_radius * .91,
                segment_color,
            )
        }
        if secondary_strength > 0 {
            // Mature bougainvillea is commonly multi-stemmed. Weave one
            // thinner leader around the routed trunk, converging at both ends
            // so it reads as a shared woody base rather than parallel piping.
            start_t := f32(point_index) / f32(len(vine_points) - 1)
            finish_t := f32(point_index + 1) / f32(len(vine_points) - 1)
            start_envelope := f32(math.sin(f64(start_t * math.PI)))
            finish_envelope := f32(math.sin(f64(finish_t * math.PI)))
            weave_amplitude := (.075 + vine_maturity * .085) * secondary_strength
            start_weave :=
                f32(math.sin(f64(f32(seed) * .071 + start_t * math.PI * 4.4))) * weave_amplitude * start_envelope
            finish_weave :=
                f32(math.sin(f64(f32(seed) * .071 + finish_t * math.PI * 4.4))) * weave_amplitude * finish_envelope
            start_depth := f32(math.cos(f64(f32(seed) * .071 + start_t * math.PI * 4.4))) * .045 * start_envelope
            finish_depth := f32(math.cos(f64(f32(seed) * .071 + finish_t * math.PI * 4.4))) * .045 * finish_envelope
            secondary_start_local_x := start_x + start_weave
            secondary_finish_local_x := end_x + finish_weave
            secondary_middle_x := (secondary_start_local_x + secondary_finish_local_x) * .5
            secondary_badness := max(
                world_climbing_leaf_stem_opening_badness(
                    structure,
                    secondary_start_local_x,
                    vine_points[point_index].y - structure.base_y,
                ),
                max(
                    world_climbing_leaf_stem_opening_badness(
                        structure,
                        secondary_finish_local_x,
                        vine_points[point_index + 1].y - structure.base_y,
                    ),
                    world_climbing_leaf_stem_opening_badness(
                        structure,
                        secondary_middle_x,
                        (vine_points[point_index].y + vine_points[point_index + 1].y) * .5 - structure.base_y,
                    ),
                ),
            )
            if secondary_badness <= .68 {
                secondary_start := vine_points[point_index]
                secondary_start.x += facade_right_x * start_weave + facade_out_x * start_depth
                secondary_start.z += facade_right_z * start_weave + facade_out_z * start_depth
                secondary_finish := vine_points[point_index + 1]
                secondary_finish.x += facade_right_x * finish_weave + facade_out_x * finish_depth
                secondary_finish.z += facade_right_z * finish_weave + facade_out_z * finish_depth
                secondary_radius := segment_radius * (.50 + secondary_strength * .12)
                secondary_color := color_lerp(segment_color, {76, 52, 39, 255}, .18)
                world_tube_between(
                    secondary_start,
                    secondary_finish,
                    {0, 1, 0},
                    secondary_radius,
                    secondary_radius * .88,
                    secondary_color,
                )
            }
        }
        if structure.kind == .Architecture && point_index > 0 {
            segment_previous_delta := vine_local_x[point_index] - vine_local_x[point_index - 1]
            next_delta := vine_local_x[point_index + 1] - vine_local_x[point_index]
            bend := math.abs(next_delta - segment_previous_delta)
            if bend > structure.width * .0045 && start_badness < .48 {
                // A subtle swollen knuckle rounds the join between the two
                // tapered tubes. Restrict it to visible bends so straight
                // leaders stay lean and vertex cost remains bounded.
                joint_radius := segment_radius * 1.04
                world_ellipsoid_rotated(
                    vine_points[point_index],
                    joint_radius,
                    joint_radius * 1.10,
                    joint_radius * .96,
                    structure.rotation,
                    woody_color,
                )
            }
        }
        if structure.kind == .Architecture &&
           detail_tier >= 2 &&
           point_index > 0 &&
           point_index % 3 == 2 &&
           start_badness < .42 {
            // Mature wall-trained bougainvillea needs sparse physical
            // attachment. A small iron eye and short jute tie make long
            // lateral leaders feel supported by the façade rather than
            // suspended in front of it.
            anchor_x, anchor_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                start_x,
                structure.depth * .5 + .07,
                structure.rotation,
            )
            anchor := third_person.Vec3{anchor_x, vine_points[point_index].y, anchor_z}
            guide_half_span := .24 + vine_maturity * .22
            guide_local_y := anchor.y - structure.base_y
            guide_left_x := start_x - guide_half_span
            guide_right_x := start_x + guide_half_span
            guide_badness := max(
                world_climbing_leaf_stem_opening_badness(structure, guide_left_x, guide_local_y),
                max(
                    world_climbing_leaf_stem_opening_badness(structure, start_x, guide_local_y),
                    world_climbing_leaf_stem_opening_badness(structure, guide_right_x, guide_local_y),
                ),
            )
            if guide_badness < .42 {
                // Eyelets work as a small tensioned training system rather
                // than isolated pegs. Keep each wire span short and test both
                // ends against openings so it stays on masonry instead of
                // crossing shutters or glass.
                guide_left_world_x, guide_left_world_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    guide_left_x,
                    structure.depth * .5 + .065,
                    structure.rotation,
                )
                guide_right_world_x, guide_right_world_z := world_rotate_xz(
                    structure.center_x,
                    structure.center_z,
                    guide_right_x,
                    structure.depth * .5 + .065,
                    structure.rotation,
                )
                world_tube_between(
                    {guide_left_world_x, anchor.y, guide_left_world_z},
                    {guide_right_world_x, anchor.y, guide_right_world_z},
                    {0, 1, 0},
                    .011,
                    .011,
                    {76, 78, 72, 255},
                )
            }
            world_tube_between(anchor, vine_points[point_index], {0, 1, 0}, .018, .018, {117, 96, 67, 255})
            world_box_rotated({anchor.x, anchor.y, anchor.z}, {.11, .11, .045}, structure.rotation, {72, 74, 68, 255})
        }
    }
    if structure.kind == .Architecture && render_root {
        basal_count := architecture.bougainvillea_basal_shoot_count(vine_maturity)
        basal_indices := [2]int{1, 3}
        root_side := root_local_x < 0 ? f32(-1) : f32(1)
        for basal in 0 ..< basal_count {
            point_index := basal_indices[basal]
            node := vine_points[point_index]
            node_local_x := vine_local_x[point_index]
            reach := structure.width * (.022 + f32(basal) * .006)
            shoot_local_x := node_local_x + root_side * reach
            shoot_local_y := node.y - structure.base_y + .16 + f32(basal) * .08
            if world_climbing_leaf_stem_opening_badness(structure, shoot_local_x, shoot_local_y) > .48 {
                continue
            }
            shoot_x, shoot_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                shoot_local_x,
                surface_z + .18,
                structure.rotation,
            )
            shoot_end := third_person.Vec3{shoot_x, structure.base_y + shoot_local_y, shoot_z}
            basal_color := color_lerp({73, 103, 61, 255}, {105, 74, 51, 255}, vine_maturity)
            world_tube_between(
                node,
                shoot_end,
                {0, 1, 0},
                .027 + vine_maturity * .009,
                .018 + vine_maturity * .005,
                basal_color,
            )
            card_width := (.58 + vine_maturity * .18) * (1 - f32(basal) * .10)
            card_height := card_width * .82
            card_center := shoot_end
            card_center.y += card_height * .30
            footprint_clear := true
            for footprint_x in -1 ..= 1 {
                for footprint_y in 0 ..= 2 {
                    sample_x := shoot_local_x + f32(footprint_x) * card_width * .31
                    sample_y := shoot_local_y + f32(footprint_y) * card_height * .28
                    if world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y) > .48 {
                        footprint_clear = false
                    }
                }
            }
            if footprint_clear {
                tile := int((plant_seed + u32(basal * 11)) % 2) * 2
                roll := root_side * (.018 + f32(basal) * .007)
                world_bougainvillea_card(card_center, card_width, card_height, tile, root_side < 0, roll, .93, true)
            }
        }
    }
    if structure.kind == .Architecture && detail_tier >= 2 && vine_maturity > .38 {
        // Bougainvillea climbs with sparse hooked thorns rather than tendrils.
        // Place only a few on established woody nodes; they should reward a
        // close façade view without turning the stem into a saw blade.
        thorn_indices := [4]int{4, 7, 10, 13}
        thorn_count := architecture.bougainvillea_thorn_count(vine_maturity, len(thorn_indices))
        thorn_facade_right_x, thorn_facade_right_z := world_rotate_xz(0, 0, 1, 0, structure.rotation)
        thorn_facade_out_x, thorn_facade_out_z := world_rotate_xz(0, 0, 0, 1, structure.rotation)
        for thorn in 0 ..< thorn_count {
            point_index := thorn_indices[len(thorn_indices) - thorn_count + thorn]
            thorn_local_y := vine_points[point_index].y - structure.base_y
            if world_climbing_leaf_stem_opening_badness(structure, vine_local_x[point_index], thorn_local_y) > .48 {
                continue
            }
            side := ((thorn + int(seed)) & 1) == 0 ? f32(1) : f32(-1)
            thorn_length := .11 + vine_maturity * .07 + f32(thorn % 2) * .025
            root := vine_points[point_index]
            bend := third_person.Vec3 {
                root.x + thorn_facade_right_x * side * thorn_length * .68 + thorn_facade_out_x * .045,
                root.y + thorn_length * .32,
                root.z + thorn_facade_right_z * side * thorn_length * .68 + thorn_facade_out_z * .045,
            }
            tip := third_person.Vec3 {
                bend.x + thorn_facade_right_x * side * thorn_length * .32 + thorn_facade_out_x * .025,
                bend.y - thorn_length * .24,
                bend.z + thorn_facade_right_z * side * thorn_length * .32 + thorn_facade_out_z * .025,
            }
            thorn_color := color_lerp({84, 111, 64, 255}, {112, 77, 51, 255}, vine_maturity)
            thorn_radius := .007 + vine_maturity * .005
            world_tube_between(root, bend, {0, 1, 0}, thorn_radius, thorn_radius * .62, thorn_color)
            world_tube_between(bend, tip, {0, 1, 0}, thorn_radius * .62, .0015, thorn_color)
        }
    }
    if structure.kind == .Architecture && detail_tier >= 2 {
        // Established wall plants are cut back repeatedly. A few short dead
        // ends with pale cut faces interrupt the mathematically continuous
        // tube and record that maintenance history without making the plant
        // look damaged or leafless.
        stub_indices := [3]int{5, 8, 11}
        stub_count := architecture.bougainvillea_pruned_stub_count(vine_maturity)
        stub_facade_right_x, stub_facade_right_z := world_rotate_xz(0, 0, 1, 0, structure.rotation)
        stub_facade_out_x, stub_facade_out_z := world_rotate_xz(0, 0, 0, 1, structure.rotation)
        for stub in 0 ..< stub_count {
            point_index := stub_indices[stub]
            node := vine_points[point_index]
            node_local_x := vine_local_x[point_index]
            side := (stub + int(seed)) % 2 == 0 ? f32(1) : f32(-1)
            stub_length := .13 + f32(stub) * .025 + vine_maturity * .035
            tip := third_person.Vec3 {
                node.x + stub_facade_right_x * side * stub_length + stub_facade_out_x * .025,
                node.y + .055 + f32(stub % 2) * .025,
                node.z + stub_facade_right_z * side * stub_length + stub_facade_out_z * .025,
            }
            tip_local_x := node_local_x + side * stub_length
            if max(
                   world_climbing_leaf_stem_opening_badness(structure, node_local_x, node.y - structure.base_y),
                   world_climbing_leaf_stem_opening_badness(structure, tip_local_x, tip.y - structure.base_y),
               ) >
               .48 {
                continue
            }
            stub_radius := (.025 + vine_maturity * .009) * (1 - f32(stub) * .08)
            stub_color := color_lerp({104, 76, 52, 255}, {128, 91, 59, 255}, vine_maturity)
            world_tube_between(node, tip, {0, 1, 0}, stub_radius, stub_radius * .84, stub_color)
            cut_color := color_lerp({185, 143, 91, 255}, {220, 181, 119, 255}, vine_maturity)
            world_ellipsoid_rotated(
                tip,
                stub_radius * .93,
                stub_radius * .82,
                stub_radius * .34,
                structure.rotation,
                cut_color,
            )
        }
    }
    if structure.kind == .Architecture && vine_maturity > .28 {
        // Established bougainvillea continually throws short renewal shoots
        // from its older framework. These small, leaf-only tufts bridge the
        // long woody trunk into the flowering crown without making the whole
        // façade uniformly bushy.
        renewal_indices := [4]int{4, 6, 8, 10}
        renewal_count := min(1 + int((vine_maturity - .28) * 3.0), len(renewal_indices))
        for renewal in 0 ..< renewal_count {
            point_index := renewal_indices[len(renewal_indices) - renewal_count + renewal]
            node := vine_points[point_index]
            node_x := vine_local_x[point_index]
            // Grow toward the nearest building edge. This keeps renewal
            // foliage on the masonry margin instead of sending alternating
            // tufts back across the window field.
            side := node_x >= 0 ? f32(1) : f32(-1)
            reach := structure.width * (.024 + f32(renewal % 2) * .007)
            shoot_local_x := node_x + side * reach
            shoot_y := node.y + .20 + f32(renewal % 2) * .10
            // Use the exact opening rectangles here. The broader crown
            // avoidance field is intentionally conservative and suppresses
            // nearly every small shoot along a windowed façade.
            if world_climbing_leaf_stem_opening_badness(structure, shoot_local_x, shoot_y - structure.base_y) > .52 {
                continue
            }
            shoot_x, shoot_z := world_rotate_xz(
                structure.center_x,
                structure.center_z,
                shoot_local_x,
                surface_z + .16,
                structure.rotation,
            )
            shoot_end := third_person.Vec3{shoot_x, shoot_y, shoot_z}
            world_tube_between(
                node,
                shoot_end,
                {0, 1, 0},
                .030 + vine_maturity * .010,
                .021 + vine_maturity * .006,
                color_lerp({73, 103, 61, 255}, {105, 74, 51, 255}, vine_maturity),
            )
            card_width := (.62 + vine_maturity * .28) * (1 - f32(renewal) * .07)
            card_height := card_width * .76
            card_center := third_person.Vec3{shoot_end.x, shoot_end.y + card_height * .28, shoot_end.z}
            footprint_clear := true
            for footprint_x in -1 ..= 1 {
                for footprint_y in 0 ..= 2 {
                    sample_x := shoot_local_x + f32(footprint_x) * card_width * .30
                    sample_y := card_center.y - structure.base_y + f32(footprint_y - 1) * card_height * .28
                    if world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y) > .52 {
                        footprint_clear = false
                    }
                }
            }
            if footprint_clear {
                tile := int((seed + u32(renewal * 5)) % 4)
                // Upright source tiles suit these young shoots better than
                // the long lateral sprays used in the terminal crown.
                tile -= tile % 2
                renewal_roll := f32(int((seed + u32(renewal * 17)) % 7) - 3) * .014
                world_bougainvillea_card(card_center, card_width, card_height, tile, side < 0, renewal_roll, .94, true)
            }
        }
    }
    // Bougainvillea carries most of its visual weight high on an exposed,
    // woody framework. Rounded terrain growth keeps the more even distribution.
    leaf_point_indices := structure.kind == .Architecture ? [6]int{7, 9, 11, 13, 14, 15} : [6]int{2, 5, 7, 10, 12, 15}
    crown_side := seed % 2 == 0 ? f32(1) : f32(-1)
    training_habit := architecture.bougainvillea_training_habit(plant_seed)
    for leaf_index in 0 ..< len(leaf_point_indices) {
        if structure.kind == .Architecture {
            active_branches := architecture.bougainvillea_active_branch_count(vine_maturity, len(leaf_point_indices))
            // Juveniles invest in their newest terminal shoots first. Lower
            // and counter-branches appear progressively as the plant matures,
            // avoiding a six-rung ladder of uniformly tiny leaf tufts.
            if leaf_index < len(leaf_point_indices) - active_branches do continue
        }
        point_index := leaf_point_indices[leaf_index]
        node_t := f32(point_index) / f32(len(vine_points) - 1)
        base := vine_points[point_index]
        leaf_side := leaf_index % 2 == 0 ? f32(1) : f32(-1)
        if structure.kind == .Architecture && leaf_index >= 3 {
            if training_habit == 0 {
                // Fan-trained plants divide their upper leaders across both
                // sides of the trunk, producing a broad, architectural crown.
                leaf_side = (leaf_index + int(seed)) % 2 == 0 ? f32(1) : f32(-1)
            } else {
                // Wind-trained plants favor one side with a single
                // counter-branch, preserving the exposed coastal silhouette.
                leaf_side = crown_side
                if leaf_index == 4 do leaf_side = -crown_side
            }
        }
        node_x := vine_local_x[point_index]
        branch_reach := structure.width * (.045 + node_t * .025)
        branch_rise := .08 + f32(leaf_index % 2) * .05
        if structure.kind == .Architecture {
            // Atlas clumps already paint a substantial woody extension from
            // their attachment anchor. Keep the procedural support compact so
            // the two systems do not double the reach into bare, lollipop-like
            // limbs before foliage begins.
            branch_reach = structure.width * (.018 + node_t * .038)
            branch_rise = .08 + node_t * .38 + f32(leaf_index % 2) * .12
        }
        branch_x, branch_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            node_x + leaf_side * branch_reach,
            surface_z + .16,
            structure.rotation,
        )
        branch_end := third_person.Vec3{branch_x, min(base.y + branch_rise, stem_end + 1.8), branch_z}
        opening_badness := world_climbing_leaf_opening_badness(
            structure,
            node_x + leaf_side * branch_reach,
            branch_end.y - structure.base_y,
        )
        // Keep a clean visual corridor over doors and windows. The stem can
        // continue past the opening, but branch/lobe geometry is omitted when
        // it would materially obscure the architectural opening.
        if opening_badness > .72 do continue
        branch_color := rl.Color{62, 108, 55, 255}
        branch_base_radius := f32(.036)
        branch_tip_radius := f32(.032)
        if structure.kind == .Architecture {
            wood_age := clamp((vine_maturity - .06) / .50, 0, 1)
            wood_age = wood_age * wood_age * (3 - 2 * wood_age)
            branch_color = color_lerp({73, 103, 61, 255}, {105, 74, 51, 255}, wood_age)
            branch_base_radius = .034 + vine_maturity * .022
            branch_tip_radius = .027 + vine_maturity * .012
            // A restrained collar hides the tube seam and gives mature
            // branches the swollen node characteristic of woody climbers.
            collar_radius := branch_base_radius * (1.05 + vine_maturity * .20)
            world_ellipsoid_rotated(
                base,
                collar_radius,
                collar_radius * 1.16,
                collar_radius * .88,
                structure.rotation,
                branch_color,
            )
        }
        world_tube_between(base, branch_end, {0, 1, 0}, branch_base_radius, branch_tip_radius, branch_color)

        if structure.kind == .Architecture && vine_maturity > .24 {
            // A mature lateral should not read as a bare support rod ending in
            // one atlas billboard. Add a restrained, leaf-only spray partway
            // along the branch. It bridges the woody framework into the crown
            // while leaving the terminal bracts visually dominant.
            connector_amount := .52 + f32((seed + u32(leaf_index * 19)) % 3) * .08
            connector_center := third_person.Vec3 {
                base.x + (branch_end.x - base.x) * connector_amount,
                base.y + (branch_end.y - base.y) * connector_amount,
                base.z + (branch_end.z - base.z) * connector_amount,
            }
            connector_local_x := node_x + leaf_side * branch_reach * connector_amount
            connector_local_y := connector_center.y - structure.base_y
            connector_badness := world_climbing_leaf_opening_badness(structure, connector_local_x, connector_local_y)
            if connector_badness < .58 {
                outward_x, outward_z := world_rotate_xz(0, 0, 0, .11, structure.rotation)
                connector_center.x += outward_x
                connector_center.z += outward_z
                connector_scale := (.48 + vine_maturity * .22) * (1 - connector_badness * .34)
                connector_tile := int((seed + u32(leaf_index * 29)) % 4)
                connector_mirrored := leaf_side < 0
                connector_roll := leaf_side * (.018 + f32(leaf_index % 2) * .009)
                world_bougainvillea_card(
                    connector_center,
                    connector_scale * 1.06,
                    connector_scale * .82,
                    connector_tile,
                    connector_mirrored,
                    connector_roll,
                    .925,
                )
            }
        }

        // Rounded terrain growth and wall-trained bougainvillea need different
        // silhouettes. They share routing, but not their main foliage mass.
        cluster_structure := structure
        cluster_structure.base_y = branch_end.y - .72
        cluster_structure.seed = seed + u32(leaf_index * 41)
        cluster_x := node_x + leaf_side * branch_reach
        attachment_x, attachment_z := world_rotate_xz(
            structure.center_x,
            structure.center_z,
            cluster_x,
            surface_z + .16,
            structure.rotation,
        )
        // Average a small attachment patch instead of using one point. On
        // rounded rocks this smooths the lobe orientation; on façades it
        // preserves a stable outward-facing plane across the whole cluster.
        normal_sum := third_person.Vec3{}
        for normal_sample in -2 ..= 2 {
            sample_x := cluster_x + f32(normal_sample) * .12
            sample_z := surface_z + .16 + f32(math.sin(f64(f32(normal_sample) * .9))) * .06
            normal_local := linalg.normalize0(third_person.Vec3{sample_x, 0, sample_z})
            normal_world_x, normal_world_z := world_rotate_xz(0, 0, normal_local.x, normal_local.z, structure.rotation)
            normal_sum.x += normal_world_x
            normal_sum.z += normal_world_z
        }
        average_normal := linalg.normalize0(normal_sum)
        surface_rotation := -math.atan2(average_normal.x, average_normal.z)
        cluster_structure.rotation = surface_rotation
        offset_x := attachment_x - structure.center_x
        offset_z := attachment_z - structure.center_z
        surface_cosine, surface_sine := math.cos(surface_rotation), math.sin(surface_rotation)
        lobe_local_x := offset_x * surface_cosine + offset_z * surface_sine
        lobe_local_z := -offset_x * surface_sine + offset_z * surface_cosine
        world_tube_between(
            branch_end,
            {attachment_x, branch_end.y + .12, attachment_z},
            {0, 1, 0},
            .052,
            .045,
            {58, 101, 53, 255},
        )
        lobe_scale := 1 - opening_badness * .42
        crown_scale := f32(1)
        if structure.kind == .Architecture {
            // Density is also maturity: a lightly painted patch begins as a
            // sparse leafy juvenile, while sustained density earns the broad,
            // flower-heavy crown of an established bougainvillea.
            maturity := architecture.bougainvillea_maturity(growth_density)
            maturity_scale := .52 + maturity * .48
            crown_scale = (.38 + node_t * 1.68) * maturity_scale
            if training_habit == 0 {
                if leaf_index >= 3 do crown_scale *= 1.06
            } else if leaf_side == crown_side {
                crown_scale *= 1.12
            }
        }
        tangent := third_person.Vec3{-average_normal.z, 0, average_normal.x}
        cluster_center := third_person.Vec3 {
            attachment_x + average_normal.x * .32,
            branch_end.y + .10,
            attachment_z + average_normal.z * .32,
        }
        if structure.kind == .Architecture {
            maturity := architecture.bougainvillea_maturity(growth_density)
            flowering := architecture.bougainvillea_branch_flowering(maturity, node_t, seed, leaf_index)
            // Even atlas columns are upright clumps; odd columns are lateral
            // sprays. Continue the procedural branch's rise/reach instead of
            // choosing a contradictory silhouette at random.
            lateral_shape := math.abs(branch_reach) > branch_rise * .92
            variation := int((seed + u32(leaf_index * 7)) % 2) * 2 + (lateral_shape ? 1 : 0)
            tile := variation
            flower_base := architecture.bougainvillea_flower_tile_base(architecture.bougainvillea_palette(plant_seed))
            if flowering {
                tile = flower_base + variation
            }
            card_width := (2.34 + f32(variation % 2) * .20) * crown_scale * lobe_scale
            card_height := (1.84 + f32((variation + 1) % 3) * .14) * crown_scale * lobe_scale
            // Avoid lining every atlas card up on the routed stem. Keep the
            // silhouette shift in façade-local space so the opening test can
            // evaluate the card's actual final horizontal placement.
            silhouette_step := f32(int((seed + u32(leaf_index * 11)) % 5) - 2)
            silhouette_shift := silhouette_step * card_width * .045
            cluster_center.y += silhouette_step * card_height * .035

            // The procedural attachment can be safely on masonry while an
            // anchored atlas clump still extends across nearby glass. Search
            // a few short offsets along the wall before shrinking or omitting
            // the clump; this preserves foliage while favoring clear masonry.
            footprint_offsets := [5]f32{0, -.28, .28, -.48, .48}
            best_footprint_score := f32(1.0e20)
            footprint_badness := f32(1)
            clearance_shift := f32(0)
            attachment_local_y := cluster_center.y - structure.base_y
            for footprint_offset in footprint_offsets {
                candidate_shift := footprint_offset * card_width
                candidate_badness := f32(0)
                // Atlas roots range from bottom-center to a lower corner, so
                // sample a conservative envelope around the anchor rather
                // than only the card's central 60 percent.
                for footprint_x in -2 ..= 2 {
                    for footprint_y in 0 ..= 3 {
                        sample_x :=
                            cluster_x + silhouette_shift + candidate_shift + f32(footprint_x) * card_width * .34
                        sample_y := attachment_local_y + f32(footprint_y) * card_height * .30
                        candidate_badness = max(
                            candidate_badness,
                            world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y),
                        )
                    }
                }
                candidate_score := candidate_badness + math.abs(footprint_offset) * .05
                if candidate_score < best_footprint_score {
                    best_footprint_score = candidate_score
                    footprint_badness = candidate_badness
                    clearance_shift = candidate_shift
                }
            }
            if footprint_badness > .90 {
                // Sparse juvenile growth is better with one fewer clump than
                // with a billboard visibly pasted over a window.
                continue
            } else if footprint_badness > .72 {
                card_width *= .62
                card_height *= .62
            } else if footprint_badness > .58 {
                card_width *= .80
                card_height *= .80
            }
            card_facade_right_x, card_facade_right_z := world_rotate_xz(0, 0, 1, 0, structure.rotation)
            resolved_shift := silhouette_shift + clearance_shift
            cluster_center.x += card_facade_right_x * resolved_shift
            cluster_center.z += card_facade_right_z * resolved_shift
            if math.abs(resolved_shift) > card_width * .12 {
                // Preserve the visual connection when the safest masonry
                // pocket moves the atlas anchor away from the original node.
                world_tube_between(
                    branch_end,
                    cluster_center,
                    {0, 1, 0},
                    branch_tip_radius * .72,
                    branch_tip_radius * .42,
                    branch_color,
                )
            }
            mirrored := (leaf_index + int(seed)) % 2 == 0
            card_camera := perspective_camera(world_renderer.editor.camera_pose, 1.35)
            branch_delta := third_person.Vec3{branch_end.x - base.x, branch_end.y - base.y, branch_end.z - base.z}
            if lateral_shape {
                // Unmirrored lateral tiles grow from their left anchor toward
                // screen-right. Mirror when the supporting branch reaches
                // screen-left so the painted continuation grows away from the
                // trunk in either view direction.
                mirrored = linalg.dot(branch_delta, card_camera.right) < 0
            }
            card_roll := f32(int((seed + u32(leaf_index * 17)) % 7) - 3) * .016
            card_value := .965 + f32((seed + u32(leaf_index * 23)) % 4) * .012
            if flowering {
                card_value = architecture.bougainvillea_bract_value(
                    maturity,
                    node_t,
                    int((seed + u32(leaf_index * 23)) % 4),
                )
            }
            if flowering && maturity > .34 {
                // Bougainvillea color comes from papery bracts carried over a
                // leafy scaffold. Let a smaller green spray show through the
                // bloom card's transparent gaps and around one lower edge so
                // dense crowns retain botanical structure instead of reading
                // as an uninterrupted patch of flower color.
                foliage_tile := (variation + int((seed + u32(leaf_index * 13)) % 2) * 2) % 4
                foliage_center := cluster_center
                foliage_center.x +=
                    tangent.x * card_width * (mirrored ? f32(.10) : f32(-.10)) - average_normal.x * .045
                foliage_center.y -= card_height * .13
                foliage_center.z +=
                    tangent.z * card_width * (mirrored ? f32(.10) : f32(-.10)) - average_normal.z * .045
                world_bougainvillea_card(
                    foliage_center,
                    card_width * (.60 + maturity * .08),
                    card_height * (.56 + maturity * .08),
                    foliage_tile,
                    !mirrored,
                    -card_roll * .72,
                    .91,
                )
            }
            world_bougainvillea_card(cluster_center, card_width, card_height, tile, mirrored, card_roll, card_value)
            resting_leaf_index := 3 + int(plant_seed % 2)
            if crown_detail_fade > .02 && flowering && maturity > .62 && leaf_index == resting_leaf_index {
                // Even at peak bloom, one sheltered crown pocket remains
                // leaf-dominant. Place a compact green spray just proud of a
                // flower card so the canopy has a readable rest between large
                // color masses instead of becoming one uniform neon shelf.
                resting_center := cluster_center
                resting_side := mirrored ? f32(1) : f32(-1)
                resting_center.x += tangent.x * card_width * resting_side * .20 + average_normal.x * .09
                resting_center.y -= card_height * .12
                resting_center.z += tangent.z * card_width * resting_side * .20 + average_normal.z * .09
                resting_tile := (variation + 3) % 4
                world_bougainvillea_card(
                    resting_center,
                    card_width * .40 * crown_detail_fade,
                    card_height * .38 * crown_detail_fade,
                    resting_tile,
                    !mirrored,
                    -card_roll * .58,
                    .93,
                    false,
                    resting_side * .085,
                )
            }
            if crown_detail_fade > .02 && maturity > .52 && node_t > .68 && (leaf_index + int(seed)) % 2 == 0 {
                // A façade-trained plant is shallow, but not planar. Push a
                // restrained secondary spray away from the wall and connect
                // it with a real twig so the crown gains parallax as the
                // camera moves without turning into a spherical shrub.
                depth_amount := .20 + maturity * .26
                depth_center := cluster_center
                depth_center.x += average_normal.x * depth_amount - tangent.x * card_width * .08
                depth_center.y -= card_height * (.08 + f32(leaf_index % 2) * .04)
                depth_center.z += average_normal.z * depth_amount - tangent.z * card_width * .08
                world_tube_between(
                    branch_end,
                    depth_center,
                    {0, 1, 0},
                    branch_tip_radius * .78 * crown_detail_fade,
                    branch_tip_radius * .48 * crown_detail_fade,
                    branch_color,
                )
                depth_tile := tile
                if flowering {
                    depth_tile = flower_base + (variation + 1) % 4
                } else {
                    depth_tile = (tile + 2) % 4
                }
                depth_mirrored := !mirrored
                world_bougainvillea_card(
                    depth_center,
                    card_width * (.46 + maturity * .10) * crown_detail_fade,
                    card_height * (.44 + maturity * .10) * crown_detail_fade,
                    depth_tile,
                    depth_mirrored,
                    card_roll * .58,
                    card_value * .955,
                    false,
                    depth_mirrored ? f32(-.13) : f32(.13),
                )
            }
            terminal_emphasis :=
                training_habit == 0 ? leaf_index >= len(leaf_point_indices) - 2 : leaf_side == crown_side
            if node_t > .76 && terminal_emphasis {
                echo_tile := tile
                if flowering {
                    echo_tile = flower_base + (variation + 2) % 4
                } else {
                    echo_tile = (tile + 2) % 4
                }
                echo_center := cluster_center
                echo_center.x += tangent.x * card_width * .24
                echo_center.y -= card_height * .18
                echo_center.z += tangent.z * card_width * .24
                echo_mirrored := linalg.dot(tangent, card_camera.right) < 0
                world_bougainvillea_card(
                    echo_center,
                    card_width * .62,
                    card_height * .60,
                    echo_tile,
                    echo_mirrored,
                    -card_roll * .84,
                    card_value * .98,
                    false,
                    echo_mirrored ? f32(-.075) : f32(.075),
                )
            }
            if flowering && node_t > .76 && terminal_emphasis {
                // Mature terminal sprays arch outward and then hang under
                // their own weight. A short descending chain breaks the
                // crown's horizontal shelf silhouette and gives the papery
                // bracts the characteristic bougainvillea cascade.
                cascade_count := architecture.bougainvillea_cascade_count(maturity)
                cascade_side := mirrored ? f32(-1) : f32(1)
                cascade_parent := cluster_center
                for cascade in 0 ..< cascade_count {
                    cascade_scale := 1 - f32(cascade) * .18
                    cascade_width := card_width * .43 * cascade_scale
                    cascade_height := card_height * .50 * cascade_scale
                    lateral_drop := cascade_side * card_width * (.14 + f32(cascade) * .10)
                    vertical_drop := card_height * (.34 + f32(cascade) * .30)
                    cascade_local_x := cluster_x + resolved_shift + lateral_drop
                    cascade_local_y := cluster_center.y - structure.base_y - vertical_drop
                    cascade_badness := f32(0)
                    for footprint_x in -1 ..= 1 {
                        for footprint_y in 0 ..= 2 {
                            sample_x := cascade_local_x + f32(footprint_x) * cascade_width * .34
                            sample_y := cascade_local_y + f32(footprint_y) * cascade_height * .32
                            cascade_badness = max(
                                cascade_badness,
                                world_climbing_leaf_stem_opening_badness(structure, sample_x, sample_y),
                            )
                        }
                    }
                    if cascade_badness > .72 do continue
                    cascade_center := cluster_center
                    cascade_center.x += tangent.x * lateral_drop + average_normal.x * (.10 + f32(cascade) * .06)
                    cascade_center.y -= vertical_drop
                    cascade_center.z += tangent.z * lateral_drop + average_normal.z * (.10 + f32(cascade) * .06)
                    world_tube_between(
                        cascade_parent,
                        cascade_center,
                        {0, 1, 0},
                        branch_tip_radius * (.54 - f32(cascade) * .08),
                        branch_tip_radius * .28,
                        branch_color,
                    )
                    cascade_tile := flower_base + (variation + cascade + 1) % 4
                    world_bougainvillea_card(
                        cascade_center,
                        cascade_width,
                        cascade_height,
                        cascade_tile,
                        cascade % 2 == 0 ? !mirrored : mirrored,
                        card_roll * .45 + cascade_side * .022,
                        card_value * (.985 - f32(cascade) * .018),
                    )
                    cascade_parent = cascade_center
                }
            }
        } else {
            world_foliage_lobe(
                cluster_structure,
                lobe_local_x,
                lobe_local_z,
                (1.52 + f32((seed + u32(leaf_index)) % 3) * .14) * lobe_scale * crown_scale,
                .86 * crown_scale,
                (1.42 + f32((seed + u32(leaf_index * 3)) % 3) * .14) * lobe_scale * crown_scale,
                0,
                false,
                1 + int((seed + u32(leaf_index)) % 3),
                0,
                false,
            )
        }
        if structure.kind == .Architecture do continue
        // Camera-facing sprays break the edge of both foliage treatments.
        spray_scale := (.74 + f32((seed + u32(leaf_index)) % 3) * .09) * crown_scale
        world_foliage_card(
            {cluster_center.x + tangent.x * .14, cluster_center.y + .05, cluster_center.z + tangent.z * .14},
            spray_scale,
            spray_scale * .86,
            leaf_index * 5 + 7,
            world_foliage_vertex_color(3, 1 + int((seed + u32(leaf_index)) % 3)),
            leaf_index % 2 == 0,
        )
        world_foliage_card(
            {
                cluster_center.x - tangent.x * .18 + average_normal.x * .08,
                cluster_center.y - .08,
                cluster_center.z - tangent.z * .18 + average_normal.z * .08,
            },
            spray_scale * .68,
            spray_scale * .62,
            leaf_index * 7 + 3,
            world_foliage_vertex_color(2, 1 + int((seed + u32(leaf_index + 1)) % 3)),
            leaf_index % 2 != 0,
        )
        accent_count := structure.kind == .Architecture ? 4 : 3
        for leaf_accent in 0 ..< accent_count {
            accent_side := leaf_accent == 1 ? f32(-1) : f32(1)
            accent_offset := (f32(leaf_accent) - f32(accent_count - 1) * .5) * .24 * crown_scale
            accent_center := third_person.Vec3 {
                cluster_center.x + tangent.x * accent_offset + average_normal.x * (.10 + f32(leaf_accent % 2) * .05),
                cluster_center.y + f32(leaf_accent - 1) * .16,
                cluster_center.z + tangent.z * accent_offset + average_normal.z * (.10 + f32(leaf_accent % 2) * .05),
            }
            accent_width := (.22 + f32(leaf_accent % 2) * .04) * crown_scale
            accent_height := .10 * crown_scale
            accent_color := leaf_accent == 1 ? rl.Color{93, 151, 70, 255} : rl.Color{76, 135, 65, 255}
            if structure.kind == .Architecture {
                world_tapered_disc_depth_rotated(
                    accent_center,
                    accent_width,
                    accent_height,
                    accent_width * .78,
                    accent_height * .82,
                    .035,
                    surface_rotation + accent_side * .12,
                    accent_color,
                )
            } else {
                world_ellipsoid_rotated(
                    accent_center,
                    accent_width,
                    accent_height,
                    (.14 + f32(leaf_accent) * .015) * crown_scale,
                    surface_rotation + accent_side * .12,
                    accent_color,
                )
            }
        }
        flowering := (seed + u32(leaf_index * 5)) % 3 == 0
        if structure.kind == .Architecture {
            flowering = node_t > .58 && (seed + u32(leaf_index * 5)) % 4 != 0
        }
        if flowering {
            petal_count := structure.kind == .Architecture ? 36 : 3
            flower_palette := int(seed % 3)
            for petal in 0 ..< petal_count {
                flower_index := petal
                bract_index := 0
                flower_count := petal_count
                if structure.kind == .Architecture {
                    flower_index = petal / 3
                    bract_index = petal % 3
                    flower_count = petal_count / 3
                }
                petal_angle := f32(flower_index) * 2.399963
                petal_radius := (.11 + f32(petal % 4) * .09) * crown_scale
                if structure.kind == .Architecture {
                    petal_radius =
                        (.08 + f32(math.sqrt(f64(f32(flower_index + 1) / f32(flower_count)))) * .62) * crown_scale
                }
                bloom_center := third_person.Vec3 {
                    cluster_center.x +
                    tangent.x * f32(math.cos(f64(petal_angle))) * petal_radius +
                    average_normal.x * (.20 + f32(petal % 2) * .05),
                    cluster_center.y + .12 + f32(math.sin(f64(petal_angle))) * petal_radius * .72,
                    cluster_center.z +
                    tangent.z * f32(math.cos(f64(petal_angle))) * petal_radius +
                    average_normal.z * (.20 + f32(petal % 2) * .05),
                }
                bloom_color := rl.Color{238, 121, 151, 255}
                switch flower_palette {
                case 0:
                    if petal % 3 == 0 {
                        bloom_color = {226, 90, 134, 255}
                    } else if petal % 3 == 1 {
                        bloom_color = {202, 57, 111, 255}
                    }
                case 1:
                    bloom_color = {245, 142, 112, 255}
                    if petal % 3 == 0 {
                        bloom_color = {231, 98, 82, 255}
                    } else if petal % 3 == 1 {
                        bloom_color = {202, 65, 70, 255}
                    }
                case 2:
                    bloom_color = {220, 123, 181, 255}
                    if petal % 3 == 0 {
                        bloom_color = {192, 78, 158, 255}
                    } else if petal % 3 == 1 {
                        bloom_color = {153, 57, 136, 255}
                    }
                }
                bloom_width := .14 * crown_scale
                bloom_height := .10 * crown_scale
                if structure.kind == .Architecture {
                    // Bougainvillea color comes from thin, pointed paper
                    // bracts rather than round flowers. Rotate each triangle
                    // in the wall plane and draw both faces.
                    bloom_width = .15 * crown_scale
                    bloom_height = .112 * crown_scale
                    bract_rotation := f32(bract_index) * math.PI * 2 / 3 + f32(seed % 11) * .19
                    direction_x := tangent.x * f32(math.cos(f64(bract_rotation)))
                    direction_y := f32(math.sin(f64(bract_rotation)))
                    direction_z := tangent.z * f32(math.cos(f64(bract_rotation)))
                    perpendicular_x := tangent.x * -f32(math.sin(f64(bract_rotation)))
                    perpendicular_y := f32(math.cos(f64(bract_rotation)))
                    perpendicular_z := tangent.z * -f32(math.sin(f64(bract_rotation)))
                    bract_tip := third_person.Vec3 {
                        bloom_center.x + direction_x * bloom_height,
                        bloom_center.y + direction_y * bloom_height,
                        bloom_center.z + direction_z * bloom_height,
                    }
                    bract_left := third_person.Vec3 {
                        bloom_center.x - direction_x * bloom_height * .58 - perpendicular_x * bloom_width,
                        bloom_center.y - direction_y * bloom_height * .58 - perpendicular_y * bloom_width,
                        bloom_center.z - direction_z * bloom_height * .58 - perpendicular_z * bloom_width,
                    }
                    bract_right := third_person.Vec3 {
                        bloom_center.x - direction_x * bloom_height * .58 + perpendicular_x * bloom_width,
                        bloom_center.y - direction_y * bloom_height * .58 + perpendicular_y * bloom_width,
                        bloom_center.z - direction_z * bloom_height * .58 + perpendicular_z * bloom_width,
                    }
                    world_triangle(bract_tip, bract_left, bract_right, bloom_color)
                    world_triangle(bract_tip, bract_right, bract_left, bloom_color)
                    if bract_index == 2 {
                        flower_center := bloom_center
                        flower_center.x += average_normal.x * .018
                        flower_center.z += average_normal.z * .018
                        world_tapered_disc_depth_rotated(
                            flower_center,
                            .042 * crown_scale,
                            .034 * crown_scale,
                            .030 * crown_scale,
                            .026 * crown_scale,
                            .012,
                            surface_rotation,
                            {244, 218, 145, 255},
                        )
                    }
                } else {
                    world_ellipsoid_rotated(
                        bloom_center,
                        bloom_width,
                        bloom_height,
                        .12 * crown_scale,
                        surface_rotation,
                        bloom_color,
                    )
                }
            }
        }
        node_width := max(f32(.18), min(structure.width * .04, f32(.32)))
        node_color := leaf_index % 2 == 0 ? rl.Color{63, 117, 62, 255} : rl.Color{78, 136, 70, 255}
        if structure.kind == .Architecture {
            world_tapered_disc_depth_rotated(
                branch_end,
                node_width,
                .09,
                node_width * .72,
                .072,
                .035,
                surface_rotation,
                node_color,
            )
        } else {
            world_ellipsoid_rotated(branch_end, node_width, .09, .15, structure.rotation, node_color)
        }

    }
}

world_climbing_leaves_for_structure :: proc(
    editor: ^Editor,
    structure: terrain.Structure,
    structure_index: int,
) {
    if editor == nil do return
    eligible :=
        structure.kind == .Architecture ||
        structure.kind == .Rock ||
        structure.kind == .Spire ||
        structure.kind == .Mountain ||
        structure.kind == .Ridge ||
        structure.kind == .Cliff
    if !eligible do return
    density := architecture.bougainvillea_density_at_structure(&editor.project.climbing_leaf_density, structure)
    if density < .035 do return
    detail_tier := 2
    if structure.kind == .Architecture {
        dx := editor.camera_pose.position.x - structure.center_x
        dz := editor.camera_pose.position.z - structure.center_z
        detail_tier = architecture.bougainvillea_detail_tier(f32(math.sqrt(f64(dx * dx + dz * dz))))
    }
        capture_seed_enabled :=
            editor.capture_bougainvillea_seed_enabled && structure.id == editor.capture_bougainvillea_structure_id
        capture_seed := capture_seed_enabled ? editor.capture_bougainvillea_seed : u32(0)
        entry := &world_renderer.climbing_leaf_geometry_cache[structure_index]
        if entry.valid &&
           entry.structure == structure &&
           entry.density == density &&
           entry.detail_tier == detail_tier &&
           entry.capture_seed_enabled == capture_seed_enabled &&
           entry.capture_seed == capture_seed {
            append(&world_renderer.vertices, ..entry.world_vertices[:])
            append(&world_renderer.bougainvillea_vertices, ..entry.bougainvillea_vertices[:])
            return
        }
        world_first := len(world_renderer.vertices)
        bougainvillea_first := len(world_renderer.bougainvillea_vertices)
        // Compound buildings, laundry anchors, and climbing growth all share
        // the same frontmost rendered mass.
        growth_structure := architecture.architecture_frontage_structure(structure)
        // A painted patch should grow into a small colony of stems rather
        // than a single line; density controls the colony size continuously.
        vine_count := min(1 + int(density * 5.0), 4)
        if structure.kind == .Architecture {
            // Mature bougainvillea usually presents one woody plant with a
            // small number of leaders, not several unrelated ivy-like tracks.
            vine_count = min(1 + int(density * 1.8), 2)
        }
        height_fraction := .50 + density * .30
        if structure.kind == .Architecture {
            maturity := architecture.bougainvillea_maturity(density)
            // Juveniles should be visibly young in reach as well as foliage
            // density. Established plants can still occupy most of a façade.
            height_fraction = architecture.bougainvillea_height_fraction(maturity)
        }
        plant_seed := structure.seed + u32(structure_index * 19)
        if capture_seed_enabled {
            plant_seed = capture_seed
        }
        root_spread := f32(math.sin(f64(f32(plant_seed) * .17))) * .38
        root_attachment_x := architecture.bougainvillea_root_attachment_x(
            growth_structure,
            root_spread * growth_structure.width * .62,
            plant_seed,
        )
        for vine in 0 ..< vine_count {
            vine_seed := plant_seed + u32(vine * 7)
            spread := root_spread
            if vine_count > 1 do spread += (f32(vine) / f32(vine_count - 1) - .5) * .24
            surface_seed := growth_structure.kind == .Architecture ? plant_seed : vine_seed
            surface_offset := f32(math.cos(f64(f32(surface_seed) * .23))) * .18
            attachment_x := spread * growth_structure.width * .62
            attachment_z := growth_structure.depth * .5 + .28 + surface_offset
            if growth_structure.kind != .Architecture {
                // Non-building targets are treated as rounded masses: place
                // each vine on the near radial shell instead of projecting it
                // onto an arbitrary rectangular front plane.
                shell_radius := max(growth_structure.width, growth_structure.depth) * .46 + .24
                attachment_x = spread * shell_radius
                shell_height := f32(
                    math.sqrt(f64(max(shell_radius * shell_radius - attachment_x * attachment_x, f32(.16)))),
                )
                attachment_z = shell_height + surface_offset
            }
            world_climbing_leaf_vine(
                growth_structure,
                attachment_x,
                root_attachment_x,
                attachment_z,
                growth_structure.height * height_fraction * (.88 + f32((vine + int(structure.seed)) % 3) * .08),
                density,
                vine_seed,
                plant_seed,
                vine == 0,
            )
        }
        clear(&entry.world_vertices)
        clear(&entry.bougainvillea_vertices)
        if world_first < len(world_renderer.vertices) {
            append(&entry.world_vertices, ..world_renderer.vertices[world_first:])
        }
        if bougainvillea_first < len(world_renderer.bougainvillea_vertices) {
            append(&entry.bougainvillea_vertices, ..world_renderer.bougainvillea_vertices[bougainvillea_first:])
        }
        entry.valid = true
        entry.structure = structure
        entry.density = density
        entry.detail_tier = detail_tier
        entry.capture_seed_enabled = capture_seed_enabled
        entry.capture_seed = capture_seed
}

world_climbing_leaf_density_overlay :: proc(editor: ^Editor) {
    if editor == nil || editor.in_map || !editor.climbing_leaf_paint_mode do return
    field := &editor.project.climbing_leaf_density
    cell := terrain.BASE_CELL_SIZE
    half := f32(terrain.RING_RESOLUTION - 1) * .5
    for z in 0 ..< terrain.RING_RESOLUTION - 1 {
        for x in 0 ..< terrain.RING_RESOLUTION - 1 {
            density := f32(field[z * terrain.RING_RESOLUTION + x]) / 255
            if density <= .01 do continue
            x0, z0 := (f32(x) - half) * cell, (f32(z) - half) * cell
            x1, z1 := x0 + cell, z0 + cell
            lift := f32(.13)
            a := third_person.Vec3{x0, terrain.sample_height(&editor.project, 0, x0, z0) + lift, z0}
            b := third_person.Vec3{x1, terrain.sample_height(&editor.project, 0, x1, z0) + lift, z0}
            c := third_person.Vec3{x1, terrain.sample_height(&editor.project, 0, x1, z1) + lift, z1}
            d := third_person.Vec3{x0, terrain.sample_height(&editor.project, 0, x0, z1) + lift, z1}
            world_quad(a, b, c, d, {57, 141, 78, u8(24 + density * 92)})
        }
    }
}

World_Aircraft_Transform :: struct {
    origin:        third_person.Vec3,
    right_basis:   third_person.Vec3,
    up_basis:      third_person.Vec3,
    forward_basis: third_person.Vec3,
}

world_aircraft_transform :: #force_inline proc(body: flight.Body_State, scale: f32) -> World_Aircraft_Transform {
    return {
        origin = {body.position.x, body.position.y, body.position.z},
        right_basis = {body.basis.right.x * scale, body.basis.right.y * scale, body.basis.right.z * scale},
        up_basis = {body.basis.up.x * scale, body.basis.up.y * scale, body.basis.up.z * scale},
        forward_basis = {body.basis.forward.x * scale, body.basis.forward.y * scale, body.basis.forward.z * scale},
    }
}

world_aircraft_vertex_world :: #force_inline proc(
    transform: World_Aircraft_Transform,
    position: [3]f32,
) -> third_person.Vec3 {
    return {
        transform.origin.x +
        transform.right_basis.x * position[0] +
        transform.up_basis.x * position[1] -
        transform.forward_basis.x * position[2],
        transform.origin.y +
        transform.right_basis.y * position[0] +
        transform.up_basis.y * position[1] -
        transform.forward_basis.y * position[2],
        transform.origin.z +
        transform.right_basis.z * position[0] +
        transform.up_basis.z * position[1] -
        transform.forward_basis.z * position[2],
    }
}

world_aircraft_normal_world :: #force_inline proc(
    transform: World_Aircraft_Transform,
    normal: [3]f32,
) -> third_person.Vec3 {
    return {
        transform.right_basis.x * normal[0] + transform.up_basis.x * normal[1] - transform.forward_basis.x * normal[2],
        transform.right_basis.y * normal[0] + transform.up_basis.y * normal[1] - transform.forward_basis.y * normal[2],
        transform.right_basis.z * normal[0] + transform.up_basis.z * normal[1] - transform.forward_basis.z * normal[2],
    }
}

world_aircraft :: proc(editor: ^Editor) {
    if editor.postale_visible {
        postale_paint_layer := f32(vehicle_paint_layer_index(.Postale))
        postale_propeller_blur := aircraft_propeller_blur_amount(editor.postale.throttle)
        postale_transform := world_aircraft_transform(editor.postale.body, POSTALE_PRESENTATION_SCALE)
        mesh := editor.postale_base_mesh
        vehicles.animate_postale_mesh(
            &mesh,
            editor.postale.flap_fraction,
            editor.flight_control.pitch,
            editor.flight_control.roll,
            editor.flight_control.yaw,
            editor.postale.propeller_turns,
            editor.postale.gear_compression / POSTALE_PRESENTATION_SCALE,
        )
        for triangle in vehicles.mesh_triangles(&mesh) {
            a := mesh.vertices[triangle.a]
            b := mesh.vertices[triangle.b]
            c := mesh.vertices[triangle.c]
            if a.part == .Propeller_Blur && postale_propeller_blur <= .01 do continue
            if vehicles.aircraft_mesh_part_uses_smooth_normals(a.part) {
                world_aircraft_triangle_smooth(
                    world_aircraft_vertex_world(postale_transform, a.position),
                    world_aircraft_vertex_world(postale_transform, b.position),
                    world_aircraft_vertex_world(postale_transform, c.position),
                    world_aircraft_normal_world(postale_transform, a.normal),
                    world_aircraft_normal_world(postale_transform, b.normal),
                    world_aircraft_normal_world(postale_transform, c.normal),
                    aircraft_postale_part_color_with_paint(editor, a.part, editor.postale.throttle),
                    a.uv,
                    b.uv,
                    c.uv,
                    postale_paint_layer,
                    vehicle_paint_part_is_paintable(a.part),
                )
            } else {
                world_aircraft_triangle(
                    world_aircraft_vertex_world(postale_transform, a.position),
                    world_aircraft_vertex_world(postale_transform, b.position),
                    world_aircraft_vertex_world(postale_transform, c.position),
                    aircraft_postale_part_color_with_paint(editor, a.part, editor.postale.throttle),
                    a.uv,
                    b.uv,
                    c.uv,
                    postale_paint_layer,
                    vehicle_paint_part_is_paintable(a.part),
                )
            }
        }
    }
    if editor.libellula_visible {
        libellula := &editor.libellula_visual_mesh
        if editor.aircraft.active == .Libellula_Mk2 {
            vehicles.libellula_mesh_copy(&editor.libellula_mk2_visual_mesh, &editor.libellula_mk2_base_mesh)
            libellula = &editor.libellula_mk2_visual_mesh
            vehicles.animate_libellula_mk2_mesh(
                libellula,
                editor.libellula.rotor_turns.x,
                editor.libellula.rotor_turns.y,
                editor.libellula.rotor_turns.z,
                editor.libellula.rotor_turns.z,
            )
        } else {
            vehicles.libellula_mesh_copy(libellula, &editor.libellula_base_mesh)
            vehicles.animate_libellula_mesh_pose(
                libellula,
                editor.libellula.rotor_turns.x,
                editor.libellula.rotor_turns.y,
                editor.libellula.rotor_turns.z,
                editor.libellula.pitch,
                editor.libellula.roll,
                0,
            )
        }
        libellula_paint_layer := f32(vehicle_paint_layer_index(editor.aircraft.active))
        libellula_transform := world_aircraft_transform(editor.libellula.body, LIBELLULA_PRESENTATION_SCALE)
        for triangle in vehicles.mesh_triangles(libellula) {
            a := libellula.vertices[triangle.a]
            b := libellula.vertices[triangle.b]
            c := libellula.vertices[triangle.c]
            world_aircraft_triangle(
                world_aircraft_vertex_world(libellula_transform, a.position),
                world_aircraft_vertex_world(libellula_transform, b.position),
                world_aircraft_vertex_world(libellula_transform, c.position),
                aircraft_part_color(a.part),
                a.uv,
                b.uv,
                c.uv,
                libellula_paint_layer,
                vehicle_paint_part_is_paintable(a.part),
            )
        }
    }
}

world_vehicle_showcase :: proc(editor: ^Editor) {
    // The showcase is intentionally self-contained: the vehicle is presented
    // against the sky with no island, runway, floor, or town geometry.
    if editor.vehicle_showcase_target == "postale" {
        world_aircraft(editor)
        world_postale_pilot(editor)
    } else if editor.vehicle_showcase_target == "libellula" || editor.vehicle_showcase_target == "libellula-mk2" {
        world_aircraft(editor)
        world_showcase_aircraft_pilot(editor, editor.libellula.body.position, editor.libellula.body.basis)
    } else {
        world_car(editor)
        world_showcase_car_pilot(editor)
    }
}

world_showcase_aircraft_pilot :: proc(editor: ^Editor, position: flight.Vec3, basis: flight.Basis) {
    rotation := math.atan2(-basis.forward.x, -basis.forward.z)
    seat_position := third_person.Vec3 {
        position.x + basis.up.x * .55,
        position.y + basis.up.y * .55,
        position.z + basis.up.z * .55,
    }
    world_mouse_model_parented(editor, {
            position          = seat_position,
            rotation          = rotation,
            accessory         = editor.mouse_headgear,
            fur               = editor.mouse_fur,
            pattern           = editor.mouse_pattern,
            scarf_enabled     = editor.mouse_scarf_enabled,
            scarf_color       = editor.mouse_scarf_color,
            player_controlled = true,
            grounded          = false,
            hide_tail         = true,
            hide_hind_feet    = true,
        }, basis)
}

world_showcase_car_pilot :: proc(editor: ^Editor) {
    world_car_pilot_model(editor, 0, 0)
}

CAR_PILOT_SCALE :: f32(.78)
CAR_PILOT_SEAT_Y :: f32(.31)
CAR_PILOT_SEAT_Z :: f32(.05)
CAR_STEERING_WHEEL_Y :: f32(.59)
CAR_STEERING_WHEEL_Z :: f32(-.25)
CAR_STEERING_WHEEL_RADIUS :: f32(.17)

World_Vehicle_Transform :: struct {
    origin:        third_person.Vec3,
    right_basis:   third_person.Vec3,
    up_basis:      third_person.Vec3,
    forward_basis: third_person.Vec3,
}

world_vehicle_transform :: #force_inline proc(
    origin: third_person.Vec3,
    yaw, pitch, roll: f32,
) -> World_Vehicle_Transform {
    pitch_cos, pitch_sin := math.cos(pitch), math.sin(pitch)
    roll_cos, roll_sin := math.cos(roll), math.sin(roll)
    heading_cos, heading_sin := math.cos(yaw), math.sin(yaw)
    return {
        origin = origin,
        right_basis = {-roll_cos * heading_sin, roll_sin, roll_cos * heading_cos},
        up_basis = {
            -pitch_sin * heading_cos + pitch_cos * roll_sin * heading_sin,
            pitch_cos * roll_cos,
            -pitch_sin * heading_sin - pitch_cos * roll_sin * heading_cos,
        },
        forward_basis = {
            pitch_cos * heading_cos + pitch_sin * roll_sin * heading_sin,
            pitch_sin * roll_cos,
            pitch_cos * heading_sin - pitch_sin * roll_sin * heading_cos,
        },
    }
}

world_car_transform :: #force_inline proc(editor: ^Editor) -> World_Vehicle_Transform {
    return world_vehicle_transform(
        editor.car.position,
        editor.car.yaw_radians,
        editor.car_drive.body_pitch,
        editor.car_drive.body_roll,
    )
}

world_trailer_transform :: #force_inline proc(editor: ^Editor) -> World_Vehicle_Transform {
    return world_vehicle_transform(
        editor.car_trailer_position,
        editor.car_trailer_yaw,
        editor.car_trailer.body_pitch,
        editor.car_trailer.body_roll,
    )
}

world_vehicle_vertex_world :: #force_inline proc(
    transform: World_Vehicle_Transform,
    position: [3]f32,
) -> third_person.Vec3 {
    return {
        transform.origin.x +
        position[0] * transform.right_basis.x +
        position[1] * transform.up_basis.x -
        position[2] * transform.forward_basis.x,
        transform.origin.y +
        position[0] * transform.right_basis.y +
        position[1] * transform.up_basis.y -
        position[2] * transform.forward_basis.y,
        transform.origin.z +
        position[0] * transform.right_basis.z +
        position[1] * transform.up_basis.z -
        position[2] * transform.forward_basis.z,
    }
}

world_car_pilot_model :: proc(editor: ^Editor, steering, acceleration: f32) {
    rotation := editor.car.yaw_radians - math.PI * .5
    car_transform := world_car_transform(editor)
    seat := world_vehicle_vertex_world(car_transform, {0, CAR_PILOT_SEAT_Y, CAR_PILOT_SEAT_Z})
    world_mouse_model_scaled(
        editor,
        {
            // Settle the mouse into the low seat while leaving its head and
            // ears above the roadster's windscreen.
            position           = seat,
            rotation           = rotation,
            accessory          = editor.mouse_headgear,
            fur                = editor.mouse_fur,
            pattern            = editor.mouse_pattern,
            scarf_enabled      = editor.mouse_scarf_enabled,
            scarf_color        = editor.mouse_scarf_color,
            player_controlled  = true,
            grounded           = false,
            hide_tail          = true,
            hide_hind_feet     = true,
            driving_pose       = true,
            drive_steering     = steering,
            drive_acceleration = acceleration,
        },
        CAR_PILOT_SCALE,
    )
}

world_car_pilot :: proc(editor: ^Editor) {
    if !editor.in_map || editor.pilot.mode != .Driving || editor.pilot.vehicle != &editor.car do return
    world_car_pilot_model(editor, editor.car_drive.steering, editor.car_drive.acceleration_feedback)
}

@(no_instrumentation)
trailer_part_color :: #force_inline proc(editor: ^Editor, part: vehicles.Aircraft_Mesh_Part) -> rl.Color {
    color := aircraft_part_color(part)
    if part == .Tail_Light {
        braking := editor.car_drive.handbrake_amount > .15 || editor.car_drive.acceleration_feedback < -.12
        if braking do color = {255, 76, 62, 255}
    }
    return color
}

world_car :: proc(editor: ^Editor) {
    mesh := vehicles.simple_car_mesh()
    trailer_speed_squared :=
        editor.car_trailer.velocity.x * editor.car_trailer.velocity.x +
        editor.car_trailer.velocity.z * editor.car_trailer.velocity.z
    trailer := vehicles.simple_car_trailer_mesh(
        !editor.car_trailer_attached,
        editor.car_trailer_attached,
        !editor.car_trailer_attached && trailer_speed_squared < .25,
    )
    vehicles.animate_trailer_wheels(&trailer, editor.car_trailer.wheel_rotation)
    car_transform := world_car_transform(editor)
    trailer_transform := world_trailer_transform(editor)
    world_car_cockpit(editor, car_transform)
    for triangle in vehicles.mesh_triangles(&mesh) {
        a := mesh.vertices[triangle.a]
        b := mesh.vertices[triangle.b]
        c := mesh.vertices[triangle.c]
        world_triangle(
            world_vehicle_vertex_world(car_transform, a.position),
            world_vehicle_vertex_world(car_transform, b.position),
            world_vehicle_vertex_world(car_transform, c.position),
            aircraft_part_color(a.part),
        )
    }
    for triangle in vehicles.mesh_triangles(&trailer) {
        a := trailer.vertices[triangle.a]
        b := trailer.vertices[triangle.b]
        c := trailer.vertices[triangle.c]
        world_triangle(
            world_vehicle_vertex_world(trailer_transform, a.position),
            world_vehicle_vertex_world(trailer_transform, b.position),
            world_vehicle_vertex_world(trailer_transform, c.position),
            trailer_part_color(editor, a.part),
        )
    }
}

world_car_cockpit :: proc(editor: ^Editor, car_transform: World_Vehicle_Transform) {
    // Keep the wheel low enough for the mouse's forepaws to meet the rim
    // without lifting its elbows into the windscreen.
    wheel_center := [3]f32{0, CAR_STEERING_WHEEL_Y, CAR_STEERING_WHEEL_Z}
    wheel_radius := CAR_STEERING_WHEEL_RADIUS
    wheel_rotation := clamp(editor.car_drive.steering, -1, 1) * .55
    forward := linalg.normalize0(
        (world_vehicle_vertex_world(car_transform, {wheel_center.x, wheel_center.y, wheel_center.z - .1}) -
            world_vehicle_vertex_world(car_transform, wheel_center)),
    )
    leather := rl.Color{48, 39, 34, 255}
    spoke := rl.Color{104, 83, 65, 255}
    SEGMENTS :: 12
    ring: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS) + wheel_rotation
        ring[segment] = world_vehicle_vertex_world(
            car_transform,
            {
                wheel_center.x + math.cos(angle) * wheel_radius,
                wheel_center.y + math.sin(angle) * wheel_radius,
                wheel_center.z,
            },
        )
    }
    for segment in 0 ..< SEGMENTS {
        world_tube_between(ring[segment], ring[(segment + 1) % SEGMENTS], forward, .026, .026, leather)
    }
    center := world_vehicle_vertex_world(car_transform, wheel_center)
    for segment in 0 ..< 3 {
        angle := f32(segment) * math.PI * 2 / 3 + wheel_rotation
        rim := world_vehicle_vertex_world(
            car_transform,
            {
                wheel_center.x + math.cos(angle) * wheel_radius * .88,
                wheel_center.y + math.sin(angle) * wheel_radius * .88,
                wheel_center.z,
            },
        )
        world_tube_between(center, rim, forward, .018, .018, spoke)
    }
    column := world_vehicle_vertex_world(car_transform, {0, .47, .08})
    world_tube_between(column, center, forward, .035, .035, spoke)
}

player_animation_approach :: proc(current, target, rate, delta_seconds: f32) -> f32 {
    maximum_delta := max(rate, f32(.1)) * delta_seconds
    if current < target do return min(current + maximum_delta, target)
    return max(current - maximum_delta, target)
}

// A semi-implicit damped spring gives the sprint pose mass: acceleration tips
// the body forward and each bound loads the spine, then both settle without
// being tied directly to a canned animation curve.
player_animation_spring :: proc(value, velocity: ^f32, target, stiffness, damping, delta_seconds: f32) {
    if value == nil || velocity == nil || delta_seconds <= 0 do return
    acceleration := (target - value^) * max(stiffness, f32(1)) - velocity^ * max(damping, f32(0))
    velocity^ += acceleration * delta_seconds
    value^ += velocity^ * delta_seconds
}

mouse_gait_weights :: proc(
    animation: ^Player_Animation_Tweak,
    horizontal_speed, airborne_weight: f32,
) -> mouse_gait.Weights {
    if animation == nil do return {walk = 1}
    return mouse_gait.weights(
        horizontal_speed,
        animation.walk_full_speed,
        animation.trot_full_speed,
        animation.bound_start_speed,
        animation.bound_full_speed,
        airborne_weight,
    )
}

Mouse_Bone :: enum u8 {
    Pelvis,
    Spine,
    Chest,
    Neck,
    Head,
}

Mouse_Bone_Pose :: struct {
    parent:        i8,
    bind_position: third_person.Vec3,
    position:      third_person.Vec3,
    pitch:         f32,
    roll:          f32,
}

Mouse_Vertex_Group :: struct {
    bone:   Mouse_Bone,
    weight: f32,
}

Mouse_Skin_Vertex :: struct {
    bind_position: third_person.Vec3,
    groups:        [2]Mouse_Vertex_Group,
    color:         rl.Color,
}

@(no_instrumentation)
mouse_skin_vertex :: #force_inline proc(
    vertex: Mouse_Skin_Vertex,
    skeleton: ^[5]Mouse_Bone_Pose,
) -> third_person.Vec3 {
    skinned: third_person.Vec3
    weight_sum: f32
    for group in vertex.groups {
        if group.weight <= 0 do continue
        bone := skeleton[int(group.bone)]
        relative := third_person.Vec3 {
            vertex.bind_position.x - bone.bind_position.x,
            vertex.bind_position.y - bone.bind_position.y,
            vertex.bind_position.z - bone.bind_position.z,
        }
        pitch_cosine, pitch_sine := math.cos(bone.pitch), math.sin(bone.pitch)
        pitched_y := relative.y * pitch_cosine - relative.z * pitch_sine
        pitched_z := relative.y * pitch_sine + relative.z * pitch_cosine
        roll_cosine, roll_sine := math.cos(bone.roll), math.sin(bone.roll)
        transformed := third_person.Vec3 {
            bone.position.x + relative.x * roll_cosine - pitched_y * roll_sine,
            bone.position.y + relative.x * roll_sine + pitched_y * roll_cosine,
            bone.position.z + pitched_z,
        }
        skinned.x += transformed.x * group.weight
        skinned.y += transformed.y * group.weight
        skinned.z += transformed.z * group.weight
        weight_sum += group.weight
    }
    if weight_sum <= .0001 do return vertex.bind_position
    inverse_weight := 1 / weight_sum
    return {skinned.x * inverse_weight, skinned.y * inverse_weight, skinned.z * inverse_weight}
}

mouse_body_surface_height :: proc(
    skeleton: ^[5]Mouse_Bone_Pose,
    local_x, local_y, local_z: f32,
) -> (
    height: f32,
    push_up, hit: bool,
) {
    if skeleton == nil do return
    RINGS :: 10
    ring_z := [RINGS]f32{-.78, -.70, -.52, -.28, -.04, .10, .20, .32, .47, .58}
    ring_y := [RINGS]f32{.33, .37, .42, .47, .52, .59, .68, .64, .61, .62}
    radius_x := [RINGS]f32{.07, .19, .29, .30, .255, .205, .20, .17, .095, .025}
    radius_y := [RINGS]f32{.09, .22, .32, .35, .28, .21, .185, .125, .070, .022}
    primary := [RINGS]Mouse_Bone{.Pelvis, .Pelvis, .Pelvis, .Spine, .Chest, .Neck, .Head, .Head, .Head, .Head}
    secondary := [RINGS]Mouse_Bone{.Spine, .Spine, .Spine, .Pelvis, .Spine, .Chest, .Neck, .Neck, .Neck, .Neck}
    primary_weight := [RINGS]f32{.98, .92, .82, .76, .68, .66, .78, .88, .96, 1}
    if local_z < ring_z[0] || local_z > ring_z[RINGS - 1] do return

    lower := 0
    for index in 0 ..< RINGS - 1 {
        if local_z >= ring_z[index] && local_z <= ring_z[index + 1] {
            lower = index
            break
        }
    }
    upper := min(lower + 1, RINGS - 1)
    span := max(ring_z[upper] - ring_z[lower], f32(.0001))
    amount := clamp((local_z - ring_z[lower]) / span, 0, 1)
    center_y := ring_y[lower] + (ring_y[upper] - ring_y[lower]) * amount
    body_radius_x := radius_x[lower] + (radius_x[upper] - radius_x[lower]) * amount
    body_radius_y := radius_y[lower] + (radius_y[upper] - radius_y[lower]) * amount
    if body_radius_x <= .001 || math.abs(local_x) >= body_radius_x do return
    normalized_x := clamp(local_x / body_radius_x, -1, 1)
    vertical_radius := body_radius_y * f32(math.sqrt(f64(max(1 - normalized_x * normalized_x, f32(0)))))
    nearest := amount < .5 ? lower : upper
    groups := [2]Mouse_Vertex_Group {
        {primary[nearest], primary_weight[nearest]},
        {secondary[nearest], 1 - primary_weight[nearest]},
    }
    posed_center := mouse_skin_vertex({bind_position = {local_x, center_y, local_z}, groups = groups}, skeleton)
    push_up = local_y >= posed_center.y
    surface_y := center_y + (push_up ? vertical_radius : -vertical_radius)
    posed_surface := mouse_skin_vertex({bind_position = {local_x, surface_y, local_z}, groups = groups}, skeleton)
    return posed_surface.y, push_up, true
}

world_mouse_skinned_hull :: proc(
    origin: third_person.Vec3,
    rotation: f32,
    skeleton: ^[5]Mouse_Bone_Pose,
    fur, fur_dark, fur_light: rl.Color,
    pattern: Mouse_Fur_Pattern,
    breath: f32,
) {
    RINGS :: 10
    SEGMENTS :: 12
    ring_z := [RINGS]f32{-.78, -.70, -.52, -.28, -.04, .10, .20, .32, .47, .58}
    // A mouse's dorsal line is a soft arch over the pelvis and ribs, then
    // descends into the neck.  Keeping the belly locations nearly unchanged
    // while lifting and enlarging these middle rings avoids the flat-backed,
    // rectangular silhouette that the low running pose previously produced.
    ring_y := [RINGS]f32{.33, .37, .42, .47, .52, .59, .68, .64, .61, .62}
    radius_x := [RINGS]f32{.07, .19, .29, .30, .255, .205, .20, .17, .095, .025}
    radius_y := [RINGS]f32{.09, .22, .32, .35, .28, .21, .185, .125, .070, .022}
    primary := [RINGS]Mouse_Bone{.Pelvis, .Pelvis, .Pelvis, .Spine, .Chest, .Neck, .Head, .Head, .Head, .Head}
    secondary := [RINGS]Mouse_Bone{.Spine, .Spine, .Spine, .Pelvis, .Spine, .Chest, .Neck, .Neck, .Neck, .Neck}
    primary_weight := [RINGS]f32{.98, .92, .82, .76, .68, .66, .78, .88, .96, 1}

    vertices: [RINGS][SEGMENTS]Mouse_Skin_Vertex
    posed: [RINGS][SEGMENTS]third_person.Vec3
    rib_weights := [RINGS]f32{0, .02, .10, .55, 1, .45, 0, 0, 0, 0}
    for ring in 0 ..< RINGS {
        breath_scale := 1 + breath * rib_weights[ring]
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
            cosine, sine := math.cos(angle), math.sin(angle)
            belly_weight := clamp((-sine - .05) * .76, 0, .68)
            if ring >= 6 do belly_weight = max(belly_weight, f32(.48))
            dorsal_weight := clamp((sine - .10) * .30, 0, .27)
            if ring >= 6 do dorsal_weight *= .55
            coat_color := color_lerp(fur, fur_light, belly_weight)
            coat_color = color_lerp(coat_color, fur_dark, dorsal_weight)
            marking := color_lerp(fur_light, {247, 239, 218, 255}, .72)
            switch pattern {
            case .Solid:
            case .Pale_Belly:
                pale_weight := clamp((-sine + .15) * 1.15, 0, .92)
                coat_color = color_lerp(coat_color, marking, pale_weight)
            case .Hooded:
                if ring < 6 {
                    hood_edge := ring == 5 ? clamp((sine + .2) * .7, 0, 1) : f32(1)
                    coat_color = color_lerp(coat_color, marking, hood_edge)
                }
            case .Piebald:
                patch_value := (ring * 7 + segment * 3 + (segment / 3) * 5) % 13
                if patch_value < 5 do coat_color = color_lerp(coat_color, marking, .92)
            case .Dorsal_Stripe:
                // A narrow dark stripe follows the spine and softens toward
                // the flanks, as on striped field mice.
                stripe_center := clamp((sine - .48) * 3.4, 0, 1)
                stripe_taper := ring == 0 || ring >= 8 ? f32(.62) : f32(1)
                coat_color = color_lerp(coat_color, fur_dark, stripe_center * stripe_taper)
            case .Masked:
                // Keep the muzzle pale while wrapping a dark mask around the
                // crown and sides of the head.
                if ring >= 6 && ring < 9 {
                    mask_weight := clamp((sine + .35) * .78, 0, .88)
                    coat_color = color_lerp(coat_color, fur_dark, mask_weight)
                } else if ring == 9 {
                    coat_color = color_lerp(coat_color, marking, .42)
                }
            }
            vertices[ring][segment] = {
                bind_position = {
                    cosine * radius_x[ring] * breath_scale,
                    ring_y[ring] + sine * radius_y[ring] * breath_scale,
                    ring_z[ring],
                },
                groups        = {{primary[ring], primary_weight[ring]}, {secondary[ring], 1 - primary_weight[ring]}},
                color         = coat_color,
            }
            local := mouse_skin_vertex(vertices[ring][segment], skeleton)
            world_x, world_z := world_rotate_xz(origin.x, origin.z, local.x, local.z, rotation)
            posed[ring][segment] = {world_x, origin.y + local.y, world_z}
        }
    }

    for ring in 0 ..< RINGS - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            a, b := posed[ring][segment], posed[ring][next]
            c, d := posed[ring + 1][next], posed[ring + 1][segment]
            world_triangle_colored(
                a,
                b,
                c,
                vertices[ring][segment].color,
                vertices[ring][next].color,
                vertices[ring + 1][next].color,
            )
            world_triangle_colored(
                a,
                c,
                d,
                vertices[ring][segment].color,
                vertices[ring + 1][next].color,
                vertices[ring + 1][segment].color,
            )
        }
    }

    rear_center_local := mouse_skin_vertex(
        {bind_position = {0, ring_y[0], ring_z[0]}, groups = {{.Pelvis, 1}, {.Spine, 0}}, color = fur},
        skeleton,
    )
    nose_center_local := mouse_skin_vertex({
            bind_position = {0, ring_y[RINGS - 1], ring_z[RINGS - 1]},
            groups        = {{.Head, 1}, {.Neck, 0}},
            color         = fur_light,
        }, skeleton)
    rear_x, rear_z := world_rotate_xz(origin.x, origin.z, rear_center_local.x, rear_center_local.z, rotation)
    nose_x, nose_z := world_rotate_xz(origin.x, origin.z, nose_center_local.x, nose_center_local.z, rotation)
    rear_center := third_person.Vec3{rear_x, origin.y + rear_center_local.y, rear_z}
    nose_center := third_person.Vec3{nose_x, origin.y + nose_center_local.y, nose_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(rear_center, posed[0][next], posed[0][segment], fur)
        world_triangle(nose_center, posed[RINGS - 1][segment], posed[RINGS - 1][next], fur_light)
    }
}

@(no_instrumentation)
mouse_ear_world_point :: #force_inline proc(
    origin, center: third_person.Vec3,
    rotation, yaw, x, y, z: f32,
) -> third_person.Vec3 {
    cosine, sine := math.cos(yaw), math.sin(yaw)
    local_x := center.x + x * cosine + z * sine
    local_z := center.z - x * sine + z * cosine - y * .20
    world_x, world_z := world_rotate_xz(origin.x, origin.z, local_x, local_z, rotation)
    return {world_x, origin.y + center.y + y, world_z}
}

world_mouse_ear :: proc(
    origin: third_person.Vec3,
    rotation: f32,
    center: third_person.Vec3,
    side, twitch: f32,
    rim_color, inner_color: rl.Color,
) {
    SEGMENTS :: 16
    // Mouse pinnae face laterally.  A shallow yaw made them disappear into
    // edge-on slivers in the gameplay side view; this angle preserves their
    // broad oval silhouette while still separating the bilateral pair.
    yaw := side * (1.02 + twitch * 5)
    outer_back, outer_front, inner_rim: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
        cosine, sine := math.cos(angle), math.sin(angle)
        root_taper := .70 + .30 * clamp((sine + .55) / 1.55, 0, 1)
        outer_x := cosine * .101 * root_taper
        outer_y := sine * .108
        inner_x := cosine * .069 * root_taper
        inner_y := .006 + sine * .073
        outer_back[segment] = mouse_ear_world_point(origin, center, rotation, yaw, outer_x, outer_y, -.034)
        outer_front[segment] = mouse_ear_world_point(origin, center, rotation, yaw, outer_x, outer_y, .034)
        inner_rim[segment] = mouse_ear_world_point(origin, center, rotation, yaw, inner_x, inner_y, .036)
    }

    back_center := mouse_ear_world_point(origin, center, rotation, yaw, 0, 0, -.034)
    // Recessing the pink center behind its inner rim gives the pinna a shallow
    // bowl instead of reading as a sticker laid over a flat disc.
    cup_center := mouse_ear_world_point(origin, center, rotation, yaw, 0, .008, .014)
    // Thin mouse ears transmit some of their pink tone even from behind. This
    // keeps the far pinna recognizable instead of reducing it to a dark fur
    // bump when its cup faces away from the camera.
    back_color := color_lerp(rim_color, inner_color, .34)
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        // The back cap faces away from the pink cup. Wind it outward so it
        // survives normal back-face culling and occludes the inner surfaces
        // when the far pinna is viewed from behind.
        world_triangle(back_center, outer_back[next], outer_back[segment], back_color)
        world_quad(outer_back[segment], outer_back[next], outer_front[next], outer_front[segment], rim_color)
        world_quad(outer_front[segment], outer_front[next], inner_rim[next], inner_rim[segment], rim_color)
        world_triangle(cup_center, inner_rim[segment], inner_rim[next], inner_color)
    }
}

player_animation_update :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || delta_seconds <= 0 do return
    animation := &editor.tweak.player_animation
    horizontal_speed := f32(
        math.sqrt(
            f64(
                editor.player.velocity.x * editor.player.velocity.x +
                editor.player.velocity.z * editor.player.velocity.z,
            ),
        ),
    )
    speed_acceleration := clamp(
        (horizontal_speed - editor.player_animation_previous_speed) / max(delta_seconds, f32(.001)),
        -30,
        30,
    )
    editor.player_animation_previous_speed = horizontal_speed
    scurry_target :=
        editor.player.running && editor.player.grounded && horizontal_speed > max(animation.walk_full_speed * .72, f32(.1)) ? f32(1) : f32(0)
    if editor.player.boost_seconds > 0 && editor.player.grounded do scurry_target = 1
    editor.player_scurry_weight = player_animation_approach(
        editor.player_scurry_weight,
        scurry_target,
        animation.locomotion_blend_rate * .8,
        delta_seconds,
    )
    scurry_lean_target :=
        editor.player_scurry_weight *
        (animation.scurry_lean_radians + speed_acceleration * animation.scurry_acceleration_lean)
    compression_impulse := max(math.sin(editor.player_stride_phase), f32(0))
    scurry_compression_target := editor.player_scurry_weight * compression_impulse * animation.scurry_compression
    player_animation_spring(
        &editor.player_scurry_lean,
        &editor.player_scurry_lean_velocity,
        scurry_lean_target,
        animation.scurry_spring_stiffness,
        animation.scurry_spring_damping,
        delta_seconds,
    )
    player_animation_spring(
        &editor.player_scurry_compression,
        &editor.player_scurry_compression_velocity,
        scurry_compression_target,
        animation.scurry_spring_stiffness * 1.25,
        animation.scurry_spring_damping,
        delta_seconds,
    )
    gait_target := clamp(horizontal_speed / max(animation.walk_full_speed, f32(.1)), 0, 1)
    airborne_target := editor.player.grounded ? f32(0) : f32(1)
    vertical_target := f32(0)
    if !editor.player.grounded {
        vertical_target = clamp(editor.player.velocity.y / max(animation.vertical_full_speed, f32(.1)), -1, 1)
    }
    editor.player_gait_weight = player_animation_approach(
        editor.player_gait_weight,
        gait_target,
        animation.locomotion_blend_rate,
        delta_seconds,
    )
    editor.player_airborne_weight = player_animation_approach(
        editor.player_airborne_weight,
        airborne_target,
        animation.airborne_blend_rate,
        delta_seconds,
    )
    editor.player_vertical_pose = player_animation_approach(
        editor.player_vertical_pose,
        vertical_target,
        animation.vertical_blend_rate,
        delta_seconds,
    )
    editor.player_turn_pose = player_animation_approach(
        editor.player_turn_pose,
        editor.player.turn_amount,
        animation.turn_blend_rate,
        delta_seconds,
    )
    editor.player_brake_pose = player_animation_approach(
        editor.player_brake_pose,
        editor.player.brake_amount,
        animation.brake_blend_rate,
        delta_seconds,
    )
    if editor.player.grounded && horizontal_speed < .08 {
        editor.player_posted_idle_seconds += delta_seconds
    } else {
        editor.player_posted_idle_seconds = 0
    }
    posted_target := editor.player_posted_idle_seconds >= 2.75 ? f32(1) : f32(0)
    editor.player_posted_weight = player_animation_approach(
        editor.player_posted_weight,
        posted_target,
        2.6,
        delta_seconds,
    )
    if editor.player.grounded {
        gait := mouse_gait_weights(animation, horizontal_speed, editor.player_airborne_weight)
        stride_radians_per_meter :=
            animation.stride_radians_per_meter * gait.walk +
            animation.trot_stride_radians_per_meter * gait.trot +
            animation.bound_stride_radians_per_meter * gait.bound
        editor.player_stride_phase += horizontal_speed * delta_seconds * max(stride_radians_per_meter, f32(.1))
        for editor.player_stride_phase >= math.PI * 2 do editor.player_stride_phase -= math.PI * 2
    }
}

mouse_surface_height :: proc(editor: ^Editor, x, z: f32) -> f32 {
    height := terrain.sample_height(&editor.project, 0, x, z)
    plan := editor_circulation_plan(editor)
    if !world_renderer.pavement_query_graph_valid ||
       world_renderer.pavement_query_revision != editor.project.revision {
        if !world_renderer.pavement_query_graph_valid ||
           world_renderer.pavement_query_graph != editor.project.road_graph {
            roads.pavement_query_build(&editor.project.road_graph, &world_renderer.pavement_query)
            world_renderer.pavement_query_graph = editor.project.road_graph
            world_renderer.pavement_query_graph_valid = true
        }
        world_renderer.pavement_query_revision = editor.project.revision
    }
    surface := circulation.surface_at_cached(
        &editor.project.road_graph,
        plan,
        &world_renderer.pavement_query,
        {x, height, z},
    )
    if surface.on_surface do height = max(height + .12, surface.height + .12)
    return height
}

MOUSE_CONTACT_SKIN :: f32(.006)

mouse_ground_contact :: proc(
    editor: ^Editor,
    point: third_person.Vec3,
    half_height: f32,
    planted: bool,
) -> third_person.Vec3 {
    floor := mouse_surface_height(editor, point.x, point.z) + half_height + MOUSE_CONTACT_SKIN
    result := point
    result.y = planted ? floor : max(result.y, floor)
    return result
}

mouse_clamp_endpoint_reach :: proc(
    root: third_person.Vec3,
    target: ^third_person.Vec3,
    minimum_reach, maximum_reach: f32,
) {
    if target == nil do return
    delta := third_person.Vec3{target.x - root.x, target.y - root.y, target.z - root.z}
    distance := linalg.length(delta)
    if distance <= .0001 {
        if minimum_reach > .0001 {
            target^ = {root.x, root.y, root.z + minimum_reach}
        }
        return
    }
    clamped_distance := clamp(distance, minimum_reach, maximum_reach)
    if math.abs(clamped_distance - distance) <= .0001 do return
    scale := clamped_distance / distance
    target^ = {root.x + delta.x * scale, root.y + delta.y * scale, root.z + delta.z * scale}
}

mouse_clamp_ground_contact_reach :: proc(root: third_person.Vec3, target: ^third_person.Vec3, maximum_reach: f32) {
    if target == nil do return
    dy := target.y - root.y
    if math.abs(dy) >= maximum_reach {
        // Keep the terrain height authoritative even when the vertical span
        // alone exhausts the chain.
        target.x = root.x
        target.z = root.z
        return
    }
    horizontal_delta := [2]f32{target.x - root.x, target.z - root.z}
    horizontal_distance := linalg.length(horizontal_delta)
    horizontal_limit := f32(math.sqrt(f64(max(maximum_reach * maximum_reach - dy * dy, f32(0)))))
    if horizontal_distance <= horizontal_limit || horizontal_distance <= .0001 do return
    scale := horizontal_limit / horizontal_distance
    target.x = root.x + horizontal_delta[0] * scale
    target.z = root.z + horizontal_delta[1] * scale
}

mouse_constrain_hind_chain :: proc(
    points: ^[4]third_person.Vec3,
    lengths: [3]f32,
    anatomical_forward: third_person.Vec3,
) {
    if points == nil do return
    root, target := points[0], points[3]
    root_to_target := third_person.Vec3{target.x - root.x, target.y - root.y, target.z - root.z}
    distance := linalg.length(root_to_target)
    total := lengths[0] + lengths[1] + lengths[2]
    if distance > total - .0001 {
        mouse_clamp_endpoint_reach(root, &target, 0, total - .0001)
        root_to_target = {target.x - root.x, target.y - root.y, target.z - root.z}
        distance = linalg.length(root_to_target)
    }
    remaining := mouse_kinematics.stable_distal_span(
        distance,
        lengths[0],
        lengths[1],
        lengths[2],
    )
    // Two nested analytic solves preserve all three segment lengths and both
    // endpoints exactly. Stable anatomical poles retain the zig-zag topology,
    // while the phase-independent distal span prevents knee/hock accordion.
    knee := mouse_kinematics.solve_two_bone(
        root,
        target,
        mouse_kinematics.hind_knee_pole(anatomical_forward),
        lengths[0],
        remaining,
    )
    hock := mouse_kinematics.solve_two_bone(
        knee,
        target,
        mouse_kinematics.hind_hock_pole(anatomical_forward),
        lengths[1],
        lengths[2],
    )
    points^ = {root, knee, hock, target}
}

Mouse_Accessory :: enum {
    None,
    Goggles,
    Flower,
    Acorn_Cap,
    Bottle_Cap,
    Paper_Boat,
    Chef_Hat,
    Ushanka,
    Beret,
    Alpine_Hat,
    Flat_Cap,
}

Mouse_Fur :: enum {
    Chestnut,
    Silver,
    Cream,
    Soot,
    Russet,
    White,
}

Mouse_Fur_Pattern :: enum {
    Solid,
    Pale_Belly,
    Hooded,
    Piebald,
    Dorsal_Stripe,
    Masked,
}

// Approximate the coat immediately surrounding a limb socket. The torso has
// denser per-vertex patterning, but carrying its dominant socket color into the
// first limb ring prevents the appendage from beginning at a hard color seam.
mouse_limb_socket_color :: proc(
    pattern: Mouse_Fur_Pattern,
    fur, fur_dark, fur_light: rl.Color,
    side: f32,
    hind: bool,
) -> rl.Color {
    marking := color_lerp(fur_light, {247, 239, 218, 255}, .72)
    switch pattern {
    case .Pale_Belly:
        return color_lerp(fur, marking, hind ? f32(.76) : f32(.66))
    case .Hooded:
        return color_lerp(fur, marking, hind ? f32(.90) : f32(.72))
    case .Piebald:
        pale_socket := hind ? side > 0 : side < 0
        if pale_socket do return color_lerp(fur, marking, .88)
    case .Dorsal_Stripe:
    // Limb sockets sit below the dorsal stripe.
    case .Masked:
    // The mask is confined to the head.
    case .Solid:
    }
    return color_lerp(fur, fur_dark, hind ? f32(.04) : f32(.08))
}

Mouse_Model :: struct {
    position:           third_person.Vec3,
    rotation:           f32,
    // Zero retains the canonical proportions so existing call sites do not
    // need to opt in. Town residents use these to keep distinct silhouettes.
    build:              f32,
    snout_length:       f32,
    accessory:          Mouse_Accessory,
    accessory_side:     f32,
    fur:                Mouse_Fur,
    pattern:            Mouse_Fur_Pattern,
    scarf_enabled:      bool,
    scarf_color:        rl.Color,
    preview:            bool,
    player_controlled:  bool,
    track_paw_plants:   bool,
    grounded:           bool,
    hide_tail:          bool,
    hide_hind_feet:     bool,
    driving_pose:       bool,
    drive_steering:     f32,
    drive_acceleration: f32,
    gait_preview:       bool,
    gait_speed:         f32,
    gait_phase:         f32,
}

// world_mouse_model builds geometry in a yaw-only frame because ordinary mice
// stay aligned to world up. Aircraft occupants need one additional parent
// transform: recover each emitted vertex's yaw-local coordinates, then place
// it in the aircraft's full right/up/forward basis so pitch and roll are
// inherited together with translation and heading.
world_mouse_model_parented :: proc(editor: ^Editor, model: Mouse_Model, basis: flight.Basis) {
    first_vertex := len(world_renderer.vertices)
    world_mouse_model(editor, model)

    yaw_right := third_person.Vec3{math.cos(model.rotation), 0, math.sin(model.rotation)}
    yaw_forward := third_person.Vec3{-math.sin(model.rotation), 0, math.cos(model.rotation)}
    origin := model.position
    for index in first_vertex ..< len(world_renderer.vertices) {
        vertex := &world_renderer.vertices[index]
        delta := third_person.Vec3 {
            vertex.position[0] - origin.x,
            vertex.position[1] - origin.y,
            vertex.position[2] - origin.z,
        }
        local_x := delta.x * yaw_right.x + delta.z * yaw_right.z
        local_y := delta.y
        local_z := delta.x * yaw_forward.x + delta.z * yaw_forward.z
        vertex.position = {
            origin.x + basis.right.x * local_x + basis.up.x * local_y + basis.forward.x * local_z,
            origin.y + basis.right.y * local_x + basis.up.y * local_y + basis.forward.y * local_z,
            origin.z + basis.right.z * local_x + basis.up.z * local_y + basis.forward.z * local_z,
        }

        normal := third_person.Vec3{vertex.normal[0], vertex.normal[1], vertex.normal[2]}
        normal_x := normal.x * yaw_right.x + normal.z * yaw_right.z
        normal_y := normal.y
        normal_z := normal.x * yaw_forward.x + normal.z * yaw_forward.z
        vertex.normal = {
            basis.right.x * normal_x + basis.up.x * normal_y + basis.forward.x * normal_z,
            basis.right.y * normal_x + basis.up.y * normal_y + basis.forward.y * normal_z,
            basis.right.z * normal_x + basis.up.z * normal_y + basis.forward.z * normal_z,
        }
    }
}

world_mouse_model_scaled :: proc(editor: ^Editor, model: Mouse_Model, scale: f32) {
    first_vertex := len(world_renderer.vertices)
    world_mouse_model(editor, model)
    safe_scale := max(scale, f32(.01))
    for index in first_vertex ..< len(world_renderer.vertices) {
        vertex := &world_renderer.vertices[index]
        vertex.position = {
            model.position.x + (vertex.position[0] - model.position.x) * safe_scale,
            model.position.y + (vertex.position[1] - model.position.y) * safe_scale,
            model.position.z + (vertex.position[2] - model.position.z) * safe_scale,
        }
    }
}

world_town_mouse_model_scaled_cached :: proc(
    editor: ^Editor,
    model: Mouse_Model,
    scale: f32,
    cache_index: int,
) {
    if editor == nil || cache_index < 0 || cache_index >= TOWN_MOUSE_CACHE_COUNT {
        world_mouse_model_scaled(editor, model, scale)
        return
    }
    entry := &world_renderer.town_mouse_geometry_cache[cache_index]
    phase := f32(cache_index) / TOWN_MOUSE_CACHE_COUNT
    animation_bucket := i64(math.floor(f64(editor.map_time * TOWN_MOUSE_ANIMATION_HZ + phase)))
    wind := model.scarf_enabled ? editor.atmosphere.weather.wind : [2]f32{}
    if entry.valid &&
       entry.model == model &&
       entry.scale == scale &&
       entry.animation_bucket == animation_bucket &&
       entry.wind == wind {
        append(&world_renderer.vertices, ..entry.vertices[:])
        return
    }

    first := len(world_renderer.vertices)
    world_mouse_model_scaled(editor, model, scale)
    clear(&entry.vertices)
    if first < len(world_renderer.vertices) {
        append(&entry.vertices, ..world_renderer.vertices[first:])
    }
    entry.valid = true
    entry.model = model
    entry.scale = scale
    entry.animation_bucket = animation_bucket
    entry.wind = wind
}

world_mouse_model :: proc(editor: ^Editor, model: Mouse_Model) {
    first_vertex := len(world_renderer.vertices)
    build := model.build
    if build <= 0 do build = 1
    snout_length := model.snout_length
    if snout_length <= 0 do snout_length = 1
    p := model.position
    if model.grounded {
        raw_height := terrain.sample_height(&editor.project, 0, p.x, p.z)
        p.y += mouse_surface_height(editor, p.x, p.z) - raw_height
    }
    rotation := model.rotation
    @(no_instrumentation)
    local_point :: #force_inline proc(origin: third_person.Vec3, rotation, x, y, z: f32) -> third_person.Vec3 {
        world_x, world_z := world_rotate_xz(origin.x, origin.z, x, z, rotation)
        return {world_x, origin.y + y, world_z}
    }

    fur: rl.Color
    fur_dark: rl.Color
    fur_light: rl.Color
    switch model.fur {
    case .Chestnut:
        fur, fur_dark, fur_light = {132, 107, 84, 255}, {91, 70, 57, 255}, {184, 164, 139, 255}
    case .Silver:
        fur, fur_dark, fur_light = {139, 145, 151, 255}, {83, 90, 98, 255}, {197, 202, 207, 255}
    case .Cream:
        fur, fur_dark, fur_light = {213, 190, 151, 255}, {145, 119, 88, 255}, {241, 224, 190, 255}
    case .Soot:
        fur, fur_dark, fur_light = {59, 63, 69, 255}, {27, 30, 35, 255}, {111, 118, 125, 255}
    case .Russet:
        fur, fur_dark, fur_light = {169, 91, 55, 255}, {103, 51, 37, 255}, {216, 139, 91, 255}
    case .White:
        fur, fur_dark, fur_light = {226, 224, 216, 255}, {157, 154, 150, 255}, {249, 246, 233, 255}
    }
    ear: rl.Color = {188, 126, 123, 255}
    paw: rl.Color = {201, 146, 139, 255}
    features: rl.Color = {35, 32, 30, 255}
    nose: rl.Color = {161, 102, 101, 255}
    tooth: rl.Color = {232, 222, 189, 255}
    leather: rl.Color = {91, 55, 38, 255}
    leather_dark: rl.Color = {58, 38, 31, 255}
    brass: rl.Color = {204, 157, 72, 255}
    goggle_glass: rl.Color = {78, 157, 169, 255}
    model_forward := third_person.Vec3{-math.sin(rotation), 0, math.cos(rotation)}
    animation := &editor.tweak.player_animation
    turn_pose :=
        model.player_controlled ? clamp(editor.player_turn_pose, -1, 1) : (model.driving_pose ? clamp(model.drive_steering, -1, 1) : f32(0))
    brake_pose := model.player_controlled ? clamp(editor.player_brake_pose, 0, 1) : f32(0)
    if model.player_controlled && editor.capture_player_turn_left_pose do turn_pose = -1
    if model.player_controlled && editor.capture_player_turn_right_pose do turn_pose = 1
    if model.player_controlled && editor.capture_player_brake_pose do brake_pose = 1
    ground_normal := model.player_controlled ? editor.player.ground_normal : third_person.Vec3{0, 1, 0}
    if ground_normal.y <= .1 do ground_normal = third_person.Vec3{0, 1, 0}
    model_right := third_person.Vec3{math.cos(rotation), 0, math.sin(rotation)}
    normal_forward := ground_normal.x * model_forward.x + ground_normal.z * model_forward.z
    normal_right := ground_normal.x * model_right.x + ground_normal.z * model_right.z
    slope_pitch := math.atan2(normal_forward, ground_normal.y) * animation.slope_alignment
    slope_roll := math.atan2(-normal_right, ground_normal.y) * animation.slope_alignment
    body_roll := slope_roll - turn_pose * animation.turn_lean_radians
    scurry_weight := model.player_controlled ? clamp(editor.player_scurry_weight, 0, 1) : f32(0)
    scurry_lean := model.player_controlled ? clamp(editor.player_scurry_lean, -.12, .32) : f32(0)
    scurry_compression :=
        model.player_controlled ? clamp(editor.player_scurry_compression, -.025, animation.scurry_compression * 1.35) : f32(0)
    drive_reaction := model.driving_pose ? -clamp(model.drive_acceleration, -1, 1) : f32(0)
    spine_side := turn_pose * animation.turn_spine_offset
    brake_compression := brake_pose * animation.brake_compression
    posted_weight :=
        model.player_controlled ? clamp(editor.player_posted_weight, 0, 1) : (model.gait_preview ? f32(0) : f32(1))
    if model.player_controlled && editor.capture_player_posted_pose do posted_weight = 1

    airborne_weight := model.player_controlled ? editor.player_airborne_weight : f32(0)
    run_weight :=
        model.player_controlled ? editor.player_gait_weight * (1 - airborne_weight) + .88 * airborne_weight : f32(0)
    stride_phase := model.player_controlled ? editor.player_stride_phase : f32(0)
    horizontal_speed := f32(
            math.sqrt(
                f64(
                    editor.player.velocity.x * editor.player.velocity.x +
                    editor.player.velocity.z * editor.player.velocity.z,
                ),
            ),
        )
    if model.gait_preview {
        run_weight = 1
        stride_phase = model.gait_phase
        horizontal_speed = model.gait_speed
    }
    gait := mouse_gait_weights(animation, horizontal_speed, airborne_weight)
    walk_weight, trot_weight, bound_weight := gait.walk, gait.trot, gait.bound
    if model.player_controlled && editor.capture_player_walk_pose {
        run_weight = 1
        stride_phase = math.PI * 1.75
        walk_weight = 1
        trot_weight = 0
        bound_weight = 0
    } else if model.player_controlled && editor.capture_player_run_compress_pose {
        run_weight = 1
        stride_phase = math.PI * .50
        walk_weight = 0
        trot_weight = 0
        bound_weight = 1
    } else if model.player_controlled &&
       (editor.capture_player_turn_left_pose || editor.capture_player_turn_right_pose) {
        run_weight = 1
        stride_phase = math.PI * 1.75
        walk_weight = 0
        trot_weight = 0
        bound_weight = 1
    } else if model.player_controlled && editor.capture_player_brake_pose {
        run_weight = 1
        stride_phase = math.PI * .50
        walk_weight = 0
        trot_weight = 0
        bound_weight = 1
    }
    vertical_pose := model.player_controlled ? editor.player_vertical_pose : f32(0)
    if model.player_controlled && (editor.capture_player_jump_pose || editor.capture_player_fall_pose) {
        airborne_weight = 1
        walk_weight = 0
        trot_weight = 0
        bound_weight = 1
        vertical_pose = clamp(
            editor.player.velocity.y / max(editor.tweak.player_animation.vertical_full_speed, f32(.1)),
            -1,
            1,
        )
    }
    jump_rise := vertical_pose * airborne_weight
    ascent_weight := max(jump_rise, f32(0))
    descent_weight := max(-jump_rise, f32(0))

    idle_phase := editor.map_time * 2.2
    // Sagittal spinal flexion is pronounced in a bound, but deliberately
    // restrained in alternating walk and trot gaits.
    bound_phase := mouse_gait.bound_animation_phase(stride_phase, bound_weight)
    bound := math.sin(bound_phase) * run_weight * mouse_gait.axial_flex_scale(gait)
    spine_extension := -bound
    bound_aerial_lift :=
        mouse_gait.bound_aerial_weight(bound_phase) *
        bound_weight *
        run_weight *
        .085
    body_bob :=
        (
            -bound * .018 +
            math.abs(math.sin(stride_phase * 2)) * mouse_gait.vertical_bob_scale(gait) +
            bound_aerial_lift
        ) * run_weight +
        math.sin(idle_phase) * .006 * (1 - run_weight) +
        animation.run_body_lift * run_weight * (1 - airborne_weight)
    body_bob -= scurry_compression
    blink_period := f32(4.6)
    blink_time := editor.map_time - f32(math.floor(f64(editor.map_time / blink_period))) * blink_period
    blink_weight := clamp(1 - math.abs(blink_time - .10) / .10, 0, 1)
    if model.player_controlled && editor.capture_player_blink_pose do blink_weight = 1
    sniff := math.sin(editor.map_time * 5.4) * .008 * (1 - run_weight)
    breathing := math.sin(editor.map_time * 1.65) * .018 * (1 - run_weight) * (1 - airborne_weight)
    head_sway := math.sin(stride_phase) * .012 * run_weight
    ear_twitch := math.sin(idle_phase * 1.7) * .006 * (1 - run_weight) + math.abs(bound) * .008 + blink_weight * .009

    // One connected hull runs from rump to nose. Its rings carry named,
    // normalized vertex groups and are skinned by this five-bone mouse rig.
    head_y :=
        .57 -
        run_weight * .17 -
        spine_extension * .018 * run_weight -
        bound * .012 +
        body_bob +
        airborne_weight * .015 -
        brake_compression * .72 +
        posted_weight * .27
    head_z :=
        .02 +
        run_weight * .18 +
        spine_extension * .150 * run_weight -
        brake_pose * .025 -
        posted_weight * .035 +
        scurry_lean * .18
    if model.driving_pose {
        // The driver reaches into the controls instead of holding the tall,
        // alert posted pose used by idle NPCs.
        head_y -= .055
        head_y -= math.abs(drive_reaction) * .018
        head_z += .055 + drive_reaction * .065
    }
    head_turn_x := spine_side * .24
    skeleton := [5]Mouse_Bone_Pose {
        {
            parent = -1,
            bind_position = {0, .40, -.48},
            position = {
                spine_side * .18,
                .36 - run_weight * .010 + body_bob - bound * .018 - brake_compression * .48 - posted_weight * .015,
                -.48 - spine_extension * .070 * run_weight + brake_pose * .035,
            },
            pitch = bound * .075 + slope_pitch * .65 - posted_weight * .05 + scurry_lean * .45,
            roll = body_roll * .82,
        },
        {
            parent = 0,
            bind_position = {0, .43, -.25},
            position = {
                spine_side * .48,
                .39 - run_weight * .035 + body_bob + bound * .025 - brake_compression * .64 + posted_weight * .15,
                -.25 +
                spine_extension * .035 * run_weight +
                brake_pose * .025 -
                posted_weight * .035 +
                drive_reaction * .018,
            },
            pitch = run_weight * .055 + bound * .085 + slope_pitch * .82 - posted_weight * .10 + scurry_lean * .72,
            roll = body_roll,
        },
        {
            parent = 1,
            bind_position = {0, .50, -.04},
            position = {
                spine_side,
                .44 - run_weight * .085 + body_bob + bound * .055 - brake_compression + posted_weight * .25,
                -.04 +
                run_weight * .06 +
                spine_extension * .080 * run_weight -
                brake_pose * .015 -
                posted_weight * .055 +
                drive_reaction * .035,
            },
            pitch = run_weight * .075 + bound * .110 + slope_pitch - posted_weight * .14 + scurry_lean,
            roll = body_roll,
        },
        {
            parent = 2,
            bind_position = {0, .58, .10},
            position = {
                head_sway * .25 + spine_side * .62,
                .50 - run_weight * .135 + body_bob + bound * .025 - brake_compression * .82 + posted_weight * .27,
                .10 +
                run_weight * .10 +
                spine_extension * .110 * run_weight -
                brake_pose * .02 -
                posted_weight * .055 +
                drive_reaction * .050,
            },
            pitch = run_weight * .085 + bound * .070 + slope_pitch * .72 - posted_weight * .08 + scurry_lean * .82,
            roll = body_roll * .58,
        },
        {
            parent = 3,
            bind_position = {0, .69, .20},
            position = {head_sway + head_turn_x, head_y, head_z + .20},
            pitch = run_weight * .055 - bound * .060 + slope_pitch * .42 + scurry_lean * .42,
            roll = body_roll * .22,
        },
    }
    world_mouse_skinned_hull(p, rotation, &skeleton, fur, fur_dark, fur_light, model.pattern, breathing)

    ear_offsets := [2]f32{-.125, .125}
    for ear_x in ear_offsets {
        side := ear_x / .125
        side_motion := ear_twitch * side
        // Keep the bilateral ears subtly asymmetric without pulling the far
        // pinna forward through the head silhouette in a true profile.
        ear_swivel := math.sin(idle_phase * 1.18 + side * 1.05) * .010 * (1 - run_weight)
        ear_depth_stagger := side * .015 + ear_swivel
        ear_height_stagger := side < 0 ? f32(.012) : f32(-.005)
        world_mouse_ear(
            p,
            rotation,
            {
                ear_x + head_sway + head_turn_x,
                head_y +
                .145 +
                side_motion +
                ear_height_stagger -
                airborne_weight * .018 +
                ear_x * math.sin(body_roll) * .65,
                head_z + .045 + ear_depth_stagger - airborne_weight * .018,
            },
            side,
            side_motion,
            fur_dark,
            ear,
        )
    }

    // Bind the muzzle features to the same skinned head tip that closes the
    // hull. Reconstructing this point from head_y/head_z ignored head pitch,
    // so the nose floated above the snout during the gathered bound pose.
    posed_muzzle_tip := mouse_skin_vertex(
        {
            bind_position = {0, .62, .58},
            groups = {{.Head, 1}, {.Neck, 0}},
        },
        &skeleton,
    )
    muzzle_x := posed_muzzle_tip.x
    muzzle_y := posed_muzzle_tip.y + .010
    muzzle_z := posed_muzzle_tip.z + sniff
    world_tapered_disc_depth_rotated(
        local_point(p, rotation, muzzle_x, muzzle_y, muzzle_z + .012),
        .028,
        .022,
        .018,
        .015,
        .040,
        rotation,
        nose,
    )
    nostril_offsets := [2]f32{-.011, .011}
    for nostril_x in nostril_offsets {
        world_vertical_disc_rotated(
            local_point(p, rotation, nostril_x + muzzle_x, muzzle_y + .003, muzzle_z + .025),
            .0045,
            .0035,
            .004,
            rotation,
            features,
        )
    }

    eye_offsets := [2]f32{-.165, .165}
    eye_radius_y := .004 + (1 - blink_weight) * .033
    for eye_x in eye_offsets {
        // Faceted ellipsoids keep the lateral eyes round through the complete
        // camera orbit. A side-canted disc only looked correct in exact
        // profile and collapsed into a black bar from the front.
        world_ellipsoid_rotated(
            local_point(
                p,
                rotation,
                eye_x + head_sway + head_turn_x,
                head_y + .018 + eye_x * math.sin(body_roll) * .32,
                head_z + .31,
            ),
            .034,
            eye_radius_y,
            .032,
            rotation,
            features,
        )
    }

    if model.accessory == .Goggles {
        // The goggles rest above the eyes so the face stays expressive. Every
        // component follows head sway and the spine-driven running reach.
        goggle_y := head_y + .112
        goggle_z := head_z + .31
        goggle_roll_slope := math.sin(body_roll) * .32
        goggle_strap_left := local_point(
            p,
            rotation,
            -.25 + head_sway + head_turn_x,
            goggle_y - .25 * goggle_roll_slope,
            head_z + .285,
        )
        goggle_strap_right := local_point(
            p,
            rotation,
            .25 + head_sway + head_turn_x,
            goggle_y + .25 * goggle_roll_slope,
            head_z + .285,
        )
        world_box_between(goggle_strap_left, goggle_strap_right, model_forward, .032, .022, leather_dark)
        // Keep each cup tight to its side of the skull. At a true profile the
        // former broad, deeply canted far cup projected beyond the muzzle and
        // looked as though it rendered through the head.
        goggle_offsets := [2]f32{-.18, .18}
        for goggle_x in goggle_offsets {
            goggle_side := goggle_x / .18
            // The two cups follow the curved brow rather than sharing one
            // billboard plane. A restrained outward cant keeps the near lens
            // readable in profile while preserving their forward function.
            goggle_cant := f32(.85)
            goggle_rotation := rotation - goggle_side * goggle_cant
            goggle_normal_x := goggle_side * f32(math.sin(f64(goggle_cant)))
            goggle_normal_z := f32(math.cos(f64(goggle_cant)))
            world_vertical_disc_rotated(
                local_point(
                    p,
                    rotation,
                    goggle_x + head_sway + head_turn_x,
                    goggle_y + goggle_x * goggle_roll_slope,
                    goggle_z,
                ),
                .050,
                .042,
                .022,
                goggle_rotation,
                leather,
            )
            world_vertical_disc_rotated(
                local_point(
                    p,
                    rotation,
                    goggle_x + goggle_normal_x * .020 + head_sway + head_turn_x,
                    goggle_y + goggle_x * goggle_roll_slope,
                    goggle_z + goggle_normal_z * .020,
                ),
                .036,
                .028,
                .010,
                goggle_rotation,
                goggle_glass,
            )
            world_vertical_disc_rotated(
                local_point(
                    p,
                    rotation,
                    goggle_x + goggle_normal_x * .030 - goggle_side * .009 + head_sway + head_turn_x,
                    goggle_y + .010 + goggle_x * goggle_roll_slope,
                    goggle_z + goggle_normal_z * .030,
                ),
                .008,
                .008,
                .005,
                goggle_rotation,
                tooth,
            )

            // Curved side shields keep the headset identifiable when the
            // camera reaches a true profile. They share the cup's material and
            // glass, so this reads as wraparound goggles rather than a badge.
            side_window_rotation := rotation - goggle_side * (math.PI * .5)
            side_window_x := goggle_x + goggle_side * .035 + head_sway + head_turn_x
            side_window_y := goggle_y + goggle_x * goggle_roll_slope
            side_window_z := goggle_z - .008
            world_vertical_disc_rotated(
                local_point(p, rotation, side_window_x, side_window_y, side_window_z),
                .024,
                .021,
                .008,
                side_window_rotation,
                leather,
            )
            world_vertical_disc_rotated(
                local_point(p, rotation, side_window_x + goggle_side * .010, side_window_y, side_window_z),
                .017,
                .014,
                .005,
                side_window_rotation,
                goggle_glass,
            )
        }
        bridge_left := local_point(
            p,
            rotation,
            -.083 + head_sway + head_turn_x,
            goggle_y - .083 * goggle_roll_slope,
            goggle_z + .015,
        )
        bridge_right := local_point(
            p,
            rotation,
            .083 + head_sway + head_turn_x,
            goggle_y + .083 * goggle_roll_slope,
            goggle_z + .015,
        )
        world_box_between(bridge_left, bridge_right, model_forward, .018, .018, brass)
        // Side straps keep the goggles legible in profile and describe how the
        // frames actually wrap around the skull instead of hovering over it.
        strap_sides := [2]f32{-1, 1}
        for strap_side in strap_sides {
            strap_front := local_point(
                p,
                rotation,
                strap_side * .195 + head_sway + head_turn_x,
                goggle_y - .004,
                goggle_z - .018,
            )
            strap_crown := local_point(
                p,
                rotation,
                strap_side * .21 + head_sway + head_turn_x,
                head_y + .105,
                head_z + .17,
            )
            strap_back := local_point(
                p,
                rotation,
                strap_side * .18 + head_sway + head_turn_x,
                head_y + .065,
                head_z - .015,
            )
            world_box_between(strap_front, strap_crown, model_forward, .018, .012, leather_dark)
            world_box_between(strap_crown, strap_back, model_forward, .018, .012, leather_dark)
        }
    } else if model.accessory == .Flower {
        // Keep the flower tucked beside one ear, but cant the whole bloom
        // outward so its petal plane clears the head instead of cutting
        // through it.
        flower_side := model.accessory_side
        if flower_side == 0 do flower_side = -1
        flower_side = flower_side < 0 ? f32(-1) : f32(1)
        flower_center_x := flower_side * .115 + head_sway + head_turn_x
        flower_center_y := head_y + .205
        flower_center_z := head_z + .095
        flower_cant := flower_side * -.95
        flower_yaw := rotation + flower_cant
        flower_plane_x := math.cos(flower_cant)
        flower_plane_z := math.sin(flower_cant)
        stem_bottom := local_point(
            p,
            rotation,
            flower_center_x - flower_side * .045,
            head_y + .105,
            flower_center_z - .025,
        )
        stem_top := local_point(p, rotation, flower_center_x, flower_center_y, flower_center_z)
        world_box_between(stem_bottom, stem_top, model_forward, .018, .012, {70, 123, 72, 255})
        petal_color: rl.Color = {238, 111, 137, 255}
        for petal_index in 0 ..< 5 {
            petal_angle := f32(petal_index) * math.PI * 2 / 5 + math.PI * .5
            petal_across := math.cos(petal_angle) * .052
            petal_x := flower_center_x + petal_across * flower_plane_x
            petal_y := flower_center_y + math.sin(petal_angle) * .052
            petal_z := flower_center_z + petal_across * flower_plane_z
            world_vertical_disc_rotated(
                local_point(p, rotation, petal_x, petal_y, petal_z),
                .044,
                .057,
                .018,
                flower_yaw,
                petal_color,
            )
        }
        world_vertical_disc_rotated(
            local_point(
                p,
                rotation,
                flower_center_x - math.sin(flower_cant) * .014,
                flower_center_y,
                flower_center_z + math.cos(flower_cant) * .014,
            ),
            .033,
            .033,
            .018,
            flower_yaw,
            {232, 180, 62, 255},
        )
    } else if model.accessory == .Acorn_Cap {
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .135
        crown_z := head_z + .105
        shell := rl.Color{105, 69, 39, 255}
        shell_dark := rl.Color{67, 43, 27, 255}
        // Keep the fitted edge inside the crown silhouette. A broad lower
        // flange reads as a brim; an acorn cup instead pinches gently around
        // the head and swells into a taller woody dome.
        world_ellipsoid_rotated(
            local_point(p, rotation, crown_x, crown_y - .002, crown_z),
            .202,
            .026,
            .188,
            rotation,
            color_lerp(shell_dark, shell, .62),
        )
        world_ellipsoid_rotated(
            local_point(p, rotation, crown_x, crown_y + .040, crown_z),
            .218,
            .115,
            .203,
            rotation,
            shell,
            .Acorn,
        )
        stem_bottom := local_point(p, rotation, crown_x + .018, crown_y + .150, crown_z - .022)
        stem_top := local_point(p, rotation, crown_x + .045, crown_y + .210, crown_z - .080)
        world_box_between(stem_bottom, stem_top, model_forward, .020, .018, shell_dark)
    } else if model.accessory == .Bottle_Cap {
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .205
        crown_z := head_z + .105
        cap := rl.Color{184, 39, 45, 255}
        world_bottle_cap_hull(local_point(p, rotation, crown_x, crown_y - .013, crown_z), rotation, cap)
    } else if model.accessory == .Paper_Boat {
        paper := rl.Color{232, 224, 198, 255}
        paper_shadow := rl.Color{190, 180, 157, 255}
        paper_light := rl.Color{248, 241, 216, 255}
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .220
        crown_z := head_z + .105
        front_z := crown_z + .115
        back_z := crown_z - .085
        left_front := local_point(p, rotation, crown_x - .135, crown_y + .005, front_z)
        right_front := local_point(p, rotation, crown_x + .135, crown_y + .005, front_z)
        keel_front := local_point(p, rotation, crown_x, crown_y - .055, front_z)
        peak_front := local_point(p, rotation, crown_x - .018, crown_y + .115, front_z)
        left_back := local_point(p, rotation, crown_x - .135, crown_y + .005, back_z)
        right_back := local_point(p, rotation, crown_x + .135, crown_y + .005, back_z)
        keel_back := local_point(p, rotation, crown_x, crown_y - .055, back_z)
        peak_back := local_point(p, rotation, crown_x - .018, crown_y + .115, back_z)

        // True folded triangular panels replace the former yawed boxes, which
        // looked like a propeller because they never rose into a boat profile.
        world_triangle(left_front, keel_front, peak_front, paper)
        world_triangle(keel_front, right_front, peak_front, paper_light)
        world_triangle(peak_back, keel_back, left_back, paper_shadow)
        world_triangle(peak_back, right_back, keel_back, paper)
        world_quad(left_back, left_front, peak_front, peak_back, paper_shadow)
        world_quad(peak_back, peak_front, right_front, right_back, paper_light)
        world_quad(left_front, left_back, keel_back, keel_front, paper_shadow)
        world_quad(keel_front, keel_back, right_back, right_front, paper)

        // A broad tapered hull separates the boat silhouette from the much
        // narrower raised fold, avoiding the profile of a conical hat.
        world_tapered_box_rotated(
            local_point(p, rotation, crown_x, crown_y - .042, crown_z),
            .095,
            .380,
            .165,
            .535,
            .205,
            rotation,
            paper,
        )
        // Contrasting gunwale and central crease remain readable when the
        // mouse occupies only a small portion of the frame.
        world_box_rotated(
            local_point(p, rotation, crown_x, crown_y + .004, crown_z + .122),
            {.525, .022, .026},
            rotation,
            paper_light,
        )
        world_box_rotated(
            local_point(p, rotation, crown_x - .018, crown_y + .038, crown_z + .128),
            {.016, .145, .018},
            rotation,
            paper_shadow,
        )
    } else if model.accessory == .Chef_Hat {
        cloth := rl.Color{226, 224, 211, 255}
        cloth_shadow := rl.Color{174, 174, 168, 255}
        cloth_light := rl.Color{244, 241, 224, 255}
        crown_x := head_sway + head_turn_x
        crown_z := head_z + .085
        // The double band hugs the skull and visually anchors the toque.
        world_box_rotated(
            local_point(p, rotation, crown_x, head_y + .190, crown_z),
            {.205, .060, .180},
            rotation,
            cloth_shadow,
        )
        world_box_rotated(
            local_point(p, rotation, crown_x, head_y + .218, crown_z + .010),
            {.190, .046, .172},
            rotation,
            cloth,
        )
        // Five overlapping matte lobes form one soft asymmetric crown without
        // the glossy eye material's bulb-like white highlights.
        puff_offsets := [5]f32{-.145, -.072, 0, .078, .150}
        for puff_x in puff_offsets {
            side := puff_x / .150
            world_ellipsoid_plain_rotated(
                local_point(
                    p,
                    rotation,
                    crown_x + puff_x,
                    head_y + .305 + (1 - math.abs(side)) * .020 + side * .008,
                    crown_z - math.abs(side) * .014,
                ),
                .105,
                .118 + (1 - math.abs(side)) * .020,
                .125,
                rotation,
                side < -.25 ? cloth_shadow : (side > .45 ? cloth_light : cloth),
            )
        }
        // A shallow crown seam adds a tailored center without competing with
        // the scalloped outline.
        world_box_rotated(
            local_point(p, rotation, crown_x, head_y + .355, crown_z + .135),
            {.010, .090, .024},
            rotation,
            cloth_shadow,
        )
    } else if model.accessory == .Ushanka {
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .150
        crown_z := head_z + .075
        wool := rl.Color{101, 72, 55, 255}
        wool_dark := rl.Color{58, 41, 34, 255}
        fur_trim := rl.Color{181, 153, 119, 255}
        fur_shadow := rl.Color{137, 111, 86, 255}
        ushanka_fur_light := rl.Color{207, 184, 149, 255}

        // One radial hull replaces the former capped side-to-side extrusion.
        // Five horizontal rings round the crown in every camera direction.
        // The lowest two rings deform downward only near local +/-X, growing
        // both ear flaps directly from the same continuous surface.
        RINGS :: 7
        SEGMENTS :: 24
        ring_y := [RINGS]f32{.145, .105, .070, .040, .010, -.020, -.045}
        ring_radius_x := [RINGS]f32{.135, .190, .215, .230, .245, .240, .225}
        ring_radius_z := [RINGS]f32{.105, .145, .170, .185, .205, .210, .205}
        hull: [RINGS][SEGMENTS]third_person.Vec3
        side_weights: [SEGMENTS]f32
        front_weights: [SEGMENTS]f32
        for ring in 0 ..< RINGS {
            for segment in 0 ..< SEGMENTS {
                angle := f32(segment) * math.PI * 2 / f32(SEGMENTS)
                cosine, sine := math.cos(angle), math.sin(angle)
                side_weight := math.abs(cosine)
                side_weight *= side_weight
                front_weight := max(sine, f32(0))
                side_weights[segment] = side_weight
                front_weights[segment] = front_weight
                flap_drop := f32(0)
                if ring == RINGS - 4 do flap_drop = side_weight * .025
                if ring == RINGS - 3 do flap_drop = side_weight * .055
                if ring == RINGS - 2 do flap_drop = side_weight * .100
                if ring == RINGS - 1 {
                    // Hold the hem near full depth across a broad side arc
                    // instead of converging to one low vertex in profile.
                    // Alternate vertices retain a subtle fur scallop.
                    flap_span := clamp(math.abs(cosine) / .72, 0, 1)
                    tuft_drop := f32(0)
                    if segment % 5 == 0 {
                        tuft_drop = .012
                    } else if segment % 5 == 3 {
                        tuft_drop = .006
                    }
                    flap_drop = flap_span * (.160 + tuft_drop)
                }
                radius_x := ring_radius_x[ring]
                radius_z := ring_radius_z[ring]
                tuft_out := f32(.002)
                if segment % 5 == 0 {
                    tuft_out = .008
                } else if segment % 5 == 2 {
                    tuft_out = -.004
                }
                if ring >= RINGS - 4 && side_weight > .24 {
                    radius_x += tuft_out * side_weight
                    radius_z += tuft_out * side_weight
                }
                if ring >= 2 && ring <= 4 && front_weight > .35 {
                    radius_z += tuft_out * front_weight
                }
                // The traditional raised forehead flap is part of this same
                // surface: push only its central front vertices outward and
                // ease the displacement to zero before the temples.
                if ring >= 2 && ring <= 4 && front_weight > .55 {
                    panel_weight := (front_weight - .55) / .45
                    panel_depth := ring == 2 ? f32(.018) : (ring == 3 ? f32(.026) : f32(.016))
                    radius_z += panel_weight * panel_depth
                }
                hull[ring][segment] = local_point(
                    p,
                    rotation,
                    crown_x + cosine * radius_x,
                    crown_y + ring_y[ring] - flap_drop,
                    crown_z + sine * radius_z,
                )
            }
        }

        crown_top := local_point(p, rotation, crown_x, crown_y + .160, crown_z - .005)
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            top_color := front_weights[segment] > .25 ? wool : wool_dark
            world_triangle(crown_top, hull[0][segment], hull[0][next], top_color)
        }
        for ring in 0 ..< RINGS - 1 {
            for segment in 0 ..< SEGMENTS {
                next := (segment + 1) % SEGMENTS
                front_weight := max(front_weights[segment], front_weights[next])
                side_weight := max(side_weights[segment], side_weights[next])
                surface_color := front_weight > .05 ? wool : wool_dark
                fur_variant := (segment * 5 + ring * 3) % 7
                // A narrow raised-looking fur brow and the two lined flaps are
                // material regions of the hull itself, not overlaid geometry.
                if (ring == 2 || ring == 3) && front_weight > .62 {
                    surface_color = fur_variant == 0 ? ushanka_fur_light : (fur_variant == 2 ? fur_shadow : fur_trim)
                } else if ring >= 3 && side_weight > .28 {
                    surface_color = fur_variant == 0 ? ushanka_fur_light : (fur_variant < 3 ? fur_shadow : fur_trim)
                } else if ring == 2 && side_weight > .45 {
                    // A cloth welt makes the flap attachment look sewn into
                    // the crown rather than painted onto the same surface.
                    surface_color = wool_dark
                } else if ring >= RINGS - 2 {
                    surface_color = wool_dark
                }
                world_quad(
                    hull[ring][segment],
                    hull[ring][next],
                    hull[ring + 1][next],
                    hull[ring + 1][segment],
                    surface_color,
                )
            }
        }
        // Close the underside so this remains one watertight hull. The cap is
        // tucked into the skull and normally invisible.
        hull_bottom := local_point(p, rotation, crown_x, crown_y - .058, crown_z)
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            world_triangle(hull_bottom, hull[RINGS - 1][next], hull[RINGS - 1][segment], wool_dark)
        }
    } else if model.accessory == .Beret {
        // Seat the band on the rear crown of the skull, just behind the ears.
        // The head's local +Z points toward the muzzle, so a small negative
        // depth offset is essential: centering this over the brow makes the
        // hat float above the ear in profile and read like a visor in front.
        crown_x := head_sway + head_turn_x - .020
        crown_y := head_y + .195
        crown_z := head_z + .015
        felt := rl.Color{133, 38, 49, 255}
        felt_fold := rl.Color{112, 31, 43, 255}
        felt_dark := rl.Color{77, 26, 35, 255}
        felt_light := rl.Color{178, 64, 70, 255}
        // Preserve the deliberate jaunty cock while inheriting most of the
        // animated head roll, so the band stays planted through turns and
        // uneven-ground poses instead of remaining level in world space.
        beret_roll := f32(.15) + body_roll * .65

        // A close-fitting oval band seats the beret on the skull. Keeping this
        // rounded avoids the rigid shelf and dangling corner of a box brim.
        world_ellipsoid_plain_oriented(
            local_point(p, rotation, crown_x + .010, crown_y - .006, crown_z - .004),
            .202,
            .026,
            .168,
            rotation,
            beret_roll,
            felt_dark,
        )
        // The crown leans to the mouse's left: a broad main disk establishes
        // the silhouette while the overlapping lobe makes the drape feel soft.
        world_ellipsoid_plain_oriented(
            local_point(p, rotation, crown_x - .045, crown_y + .036, crown_z - .004),
            .276,
            .073,
            .222,
            rotation,
            beret_roll,
            felt,
        )
        world_ellipsoid_plain_oriented(
            local_point(p, rotation, crown_x - .142, crown_y + .016, crown_z - .002),
            .145,
            .058,
            .160,
            rotation,
            beret_roll,
            felt_fold,
        )
        // A restrained highlight follows the upper fold instead of reading as
        // a separate cap sitting on top.
        world_ellipsoid_plain_oriented(
            local_point(p, rotation, crown_x - .105, crown_y + .086, crown_z + .025),
            .138,
            .025,
            .110,
            rotation,
            beret_roll,
            felt_light,
        )
        // The short cabillou follows the rolled crown normal instead of
        // remaining conspicuously vertical after the rest of the hat cocks.
        cabillou_root := local_point(p, rotation, crown_x - .070, crown_y + .108, crown_z - .018)
        cabillou_tip := local_point(
            p,
            rotation,
            crown_x - .070 - math.sin(beret_roll) * .042,
            crown_y + .108 + math.cos(beret_roll) * .042,
            crown_z - .018,
        )
        world_box_between(cabillou_root, cabillou_tip, model_forward, .014, .014, felt_dark)
    } else if model.accessory == .Alpine_Hat {
        crown_x := head_sway + head_turn_x
        // Seat the brim into the crown of the head instead of perching the
        // whole assembly above the ears.
        crown_y := head_y + .155
        crown_z := head_z + .070
        felt := rl.Color{67, 105, 71, 255}
        felt_dark := rl.Color{38, 69, 48, 255}
        felt_light := rl.Color{91, 125, 86, 255}
        band := rl.Color{103, 61, 39, 255}
        band_light := rl.Color{143, 91, 54, 255}
        feather := rl.Color{190, 58, 43, 255}
        feather_light := rl.Color{224, 86, 54, 255}

        // Brim, crown, shoulder, and top are one continuous closed felt shell.
        // The profile contracts and shifts rearward as it rises, producing the
        // characteristic Alpine taper without stacked primitive intersections.
        world_alpine_hat_hull(
            local_point(p, rotation, crown_x, crown_y - .015, crown_z + .005),
            rotation,
            felt_dark,
            felt,
            felt_light,
        )

        // Build the hatband as an oval collar so it remains continuous in
        // front and three-quarter views. The small buckle gives it a focal
        // point without obscuring the face.
        world_ellipsoid_plain_rotated(
            local_point(p, rotation, crown_x, crown_y + .005, crown_z),
            .250,
            .038,
            .201,
            rotation,
            band,
        )
        world_box_rotated(
            local_point(p, rotation, crown_x + .135, crown_y + .010, crown_z + .172),
            {.055, .066, .018},
            rotation,
            band_light,
        )
        // Continue the band along the feather side. The oval collar supplies
        // the curved lower edge; this shallow strip keeps the leather legible
        // in profile instead of collapsing to a small brown diamond.
        world_box_rotated(
            local_point(p, rotation, crown_x + .218, crown_y + .010, crown_z),
            {.028, .058, .285},
            rotation,
            band,
        )

        // The plume is a single smooth vane with its broad face in the hat's
        // side plane. This avoids both a twig-like front view and the blocky
        // stepped profile produced by assembled vane segments.
        feather_base := local_point(p, rotation, crown_x + .155, crown_y + .030, crown_z + .145)
        feather_tip := local_point(p, rotation, crown_x + .280, crown_y + .365, crown_z + .108)
        world_alpine_feather_hull(
            local_point(p, rotation, crown_x + .225, crown_y + .205, crown_z + .122),
            rotation,
            feather,
            feather_light,
        )
        world_box_between(feather_base, feather_tip, model_forward, .012, .020, feather)
    } else if model.accessory == .Flat_Cap {
        crown_x := head_sway + head_turn_x
        crown_y := head_y + .155
        crown_z := head_z + .070
        tweed := rl.Color{118, 103, 82, 255}
        tweed_dark := rl.Color{62, 54, 46, 255}
        tweed_light := rl.Color{137, 120, 94, 255}
        tweed_front := rl.Color{126, 110, 87, 255}

        world_flat_cap_hull(
            local_point(p, rotation, crown_x, crown_y, crown_z),
            rotation,
            tweed_dark,
            tweed,
            tweed_front,
            tweed_light,
        )
    }

    if model.scarf_enabled {
        // The scarf is tied at the neck and has two loose tails.  The tails
        // use local airflow so the same response works as the mouse turns:
        // running speed and the world's wind both feed the flap amplitude.
        scarf := model.scarf_color
        scarf.a = 255
        scarf_dark := color_lerp(scarf, {24, 10, 18, 255}, .42)
        scarf_light := color_lerp(scarf, {255, 224, 211, 255}, .30)
        wind_x, wind_z := editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]
        wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
        wind_forward := wind_x * model_forward.x + wind_z * model_forward.z
        wind_right := wind_x * model_right.x + wind_z * model_right.z
        speed_air := horizontal_speed * .42
        wind_air := wind_speed * .075
        flap := clamp(max(speed_air, wind_air), 0, 1)
        // Keep scarf animation local to the rendered mouse. Previously every
        // collar read the player's rotation and every tail shared one phase,
        // which made a group of scarf-wearing mice move as one object.
        position_phase_seed := math.sin(f64(model.position.x) * 12.9898 + f64(model.position.z) * 78.233) * 43758.5453
        scarf_phase_offset := f32(position_phase_seed - math.floor(position_phase_seed)) * math.PI * 2
        scarf_rotation := scarf_phase_offset
        if model.player_controlled {
            scarf_phase_offset = 0
            scarf_rotation = editor.mouse_scarf_rotation
        }
        flap_phase := editor.map_time * (5.2 + flap * 3.8) + wind_forward * .08 + scarf_phase_offset
        sway := math.sin(flap_phase) * (.018 + flap * .055)
        wind_sway := clamp(wind_right * .006, -.07, .07)

        // Ring five of the body hull is the neck cross-section. Recreate that
        // same X/Y ellipse, skin it with the same Neck/Chest weights, and give
        // the scarf width along local Z (the mouse's head-to-tail axis).
        SCARF_COLLAR_SEGMENTS :: 32
        SCARF_NECK_Z :: f32(.10)
        SCARF_NECK_CENTER_Y :: f32(.59)
        SCARF_NECK_RADIUS_X :: f32(.205)
        SCARF_NECK_RADIUS_Y :: f32(.210)
        SCARF_SURFACE_CLEARANCE :: f32(.022)
        SCARF_HALF_WIDTH :: f32(.055)
        collar_rear_local, collar_front_local: [SCARF_COLLAR_SEGMENTS]third_person.Vec3
        collar_rear, collar_front: [SCARF_COLLAR_SEGMENTS]third_person.Vec3
        collar_color: [SCARF_COLLAR_SEGMENTS]rl.Color
        for segment in 0 ..< SCARF_COLLAR_SEGMENTS {
            angle := f32(segment) * math.PI * 2 / f32(SCARF_COLLAR_SEGMENTS) + scarf_rotation
            ring_x := math.cos(angle) * (SCARF_NECK_RADIUS_X + SCARF_SURFACE_CLEARANCE)
            ring_y := SCARF_NECK_CENTER_Y + math.sin(angle) * (SCARF_NECK_RADIUS_Y + SCARF_SURFACE_CLEARANCE)
            rear_vertex := Mouse_Skin_Vertex {
                bind_position = {ring_x, ring_y, SCARF_NECK_Z - SCARF_HALF_WIDTH},
                groups        = {{.Neck, .66}, {.Chest, .34}},
            }
            front_vertex := rear_vertex
            front_vertex.bind_position.z = SCARF_NECK_Z + SCARF_HALF_WIDTH
            collar_rear_local[segment] = mouse_skin_vertex(rear_vertex, &skeleton)
            collar_front_local[segment] = mouse_skin_vertex(front_vertex, &skeleton)
            rear := collar_rear_local[segment]
            front := collar_front_local[segment]
            collar_rear[segment] = local_point(p, rotation, rear.x, rear.y, rear.z)
            collar_front[segment] = local_point(p, rotation, front.x, front.y, front.z)
            light_amount := clamp(.52 + math.cos(angle - .65) * .28 + math.sin(angle) * .12, 0, 1)
            collar_color[segment] = color_lerp(scarf_dark, scarf_light, light_amount)
        }
        for segment in 0 ..< SCARF_COLLAR_SEGMENTS {
            next := (segment + 1) % SCARF_COLLAR_SEGMENTS
            world_quad_colored(
                collar_rear[segment],
                collar_rear[next],
                collar_front[next],
                collar_front[segment],
                collar_color[segment],
                collar_color[next],
                collar_color[next],
                collar_color[segment],
            )
        }

        // Attach both tails to adjacent points on the dorsal rear edge of the
        // skinned collar. Their roots inherit the exact posed neck location;
        // only the free spans react to speed and wind.
        scarf_sides := [2]f32{-1, 1}
        for side_f, side_index in scarf_sides {
            // Leave the dorsal centerline open for the rear ear. Starting on
            // the upper side quadrants lets each tail pass beneath the ears
            // before the airflow carries it over the back.
            attach_index := SCARF_COLLAR_SEGMENTS / 8
            if side_index == 0 do attach_index = SCARF_COLLAR_SEGMENTS * 3 / 8
            root_local := collar_rear_local[attach_index]
            SCARF_TAIL_POINTS :: 7
            SCARF_BODY_CLEARANCE :: f32(.030)
            tail_center, tail_left, tail_right: [SCARF_TAIL_POINTS]third_person.Vec3
            tail_color: [SCARF_TAIL_POINTS]rl.Color
            for point_index in 0 ..< SCARF_TAIL_POINTS {
                amount := f32(point_index) / f32(SCARF_TAIL_POINTS - 1)
                eased := amount * amount * (3 - 2 * amount)
                tail_phase := flap_phase + amount * 2.35 + f32(side_index) * .72
                local_x :=
                    root_local.x +
                    wind_sway * eased +
                    sway * side_f * (amount + eased * .45) +
                    math.sin(tail_phase) * flap * .026 * amount
                local_y := root_local.y - .070 * amount + math.sin(tail_phase * 1.13) * flap * .050 * amount
                local_z := root_local.z - (.500 + flap * .200) * amount + wind_forward * .014 * eased
                if body_y, push_up, body_hit := mouse_body_surface_height(&skeleton, local_x, local_y, local_z);
                   body_hit {
                    if push_up {
                        local_y = max(local_y, body_y + SCARF_BODY_CLEARANCE)
                    } else {
                        local_y = min(local_y, body_y - SCARF_BODY_CLEARANCE)
                    }
                }
                width := (.072 + flap * .014) * (1 - amount * .38)
                tail_center[point_index] = local_point(p, rotation, local_x, local_y, local_z)
                tail_left[point_index] = local_point(p, rotation, local_x - width, local_y, local_z)
                tail_right[point_index] = local_point(p, rotation, local_x + width, local_y, local_z)
                tail_color[point_index] = color_lerp(scarf, scarf_light, amount * .72)
            }
            for segment in 0 ..< SCARF_TAIL_POINTS - 1 {
                world_quad_colored(
                    tail_left[segment],
                    tail_right[segment],
                    tail_right[segment + 1],
                    tail_left[segment + 1],
                    tail_color[segment],
                    tail_color[segment],
                    tail_color[segment + 1],
                    tail_color[segment + 1],
                )
                amount := f32(segment) / f32(SCARF_TAIL_POINTS - 1)
                edge_width := .030 * (1 - amount * .35)
                world_box_between(
                    tail_center[segment],
                    tail_center[segment + 1],
                    model_forward,
                    edge_width,
                    edge_width * .68,
                    tail_color[segment],
                )
            }
        }
    }

    world_box_rotated(
        local_point(p, rotation, -.008 + muzzle_x, muzzle_y - .066, muzzle_z - .040),
        {.007, .010, .008},
        rotation,
        tooth,
    )
    world_box_rotated(
        local_point(p, rotation, .008 + muzzle_x, muzzle_y - .066, muzzle_z - .040),
        {.007, .010, .008},
        rotation,
        tooth,
    )

    sides := [2]f32{-1, 1}
    whisker_scale := model.preview ? f32(.38) : f32(1)
    for side_f in sides {
        whisker_root := local_point(p, rotation, side_f * .035 + muzzle_x, muzzle_y, muzzle_z - .025)
        for whisker_index in 0 ..< 3 {
            whisker_phase := editor.map_time * 4.2 + f32(whisker_index) * .82 + side_f * .38 + stride_phase * .18
            whisker_flex := math.sin(whisker_phase) * (.010 + .005 * run_weight)
            whisker_y := muzzle_y - .055 + f32(whisker_index) * .048
            whisker_mid := local_point(
                p,
                rotation,
                side_f * (.19 * whisker_scale + f32(whisker_index) * .012 * whisker_scale) + muzzle_x,
                (muzzle_y + whisker_y) * .5 + whisker_flex,
                muzzle_z - .060,
            )
            whisker_tip := local_point(
                p,
                rotation,
                side_f *
                    (.36 * whisker_scale + f32(whisker_index) * .022 * whisker_scale + whisker_flex * whisker_scale) +
                muzzle_x,
                whisker_y + whisker_flex,
                muzzle_z - .120 - f32(whisker_index) * .012,
            )
            world_box_between(whisker_root, whisker_mid, model_forward, .006, .006, fur_light)
            world_box_between(whisker_mid, whisker_tip, model_forward, .005, .005, fur_light)
        }
    }

    // Mice progress from a four-beat walk through diagonal trot to a bound.
    // Generate all three footfall patterns and blend them by speed so gait
    // transitions do not pop when the controller accelerates.
    air_tuck := airborne_weight * (.13 + ascent_weight * .05 - descent_weight * .085)
    for side_f, side_index in sides {
        left_side := side_f < 0
        // Walk footfalls: LF, RH, RF, LH. Trot synchronizes diagonal pairs;
        // bound synchronizes each homologous pair, fore then hind.
        front_walk_offset := left_side ? f32(0) : f32(.50)
        rear_walk_offset := left_side ? f32(.25) : f32(.75)
        front_trot_offset := left_side ? f32(0) : f32(.50)
        rear_trot_offset := left_side ? f32(.50) : f32(0)
        // Gallop and half-bound are brief transitional gaits in mice. During
        // the trot-to-bound blend, retain a lead-limb split that closes only
        // as full-bound synchronization takes over.
        bilateral_lag := side_f * mouse_gait.bound_bilateral_lag(bound_weight)
        front_motion := mouse_gait.blend_scaled(
            stride_phase,
            front_walk_offset,
            front_trot_offset,
            mouse_gait.BOUND_PHASE_OFFSET + bilateral_lag,
            gait,
            .68,
            .56,
            .34,
            animation.stride_radians_per_meter,
            animation.trot_stride_radians_per_meter,
            animation.bound_stride_radians_per_meter,
        )
        rear_motion := mouse_gait.blend_scaled(
            stride_phase,
            rear_walk_offset,
            rear_trot_offset,
            .50 + mouse_gait.BOUND_PHASE_OFFSET - bilateral_lag,
            gait,
            .76,
            .60,
            .36,
            animation.stride_radians_per_meter,
            animation.trot_stride_radians_per_meter,
            animation.bound_stride_radians_per_meter,
        )
        front_cycle := front_motion.reach * run_weight
        rear_cycle := rear_motion.reach * run_weight
        front_lift_scale :=
            .075 * walk_weight +
            .088 * trot_weight +
            .145 * bound_weight
        hind_lift_scale :=
            .090 * walk_weight +
            .105 * trot_weight +
            .165 * bound_weight
        front_lift := front_motion.lift * front_lift_scale * run_weight
        scapula_slide := front_cycle * .038
        inside_turn := max(side_f * turn_pose, f32(0))
        outside_turn := max(-side_f * turn_pose, f32(0))
        paw_turn_reach := animation.turn_paw_offset * (outside_turn - inside_turn * .45)
        idle_fore_shoulder := third_person.Vec3{side_f * .12, .31, .04}
        run_fore_shoulder := third_person.Vec3{side_f * .13, .31, .075}
        fore_socket_bind := third_person.Vec3 {
            idle_fore_shoulder.x +
                (run_fore_shoulder.x - idle_fore_shoulder.x) * run_weight +
                side_f * paw_turn_reach * .35 -
                side_f * posted_weight * .020,
            idle_fore_shoulder.y - inside_turn * .025 + posted_weight * .065,
            idle_fore_shoulder.z +
                (run_fore_shoulder.z - idle_fore_shoulder.z) * run_weight +
                scapula_slide +
                posted_weight * .090,
        }
        posed_fore_socket := mouse_skin_vertex(
            {bind_position = fore_socket_bind, groups = {{.Chest, .68}, {.Spine, .32}}},
            &skeleton,
        )
        fore_shoulder := local_point(p, rotation, posed_fore_socket.x, posed_fore_socket.y, posed_fore_socket.z)
        fore_elbow := local_point(
            p,
            rotation,
            side_f * (.095 * (1 - run_weight) + .125 * run_weight + paw_turn_reach * .6) -
            side_f * posted_weight * .018,
            .16 * (1 - run_weight) +
            .155 * run_weight +
            front_lift * .35 +
            air_tuck * .55 -
            brake_compression * .55 -
            inside_turn * .02 +
            posted_weight * .30,
            .17 * (1 - run_weight) +
            (.145 + front_cycle * .090) * run_weight +
            brake_pose * .055 +
            posted_weight * .015,
        )
        idle_groom := math.sin(idle_phase * .78 + side_f * .9) * .009 * (1 - run_weight)
        fore_paw_x :=
            side_f * (.09 * (1 - run_weight) + .105 * run_weight + descent_weight * .018 + paw_turn_reach) -
            side_f * posted_weight * .022
        fore_paw_y :=
            .038 * (1 - run_weight) +
            .042 * run_weight +
            front_lift +
            air_tuck +
            idle_groom -
            inside_turn * .018 +
            posted_weight * .405
        fore_paw_z :=
            .29 * (1 - run_weight) +
            (.235 + front_cycle + side_f * .014) * run_weight +
            idle_groom * side_f * .55 +
            brake_pose * .12 -
            posted_weight * .095
        fore_paw := local_point(p, rotation, fore_paw_x, fore_paw_y, fore_paw_z)
        if model.driving_pose {
            // Preserve the anatomical shoulder sockets computed above and
            // place each paw directly on the steering-wheel rim. Convert the
            // car-authored wheel dimensions into the scaled mouse-local frame
            // so the grip cannot drift when either side is adjusted.
            steering := clamp(model.drive_steering, -1, 1)
            wheel_rotation := steering * .55
            grip_radius := CAR_STEERING_WHEEL_RADIUS / CAR_PILOT_SCALE
            neutral_grip_x := side_f * grip_radius * f32(.8660254)
            neutral_grip_y := grip_radius * .5
            grip_x := neutral_grip_x * math.cos(wheel_rotation) - neutral_grip_y * math.sin(wheel_rotation)
            grip_y :=
                (CAR_STEERING_WHEEL_Y - CAR_PILOT_SEAT_Y) / CAR_PILOT_SCALE +
                neutral_grip_y * math.cos(wheel_rotation) +
                neutral_grip_x * math.sin(wheel_rotation)
            grip_z := (CAR_PILOT_SEAT_Z - CAR_STEERING_WHEEL_Z) / CAR_PILOT_SCALE
            fore_paw = local_point(p, rotation, grip_x, grip_y, grip_z)
            // A mouse forelimb reaches from a low shoulder as a soft, shallow
            // chain. Place the elbow along that reach with only a slight sag;
            // a raised midpoint creates an angular, human-like bent arm.
            fore_elbow = third_person.Vec3 {
                fore_shoulder.x * .56 + fore_paw.x * .44,
                fore_shoulder.y * .56 + fore_paw.y * .44 - .018 * CAR_PILOT_SCALE,
                fore_shoulder.z * .56 + fore_paw.z * .44,
            }
        }
        // Decide contact from the final posed height, rather than the raw gait
        // curve. During deceleration run_weight lowers the visible paw before
        // the source cycle reaches stance; using the source lift here made a
        // visibly grounded paw slide with the body.
        // Contact phase comes from the unattenuated gait cycle, not the
        // visibly blended lift. During acceleration run_weight starts near
        // zero; using front_lift here incorrectly pins both forepaws even
        // while one side's underlying gait is already in recovery.
        fore_locomoting := horizontal_speed > .08 || run_weight > .03
        fore_planted :=
            model.grounded &&
            posted_weight < .5 &&
            (!fore_locomoting || front_motion.lift < .025)
        // Mouse forearms are approximately as long as, or slightly longer
        // than, the humerus. Keep the complete chain compact so the proximal
        // limb remains tucked inside the chest silhouette instead of reading
        // as a long, human-like arm.
        FORE_UPPER_LENGTH :: f32(.235)
        FORE_LOWER_LENGTH :: f32(.235)
        fore_minimum_reach := math.abs(FORE_UPPER_LENGTH - FORE_LOWER_LENGTH) + .0001
        fore_maximum_reach := FORE_UPPER_LENGTH + FORE_LOWER_LENGTH - .0001
        if model.grounded {
            fore_paw = mouse_ground_contact(editor, fore_paw, .024, fore_planted)
            mouse_clamp_ground_contact_reach(fore_shoulder, &fore_paw, fore_maximum_reach)
        } else {
            mouse_clamp_endpoint_reach(fore_shoulder, &fore_paw, fore_minimum_reach, fore_maximum_reach)
        }
        if model.track_paw_plants {
            fore_contact := mouse_paws.resolve(
                &editor.player_paws.contacts[side_index * 2],
                fore_shoulder,
                fore_paw,
                fore_planted,
                fore_maximum_reach,
                rotation,
            )
            fore_paw = fore_contact.position
        }
        if model.grounded {
            fore_paw = mouse_ground_contact(editor, fore_paw, .024, fore_planted)
            mouse_clamp_ground_contact_reach(fore_shoulder, &fore_paw, fore_maximum_reach)
            if model.track_paw_plants && fore_planted {
                editor.player_paws.contacts[side_index * 2].anchor = fore_paw
            }
        }
        fore_elbow = mouse_kinematics.solve_two_bone(
            fore_shoulder,
            fore_paw,
            mouse_kinematics.fore_elbow_pole(model_forward),
            FORE_UPPER_LENGTH,
            FORE_LOWER_LENGTH,
        )
        fore_wrist := third_person.Vec3 {
            fore_elbow.x * .30 + fore_paw.x * .70,
            fore_elbow.y * .30 + fore_paw.y * .70,
            fore_elbow.z * .30 + fore_paw.z * .70,
        }
        fore_points := [4]third_person.Vec3{fore_shoulder, fore_elbow, fore_wrist, fore_paw}
        fore_radii := [4]f32{.044, .035, .024, .017}
        fore_socket_color := mouse_limb_socket_color(model.pattern, fur, fur_dark, fur_light, side_f, false)
        fore_colors := [4]rl.Color{fore_socket_color, fur_dark, paw, paw}
        // A compact shoulder bulb overlaps both the skinned chest and the
        // capped limb root. A flat cap alone cannot cover the wedge that
        // opens between those independently posed surfaces at deep flexion.
        shoulder_socket_center := fore_shoulder
        shoulder_socket_center.y += .018
        world_ellipsoid_rotated(
            shoulder_socket_center,
            .046,
            .050,
            .052,
            rotation,
            fore_socket_color,
            .Plain,
        )
        world_mouse_limb_hull(fore_points[:], fore_radii[:], fore_colors[:], model_forward)
        // Paws are low pads lying in the ground plane. The former vertical
        // discs presented their extrusion as a rectangular bar in profile.
        world_vertical_prism(fore_paw, .044, .041, .030, rotation, paw)
        for digit in 0 ..< 3 {
            digit_tip := local_point(
                fore_paw,
                rotation,
                side_f * (f32(digit) - 1) * .013,
                -.036 * (1 - run_weight) - .006 * run_weight,
                .018 * (1 - run_weight) + .064 * run_weight,
            )
            if model.grounded {
                digit_tip = mouse_ground_contact(editor, digit_tip, .008, fore_planted)
            }
            world_tube_between(fore_paw, digit_tip, model_forward, .008, .008, paw)
        }

        hind_cycle := rear_cycle
        hind_lift := rear_motion.lift * hind_lift_scale * run_weight
        pelvic_drive := hind_cycle * .028
        idle_hind_socket := third_person.Vec3{side_f * .16, .30, -.47}
        hind_socket_bind := third_person.Vec3 {
            idle_hind_socket.x + side_f * (paw_turn_reach * .25 + posted_weight * .030),
            idle_hind_socket.y - inside_turn * .025,
            idle_hind_socket.z + pelvic_drive,
        }
        posed_hind_socket := mouse_skin_vertex(
            {bind_position = hind_socket_bind, groups = {{.Pelvis, .82}, {.Spine, .18}}},
            &skeleton,
        )
        hind_hip := local_point(p, rotation, posed_hind_socket.x, posed_hind_socket.y, posed_hind_socket.z)
        // The hind leg needs both a forward knee and a rear hock. Collapsing
        // those joints into one segment hides the entire chain inside the
        // haunch in side views and makes the paw appear disconnected.
        hind_knee := local_point(
            p,
            rotation,
            side_f * (.205 + descent_weight * .012 + paw_turn_reach * .48 + posted_weight * .035),
            .18 + hind_lift * .35 + air_tuck * .32 - brake_compression * .25 + posted_weight * .015,
            -.25 + hind_cycle * .13 * run_weight + brake_pose * .105 - posted_weight * .055,
        )
        hind_hock := local_point(
            p,
            rotation,
            side_f * (.22 + descent_weight * .018 + paw_turn_reach * .68 + posted_weight * .040),
            .075 + hind_lift * .60 + air_tuck * .48 - brake_compression * .22,
            -.43 - hind_cycle * .060 * run_weight + brake_pose * .075 - posted_weight * .12,
        )
        hind_paw_x := side_f * (.195 + descent_weight * .025 + paw_turn_reach + posted_weight * .045)
        hind_paw_y := .042 + hind_lift + air_tuck - inside_turn * .014
        // An alert mouse plants its long hind feet forward under the belly;
        // this exposes the toes and supports the raised torso instead of
        // balancing it on two vertical hocks.
        hind_paw_z :=
            -.16 +
            hind_cycle * run_weight +
            side_f * .018 * run_weight +
            brake_pose * .15 -
            posted_weight * .10
        hind_paw := local_point(p, rotation, hind_paw_x, hind_paw_y, hind_paw_z)
        if model.driving_pose {
            // Fold the rear legs into the bucket seat. Keeping the hock behind
            // the knee creates a readable seated zig-zag when the cockpit is
            // viewed from either three-quarter angle.
            hind_hip = local_point(p, rotation, side_f * .17, .285, -.43)
            hind_knee = local_point(p, rotation, side_f * .205, .19, -.20)
            hind_hock = local_point(p, rotation, side_f * .19, .105, -.36)
            hind_paw = local_point(p, rotation, side_f * .17, .095, -.11)
        }
        // Release both pairs while rising into the posted pose. Otherwise the
        // authored hind-foot shift stretches back toward the last locomotion
        // contact cached in world space.
        hind_planted := model.grounded && hind_lift < .003 && posted_weight < .5
        // Preserve the authored .74 total reach while using mouse-like
        // proportions: a tibia longer than the femur and a long, but not
        // dominant, hock-to-paw segment.
        HIND_LENGTHS :: [3]f32{.220, .270, .250}
        if model.track_paw_plants {
            hind_contact := mouse_paws.resolve(
                &editor.player_paws.contacts[side_index * 2 + 1],
                hind_hip,
                hind_paw,
                hind_planted,
                HIND_LENGTHS[0] + HIND_LENGTHS[1] + HIND_LENGTHS[2],
                rotation,
            )
            hind_paw = hind_contact.position
        }
        if model.grounded {
            hind_paw = mouse_ground_contact(editor, hind_paw, .024, hind_planted)
            if model.track_paw_plants && hind_planted {
                editor.player_paws.contacts[side_index * 2 + 1].anchor = hind_paw
            }
        }
        hind_chain := [4]third_person.Vec3{hind_hip, hind_knee, hind_hock, hind_paw}
        mouse_constrain_hind_chain(&hind_chain, HIND_LENGTHS, model_forward)
        hind_hip, hind_knee, hind_hock, hind_paw = hind_chain[0], hind_chain[1], hind_chain[2], hind_chain[3]
        if model.hide_hind_feet {
            // Vehicle seats conceal the folded rear feet. Stop the visible
            // limb at the hock so pads and toes cannot poke through bodywork.
            hind_points := [3]third_person.Vec3{hind_hip, hind_knee, hind_hock}
            hind_radii := [3]f32{.065, .052, .041}
            hind_socket_color := mouse_limb_socket_color(model.pattern, fur, fur_dark, fur_light, side_f, true)
            hind_colors := [3]rl.Color{hind_socket_color, fur, fur_dark}
            world_mouse_limb_hull(hind_points[:], hind_radii[:], hind_colors[:], model_forward, false)
        } else {
            hind_ankle := third_person.Vec3 {
                hind_hock.x * .42 + hind_paw.x * .58,
                hind_hock.y * .42 + hind_paw.y * .58,
                hind_hock.z * .42 + hind_paw.z * .58,
            }
            hind_points := [5]third_person.Vec3{hind_hip, hind_knee, hind_hock, hind_ankle, hind_paw}
            hind_radii := [5]f32{.065, .052, .041, .030, .022}
            hind_socket_color := mouse_limb_socket_color(model.pattern, fur, fur_dark, fur_light, side_f, true)
            hind_colors := [5]rl.Color{hind_socket_color, fur, fur_dark, paw, paw}
            world_mouse_limb_hull(hind_points[:], hind_radii[:], hind_colors[:], model_forward, false)
            world_vertical_prism(hind_paw, .058, .058, .032, rotation, paw)
            for digit in 0 ..< 3 {
                digit_tip := local_point(hind_paw, rotation, side_f * (f32(digit) - 1) * .017, -.008, .092)
                if model.grounded {
                    digit_tip = mouse_ground_contact(editor, digit_tip, .009, hind_planted)
                }
                world_tube_between(hind_paw, digit_tip, model_forward, .009, .009, paw)
            }
        }
    }

    // A freshly spawned player can be submitted before its first simulation
    // step. The zero-initialized Verlet points live at world origin, so
    // building a hull from them stretches the root ring across the map and
    // produces a large triangle fan in capture-mode's early frames. Use the
    // authored tail until physics has established a complete local chain.
    if model.player_controlled && editor.player_tail.initialized {
        tail_points: [mouse_tail.POINT_COUNT]third_person.Vec3
        tail_radii: [mouse_tail.POINT_COUNT]f32
        tail_colors: [mouse_tail.POINT_COUNT]rl.Color
        for point, tail_index in editor.player_tail.points {
            weight := f32(tail_index) / f32(len(editor.player_tail.points) - 1)
            tail_points[tail_index] = point.position
            // Preserve a readable sub-pixel-safe tip at gameplay distance.
            // The physical taper remains pronounced, but no longer vanishes
            // between low-poly radial facets when the tail lies on pavement.
            tail_radii[tail_index] = editor.tweak.player_tail.radius * (1 - weight * .48)
            tail_colors[tail_index] = paw
            tail_floor :=
                mouse_surface_height(editor, point.position.x, point.position.z) +
                tail_radii[tail_index] +
                MOUSE_CONTACT_SKIN
            tail_points[tail_index].y = max(tail_points[tail_index].y, tail_floor)
            // At the low gameplay camera, a mathematically tangent tail loses
            // its lower facets to the road depth buffer. Reach full visual
            // clearance over the first few links, then add a slight tapering
            // bias toward the thin tip. The root remains fixed to the rump.
            clearance_weight := clamp(weight * 4, 0, 1)
            tail_points[tail_index].y += clearance_weight * .012 + weight * .012
        }
        // Clearing only the Verlet points is insufficient on a road crown or
        // uneven heightfield: the straight rendered span between two clear
        // endpoints can still pass through a higher patch of ground. Sample
        // each span and lift both of its endpoints by any missing clearance.
        // Two passes also propagate the correction through neighboring spans
        // without changing the physics state or detaching the root.
        for _ in 0 ..< 2 {
            for tail_index in 0 ..< len(tail_points) - 1 {
                for sample_index in 1 ..= 3 {
                    amount := f32(sample_index) * .25
                    sample := third_person.Vec3 {
                        tail_points[tail_index].x * (1 - amount) + tail_points[tail_index + 1].x * amount,
                        tail_points[tail_index].y * (1 - amount) + tail_points[tail_index + 1].y * amount,
                        tail_points[tail_index].z * (1 - amount) + tail_points[tail_index + 1].z * amount,
                    }
                    radius := tail_radii[tail_index] * (1 - amount) + tail_radii[tail_index + 1] * amount
                    floor := mouse_surface_height(editor, sample.x, sample.z) + radius + MOUSE_CONTACT_SKIN
                    penetration := floor - sample.y
                    if penetration > 0 {
                        // Apply the full correction at both ends so their
                        // interpolation is guaranteed to clear this sample.
                        tail_points[tail_index].y += penetration
                        tail_points[tail_index + 1].y += penetration
                    }
                }
            }
        }
        world_mouse_limb_hull(tail_points[:], tail_radii[:], tail_colors[:], model_forward)
    } else if !model.hide_tail {
        tail_points: [9]third_person.Vec3
        tail_radii: [9]f32
        tail_colors: [9]rl.Color
        tail_bind_root := third_person.Vec3{0, .28, -.78}
        tail_posed_root := mouse_skin_vertex(
            {bind_position = tail_bind_root, groups = {{.Pelvis, 1}, {.Spine, 0}}},
            &skeleton,
        )
        tail_root_delta := tail_posed_root - tail_bind_root
        tail_points[0] = local_point(p, rotation, tail_posed_root.x, tail_posed_root.y, tail_posed_root.z)
        tail_radii[0] = .027
        tail_colors[0] = paw
        for tail_index in 1 ..= 8 {
            weight := f32(tail_index) / 8
            gait_sway := model.gait_preview ? mouse_gait.tail_counter_sway(stride_phase, weight, gait) : f32(0)
            root_follow := mouse_gait.tail_root_follow(weight)
            tail_points[tail_index] = local_point(
                p,
                rotation,
                math.sin(weight * math.PI) * .13 + gait_sway + tail_root_delta.x * root_follow,
                .28 * (1 - weight) + .035 * weight + tail_root_delta.y * root_follow,
                -.78 - weight * .82 + tail_root_delta.z * root_follow,
            )
            tail_radii[tail_index] = .027 * (1 - weight * .58)
            tail_colors[tail_index] = paw
            if model.grounded {
                surface :=
                    mouse_surface_height(editor, tail_points[tail_index].x, tail_points[tail_index].z) +
                    tail_radii[tail_index] +
                    MOUSE_CONTACT_SKIN
                tail_points[tail_index].y = max(tail_points[tail_index].y, surface)
            }
        }
        world_mouse_limb_hull(tail_points[:], tail_radii[:], tail_colors[:], model_forward)
    }

    // Apply identity-preserving physiognomy after assembling the complete
    // mouse so facial features, accessories, limbs, and clothing remain
    // attached. Build changes lateral breadth; snout length affects only the
    // face in front of the head joint instead of lengthening the whole torso.
    if math.abs(build - 1) > .0001 || math.abs(snout_length - 1) > .0001 {
        yaw_right := third_person.Vec3{math.cos(rotation), 0, math.sin(rotation)}
        yaw_forward := third_person.Vec3{-math.sin(rotation), 0, math.cos(rotation)}
        snout_root := f32(.20)
        for index in first_vertex ..< len(world_renderer.vertices) {
            vertex := &world_renderer.vertices[index]
            delta := third_person.Vec3 {
                vertex.position[0] - p.x,
                vertex.position[1] - p.y,
                vertex.position[2] - p.z,
            }
            local_x := delta.x * yaw_right.x + delta.z * yaw_right.z
            local_z := delta.x * yaw_forward.x + delta.z * yaw_forward.z
            local_x *= build
            if local_z > snout_root {
                local_z = snout_root + (local_z - snout_root) * snout_length
            }
            vertex.position[0] = p.x + yaw_right.x * local_x + yaw_forward.x * local_z
            vertex.position[2] = p.z + yaw_right.z * local_x + yaw_forward.z * local_z

            normal := third_person.Vec3{vertex.normal[0], vertex.normal[1], vertex.normal[2]}
            normal_x := (normal.x * yaw_right.x + normal.z * yaw_right.z) / build
            normal_y := normal.y
            normal_z := normal.x * yaw_forward.x + normal.z * yaw_forward.z
            if local_z > snout_root do normal_z /= snout_length
            length := f32(math.sqrt(f64(normal_x * normal_x + normal_y * normal_y + normal_z * normal_z)))
            if length > .0001 {
                normal_x /= length
                normal_y /= length
                normal_z /= length
                vertex.normal = {
                    yaw_right.x * normal_x + yaw_forward.x * normal_z,
                    normal_y,
                    yaw_right.z * normal_x + yaw_forward.z * normal_z,
                }
            }
        }
    }
}

world_character :: proc(editor: ^Editor) {
    if !editor.in_map || editor.pilot.mode != .On_Foot do return
    world_mouse_model(editor, {
        position          = editor.player.position,
        rotation          = math.PI - editor.player.facing_yaw_radians,
        accessory         = editor.mouse_headgear,
        fur               = editor.mouse_fur,
        pattern           = editor.mouse_pattern,
        scarf_enabled     = editor.mouse_scarf_enabled,
        scarf_color       = editor.mouse_scarf_color,
        player_controlled = true,
        track_paw_plants  = true,
        grounded          = editor.player.grounded,
    })
}

world_postale_pilot :: proc(editor: ^Editor) {
    if !editor.in_map || !editor.postale_visible || editor.pilot.mode != .Driving do return
    if editor.pilot.vehicle != &editor.postale.vehicle do return

    body := editor.postale.body
    // Parent the pilot to a fixed seat in Postale mesh-local space. The mouse
    // model's origin is at its feet, so the seat belongs below the high wing,
    // inside the forward fuselage—not on top of the aircraft.
    seat_local := [3]f32{0, -.37, -.20}
    position := postale_vertex_world(&editor.postale, seat_local, POSTALE_PRESENTATION_SCALE)
    rotation := math.atan2(-body.basis.forward.x, -body.basis.forward.z)
    world_mouse_model_parented(editor, {
            position          = position,
            rotation          = rotation,
            accessory         = editor.mouse_headgear,
            fur               = editor.mouse_fur,
            pattern           = editor.mouse_pattern,
            scarf_enabled     = editor.mouse_scarf_enabled,
            scarf_color       = editor.mouse_scarf_color,
            player_controlled = true,
            grounded          = false,
            hide_tail         = true,
            hide_hind_feet    = true,
        }, body.basis)
}

MARTA_STOOL_HEIGHT :: f32(.49)

world_attendant_kiosk :: proc(editor: ^Editor) {
    if !editor.in_map || !editor.libellula_visible do return
    world_attendant_kiosk_at(editor, editor.attendant_position)
    world_attendant_kiosk_at(editor, editor.gerta_position)
}

world_attendant_kiosk_at :: proc(editor: ^Editor, p: third_person.Vec3) {
    ground := terrain.sample_height(&editor.project, 0, p.x, p.z)
    timber := rl.Color{92, 61, 38, 255}
    painted := rl.Color{188, 58, 48, 255}
    cream := rl.Color{232, 218, 181, 255}
    roof := rl.Color{55, 72, 76, 255}

    // A maintained limestone apron keeps the service counter accessible.
    world_land_surface_rotated(editor, p.x, p.z + .35, 4.2, 3.8, 0, .09, {181, 169, 137, 255})
    world_land_surface_rotated(editor, p.x, p.z - 2.65, 1.65, 3.0, 0, .10, {194, 183, 153, 255})

    // Open-front runway kiosk: a raised deck, sheltered counter, rear wall,
    // and striped sign. The opening faces the runway along -Z.
    world_box_rotated({p.x, ground + .08, p.z + .42}, {3.2, .16, 2.6}, 0, timber)
    world_box_rotated({p.x, ground + 1.35, p.z + 1.58}, {3.2, 2.7, .16}, 0, painted)
    world_box_rotated({p.x - 1.52, ground + 1.30, p.z + .42}, {.16, 2.6, 2.35}, 0, painted)
    world_box_rotated({p.x + 1.52, ground + 1.30, p.z + .42}, {.16, 2.6, 2.35}, 0, painted)
    world_box_rotated({p.x, ground + 2.78, p.z + .38}, {3.65, .18, 3.0}, 0, roof)
    world_box_rotated({p.x, ground + 1.02, p.z - .54}, {3.0, .16, .48}, 0, cream)
    world_box_rotated({p.x, ground + .62, p.z - .36}, {2.85, .72, .14}, 0, timber)
    world_box_rotated({p.x, ground + 2.28, p.z + 1.47}, {2.25, .48, .08}, 0, cream)
    world_box_rotated({p.x, ground + 2.28, p.z + 1.40}, {1.55, .14, .06}, 0, painted)

    // Marta is much shorter than the service counter. Give her a sturdy
    // standing stool on the raised deck so she can comfortably see customers.
    stool := rl.Color{126, 82, 47, 255}
    world_box_rotated({p.x, ground + MARTA_STOOL_HEIGHT - .06, p.z}, {.62, .12, .54}, 0, stool)
    stool_leg_offsets := [4][2]f32{{-.23, -.19}, {-.23, .19}, {.23, -.19}, {.23, .19}}
    for offset in stool_leg_offsets {
        world_box_rotated({p.x + offset.x, ground + .295, p.z + offset.y}, {.10, .27, .10}, 0, timber)
    }
}

world_marta :: proc(editor: ^Editor) {
    if !editor.in_map || !editor.libellula_visible do return
    delta := third_person.Vec3 {
        editor.player.position.x - editor.attendant_position.x,
        0,
        editor.player.position.z - editor.attendant_position.z,
    }
    facing := math.atan2(-delta.x, -delta.z)
    position := editor.attendant_position
    position.y += MARTA_STOOL_HEIGHT
    world_mouse_model(
        editor,
        {
            position = position,
            rotation = math.PI - facing,
            build = .88,
            snout_length = 1.12,
            accessory = .Flower,
            grounded = false,
        },
    )
    world_mouse_interaction_indicator(editor, position)
}

world_gerta :: proc(editor: ^Editor) {
    if !editor.in_map || !editor.libellula_visible do return
    delta := third_person.Vec3 {
        editor.player.position.x - editor.gerta_position.x,
        0,
        editor.player.position.z - editor.gerta_position.z,
    }
    facing := math.atan2(-delta.x, -delta.z)
    position := editor.gerta_position
    position.y += MARTA_STOOL_HEIGHT
    world_mouse_model(
        editor,
        {
            position = position,
            rotation = math.PI - facing,
            build = 1.16,
            snout_length = .92,
            accessory = .Flower,
            accessory_side = 1,
            grounded = false,
        },
    )
    world_mouse_interaction_indicator(editor, position)
}

world_mouse_interaction_indicator :: proc(editor: ^Editor, mouse_position: third_person.Vec3) {
    if editor == nil || editor.pilot.mode != .On_Foot || editor.attendant_dialogue_open || pause_menu_is_open(editor) {
        return
    }

    // Crossed slabs keep the punctuation legible from every approach without
    // requiring a screen-space overlay or a camera-facing render path.
    bob := f32(math.sin(rl.GetTime() * 3.2)) * .055
    center := third_person.Vec3{mouse_position.x, mouse_position.y + 1.18 + bob, mouse_position.z}
    gold := rl.Color{247, 191, 54, 255}
    shadow := rl.Color{91, 57, 29, 255}

    rotations := [2]f32{0, math.PI * .5}
    for rotation in rotations {
        world_box_rotated({center.x, center.y + .17, center.z}, {.105, .34, .045}, rotation, shadow)
        world_box_rotated({center.x, center.y + .18, center.z}, {.065, .30, .065}, rotation, gold)
        world_box_rotated({center.x, center.y - .10, center.z}, {.12, .12, .055}, rotation, shadow)
        world_box_rotated({center.x, center.y - .10, center.z}, {.08, .08, .075}, rotation, gold)
    }
}

Town_Mouse :: struct {
    lateral:     f32,
    outward:     f32,
    facing:      f32,
    scale:       f32,
    build:       f32,
    snout_length: f32,
    accessory:   Mouse_Accessory,
    fur:         Mouse_Fur,
    pattern:     Mouse_Fur_Pattern,
    scarf:       bool,
    scarf_color: rl.Color,
}

story_resident_town_slot :: proc(resident: story.Resident) -> (island_index, resident_index: int, ok: bool) {
    switch resident {
    case .Niko:
        return 0, 0, true
    case .Bojan:
        return 0, 2, true
    case .Iva:
        return 1, 1, true
    case .Zora:
        return 1, 5, true
    case .Marta:
        return 0, 0, false
    case .Gerta:
        return 0, 0, false
    }
    return 0, 0, false
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
        x, z := world_rotate_xz(
            frontage.center_x,
            frontage.center_z,
            lateral[resident_index],
            frontage.depth * .5 + outward[resident_index] + f32(doorway_row) * 1.25,
            frontage.rotation,
        )
        ground_y := terrain.sample_height(&editor.project, 0, x, z)
        if ground_y <= editor.project.sea_level + .35 do continue
        return {x, ground_y, z}, frontage.rotation, true
    }
    return {}, 0, false
}

world_story_meeting_pose :: proc(editor: ^Editor) -> (niko, iva, center: third_person.Vec3, rotation: f32, ok: bool) {
    home, frontage_rotation, found := world_story_resident_home_pose(editor, .Niko)
    if !found do return {}, {}, {}, 0, false
    // The procedural resident point sits just beyond the doorway. Spread the
    // pair along the façade and lift the awning center slightly toward it.
    side_x, side_z := math.cos(frontage_rotation), math.sin(frontage_rotation)
    out_x, out_z := -math.sin(frontage_rotation), math.cos(frontage_rotation)
    center = {home.x - out_x * .28, 0, home.z - out_z * .28}
    center.y = terrain.sample_height(&editor.project, 0, center.x, center.z)
    niko = {center.x - side_x * .62, 0, center.z - side_z * .62}
    iva = {center.x + side_x * .62, 0, center.z + side_z * .62}
    niko.y = terrain.sample_height(&editor.project, 0, niko.x, niko.z)
    iva.y = terrain.sample_height(&editor.project, 0, iva.x, iva.z)
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

world_story_meeting :: proc(editor: ^Editor) {
    if editor == nil || editor.story_state.romance != .Meeting do return
    niko, iva, center, rotation, found := world_story_meeting_pose(editor)
    if !found do return

    // A temporary quay awning gives the meeting a readable landmark without
    // requiring a hand-authored coordinate or a new asset.
    blue := rl.Color{53, 103, 151, 255}
    pale := rl.Color{219, 230, 220, 255}
    timber := rl.Color{91, 63, 41, 255}
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
        ground := terrain.sample_height(&editor.project, 0, post_x, post_z)
        world_box_rotated(
            {post_x, ground + (canopy_y - ground) * .5, post_z},
            {.075, canopy_y - ground, .075},
            rotation,
            timber,
        )
    }

    facing_niko := math.atan2(iva.x - niko.x, iva.z - niko.z)
    facing_iva := math.atan2(niko.x - iva.x, niko.z - iva.z)
    world_town_mouse_model_scaled_cached(editor, {
            position  = niko,
            rotation  = math.PI - facing_niko,
            build     = 1.12,
            snout_length = .94,
            accessory = .Acorn_Cap,
            fur       = .Chestnut,
            pattern   = .Pale_Belly,
            grounded  = true,
        }, 1.02, TOWN_MOUSE_CACHE_COUNT - 2)
    world_town_mouse_model_scaled_cached(editor, {
            position      = iva,
            rotation      = math.PI - facing_iva,
            build         = .86,
            snout_length  = 1.16,
            accessory     = .Flower,
            fur           = .Cream,
            pattern       = .Piebald,
            scarf_enabled = true,
            scarf_color   = {177, 65, 73, 255},
            grounded      = true,
        }, .96, TOWN_MOUSE_CACHE_COUNT - 1)
    if story.resident_has_action(&editor.story_state, .Niko) {
        world_mouse_interaction_indicator(editor, niko)
    }
}

world_town_mice :: proc(editor: ^Editor) {
    if editor == nil do return

    residents := [7]Town_Mouse {
        {-1.0, 2.5, .18, 1.08, 1.12, .94, .Acorn_Cap, .Chestnut, .Pale_Belly, false, {}},
        {.8, 2.2, -.22, .91, .86, 1.16, .Flower, .Cream, .Piebald, true, {177, 65, 73, 255}},
        {-1.3, 2.7, .12, 1.14, 1.22, .88, .Bottle_Cap, .Soot, .Solid, true, {61, 112, 139, 255}},
        {1.1, 2.4, -.16, 1.00, .94, 1.22, .Paper_Boat, .Silver, .Hooded, false, {}},
        {-.7, 2.2, .24, .86, 1.08, 1.02, .Chef_Hat, .White, .Pale_Belly, false, {}},
        {1.4, 2.6, -.10, 1.05, 1.18, 1.10, .None, .Russet, .Piebald, true, {205, 151, 52, 255}},
        {-.9, 2.3, .20, .96, .82, .90, .Goggles, .Chestnut, .Hooded, false, {}},
    }
    structures := editor.project.structures[:editor.project.structure_count]
    world_structure_storage_ensure(len(structures))
    half_extent := f32(terrain.WORLD_SIZE_METERS * .5)
    island_radius := half_extent * terrain.DEFAULT_ISLAND_RADIUS
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

        // Sparse towns still receive the complete cast. When there are fewer
        // façades than residents, wrap to a second doorway position rather
        // than silently shrinking the population with the building density.
        for resident, resident_index in residents {
            for attempt in 0 ..< candidate_count {
                candidate_index := candidates[(resident_index + attempt) % candidate_count]
                frontage := architecture.architecture_frontage_structure(structures[candidate_index])
                doorway_row := resident_index / candidate_count
                x, z := world_rotate_xz(
                    frontage.center_x,
                    frontage.center_z,
                    resident.lateral,
                    frontage.depth * .5 + resident.outward + f32(doorway_row) * 1.25,
                    frontage.rotation,
                )
                ground_y := terrain.sample_height(&editor.project, 0, x, z)
                if ground_y <= editor.project.sea_level + .35 do continue
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
                }
                if named &&
                   editor.story_state.romance == .Meeting &&
                   (named_resident == .Niko || named_resident == .Iva) {
                    break
                }
                rotation := frontage.rotation + math.PI * .5 + resident.facing
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
                        scarf_color   = resident.scarf_color,
                        grounded      = true,
                    }, resident.scale, island_index * len(residents) + resident_index)
                if named && story.resident_has_action(&editor.story_state, named_resident) {
                    world_mouse_interaction_indicator(editor, {x, ground_y, z})
                }
                break
            }
        }
    }
    world_story_meeting(editor)
}

world_brush_disc :: proc(editor: ^Editor, x, z, radius, height_offset: f32, color: rl.Color) {
    if editor == nil do return
    segments := 48
    center := third_person.Vec3{x, terrain.sample_height(&editor.project, 0, x, z) + height_offset, z}
    for i in 0 ..< segments {
        a0 := f32(i) * 2 * math.PI / f32(segments)
        a1 := f32(i + 1) * 2 * math.PI / f32(segments)
        p0 := third_person.Vec3{x + math.cos(a0) * radius, 0, z + math.sin(a0) * radius}
        p1 := third_person.Vec3{x + math.cos(a1) * radius, 0, z + math.sin(a1) * radius}
        p0.y = terrain.sample_height(&editor.project, 0, p0.x, p0.z) + height_offset
        p1.y = terrain.sample_height(&editor.project, 0, p1.x, p1.z) + height_offset
        // Ground decal fan: upward face front (CCW) so it survives culling.
        world_triangle(center, p1, p0, color)
    }
}

world_brush :: proc(editor: ^Editor) {
    formation_brush := editor.authoring_tool == .Formations || editor.authoring_tool == .Foliage
    if editor.in_map ||
       (editor.tool == .Structure &&
               !editor.architecture_paint_mode &&
               !editor.marina_paint_mode &&
               !editor.farm_paint_mode &&
               !editor.climbing_leaf_paint_mode &&
               !formation_brush) {
        return
    }
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    mouse, inside := rl.GetWorldMousePosition()
    if !inside do return
    x, z, hit := terrain_under_cursor_3d(editor, camera, mouse, ADRIATIC_WORLD_WIDTH, ADRIATIC_WORLD_HEIGHT)
    if !hit do return
    color: rl.Color = {230, 244, 218, 76}
    radius, hardness := editor.radius, editor.hardness
    switch editor.tool {
    case .Raise:
        color = {244, 214, 122, 88}
    case .Smooth:
        color = {176, 225, 236, 88}
    case .Paint:
        color = {168, 239, 220, 88}
    case .Structure:
        color = {90, 102, 112, 86}
        radius = editor.architecture_brush_radius
        hardness = editor.architecture_brush_hardness
        if editor.marina_paint_mode {
            color = {70, 170, 202, 92}
            radius = editor.marina_brush_radius
            hardness = .72
        } else if editor.farm_paint_mode {
            color = editor.farm_preview_valid ? rl.Color{153, 174, 76, 92} : rl.Color{218, 105, 86, 104}
            radius = editor.farm_brush_radius
            hardness = .68
        } else if formation_brush {
            color = editor.authoring_tool == .Foliage ? rl.Color{105, 176, 92, 96} : rl.Color{172, 126, 84, 96}
            radius = editor.formation_brush_radius
            hardness = editor.formation_brush_hardness
        } else if editor.climbing_leaf_paint_mode {
            color = {72, 164, 88, 96}
            radius = editor.climbing_leaf_brush_radius
            hardness = editor.climbing_leaf_brush_hardness
        }
    }
    if rl.IsMouseButtonDown(.RIGHT) do color = {245, 126, 112, 108}
    world_brush_disc(editor, x, z, radius, .09, color)
    // A denser inner disc makes the hardness setting legible at the cursor:
    // harder brushes have a larger, more opaque core while the outer disc
    // continues to show the full affected radius.
    inner_radius := radius * (.25 + hardness * .65)
    core := color
    core.a = u8(min(int(color.a) + 34, 180))
    world_brush_disc(editor, x, z, inner_radius, .105, core)
}

world_ground_grass :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map || editor.benchmark_ground_grass_disabled do return
    // Populate around the active view rather than the player character. This
    // keeps the visible field dense when an inspection or chase camera moves
    // away from the mouse, while the snapped world grid prevents shimmer.
    field_x, field_z := editor.camera_pose.position.x, editor.camera_pose.position.z
    field_radius := f32(42)
    if driving_aircraft(editor) {
        body := active_aircraft_body(editor)
        ground := terrain.sample_height(&editor.project, 0, body.position.x, body.position.z)
        if body.position.y - ground > 28 do return
        field_radius = 60
    } else if editor.pilot.mode != .On_Foot {
        return
    }

    building_footprints := world_architecture_grass_footprints(editor)
    defer delete(building_footprints)
    circulation_plan := editor_circulation_plan(editor)

    // A snapped, deterministic field follows the camera without shimmer. Its
    // concentric density falloff keeps the near field lush while bounding CPU
    // terrain samples and opaque blade geometry for the 4K frame budget.
    // Half the spacing in both axes yields four times the card density.
    SPACING :: f32(.46)
    grid_radius := int(math.ceil(f64(field_radius / SPACING)))
    center_x := f32(math.floor(f64(field_x / SPACING))) * SPACING
    center_z := f32(math.floor(f64(field_z / SPACING))) * SPACING
    for grid_z in -grid_radius ..= grid_radius {
        for grid_x in -grid_radius ..= grid_radius {
            world_grid_x := grid_x + int(center_x / SPACING)
            world_grid_z := grid_z + int(center_z / SPACING)
            seed_index := world_grid_x * 73856093 + world_grid_z * 19349663
            jitter_x := (wind_streak_hash(seed_index, 1) - .5) * SPACING * .76
            jitter_z := (wind_streak_hash(seed_index, 2) - .5) * SPACING * .76
            x := center_x + f32(grid_x) * SPACING + jitter_x
            z := center_z + f32(grid_z) * SPACING + jitter_z
            dx, dz := x - field_x, z - field_z
            distance_squared := dx * dx + dz * dz
            if distance_squared > field_radius * field_radius do continue
            distance := f32(math.sqrt(f64(distance_squared)))
            fade := clamp((distance - field_radius * .35) / (field_radius * .65), f32(0), f32(1))
            fade = fade * fade * (3 - 2 * fade)
            density := 1 - fade
            // Dither the population all the way to zero instead of retaining
            // half the cards at the render limit and dropping them at once.
            if wind_streak_hash(seed_index, 3) > density do continue
            height_at := terrain.sample_height(&editor.project, 0, x, z)
            if farmland_excludes_ground_grass(editor, x, z) do continue
            if !wildflowers_renderable_at(editor, x, z, circulation_plan) do continue
            variation := wind_streak_hash(seed_index, 4)
            // The atlas is sampled as luminance, so elevation can drive the
            // complete palette without additional texture variants. Moist,
            // near-shore grass is cool and blue-green; high exposed slopes
            // transition through olive into a dry, sun-warmed yellow-green.
            elevation := max(height_at - editor.project.sea_level, f32(0))
            altitude := clamp((elevation - 2.4) / 28, f32(0), f32(1))
            low := rl.Color{49, 112, 78, 255}
            middle := rl.Color{75, 137, 68, 255}
            high := rl.Color{139, 145, 70, 255}
            color := color_lerp(middle, high, (altitude - .52) / .48)
            if altitude < .52 {
                color = color_lerp(low, middle, altitude / .52)
            }
            // Large, stable patches echo the canopy families: cool sea-facing
            // hollows, silvery herb grass, and dry gold-green exposed slopes.
            // The low blend amount preserves terrain matching while producing
            // visible postcard color regions from an overview camera.
            temperature_field :=
                f32(math.sin(f64(x * .018 + z * .007))) + f32(math.sin(f64(x * -.006 + z * .014 + 2.1))) * .55
            if temperature_field < -.55 {
                color = color_lerp(color, {49, 105, 84, 255}, .24)
            } else if temperature_field > .58 {
                color = color_lerp(color, {161, 153, 74, 255}, .27)
            } else {
                color = color_lerp(color, {111, 137, 91, 255}, .16)
            }
            color = color_lerp(color, {170, 166, 87, 255}, variation * .08)
            // Keep the authored grass hue, but match its value to the shaded
            // terrain beneath it. In the outer falloff, converge on the exact
            // terrain color so the final cards cannot form a dark cutoff ring.
            ground_color := clipmap_vertex_color(editor, 0, x, z, height_at)
            grass_value := f32(color.r) * .2126 + f32(color.g) * .7152 + f32(color.b) * .0722
            ground_value := f32(ground_color.r) * .2126 + f32(ground_color.g) * .7152 + f32(ground_color.b) * .0722
            value_scale := ground_value / max(grass_value, f32(1))
            color.r = u8(clamp(f32(color.r) * value_scale, 0, 255))
            color.g = u8(clamp(f32(color.g) * value_scale, 0, 255))
            color.b = u8(clamp(f32(color.b) * value_scale, 0, 255))
            color = color_lerp(color, ground_color, fade)
            color.a = u8(clamp(density * 255, 0, 255))
            // Size uses independent hashes so the field does not repeat one
            // uniformly scaled tuft silhouette. Most blades stay near the
            // median, with occasional cropped and seed-head-tall outliers.
            height_noise := wind_streak_hash(seed_index, 7)
            width_noise := wind_streak_hash(seed_index, 8)
            height := .48 + height_noise * .62
            if height_noise < .12 {
                height *= .62
            } else if height_noise > .90 {
                height *= 1.28
            }
            architecture_height_scale := world_architecture_grass_height_scale(building_footprints[:], x, z)
            if architecture_height_scale <= 0 do continue
            height *= architecture_height_scale
            width := height * (.56 + width_noise * .48)
            world_grass_card({x, height_at + height * .5, z}, width, height, abs(seed_index) % 16, color)
            flower_density := wildflower_density_at(x, z)
            if flower_density > .18 && wind_streak_hash(seed_index, 12) < flower_density * .34 {
                flower_height := .32 + wind_streak_hash(seed_index, 13) * .34
                world_wildflower_card(
                    {x, height_at + flower_height * .5 + .12, z},
                    .22 + wind_streak_hash(seed_index, 14) * .18,
                    flower_height,
                    abs(seed_index / 11) % 16,
                )
            }
        }
    }
}

world_build :: proc(editor: ^Editor) {
    world_structure_storage_ensure(editor.project.structure_count)
    clear(&world_renderer.vertices)
    clear(&world_renderer.static_vertices)
    clear(&world_renderer.static_indices)
    clear(&world_renderer.wing_trail_vertices)
    clear(&world_renderer.wing_trail_indices)
    clear(&world_renderer.wing_trail_optimized_indices)
    clear(&world_renderer.road_vertices)
    clear(&world_renderer.foliage_vertices)
    clear(&world_renderer.bougainvillea_vertices)
    clear(&world_renderer.grass_instances)
    clear(&world_renderer.wildflower_instances)
    world_renderer.structure_lod_counts = {}
    world_renderer.structure_lod_world_vertices = 0
    world_renderer.structure_lod_foliage_vertices = 0
    world_renderer.player_vertex_first = 0
    world_renderer.player_vertex_count = 0
    world_renderer.dynamic_caster_first = 0
    world_renderer.dynamic_caster_count = 0
    if editor.pause_screen == .Customization {
        // The customization screen gets a purpose-built miniature world pass.
        // It uses the exact gameplay model and materials, rather than maintaining
        // a second approximation of the mouse in the UI layer.
        world_ellipsoid_rotated({0, -.08, 0}, .72, .08, .72, 0, {40, 58, 61, 255})
        world_ellipsoid_rotated({0, -.025, 0}, .60, .035, .60, 0, {77, 112, 111, 255})
        world_mouse_model(editor, {
            position          = {0, 0, 0},
            rotation          = editor.customization_preview_yaw + .65,
            accessory         = editor.mouse_headgear,
            fur               = editor.mouse_fur,
            pattern           = editor.mouse_pattern,
            scarf_enabled     = editor.mouse_scarf_enabled,
            scarf_color       = editor.mouse_scarf_color,
            preview           = true,
            player_controlled = true,
            grounded          = false,
        })
        return
    }
    if editor.vehicle_showcase_scene {
        world_vehicle_showcase(editor)
        return
    }
    if lab_scene_draw_world(editor) do return
    // Depth testing makes submission order independent. Put authored gameplay
    // meshes first so dense terrain can consume only the remaining capacity
    // instead of silently dropping vehicles at the end of the frame.
    world_ocean(editor)
    for index in 0 ..< editor.default_marina_count {
        world_markov_marina_facility(
            editor,
            &editor.default_marinas[index],
            false,
            MARINA_GEOMETRY_CACHE_DEFAULT_FIRST + index,
        )
    }
    if editor.marina_authored {
        world_markov_marina_facility(editor, &editor.marina_authored_plan, false, MARINA_GEOMETRY_CACHE_AUTHORED)
    }
    if editor.marina_paint_mode && editor.marina_preview_valid {
        world_markov_marina_facility(editor, &editor.marina_preview_plan, false, MARINA_GEOMETRY_CACHE_PREVIEW)
    }
    if !lab_scene_suppresses_infrastructure(editor) do world_infrastructure(editor)
    world_roads(editor)
    world_boat_wakes(editor)
    world_city_density_overlay(editor)
    world_climbing_leaf_density_overlay(editor)
    // The player and vehicles are gameplay-critical. Submit them before any
    // capacity-limited environment detail so a dense scene can never cull the
    // controlled character or the vehicle they occupy. Keeping all vehicles
    // in this protected group also prevents an enter/exit transition from
    // exposing a one-frame ordering gap.
    world_renderer.dynamic_caster_first = len(world_renderer.vertices)
    world_npc_boats(editor)
    world_aircraft(editor)
    world_car(editor)
    world_car_pilot(editor)
    world_renderer.player_vertex_first = len(world_renderer.vertices)
    world_character(editor)
    world_renderer.player_vertex_count = len(world_renderer.vertices) - world_renderer.player_vertex_first
    world_postale_pilot(editor)
    // Persistent characters and their interaction landmarks must be submitted
    // before the capacity-limited procedural town and vegetation passes.
    world_attendant_kiosk(editor)
    world_marta(editor)
    world_gerta(editor)
    world_town_mice(editor)
    world_authored_farmland(editor)
    lab_scene_draw_world_overlay(editor)
    world_renderer.dynamic_caster_count = len(world_renderer.vertices) - world_renderer.dynamic_caster_first
    world_structures(editor)
    world_ground_grass(editor)
    world_renderer.player_shadow_receiver = mouse_surface_height(
        editor,
        editor.player.position.x,
        editor.player.position.z,
    )
    world_brush(editor)
    world_vehicle_particles(editor)
    world_petal_particles(editor)
    world_wing_trails(editor)
    world_wind_streaks(editor)
}

world_petal_particles :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    palette := [5]rl.Color {
        {246, 201, 70, 235},
        {242, 121, 151, 235},
        {199, 151, 229, 225},
        {248, 238, 210, 230},
        {218, 78, 105, 230},
    }
    for particle in editor.petal_effects.particles[:editor.petal_effects.count] {
        display := particles.Vehicle_Particle {
            position = particle.position,
            velocity = particle.velocity,
            life     = particle.life,
            max_life = particle.max_life,
            size     = particle.size,
            seed     = particle.seed,
        }
        world_vehicle_particle(camera, display, palette[int(particle.seed % u32(len(palette)))])
    }
}

customization_preview_camera_pose :: proc() -> third_person.Camera_Pose {
    return {position = {2.28, 1.18, 3.08}, target = {1.86, .38, 0}}
}

world_vehicle_particle :: proc(
    camera: Perspective_Camera,
    particle: particles.Vehicle_Particle,
    color: rl.Color,
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
    shade := rl.Color{color.r, color.g, color.b, alpha}
    world_quad(
        {p.x - right.x - up.x, p.y - right.y - up.y, p.z - right.z - up.z},
        {p.x + right.x - up.x, p.y + right.y - up.y, p.z + right.z - up.z},
        {p.x + right.x + up.x, p.y + right.y + up.y, p.z + right.z + up.z},
        {p.x - right.x + up.x, p.y - right.y + up.y, p.z - right.z + up.z},
        shade,
    )
}

world_vehicle_particles :: proc(editor: ^Editor) {
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for particle in editor.vehicle_effects.dust[:editor.vehicle_effects.dust_count] {
        color := rl.Color{112, 119, 116, 100}
        switch particle.surface {
        case .Asphalt:
            color = {116, 123, 124, 62}
        case .Gravel:
            color = {203, 181, 133, 178}
        case .Cobblestone:
            color = {156, 162, 157, 105}
        case .Dirt:
            color = {177, 111, 62, 190}
        case .Grass:
            color = {119, 126, 78, 132}
        case .Sand:
            color = {210, 192, 150, 150}
        }
        world_vehicle_particle(camera, particle, color)
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
            fade := clamp(particle.life / particle.max_life, 0, 1)
            radius := particle.size * (.8 + fade * .35)
            opacity := fade * fade
            color := rl.Color{205, 239, 236, u8(clamp(opacity * 120, 0, 120))}
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

wind_streak_hash :: proc(index, salt: int) -> f32 {
    value := math.sin(f64(index * 127 + salt * 311) * 12.9898) * 43758.5453
    return f32(value - math.floor(value))
}

world_wind_streaks :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map || !driving_aircraft(editor) do return
    wind_x, wind_z := editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]
    wind_speed := f32(math.sqrt(f64(wind_x * wind_x + wind_z * wind_z)))
    strength := clamp((wind_speed - 1) / 8, 0, 1)
    if strength <= .001 do return

    body := active_aircraft_body(editor)
    direction_x, direction_z := wind_x / wind_speed, wind_z / wind_speed
    side_x, side_z := -direction_z, direction_x
    time := editor.map_time
    camera := perspective_camera(
        editor.camera_pose,
        editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35,
    )
    for index in 0 ..< 32 {
        speed_variation := .72 + wind_streak_hash(index, 1) * .56
        cycle := time * wind_speed * .035 * speed_variation + wind_streak_hash(index, 2)
        phase := cycle - f32(math.floor(f64(cycle)))
        along := (phase - .5) * 82
        lateral := (wind_streak_hash(index, 3) - .5) * 62
        vertical := (wind_streak_hash(index, 4) - .5) * 25 + 3
        center := particles.Vec3 {
            body.position.x + direction_x * along + side_x * lateral,
            body.position.y + vertical,
            body.position.z + direction_z * along + side_z * lateral,
        }
        streak_length := (1.4 + wind_speed * .58) * (.62 + wind_streak_hash(index, 5) * .58)
        tail := particles.Vec3 {
            center.x - direction_x * streak_length,
            center.y,
            center.z - direction_z * streak_length,
        }
        fade := math.sin(phase * math.PI)
        alpha := u8(clamp((22 + strength * 82) * fade, 0, 104))
        width := .018 + strength * .035
        offset := third_person.Vec3{camera.up.x * width, camera.up.y * width, camera.up.z * width}
        world_quad(
            {tail.x - offset.x, tail.y - offset.y, tail.z - offset.z},
            {center.x - offset.x, center.y - offset.y, center.z - offset.z},
            {center.x + offset.x, center.y + offset.y, center.z + offset.z},
            {tail.x + offset.x, tail.y + offset.y, tail.z + offset.z},
            // Cool blue distinguishes wind moving through world space from
            // the warm radial speed lines drawn in the flight overlay.
            {r = 137, g = 218, b = 235, a = alpha},
        )
    }
}

vehicle_paint_atlas_create :: proc(ctx: ^engine.Vk_Context, out: ^resources.Image) -> bool {
    if ctx == nil || out == nil do return false
    if !resources.image_array_create(
        ctx,
        VEHICLE_PAINT_TEXTURE_WIDTH,
        VEHICLE_PAINT_TEXTURE_HEIGHT,
        VEHICLE_PAINT_AIRCRAFT_COUNT,
        .R8G8B8A8_SRGB,
        {.TRANSFER_DST, .SAMPLED},
        {.COLOR},
        .D2_ARRAY,
        false,
        out,
        "vehicle paint texture array",
    ) {
        return false
    }
    staging: engine.Vk_Buffer
    total_size := VEHICLE_PAINT_TEXTURE_BYTE_COUNT * VEHICLE_PAINT_AIRCRAFT_COUNT
    if !engine.vk_create_host_buffer(ctx, vk.DeviceSize(total_size), {.TRANSFER_SRC}, &staging) {
        resources.image_destroy(out, ctx)
        return false
    }
    defer engine.vk_destroy_buffer(ctx, &staging)
    pixels := mem.slice_ptr(cast([^]u8)staging.mapped, total_size)
    for &pixel in pixels do pixel = 0
    cmd, begun := engine.vk_begin_upload_commands(ctx)
    if !begun {
        resources.image_destroy(out, ctx)
        return false
    }
    barrier := vk.ImageMemoryBarrier2 {
        sType = .IMAGE_MEMORY_BARRIER_2,
        srcStageMask = {.TOP_OF_PIPE},
        dstStageMask = {.TRANSFER},
        dstAccessMask = {.TRANSFER_WRITE},
        oldLayout = .UNDEFINED,
        newLayout = .TRANSFER_DST_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image = out.image,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = VEHICLE_PAINT_AIRCRAFT_COUNT,
        },
    }
    dependency := vk.DependencyInfo {
        sType                   = .DEPENDENCY_INFO,
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers    = &barrier,
    }
    vk.CmdPipelineBarrier2(cmd, &dependency)
    region := vk.BufferImageCopy {
        imageSubresource = {
            aspectMask = {.COLOR},
            mipLevel = 0,
            baseArrayLayer = 0,
            layerCount = VEHICLE_PAINT_AIRCRAFT_COUNT,
        },
        imageExtent = {VEHICLE_PAINT_TEXTURE_WIDTH, VEHICLE_PAINT_TEXTURE_HEIGHT, 1},
    }
    vk.CmdCopyBufferToImage(cmd, staging.handle, out.image, .TRANSFER_DST_OPTIMAL, 1, &region)
    barrier.srcStageMask = {.TRANSFER}
    barrier.srcAccessMask = {.TRANSFER_WRITE}
    barrier.dstStageMask = {.FRAGMENT_SHADER}
    barrier.dstAccessMask = {.SHADER_READ}
    barrier.oldLayout = .TRANSFER_DST_OPTIMAL
    barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
    vk.CmdPipelineBarrier2(cmd, &dependency)
    if !engine.vk_submit_upload_commands(ctx) {
        resources.image_destroy(out, ctx)
        return false
    }
    sampler_info := vk.SamplerCreateInfo {
        sType        = .SAMPLER_CREATE_INFO,
        magFilter    = .LINEAR,
        minFilter    = .LINEAR,
        mipmapMode   = .LINEAR,
        addressModeU = .CLAMP_TO_EDGE,
        addressModeV = .CLAMP_TO_EDGE,
        addressModeW = .CLAMP_TO_EDGE,
        minLod       = 0,
        maxLod       = 0,
    }
    if vk.CreateSampler(ctx.device, &sampler_info, nil, &out.sampler) != .SUCCESS {
        resources.image_destroy(out, ctx)
        return false
    }
    engine.vk_set_debug_name(ctx, .SAMPLER, auto_cast out.sampler, "vehicle paint sampler")
    return true
}

vehicle_paint_atlas_flush :: proc(editor: ^Editor, cmd: vk.CommandBuffer, frame_index: int) {
    if editor == nil ||
       (!editor.vehicle_paint_texture_dirty && !editor.vehicle_paint_preview_texture_dirty) ||
       cmd == nil ||
       frame_index < 0 ||
       frame_index >= engine.MAX_FRAMES_IN_FLIGHT {
        return
    }
    staging := &world_renderer.vehicle_paint_staging[frame_index]
    if staging.handle == vk.Buffer(0) || staging.mapped == nil do return
    mem.copy_non_overlapping(staging.mapped, raw_data(vehicle_paint_pixels(editor)), VEHICLE_PAINT_TEXTURE_BYTE_COUNT)
    staging_pixels := mem.slice_ptr(cast([^]u8)staging.mapped, VEHICLE_PAINT_TEXTURE_BYTE_COUNT)
    for preview_alpha, byte_index in editor.vehicle_paint_preview_pixels {
        if byte_index % 4 != 3 || preview_alpha == 0 do continue
        pixel := byte_index - 3
        blend := f32(preview_alpha) / 255
        staging_pixels[pixel] = u8(
            f32(editor.vehicle_paint_preview_pixels[pixel]) * blend + f32(staging_pixels[pixel]) * (1 - blend),
        )
        staging_pixels[pixel + 1] = u8(
            f32(editor.vehicle_paint_preview_pixels[pixel + 1]) * blend + f32(staging_pixels[pixel + 1]) * (1 - blend),
        )
        staging_pixels[pixel + 2] = u8(
            f32(editor.vehicle_paint_preview_pixels[pixel + 2]) * blend + f32(staging_pixels[pixel + 2]) * (1 - blend),
        )
        staging_pixels[pixel + 3] = max(staging_pixels[pixel + 3], preview_alpha)
    }
    layer := u32(vehicle_paint_layer_index(editor.aircraft.active))
    barrier := vk.ImageMemoryBarrier2 {
        sType = .IMAGE_MEMORY_BARRIER_2,
        srcStageMask = {.FRAGMENT_SHADER},
        srcAccessMask = {.SHADER_READ},
        dstStageMask = {.TRANSFER},
        dstAccessMask = {.TRANSFER_WRITE},
        oldLayout = .SHADER_READ_ONLY_OPTIMAL,
        newLayout = .TRANSFER_DST_OPTIMAL,
        srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
        image = world_renderer.vehicle_paint_atlas.image,
        subresourceRange = {
            aspectMask = {.COLOR},
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = layer,
            layerCount = 1,
        },
    }
    dependency := vk.DependencyInfo {
        sType                   = .DEPENDENCY_INFO,
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers    = &barrier,
    }
    vk.CmdPipelineBarrier2(cmd, &dependency)
    region := vk.BufferImageCopy {
        imageSubresource = {aspectMask = {.COLOR}, mipLevel = 0, baseArrayLayer = layer, layerCount = 1},
        imageExtent = {VEHICLE_PAINT_TEXTURE_WIDTH, VEHICLE_PAINT_TEXTURE_HEIGHT, 1},
    }
    vk.CmdCopyBufferToImage(
        cmd,
        staging.handle,
        world_renderer.vehicle_paint_atlas.image,
        .TRANSFER_DST_OPTIMAL,
        1,
        &region,
    )
    barrier.srcStageMask = {.TRANSFER}
    barrier.srcAccessMask = {.TRANSFER_WRITE}
    barrier.dstStageMask = {.FRAGMENT_SHADER}
    barrier.dstAccessMask = {.SHADER_READ}
    barrier.oldLayout = .TRANSFER_DST_OPTIMAL
    barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
    vk.CmdPipelineBarrier2(cmd, &dependency)
    editor.vehicle_paint_texture_dirty = false
    editor.vehicle_paint_preview_texture_dirty = false
}

world_renderer_create :: proc(ctx: ^engine.Vk_Context) -> bool {
    if !dynamic_shadow_create(&world_renderer.dynamic_shadow, ctx) do return false
    paint_bindings := [4]vk.DescriptorSetLayoutBinding {
        {binding = 0, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 1, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 2, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 3, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
    }
    paint_layout_info := vk.DescriptorSetLayoutCreateInfo {
        sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = 4,
        pBindings    = raw_data(paint_bindings[:]),
    }
    if vk.CreateDescriptorSetLayout(ctx.device, &paint_layout_info, nil, &world_renderer.vehicle_paint_descriptor_layout) != .SUCCESS do return false
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET_LAYOUT,
        auto_cast world_renderer.vehicle_paint_descriptor_layout,
        "vehicle paint descriptor set layout",
    )
    paint_pool_sizes := [2]vk.DescriptorPoolSize {
        {type = .SAMPLED_IMAGE, descriptorCount = 2},
        {type = .SAMPLER, descriptorCount = 2},
    }
    paint_pool_info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets       = 1,
        poolSizeCount = 2,
        pPoolSizes    = raw_data(paint_pool_sizes[:]),
    }
    if vk.CreateDescriptorPool(ctx.device, &paint_pool_info, nil, &world_renderer.vehicle_paint_descriptor_pool) != .SUCCESS do return false
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_POOL,
        auto_cast world_renderer.vehicle_paint_descriptor_pool,
        "vehicle paint descriptor pool",
    )
    paint_allocate := vk.DescriptorSetAllocateInfo {
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool     = world_renderer.vehicle_paint_descriptor_pool,
        descriptorSetCount = 1,
        pSetLayouts        = &world_renderer.vehicle_paint_descriptor_layout,
    }
    if vk.AllocateDescriptorSets(ctx.device, &paint_allocate, &world_renderer.vehicle_paint_descriptor) != .SUCCESS do return false
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET,
        auto_cast world_renderer.vehicle_paint_descriptor,
        "vehicle paint descriptor set",
    )
    if !vehicle_paint_atlas_create(ctx, &world_renderer.vehicle_paint_atlas) do return false
    if !resources.texture_load_file(
        ctx,
        "assets/textures/accessories/soda-cap-logo.png",
        &world_renderer.soda_cap_logo,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    paint_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.vehicle_paint_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    paint_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.vehicle_paint_atlas.sampler,
    }
    soda_logo_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.soda_cap_logo.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    soda_logo_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.soda_cap_logo.sampler,
    }
    paint_writes := [4]vk.WriteDescriptorSet {
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &paint_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &paint_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 2,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &soda_logo_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.vehicle_paint_descriptor,
            dstBinding = 3,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &soda_logo_sampler_info,
        },
    }
    vk.UpdateDescriptorSets(ctx.device, 4, raw_data(paint_writes[:]), 0, nil)
    pr := vk.PushConstantRange {
        stageFlags = {.VERTEX, .FRAGMENT},
        size       = u32(size_of(World_Push)),
    }
    world_set_layouts := [2]vk.DescriptorSetLayout {
        world_renderer.vehicle_paint_descriptor_layout,
        world_renderer.dynamic_shadow.descriptor_layout,
    }
    li := vk.PipelineLayoutCreateInfo {
        sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
        pushConstantRangeCount = 1,
        pPushConstantRanges    = &pr,
        setLayoutCount         = 2,
        pSetLayouts            = raw_data(world_set_layouts[:]),
    }
    if vk.CreatePipelineLayout(ctx.device, &li, nil, &world_renderer.layout) != .SUCCESS do return false
    engine.vk_set_debug_name(ctx, .PIPELINE_LAYOUT, auto_cast world_renderer.layout, "world pipeline layout")
    foliage_bindings := [2]vk.DescriptorSetLayoutBinding {
        {binding = 0, descriptorType = .SAMPLED_IMAGE, descriptorCount = 1, stageFlags = {.FRAGMENT}},
        {binding = 1, descriptorType = .SAMPLER, descriptorCount = 1, stageFlags = {.FRAGMENT}},
    }
    foliage_descriptor_info := vk.DescriptorSetLayoutCreateInfo {
        sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        bindingCount = 2,
        pBindings    = raw_data(foliage_bindings[:]),
    }
    if vk.CreateDescriptorSetLayout(
           ctx.device,
           &foliage_descriptor_info,
           nil,
           &world_renderer.foliage_descriptor_layout,
       ) !=
       .SUCCESS {
        return false
    }
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET_LAYOUT,
        auto_cast world_renderer.foliage_descriptor_layout,
        "foliage descriptor set layout",
    )
    foliage_pool_sizes := [2]vk.DescriptorPoolSize {
        {type = .SAMPLED_IMAGE, descriptorCount = 4},
        {type = .SAMPLER, descriptorCount = 4},
    }
    foliage_pool_info := vk.DescriptorPoolCreateInfo {
        sType         = .DESCRIPTOR_POOL_CREATE_INFO,
        maxSets       = 4,
        poolSizeCount = 2,
        pPoolSizes    = raw_data(foliage_pool_sizes[:]),
    }
    if vk.CreateDescriptorPool(ctx.device, &foliage_pool_info, nil, &world_renderer.foliage_descriptor_pool) !=
       .SUCCESS {
        return false
    }
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_POOL,
        auto_cast world_renderer.foliage_descriptor_pool,
        "foliage descriptor pool",
    )
    foliage_layouts := [4]vk.DescriptorSetLayout {
        world_renderer.foliage_descriptor_layout,
        world_renderer.foliage_descriptor_layout,
        world_renderer.foliage_descriptor_layout,
        world_renderer.foliage_descriptor_layout,
    }
    foliage_descriptors: [4]vk.DescriptorSet
    foliage_allocate := vk.DescriptorSetAllocateInfo {
        sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
        descriptorPool     = world_renderer.foliage_descriptor_pool,
        descriptorSetCount = 4,
        pSetLayouts        = raw_data(foliage_layouts[:]),
    }
    if vk.AllocateDescriptorSets(ctx.device, &foliage_allocate, raw_data(foliage_descriptors[:])) != .SUCCESS {
        return false
    }
    world_renderer.foliage_descriptor = foliage_descriptors[0]
    world_renderer.bougainvillea_descriptor = foliage_descriptors[1]
    world_renderer.grass_descriptor = foliage_descriptors[2]
    world_renderer.wildflower_descriptor = foliage_descriptors[3]
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET,
        auto_cast world_renderer.foliage_descriptor,
        "foliage descriptor set",
    )
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET,
        auto_cast world_renderer.bougainvillea_descriptor,
        "bougainvillea descriptor set",
    )
    engine.vk_set_debug_name(ctx, .DESCRIPTOR_SET, auto_cast world_renderer.grass_descriptor, "grass descriptor set")
    engine.vk_set_debug_name(
        ctx,
        .DESCRIPTOR_SET,
        auto_cast world_renderer.wildflower_descriptor,
        "wildflower descriptor set",
    )
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/leaf-branches-atlas.png",
        &world_renderer.foliage_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/bougainvillea-clumps-atlas-v2.png",
        &world_renderer.bougainvillea_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/grass-tufts-atlas.png",
        &world_renderer.grass_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    if !resources.texture_load_file(
        ctx,
        "assets/textures/foliage/wildflower-billboards-atlas.png",
        &world_renderer.wildflower_atlas,
        {address_mode = .CLAMP_TO_EDGE},
    ) {
        return false
    }
    foliage_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.foliage_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    foliage_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.foliage_atlas.sampler,
    }
    bougainvillea_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.bougainvillea_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    bougainvillea_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.bougainvillea_atlas.sampler,
    }
    grass_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.grass_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    grass_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.grass_atlas.sampler,
    }
    wildflower_image_info := vk.DescriptorImageInfo {
        imageView   = world_renderer.wildflower_atlas.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    }
    wildflower_sampler_info := vk.DescriptorImageInfo {
        sampler = world_renderer.wildflower_atlas.sampler,
    }
    foliage_writes := [8]vk.WriteDescriptorSet {
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.foliage_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &foliage_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.foliage_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &foliage_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.bougainvillea_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &bougainvillea_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.bougainvillea_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &bougainvillea_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.grass_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &grass_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.grass_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &grass_sampler_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.wildflower_descriptor,
            dstBinding = 0,
            descriptorCount = 1,
            descriptorType = .SAMPLED_IMAGE,
            pImageInfo = &wildflower_image_info,
        },
        {
            sType = .WRITE_DESCRIPTOR_SET,
            dstSet = world_renderer.wildflower_descriptor,
            dstBinding = 1,
            descriptorCount = 1,
            descriptorType = .SAMPLER,
            pImageInfo = &wildflower_sampler_info,
        },
    }
    vk.UpdateDescriptorSets(ctx.device, 8, raw_data(foliage_writes[:]), 0, nil)
    foliage_layout_info := li
    foliage_layout_info.setLayoutCount = 1
    foliage_set_layouts := [2]vk.DescriptorSetLayout {
        world_renderer.foliage_descriptor_layout,
        world_renderer.dynamic_shadow.descriptor_layout,
    }
    foliage_layout_info.setLayoutCount = 2
    foliage_layout_info.pSetLayouts = raw_data(foliage_set_layouts[:])
    if vk.CreatePipelineLayout(ctx.device, &foliage_layout_info, nil, &world_renderer.foliage_layout) != .SUCCESS {
        return false
    }
    engine.vk_set_debug_name(ctx, .PIPELINE_LAYOUT, auto_cast world_renderer.foliage_layout, "foliage pipeline layout")
    sky_pr := vk.PushConstantRange {
        stageFlags = {.VERTEX, .FRAGMENT},
        size       = u32(size_of(Sky_Push)),
    }
    sky_li := vk.PipelineLayoutCreateInfo {
        sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
        pushConstantRangeCount = 1,
        pPushConstantRanges    = &sky_pr,
    }
    if vk.CreatePipelineLayout(ctx.device, &sky_li, nil, &world_renderer.sky_layout) != .SUCCESS do return false
    engine.vk_set_debug_name(ctx, .PIPELINE_LAYOUT, auto_cast world_renderer.sky_layout, "sky pipeline layout")
    vert, frag: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/world.slang", "shaders/world.vert", .Vertex, "vertex_main", &vert) do return false
    defer engine.vk_destroy_shader_module(ctx, &vert)
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/world.slang", "shaders/world.frag", .Fragment, "fragment_main", &frag) do return false
    defer engine.vk_destroy_shader_module(ctx, &frag)
    stages := [2]vk.PipelineShaderStageCreateInfo {
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = vert.handle, pName = "main"},
        {sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = frag.handle, pName = "main"},
    }
    binding := vk.VertexInputBindingDescription {
        stride    = u32(size_of(World_Vertex)),
        inputRate = .VERTEX,
    }
    attrs := [6]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(World_Vertex, position))},
        {location = 1, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(World_Vertex, color))},
        {location = 2, format = .R32_UINT, offset = u32(offset_of(World_Vertex, kind))},
        {location = 3, format = .R32G32B32_SFLOAT, offset = u32(offset_of(World_Vertex, normal))},
        {location = 4, format = .R32G32_SFLOAT, offset = u32(offset_of(World_Vertex, material))},
        {location = 5, format = .R32G32_SFLOAT, offset = u32(offset_of(World_Vertex, uv))},
    }
    vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &binding,
        vertexAttributeDescriptionCount = 6,
        pVertexAttributeDescriptions    = raw_data(attrs[:]),
    }
    ia := vk.PipelineInputAssemblyStateCreateInfo {
        sType    = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        topology = .TRIANGLE_LIST,
    }
    vp := vk.PipelineViewportStateCreateInfo {
        sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        viewportCount = 1,
        scissorCount  = 1,
    }
    rs := vk.PipelineRasterizationStateCreateInfo {
        sType       = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        polygonMode = .FILL,
        cullMode    = {.BACK},
        frontFace   = .COUNTER_CLOCKWISE,
        lineWidth   = 1,
    }
    ms := vk.PipelineMultisampleStateCreateInfo {
        sType                = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        rasterizationSamples = {._1},
    }
    depth := vk.PipelineDepthStencilStateCreateInfo {
        sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable  = true,
        depthWriteEnable = true,
        depthCompareOp   = .LESS,
    }
    ca := vk.PipelineColorBlendAttachmentState {
        // World vertices are mostly opaque, but authored shadows use their
        // alpha for a soft penumbra. Keep alpha-one geometry unchanged while
        // allowing those shadow layers to composite over the terrain.
        blendEnable         = true,
        srcColorBlendFactor = .SRC_ALPHA,
        dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
        colorBlendOp        = .ADD,
        srcAlphaBlendFactor = .ONE,
        dstAlphaBlendFactor = .ONE_MINUS_SRC_ALPHA,
        alphaBlendOp        = .ADD,
        colorWriteMask      = {.R, .G, .B, .A},
    }
    cb := vk.PipelineColorBlendStateCreateInfo {
        sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        attachmentCount = 1,
        pAttachments    = &ca,
    }
    ds := [2]vk.DynamicState{.VIEWPORT, .SCISSOR}
    di := vk.PipelineDynamicStateCreateInfo {
        sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        dynamicStateCount = 2,
        pDynamicStates    = raw_data(ds[:]),
    }
    info := vk.GraphicsPipelineCreateInfo {
        sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
        stageCount          = 2,
        pStages             = raw_data(stages[:]),
        pVertexInputState   = &vi,
        pInputAssemblyState = &ia,
        pViewportState      = &vp,
        pRasterizationState = &rs,
        pMultisampleState   = &ms,
        pDepthStencilState  = &depth,
        pColorBlendState    = &cb,
        pDynamicState       = &di,
        layout              = world_renderer.layout,
    }
    if !render3d.create_color_pipeline_variants(ctx, &info, .D32_SFLOAT, &world_renderer.pipelines) do return false
    shadow_vert, shadow_frag: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/world.slang",
        "shaders/player-shadow.vert",
        .Vertex,
        "shadow_vertex",
        &shadow_vert,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &shadow_vert)
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/world.slang",
        "shaders/player-shadow.frag",
        .Fragment,
        "shadow_fragment",
        &shadow_frag,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &shadow_frag)
    shadow_stages := stages
    shadow_stages[0].module = shadow_vert.handle
    shadow_stages[1].module = shadow_frag.handle
    shadow_rs := rs
    shadow_rs.cullMode = {}
    shadow_rs.depthBiasEnable = true
    // The character shadow lies almost coplanar with roads and terrain.
    // A one-unit bias still produces horizontal depth-fighting gaps at the
    // low gameplay camera, especially on road crowns. Pull the shadow toward
    // the camera in depth only so its silhouette remains continuous without
    // visibly lifting the projected geometry away from the ground.
    shadow_rs.depthBiasConstantFactor = -8
    shadow_rs.depthBiasSlopeFactor = -2
    shadow_depth := depth
    shadow_depth.depthCompareOp = .LESS_OR_EQUAL
    shadow_info := info
    shadow_info.pStages = raw_data(shadow_stages[:])
    shadow_info.pRasterizationState = &shadow_rs
    shadow_info.pDepthStencilState = &shadow_depth
    if !render3d.create_color_pipeline_variants(ctx, &shadow_info, .D32_SFLOAT, &world_renderer.shadow_pipelines) {
        return false
    }
    // Roads are submitted after the terrain. A small negative polygon offset
    // pulls only their fragments toward the camera under the conventional
    // LESS depth convention, preventing coplanar flicker at grazing angles
    // without making unrelated world geometry bleed through terrain.
    road_rs := rs
    // Roads are a thin authored terrain overlay and legacy edge, cap, and
    // junction builders do not share one winding convention. Keep only this
    // dedicated pass two-sided so back-face culling cannot erase long strips.
    road_rs.cullMode = {}
    road_rs.depthBiasEnable = true
    road_rs.depthBiasConstantFactor = -1
    road_rs.depthBiasSlopeFactor = -1
    road_depth := depth
    road_depth.depthCompareOp = .LESS_OR_EQUAL
    road_info := info
    road_info.pRasterizationState = &road_rs
    road_info.pDepthStencilState = &road_depth
    if !render3d.create_color_pipeline_variants(ctx, &road_info, .D32_SFLOAT, &world_renderer.road_pipelines) do return false
    foliage_vert, foliage_frag: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/foliage.slang",
        "shaders/foliage.vert",
        .Vertex,
        "vertex_main",
        &foliage_vert,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &foliage_vert)
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/foliage.slang",
        "shaders/foliage.frag",
        .Fragment,
        "fragment_main",
        &foliage_frag,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &foliage_frag)
    foliage_stages := stages
    foliage_stages[0].module = foliage_vert.handle
    foliage_stages[1].module = foliage_frag.handle
    foliage_binding := vk.VertexInputBindingDescription {
        stride    = u32(size_of(Foliage_Vertex)),
        inputRate = .VERTEX,
    }
    foliage_attributes := [4]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Foliage_Vertex, position))},
        {location = 1, format = .R32G32_SFLOAT, offset = u32(offset_of(Foliage_Vertex, uv))},
        {location = 2, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Foliage_Vertex, color))},
        {location = 3, format = .R32_UINT, offset = u32(offset_of(Foliage_Vertex, kind))},
    }
    foliage_vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &foliage_binding,
        vertexAttributeDescriptionCount = 4,
        pVertexAttributeDescriptions    = raw_data(foliage_attributes[:]),
    }
    foliage_depth := depth
    foliage_depth.depthCompareOp = .LESS_OR_EQUAL
    foliage_info := info
    foliage_info.pStages = raw_data(foliage_stages[:])
    foliage_info.pVertexInputState = &foliage_vi
    foliage_info.pDepthStencilState = &foliage_depth
    foliage_info.layout = world_renderer.foliage_layout
    if !render3d.create_color_pipeline_variants(ctx, &foliage_info, .D32_SFLOAT, &world_renderer.foliage_pipelines) {
        return false
    }
    grass_vert: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(
        ctx,
        "assets/shaders/foliage.slang",
        "shaders/grass.vert",
        .Vertex,
        "grass_vertex_main",
        &grass_vert,
    ) {
        return false
    }
    defer engine.vk_destroy_shader_module(ctx, &grass_vert)
    grass_stages := foliage_stages
    grass_stages[0].module = grass_vert.handle
    grass_binding := vk.VertexInputBindingDescription {
        stride    = u32(size_of(Grass_Instance)),
        inputRate = .INSTANCE,
    }
    grass_attributes := [4]vk.VertexInputAttributeDescription {
        {location = 0, format = .R32G32B32_SFLOAT, offset = u32(offset_of(Grass_Instance, center))},
        {location = 1, format = .R32G32_SFLOAT, offset = u32(offset_of(Grass_Instance, size))},
        {location = 2, format = .R32_UINT, offset = u32(offset_of(Grass_Instance, tile))},
        {location = 3, format = .R32G32B32A32_SFLOAT, offset = u32(offset_of(Grass_Instance, color))},
    }
    grass_vi := vk.PipelineVertexInputStateCreateInfo {
        sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = &grass_binding,
        vertexAttributeDescriptionCount = 4,
        pVertexAttributeDescriptions    = raw_data(grass_attributes[:]),
    }
    grass_info := foliage_info
    grass_info.pStages = raw_data(grass_stages[:])
    grass_info.pVertexInputState = &grass_vi
    if !render3d.create_color_pipeline_variants(ctx, &grass_info, .D32_SFLOAT, &world_renderer.grass_pipelines) {
        return false
    }
    particle_vert, particle_frag: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/particles.slang", "shaders/particles.vert", .Vertex, "vertex_main", &particle_vert) do return false
    defer engine.vk_destroy_shader_module(ctx, &particle_vert)
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/particles.slang", "shaders/particles.frag", .Fragment, "fragment_main", &particle_frag) do return false
    defer engine.vk_destroy_shader_module(ctx, &particle_frag)
    particle_stages := stages
    particle_stages[0].module = particle_vert.handle
    particle_stages[1].module = particle_frag.handle
    particle_info := info
    particle_info.pStages = raw_data(particle_stages[:])
    particle_vi := vk.PipelineVertexInputStateCreateInfo {
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    }
    particle_info.pVertexInputState = &particle_vi
    particle_info.pInputAssemblyState = &ia
    particle_info.pInputAssemblyState.topology = .TRIANGLE_LIST
    particle_info.pDepthStencilState = &depth
    particle_info.layout = world_renderer.layout
    if !render3d.create_color_pipeline_variants(ctx, &particle_info, .D32_SFLOAT, &world_renderer.particle_pipelines) do return false
    sky_vert, sky_frag: engine.Vk_Shader_Module
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/sky.slang", "shaders/world-sky.vert", .Vertex, "sky_vertex", &sky_vert) do return false
    defer engine.vk_destroy_shader_module(ctx, &sky_vert)
    if !engine.vk_load_shader_module_with_fallback(ctx, "assets/shaders/sky.slang", "shaders/world-sky.frag", .Fragment, "sky_fragment", &sky_frag) do return false
    defer engine.vk_destroy_shader_module(ctx, &sky_frag)
    stages[0].module = sky_vert.handle
    stages[1].module = sky_frag.handle
    sky_vi := vk.PipelineVertexInputStateCreateInfo {
        sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
    }
    sky_depth := vk.PipelineDepthStencilStateCreateInfo {
        sType            = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
        depthTestEnable  = false,
        depthWriteEnable = false,
    }
    // The sky writes alpha zero as a classification marker for the world
    // palette post-process. It must not alpha-blend against the cleared target,
    // or the marker would also attenuate the sky color.
    sky_ca := ca
    sky_ca.blendEnable = false
    sky_cb := cb
    sky_cb.pAttachments = &sky_ca
    sky_rs := rs
    sky_rs.cullMode = {}
    sky_info := info
    sky_info.pVertexInputState = &sky_vi
    sky_info.pDepthStencilState = &sky_depth
    sky_info.pColorBlendState = &sky_cb
    sky_info.pRasterizationState = &sky_rs
    sky_info.layout = world_renderer.sky_layout
    if !render3d.create_color_pipeline_variants(ctx, &sky_info, .D32_SFLOAT, &world_renderer.sky_pipelines) do return false
    for &buffer in world_renderer.vertex {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WORLD_VERTEX_INITIAL_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &buffer,
            "world dynamic vertex buffer",
        ) {
            return false
        }
    }
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WORLD_VERTEX_INITIAL_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &world_renderer.static_vertex[frame],
            "world static vertex buffer",
        ) {
            return false
        }
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WORLD_VERTEX_INITIAL_CAPACITY * size_of(u32)),
            {.INDEX_BUFFER},
            &world_renderer.static_index[frame],
            "world static index buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.road_vertex {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(ROAD_VERTEX_INITIAL_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &buffer,
            "world road vertex buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.foliage_vertex {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(
                (FOLIAGE_VERTEX_INITIAL_CAPACITY + BOUGAINVILLEA_VERTEX_INITIAL_CAPACITY) *
                size_of(Foliage_Vertex),
            ),
            {.VERTEX_BUFFER},
            &buffer,
            "world foliage vertex buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.grass_instance {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(
                (GRASS_INSTANCE_INITIAL_CAPACITY + WILDFLOWER_INSTANCE_INITIAL_CAPACITY) *
                size_of(Grass_Instance),
            ),
            {.VERTEX_BUFFER},
            &buffer,
            "world grass instance buffer",
        ) {
            return false
        }
    }
    for &buffer in world_renderer.vehicle_paint_staging {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(VEHICLE_PAINT_TEXTURE_BYTE_COUNT),
            {.TRANSFER_SRC},
            &buffer,
            "vehicle paint staging buffer",
        ) {
            return false
        }
    }
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WING_TRAIL_VERTEX_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &world_renderer.wing_trail_vertex[frame],
            "wing trail vertex buffer",
        ) {
            return false
        }
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(WING_TRAIL_INDEX_CAPACITY * size_of(u16)),
            {.INDEX_BUFFER},
            &world_renderer.wing_trail_index[frame],
            "wing trail index buffer",
        ) {
            return false
        }
        if !world_host_buffer_create(
            ctx,
            vk.DeviceSize(SHADOW_VERTEX_INITIAL_CAPACITY * size_of(World_Vertex)),
            {.VERTEX_BUFFER},
            &world_renderer.shadow_vertex[frame],
            "world shadow vertex buffer",
        ) {
            return false
        }
    }
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        for level in 0 ..< terrain.CLIPMAP_LEVELS {
            if !world_host_buffer_create(
                ctx,
                vk.DeviceSize(CLIPMAP_VERTEX_COUNT * size_of(World_Vertex)),
                {.VERTEX_BUFFER},
                &world_renderer.clipmap_vertex[frame][level],
                "world clipmap vertex buffer",
            ) {
                return false
            }
        }
    }
    if !clipmap_create_indices(ctx) do return false
    world_renderer.vertices = make([dynamic]World_Vertex, 0, WORLD_VERTEX_INITIAL_CAPACITY)
    world_renderer.static_vertices = make([dynamic]World_Vertex, 0, WORLD_VERTEX_INITIAL_CAPACITY)
    world_renderer.static_indices = make([dynamic]u32, 0, WORLD_VERTEX_INITIAL_CAPACITY)
    world_renderer.road_vertices = make([dynamic]World_Vertex, 0, ROAD_VERTEX_INITIAL_CAPACITY)
    world_renderer.foliage_vertices = make([dynamic]Foliage_Vertex, 0, FOLIAGE_VERTEX_INITIAL_CAPACITY)
    world_renderer.bougainvillea_vertices =
        make([dynamic]Foliage_Vertex, 0, BOUGAINVILLEA_VERTEX_INITIAL_CAPACITY)
    world_renderer.grass_instances = make([dynamic]Grass_Instance, 0, GRASS_INSTANCE_INITIAL_CAPACITY)
    world_renderer.wildflower_instances = make([dynamic]Grass_Instance, 0, WILDFLOWER_INSTANCE_INITIAL_CAPACITY)
    world_renderer.wing_trail_vertices = make([dynamic]World_Vertex, 0, WING_TRAIL_VERTEX_CAPACITY)
    world_renderer.wing_trail_indices = make([dynamic]u16, 0, WING_TRAIL_INDEX_CAPACITY)
    world_renderer.wing_trail_optimized_indices = make([dynamic]u16, 0, WING_TRAIL_INDEX_CAPACITY)
    world_renderer.land_surface_samples = make([dynamic]World_Land_Surface_Sample, 0, 256)
    world_renderer.shadow_vertices = make([dynamic]World_Vertex, 0, SHADOW_VERTEX_INITIAL_CAPACITY)
    world_renderer.ctx = ctx
    world_renderer.initialized = true
    return true
}

world_pre_pass :: proc(pass: ^rl.World_Pass_Context, _: rawptr) {
    if !world_renderer.initialized && !world_renderer_create(pass.ctx) do return
    editor := world_renderer.editor
    if editor == nil do return
    vehicle_paint_atlas_flush(editor, pass.frame.command_buffer, int(pass.frame.frame_index))
    if !world_renderer.dynamic_shadow.enabled do return
    frame_index := int(pass.frame.frame_index)
    // Build before the canvas begins its color rendering scope so the same
    // animated frame can be submitted to the independent depth-only pass.
    world_renderer.dynamic_shadow.anchor = dynamic_shadow_resolve_anchor(editor)
    world_build(editor)
    dynamic_shadow_build_casters(editor)
    dynamic_shadow_update_transform(editor, frame_index)
    if len(world_renderer.shadow_vertices) > 0 {
        required := vk.DeviceSize(len(world_renderer.shadow_vertices) * size_of(World_Vertex))
        if !world_host_buffer_ensure(
            world_renderer.ctx,
            &world_renderer.shadow_vertex[frame_index],
            required,
            {.VERTEX_BUFFER},
            "world shadow vertex buffer",
        ) {
            return
        }
        mem.copy_non_overlapping(
            world_renderer.shadow_vertex[frame_index].mapped,
            raw_data(world_renderer.shadow_vertices[:]),
            int(required),
        )
    }
    dynamic_shadow_render(pass, frame_index)
    world_renderer.dynamic_shadow.frame_prepared = true
}

world_pass :: proc(pass: ^rl.World_Pass_Context, _: rawptr) {
    if !world_renderer.initialized do return
    editor := world_renderer.editor
    if editor == nil do return
    if !world_renderer.dynamic_shadow.frame_prepared {
        world_build(editor)
    }
    world_renderer.dynamic_shadow.frame_prepared = false
    if !editor.vehicle_showcase_scene && !lab_scene_replaces_world(editor) {
        clipmap_update(editor, int(pass.frame.frame_index))
    }
    frame_index := int(pass.frame.frame_index)
    if !world_frame_geometry_buffers_ensure(frame_index) do return
    buffer := &world_renderer.vertex[frame_index]
    static_vertex_buffer := &world_renderer.static_vertex[frame_index]
    static_index_buffer := &world_renderer.static_index[frame_index]
    road_buffer := &world_renderer.road_vertex[frame_index]
    foliage_buffer := &world_renderer.foliage_vertex[frame_index]
    grass_instance_buffer := &world_renderer.grass_instance[frame_index]
    wing_trail_vertex_buffer := &world_renderer.wing_trail_vertex[frame_index]
    wing_trail_index_buffer := &world_renderer.wing_trail_index[frame_index]
    if len(world_renderer.vertices) > 0 {
        mem.copy_non_overlapping(
            buffer.mapped,
            raw_data(world_renderer.vertices[:]),
            len(world_renderer.vertices) * size_of(World_Vertex),
        )
    }
    if len(world_renderer.static_vertices) > 0 {
        mem.copy_non_overlapping(
            static_vertex_buffer.mapped,
            raw_data(world_renderer.static_vertices[:]),
            len(world_renderer.static_vertices) * size_of(World_Vertex),
        )
    }
    if len(world_renderer.static_indices) > 0 {
        mem.copy_non_overlapping(
            static_index_buffer.mapped,
            raw_data(world_renderer.static_indices[:]),
            len(world_renderer.static_indices) * size_of(u32),
        )
    }
    if len(world_renderer.road_vertices) > 0 {
        mem.copy_non_overlapping(
            road_buffer.mapped,
            raw_data(world_renderer.road_vertices[:]),
            len(world_renderer.road_vertices) * size_of(World_Vertex),
        )
    }
    if len(world_renderer.foliage_vertices) > 0 {
        mem.copy_non_overlapping(
            foliage_buffer.mapped,
            raw_data(world_renderer.foliage_vertices[:]),
            len(world_renderer.foliage_vertices) * size_of(Foliage_Vertex),
        )
    }
    if len(world_renderer.bougainvillea_vertices) > 0 {
        destination := cast(rawptr)(cast(uintptr)foliage_buffer.mapped +
            uintptr(len(world_renderer.foliage_vertices) * size_of(Foliage_Vertex)))
        mem.copy_non_overlapping(
            destination,
            raw_data(world_renderer.bougainvillea_vertices[:]),
            len(world_renderer.bougainvillea_vertices) * size_of(Foliage_Vertex),
        )
    }
    if len(world_renderer.grass_instances) > 0 {
        mem.copy_non_overlapping(
            grass_instance_buffer.mapped,
            raw_data(world_renderer.grass_instances[:]),
            len(world_renderer.grass_instances) * size_of(Grass_Instance),
        )
    }
    if len(world_renderer.wildflower_instances) > 0 {
        destination := cast(rawptr)(cast(uintptr)grass_instance_buffer.mapped +
            uintptr(len(world_renderer.grass_instances) * size_of(Grass_Instance)))
        mem.copy_non_overlapping(
            destination,
            raw_data(world_renderer.wildflower_instances[:]),
            len(world_renderer.wildflower_instances) * size_of(Grass_Instance),
        )
    }
    if len(world_renderer.wing_trail_vertices) > 0 {
        mem.copy_non_overlapping(
            wing_trail_vertex_buffer.mapped,
            raw_data(world_renderer.wing_trail_vertices),
            len(world_renderer.wing_trail_vertices) * size_of(World_Vertex),
        )
        mem.copy_non_overlapping(
            wing_trail_index_buffer.mapped,
            raw_data(world_renderer.wing_trail_optimized_indices),
            len(world_renderer.wing_trail_optimized_indices) * size_of(u16),
        )
    }
    viewport := vk.Viewport {
        width    = f32(pass.framebuffer_extent.width),
        height   = f32(pass.framebuffer_extent.height),
        minDepth = 0,
        maxDepth = 1,
    }
    scissor := vk.Rect2D {
        extent = pass.framebuffer_extent,
    }
    vk.CmdSetViewport(pass.frame.command_buffer, 0, 1, &viewport)
    vk.CmdSetScissor(pass.frame.command_buffer, 0, 1, &scissor)
    pipeline_index := pass.color_format == vk.Format.R16G16B16A16_SFLOAT ? 1 : 0
    render_camera_pose :=
        editor.pause_screen == .Customization ? customization_preview_camera_pose() : editor.camera_pose
    focal_length :=
        editor.vehicle_showcase_scene ? VEHICLE_SHOWCASE_FOCAL_LENGTH : (editor.in_map && driving_aircraft(editor) ? editor.flight_camera.focal_length : 1.35)
    if editor.cinematic_playback.script != nil {
        focal_length = max(editor.cinematic_focal_length, f32(.01))
    }
    camera := perspective_camera(render_camera_pose, focal_length)
    sky := atmosphere.sample(&editor.atmosphere)
    fog := world_sky_horizon_color(sky)
    world_push := World_Push {
        camera_position = {camera.position.x, camera.position.y, camera.position.z, world_camera_near_clip(editor)},
        camera_right    = {camera.right.x, camera.right.y, camera.right.z, WORLD_FAR_CLIP},
        camera_up       = {camera.up.x, camera.up.y, camera.up.z, 0},
        camera_forward  = {camera.forward.x, camera.forward.y, camera.forward.z, 0},
        projection      = {
            camera.focal_length,
            f32(pass.framebuffer_extent.width) / f32(max(pass.framebuffer_extent.height, 1)),
            WORLD_FOG_START,
            WORLD_FOG_END,
        },
        fog_color       = world_color(fog),
        water           = {sky.cloud_time_seconds, sky.weather.severity, sky.weather.wind[0], sky.weather.wind[1]},
        sun             = world_scene_sun(editor, sky),
    }
    sky_push := Sky_Push {
        camera_right   = {
            camera.right.x,
            camera.right.y,
            camera.right.z,
            f32(pass.framebuffer_extent.width) / f32(max(pass.framebuffer_extent.height, 1)),
        },
        camera_up      = {camera.up.x, camera.up.y, camera.up.z, camera.focal_length},
        camera_forward = {camera.forward.x, camera.forward.y, camera.forward.z, 0},
        sun_direction  = {sky.sun_direction[0], sky.sun_direction[1], sky.sun_direction[2], f32(sky.cloud_seed)},
        moon_direction = {sky.moon_direction[0], sky.moon_direction[1], sky.moon_direction[2], sky.moon_illumination},
        time_light     = {sky.world_minutes, sky.cloud_time_seconds, sky.daylight, sky.twilight},
        wind_cloud     = {
            sky.weather.wind[0],
            sky.weather.wind[1],
            sky.weather.cloud_cover,
            sky.weather.precipitation,
        },
        haze_severity  = {sky.weather.haze, sky.weather.severity, sky.world_days, 0},
    }
    offset := vk.DeviceSize(0)
    graph_context := Render_Graph_Context {
        pass                     = pass,
        buffer                   = buffer,
        static_vertex_buffer     = static_vertex_buffer,
        static_index_buffer      = static_index_buffer,
        road_buffer              = road_buffer,
        foliage_buffer           = foliage_buffer,
        grass_instance_buffer    = grass_instance_buffer,
        wing_trail_vertex_buffer = wing_trail_vertex_buffer,
        wing_trail_index_buffer  = wing_trail_index_buffer,
        offset                   = offset,
        pipeline_index           = pipeline_index,
        world_push               = world_push,
        sky_push                 = sky_push,
    }
    if !world_render_graph_ready {
        world_render_graph_ready = adriatic_render_graph(&world_render_graph)
    }
    if world_render_graph_ready do _ = render_graph.execute(&world_render_graph, &graph_context)
}

world_renderer_attach :: proc(editor: ^Editor) {
    world_renderer.editor = editor
    rl.SetWorldPrePass(world_pre_pass)
    rl.SetWorldPass(world_pass)
    rl.SetUIPass(imgui_ui_pass)
}

world_renderer_destroy :: proc() {
    if !world_renderer.initialized do return
    _ = vk.DeviceWaitIdle(world_renderer.ctx.device)
    imgui_destroy()
    for &buffer in world_renderer.vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.static_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.static_index do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.road_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.foliage_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.grass_instance do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.vehicle_paint_staging do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.wing_trail_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.wing_trail_index do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for &buffer in world_renderer.shadow_vertex do engine.vk_destroy_buffer(world_renderer.ctx, &buffer)
    for frame in 0 ..< engine.MAX_FRAMES_IN_FLIGHT {
        for level in 0 ..< terrain.CLIPMAP_LEVELS {
            engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_vertex[frame][level])
        }
    }
    engine.vk_destroy_buffer(world_renderer.ctx, &world_renderer.clipmap_index)
    roads.mesh_destroy(&world_renderer.road_mesh)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.shadow_pipelines)
    dynamic_shadow_destroy(&world_renderer.dynamic_shadow, world_renderer.ctx)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.road_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.sky_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.particle_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.foliage_pipelines)
    render3d.destroy_color_pipeline_variants(world_renderer.ctx, &world_renderer.grass_pipelines)
    resources.image_destroy(&world_renderer.foliage_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.bougainvillea_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.grass_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.wildflower_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.vehicle_paint_atlas, world_renderer.ctx)
    resources.image_destroy(&world_renderer.soda_cap_logo, world_renderer.ctx)
    if world_renderer.layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.layout, nil)
    if world_renderer.sky_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.sky_layout, nil)
    if world_renderer.foliage_layout != vk.PipelineLayout(0) do vk.DestroyPipelineLayout(world_renderer.ctx.device, world_renderer.foliage_layout, nil)
    if world_renderer.foliage_descriptor_pool != vk.DescriptorPool(0) {
        vk.DestroyDescriptorPool(world_renderer.ctx.device, world_renderer.foliage_descriptor_pool, nil)
    }
    if world_renderer.foliage_descriptor_layout != vk.DescriptorSetLayout(0) {
        vk.DestroyDescriptorSetLayout(world_renderer.ctx.device, world_renderer.foliage_descriptor_layout, nil)
    }
    if world_renderer.vehicle_paint_descriptor_pool != vk.DescriptorPool(0) {
        vk.DestroyDescriptorPool(world_renderer.ctx.device, world_renderer.vehicle_paint_descriptor_pool, nil)
    }
    if world_renderer.vehicle_paint_descriptor_layout != vk.DescriptorSetLayout(0) {
        vk.DestroyDescriptorSetLayout(world_renderer.ctx.device, world_renderer.vehicle_paint_descriptor_layout, nil)
    }
    delete(world_renderer.vertices)
    delete(world_renderer.static_vertices)
    delete(world_renderer.static_indices)
    delete(world_renderer.road_vertices)
    delete(world_renderer.foliage_vertices)
    delete(world_renderer.bougainvillea_vertices)
    delete(world_renderer.grass_instances)
    delete(world_renderer.wildflower_instances)
    delete(world_renderer.wing_trail_vertices)
    delete(world_renderer.wing_trail_indices)
    delete(world_renderer.wing_trail_optimized_indices)
    delete(world_renderer.land_surface_samples)
    delete(world_renderer.shadow_vertices)
    for &entry in world_renderer.foliage_geometry_cache {
        delete(entry.world_vertices)
        delete(entry.foliage_vertices)
    }
    delete(world_renderer.foliage_geometry_cache)
    for &entry in world_renderer.static_geometry_cache {
        delete(entry.world_vertices)
        delete(entry.world_indices)
        delete(entry.foliage_vertices)
        delete(entry.bougainvillea_vertices)
    }
    delete(world_renderer.static_geometry_cache)
    for &entry in world_renderer.climbing_leaf_geometry_cache {
        delete(entry.world_vertices)
        delete(entry.bougainvillea_vertices)
    }
    delete(world_renderer.climbing_leaf_geometry_cache)
    delete(world_renderer.static_visibility_classification)
    delete(world_renderer.structure_visibility_order)
    delete(world_renderer.structure_visibility_centers)
    delete(world_renderer.structure_building_spans)
    delete(world_renderer.structure_candidates)
    for &entry in world_renderer.town_mouse_geometry_cache {
        delete(entry.vertices)
    }
    for &entry in world_renderer.marina_geometry_cache {
        delete(entry.world_vertices)
    }
    world_renderer = {}
}
