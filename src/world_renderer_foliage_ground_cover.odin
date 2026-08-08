package main
import "core:math"

import terrain "../packages/terrain"
import "core:math/linalg"
import canvas2d "zelda_engine:canvas2d"
import third_person "zelda_engine:third_person"

world_foliage_trunk :: proc(x, z, base_y, height, radius, crown_span: f32, seed: u32) {
    // Eight sides are enough to remove the conspicuous hexagonal shaft at
    // walking distance while keeping mature forests inexpensive.
    SEGMENTS :: 8
    TRUNK_RINGS :: 4
    base: [SEGMENTS]third_person.Vec3
    top: [SEGMENTS]third_person.Vec3
    rings: [TRUNK_RINGS][SEGMENTS]third_person.Vec3
    lean_angle := f32(seed % 628) * .01
    lean_x := math.cos(lean_angle) * height * .045
    lean_z := math.sin(lean_angle) * height * .045
    bend_angle := lean_angle + math.PI * .5 + f32(seed % 17) * .037
    bend_x, bend_z := math.cos(bend_angle), math.sin(bend_angle)
    ring_fraction := [TRUNK_RINGS]f32{0, .34, .69, 1}
    ring_radius := [TRUNK_RINGS]f32{1, .91, .78, .66}
    for ring in 0 ..< TRUNK_RINGS {
        fraction := ring_fraction[ring]
        curve := f32(math.sin(f64(fraction * math.PI)))
        center_x := x + lean_x * fraction + bend_x * height * .027 * curve
        center_z := z + lean_z * fraction + bend_z * height * .027 * curve
        for segment in 0 ..< SEGMENTS {
            angle := f32(segment) * math.PI * 2 / SEGMENTS + f32(ring) * .025
            rings[ring][segment] = {
                center_x + math.cos(angle) * radius * ring_radius[ring],
                base_y + height * fraction,
                center_z + math.sin(angle) * radius * ring_radius[ring],
            }
        }
    }
    for segment in 0 ..< SEGMENTS {
        base[segment] = rings[0][segment]
        top[segment] = rings[TRUNK_RINGS - 1][segment]
    }
    bark_light := [TRUNK_RINGS - 1]canvas2d.Color{{91, 72, 52, 255}, {97, 76, 54, 255}, {103, 80, 55, 255}}
    bark_shadow := [TRUNK_RINGS - 1]canvas2d.Color{{62, 55, 46, 255}, {66, 58, 47, 255}, {71, 61, 48, 255}}
    // Neighboring patches should not all expose the same orange-brown posts.
    // Three restrained bark families give the woodland warm oak, cool
    // gray-bark, and muted umber notes while keeping every trunk subordinate
    // to the canopy. Moss is applied afterward and ties the families together.
    bark_family := seed % 3
    if bark_family == 1 {
        bark_light = {{91, 79, 62, 255}, {98, 84, 64, 255}, {105, 89, 66, 255}}
        bark_shadow = {{62, 58, 50, 255}, {66, 61, 51, 255}, {71, 65, 53, 255}}
    } else if bark_family == 2 {
        bark_light = {{102, 69, 49, 255}, {109, 73, 51, 255}, {116, 78, 53, 255}}
        bark_shadow = {{68, 52, 43, 255}, {73, 55, 44, 255}, {78, 58, 45, 255}}
    }
    moss_light := [TRUNK_RINGS - 1]canvas2d.Color{{91, 94, 53, 255}, {94, 96, 55, 255}, {96, 98, 57, 255}}
    moss_shadow := [TRUNK_RINGS - 1]canvas2d.Color{{59, 67, 45, 255}, {62, 69, 46, 255}, {65, 71, 47, 255}}
    for ring in 0 ..< TRUNK_RINGS - 1 {
        for segment in 0 ..< SEGMENTS {
            next := (segment + 1) % SEGMENTS
            // Let bark value travel continuously around the trunk instead of
            // assigning every third face a dark stripe. A seed phase keeps
            // neighboring trunks from repeating the identical highlight.
            face_angle := (f32(segment) + .5) * math.PI * 2 / SEGMENTS + f32(seed % 37) * .017
            bark_rhythm := f32(math.sin(f64(f32(segment) * 1.73 + f32(ring) * 2.11 + f32(seed % 29) * .19))) * .045
            face_light := clamp(.18 + (.5 + .5 * math.cos(face_angle - .72)) * .72 + bark_rhythm, .12, .94)
            lower_color := color_lerp(bark_shadow[ring], bark_light[ring], face_light)
            upper_index := min(ring + 1, TRUNK_RINGS - 2)
            upper_color := color_lerp(bark_shadow[upper_index], bark_light[upper_index], face_light)
            // Moss shares one broad, cool-facing side across the woodland,
            // with a small per-tree drift. Blending it into the existing
            // vertices keeps the shaft inexpensive and avoids pasted stripes.
            moss_angle := math.PI * 1.38 + f32(seed % 13) * .018
            moss_facing := .5 + .5 * math.cos(face_angle - moss_angle)
            moss_amount := clamp((moss_facing - .38) * .48, 0, .28) * (1 - f32(ring) * .19)
            lower_moss := color_lerp(moss_shadow[ring], moss_light[ring], face_light)
            upper_moss := color_lerp(moss_shadow[upper_index], moss_light[upper_index], face_light)
            lower_color = color_lerp(lower_color, lower_moss, moss_amount)
            upper_color = color_lerp(upper_color, upper_moss, moss_amount * .82)
            world_quad_colored(
                rings[ring][segment],
                rings[ring + 1][segment],
                rings[ring + 1][next],
                rings[ring][next],
                lower_color,
                upper_color,
                upper_color,
                lower_color,
            )
        }
    }

    // Sparse vertical brush strips keep the broad front faces from reading as
    // untextured orange posts. They sit just above the lower shaft and rotate
    // per tree; one dark bark split and one shorter moss stroke are enough to
    // imply surface rhythm without introducing another material or texture.
    for stroke in 0 ..< 2 {
        stroke_angle := f32(seed % 211) * .029 + f32(stroke) * 2.17
        outward_x, outward_z := math.cos(stroke_angle), math.sin(stroke_angle)
        tangent_x, tangent_z := -outward_z, outward_x
        stroke_width := radius * (stroke == 0 ? f32(.20) : f32(.27))
        stroke_bottom := base_y + height * (stroke == 0 ? f32(.12) : f32(.07))
        stroke_top := base_y + height * (stroke == 0 ? f32(.43) : f32(.28))
        lower_outset := radius * 1.018
        upper_radius :=
            radius *
            (ring_radius[1] +
                    (ring_radius[2] - ring_radius[1]) *
                        clamp(
                            ((stroke_top - base_y) / height - ring_fraction[1]) /
                            (ring_fraction[2] - ring_fraction[1]),
                            0,
                            1,
                        ))
        upper_outset := upper_radius * 1.018
        stroke_color := canvas2d.Color{52, 49, 42, 220}
        if stroke == 1 do stroke_color = {64, 76, 49, 205}
        world_quad(
            {
                x + outward_x * lower_outset - tangent_x * stroke_width,
                stroke_bottom,
                z + outward_z * lower_outset - tangent_z * stroke_width,
            },
            {
                x +
                lean_x * (stroke_top - base_y) / height +
                outward_x * upper_outset -
                tangent_x * stroke_width * .68,
                stroke_top - height * .012,
                z +
                lean_z * (stroke_top - base_y) / height +
                outward_z * upper_outset -
                tangent_z * stroke_width * .68,
            },
            {
                x +
                lean_x * (stroke_top - base_y) / height +
                outward_x * upper_outset +
                tangent_x * stroke_width * .68,
                stroke_top,
                z +
                lean_z * (stroke_top - base_y) / height +
                outward_z * upper_outset +
                tangent_z * stroke_width * .68,
            },
            {
                x + outward_x * lower_outset + tangent_x * stroke_width,
                stroke_bottom + height * .018,
                z + outward_z * lower_outset + tangent_z * stroke_width,
            },
            stroke_color,
        )
    }

    // Three low buttress roots anchor the stylized trunk to the terrain.
    // Their uneven reach avoids a decorative star, and the wedges disappear
    // naturally beneath understory when viewed from above.
    ROOTS :: 3
    for root in 0 ..< ROOTS {
        angle :=
            lean_angle +
            f32(root) * math.PI * 2 / ROOTS +
            f32(math.sin(f64(f32(seed) * .023 + f32(root) * 1.71))) * .29
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        root_reach := radius * (2.35 + f32(root % 2) * .62)
        root_half_width := radius * (.54 + f32((root + 1) % 2) * .12)
        shoulder := third_person.Vec3 {
            x + direction_x * radius * .72,
            base_y + radius * (1.75 + f32(root) * .16),
            z + direction_z * radius * .72,
        }
        left := third_person.Vec3 {
            x + direction_x * radius - side_x * root_half_width,
            base_y + .035,
            z + direction_z * radius - side_z * root_half_width,
        }
        right := third_person.Vec3 {
            x + direction_x * radius + side_x * root_half_width,
            base_y + .035,
            z + direction_z * radius + side_z * root_half_width,
        }
        tip := third_person.Vec3{x + direction_x * root_reach, base_y + .025, z + direction_z * root_reach}
        root_light := canvas2d.Color{91, 71, 52, 255}
        root_shadow := canvas2d.Color{62, 54, 46, 255}
        if bark_family == 1 {
            root_light = {87, 76, 61, 255}
            root_shadow = {59, 57, 51, 255}
        } else if bark_family == 2 {
            root_light = {96, 66, 50, 255}
            root_shadow = {65, 50, 43, 255}
        }
        if root % 2 == 1 {
            root_light = color_lerp(root_light, {67, 63, 52, 255}, .34)
            root_shadow = color_lerp(root_shadow, {49, 50, 45, 255}, .22)
        }
        world_triangle_colored(left, tip, shoulder, root_shadow, root_shadow, root_light)
        world_triangle_colored(tip, right, shoulder, root_shadow, root_light, root_light)
    }

    crown := third_person.Vec3{x + lean_x, base_y + height, z + lean_z}
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle(top[segment], crown, top[next], {65, 54, 39, 255})
    }

    // A few broad forked limbs turn the supporting pole into a tree. They
    // disappear into the crown from above but become an important readable
    // layer at walking height and across glade openings.
    LIMBS :: 3
    for limb in 0 ..< LIMBS {
        angle :=
            lean_angle +
            f32(limb) * math.PI * 2 / LIMBS +
            f32(math.sin(f64(f32(seed) * .017 + f32(limb) * 1.91))) * .34
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        start_height := height * (.54 + f32(limb) * .055)
        start_fraction := start_height / height
        start_curve := f32(math.sin(f64(start_fraction * math.PI)))
        // Limb reach belongs to the crown, not the shaft radius. Radius-only
        // branches remained metre-wide nubs beneath twenty-metre canopy
        // shelves, leaving every mature tree as a foliage disk on a pole.
        reach := max(radius * (2.75 + f32(limb % 2) * .58), crown_span * (.27 + f32(limb % 2) * .045))
        start := third_person.Vec3 {
            x + lean_x * start_fraction + bend_x * height * .027 * start_curve,
            base_y + start_height,
            z + lean_z * start_fraction + bend_z * height * .027 * start_curve,
        }
        finish := third_person.Vec3 {
            x + lean_x * .92 + direction_x * reach,
            base_y + height * (.76 + f32(limb) * .035),
            z + lean_z * .92 + direction_z * reach,
        }
        start_half_width := radius * .58
        finish_half_width := radius * .28
        limb_color := canvas2d.Color{80, 64, 49, 255}
        if bark_family == 1 do limb_color = {76, 69, 57, 255}
        if bark_family == 2 do limb_color = {88, 60, 46, 255}
        if limb % 2 == 1 {
            limb_color = color_lerp(limb_color, {55, 53, 47, 255}, .42)
        }
        world_quad(
            {start.x - side_x * start_half_width, start.y, start.z - side_z * start_half_width},
            {start.x + side_x * start_half_width, start.y, start.z + side_z * start_half_width},
            {finish.x + side_x * finish_half_width, finish.y, finish.z + side_z * finish_half_width},
            {finish.x - side_x * finish_half_width, finish.y, finish.z - side_z * finish_half_width},
            limb_color,
        )
    }
}

