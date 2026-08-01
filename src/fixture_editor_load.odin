package main

import engine_sound "../packages/engine_sound"
import farmland "../packages/farmland"
import flight "../packages/flight"
import game_input "../packages/game_input"
import story "../packages/story"
import surface_weather "../packages/surface_weather"
import tarot "../packages/tarot"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "core:math"
import "core:mem"
import canvas2d "zelda_engine:canvas2d"

Fixture_Editor_Load_Error_Kind :: enum {
    None,
    Invalid_Argument,
    Decode,
    Invalid_State,
    Lifecycle,
    Out_Of_Memory,
    Runtime_Stage,
}

Fixture_Editor_Load_Error :: struct {
    kind:      Fixture_Editor_Load_Error_Kind,
    path:      string,
    codec:     Fixture_Codec_Error,
    lifecycle: Fixture_Lifecycle_Error,
}

fixture_editor_load_error_dispose :: proc(error: ^Fixture_Editor_Load_Error) {
    if error == nil do return
    fixture_codec_error_dispose(&error.codec)
    error^ = {}
}

fixture_editor_count_valid :: #force_inline proc(count, capacity: int) -> bool {
    return count >= 0 && count <= capacity
}

fixture_editor_scalar_finite :: #force_inline proc(value: f32) -> bool {
    return value == value && !math.is_inf_f32(value)
}

fixture_editor_vec2_finite :: #force_inline proc(value: [2]f32) -> bool {
    return fixture_editor_scalar_finite(value.x) && fixture_editor_scalar_finite(value.y)
}

fixture_editor_vec3_finite :: #force_inline proc(value: [3]f32) -> bool {
    return(
        fixture_editor_scalar_finite(value.x) &&
        fixture_editor_scalar_finite(value.y) &&
        fixture_editor_scalar_finite(value.z) \
    )
}

fixture_editor_orientation_valid :: #force_inline proc(value: quaternion128) -> bool {
    if !fixture_editor_scalar_finite(value.x) ||
       !fixture_editor_scalar_finite(value.y) ||
       !fixture_editor_scalar_finite(value.z) ||
       !fixture_editor_scalar_finite(value.w) {
        return false
    }
    length_squared := value.x * value.x + value.y * value.y + value.z * value.z + value.w * value.w
    return fixture_editor_scalar_finite(length_squared) && length_squared > 1e-8
}

fixture_editor_body_state_valid :: #force_inline proc(body: flight.Body_State) -> bool {
    return(
        fixture_editor_vec3_finite(body.position) &&
        fixture_editor_vec3_finite(body.velocity) &&
        fixture_editor_vec3_finite(body.angular_velocity_world) &&
        fixture_editor_orientation_valid(body.orientation) \
    )
}

fixture_editor_basis_finite :: #force_inline proc(basis: flight.Basis) -> bool {
    return(
        fixture_editor_vec3_finite(basis.forward) &&
        fixture_editor_vec3_finite(basis.up) &&
        fixture_editor_vec3_finite(basis.right) \
    )
}

