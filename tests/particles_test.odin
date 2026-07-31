package tests

import particle_systems "../packages/particles"
import "core:testing"

@(test)
vehicle_dust_profiles_have_distinct_motion_and_scale :: proc(t: ^testing.T) {
    asphalt := particle_systems.new_vehicle_effects(0x1234)
    gravel := particle_systems.new_vehicle_effects(0x1234)
    cobble := particle_systems.new_vehicle_effects(0x1234)
    dirt := particle_systems.new_vehicle_effects(0x1234)
    sand := particle_systems.new_vehicle_effects(0x1234)
    origin := particle_systems.Vec3{4, 2, 8}

    particle_systems.spawn_dust(&asphalt, {position = origin, grounded = true, surface = .Asphalt}, 1)
    particle_systems.spawn_dust(&gravel, {position = origin, grounded = true, surface = .Gravel}, 1)
    particle_systems.spawn_dust(&cobble, {position = origin, grounded = true, surface = .Cobblestone}, 1)
    particle_systems.spawn_dust(&dirt, {position = origin, grounded = true, surface = .Dirt}, 1)
    particle_systems.spawn_dust(&sand, {position = origin, grounded = true, surface = .Sand}, 1)

    testing.expect(t, asphalt.dust_count == 1 && gravel.dust_count == 1)
    testing.expect(t, cobble.dust_count == 1 && dirt.dust_count == 1)
    testing.expect(t, asphalt.dust[0].surface == .Asphalt)
    testing.expect(t, gravel.dust[0].surface == .Gravel)
    testing.expect(t, cobble.dust[0].surface == .Cobblestone)
    testing.expect(t, dirt.dust[0].surface == .Dirt)
    testing.expect(t, sand.dust[0].surface == .Sand)
    testing.expect(t, asphalt.dust[0].max_life < cobble.dust[0].max_life)
    testing.expect(t, cobble.dust[0].max_life < dirt.dust[0].max_life)
    testing.expect(t, asphalt.dust[0].size < gravel.dust[0].size)
    testing.expect(t, gravel.dust[0].size < dirt.dust[0].size)
    testing.expect(t, sand.dust[0].max_life > cobble.dust[0].max_life)
}

@(test)
vehicle_dust_spawn_density_tracks_road_surface :: proc(t: ^testing.T) {
    asphalt := particle_systems.new_vehicle_effects(0x5678)
    gravel := particle_systems.new_vehicle_effects(0x5678)
    asphalt_contacts: [4]particle_systems.Vehicle_Contact
    gravel_contacts: [4]particle_systems.Vehicle_Contact
    for index in 0 ..< 4 {
        asphalt_contacts[index] = {
            grounded = true,
            surface  = .Asphalt,
        }
        gravel_contacts[index] = {
            grounded = true,
            surface  = .Gravel,
        }
    }
    particle_systems.step_vehicle_effects(&asphalt, .05, 12, 0, false, 0, asphalt_contacts)
    particle_systems.step_vehicle_effects(&gravel, .05, 12, 0, false, 0, gravel_contacts)
    testing.expect(t, asphalt.dust_count == 0)
    testing.expect(t, gravel.dust_count > asphalt.dust_count)
}

@(test)
scrabble_sprays_backwards_at_a_bounded_rate :: proc(t: ^testing.T) {
    effects := particle_systems.new_vehicle_effects(0x9abc)
    contact := particle_systems.Vehicle_Contact {
        position = {2, 0, 4},
        grounded = true,
        surface  = .Dirt,
    }
    particle_systems.spawn_scrabble(&effects, .05, contact, {0, 0, 1}, 1)

    testing.expect(t, effects.dust_count == 1)
    testing.expect(t, effects.dust[0].velocity.z < 0)
    testing.expect(t, effects.dust[0].life == effects.dust[0].max_life)
    testing.expect(t, effects.dust_spawn >= 0 && effects.dust_spawn < 1)
}

@(test)
wing_trails_wait_for_flying_speed_and_expire :: proc(t: ^testing.T) {
    trails := particle_systems.new_wing_trails(0x57494e47)
    left, right := particle_systems.Vec3{-5, 2, 0}, particle_systems.Vec3{5, 2, 0}
    forward, up := particle_systems.Vec3{0, 0, 1}, particle_systems.Vec3{0, 1, 0}

    particle_systems.step_wing_trails(&trails, .05, left, right, forward, up, {}, 11)
    testing.expect(t, trails.count == 0)

    particle_systems.step_wing_trails(&trails, .05, left, right, forward, up, {}, 46)
    testing.expect(t, trails.count > 0)
    for _ in 0 ..< 30 {
        particle_systems.step_wing_trails(&trails, .05, left, right, forward, up, {}, 0)
    }
    testing.expect(t, trails.count == 0)
}

@(test)
wing_trail_lifetime_tightens_at_extreme_speed :: proc(t: ^testing.T) {
    testing.expect(t, particle_systems.wing_trail_lifetime_scale(46) == 1)
    testing.expect(t, particle_systems.wing_trail_lifetime_scale(90) == .65)
    testing.expect(
        t,
        particle_systems.wing_trail_lifetime_scale(72) < particle_systems.wing_trail_lifetime_scale(58),
    )
}

@(test)
wing_trails_curve_with_crosswind :: proc(t: ^testing.T) {
    trails := particle_systems.new_wing_trails(0x43524f53)
    left, right := particle_systems.Vec3{-5, 2, 0}, particle_systems.Vec3{5, 2, 0}
    forward, up := particle_systems.Vec3{0, 0, 1}, particle_systems.Vec3{0, 1, 0}
    crosswind := particle_systems.Vec3{8, 0, 0}

    particle_systems.step_wing_trails(&trails, .05, left, right, forward, up, crosswind, 46)
    testing.expect(t, trails.count > 0)
    initial_x := trails.particles[0].position.x
    for _ in 0 ..< 4 {
        particle_systems.step_wing_trails(&trails, .05, left, right, forward, up, crosswind, 0)
    }
    testing.expect(t, trails.particles[0].position.x > initial_x)
}
