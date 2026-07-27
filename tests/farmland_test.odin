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
