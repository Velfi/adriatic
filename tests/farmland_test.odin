package tests

import farmland "../packages/farmland"
import "core:testing"

farmland_fingerprint :: proc(plan: ^farmland.Plan) -> u64 {
    hash := u64(1469598103934665603)
    for parcel in plan.parcels[:plan.parcel_count] {
        hash = (hash ~ u64(parcel.min_x + 1)) * 1099511628211
        hash = (hash ~ u64(parcel.min_z + 1)) * 1099511628211
        hash = (hash ~ u64(parcel.max_x + 1)) * 1099511628211
        hash = (hash ~ u64(parcel.max_z + 1)) * 1099511628211
        hash = (hash ~ u64(parcel.crop)) * 1099511628211
        hash = (hash ~ u64(parcel.row_axis_x)) * 1099511628211
    }
    return hash
}

@(test)
markov_farmland_is_valid_deterministic_and_seeded :: proc(t: ^testing.T) {
    a := farmland.generate(0x4641524d)
    b := farmland.generate(0x4641524d)
    c := farmland.generate(7123)
    testing.expect(t, farmland.validate(&a))
    testing.expect(t, farmland.validate(&b))
    testing.expect(t, farmland.validate(&c))
    testing.expect(t, farmland_fingerprint(&a) == farmland_fingerprint(&b))
    testing.expect(t, farmland_fingerprint(&a) != farmland_fingerprint(&c))
}

@(test)
farmland_always_reserves_a_kitchen_garden :: proc(t: ^testing.T) {
    sizes := [3][2]int{{7, 7}, {8, 8}, {25, 19}}
    for dimensions in sizes {
        plan := farmland.generate_sized(73, dimensions[0], dimensions[1])
        testing.expect(t, plan.garden_span >= 1)
        testing.expect(t, plan.garden_x >= 0 && plan.garden_x + plan.garden_span <= plan.width)
        testing.expect(t, plan.garden_z >= 0 && plan.garden_z + plan.garden_span <= plan.height)
    }
}

@(test)
markov_farmland_partitions_cover_the_grid_exactly :: proc(t: ^testing.T) {
    plan := farmland.generate(41)
    coverage: [farmland.GRID_WIDTH * farmland.GRID_HEIGHT]u8
    for parcel in plan.parcels[:plan.parcel_count] {
        for z in parcel.min_z ..< parcel.max_z {
            for x in parcel.min_x ..< parcel.max_x {
                coverage[z * farmland.GRID_WIDTH + x] += 1
            }
        }
    }
    for count in coverage {
        testing.expect(t, count == 1)
    }
}

@(test)
farmland_layout_responds_to_footprint_size_and_aspect :: proc(t: ^testing.T) {
    small := farmland.generate_sized(41, 10, 8)
    wide := farmland.generate_sized(41, 38, 10)
    tall := farmland.generate_sized(41, 10, 38)
    testing.expect(t, farmland.validate(&small))
    testing.expect(t, farmland.validate(&wide))
    testing.expect(t, farmland.validate(&tall))
    testing.expect(t, small.width == 10 && small.height == 8)
    testing.expect(t, wide.width == 38 && wide.height == 10)
    testing.expect(t, tall.width == 10 && tall.height == 38)
    testing.expect(t, small.parcel_count < wide.parcel_count)
    testing.expect(t, farmland_fingerprint(&wide) != farmland_fingerprint(&tall))
}

@(test)
small_farmland_has_at_most_one_internal_hedge :: proc(t: ^testing.T) {
    tiny := farmland.generate_sized(41, 7, 7)
    aegean := farmland.generate_sized(41, 8, 8)
    continental := farmland.generate_sized(41, 10, 9)
    testing.expect(t, farmland.validate(&tiny))
    testing.expect(t, farmland.validate(&aegean))
    testing.expect(t, farmland.validate(&continental))
    testing.expect(t, tiny.parcel_count == 1)
    testing.expect(t, aegean.parcel_count == 1)
    testing.expect(t, continental.parcel_count == 1)
}

@(test)
farmland_traditions_produce_distinct_field_systems :: proc(t: ^testing.T) {
    ancient := farmland.generate_sized_for_tradition(7123, 48, 36, .Ancient_Enclosure)
    parliamentary := farmland.generate_sized_for_tradition(7123, 48, 36, .Parliamentary_Enclosure)
    testing.expect(t, farmland.validate(&ancient))
    testing.expect(t, farmland.validate(&parliamentary))
    testing.expect(t, ancient.tradition == .Ancient_Enclosure)
    testing.expect(t, parliamentary.tradition == .Parliamentary_Enclosure)
    testing.expect(t, farmland_fingerprint(&ancient) != farmland_fingerprint(&parliamentary))
}
