package particles

import air_effects "../air_effects"
import "core:math"

MAX_CPU_PARTICLES :: 384
MAX_DUST_PARTICLES :: 256
MAX_WING_TRAIL_PARTICLES :: 576
MAX_PETAL_PARTICLES :: 192

Vec3 :: struct {
    x, y, z: f32,
}

Particle :: struct {
    position: Vec3,
    velocity: Vec3,
    life:     f32,
    max_life: f32,
    size:     f32,
    seed:     u32,
}

Vehicle_Contact :: struct {
    position: Vec3,
    grounded: bool,
    surface:  Dust_Surface,
}

Dust_Surface :: enum u8 {
    Grass,
    Asphalt,
    Gravel,
    Cobblestone,
    Dirt,
    Sand,
}

Vehicle_Particle :: struct {
    position: Vec3,
    velocity: Vec3,
    life:     f32,
    max_life: f32,
    size:     f32,
    seed:     u32,
    surface:  Dust_Surface,
}

Vehicle_Effects :: struct {
    dust:       [MAX_DUST_PARTICLES]Vehicle_Particle,
    dust_count: int,
    dust_spawn: f32,
    seed:       u32,
}

Wing_Trail_Particle :: struct {
    position: Vec3,
    velocity: Vec3,
    life:     f32,
    max_life: f32,
    size:     f32,
    seed:     u32,
    side:     u8,
    curve:    f32,
}

Wing_Trails :: struct {
    particles: [MAX_WING_TRAIL_PARTICLES]Wing_Trail_Particle,
    count:     int,
    spawn:     f32,
    seed:      u32,
}

Petal_Effects :: struct {
    particles: [MAX_PETAL_PARTICLES]Particle,
    count:     int,
    spawn:     f32,
    seed:      u32,
}

Cpu_System :: struct {
    particles: [MAX_CPU_PARTICLES]Particle,
    count:     int,
    clock:     f32,
    spawn:     f32,
    seed:      u32,
}

new_cpu :: proc(seed: u32) -> Cpu_System {
    return {seed = seed, spawn = .0}
}

next_random :: proc(seed: ^u32) -> f32 {
    seed^ = seed^ * 1664525 + 1013904223
    return f32(seed^ & 0x00ffffff) / f32(0x01000000)
}

spawn_one :: proc(system: ^Cpu_System, origin: Vec3) {
    if system.count >= MAX_CPU_PARTICLES do return
    r0 := next_random(&system.seed)
    r1 := next_random(&system.seed)
    r2 := next_random(&system.seed)
    angle := r0 * math.PI * 2
    particle := &system.particles[system.count]
    particle^ = {
        position = {origin.x + math.cos(angle) * (r1 * 1.8), origin.y, origin.z + math.sin(angle) * (r1 * 1.8)},
        velocity = {math.cos(angle) * (.35 + r1 * .55), .45 + r2 * .75, math.sin(angle) * (.35 + r1 * .55)},
        life     = 1.2 + r2 * 1.7,
        max_life = 1.2 + r2 * 1.7,
        size     = .08 + r1 * .14,
        seed     = system.seed,
    }
    system.count += 1
}

step :: proc(system: ^Cpu_System, delta_seconds: f32, origin: Vec3) {
    dt := clamp(delta_seconds, 0, .05)
    system.clock += dt
    system.spawn += dt * 72
    for system.spawn >= 1 {
        spawn_one(system, origin)
        system.spawn -= 1
    }
    write := 0
    for read in 0 ..< system.count {
        particle := &system.particles[read]
        particle.life -= dt
        if particle.life <= 0 do continue
        particle.velocity.y -= .36 * dt
        particle.position.x += particle.velocity.x * dt
        particle.position.y += particle.velocity.y * dt
        particle.position.z += particle.velocity.z * dt
        if write != read do system.particles[write] = particle^
        write += 1
    }
    system.count = write
}

active_count :: proc(system: ^Cpu_System) -> int { return system.count }

new_vehicle_effects :: proc(seed: u32) -> Vehicle_Effects { return {seed = seed} }

new_wing_trails :: proc(seed: u32) -> Wing_Trails { return {seed = seed} }

wing_trail_lifetime_scale :: proc(airspeed: f32) -> f32 {
    return 1 - air_effects.eased_range(airspeed, 55, 90) * .35
}