fixture_editor_load_preflight :: proc(fixture: ^Fixture) -> string {
    if fixture == nil do return "fixture"
    if fixture.active_lab_scene != "" do return "active_lab_scene"
    if !fixture_editor_count_valid(fixture.note_count, len(fixture.notes)) do return "note_count"
    for &note in fixture.notes[:fixture.note_count] {
        if !fixture_editor_vec3_finite(note.fallback_position) do return "notes.fallback_position"
        terminated := false
        for byte in note.text {
            if byte == 0 {
                terminated = true
                break
            }
        }
        if !terminated do return "notes.text"
    }
    if !fixture_editor_count_valid(fixture.project.structure_count, len(fixture.project.structures)) {
        return "project.structure_count"
    }
    if fixture.structure_selected < -1 || fixture.structure_selected >= fixture.project.structure_count {
        return "structure_selected"
    }
    if fixture.structure_scatter_count < 2 || fixture.structure_scatter_count > 8 {
        return "structure_scatter_count"
    }
    if !fixture_editor_count_valid(fixture.curve_point_count, len(fixture.curve_points)) {
        return "curve_point_count"
    }
    if !fixture_editor_scalar_finite(fixture.project.sea_level) do return "project.sea_level"
    for &level in fixture.project.levels {
        if !fixture_editor_scalar_finite(level.cell_size) || level.cell_size <= 0 {
            return "project.levels.cell_size"
        }
        if !fixture_editor_scalar_finite(level.origin_x) || !fixture_editor_scalar_finite(level.origin_z) {
            return "project.levels.origin"
        }
        for height in level.heights {
            if !fixture_editor_scalar_finite(height) do return "project.levels.heights"
        }
    }
    for &structure in fixture.project.structures[:fixture.project.structure_count] {
        values := [?]f32 {
            structure.center_x,
            structure.center_z,
            structure.width,
            structure.depth,
            structure.base_y,
            structure.height,
            structure.rotation,
        }
        for value in values {
            if !fixture_editor_scalar_finite(value) do return "project.structures"
        }
        if structure.width < 0 || structure.depth < 0 || structure.height < 0 {
            return "project.structures.dimensions"
        }
    }
    graph := &fixture.project.road_graph
    if !fixture_editor_count_valid(graph.node_count, len(graph.nodes)) {
        return "project.road_graph.node_count"
    }
    if !fixture_editor_count_valid(graph.edge_count, len(graph.edges)) {
        return "project.road_graph.edge_count"
    }
    if fixture.road_selected_node < -1 || fixture.road_selected_node >= graph.node_count {
        return "road_selected_node"
    }
    for &node in graph.nodes[:graph.node_count] {
        if !fixture_editor_vec3_finite(node.position) ||
           !fixture_editor_vec3_finite(node.up) ||
           !fixture_editor_scalar_finite(node.junction_radius) ||
           node.junction_radius < 0 {
            return "project.road_graph.nodes"
        }
    }
    for &edge in graph.edges[:graph.edge_count] {
        if edge.from < 0 || edge.from >= graph.node_count || edge.to < 0 || edge.to >= graph.node_count {
            return "project.road_graph.edges.endpoint"
        }
        if !fixture_editor_vec3_finite(edge.control_from) ||
           !fixture_editor_vec3_finite(edge.control_to) ||
           !fixture_editor_scalar_finite(edge.half_width) ||
           !fixture_editor_scalar_finite(edge.shoulder_width) ||
           edge.half_width < 0 ||
           edge.shoulder_width < 0 {
            return "project.road_graph.edges"
        }
    }
    if !fixture_editor_vec3_finite(fixture.player.position) || !fixture_editor_vec3_finite(fixture.player.velocity) {
        return "player"
    }
    if !fixture_editor_vec3_finite(fixture.car.position) || !fixture_editor_scalar_finite(fixture.car.yaw_radians) {
        return "car"
    }

    city := &fixture.architecture_city_plan
    if !fixture_editor_count_valid(city.count, len(city.structures)) {
        return "architecture_city_plan.count"
    }
    if !fixture_editor_count_valid(city.parcel_count, len(city.parcels)) {
        return "architecture_city_plan.parcel_count"
    }
    if !fixture_editor_count_valid(city.alley_count, len(city.alleys)) {
        return "architecture_city_plan.alley_count"
    }
    if !fixture_editor_count_valid(city.lamp_count, len(city.lamps)) {
        return "architecture_city_plan.lamp_count"
    }

    if !fixture_editor_count_valid(fixture.aircraft.count, len(fixture.aircraft.slots)) {
        return "aircraft.count"
    }
    if !fixture_editor_body_state_valid(fixture.postale.body) do return "postale.body"
    if !fixture_editor_vec3_finite(fixture.postale.spawn_position) ||
       !fixture_editor_orientation_valid(fixture.postale.spawn_orientation) {
        return "postale.spawn"
    }
    if !flight.ace_tuning_is_valid(fixture.postale.ace_tuning) do return "postale.ace_tuning"
    if !fixture_editor_body_state_valid(fixture.libellula.body) do return "libellula.body"
    if !fixture_editor_vec3_finite(fixture.libellula.spawn_position) ||
       !fixture_editor_orientation_valid(fixture.libellula.spawn_orientation) {
        return "libellula.spawn"
    }
    if !fixture_editor_body_state_valid(fixture.rondine.body) do return "rondine.body"
    if !fixture_editor_vec3_finite(fixture.rondine.spawn_position) ||
       !fixture_editor_basis_finite(fixture.rondine.spawn_basis) {
        return "rondine.spawn"
    }
    if !fixture_editor_count_valid(fixture.boat_traffic.count, len(fixture.boat_traffic.agents)) {
        return "boat_traffic.count"
    }
    for &agent, index in fixture.boat_traffic.agents[:fixture.boat_traffic.count] {
        if !fixture_editor_vec2_finite(agent.position) ||
           !fixture_editor_vec2_finite(agent.velocity) ||
           !fixture_editor_scalar_finite(agent.yaw) ||
           !fixture_editor_scalar_finite(agent.speed) ||
           !fixture_editor_scalar_finite(agent.throttle) {
            return index == 0 ? "boat_traffic.agents[0]" : "boat_traffic.agents"
        }
        if !fixture_editor_count_valid(agent.route_count, len(agent.route)) {
            return index == 0 ? "boat_traffic.agents[0].route_count" : "boat_traffic.agents.route_count"
        }
        if !fixture_editor_count_valid(agent.schedule_count, len(agent.schedule)) {
            return index == 0 ? "boat_traffic.agents[0].schedule_count" : "boat_traffic.agents.schedule_count"
        }
        if !fixture_editor_count_valid(agent.wake_count, len(agent.wake)) {
            return index == 0 ? "boat_traffic.agents[0].wake_count" : "boat_traffic.agents.wake_count"
        }
        if agent.route_count > 0 && (agent.route_index < 0 || agent.route_index >= agent.route_count) {
            return index == 0 ? "boat_traffic.agents[0].route_index" : "boat_traffic.agents.route_index"
        }
        for route in agent.route[:agent.route_count] {
            if !fixture_editor_vec2_finite(route) {
                return index == 0 ? "boat_traffic.agents[0].route" : "boat_traffic.agents.route"
            }
        }
    }
    if !fixture_editor_count_valid(fixture.rondine.wake_count, len(fixture.rondine.wake)) {
        return "rondine.wake_count"
    }
    if !fixture_editor_count_valid(fixture.farm_count, len(fixture.farms)) {
        return "farm_count"
    }
    for &farm in fixture.farms[:fixture.farm_count] {
        if !fixture_editor_count_valid(farm.plan.parcel_count, len(farm.plan.parcels)) {
            return "farms.plan.parcel_count"
        }
        if farm.plan.valid && !farmland.validate(&farm.plan) do return "farms.plan"
    }
    if !fixture_editor_count_valid(fixture.wreck_count, len(fixture.wrecks)) {
        return "wreck_count"
    }
    for &wreck in fixture.wrecks[:fixture.wreck_count] {
        if !fixture_editor_count_valid(wreck.part_count, len(wreck.parts)) {
            return "wrecks.part_count"
        }
    }
    if !fixture_editor_count_valid(fixture.greek_placement_count, len(fixture.greek_placements)) {
        return "greek_placement_count"
    }
    if fixture.authoring_tool == .GreekAssets &&
       (fixture.greek_asset_selected < 0 || fixture.greek_asset_selected >= GREEK_ASSET_CAPACITY) {
        return "greek_asset_selected"
    }
    for &placement in fixture.greek_placements[:fixture.greek_placement_count] {
        if placement.asset_index < 0 || placement.asset_index >= GREEK_ASSET_CAPACITY {
            return "greek_placements.asset_index"
        }
    }
    if fixture.marina_authored {
        plan := &fixture.marina_authored_plan
        if !fixture_editor_count_valid(plan.segment_count, len(plan.segments)) {
            return "marina_authored_plan.segment_count"
        }
        if !fixture_editor_count_valid(plan.slip_count, len(plan.slips)) {
            return "marina_authored_plan.slip_count"
        }
        if !fixture_editor_count_valid(plan.prop_count, len(plan.props)) {
            return "marina_authored_plan.prop_count"
        }
        if !fixture_editor_count_valid(plan.route.count, len(plan.route.points)) {
            return "marina_authored_plan.route.count"
        }
    }
    if !fixture_editor_count_valid(fixture.vehicle_effects.dust_count, len(fixture.vehicle_effects.dust)) {
        return "vehicle_effects.dust_count"
    }
    if !fixture_editor_count_valid(fixture.wing_trails.count, len(fixture.wing_trails.particles)) {
        return "wing_trails.count"
    }
    if !fixture_editor_count_valid(fixture.petal_effects.count, len(fixture.petal_effects.particles)) {
        return "petal_effects.count"
    }
    if fixture.vehicle_paint_color < 0 ||
       fixture.vehicle_paint_color >= len(VEHICLE_PAINT_COLORS) ||
       fixture.vehicle_paint_secondary_color < 0 ||
       fixture.vehicle_paint_secondary_color >= len(VEHICLE_PAINT_COLORS) ||
       fixture.vehicle_paint_pattern < 0 ||
       fixture.vehicle_paint_pattern >= len(VEHICLE_PAINT_PATTERN_NAMES) ||
       fixture.vehicle_paint_shape_kind < 0 ||
       fixture.vehicle_paint_shape_kind >= len(VEHICLE_PAINT_SHAPE_NAMES) ||
       fixture.vehicle_paint_component < 0 ||
       fixture.vehicle_paint_component >= len(VEHICLE_PAINT_COMPONENT_NAMES) {
        return "vehicle_paint_settings.index"
    }
    if fixture.vehicle_paint_pattern_size < 0 ||
       fixture.vehicle_paint_shape_size < 0 ||
       fixture.vehicle_paint_brush_radius < 0 ||
       !fixture_editor_scalar_finite(fixture.vehicle_paint_pattern_rotation) ||
       !fixture_editor_scalar_finite(fixture.vehicle_paint_shape_rotation) ||
       !fixture_editor_scalar_finite(fixture.vehicle_paint_brush_hardness) ||
       !fixture_editor_scalar_finite(fixture.vehicle_paint_brush_strength) ||
       fixture.vehicle_paint_brush_hardness < 0 ||
       fixture.vehicle_paint_brush_hardness > 1 ||
       fixture.vehicle_paint_brush_strength < 0 ||
       fixture.vehicle_paint_brush_strength > 1 {
        return "vehicle_paint_settings.value"
    }
    if fixture.story_state.tarot_layout.count != 0 && !tarot.valid(&fixture.story_state.tarot_layout) {
        return "story_state.tarot_layout"
    }

    settlement := &fixture.settlement_plan
    counts := [?]struct {
        count: int,
        cap:   int,
        path:  string,
    } {
        {settlement.brush_piece_count, len(settlement.brush_pieces), "settlement_plan.brush_piece_count"},
        {settlement.activity_point_count, len(settlement.activity_points), "settlement_plan.activity_point_count"},
        {settlement.inhabitant_count, len(settlement.inhabitants), "settlement_plan.inhabitant_count"},
        {settlement.neighborhood_count, len(settlement.neighborhoods), "settlement_plan.neighborhood_count"},
        {settlement.macro_cell_count, len(settlement.macro_cells), "settlement_plan.macro_cell_count"},
        {settlement.route_count, len(settlement.routes), "settlement_plan.route_count"},
        {settlement.block_count, len(settlement.blocks), "settlement_plan.block_count"},
        {settlement.site_count, len(settlement.sites), "settlement_plan.site_count"},
        {settlement.rejected_site_count, len(settlement.rejected_sites), "settlement_plan.rejected_site_count"},
        {
            settlement.decorative_foliage_count,
            len(settlement.decorative_foliage),
            "settlement_plan.decorative_foliage_count",
        },
        {settlement.terrain_edit_count, len(settlement.terrain_edits), "settlement_plan.terrain_edit_count"},
        {
            settlement.ordinary_purpose_count,
            len(settlement.ordinary_purposes),
            "settlement_plan.ordinary_purpose_count",
        },
    }
    for value in counts {
        if !fixture_editor_count_valid(value.count, value.cap) do return value.path
    }
    for &route in settlement.routes[:settlement.route_count] {
        if !fixture_editor_count_valid(route.geometry.count, len(route.geometry.points)) {
            return "settlement_plan.routes.geometry.count"
        }
    }
    for &block in settlement.blocks[:settlement.block_count] {
        if !fixture_editor_count_valid(block.corner_count, len(block.corners)) {
            return "settlement_plan.blocks.corner_count"
        }
    }
    return ""
}

