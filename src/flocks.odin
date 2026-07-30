package main

import boats "../packages/boats"
import flocks "../packages/flocks"
import harbor "../packages/harbor"
import marina "../packages/marina"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import rl "zelda_engine:canvas2d"

TOWN_GROUND_FLOCK_LIMIT :: 4

bird_building_avoidance_velocity :: proc(
    position, velocity: flocks.Vec3,
    structure: terrain.Structure,
    dt: f32,
) -> flocks.Vec3 {
    if structure.kind != .Architecture || structure.height <= 0 do return velocity
    speed := f32(math.sqrt(f64(velocity.x * velocity.x + velocity.z * velocity.z)))
    lookahead_seconds := clamp(.45 + speed * .055, f32(.45), f32(1.15))
    predicted := position + velocity * lookahead_seconds
    cosine, sine := math.cos(structure.rotation), math.sin(structure.rotation)
    dx, dz := predicted.x - structure.center_x, predicted.z - structure.center_z
    local_x := dx * cosine + dz * sine
    local_z := -dx * sine + dz * cosine
    margin := 1.4 + speed * .12
    half_x := structure.width * .5 + margin
    half_z := structure.depth * .5 + margin
    roof := structure.base_y + structure.height
    if abs(local_x) > half_x || abs(local_z) > half_z || predicted.y < structure.base_y - 1 || predicted.y > roof + 4 {
        return velocity
    }

    penetration_x := half_x - abs(local_x)
    penetration_z := half_z - abs(local_z)
    local_away := [2]f32{}
    if penetration_x < penetration_z {
        local_away.x = local_x < 0 ? f32(-1) : f32(1)
    } else {
        local_away.y = local_z < 0 ? f32(-1) : f32(1)
    }
    away := flocks.Vec3{local_away.x * cosine - local_away.y * sine, 0, local_away.x * sine + local_away.y * cosine}
    urgency := clamp(1 - min(penetration_x, penetration_z) / max(margin, f32(.01)), f32(.25), f32(1))
    result := velocity
    result.x += away.x * (7 + speed * .55) * urgency * min(dt * 8, f32(1))
    result.z += away.z * (7 + speed * .55) * urgency * min(dt * 8, f32(1))
    roof_clearance := roof + 2.5 - predicted.y
    if roof_clearance > 0 {
        result.y += clamp(roof_clearance * .7, f32(1.2), f32(5)) * min(dt * 6, f32(1))
    }
    return result
}

world_flocks_avoid_buildings :: proc(editor: ^Editor, system: ^flocks.System, dt: f32) {
    if editor == nil || system == nil || dt <= 0 || editor.project.structure_count <= 0 do return
    for &boid in system.boids[:system.boid_count] {
        if boid.mode != .Flying do continue
        original := boid.velocity
        best := original
        best_change_squared := f32(0)
        for structure in editor.project.structures[:editor.project.structure_count] {
            candidate := bird_building_avoidance_velocity(boid.position, original, structure, dt)
            change := candidate - original
            change_squared := linalg.dot(change, change)
            if change_squared > best_change_squared {
                best, best_change_squared = candidate, change_squared
            }
        }
        boid.velocity = best
    }
}