new_petal_effects :: proc(seed: u32) -> Petal_Effects { return {seed = seed} }

step_petals :: proc(effects: ^Petal_Effects, delta_seconds: f32, origin, motion, wind: Vec3, intensity: f32) {
    dt := clamp(delta_seconds, 0, .05)
    effects.spawn += dt * 34 * clamp(intensity, 0, 1)
    for effects.spawn >= 1 && effects.count < MAX_PETAL_PARTICLES {
        angle := next_random(&effects.seed) * math.PI * 2
        radius := next_random(&effects.seed) * (1.1 + intensity * 1.4)
        lift := next_random(&effects.seed)
        life := 1.1 + next_random(&effects.seed) * 1.35
        particle := &effects.particles[effects.count]
        particle^ = {
            position = {
                origin.x + math.cos(angle) * radius,
                origin.y + .12 + lift * .42,
                origin.z + math.sin(angle) * radius,
            },
            velocity = {
                motion.x * .10 + math.cos(angle) * (.35 + intensity * .85),
                .55 + lift * 1.25 + intensity * .45,
                motion.z * .10 + math.sin(angle) * (.35 + intensity * .85),
            },
            life     = life,
            max_life = life,
            size     = .035 + next_random(&effects.seed) * .055,
            seed     = effects.seed,
        }
        effects.count += 1
        effects.spawn -= 1
    }
    if intensity <= 0 do effects.spawn = min(effects.spawn, .95)

    write := 0
    for read in 0 ..< effects.count {
        particle := &effects.particles[read]
        particle.life -= dt
        if particle.life <= 0 do continue
        flutter := math.sin(f32(particle.seed & 255) + particle.life * 13) * .34
        particle.velocity.x += (wind.x * .7 + flutter) * dt
        particle.velocity.z += (wind.z * .7 - flutter * .45) * dt
        particle.velocity.y -= .52 * dt
        particle.position.x += particle.velocity.x * dt
        particle.position.y += particle.velocity.y * dt
        particle.position.z += particle.velocity.z * dt
        if write != read do effects.particles[write] = particle^
        write += 1
    }
    effects.count = write
}

spawn_dust :: proc(effects: ^Vehicle_Effects, contact: Vehicle_Contact, intensity: f32) {
    if effects.dust_count >= MAX_DUST_PARTICLES || !contact.grounded do return
    spread_x := next_random(&effects.seed) - .5
    spread_z := next_random(&effects.seed) - .5
    lift := next_random(&effects.seed)
    position_spread, velocity_spread := f32(.18), f32(.35 + intensity)
    base_lift, lift_range := f32(.18), f32(.32)
    base_life, life_range := f32(.28), f32(.42)
    base_size, intensity_size, lift_size := f32(.08), f32(.08), f32(.10)
    switch contact.surface {
    case .Asphalt:
        position_spread, velocity_spread = .10, .16 + intensity * .24
        base_lift, lift_range = .07, .10
        base_life, life_range = .16, .20
        base_size, intensity_size, lift_size = .035, .035, .035
    case .Gravel:
        position_spread, velocity_spread = .24, .52 + intensity * .70
        base_lift, lift_range = .15, .32
        base_life, life_range = .30, .34
        base_size, intensity_size, lift_size = .055, .055, .075
    case .Cobblestone:
        position_spread, velocity_spread = .13, .24 + intensity * .30
        base_lift, lift_range = .09, .16
        base_life, life_range = .20, .23
        base_size, intensity_size, lift_size = .04, .04, .045
    case .Dirt:
        position_spread, velocity_spread = .28, .42 + intensity * .54
        base_lift, lift_range = .22, .42
        base_life, life_range = .48, .48
        base_size, intensity_size, lift_size = .10, .09, .13
    case .Grass:
        position_spread, velocity_spread = .22, .32 + intensity * .40
        base_lift, lift_range = .15, .25
        base_life, life_range = .30, .32
        base_size, intensity_size, lift_size = .07, .06, .08
    case .Sand:
        // Fine grains launch a broad, buoyant plume that lingers longer than
        // grass clippings while staying lighter than heavy dirt clods.
        position_spread, velocity_spread = .26, .38 + intensity * .48
        base_lift, lift_range = .20, .30
        base_life, life_range = .40, .40
        base_size, intensity_size, lift_size = .06, .05, .07
    }
    life := base_life + lift * life_range
    particle := &effects.dust[effects.dust_count]
    particle^ = {
        position = {
            contact.position.x + spread_x * position_spread,
            contact.position.y + .045,
            contact.position.z + spread_z * position_spread,
        },
        velocity = {spread_x * velocity_spread, base_lift + lift * lift_range, spread_z * velocity_spread},
        life     = life,
        max_life = life,
        size     = base_size + intensity * intensity_size + lift * lift_size,
        seed     = effects.seed,
        surface  = contact.surface,
    }
    effects.dust_count += 1
}

