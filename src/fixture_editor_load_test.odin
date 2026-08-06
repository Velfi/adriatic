package main

import architecture "../packages/architecture"
import fixture_file "../packages/fixture_file"
import fixture_v0001 "../packages/fixture_history/v0001"
import flight "../packages/flight"
import hs "zelda_engine:hs"
import terrain "../packages/terrain"
import vehicles "../packages/vehicles"
import "base:runtime"
import "core:math"
import "core:mem"
import "core:testing"
import sdl "vendor:sdl3"

when ODIN_TEST {
    Fixture_Editor_Test_Root_Snapshot :: struct {
        gameplay_options:        Gameplay_Options,
        control_hint_texture:    int,
        paint_icon_texture:      int,
        authoring_tool_texture:  int,
        sculpt_tool_texture:     int,
        tarot_texture:           int,
        postale_base_vertices:   int,
        libellula_base_vertices: int,
        audio_stream:            ^sdl.AudioStream,
        audio_userdata:          rawptr,
    }

    Fixture_Editor_Test_Live_Snapshot :: struct {
        authoring_tool:     Authoring_Tool,
        project_revision:   u64,
        project_structures: rawptr,
        owner_arena:        rawptr,
        gameplay_world:     rawptr,
        car_vehicle:        rawptr,
        paint_pixels:       rawptr,
        root:               Fixture_Editor_Test_Root_Snapshot,
    }

    fixture_editor_test_source :: proc() -> ^Fixture {
        source := new(Fixture)
        terrain.init_project(&source.project)
        source.project.revision = 707
        source.project.sea_level = 3
        append(
            &source.project.structures,
            terrain.Structure {
                id = 81,
                center_x = 4,
                center_z = -7,
                width = 5,
                depth = 6,
                base_y = 1,
                height = 4,
                kind = .Rock,
            },
        )
        source.project.structure_count = 1
        source.authoring_tool = .Marina
        source.sdf_obstacles[0] = {
            position     = {12, 8, -4},
            rotation     = flight.identity_orientation(),
            scale        = {1, 2, .5},
            major_radius = 7,
            tube_radius  = 1.5,
            color        = {210, 90, 30, 255},
        }
        source.sdf_obstacle_count = 1
        source.sdf_obstacle_selected = 0
        source.structure_selected = 0
        source.structure_scatter_count = 4
        source.road_selected_node = -1
        source.architecture_city_plan.lamps = make([dynamic]architecture.City_Lamp, 1)
        source.architecture_city_plan.lamps[0] = {
            x   = 23,
            z   = -41,
            yaw = .25,
        }
        source.architecture_city_plan.lamp_count = 1
        source.occupant = .Car
        source.pilot.mode = .Driving
        source.player.position = {0, 8, 0}
        source.car.position = {0, 8, 0}
        source.car.yaw_radians = .25
        source.aircraft.count = 4
        source.aircraft.active = .Postale
        kinds := [?]vehicles.Aircraft_Kind{.Postale, .Libellula, .Libellula_Mk2, .Rondine}
        for kind, index in kinds {
            source.aircraft.slots[index] = {
                kind      = kind,
                name      = "fixture-aircraft",
                available = true,
            }
        }
        identity := flight.identity_orientation()
        source.postale.body.orientation = identity
        source.postale.spawn_orientation = identity
        source.libellula.body.orientation = identity
        source.libellula.spawn_orientation = identity
        source.rondine.body.orientation = identity
        source.vehicle_paint_color = 0
        source.vehicle_paint_secondary_color = 13
        source.vehicle_paint_pattern = 0
        source.vehicle_paint_pattern_size = 32
        source.vehicle_paint_shape_kind = 0
        source.vehicle_paint_shape_size = 32
        source.vehicle_paint_component = 0
        source.vehicle_paint_brush_radius = 14
        source.vehicle_paint_brush_hardness = .75
        source.vehicle_paint_brush_strength = .75
        map_source, map_error, captured := fixture_map_source_capture_inline(source)
        map_artifact_error_dispose(&map_error)
        if !captured {
            fixture_storage_destroy(source)
            free(source)
            return nil
        }
        source.map_source = map_source
        return source
    }

    fixture_editor_test_source_destroy :: proc(source: ^Fixture) {
        if source == nil do return
        delete(source.map_source.inline_bytes)
        fixture_storage_destroy(source)
        free(source)
    }

    fixture_editor_test_current_container :: proc(t: ^testing.T) -> []byte {
        source := fixture_editor_test_source()
        defer fixture_editor_test_source_destroy(source)
        data, error, ok := fixture_codec_encode(source, context.allocator)
        testing.expect(t, ok && error.kind == .None)
        fixture_codec_error_dispose(&error)
        return data
    }

    fixture_editor_test_v1_container :: proc(t: ^testing.T) -> []byte {
        payload, payload_ok := fixture_migration_test_historical_payload(t)
        testing.expect(t, payload_ok)
        if !payload_ok do return nil
        defer delete(payload)

        historical := new(fixture_v0001.Fixture)
        defer fixture_codec_test_destroy_historical(historical)
        value := any {
            data = rawptr(historical),
            id   = typeid_of(fixture_v0001.Fixture),
        }
        decode_error, decoded := hs.portable_decode(
            value,
            payload,
            fixture_codec_historical_portable_config(),
            context.allocator,
        )
        testing.expect(t, decoded && decode_error.kind == .None)
        hs.portable_error_dispose(&decode_error)
        if !decoded do return nil

        delete(historical.active_lab_scene)
        historical.active_lab_scene = ""
        historical.structure_selected = 0
        historical.structure_scatter_count = 4
        historical.road_selected_node = -1
        historical.greek_asset_selected = 0
        historical.vehicle_paint_color = 0
        historical.vehicle_paint_secondary_color = 13
        historical.vehicle_paint_pattern = 0
        historical.vehicle_paint_pattern_size = 32
        historical.vehicle_paint_shape_kind = 0
        historical.vehicle_paint_shape_size = 32
        historical.vehicle_paint_component = 0
        historical.vehicle_paint_brush_radius = 14
        historical.vehicle_paint_brush_hardness = .75
        historical.vehicle_paint_brush_strength = .75
        historical.farms[0].plan.valid = false
        for &level, index in historical.project.levels {
            level.cell_size = terrain.FINE_CELL_SIZE * f32(u32(1) << u32(index))
            level.origin_x = -f32(terrain.RING_RESOLUTION / 2) * level.cell_size
            level.origin_z = level.origin_x
        }
        clean_payload, encode_error, encoded := hs.portable_encode(
            value,
            fixture_codec_historical_portable_config(),
            context.allocator,
        )
        testing.expect(t, encoded && encode_error.kind == .None)
        hs.portable_error_dispose(&encode_error)
        if !encoded do return nil
        defer delete(clean_payload)

        container, container_error, container_ok := fixture_file.fixture_container_encode(
            clean_payload,
            1,
            alloc = context.allocator,
        )
        testing.expect(t, container_ok && container_error.kind == .None)
        return container
    }

    fixture_editor_test_root_snapshot :: proc(editor: ^Editor) -> Fixture_Editor_Test_Root_Snapshot {
        return {
            gameplay_options = editor.gameplay_options,
            control_hint_texture = editor.control_hint_atlases.keyboard_mouse.id,
            paint_icon_texture = editor.vehicle_paint_tool_icons.id,
            authoring_tool_texture = editor.authoring_tool_atlas.id,
            sculpt_tool_texture = editor.sculpt_tool_atlas.id,
            tarot_texture = editor.tarot_atlas.id,
            postale_base_vertices = editor.postale_base_mesh.vertex_count,
            libellula_base_vertices = editor.libellula_base_mesh.vertex_count,
            audio_stream = editor.engine_audio.stream,
            audio_userdata = editor.engine_audio.aux_userdata,
        }
    }

    fixture_editor_test_root_equal :: proc(editor: ^Editor, snapshot: Fixture_Editor_Test_Root_Snapshot) -> bool {
        return(
            editor.gameplay_options == snapshot.gameplay_options &&
            editor.control_hint_atlases.keyboard_mouse.id == snapshot.control_hint_texture &&
            editor.vehicle_paint_tool_icons.id == snapshot.paint_icon_texture &&
            editor.authoring_tool_atlas.id == snapshot.authoring_tool_texture &&
            editor.sculpt_tool_atlas.id == snapshot.sculpt_tool_texture &&
            editor.tarot_atlas.id == snapshot.tarot_texture &&
            editor.postale_base_mesh.vertex_count == snapshot.postale_base_vertices &&
            editor.libellula_base_mesh.vertex_count == snapshot.libellula_base_vertices &&
            editor.engine_audio.stream == snapshot.audio_stream &&
            editor.engine_audio.aux_userdata == snapshot.audio_userdata \
        )
    }

    fixture_editor_test_editor :: proc(t: ^testing.T) -> ^Editor {
        editor := new(Editor)
        terrain.init_project(&editor.project)
        editor.authoring_tool = .Farm
        editor.terrain_revision = 707
        editor.gameplay_options = gameplay_options_default()
        editor.gameplay_options.look_sensitivity = .031
        editor.control_hint_atlases.keyboard_mouse.id = 0x111
        editor.vehicle_paint_tool_icons.id = 0x222
        editor.authoring_tool_atlas.id = 0x2aa
        editor.sculpt_tool_atlas.id = 0x2bb
        editor.tarot_atlas.id = 0x333
        editor.postale_base_mesh = new(vehicles.Aircraft_Mesh)
        editor.car_base_mesh = new(vehicles.Aircraft_Mesh)
        editor.postale_base_mesh.vertex_count = 41
        editor.libellula_base_mesh.vertex_count = 43
        editor.engine_audio.stream = cast(^sdl.AudioStream)uintptr(0x1234)
        editor.engine_audio.aux_userdata = cast(rawptr)uintptr(0x5678)
        editor.engine_audio.mute_gain = .25
        editor.aircraft_fixed_accumulator = 4
        editor.controller_disconnect_notice = true
        testing.expect(t, vehicle_paint_storage_ensure(editor))
        testing.expect(t, vehicle_paint_history_try_init(editor))
        testing.expect(t, gameplay_physics_create(editor))
        car_physics_create(editor)
        testing.expect(t, editor.car_physics_vehicle != nil)
        return editor
    }

    fixture_editor_test_destroy :: proc(editor: ^Editor) {
        if editor == nil do return
        markov_marina_buoy_physics_destroy(editor)
        car_physics_destroy(editor)
        gameplay_physics_destroy(editor)
        attendant_dialogue_definition_release(editor)
        fixture_editor_paint_history_destroy(editor)
        vehicle_paint_storage_destroy(editor)
        fixture_storage_destroy(&editor.fixture)
        structure_history_storage_destroy(editor)
        fixture_migration_result_dispose(&editor.fixture_owner)
        free(editor.postale_base_mesh)
        free(editor.car_base_mesh)
        free(editor)
    }

    fixture_editor_test_live_snapshot :: proc(editor: ^Editor) -> Fixture_Editor_Test_Live_Snapshot {
        return {
            authoring_tool = editor.authoring_tool,
            project_revision = editor.project.revision,
            project_structures = raw_data(editor.project.structures),
            owner_arena = rawptr(editor.fixture_owner.arena),
            gameplay_world = rawptr(editor.gameplay_physics.world),
            car_vehicle = rawptr(editor.car_physics_vehicle),
            paint_pixels = raw_data(editor.vehicle_paint_open_pixels),
            root = fixture_editor_test_root_snapshot(editor),
        }
    }

    fixture_editor_test_live_equal :: proc(editor: ^Editor, snapshot: Fixture_Editor_Test_Live_Snapshot) -> bool {
        return(
            editor.authoring_tool == snapshot.authoring_tool &&
            editor.project.revision == snapshot.project_revision &&
            raw_data(editor.project.structures) == snapshot.project_structures &&
            rawptr(editor.fixture_owner.arena) == snapshot.owner_arena &&
            rawptr(editor.gameplay_physics.world) == snapshot.gameplay_world &&
            rawptr(editor.car_physics_vehicle) == snapshot.car_vehicle &&
            raw_data(editor.vehicle_paint_open_pixels) == snapshot.paint_pixels &&
            fixture_editor_test_root_equal(editor, snapshot.root) \
        )
    }

    fixture_editor_test_expect_failure :: proc(
        t: ^testing.T,
        editor: ^Editor,
        data: []byte,
        allocator: mem.Allocator,
        snapshot: Fixture_Editor_Test_Live_Snapshot,
    ) {
        input_snapshot := fixture_codec_test_copy(data)
        defer delete(input_snapshot)
        error, ok := fixture_editor_load(editor, data, allocator)
        testing.expect(t, !ok)
        testing.expect(t, fixture_editor_test_live_equal(editor, snapshot))
        testing.expect(t, fixture_codec_test_bytes_equal(data, input_snapshot))
        fixture_editor_load_error_dispose(&error)
        fixture_editor_load_error_dispose(&error)
    }

    @(test)
    fixture_editor_load_v0018_applies_inline_map_without_leaking :: proc(t: ^testing.T) {
        payload := fixture_migration_v0018_to_v0019_payload(t, 0xa5)
        testing.expect(t, payload != nil)
        if payload == nil do return
        defer delete(payload)
        data, container_error, encoded := fixture_file.fixture_container_encode(payload, 18)
        testing.expect(t, encoded && container_error.kind == .None)
        if !encoded do return
        defer delete(data)

        editor := fixture_editor_test_editor(t)
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        error, loaded := fixture_editor_load(editor, data, fixture_migration_test_allocator(&state))
        testing.expect(t, loaded && error.kind == .None)
        fixture_editor_load_error_dispose(&error)
        if loaded {
            testing.expect(
                t,
                editor.project.structure_count == 1 &&
                editor.project.structures[0].id == 0x300 &&
                editor.default_map_regeneration_seeds[0] == 0x10203040 &&
                editor.marina_authored,
            )
        }
        fixture_editor_test_destroy(editor)
        testing.expect(t, state.outstanding == 0)
    }

    @(test)
    fixture_editor_load_current_rebuilds_runtime_and_releases_replaced_state :: proc(t: ^testing.T) {
        data := fixture_editor_test_current_container(t)
        testing.expect(t, data != nil)
        if data == nil do return
        defer delete(data)
        input_snapshot := fixture_codec_test_copy(data)
        defer delete(input_snapshot)

        editor := fixture_editor_test_editor(t)
        defer fixture_editor_test_destroy(editor)
        editor.vehicle_paint_layers[0][0] = 0x5c
        editor.structure_undo[0] = new(Structure_History_State)
        editor.structure_undo[0].structures = make([dynamic]terrain.Structure, 1)
        editor.structure_undo_count = 1
        editor.structure_redo[0] = new(Structure_History_State)
        editor.structure_redo[0].structures = make([dynamic]terrain.Structure, 1)
        editor.structure_redo_count = 1
        root_snapshot := fixture_editor_test_root_snapshot(editor)
        old_terrain_revision := editor.terrain_revision
        clipmap_snapshot := world_renderer.clipmap_dirty
        paint_snapshot := world_renderer.vehicle_paint_dirty_layers
        road_valid_snapshot := world_renderer.road_graph_valid
        road_geometry_snapshot := world_renderer.road_geometry_valid
        defer {
            world_renderer.clipmap_dirty = clipmap_snapshot
            world_renderer.vehicle_paint_dirty_layers = paint_snapshot
            world_renderer.road_graph_valid = road_valid_snapshot
            world_renderer.road_geometry_valid = road_geometry_snapshot
        }
        world_renderer.clipmap_dirty = {}
        world_renderer.vehicle_paint_dirty_layers = {}
        world_renderer.road_graph_valid = true
        world_renderer.road_revision = 707
        world_renderer.road_geometry_valid = true
        world_renderer.road_geometry_revision = 707
        world_renderer.road_geometry_terrain_revision = old_terrain_revision

        error, ok := fixture_editor_load(editor, data, context.allocator)
        testing.expect(t, ok && error.kind == .None)
        fixture_editor_load_error_dispose(&error)
        if !ok do return

        testing.expect(t, editor.fixture_owner.fixture == &editor.fixture)
        testing.expect(t, editor.fixture_owner.arena != nil)
        testing.expect(t, editor.project.revision == 707)
        testing.expect(t, editor.authoring_tool == .Marina)
        testing.expect(t, editor.sdf_obstacle_count == 1)
        testing.expect(t, editor.sdf_obstacle_selected == 0)
        testing.expect(t, editor.sdf_obstacles[0].position == flight.Vec3{12, 8, -4})
        testing.expect(t, editor.sdf_obstacle_interaction.hovered == -1)
        testing.expect(t, editor.architecture_city_plan.lamp_count == 1)
        testing.expect(t, editor.architecture_city_plan.lamps[0].x == 23)
        testing.expect(t, editor.vehicle_paint_layers[0][0] == 0x5c)
        testing.expect(t, fixture_lifecycle_test_bound(&editor.fixture, .Car))
        testing.expect(t, fixture_editor_test_root_equal(editor, root_snapshot))
        testing.expect(t, editor.engine_audio.mute_gain == 1)
        testing.expect(t, editor.aircraft_fixed_accumulator == 0)
        testing.expect(t, !editor.controller_disconnect_notice)
        testing.expect(t, editor.gameplay_physics.world != nil)
        testing.expect(t, editor.car_physics_world == editor.gameplay_physics.world)
        testing.expect(t, editor.car_physics_vehicle != nil)
        testing.expect(t, editor.terrain_revision != old_terrain_revision)
        testing.expect(t, !world_renderer.road_graph_valid)
        testing.expect(t, !world_renderer.road_geometry_valid)
        testing.expect(t, editor.structure_undo_count == 0 && editor.structure_redo_count == 0)
        testing.expect(t, editor.structure_undo[0] == nil)
        testing.expect(t, editor.structure_redo[0] == nil)
        structure_history_push_undo(editor)
        structure_history_push_redo(editor)
        testing.expect(t, editor.structure_undo_count == 1 && editor.structure_redo_count == 1)
        testing.expect(t, raw_data(editor.structure_undo[0].structures) != nil)
        testing.expect(t, raw_data(editor.structure_redo[0].structures) != nil)
        for dirty in world_renderer.clipmap_dirty {
            testing.expect(t, dirty.valid && dirty.full_rebuild && dirty.revision == editor.terrain_revision)
        }
        for dirty in world_renderer.vehicle_paint_dirty_layers do testing.expect(t, dirty)

        lamp_count := len(editor.architecture_city_plan.lamps)
        append(&editor.architecture_city_plan.lamps, architecture.City_Lamp{x = 91})
        testing.expect(t, len(editor.architecture_city_plan.lamps) == lamp_count + 1)
        replacement := make(
            [dynamic]architecture.City_Lamp,
            len(editor.architecture_city_plan.lamps),
            len(editor.architecture_city_plan.lamps) + 4,
        )
        copy(replacement[:], editor.architecture_city_plan.lamps[:])
        editor.architecture_city_plan.lamps = replacement

        second_error, second_ok := fixture_editor_load(editor, data, context.allocator)
        testing.expect(t, second_ok && second_error.kind == .None)
        fixture_editor_load_error_dispose(&second_error)
        testing.expect(t, fixture_lifecycle_test_bound(&editor.fixture, .Car))
        testing.expect(t, fixture_editor_test_root_equal(editor, root_snapshot))
        testing.expect(t, editor.structure_undo[0] == nil)
        testing.expect(t, editor.structure_redo[0] == nil)
        structure_history_push_undo(editor)
        structure_history_push_redo(editor)
        for _ in 0 ..< 3 {
            gameplay_physics_begin_frame(editor)
            car_physics_step(editor, .15, .02, false, vehicles.CAR_DRIVE_DEFAULT_SURFACE, 1.0 / 60.0, 0)
        }
        testing.expect(t, editor.gameplay_physics.world != nil && editor.car_physics_vehicle != nil)
        testing.expect(t, fixture_codec_test_bytes_equal(data, input_snapshot))
    }

    @(test)
    fixture_editor_load_golden_v1_migrates_and_binds_destination :: proc(t: ^testing.T) {
        data := fixture_editor_test_v1_container(t)
        testing.expect(t, data != nil)
        if data == nil do return
        defer delete(data)
        input_snapshot := fixture_codec_test_copy(data)
        defer delete(input_snapshot)

        editor := fixture_editor_test_editor(t)
        defer fixture_editor_test_destroy(editor)
        root_snapshot := fixture_editor_test_root_snapshot(editor)
        error, ok := fixture_editor_load(editor, data, context.allocator)
        testing.expect(t, ok && error.kind == .None)
        fixture_editor_load_error_dispose(&error)
        if !ok do return

        testing.expect(t, editor.fixture_owner.fixture == &editor.fixture)
        testing.expect(t, editor.fixture_owner.arena != nil)
        testing.expect(t, editor.project.structures[0].id == 0x1111)
        testing.expect(t, editor.active_lab_scene == "")
        testing.expect(t, fixture_lifecycle_test_bound(&editor.fixture, .On_Foot))
        testing.expect(t, fixture_editor_test_root_equal(editor, root_snapshot))
        testing.expect(t, editor.gameplay_physics.world != nil && editor.car_physics_vehicle != nil)
        testing.expect(t, fixture_codec_test_bytes_equal(data, input_snapshot))
    }

    @(test)
    fixture_editor_load_failures_are_atomic_and_release_every_allocation :: proc(t: ^testing.T) {
        valid := fixture_editor_test_current_container(t)
        testing.expect(t, valid != nil)
        if valid == nil do return
        defer delete(valid)
        valid_snapshot := fixture_codec_test_copy(valid)
        defer delete(valid_snapshot)

        editor := fixture_editor_test_editor(t)
        defer fixture_editor_test_destroy(editor)
        live_snapshot := fixture_editor_test_live_snapshot(editor)

        nil_error, nil_ok := fixture_editor_load(editor, valid, {})
        testing.expect(t, !nil_ok && nil_error.kind == .Invalid_Argument)
        testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
        fixture_editor_load_error_dispose(&nil_error)

        corrupt := fixture_codec_test_copy(valid)
        corrupt[len(corrupt) - 1] ~= 0xff
        fixture_editor_test_expect_failure(t, editor, corrupt, context.allocator, live_snapshot)
        delete(corrupt)

        invalid_map_source := fixture_editor_test_source()
        invalid_map_source.map_source.inline_bytes[len(invalid_map_source.map_source.inline_bytes) - 1] ~= 0xff
        invalid_map, invalid_map_error, invalid_map_ok := fixture_codec_encode(invalid_map_source, context.allocator)
        testing.expect(t, invalid_map_ok && invalid_map_error.kind == .None)
        fixture_codec_error_dispose(&invalid_map_error)
        fixture_editor_test_source_destroy(invalid_map_source)
        if invalid_map_ok {
            fixture_editor_test_expect_failure(t, editor, invalid_map, context.allocator, live_snapshot)
            delete(invalid_map)
        }

        invalid_lifecycle_source := fixture_editor_test_source()
        invalid_lifecycle_source.aircraft.count = 3
        invalid_lifecycle, invalid_lifecycle_error, invalid_lifecycle_ok := fixture_codec_encode(
            invalid_lifecycle_source,
            context.allocator,
        )
        testing.expect(t, invalid_lifecycle_ok && invalid_lifecycle_error.kind == .None)
        fixture_codec_error_dispose(&invalid_lifecycle_error)
        fixture_editor_test_source_destroy(invalid_lifecycle_source)
        if invalid_lifecycle_ok {
            fixture_editor_test_expect_failure(t, editor, invalid_lifecycle, context.allocator, live_snapshot)
            post_apply_state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = -1,
            }
            post_apply_error, post_apply_ok := fixture_editor_load(
                editor,
                invalid_lifecycle,
                fixture_migration_test_allocator(&post_apply_state),
            )
            testing.expect(t, !post_apply_ok && post_apply_error.kind == .Lifecycle)
            testing.expect(t, fixture_editor_test_live_equal(editor, live_snapshot))
            fixture_editor_load_error_dispose(&post_apply_error)
            testing.expect(t, post_apply_state.outstanding == 0)
            delete(invalid_lifecycle)
        }

        invalid_body_source := fixture_editor_test_source()
        invalid_body_source.postale.body.position.x = math.nan_f32()
        invalid_body, invalid_body_error, invalid_body_ok := fixture_codec_encode(
            invalid_body_source,
            context.allocator,
        )
        testing.expect(t, invalid_body_ok && invalid_body_error.kind == .None)
        fixture_codec_error_dispose(&invalid_body_error)
        fixture_editor_test_source_destroy(invalid_body_source)
        if invalid_body_ok {
            fixture_editor_test_expect_failure(t, editor, invalid_body, context.allocator, live_snapshot)
            delete(invalid_body)
        }

        invalid_orientation_source := fixture_editor_test_source()
        invalid_orientation_source.libellula.body.orientation = {}
        invalid_orientation, invalid_orientation_error, invalid_orientation_ok := fixture_codec_encode(
            invalid_orientation_source,
            context.allocator,
        )
        testing.expect(t, invalid_orientation_ok && invalid_orientation_error.kind == .None)
        fixture_codec_error_dispose(&invalid_orientation_error)
        fixture_editor_test_source_destroy(invalid_orientation_source)
        if invalid_orientation_ok {
            fixture_editor_test_expect_failure(t, editor, invalid_orientation, context.allocator, live_snapshot)
            delete(invalid_orientation)
        }

        invalid_tuning_source := fixture_editor_test_source()
        invalid_tuning_source.postale.ace_tuning.weight = 2
        invalid_tuning, invalid_tuning_error, invalid_tuning_ok := fixture_codec_encode(
            invalid_tuning_source,
            context.allocator,
        )
        testing.expect(t, invalid_tuning_ok && invalid_tuning_error.kind == .None)
        fixture_codec_error_dispose(&invalid_tuning_error)
        fixture_editor_test_source_destroy(invalid_tuning_source)
        if invalid_tuning_ok {
            fixture_editor_test_expect_failure(t, editor, invalid_tuning, context.allocator, live_snapshot)
            delete(invalid_tuning)
        }

        hostile_counts := fixture_editor_test_source()
        hostile_counts.vehicle_effects.dust_count = len(hostile_counts.vehicle_effects.dust) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "vehicle_effects.dust_count")
        hostile_counts.vehicle_effects.dust_count = 0
        hostile_counts.wing_trails.count = len(hostile_counts.wing_trails.particles) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "wing_trails.count")
        hostile_counts.wing_trails.count = 0
        hostile_counts.petal_effects.count = len(hostile_counts.petal_effects.particles) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "petal_effects.count")
        hostile_counts.petal_effects.count = 0
        hostile_counts.settlement_plan.route_count = 1
        hostile_counts.settlement_plan.routes[0].geometry.count =
            len(hostile_counts.settlement_plan.routes[0].geometry.points) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "settlement_plan.routes.geometry.count")
        hostile_counts.settlement_plan.routes[0].geometry.count = 0
        hostile_counts.settlement_plan.route_count = 0
        hostile_counts.settlement_plan.growth_event_count = len(hostile_counts.settlement_plan.growth_events) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "settlement_plan.growth_event_count")
        hostile_counts.settlement_plan.growth_event_count = 0
        hostile_counts.settlement_plan.garden_count = len(hostile_counts.settlement_plan.gardens) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "settlement_plan.garden_count")
        hostile_counts.settlement_plan.garden_count = 0
        hostile_counts.settlement_plan.patio_count = len(hostile_counts.settlement_plan.patios) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "settlement_plan.patio_count")
        hostile_counts.settlement_plan.patio_count = 0
        hostile_counts.harbor_authored_plan.structure_count = len(hostile_counts.harbor_authored_plan.structures) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "harbor_authored_plan.count")
        hostile_counts.harbor_authored_plan.structure_count = 0
        hostile_counts.harbor_authored_plan.shoreline.count =
            len(hostile_counts.harbor_authored_plan.shoreline.points) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "harbor_authored_plan.count")
        hostile_counts.harbor_authored_plan.shoreline.count = 0
        hostile_counts.harbor_authored_plan.route_count = 1
        hostile_counts.harbor_authored_plan.routes[0].count =
            len(hostile_counts.harbor_authored_plan.routes[0].points) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "harbor_authored_plan.count")
        hostile_counts.harbor_authored_plan.routes[0].count = 0
        hostile_counts.harbor_authored_plan.route_count = 0
        hostile_counts.harbor_authored_intervention.phase_count =
            len(hostile_counts.harbor_authored_intervention.phases) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "harbor_authored_intervention.count")
        hostile_counts.harbor_authored_intervention.phase_count = 0
        hostile_counts.harbor_authored_intervention.runtime_plan.berth_count =
            len(hostile_counts.harbor_authored_intervention.runtime_plan.berths) + 1
        testing.expect(t, fixture_editor_load_preflight(hostile_counts) == "harbor_authored_intervention.count")
        fixture_editor_test_source_destroy(hostile_counts)

        probe_state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = -1,
        }
        probe := fixture_editor_test_editor(t)
        probe_error, probe_ok := fixture_editor_load(probe, valid, fixture_migration_test_allocator(&probe_state))
        testing.expect(t, probe_ok && probe_error.kind == .None)
        fixture_editor_load_error_dispose(&probe_error)
        allocation_count := probe_state.allocation_calls
        testing.expect(t, allocation_count > 0 && probe_state.outstanding > 0)
        fixture_editor_test_destroy(probe)
        testing.expect(t, probe_state.outstanding == 0)

        for fail_at in 0 ..< allocation_count {
            state := fixture_migration_test_allocator_state {
                base    = runtime.default_allocator(),
                fail_at = fail_at,
            }
            fixture_editor_test_expect_failure(
                t,
                editor,
                valid,
                fixture_migration_test_allocator(&state),
                live_snapshot,
            )
            testing.expect(t, state.allocation_calls == fail_at + 1)
            testing.expect(t, state.outstanding == 0)
        }
        testing.expect(t, fixture_codec_test_bytes_equal(valid, valid_snapshot))
    }
}