world_flocks_step :: proc(editor: ^Editor, dt: f32) {
    if editor == nil do return
    anchors: [flocks.MAX_FLOCKS]flocks.Anchor
    count := 0
    for &plan, index in editor.default_harbors[:editor.default_marina_count] {
        if count >= len(anchors) do break
        office := plan.office
        anchors[count] = {
            position      = {office.x, editor.project.sea_level, office.z},
            kind          = .Harbor,
            movement      = .Patrol,
            seed          = plan.seed ~ u32(index) * 0x9e3779b9,
            patrol_radius = 26 + f32(index % 3) * 5,
            patrol_speed  = 3.8 + f32(index % 2) * .7,
        }
        count += 1
    }
    if editor.marina_authored && count < len(anchors) {
        plan := &editor.marina_authored_plan
        office := marina.plan_world_position(plan, {plan.office.x, plan.office.z})
        anchors[count] = {
            position      = {office.x, editor.project.sea_level, office.z},
            kind          = .Harbor,
            movement      = .Patrol,
            seed          = plan.seed,
            patrol_radius = 28,
            patrol_speed  = 4.1,
        }
        count += 1
    }
    for &agent, index in editor.boat_traffic.agents[:editor.boat_traffic.count] {
        if count >= len(anchors) do break
        if agent.class != .Fishing || agent.behavior == .Moored do continue
        anchors[count] = {
            position = {agent.position.x, editor.project.sea_level, agent.position.y},
            kind     = .Fishing,
            seed     = 0xf1570000 ~ u32(index),
        }
        count += 1
    }
    flocks.sync_anchors(&editor.bird_flocks, anchors[:count])
    flocks.step_markers(&editor.bird_flocks, dt)
    flocks.step(&editor.bird_flocks, dt, {editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]})
    world_flocks_avoid_buildings(editor, &editor.bird_flocks, dt)

    ground_anchors: [flocks.MAX_FLOCKS]flocks.Anchor
    ground_count := 0
    for &plan, index in editor.default_harbors[:editor.default_marina_count] {
        if ground_count >= len(ground_anchors) do break
        office := harbor.add(plan.office, harbor.add(harbor.scale(plan.tangent, 4.6), harbor.scale(plan.outward, 3.5)))
        ground_anchors[ground_count] = {
            position = {office.x, mouse_surface_height(editor, office.x, office.z), office.z},
            kind     = .Harbor,
            seed     = plan.seed ~ 0x67726f75 ~ u32(index) * 0x85ebca6b,
        }
        ground_count += 1
    }
    if editor.marina_authored && ground_count < len(ground_anchors) {
        plan := &editor.marina_authored_plan
        office := marina.plan_world_position(plan, {plan.office.x + 4.6, plan.office.z + 3.5})
        ground_anchors[ground_count] = {
            position = {office.x, mouse_surface_height(editor, office.x, office.z), office.z},
            kind     = .Harbor,
            seed     = plan.seed ~ 0x67726f75,
        }
        ground_count += 1
    }
    town_flocks := 0
    circulation_plan := editor_circulation_plan(editor)
    if circulation_plan != nil {
        for area, area_index in circulation_plan.areas[:circulation_plan.count] {
            if ground_count >= len(ground_anchors) || town_flocks >= TOWN_GROUND_FLOCK_LIMIT do break
            if area.kind != .Plaza || !area.walkable do continue
            // Offset slightly from the exact plaza center so the birds leave
            // the principal pedestrian crossing clear while remaining in the
            // open, readable public space.
            offset_angle := f32(area_index) * 2.399963
            x := area.center_x + math.cos(offset_angle) * min(area.width * .18, f32(3))
            z := area.center_z + math.sin(offset_angle) * min(area.length * .18, f32(3))
            ground_anchors[ground_count] = {
                position = {x, mouse_surface_height(editor, x, z), z},
                kind     = .Harbor,
                seed     = 0x746f776e ~ u32(area_index) * 0x9e3779b9,
            }
            ground_count += 1
            town_flocks += 1
        }
    }
    flocks.sync_ground_anchors(&editor.ground_bird_flocks, ground_anchors[:ground_count])
    for &boid in editor.ground_bird_flocks.boids[:editor.ground_bird_flocks.boid_count] {
        if boid.mode == .Flying do continue
        boid.ground_y = mouse_surface_height(editor, boid.position.x, boid.position.z) + .12
        boid.position.y = boid.ground_y
    }
    player_speed := f32(
        math.sqrt(
            f64(
                editor.player.velocity.x * editor.player.velocity.x +
                editor.player.velocity.z * editor.player.velocity.z,
            ),
        ),
    )
    threat_position := third_person.Vec3{editor.player.position.x, editor.player.position.y, editor.player.position.z}
    threat_active := editor.in_map && editor.pilot.mode == .On_Foot && editor.player.grounded && player_speed >= 1.5
    if editor.in_map && editor.pilot.mode == .Driving && editor.pilot.vehicle != nil {
        threat_position = editor.pilot.vehicle.position
        threat_active = true
    }
    flocks.step_grounded(
        &editor.ground_bird_flocks,
        dt,
        {editor.atmosphere.weather.wind[0], editor.atmosphere.weather.wind[1]},
        {threat_position.x, threat_position.y, threat_position.z},
        threat_active,
    )
    world_flocks_avoid_buildings(editor, &editor.ground_bird_flocks, dt)
}

world_bird_double_triangle :: proc(a, b, c: third_person.Vec3, color: rl.Color) {
    world_triangle(a, b, c, color)
    world_triangle(c, b, a, color)
}

