package mouse_paws

import third_person "zelda_engine:third_person"
import "core:math"

PAW_COUNT :: 4
TOE_COUNT :: 3

// A transient result supplied by gameplay physics. It deliberately contains
// no allocator-owned data and lives only in the player presentation rig.
Paw_Surface_Sample :: struct {
    position:      third_person.Vec3,
    normal:        third_person.Vec3,
    body:          u32,
    body_position: third_person.Vec3,
    body_rotation: [4]f32,
    valid:         bool,
}

Resolved_Toe_Pose :: struct {
    root, tip: third_person.Vec3,
    supported: bool,
}

Resolved_Paw_Pose :: struct {
    limb_root:    third_person.Vec3,
    pad_position: third_person.Vec3,
    pad_normal:   third_person.Vec3,
    toes:         [TOE_COUNT]Resolved_Toe_Pose,
    compression:  f32,
    valid:        bool,
}

Authored_Paw_Pose :: struct {
    socket, desired: third_person.Vec3,
    maximum_reach:   f32,
    stance:          bool,
    valid:           bool,
}

Contact_Phase :: enum u8 {
    Swing,
    Stance,
}

Contact_Event :: enum u8 {
    None,
    Released,
    Planted,
    Replanted_Teleport,
    Replanted_Reach,
    Replanted_Turn,
}

Contact :: struct {
    anchor:               third_person.Vec3,
    local_anchor:         third_person.Vec3,
    local_normal:         third_person.Vec3,
    support_body:         u32,
    plant_yaw_radians:    f32,
    compression:          f32,
    compression_velocity: f32,
    phase:                Contact_Phase,
}

Rig :: struct {
    contacts:               [PAW_COUNT]Contact,
    authored:               [PAW_COUNT]Authored_Paw_Pose,
    resolved:               [PAW_COUNT]Resolved_Paw_Pose,
    evaluated_sockets:      [PAW_COUNT]third_person.Vec3,
    evaluated_socket_valid: [PAW_COUNT]bool,
}

Resolve_Result :: struct {
    position: third_person.Vec3,
    event:    Contact_Event,
}

Config :: struct {
    // Replant before an analytic chain reaches full extension. The remaining
    // margin keeps the knee/elbow pole stable instead of letting the limb
    // flatten into a straight line for several frames.
    reach_fraction:                   f32,
    // A planted contact is no longer anatomically compatible after its
    // socket-to-paw direction rotates this far from the authored target.
    maximum_direction_change_radians: f32,
    // Desired contacts farther than this many limb lengths from their anchor
    // are teleports, not strides.
    teleport_reach_scale:             f32,
}

DEFAULT_CONFIG :: Config {
    reach_fraction                   = .82,
    maximum_direction_change_radians = math.PI * .30,
    teleport_reach_scale             = 3,
}

default_config :: proc() -> Config { return DEFAULT_CONFIG }

reset :: proc(rig: ^Rig) {
    if rig == nil do return
    rig^ = {}
}

authored_pose :: proc(rig: ^Rig, index: int) -> Authored_Paw_Pose {
    if rig == nil || index < 0 || index >= PAW_COUNT do return {}
    return rig.authored[index]
}

resolved_pose :: proc(rig: ^Rig, index: int) -> Resolved_Paw_Pose {
    if rig == nil || index < 0 || index >= PAW_COUNT do return {}
    return rig.resolved[index]
}

set_evaluated_socket :: proc(rig: ^Rig, index: int, socket: third_person.Vec3) {
    if rig == nil || index < 0 || index >= PAW_COUNT do return
    rig.evaluated_sockets[index] = socket
    rig.evaluated_socket_valid[index] = true
}

evaluated_socket :: proc(rig: ^Rig, index: int) -> (third_person.Vec3, bool) {
    if rig == nil || index < 0 || index >= PAW_COUNT || !rig.evaluated_socket_valid[index] do return {}, false
    return rig.evaluated_sockets[index], true
}

quat_conjugate_rotate :: proc(q: [4]f32, value: third_person.Vec3) -> third_person.Vec3 {
    // Unit-quaternion inverse rotation, expanded to keep this package free of
    // renderer or physics-world dependencies.
    tx := 2 * (q.y * value.z - q.z * value.y)
    ty := 2 * (q.z * value.x - q.x * value.z)
    tz := 2 * (q.x * value.y - q.y * value.x)
    return {
        value.x - q.w * tx + (q.y * tz - q.z * ty),
        value.y - q.w * ty + (q.z * tx - q.x * tz),
        value.z - q.w * tz + (q.x * ty - q.y * tx),
    }
}

quat_rotate :: proc(q: [4]f32, value: third_person.Vec3) -> third_person.Vec3 {
    tx := 2 * (q.y * value.z - q.z * value.y)
    ty := 2 * (q.z * value.x - q.x * value.z)
    tz := 2 * (q.x * value.y - q.y * value.x)
    return {
        value.x + q.w * tx + (q.y * tz - q.z * ty),
        value.y + q.w * ty + (q.z * tx - q.x * tz),
        value.z + q.w * tz + (q.x * ty - q.y * tx),
    }
}

