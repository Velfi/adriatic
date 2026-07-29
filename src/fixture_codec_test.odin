package main

import architecture "../packages/architecture"
import fixture_file "../packages/fixture_file"
import fixture_v0001 "../packages/fixture_history/v0001"
import fixture_v0002 "../packages/fixture_history/v0002"
import hs "../packages/hs"
import quest "../packages/quest"
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
        source.project.levels[len(source.project.levels) - 1].heights[len(source.project.levels[0].heights) - 1] = f32(
            91.5,
        )
        source.project.city_density[len(source.project.city_density) - 1] = 0xa5

        source.authoring_tool = .Marina
        source.editor_ui.left_collapsed = true
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
        source.aircraft.count = 1
        source.aircraft.active = .Postale
        source.aircraft.slots[0] = {
            kind      = .Postale,
            name      = "postale-slot-marker",
            available = true,
        }
        source.vehicle_showcase_target = "showcase-target-marker"
        source.active_lab_scene = "active-lab-marker"

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
        source.vehicle_paint_layers[0][0] = 17
        source.vehicle_paint_layers[2][VEHICLE_PAINT_TEXTURE_BYTE_COUNT - 1] = 231
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
        return source
    }

    fixture_codec_test_bytes_equal :: proc(left, right: []byte) -> bool {
        if len(left) != len(right) do return false
        for index in 0 ..< len(left) {
            if left[index] != right[index] do return false
        }
        return true
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

    fixture_codec_test_v2_payload :: proc(t: ^testing.T) -> ([]byte, bool) {
        arena, arena_ok := fixture_migration_arena_allocate(context.allocator)
        testing.expect(t, arena_ok)
        if !arena_ok do return nil, false
        defer fixture_migration_arena_dispose(arena, context.allocator)

        allocator := mem.dynamic_arena_allocator(arena)
        historical := new(fixture_v0002.Fixture, allocator)
        testing.expect(t, historical != nil)
        if historical == nil do return nil, false

        historical.pilot.mode = .Driving
        historical.architecture_brush_radius = 45
        historical.aircraft.slots[0].kind = .Postale
        historical.aircraft.slots[1].kind = .Libellula
        historical.aircraft.slots[2].kind = .Libellula_Mk2
        historical.aircraft.active = .Libellula_Mk2
        historical.aircraft.count = 3
        historical.structure_selected = 731
        historical.vehicle_showcase_target = "codec-v2-target"
        historical.active_lab_scene = "codec-v2-lab"
        historical.architecture_city_plan.lamps = make([dynamic]fixture_v0002.History_Type_0001, 1, allocator)
        historical.architecture_city_plan.lamp_count = 1
        historical.architecture_city_plan.lamps[0] = {
            x   = 73,
            z   = -37,
            yaw = f32(.375),
        }

        payload, portable_error, ok := hs.portable_encode(
            any{data = rawptr(historical), id = typeid_of(fixture_v0002.Fixture)},
            fixture_codec_historical_portable_config(),
            context.allocator,
        )
        testing.expect(t, ok && portable_error.kind == .None)
        hs.portable_error_dispose(&portable_error)
        hs.portable_error_dispose(&portable_error)
        return payload, ok
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
            testing.expect(t, decoded.project.sea_level == source.project.sea_level)
            testing.expect(t, decoded.project.revision == source.project.revision)
            testing.expect(t, decoded.project.structures[0].id == source.project.structures[0].id)
            testing.expect(t, len(decoded.project.structures) == 1)
            testing.expect(
                t,
                decoded.project.levels[len(decoded.project.levels) - 1].heights[len(decoded.project.levels[0].heights) - 1] ==
                f32(91.5),
            )
            testing.expect(t, decoded.project.city_density[len(decoded.project.city_density) - 1] == 0xa5)
            testing.expect(t, decoded.authoring_tool == .Marina)
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
            testing.expect(t, decoded.marina_authored_plan.seed == source.marina_authored_plan.seed)
            testing.expect(t, decoded.farm_count == 1)
            testing.expect(t, decoded.farms[0].origin_x == source.farms[0].origin_x)
            testing.expect(t, decoded.farms[0].scale_x == source.farms[0].scale_x)
            testing.expect(t, decoded.farms[0].scale_z == source.farms[0].scale_z)
            testing.expect(t, decoded.farms[0].plan.width == source.farms[0].plan.width)
            testing.expect(t, decoded.farms[0].plan.height == source.farms[0].plan.height)
            testing.expect(t, decoded.farms[0].plan.tradition == source.farms[0].plan.tradition)
            testing.expect(t, decoded.player.position == source.player.position)
            testing.expect(t, decoded.camera.distance == source.camera.distance)
            testing.expect(t, decoded.flight_camera.focal_length == source.flight_camera.focal_length)
            testing.expect(t, decoded.boat_traffic.clock == source.boat_traffic.clock)
            testing.expect(t, decoded.boat_traffic.agents[0].schedule[0].speed_scale == f32(.78))
            testing.expect(t, decoded.pilot.position == source.pilot.position)
            testing.expect(t, decoded.aircraft.slots[0].name == "postale-slot-marker")
            testing.expect(t, decoded.aircraft.slots[0].available)
            testing.expect(t, decoded.vehicle_showcase_target == "showcase-target-marker")
            testing.expect(t, decoded.active_lab_scene == "active-lab-marker")
            testing.expect(t, decoded.settlement_plan.valid)
            testing.expect(t, decoded.settlement_plan.neighborhood_count == 1)
            testing.expect(t, decoded.story_state.delivery.subject == "delivery-subject-marker")
            testing.expect(t, decoded.story_state.resident_action_seen == source.story_state.resident_action_seen)
            testing.expect(t, decoded.atmosphere.world_minutes == source.atmosphere.world_minutes)
            testing.expect(t, decoded.vehicle_effects.seed == source.vehicle_effects.seed)
            testing.expect(t, decoded.tweak.atmosphere.world_minutes == source.tweak.atmosphere.world_minutes)
            testing.expect(t, decoded.mouse_fur == .Silver)
            testing.expect(t, decoded.mouse_pattern == .Dorsal_Stripe)
            testing.expect(t, decoded.vehicle_paint_layers[0][0] == 17)
            testing.expect(t, decoded.vehicle_paint_layers[2][VEHICLE_PAINT_TEXTURE_BYTE_COUNT - 1] == 231)

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

        v2_payload, v2_payload_ok := fixture_codec_test_v2_payload(t)
        testing.expect(t, v2_payload_ok)
        if v2_payload_ok {
            v2_container, v2_container_error, v2_container_ok := fixture_file.fixture_container_encode(
                v2_payload,
                fixture_v0002.FIXTURE_SCHEMA_VERSION,
                alloc = context.allocator,
            )
            testing.expect(t, v2_container_ok && v2_container_error.kind == .None)
            delete(v2_payload)
            if v2_container_ok {
                v2_snapshot := fixture_codec_test_copy(v2_container)
                v2_result, v2_error, v2_ok := fixture_codec_decode(v2_container, context.allocator)
                v2_result_again, v2_error_again, v2_ok_again := fixture_codec_decode(v2_container, context.allocator)
                testing.expect(t, v2_ok && v2_error.kind == .None)
                testing.expect(t, v2_ok_again && v2_error_again.kind == .None)
                if v2_ok && v2_ok_again {
                    testing.expect(t, v2_result.fixture.occupant == .On_Foot)
                    testing.expect(t, v2_result.fixture.pilot.mode == .Driving)
                    testing.expect(t, v2_result.fixture.aircraft.active == .Libellula_Mk2)
                    testing.expect(t, v2_result.fixture.structure_selected == 731)
                    testing.expect(t, v2_result.fixture.vehicle_showcase_target == "codec-v2-target")
                    testing.expect(t, v2_result.fixture.active_lab_scene == "codec-v2-lab")
                    testing.expect(t, v2_result.fixture.architecture_city_plan.lamp_count == 1)
                    testing.expect(t, len(v2_result.fixture.architecture_city_plan.lamps) == 1)
                    testing.expect(t, v2_result.fixture.architecture_city_plan.lamps[0].x == 73)
                    testing.expect(t, v2_result.fixture.architecture_city_plan.lamps[0].z == -37)

                    v2_encoded, v2_encode_error, v2_encoded_ok := fixture_codec_encode(
                        v2_result.fixture,
                        context.allocator,
                    )
                    v2_encoded_again, v2_encode_error_again, v2_encoded_again_ok := fixture_codec_encode(
                        v2_result_again.fixture,
                        context.allocator,
                    )
                    testing.expect(t, v2_encoded_ok && v2_encode_error.kind == .None)
                    testing.expect(t, v2_encoded_again_ok && v2_encode_error_again.kind == .None)
                    if v2_encoded_ok && v2_encoded_again_ok {
                        v2_encoded_view, v2_encoded_view_error, v2_encoded_view_ok :=
                            fixture_file.fixture_container_decode(v2_encoded)
                        testing.expect(t, v2_encoded_view_ok && v2_encoded_view_error.kind == .None)
                        testing.expect(t, v2_encoded_view.schema_version == u32(FIXTURE_SCHEMA_VERSION))
                        testing.expect(t, fixture_codec_test_bytes_equal(v2_encoded, v2_encoded_again))
                    }
                    if v2_encoded_ok do delete(v2_encoded)
                    if v2_encoded_again_ok do delete(v2_encoded_again)
                    fixture_codec_error_dispose(&v2_encode_error)
                    fixture_codec_error_dispose(&v2_encode_error)
                    fixture_codec_error_dispose(&v2_encode_error_again)
                    fixture_codec_error_dispose(&v2_encode_error_again)

                    v2_lamps := cast(^runtime.Raw_Dynamic_Array)(&v2_result.fixture.architecture_city_plan.lamps)
                    testing.expect(t, v2_lamps.allocator.data == rawptr(v2_result.arena))
                    previous_v2_lamp_length := len(v2_result.fixture.architecture_city_plan.lamps)
                    append(&v2_result.fixture.architecture_city_plan.lamps, architecture.City_Lamp{x = 9003})
                    testing.expect(
                        t,
                        len(v2_result.fixture.architecture_city_plan.lamps) == previous_v2_lamp_length + 1,
                    )
                    testing.expect(
                        t,
                        v2_result.fixture.architecture_city_plan.lamps[previous_v2_lamp_length].x == 9003,
                    )
                }
                testing.expect(t, fixture_codec_test_bytes_equal(v2_snapshot, v2_container))
                fixture_codec_error_dispose(&v2_error)
                fixture_codec_error_dispose(&v2_error)
                fixture_codec_error_dispose(&v2_error_again)
                fixture_codec_error_dispose(&v2_error_again)
                fixture_migration_result_dispose(&v2_result)
                fixture_migration_result_dispose(&v2_result)
                fixture_migration_result_dispose(&v2_result_again)
                fixture_migration_result_dispose(&v2_result_again)
                testing.expect(t, fixture_migration_result_empty(&v2_result))
                testing.expect(t, fixture_migration_result_empty(&v2_result_again))
                delete(v2_snapshot)
                delete(v2_container)
            }
        }

        v1_payload, v1_payload_ok := fixture_migration_v0002_to_v0003_test_v1_payload(t)
        testing.expect(t, v1_payload_ok)
        if v1_payload_ok {
            v1_container, v1_container_error, v1_container_ok := fixture_file.fixture_container_encode(
                v1_payload,
                1,
                alloc = context.allocator,
            )
            testing.expect(t, v1_container_ok)
            testing.expect(t, v1_container_error.kind == .None)
            delete(v1_payload)
            if v1_container_ok {
                v1_snapshot := fixture_codec_test_copy(v1_container)
                v1_view, v1_view_error, v1_view_ok := fixture_file.fixture_container_decode(v1_container)
                testing.expect(t, v1_view_ok && v1_view_error.kind == .None)
                testing.expect(t, v1_view.schema_version == 1)

                v1_result, v1_error, v1_ok := fixture_codec_decode(v1_container, context.allocator)
                v1_result_again, v1_error_again, v1_ok_again := fixture_codec_decode(v1_container, context.allocator)
                testing.expect(t, v1_ok && v1_ok_again)
                testing.expect(t, v1_error.kind == .None && v1_error_again.kind == .None)
                if v1_ok && v1_ok_again {
                    v1_fixture := v1_result.fixture
                    testing.expect(t, v1_fixture.project.sea_level == f32(12.75))
                    testing.expect(t, v1_fixture.project.revision == 77)
                    testing.expect(t, v1_fixture.project.structure_count == 1)
                    testing.expect(t, len(v1_fixture.project.structures) == 1)
                    testing.expect(t, v1_fixture.project.structures[0].id == 0x1111)
                    testing.expect(t, v1_fixture.architecture_city_plan.count == 1)
                    testing.expect(t, len(v1_fixture.architecture_city_plan.structures) == 1)
                    testing.expect(t, len(v1_fixture.architecture_city_plan.parcels) == 1)
                    testing.expect(t, len(v1_fixture.architecture_city_plan.alleys) == 1)
                    testing.expect(t, len(v1_fixture.architecture_city_plan.lamps) == 1)
                    testing.expect(t, v1_fixture.farm_count == 1)
                    testing.expect(t, v1_fixture.farms[0].plan.width == 25)
                    testing.expect(t, v1_fixture.farms[0].plan.height == 19)
                    testing.expect(t, v1_fixture.farms[0].scale_x == 1)
                    testing.expect(t, v1_fixture.farms[0].scale_z == 1)
                    testing.expect(t, v1_fixture.vehicle_showcase_target == "historical-target")
                    testing.expect(t, v1_fixture.active_lab_scene == "historical-lab")
                    testing.expect(t, v1_fixture.story_state.quest.definition_id == "two-island-story")
                    testing.expect(t, v1_fixture.story_state.quest.revision == 1)
                    testing.expect(t, v1_fixture.tracked_quest_node == quest.no_node)
                    testing.expect(t, !v1_fixture.quest_tracking_suppressed)
                    testing.expect(t, v1_fixture.quest_tracking_revision == 1)
                    testing.expect(t, v1_fixture.occupant == .On_Foot)
                    testing.expect(t, v1_fixture.pilot.mode == .Driving)
                    testing.expect(t, v1_fixture.aircraft.active == .Libellula_Mk2)
                    v1_lamps := cast(^runtime.Raw_Dynamic_Array)(&v1_fixture.architecture_city_plan.lamps)
                    testing.expect(t, v1_lamps.allocator.data == rawptr(v1_result.arena))

                    v1_encoded, v1_encode_error, v1_encoded_ok := fixture_codec_encode(
                        v1_result.fixture,
                        context.allocator,
                    )
                    v1_encoded_again, v1_encode_error_again, v1_encoded_again_ok := fixture_codec_encode(
                        v1_result_again.fixture,
                        context.allocator,
                    )
                    testing.expect(t, v1_encoded_ok && v1_encoded_again_ok)
                    testing.expect(t, v1_encode_error.kind == .None && v1_encode_error_again.kind == .None)
                    if v1_encoded_ok && v1_encoded_again_ok {
                        v1_encoded_view, v1_encoded_view_error, v1_encoded_view_ok :=
                            fixture_file.fixture_container_decode(v1_encoded)
                        testing.expect(t, v1_encoded_view_ok && v1_encoded_view_error.kind == .None)
                        testing.expect(t, v1_encoded_view.schema_version == u32(FIXTURE_SCHEMA_VERSION))
                        testing.expect(t, fixture_codec_test_bytes_equal(v1_encoded, v1_encoded_again))
                    }
                    if v1_encoded_ok do delete(v1_encoded)
                    if v1_encoded_again_ok do delete(v1_encoded_again)
                    fixture_codec_error_dispose(&v1_encode_error)
                    fixture_codec_error_dispose(&v1_encode_error_again)
                    fixture_codec_error_dispose(&v1_encode_error)
                    fixture_codec_error_dispose(&v1_encode_error_again)

                    previous_v1_lamp_length := len(v1_fixture.architecture_city_plan.lamps)
                    append(&v1_fixture.architecture_city_plan.lamps, architecture.City_Lamp{x = 9002})
                    testing.expect(t, len(v1_fixture.architecture_city_plan.lamps) == previous_v1_lamp_length + 1)
                    testing.expect(t, v1_fixture.architecture_city_plan.lamps[previous_v1_lamp_length].x == 9002)
                }
                testing.expect(t, fixture_codec_test_bytes_equal(v1_snapshot, v1_container))
                fixture_codec_error_dispose(&v1_error)
                fixture_codec_error_dispose(&v1_error)
                fixture_codec_error_dispose(&v1_error_again)
                fixture_codec_error_dispose(&v1_error_again)
                fixture_migration_result_dispose(&v1_result)
                fixture_migration_result_dispose(&v1_result)
                fixture_migration_result_dispose(&v1_result_again)
                fixture_migration_result_dispose(&v1_result_again)
                delete(v1_snapshot)
                delete(v1_container)
            }
        }

        nil_allocator: mem.Allocator
        nil_result, nil_error, nil_ok := fixture_codec_decode(first, nil_allocator)
        testing.expect(t, !nil_ok && nil_error.kind == .Invalid_Argument)
        fixture_codec_test_expect_empty(t, &nil_result, &nil_error)

        for length in 0 ..< fixture_file.Fixture_Container_Header_Size {
            truncated_result, truncated_error, truncated_ok := fixture_codec_decode(first[:length], context.allocator)
            testing.expect(t, !truncated_ok)
            testing.expect(t, truncated_error.kind == .Container_Decode)
            testing.expect(t, truncated_error.container.kind == .Truncated)
            fixture_codec_test_expect_empty(t, &truncated_result, &truncated_error)
        }

        corrupt := fixture_codec_test_copy(first)
        corrupt[fixture_file.Fixture_Container_Header_Size] = corrupt[fixture_file.Fixture_Container_Header_Size] ~ 1
        corrupt_result, corrupt_error, corrupt_ok := fixture_codec_decode(corrupt, context.allocator)
        testing.expect(t, !corrupt_ok)
        testing.expect(t, corrupt_error.kind == .Container_Decode)
        testing.expect(t, corrupt_error.container.kind == .Checksum_Mismatch)
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
