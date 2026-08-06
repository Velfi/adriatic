package tests

import mouse_paws "../packages/mouse_paws"
import third_person "zelda_engine:third_person"
import "core:math"
import "core:testing"

@(test)
mouse_paw_contact_has_explicit_stance_and_swing_transitions :: proc(t: ^testing.T) {
    contact: mouse_paws.Contact
    desired := third_person.Vec3{2, .1, 3}

    planted := mouse_paws.resolve(&contact, {2, .4, 3}, desired, true, .5, 0)
    testing.expect(t, planted.event == .Planted)
    testing.expect(t, contact.phase == .Stance && contact.anchor == desired)

    held := mouse_paws.resolve(&contact, {2, .4, 3}, {2.1, .1, 3}, true, .5, 0)
    testing.expect(t, held.event == .None)
    testing.expect(t, held.position.x == desired.x && held.position.z == desired.z)

    released := mouse_paws.resolve(&contact, {2, .4, 3}, {2.1, .2, 3}, false, .5, 0)
    testing.expect(t, released.event == .Released)
    testing.expect(t, contact.phase == .Swing && released.position.y == .2)
}

@(test)
mouse_paw_contact_replants_before_full_extension :: proc(t: ^testing.T) {
    contact := mouse_paws.Contact {
        anchor = {0, 0, 0},
        phase  = .Stance,
    }
    result := mouse_paws.resolve(&contact, {.42, 0, 0}, {.45, 0, 0}, true, .5, 0)
    testing.expect(t, result.event == .Replanted_Reach)
    testing.expect(t, result.position == third_person.Vec3{.45, 0, 0})
}

@(test)
mouse_paw_contact_replants_when_the_body_turns_under_it :: proc(t: ^testing.T) {
    contact := mouse_paws.Contact {
        anchor            = {0, 0, -1},
        plant_yaw_radians = 0,
        phase             = .Stance,
    }
    result := mouse_paws.resolve(&contact, {}, {1, 0, 0}, true, 2, math.PI * .5)
    testing.expect(t, result.event == .Replanted_Turn)
    testing.expect(t, contact.anchor == third_person.Vec3{1, 0, 0})
}

@(test)
mouse_paw_contact_does_not_mistake_socket_translation_for_turning :: proc(t: ^testing.T) {
    contact := mouse_paws.Contact {
        anchor            = {0, 0, -1},
        plant_yaw_radians = 0,
        phase             = .Stance,
    }
    // The socket has moved past the world-space anchor, reversing the old
    // socket-to-anchor vector, but the body itself has not turned.
    result := mouse_paws.resolve(&contact, {0, 0, -1.2}, {0, 0, -2}, true, 2, 0)
    testing.expect(t, result.event == .None)
    testing.expect(t, result.position == contact.anchor)
}

@(test)
mouse_paw_contact_uses_limb_scale_for_teleport_detection :: proc(t: ^testing.T) {
    contact := mouse_paws.Contact {
        anchor = {4, 0, 5},
        phase  = .Stance,
    }
    result := mouse_paws.resolve(&contact, {4, 0, 5}, {6, 0, 5}, true, .5, 0)
    testing.expect(t, result.event == .Replanted_Teleport)
    testing.expect(t, contact.anchor == third_person.Vec3{6, 0, 5})
}

@(test)
mouse_paw_rig_reset_releases_every_contact :: proc(t: ^testing.T) {
    rig: mouse_paws.Rig
    for &contact in rig.contacts {
        contact.phase = .Stance
        contact.anchor = {1, 2, 3}
    }
    mouse_paws.reset(&rig)
    for contact in rig.contacts {
        testing.expect(t, contact.phase == .Swing)
        testing.expect(t, contact.anchor == third_person.Vec3{})
    }
}

@(test)
mouse_paw_support_anchor_follows_body_translation_and_rotation :: proc(t: ^testing.T) {
    contact: mouse_paws.Contact
    half_turn_sine := math.sin(f32(math.PI * .25))
    half_turn_cosine := math.cos(f32(math.PI * .25))
    sample := mouse_paws.Paw_Surface_Sample {
        position      = {3, 2, 4},
        body          = 7,
        body_position = {2, 2, 4},
        body_rotation = {0, 0, 0, 1},
        valid         = true,
    }
    mouse_paws.store_support_local(&contact, sample)
    moved := mouse_paws.support_world_position(contact, {5, 2, 6}, {0, half_turn_sine, 0, half_turn_cosine})
    testing.expect(t, math.abs(moved.x - 5) < .001)
    testing.expect(t, math.abs(moved.z - 5) < .001)
}

@(test)
mouse_paw_touchdown_deforms_then_critically_recovers :: proc(t: ^testing.T) {
    contact: mouse_paws.Contact
    peak := mouse_paws.step_compression(&contact, true, 1.0 / 120.0)
    testing.expect(t, peak > .5 && peak <= 1)
    for _ in 0 ..< 120 do mouse_paws.step_compression(&contact, false, 1.0 / 120.0)
    testing.expect(t, contact.compression < .001)
    scale := mouse_paws.pad_scale(1)
    testing.expect(t, math.abs(scale.x - 1.10) < .0001)
    testing.expect(t, math.abs(scale.y - .72) < .0001)
    testing.expect(t, math.abs(scale.z - 1.14) < .0001)
}

@(test)
mouse_paw_toes_resolve_independently_and_bound_ledge_drape :: proc(t: ^testing.T) {
    root := third_person.Vec3{0, 1, 0}
    desired := third_person.Vec3{0, 1, .1}
    high := mouse_paws.resolve_toe(root, desired, {position = {0, 4, .1}, valid = true}, .1)
    low := mouse_paws.resolve_toe(root, desired, {position = {0, -4, .1}, valid = true}, .1)
    hanging := mouse_paws.resolve_toe(root, desired, {}, .1)
    testing.expect(t, math.abs(high.tip.y - 1.035) < .0001)
    testing.expect(t, math.abs(low.tip.y - .95) < .0001)
    testing.expect(t, !hanging.supported && hanging.tip.y < desired.y)
}

@(test)
mouse_paw_resolved_render_reads_are_immutable :: proc(t: ^testing.T) {
    rig: mouse_paws.Rig
    rig.authored[0] = {
        socket  = {1, 2, 3},
        desired = {4, 5, 6},
        valid   = true,
    }
    rig.resolved[0] = {
        pad_position = {7, 8, 9},
        pad_normal   = {0, 1, 0},
        valid        = true,
    }
    before := rig
    for _ in 0 ..< 32 {
        _ = mouse_paws.authored_pose(&rig, 0)
        _ = mouse_paws.resolved_pose(&rig, 0)
    }
    testing.expect(t, rig == before)
}

@(test)
mouse_paw_moving_support_keeps_contact_beyond_the_old_ray :: proc(t: ^testing.T) {
    contact := mouse_paws.Contact {
        anchor       = {},
        local_anchor = {},
        support_body = 9,
        phase        = .Stance,
    }
    moved_anchor := mouse_paws.support_world_position(contact, {2, .5, 0}, {0, 0, 0, 1})
    contact.anchor = moved_anchor
    result := mouse_paws.resolve(&contact, {2, .8, 0}, moved_anchor, true, .5, 0)
    testing.expect(t, result.event == .None)
    testing.expect(t, result.position == moved_anchor)
}