world_foliage_understory_tuft :: proc(x, z, base_y, width, height: f32, seed: u32) {
    FRONDS :: 6
    camera_position := world_renderer.editor.camera_pose.position
    camera_delta_x := camera_position.x - x
    camera_delta_z := camera_position.z - z
    leaflet_distance := f32(math.sqrt(f64(camera_delta_x * camera_delta_x + camera_delta_z * camera_delta_z)))
    // Leaflet tiers are a walking-distance silhouette feature. Beyond this
    // range they occupy sub-pixel space and would only consume world-mesh
    // capacity needed by the dense forest canopy.
    emit_leaflets := leaflet_distance < 220
    emit_lush_leaflets := leaflet_distance < 140
    for frond in 0 ..< FRONDS {
        angle := f32(frond) * math.PI * 2 / FRONDS + f32(seed % 113) * .037
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        spread := width * (.24 + f32(frond % 2) * .055)
        if emit_lush_leaflets {
            // At walking distance the central triangle is only a narrow stem;
            // the tiered leaflets, not a giant spearhead, carry the fern.
            spread = width * (.065 + f32(frond % 2) * .018)
        }
        lean := width * (.18 + f32((frond + 1) % 3) * .045)
        blade_height := height * (.72 + f32(math.sin(f64(f32(seed) * .011 + f32(frond) * 1.83))) * .18)
        left := third_person.Vec3{x - side_x * spread, base_y + .08, z - side_z * spread}
        right := third_person.Vec3{x + side_x * spread, base_y + .08, z + side_z * spread}
        tip := third_person.Vec3{x + direction_x * lean, base_y + blade_height, z + direction_z * lean}
        color := canvas2d.Color{46, 91, 60, 255}
        if frond % 3 == 1 do color = {58, 108, 64, 255}
        if frond % 3 == 2 do color = {39, 80, 59, 255}
        tip_color := color
        tip_color.r = u8(min(int(tip_color.r) + 12, 255))
        tip_color.g = u8(min(int(tip_color.g) + 16, 255))
        tip_color.b = u8(min(int(tip_color.b) + 5, 255))
        // Ground vertices carry a downward normal so the canopy wind weight is
        // zero; the upright tip carries the full weight. The same triangle
        // therefore bends like a rooted fern instead of sliding as one rigid
        // piece across the forest floor.
        base_normal := third_person.Vec3{0, -1, 0}
        tip_normal := linalg.normalize0(third_person.Vec3{direction_x * .34, .94, direction_z * .34})
        world_triangle_foliage(left, tip, right, color, tip_color, color, base_normal, tip_normal, base_normal)

        // Walking-distance ferns carry three tapered leaflet tiers on every
        // frond. The middle LOD keeps one tier on alternating fronds, and the
        // distant LOD retains only the broad blade. This turns nearby cones
        // into layered woodland silhouettes without multiplying the stress
        // scene's sub-pixel geometry.
        tier_count := 0
        if emit_lush_leaflets {
            tier_count = 3
        } else if emit_leaflets && frond % 2 == 0 {
            tier_count = 1
        }
        lush_fractions := [3]f32{.29, .49, .68}
        lush_reaches := [3]f32{.32, .27, .20}
        for tier in 0 ..< tier_count {
            leaflet_fraction := f32(.56)
            if emit_lush_leaflets {
                leaflet_fraction = lush_fractions[tier]
            }
            stem_half_span := emit_lush_leaflets ? f32(.075) : f32(.08)
            stem_back_fraction := leaflet_fraction - stem_half_span
            stem_front_fraction := leaflet_fraction + stem_half_span
            stem_back := third_person.Vec3 {
                x + direction_x * lean * stem_back_fraction,
                base_y + blade_height * stem_back_fraction,
                z + direction_z * lean * stem_back_fraction,
            }
            stem_front := third_person.Vec3 {
                x + direction_x * lean * stem_front_fraction,
                base_y + blade_height * stem_front_fraction,
                z + direction_z * lean * stem_front_fraction,
            }
            leaflet_center_x := x + direction_x * lean * leaflet_fraction
            leaflet_center_z := z + direction_z * lean * leaflet_fraction
            leaflet_reach := width * (.23 + f32(frond % 2) * .035)
            if emit_lush_leaflets {
                leaflet_reach = width * lush_reaches[tier]
            }
            leaflet_lift := height * (.030 + f32((frond + tier + 1) % 2) * .012)
            left_leaflet := third_person.Vec3 {
                leaflet_center_x - side_x * leaflet_reach,
                base_y + blade_height * leaflet_fraction + leaflet_lift,
                leaflet_center_z - side_z * leaflet_reach,
            }
            right_leaflet := third_person.Vec3 {
                leaflet_center_x + side_x * leaflet_reach,
                base_y + blade_height * leaflet_fraction + leaflet_lift,
                leaflet_center_z + side_z * leaflet_reach,
            }
            leaflet_color := tip_color
            if tier == 0 {
                leaflet_color.r = u8(max(int(leaflet_color.r) - 6, 0))
                leaflet_color.g = u8(max(int(leaflet_color.g) - 7, 0))
            }
            stem_normal := linalg.normalize0(third_person.Vec3{direction_x * .18, .44, direction_z * .18})
            leaflet_normal := linalg.normalize0(third_person.Vec3{direction_x * .24, .68, direction_z * .24})
            world_triangle_foliage(
                stem_back,
                left_leaflet,
                stem_front,
                color,
                leaflet_color,
                leaflet_color,
                stem_normal,
                leaflet_normal,
                leaflet_normal,
            )
            world_triangle_foliage(
                stem_front,
                right_leaflet,
                stem_back,
                leaflet_color,
                leaflet_color,
                color,
                leaflet_normal,
                leaflet_normal,
                stem_normal,
            )
        }
    }
}

