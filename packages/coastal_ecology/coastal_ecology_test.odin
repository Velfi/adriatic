package coastal_ecology

import "core:math"
import "core:testing"

@(test)
deterministic_generation :: proc(t: ^testing.T) {
    config := default_config()
    a, b := generate(config), generate(config)
    testing.expect(t, a.organism_count == b.organism_count)
    testing.expect(t, a.wrack_count == b.wrack_count)
    testing.expect(t, a.pool_cells == b.pool_cells)
    testing.expect(t, a.cells[317] == b.cells[317])
    testing.expect(t, a.organisms[0] == b.organisms[0])
    if a.wrack_count > 0 do testing.expect(t, a.wrack[0] == b.wrack[0])
}

@(test)
wrack_tracks_the_spring_high_water_contour :: proc(t: ^testing.T) {
    config := default_config()
    plan := generate(config)
    high := tide_height(config, .5)
    testing.expect(t, plan.wrack_count > 0)
    for strand in plan.wrack[:plan.wrack_count] {
        testing.expect(t, math.abs(strand.y - high) <= .35)
    }
}

@(test)
tide_floods_rock_but_pools_retain_water :: proc(t: ^testing.T) {
    config := default_config()
    dry := Cell {
        height     = 1,
        water_trap = 0,
    }
    pool := Cell {
        height     = 1,
        water_trap = .8,
    }
    _, dry_wet := water_level(dry, config, 0)
    pool_level, pool_wet := water_level(pool, config, 0)
    testing.expect(t, !dry_wet)
    testing.expect(t, pool_wet)
    testing.expect(t, pool_level > pool.height)
    testing.expect(t, tide_height(config, .5) > tide_height(config, 0))
}

@(test)
rock_shape_changes_ecology :: proc(t: ^testing.T) {
    a_config := default_config()
    b_config := a_config
    b_config.seed += 1
    a, b := generate(a_config), generate(b_config)
    changed := a.pool_cells != b.pool_cells || a.organism_count != b.organism_count
    if !changed {
        for index in 0 ..< min(a.organism_count, b.organism_count) {
            if a.organisms[index].species != b.organisms[index].species {
                changed = true
                break
            }
        }
    }
    testing.expect(t, changed)
}
