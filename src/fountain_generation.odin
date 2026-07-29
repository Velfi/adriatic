package main

import fountains "../packages/fountains"
import third_person "../packages/third_person"
import "core:math"
import rl "zelda_engine:canvas2d"

FOUNTAIN_STONE := rl.Color{178, 169, 148, 255}
FOUNTAIN_STONE_DARK := rl.Color{112, 107, 98, 255}
FOUNTAIN_WATER := rl.Color{55, 138, 163, 210}
FOUNTAIN_SPRAY := rl.Color{178, 224, 232, 190}
FOUNTAIN_FOAM := rl.Color{188, 226, 232, 185}
FOUNTAIN_MIST := rl.Color{207, 235, 239, 155}

fountain_fraction :: #force_inline proc(value: f32) -> f32 {
    return value - f32(math.floor(f64(value)))
}

world_fountain_ripple :: proc(center: third_person.Vec3, radius, width: f32, color: rl.Color, seed: u32) {
    SEGMENTS :: 20
    for segment in 0 ..< SEGMENTS {
        mixed := fountains.mix(seed ~ u32(segment + 1) * 0x9e3779b9)
        // Preserve broad arcs, but puncture each ring in different places.
        // Adjacent segments share the coarse group bit so gaps read as foam
        // breakup rather than evenly dashed linework.
        group := segment / 2
        group_hash := fountains.mix(seed ~ u32(group + 17) * 0x85ebca6b)
        if group_hash & 7 == 0 do continue
        a := f32(segment) * math.PI * 2 / SEGMENTS
        b := f32(segment + 1) * math.PI * 2 / SEGMENTS
        jitter_a := (f32(mixed & 255) / 255 - .5) * width * .72
        next_mixed := fountains.mix(seed ~ u32((segment + 1) % SEGMENTS + 1) * 0x9e3779b9)
        jitter_b := (f32(next_mixed & 255) / 255 - .5) * width * .72
        radius_a := radius + jitter_a
        radius_b := radius + jitter_b
        width_a := width * (.72 + f32((mixed >> 8) & 255) / 255 * .48)
        width_b := width * (.72 + f32((next_mixed >> 8) & 255) / 255 * .48)
        inner_a_radius := max(radius_a - width_a * .5, f32(.01))
        outer_a_radius := radius_a + width_a * .5
        inner_b_radius := max(radius_b - width_b * .5, f32(.01))
        outer_b_radius := radius_b + width_b * .5
        inner_a := third_person.Vec3 {
            center.x + math.cos(a) * inner_a_radius,
            center.y,
            center.z + math.sin(a) * inner_a_radius,
        }
        inner_b := third_person.Vec3 {
            center.x + math.cos(b) * inner_b_radius,
            center.y,
            center.z + math.sin(b) * inner_b_radius,
        }
        outer_a := third_person.Vec3 {
            center.x + math.cos(a) * outer_a_radius,
            center.y,
            center.z + math.sin(a) * outer_a_radius,
        }
        outer_b := third_person.Vec3 {
            center.x + math.cos(b) * outer_b_radius,
            center.y,
            center.z + math.sin(b) * outer_b_radius,
        }
        // Foam highlights stay in the plain pass so the water shader does not
        // absorb the thin ring into the basin surface.
        world_quad(inner_a, inner_b, outer_b, outer_a, color)
    }
}

