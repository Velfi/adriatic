package main

import architecture "../packages/architecture"
import circulation "../packages/circulation"
import flight "../packages/flight"
import fountains "../packages/fountains"
import roads "../packages/roads"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "zelda_engine:third_person"
import vehicles "../packages/vehicles"
import vk "vendor:vulkan"
import engine "zelda_engine:engine"
import render3d "zelda_engine:render3d"
import resources "zelda_engine:render_resources"

// Stable semantic surface IDs shared by settlement generators. Keep existing
// values fixed: generated geometry and shaders exchange these compact IDs.
Settlement_Material :: enum u8 {
    Pale_Adriatic_Limestone,
    Sun_Washed_Stucco,
    Arcade_Terrazzo,
    Counter_Toe_Kick,
    Painted_Steel,
    Dark_Hardware,
    Bench_Slatted_Hardwood,
    Fired_Terracotta,
    Moist_Planter_Soil,
    Airport_Asphalt,
    Pale_Concrete_Curb,
    Drainage_Grate,
    Road_Marking_White,
    Road_Marking_Ochre,
    Aged_Brass_Details,
    Aerodromo_Enamel_Face,
    Aerodromo_Enamel_Rim,
    Exposed_Salted_Limestone,
    Foot_Polished_Terrazzo,
    Exterior_Forecourt_Paving,
    Standing_Seam_Roof,
    Monitor_Tinted_Glass,
    Anodized_Glazing_Frame,
    Teal_Counter_Tile,
    Counter_Grout,
    Counter_Worktop_Laminate,
    Postal_Enamel_Red,
    Postal_Sorting_Wood,
}

Car_Paint_Finish :: enum u8 {
    Opaque,
    Metal_Flake,
}

World_Vertex :: struct {
    position: [3]f32,
    color:    [4]f32,
    kind:     World_Material_Kind,
    normal:   [3]f32,
    // Lit: metallic, roughness. Car paint: finish, roughness.
    // Vehicle: paintable, atlas layer.
    material: [2]f32,
    uv:       [2]f32,
}

Plant_Vertex :: struct {
    position:         [3]f32,
    color:            [4]f32,
    kind:             World_Material_Kind,
    normal:           [3]f32,
    material:         [2]f32,
    uv:               [2]f32,
    primary_anchor:   [3]f32,
    secondary_anchor: [3]f32,
    axis_position:    f32,
    stiffness:        f32,
    leaf_pivot:       [3]f32,
    flutter:          f32,
    hierarchy_depth:  u32,
    phase:            f32,
}

World_Land_Surface_Sample :: struct {
    x, z, height: f32,
}

Town_Mouse_Placement :: struct {
    position: third_person.Vec3,
    rotation: f32,
    valid:    bool,
}

Resident_Home_Cache_Entry :: struct {
    position: third_person.Vec3,
    rotation: f32,
    found:    bool,
    valid:    bool,
}

Road_Geometry_Cache_Chunk :: struct {
    first_vertex: int,
    vertex_count: int,
    center:       third_person.Vec3,
    radius:       f32,
}

Architecture_Alley_Render_Cache :: struct {
    valid:           bool,
    alley:           architecture.City_Alley,
    curve_points:    [13][2]f32,
    curve_distances: [13]f32,
    curve_segments:  int,
    curve_length:    f32,
    grade:           f32,
    start_height:    f32,
    end_height:      f32,
}

Architecture_Alley_Overlap_Cache :: struct {
    valid:     bool,
    structure: terrain.Structure,
    overlaps:  bool,
}

Foliage_Vertex :: struct {
    position: [3]f32,
    uv:       [2]f32,
    color:    [4]f32,
    kind:     u32,
}

Bougainvillea_Card_Descriptor :: struct {
    center:       third_person.Vec3,
    width:        f32,
    height:       f32,
    tile:         int,
    mirror:       bool,
    roll:         f32,
    value:        f32,
    young_growth: bool,
    yaw_bias:     f32,
}

Bougainvillea_Instance :: struct {
    center:   [3]f32,
    size:     [2]f32,
    tile:     u32,
    // x: mirror, y: roll, z: value, w: young-growth marker.
    params:   [4]f32,
    yaw_bias: f32,
}

Grass_Instance :: struct {
    center:       [3]f32,
    size:         [2]f32,
    tile:         u32,
    color:        [4]f32,
    ground_color: [4]f32,
    // x: deterministic density roll, y: field radius, z: GPU culling enabled.
    cull_params:  [4]f32,
}

