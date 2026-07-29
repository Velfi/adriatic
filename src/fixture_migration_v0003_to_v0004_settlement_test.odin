package main

import buildings "../packages/buildings"
import fixture_v0003 "../packages/fixture_history/v0003"
import roads "../packages/roads"
import terrain "../packages/terrain"
import "base:runtime"
import "core:mem"
import "core:testing"

when ODIN_TEST {
    fixture_migration_v0003_settlement_test_call :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
    ) -> Fixture_Migration_Error {
        state := fixture_migration_test_allocator_state {
            base    = runtime.default_allocator(),
            fail_at = 0,
        }
        error := fixture_migrate_v0003_to_v0004(historical^, tentative, fixture_migration_test_allocator(&state))
        testing.expect(t, state.allocation_calls == 0 && state.outstanding == 0)
        return error
    }

    fixture_migration_v0003_settlement_test_seed_stats :: proc(stats: ^fixture_v0003.History_Type_0135, index: int) {
        stats^ = {
            count  = index,
            min    = f32(index) + 0.1,
            p10    = f32(index) + 0.2,
            median = f32(index) + 0.3,
            mean   = f32(index) + 0.4,
            p90    = f32(index) + 0.5,
            max    = f32(index) + 0.6,
        }
    }

    fixture_migration_v0003_settlement_test_prepare :: proc(historical: ^fixture_v0003.Fixture, tentative: ^Fixture) {
        fixture_migration_v0003_root_test_prepare(historical, tentative)

        plan_bytes := mem.slice_ptr(cast([^]u8)&tentative.settlement_plan, size_of(tentative.settlement_plan))
        for &byte in plan_bytes do byte = 0xa5

        plan := &historical.settlement_plan
        plan.request.region = .Aegean
        plan.request.scale = .Village
        plan.request.seed = 0x12345678
        plan.request.center = {12.5, -9.25}
        plan.request.radius = 88
        plan.village_reason = .Upland_Pastoral
        plan.neighborhood_count = len(plan.neighborhoods)
        plan.macro_cell_count = len(plan.macro_cells)
        plan.route_count = len(plan.routes)
        plan.block_count = len(plan.blocks)
        plan.site_count = len(plan.sites)
        plan.rejected_site_count = len(plan.rejected_sites)
        plan.decorative_foliage_count = len(plan.decorative_foliage)
        plan.terrain_edit_count = len(plan.terrain_edits)
        plan.ordinary_purpose_count = len(plan.ordinary_purposes)
        plan.valid = true
        tentative.settlement_plan.neighborhood_count = plan.neighborhood_count
        tentative.settlement_plan.macro_cell_count = plan.macro_cell_count
        tentative.settlement_plan.route_count = plan.route_count
        tentative.settlement_plan.block_count = plan.block_count
        tentative.settlement_plan.site_count = plan.site_count
        tentative.settlement_plan.rejected_site_count = plan.rejected_site_count
        tentative.settlement_plan.decorative_foliage_count = plan.decorative_foliage_count
        tentative.settlement_plan.terrain_edit_count = plan.terrain_edit_count
        tentative.settlement_plan.ordinary_purpose_count = plan.ordinary_purpose_count
        tentative.settlement_plan.request.region = .Adriatic
        tentative.settlement_plan.request.scale = .City
        tentative.settlement_plan.request.seed = 0xfeedbeef
        tentative.settlement_plan.request.center = {-71, 72}
        tentative.settlement_plan.request.radius = 73
        tentative.settlement_plan.village_reason = .Route_Stop
        tentative.settlement_plan.neighborhoods[0].radius = 74
        tentative.settlement_plan.blocks[0].area = 75
        tentative.settlement_plan.sites[0].density = 76
        tentative.settlement_plan.metrics.route_length.mean = 77
        tentative.settlement_plan.metrics.network_density = 78
        tentative.settlement_plan.metrics.attached_share = 79
        tentative.settlement_plan.valid = false

        for &neighborhood, index in plan.neighborhoods {
            neighborhood.center = {f32(index), f32(-index)}
            neighborhood.radius = f32(index) + 1
            neighborhood.density = f32(index) + 2
            neighborhood.age = f32(index) + 3
            neighborhood.suitability = f32(index) + 4
            neighborhood.tissue = fixture_v0003.History_Type_0141(index % 9)
        }
        for &cell, index in plan.macro_cells {
            cell.center = {f32(index) + 5, f32(index) + 6}
            cell.radius = f32(index) + 7
            cell.density = f32(index) + 8
            cell.age = f32(index) + 9
            cell.suitability = f32(index) + 10
            cell.tissue = fixture_v0003.History_Type_0141(index % 9)
        }
        for &route, index in plan.routes {
            route.geometry.count = index % 13
            for &point, point_index in route.geometry.points {
                point = {f32(index * 100 + point_index), f32(-index * 100 - point_index)}
            }
            route.class = fixture_v0003.History_Type_0134(index % 8)
            route.width = f32(index) + 0.25
            route.shoulder = f32(index) + 0.5
            route.pavement = fixture_v0003.History_Type_0069(index % 4)
            route.required = index % 2 == 0
            route.drivable = index % 3 == 0
            route.average_grade = f32(index) + 0.75
            route.maximum_grade = f32(index) + 1.25
        }
        for &block, index in plan.blocks {
            block.center = {f32(index), f32(index + 1)}
            block.corner_count = index % 9
            for &corner, corner_index in block.corners {
                corner = {f32(index * 10 + corner_index), f32(index * 20 + corner_index)}
            }
            block.short_side = f32(index) + 2
            block.long_side = f32(index) + 3
            block.area = f32(index) + 4
            block.irregularity = f32(index) + 5
            block.tissue = fixture_v0003.History_Type_0141(index % 9)
        }
        for &site, index in plan.sites {
            site.structure.kind = fixture_v0003.History_Type_0085(index % 8)
            site.structure.building.archetype = fixture_v0003.History_Type_0014(index % 18)
            site.structure.building.purpose = fixture_v0003.History_Type_0017(index % 8)
            site.structure.building.region = fixture_v0003.History_Type_0018(index % 2)
            site.structure.building.landmark_kind = fixture_v0003.History_Type_0016(index % 9)
            site.kind = fixture_v0003.History_Type_0138(index % 4)
            site.tissue = fixture_v0003.History_Type_0141(index % 9)
            site.landmark_kind = fixture_v0003.History_Type_0126(index % 8)
            site.purpose = fixture_v0003.History_Type_0125(index % 8)
        }
        for &site, index in plan.rejected_sites {
            site.structure.kind = fixture_v0003.History_Type_0085(index % 8)
            site.structure.building.archetype = fixture_v0003.History_Type_0014(index % 18)
            site.structure.building.purpose = fixture_v0003.History_Type_0017(index % 8)
            site.structure.building.region = fixture_v0003.History_Type_0018(index % 2)
            site.structure.building.landmark_kind = fixture_v0003.History_Type_0016(index % 9)
            site.kind = fixture_v0003.History_Type_0138(index % 4)
            site.tissue = fixture_v0003.History_Type_0141(index % 9)
            site.landmark_kind = fixture_v0003.History_Type_0126(index % 8)
            site.purpose = fixture_v0003.History_Type_0125(index % 8)
        }
        for &structure, index in plan.decorative_foliage {
            structure.kind = fixture_v0003.History_Type_0085(index % 8)
            structure.building.archetype = fixture_v0003.History_Type_0014(index % 18)
            structure.building.purpose = fixture_v0003.History_Type_0017(index % 8)
            structure.building.region = fixture_v0003.History_Type_0018(index % 2)
            structure.building.landmark_kind = fixture_v0003.History_Type_0016(index % 9)
        }
        for &edit, index in plan.terrain_edits {
            edit.kind = fixture_v0003.History_Type_0140(index % 5)
        }
        for &purpose, index in plan.ordinary_purposes {
            purpose = fixture_v0003.History_Type_0125(index % 8)
        }

        metrics := &plan.metrics
        fixed_stats := [?]^fixture_v0003.History_Type_0135 {
            &metrics.route_length,
            &metrics.route_width,
            &metrics.route_grade,
            &metrics.intersection_spacing,
            &metrics.block_short_side,
            &metrics.block_long_side,
            &metrics.block_area,
            &metrics.block_aspect,
            &metrics.block_irregularity,
            &metrics.parcel_frontage,
            &metrics.parcel_depth,
            &metrics.building_height,
            &metrics.building_footprint,
            &metrics.building_floors,
        }
        for stats, index in fixed_stats {
            fixture_migration_v0003_settlement_test_seed_stats(stats, index + 1)
        }
        for &stats, index in metrics.route_length_by_class {
            fixture_migration_v0003_settlement_test_seed_stats(&stats, index + 20)
        }
        for &stats, index in metrics.route_width_by_class {
            fixture_migration_v0003_settlement_test_seed_stats(&stats, index + 40)
        }
        metrics.network_density = 91
        metrics.attached_share = 92
        metrics.density_band_count = {93, 94, 95}
        metrics.wide_route_share = 96
        metrics.minor_route_share = 97
        metrics.fabric_aspect_ratio = 98
        metrics.fabric_quadrants = 99
        metrics.landmark_count = 100
        metrics.park_count = 101
        metrics.rejected_count = 102
        metrics.cut_volume = 103
        metrics.fill_volume = 104
    }

    fixture_migration_v0003_settlement_test_copy_route :: proc(
        historical: fixture_v0003.History_Type_0130,
        tentative: ^Settlement_Planned_Route,
    ) {
        tentative.geometry.points = historical.geometry.points
        tentative.geometry.count = historical.geometry.count
        tentative.class = Settlement_Route_Class(int(historical.class))
        tentative.width = historical.width
        tentative.shoulder = historical.shoulder
        tentative.pavement = roads.Pavement(int(historical.pavement))
        tentative.required = historical.required
        tentative.drivable = historical.drivable
        tentative.average_grade = historical.average_grade
        tentative.maximum_grade = historical.maximum_grade
    }

    fixture_migration_v0003_settlement_test_oracle :: proc(
        #by_ptr historical: fixture_v0003.Fixture,
        expected: ^Settlement_Plan,
    ) {
        for site, index in historical.settlement_plan.sites {
            expected.sites[index].structure.building.archetype = buildings.Archetype(
                int(site.structure.building.archetype),
            )
            expected.sites[index].structure.building.landmark_kind = buildings.Landmark_Kind(
                int(site.structure.building.landmark_kind),
            )
            expected.sites[index].structure.entrance_side = .Front
        }
        for site, index in historical.settlement_plan.rejected_sites {
            expected.rejected_sites[index].structure.building.archetype = buildings.Archetype(
                int(site.structure.building.archetype),
            )
            expected.rejected_sites[index].structure.building.landmark_kind = buildings.Landmark_Kind(
                int(site.structure.building.landmark_kind),
            )
            expected.rejected_sites[index].structure.entrance_side = .Front
        }
        for structure, index in historical.settlement_plan.decorative_foliage {
            expected.decorative_foliage[index].building.archetype = buildings.Archetype(
                int(structure.building.archetype),
            )
            expected.decorative_foliage[index].building.landmark_kind = buildings.Landmark_Kind(
                int(structure.building.landmark_kind),
            )
            expected.decorative_foliage[index].entrance_side = terrain.Entrance_Side.Front
        }
        failure := int(historical.settlement_plan.acceptance_failure)
        if failure >= 5 do failure += 1
        expected.acceptance_failure = Settlement_Acceptance_Failure(failure)

        expected.request.density = 0
        expected.brush_pieces = {}
        expected.brush_piece_count = 0
        expected.next_brush_component_id = 0
        expected.program = {}
        expected.activity_points = {}
        expected.activity_point_count = 0
        expected.inhabitants = {}
        expected.inhabitant_count = 0
        expected.route_piece_ids = {}
        expected.access_routes_truncated = false
        expected.access_required_count = 0
        expected.access_connected_count = 0
        expected.access_max_degree = 0
        expected.access_shallow_junctions = 0
        expected.access_hairpin_bends = 0
        expected.access_crossings = 0
        expected.access_unsplit_junctions = 0
        expected.access_bad_door_approaches = 0
        expected.access_bad_road_approaches = 0
        expected.access_stair_routes = 0
        expected.access_excessive_grades = 0
        expected.access_shared_segments = 0
        expected.access_widened_segments = 0
        expected.access_max_shared_width_step = 0
        expected.access_orphan_endpoints = 0
        expected.road_badness_sum = 0
        expected.road_badness_count = 0
        expected.site_piece_ids = {}
        expected.metrics.dead_end_frontage = {}
        expected.metrics.road_badness = 0
        for route, index in historical.settlement_plan.routes {
            fixture_migration_v0003_settlement_test_copy_route(route, &expected.routes[index])
        }
        for index in len(historical.settlement_plan.routes) ..< len(expected.routes) {
            expected.routes[index] = {}
        }
    }

    fixture_migration_v0003_settlement_test_expect_defaults :: proc(t: ^testing.T, plan: ^Settlement_Plan) {
        testing.expect(
            t,
            plan.request.density == 0 &&
            plan.brush_piece_count == 0 &&
            plan.next_brush_component_id == 0 &&
            plan.activity_point_count == 0 &&
            plan.inhabitant_count == 0 &&
            !plan.access_routes_truncated &&
            plan.access_required_count == 0 &&
            plan.access_connected_count == 0 &&
            plan.access_max_degree == 0 &&
            plan.access_shallow_junctions == 0 &&
            plan.access_hairpin_bends == 0 &&
            plan.access_crossings == 0 &&
            plan.access_unsplit_junctions == 0 &&
            plan.access_bad_door_approaches == 0 &&
            plan.access_bad_road_approaches == 0 &&
            plan.access_stair_routes == 0 &&
            plan.access_excessive_grades == 0 &&
            plan.access_shared_segments == 0 &&
            plan.access_widened_segments == 0 &&
            plan.access_max_shared_width_step == 0 &&
            plan.access_orphan_endpoints == 0 &&
            plan.road_badness_sum == 0 &&
            plan.road_badness_count == 0 &&
            plan.metrics.road_badness == 0,
        )
        testing.expect(t, plan.brush_pieces == [SETTLEMENT_BRUSH_PIECE_CAPACITY]Settlement_Brush_Piece{})
        testing.expect(t, plan.program == Settlement_Program{})
        testing.expect(t, plan.activity_points == [SETTLEMENT_ACTIVITY_CAPACITY]Settlement_Activity_Point{})
        testing.expect(t, plan.inhabitants == [SETTLEMENT_INHABITANT_CAPACITY]Settlement_Inhabitant{})
        testing.expect(t, plan.route_piece_ids == [SETTLEMENT_PLANNED_ROUTE_CAPACITY]u32{})
        testing.expect(t, plan.site_piece_ids == [SETTLEMENT_SITE_CAPACITY]u32{})
        testing.expect(t, plan.metrics.dead_end_frontage == Settlement_Scalar_Stats{})
    }

    fixture_migration_v0003_settlement_test_expect_atomic_failure :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
        expected_id: string,
    ) {
        snapshot, snapshot_ok := fixture_migration_structural_snapshot(tentative, runtime.default_allocator())
        testing.expect(t, snapshot_ok)
        if !snapshot_ok do return
        error := fixture_migration_v0003_settlement_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .Invalid_Source && error.change_id == expected_id)
        testing.expect(t, fixture_migration_structural_snapshot_matches(snapshot, tentative))
        fixture_migration_structural_snapshot_dispose(&snapshot)
        fixture_migration_structural_snapshot_dispose(&snapshot)
    }

    fixture_migration_v0003_settlement_test_expect_preflight_failure :: proc(
        t: ^testing.T,
        historical: ^fixture_v0003.Fixture,
        tentative: ^Fixture,
    ) {
        error := fixture_migration_v0003_settlement_preflight(historical^, tentative)
        testing.expect(t, error.kind == .Invalid_Source && error.change_id == FIXTURE_MIGRATION_V0003_SETTLEMENT_ID)
    }

    @(test)
    fixture_migration_v0003_to_v0004_settlement_routes_defaults_and_failures :: proc(t: ^testing.T) {
        context.allocator = context.temp_allocator
        runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()

        historical, tentative, made := fixture_migration_v0003_structural_test_make(t)
        if !made {
            fixture_migration_v0003_structural_test_destroy(historical, tentative)
            return
        }
        defer fixture_migration_v0003_structural_test_destroy(historical, tentative)

        fixture_migration_v0003_settlement_test_prepare(historical, tentative)
        before := tentative.settlement_plan
        expected := before
        fixture_migration_v0003_settlement_test_oracle(historical^, &expected)
        error := fixture_migration_v0003_settlement_test_call(t, historical, tentative)
        testing.expect(t, error.kind == .None && error.change_id == "")
        expected_bytes := mem.slice_ptr(cast([^]u8)&expected, size_of(expected))
        actual_bytes := mem.slice_ptr(cast([^]u8)&tentative.settlement_plan, size_of(tentative.settlement_plan))
        testing.expect(t, fixture_migration_test_bytes_equal(actual_bytes, expected_bytes))
        testing.expect(
            t,
            tentative.settlement_plan.request.density == 0 &&
            tentative.settlement_plan.request.seed == 0xfeedbeef &&
            tentative.settlement_plan.request.center == [2]f32{-71, 72} &&
            tentative.settlement_plan.request.radius == 73 &&
            tentative.settlement_plan.neighborhoods[0].radius == 74 &&
            tentative.settlement_plan.blocks[0].area == 75 &&
            tentative.settlement_plan.sites[0].density == 76 &&
            tentative.settlement_plan.metrics.route_length.mean == 77 &&
            tentative.settlement_plan.metrics.network_density == 78 &&
            tentative.settlement_plan.metrics.attached_share == 79 &&
            !tentative.settlement_plan.valid,
        )
        testing.expect(
            t,
            tentative.settlement_plan.request.region == before.request.region &&
            tentative.settlement_plan.request.scale == before.request.scale &&
            tentative.settlement_plan.village_reason == before.village_reason &&
            tentative.settlement_plan.neighborhood_count == before.neighborhood_count &&
            tentative.settlement_plan.macro_cell_count == before.macro_cell_count &&
            tentative.settlement_plan.route_count == before.route_count &&
            tentative.settlement_plan.block_count == before.block_count &&
            tentative.settlement_plan.site_count == before.site_count &&
            tentative.settlement_plan.rejected_site_count == before.rejected_site_count &&
            tentative.settlement_plan.decorative_foliage_count == before.decorative_foliage_count &&
            tentative.settlement_plan.terrain_edit_count == before.terrain_edit_count &&
            tentative.settlement_plan.ordinary_purpose_count == before.ordinary_purpose_count,
        )
        fixture_migration_v0003_settlement_test_expect_defaults(t, &tentative.settlement_plan)
        for index in 0 ..< 48 {
            testing.expect(
                t,
                tentative.settlement_plan.routes[index].geometry.points ==
                    historical.settlement_plan.routes[index].geometry.points &&
                tentative.settlement_plan.routes[index].geometry.count ==
                    historical.settlement_plan.routes[index].geometry.count &&
                int(tentative.settlement_plan.routes[index].class) ==
                    int(historical.settlement_plan.routes[index].class) &&
                tentative.settlement_plan.routes[index].width == historical.settlement_plan.routes[index].width &&
                tentative.settlement_plan.routes[index].shoulder ==
                    historical.settlement_plan.routes[index].shoulder &&
                int(tentative.settlement_plan.routes[index].pavement) ==
                    int(historical.settlement_plan.routes[index].pavement) &&
                tentative.settlement_plan.routes[index].required ==
                    historical.settlement_plan.routes[index].required &&
                tentative.settlement_plan.routes[index].drivable ==
                    historical.settlement_plan.routes[index].drivable &&
                tentative.settlement_plan.routes[index].average_grade ==
                    historical.settlement_plan.routes[index].average_grade &&
                tentative.settlement_plan.routes[index].maximum_grade ==
                    historical.settlement_plan.routes[index].maximum_grade,
            )
        }
        zero_route := Settlement_Planned_Route{}
        zero_route_bytes := mem.slice_ptr(cast([^]u8)&zero_route, size_of(zero_route))
        for index in 48 ..< len(tentative.settlement_plan.routes) {
            route_bytes := mem.slice_ptr(
                cast([^]u8)&tentative.settlement_plan.routes[index],
                size_of(tentative.settlement_plan.routes[index]),
            )
            testing.expect(t, fixture_migration_test_bytes_equal(route_bytes, zero_route_bytes))
        }

        fixture_migration_v0003_settlement_test_prepare(historical, tentative)
        count_fields := [?]^int {
            &historical.settlement_plan.neighborhood_count,
            &historical.settlement_plan.macro_cell_count,
            &historical.settlement_plan.route_count,
            &historical.settlement_plan.block_count,
            &historical.settlement_plan.site_count,
            &historical.settlement_plan.rejected_site_count,
            &historical.settlement_plan.decorative_foliage_count,
            &historical.settlement_plan.terrain_edit_count,
            &historical.settlement_plan.ordinary_purpose_count,
        }
        capacities := [?]int{96, 192, 48, 128, 256, 32, 32, 192, 256}
        for count, index in count_fields {
            count^ = -1
            fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
            count^ = capacities[index] + 1
            fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
            count^ = capacities[index]
        }
        historical.settlement_plan.route_count = 0
        tentative.settlement_plan.route_count = 0
        for &route in historical.settlement_plan.routes {
            route.geometry.count = -1
            fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
            route.geometry.count = 13
            fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
            route.geometry.count = 12
        }
        historical.settlement_plan.route_count = len(historical.settlement_plan.routes)
        tentative.settlement_plan.route_count = historical.settlement_plan.route_count
        historical.settlement_plan.block_count = 0
        tentative.settlement_plan.block_count = 0
        for &block in historical.settlement_plan.blocks {
            block.corner_count = -1
            fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
            block.corner_count = 9
            fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
            block.corner_count = 8
        }
        historical.settlement_plan.block_count = len(historical.settlement_plan.blocks)
        tentative.settlement_plan.block_count = historical.settlement_plan.block_count

        metrics := &historical.settlement_plan.metrics
        fixed_count_fields := [?]^int {
            &metrics.route_length.count,
            &metrics.route_width.count,
            &metrics.route_grade.count,
            &metrics.intersection_spacing.count,
            &metrics.block_short_side.count,
            &metrics.block_long_side.count,
            &metrics.block_area.count,
            &metrics.block_aspect.count,
            &metrics.block_irregularity.count,
            &metrics.parcel_frontage.count,
            &metrics.parcel_depth.count,
            &metrics.building_height.count,
            &metrics.building_footprint.count,
            &metrics.building_floors.count,
            &metrics.density_band_count[0],
            &metrics.density_band_count[1],
            &metrics.density_band_count[2],
            &metrics.fabric_quadrants,
            &metrics.landmark_count,
            &metrics.park_count,
            &metrics.rejected_count,
        }
        for count in fixed_count_fields {
            old_count := count^
            count^ = -1
            fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
            count^ = old_count
        }
        for &stats in metrics.route_length_by_class {
            old_count := stats.count
            stats.count = -1
            fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
            stats.count = old_count
        }
        for &stats in metrics.route_width_by_class {
            old_count := stats.count
            stats.count = -1
            fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
            stats.count = old_count
        }

        historical.settlement_plan.request.region = fixture_v0003.History_Type_0131(-1)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.request.region = .Aegean
        historical.settlement_plan.request.scale = fixture_v0003.History_Type_0136(3)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.request.scale = .Village
        historical.settlement_plan.village_reason = fixture_v0003.History_Type_0146(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.village_reason = .Upland_Pastoral
        historical.settlement_plan.neighborhood_count = 0
        tentative.settlement_plan.neighborhood_count = 0
        historical.settlement_plan.neighborhoods[95].tissue = fixture_v0003.History_Type_0141(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.neighborhoods[95].tissue = .Church_Cluster
        historical.settlement_plan.neighborhood_count = len(historical.settlement_plan.neighborhoods)
        tentative.settlement_plan.neighborhood_count = historical.settlement_plan.neighborhood_count
        historical.settlement_plan.macro_cell_count = 0
        tentative.settlement_plan.macro_cell_count = 0
        historical.settlement_plan.macro_cells[191].tissue = fixture_v0003.History_Type_0141(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.macro_cells[191].tissue = .Church_Cluster
        historical.settlement_plan.macro_cell_count = len(historical.settlement_plan.macro_cells)
        tentative.settlement_plan.macro_cell_count = historical.settlement_plan.macro_cell_count
        historical.settlement_plan.route_count = 0
        tentative.settlement_plan.route_count = 0
        historical.settlement_plan.routes[47].class = fixture_v0003.History_Type_0134(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.routes[47].class = .Ridge
        historical.settlement_plan.routes[47].pavement = fixture_v0003.History_Type_0069(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.routes[47].pavement = .Dirt
        historical.settlement_plan.route_count = len(historical.settlement_plan.routes)
        tentative.settlement_plan.route_count = historical.settlement_plan.route_count
        historical.settlement_plan.block_count = 0
        tentative.settlement_plan.block_count = 0
        historical.settlement_plan.blocks[127].tissue = fixture_v0003.History_Type_0141(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.blocks[127].tissue = .Church_Cluster
        historical.settlement_plan.block_count = len(historical.settlement_plan.blocks)
        tentative.settlement_plan.block_count = historical.settlement_plan.block_count
        historical.settlement_plan.site_count = 0
        tentative.settlement_plan.site_count = 0
        historical.settlement_plan.sites[255].kind = fixture_v0003.History_Type_0138(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.sites[255].kind = .Rejected
        historical.settlement_plan.sites[255].tissue = fixture_v0003.History_Type_0141(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.sites[255].tissue = .Church_Cluster
        historical.settlement_plan.sites[255].landmark_kind = fixture_v0003.History_Type_0126(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.sites[255].landmark_kind = .Cycladic_Bell
        historical.settlement_plan.sites[255].purpose = fixture_v0003.History_Type_0125(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.sites[255].purpose = .Storehouse
        historical.settlement_plan.sites[255].structure.kind = fixture_v0003.History_Type_0085(8)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.sites[255].structure.kind = .Architecture
        historical.settlement_plan.sites[255].structure.building.purpose = fixture_v0003.History_Type_0017(8)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.sites[255].structure.building.purpose = .Storehouse
        historical.settlement_plan.sites[255].structure.building.region = fixture_v0003.History_Type_0018(2)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.sites[255].structure.building.region = .Aegean
        historical.settlement_plan.site_count = len(historical.settlement_plan.sites)
        tentative.settlement_plan.site_count = historical.settlement_plan.site_count
        historical.settlement_plan.rejected_site_count = 0
        tentative.settlement_plan.rejected_site_count = 0
        historical.settlement_plan.rejected_sites[31].kind = fixture_v0003.History_Type_0138(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.rejected_sites[31].kind = .Rejected
        historical.settlement_plan.rejected_sites[31].tissue = fixture_v0003.History_Type_0141(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.rejected_sites[31].tissue = .Church_Cluster
        historical.settlement_plan.rejected_sites[31].landmark_kind = fixture_v0003.History_Type_0126(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.rejected_sites[31].landmark_kind = .Cycladic_Bell
        historical.settlement_plan.rejected_sites[31].purpose = fixture_v0003.History_Type_0125(255)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.rejected_sites[31].purpose = .Storehouse
        historical.settlement_plan.rejected_sites[31].structure.kind = fixture_v0003.History_Type_0085(8)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.rejected_sites[31].structure.kind = .Architecture
        historical.settlement_plan.rejected_sites[31].structure.building.purpose = fixture_v0003.History_Type_0017(8)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.rejected_sites[31].structure.building.purpose = .Storehouse
        historical.settlement_plan.rejected_sites[31].structure.building.region = fixture_v0003.History_Type_0018(2)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.rejected_sites[31].structure.building.region = .Aegean
        historical.settlement_plan.rejected_site_count = len(historical.settlement_plan.rejected_sites)
        tentative.settlement_plan.rejected_site_count = historical.settlement_plan.rejected_site_count
        historical.settlement_plan.decorative_foliage_count = 0
        tentative.settlement_plan.decorative_foliage_count = 0
        historical.settlement_plan.decorative_foliage[31].kind = fixture_v0003.History_Type_0085(8)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.decorative_foliage[31].kind = .Architecture
        historical.settlement_plan.decorative_foliage[31].building.purpose = fixture_v0003.History_Type_0017(8)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.decorative_foliage[31].building.purpose = .Storehouse
        historical.settlement_plan.decorative_foliage[31].building.region = fixture_v0003.History_Type_0018(2)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.decorative_foliage[31].building.region = .Aegean
        historical.settlement_plan.decorative_foliage_count = len(historical.settlement_plan.decorative_foliage)
        tentative.settlement_plan.decorative_foliage_count = historical.settlement_plan.decorative_foliage_count
        historical.settlement_plan.terrain_edit_count = 0
        tentative.settlement_plan.terrain_edit_count = 0
        historical.settlement_plan.terrain_edits[191].kind = fixture_v0003.History_Type_0140(5)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.terrain_edits[191].kind = .Retaining_Edge
        historical.settlement_plan.terrain_edit_count = len(historical.settlement_plan.terrain_edits)
        tentative.settlement_plan.terrain_edit_count = historical.settlement_plan.terrain_edit_count
        historical.settlement_plan.ordinary_purpose_count = 0
        tentative.settlement_plan.ordinary_purpose_count = 0
        historical.settlement_plan.ordinary_purposes[255] = fixture_v0003.History_Type_0125(8)
        fixture_migration_v0003_settlement_test_expect_preflight_failure(t, historical, tentative)
        historical.settlement_plan.ordinary_purposes[255] = .Storehouse
        historical.settlement_plan.ordinary_purpose_count = len(historical.settlement_plan.ordinary_purposes)
        tentative.settlement_plan.ordinary_purpose_count = historical.settlement_plan.ordinary_purpose_count

        testing.expect(
            t,
            len(historical.settlement_plan.routes) == 48 &&
            len(tentative.settlement_plan.routes) == 320 &&
            len(historical.settlement_plan.neighborhoods) == len(tentative.settlement_plan.neighborhoods) &&
            len(historical.settlement_plan.macro_cells) == len(tentative.settlement_plan.macro_cells) &&
            len(historical.settlement_plan.blocks) == len(tentative.settlement_plan.blocks) &&
            len(historical.settlement_plan.sites) == len(tentative.settlement_plan.sites) &&
            len(historical.settlement_plan.rejected_sites) == len(tentative.settlement_plan.rejected_sites) &&
            len(historical.settlement_plan.decorative_foliage) == len(tentative.settlement_plan.decorative_foliage) &&
            len(historical.settlement_plan.terrain_edits) == len(tentative.settlement_plan.terrain_edits) &&
            len(historical.settlement_plan.ordinary_purposes) == len(tentative.settlement_plan.ordinary_purposes),
        )

        fixture_migration_v0003_settlement_test_prepare(historical, tentative)
        historical.settlement_plan.routes[47].geometry.count = 13
        fixture_migration_v0003_settlement_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_SETTLEMENT_ID,
        )

        source_counts := [?]^int {
            &historical.settlement_plan.neighborhood_count,
            &historical.settlement_plan.macro_cell_count,
            &historical.settlement_plan.route_count,
            &historical.settlement_plan.block_count,
            &historical.settlement_plan.site_count,
            &historical.settlement_plan.rejected_site_count,
            &historical.settlement_plan.decorative_foliage_count,
            &historical.settlement_plan.terrain_edit_count,
            &historical.settlement_plan.ordinary_purpose_count,
        }
        destination_counts := [?]^int {
            &tentative.settlement_plan.neighborhood_count,
            &tentative.settlement_plan.macro_cell_count,
            &tentative.settlement_plan.route_count,
            &tentative.settlement_plan.block_count,
            &tentative.settlement_plan.site_count,
            &tentative.settlement_plan.rejected_site_count,
            &tentative.settlement_plan.decorative_foliage_count,
            &tentative.settlement_plan.terrain_edit_count,
            &tentative.settlement_plan.ordinary_purpose_count,
        }
        for index in 0 ..< len(source_counts) {
            fixture_migration_v0003_settlement_test_prepare(historical, tentative)
            destination_counts[index]^ = source_counts[index]^ - 1
            fixture_migration_v0003_settlement_test_expect_atomic_failure(
                t,
                historical,
                tentative,
                FIXTURE_MIGRATION_V0003_SETTLEMENT_ID,
            )
        }

        fixture_migration_v0003_settlement_test_prepare(historical, tentative)
        historical.aircraft.slots[7].kind = fixture_v0003.History_Type_0097(3)
        historical.settlement_plan.routes[47].geometry.count = 13
        fixture_migration_v0003_settlement_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_AIRCRAFT_ID,
        )
        fixture_migration_v0003_settlement_test_prepare(historical, tentative)
        historical.architecture_brush_radius = -1
        historical.settlement_plan.routes[47].geometry.count = 13
        fixture_migration_v0003_settlement_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_BRUSH_PRESET_ID,
        )
        fixture_migration_v0003_settlement_test_prepare(historical, tentative)
        historical.aircraft.count = 2
        historical.settlement_plan.routes[47].geometry.count = 13
        fixture_migration_v0003_settlement_test_expect_atomic_failure(
            t,
            historical,
            tentative,
            FIXTURE_MIGRATION_V0003_RONDINE_ID,
        )

        nil_error := fixture_migration_v0003_settlement_test_call(t, historical, nil)
        testing.expect(t, nil_error.kind == .Invalid_Argument && nil_error.change_id == "")
    }
}
