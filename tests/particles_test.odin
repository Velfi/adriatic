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
