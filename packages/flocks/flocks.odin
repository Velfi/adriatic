package flocks

import "core:math"
import "core:math/linalg"

BOIDS_PER_FLOCK :: 9
STRESS_BOID_COUNT :: 10_000
MAX_FLOCKS :: (STRESS_BOID_COUNT + BOIDS_PER_FLOCK - 1) / BOIDS_PER_FLOCK
MAX_BOIDS :: MAX_FLOCKS * BOIDS_PER_FLOCK

Vec3 :: [3]f32

Anchor_Kind :: enum u8 {
    Harbor,
    Fishing,
}

Anchor_Movement :: enum u8 {
    External,
    Patrol,
}

Anchor :: struct {
    position:      Vec3,
    home_position: Vec3,
    velocity:      Vec3,
    kind:          Anchor_Kind,
    movement:      Anchor_Movement,
    seed:          u32,
    patrol_radius: f32,
    patrol_speed:  f32,
    patrol_phase:  f32,
}

Boid_Mode :: enum u8 {
    Flying,
    Grounded,
    Launching,
}

Boid :: struct {
    position:     Vec3,
    velocity:     Vec3,
    flock:        int,
    mode:         Boid_Mode,
    ground_y:     f32,
    launch_delay: f32,
    wander_phase: f32,
}

System :: struct {
    boids:        [MAX_BOIDS]Boid,
    boid_count:   int,
    anchors:      [MAX_FLOCKS]Anchor,
    anchor_count: int,
}

hash01 :: proc(value: u32) -> f32 {
    hash := value
    hash ~= hash >> 16
    hash *= 0x7feb352d
    hash ~= hash >> 15
    hash *= 0x846ca68b
    hash ~= hash >> 16
    return f32(hash & 0xffff) / 65535
}

spawn_flock :: proc(system: ^System, flock: int) {
    anchor := system.anchors[flock]
    first := flock * BOIDS_PER_FLOCK
    for local in 0 ..< BOIDS_PER_FLOCK {
        index := first + local
        angle := hash01(anchor.seed + u32(local) * 17) * math.PI * 2
        radius := 5 + hash01(anchor.seed + u32(local) * 41) * 12
        altitude := 10 + hash01(anchor.seed + u32(local) * 73) * 8
        system.boids[index] = {
            position = anchor.position + Vec3{math.cos(angle) * radius, altitude, math.sin(angle) * radius},
            velocity = {-math.sin(angle) * 7, 0, math.cos(angle) * 7},
            flock    = flock,
        }
    }
}

spawn_ground_flock :: proc(system: ^System, flock: int) {
    anchor := system.anchors[flock]
    first := flock * BOIDS_PER_FLOCK
    for local in 0 ..< BOIDS_PER_FLOCK {
        index := first + local
        angle := hash01(anchor.seed + u32(local) * 29) * math.PI * 2
        radius := 1.2 + hash01(anchor.seed + u32(local) * 53) * 3.2
        heading := hash01(anchor.seed + u32(local) * 79) * math.PI * 2
        system.boids[index] = {
            position     = anchor.position + Vec3{math.cos(angle) * radius, 0, math.sin(angle) * radius},
            velocity     = {math.cos(heading) * .28, 0, math.sin(heading) * .28},
            flock        = flock,
            mode         = .Grounded,
            ground_y     = anchor.position.y,
            wander_phase = heading,
        }
    }
}

sync_anchors :: proc(system: ^System, anchors: []Anchor) {
    count := min(len(anchors), MAX_FLOCKS)
    old_count := system.anchor_count
    system.anchor_count = count
    for anchor, index in anchors[:count] {
        changed :=
            index >= old_count ||
            system.anchors[index].kind != anchor.kind ||
            system.anchors[index].movement != anchor.movement ||
            system.anchors[index].seed != anchor.seed ||
            linalg.dot(
                system.anchors[index].position - anchor.position,
                system.anchors[index].position - anchor.position,
            ) >
                40 * 40
        if changed {
            system.anchors[index] = anchor
            system.anchors[index].home_position = anchor.position
            system.anchors[index].patrol_phase = hash01(anchor.seed ~ 0xa511e9b3) * math.PI * 2
            spawn_flock(system, index)
        } else if anchor.movement == .External {
            previous := system.anchors[index].position
            system.anchors[index] = anchor
            system.anchors[index].home_position = anchor.position
            system.anchors[index].velocity = anchor.position - previous
        } else {
            system.anchors[index].home_position = anchor.position
            system.anchors[index].kind = anchor.kind
            system.anchors[index].patrol_radius = anchor.patrol_radius
            system.anchors[index].patrol_speed = anchor.patrol_speed
        }
    }
    system.boid_count = count * BOIDS_PER_FLOCK
}

step_markers :: proc(system: ^System, dt: f32) {
    if system == nil || dt <= 0 do return
    step_seconds := min(dt, f32(.05))
    for &anchor in system.anchors[:system.anchor_count] {
        if anchor.movement != .Patrol do continue
        radius := max(anchor.patrol_radius, f32(1))
        speed := max(anchor.patrol_speed, f32(.1))
        previous := anchor.position
        anchor.patrol_phase += speed / radius * step_seconds
        anchor.position =
            anchor.home_position +
            Vec3 {
                    math.cos(anchor.patrol_phase) * radius,
                    math.sin(anchor.patrol_phase * .53) * 2.5,
                    math.sin(anchor.patrol_phase) * radius * .72,
                }
        anchor.velocity = (anchor.position - previous) / step_seconds
    }
}

