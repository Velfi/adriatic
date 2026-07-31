package main

import mouse_paws "../packages/mouse_paws"
import third_person "../packages/third_person"
import "core:math"
import "core:math/linalg"
import physics "zelda_engine:physics"

PLAYER_PAW_RAY_RISE :: f32(.20)
PLAYER_PAW_RAY_LENGTH :: f32(.48)
PLAYER_PAW_MIN_NORMAL_Y :: f32(.62)

player_paw_surface_sample :: proc(editor: ^Editor, desired: third_person.Vec3) -> mouse_paws.Paw_Surface_Sample {
    if editor == nil || editor.gameplay_physics.world == nil do return {}
    walkable_layers :=
        u16(1 << u16(physics.Object_Layer.Static_World)) |
        u16(1 << u16(physics.Object_Layer.Moving)) |
        u16(1 << u16(physics.Object_Layer.Vehicle)) |
        u16(1 << u16(physics.Object_Layer.Boat)) |
        u16(1 << u16(physics.Object_Layer.Prop))
    hit, ok := physics.cast_ray_filtered(
        editor.gameplay_physics.world,
        {desired.x, desired.y + PLAYER_PAW_RAY_RISE, desired.z},
        {0, -1, 0},
        PLAYER_PAW_RAY_LENGTH,
        walkable_layers,
    )
    if !ok || hit.normal.y < PLAYER_PAW_MIN_NORMAL_Y do return {}
    body_position, body_rotation, body_ok := physics.get_transform(editor.gameplay_physics.world, hit.body)
    if !body_ok do return {}
    return {
        position      = {hit.position.x, hit.position.y, hit.position.z},
        normal        = linalg.normalize0(third_person.Vec3{hit.normal.x, hit.normal.y, hit.normal.z}),
        body          = u32(hit.body),
        body_position = {body_position.x, body_position.y, body_position.z},
        body_rotation = body_rotation,
        valid         = true,
    }
}

player_paws_step :: proc(editor: ^Editor, delta_seconds: f32) {
    if editor == nil do return
    rig := &editor.player_paws
    if editor.gameplay_physics.world == nil || !editor.player.grounded || editor.pilot.mode != .On_Foot {
        mouse_paws.reset(rig)
        return
    }
    // The procedural mouse model's canonical forward axis is +Z, while
    // gameplay facing uses -Z at zero yaw. Match world_character's
    // presentation rotation so the physics-authored sockets and contacts
    // remain attached to the rendered shoulders and hips.
    yaw := math.PI - editor.player.facing_yaw_radians
    cosine, sine := math.cos(yaw), math.sin(yaw)
    for paw_index in 0 ..< mouse_paws.PAW_COUNT {
        side := paw_index < 2 ? f32(-1) : f32(1)
        fore := paw_index % 2 == 0
        phase_offset := fore ? (side < 0 ? f32(0) : math.PI) : (side < 0 ? math.PI : f32(0))
        cycle := math.mod(editor.player_stride_phase + phase_offset, math.TAU)
        stance := cycle < math.PI * 1.18
        local_x := side * (fore ? f32(.105) : f32(.195))
        local_z := fore ? f32(.235) : f32(-.16)
        local_z += math.sin(cycle) * (fore ? f32(.11) : f32(.14)) * editor.player_gait_weight
        desired := third_person.Vec3 {
            editor.player.position.x + local_x * cosine - local_z * sine,
            editor.player.position.y + .06,
            editor.player.position.z + local_x * sine + local_z * cosine,
        }
        contact := &rig.contacts[paw_index]
        support_valid := false
        support_sample: mouse_paws.Paw_Surface_Sample
        if contact.phase == .Stance && contact.support_body != u32(physics.INVALID_BODY) {
            body_position, body_rotation, body_ok := physics.get_transform(
                editor.gameplay_physics.world, physics.Body_ID(contact.support_body),
            )
            if body_ok {
                contact.anchor = mouse_paws.support_world_position(
                    contact^,
                    {body_position.x, body_position.y, body_position.z},
                    body_rotation,
                )
                support_sample = {
                    position      = contact.anchor,
                    normal        = linalg.normalize0(mouse_paws.support_world_normal(contact^, body_rotation)),
                    body          = contact.support_body,
                    body_position = {body_position.x, body_position.y, body_position.z},
                    body_rotation = body_rotation,
                    valid         = true,
                }
                support_valid = true
            } else {
                contact.phase = .Swing
            }
        }
        desired_sample := player_paw_surface_sample(editor, desired)
        if desired_sample.valid do desired = desired_sample.position + desired_sample.normal * f32(.021)
        if !support_valid && !desired_sample.valid do stance = false
        maximum_reach := fore ? f32(.47) : f32(.74)
        socket_local_z := fore ? f32(.04) : f32(-.47)
        socket_local_x := side * (fore ? f32(.12) : f32(.16))
        socket := third_person.Vec3 {
            editor.player.position.x + socket_local_x * cosine - socket_local_z * sine,
            editor.player.position.y + (fore ? f32(.31) : f32(.30)),
            editor.player.position.z + socket_local_x * sine + socket_local_z * cosine,
        }
        rig.authored[paw_index] = {
            socket = socket, desired = desired, maximum_reach = maximum_reach,
            stance = stance, valid = true,
        }
        result := mouse_paws.resolve(contact, socket, desired, stance, maximum_reach, yaw)
        touchdown := result.event == .Planted || result.event == .Replanted_Reach || result.event == .Replanted_Turn || result.event == .Replanted_Teleport
        if touchdown && !desired_sample.valid {
            result = mouse_paws.release(contact, desired)
            stance = false
            touchdown = false
        }
        if touchdown do mouse_paws.store_support_local(contact, desired_sample)
        compression := mouse_paws.step_compression(contact, touchdown, delta_seconds)
        if !stance || contact.phase != .Stance {
            rig.resolved[paw_index] = {}
            continue
        }
        pose_sample := touchdown ? desired_sample : support_sample
        if !pose_sample.valid {
            rig.resolved[paw_index] = {}
            continue
        }
        if !touchdown do result.position = contact.anchor
        pose := mouse_paws.Resolved_Paw_Pose {
            limb_root    = socket,
            pad_position = result.position,
            pad_normal   = pose_sample.normal,
            compression  = compression,
            valid        = true,
        }
        toe_length := fore ? f32(.064) : f32(.092)
        toe_spread := fore ? f32(.013) : f32(.017)
        forward := third_person.Vec3{-sine, 0, cosine}
        right := third_person.Vec3{cosine, 0, sine}
        for toe_index in 0 ..< mouse_paws.TOE_COUNT {
            toe_root := pose.pad_position + right * (side * (f32(toe_index) - 1) * toe_spread)
            toe_desired := toe_root + forward * toe_length
            toe_sample := player_paw_surface_sample(editor, toe_desired)
            pose.toes[toe_index] = mouse_paws.resolve_toe(toe_root, toe_desired, toe_sample, toe_length)
        }
        rig.resolved[paw_index] = pose
    }
}