World_Mesh_Instance :: struct {
    basis_x_translation_x: [4]f32,
    basis_y_translation_y: [4]f32,
    basis_z_translation_z: [4]f32,
    color:                 [4]f32,
    normal_override:       [4]f32,
    // xyz: rooted plant origin, w: species/maturity compliance. Zero keeps
    // ordinary world instances on the existing non-hierarchical path.
    plant_root_compliance: [4]f32,
    // x: deterministic phase, y: stiffness, z: flutter, w: LOD opacity.
    plant_motion:          [4]f32,
}

World_Instance_Mesh :: struct {
    first_vertex:    u32,
    vertex_capacity: u32,
    first_index:     u32,
    index_count:     u32,
    index_capacity:  u32,
    first_instance:  u32,
    casts_shadow:    bool,
    instances:       [dynamic]World_Mesh_Instance,
}

Plant_Instance_Mesh :: struct {
    first_vertex:    u32,
    vertex_capacity: u32,
    first_index:     u32,
    index_count:     u32,
    index_capacity:  u32,
    first_instance:  u32,
    casts_shadow:    bool,
    available:       bool,
    instances:       [dynamic]World_Mesh_Instance,
}

Middle_Tree_Shadow_Proxy :: struct {
    center:                       third_person.Vec3,
    radius_x, radius_y, radius_z: f32,
}

Architecture_Grass_Footprint :: struct {
    center_x, center_z:     f32,
    half_width, half_depth: f32,
    rotation:               f32,
}

Foliage_Geometry_Cache_Entry :: struct {
    valid:            bool,
    structure:        terrain.Structure,
    aerial_view:      bool,
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
    plant_lod:              Generated_Plant_Render_LOD,
    lod_transition:         f32,
    billboard_right:        [3]f32,
    billboard_up:           [3]f32,
    world_vertices:         [dynamic]World_Vertex,
    world_indices:          [dynamic]u32,
    foliage_vertices:       [dynamic]Foliage_Vertex,
    bougainvillea_vertices: [dynamic]Foliage_Vertex,
    bougainvillea_cards:    [dynamic]Bougainvillea_Card_Descriptor,
    retained_first_vertex:  u32,
    retained_first_index:   u32,
}

Retained_Static_Draw :: struct {
    cache_index: int,
}

Climbing_Leaf_Geometry_Cache_Entry :: struct {
    valid:                  bool,
    structure:              terrain.Structure,
    density:                f32,
    detail_tier:            int,
    capture_seed_enabled:   bool,
    capture_seed:           u32,
    billboard_right:        [3]f32,
    billboard_up:           [3]f32,
    world_vertices:         [dynamic]World_Vertex,
    bougainvillea_vertices: [dynamic]Foliage_Vertex,
    cards:                  [dynamic]Bougainvillea_Card_Descriptor,
}

TOWN_MOUSE_CACHE_TOWN_FIRST :: 0
TOWN_MOUSE_CACHE_TOWN_COUNT :: len(terrain.DEFAULT_ISLAND_SIGNS) * 8
TOWN_MOUSE_CACHE_ZORA :: TOWN_MOUSE_CACHE_TOWN_FIRST + TOWN_MOUSE_CACHE_TOWN_COUNT
TOWN_MOUSE_CACHE_POSTAL_FIRST :: TOWN_MOUSE_CACHE_ZORA + 1
TOWN_MOUSE_CACHE_MEETING_NIKO :: TOWN_MOUSE_CACHE_POSTAL_FIRST + 2
TOWN_MOUSE_CACHE_MEETING_IVA :: TOWN_MOUSE_CACHE_MEETING_NIKO + 1
TOWN_MOUSE_CACHE_LIGHTHOUSE_FIRST :: TOWN_MOUSE_CACHE_MEETING_IVA + 1
TOWN_MOUSE_CACHE_COUNT :: TOWN_MOUSE_CACHE_LIGHTHOUSE_FIRST + len(terrain.DEFAULT_ISLAND_SIGNS)
TOWN_MOUSE_PORTRAIT_ANIMATION_HZ :: f32(30)
TOWN_MOUSE_TERRAIN_RADIUS :: f32(2.5)
TOWN_MOUSE_GROUND_SAMPLE_COUNT :: 32