store_support_local :: proc(contact: ^Contact, sample: Paw_Surface_Sample) {
    if contact == nil || !sample.valid do return
    contact.support_body = sample.body
    contact.local_anchor = quat_conjugate_rotate(sample.body_rotation, sample.position - sample.body_position)
    contact.local_normal = quat_conjugate_rotate(sample.body_rotation, sample.normal)
}

support_world_position :: proc(
    contact: Contact,
    body_position: third_person.Vec3,
    body_rotation: [4]f32,
) -> third_person.Vec3 {
    return body_position + quat_rotate(body_rotation, contact.local_anchor)
}

support_world_normal :: proc(contact: Contact, body_rotation: [4]f32) -> third_person.Vec3 {
    return quat_rotate(body_rotation, contact.local_normal)
}

step_compression :: proc(contact: ^Contact, touchdown: bool, delta_seconds: f32) -> f32 {
    if contact == nil do return 0
    if touchdown {
        contact.compression = max(contact.compression, f32(.72))
        contact.compression_velocity = max(contact.compression_velocity, f32(5.5))
    }
    target := f32(0)
    dt := clamp(delta_seconds, f32(0), f32(.05))
    // Exact critically-damped spring integration at 18 rad/s. Touchdown is
    // intentionally restrained by the same spring instead of snapping flat.
    omega := f32(18)
    displacement := contact.compression - target
    decay := f32(math.exp(f64(-omega * dt)))
    next_displacement := (displacement + (contact.compression_velocity + omega * displacement) * dt) * decay
    contact.compression_velocity =
        (contact.compression_velocity - omega * (contact.compression_velocity + omega * displacement) * dt) * decay
    contact.compression = clamp(target + next_displacement, 0, 1)
    return contact.compression
}

pad_scale :: proc(compression: f32) -> third_person.Vec3 {
    amount := clamp(compression, 0, 1)
    return {1 + amount * .10, 1 - amount * .28, 1 + amount * .14}
}

resolve_toe :: proc(
    root, desired: third_person.Vec3,
    sample: Paw_Surface_Sample,
    toe_length: f32,
) -> Resolved_Toe_Pose {
    result := Resolved_Toe_Pose {
        root = root,
        tip  = desired,
    }
    if !sample.valid {
        result.tip.y -= max(toe_length, f32(0)) * .28
        return result
    }
    result.supported = true
    result.tip.y = root.y + clamp(sample.position.y + .008 - root.y, -toe_length * .5, toe_length * .35)
    return result
}

release :: proc(contact: ^Contact, desired: third_person.Vec3) -> Resolve_Result {
    if contact == nil do return {position = desired}
    event: Contact_Event
    if contact.phase == .Stance do event = .Released
    contact.phase = .Swing
    return {position = desired, event = event}
}

plant :: proc(
    contact: ^Contact,
    desired: third_person.Vec3,
    body_yaw_radians: f32,
    event: Contact_Event,
) -> Resolve_Result {
    contact.anchor = desired
    contact.plant_yaw_radians = body_yaw_radians
    contact.phase = .Stance
    return {position = desired, event = event}
}

resolve :: proc(
    contact: ^Contact,
    socket, desired: third_person.Vec3,
    stance: bool,
    maximum_reach: f32,
    body_yaw_radians: f32,
    config: Config = DEFAULT_CONFIG,
) -> Resolve_Result {
    if contact == nil || !stance || maximum_reach <= .0001 {
        return release(contact, desired)
    }
    if contact.phase != .Stance {
        return plant(contact, desired, body_yaw_radians, .Planted)
    }

    desired_from_anchor_x := desired.x - contact.anchor.x
    desired_from_anchor_z := desired.z - contact.anchor.z
    teleport_distance := maximum_reach * max(config.teleport_reach_scale, f32(1))
    if desired_from_anchor_x * desired_from_anchor_x + desired_from_anchor_z * desired_from_anchor_z >
       teleport_distance * teleport_distance {
        return plant(contact, desired, body_yaw_radians, .Replanted_Teleport)
    }

    cached_x := contact.anchor.x - socket.x
    cached_y := contact.anchor.y - socket.y
    cached_z := contact.anchor.z - socket.z
    reach_limit := maximum_reach * clamp(config.reach_fraction, .1, .99)
    if cached_x * cached_x + cached_y * cached_y + cached_z * cached_z > reach_limit * reach_limit {
        return plant(contact, desired, body_yaw_radians, .Replanted_Reach)
    }

    yaw_delta := body_yaw_radians - contact.plant_yaw_radians
    for yaw_delta > math.PI do yaw_delta -= math.TAU
    for yaw_delta < -math.PI do yaw_delta += math.TAU
    direction_limit := clamp(config.maximum_direction_change_radians, f32(.01), math.PI)
    if math.abs(yaw_delta) > direction_limit {
        return plant(contact, desired, body_yaw_radians, .Replanted_Turn)
    }

    // Preserve horizontal ground contact but let terrain resolution own the
    // vertical coordinate. This keeps a planted paw stable on the ground
    // without pinning it to an obsolete height when crossing a slope seam.
    result := desired
    result.x = contact.anchor.x
    result.z = contact.anchor.z
    return {position = result}
}