spawn_stop_spray :: proc(effects: ^Vehicle_Effects, contact: Vehicle_Contact, travel_direction: Vec3, intensity: f32) {
    if effects == nil || !contact.grounded do return
    strength := clamp(intensity, f32(0), f32(1))
    count := 3 + int(strength * 3)
    for _ in 0 ..< count {
        if effects.dust_count >= MAX_DUST_PARTICLES do break
        spawn_dust(effects, contact, .35 + strength * .55)
        particle := &effects.dust[effects.dust_count - 1]
        forward_scatter := .40 + next_random(&effects.seed) * (.60 + strength * .60)
        side_scatter := (next_random(&effects.seed) - .5) * (.45 + strength * .35)
        particle.velocity.x += -travel_direction.x * forward_scatter - travel_direction.z * side_scatter
        particle.velocity.z += -travel_direction.z * forward_scatter + travel_direction.x * side_scatter
        particle.velocity.y += .06 + next_random(&effects.seed) * (.08 + strength * .12)
        particle.size *= .95
    }
}

// spawn_scrabble emits the small, rapid rearward spray made by paws working
// hard without gaining much ground. Unlike stop spray this is rate-based and
// deliberately stays close to the surface so it reads as traction, not impact.
spawn_scrabble :: proc(
    effects: ^Vehicle_Effects,
    delta_seconds: f32,
    contact: Vehicle_Contact,
    intent_direction: Vec3,
    intensity: f32,
) {
    if effects == nil || !contact.grounded do return
    strength := clamp(intensity, f32(0), f32(1))
    if strength <= 0 do return
    effects.dust_spawn += clamp(delta_seconds, f32(0), f32(.05)) * (10 + strength * 18)
    for effects.dust_spawn >= 1 {
        if effects.dust_count >= MAX_DUST_PARTICLES {
            effects.dust_spawn = .95
            break
        }
        spawn_dust(effects, contact, .18 + strength * .38)
        particle := &effects.dust[effects.dust_count - 1]
        rearward := .24 + next_random(&effects.seed) * (.32 + strength * .30)
        sideways := (next_random(&effects.seed) - .5) * (.34 + strength * .26)
        particle.velocity.x += -intent_direction.x * rearward - intent_direction.z * sideways
        particle.velocity.z += -intent_direction.z * rearward + intent_direction.x * sideways
        particle.velocity.y *= .58
        particle.life *= .72
        particle.max_life = particle.life
        particle.size *= .72
        effects.dust_spawn -= 1
    }
}

