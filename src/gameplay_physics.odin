package main

import boats "../packages/boats"
import terrain "../packages/terrain"
import third_person "../packages/third_person"
import vehicles "../packages/vehicles"
import "core:math"
import "core:math/linalg"
import physics "zelda_engine:physics"

GAMEPLAY_PHYSICS_FIXED_STEP :: f64(1.0 / 120.0)
GAMEPLAY_PHYSICS_MAX_CATCH_UP :: f64(.1)
GAMEPLAY_PLAYER_HALF_HEIGHT :: f32(.18)
GAMEPLAY_PLAYER_RADIUS :: f32(.24)
GAMEPLAY_PLAYER_STEP_HEIGHT :: f32(.18)
GAMEPLAY_PLAYER_STEP_DOWN :: f32(.24)

Gameplay_Physics :: struct {
    world:                 physics.World,
    player:                physics.Character,
    player_tail_proxy:     physics.Body_ID,
    terrain:               [terrain.CLIPMAP_LEVELS]physics.Body_ID,
    static_bodies:         [dynamic]physics.Body_ID,
    boat_bodies:           [boats.TRAFFIC_CAPACITY]physics.Body_ID,
    boat_count:            int,
    accumulator:           f64,
    terrain_revision:      u64,
    structure_revision:    u64,
    stepped_this_frame:    bool,
    player_position:       third_person.Vec3,
    player_position_valid: bool,
}

Player_Placement_Reason :: enum {
    Startup,
    Reset,
    Teleport,
    Vehicle_Exit,
    Crash_Recovery,
    Scene_Setup,
    Aircraft_Selection,
}

// player_place is the sole boundary for discontinuous on-foot movement.
// Continuous walking remains physics-driven in gameplay_physics_resolve_player.
// Keeping the presentation, occupancy, and physics representations together
// prevents a stale character body from undoing a spawn on the next step.
player_place :: proc(
    editor: ^Editor,
    position: third_person.Vec3,
    reason: Player_Placement_Reason,
    facing_yaw_radians: f32 = 0,
    grounded: bool = true,
) {
    if editor == nil do return
    if editor.pilot.vehicle != nil {
        editor.pilot.vehicle.driver = nil
    }
    editor.pilot.vehicle = nil
    editor.pilot.mode = vehicles.Occupancy_Mode.On_Foot
    editor.player.position = position
    editor.player.velocity = {}
    editor.player.facing_yaw_radians = facing_yaw_radians
    editor.player.grounded = grounded
    editor.pilot.position = position
    editor.pilot.facing_yaw_radians = facing_yaw_radians
    editor.player_stride_phase = 0
    editor.player_gait_weight = 0
    editor.player_airborne_weight = 0
    editor.player_animation_previous_speed = 0
    editor.player_placement_reason = reason
    editor.player_placement_revision += 1
    gameplay_physics_teleport_player(editor)
}

gameplay_physics_destroy :: proc(editor: ^Editor) {
    if editor == nil do return
    state := &editor.gameplay_physics
    if state.world != nil {
        if state.player != nil do physics.destroy_character(state.world, state.player)
        physics.destroy_world(state.world)
    }
    delete(state.static_bodies)
    state^ = {}
}

gameplay_physics_add_terrain :: proc(editor: ^Editor) -> bool {
    state := &editor.gameplay_physics
    state.player_tail_proxy = physics.INVALID_BODY
    collision_heights := make([]f32, terrain.SAMPLES_PER_LEVEL)
    defer delete(collision_heights)
    for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
        level := &editor.project.levels[level_index]
        car_physics_level_heights(editor, level_index, collision_heights)
        state.terrain[level_index] = physics.add_height_field(
            state.world,
            collision_heights,
            terrain.RING_RESOLUTION,
            {level.origin_x, 0, level.origin_z},
            {level.cell_size, 1, level.cell_size},
            4,
            8,
            user_data = u64(0x1000 + level_index),
        )
        if state.terrain[level_index] == physics.INVALID_BODY do return false
    }
    state.terrain_revision = editor.terrain_revision
    return true
}

gameplay_physics_rebuild_structures :: proc(editor: ^Editor) {
    if editor == nil || editor.gameplay_physics.world == nil do return
    state := &editor.gameplay_physics
    for body in state.static_bodies do physics.remove_body(state.world, body)
    clear(&state.static_bodies)
    for structure, index in editor.project.structures[:editor.project.structure_count] {
        if structure.kind == .Foliage || structure.width <= 0 || structure.depth <= 0 || structure.height <= 0 {
            continue
        }
        half_extent := physics.Vec3 {
            max(structure.width * .5, f32(.02)),
            max(structure.height * .5, f32(.02)),
            max(structure.depth * .5, f32(.02)),
        }
        half_yaw := structure.rotation * .5
        rotation := physics.Quat{0, math.sin(half_yaw), 0, math.cos(half_yaw)}
        body := physics.add_box_layered(
            state.world,
            half_extent,
            {structure.center_x, structure.base_y + structure.height * .5, structure.center_z},
            rotation = rotation,
            user_data = u64(0x2000_0000) | u64(index),
        )
        if body != physics.INVALID_BODY do append(&state.static_bodies, body)
    }
    state.structure_revision = editor.project.revision
}