sync_ground_anchors :: proc(system: ^System, anchors: []Anchor) {
    count := min(len(anchors), MAX_FLOCKS)
    old_count := system.anchor_count
    system.anchor_count = count
    for anchor, index in anchors[:count] {
        delta := system.anchors[index].position - anchor.position
        changed :=
            index >= old_count || system.anchors[index].seed != anchor.seed || linalg.dot(delta, delta) > 40 * 40
        system.anchors[index] = anchor
        system.anchors[index].home_position = anchor.position
        if changed do spawn_ground_flock(system, index)
    }
    system.boid_count = count * BOIDS_PER_FLOCK
}

step :: proc(system: ^System, dt: f32, wind: [2]f32) {
    if system == nil || dt <= 0 || system.boid_count <= 0 do return
    step_seconds := min(dt, f32(.05))
    for flock in 0 ..< system.anchor_count {
        flock_first := flock * BOIDS_PER_FLOCK
        flock_last := min(flock_first + BOIDS_PER_FLOCK, system.boid_count)
        if flock_first >= flock_last do break
        snapshot: [BOIDS_PER_FLOCK]Boid
        copy(snapshot[:], system.boids[flock_first:flock_last])
        for boid, local_index in snapshot[:flock_last - flock_first] {
            index := flock_first + local_index
            if boid.mode != .Flying do continue
            separation, alignment, cohesion: Vec3
            neighbors := 0
            for other, other_index in snapshot[:flock_last - flock_first] {
                if other_index == local_index do continue
                delta := other.position - boid.position
                distance_squared := linalg.dot(delta, delta)
                if distance_squared > 18 * 18 || distance_squared < .001 do continue
                neighbors += 1
                alignment += other.velocity
                cohesion += other.position
                if distance_squared < 5 * 5 {
                    separation -= delta / max(distance_squared, f32(.25))
                }
            }
            acceleration: Vec3
            if neighbors > 0 {
                inverse := 1 / f32(neighbors)
                acceleration += separation * 22
                acceleration += (alignment * inverse - boid.velocity) * .65
                acceleration += (cohesion * inverse - boid.position) * .20
            }
            anchor := system.anchors[boid.flock]
            orbit := anchor.position + Vec3{0, anchor.kind == .Fishing ? f32(13) : f32(17), 0}
            to_anchor := orbit - boid.position
            acceleration += Vec3{to_anchor.x, to_anchor.y * 1.8, to_anchor.z} * .10
            acceleration += Vec3{wind.x * .12, 0, wind.y * .12}
            velocity := boid.velocity + acceleration * step_seconds
            horizontal_speed := f32(math.sqrt(f64(velocity.x * velocity.x + velocity.z * velocity.z)))
            target_speed := anchor.kind == .Fishing ? f32(8.5) : f32(7)
            if horizontal_speed > .01 {
                scale := clamp(target_speed / horizontal_speed, f32(.72), f32(1.3))
                velocity.x *= scale
                velocity.z *= scale
            }
            velocity.y = clamp(velocity.y, f32(-2.5), f32(2.5))
            system.boids[index].velocity = velocity
            system.boids[index].position = boid.position + velocity * step_seconds
        }
    }
}

step_grounded :: proc(system: ^System, dt: f32, wind: [2]f32, threat_position: Vec3, threat_running: bool) {
    if system == nil || dt <= 0 do return
    step_seconds := min(dt, f32(.05))
    for flock in 0 ..< system.anchor_count {
        first := flock * BOIDS_PER_FLOCK
        last := min(first + BOIDS_PER_FLOCK, system.boid_count)
        if first >= last do break
        anchor := system.anchors[flock]
        threat_delta := threat_position - anchor.position
        scare := threat_running && threat_delta.x * threat_delta.x + threat_delta.z * threat_delta.z <= 12 * 12
        if scare {
            for local in 0 ..< last - first {
                boid := &system.boids[first + local]
                if boid.mode != .Grounded do continue
                boid.mode = .Launching
                boid.launch_delay = f32(local) * .055 + hash01(anchor.seed + u32(local) * 101) * .10
            }
        }
        for local in 0 ..< last - first {
            boid := &system.boids[first + local]
            switch boid.mode {
            case .Grounded:
                boid.wander_phase += (.32 + hash01(anchor.seed + u32(local) * 131) * .28) * step_seconds
                desired := Vec3{math.cos(boid.wander_phase) * .34, 0, math.sin(boid.wander_phase) * .34}
                to_anchor := anchor.position - boid.position
                distance_squared := to_anchor.x * to_anchor.x + to_anchor.z * to_anchor.z
                if distance_squared > 4.5 * 4.5 {
                    desired.x += to_anchor.x * .25
                    desired.z += to_anchor.z * .25
                }
                boid.velocity += (desired - boid.velocity) * min(step_seconds * 2.4, f32(1))
                boid.position += boid.velocity * step_seconds
                boid.position.y = boid.ground_y
            case .Launching:
                boid.launch_delay -= step_seconds
                if boid.launch_delay > 0 do continue
                away := boid.position - threat_position
                away.y = 0
                length := f32(math.sqrt(f64(away.x * away.x + away.z * away.z)))
                if length <= .01 {
                    away = {math.cos(boid.wander_phase), 0, math.sin(boid.wander_phase)}
                } else {
                    away /= length
                }
                boid.mode = .Flying
                boid.velocity = {away.x * 5.5, 4.5 + f32(local % 3) * .35, away.z * 5.5}
                boid.position.y = boid.ground_y + .12
            case .Flying:
            }
        }
    }
    step(system, step_seconds, wind)
}
