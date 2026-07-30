package boats

import "core:testing"

ocean_test_advance :: proc(traffic: ^Ocean_Traffic, seconds: f32) {
    steps := int(seconds * 10)
    for _ in 0 ..< steps do ocean_traffic_step(traffic, .1)
}

@(test)
ocean_ship_scale_matches_references :: proc(t: ^testing.T) {
    tanker := ocean_specifications(.Product_Tanker)
    cruise := ocean_specifications(.Cruise_Ship)
    testing.expect_value(t, tanker.length, f32(182.90))
    testing.expect_value(t, tanker.beam, f32(40.00))
    testing.expect_value(t, tanker.draft, f32(11.30))
    testing.expect_value(t, tanker.cruise_speed_mps, f32(7.46))
    testing.expect_value(t, cruise.length, f32(294.13))
    testing.expect_value(t, cruise.beam, f32(32.20))
    testing.expect_value(t, cruise.draft, f32(8.30))
    testing.expect_value(t, cruise.cruise_speed_mps, f32(12.86))
}

@(test)
ocean_traffic_waits_crosses_center_and_alternates :: proc(t: ^testing.T) {
    traffic := new_ocean_traffic()
    ocean_test_advance(&traffic, 89)
    testing.expect(t, !traffic.agent.active)
    ocean_test_advance(&traffic, 2)
    testing.expect(t, traffic.agent.active)
    testing.expect_value(t, traffic.agent.class, Ocean_Class.Product_Tanker)
    testing.expect(t, traffic.agent.position.x < -OCEAN_ROUTE_HALF_EXTENT + 10)

    ocean_test_advance(&traffic, OCEAN_ROUTE_HALF_EXTENT / 7.46 + 1)
    testing.expect(t, abs(traffic.agent.position.x) < 20)
    testing.expect(t, traffic.agent.wake_count > 40)
    testing.expect(t, traffic.agent.wake[0].age > 20)
    ocean_test_advance(&traffic, OCEAN_ROUTE_HALF_EXTENT / 7.46 + 2)
    testing.expect(t, !traffic.agent.active)
    testing.expect_value(t, traffic.next_class, Ocean_Class.Cruise_Ship)
    testing.expect(t, traffic.seconds_until_ship >= 295)
}

@(test)
ocean_ship_meshes_fit_the_shared_mesh_capacity :: proc(t: ^testing.T) {
    tanker := ocean_mesh(.Product_Tanker)
    cruise := ocean_mesh(.Cruise_Ship)
    testing.expect(t, tanker != nil && tanker.vertex_count > 0 && tanker.vertex_count < MESH_VERTEX_CAPACITY)
    testing.expect(t, cruise != nil && cruise.vertex_count > 0 && cruise.vertex_count < MESH_VERTEX_CAPACITY)
    testing.expect(t, tanker.triangle_count > 0 && tanker.triangle_count < MESH_TRIANGLE_CAPACITY)
    testing.expect(t, cruise.triangle_count > 0 && cruise.triangle_count < MESH_TRIANGLE_CAPACITY)
}