gameplay_physics_create :: proc(editor: ^Editor) -> bool {
    if editor == nil do return false
    gameplay_physics_destroy(editor)
    state := &editor.gameplay_physics
    // Adriatic's active map stays well below this body count. Four workers
    // amortize the unified soft-body, vehicle and contact step without
    // dispatching across every hardware thread.
    state.world = physics.create_world(8_192, 4)
    if state.world == nil do return false
    physics.set_gravity(state.world, {0, -9.81, 0})
    // CharacterVirtual remains isolated from the owner's tail proxy. The
    // proxy sees only soft bodies, giving tails owner collision without
    // introducing a controller/self contact.
    physics.set_layer_mask(state.world, .Character, 0xffbf)
    physics.set_layer_mask(state.world, .Soft_Body, 0x01fb)
    physics.set_layer_mask(state.world, .Sensor, 0x0031)
    physics.set_layer_mask(state.world, .Character_Proxy, 0x0040)
    if !gameplay_physics_add_terrain(editor) {
        gameplay_physics_destroy(editor)
        return false
    }
    gameplay_physics_rebuild_structures(editor)
    state.player = physics.create_character(
        state.world,
        GAMEPLAY_PLAYER_HALF_HEIGHT,
        GAMEPLAY_PLAYER_RADIUS,
        {
            editor.player.position.x,
            editor.player.position.y + GAMEPLAY_PLAYER_HALF_HEIGHT + GAMEPLAY_PLAYER_RADIUS,
            editor.player.position.z,
        },
        math.PI * .30,
        mass = 1,
        max_strength = 80,
        user_data = 1,
    )
    if state.player == nil {
        gameplay_physics_destroy(editor)
        return false
    }
    state.player_position = editor.player.position
    state.player_position_valid = true
    gameplay_physics_rebuild_boats(editor)
    return true
}

gameplay_physics_rebuild_boats :: proc(editor: ^Editor) {
    if editor == nil || editor.gameplay_physics.world == nil do return
    state := &editor.gameplay_physics
    for index in 0 ..< state.boat_count {
        if state.boat_bodies[index] != physics.INVALID_BODY {
            physics.remove_body(state.world, state.boat_bodies[index])
        }
    }
    state.boat_bodies = {}
    state.boat_count = min(editor.boat_traffic.count, len(state.boat_bodies))
    for index in 0 ..< state.boat_count {
        agent := &editor.boat_traffic.agents[index]
        spec := boats.specifications(agent.class)
        half_yaw := agent.yaw * .5
        state.boat_bodies[index] = physics.add_box_layered(
            state.world,
            {spec.beam * .42, max(spec.draft * .5, f32(.18)), spec.length * .45},
            {agent.position.x, editor.project.sea_level, agent.position.y},
            .Kinematic,
            rotation = {0, math.sin(half_yaw), 0, math.cos(half_yaw)},
            user_data = u64(0x3000_0000) | u64(index),
            layer = .Boat,
            friction = .35,
        )
    }
}

gameplay_physics_sync_boats :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || editor.gameplay_physics.world == nil || delta_seconds <= 0 do return
    state := &editor.gameplay_physics
    if state.boat_count != editor.boat_traffic.count {
        gameplay_physics_rebuild_boats(editor)
    }
    for index in 0 ..< state.boat_count {
        body := state.boat_bodies[index]
        if body == physics.INVALID_BODY do continue
        agent := &editor.boat_traffic.agents[index]
        half_yaw := agent.yaw * .5
        physics.move_kinematic(
            state.world,
            body,
            {agent.position.x, editor.project.sea_level, agent.position.y},
            {0, math.sin(half_yaw), 0, math.cos(half_yaw)},
            delta_seconds,
        )
    }
}

gameplay_physics_sync_revisions :: proc(editor: ^Editor) {
    if editor == nil || editor.gameplay_physics.world == nil do return
    state := &editor.gameplay_physics
    if state.terrain_revision != editor.terrain_revision {
        collision_heights := make([]f32, terrain.SAMPLES_PER_LEVEL)
        defer delete(collision_heights)
        updated := true
        for level_index in 0 ..< terrain.CLIPMAP_LEVELS {
            car_physics_level_heights(editor, level_index, collision_heights)
            updated =
                physics.update_height_field(
                    state.world,
                    state.terrain[level_index],
                    0,
                    0,
                    terrain.RING_RESOLUTION,
                    terrain.RING_RESOLUTION,
                    collision_heights,
                    terrain.RING_RESOLUTION,
                ) &&
                updated
        }
        if updated do state.terrain_revision = editor.terrain_revision
    }
    if state.structure_revision != editor.project.revision {
        gameplay_physics_rebuild_structures(editor)
    }
}