world_foliage_ground_rosette :: proc(x, z, base_y, width, height: f32, seed: u32) {
    camera_position := world_renderer.editor.camera_pose.position
    camera_delta_x := camera_position.x - x
    camera_delta_z := camera_position.z - z
    camera_distance := f32(math.sqrt(f64(camera_delta_x * camera_delta_x + camera_delta_z * camera_delta_z)))
    leaf_count := 4
    if camera_distance < 180 do leaf_count = 7
    for leaf in 0 ..< leaf_count {
        angle := f32(leaf) * math.PI * 2 / f32(leaf_count) + f32(seed % 137) * .031
        direction_x, direction_z := math.cos(angle), math.sin(angle)
        side_x, side_z := -direction_z, direction_x
        reach := width * (.34 + f32(math.sin(f64(f32(seed) * .013 + f32(leaf) * 1.79))) * .08)
        lift := height * (.56 + f32(math.sin(f64(f32(seed) * .019 + f32(leaf) * 2.17))) * .18)
        half_width := width * (.105 + f32(leaf % 2) * .018)
        root := third_person.Vec3{x, base_y + .07, z}
        left := third_person.Vec3 {
            x + direction_x * reach * .50 - side_x * half_width,
            base_y + lift * .72,
            z + direction_z * reach * .50 - side_z * half_width,
        }
        right := third_person.Vec3 {
            x + direction_x * reach * .50 + side_x * half_width,
            base_y + lift * .72,
            z + direction_z * reach * .50 + side_z * half_width,
        }
        tip := third_person.Vec3{x + direction_x * reach, base_y + lift * .38, z + direction_z * reach}
        root_color := canvas2d.Color{38, 77, 53, 255}
        leaf_color := canvas2d.Color{61, 111, 66, 255}
        tip_color := canvas2d.Color{70, 118, 68, 255}
        if leaf % 3 == 1 {
            root_color = {43, 81, 48, 255}
            leaf_color = {72, 119, 62, 255}
            tip_color = {82, 128, 66, 255}
        } else if leaf % 3 == 2 {
            root_color = {35, 72, 56, 255}
            leaf_color = {53, 101, 71, 255}
            tip_color = {63, 111, 74, 255}
        }
        root_normal := third_person.Vec3{0, -1, 0}
        leaf_normal := linalg.normalize0(third_person.Vec3{direction_x * .32, .88, direction_z * .32})
        tip_normal := linalg.normalize0(third_person.Vec3{direction_x * .46, .76, direction_z * .46})
        world_triangle_foliage(
            root,
            left,
            tip,
            root_color,
            leaf_color,
            tip_color,
            root_normal,
            leaf_normal,
            tip_normal,
            .Leaf,
        )
        world_triangle_foliage(
            root,
            tip,
            right,
            root_color,
            tip_color,
            leaf_color,
            root_normal,
            tip_normal,
            leaf_normal,
            .Leaf,
        )
    }
}