fixture_editor_paint_history_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    allocator := context.allocator
    if editor.fixture_owner.arena != nil {
        allocator = editor.fixture_owner.arena_allocator
    }
    vehicle_paint_history_destroy(editor, allocator)
}

fixture_editor_next_terrain_revision :: proc(revision: u64) -> u64 {
    return revision == max(u64) ? 1 : revision + 1
}

fixture_editor_stage_destroy :: proc(stage: ^Editor, paint_allocator: mem.Allocator) {
    if stage == nil do return
    markov_marina_buoy_physics_destroy(stage)
    car_physics_destroy(stage)
    gameplay_physics_destroy(stage)
    vehicle_paint_history_destroy(stage, paint_allocator)
}

fixture_editor_reset_runtime :: proc(editor: ^Editor) {
    surface_weather.initialize(&editor.surface_weather, terrain.WORLD_SIZE_METERS * .5)
    editor.structure_placing = false
    editor.structure_moving = false
    editor.formation_brush_painting = false
    editor.architecture_painting = false
    editor.climbing_leaf_painting = false
    editor.curve_drawing = false
    editor.road_drag_edge = -1
    editor.road_drag_handle = -1
    editor.road_hover_edge = -1
    editor.road_hover_handle = -1
    editor.road_drag_handle_moved = false
    editor.crash_recovery_phase = .Inactive
    editor.crash_recovery_seconds = 0
    editor.cinematic_playback = {}
    editor.story_cinematic_restore_pose = {}
    editor.story_meeting_cinematic_pending = false
    editor.story_cinematic_active = false
    editor.flight_throttle_overlay_value = 0
    editor.flight_throttle_overlay_changed_at = 0
    editor.flight_throttle_overlay_fade_started_at = 0
    editor.flight_throttle_overlay_initialized = false
    editor.vehicle_paint_stroke_active = false
    editor.vehicle_paint_tool_drag_active = false
    editor.vehicle_paint_orbit_drag_active = false
    editor.vehicle_paint_brush_slider_active = -1
    editor.vehicle_paint_history_capturing = false
    editor.vehicle_paint_save_pending = false
    editor.vehicle_paint_save_due_at = 0
    editor.vehicle_paint_save_failed = false
    editor.vehicle_paint_clear_confirm_until = 0
    editor.vehicle_paint_sound_until = 0
    editor.vehicle_paint_settings_initialized = true
    editor.attendant_dialogue = {}
    editor.attendant_dialogue_open = false
    editor.attendant_dialogue_focus = 0
    editor.dialogue_session = {}
    editor.runtime_input = game_input.default_state()
    editor.controller_disconnect_notice = false
    editor.aircraft_fixed_accumulator = 0
    editor.aircraft_previous_body = {}
    editor.aircraft_previous_body_valid = false
    editor.car_physics_accumulator = 0
    editor.car_wheels = {}
    editor.car_impact_detector = {}
    editor.car_audio_damage = 0
    editor.car_audio_gearbox = {}
    editor.landing_wheel_squeal = 0
    editor.landing_wheel_speed = 0
    engine_sound.reset_runtime_preserving_io(&editor.engine_audio)
    story.init_catalog(&editor.story_catalog)
    story.init_quest_catalog(&editor.story_quest_catalog)
    _ = story.ensure_quest_progress(&editor.story_state)
    editor.circulation_plan = {}
    editor.circulation_revision = 0
    editor.circulation_plan_valid = false
    editor.circulation_structure_count = 0
    clear(&editor.circulation_structures)
    clear(&editor.libellula_projected_faces)
    if editor.libellula_visual_mesh.vertices != nil {
        vehicles.libellula_mesh_copy(&editor.libellula_visual_mesh, &editor.libellula_base_mesh)
    }
    if editor.libellula_mk2_visual_mesh.vertices != nil {
        vehicles.libellula_mesh_copy(&editor.libellula_mk2_visual_mesh, &editor.libellula_mk2_base_mesh)
    }
    if canvas2d.PersistentState() != nil {
        dither_apply(editor)
    } else {
        dither_reset(editor)
    }
    vehicle_paint_atlas_invalidate_all()
    world_renderer_fixture_invalidate(editor)
    editor.gameplay_physics.terrain_revision = editor.terrain_revision
    editor.car_physics_terrain_revision = editor.terrain_revision
}