gameplay_physics_teleport_player :: proc(editor: ^Editor) {
    if editor == nil || editor.gameplay_physics.player == nil do return
    physics.set_character_position(
        editor.gameplay_physics.player,
        {
            editor.player.position.x,
            editor.player.position.y + GAMEPLAY_PLAYER_HALF_HEIGHT + GAMEPLAY_PLAYER_RADIUS,
            editor.player.position.z,
        },
    )
    editor.gameplay_physics.player_position = editor.player.position
    editor.gameplay_physics.player_position_valid = true
}

gameplay_physics_player_needs_teleport :: #force_inline proc(
    position, cached: third_person.Vec3,
    cached_valid: bool,
) -> bool {
    if !cached_valid do return true
    delta := position - cached
    return linalg.dot(delta, delta) > f32(.000001)
}

gameplay_physics_resolve_player :: proc(editor: ^Editor, delta_seconds: f32) -> bool {
    if editor == nil || delta_seconds <= 0 do return false
    if editor.gameplay_physics.world == nil && !gameplay_physics_create(editor) do return false
    gameplay_physics_sync_revisions(editor)
    // Defensive reconciliation for legacy scene/capture setup code. A
    // discontinuous gameplay position change must never be overwritten by a
    // stale physics character on the next frame.
    if gameplay_physics_player_needs_teleport(
        editor.player.position,
        editor.gameplay_physics.player_position,
        editor.gameplay_physics.player_position_valid,
    ) {
        gameplay_physics_teleport_player(editor)
    }
    state, ok := physics.step_character(
        editor.gameplay_physics.world,
        editor.gameplay_physics.player,
        {editor.player.velocity.x, editor.player.velocity.y, editor.player.velocity.z},
        min(delta_seconds, f32(.05)),
        {0, -editor.tweak.player.gravity, 0},
        GAMEPLAY_PLAYER_STEP_HEIGHT,
        GAMEPLAY_PLAYER_STEP_DOWN,
    )
    if !ok do return false
    editor.player.position = {
        state.position.x,
        state.position.y - GAMEPLAY_PLAYER_HALF_HEIGHT - GAMEPLAY_PLAYER_RADIUS,
        state.position.z,
    }
    editor.player.velocity = state.velocity
    editor.player.ground_normal = state.ground_normal
    editor.player.grounded = state.ground_state == .On_Ground || state.ground_state == .On_Steep_Ground
    editor.gameplay_physics.player_position = editor.player.position
    editor.gameplay_physics.player_position_valid = true
    return true
}

gameplay_physics_step_world :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil || editor.gameplay_physics.world == nil || delta_seconds <= 0 do return
    state := &editor.gameplay_physics
    if state.stepped_this_frame do return
    state.stepped_this_frame = true
    state.accumulator = min(state.accumulator + f64(delta_seconds), GAMEPLAY_PHYSICS_MAX_CATCH_UP)
    for state.accumulator >= GAMEPLAY_PHYSICS_FIXED_STEP {
        physics.step(state.world, f32(GAMEPLAY_PHYSICS_FIXED_STEP), 1)
        state.accumulator -= GAMEPLAY_PHYSICS_FIXED_STEP
    }
}

gameplay_physics_begin_frame :: proc(editor: ^Editor) {
    if editor == nil do return
    editor.gameplay_physics.stepped_this_frame = false
}

gameplay_physics_resolve_camera :: proc(
    editor: ^Editor,
    pose: third_person.Camera_Pose,
    clearance: f32 = .18,
) -> third_person.Camera_Pose {
    if editor == nil || editor.gameplay_physics.world == nil do return pose
    offset := pose.position - pose.target
    distance := math.sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z)
    if distance <= .001 do return pose
    direction := physics.Vec3{offset.x / distance, offset.y / distance, offset.z / distance}
    hit, ok := physics.cast_ray_layer(
        editor.gameplay_physics.world,
        {pose.target.x, pose.target.y, pose.target.z},
        direction,
        distance,
        .Sensor,
    )
    if !ok do return pose
    safe_distance := max(hit.fraction * distance - max(clearance, f32(0)), f32(.05))
    result := pose
    result.position =
        pose.target +
        third_person.Vec3{direction.x * safe_distance, direction.y * safe_distance, direction.z * safe_distance}
    return result
}
