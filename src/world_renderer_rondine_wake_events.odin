package main
import "core:math"

import third_person "../packages/third_person"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"

world_rondine_wake_events :: proc(editor: ^Editor, sea_y: f32, camera: Perspective_Camera) {
    // A switchback stamps its large and medium crossover geometry into the
    // water at the actual slip-sign change. The slashes slowly separate while
    // the hooks continue toward the newly loaded side, leaving a short,
    // readable hinge between the two drift arcs.
    for sample in editor.rondine.wake[:editor.rondine.wake_count] {
        if sample.transition <= .04 do continue
        center := third_person.Vec3{sample.position.x, sea_y + .030, sample.position.z}
        depth := linalg.dot(center - camera.position, camera.forward)
        if depth < 7.5 do continue
        camera_fade := clamp((depth - 7.5) / 5.5, 0, 1)
        life_fade := clamp(1 - sample.age / sample.lifetime, 0, 1)
        stamped_transition_strength := sample.transition * life_fade * life_fade * camera_fade
        if stamped_transition_strength <= .025 do continue
        stamped_transition_visibility := f32(math.sqrt(f64(stamped_transition_strength)))
        forward := third_person.Vec3{sample.forward.x, 0, sample.forward.z}
        right := third_person.Vec3{sample.right.x, 0, sample.right.z}
        back := -forward
        loaded_side := sample.slip < 0 ? f32(-1) : f32(1)
        stamped_transition_alpha := u8(clamp(216 * stamped_transition_visibility, 0, 224))
        for slash in 0 ..< 2 {
            slash_f := f32(slash)
            slash_sign := slash == 0 ? f32(-1) : f32(1)
            slash_position :=
                center +
                back * (.34 + slash_f * .24 + sample.age * .24) +
                right * (loaded_side * slash_sign * (.10 + sample.age * .16))
            slash_tangent := back * .72 + right * (loaded_side * slash_sign)
            world_rondine_surface_chip(
                slash_position,
                slash_tangent,
                right * (loaded_side * slash_sign) - back * .18,
                1.18 + stamped_transition_visibility * .44 - slash_f * .10,
                .105 + stamped_transition_visibility * .038,
                {232, 254, 248, u8(f32(stamped_transition_alpha) * (1 - slash_f * .15))},
                double_sided = true,
            )
        }
        for hook in 0 ..< 3 {
            hook_f := f32(hook)
            hook_position :=
                center +
                back * (.82 + hook_f * .43 + sample.age * .30) +
                right * (loaded_side * (.48 + hook_f * .30 + sample.age * .18))
            hook_tangent := right * loaded_side + back * (.58 - hook_f * .08)
            world_rondine_surface_chip(
                hook_position,
                hook_tangent,
                back - right * (loaded_side * .20),
                .42 + stamped_transition_visibility * .17 - hook_f * .035,
                .052 + stamped_transition_visibility * .019,
                {228, 253, 247, u8(f32(stamped_transition_alpha) * (.86 - hook_f * .18))},
                double_sided = true,
            )
        }
    }

    // One expanding broken ring remains where the hull first broke loose.
    // It is stamped by the runtime once per kick episode, giving the water a
    // persistent "skid-start" scar without allocating a particle emitter.
    for sample in editor.rondine.wake[:editor.rondine.wake_count] {
        if sample.kick <= .01 do continue
        center := third_person.Vec3{sample.position.x, sea_y + .025, sample.position.z}
        depth := linalg.dot(center - camera.position, camera.forward)
        if depth < 7.5 do continue
        camera_fade := clamp((depth - 7.5) / 5.5, 0, 1)
        event_bead_distance_fade := clamp((92 - depth) / 34, 0, 1)
        life_fade := clamp(1 - sample.age / sample.lifetime, 0, 1)
        scar_strength := sample.kick * life_fade * camera_fade
        if scar_strength <= .025 do continue
        scar_visibility := f32(math.sqrt(f64(scar_strength)))
        forward := third_person.Vec3{sample.forward.x, 0, sample.forward.z}
        right := third_person.Vec3{sample.right.x, 0, sample.right.z}
        radius := .88 + sample.age * 1.78
        for spoke in 0 ..< 12 {
            seed := world_rondine_wake_hash(sample.serial, 1, u32(80 + spoke))
            if seed % 5 >= 3 do continue
            variation := f32((seed >> 4) % 17) / 16
            angle_jitter := (variation - .5) * .20
            angle := f32(spoke) / 12 * math.TAU + angle_jitter
            cosine, sine := math.cos(angle), math.sin(angle)
            radial := right * cosine + forward * sine
            tangent := right * -sine + forward * cosine
            spoke_radius := radius * (.84 + variation * .32)
            position := center + radial * spoke_radius
            scar_alpha := u8(clamp((176 + variation * 68) * scar_visibility, 0, 232))
            scar_color := canvas2d.Color{229, 252, 246, scar_alpha}
            fragment_length := .24 + sample.age * .15 + variation * .17
            fragment_width := .055 + scar_visibility * .058 + variation * .032
            world_rondine_surface_chip(
                position,
                tangent,
                radial,
                fragment_length,
                fragment_width,
                scar_color,
                double_sided = true,
            )
        }

        // The expanding ring marks the impulse location, while this short
        // asymmetric gouge records which side actually broke traction. It
        // begins behind the loaded stern so it remains visible while the
        // center of the ring is still occluded by the aircraft.
        loaded_sign := sample.slip < 0 ? f32(-1) : f32(1)
        back := -forward
        gouge_alpha := u8(clamp(214 * scar_visibility, 0, 224))
        gouge_color := canvas2d.Color{233, 253, 247, gouge_alpha}
        for gouge in 0 ..< 3 {
            gouge_f := f32(gouge)
            gouge_position :=
                center +
                back * (.58 + sample.age * .62 + gouge_f * .24) +
                right * (loaded_sign * (.22 + gouge_f * .18))
            gouge_position.y += .012
            gouge_tangent := back * (.48 + gouge_f * .10) + right * (loaded_sign * (.82 + gouge_f * .08))
            gouge_radial := right * loaded_sign - back * (.12 + gouge_f * .05)
            world_rondine_surface_chip(
                gouge_position,
                gouge_tangent,
                gouge_radial,
                .20 + scar_visibility * .16 - gouge_f * .018,
                .038 + scar_visibility * .022,
                {gouge_color.r, gouge_color.g, gouge_color.b, u8(f32(gouge_alpha) * (1 - gouge_f * .19))},
                double_sided = true,
            )
        }

        // Breakaway leaves a one-sided fan of ballistic beads at the skid
        // origin. This is deliberately unlike touchdown's radial burst: every
        // trajectory favors the loaded side and trails aft, preserving the
        // direction of the initial loss of grip after the live kick rays move
        // away with the aircraft.
        if sample.age < .52 {
            for bead in 0 ..< 5 {
                seed := world_rondine_wake_hash(sample.serial, 1, u32(250 + bead))
                variation := f32(seed % 31) / 30
                spread := (f32(bead) - 2) * .16 + (variation - .5) * .12
                launch_direction := right * (loaded_sign * (.76 + spread)) + back * (.34 + variation * .38)
                launch_speed := 1.15 + variation * 1.25
                lift_speed := 1.15 + variation * 1.20
                bead_position := center + right * (loaded_sign * .34) + launch_direction * (sample.age * launch_speed)
                bead_position.y += .08 + sample.age * lift_speed - 3.15 * sample.age * sample.age
                bead_direction :=
                    launch_direction * launch_speed + third_person.Vec3{0, lift_speed - 6.3 * sample.age, 0}
                bead_life := clamp(1 - sample.age / .52, 0, 1)
                bead_alpha := u8(
                    clamp((136 + variation * 78) * scar_visibility * bead_life * event_bead_distance_fade, 0, 210),
                )
                bead_color := canvas2d.Color{232, 253, 247, bead_alpha}
                bead_streak_size := .070 + variation * .090
                world_rondine_spray_streak(camera, bead_position, bead_direction, bead_streak_size, bead_color)
                world_rondine_spray_bead(
                    camera,
                    bead_position + linalg.normalize0(bead_direction) * (bead_streak_size * 2.4),
                    .022 + variation * .018,
                    bead_color,
                )
            }
        }
    }

    // The hull slap leaves an expanding, elliptical broken ring. Its long
    // axis runs across the hull beam, distinguishing touchdown from the round
    // breakaway scar and the crossed hookup zipper.
    for sample in editor.rondine.wake[:editor.rondine.wake_count] {
        if sample.impact <= .04 do continue
        center := third_person.Vec3{sample.position.x, sea_y + .027, sample.position.z}
        depth := linalg.dot(center - camera.position, camera.forward)
        if depth < 7.5 do continue
        camera_fade := clamp((depth - 7.5) / 5.5, 0, 1)
        event_bead_distance_fade := clamp((92 - depth) / 34, 0, 1)
        life_fade := clamp(1 - sample.age / sample.lifetime, 0, 1)
        ring_strength := sample.impact * life_fade * camera_fade
        if ring_strength <= .025 do continue
        ring_visibility := f32(math.sqrt(f64(ring_strength)))
        forward := third_person.Vec3{sample.forward.x, 0, sample.forward.z}
        right := third_person.Vec3{sample.right.x, 0, sample.right.z}
        radius := .78 + sample.age * 2.8
        for spoke in 0 ..< 10 {
            seed := world_rondine_wake_hash(sample.serial, 0, u32(150 + spoke))
            if seed % 5 == 0 do continue
            variation := f32((seed >> 3) % 19) / 18
            angle := f32(spoke) / 10 * math.TAU + (variation - .5) * .14
            cosine, sine := math.cos(angle), math.sin(angle)
            radial := right * cosine + forward * (sine * .58)
            tangent := right * -sine + forward * (cosine * .58)
            position := center + radial * radius * (.88 + variation * .24)
            ring_alpha := u8(clamp((174 + variation * 70) * ring_visibility, 0, 224))
            ring_color := canvas2d.Color{228, 251, 245, ring_alpha}
            fragment_length := .22 + sample.age * .15 + variation * .13
            fragment_width := .052 + ring_visibility * .042 + variation * .028
            world_rondine_surface_chip(
                position,
                tangent,
                radial,
                fragment_length,
                fragment_width,
                ring_color,
                double_sided = true,
            )
            // Every second outer chip echoes inward at lower contrast. This
            // sparse rebound ripple supplies a medium-scale beat beneath the
            // large touchdown ellipse without becoming a second solid ring.
            if spoke % 2 == 0 {
                inner_position := center + radial * radius * (.48 + variation * .08)
                rebound_alpha := u8(f32(ring_alpha) * .48)
                rebound_color := canvas2d.Color{210, 242, 239, rebound_alpha}
                world_rondine_surface_chip(
                    inner_position,
                    tangent,
                    radial,
                    fragment_length * .62,
                    fragment_width * .72,
                    rebound_color,
                    double_sided = true,
                )
            }
        }

        // A hull slap begins as a beam-wide pressure bar before resolving
        // into the expanding ellipse. Two offset chips keep the bar broken
        // and directional while making touchdown unmistakable beneath the
        // aircraft during its strongest frames.
        slap_alpha := u8(clamp(218 * ring_visibility, 0, 226))
        slap_color := canvas2d.Color{234, 253, 247, slap_alpha}
        for slap in 0 ..< 2 {
            slap_f := f32(slap)
            slap_position := center + forward * ((slap_f - .5) * (.20 + sample.age * .42))
            slap_position.y += .012
            world_rondine_surface_chip(
                slap_position,
                right,
                forward,
                .46 + sample.age * 1.05 + ring_visibility * .26 - slap_f * .04,
                .055 + ring_visibility * .028,
                {slap_color.r, slap_color.g, slap_color.b, u8(f32(slap_alpha) * (1 - slap_f * .22))},
                double_sided = true,
            )
        }

        // Fine ballistic beads remain at the impact site after the live hull
        // burst has moved away with the aircraft. Reconstructing their arcs
        // from sample age gives touchdown a short sparkling tail without a
        // particle emitter or mutable per-droplet state.
        if sample.age < .58 {
            for bead in 0 ..< 6 {
                seed := world_rondine_wake_hash(sample.serial, 0, u32(230 + bead))
                variation := f32(seed % 29) / 28
                angle := f32(bead) / 6 * math.TAU + (variation - .5) * .28
                cosine, sine := math.cos(angle), math.sin(angle)
                radial := right * cosine + forward * (sine * .72)
                launch_speed := 1.25 + variation * 1.15
                lift_speed := 1.45 + variation * 1.05
                bead_position := center + radial * (sample.age * launch_speed)
                bead_position.y += .10 + sample.age * lift_speed - 3.4 * sample.age * sample.age
                bead_direction := radial * launch_speed + third_person.Vec3{0, lift_speed - 6.8 * sample.age, 0}
                bead_life := clamp(1 - sample.age / .58, 0, 1)
                bead_alpha := u8(
                    clamp((142 + variation * 74) * ring_visibility * bead_life * event_bead_distance_fade, 0, 214),
                )
                bead_color := canvas2d.Color{232, 253, 247, bead_alpha}
                bead_streak_size := .075 + variation * .085
                world_rondine_spray_streak(camera, bead_position, bead_direction, bead_streak_size, bead_color)
                world_rondine_spray_bead(
                    camera,
                    bead_position + linalg.normalize0(bead_direction) * (bead_streak_size * 2.4),
                    .024 + variation * .018,
                    bead_color,
                )
            }
        }
    }

    // Liftoff leaves a final feathered release mark where the hull stops
    // loading the water. It points aft and narrows toward the last contact,
    // visually opposing touchdown's broad transverse slap.
    for sample in editor.rondine.wake[:editor.rondine.wake_count] {
        if sample.release <= .04 do continue
        center := third_person.Vec3{sample.position.x, sea_y + .028, sample.position.z}
        depth := linalg.dot(center - camera.position, camera.forward)
        if depth < 7.5 do continue
        camera_fade := clamp((depth - 7.5) / 5.5, 0, 1)
        release_bead_distance_fade := clamp((92 - depth) / 34, 0, 1)
        life_fade := clamp(1 - sample.age / sample.lifetime, 0, 1)
        release_strength := sample.release * life_fade * life_fade * camera_fade
        if release_strength <= .02 do continue
        release_visibility := f32(math.sqrt(f64(release_strength)))
        forward := third_person.Vec3{sample.forward.x, 0, sample.forward.z}
        right := third_person.Vec3{sample.right.x, 0, sample.right.z}
        back := -forward

        // A broad suction knuckle is the large beat; it quickly fades into
        // the narrower paired quill marks behind it.
        knuckle_alpha := u8(clamp(188 * release_visibility, 0, 202))
        knuckle_color := canvas2d.Color{225, 250, 244, knuckle_alpha}
        world_rondine_surface_chip(
            center + back * (.12 + sample.age * .22),
            right,
            back,
            .42 + sample.age * .38 + release_visibility * .16,
            .060 + release_visibility * .026,
            knuckle_color,
            double_sided = true,
        )

        // Four paired quills converge toward the final hull-contact point.
        // Their staggered lengths give the mark a directional feather shape
        // instead of another symmetric ring.
        for quill in 0 ..< 4 {
            quill_f := f32(quill)
            quill_seed := world_rondine_wake_hash(sample.serial, 0, u32(360 + quill))
            quill_variation := f32(quill_seed % 19) / 18
            for side in 0 ..< 2 {
                side_sign := side == 0 ? f32(-1) : f32(1)
                lateral_width := .54 - quill_f * .105 + quill_variation * .06
                quill_position :=
                    center + back * (.28 + quill_f * .25 + sample.age * .18) + right * (side_sign * lateral_width)
                quill_position.y += .010
                quill_tangent := back * (.74 + quill_f * .08) - right * (side_sign * (.34 + quill_f * .07))
                quill_radial := right * side_sign + back * .16
                quill_alpha := u8(
                    clamp((174 + quill_variation * 42) * release_visibility * (1 - quill_f * .13), 0, 210),
                )
                world_rondine_surface_chip(
                    quill_position,
                    quill_tangent,
                    quill_radial,
                    .18 + release_visibility * .11 - quill_f * .012,
                    .032 + release_visibility * .014,
                    {230, 252, 246, quill_alpha},
                    double_sided = true,
                )
            }
        }

        // Four tiny beads peel aft and fall back toward the release feather.
        // Their low, converging trajectories contrast touchdown's high radial
        // explosion and complete the small-scale layer of the liftoff beat.
        if sample.age < .48 {
            for bead in 0 ..< 4 {
                bead_f := f32(bead)
                side_sign := bead & 1 == 0 ? f32(-1) : f32(1)
                seed := world_rondine_wake_hash(sample.serial, u32(bead & 1), u32(390 + bead))
                variation := f32(seed % 23) / 22
                launch_direction :=
                    back * (.62 + bead_f * .10 + variation * .18) +
                    right * (side_sign * (.34 + bead_f * .08 + variation * .12))
                launch_speed := .78 + variation * .62
                lift_speed := .62 + variation * .48
                bead_position :=
                    center +
                    right * (side_sign * (.18 + bead_f * .055)) +
                    launch_direction * (sample.age * launch_speed)
                bead_position.y += .14 + sample.age * lift_speed - 3.45 * sample.age * sample.age
                bead_direction :=
                    launch_direction * launch_speed + third_person.Vec3{0, lift_speed - 6.9 * sample.age, 0}
                bead_life := clamp(1 - sample.age / .48, 0, 1)
                bead_alpha := u8(
                    clamp(
                        (142 + variation * 62) * release_visibility * bead_life * release_bead_distance_fade,
                        0,
                        205,
                    ),
                )
                bead_color := canvas2d.Color{232, 253, 247, bead_alpha}
                bead_streak_size := .060 + variation * .070
                world_rondine_spray_streak(camera, bead_position, bead_direction, bead_streak_size, bead_color)
                world_rondine_spray_bead(
                    camera,
                    bead_position + linalg.normalize0(bead_direction) * (bead_streak_size * 2.2),
                    .020 + variation * .014,
                    bead_color,
                )
            }
        }
    }

    // Grip recovery is stamped into the trail as a short converging zipper.
    // Unlike the live hookup clap, these paired surface stitches remain at the
    // exact places where lateral energy collapsed, making the end of a drift
    // readable for a moment after the boat has already straightened.
    for sample in editor.rondine.wake[:editor.rondine.wake_count] {
        if sample.hookup <= .06 do continue
        center := third_person.Vec3{sample.position.x, sea_y + .032, sample.position.z}
        depth := linalg.dot(center - camera.position, camera.forward)
        if depth < 7.5 do continue
        camera_fade := clamp((depth - 7.5) / 5.5, 0, 1)
        event_bead_distance_fade := clamp((92 - depth) / 34, 0, 1)
        life_fade := clamp(1 - sample.age / sample.lifetime, 0, 1)
        stitch_strength := sample.hookup * life_fade * life_fade * camera_fade
        if stitch_strength <= .035 do continue
        forward := third_person.Vec3{sample.forward.x, 0, sample.forward.z}
        right := third_person.Vec3{sample.right.x, 0, sample.right.z}
        back := -forward
        serial_variation := f32(world_rondine_wake_hash(sample.serial, 0, 130) % 17) / 16
        stitch_visibility := f32(math.sqrt(f64(stitch_strength)))
        for side in 0 ..< 2 {
            side_sign := side == 0 ? f32(-1) : f32(1)
            position := center + right * (side_sign * (.42 + serial_variation * .18)) + back * (serial_variation * .10)
            direction := back * (.22 + serial_variation * .13) - right * (side_sign * (.72 + stitch_strength * .30))
            stitch_alpha := u8(clamp((136 + serial_variation * 52) * stitch_strength, 0, 194))
            stitch_color := canvas2d.Color{228, 252, 246, stitch_alpha}
            world_rondine_spray_streak(
                camera,
                position,
                direction,
                .14 + stitch_strength * .16 + serial_variation * .055,
                stitch_color,
            )
        }

        // Three paired surface teeth close toward the centerline behind the
        // transient spray clap. Unlike countersteer's repeated herringbone,
        // this is a single short V whose spacing collapses rearward, clearly
        // communicating that lateral grip has rejoined.
        zipper_alpha := u8(clamp(204 * stitch_visibility, 0, 210))
        zipper_color := canvas2d.Color{232, 253, 247, zipper_alpha}
        for tooth in 0 ..< 3 {
            tooth_f := f32(tooth)
            lateral_width := .48 - tooth_f * .13
            for side in 0 ..< 2 {
                side_sign := side == 0 ? f32(-1) : f32(1)
                tooth_position := center + back * (.16 + tooth_f * .24) + right * (side_sign * lateral_width)
                tooth_position.y += .012
                tooth_tangent := back * (.38 + tooth_f * .06) - right * (side_sign * (.82 - tooth_f * .08))
                tooth_radial := right * side_sign + back * .12
                tooth_alpha := u8(f32(zipper_alpha) * (1 - tooth_f * .16))
                world_rondine_surface_chip(
                    tooth_position,
                    tooth_tangent,
                    tooth_radial,
                    .16 + stitch_visibility * .11 - tooth_f * .012,
                    .034 + stitch_visibility * .016,
                    {zipper_color.r, zipper_color.g, zipper_color.b, tooth_alpha},
                    double_sided = true,
                )
            }
        }

        // A low pair of broad closing collars supplies the large-scale mass
        // behind the zipper. Each collar sweeps inward from the former drift
        // shoulders, then the small center knot marks where the two pressure
        // fronts meet. The soft-edged surface chips keep this planted on the
        // water instead of reading as another airborne spray fan.
        collar_alpha := u8(clamp(112 * stitch_visibility, 0, 138))
        collar_color := canvas2d.Color{211, 247, 241, collar_alpha}
        for side in 0 ..< 2 {
            side_sign := side == 0 ? f32(-1) : f32(1)
            collar_position := center + back * (.33 + serial_variation * .08) + right * (side_sign * .34)
            collar_tangent := back * .46 - right * (side_sign * .88)
            collar_radial := right * side_sign + back * .52
            world_rondine_surface_chip(
                collar_position,
                collar_tangent,
                collar_radial,
                .46 + stitch_visibility * .17,
                .105 + stitch_visibility * .035,
                collar_color,
                true,
            )
        }
        knot_alpha := u8(clamp(174 * stitch_visibility, 0, 192))
        knot_color := canvas2d.Color{236, 255, 249, knot_alpha}
        knot_position := center + back * .66
        knot_position.y += .018
        world_rondine_surface_chip(
            knot_position,
            back,
            right,
            .18 + stitch_visibility * .08,
            .065 + stitch_visibility * .025,
            knot_color,
            true,
        )
        world_rondine_surface_chip(
            knot_position,
            right,
            back,
            .10 + stitch_visibility * .04,
            .045 + stitch_visibility * .018,
            knot_color,
            true,
        )

        // Four small beads cross inward above the stored zipper, echoing the
        // live hookup clap after the aircraft has moved on. Their opposing
        // trajectories make recovery feel like pressure collapsing back
        // toward the centerline rather than another outward impact burst.
        if sample.age < .46 {
            for side in 0 ..< 2 {
                side_sign := side == 0 ? f32(-1) : f32(1)
                for bead in 0 ..< 2 {
                    seed := world_rondine_wake_hash(sample.serial, u32(side), u32(270 + bead))
                    variation := f32(seed % 23) / 22
                    bead_f := f32(bead)
                    launch_direction :=
                        back * (.34 + bead_f * .18 + variation * .18) -
                        right * (side_sign * (.78 + bead_f * .22 + variation * .16))
                    launch_speed := .88 + variation * .72
                    lift_speed := 1.00 + bead_f * .20 + variation * .72
                    bead_position :=
                        center +
                        right * (side_sign * (.48 + bead_f * .12)) +
                        launch_direction * (sample.age * launch_speed)
                    bead_position.y += .08 + sample.age * lift_speed - 3.0 * sample.age * sample.age
                    bead_direction :=
                        launch_direction * launch_speed + third_person.Vec3{0, lift_speed - 6.0 * sample.age, 0}
                    bead_life := clamp(1 - sample.age / .46, 0, 1)
                    bead_alpha := u8(
                        clamp(
                            (136 + variation * 70) * stitch_visibility * bead_life * event_bead_distance_fade,
                            0,
                            202,
                        ),
                    )
                    bead_color := canvas2d.Color{232, 253, 247, bead_alpha}
                    bead_streak_size := .065 + variation * .075
                    world_rondine_spray_streak(camera, bead_position, bead_direction, bead_streak_size, bead_color)
                    world_rondine_spray_bead(
                        camera,
                        bead_position + linalg.normalize0(bead_direction) * (bead_streak_size * 2.4),
                        .020 + variation * .016,
                        bead_color,
                    )
                }
            }
        }
    }

    // Fine spray: deterministic ballistic droplets provide the small-scale
    // layer. They are reconstructed from recent wake samples, so this remains
    // a procedural effect with no atlas, emitter allocation, or saved state.
    for sample in editor.rondine.wake[:editor.rondine.wake_count] {
        if sample.age > .88 || sample.strength < .16 || sample.serial % 2 != 0 do continue
        base := third_person.Vec3{sample.position.x, sea_y, sample.position.z}
        sample_depth := linalg.dot(base - camera.position, camera.forward)
        if sample_depth < 7.5 do continue
        sample_camera_fade := clamp((sample_depth - 7.5) / 5.5, 0, 1)
        droplet_distance_fade := clamp((92 - sample_depth) / 34, 0, 1)
        if droplet_distance_fade <= .02 do continue
        right := third_person.Vec3{sample.right.x, 0, sample.right.z}
        back := -third_person.Vec3{sample.forward.x, 0, sample.forward.z}
        turn := clamp(-sample.turn + sample.slip * 1.8, -1, 1)
        for side in 0 ..< 2 {
            side_sign := side == 0 ? f32(-1) : f32(1)
            outside := clamp(1 + side_sign * turn * .62, .38, 1.62)
            pressure_role := outside >= 1 ? u32(1) : u32(0)
            droplet_count := outside > 1 ? 5 : 3
            for droplet in 0 ..< droplet_count {
                seed := world_rondine_wake_hash(sample.serial, pressure_role, u32(10 + droplet))
                variation := f32(seed % 13) / 12
                launch_height := .32 + variation * .72
                outward_speed := (.72 + variation * 1.35) * outside
                rear_speed := .4 + f32((seed >> 2) % 7) * .11
                age := sample.age
                // Launch slightly above the surface and solve the descending
                // water crossing analytically. The old `y < sea + .035`
                // clamp treated the first few rising frames as landed, then
                // let the bead skate indefinitely along the water. Keeping a
                // stable impact time gives every fleck one clean airborne arc
                // and one anchored surface response.
                launch_clearance := f32(.08)
                water_clearance := f32(.035)
                gravity_half := f32(1.45)
                landing_time :=
                    (launch_height +
                        f32(
                            math.sqrt(
                                f64(
                                    launch_height * launch_height +
                                    4 * gravity_half * (launch_clearance - water_clearance),
                                ),
                            ),
                        )) /
                    (2 * gravity_half)
                flight_age := min(age, landing_time)
                position :=
                    base + right * (side_sign * (.72 + outward_speed * flight_age)) + back * (rear_speed * flight_age)
                position.y += launch_clearance + launch_height * flight_age - gravity_half * flight_age * flight_age
                landed := age >= landing_time
                if landed do position.y = sea_y + water_clearance
                max_life := f32(.78)
                life := max(max_life - age, f32(.01))
                direction :=
                    right * (side_sign * outward_speed) +
                    back * rear_speed +
                    third_person.Vec3{0, launch_height - 2.9 * flight_age, 0}
                opacity := clamp(life / max_life, 0, 1) * sample_camera_fade * droplet_distance_fade
                droplet_color := canvas2d.Color{224, 250, 245, u8((165 + variation * 68) * opacity)}
                // One heavier bead per loaded-side burst supplies a readable
                // medium-small accent; the rest remain fine tapered needles.
                bead_scale := pressure_role == 1 && droplet == 0 ? f32(1.55) : f32(1)
                streak_size := (.11 + variation * .15) * bead_scale
                world_rondine_spray_streak(camera, position, direction, streak_size, droplet_color)
                if pressure_role == 1 && droplet == 0 && !landed {
                    world_rondine_spray_bead(
                        camera,
                        position + linalg.normalize0(direction) * (streak_size * 2.4),
                        .032 + variation * .026,
                        droplet_color,
                    )
                }

                // The heavy loaded-side bead leaves a brief anchored skip
                // crown when its ballistic path reconnects with the surface.
                // The crossed streaks provide the medium-small read while two
                // expanding chips add a tiny concentric water response.
                if landed && pressure_role == 1 && droplet == 0 {
                    impact_age := age - landing_time
                    impact_life := clamp(1 - impact_age / .20, 0, 1)
                    impact_alpha := u8(128 * opacity * impact_life)
                    impact_color := canvas2d.Color{220, 248, 243, impact_alpha}
                    impact_outward := right * side_sign + back * (.18 + variation * .18)
                    impact_cross := back - right * (side_sign * (.24 + variation * .16))
                    world_rondine_spray_streak(camera, position, impact_outward, .18 + variation * .09, impact_color)
                    world_rondine_spray_streak(
                        camera,
                        position + back * .045,
                        impact_cross,
                        .12 + variation * .06,
                        {impact_color.r, impact_color.g, impact_color.b, u8(f32(impact_alpha) * .72)},
                    )
                    if impact_life > .02 {
                        chip_radius := .055 + impact_age * .58
                        world_rondine_surface_chip(
                            position + impact_outward * (impact_age * .16),
                            impact_cross,
                            impact_outward,
                            chip_radius,
                            .018 + impact_life * .018,
                            {224, 250, 244, u8(f32(impact_alpha) * .82)},
                        )
                        world_rondine_surface_chip(
                            position - impact_outward * (impact_age * .10),
                            impact_outward,
                            impact_cross,
                            chip_radius * .62,
                            .014 + impact_life * .012,
                            {215, 246, 242, u8(f32(impact_alpha) * .54)},
                        )
                    }
                }
            }
        }
    }
}
