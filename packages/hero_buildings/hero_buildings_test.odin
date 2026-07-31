package hero_buildings

import "core:testing"

@(test)
post_office_plans_are_deterministic_and_valid :: proc(t: ^testing.T) {
    first := generate(1948, defaults())
    second := generate(1948, defaults())
    testing.expect(t, first.valid)
    testing.expect_value(t, first, second)
}

@(test)
airport_terminals_share_the_open_pavilion_contract :: proc(t: ^testing.T) {
    for seed in u32(0) ..< 256 {
        plan := generate(seed, defaults(.Airport_Terminal))
        testing.expect(t, plan.valid)
        testing.expect_value(t, plan.kind, Kind.Airport_Terminal)
        testing.expect(t, plan.open_office)
        testing.expect(t, plan.circular_counter)
        testing.expect(t, !plan.has_secure_room)
        testing.expect_value(t, plan.secure_width, f32(0))
        testing.expect_value(t, plan.secure_depth, f32(0))
        testing.expect(t, plan.frontage > generate(seed, defaults(.Post_Office)).frontage)
    }
}

@(test)
clinics_keep_public_waiting_open_and_private_rooms_compact :: proc(t: ^testing.T) {
    roofs_seen: [len(Roof_Form)]bool
    rooms_seen: [len(Room_Arrangement)]bool
    counters_seen: [len(Counter_Form)]bool
    waiting_seen: [len(Waiting_Layout)]bool
    for seed in u32(0) ..< 256 {
        plan := generate(seed, defaults(.Clinic))
        testing.expect(t, plan.valid)
        testing.expect_value(t, plan.kind, Kind.Clinic)
        testing.expect(t, plan.open_office)
        testing.expect(t, !plan.circular_counter)
        testing.expect_value(t, plan.private_room_count, 2)
        testing.expect(t, plan.has_secure_room)
        testing.expect(t, plan.secure_width * plan.secure_depth * 2 < plan.frontage * plan.depth * .18)
        roofs_seen[int(plan.roof_form)] = true
        rooms_seen[int(plan.room_arrangement)] = true
        counters_seen[int(plan.counter_form)] = true
        waiting_seen[int(plan.waiting_layout)] = true
    }
    for seen in roofs_seen do testing.expect(t, seen)
    for seen in rooms_seen do testing.expect(t, seen)
    testing.expect(t, counters_seen[int(Counter_Form.Linear)])
    testing.expect(t, counters_seen[int(Counter_Form.L_Shaped)])
    testing.expect(t, !counters_seen[int(Counter_Form.Circular)])
    for seen in waiting_seen do testing.expect(t, seen)
}

@(test)
post_office_keeps_a_deep_open_arcade_across_seeds :: proc(t: ^testing.T) {
    for seed in u32(0) ..< 256 {
        plan := generate(seed, defaults())
        testing.expect(t, plan.valid)
        testing.expect(t, plan.arcade_depth >= 4.5)
        testing.expect(t, plan.arcade_depth < plan.depth * .60)
        testing.expect(t, plan.bay_width > plan.pier_width * 2.5)
        testing.expect(t, plan.bay_count & 1 == 1)
        testing.expect(t, plan.open_office)
        testing.expect(t, plan.secure_width * plan.secure_depth < plan.frontage * plan.depth * .10)
    }
}

@(test)
configuration_is_clamped_to_hero_building_domain :: proc(t: ^testing.T) {
    plan := generate(8, {frontage = 200, depth = 2, arcade_depth = 90, bay_count = 2, arcade_height = 20})
    testing.expect(t, plan.valid)
    testing.expect_value(t, plan.bay_count, 3)
    testing.expect(t, plan.frontage <= 36)
    testing.expect(t, plan.depth >= 11)
    testing.expect(t, plan.arcade_height <= 6.7)
}
