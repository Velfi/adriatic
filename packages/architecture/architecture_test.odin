package architecture

import terrain "../terrain"
import "core:testing"

@(test)
tight_route_v_becomes_y :: proc(t: ^testing.T) {
    network: Town_Route_Network
    apex := town_route_add_node(&network, {0, 0}, true)
    left := town_route_add_node(&network, {30, 5})
    right := town_route_add_node(&network, {30, -5})
    town_route_add_edge(&network, apex, left)
    town_route_add_edge(&network, apex, right)

    town_route_merge_tight_vs(&network)

    testing.expect_value(t, network.node_count, 4)
    testing.expect_value(t, network.edge_count, 3)
    junction := 3
    testing.expect(t, network.nodes[junction].y_junction)
    testing.expect(t, town_route_nodes_adjacent(&network, apex, junction))
    testing.expect(t, town_route_nodes_adjacent(&network, junction, left))
    testing.expect(t, town_route_nodes_adjacent(&network, junction, right))
    testing.expect(t, !town_route_nodes_adjacent(&network, apex, left))
    testing.expect(t, !town_route_nodes_adjacent(&network, apex, right))
}

@(test)
route_avoidance_pushes_out_of_rotated_building :: proc(t: ^testing.T) {
    structure := terrain.Structure {
        center_x = 10,
        center_z = 20,
        width    = 12,
        depth    = 8,
        rotation = .35,
        seed     = 2,
    }
    force := town_route_building_avoidance({10, 20}, structure)
    testing.expect(t, force[0] != 0 || force[1] != 0)

    distant := town_route_building_avoidance({40, 50}, structure)
    testing.expect_value(t, distant, [2]f32{})
}

@(test)
crowded_route_nodes_merge_and_rewire :: proc(t: ^testing.T) {
    network: Town_Route_Network
    left := town_route_add_node(&network, {-20, 0}, true)
    first := town_route_add_node(&network, {0, -2})
    second := town_route_add_node(&network, {0, 2})
    right := town_route_add_node(&network, {20, 0}, true)
    town_route_add_edge(&network, left, first)
    town_route_add_edge(&network, second, right)

    town_route_consolidate_crowding(&network)

    testing.expect_value(t, network.node_count, 3)
    testing.expect_value(t, network.edge_count, 2)
    testing.expect(t, town_route_nodes_adjacent(&network, 0, 1))
    testing.expect(t, town_route_nodes_adjacent(&network, 1, 2))
}

@(test)
wide_route_v_keeps_its_topology :: proc(t: ^testing.T) {
    network: Town_Route_Network
    apex := town_route_add_node(&network, {0, 0}, true)
    left := town_route_add_node(&network, {20, 20})
    right := town_route_add_node(&network, {20, -20})
    town_route_add_edge(&network, apex, left)
    town_route_add_edge(&network, apex, right)

    town_route_merge_tight_vs(&network)

    testing.expect_value(t, network.node_count, 3)
    testing.expect_value(t, network.edge_count, 2)
}