world_bird :: proc(position, velocity: flocks.Vec3, phase: f32) {
    forward := third_person.Vec3{velocity.x, velocity.y * .35, velocity.z}
    speed := f32(math.sqrt(f64(forward.x * forward.x + forward.y * forward.y + forward.z * forward.z)))
    if speed <= .01 do return
    forward /= speed
    right := linalg.normalize0(linalg.cross(third_person.Vec3{0, 1, 0}, forward))
    up := linalg.normalize0(linalg.cross(forward, right))
    center := third_person.Vec3{position.x, position.y, position.z}
    white := rl.Color{230, 232, 222, 255}
    shadow := rl.Color{184, 192, 190, 255}
    mantle := rl.Color{166, 177, 179, 255}
    charcoal := rl.Color{54, 64, 68, 255}
    beak := rl.Color{218, 157, 62, 255}

    tail_root := center - forward * .26
    chest := center + forward * .25 + up * .015
    world_tube_between(tail_root, chest, up, .115, .14, white)
    head_center := center + forward * .34 + up * .075
    world_tube_between(chest, head_center, up, .11, .105, white)

    beak_base_left := head_center - right * .055 - up * .02
    beak_base_right := head_center + right * .055 - up * .02
    beak_top := head_center + up * .055
    beak_tip := head_center + forward * .17 - up * .025
    world_triangle(beak_base_left, beak_base_right, beak_tip, beak)
    world_triangle(beak_base_right, beak_top, beak_tip, beak)
    world_triangle(beak_top, beak_base_left, beak_tip, beak)
    eye_sides := [2]f32{-1, 1}
    for side in eye_sides {
        eye_center := head_center + forward * .045 + right * side * .098 + up * .045
        world_bird_double_triangle(
            eye_center + forward * .018,
            eye_center - forward * .014 + up * .016,
            eye_center - forward * .014 - up * .016,
            charcoal,
        )
    }

    // Broad, slightly swept gull wings: pale inner coverts and charcoal
    // primaries at the tips. The two faces keep the silhouette readable from
    // above, below, and during the full flap cycle.
    // Seabirds alternate short flapping bouts with long, shallow-dihedral
    // glides instead of beating continuously.
    flap_effort := clamp(math.sin(phase * .18) * 3 + .35, f32(0), f32(1))
    flap := f32(math.sin(phase) * .22 * flap_effort + (1 - flap_effort) * .045)
    shoulder_forward := center + forward * .08
    sides := [2]f32{-1, 1}
    for side in sides {
        root_front := shoulder_forward + right * side * .08 + up * .035
        root_back := center - forward * .17 + right * side * .07
        wrist := center - forward * .04 + right * side * .43 + up * flap
        wrist_back := center - forward * .19 + right * side * .34 + up * (flap * .82 - .025)
        tip := center - forward * .20 + right * side * .70 + up * (flap * 1.18 - .015)
        tip_back := center - forward * .31 + right * side * .58 + up * (flap - .035)
        world_bird_double_triangle(root_front, wrist, wrist_back, mantle)
        world_bird_double_triangle(root_front, wrist_back, root_back, shadow)
        world_bird_double_triangle(wrist, tip, tip_back, charcoal)
        world_bird_double_triangle(wrist, tip_back, wrist_back, charcoal)
    }

    tail_left := tail_root - right * .12
    tail_right := tail_root + right * .12
    tail_notch := tail_root - forward * .11
    tail_left_tip := tail_root - forward * .20 - right * .15
    tail_right_tip := tail_root - forward * .20 + right * .15
    world_bird_double_triangle(tail_left, tail_left_tip, tail_notch, white)
    world_bird_double_triangle(tail_notch, tail_right_tip, tail_right, white)
}

world_ground_bird :: proc(position, velocity: flocks.Vec3, phase: f32) {
    forward := third_person.Vec3{velocity.x, 0, velocity.z}
    speed := f32(math.sqrt(f64(forward.x * forward.x + forward.z * forward.z)))
    if speed <= .01 {
        forward = {0, 0, 1}
    } else {
        forward /= speed
    }
    right := third_person.Vec3{-forward.z, 0, forward.x}
    up := third_person.Vec3{0, 1, 0}
    foot := third_person.Vec3{position.x, position.y, position.z}
    body := foot + up * .19
    head_bob := f32(math.sin(phase * 2.1) * .018)
    white := rl.Color{230, 232, 222, 255}
    mantle := rl.Color{166, 177, 179, 255}
    charcoal := rl.Color{54, 64, 68, 255}
    ochre := rl.Color{218, 157, 62, 255}

    tail := body - forward * .25
    chest := body + forward * .20 + up * .025
    world_tube_between(tail, chest, up, .105, .13, white)
    head := chest + forward * .075 + up * (.105 + head_bob)
    world_tube_between(chest, head, forward, .09, .085, white)
    beak_tip := head + forward * .15 - up * .015
    world_bird_double_triangle(head - right * .055, head + right * .055, beak_tip, ochre)

    // Folded wings make a compact gray teardrop on either side of the body.
    sides := [2]f32{-1, 1}
    for side in sides {
        shoulder := body + forward * .11 + right * side * .105 + up * .055
        wing_tip := body - forward * .24 + right * side * .115 + up * .005
        lower := body - forward * .10 + right * side * .125 - up * .055
        world_bird_double_triangle(shoulder, wing_tip, lower, mantle)
        dark_tip := body - forward * .29 + right * side * .105
        world_bird_double_triangle(wing_tip, dark_tip, lower, charcoal)
    }
    for side in sides {
        ankle := foot + right * side * .055 + up * .035
        world_tube_between(ankle, foot + right * side * .055, forward, .012, .012, ochre)
    }
}

world_bird_flocks :: proc(editor: ^Editor) {
    if editor == nil || !editor.in_map do return
    for boid, index in editor.bird_flocks.boids[:editor.bird_flocks.boid_count] {
        if !world_sphere_in_view(editor, {boid.position.x, boid.position.y, boid.position.z}, 1) do continue
        world_bird(boid.position, boid.velocity, editor.map_time * 8 + f32(index) * .73)
    }
    for boid, index in editor.ground_bird_flocks.boids[:editor.ground_bird_flocks.boid_count] {
        if !world_sphere_in_view(editor, {boid.position.x, boid.position.y, boid.position.z}, 1) do continue
        if boid.mode == .Flying {
            world_bird(boid.position, boid.velocity, editor.map_time * 8 + f32(index) * .73)
        } else {
            world_ground_bird(boid.position, boid.velocity, editor.map_time + f32(index) * .91)
        }
    }
}