Town_Mouse_Geometry_Cache_Entry :: struct {
    valid:                   bool,
    model:                   Mouse_Model,
    scale:                   f32,
    animation_bucket:        i64,
    project_revision:        u64,
    terrain_revision:        u64,
    ground_valid:            bool,
    ground_model:            Mouse_Model,
    ground_scale:            f32,
    ground_project_revision: u64,
    ground_terrain_revision: u64,
    ground_sample_count:     int,
    ground_samples:          [TOWN_MOUSE_GROUND_SAMPLE_COUNT]f32,
    vertices:                [dynamic]World_Vertex,
}

Town_Mouse_Ground_Cache_Context :: struct {
    entry:  ^Town_Mouse_Geometry_Cache_Entry,
    reuse:  bool,
    cursor: int,
}

Libellula_Geometry_Cache_Entry :: struct {
    valid:       bool,
    body:        flight.Body_State,
    kind:        vehicles.Aircraft_Kind,
    rotor_turns: [3]f32,
    pitch, roll: f32,
    vertices:    [dynamic]World_Vertex,
}

Terrain_Dirty_Bounds :: struct {
    valid:        bool,
    full_rebuild: bool,
    revision:     u64,
    min_x, min_z: f32,
    max_x, max_z: f32,
}

Architecture_Street_Area_Cache :: struct {
    valid:                              bool,
    area:                               circulation.Area,
    project_revision, terrain_revision: u64,
    vertices:                           [dynamic]World_Vertex,
}

Settlement_Fountain_Geometry_Cache :: struct {
    valid:            bool,
    structure_id:     u64,
    seed:             u32,
    radius:           f32,
    style:            fountains.Style,
    jet_count:        int,
    jet_height:       f32,
    origin:           third_person.Vec3,
    rotation:         f32,
    terrain_revision: u64,
    vertices:         [dynamic]World_Vertex,
}