world_fountain_impact_effects :: proc(
    impact: third_person.Vec3,
    radial_x, radial_z: f32,
    seed: u32,
    elapsed: f32,
    style: fountains.Style,
) {
    crown_rays := style == .Bowl ? 3 : (style == .Tiered ? 5 : 4)
    droplet_count := style == .Bowl ? 3 : (style == .Tiered ? 6 : 5)
    mist_count := style == .Bowl ? 0 : (style == .Tiered ? 6 : 4)
    ripple_reach := style == .Bowl ? f32(.46) : (style == .Tiered ? f32(.70) : f32(.58))
    ripple_count := style == .Courtyard ? 2 : 1
    event_speed := style == .Bowl ? f32(.82) : (style == .Tiered ? f32(.74) : f32(.68))
    event_phase := fountain_fraction(elapsed * event_speed + f32(seed & 1023) / 1023)
    burst := clamp(1 - event_phase / .38, f32(0), f32(1))
    crown_strength := .22 + burst * .78
    // A compact crown gives every stream a readable contact point even when
    // individual droplets are between bursts. Its strong early pulse keeps
    // the impacts from reading as identical static star shapes.
    for ray in 0 ..< crown_rays {
        ray_hash := fountains.mix(seed ~ u32(ray + 1) * 0x27d4eb2d)
        angle_jitter := (f32(ray_hash & 255) / 255 - .5) * .34
        angle := f32(ray) * math.PI * 2 / f32(crown_rays) + f32(seed & 255) * .011 + angle_jitter
        direction := third_person.Vec3{math.cos(angle), 0, math.sin(angle)}
        start := impact + direction * .035
        reach := (.15 + f32((ray_hash >> 8) & 255) / 255 * .12) * (.70 + crown_strength * .30)
        finish := impact + direction * reach
        finish.y += (.025 + f32((ray_hash >> 16) & 255) / 255 * .065) * (.62 + crown_strength * .38)
        crown_radius := .017 + f32((ray_hash >> 24) & 255) / 255 * .010
        crown_alpha := u8(clamp(crown_strength * f32(FOUNTAIN_FOAM.a), f32(0), f32(FOUNTAIN_FOAM.a)))
        world_tube_between(
            start,
            finish,
            {radial_x, 0, radial_z},
            crown_radius * (.76 + crown_strength * .24),
            crown_radius * .5,
            {FOUNTAIN_FOAM.r, FOUNTAIN_FOAM.g, FOUNTAIN_FOAM.b, crown_alpha},
        )
    }

    // Stateless looping droplets avoid per-fountain mutable emitters while
    // retaining deterministic timing for captures and generated settlements.
    for droplet in 0 ..< droplet_count {
        mixed := fountains.mix(seed ~ u32(droplet + 1) * 0x9e3779b9)
        phase_offset := f32(mixed & 1023) / 1023
        life := fountain_fraction(event_phase + phase_offset * .74)
        angle := f32((mixed >> 16) & 1023) / 1023 * math.PI * 2
        speed := .18 + f32((mixed >> 26) & 31) / 31 * .34
        lift := .24 + f32((mixed >> 21) & 31) / 31 * .34
        position := third_person.Vec3 {
            impact.x + math.cos(angle) * speed * life,
            impact.y + .025 + math.sin(life * math.PI) * lift,
            impact.z + math.sin(angle) * speed * life,
        }
        size := (.028 + f32(mixed & 15) / 15 * .026) * (1 - life * .40)
        world_ellipsoid_matte_rotated(position, size, size * 1.7, size, angle, FOUNTAIN_FOAM)
    }

    // Fine suspended mist occupies a slower, wider envelope than the ballistic
    // droplets. It is reserved for higher-pressure styles.
    for mist_index in 0 ..< mist_count {
        mixed := fountains.mix(seed ~ u32(mist_index + 31) * 0x165667b1)
        phase := fountain_fraction(event_phase * .82 + f32(mixed & 1023) / 1023)
        angle := f32((mixed >> 16) & 1023) / 1023 * math.PI * 2
        spread := .06 + phase * (.18 + f32((mixed >> 26) & 31) / 31 * .16)
        lift := phase * (.22 + f32((mixed >> 21) & 31) / 31 * .22) - phase * phase * .12
        position := third_person.Vec3 {
            impact.x + math.cos(angle) * spread,
            impact.y + .055 + lift,
            impact.z + math.sin(angle) * spread,
        }
        size := (.026 + f32((mixed >> 10) & 15) / 15 * .024) * (1 - phase * .58)
        alpha := u8(clamp((1 - phase) * f32(FOUNTAIN_MIST.a), f32(0), f32(FOUNTAIN_MIST.a)))
        world_ellipsoid_matte_rotated(
            position,
            size * 1.35,
            size,
            size * 1.35,
            angle,
            {FOUNTAIN_MIST.r, FOUNTAIN_MIST.g, FOUNTAIN_MIST.b, alpha},
        )
    }

    // Rings share the splash event clock, growing out of the crown and fading
    // quadratically. The short duty cycle leaves calm gaps between impacts
    // instead of covering the basin in permanent linework.
    for ripple in 0 ..< ripple_count {
        phase := fountain_fraction(event_phase + f32(ripple) * .46)
        radius := .08 + phase * ripple_reach
        fade := (1 - phase) * (1 - phase)
        onset := clamp(phase / .08, f32(0), f32(1))
        alpha := u8(clamp(fade * onset * 178, f32(0), f32(178)))
        world_fountain_ripple(
            {impact.x, impact.y + .018, impact.z},
            radius,
            .027 + phase * .020,
            {128, 190, 201, alpha},
            seed ~ u32(ripple + 1) * 0x7f4a7c15,
        )
    }
}

