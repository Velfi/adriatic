package main

import flocks "../packages/flocks"
import terrain "../packages/terrain"
import "core:testing"

@(test)
flying_birds_predictively_steer_away_from_building_walls :: proc(t: ^testing.T) {
    building := terrain.structure_make(0, 0, 10, 10, 0, 10)
    building.kind = .Architecture
    incoming := flocks.Vec3{8, 0, 0}
    avoided := bird_building_avoidance_velocity({-10, 4, 0}, incoming, building, 1.0 / 60.0)
    testing.expect(t, avoided.x < incoming.x)
    testing.expect(t, avoided.y > incoming.y)
}

flying_birds_above_roof_clearance_do_not_steer :: proc(t: ^testing.T) {
    building := terrain.structure_make(0, 0, 10, 10, 0, 10)
    building.kind = .Architecture
    incoming := flocks.Vec3{8, 0, 0}
    avoided := bird_building_avoidance_velocity({-10, 15, 0}, incoming, building, 1.0 / 60.0)
    testing.expect_value(t, avoided, incoming)
}