step_vehicle_effects :: proc(
    effects: ^Vehicle_Effects,
    delta_seconds: f32,
    speed, steering: f32,
    handbrake: bool,
    slip: f32,
    contacts: [4]Vehicle_Contact,
) {
    dt := clamp(delta_seconds, 0, .05)
    intensity := clamp(
        speed / 12 + abs(steering) * speed / 18 + clamp(slip, f32(0), f32(1)) * .7 + (handbrake ? f32(.65) : f32(0)),
        0,
        1.5,
    )
    surface := Dust_Surface.Grass
    for contact in contacts {
        if contact.grounded {
            surface = contact.surface
            break
        }
    }
    spawn_scale := f32(.55)
    switch surface {
    case .Asphalt:
        spawn_scale = .16
    case .Gravel:
        spawn_scale = 1.25
    case .Cobblestone:
        spawn_scale = .38
    case .Dirt:
        spawn_scale = 1
    case .Grass:
        spawn_scale = .55
    case .Sand:
        spawn_scale = 1.15
    }
    effects.dust_spawn += dt * intensity * 48 * spawn_scale
    for effects.dust_spawn >= 1 {
        for index in 0 ..< 4 {
            if intensity > .18 do spawn_dust(effects, contacts[index], intensity)
        }
        effects.dust_spawn -= 1
    }
    write := 0
    for read in 0 ..< effects.dust_count {
        particle := &effects.dust[read]
        particle.life -= dt
        if particle.life <= 0 do continue
        buoyancy := f32(.18)
        drag := f32(.94)
        switch particle.surface {
        case .Asphalt:
            buoyancy, drag = .07, .88
        case .Gravel:
            buoyancy, drag = -.18, .97
        case .Cobblestone:
            buoyancy, drag = .04, .90
        case .Dirt:
            buoyancy, drag = .30, .97
        case .Grass:
            buoyancy, drag = .16, .94
        case .Sand:
            buoyancy, drag = .24, .95
        }
        particle.velocity.x *= f32(math.pow(f64(drag), f64(dt * 60)))
        particle.velocity.z *= f32(math.pow(f64(drag), f64(dt * 60)))
        particle.velocity.y += buoyancy * dt
        particle.position.x += particle.velocity.x * dt
        particle.position.y += particle.velocity.y * dt
        particle.position.z += particle.velocity.z * dt
        if write != read do effects.dust[write] = particle^
        write += 1
    }
    effects.dust_count = write
}

step_wing_trails :: proc(
    trails: ^Wing_Trails,
    delta_seconds: f32,
    left_tip, right_tip, forward, up, wind: Vec3,
    airspeed: f32,
) {
    dt := clamp(delta_seconds, 0, .05)
    wind_speed := f32(math.sqrt(f64(wind.x * wind.x + wind.z * wind.z)))
    // `airspeed` is already relative airflow. Raw weather magnitude must not
    // re-strengthen vapor after a matching tailwind has cancelled that flow.
    strength := air_effects.vapor_strength(airspeed)
    trails.spawn += dt * strength * 72
    trails_curve := wind.x * forward.z - wind.z * forward.x
    trails_right := Vec3 {
        forward.y * up.z - forward.z * up.y,
        forward.z * up.x - forward.x * up.z,
        forward.x * up.y - forward.y * up.x,
    }
    for trails.spawn >= 1 {
        // Wingtip vapor is a paired effect. If only one slot remains, defer
        // the spawn instead of letting the left side permanently starve the
        // right side once the fixed particle pool reaches steady state.
        if trails.count + 2 > MAX_WING_TRAIL_PARTICLES do break
        pair_life := (.55 + next_random(&trails.seed) * (.55 + wind_speed * .02)) * wing_trail_lifetime_scale(airspeed)
        for side in 0 ..< 2 {
            tip := side == 0 ? left_tip : right_tip
            jitter := next_random(&trails.seed) - .5
            particle := &trails.particles[trails.count]
            particle^ = {
                position = {tip.x, tip.y, tip.z},
                velocity = {
                    -forward.x * (airspeed * (.19 + jitter * .022)) + wind.x * .18,
                    -forward.y * (airspeed * .19) + wind.y * .18 + up.y * jitter * .08,
                    -forward.z * (airspeed * (.19 + jitter * .022)) + wind.z * .18,
                },
                life     = pair_life,
                max_life = pair_life,
                size     = .012 + strength * .020 + wind_speed * .0008,
                seed     = trails.seed,
                side     = u8(side),
                curve    = trails_curve * (.7 + next_random(&trails.seed) * .3),
            }
            trails.count += 1
        }
        trails.spawn -= 1
    }
    write := 0
    for read in 0 ..< trails.count {
        particle := &trails.particles[read]
        particle.life -= dt
        if particle.life <= 0 do continue
        age := 1 - particle.life / particle.max_life
        particle.velocity.x += trails_right.x * particle.curve * age * dt
        particle.velocity.y += trails_right.y * particle.curve * age * dt
        particle.velocity.z += trails_right.z * particle.curve * age * dt
        particle.velocity.y -= .025 * dt
        particle.position.x += particle.velocity.x * dt
        particle.position.y += particle.velocity.y * dt
        particle.position.z += particle.velocity.z * dt
        if write != read do trails.particles[write] = particle^
        write += 1
    }
    trails.count = write
}