world_fountain_tier_cascades :: proc(plan: ^fountains.Plan, origin: third_person.Vec3, rotation, elapsed: f32) {
    if plan == nil || plan.style != .Tiered || plan.tier_count < 2 do return

    CASCADE_COUNT :: 8
    CASCADE_STEPS :: 6
    upper_radius := f32(.70)
    lower_radius := f32(1.22)
    upper_y := origin.y + f32(2.47)
    lower_y := origin.y + f32(1.67)
    for cascade in 0 ..< CASCADE_COUNT {
        mixed := fountains.mix(plan.seed ~ u32(cascade + 1) * 0x9e3779b9)
        angle := rotation + f32(cascade) * math.PI * 2 / CASCADE_COUNT
        angle += (f32(mixed & 255) / 255 - .5) * .12
        radial := third_person.Vec3{math.cos(angle), 0, math.sin(angle)}
        tangent := third_person.Vec3{-radial.z, 0, radial.x}
        pulse := math.sin(elapsed * (1.75 + f32((mixed >> 8) & 7) * .035) + f32(cascade) * 1.41)
        previous := origin + radial * upper_radius
        previous.y = upper_y
        for step in 1 ..= CASCADE_STEPS {
            t := f32(step) / CASCADE_STEPS
            outward := upper_radius + (lower_radius - upper_radius) * t + math.sin(t * math.PI) * .13
            flutter := math.sin(elapsed * 3.1 + f32(cascade) * 2.17 + t * 7.3) * .012 * math.sin(t * math.PI)
            current := origin + radial * outward + tangent * flutter
            current.y = upper_y + (lower_y - upper_y) * t + math.sin(t * math.PI) * (.055 + pulse * .008)
            stream_radius := (.027 + pulse * .0018) * (1 - t * .27)
            if t < .90 {
                world_tube_between(
                    previous,
                    current,
                    {0, 0, 1},
                    stream_radius,
                    stream_radius * .72,
                    {178, 224, 232, 190},
                )
            } else {
                for bead in 0 ..< 2 {
                    bead_hash := fountains.mix(mixed ~ u32(bead + 1) * 0x7f4a7c15)
                    travel := fountain_fraction(
                        elapsed * (1.8 + f32((bead_hash >> 12) & 7) * .04) +
                        f32(bead) * .47 +
                        f32(bead_hash & 1023) / 1023,
                    )
                    bead_position := previous + (current - previous) * travel
                    world_ellipsoid_matte_rotated(
                        bead_position,
                        stream_radius * .82,
                        stream_radius * 1.95,
                        stream_radius * .82,
                        angle,
                        {188, 226, 232, 185},
                    )
                }
            }
            previous = current
        }

        // A compact aerated contact mark anchors each overflow strand to the
        // lower tray without adding another full-sized basin ripple.
        contact := origin + radial * lower_radius
        contact.y = lower_y + .012
        foam_size := .032 + f32((mixed >> 16) & 15) / 15 * .012
        world_ellipsoid_matte_rotated(contact, foam_size * 1.35, foam_size * .52, foam_size, angle, FOUNTAIN_FOAM)
    }
}