Airport_Kiosk_Geometry_Cache :: struct {
    position_x, position_z: f32,
    rotation:               f32,
    terrain_revision:       u64,
    plant_lods:             [4]Generated_Plant_Render_LOD,
    valid:                  bool,
    prefix_vertices:        [dynamic]World_Vertex,
    suffix_vertices:        [dynamic]World_Vertex,
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

World_Shadow_Caster_Range :: struct {
    first: int,
    count: int,
}

World_Static_Shadow_Caster_Range :: struct {
    first, count:     int,
    minimum, maximum: third_person.Vec3,
}

Dynamic_Shadow_Terrain_Cache :: struct {
    vertices:                           [dynamic]World_Vertex,
    start_x, start_z:                   f32,
    project_revision, terrain_revision: u64,
    valid:                              bool,
}

Bathymetry_Geometry_Cache_Entry :: struct {
    vertices:           [dynamic]World_Vertex,
    chunk_x, chunk_z:   i32,
    owner:              terrain.Island_ID,
    source:             terrain.Water_Source_Kind,
    chunk_revision:     u64,
    origin_x, origin_z: f32,
    valid:              bool,
}

World_Renderer :: struct {
    editor:                                       ^Editor,
    ctx:                                          ^engine.Vk_Context,
    pipelines:                                    [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    player_outline_mask_pipelines:                [3]vk.Pipeline,
    transparent_pipelines:                        [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    shadow_pipelines:                             [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    dynamic_shadow:                               Dynamic_Shadow_State,
    shadow_vertex:                                [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    shadow_vertices:                              [dynamic]World_Vertex,
    shadow_world_ranges:                          [dynamic]World_Shadow_Caster_Range,
    dynamic_vertex_uploaded:                      bool,
    dynamic_shadow_terrain_cache:                 Dynamic_Shadow_Terrain_Cache,
    dynamic_shadow_terrain_cache_builds:          u64,
    dynamic_shadow_terrain_cache_reuses:          u64,
    dynamic_caster_first:                         int,
    dynamic_caster_count:                         int,
    explicit_shadow_caster_ranges:                [dynamic]World_Shadow_Caster_Range,
    static_shadow_caster_ranges:                  [dynamic]World_Static_Shadow_Caster_Range,
    road_pipelines:                               [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    sky_pipelines:                                [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    particle_pipelines:                           [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    foliage_pipelines:                            [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    bougainvillea_pipelines:                      [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    grass_pipelines:                              [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    instance_pipelines:                           [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    plant_pipelines:                              [render3d.COLOR_PIPELINE_VARIANT_COUNT]vk.Pipeline,
    layout:                                       vk.PipelineLayout,
    sky_layout:                                   vk.PipelineLayout,
    foliage_layout:                               vk.PipelineLayout,
    foliage_descriptor_layout:                    vk.DescriptorSetLayout,
    foliage_descriptor_pool:                      vk.DescriptorPool,
    foliage_descriptor:                           vk.DescriptorSet,
    bougainvillea_descriptor:                     vk.DescriptorSet,
    grass_descriptor:                             vk.DescriptorSet,
    wildflower_descriptor:                        vk.DescriptorSet,
    marsh_descriptor:                             vk.DescriptorSet,
    terrain_particle_descriptor:                  vk.DescriptorSet,
    foliage_atlas:                                resources.Image,
    bougainvillea_atlas:                          resources.Image,
    grass_atlas:                                  resources.Image,
    wildflower_atlas:                             resources.Image,
    marsh_atlas:                                  resources.Image,
    terrain_particle_atlas:                       resources.Image,
    vehicle_paint_atlas:                          resources.Image,
    soda_cap_logo:                                resources.Image,
    architecture_material_atlas:                  resources.Image,
    business_sign_atlas:                          resources.Image,
    material_lab_maps:                            [MATERIAL_LAB_MAP_COUNT]resources.Image,
    material_lab_map_revision:                    u64,
    vehicle_paint_staging:                        [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    vehicle_paint_descriptor_layout:              vk.DescriptorSetLayout,
    vehicle_paint_descriptor_pool:                vk.DescriptorPool,
    vehicle_paint_descriptor:                     vk.DescriptorSet,
    vehicle_paint_dirty_layers:                   [VEHICLE_PAINT_AIRCRAFT_COUNT]bool,
    vertex:                                       [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    static_vertex:                                [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    static_index:                                 [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    static_indirect:                              [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    road_vertex:                                  [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    road_indirect:                                [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    foliage_vertex:                               [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    bougainvillea_instance:                       [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    grass_instance:                               [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    instance_vertex:                              [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    plant_vertex:                                 [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    instance_index:                               [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    instance_data:                                [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    wing_trail_vertex:                            [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    wing_trail_index:                             [engine.MAX_FRAMES_IN_FLIGHT]engine.Vk_Buffer,
    vertices:                                     [dynamic]World_Vertex,
    late_transparent_vertices:                    [dynamic]World_Vertex,
    late_transparent_first:                       int,
    late_transparent_count:                       int,
    scene_daylight:                               f32,
    static_vertices:                              [dynamic]World_Vertex,
    static_indices:                               [dynamic]u32,
    retained_static_draws:                        [dynamic]Retained_Static_Draw,
    static_draw_commands:                         [dynamic]vk.DrawIndexedIndirectCommand,
    retained_static_revision:                     u64,
    retained_static_uploaded_revision:            [engine.MAX_FRAMES_IN_FLIGHT]u64,
    retained_static_dirty:                        bool,
    retained_patio_vertices:                      [dynamic]World_Vertex,
    retained_patio_indices:                       [dynamic]u32,
    retained_patio_first_vertex:                  u32,
    retained_patio_first_index:                   u32,
    retained_patio_index_count:                   u32,
    retained_patio_revision:                      u64,
    retained_patio_uploaded_revision:             [engine.MAX_FRAMES_IN_FLIGHT]u64,
    retained_patio_dirty:                         bool,
    retained_patio_rebuilding:                    bool,
    road_vertices:                                [dynamic]World_Vertex,
    road_draw_commands:                           [dynamic]vk.DrawIndirectCommand,
    foliage_vertices:                             [dynamic]Foliage_Vertex,
    bougainvillea_vertices:                       [dynamic]Foliage_Vertex,
    bougainvillea_instances:                      [dynamic]Bougainvillea_Instance,
    grass_instances:                              [dynamic]Grass_Instance,
    wildflower_instances:                         [dynamic]Grass_Instance,
    marsh_instances:                              [dynamic]Grass_Instance,
    terrain_particle_vertices:                    [dynamic]Foliage_Vertex,
    instance_vertices:                            [dynamic]World_Vertex,
    plant_vertices:                               [dynamic]Plant_Vertex,
    instance_indices:                             [dynamic]u32,
    instance_flattened:                           [dynamic]World_Mesh_Instance,
    instance_meshes:                              [dynamic]World_Instance_Mesh,
    plant_meshes:                                 [dynamic]Plant_Instance_Mesh,
    middle_tree_shadow_proxies:                   [dynamic]Middle_Tree_Shadow_Proxy,
    wing_trail_vertices:                          [dynamic]World_Vertex,
    wing_trail_indices:                           [dynamic]u16,
    wing_trail_optimized_indices:                 [dynamic]u16,
    land_surface_samples:                         [dynamic]World_Land_Surface_Sample,
    player_vertex_first:                          int,
    player_vertex_count:                          int,
    current_world_push:                           World_Push,
    player_shadow_receiver:                       f32,
    clipmap_vertex:                               [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]engine.Vk_Buffer,
    clipmap_index:                                engine.Vk_Buffer,
    clipmap_outer_full_index:                     engine.Vk_Buffer,
    clipmap_ring_index:                           [3][3]engine.Vk_Buffer,
    clipmap_full_indices:                         u32,
    clipmap_outer_full_indices:                   u32,
    clipmap_ring_indices:                         u32,
    clipmap_revision:                             [engine.MAX_FRAMES_IN_FLIGHT]u64,
    clipmap_center:                               [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS][2]f32,
    clipmap_valid:                                [engine.MAX_FRAMES_IN_FLIGHT][terrain.CLIPMAP_LEVELS]bool,
    clipmap_dirty:                                [engine.MAX_FRAMES_IN_FLIGHT]Terrain_Dirty_Bounds,
    clipmap_cache_dirty:                          Terrain_Dirty_Bounds,
    terrain_live_edit_active:                     bool,
    terrain_live_edit_dirty:                      Terrain_Dirty_Bounds,
    terrain_live_edit_frame_dirty:                Terrain_Dirty_Bounds,
    clipmap_cache_vertex:                         [terrain.CLIPMAP_LEVELS][dynamic]World_Vertex,
    clipmap_scratch_vertex:                       [terrain.CLIPMAP_LEVELS][dynamic]World_Vertex,
    clipmap_cache_center:                         [terrain.CLIPMAP_LEVELS][2]f32,
    clipmap_cache_valid:                          [terrain.CLIPMAP_LEVELS]bool,
    clipmap_cache_revision:                       u64,
    clipmap_first_level:                          int,
    clipmap_levels_generated:                     u64,
    clipmap_levels_copied:                        u64,
    clipmap_full_rebuilds:                        u64,
    clipmap_incremental_shifts:                   u64,
    clipmap_cells_copied:                         u64,
    clipmap_cells_generated:                      u64,
    grass_candidate_hits:                         u64,
    grass_candidate_misses:                       u64,
    grass_instances_emitted:                      u64,
    grass_stream_dirty:                           bool,
    grass_chunk_cache:                            map[[2]int]^Ground_Grass_Chunk,
    grass_chunk_pool:                             [dynamic]^Ground_Grass_Chunk,
    grass_chunk_clock:                            u64,
    grass_cache_terrain_revision:                 u64,
    grass_cache_project_revision:                 u64,
    climbing_leaf_cache_builds:                   u64,
    climbing_leaf_cache_reuses:                   u64,
    town_mouse_cache_builds:                      u64,
    town_mouse_cache_reuses:                      u64,
    town_mouse_ground_cache_hits:                 u64,
    town_mouse_ground_cache_misses:               u64,
    town_mouse_placements:                        [2][8]Town_Mouse_Placement,
    town_mouse_placement_project_revision:        u64,
    town_mouse_placement_terrain_revision:        u64,
    town_mouse_placement_valid:                   bool,
    resident_home_cache:                          [story.Resident]Resident_Home_Cache_Entry,
    resident_home_project_revision:               u64,
    resident_home_terrain_revision:               u64,
    resident_home_cache_valid:                    bool,
    ocean_geometry_cache:                         [dynamic]World_Vertex,
    ocean_cache_center:                           [2]f32,
    ocean_cache_grid_cell:                        f32,
    ocean_cache_project_revision:                 u64,
    ocean_cache_terrain_revision:                 u64,
    ocean_cache_sea_level:                        f32,
    ocean_cache_in_map:                           bool,
    ocean_cache_markov_island:                    bool,
    ocean_cache_valid:                            bool,
    ocean_sample_grid:                            [dynamic]World_Vertex,
    ocean_sample_grid_scratch:                    [dynamic]World_Vertex,
    ocean_sample_grid_center:                     [2]f32,
    ocean_sample_grid_cell:                       f32,
    ocean_sample_grid_valid:                      bool,
    ocean_sample_grid_dirty:                      Terrain_Dirty_Bounds,
    bathymetry_geometry_cache:                    [dynamic]Bathymetry_Geometry_Cache_Entry,
    bathymetry_geometry_cache_builds:             u64,
    bathymetry_geometry_cache_reuses:             u64,
    dirty_build_ms:                               f64,
    frame_build_ms:                               f64,
    visibility_build_cpu_ms:                      f64,
    texture_upload_ms:                            f64,
    rebuilt_static_objects:                       u64,
    rebuilt_static_pages:                         u64,
    static_bytes_uploaded:                        u64,
    indexed_cells:                                u64,
    visible_clusters:                             u64,
    indirect_command_count:                       u64,
    retired_bytes:                                u64,
    road_mesh:                                    roads.Mesh,
    road_graph:                                   roads.Graph,
    road_graph_valid:                             bool,
    road_revision:                                u64,
    road_geometry_cache:                          [dynamic]World_Vertex,
    road_geometry_chunks:                         [dynamic]Road_Geometry_Cache_Chunk,
    road_geometry_revision:                       u64,
    road_geometry_terrain_revision:               u64,
    road_geometry_valid:                          bool,
    road_geometry_gpu_revision:                   u64,
    road_geometry_uploaded_revision:              [engine.MAX_FRAMES_IN_FLIGHT]u64,
    architecture_alley_render_cache:              [dynamic]Architecture_Alley_Render_Cache,
    architecture_alley_terrain_revision:          u64,
    architecture_alley_project_revision:          u64,
    architecture_alley_geometry_cache:            [dynamic]World_Vertex,
    architecture_alley_geometry_plan:             [dynamic]architecture.City_Alley,
    architecture_alley_geometry_terrain_revision: u64,
    architecture_alley_geometry_project_revision: u64,
    architecture_alley_geometry_valid:            bool,
    architecture_alley_geometry_building:         bool,
    architecture_alley_overlap_cache:             [dynamic]Architecture_Alley_Overlap_Cache,
    architecture_alley_overlap_plan:              [dynamic]architecture.City_Alley,
    architecture_street_area_cache:               [dynamic]Architecture_Street_Area_Cache,
    settlement_fountain_geometry_cache:           [dynamic]Settlement_Fountain_Geometry_Cache,
    airport_kiosk_geometry_cache:                 [dynamic]Airport_Kiosk_Geometry_Cache,
    laundry_geometry_cache:                       [dynamic]World_Vertex,
    laundry_geometry_revision:                    u64,
    laundry_geometry_terrain_revision:            u64,
    laundry_geometry_valid:                       bool,
    pavement_query:                               roads.Pavement_Query,
    pavement_query_graph:                         roads.Graph,
    pavement_query_graph_valid:                   bool,
    pavement_query_revision:                      u64,
    foliage_geometry_cache:                       [dynamic]Foliage_Geometry_Cache_Entry,
    static_geometry_cache:                        [dynamic]Static_Geometry_Cache_Entry,
    climbing_leaf_geometry_cache:                 [dynamic]Climbing_Leaf_Geometry_Cache_Entry,
    town_mouse_geometry_cache:                    [TOWN_MOUSE_CACHE_COUNT]Town_Mouse_Geometry_Cache_Entry,
    dialogue_portrait_geometry_cache:             [2]Town_Mouse_Geometry_Cache_Entry,
    libellula_geometry_cache:                     Libellula_Geometry_Cache_Entry,
    postale_pose_mesh:                            ^vehicles.Aircraft_Mesh,
    trailer_pose_mesh:                            ^vehicles.Aircraft_Mesh,
    trailer_baked_meshes:                         [3]^vehicles.Aircraft_Mesh,
    marina_geometry_cache:                        [MARINA_GEOMETRY_CACHE_CAPACITY]Marina_Geometry_Cache_Entry,
    structure_lod_counts:                         [3]int,
    structure_lod_cache_rebuilds:                 u64,
    structure_lod_world_vertices:                 int,
    structure_lod_foliage_vertices:               int,
    static_visibility:                            Static_Visibility_Stats,
    static_visibility_classification:             [dynamic]Static_Visibility_Classification,
    structure_visibility_order:                   [dynamic]Structure_Visibility_Order,
    overlay_chunk_bounds:                         [dynamic]Overlay_Chunk_Bounds,
    overlay_chunk_terrain_revision:               u64,
    structure_building_spans:                     [dynamic]u8,
    structure_candidates:                         [dynamic]int,
    spatial_index:                                World_Spatial_Index,
    spatial_project_revision:                     u64,
    initialized:                                  bool,
}

world_renderer: World_Renderer
town_mouse_ground_cache_context: ^Town_Mouse_Ground_Cache_Context
climbing_leaf_card_capture: ^[dynamic]Bougainvillea_Card_Descriptor

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