fixture_editor_load :: proc(
    editor: ^Editor,
    data: []byte,
    alloc := context.allocator,
) -> (
    error: Fixture_Editor_Load_Error,
    ok: bool,
) {
    if editor == nil || len(data) == 0 || alloc.procedure == nil {
        return {kind = .Invalid_Argument}, false
    }

    candidate, codec_error, decoded := fixture_codec_decode(data, alloc)
    if !decoded {
        return {kind = .Decode, codec = codec_error}, false
    }
    candidate_owned := true
    defer if candidate_owned do fixture_migration_result_dispose(&candidate)

    if path := fixture_editor_load_preflight(candidate.fixture); path != "" {
        return {kind = .Invalid_State, path = path}, false
    }
    bind_plan: Fixture_Lifecycle_Bind_Plan
    if lifecycle_error := fixture_lifecycle_prepare(candidate.fixture, &bind_plan); lifecycle_error.kind != .None {
        return {kind = .Lifecycle, lifecycle = lifecycle_error}, false
    }

    stage_bytes, allocation_error := mem.alloc_bytes(size_of(Editor), align_of(Editor), alloc)
    if allocation_error != nil || stage_bytes == nil {
        return {kind = .Out_Of_Memory}, false
    }
    stage := cast(^Editor)raw_data(stage_bytes)
    stage^ = {}
    stage.fixture = candidate.fixture^
    stage.terrain_revision = fixture_editor_next_terrain_revision(editor.terrain_revision)
    stage_live := true
    defer {
        if stage_live do fixture_editor_stage_destroy(stage, alloc)
        _ = mem.free(rawptr(stage), alloc)
    }

    if !vehicle_paint_history_try_init(stage, alloc) {
        return {kind = .Out_Of_Memory}, false
    }
    if !gameplay_physics_create(stage) {
        return {kind = .Runtime_Stage, path = "gameplay_physics"}, false
    }
    car_physics_create(stage)
    if stage.car_physics_world == nil || stage.car_physics_vehicle == nil {
        return {kind = .Runtime_Stage, path = "car_physics"}, false
    }
    fixture_notes_before_fixture_replace(editor)
    old_owner := editor.fixture_owner
    if editor.active_lab_scene != "" {
        definition := lab_scene_find(editor.active_lab_scene)
        if definition != nil && definition.exit != nil do definition.exit(editor)
    }
    markov_marina_buoy_physics_destroy(editor)
    car_physics_destroy(editor)
    gameplay_physics_destroy(editor)
    attendant_dialogue_definition_release(editor)
    fixture_editor_paint_history_destroy(editor)
    fixture_storage_destroy(&editor.fixture)
    structure_history_storage_destroy(editor)

    editor.fixture = stage.fixture
    editor.fixture_owner = candidate
    editor.fixture_owner.fixture = &editor.fixture
    candidate = {}
    candidate_owned = false
    fixture_lifecycle_apply(&editor.fixture, &bind_plan)
    fixture_notes_after_fixture_replace()

    editor.gameplay_physics = stage.gameplay_physics
    editor.car_physics_world = stage.car_physics_world
    editor.car_physics_vehicle = stage.car_physics_vehicle
    editor.car_physics_terrain = stage.car_physics_terrain
    editor.car_physics_terrain_revision = stage.car_physics_terrain_revision
    stage.gameplay_physics = {}
    stage.car_physics_world = nil
    stage.car_physics_vehicle = nil
    stage.car_physics_terrain = {}
    stage.marina_buoys = {}
    stage.vehicle_paint_open_pixels = nil
    stage.vehicle_paint_tool_drag_texels = nil
    stage.vehicle_paint_tool_drag_mirror_texels = nil
    stage.vehicle_paint_undo = {}
    stage.vehicle_paint_redo = {}
    stage_live = false

    fixture_migration_result_dispose(&old_owner)
    fixture_editor_reset_runtime(editor)
    return {}, true
}
