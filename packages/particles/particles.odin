package particles

import "core:math"

MAX_CPU_PARTICLES :: 384
MAX_DUST_PARTICLES :: 256
MAX_EXHAUST_PARTICLES :: 128
MAX_WING_TRAIL_PARTICLES :: 192

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
}

Vehicle_Particle :: struct {
	position: Vec3,
	velocity: Vec3,
	life:     f32,
	max_life: f32,
	size:     f32,
	seed:     u32,
}

Vehicle_Effects :: struct {
	dust:          [MAX_DUST_PARTICLES]Vehicle_Particle,
	dust_count:    int,
	exhaust:       [MAX_EXHAUST_PARTICLES]Vehicle_Particle,
	exhaust_count: int,
	dust_spawn:    f32,
	exhaust_spawn: f32,
	seed:          u32,
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
		position = {
			origin.x + math.cos(angle) * (r1 * 1.8),
			origin.y,
			origin.z + math.sin(angle) * (r1 * 1.8),
		},
		velocity = {
			math.cos(angle) * (.35 + r1 * .55),
			.45 + r2 * .75,
			math.sin(angle) * (.35 + r1 * .55),
		},
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

active_count :: proc(system: ^Cpu_System) -> int {return system.count}

new_vehicle_effects :: proc(seed: u32) -> Vehicle_Effects {return {seed = seed}}

new_wing_trails :: proc(seed: u32) -> Wing_Trails {return {seed = seed}}

spawn_dust :: proc(effects: ^Vehicle_Effects, contact: Vehicle_Contact, intensity: f32) {
	if effects.dust_count >= MAX_DUST_PARTICLES || !contact.grounded do return
	spread := next_random(&effects.seed) - .5
	lift := next_random(&effects.seed)
	particle := &effects.dust[effects.dust_count]
	particle^ = {
		position = {
			contact.position.x + spread * .18,
			contact.position.y + .045,
			contact.position.z + spread * .18,
		},
		velocity = {spread * (.35 + intensity), .18 + lift * .32, spread * (.35 + intensity)},
		life     = .28 + lift * .42,
		max_life = .28 + lift * .42,
		size     = .08 + intensity * .08 + lift * .10,
		seed     = effects.seed,
	}
	effects.dust_count += 1
}

spawn_exhaust :: proc(effects: ^Vehicle_Effects, position: Vec3, yaw: f32, intensity: f32) {
	if effects.exhaust_count >= MAX_EXHAUST_PARTICLES do return
	forward := Vec3{math.cos(yaw), 0, math.sin(yaw)}
	spread := next_random(&effects.seed) - .5
	lift := next_random(&effects.seed)
	particle := &effects.exhaust[effects.exhaust_count]
	particle^ = {
		position = {
			position.x - forward.x * 1.92,
			position.y + .42,
			position.z - forward.z * 1.92,
		},
		velocity = {
			-forward.x * (.25 + intensity * .45) + spread * .22,
			.08 + lift * .15,
			-forward.z * (.25 + intensity * .45) + spread * .22,
		},
		life     = .34 + lift * .42,
		max_life = .34 + lift * .42,
		size     = .055 + intensity * .045 + lift * .06,
		seed     = effects.seed,
	}
	effects.exhaust_count += 1
}

step_vehicle_effects :: proc(
	effects: ^Vehicle_Effects,
	delta_seconds: f32,
	position: Vec3,
	yaw, speed, steering, throttle: f32,
	handbrake: bool,
	contacts: [4]Vehicle_Contact,
) {
	dt := clamp(delta_seconds, 0, .05)
	intensity := clamp(
		speed / 12 + abs(steering) * speed / 18 + (handbrake ? f32(.65) : f32(0)),
		0,
		1.5,
	)
	effects.dust_spawn += dt * intensity * 48
	for effects.dust_spawn >= 1 {
		for index in 0 ..< 4 {
			if intensity > .18 do spawn_dust(effects, contacts[index], intensity)
		}
		effects.dust_spawn -= 1
	}
	exhaust_intensity := clamp(abs(throttle) * .7 + speed / 32, 0, 1)
	effects.exhaust_spawn += dt * (4 + exhaust_intensity * 22)
	for effects.exhaust_spawn >= 1 {
		if exhaust_intensity > .02 do spawn_exhaust(effects, position, yaw, exhaust_intensity)
		effects.exhaust_spawn -= 1
	}
	write := 0
	for read in 0 ..< effects.dust_count {
		particle := &effects.dust[read]
		particle.life -= dt
		if particle.life <= 0 do continue
		particle.velocity.y += .22 * dt
		particle.position.x += particle.velocity.x * dt
		particle.position.y += particle.velocity.y * dt
		particle.position.z += particle.velocity.z * dt
		if write != read do effects.dust[write] = particle^
		write += 1
	}
	effects.dust_count = write
	write = 0
	for read in 0 ..< effects.exhaust_count {
		particle := &effects.exhaust[read]
		particle.life -= dt
		if particle.life <= 0 do continue
		particle.velocity.y += .06 * dt
		particle.position.x += particle.velocity.x * dt
		particle.position.y += particle.velocity.y * dt
		particle.position.z += particle.velocity.z * dt
		if write != read do effects.exhaust[write] = particle^
		write += 1
	}
	effects.exhaust_count = write
}

step_wing_trails :: proc(
	trails: ^Wing_Trails,
	delta_seconds: f32,
	left_tip, right_tip, forward, up, wind: Vec3,
	airspeed: f32,
) {
	dt := clamp(delta_seconds, 0, .05)
	wind_speed := f32(math.sqrt(f64(wind.x * wind.x + wind.z * wind.z)))
	strength := clamp((airspeed - 12) / 34, 0, 1) * (1 + wind_speed * .025)
	trails.spawn += dt * strength * 72
	trails_curve := wind.x * forward.z - wind.z * forward.x
	trails_right := Vec3 {
		x = forward.y * up.z - forward.z * up.y,
		y = forward.z * up.x - forward.x * up.z,
		z = forward.x * up.y - forward.y * up.x,
	}
	for trails.spawn >= 1 {
		for side in 0 ..< 2 {
			if trails.count >= MAX_WING_TRAIL_PARTICLES do break
			tip := side == 0 ? left_tip : right_tip
			jitter := next_random(&trails.seed) - .5
			life := .55 + next_random(&trails.seed) * (.55 + wind_speed * .02)
			particle := &trails.particles[trails.count]
			particle^ = {
				position = {tip.x, tip.y, tip.z},
				velocity = {
					-forward.x * (airspeed * (.22 + jitter * .025)) + wind.x * .18,
					-forward.y * (airspeed * .22) + wind.y * .18 + up.y * jitter * .08,
					-forward.z * (airspeed * (.22 + jitter * .025)) + wind.z * .18,
				},
				life     = life,
				max_life = life,
				size     = .09 + strength * .12 + wind_speed * .004,
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
