package main

import architecture "../packages/architecture"
import fixture_file "../packages/fixture_file"
import fixture_v0001 "../packages/fixture_history/v0001"
import flight "../packages/flight"
import hs "../packages/hs"
import story "../packages/story"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"
import "core:time"

when ODIN_TEST {
    fixture_codec_test_destroy_source :: proc(source: ^Fixture) {
        if source == nil do return
        delete(source.map_source.inline_bytes)
        architecture.city_plan_destroy(&source.architecture_city_plan)
        architecture.city_plan_destroy(&source.architecture_preview_plan)
        terrain.destroy_project(&source.project)
        delete(source.circulation_structures)
        delete(source.vehicle_paint_open_pixels)
        free(source)
    }

    fixture_codec_test_copy :: proc(data: []byte) -> []byte {
        result := make([]byte, len(data), context.allocator)
        copy(result, data)
        return result
    }

    fixture_codec_test_destroy_historical :: proc(historical: ^fixture_v0001.Fixture) {
        if historical == nil do return
        delete(historical.vehicle_showcase_target)
        delete(historical.active_lab_scene)
        free(historical)
    }

    fixture_codec_test_source :: proc() -> ^Fixture {
        source := new(Fixture)
        source.project.sea_level = f32(12.75)
        source.project.revision = 77
        source.project.structure_count = 1
        source.project.next_structure_id = 2
        source.project.structures = make([dynamic]terrain.Structure, 1)
        source.project.structures[0] = {
            id       = 1,
            group_id = 9,
            center_x = 18,
            center_z = -24,
            width    = 8,
            depth    = 6,
            base_y   = 3,
            height   = 11,
            rotation = .25,
            color    = {12, 34, 56, 255},
            kind     = .Rock,
            seed     = 0x11223344,
        }
        for &level, index in source.project.levels {
            level.cell_size = terrain.FINE_CELL_SIZE * f32(u32(1) << u32(index))
            level.origin_x = -f32(terrain.RING_RESOLUTION / 2) * level.cell_size
            level.origin_z = level.origin_x
        }
        source.project.levels[len(source.project.levels) - 1].heights[len(source.project.levels[0].heights) - 1] = f32(
            91.5,
        )
        source.project.city_density[len(source.project.city_density) - 1] = 0xa5

        source.authoring_tool = .Marina
        source.editor_ui.left_collapsed = true
        source.sdf_obstacles[0] = {
            position     = {13, 21, -34},
            scale        = {1.5, .75, 2},
            major_radius = 8,
            tube_radius  = 2,
            color        = {31, 127, 223, 255},
        }
        source.sdf_obstacles[0].rotation.w = 1
        source.sdf_obstacles[0].rotation.x = 0
        source.sdf_obstacles[0].rotation.y = 0
        source.sdf_obstacles[0].rotation.z = 0
        source.sdf_obstacle_count = 1
        source.sdf_obstacle_selected = 0
        source.sdf_obstacle_interaction.hovered = 7
        source.tool = .Paint
        source.radius = f32(6.25)
        source.strength = f32(.73)
        source.structure_selected = 0
        source.structure_kind = .Rock
        source.architecture_city_plan.count = 1
        source.architecture_city_plan.structures = make([dynamic]terrain.Structure, 1)
        source.architecture_city_plan.structures[0].id = 0xabc
        source.architecture_city_plan.structures[0].kind = .Architecture
        source.architecture_city_plan.structures[0].center_x = 44
        source.architecture_city_plan.structures[0].center_z = -11
        source.architecture_city_plan.parcels = make([dynamic]architecture.City_Parcel, 1)
        source.architecture_city_plan.parcel_count = 1
        source.architecture_city_plan.parcels[0].corners[0] = {1, 2}
        source.architecture_city_plan.parcels[0].corners[1] = {3, 4}
        source.architecture_city_plan.parcels[0].frontage_width = 12
        source.architecture_city_plan.parcels[0].depth = 18
        source.architecture_city_plan.parcels[0].density = f32(.75)
        source.architecture_city_plan.parcels[0].seed = 0x50415243
        source.architecture_city_plan.parcels[0].attached = true
        source.architecture_city_plan.parcels[0].alley_frontage = true
        source.architecture_city_plan.alleys = make([dynamic]architecture.City_Alley, 1)
        source.architecture_city_plan.alley_count = 1
        source.architecture_city_plan.alleys[0] = {
            start_x    = 5,
            start_z    = -6,
            end_x      = 25,
            end_z      = 26,
            half_width = f32(1.5),
        }
        source.architecture_city_plan.lamps = make([dynamic]architecture.City_Lamp, 1)
        source.architecture_city_plan.lamp_count = 1
        source.architecture_city_plan.lamps[0] = {
            x   = 33,
            z   = -34,
            yaw = f32(.6),
        }
        source.architecture_brush_shape = .Macaroni
        source.architecture_brush_preset = .Large

        source.marina_authored = true
        source.marina_authored_plan.seed = 0x4d415249
        source.marina_authored_plan.layout_seed = 0x12345678
        source.marina_authored_plan.valid = true
        source.default_map_regeneration_seeds = {0x10203040, 0x50607080}
        source.default_marina_count = 1
        source.default_marina_islands[0] = story.Island.East
        source.default_marinas[0].seed = 0x4d415249
        source.default_marinas[0].layout_seed = 0x13579bdf
        source.default_marinas[0].valid = true
        source.default_harbors[0].seed = 0x48415242
        source.default_harbors[0].generation_version = 2
        source.default_harbors[0].valid = true
        source.farms[0].origin_x = f32(101)
        source.farms[0].origin_z = f32(-202)
        source.farms[0].yaw = f32(.35)
        source.farms[0].scale_x = f32(1.25)
        source.farms[0].scale_z = f32(.8)
        source.farms[0].plan.width = 25
        source.farms[0].plan.height = 19
        source.farms[0].plan.tradition = .Ancient_Enclosure
        source.farm_count = 1

        source.player.position = {1, 2, 3}
        source.player.velocity = {-.5, 0, 1.25}
        source.player.grounded = true
        source.camera = {
            yaw_radians   = .4,
            pitch_radians = -.2,
            distance      = 8,
            height        = 3,
        }
        source.camera_pose = {
            position = {1, 5, 9},
            target   = {1, 1, 3},
        }
        source.cameras.active = .Inspection
        source.cameras.poses[third_person.Camera_Slot.Inspection] = source.camera_pose
        source.flight_camera.focal_length = f32(2.75)
        source.flight_camera.initialized = true

        source.boat_traffic.clock = f32(876.5)
        source.boat_traffic.count = 1
        source.boat_traffic.agents[0].class = .Motor
        source.boat_traffic.agents[0].position = {55, -66}
        source.boat_traffic.agents[0].speed = f32(4.5)
        source.boat_traffic.agents[0].route_count = 1
        source.boat_traffic.agents[0].route[0] = {55, -66}
        source.boat_traffic.agents[0].schedule_count = 1
        source.boat_traffic.agents[0].schedule[0] = {480, 720, .Transit, .78}

        source.pilot.position = {10, 0, -10}
        source.pilot.mode = .On_Foot
        source.car.position = {20, 0, -20}
        source.car.yaw_radians = f32(.6)
        source.car.locked = false
        source.postale.throttle = f32(.62)
        source.libellula.throttle = f32(.38)
        source.postale.body.angular_velocity_world = {1, 2, 3}
        source.libellula.body.angular_velocity_world = {-4, 5, -6}
        source.rondine.body.angular_velocity_world = {7, 8, 9}
        source.postale.body.orientation = flight.orientation_from_basis(fixture_migration_v0004_runtime_basis(0))
        source.libellula.body.orientation = flight.orientation_from_basis(fixture_migration_v0004_runtime_basis(1))
        source.rondine.body.orientation = flight.orientation_from_basis(fixture_migration_v0004_runtime_basis(2))
        source.postale.spawn_orientation = flight.orientation_from_basis(fixture_migration_v0004_runtime_basis(3))
        source.libellula.spawn_orientation = flight.orientation_from_basis(fixture_migration_v0004_runtime_basis(4))
        source.postale.flight_model = .Ace_Arcade
        source.postale.ace_tuning = {
            pace       = f32(.11),
            roll_snap  = f32(.22),
            air_grip   = f32(.33),
            exit_catch = f32(.44),
        }
        source.postale.ace_runtime = {
            energy       = f32(.71),
            edge_state   = .Hang,
            edge_seconds = f32(1.25),
            local_rate   = {91, 92, 93},
        }
        source.postale.telemetry.airspeed = 94
        source.postale.ace_telemetry.pace = 95
        source.libellula.telemetry.total_thrust = 96
        source.camera_target_lock = true
        source.aircraft.count = 1
        source.aircraft.active = .Postale
        source.aircraft.slots[0] = {
            kind      = .Postale,
            name      = "postale-slot-marker",
            available = true,
        }
        source.vehicle_showcase_target = "showcase-target-marker"
        source.lab = {
            kind = .Dunes,
            dunes = {seed = 0x44554e45, wind_angle = .08, vegetation = .76},
        }

        source.settlement_plan.valid = true
        source.settlement_plan.neighborhood_count = 1
        source.settlement_plan.route_count = 1
        source.story_state.romance = .Corresponding
        source.story_state.repair = .Diagnosed
        source.story_state.delivery = {
            active      = true,
            kind        = .First_Letter,
            from        = .Niko,
            to          = .Iva,
            origin      = .West,
            destination = .East,
            subject     = "delivery-subject-marker",
        }
        source.story_state.completed_deliveries = 3
        source.story_state.resident_action_seen[.Niko] = 0x4e494b4f
        source.story_state.resident_action_seen[.Anica] = 0x414e4943
        source.atmosphere.seed = 0x41544d4f
        source.atmosphere.world_minutes = f32(1234.5)
        source.atmosphere.override = .Windy
        source.atmosphere.schedule = {
            initialized = true,
            rng_state = 0x46524e54,
            elapsed_seconds = 412.5,
            next_event_seconds = 901.25,
            event_serial = 7,
            front = {
                active = true,
                event_id = 7,
                seed = 0x53544f52,
                start_seconds = 400,
                end_seconds = 1000,
                origin = {-2400, 1750},
                direction = {.8, -.6},
                speed = 14.25,
                width = 2300,
                intensity = .86,
                gustiness = .71,
                rainfall = .92,
                visibility_loss = .64,
                cell_scale = 880,
                cell_phase = 1.75,
            },
        }
        source.vehicle_effects.seed = 0x56454658
        source.vehicle_effects.dust_count = 1
        source.vehicle_effects.dust[0].seed = 0x1234
        source.wing_trails.seed = 0x57494e47
        source.wing_trails.count = 1
        source.petal_effects.seed = 0x50455441
        source.petal_effects.count = 1
        source.tweak.atmosphere.world_minutes = f32(222.25)
        source.mouse_fur = .Silver
        source.mouse_pattern = .Dorsal_Stripe
        source.mouse_headgear = .Beret
        source.mouse_scarf_enabled = true
        source.mouse_scarf_rotation = f32(.45)

        source.vehicle_paint_tool = .Pattern
        source.vehicle_paint_brush_radius = 13
        source.vehicle_paint_brush_strength = f32(.81)
        source.vehicle_paint_components = {true, false, true, true, false}

        source.circulation_plan_valid = true
        source.circulation_revision = 0xdeadbeef
        source.circulation_structures = make([dynamic]terrain.Structure, 1)
        source.circulation_structures[0].id = 0xc1c1c1c1
        source.circulation_structure_count = 1
        source.structure_placing = true
        source.architecture_painting = true
        source.architecture_density_preview[123] = 0xc1
        source.architecture_preview_plan.structures = make([dynamic]terrain.Structure, 1)
        source.architecture_preview_plan.structures[0].id = 0xc2
        source.marina_preview_valid = true
        source.marina_preview_variation = 0xc3
        source.cursor_world_x = f32(333)
        source.cursor_world_z = f32(-444)
        source.cursor_hit = true
        source.map_time = f32(555)
        source.vehicle_paint_texture_dirty = true
        source.vehicle_paint_preview_pixels[37] = 0xd4
        source.vehicle_paint_history_pixels[38] = 0xd5
        source.vehicle_paint_texel_part[39] = 0xd6
        source.vehicle_paint_open_pixels = make([]u8, 24)
        marker := [24]byte {
            'E',
            'X',
            'C',
            'L',
            'U',
            'D',
            'E',
            'D',
            '-',
            'P',
            'A',
            'I',
            'N',
            'T',
            '-',
            'M',
            'A',
            'R',
            'K',
            'E',
            'R',
            '!',
            '!',
            '!',
        }
        copy(source.vehicle_paint_open_pixels, marker[:])

        source.pilot.vehicle = &source.car
        source.car.driver = &source.pilot
        source.aircraft.slots[0].vehicle = &source.car
        map_source, map_error, captured := fixture_map_source_capture_inline(source)
        map_artifact_error_dispose(&map_error)
        if !captured {
            fixture_codec_test_destroy_source(source)
            return nil
        }
        source.map_source = map_source
        return source
    }

    fixture_codec_test_expect_current_v5 :: proc(t: ^testing.T, source, decoded: ^Fixture) {
        testing.expect(
            t,
            decoded.postale.body.angular_velocity_world == source.postale.body.angular_velocity_world &&
            decoded.libellula.body.angular_velocity_world == source.libellula.body.angular_velocity_world &&
            decoded.rondine.body.angular_velocity_world == source.rondine.body.angular_velocity_world,
        )
        testing.expect(
            t,
            decoded.postale.body.orientation.x == source.postale.body.orientation.x &&
                decoded.postale.body.orientation.y == source.postale.body.orientation.y &&
                decoded.postale.body.orientation.z == source.postale.body.orientation.z &&
                decoded.postale.body.orientation.w == source.postale.body.orientation.w &&
                decoded.libellula.body.orientation.x == source.libellula.body.orientation.x &&
                decoded.libellula.body.orientation.y == source.libellula.body.orientation.y &&
                decoded.libellula.body.orientation.z == source.libellula.body.orientation.z &&
                decoded.libellula.body.orientation.w == source.libellula.body.orientation.w &&
                decoded.rondine.body.orientation.x == source.rondine.body.orientation.x &&
                decoded.rondine.body.orientation.y == source.rondine.body.orientation.y &&
                decoded.rondine.body.orientation.z == source.rondine.body.orientation.z &&
                decoded.rondine.body.orientation.w == source.rondine.body.orientation.w &&
                decoded.postale.spawn_orientation.x == source.postale.spawn_orientation.x &&
                decoded.postale.spawn_orientation.y == source.postale.spawn_orientation.y &&
                decoded.postale.spawn_orientation.z == source.postale.spawn_orientation.z &&
                decoded.postale.spawn_orientation.w == source.postale.spawn_orientation.w &&
                decoded.libellula.spawn_orientation.x == source.libellula.spawn_orientation.x &&
                decoded.libellula.spawn_orientation.y == source.libellula.spawn_orientation.y &&
                decoded.libellula.spawn_orientation.z == source.libellula.spawn_orientation.z &&
                decoded.libellula.spawn_orientation.w == source.libellula.spawn_orientation.w,
        )
        testing.expect(
            t,
            decoded.postale.flight_model == .Ace_Arcade &&
            decoded.postale.ace_tuning == source.postale.ace_tuning &&
            decoded.postale.ace_runtime.energy == source.postale.ace_runtime.energy &&
            decoded.postale.ace_runtime.edge_state == source.postale.ace_runtime.edge_state &&
            decoded.postale.ace_runtime.edge_seconds == source.postale.ace_runtime.edge_seconds,
        )
        testing.expect(
            t,
            decoded.postale.ace_runtime.local_rate == flight.Vec3{} &&
            decoded.postale.telemetry.airspeed == 0 &&
            decoded.postale.ace_telemetry.pace == 0 &&
            decoded.libellula.telemetry.total_thrust == 0 &&
            !decoded.camera_target_lock,
        )
    }

    fixture_codec_test_bytes_equal :: proc(left, right: []byte) -> bool {
        if len(left) != len(right) do return false
        for index in 0 ..< len(left) {
            if left[index] != right[index] do return false
        }
        return true
    }

    fixture_codec_test_decode_inline_map_source :: proc(
        t: ^testing.T,
        source: Fixture_Map_Source,
    ) -> ^Map_Artifact {
        testing.expect(t, source.kind == .Inline && len(source.inline_bytes) > 0 && source.sidecar == {})
        if source.kind != .Inline || len(source.inline_bytes) == 0 || source.sidecar != {} do return nil
        artifact, error, decoded := map_artifact_decode(source.inline_bytes[:])
        testing.expect(t, decoded && error.kind == .None)
        map_artifact_error_dispose(&error)
        if !decoded do return nil
        return artifact
    }

    fixture_codec_test_expect_empty :: proc(
        t: ^testing.T,
        result: ^Fixture_Migration_Result,
        error: ^Fixture_Codec_Error,
    ) {
        testing.expect(t, fixture_migration_result_empty(result))
        fixture_codec_error_dispose(error)
        fixture_codec_error_dispose(error)
        fixture_migration_result_dispose(result)
        fixture_migration_result_dispose(result)
        testing.expect(t, fixture_migration_result_empty(result))
    }

    fixture_codec_test_invalid_historical_payload :: proc(t: ^testing.T) -> ([]byte, bool) {
        payload, payload_ok := fixture_migration_test_historical_payload(t)
        if !payload_ok do return nil, false
        historical := new(fixture_v0001.Fixture)
        historical_value := any {
            data = rawptr(historical),
            id   = typeid_of(fixture_v0001.Fixture),
        }
        decode_error, decode_ok := hs.portable_decode(
            historical_value,
            payload,
            fixture_codec_portable_config(),
            context.allocator,
        )
        delete(payload)
        testing.expect(t, decode_ok)
        if !decode_ok {
            hs.portable_error_dispose(&decode_error)
            fixture_codec_test_destroy_historical(historical)
            return nil, false
        }
        hs.portable_error_dispose(&decode_error)
        historical.project.structure_count = 257
        invalid, encode_error, encode_ok := hs.portable_encode(
            historical_value,
            fixture_codec_portable_config(),
            context.allocator,
        )
        hs.portable_error_dispose(&encode_error)
        fixture_codec_test_destroy_historical(historical)
        return invalid, encode_ok
    }

    fixture_codec_test_historical_payload :: proc(t: ^testing.T, version: int) -> ([]byte, bool) {
        switch version {
        case 1:
            return fixture_migration_v0004_runtime_v1_payload(t)
        case 2:
            return fixture_migration_v0004_runtime_v2_payload(t)
        case 3:
            return fixture_migration_v0004_runtime_v3_payload(t)
        case 4:
            return fixture_migration_v0004_runtime_v4_payload(t)
        }
        testing.expect(t, false)
        return nil, false
    }

    fixture_codec_test_historical_container :: proc(t: ^testing.T, version: int) -> ([]byte, bool) {
        payload, payload_ok := fixture_codec_test_historical_payload(t, version)
        testing.expect(t, payload_ok)
        if !payload_ok do return nil, false
        defer delete(payload)
        container, container_error, container_ok := fixture_file.fixture_container_encode(
            payload,
            u32(version),
            alloc = context.allocator,
        )
        testing.expect(t, container_ok && container_error.kind == .None)
        return container, container_ok
    }

    fixture_codec_test_expect_historical_round_trip :: proc(t: ^testing.T, container: []byte, version: int) {
        snapshot := fixture_codec_test_copy(container)
        defer delete(snapshot)
        first, first_error, first_ok := fixture_codec_decode(container, context.allocator)
        second, second_error, second_ok := fixture_codec_decode(container, context.allocator)
        testing.expect(t, first_ok && first_error.kind == .None)
        testing.expect(t, second_ok && second_error.kind == .None)

        if first_ok && second_ok {
            first_encoded, first_encode_error, first_encoded_ok := fixture_codec_encode(
                first.fixture,
                context.allocator,
            )
            second_encoded, second_encode_error, second_encoded_ok := fixture_codec_encode(
                second.fixture,
                context.allocator,
            )
            testing.expect(t, first_encoded_ok && first_encode_error.kind == .None)
            testing.expect(t, second_encoded_ok && second_encode_error.kind == .None)
            if first_encoded_ok && second_encoded_ok {
                view, view_error, view_ok := fixture_file.fixture_container_decode(first_encoded)
                testing.expect(t, view_ok && view_error.kind == .None)
                testing.expect(t, view.schema_version == u32(FIXTURE_SCHEMA_VERSION))
                testing.expect(t, fixture_codec_test_bytes_equal(first_encoded, second_encoded))
            }
            if first_encoded_ok do delete(first_encoded)
            if second_encoded_ok do delete(second_encoded)
            fixture_codec_error_dispose(&first_encode_error)
            fixture_codec_error_dispose(&first_encode_error)
            fixture_codec_error_dispose(&second_encode_error)
            fixture_codec_error_dispose(&second_encode_error)

            fixture_migration_v0004_runtime_expect_result(t, &first, version)
            fixture_migration_v0004_runtime_expect_result(t, &second, version)
        }
        testing.expect(t, fixture_codec_test_bytes_equal(container, snapshot))
        fixture_codec_error_dispose(&first_error)
        fixture_codec_error_dispose(&first_error)
        fixture_codec_error_dispose(&second_error)
        fixture_codec_error_dispose(&second_error)
        fixture_migration_result_dispose(&first)
        fixture_migration_result_dispose(&first)
        fixture_migration_result_dispose(&second)
        fixture_migration_result_dispose(&second)
        testing.expect(t, fixture_migration_result_empty(&first) && fixture_migration_result_empty(&second))
    }

    fixture_codec_test_expect_v4_migration_failure :: proc(
        t: ^testing.T,
        payload: []byte,
        expected_change_id: string,
    ) {
        container, container_error, container_ok := fixture_file.fixture_container_encode(
            payload,
            4,
            alloc = context.allocator,
        )
        testing.expect(t, container_ok && container_error.kind == .None)
        if !container_ok do return
        defer delete(container)
        snapshot := fixture_codec_test_copy(container)
        defer delete(snapshot)
        result, error, ok := fixture_codec_decode(container, context.allocator)
        testing.expect(
            t,
            !ok &&
            error.kind == .Migration &&
            error.migration.kind == .Step_Failure &&
            error.migration.change_id == expected_change_id &&
            fixture_migration_result_empty(&result) &&
            fixture_codec_test_bytes_equal(container, snapshot),
        )
        fixture_codec_test_expect_empty(t, &result, &error)
    }

    @(test)
    fixture_codec_real_fixture_round_trip_and_failures :: proc(t: ^testing.T) {
        source := fixture_codec_test_source()
        defer fixture_codec_test_destroy_source(source)

        occupant_values := [6]vehicles.Fixture_Occupant{.On_Foot, .Car, .Postale, .Libellula, .Libellula_Mk2, .Rondine}
        for occupant in occupant_values {
            source.occupant = occupant
            source_lamp_count := len(source.architecture_city_plan.lamps)
            occupant_first, occupant_first_error, occupant_first_ok := fixture_codec_encode(source, context.allocator)
            testing.expect(t, occupant_first_ok && occupant_first_error.kind == .None)
            occupant_second, occupant_second_error, occupant_second_ok := fixture_codec_encode(
                source,
                context.allocator,
            )
            testing.expect(t, occupant_second_ok && occupant_second_error.kind == .None)
            if occupant_first_ok && occupant_second_ok {
                testing.expect(t, fixture_codec_test_bytes_equal(occupant_first, occupant_second))
                occupant_view, occupant_view_error, occupant_view_ok := fixture_file.fixture_container_decode(
                    occupant_first,
                )
                testing.expect(t, occupant_view_ok && occupant_view_error.kind == .None)
                testing.expect(t, occupant_view.schema_version == u32(FIXTURE_SCHEMA_VERSION))
                occupant_snapshot := fixture_codec_test_copy(occupant_first)
                occupant_result, occupant_error, occupant_ok := fixture_codec_decode(occupant_first, context.allocator)
                testing.expect(t, occupant_ok && occupant_error.kind == .None)
                if occupant_ok {
                    testing.expect(t, occupant_result.fixture.occupant == occupant)
                    fixture_codec_test_expect_current_v5(t, source, occupant_result.fixture)
                    testing.expect(t, occupant_result.fixture.pilot.mode == .On_Foot)
                    testing.expect(t, occupant_result.fixture.aircraft.active == .Postale)
                    testing.expect(
                        t,
                        occupant_result.fixture.story_state.resident_action_seen ==
                        source.story_state.resident_action_seen,
                    )
                    occupant_restored, occupant_restored_error, occupant_restored_ok := fixture_codec_encode(
                        occupant_result.fixture,
                        context.allocator,
                    )
                    testing.expect(t, occupant_restored_ok && occupant_restored_error.kind == .None)
                    if occupant_restored_ok {
                        testing.expect(t, fixture_codec_test_bytes_equal(occupant_first, occupant_restored))
                        delete(occupant_restored)
                    }
                    fixture_codec_error_dispose(&occupant_restored_error)
                    fixture_codec_error_dispose(&occupant_restored_error)

                    occupant_lamps := cast(^runtime.Raw_Dynamic_Array)&occupant_result.fixture.architecture_city_plan.lamps
                    testing.expect(t, occupant_lamps.allocator.data == rawptr(occupant_result.arena))
                    previous_length := len(occupant_result.fixture.architecture_city_plan.lamps)
                    append(&occupant_result.fixture.architecture_city_plan.lamps, architecture.City_Lamp{x = 7000})
                    testing.expect(t, len(occupant_result.fixture.architecture_city_plan.lamps) == previous_length + 1)
                }
                testing.expect(t, fixture_codec_test_bytes_equal(occupant_first, occupant_snapshot))
                delete(occupant_snapshot)
                fixture_codec_error_dispose(&occupant_error)
                fixture_codec_error_dispose(&occupant_error)
                fixture_migration_result_dispose(&occupant_result)
                fixture_migration_result_dispose(&occupant_result)
                testing.expect(t, fixture_migration_result_empty(&occupant_result))
            }
            testing.expect(t, source.occupant == occupant)
            testing.expect(t, source.pilot.mode == .On_Foot)
            testing.expect(t, source.aircraft.active == .Postale)
            testing.expect(t, source.pilot.vehicle == &source.car)
            testing.expect(t, source.car.driver == &source.pilot)
            testing.expect(t, len(source.architecture_city_plan.lamps) == source_lamp_count)
            fixture_codec_error_dispose(&occupant_first_error)
            fixture_codec_error_dispose(&occupant_first_error)
            fixture_codec_error_dispose(&occupant_second_error)
            fixture_codec_error_dispose(&occupant_second_error)
            if occupant_first_ok do delete(occupant_first)
            if occupant_second_ok do delete(occupant_second)
        }
        source.occupant = .On_Foot

        encode_start := time.tick_now()
        first, first_error, first_ok := fixture_codec_encode(source, context.allocator)
        encode_ms := time.duration_seconds(time.tick_since(encode_start)) * 1000
        testing.expect(t, first_ok)
        testing.expect(t, first_error.kind == .None)
        if !first_ok do return
        second, second_error, second_ok := fixture_codec_encode(source, context.allocator)
        testing.expect(t, second_ok)
        testing.expect(t, second_error.kind == .None)
        testing.expect(t, len(first) == len(second))
        testing.expect(t, len(first) * 10 <= fixture_file.Fixture_Container_Default_Payload_Cap * 9)
        defer delete(first)
        defer delete(second)
        first_snapshot := fixture_codec_test_copy(first)
        defer delete(first_snapshot)
        if second_ok {
            for index in 0 ..< len(first) {
                testing.expect(t, first[index] == second[index])
            }
        }

        container_view, container_error, container_ok := fixture_file.fixture_container_decode(first)
        testing.expect(t, container_ok)
        testing.expect(t, container_error.kind == .None)
        testing.expect(t, container_view.schema_version == u32(FIXTURE_SCHEMA_VERSION))
        portable_size := len(container_view.payload)
        container_size := len(first)
        payload_text := string(container_view.payload)
        testing.expect(t, !strings.contains(payload_text, "circulation_plan"))
        testing.expect(t, !strings.contains(payload_text, "circulation_structures"))
        testing.expect(t, !strings.contains(payload_text, "architecture_density_preview"))
        testing.expect(t, !strings.contains(payload_text, "vehicle_paint_open_pixels"))
        testing.expect(t, !strings.contains(payload_text, "EXCLUDED-PAINT-MARKER"))

        decode_start := time.tick_now()
        current_result, decode_error, decode_ok := fixture_codec_decode(first, context.allocator)
        decode_ms := time.duration_seconds(time.tick_since(decode_start)) * 1000
        testing.expect(t, decode_ok)
        testing.expect(t, decode_error.kind == .None)
        decoded := current_result.fixture
        testing.expect(t, decoded != nil)
        if decode_ok {
            fixture_codec_test_expect_current_v5(t, source, decoded)
            artifact := fixture_codec_test_decode_inline_map_source(t, decoded.map_source)
            defer map_artifact_destroy(artifact)
            if artifact != nil {
                testing.expect(t, artifact.project.sea_level == source.project.sea_level)
                testing.expect(t, artifact.project.revision == source.project.revision)
                testing.expect(t, artifact.project.structures[0].id == source.project.structures[0].id)
                testing.expect(t, len(artifact.project.structures) == 1)
                testing.expect(
                    t,
                    artifact.project.levels[len(artifact.project.levels) - 1].heights[
                        len(artifact.project.levels[0].heights) - 1
                    ] == f32(91.5),
                )
                testing.expect(t, artifact.project.city_density[len(artifact.project.city_density) - 1] == 0xa5)
                testing.expect(t, artifact.marina_authored_plan.seed == source.marina_authored_plan.seed)
                testing.expect_value(t, artifact.seeds, source.default_map_regeneration_seeds)
                testing.expect(t, artifact.default_marina_count == 1)
                testing.expect(t, artifact.default_marina_islands[0] == story.Island.East)
                testing.expect(t, artifact.default_marinas[0].seed == source.default_marinas[0].seed)
                testing.expect(t, artifact.default_marinas[0].layout_seed == source.default_marinas[0].layout_seed)
                testing.expect(t, artifact.default_marinas[0].valid)
                testing.expect(t, artifact.default_harbors[0].seed == source.default_harbors[0].seed)
                testing.expect(t, artifact.default_harbors[0].generation_version == 2)
                testing.expect(t, artifact.default_harbors[0].valid)
                testing.expect(t, artifact.farm_count == 1)
                testing.expect(t, artifact.farms[0].origin_x == source.farms[0].origin_x)
                testing.expect(t, artifact.farms[0].scale_x == source.farms[0].scale_x)
                testing.expect(t, artifact.farms[0].scale_z == source.farms[0].scale_z)
                testing.expect(t, artifact.farms[0].plan.width == source.farms[0].plan.width)
                testing.expect(t, artifact.farms[0].plan.height == source.farms[0].plan.height)
                testing.expect(t, artifact.farms[0].plan.tradition == source.farms[0].plan.tradition)
                testing.expect(t, artifact.settlement_plan.valid)
                testing.expect(t, artifact.settlement_plan.neighborhood_count == 1)
            }
            testing.expect(t, decoded.authoring_tool == .Marina)
            testing.expect(t, decoded.sdf_obstacle_count == 1)
            testing.expect(t, decoded.sdf_obstacle_selected == 0)
            testing.expect(
                t,
                decoded.sdf_obstacles[0].position.x == source.sdf_obstacles[0].position.x &&
                    decoded.sdf_obstacles[0].position.y == source.sdf_obstacles[0].position.y &&
                    decoded.sdf_obstacles[0].position.z == source.sdf_obstacles[0].position.z &&
                    decoded.sdf_obstacles[0].rotation.x == source.sdf_obstacles[0].rotation.x &&
                    decoded.sdf_obstacles[0].rotation.y == source.sdf_obstacles[0].rotation.y &&
                    decoded.sdf_obstacles[0].rotation.z == source.sdf_obstacles[0].rotation.z &&
                    decoded.sdf_obstacles[0].rotation.w == source.sdf_obstacles[0].rotation.w &&
                    decoded.sdf_obstacles[0].scale.x == source.sdf_obstacles[0].scale.x &&
                    decoded.sdf_obstacles[0].scale.y == source.sdf_obstacles[0].scale.y &&
                    decoded.sdf_obstacles[0].scale.z == source.sdf_obstacles[0].scale.z &&
                    decoded.sdf_obstacles[0].major_radius == source.sdf_obstacles[0].major_radius &&
                    decoded.sdf_obstacles[0].tube_radius == source.sdf_obstacles[0].tube_radius &&
                    decoded.sdf_obstacles[0].color[0] == source.sdf_obstacles[0].color[0] &&
                    decoded.sdf_obstacles[0].color[1] == source.sdf_obstacles[0].color[1] &&
                    decoded.sdf_obstacles[0].color[2] == source.sdf_obstacles[0].color[2] &&
                    decoded.sdf_obstacles[0].color[3] == source.sdf_obstacles[0].color[3],
            )
            testing.expect(
                t,
                decoded.sdf_obstacle_interaction.hovered == 0 &&
                    decoded.sdf_obstacle_interaction.gizmo_mode == .None &&
                    decoded.sdf_obstacle_interaction.constrained_axis == .None &&
                    !decoded.sdf_obstacle_interaction.transform_snapshot_valid &&
                    !decoded.sdf_obstacle_interaction.inspector_euler_valid,
            )
            testing.expect(t, decoded.radius == source.radius)
            testing.expect(t, decoded.architecture_city_plan.count == 1)
            testing.expect(t, len(decoded.architecture_city_plan.structures) == 1)
            testing.expect(t, decoded.architecture_city_plan.structures[0].id == 0xabc)
            testing.expect(t, decoded.architecture_city_plan.parcel_count == 1)
            testing.expect(t, len(decoded.architecture_city_plan.parcels) == 1)
            testing.expect(t, decoded.architecture_city_plan.parcels[0].seed == 0x50415243)
            testing.expect(t, decoded.architecture_city_plan.parcels[0].attached)
            testing.expect(t, decoded.architecture_city_plan.alley_count == 1)
            testing.expect(t, len(decoded.architecture_city_plan.alleys) == 1)
            testing.expect(t, decoded.architecture_city_plan.alleys[0].end_z == f32(26))
            testing.expect(t, decoded.architecture_city_plan.lamp_count == 1)
            testing.expect(t, len(decoded.architecture_city_plan.lamps) == 1)
            testing.expect(t, decoded.architecture_city_plan.lamps[0].yaw == f32(.6))
            testing.expect(t, decoded.architecture_brush_shape == source.architecture_brush_shape)
            testing.expect(t, decoded.architecture_brush_preset == source.architecture_brush_preset)
            testing.expect(t, decoded.player.position == source.player.position)
            testing.expect(t, decoded.camera.distance == source.camera.distance)
            testing.expect(t, decoded.flight_camera.focal_length == source.flight_camera.focal_length)
            testing.expect(t, decoded.boat_traffic.clock == source.boat_traffic.clock)
            testing.expect(t, decoded.boat_traffic.agents[0].schedule[0].speed_scale == f32(.78))
            testing.expect(t, decoded.pilot.position == source.pilot.position)
            testing.expect(t, decoded.aircraft.slots[0].name == "postale-slot-marker")
            testing.expect(t, decoded.aircraft.slots[0].available)
            testing.expect(t, decoded.vehicle_showcase_target == "showcase-target-marker")
            testing.expect(t, decoded.lab == source.lab)
            testing.expect(t, decoded.story_state.delivery.subject == "delivery-subject-marker")
            testing.expect(t, decoded.story_state.resident_action_seen == source.story_state.resident_action_seen)
            testing.expect(t, decoded.atmosphere.world_minutes == source.atmosphere.world_minutes)
            testing.expect(t, decoded.atmosphere.schedule == source.atmosphere.schedule)
            testing.expect(t, decoded.vehicle_effects.seed == source.vehicle_effects.seed)
            testing.expect(t, decoded.tweak.atmosphere.world_minutes == source.tweak.atmosphere.world_minutes)
            testing.expect(t, decoded.mouse_fur == .Silver)
            testing.expect(t, decoded.mouse_pattern == .Dorsal_Stripe)
            testing.expect(t, !decoded.circulation_plan_valid)
            testing.expect(t, decoded.circulation_revision == 0)
            testing.expect(t, len(decoded.circulation_structures) == 0)
            testing.expect(t, !decoded.structure_placing)
            testing.expect(t, !decoded.architecture_painting)
            testing.expect(t, decoded.architecture_density_preview[123] == 0)
            testing.expect(t, len(decoded.architecture_preview_plan.structures) == 0)
            testing.expect(t, !decoded.marina_preview_valid)
            testing.expect(t, decoded.marina_preview_variation == 0)
            testing.expect(t, !decoded.cursor_hit)
            testing.expect(t, decoded.map_time == 0)
            testing.expect(t, !decoded.vehicle_paint_texture_dirty)
            testing.expect(t, decoded.vehicle_paint_preview_pixels[37] == 0)
            testing.expect(t, decoded.vehicle_paint_history_pixels[38] == 0)
            testing.expect(t, decoded.vehicle_paint_texel_part[39] == 0)
            testing.expect(t, len(decoded.vehicle_paint_open_pixels) == 0)
            testing.expect(t, decoded.pilot.vehicle == nil)
            testing.expect(t, decoded.car.driver == nil)
            testing.expect(t, decoded.aircraft.slots[0].vehicle == nil)

            restored, restored_error, restored_ok := fixture_codec_encode(decoded, context.allocator)
            testing.expect(t, restored_ok)
            testing.expect(t, restored_error.kind == .None)
            if restored_ok {
                testing.expect(t, len(restored) == len(first))
                for index in 0 ..< len(first) {
                    testing.expect(t, first[index] == restored[index])
                }
                delete(restored)
            }
            fixture_codec_error_dispose(&restored_error)
            fixture_codec_error_dispose(&restored_error)

            decoded_lamps := cast(^runtime.Raw_Dynamic_Array)(&decoded.architecture_city_plan.lamps)
            testing.expect(t, decoded_lamps.allocator.data == rawptr(current_result.arena))
            previous_lamp_length := len(decoded.architecture_city_plan.lamps)
            append(&decoded.architecture_city_plan.lamps, architecture.City_Lamp{x = 9001})
            testing.expect(t, len(decoded.architecture_city_plan.lamps) == previous_lamp_length + 1)
            testing.expect(t, decoded.architecture_city_plan.lamps[previous_lamp_length].x == 9001)
        }
        fixture_codec_error_dispose(&decode_error)
        fixture_codec_error_dispose(&decode_error)
        fixture_migration_result_dispose(&current_result)
        fixture_migration_result_dispose(&current_result)
        testing.expect(t, fixture_migration_result_empty(&current_result))

        for version in 1 ..= 4 {
            historical_container, historical_ok := fixture_codec_test_historical_container(t, version)
            if !historical_ok do continue
            fixture_codec_test_expect_historical_round_trip(t, historical_container, version)
            delete(historical_container)
        }

        nil_allocator: mem.Allocator
        nil_result, nil_error, nil_ok := fixture_codec_decode(first, nil_allocator)
        testing.expect(t, !nil_ok && nil_error.kind == .Invalid_Argument)
        fixture_codec_test_expect_empty(t, &nil_result, &nil_error)

        for length in 0 ..< fixture_file.Sectioned_Container_Header_Size {
            truncated_result, truncated_error, truncated_ok := fixture_codec_decode(first[:length], context.allocator)
            testing.expect(t, !truncated_ok)
            if length < len(fixture_file.Sectioned_Container_Magic) {
                testing.expect(t, truncated_error.kind == .Container_Decode)
                testing.expect(t, truncated_error.container.kind == .Truncated)
            } else {
                testing.expect(t, truncated_error.kind == .Sectioned_Container_Decode)
                testing.expect(t, truncated_error.sectioned.kind == .Truncated)
            }
            fixture_codec_test_expect_empty(t, &truncated_result, &truncated_error)
        }

        corrupt := fixture_codec_test_copy(first)
        corrupt[fixture_file.Sectioned_Container_Header_Size + fixture_file.Sectioned_Container_Entry_Size] =
            corrupt[fixture_file.Sectioned_Container_Header_Size + fixture_file.Sectioned_Container_Entry_Size] ~ 1
        corrupt_result, corrupt_error, corrupt_ok := fixture_codec_decode(corrupt, context.allocator)
        testing.expect(t, !corrupt_ok)
        testing.expect(t, corrupt_error.kind == .Sectioned_Container_Decode)
        testing.expect(t, corrupt_error.sectioned.kind == .Checksum_Mismatch)
        fixture_codec_test_expect_empty(t, &corrupt_result, &corrupt_error)
        delete(corrupt)

        schema_container, schema_container_error, schema_container_ok := fixture_file.fixture_container_encode(
            container_view.payload,
            u32(FIXTURE_SCHEMA_VERSION + 1),
            alloc = context.allocator,
        )
        testing.expect(t, schema_container_ok)
        testing.expect(t, schema_container_error.kind == .None)
        if schema_container_ok {
            schema_result, schema_error, schema_ok := fixture_codec_decode(schema_container, context.allocator)
            testing.expect(t, !schema_ok)
            testing.expect(t, schema_error.kind == .Schema_Mismatch)
            fixture_codec_test_expect_empty(t, &schema_result, &schema_error)
            delete(schema_container)
        }

        malformed_payload := []byte{1, 2, 3, 4}
        malformed, malformed_error, malformed_ok := fixture_file.fixture_container_encode(
            malformed_payload,
            u32(FIXTURE_SCHEMA_VERSION),
            alloc = context.allocator,
        )
        testing.expect(t, malformed_ok)
        testing.expect(t, malformed_error.kind == .None)
        if malformed_ok {
            malformed_result, malformed_codec_error, malformed_decode_ok := fixture_codec_decode(
                malformed,
                context.allocator,
            )
            testing.expect(t, !malformed_decode_ok)
            testing.expect(t, malformed_codec_error.kind == .Migration)
            testing.expect(t, malformed_codec_error.migration.kind == .Tentative_Decode)
            fixture_codec_test_expect_empty(t, &malformed_result, &malformed_codec_error)
            delete(malformed)
        }

        invalid_payload, invalid_payload_ok := fixture_codec_test_invalid_historical_payload(t)
        testing.expect(t, invalid_payload_ok)
        if invalid_payload_ok {
            invalid_container, invalid_container_error, invalid_container_ok := fixture_file.fixture_container_encode(
                invalid_payload,
                1,
                alloc = context.allocator,
            )
            testing.expect(t, invalid_container_ok)
            testing.expect(t, invalid_container_error.kind == .None)
            delete(invalid_payload)
            if invalid_container_ok {
                invalid_result, invalid_error, invalid_ok := fixture_codec_decode(invalid_container, context.allocator)
                testing.expect(t, !invalid_ok)
                testing.expect(t, invalid_error.kind == .Migration)
                testing.expect(t, invalid_error.migration.kind == .Step_Failure)
                testing.expect(t, invalid_error.migration.change_id == FIXTURE_MIGRATION_V0001_TERRAIN_STRUCTURES_ID)
                fixture_codec_test_expect_empty(t, &invalid_result, &invalid_error)
                delete(invalid_container)
            }
        }

        bad_basis, bad_basis_ok := fixture_migration_v0004_runtime_v4_payload(t, invalid_basis = true)
        bad_angular, bad_angular_ok := fixture_migration_v0004_runtime_v4_payload(t, invalid_angular = true)
        testing.expect(t, bad_basis_ok && bad_angular_ok)
        if bad_basis_ok {
            fixture_codec_test_expect_v4_migration_failure(
                t,
                bad_basis,
                FIXTURE_MIGRATION_V0004_TO_V0005_BODY_ORIENTATION_ID,
            )
            delete(bad_basis)
        }
        if bad_angular_ok {
            fixture_codec_test_expect_v4_migration_failure(t, bad_angular, FIXTURE_MIGRATION_V0004_TO_V0005_ANGULAR_ID)
            delete(bad_angular)
        }
        testing.expect(t, fixture_codec_test_bytes_equal(first_snapshot, first))
        testing.expect(t, container_size > 0)

        fmt.printf(
            "fixture codec: Fixture=%d portable=%d container=%d encode_ms=%.3f decode_ms=%.3f\n",
            size_of(Fixture),
            portable_size,
            container_size,
            encode_ms,
            decode_ms,
        )
    }
}