world_fountain_structure :: proc(plan: ^fountains.Plan, origin: third_person.Vec3, rotation: f32 = 0) {
    if plan == nil || !plan.valid do return

    // Build an actual hollow basin. The previous nested solid prisms left the
    // water buried beneath their top faces, hiding ripples and contact foam.
    wall_thickness := clamp(plan.radius * .14, f32(.38), f32(.7))
    inner_radius := plan.radius - wall_thickness
    floor_height := f32(.16)
    world_vertical_prism(
        {origin.x, origin.y + floor_height * .5, origin.z},
        inner_radius,
        inner_radius,
        floor_height,
        rotation,
        FOUNTAIN_STONE_DARK,
    )
    BASIN_SEGMENTS :: 24
    wall_center_radius := plan.radius - wall_thickness * .5
    wall_length := wall_center_radius * math.PI * 2 / BASIN_SEGMENTS * 1.015
    for segment in 0 ..< BASIN_SEGMENTS {
        angle := rotation + (f32(segment) + .5) * math.PI * 2 / BASIN_SEGMENTS
        center := third_person.Vec3 {
            origin.x + math.cos(angle) * wall_center_radius,
            origin.y + plan.wall_height * .5,
            origin.z + math.sin(angle) * wall_center_radius,
        }
        world_box_rotated(
            center,
            {wall_length, plan.wall_height, wall_thickness},
            angle + math.PI * .5,
            FOUNTAIN_STONE,
        )
    }

    water_y := origin.y + plan.water_level
    center_water := plan.style == .Bowl ? rl.Color{98, 188, 202, 230} : rl.Color{77, 177, 205, 230}
    edge_water := plan.style == .Courtyard ? rl.Color{73, 170, 186, 225} : rl.Color{49, 139, 174, 225}
    for segment in 0 ..< BASIN_SEGMENTS {
        a := f32(segment) * math.PI * 2 / BASIN_SEGMENTS
        b := f32(segment + 1) * math.PI * 2 / BASIN_SEGMENTS
        center := third_person.Vec3{origin.x, water_y, origin.z}
        edge_a := third_person.Vec3 {
            origin.x + math.cos(a) * (inner_radius - .12),
            water_y,
            origin.z + math.sin(a) * (inner_radius - .12),
        }
        edge_b := third_person.Vec3 {
            origin.x + math.cos(b) * (inner_radius - .12),
            water_y,
            origin.z + math.sin(b) * (inner_radius - .12),
        }
        // Reverse the x/z fan order so its normal points upward under the
        // world's counter-clockwise back-face culling.
        world_fountain_water_triangle_colored(center, edge_b, edge_a, center_water, edge_water, edge_water)
    }

    pedestal_height := plan.style == .Tiered ? f32(2.35) : f32(1.25)
    world_vertical_prism(
        {origin.x, origin.y + pedestal_height * .5, origin.z},
        .48,
        .48,
        pedestal_height,
        rotation,
        FOUNTAIN_STONE_DARK,
    )
    if plan.tier_count > 1 {
        world_vertical_prism(
            {origin.x, origin.y + 1.55, origin.z},
            1.48,
            1.48,
            .18,
            rotation + math.PI / 12,
            FOUNTAIN_STONE,
        )
        world_vertical_prism({origin.x, origin.y + 2.38, origin.z}, .78, .78, .16, rotation, FOUNTAIN_STONE)
    }
}

