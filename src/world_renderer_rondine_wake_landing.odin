package main
import "core:math"

import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_rondine_wake_landing :: proc(
    camera: Perspective_Camera,
    contact_base, contact_forward, contact_right, contact_back, stern: third_person.Vec3,
    surface_impact: f32,
    live_spray_epoch: u32,
    live_spray_blend: f32,
) {
    // needles provide the fast bright edge while varied elevation keeps
    // the burst from reading as a flat, mechanically perfect star.
    if surface_impact > .06 {
        impact_visibility := f32(math.sqrt(f64(surface_impact)))
        slap_alpha := u8(clamp(218 * impact_visibility, 0, 224))
        slap_color := canvas2d.Color{234, 253, 247, slap_alpha}
        // The main bar crosses the hull beam and expands with impact
        // energy. Its transparent tips keep it from becoming a hard white
        // plank while supplying the large-scale pressure beat that the
        // radial needles sit on top of.
        world_rondine_surface_chip(
            stern + contact_back * (.30 + surface_impact * .22),
            contact_right,
            contact_forward,
            1.18 + surface_impact * .78,
            .070 + impact_visibility * .055,
            slap_color,
            double_sided = true,
        )
        // A shorter rebound knuckle sits just forward of the stern bar.
        // Slight yaw relative to the beam prevents the two marks reading
        // as a repeated symbol while keeping both outside the aircraft's
        // screen-space occlusion.
        rebound_contact := stern + contact_forward * (.32 + surface_impact * .18)
        rebound_tangent := contact_right * .94 + contact_back * .18
        rebound_radial := contact_forward + contact_right * .12
        world_rondine_surface_chip(
            rebound_contact,
            rebound_tangent,
            rebound_radial,
            .58 + surface_impact * .34,
            .050 + impact_visibility * .035,
            {slap_color.r, slap_color.g, slap_color.b, u8(f32(slap_alpha) * .74)},
            double_sided = true,
        )

        for ray in 0 ..< 8 {
            ray_f := f32(ray)
            variation := world_rondine_live_variation(live_spray_epoch, live_spray_blend, u32(ray & 1), u32(140 + ray))
            angle := ray_f / 8 * math.TAU + (variation - .5) * .16
            cosine, sine := math.cos(angle), math.sin(angle)
            radial := contact_right * cosine + contact_forward * sine
            position := contact_base + radial * (.48 + variation * .30)
            position.y += .05 + variation * .11
            direction :=
                radial * (1.05 + variation * .50) +
                contact_back * (.14 + surface_impact * .18) +
                third_person.Vec3{0, .20 + variation * .42, 0}
            impact_alpha := u8(clamp((156 + variation * 78) * surface_impact, 0, 228))
            impact_color := canvas2d.Color{234, 253, 247, impact_alpha}
            world_rondine_spray_streak(
                camera,
                position,
                direction,
                .30 + surface_impact * .42 + variation * .16,
                impact_color,
            )
        }
    }

}
