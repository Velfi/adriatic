package tests

import mouse_paws "../packages/mouse_paws"
import third_person "../packages/third_person"
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
