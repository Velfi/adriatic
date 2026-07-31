package main

import fixture_v0014 "../packages/fixture_history/v0014"
import "core:testing"

@(test)
fixture_migration_v0014_to_v0015_preserves_wing_trails_and_widens_capacity :: proc(t: ^testing.T) {
    historical := new(fixture_v0014.Fixture)
    tentative := new(Fixture)
    defer free(historical)
    defer free(tentative)

    historical.wing_trails.count = 2
    historical.wing_trails.spawn = .75
    historical.wing_trails.seed = 0x57494e47
    historical.wing_trails.particles[1] = {
        position = {1, 2, 3},
        velocity = {4, 5, 6},
        life = .4,
        max_life = .8,
        size = .03,
        seed = 91,
        side = 1,
        curve = -.2,
    }
    tentative.wing_trails.count = historical.wing_trails.count
    tentative.wing_trails.spawn = historical.wing_trails.spawn
    tentative.wing_trails.seed = historical.wing_trails.seed

    migration_error := fixture_migrate_v0014_to_v0015(historical^, tentative, context.allocator)
    testing.expect(t, migration_error.kind == .None)
    testing.expect(t, len(tentative.wing_trails.particles) == 576)
    testing.expect(t, tentative.wing_trails.count == 2)
    testing.expect(t, tentative.wing_trails.particles[1].position.x == 1)
    testing.expect(t, tentative.wing_trails.particles[1].velocity.z == 6)
    testing.expect(t, tentative.wing_trails.particles[1].side == 1)
    testing.expect(t, tentative.wing_trails.particles[192].life == 0)
}

