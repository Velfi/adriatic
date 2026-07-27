package tests

import boats "../packages/boats"
import "core:testing"

@(test)
npc_boat_classes_have_researched_dimensions_and_one_mesh :: proc(t: ^testing.T) {
    classes := [4]boats.Class{.Motor, .Sail, .Fishing, .Tug}
    expected_lengths := [4]f32{6.50, 7.99, 7.72, 24.99}
    expected_beams := [4]f32{2.60, 2.54, 2.90, 12.19}
    for class, index in classes {
        spec := boats.specifications(class)
        mesh := boats.mesh(class)
        testing.expect(t, spec.length == expected_lengths[index])
        testing.expect(t, spec.beam == expected_beams[index])
        testing.expect(t, mesh.vertex_count > 0)
        testing.expect(t, mesh.triangle_count > 0)
        testing.expect(t, len(boats.vertices(&mesh)) == mesh.vertex_count)
        testing.expect(t, len(boats.triangles(&mesh)) == mesh.triangle_count)
    }
}

@(test)
npc_boat_classes_keep_distinct_operating_profiles :: proc(t: ^testing.T) {
    motor := boats.specifications(.Motor)
    sail := boats.specifications(.Sail)
    fishing := boats.specifications(.Fishing)
    tug := boats.specifications(.Tug)
    testing.expect(t, motor.cruise_speed_mps > fishing.cruise_speed_mps)
    testing.expect(t, sail.height_or_clearance > fishing.height_or_clearance)
    testing.expect(t, tug.length > sail.length * 3)
    testing.expect(t, tug.beam > motor.beam * 4)
}

@(test)
dockmaster_dinghy_is_a_small_complete_harbor_tender :: proc(t: ^testing.T) {
    spec := boats.specifications(.Dinghy)
    mesh := boats.mesh(.Dinghy)
    testing.expect(t, spec.length == 3.10)
    testing.expect(t, spec.beam == 1.35)
    testing.expect(t, spec.length < boats.specifications(.Motor).length * .5)
    testing.expect(t, mesh.vertex_count > 0)
    testing.expect(t, mesh.triangle_count > 0)
}

@(test)
npc_boat_hulls_close_bow_and_stern_with_five_triangle_caps :: proc(t: ^testing.T) {
    classes := [4]boats.Class{.Motor, .Sail, .Fishing, .Tug}
    for class in classes {
        spec := boats.specifications(class)
        mesh := boats.mesh(class)
        bow_z := -spec.length * .5
        stern_z := spec.length * .5
        bow_faces, stern_faces := 0, 0
        for face in boats.triangles(&mesh) {
            a := mesh.vertices[face.a]
            b := mesh.vertices[face.b]
            c := mesh.vertices[face.c]
            if a.part != .Hull || b.part != .Hull || c.part != .Hull do continue
            if a.position[2] == bow_z && b.position[2] == bow_z && c.position[2] == bow_z {
                bow_faces += 1
            }
            if a.position[2] == stern_z && b.position[2] == stern_z && c.position[2] == stern_z {
                stern_faces += 1
            }
        }
        testing.expect(t, bow_faces == 5)
        testing.expect(t, stern_faces == 5)
    }
}

@(test)
boat_traffic_runs_schedules_patrols_loiters_and_wakes :: proc(t: ^testing.T) {
    traffic := boats.new_traffic()
    saw_patrol, saw_loiter, saw_transit := false, false, false
    initial_route := traffic.agents[0].route_index
    world_minutes := f32(240)
    for _ in 0 ..< 4200 {
        boats.step(&traffic, .05, world_minutes)
        world_minutes += .05 * 4
        for agent in traffic.agents[:traffic.count] {
            switch agent.behavior {
            case .Patrol:
                saw_patrol = true
            case .Loiter:
                saw_loiter = true
            case .Transit:
                saw_transit = true
            case .Moored:
            }
        }
    }
    testing.expect(t, saw_patrol)
    testing.expect(t, saw_loiter)
    testing.expect(t, saw_transit)
    testing.expect(t, traffic.agents[0].route_index != initial_route)
    for agent in traffic.agents[:traffic.count] {
        testing.expect(t, agent.speed >= 0)
        testing.expect(t, agent.wake_count > 0)
    }
}

@(test)
moored_boats_hold_their_berth_and_never_make_wakes :: proc(t: ^testing.T) {
    traffic: boats.Traffic
    position := boats.Vec2{12, -8}
    agent := boats.add_moored_agent(&traffic, .Sail, position, 1.25)
    testing.expect(t, agent != nil)
    for _ in 0 ..< 200 do boats.step(&traffic, .05, 9 * 60)
    testing.expect(t, traffic.count == 1)
    testing.expect(t, traffic.agents[0].behavior == .Moored)
    testing.expect(t, traffic.agents[0].position == position)
    testing.expect(t, traffic.agents[0].yaw == 1.25)
    testing.expect(t, traffic.agents[0].speed == 0)
    testing.expect(t, traffic.agents[0].wake_count == 0)
}

@(test)
boat_schedule_uses_world_time_of_day :: proc(t: ^testing.T) {
    traffic := boats.new_traffic()
    fishing := &traffic.agents[int(boats.Class.Fishing)]
    motor := &traffic.agents[int(boats.Class.Motor)]
    tug := &traffic.agents[int(boats.Class.Tug)]
    behavior, _ := boats.schedule_behavior(fishing, 2 * 60)
    testing.expect(t, behavior == .Transit)
    behavior, _ = boats.schedule_behavior(motor, 8 * 60)
    testing.expect(t, behavior == .Patrol)
    behavior, _ = boats.schedule_behavior(tug, 13 * 60)
    testing.expect(t, behavior == .Transit)
    behavior, _ = boats.schedule_behavior(motor, 23 * 60)
    testing.expect(t, behavior == .Loiter)
}

@(test)
boat_avoidance_steers_apart_before_contact :: proc(t: ^testing.T) {
    traffic := boats.new_traffic()
    traffic.count = 2
    traffic.agents[0].position = {0, 0}
    traffic.agents[1].position = {8, 0}
    traffic.agents[0].velocity = {3, 0}
    traffic.agents[1].velocity = {-3, 0}
    first := boats.avoidance_vector(&traffic, 0)
    second := boats.avoidance_vector(&traffic, 1)
    testing.expect(t, first.x < 0)
    testing.expect(t, second.x > 0)
    testing.expect(t, boats.vec_dot(first, second) < 0)
}

@(test)
boat_wake_scales_with_speed_power_and_displacement :: proc(t: ^testing.T) {
    classes := [4]boats.Class{.Motor, .Sail, .Fishing, .Tug}
    for class in classes {
        spec := boats.specifications(class)
        slow := boats.wake_strength(class, spec.cruise_speed_mps * .25)
        cruise := boats.wake_strength(class, spec.cruise_speed_mps)
        testing.expect(t, slow > 0)
        testing.expect(t, cruise > slow)
    }
    motor := boats.wake_strength(.Motor, boats.specifications(.Motor).cruise_speed_mps)
    sail := boats.wake_strength(.Sail, boats.specifications(.Sail).cruise_speed_mps)
    tug := boats.wake_strength(.Tug, boats.specifications(.Tug).cruise_speed_mps)
    testing.expect(t, motor > sail)
    testing.expect(t, tug > sail)
}