world_foliage_ground_dapple :: proc(x, z, base_y, width, depth, rotation: f32, seed: u32) {
    SEGMENTS :: 7
    // Painted woodland floors need readable pools of bounced canopy light.
    // Keep the irregular edge fully transparent, but lift the center enough
    // to separate fern and trunk silhouettes from one uniform green plane.
    center_color := canvas2d.Color{184, 166, 86, 101}
    if seed % 3 == 1 do center_color = {143, 154, 83, 92}
    if seed % 3 == 2 do center_color = {197, 172, 91, 98}
    edge_color := center_color
    edge_color.a = 0
    center := third_person.Vec3{x, base_y + .115, z}
    points: [SEGMENTS]third_person.Vec3
    for segment in 0 ..< SEGMENTS {
        angle := rotation + f32(segment) * math.PI * 2 / SEGMENTS
        irregularity := .82 + f32(math.sin(f64(f32(seed) * .019 + f32(segment) * 2.37))) * .18
        points[segment] = {
            x + math.cos(angle) * width * .5 * irregularity,
            base_y + .11,
            z + math.sin(angle) * depth * .5 * irregularity,
        }
    }
    for segment in 0 ..< SEGMENTS {
        next := (segment + 1) % SEGMENTS
        world_triangle_colored(points[segment], points[next], center, edge_color, edge_color, center_color)
    }
}
