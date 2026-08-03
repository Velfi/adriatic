package main

import fixture_v0014 "../packages/fixture_history/v0014"
import "core:mem"

FIXTURE_MIGRATION_V0014_TO_V0015_FROM_VERSION :: 14
FIXTURE_MIGRATION_V0014_TO_V0015_TO_VERSION :: 15
FIXTURE_MIGRATION_V0014_TO_V0015_RESOLUTIONS :: [?]Fixture_Migration_Resolution {
    Fixture_Migration_Resolution {
        change_id = "field-type:adriatic:packages/particles.Wing_Trails.particles",
        kind = .Scripted,
    },
}

fixture_migrate_v0014_to_v0015 :: proc(
    #by_ptr historical: fixture_v0014.Fixture,
    tentative: ^Fixture,
    allocator: mem.Allocator,
) -> Fixture_Migration_Error {
    _ = allocator
    if tentative == nil do return {kind = .Invalid_Argument}
    if historical.wing_trails.count < 0 || historical.wing_trails.count > len(historical.wing_trails.particles) {
        return {kind = .Invalid_Source, change_id = "field-type:adriatic:packages/particles.Wing_Trails.particles"}
    }
    for source, index in historical.wing_trails.particles {
        tentative.wing_trails.particles[index] = {
            position = {source.position.x, source.position.y, source.position.z},
            velocity = {source.velocity.x, source.velocity.y, source.velocity.z},
            life     = source.life,
            max_life = source.max_life,
            size     = source.size,
            seed     = source.seed,
            side     = source.side,
            curve    = source.curve,
        }
    }
    return fixture_v0015_validate_wing_trails(tentative)
}

fixture_v0015_validate_wing_trails :: proc(tentative: ^Fixture) -> Fixture_Migration_Error {
    if tentative == nil do return {kind = .Invalid_Argument}
    if tentative.wing_trails.count < 0 || tentative.wing_trails.count > 192 {
        return {kind = .Invalid_Source, change_id = "field-type:adriatic:packages/particles.Wing_Trails.particles"}
    }
    return {}
}
