package main
import "core:math"

import rondine_game "../packages/rondine"
import third_person "zelda_engine:third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_rondine_wake_pressure_sides :: proc(
    older, newer: rondine_game.Wake_Sample,
    older_fade, newer_fade, older_fade_linear, newer_fade_linear: f32,
    older_base, newer_base, older_right, newer_right: third_person.Vec3,
    older_turn, newer_turn, fine_distance_fade, medium_distance_fade: f32,
    camera: Perspective_Camera,
) {
    for side in 0 ..< 2 {
        side_sign := side == 0 ? f32(-1) : f32(1)
        older_outside := clamp(1 + side_sign * older_turn * .62, .38, 1.62)
        newer_outside := clamp(1 + side_sign * newer_turn * .62, .38, 1.62)
        pressure_role := older_outside >= 1 ? u32(1) : u32(0)
        tail_dropout :=
            older_fade < .28 && newer_fade < .36 && world_rondine_wake_hash(older.serial, pressure_role, 1) % 5 == 0
        if tail_dropout do continue
        older_spread_age := min(older.age, f32(1.25))
        newer_spread_age := min(newer.age, f32(1.25))
        older_inner_width := .58 + older_spread_age * .34
        newer_inner_width := .58 + newer_spread_age * .34
        older_edge_variation := .78 + f32(world_rondine_wake_hash(older.serial, pressure_role, 2) % 13) * .035
        newer_edge_variation := .78 + f32(world_rondine_wake_hash(newer.serial, pressure_role, 2) % 13) * .035
        older_outer_width := (.92 + older_spread_age * 2.25) * older_outside * older_edge_variation
        newer_outer_width := (.92 + newer_spread_age * 2.25) * newer_outside * newer_edge_variation
        older_inner := older_base + older_right * (side_sign * older_inner_width)
        newer_inner := newer_base + newer_right * (side_sign * newer_inner_width)
        older_outer := older_base + older_right * (side_sign * older_outer_width)
        newer_outer := newer_base + newer_right * (side_sign * newer_outer_width)
        older_alpha := u8(clamp(205 * older.strength * older_fade * older_outside, 0, 232))
        newer_alpha := u8(clamp(205 * newer.strength * newer_fade * newer_outside, 0, 232))
        // Freshly aerated water is warm and almost white; as bubbles
        // collapse, shift the surviving pressure mark back toward the
        // ocean's turquoise. This age hierarchy reserves the brightest
        // values for live spray, shards, and individual impact flecks.
        older_aeration := clamp(older_fade_linear * 1.35, 0, 1)
        newer_aeration := clamp(newer_fade_linear * 1.35, 0, 1)
        older_foam := canvas2d.Color {
            u8(166 + older_aeration * 62),
            u8(221 + older_aeration * 29),
            u8(226 + older_aeration * 19),
            older_alpha,
        }
        newer_foam := canvas2d.Color {
            u8(166 + newer_aeration * 62),
            u8(221 + newer_aeration * 29),
            u8(226 + newer_aeration * 19),
            newer_alpha,
        }
        older_clear := canvas2d.Color {
            u8(142 + older_aeration * 20),
            u8(208 + older_aeration * 18),
            u8(218 + older_aeration * 8),
            u8(f32(older_alpha) * .42),
        }
        newer_clear := canvas2d.Color {
            u8(142 + newer_aeration * 20),
            u8(208 + newer_aeration * 18),
            u8(218 + newer_aeration * 8),
            u8(f32(newer_alpha) * .42),
        }
        older_band_outer := older_inner + (older_outer - older_inner) * (.24 + older_fade * .16)
        newer_band_outer := newer_inner + (newer_outer - newer_inner) * (.24 + newer_fade * .16)
        // A continuous translucent under-ribbon carries the main foam
        // mass. Bright packets still articulate churn on top, but their
        // triangular gaps no longer define the entire silhouette.
        older_band_base := canvas2d.Color{older_foam.r, older_foam.g, older_foam.b, u8(f32(older_foam.a) * .44)}
        newer_band_base := canvas2d.Color{newer_foam.r, newer_foam.g, newer_foam.b, u8(f32(newer_foam.a) * .44)}
        older_band_clear := canvas2d.Color{older_clear.r, older_clear.g, older_clear.b, u8(f32(older_clear.a) * .72)}
        newer_band_clear := canvas2d.Color{newer_clear.r, newer_clear.g, newer_clear.b, u8(f32(newer_clear.a) * .72)}
        world_rondine_triangle_colored(
            older_inner,
            newer_inner,
            newer_band_outer,
            older_band_base,
            newer_band_base,
            newer_band_clear,
            side == 1,
        )
        world_rondine_triangle_colored(
            older_inner,
            newer_band_outer,
            older_band_outer,
            older_band_base,
            newer_band_clear,
            older_band_clear,
            side == 1,
        )
        // Keep the underlying pressure rim continuous, but punch
        // deterministic gaps into the bright foam rail. A solid ribbon
        // reads as a vector line from the chase camera; packets read as
        // successive breaking crests.
        foam_packet_hash := world_rondine_wake_hash(older.serial, pressure_role, 6)
        // Leave real water-colored gaps between foam packets. At the old
        // roughly-even duty cycle adjacent segments frequently joined
        // into long vector-like rails, especially from the movement-lab
        // camera. The loaded edge remains busier, but neither side can
        // become a continuous painted stripe.
        foam_packet := pressure_role == 1 ? foam_packet_hash % 8 < 7 : foam_packet_hash % 5 < 4
        if foam_packet {
            packet_inset := .10 + f32((foam_packet_hash >> 7) % 13) / 100
            packet_start_inner := older_inner + (newer_inner - older_inner) * packet_inset
            packet_end_inner := older_inner + (newer_inner - older_inner) * (1 - packet_inset)
            packet_start_outer := older_band_outer + (newer_band_outer - older_band_outer) * packet_inset
            packet_end_outer := older_band_outer + (newer_band_outer - older_band_outer) * (1 - packet_inset)
            packet_mid_inner := (packet_start_inner + packet_end_inner) * .5
            packet_mid_outer := (packet_start_outer + packet_end_outer) * .5
            packet_tip_clear := canvas2d.Color{older_foam.r, older_foam.g, older_foam.b, 0}
            packet_mid_foam := canvas2d.Color {
                u8((u16(older_foam.r) + u16(newer_foam.r)) / 2),
                u8((u16(older_foam.g) + u16(newer_foam.g)) / 2),
                u8((u16(older_foam.b) + u16(newer_foam.b)) / 2),
                u8((u16(older_foam.a) + u16(newer_foam.a)) / 2),
            }
            packet_mid_clear := canvas2d.Color {
                u8((u16(older_clear.r) + u16(newer_clear.r)) / 2),
                u8((u16(older_clear.g) + u16(newer_clear.g)) / 2),
                u8((u16(older_clear.b) + u16(newer_clear.b)) / 2),
                u8((u16(older_clear.a) + u16(newer_clear.a)) / 2),
            }
            world_rondine_triangle_colored(
                packet_start_inner,
                packet_mid_inner,
                packet_mid_outer,
                packet_tip_clear,
                packet_mid_foam,
                packet_mid_clear,
                side == 1,
            )
            world_rondine_triangle_colored(
                packet_start_inner,
                packet_start_outer,
                packet_mid_outer,
                packet_tip_clear,
                packet_tip_clear,
                packet_mid_clear,
                side == 1,
            )
            world_rondine_triangle_colored(
                packet_mid_inner,
                packet_end_inner,
                packet_end_outer,
                packet_mid_foam,
                packet_tip_clear,
                packet_tip_clear,
                side == 1,
            )
            world_rondine_triangle_colored(
                packet_mid_inner,
                packet_end_outer,
                packet_mid_outer,
                packet_mid_foam,
                packet_tip_clear,
                packet_mid_clear,
                side == 1,
            )
        }

        // Retain a faint outside pressure edge without filling the entire
        // fan between it and the inner foam band. This keeps the wake's
        // broad drift silhouette while avoiding a screen-sized solid
        // triangle in the low chase camera.
        older_rim_inner := older_outer + (older_inner - older_outer) * .11
        newer_rim_inner := newer_outer + (newer_inner - newer_outer) * .11
        older_rim := canvas2d.Color{177, 232, 233, u8(f32(older_alpha) * .24)}
        newer_rim := canvas2d.Color{177, 232, 233, u8(f32(newer_alpha) * .24)}
        rim_packet :=
            world_rondine_wake_hash(older.serial, pressure_role, 7) % 7 < (pressure_role == 1 ? u32(6) : u32(5))
        if rim_packet {
            world_rondine_triangle_colored(
                older_rim_inner,
                newer_rim_inner,
                newer_outer,
                older_rim,
                newer_rim,
                newer_clear,
                side == 1,
            )
            world_rondine_triangle_colored(
                older_rim_inner,
                newer_outer,
                older_outer,
                older_rim,
                newer_clear,
                older_clear,
                side == 1,
            )
        }

        // Tiny surface flecks sit between the bright inner packet and the
        // faint pressure rim. Reconstructing them from the sample serial
        // keeps every glint fixed in the water instead of swimming with
        // the camera. The loaded side receives a second fleck, while the
        // alternating sample gate prevents a continuous dotted rail.
        fleck_strength :=
            (older.strength * older_fade + newer.strength * newer_fade) *
            .5 *
            clamp(.6 + (older_outside - .7) * .65, .45, 1.2) *
            fine_distance_fade
        if older.serial % 2 == 0 && older.age < 1.28 && fleck_strength > .10 {
            fleck_count := pressure_role == 1 ? 2 : 1
            segment_direction := newer_base - older_base
            for fleck in 0 ..< fleck_count {
                seed := world_rondine_wake_hash(older.serial, pressure_role, u32(100 + side * 3 + fleck))
                if seed % 5 == 0 do continue
                along := .20 + f32((seed >> 3) % 53) / 88
                across := .18 + f32((seed >> 9) % 59) / 82
                inner_position := older_inner + (newer_inner - older_inner) * along
                outer_position := older_outer + (newer_outer - older_outer) * along
                position := inner_position + (outer_position - inner_position) * across
                position.y += .028
                outward := (older_right + newer_right) * (side_sign * (.08 + f32((seed >> 15) % 17) * .006))
                direction := segment_direction * .36 + outward
                variation := f32((seed >> 20) % 29) / 28
                fleck_alpha := u8(clamp((112 + variation * 72) * fleck_strength, 0, 174))
                fleck_color := canvas2d.Color{229, 252, 246, fleck_alpha}
                world_rondine_spray_streak(camera, position, direction, .055 + variation * .075, fleck_color)
            }
        }

        // Surface-level breakers interrupt the loaded rail at irregular
        // intervals. They provide medium-scale foam detail even when the
        // taller shards are edge-on to the chase camera.
        breaker_step :=
            pressure_role == 1 && older.age < 1.05 && world_rondine_wake_hash(older.serial, pressure_role, 5) % 7 < 3
        breaker_strength := older.strength * max(older_fade, newer_fade) * medium_distance_fade
        if breaker_step && breaker_strength > .14 {
            breaker_root := (older_band_outer + newer_band_outer) * .5
            breaker_tip := breaker_root + older_right * (side_sign * (.16 + breaker_strength * .28))
            breaker_root.y += .022
            breaker_tip.y += .026
            breaker_alpha := u8(clamp(145 * breaker_strength, 0, 160))
            breaker_foam := canvas2d.Color{225, 249, 243, breaker_alpha}
            breaker_clear := canvas2d.Color{151, 220, 225, 0}
            world_rondine_triangle_colored(
                older_band_outer,
                newer_band_outer,
                breaker_tip,
                older_clear,
                newer_clear,
                breaker_foam,
                side == 1,
            )
            breaker_tail := breaker_root + (breaker_tip - breaker_root) * .55
            world_rondine_triangle_colored(
                newer_band_outer,
                breaker_tail,
                breaker_tip,
                newer_clear,
                breaker_clear,
                breaker_foam,
                side == 1,
            )
        }

        // Sparse raised shards catch the light on the outside of a hard
        // drift. Their alternating placement breaks up the ribbon without
        // introducing particles, textures, or camera-facing billboards.
        shard_step := world_rondine_wake_hash(older.serial, pressure_role, 3) % 5 < 2
        shard_strength :=
            older.strength * older_fade * clamp(.28 + (older_outside - .7) * 1.15, .18, 1) * medium_distance_fade
        if shard_step && shard_strength > .12 && older.age < .9 {
            along := (older_outer + newer_outer) * .5
            crest := along + older_right * (side_sign * (.22 + older.age * .18))
            crest.y += .38 + shard_strength * 1.70
            shard_alpha := u8(clamp(150 * shard_strength, 0, 190))
            shard_foam := canvas2d.Color{221, 248, 242, shard_alpha}
            shard_mist := canvas2d.Color{137, 215, 223, u8(f32(shard_alpha) * .5)}
            world_rondine_triangle_colored(
                older_outer,
                newer_outer,
                crest,
                older_clear,
                newer_clear,
                shard_mist,
                side == 1,
            )
            tip := crest + older_right * (side_sign * (.18 + shard_strength * .42))
            tip.y -= .08
            world_rondine_triangle_colored(
                newer_outer,
                tip,
                crest,
                newer_clear,
                {shard_foam.r, shard_foam.g, shard_foam.b, 0},
                shard_foam,
                side == 1,
            )
        }

        // Strong slides also comb the loaded pressure field sideways.
        // These short transverse crests are fixed to the sampled water,
        // so they read as turbulent claw marks instead of particles that
        // follow the aircraft. Their diagonal alternates slightly from
        // packet to packet to avoid forming another regular herringbone.
        claw_strength :=
            clamp(math.abs(older.slip) * 3.15, 0, 1) *
            older.strength *
            max(older_fade, newer_fade) *
            medium_distance_fade
        claw_step :=
            pressure_role == 1 && older.age < 1.08 && world_rondine_wake_hash(older.serial, pressure_role, 188) % 5 < 2
        if claw_step && claw_strength > .16 {
            claw_seed := world_rondine_wake_hash(older.serial, pressure_role, 189)
            claw_variation := f32(claw_seed % 23) / 22
            claw_forward := third_person.Vec3{older.forward.x, 0, older.forward.z}
            claw_center := older_inner + (older_outer - older_inner) * (.30 + claw_variation * .32)
            claw_center += (newer_base - older_base) * (.24 + claw_variation * .34)
            claw_center.y += .036
            claw_tangent :=
                older_right * (side_sign * (.84 + claw_variation * .18)) + claw_forward * (.16 + claw_variation * .20)
            claw_radial := claw_forward - older_right * (side_sign * (.10 + claw_variation * .12))
            claw_alpha := u8(clamp((132 + claw_variation * 52) * claw_strength, 0, 188))
            claw_color := canvas2d.Color{226, 250, 244, claw_alpha}
            for tooth in 0 ..< 2 {
                tooth_f := f32(tooth)
                tooth_position :=
                    claw_center -
                    claw_forward * (tooth_f * (.15 + claw_variation * .06)) +
                    older_right * (side_sign * tooth_f * .06)
                world_rondine_surface_chip(
                    tooth_position,
                    claw_tangent,
                    claw_radial,
                    .18 + claw_strength * .13 - tooth_f * .025,
                    .028 + claw_strength * .018,
                    {claw_color.r, claw_color.g, claw_color.b, u8(f32(claw_alpha) * (1 - tooth_f * .22))},
                )
            }
        }
    }

}