world_fountain_effects :: proc(plan: ^fountains.Plan, origin: third_person.Vec3, rotation: f32 = 0) {
    if plan == nil || !plan.valid do return

    water_y := origin.y + plan.water_level
    elapsed := f32(rl.GetTime())
    world_fountain_tier_cascades(plan, origin, rotation, elapsed)
    // More samples and a taper give streams a continuous ballistic silhouette
    // instead of three rigid pipe sections.
    for jet, jet_index in plan.jets[:plan.jet_count] {
        jet_angle := jet.angle + rotation
        radial_x := math.cos(jet_angle)
        radial_z := math.sin(jet_angle)
        nozzle_radius := plan.style == .Tiered ? f32(.58) : max(f32(.42), jet.radius * .34)
        nozzle_y := plan.style == .Tiered ? origin.y + f32(2.48) : water_y + .10
        nozzle := third_person.Vec3{origin.x + radial_x * nozzle_radius, nozzle_y, origin.z + radial_z * nozzle_radius}
        tangent_x, tangent_z := -radial_z, radial_x
        if plan.style == .Tiered {
            for spray_index in 0 ..< 2 {
                mixed := fountains.mix(plan.seed ~ u32(jet_index + 1) * 0x517cc1b7 ~ u32(spray_index + 1) * 0x9e3779b9)
                phase := fountain_fraction(elapsed * (.82 + f32((mixed >> 8) & 7) * .045) + f32(mixed & 1023) / 1023)
                tangent_offset := (f32((mixed >> 18) & 255) / 255 - .5) * (.10 + phase * .10)
                position := third_person.Vec3 {
                    nozzle.x + radial_x * (.03 + phase * .16) + tangent_x * tangent_offset,
                    nozzle.y - .04 + math.sin(phase * math.PI) * .18 - phase * .07,
                    nozzle.z + radial_z * (.03 + phase * .16) + tangent_z * tangent_offset,
                }
                size := (.021 + f32((mixed >> 26) & 31) / 31 * .017) * (1 - phase * .52)
                alpha := u8(clamp((1 - phase) * 150, f32(0), f32(150)))
                world_ellipsoid_matte_rotated(position, size, size * 1.45, size, jet_angle, {201, 233, 238, alpha})
            }
        }
        previous := nozzle
        STREAM_STEPS :: 11
        pressure := 1 + math.sin(elapsed * 2.15 + f32(jet_index) * 1.73) * .035
        breakup_start := plan.style == .Bowl ? f32(.92) : (plan.style == .Tiered ? f32(.82) : f32(.80))
        for step in 1 ..= STREAM_STEPS {
            t := f32(step) / STREAM_STEPS
            radius_at_t := nozzle_radius + (jet.radius - nozzle_radius) * t
            wobble := math.sin(t * math.PI) * math.sin(elapsed * 2.7 + f32(jet_index) * 2.11 + t * 5.2) * .024
            current := third_person.Vec3 {
                origin.x + radial_x * radius_at_t + tangent_x * wobble,
                water_y + (nozzle.y - water_y) * (1 - t) + jet.height * pressure * 2.25 * t * (1 - t),
                origin.z + radial_z * radius_at_t + tangent_z * wobble,
            }
            radius := .034 * (1 - t * .38)
            if t < breakup_start {
                world_tube_between(previous, current, {0, 0, 1}, radius, radius * .82, FOUNTAIN_SPRAY)
                // A narrow offset highlight gives the translucent stream a
                // rounded, moving-water read instead of a flat cyan wire.
                highlight_offset := third_person.Vec3{tangent_x * radius * .34, radius * .12, tangent_z * radius * .34}
                highlight_alpha := u8(clamp((1 - t * .72) * 132, f32(38), f32(132)))
                world_tube_between(
                    previous + highlight_offset,
                    current + highlight_offset,
                    {0, 0, 1},
                    radius * .28,
                    radius * .20,
                    {FOUNTAIN_FOAM.r, FOUNTAIN_FOAM.g, FOUNTAIN_FOAM.b, highlight_alpha},
                )
            } else {
                // Gravity and air resistance break the descending tail into
                // elongated beads before it reaches the basin.
                mixed := fountains.mix(plan.seed ~ u32(jet_index + 1) * 0x85ebca6b ~ u32(step) * 0x27d4eb2d)
                for bead_index in 0 ..< 2 {
                    bead_hash := fountains.mix(mixed ~ u32(bead_index + 1) * 0x7f4a7c15)
                    base_offset := bead_index == 0 ? f32(.24) : f32(.68)
                    travel := fountain_fraction(elapsed * (1.72 + f32((bead_hash >> 24) & 7) * .055) + base_offset)
                    offset := clamp(travel + (f32(bead_hash & 255) / 255 - .5) * .12, f32(.04), f32(.96))
                    bead := previous + (current - previous) * offset
                    bead_radius := radius * (.68 + f32((bead_hash >> 8) & 255) / 255 * .32)
                    world_ellipsoid_matte_rotated(
                        bead,
                        bead_radius,
                        bead_radius * (1.65 + f32((bead_hash >> 16) & 255) / 255 * .65),
                        bead_radius,
                        jet_angle,
                        FOUNTAIN_SPRAY,
                    )
                }
            }
            previous = current
        }
        world_fountain_impact_effects(
            previous,
            radial_x,
            radial_z,
            plan.seed ~ u32(jet_index + 1) * 0x85ebca6b,
            elapsed,
            plan.style,
        )
    }
}

world_fountain :: proc(plan: ^fountains.Plan, origin: third_person.Vec3, rotation: f32 = 0) {
    world_fountain_structure(plan, origin, rotation)
    world_fountain_effects(plan, origin, rotation)
}
