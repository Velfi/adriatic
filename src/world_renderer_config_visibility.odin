package main
import "core:math"
import "core:testing"

import cinematic "../packages/cinematic"
import particles "../packages/particles"
import terrain "../packages/terrain"
import "core:math/linalg"
import vk "vendor:vulkan"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

WORLD_VERTEX_INITIAL_CAPACITY :: 600_000
ROAD_VERTEX_INITIAL_CAPACITY :: 320_000
FOLIAGE_VERTEX_INITIAL_CAPACITY :: 24_000
// Bougainvillea cards use four anchor-centered sub-quads (24 vertices) so
// their painted roots remain fixed under wind. Preserve the former effective
// budget of 2,000 cards after that fourfold tessellation.
BOUGAINVILLEA_VERTEX_INITIAL_CAPACITY :: 48_000
GRASS_INSTANCE_INITIAL_CAPACITY :: 18_000
WILDFLOWER_INSTANCE_INITIAL_CAPACITY :: 4_000
MARSH_INSTANCE_INITIAL_CAPACITY :: 18_000
WING_TRAIL_VERTEX_CAPACITY :: particles.MAX_WING_TRAIL_PARTICLES * 8
WING_TRAIL_INDEX_CAPACITY :: (particles.MAX_WING_TRAIL_PARTICLES - 2) * 8 * 6 + 8 * 6
SHADOW_VERTEX_INITIAL_CAPACITY :: 180_000
CLIPMAP_GRID_RESOLUTION :: (terrain.TERRAIN_RESOLUTION - 1) / 2 + 2
CLIPMAP_VERTEX_COUNT :: CLIPMAP_GRID_RESOLUTION * CLIPMAP_GRID_RESOLUTION
CLIPMAP_INNER_GRID_RESOLUTION :: terrain.TERRAIN_RESOLUTION + 1
CLIPMAP_INNER_VERTEX_COUNT :: CLIPMAP_INNER_GRID_RESOLUTION * CLIPMAP_INNER_GRID_RESOLUTION
CLIPMAP_FULL_INDEX_COUNT :: (CLIPMAP_INNER_GRID_RESOLUTION - 1) * (CLIPMAP_INNER_GRID_RESOLUTION - 1) * 6
CLIPMAP_TRANSITION_WIDTH :: 4
CLIPMAP_MIN_VERTEX_SPACING_PIXELS :: f32(1)

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

// Runtime-only authoring controls. These deliberately live outside Fixture.
fog_debug_enabled := true
fog_debug_shells := true
fog_debug_density_multiplier := f32(1)

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
    candidates:               u32,
    frustum_culled:           u32,
    occlusion_culled:         u32,
    force_visible:            u32,
    empty:                    u32,
    emitted_draws:            u32,
    opaque_cost:              u32,
    foliage_cost:             u32,
    bougainvillea_cost:       u32,
    atlas_opaque_used:        u32,
    atlas_foliage_used:       u32,
    atlas_bougainvillea_used: u32,
    atlas_fragmentation:      f32,
}

Structure_Visibility_Order :: struct {
    index:            int,
    distance_squared: f32,
}

OVERLAY_CHUNK_CELLS :: 16
OVERLAY_CHUNKS_PER_AXIS :: (terrain.RING_RESOLUTION - 2) / OVERLAY_CHUNK_CELLS + 1

Overlay_Chunk_Bounds :: struct {
    center: third_person.Vec3,
    radius: f32,
}

GROUND_GRASS_SPACING :: f32(.46)
GROUND_GRASS_CHUNK_CELLS :: 16
GROUND_GRASS_CHUNK_WORLD_SIZE :: GROUND_GRASS_SPACING * f32(GROUND_GRASS_CHUNK_CELLS)
GROUND_GRASS_CACHE_BUDGET_BYTES :: 8 * 1024 * 1024

Ground_Grass_Cached_Instance :: struct {
    grass:        Grass_Instance,
    ground_color: [4]f32,
    density_roll: f32,
    flower_y:     f32,
    flower_size:  [2]f32,
    flower_tile:  u32,
    has_flower:   bool,
}

