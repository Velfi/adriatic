package mouse_paws

import third_person "../third_person"
import "core:math"

PAW_COUNT :: 4

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
    anchor:            third_person.Vec3,
    plant_yaw_radians: f32,
    phase:             Contact_Phase,
}

Rig :: struct {
    contacts: [PAW_COUNT]Contact,
}

Resolve_Result :: struct {
    position: third_person.Vec3,
    event:    Contact_Event,
}

Config :: struct {
    // Replant before an analytic chain reaches full extension. The remaining
    // margin keeps the knee/elbow pole stable instead of letting the limb
    // flatten into a straight line for several frames.
    reach_fraction: f32,
    // A planted contact is no longer anatomically compatible after its
    // socket-to-paw direction rotates this far from the authored target.
    maximum_direction_change_radians: f32,
    // Desired contacts farther than this many limb lengths from their anchor
    // are teleports, not strides.
    teleport_reach_scale: f32,
}

DEFAULT_CONFIG :: Config {
    reach_fraction                    = .82,
    maximum_direction_change_radians = math.PI * .30,
    teleport_reach_scale              = 3,
}

default_config :: proc() -> Config { return DEFAULT_CONFIG }

reset :: proc(rig: ^Rig) {
    if rig == nil do return
    rig^ = {}
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