Ground_Grass_Chunk :: struct {
    entries:        [GROUND_GRASS_CHUNK_CELLS * GROUND_GRASS_CHUNK_CELLS]Ground_Grass_Cached_Instance,
    count:          int,
    built_cells:    int,
    last_used:      u64,
    stream_emitted: bool,
}

@(no_instrumentation)
structure_visibility_order_less :: #force_inline proc(a, b: Structure_Visibility_Order) -> bool {
    if a.distance_squared != b.distance_squared do return a.distance_squared < b.distance_squared
    return a.index < b.index
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
    return max(radius, f32(0)) * 2 * max(camera.focal_length, f32(.01)) * max(viewport_height, f32(1)) * .5 / depth
}

// Conservative sphere/frustum test in the same camera basis and projection
// convention used by the world shaders. A sphere intersecting any plane stays
// visible; this deliberately prefers extra work over a visible false reject.
@(no_instrumentation)
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
    center := third_person.Vec3{structure.center_x, structure.base_y + structure.height * .5, structure.center_z}
    radius :=
        f32(
            math.sqrt(
                f64(
                    structure.width * structure.width +
                    structure.depth * structure.depth +
                    structure.height * structure.height,
                ),
            ),
        ) *
        .5
    return center, radius
}

structure_lod_select :: proc(
    projected_diameter: f32,
    previous: Structure_LOD,
    force_near := false,
) -> Structure_LOD_Result {
    if structure_lod_forced >= 0 {
        return {tier = Structure_LOD(structure_lod_forced), projected_diameter = projected_diameter, transition = 1}
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
    center := third_person.Vec3{structure.center_x, structure.base_y + structure.height * .5, structure.center_z}
    radius :=
        f32(
            math.sqrt(
                f64(
                    structure.width * structure.width +
                    structure.depth * structure.depth +
                    structure.height * structure.height,
                ),
            ),
        ) *
        .5
    near_plane := editor.in_map && driving_aircraft(editor) ? WORLD_FLIGHT_NEAR_CLIP : WORLD_PLAY_NEAR_CLIP
    diameter := structure_lod_projected_diameter(camera, center, radius, f32(canvas2d.GetScreenHeight()), near_plane)
    return structure_lod_select(diameter, previous, force_near)
}

foliage_aerial_view_select :: #force_inline proc(
    camera_clearance, structure_height: f32,
    previous, flying: bool,
) -> bool {
    // Aircraft reach the aerial treatment earlier, but a parked or
    // canopy-height aircraft still needs the full ground silhouette,
    // understory, and outline cards. Clearance—not control mode—remains the
    // authority in both cases.
    threshold := max(f32(110), structure_height * 1.35)
    if flying do threshold = max(f32(55), structure_height * .75)
    // Enter above the authored threshold and remain aerial until the camera
    // descends well below it. This keeps cached young groves from alternating
    // between shrub and woodland topology when a flight camera, editor orbit,
    // or terrain sample hovers near one exact height.
    enter_threshold := threshold * 1.10
    exit_threshold := threshold * .90
    return previous ? camera_clearance > exit_threshold : camera_clearance > enter_threshold
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
            position     = {0, 0, 0},
            forward      = {0, 0, -1},
            right        = {1, 0, 0},
            up           = {0, 1, 0},
            focal_length = 1,
        }
        diameter := structure_lod_projected_diameter(camera, {0, 0, -10}, 1, 1000, .2)
        testing.expect(t, math.abs(diameter - 100) < .001)
        camera.focal_length = 2
        testing.expect(t, math.abs(structure_lod_projected_diameter(camera, {0, 0, -10}, 1, 1000, .2) - 200) < .001)
        testing.expect(t, structure_lod_projected_diameter(camera, {0, 0, -.5}, 1, 1000, .2) >= 1e8)
    }

    @(test)
    foliage_aerial_view_uses_hysteresis_and_flight_override :: proc(t: ^testing.T) {
        // A 60 m formation uses the fixed 110 m minimum: enter at 121 m and
        // leave below 99 m, with the band preserving the previous state.
        testing.expect(t, !foliage_aerial_view_select(115, 60, false, false))
        testing.expect(t, foliage_aerial_view_select(122, 60, false, false))
        testing.expect(t, foliage_aerial_view_select(105, 60, true, false))
        testing.expect(t, !foliage_aerial_view_select(98, 60, true, false))
        testing.expect(t, !foliage_aerial_view_select(0, 60, false, true))
        testing.expect(t, !foliage_aerial_view_select(60, 60, false, true))
        testing.expect(t, foliage_aerial_view_select(61, 60, false, true))
        testing.expect(t, foliage_aerial_view_select(52, 60, true, true))
        testing.expect(t, !foliage_aerial_view_select(49, 60, true, true))

        // Taller formations scale the band from their own height.
        testing.expect(t, !foliage_aerial_view_select(148, 100, false, false))
        testing.expect(t, foliage_aerial_view_select(149, 100, false, false))
        testing.expect(t, foliage_aerial_view_select(122, 100, true, false))
        testing.expect(t, !foliage_aerial_view_select(121, 100, true, false))
    }

    @(test)
    roof_surface_height_is_symmetric_and_reaches_eaves :: proc(t: ^testing.T) {
        eave_y, rise, half_width := f32(12), f32(6), f32(10)
        testing.expect(t, math.abs(world_roof_surface_y(eave_y, rise, half_width, 0) - 18) < .0001)
        testing.expect(t, math.abs(world_roof_surface_y(eave_y, rise, half_width, -4) - 15.6) < .0001)
        testing.expect(t, math.abs(world_roof_surface_y(eave_y, rise, half_width, 4) - 15.6) < .0001)
        testing.expect(t, math.abs(world_roof_surface_y(eave_y, rise, half_width, -10) - 12) < .0001)
        testing.expect(t, math.abs(world_roof_surface_y(eave_y, rise, half_width, 10) - 12) < .0001)
        testing.expect(t, math.abs(world_roof_surface_y(eave_y, rise, half_width, 40) - 12) < .0001)
        testing.expect_value(t, world_roof_surface_y(eave_y, rise, 0, 3), eave_y)
    }

    @(test)
    roof_frame_runs_ridge_along_longest_footprint_axis :: proc(t: ^testing.T) {
        width, depth, rotation := world_roof_long_axis_frame(18, 8, f32(.25))
        testing.expect_value(t, width, f32(8))
        testing.expect_value(t, depth, f32(18))
        testing.expect(t, math.abs(rotation - (f32(.25) + math.PI * .5)) < .0001)

        width, depth, rotation = world_roof_long_axis_frame(8, 18, f32(.25))
        testing.expect_value(t, width, f32(8))
        testing.expect_value(t, depth, f32(18))
        testing.expect_value(t, rotation, f32(.25))
    }

    @(test)
    gable_attic_opening_plan_preserves_rake_clearance :: proc(t: ^testing.T) {
        gable_kinds := [2]bool{false, true}
        for width_index in 6 ..= 48 {
            building_width := f32(width_index)
            for low_gable in gable_kinds {
                opening_width, opening_height, rise, center_fraction, valid := world_gable_attic_opening_plan(
                    building_width,
                    low_gable,
                )
                if !valid do continue
                frame_margin := f32(.18)
                top_fraction := center_fraction + (opening_height * .5 + frame_margin) / rise
                available_width := building_width * (1 - top_fraction) * .72
                testing.expect(t, opening_width + frame_margin * 2 <= available_width + .0001)
                testing.expect(t, top_fraction < 1)
                testing.expect(t, opening_width >= .80)
                testing.expect(t, opening_height >= .65)
            }
        }
    }

    @(test)
    static_frustum_is_conservative_at_planes_and_rejects_clear_misses :: proc(t: ^testing.T) {
        camera := Perspective_Camera {
            position     = {},
            forward      = {0, 0, -1},
            right        = {1, 0, 0},
            up           = {0, 1, 0},
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

    @(test)
    papi_signal_card_preserves_long_range_angular_size :: proc(t: ^testing.T) {
        testing.expect_value(t, papi_signal_card_size(120), f32(.46))
        testing.expect_value(t, papi_signal_card_size(300), f32(.60))
        testing.expect_value(t, papi_signal_card_size(500), f32(1))
        testing.expect_value(t, papi_signal_card_size(1000), PAPI_SIGNAL_CARD_MAX_SIZE)
    }
}
